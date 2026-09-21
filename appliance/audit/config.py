"""Configuration, read entirely from the environment (sourced from .env by compose).

Nothing site-specific is hardcoded here, see docs/TEMPLATE_TODO.md.
"""
import os


def _bool(name, default=False):
    return os.environ.get(name, str(default)).strip().lower() in ("1", "true", "yes", "on")


def _int(name, default):
    raw = os.environ.get(name, "").strip()
    return int(raw) if raw else default


# --- InfluxDB -----------------------------------------------------------------
INFLUX_URL = os.environ.get("INFLUX_URL", "http://influxdb:8086").strip()
INFLUX_ORG = os.environ.get("INFLUXDB_ORG", "").strip()
INFLUX_BUCKET = os.environ.get("INFLUXDB_BUCKET", "").strip()
INFLUX_TOKEN = os.environ.get("INFLUXDB_TOKEN", "").strip()
# One measurement for every audit source, separated by the `source` tag -- the
# same shape as security_alerts' test/live split. Four sources in four
# measurements would mean four queries behind one table for no benefit.
AUDIT_MEASUREMENT = os.environ.get("AUDIT_MEASUREMENT", "").strip() or "audit_log"

# --- Collector ----------------------------------------------------------------
POLL_INTERVAL_S = _int("AUDIT_POLL_INTERVAL_S", 300)
# How far back the very first run reaches when a source has stored nothing yet.
BACKFILL_DAYS = _int("AUDIT_BACKFILL_DAYS", 30)
# Each poll re-reads this far behind the cursor. Events are not always queryable
# the instant they happen, so a strict "newer than last seen" window would drop
# late arrivals. Re-reads are harmless: an event always maps to the same series
# and timestamp, so it overwrites itself.
OVERLAP_MIN = _int("AUDIT_OVERLAP_MIN", 10)
HTTP_TIMEOUT_S = _int("AUDIT_HTTP_TIMEOUT_S", 30)

# --- Service ------------------------------------------------------------------
# Internal only: not published to the host in docker-compose.yml, reached by the
# hub over the compose network as http://audit-collector:5003.
PORT = _int("AUDIT_PORT", 5003)

# --- Source: Tailscale --------------------------------------------------------
# Off by default: it needs a credential a human has to create in the Tailscale
# admin console, so a stack brought up without one idles instead of logging auth
# failures forever.
TS_ENABLED = _bool("TSAUDIT_ENABLED", False)
TS_API_URL = os.environ.get("TSAUDIT_API_URL", "https://api.tailscale.com").strip().rstrip("/")
# "-" means "the tailnet this credential belongs to", which is what you want for
# an OAuth client. A personal tailnet's explicit name is the owner's login.
TS_TAILNET = os.environ.get("TAILSCALE_TAILNET", "-").strip() or "-"
TS_OAUTH_CLIENT_ID = os.environ.get("TAILSCALE_OAUTH_CLIENT_ID", "").strip()
TS_OAUTH_CLIENT_SECRET = os.environ.get("TAILSCALE_OAUTH_CLIENT_SECRET", "").strip()
TS_API_KEY = os.environ.get("TAILSCALE_API_KEY", "").strip()
# Tailscale keeps configuration audit logs for 90 days, so reaching past that is
# wasted work.
TS_MAX_BACKFILL_DAYS = 90

# --- Source: Proxmox VE -------------------------------------------------------
# On by default, unlike Tailscale: it reuses the credentials the backup-trigger
# service already needs, so there is nothing new for an operator to create. With
# no PVE credentials configured it reports itself unconfigured and idles.
PVE_ENABLED = _bool("PVEAUDIT_ENABLED", True)
PVE_HOST = os.environ.get("PVE_HOST", "").strip()
PVE_PORT = _int("PVE_PORT", 8006)
PVE_VERIFY_SSL = _bool("PVE_VERIFY_SSL", False)
PVE_TOKEN_ID = os.environ.get("PVE_TOKEN_ID", "").strip()
PVE_TOKEN_SECRET = os.environ.get("PVE_TOKEN_SECRET", "").strip()
PVE_USER = os.environ.get("PVE_USER", "").strip()
PVE_PASSWORD = os.environ.get("PVE_PASSWORD", "").strip()
# /cluster/log cannot be filtered by time server-side (see sources/pve.py), so a
# poll pulls this many recent entries and discards what it has already stored.
PVE_LOG_MAX = _int("PVEAUDIT_LOG_MAX", 500)
# Per-node task pages. /nodes/{node}/tasks does honour `since`, so this is only a
# ceiling on one poll's worth.
PVE_TASK_LIMIT = _int("PVEAUDIT_TASK_LIMIT", 500)
