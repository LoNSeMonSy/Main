"""Line-protocol writer for the audit_log measurement, plus the per-source cursor.

Same dependency-light approach as alertgen/influx.py and trigger/influx.py: the v2
write and query APIs are each a single POST, so there is no reason to pull in the
full influxdb-client.

Schema (measurement `audit_log`)
--------------------------------
tags    source       which system the event came from: tailscale | pve
        action       the operation, e.g. UPDATE / AUTH_OK / VZDUMP
        actor        who did it -- a login name, or a token/machine identity
        target       the specific object acted on
        target_type  the kind of thing it is, e.g. DEVICE / NODE / GUEST / ACL
        origin       where it came from, e.g. ADMIN_UI / cluster-log / task
fields  target_id        string
        target_property  string  -- which property of the target changed
        actor_id         string
        actor_display    string
        actor_type       string
        event_type       string  -- the source's own record type
        event_id         string  -- stable identity, also the de-duplication key
        message          string  -- the source's human-readable line, if any
        old_value        string  -- previous value, flattened to JSON if structured
        new_value        string
timestamp                ns, the event's own time (see the nudge below)

`target` is a **tag**, unlike `source_ip` on security_alerts, and the difference is
deliberate. That one is attacker-supplied and unbounded -- thousands of distinct
addresses from one scan -- and nothing queried by it. Audit targets are bounded by
how much infrastructure exists (nodes, guests, devices, users) and are now queried
directly: the hub's profile view asks "everything that ever happened to this
target", which is a tag lookup rather than a scan of every row in the window.
"""
import csv
import hashlib
import io
import logging
import time

import requests

import config

log = logging.getLogger(__name__)

# Events emitted by a single action can share one timestamp, and InfluxDB
# overwrites points that share a measurement, tag set and timestamp -- so siblings
# would silently eat each other. Each row's timestamp is therefore nudged by a
# deterministic sub-microsecond offset derived from its event_id. Deterministic is
# the important part: re-reading the same event on an overlapping poll lands on the
# same timestamp, so the write is an idempotent overwrite rather than a duplicate
# row. A sub-microsecond shift is invisible at display precision.
_NUDGE_MODULUS = 1000

TAG_KEYS = ("source", "action", "actor", "target", "target_type", "origin")
FIELD_KEYS = (
    "target_id", "target_property", "actor_id", "actor_display", "actor_type",
    "event_type", "event_id", "message", "old_value", "new_value",
)


def _esc_tag(value):
    return (
        str(value).replace("\\", "\\\\").replace(",", "\\,").replace(" ", "\\ ").replace("=", "\\=")
    )


def _esc_measurement(value):
    return str(value).replace("\\", "\\\\").replace(",", "\\,").replace(" ", "\\ ")


def _flux_str(value):
    return str(value).replace("\\", "\\\\").replace('"', '\\"')


def build_line(measurement, tags, fields, ts_ns=None):
    """Render one point of InfluxDB line protocol. Returns None if no valid fields."""
    parts = [_esc_measurement(measurement)]
    for key, value in sorted(tags.items()):
        if value in (None, ""):
            continue
        parts.append(f"{_esc_tag(key)}={_esc_tag(value)}")
    head = ",".join(parts)

    rendered = []
    for key, value in sorted(fields.items()):
        if value is None or value == "":
            continue
        if isinstance(value, bool):
            rendered.append(f"{_esc_tag(key)}={'true' if value else 'false'}")
        elif isinstance(value, int):
            rendered.append(f"{_esc_tag(key)}={value}i")
        elif isinstance(value, float):
            rendered.append(f"{_esc_tag(key)}={value}")
        else:
            escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
            rendered.append(f'{_esc_tag(key)}="{escaped}"')
    if not rendered:
        return None

    ts = ts_ns if ts_ns is not None else time.time_ns()
    return f"{head} {','.join(rendered)} {ts}"


def _nudged_ts(event):
    digest = hashlib.sha1(event["event_id"].encode("utf-8")).digest()
    return event["ts_ns"] + int.from_bytes(digest[:4], "big") % _NUDGE_MODULUS


