# Systems

Everything LoNSeMonSy uses, and what for.

| System | What it's for |
|---|---|
| [Wazuh](https://documentation.wazuh.com/current/index.html) | detection engine: collects logs, raises alerts, blocks attackers |
| [Wazuh agent](https://documentation.wazuh.com/current/installation-guide/wazuh-agent/index.html) | runs on each computer and sends its security logs |
| [Wazuh indexer](https://documentation.wazuh.com/current/getting-started/components/wazuh-indexer.html) | stores and searches the alerts |
| [Suricata](https://docs.suricata.io/) | spots port scans |
| [NetAlertX](https://docs.netalertx.com/) | lists every device on the network and flags new ones |
| [Grafana](https://grafana.com/docs/grafana/latest/) | the dashboard; also sends alarm emails over SMTP |
| [InfluxDB](https://docs.influxdata.com/influxdb/v2/) | stores measurements over time |
| [ufw](https://documentation.ubuntu.com/server/how-to/security/firewalls/) | Ubuntu's firewall |
| [Docker Compose](https://docs.docker.com/compose/) | runs Grafana, InfluxDB and NetAlertX |
| [Ubuntu Server](https://ubuntu.com/server/docs) | the operating system |
| [GitHub](https://docs.github.com/) | where the code lives; installs and updates come from here |

Our own servers also use [Proxmox VE](https://pve.proxmox.com/pve-docs/), [Proxmox Backup Server](https://pbs.proxmox.com/docs/) with [AWS S3](https://docs.aws.amazon.com/s3/), [Tailscale](https://tailscale.com/kb/) and [Kali Linux](https://www.kali.org/docs/) for the test lab. Customers don't need them.
