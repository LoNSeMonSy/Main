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

---

## Update (September 2026): SIEM pivot + cleanup

We evaluated open-source SIEMs (Wazuh / Security Onion / CrowdSec) against our
constraints and **adopted Wazuh** as the detection engine rather than writing the
detection layer ourselves — see DECISIONS.md for the full reasoning. This reshapes
the phases below.

**Done**
- Wazuh server (manager + indexer + dashboard) running on the appliance; SSH
  brute-force detection works out of the box (agent 000, ~1k real alerts).
- Grafana ↔ Wazuh wired as code: `grafana-opensearch-datasource` provisioned so
  Grafana reads Wazuh alerts (config in `grafana/provisioning/datasources/opensearch.yml`).
- Retired the custom hub: `alerts-feed` (port 5002) and the fake `alert-generator`
  removed. No more custom pages — Grafana is the interface.
- Versions pinned (`VERSIONS`); Grafana image pinned off `:latest`.
- Repo made customer-facing: root `README.md`, `LICENSE.md` (AGPL-3.0), draft
  `install.sh` wizard, `appliance/.env.example`.

**Tiered interface (decided)**
- **Grafana** = the default UI: a simple overview for the business owner.
- **Wazuh dashboard** = optional advanced view for an MSP / IT contractor.
- Both read the same Wazuh indexer. If RAM gets tight, disable the Wazuh *dashboard*,
  never the *indexer* (Grafana needs it).

**Still open**
- Detection scenarios 2 (new/unknown device) and 3 (port scan): scenario 3 is blocked
  on network visibility (mirror port — Tim), scenario 2 has no config-only Wazuh answer.
- Tune `wazuh/local_rules.xml` (team's detection work) and prove it via `wazuh/TESTING.md`.
- Retention: apply `wazuh/ism-policy.json` (indexer) + InfluxDB retention (DB owner).
- Wizard: integrate the Wazuh *server* install into `install.sh`; multi-node discovery.
