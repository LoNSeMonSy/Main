# Systems

Everything LoNSeMonSy is built from, and what each one is for.

## Security

| System | What it's for |
|---|---|
| [Wazuh](https://documentation.wazuh.com/current/index.html) | Detection engine. Collects logs from monitored machines, raises alerts, and blocks attackers. |
| [Wazuh agent](https://documentation.wazuh.com/current/installation-guide/wazuh-agent/index.html) | Runs on each server or PC and sends its security logs to the appliance. |
| [Suricata](https://docs.suricata.io/) | Watches network traffic to the appliance and flags port scans. |
| [ufw](https://documentation.ubuntu.com/server/how-to/security/firewalls/) | Ubuntu's firewall. Only lets in the ports LoNSeMonSy needs. |

## Network

| System | What it's for |
|---|---|
| [NetAlertX](https://docs.netalertx.com/) | Scans the network, lists every device, and flags new ones. |

## Database

| System | What it's for |
|---|---|
| [Wazuh indexer](https://documentation.wazuh.com/current/getting-started/components/wazuh-indexer.html) | Stores and searches security alerts (based on OpenSearch). |
| [InfluxDB](https://docs.influxdata.com/influxdb/v2/) | Stores measurements over time. |
| [SQLite](https://www.sqlite.org/docs.html) | NetAlertX's built-in device list. |

## Dashboard and alerts

| System | What it's for |
|---|---|
| [Grafana](https://grafana.com/docs/grafana/latest/) | The dashboard. Shows alerts, devices and alarms in one place, and sends alert emails. |
| [SMTP](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#smtp) | How Grafana sends alert emails, through a mail server such as Gmail (port 587, STARTTLS). |

## Platform

| System | What it's for |
|---|---|
| [Ubuntu Server](https://ubuntu.com/server/docs) | The operating system the appliance runs on. |
| [Docker Compose](https://docs.docker.com/compose/) | Runs Grafana, InfluxDB and NetAlertX as containers. |
| [GitHub](https://docs.github.com/) | Where the code lives, and how appliances install and update. |

## Our own infrastructure (not needed by customers)

| System | What it's for |
|---|---|
| [Proxmox VE](https://pve.proxmox.com/pve-docs/) | Runs our appliance and test lab as virtual machines and containers. |
| [Proxmox Backup Server](https://pbs.proxmox.com/docs/) | Backs up our own servers. |
| [AWS S3](https://docs.aws.amazon.com/s3/) | Offsite copy of our backups. |
| [Tailscale](https://tailscale.com/kb/) | Remote access to our servers. |
| [Kali Linux](https://www.kali.org/docs/) | The attacker in our test lab (nmap, hydra). |
