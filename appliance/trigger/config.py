"""Configuration, read entirely from the environment (sourced from .env by compose).

Nothing site-specific is hardcoded here, see docs/TEMPLATE_TODO.md.
"""
import os


def _bool(name, default=False):
    return os.environ.get(name, str(default)).strip().lower() in ("1", "true", "yes", "on")


def _int(name, default):
    raw = os.environ.get(name, "").strip()
    return int(raw) if raw else default


# --- Proxmox VE ---------------------------------------------------------------
PVE_HOST = os.environ.get("PVE_HOST", "").strip()
PVE_PORT = _int("PVE_PORT", 8006)
PVE_NODE = os.environ.get("PVE_NODE", "").strip()
PVE_VERIFY_SSL = _bool("PVE_VERIFY_SSL", False)

# Preferred: API token auth (no ticket refresh, scoped permissions).
PVE_TOKEN_ID = os.environ.get("PVE_TOKEN_ID", "").strip()
PVE_TOKEN_SECRET = os.environ.get("PVE_TOKEN_SECRET", "").strip()

# Fallback: username/password ticket auth.
PVE_USER = os.environ.get("PVE_USER", "").strip()
PVE_PASSWORD = os.environ.get("PVE_PASSWORD", "").strip()

# --- Backup job defaults ------------------------------------------------------
BACKUP_STORAGE = os.environ.get("BACKUP_STORAGE", "").strip()
# Comma-separated VMIDs. Empty means "all guests on the node" (vzdump --all).
BACKUP_VMIDS = [v.strip() for v in os.environ.get("BACKUP_VMIDS", "").split(",") if v.strip()]
BACKUP_MODE = os.environ.get("BACKUP_MODE", "snapshot").strip()
BACKUP_COMPRESS = os.environ.get("BACKUP_COMPRESS", "zstd").strip()
BACKUP_NOTES = os.environ.get("BACKUP_NOTES", "Manual trigger from Grafana").strip()

# --- InfluxDB -----------------------------------------------------------------
INFLUX_URL = os.environ.get("INFLUX_URL", "http://influxdb:8086").strip()
INFLUX_ORG = os.environ.get("INFLUXDB_ORG", "").strip()
INFLUX_BUCKET = os.environ.get("INFLUXDB_BUCKET", "").strip()
INFLUX_TOKEN = os.environ.get("INFLUXDB_TOKEN", "").strip()
INFLUX_MEASUREMENT = os.environ.get("INFLUX_PROGRESS_MEASUREMENT", "pbs_backup_progress").strip()

# --- PBS import (makes manual runs appear in the Backup Tasks table promptly) ---
# pbs_backup_task.py has to run ON PBS (it reads a local task archive), so after a
# backup finishes we ask PBS to re-import. Re-importing is idempotent: identical tags
# and timestamps mean InfluxDB overwrites rather than duplicating rows.
PBS_HOST = os.environ.get("PBS_HOST", "").strip()
PBS_SSH_USER = os.environ.get("PBS_SSH_USER", "root").strip()
PBS_SSH_KEY = os.environ.get("PBS_SSH_KEY", "/run/secrets/pbs_key").strip()
PBS_KNOWN_HOSTS = os.environ.get("PBS_KNOWN_HOSTS", "/run/secrets/pbs_known_hosts").strip()
PBS_IMPORT_ENABLED = _bool("PBS_IMPORT_ENABLED", False)
PBS_IMPORT_TIMEOUT_S = _int("PBS_IMPORT_TIMEOUT_S", 120)

# --- Service ------------------------------------------------------------------
TRIGGER_PORT = _int("TRIGGER_PORT", 5001)
POLL_INTERVAL_S = _int("POLL_INTERVAL_S", 5)
# Safety valve so a wedged task cannot leave a polling thread running forever.
POLL_MAX_S = _int("POLL_MAX_S", 21600)
# Browsers hit this directly from the Grafana dashboard, so CORS matters.
CORS_ORIGIN = os.environ.get("CORS_ORIGIN", "*").strip()
# Optional shared secret. When set, requests must send X-Trigger-Token.
TRIGGER_TOKEN = os.environ.get("TRIGGER_TOKEN", "").strip()


def missing_required():
    """Return the names of config values the service cannot start a job without."""
    missing = []
    if not PVE_HOST:
        missing.append("PVE_HOST")
    if not PVE_NODE:
        missing.append("PVE_NODE")
    if not (PVE_TOKEN_ID and PVE_TOKEN_SECRET) and not (PVE_USER and PVE_PASSWORD):
        missing.append("PVE_TOKEN_ID+PVE_TOKEN_SECRET or PVE_USER+PVE_PASSWORD")
    for name in ("INFLUX_ORG", "INFLUX_BUCKET", "INFLUX_TOKEN"):
        if not globals()[name]:
            missing.append(name)
    return missing
