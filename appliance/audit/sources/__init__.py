"""Audit sources: each one turns some system's log into the shared event shape.

A source module exposes four things, and the collector needs nothing else:

    NAME             the value written to the `source` tag
    enabled()        whether the operator switched it on
    missing_config() names of settings it cannot run without ([] when ready)
    fetch(a, b)      normalised events with a.ts_ns in [a, b], oldest first

Keeping the contract this small is what lets PBS or a syslog receiver be added
later as one file plus one line in SOURCES, rather than another container.
"""
import datetime as dt
import json
import re

_TS_RE = re.compile(
    r"^(?P<base>\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})"
    r"(?:\.(?P<frac>\d+))?(?P<tz>Z|z|[+-]\d{2}:?\d{2})?$"
)


class SourceError(Exception):
    """Raised when a source's upstream cannot be reached or refuses credentials."""


def rfc3339_to_ns(value):
    """Parse an RFC3339 timestamp to integer nanoseconds, keeping sub-microseconds.

    datetime.fromisoformat() truncates at microseconds; events can carry more
    precision than that and the value is used as a poll cursor, so the tail digits
    are parsed by hand. Same approach as alerts/influx_query.py.
    """
    match = _TS_RE.match(str(value).strip())
    if not match:
        return None
    tz = (match.group("tz") or "Z").replace("z", "Z")
    if tz == "Z":
        offset = "+00:00"
    elif ":" not in tz:
        offset = f"{tz[:3]}:{tz[3:]}"
    else:
        offset = tz
    base = match.group("base").replace(" ", "T") + offset
    try:
        seconds = int(dt.datetime.fromisoformat(base).timestamp())
    except ValueError:
        return None
    frac = (match.group("frac") or "").ljust(9, "0")[:9]
    return seconds * 1_000_000_000 + int(frac or 0)


def ns_to_rfc3339(ts_ns):
    """Render integer nanoseconds as an RFC3339 UTC string an API will accept."""
    secs, rem = divmod(int(ts_ns), 1_000_000_000)
    stamp = dt.datetime.fromtimestamp(secs, dt.timezone.utc)
    return f"{stamp.strftime('%Y-%m-%dT%H:%M:%S')}.{rem:09d}Z"


def stringify(value):
    """Flatten a structured old/new value to something a string field can hold."""
    if value in (None, "", {}, []):
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (dict, list)):
        return json.dumps(value, separators=(",", ":"), sort_keys=True)
    return str(value)


def make_event(source, ts_ns, action, actor, target="", uid="", **extra):
    """Build one event in the shape influx.py and the hub both expect.

    Everything optional degrades to an empty string rather than dropping the row --
    an event with an odd shape is still worth seeing in the table.
    """
    target_type = str(extra.get("target_type") or "").strip()
    target_property = str(extra.get("target_property") or "").strip()
    actor = str(actor or "").strip() or "unknown"
    target = str(target or "").strip()
    action = str(action or "").strip() or "UNKNOWN"

    # Stable identity, and the de-duplication key. `uid` is whatever the source
    # can offer that is already unique (a UPID, an event group id); the rest
    # disambiguates siblings that share one, which is the case that would
    # otherwise collide in InfluxDB.
    event_id = "|".join([
        source, str(uid), str(ts_ns), action, actor, target_type, target, target_property,
    ])

    return {
        "source": source,
        "event_id": event_id,
        "ts_ns": int(ts_ns),
        "action": action,
        "actor": actor,
        "target": target,
        "target_type": target_type,
        "target_property": target_property,
        "origin": str(extra.get("origin") or "").strip(),
        "actor_id": str(extra.get("actor_id") or "").strip(),
        "actor_display": str(extra.get("actor_display") or "").strip(),
        "actor_type": str(extra.get("actor_type") or "").strip(),
        "event_type": str(extra.get("event_type") or "").strip(),
        "message": str(extra.get("message") or "").strip(),
        "old_value": stringify(extra.get("old_value")),
        "new_value": stringify(extra.get("new_value")),
    }


from . import pve, tailscale  # noqa: E402  (imported after the helpers they use)

SOURCES = {tailscale.NAME: tailscale, pve.NAME: pve}


def enabled_sources():
    """The sources the operator has switched on, in a stable order."""
    return [SOURCES[name] for name in sorted(SOURCES) if SOURCES[name].enabled()]
