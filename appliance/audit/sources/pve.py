"""Source: Proxmox VE cluster log and task history.

Needs no new credentials -- it reuses the PVE_TOKEN_ID/PVE_TOKEN_SECRET pair the
backup-trigger service already requires, which is why this source defaults to on
while Tailscale defaults to off.

Two feeds, distinguished by the `origin` tag:

  cluster-log  GET /api2/json/cluster/log?max=N
               The actual audit trail: logins, auth failures, task start/end,
               permission denials, cluster-wide across every node.
  task         GET /api2/json/nodes/{node}/tasks?since=&until=&limit=&source=all
               What ran, who ran it, and how it finished.

**/cluster/log cannot be filtered by time.** It accepts a `since` parameter, but
that is a log *index*, not a timestamp -- passing a unix time returns zero rows
(verified against this cluster). So a poll pulls the most recent PVE_LOG_MAX
entries and discards everything outside the window client-side. Per-node
/tasks *does* honour `since`/`until` as unix seconds, so that feed is filtered
server-side properly.

A task appears twice over its life, first RUNNING then with its final status.
Both map to the same event id (the UPID) and the same timestamp (starttime), so
the second write updates the row in place rather than adding a duplicate.
"""
import logging
import re
import threading
import time

import requests
import urllib3

import config
from . import SourceError, make_event

log = logging.getLogger(__name__)

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

NAME = "pve"

# Conservative classification: only patterns that are unambiguous get a verb, and
# anything else falls back to the syslog tag. The raw line is always kept in
# `message`, so nothing is lost to a miss.
_CLASSIFY = (
    (re.compile(r"successful auth", re.I), "AUTH_OK"),
    (re.compile(r"authentication failure|auth(?:entication)? failed|invalid credentials"
                r"|no such user|password verification failed", re.I), "AUTH_FAIL"),
    (re.compile(r"permission denied|insufficient permission|forbidden", re.I), "DENIED"),
    (re.compile(r"^starting task\b", re.I), "TASK_START"),
    (re.compile(r"^end task\b", re.I), "TASK_END"),
)

# syslog priority -> a word the UI can colour on
_SEVERITY = {0: "emerg", 1: "alert", 2: "crit", 3: "error",
             4: "warning", 5: "notice", 6: "info", 7: "debug"}


def enabled():
    return config.PVE_ENABLED


def missing_config():
    missing = []
    if not config.PVE_HOST:
        missing.append("PVE_HOST")
    has_token = config.PVE_TOKEN_ID and config.PVE_TOKEN_SECRET
    has_login = config.PVE_USER and config.PVE_PASSWORD
    if not has_token and not has_login:
        missing.append("PVE_TOKEN_ID+PVE_TOKEN_SECRET or PVE_USER+PVE_PASSWORD")
    return missing


def max_backfill_days():
    # PVE keeps its cluster log until it rotates; nothing to cap against.
    return None


class _Client:
    """Read-only PVE API client. Token auth preferred, ticket auth as fallback.

    Mirrors trigger/pve.py's two auth modes, minus the CSRF token -- every call
    here is a GET, and PVE only requires CSRF on writes.
    """

    def __init__(self):
        self._lock = threading.Lock()
        self._ticket = None
        self._expires_at = 0.0

    @property
    def base(self):
        return f"https://{config.PVE_HOST}:{config.PVE_PORT}/api2/json"

    def _headers(self):
        if config.PVE_TOKEN_ID and config.PVE_TOKEN_SECRET:
            return {"Authorization":
                    f"PVEAPIToken={config.PVE_TOKEN_ID}={config.PVE_TOKEN_SECRET}"}
        return {"Cookie": f"PVEAuthCookie={self._auth_ticket()}"}

    def _auth_ticket(self):
        with self._lock:
            # PVE tickets last two hours; renew well before that.
            if self._ticket and time.monotonic() < self._expires_at:
                return self._ticket
            try:
                resp = requests.post(
                    f"{self.base}/access/ticket",
                    data={"username": config.PVE_USER, "password": config.PVE_PASSWORD},
                    verify=config.PVE_VERIFY_SSL,
                    timeout=config.HTTP_TIMEOUT_S,
                )
            except requests.RequestException as exc:
                raise SourceError(f"PVE ticket request failed: {exc}") from exc
            if resp.status_code >= 300:
                raise SourceError(f"PVE ticket rejected: HTTP {resp.status_code}")
            data = (resp.json() or {}).get("data") or {}
            ticket = data.get("ticket")
            if not ticket:
                raise SourceError("PVE ticket response carried no ticket")
            self._ticket = ticket
            self._expires_at = time.monotonic() + 3600
            return ticket

    def get(self, path, params=None):
        try:
            resp = requests.get(
                f"{self.base}{path}",
                params=params or {},
                headers=self._headers(),
                verify=config.PVE_VERIFY_SSL,
                timeout=config.HTTP_TIMEOUT_S,
            )
        except requests.RequestException as exc:
            raise SourceError(f"PVE request to {path} failed: {exc}") from exc

        if resp.status_code == 401:
            raise SourceError(f"PVE rejected the credentials (HTTP 401) on {path}")
        if resp.status_code == 403:
            raise SourceError(
                f"PVE forbade {path} (HTTP 403) -- the token most likely lacks "
                "Sys.Audit on /"
            )
        if resp.status_code >= 300:
            raise SourceError(f"PVE {path} returned HTTP {resp.status_code} {resp.text[:160]}")

        try:
            return (resp.json() or {}).get("data")
        except ValueError as exc:
            raise SourceError(f"PVE {path} response was not JSON") from exc


