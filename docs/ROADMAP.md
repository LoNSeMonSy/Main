# Roadmap

Customers install on plain Ubuntu with one script. Our own servers and backups (Proxmox, Proxmox Backup Server, AWS) are how the team runs its systems, not part of the product.

## Done

- Wazuh detection, with automatic blocking of SSH brute force
- Suricata port-scan detection, on by default
- NetAlertX device discovery, with a new-device alarm
- Grafana: Active Alarms, Security Overview, Updates page, email alarms, five severity levels
- Firewall on by default, open ports named in setup's output
- One-command install with two optional questions, and the `lonsemonsy` command
- Lint checks on every push
- Optional encrypted cloud backup (Restic), with restore and a backup alarm

## Next

- Optional company name in setup (shown in Grafana and alarm emails)
- Dedicated staging machine

## Later

- Local AI that explains alarms in plain English (optional add-on)
- Whole-network port-scan detection (needs a mirrored switch port)
