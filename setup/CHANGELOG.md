# Changelog

Newest first.

## 0.6.1 - 2026-11-19

- Clearer setup questions, with help: type ? at any question
- Setup says how long it takes, shows live progress, and waits for Ubuntu's own updates
- Setup and lsmsy greet you by your business name
- Backups are saved on the server every night; the cloud copy is optional
- lsmsy password sets a new Grafana or Wazuh admin password

## 0.6.0 - 2026-11-12

- New Grafana pages: Vulnerabilities, Audit and System Health
- New alarms: disk almost full, server low on memory
- lsmsy update now also applies new setup steps, rules and commands
- Setup adds a swap file on machines with under 8 GB of memory, and asks for a company or site name
- Port scan sources now show on the Security Overview page
- Links to Wazuh and NetAlertX moved to their own row on every page

## 0.5.5 - 2026-11-04

- Fix: port-scan detection stopped working after the weekly Suricata rule update. On an existing install, run setup again to get the fix.

## 0.5.0 - 2026-10-25

- First release
- One-command install on Ubuntu: Wazuh, Suricata, NetAlertX, Grafana and the firewall
- Auto-block for SSH brute force
- Email alarms and a daily update check
