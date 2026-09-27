# Weekly Suricata rule refresh silently stops port-scan detection

**Found:** 2026-09-27, while re-testing port-scan detection before the demo.
**Severity:** medium. Scan detection goes dark every week with no error anywhere.
**Status:** open. Worked around by hand (Suricata restarted 2026-09-27 22:24 UTC);
the cause is not fixed. Next scheduled refresh: Sun 2026-10-04 ~04:51 UTC.

## What

`suricata-update.timer` runs every Sunday. Its service ends with
`suricatasc -c reload-rules` (a live reload, no restart). After the reload on
2026-09-27 04:57, an `nmap -sS --top-ports 300` from `kali-redteam` produced
**no** Suricata alerts at all, even though the same scan produced five on
2026-09-26 (see `docs/PORTSCAN.md`). Suricata stayed "active" and kept writing
`stats.log`, so nothing looked wrong.

After `sudo systemctl restart suricata`, the identical scan immediately produced
all five alerts again, and they reached Wazuh as rule 86601.

## Likely cause (not yet proven)

`HOME_NET` is set to the appliance's own address with `--set` on the command line
at service start (`10-lonsemonsy-homenet.conf`). A live rule reload re-reads the
address groups from `suricata.yaml`, which still says `192.168.0.0/16,...`. That
puts the attacker inside `HOME_NET`, which is exactly the "not one scan rule
fires" case `PORTSCAN.md` describes.

## Options

1. Have the refresh **restart** Suricata instead of reloading it
   (`ExecStartPost=-/usr/bin/systemctl restart suricata`). A few seconds of no
   capture once a week.
2. Put the derived `HOME_NET` into a file `suricata.yaml` includes, so a reload
   sees the same value as a restart.

Either way, re-run the scan test after the next refresh to confirm.
