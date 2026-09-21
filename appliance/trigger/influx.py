"""Line-protocol writer for the existing InfluxDB monitoring bucket.

Deliberately dependency-light: the v2 write API is a single POST, so there is no
reason to pull in the full influxdb-client just for this.
"""
import logging
import time

import requests

import config

log = logging.getLogger(__name__)

_STATE_INT = {"running": 0, "ok": 1, "error": 2, "unknown": 3}


def _esc_tag(value):
    return (
        str(value).replace("\\", "\\\\").replace(",", "\\,").replace(" ", "\\ ").replace("=", "\\=")
    )


def _esc_measurement(value):
    return str(value).replace("\\", "\\\\").replace(",", "\\,").replace(" ", "\\ ")


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
        if value is None:
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


def write_progress(snapshot, source="manual"):
    """Persist one progress snapshot so a native Grafana panel can render it."""
    state = snapshot.get("state", "unknown")
    line = build_line(
        config.INFLUX_MEASUREMENT,
        tags={
            "upid": snapshot.get("upid"),
            "node": snapshot.get("node"),
            "vmid": snapshot.get("vmid"),
            "status": state,
            "source": source,
        },
        fields={
            "percent": float(snapshot.get("percent") or 0.0),
            # Progress across the whole job (finished guests + the one in flight),
            # so the gauge climbs 0->100 once per job instead of once per guest.
            "overall_percent": float(snapshot.get("overall_percent") or 0.0),
            "bytes_done": snapshot.get("bytes_done"),
            "bytes_total": snapshot.get("bytes_total"),
            "read_bytes_s": snapshot.get("read_bytes_s"),
            "write_bytes_s": snapshot.get("write_bytes_s"),
            "elapsed_s": snapshot.get("elapsed_s"),
            "eta_s": snapshot.get("eta_s"),
            "status_int": _STATE_INT.get(state, 3),
            # Human-readable "Running: TESTVM (999) - 4 of 13", so the dashboard can
            # say which guest the percentage belongs to as it cycles 0->100 per guest.
            "state_label": snapshot.get("state_label"),
            "vm_name": snapshot.get("vm_name"),
            "vm_index": snapshot.get("vm_index"),
            "vm_total": snapshot.get("vm_total"),
            "guests_done": snapshot.get("guests_done"),
            "guests_failed": snapshot.get("guests_failed"),
            "error_message": snapshot.get("error_message"),
        },
    )
    if not line:
        return False
    return write_lines([line])


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
            timeout=15,
        )
    except requests.RequestException as exc:
        log.warning("InfluxDB write failed: %s", exc)
        return False

    if resp.status_code >= 300:
        log.warning("InfluxDB write rejected: HTTP %s %s", resp.status_code, resp.text[:300])
        return False
    return True


def health():
    try:
        resp = requests.get(f"{config.INFLUX_URL.rstrip('/')}/health", timeout=10)
        return resp.status_code == 200
    except requests.RequestException:
        return False
