# Changelog

Newest first.

## 0.6.2 - 2026-11-23

- AI explanations of serious alarms (optional): on this server or another computer running Ollama
- NetAlertX asks for a password; passwords are shorter (12 characters); SSH only from the office network and Tailscale
- Remote access: sign in with a link or QR code instead of a key; Devices page shows which phones and laptops can connect, with an alarm for a new one
- Forgot the Grafana password: the reset link goes to the alarm email
- lsmsy users adds and removes accounts; lsmsy help is grouped
- New Backups page with Back up now buttons (admins only); setup asks the backup time and time zone
- Five wrong passwords on the Wazuh or NetAlertX login blocks that address for 10 minutes
- Alarm emails say what happened, where and from which address; fewer emails right after setup
- Once remote access is on, the dashboards only open over Tailscale (lsmsy remote ip on undoes it)
- The business name shows on every Grafana page; backup emails list what was saved
- High and Critical alarms have their own email: the subject says so, it starts with what to do, Critical repeats every hour
- Setup ends with a test alarm on the dashboard and by email
- lsmsy commands can't be run again right away (test, backup, update and others)

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
