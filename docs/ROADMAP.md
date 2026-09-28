# Roadmap

## Scope

- Customers install on **plain Ubuntu** from this repo with one script. No special hardware and no hypervisor required.
- The machine's own firewall (**ufw**) is turned on during setup.
- Our own servers and backups (Proxmox, Proxmox Backup Server, AWS) are how the team runs its systems. They are not part of the product.

## Done

- Wazuh detection with SSH brute-force alerts and automatic IP blocking
- Suricata port-scan detection (scans aimed at the appliance)
- NetAlertX device discovery, with an alarm when new devices join the network
- Grafana: Security Overview, Active Alarms home page, email alerts, five severity levels
- Test lab for staging: server, workstation and attacker

## Next

- Firewall locked down by default on every install
- Dedicated staging machine
- Add more machines to monitor with one command ([wazuh/README.md](../wazuh/README.md))

## Later

- Cloud backup for customers (S3 or Backblaze), with an optional local backup server
- Whole-network port-scan detection (needs a mirrored switch port)
- Ready-to-import VM image