def event_to_line(event):
    # Empty tag values are dropped by build_line, which would merge rows into a
    # different series than intended, so every tag gets a placeholder instead.
    tags = {k: (event.get(k) or "none") for k in TAG_KEYS}
    fields = {k: event.get(k) for k in FIELD_KEYS}
    return build_line(config.AUDIT_MEASUREMENT, tags, fields, ts_ns=_nudged_ts(event))


def write_events(events):
    """Persist normalised audit events. Returns the number written."""
    lines = [line for line in (event_to_line(e) for e in events) if line]
    if not lines:
        return 0
    # Chunked so one long backfill cannot build a single oversized request body.
    written = 0
    for start in range(0, len(lines), 500):
        chunk = lines[start : start + 500]
        if not write_lines(chunk):
            return written
        written += len(chunk)
    return written


def write_lines(lines):
    url = f"{config.INFLUX_URL.rstrip('/')}/api/v2/write"
    try:
        resp = requests.post(
            url,
            params={"org": config.INFLUX_ORG, "bucket": config.INFLUX_BUCKET, "precision": "ns"},
            headers={
                "Authorization": f"Token {config.INFLUX_TOKEN}",
                "Content-Type": "text/plain; charset=utf-8",
            },
            data="\n".join(lines).encode("utf-8"),
            timeout=30,
        )
    except requests.RequestException as exc:
        log.warning("InfluxDB write failed: %s", exc)
        return False

    if resp.status_code >= 300:
        log.warning("InfluxDB write rejected: HTTP %s %s", resp.status_code, resp.text[:300])
        return False
    return True


def _parse_annotated_csv(text):
    """Yield dict rows from InfluxDB's annotated CSV, across however many tables."""
    rows = []
    header = None
    for parts in csv.reader(io.StringIO(text)):
        if not parts or all(p == "" for p in parts):
            header = None
            continue
        if parts[0].startswith("#"):
            header = None
            continue
        if header is None:
            header = parts
            continue
        rows.append(dict(zip(header, parts)))
    return rows


def query(flux):
    url = f"{config.INFLUX_URL.rstrip('/')}/api/v2/query"
    try:
        resp = requests.post(
            url,
            params={"org": config.INFLUX_ORG},
            headers={
                "Authorization": f"Token {config.INFLUX_TOKEN}",
                "Content-Type": "application/vnd.flux",
                "Accept": "application/csv",
            },
            data=flux.encode("utf-8"),
            timeout=30,
        )
    except requests.RequestException as exc:
        log.warning("InfluxDB query failed: %s", exc)
        return None

    if resp.status_code >= 300:
        log.warning("InfluxDB query rejected: HTTP %s %s", resp.status_code, resp.text[:300])
        return None
    return _parse_annotated_csv(resp.text)


def latest_event_ns(source):
    """Newest stored timestamp for one source, or None if it has written nothing.

    The cursor is per source: enabling a second source must not make it think it
    has already caught up to the first one's history. InfluxDB itself is the store,
    so a container restart resumes without a state file or a volume.
    """
    flux = f'''
from(bucket: "{_flux_str(config.INFLUX_BUCKET)}")
  |> range(start: -90d)
  |> filter(fn: (r) => r._measurement == "{_flux_str(config.AUDIT_MEASUREMENT)}")
  |> filter(fn: (r) => r.source == "{_flux_str(source)}")
  |> filter(fn: (r) => r._field == "event_id")
  |> group()
  |> sort(columns: ["_time"], desc: true)
  |> limit(n: 1)
'''.strip()
    rows = query(flux)
    if not rows:
        return None
    from sources import rfc3339_to_ns

    return rfc3339_to_ns(rows[0].get("_time", ""))


def health():
    try:
        resp = requests.get(f"{config.INFLUX_URL.rstrip('/')}/health", timeout=10)
        return resp.status_code == 200
    except requests.RequestException:
        return False
