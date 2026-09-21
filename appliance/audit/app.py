"""Audit log collector: Tailscale + Proxmox VE -> InfluxDB, with a manual trigger.

POST /poll           -> poll every enabled source now; the hub's "Poll Now" button
POST /poll/<source>  -> poll just one source
GET  /health         -> per-source config, credential shape and last-poll outcome

The scheduled loops are what normally fill the measurement; this HTTP surface
exists so the Audit Logs tab can force a poll instead of waiting out the interval,
which matters most while you are still checking that credentials work.

Not published to the host in docker-compose.yml: only alerts-feed calls it, over
the compose network by service name. That keeps the button same-origin for the
browser and avoids opening another port.
"""
import logging

from flask import Flask, jsonify

import config
import influx
from poller import poller
from sources import SOURCES, enabled_sources

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s %(levelname)s [%(name)s] %(message)s"
)
log = logging.getLogger("audit")

app = Flask(__name__)


def _summarise(results):
    """Turn per-source results into one HTTP answer.

    Partial success is still success: if Proxmox ingested and Tailscale is not
    configured, the operator wants the rows and the caveat, not a failure.
    """
    if not results:
        return jsonify({
            "status": "disabled",
            "message": "no audit sources are enabled",
            "results": [],
        }), 503

    written = sum(r["written"] for r in results)
    if any(r["ok"] for r in results):
        return jsonify({
            "status": "ok",
            "written": written,
            "results": results,
            "poller": poller.status(),
        })

    reasons = {r["reason"] for r in results}
    if reasons == {"busy"}:
        return jsonify({"status": "busy", "message": "a poll is already running",
                        "results": results}), 409
    if reasons == {"unconfigured"}:
        missing = sorted({m for r in results for m in r.get("missing", [])})
        return jsonify({"status": "unconfigured", "missing_config": missing,
                        "message": "no audit source is configured yet",
                        "results": results}), 503
    message = next((r.get("error") for r in results if r.get("error")), "poll failed")
    return jsonify({"status": "error", "message": message, "results": results}), 502


@app.post("/poll")
def poll_now():
    """Fetch on demand. Deliberately synchronous: the caller wants the outcome.

    A manual poll is allowed even when a source's scheduled loop is off, as long
    as its credentials exist -- that is exactly the "paste the client id and see if
    it works before committing to it" case the button was added for.
    """
    return _summarise(poller.poll_all(trigger="manual"))


@app.post("/poll/<source>")
def poll_one(source):
    if source not in SOURCES:
        return jsonify({"status": "unknown_source",
                        "sources": sorted(SOURCES)}), 404
    return _summarise([poller.poll_source(source, trigger="manual")])


@app.get("/health")
def health():
    influx_ok = influx.health()
    statuses = poller.status()
    ready = [n for n, s in statuses.items() if s["enabled"] and not s["missing_config"]]
    ok = influx_ok and bool(ready)
    return jsonify({
        "status": "ok" if ok else "degraded",
        "influxdb": {"url": config.INFLUX_URL, "reachable": influx_ok},
        "bucket": config.INFLUX_BUCKET,
        "measurement": config.AUDIT_MEASUREMENT,
        "poll_interval_s": config.POLL_INTERVAL_S,
        "backfill_days": config.BACKFILL_DAYS,
        "overlap_min": config.OVERLAP_MIN,
        "sources": statuses,
        "enabled_sources": [s.NAME for s in enabled_sources()],
        "ready_sources": sorted(ready),
    }), (200 if ok else 503)


# Started at import so the scheduled loops are running before the first request.
poller.start()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=config.PORT)
