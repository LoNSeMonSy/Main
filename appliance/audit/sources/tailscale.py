"""Source: Tailscale configuration audit logs.

Endpoint (confirmed against Tailscale's own docs, not guessed):

    GET {API_URL}/api/v2/tailnet/{tailnet}/logging/configuration?start=...&end=...

`start` and `end` are required, RFC3339, and inclusive at nanosecond resolution.
The required scope is `logs:configuration:read`. Configuration audit logs are
available on every plan including the free Personal tier, retained for 90 days.

Two credential shapes, checked in that order:

  1. An OAuth client (client id + secret) exchanged at /api/v2/oauth/token for a
     one-hour bearer token. Preferred: the scope can be narrowed to
     logs:configuration:read alone, and no long-lived secret rides on each call.
  2. A personal API key (tskey-api-...), sent as a bearer token directly. Simpler
     to create but unscoped and expiring, so it is the fallback, not the default.
"""
import logging
import threading
import time

import requests

import config
from . import SourceError, make_event, ns_to_rfc3339, rfc3339_to_ns

log = logging.getLogger(__name__)

NAME = "tailscale"

# Refresh a little before the hour is up rather than racing the expiry.
_TOKEN_REFRESH_MARGIN_S = 120


def enabled():
    return config.TS_ENABLED


def missing_config():
    if config.TS_API_KEY or (config.TS_OAUTH_CLIENT_ID and config.TS_OAUTH_CLIENT_SECRET):
        return []
    return ["TAILSCALE_OAUTH_CLIENT_ID+TAILSCALE_OAUTH_CLIENT_SECRET or TAILSCALE_API_KEY"]


def max_backfill_days():
    return config.TS_MAX_BACKFILL_DAYS


class _TokenCache:
    """Holds the OAuth access token and swaps it out shortly before it expires."""

    def __init__(self):
        self._lock = threading.Lock()
        self._token = None
        self._expires_at = 0.0

    def bearer(self):
        # A plain API key is already a bearer token; nothing to exchange.
        if not (config.TS_OAUTH_CLIENT_ID and config.TS_OAUTH_CLIENT_SECRET):
            if not config.TS_API_KEY:
                raise SourceError("no Tailscale credentials configured")
            return config.TS_API_KEY

        with self._lock:
            if self._token and time.monotonic() < self._expires_at:
                return self._token
            self._token, ttl = self._exchange()
            self._expires_at = time.monotonic() + max(60, ttl - _TOKEN_REFRESH_MARGIN_S)
            log.info("obtained Tailscale OAuth access token (valid %ss)", ttl)
            return self._token

    def _exchange(self):
        url = f"{config.TS_API_URL}/api/v2/oauth/token"
        try:
            resp = requests.post(
                url,
                data={
                    "client_id": config.TS_OAUTH_CLIENT_ID,
                    "client_secret": config.TS_OAUTH_CLIENT_SECRET,
                    "grant_type": "client_credentials",
                },
                timeout=config.HTTP_TIMEOUT_S,
            )
        except requests.RequestException as exc:
            raise SourceError(f"OAuth token request failed: {exc}") from exc

        if resp.status_code >= 300:
            raise SourceError(
                f"OAuth token request rejected: HTTP {resp.status_code} {resp.text[:200]}"
            )
        try:
            payload = resp.json()
        except ValueError as exc:
            raise SourceError("OAuth token response was not JSON") from exc

        token = payload.get("access_token")
        if not token:
            raise SourceError("OAuth token response carried no access_token")
        return token, int(payload.get("expires_in") or 3600)

    def invalidate(self):
        with self._lock:
            self._token = None
            self._expires_at = 0.0


_tokens = _TokenCache()


def _first(mapping, *keys):
    """First non-empty value among `keys`, tolerating non-dict input."""
    if not isinstance(mapping, dict):
        return ""
    for key in keys:
        value = mapping.get(key)
        if value not in (None, "", {}, []):
            return str(value).strip()
    return ""


def normalise(event):
    """Flatten one raw API event into the shared shape.

    Field names follow Tailscale's documented response: eventTime, action, actor
    {id, loginName, displayName, type}, target {id, name, type, property}, origin,
    old/new, eventGroupID.
    """
    if not isinstance(event, dict):
        return None

    ts_ns = rfc3339_to_ns(_first(event, "eventTime", "timestamp", "time"))
    if ts_ns is None:
        return None

    actor = event.get("actor") if isinstance(event.get("actor"), dict) else {}
    target = event.get("target") if isinstance(event.get("target"), dict) else {}

    return make_event(
        NAME,
        ts_ns,
        _first(event, "action", "eventName"),
        # The console shows a login where it has one and falls back to the display
        # name for tagged/machine actors, which have none.
        _first(actor, "loginName", "displayName", "id"),
        target=_first(target, "name", "id"),
        # eventGroupID groups the events emitted by one operation, so on its own it
        # is not unique -- make_event's target/property suffix separates siblings.
        uid=_first(event, "eventGroupID", "eventID", "id"),
        target_type=_first(target, "type"),
        target_property=_first(target, "property"),
        origin=_first(event, "origin"),
        actor_id=_first(actor, "id"),
        actor_display=_first(actor, "displayName"),
        actor_type=_first(actor, "type"),
        event_type=_first(event, "type"),
        old_value=event.get("old"),
        new_value=event.get("new"),
    )


def _extract_events(payload):
    """Pull the event array out of the response.

    Tailscale documents the body as a TailnetLogsResponse wrapper; accepting a bare
    array and a couple of plausible wrapper keys costs nothing and means a shape
    change upstream degrades to "no rows" instead of a crash loop.
    """
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in ("logs", "data", "events", "auditLogs"):
            value = payload.get(key)
            if isinstance(value, list):
                return value
    return []


def fetch(start_ns, end_ns):
    """Configuration audit events in [start_ns, end_ns], normalised, oldest first."""
    url = f"{config.TS_API_URL}/api/v2/tailnet/{config.TS_TAILNET}/logging/configuration"
    params = {"start": ns_to_rfc3339(start_ns), "end": ns_to_rfc3339(end_ns)}

    def _call():
        return requests.get(
            url,
            params=params,
            headers={
                "Authorization": f"Bearer {_tokens.bearer()}",
                "Accept": "application/json",
            },
            timeout=config.HTTP_TIMEOUT_S,
        )

    try:
        resp = _call()
        # A cached token can be revoked or rotated out from under us; re-exchange
        # once before treating 401 as a real credential problem.
        if resp.status_code == 401:
            _tokens.invalidate()
            resp = _call()
    except requests.RequestException as exc:
        raise SourceError(f"audit log request failed: {exc}") from exc

    if resp.status_code == 403:
        raise SourceError(
            "audit log request forbidden (HTTP 403) -- the credential most likely "
            "lacks the logs:configuration:read scope"
        )
    if resp.status_code >= 300:
        raise SourceError(
            f"audit log request rejected: HTTP {resp.status_code} {resp.text[:200]}"
        )

    try:
        payload = resp.json()
    except ValueError as exc:
        raise SourceError("audit log response was not JSON") from exc

    events = [e for e in (normalise(e) for e in _extract_events(payload)) if e]
    events.sort(key=lambda e: (e["ts_ns"], e["event_id"]))
    return events
