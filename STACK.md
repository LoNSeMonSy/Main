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
