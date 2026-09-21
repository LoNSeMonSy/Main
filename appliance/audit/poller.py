"""One poll loop per audit source, plus a manual trigger for the hub's button.

Mirrors alerts/feed.py's one-thread-per-mode shape: each source gets its own
thread, its own cursor and its own lock, so a slow or broken Tailscale poll cannot
stall Proxmox ingestion or the other way round.

Each lock is acquired non-blocking. A caller that finds a source already polling
is told so rather than queued behind it -- the same answer backup-trigger gives
for a stacked vzdump, and for the same reason: two overlapping polls would race on
the cursor and re-request the same window twice.
"""
import logging
import threading
import time

import config
import influx
from sources import SOURCES, SourceError, enabled_sources

log = logging.getLogger(__name__)

_NS_PER_DAY = 86_400 * 1_000_000_000
_NS_PER_MIN = 60 * 1_000_000_000

# Longest span asked for in one upstream call. Neither source paginates, so a
# 30-day backfill is walked in slices rather than pulled as one huge response.
_MAX_WINDOW_NS = 7 * _NS_PER_DAY


class Poller:
    def __init__(self):
        self._locks = {name: threading.Lock() for name in SOURCES}
        self._state_lock = threading.Lock()
        self._cursors = {name: None for name in SOURCES}
        self._threads = {}
        self._status = {
            name: {
                "last_poll_ms": None, "last_ok": None, "last_error": None,
                "last_written": 0, "total_written": 0, "last_trigger": None,
            }
            for name in SOURCES
        }

    # --- state ----------------------------------------------------------------
    def status(self):
        with self._state_lock:
            snapshot = {name: dict(s) for name, s in self._status.items()}
        for name, entry in snapshot.items():
            entry["enabled"] = SOURCES[name].enabled()
            entry["missing_config"] = SOURCES[name].missing_config()
            entry["running"] = self._locks[name].locked()
            entry["scheduled_loop"] = name in self._threads
        return snapshot

    def _mark(self, name, ok, trigger, written=0, error=None):
        with self._state_lock:
            entry = self._status[name]
            entry["last_poll_ms"] = int(time.time() * 1000)
            entry["last_ok"] = ok
            entry["last_error"] = error
            entry["last_written"] = written
            entry["last_trigger"] = trigger
            if written:
                entry["total_written"] += written

    # --- cursor ---------------------------------------------------------------
    def _initial_cursor(self, source):
        """Resume from this source's newest stored event, else reach back.

        The cursor is per source and lives in InfluxDB, so enabling a second source
        later does not make it think it has already caught up to the first one's
        history, and a container restart needs no state file or volume.
        """
        latest = influx.latest_event_ns(source.NAME)
        if latest is not None:
            log.info("[%s] resuming from the newest stored event", source.NAME)
            return latest

        days = config.BACKFILL_DAYS
        cap = source.max_backfill_days()
        if cap is not None:
            days = min(days, cap)
        log.info("[%s] nothing stored yet, backfilling %d day(s)", source.NAME, days)
        return time.time_ns() - days * _NS_PER_DAY

    # --- the fetch ------------------------------------------------------------
    def _poll_once(self, source, cursor):
        """Fetch and store everything from `cursor` to now. Returns (cursor, written)."""
        # Re-read a little behind the cursor: an event is not always queryable the
        # instant it happens, and re-writes are idempotent (see influx.py).
        start = cursor - config.OVERLAP_MIN * _NS_PER_MIN
        end = time.time_ns()
        if end <= start:
            return cursor, 0

        newest = cursor
        total = 0
        window_start = start
        while window_start < end:
            window_end = min(window_start + _MAX_WINDOW_NS, end)
            events = source.fetch(window_start, window_end)
            if events:
                written = influx.write_events(events)
                total += written
                newest = max(newest, max(e["ts_ns"] for e in events))
                if written < len(events):
                    # A failed write must not advance the cursor past what was
                    # stored, or the missing events would never be fetched again.
                    log.warning("[%s] only %d of %d event(s) written, holding cursor",
                                source.NAME, written, len(events))
                    return cursor, total
            window_start = window_end
        return newest, total

    def poll_source(self, name, trigger="scheduled"):
        """Run one poll of one source. Returns a result dict; never raises."""
        source = SOURCES.get(name)
        if source is None:
            return {"source": name, "ok": False, "reason": "unknown", "written": 0}

        missing = source.missing_config()
        if missing:
            return {"source": name, "ok": False, "reason": "unconfigured",
                    "missing": missing, "written": 0}

        if not self._locks[name].acquire(blocking=False):
            return {"source": name, "ok": False, "reason": "busy", "written": 0}

        try:
            if self._cursors[name] is None:
                self._cursors[name] = self._initial_cursor(source)
            cursor, written = self._poll_once(source, self._cursors[name])
            self._cursors[name] = cursor
            self._mark(name, True, trigger, written=written)
            if written:
                log.info("[%s] wrote %d event(s) (%s)", name, written, trigger)
            elif trigger == "manual":
                log.info("[%s] manual poll found no new events", name)
            return {"source": name, "ok": True, "written": written, "reason": None}
        except SourceError as exc:
            # Credential and reachability problems get one clear line, not a stack
            # trace; the loop keeps going so a transient outage self-heals.
            log.warning("[%s] %s", name, exc)
            self._mark(name, False, trigger, error=str(exc))
            return {"source": name, "ok": False, "reason": "upstream",
                    "error": str(exc), "written": 0}
        except Exception as exc:
            log.exception("[%s] unexpected error during poll", name)
            self._mark(name, False, trigger, error=str(exc))
            return {"source": name, "ok": False, "reason": "error",
                    "error": str(exc), "written": 0}
        finally:
            self._locks[name].release()

    def poll_all(self, trigger="manual"):
        """Poll every *configured* source, enabled or not. One result per source.

        Deliberately not filtered on enabled(): a manual poll checks credentials,
        not the scheduling switch. That is the whole "paste the client id, press
        the button, see whether it works, then commit to enabling it" path -- a
        source you cannot poll until you have already enabled it is useless for
        finding out whether enabling it would work.

        Sources with no credentials are still returned, carrying their
        "unconfigured" reason, so the caller can say which ones sat out.
        """
        return [self.poll_source(name, trigger=trigger) for name in sorted(SOURCES)]

    # --- scheduled loops ------------------------------------------------------
    def start(self):
        """Start one background loop per enabled, configured source."""
        for source in enabled_sources():
            missing = source.missing_config()
            if missing:
                log.info("[%s] missing config: %s -- no scheduled polling "
                         "(the hub's Poll Now button still works once it is set)",
                         source.NAME, ", ".join(missing))
                continue
            with self._state_lock:
                if source.NAME in self._threads:
                    continue
                thread = threading.Thread(
                    target=self._loop, args=(source.NAME,),
                    name=f"poll-{source.NAME}", daemon=True,
                )
                self._threads[source.NAME] = thread
            thread.start()
            log.info("[%s] polling every %ds into measurement %r",
                     source.NAME, config.POLL_INTERVAL_S, config.AUDIT_MEASUREMENT)

        for name in SOURCES:
            if not SOURCES[name].enabled():
                log.info("[%s] disabled -- set its *_ENABLED to true to schedule it", name)

    def _loop(self, name):
        while True:
            self.poll_source(name, trigger="scheduled")
            time.sleep(config.POLL_INTERVAL_S)


poller = Poller()
