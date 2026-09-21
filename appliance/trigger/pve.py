"""Minimal Proxmox VE API client, just enough to start a vzdump job and watch it.

Two auth modes: API token (preferred, stateless) or username/password ticket.
"""
import logging
import re
import time
import urllib3

import requests

import config

log = logging.getLogger(__name__)

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# vzdump reports progress only in its task log, not in the task status endpoint.
# Example line:
#   INFO:  12% (1.2 GiB of 10.0 GiB) in 3s, read: 400.0 MiB/s, write: 380.0 MiB/s
_PROGRESS_RE = re.compile(
    r"(?P<pct>\d{1,3})%\s*\(\s*(?P<done>[\d.]+\s*[KMGTP]?i?B)\s+of\s+(?P<total>[\d.]+\s*[KMGTP]?i?B)\s*\)"
    r"(?:\s+in\s+(?P<elapsed>\d+\s*[hms](?:\s*\d+\s*[hms])*))?"
    r"(?:.*?read:\s*(?P<read>[\d.]+\s*[KMGTP]?i?B)/s)?"
    r"(?:.*?write:\s*(?P<write>[\d.]+\s*[KMGTP]?i?B)/s)?",
    re.IGNORECASE,
)
_VM_START_RE = re.compile(r"Starting Backup of VM (\d+)(?:\s*\((\w+)\))?", re.IGNORECASE)
# LXC guests log "CT Name:", QEMU guests log "VM Name:", and some guests log neither.
_VM_NAME_RE = re.compile(r"\b(?:VM|CT) Name:\s*(.+?)\s*$", re.IGNORECASE)
_VM_DONE_RE = re.compile(r"Finished Backup of VM (\d+)", re.IGNORECASE)
_VM_FAIL_RE = re.compile(r"Backup of VM (\d+) failed\s*-\s*(.+?)\s*$", re.IGNORECASE)
# Line 0 echoes the whole command, which is the only place the job's scope appears.
_JOB_CMD_RE = re.compile(r"starting new backup job:\s*vzdump\s+(.*)$", re.IGNORECASE)
GUEST_COUNT_TTL_S = 300
_UNITS = {
    "b": 1,
    "kb": 10**3, "mb": 10**6, "gb": 10**9, "tb": 10**12, "pb": 10**15,
    "kib": 2**10, "mib": 2**20, "gib": 2**30, "tib": 2**40, "pib": 2**50,
}


class PveError(RuntimeError):
    pass


def parse_size(text):
    """'1.2 GiB' -> bytes. Returns None if it does not look like a size."""
    if not text:
        return None
    m = re.match(r"\s*([\d.]+)\s*([KMGTP]?i?B)\s*$", text, re.IGNORECASE)
    if not m:
        return None
    try:
        return int(float(m.group(1)) * _UNITS[m.group(2).lower()])
    except (KeyError, ValueError):
        return None


def parse_duration(text):
    """'1h2m3s' / '45s' -> seconds. Returns None if unparseable."""
    if not text:
        return None
    total, found = 0, False
    for value, unit in re.findall(r"(\d+)\s*([hms])", text, re.IGNORECASE):
        found = True
        total += int(value) * {"h": 3600, "m": 60, "s": 1}[unit.lower()]
    return total if found else None


def upid_node(upid):
    """UPID:node:pid:pstart:starttime:type:id:user: -> node."""
    parts = upid.split(":")
    return parts[1] if len(parts) > 1 else config.PVE_NODE


def upid_starttime(upid):
    """Start time is hex-encoded in field 4 of the UPID."""
    parts = upid.split(":")
    if len(parts) > 4:
        try:
            return int(parts[4], 16)
        except ValueError:
            pass
    return None


