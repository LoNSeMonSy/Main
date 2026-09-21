# Network Scanner (NetAlertX)

Off-the-shelf network device discovery + new-device alerts. Satisfies SRS 3.2 "Scan the
Network" (populates the `Device` class) and roadmap scenario 2 (new/unknown device).

- **Tool:** NetAlertX (`ghcr.io/netalertx/netalertx`, pinned in `VERSIONS`), run as a Docker
  service in `appliance/docker-compose.yml`.
- **How it scans:** active ARP scan of the LAN. Runs `network_mode: host` because ARP is a
  layer-2 operation — this only shares the appliance's existing LAN access; it does **not**
  modify `vmbr0` or affect GUI/SSH reachability.
- **Access:** `http://192.168.12.112:20211` (also over Tailscale). GraphQL on 20212.
- **Scan target:** `SCAN_SUBNETS` (default `192.168.12.0/24 --interface=eth0`), set in `.env`.
- **New-device detection:** built-in NEWDEV plugin flags unknown devices; notification
  channels (email/webhook) are set in the UI if wanted.

Scope: this is *active* discovery (who is on the network). *Passive* port-scan detection is
separate and deferred — it needs a bridge traffic mirror (host networking, Tim's call). See
`docs/DECISIONS.md`.
