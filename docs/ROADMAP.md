# LoNSeMonSy: Roadmap

## Phase 1: Summer rebuild (Tim, solo)
Goal: reach demo-parity (backups working, dashboard working, database working) on a 
portable, Dockerized appliance instead of hardcoded IPs and cloud services.
- Self-hosted InfluxDB + Grafana in Docker (done)
- pbs_backup_task.py pointed at local InfluxDB (in progress)
- Dashboard rebuilt in local Grafana (next)
- Audit: confirm all site-specific values live only in .env, nothing hardcoded

## Phase 2: Fall, detection layer (team)
- Log/event collection pipeline
- Detection rules for 3 attack scenarios: SSH brute-force, new/unknown device, port scan
- Alerting wired to detections

## Phase 3: Fall, packaging
- First-boot config wizard (prompts for the same fields currently in .env)
- Install script for deploying to a fresh customer Proxmox host
- Security defaults: no default passwords, locked-down services, firewall rules

## Phase 4: Fall, differentiators and pitch
- Fuse backup + detection into one demo flow (catch attack, then one-command recovery)
- Optional local AI alert explainer (Ollama)
- Business/positioning deck: LoNSeMonSy vs Security Onion vs SentinelOne