class PveClient:
    def __init__(self):
        self.base = f"https://{config.PVE_HOST}:{config.PVE_PORT}/api2/json"
        self.session = requests.Session()
        self.session.verify = config.PVE_VERIFY_SSL
        self._csrf = None
        self._ticket_expires = 0
        self._guest_count = None
        self._guest_count_expires = 0

    # -- auth ------------------------------------------------------------------
    def _headers(self, write=False):
        if config.PVE_TOKEN_ID and config.PVE_TOKEN_SECRET:
            return {"Authorization": f"PVEAPIToken={config.PVE_TOKEN_ID}={config.PVE_TOKEN_SECRET}"}
        self._ensure_ticket()
        return {"CSRFPreventionToken": self._csrf} if write else {}

    def _ensure_ticket(self):
        # PVE tickets are valid for 2h; refresh a little early.
        if self._csrf and time.time() < self._ticket_expires:
            return
        if not (config.PVE_USER and config.PVE_PASSWORD):
            raise PveError("no PVE credentials configured")
        resp = self.session.post(
            f"{self.base}/access/ticket",
            data={"username": config.PVE_USER, "password": config.PVE_PASSWORD},
            timeout=20,
        )
        if resp.status_code != 200:
            raise PveError(f"PVE login failed: HTTP {resp.status_code} {resp.text[:200]}")
        data = resp.json().get("data") or {}
        ticket = data.get("ticket")
        self._csrf = data.get("CSRFPreventionToken")
        if not ticket:
            raise PveError("PVE login returned no ticket")
        self.session.cookies.set("PVEAuthCookie", ticket)
        self._ticket_expires = time.time() + 5400

    # -- requests --------------------------------------------------------------
    def _get(self, path, params=None):
        resp = self.session.get(
            f"{self.base}{path}", headers=self._headers(), params=params, timeout=30
        )
        if resp.status_code != 200:
            raise PveError(f"GET {path} -> HTTP {resp.status_code}: {resp.text[:300]}")
        return resp.json().get("data")

    def _post(self, path, data=None):
        resp = self.session.post(
            f"{self.base}{path}", headers=self._headers(write=True), data=data, timeout=60
        )
        if resp.status_code not in (200, 201):
            raise PveError(f"POST {path} -> HTTP {resp.status_code}: {resp.text[:300]}")
        return resp.json().get("data")

    # -- operations ------------------------------------------------------------
    def version(self):
        return self._get("/version")

    def start_backup(self, vmids=None, storage=None, mode=None, compress=None, notes=None):
        """Kick off a vzdump job. Returns the UPID of the resulting task."""
        node = config.PVE_NODE
        params = {
            "mode": mode or config.BACKUP_MODE,
            "storage": storage or config.BACKUP_STORAGE,
            "compress": compress or config.BACKUP_COMPRESS,
        }
        params = {k: v for k, v in params.items() if v}

        vmids = vmids if vmids is not None else config.BACKUP_VMIDS
        if vmids:
            params["vmid"] = ",".join(str(v) for v in vmids)
        else:
            params["all"] = 1

        note = notes or config.BACKUP_NOTES
        if note:
            # PVE 7.2+ names this notes-template; harmless if the target ignores it.
            params["notes-template"] = note

        upid = self._post(f"/nodes/{node}/vzdump", data=params)
        if not isinstance(upid, str) or not upid.startswith("UPID:"):
            raise PveError(f"vzdump did not return a UPID, got: {upid!r}")
        return upid

    def node_guest_count(self):
        """How many guests exist on the node, for '--all' jobs.

        Cached briefly rather than forever: guests get created and destroyed, and a
        permanently cached count would keep reporting "N of <stale total>".
        """
        if self._guest_count is not None and time.time() < self._guest_count_expires:
            return self._guest_count
        total = 0
        for kind in ("qemu", "lxc"):
            try:
                total += len(self._get(f"/nodes/{config.PVE_NODE}/{kind}") or [])
            except PveError:
                return None
        self._guest_count = total
        self._guest_count_expires = time.time() + GUEST_COUNT_TTL_S
        return total

    def _job_total(self, lines):
        """Guest count for the job, derived from the vzdump command echoed in the log.

        The echo is usually line 0, but a job waiting on vzdump's global lock logs
        "trying to get global lock - waiting..." first, so the whole head is scanned.
        """
        m = None
        for line in (lines or [])[:20]:
            m = _JOB_CMD_RE.search(line or "")
            if m:
                break
        if not m:
            return None
        cmd = m.group(1)
        # PVE echoes scoped guests positionally ("vzdump 999 --storage ..."), and only
        # sometimes as --vmid, so both forms have to be handled.
        positional = re.match(r"^([\d,\s]+?)(?=\s+--|\s*$)", cmd)
        vmid = re.search(r"--vmid[\s=]+(\S+)", cmd)
        raw = None
        if positional:
            raw = positional.group(1)
        elif vmid:
            raw = vmid.group(1)
        if raw:
            return len([v for v in re.split(r"[,\s]+", raw.strip("'\"")) if v])
        if re.search(r"--all[\s=]+1", cmd):
            return self.node_guest_count()
        return None

    def running_vzdump(self):
        """UPID of a vzdump already running on the node, if any.

        vzdump serialises on a global lock, so a second job does not run in parallel,
        it queues -- and a queued job publishes no useful progress while it waits.
        """
        try:
            # source=active is essential: /tasks defaults to source=archive, which
            # lists only *finished* tasks, so a running job is invisible without it.
            # (There is no "running" parameter -- sending one fails with HTTP 400.)
            tasks = self._get(
                f"/nodes/{config.PVE_NODE}/tasks",
                params={"limit": 20, "typefilter": "vzdump", "source": "active"},
            ) or []
        except PveError as exc:
            # Do not silently pretend nothing is running -- that is how a broken guard
            # looks identical to an idle node.
            log.warning("could not list vzdump tasks: %s", exc)
            return None
        for task in tasks:
            if task.get("endtime"):
                continue
            if str(task.get("status", "")).lower() in ("", "running"):
                return task.get("upid")
        return None

    def task_status(self, upid):
        node = upid_node(upid)
        return self._get(f"/nodes/{node}/tasks/{upid}/status") or {}

    def task_log(self, upid, start=0, limit=500):
        node = upid_node(upid)
        lines = self._get(
            f"/nodes/{node}/tasks/{upid}/log", params={"start": start, "limit": limit}
        ) or []
        return [entry.get("t", "") for entry in lines]

    def task_progress(self, upid, log_start=0):
        """Merge task status with the latest progress line from the task log."""
        status = self.task_status(upid)
        running = status.get("status") == "running"
        exitstatus = status.get("exitstatus")

        # Pull a generous tail of the log so we always see the newest progress line.
        lines = self.task_log(upid, start=log_start, limit=1000)

        progress = {}
        current_vmid = None
        order = []            # guests in the order vzdump started them
        names = {}            # vmid -> guest name, when the log reports one
        done, failed = [], []  # completed / failed vmids
        errors = {}           # vmid -> failure reason

        for line in lines:
            vm = _VM_START_RE.search(line)
            if vm:
                current_vmid = vm.group(1)
                if current_vmid not in order:
                    order.append(current_vmid)
                # Each guest restarts at 0%; without this reset a guest that finishes
                # too fast to log any progress inherits the previous guest's numbers.
                progress = {}
                continue

            name = _VM_NAME_RE.search(line)
            if name and current_vmid:
                names[current_vmid] = name.group(1)
                continue

            fin = _VM_DONE_RE.search(line)
            if fin:
                if fin.group(1) not in done:
                    done.append(fin.group(1))
                continue

            bad = _VM_FAIL_RE.search(line)
            if bad:
                if bad.group(1) not in failed:
                    failed.append(bad.group(1))
                errors[bad.group(1)] = bad.group(2)
                continue

            m = _PROGRESS_RE.search(line)
            if m:
                progress = {
                    "percent": float(m.group("pct")),
                    "bytes_done": parse_size(m.group("done")),
                    "bytes_total": parse_size(m.group("total")),
                    "elapsed_s": parse_duration(m.group("elapsed")),
                    "read_bytes_s": parse_size(m.group("read")),
                    "write_bytes_s": parse_size(m.group("write")),
                    "vmid": current_vmid,
                }

        starttime = status.get("starttime") or upid_starttime(upid)
        wall_elapsed = int(time.time() - starttime) if starttime else None

        if running:
            state = "running"
        elif exitstatus in ("OK", "ok"):
            state = "ok"
        elif exitstatus:
            state = "error"
        else:
            state = "unknown"

        percent = progress.get("percent")
        if state == "ok":
            percent = 100.0
        elif percent is None:
            percent = 0.0

        vm_total = self._job_total(lines)
        vm_index = len(order) if order else None
        vm_name = None  # set below, so it always agrees with the reported vmid

        # Whole-job progress. vzdump backs guests up one at a time and restarts its
        # log percentage at 0 for each one, so the per-guest number on its own looks
        # like the job keeps starting over. Count finished guests as whole units and
        # add the fraction of the guest currently in flight. Guests are weighted
        # equally: vzdump publishes no job-wide byte total up front, so there is
        # nothing better to weight by -- a 2 GB guest and a 200 GB guest each count
        # as one unit, so the bar advances unevenly but never goes backwards.
        completed = set(done) | set(failed)
        if vm_total:
            in_flight = 0.0
            if state == "running" and current_vmid and current_vmid not in completed:
                in_flight = min(max(percent, 0.0), 100.0) / 100.0
            overall_percent = min(100.0, round((len(completed) + in_flight) * 100.0 / vm_total, 1))
        else:
            # The job's scope never appeared in the log head, so there is no
            # denominator. Fall back to the per-guest number to keep the gauge
            # populated rather than blank -- it is the only figure available.
            overall_percent = percent
        if state == "ok":
            overall_percent = 100.0

        # ETA for the whole job: wall-clock elapsed against *overall* progress, not
        # the current guest's own elapsed. A per-guest ETA next to a whole-job gauge
        # reads as the time left on the job and is wrong by however many guests are
        # still queued. A finished task must publish eta_s = 0 rather than omitting
        # the field: Flux last() skips nulls, so an absent value leaves the panel
        # showing the final in-flight estimate forever.
        eta_s = 0 if state in ("ok", "error") else None
        if state == "running" and overall_percent >= 100:
            # Every guest is accounted for and vzdump is just closing the job out;
            # publishing 0 beats leaving the last mid-job estimate on the panel.
            eta_s = 0
        elif state == "running" and wall_elapsed and 0 < overall_percent < 100:
            eta_s = int(wall_elapsed * (100.0 - overall_percent) / overall_percent)

        def label_for(vmid):
            return f"{names.get(vmid, 'vm-' + vmid)} ({vmid})"

        # On a terminal failure the guest that actually broke is what matters, not
        # whichever guest happened to be last -- vzdump keeps going after one fails.
        if state == "error" and failed:
            reported_vmid = failed[0]
            names_failed = ", ".join(label_for(v) for v in failed)
            state_label = f"Failed: {names_failed}"
        elif state == "error":
            reported_vmid = current_vmid
            state_label = "Failed"
        elif state == "ok":
            reported_vmid = current_vmid
            state_label = f"Complete: {len(done)} guest{'s' if len(done) != 1 else ''}"
        elif state == "running" and current_vmid:
            reported_vmid = current_vmid
            position = f" - {vm_index} of {vm_total}" if vm_index and vm_total else ""
            # The per-guest percentage lives in the label now that the gauge next to
            # it counts the whole job, so neither number is lost.
            state_label = f"Running: {label_for(current_vmid)}{position} - {percent:.0f}%"
        elif state == "running":
            reported_vmid = None
            state_label = "Starting"
        else:
            reported_vmid = current_vmid
            state_label = "Unknown"

        if reported_vmid:
            vm_name = names.get(reported_vmid)

        return {
            "upid": upid,
            "node": upid_node(upid),
            "state": state,
            "state_label": state_label,
            "running": running,
            "exitstatus": exitstatus,
            "percent": percent,
            "overall_percent": overall_percent,
            "bytes_done": progress.get("bytes_done"),
            "bytes_total": progress.get("bytes_total"),
            "read_bytes_s": progress.get("read_bytes_s"),
            "write_bytes_s": progress.get("write_bytes_s"),
            "elapsed_s": wall_elapsed,
            "eta_s": eta_s,
            "vmid": reported_vmid,
            "vm_name": vm_name,
            "vm_index": vm_index,
            "vm_total": vm_total,
            "guests_done": len(done),
            "guests_failed": len(failed),
            "failed_vmids": failed,
            "error_message": "; ".join(f"{label_for(v)}: {errors[v]}" for v in failed) or None,
            "starttime": starttime,
            "log_tail": lines[-5:],
        }
