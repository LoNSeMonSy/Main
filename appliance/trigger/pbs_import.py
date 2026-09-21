"""Ask PBS to re-import its task archive into InfluxDB.

`pbs_backup_task.py` cannot move to this appliance (it reads PBS's local task archive),
so the appliance triggers it over SSH instead. The remote key is restricted to a forced
command, so this cannot run anything else on PBS.
"""
import logging
import subprocess

import config

log = logging.getLogger(__name__)


def run_import():
    """Returns (ok, detail). Never raises: a failed import must not fail the backup."""
    if not config.PBS_IMPORT_ENABLED:
        return False, "disabled"
    if not config.PBS_HOST:
        return False, "PBS_HOST not set"

    cmd = [
        "ssh",
        "-i", config.PBS_SSH_KEY,
        "-o", "IdentitiesOnly=yes",
        "-o", "BatchMode=yes",
        "-o", f"UserKnownHostsFile={config.PBS_KNOWN_HOSTS}",
        "-o", "StrictHostKeyChecking=yes",
        "-o", "ConnectTimeout=10",
        f"{config.PBS_SSH_USER}@{config.PBS_HOST}",
        # Ignored twice over: the PBS key is pinned to a forced command, and the label
        # no longer decides anything -- pbs_backup_task.py works each task's
        # manual/automatic label out per task. Kept for a readable audit log.
        "pbs-backup-run manual",
    ]
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=config.PBS_IMPORT_TIMEOUT_S
        )
    except subprocess.TimeoutExpired:
        log.warning("PBS import timed out after %ss", config.PBS_IMPORT_TIMEOUT_S)
        return False, "timeout"
    except OSError as exc:
        log.warning("PBS import could not start: %s", exc)
        return False, str(exc)

    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()[:300]
        log.warning("PBS import failed (rc=%s): %s", proc.returncode, detail)
        return False, detail
    log.info("PBS import completed")
    return True, (proc.stdout or "").strip()[:300]
