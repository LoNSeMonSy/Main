# Changelog

Newest first. The appliance checks this once a day and shows the newest section on the
Grafana **Updates** page.

## 0.5.0 - 2026-09-29

- Setup installs everything: Docker, the firewall, and the Wazuh server, connected to Grafana
- SSH brute-force attackers are blocked automatically for 10 minutes
- Alarm when a new device joins the network
- Active Alarms home page with five plain severity levels
- Port-scan detection with Suricata
- Firewall on by default, internal services closed to the network
- Wazuh starts reliably after a reboot
- Wazuh watches the appliance's Docker containers (started, stopped, crashed)
- Click any alert, machine or device in Grafana to open it in Wazuh or NetAlertX, with tabs to every dashboard at the top
- Update banner: Grafana shows when a new LoNSeMonSy version is available
