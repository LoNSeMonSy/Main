# Log rotation can drop Suricata alerts before Wazuh reads them

**Found:** 2026-09-26, while wiring Suricata into Wazuh.
**Severity:** low (narrow window, self-healing) — but it is a *detection* gap, so
it is worth a decision rather than a silent fix.
**Status:** open, not fixed.

## What

`/etc/logrotate.d/suricata` rotates with `copytruncate`: it copies the file, then
truncates the original in place. `wazuh-logcollector` follows `eve.json` by byte
offset. Between the copy and the truncate, any alert Suricata writes is lost, and
immediately after the truncate the collector still holds the pre-rotation offset,
so it reads nothing until the file grows back past that point.

## How it was observed

Not theoretical — hit by accident. `eve.json` was truncated manually during
testing, a scan was run, Suricata logged 5 alerts, and Wazuh ingested **0**. A
later scan caused the file to pass the stale offset and Wazuh then delivered all
9 lines at once, so it does recover.

## Why it is low severity today

`eve.json` is trimmed to alert events only, so it sits at 0 B/s when idle and will
essentially never hit `maxsize 50M`. Rotation realistically only fires during a
sustained attack — which is exactly the worst time to drop events, hence logging
it rather than ignoring it.

## Possible fix (needs a decision)

Switch the rotation to `create` (rename + recreate) instead of `copytruncate` and
rely on the existing `postrotate` `kill -HUP` for Suricata to reopen its files.
Wazuh handles an inode change cleanly, which removes the offset problem entirely.
Not done unilaterally: if Suricata ever fails to reopen on HUP, it would log to a
deleted inode and we would lose *everything* rather than a few events — a worse
failure mode that should be tested before adopting.

See `docs/PORTSCAN.md`.
