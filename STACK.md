# Systems Used — LoNSeMonSy

## Virtualization & OS
- Proxmox VE
- Ubuntu Server (appliance VM)
- Debian 12 (LXC containers)

## Containers
- Docker
- Docker Compose
- LXC

## Databases / Data stores
- InfluxDB (OSS 2.7)
- OpenSearch (Wazuh indexer)

## Security & Detection
- Wazuh (manager, indexer, dashboard)
- Wazuh agents
- NetAlertX (network scanner / new-device detection)
- nmap / arp-scan (bundled in NetAlertX)

## Network
- Tailscale
- vmbr0 (Proxmox bridge)

## Visualization / Dashboard
- Grafana (OSS)
- grafana-opensearch-datasource (plugin)
- volkovlabs-form-panel (plugin)

## Backup
- Proxmox Backup Server (PBS)
- vzdump

## Application services (our own)
- backup-trigger (Flask / Gunicorn)
- audit-collector (Flask / Gunicorn)

## Languages & Tooling
- Python
- Flask
- Gunicorn

## Dev / Version Control
- Git
- GitHub

## Planned (not yet deployed)
- Ollama (local AI — plain-English alert explainer)

## Hosts & Addresses

| Host | Runs | Local IP | Tailscale IP |
|---|---|---|---|
| appliance (grafana-influxdb) | Grafana, InfluxDB, Wazuh, NetAlertX, backup-trigger, audit-collector | 192.168.12.112 | 100.75.238.78 |
| mainserver | Proxmox VE | 192.168.12.230 | 100.117.221.2 |
| PBS | Proxmox Backup Server | 192.168.12.131 | 100.109.112.31 |
| backupserver | Proxmox node | 192.168.12.130 | 100.123.236.113 |
| WIZARDTEST | test VM (stopped) | DHCP | 100.65.246.6 |
| srv-files01 | test LXC | 192.168.12.134 | — |
| ws-reception | test LXC | 192.168.12.173 | — |
| kali-redteam | test LXC | 192.168.12.102 | — |

## Service ports (on the appliance)

| Service | URL |
|---|---|
| Grafana | http://192.168.12.112:3000 · http://100.75.238.78:3000 |
| Wazuh dashboard | https://192.168.12.112 · https://100.75.238.78 |
| NetAlertX | http://192.168.12.112:20211 · http://100.75.238.78:20211 |
| InfluxDB | http://192.168.12.112:8086 |
| backup-trigger | http://192.168.12.112:5001 |