_client = _Client()


def _classify(msg, tag):
    for pattern, action in _CLASSIFY:
        if pattern.search(msg):
            return action
    return (tag or "log").upper()


def _cluster_log_events(start_ns, end_ns):
    rows = _client.get("/cluster/log", {"max": config.PVE_LOG_MAX}) or []
    start_s, end_s = start_ns / 1e9, end_ns / 1e9

    events = []
    for row in rows:
        when = row.get("time")
        if not isinstance(when, (int, float)) or not (start_s <= when <= end_s):
            continue
        msg = str(row.get("msg") or "").strip()
        node = str(row.get("node") or "").strip()
        tag = str(row.get("tag") or "").strip()
        events.append(make_event(
            NAME,
            int(when) * 1_000_000_000,
            _classify(msg, tag),
            row.get("user"),
            target=node,
            # `id` is PVE's own per-entry identifier; uid is a fallback for older
            # releases that do not send it.
            uid=str(row.get("id") or row.get("uid") or ""),
            target_type="NODE",
            origin="cluster-log",
            event_type=_SEVERITY.get(row.get("pri"), "info"),
            message=msg,
            actor_type="token" if "!" in str(row.get("user") or "") else "user",
        ))
    return events


def _task_events(start_ns, end_ns):
    nodes = _client.get("/nodes") or []
    start_s, end_s = int(start_ns // 1_000_000_000), int(end_ns // 1_000_000_000)

    events = []
    for node in nodes:
        name = node.get("node")
        if not name:
            continue
        rows = _client.get(f"/nodes/{name}/tasks", {
            "since": start_s,
            "until": end_s,
            "limit": config.PVE_TASK_LIMIT,
            # Without source=all this lists only finished tasks, so a job that is
            # still running would never appear -- the same trap the trigger
            # service hit with source=archive.
            "source": "all",
        }) or []

        for row in rows:
            when = row.get("starttime")
            if not isinstance(when, (int, float)):
                continue
            guest = str(row.get("id") or "").strip()
            status = str(row.get("status") or "").strip()
            duration = None
            if isinstance(row.get("endtime"), (int, float)):
                duration = int(row["endtime"]) - int(when)
            events.append(make_event(
                NAME,
                int(when) * 1_000_000_000,
                str(row.get("type") or "task").upper(),
                row.get("user"),
                # Guest-scoped tasks name the guest; node-scoped ones name the node.
                target=guest or name,
                # The UPID is globally unique, so the RUNNING and finished writes
                # for one task land on the same row and the status updates in place.
                uid=str(row.get("upid") or ""),
                target_type="GUEST" if guest else "NODE",
                origin="task",
                event_type="task",
                message=(f"{status} on {name}" + (f" in {duration}s" if duration is not None else "")),
                new_value=status,
                actor_type="token" if "!" in str(row.get("user") or "") else "user",
                target_property=name if guest else "",
            ))
    return events


def fetch(start_ns, end_ns):
    """Cluster log + task events in [start_ns, end_ns], normalised, oldest first."""
    events = _cluster_log_events(start_ns, end_ns) + _task_events(start_ns, end_ns)
    events.sort(key=lambda e: (e["ts_ns"], e["event_id"]))
    return events
