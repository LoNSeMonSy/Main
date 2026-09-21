"""Backup trigger webhook.

POST /api/backup/start          -> kicks off a vzdump job on the PVE node, returns its UPID
GET  /api/backup/status/<upid>  -> live percentage / bytes / elapsed / ETA for that task
GET  /api/backup/current        -> the most recently started job, for convenience
GET  /health                    -> service + dependency health

While a job runs, a background thread writes progress into the InfluxDB monitoring
bucket so a native Grafana panel renders it. The dashboard button only calls /start.
"""
import logging
import threading
import time

from flask import Flask, jsonify, request

import config
import influx
import pbs_import
from pve import PveClient, PveError

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s %(levelname)s [%(name)s] %(message)s"
)
log = logging.getLogger("trigger")

app = Flask(__name__)
client = PveClient()

# upid -> {"snapshot": {...}, "source": str, "started_at": float, "thread": Thread}
_jobs = {}
_jobs_lock = threading.Lock()
_last_upid = None


# --- cross-cutting ------------------------------------------------------------
@app.after_request
def add_cors(resp):
    resp.headers["Access-Control-Allow-Origin"] = config.CORS_ORIGIN
    resp.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type, X-Trigger-Token"
    resp.headers["Access-Control-Max-Age"] = "600"
    return resp


@app.before_request
def guard():
    if request.method == "OPTIONS":
        return ("", 204)
    if not config.TRIGGER_TOKEN:
        return None
    if request.path == "/health":
        return None
    supplied = request.headers.get("X-Trigger-Token", "")
    if supplied != config.TRIGGER_TOKEN:
        return jsonify({"error": "unauthorized"}), 401
    return None


# --- progress polling ---------------------------------------------------------
def _record(upid, snapshot, source):
    with _jobs_lock:
        job = _jobs.setdefault(upid, {"source": source, "started_at": time.time()})
        job["snapshot"] = snapshot


def _poll_job(upid, source):
    """Follow a task to completion, writing each snapshot into InfluxDB."""
    deadline = time.time() + config.POLL_MAX_S
    log.info("polling %s", upid)
    while time.time() < deadline:
        try:
            snapshot = client.task_progress(upid)
        except PveError as exc:
            log.warning("progress poll failed for %s: %s", upid, exc)
            time.sleep(config.POLL_INTERVAL_S)
            continue

        _record(upid, snapshot, source)
        influx.write_progress(snapshot, source=source)

        if snapshot["state"] != "running":
            log.info("job %s finished: %s (%.0f%%)", upid, snapshot["state"], snapshot["percent"])
            # Pull the finished tasks into pbs_backup_main so the Backup Tasks table
            # shows this run now rather than after PBS's nightly cron.
            ok, detail = pbs_import.run_import()
            if not ok and detail != "disabled":
                log.warning("post-backup PBS import did not run: %s", detail)
            return
        time.sleep(config.POLL_INTERVAL_S)

    log.warning("stopped polling %s after %ss", upid, config.POLL_MAX_S)
    stale = {"upid": upid, "node": None, "state": "unknown", "percent": 0.0, "overall_percent": 0.0}
    influx.write_progress(stale, source=source)


def _watch(upid, source):
    thread = threading.Thread(target=_poll_job, args=(upid, source), daemon=True)
    with _jobs_lock:
        _jobs.setdefault(upid, {"source": source, "started_at": time.time()})["thread"] = thread
    thread.start()


# --- endpoints ----------------------------------------------------------------
@app.post("/api/backup/start")
def start_backup():
    global _last_upid

    missing = config.missing_required()
    if missing:
        return jsonify({"error": "service not configured", "missing": missing}), 503

    # Refuse to stack jobs: vzdump queues behind its own global lock, and a queued
    # job just publishes "Starting" every poll, which fights the live job for the
    # dashboard's last() value. Hand back the job already in flight instead.
    try:
        in_flight = client.running_vzdump()
    except PveError:
        in_flight = None
    if in_flight:
        with _jobs_lock:
            known = in_flight in _jobs
        if not known:
            _watch(in_flight, "adopted")
        return (
            jsonify(
                {
                    "upid": in_flight,
                    "state": "running",
                    "already_running": True,
                    "message": "A backup is already running on this node.",
                }
            ),
            409,
        )

    body = request.get_json(silent=True) or {}
    vmids = body.get("vmids")
    if isinstance(vmids, str):
        vmids = [v.strip() for v in vmids.split(",") if v.strip()]

    source = body.get("source") or "manual"

    try:
        upid = client.start_backup(
            vmids=vmids,
            storage=body.get("storage"),
            mode=body.get("mode"),
            compress=body.get("compress"),
            notes=body.get("notes"),
        )
    except PveError as exc:
        log.error("failed to start backup: %s", exc)
        return jsonify({"error": str(exc)}), 502

    log.info("started backup %s (source=%s)", upid, source)
    _last_upid = upid

    # Emit an immediate 0% point so the dashboard reacts without waiting a poll cycle.
    initial = {
        "upid": upid,
        "node": upid.split(":")[1] if ":" in upid else None,
        "state": "running",
        "state_label": "Starting",
        "percent": 0.0,
        "overall_percent": 0.0,
        "elapsed_s": 0,
    }
    _record(upid, initial, source)
    influx.write_progress(initial, source=source)
    _watch(upid, source)

    return jsonify({"upid": upid, "node": initial["node"], "state": "running", "source": source}), 202


@app.get("/api/backup/status/<path:upid>")
def backup_status(upid):
    if not upid.startswith("UPID:"):
        return jsonify({"error": "not a UPID"}), 400
    try:
        snapshot = client.task_progress(upid)
    except PveError as exc:
        return jsonify({"error": str(exc)}), 502

    with _jobs_lock:
        known = upid in _jobs
        source = _jobs.get(upid, {}).get("source", "unknown")
    _record(upid, snapshot, source)

    # A task we were never watching (e.g. started from the PVE UI) still gets followed.
    if not known and snapshot["state"] == "running":
        _watch(upid, source)

    return jsonify(snapshot)


@app.get("/api/backup/current")
def backup_current():
    with _jobs_lock:
        if not _last_upid or _last_upid not in _jobs:
            return jsonify({"state": "idle", "upid": None}), 200
        snapshot = dict(_jobs[_last_upid].get("snapshot") or {})
    return jsonify(snapshot or {"state": "idle", "upid": None})


@app.get("/health")
def health():
    missing = config.missing_required()
    pve_ok, pve_detail = False, None
    try:
        version = client.version() or {}
        pve_ok = True
        pve_detail = version.get("version")
    except (PveError, Exception) as exc:  # noqa: B014 - network errors vary
        pve_detail = str(exc)[:200]

    influx_ok = influx.health()
    ok = pve_ok and influx_ok and not missing
    return (
        jsonify(
            {
                "status": "ok" if ok else "degraded",
                "pve": {"reachable": pve_ok, "detail": pve_detail, "node": config.PVE_NODE},
                "influxdb": {"reachable": influx_ok, "bucket": config.INFLUX_BUCKET},
                "pbs_import": {"enabled": config.PBS_IMPORT_ENABLED, "host": config.PBS_HOST or None},
                "missing_config": missing,
            }
        ),
        200 if ok else 503,
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=config.TRIGGER_PORT)
