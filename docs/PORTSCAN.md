# Port-scan detection (Suricata)

Detects a port scan aimed at the appliance and raises it as a Wazuh alert, which
Grafana already reads. Off-the-shelf tooling, config only — no hand-written
detection logic.

Chain: `nmap` → **Suricata** (`eve.json`) → **Wazuh** (rule 86601) → indexer →
**Grafana**. This is the same path the SSH brute-force demo uses, so the alert
lands next to it with no new plumbing.

## Install

    sudo appliance/suricata/install-suricata.sh

Idempotent, safe to re-run. It installs Suricata, applies the scan-only ruleset,
tunes `suricata.yaml`, adds the Wazuh `<localfile>` block and restarts both
services. Everything it does is listed below.

## Why nothing here hardcodes 192.168.12.0/24

The ET SCAN signatures are written `$EXTERNAL_NET any -> $HOME_NET any`, so
`HOME_NET` decides what counts as "inbound". It is the only site-specific value in
the whole setup — and we never store it as a literal.

`/usr/local/sbin/lonsemonsy-homenet` derives it from the appliance's own interface
**every time the service starts** (systemd drop-in
`10-lonsemonsy-homenet.conf` passes it via `--set`). A customer on `10.4.0.0/16`
gets the right value with no edit, and a DHCP change can't leave it stale.

Policy lives in `/etc/default/lonsemonsy-suricata`:

| `SURICATA_HOME_NET_POLICY` | Derives | Use when |
|---|---|---|
| `self` (default) | the appliance's own address, `/32` | now — Suricata only sees traffic addressed to this host |
| `lan` | the appliance's subnet, e.g. `10.4.0.0/16` | after a vmbr0 mirror/SPAN feeds it whole-network traffic |

`SURICATA_HOME_NET` overrides both if a site ever needs an explicit list.

**This matters more than it looks.** With Suricata's stock
`HOME_NET: 192.168.0.0/16`, the lab's attacker (192.168.12.102) is *inside*
`HOME_NET`, so `EXTERNAL_NET` (`!$HOME_NET`) excludes it and **not one scan rule
fires**. Setting `HOME_NET` to the appliance itself is what makes a LAN-internal
scan visible — and it also stops NetAlertX's own outbound nmap sweeps from
alerting on themselves.

## What the install changes

- **Ruleset** — ET Open is ~69k rules. `disable.conf` (`re:.`) turns everything
  off, `enable.conf` (`group:emerging-scan.rules`) re-enables the scan group:
  **367 rules**, ~64 MB RSS. Deliberate: the Wazuh indexer already holds ~2.5 GB
  on a 7.8 GB box, so the full ruleset was not affordable.
- **`eve.json` → alerts only.** Stock config also logs `flow`/`dns`/`tls`/`http`
  per packet — measured at **120 MB/day here**, all of which would have been
  ingested by Wazuh for zero detection benefit. Now idle growth is 0 B/s; the file
  only grows during an actual attack.
- **`stats.log` interval 8s → 600s** (~94 MB/day → ~1 MB/day). Kept, not disabled,
  because it is how you check for kernel packet drops.
- **logrotate** — the packaged `/etc/logrotate.d/suricata` ships *no* frequency
  directive, so it silently inherited `weekly`. Now `daily` + `maxsize 50M`.
- **Wazuh** — a `<localfile>` block reading `/var/log/suricata/eve.json` as
  `json`. Wazuh's native decoder and stock rules `86600`/`86601` (group
  `ids,suricata`) do the rest; no custom rule needed to get alerts flowing.
- **Weekly rule refresh** — `suricata-update.timer` (Sun 04:30, randomized). It
  re-applies `disable.conf`/`enable.conf` each run, so the ruleset stays scan-only
  instead of ballooning back to full ET Open. Reloads live, no restart.

## Verified working

Scan run from `kali-redteam` (LXC 8103, 192.168.12.102):

    pct exec 8103 -- nmap -sS -T4 --top-ports 300 192.168.12.112

Suricata fired, and all five reached `alerts.json` **and** the indexer
(`wazuh-alerts-*`, queried as the same `grafana` user the datasource uses):

| Suricata sid | Signature | Wazuh |
|---|---|---|
| 2009582 | ET SCAN NMAP -sS window 1024 | rule 86601, level 3 |
| 2010935 | ET SCAN Suspicious inbound to MSSQL port 1433 | rule 86601, level 3 |
| 2010936 | ET SCAN Suspicious inbound to Oracle SQL port 1521 | rule 86601, level 3 |
| 2010937 | ET SCAN Suspicious inbound to mySQL port 3306 | rule 86601, level 3 |
| 2010939 | ET SCAN Suspicious inbound to PostgreSQL port 5432 | rule 86601, level 3 |

`data.src_ip` is populated (`192.168.12.102`), which is what a Grafana panel or a
local rule would group on.

Watch it live:

    sudo tail -f /var/ossec/logs/alerts/alerts.json | grep -i suricata

## Still to do (deliberately not done here)

- **A tuned local rule.** Stock 86601 is level 3 with a generic description. The
  project's pattern — stock behaviour vs. your own rule — is the thing to demo,
  exactly as `100100` does for SSH brute force in `wazuh/local_rules.xml`. Writing
  that rule is coursework, so it was left alone.
- **A Grafana panel.** The data is queryable now; the dashboard was being edited
  in parallel, so no panel was added to avoid a conflict.
- **Whole-network scanning.** Needs a vmbr0 mirror/SPAN — host networking, Tim's
  call. Flip the policy to `lan` on the day that lands.

## Limitations

- Sees only traffic addressed to the appliance. `vmbr0` is a switching bridge, so
  a scan of *another* host never reaches this NIC. This is a visibility limit, not
  a tuning one — no config fixes it without a mirror.
- `-sS` and connect scans are caught. A slow scan spread over hours may stay under
  the thresholds in some ET rules.

## Rollback

Passive throughout: Suricata only sniffs, nothing touches routing or `vmbr0`, and
no active-response/auto-ban is configured, so this cannot lock anyone out.

    sudo systemctl disable --now suricata suricata-update.timer
    sudo apt purge -y suricata
    # remove the <localfile> block for eve.json, then:
    sudo systemctl restart wazuh-manager

`ossec.conf` and `suricata.yaml` are backed up next to the originals before any
edit (`.pre-suricata-*`, `.orig-*`).
