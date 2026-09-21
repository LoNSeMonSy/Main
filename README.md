# LoNSeMonSy

**Local-first network security monitoring + backup, for small businesses without a
security team.** Runs as a single appliance on a customer's own Proxmox host. All
data stays on their hardware — no cloud, no vendor seeing their security events.

> Status: **alpha / rough draft.** Actively changing. Not yet a turnkey install.

## What it does

- **Detects** attacks with [Wazuh](https://wazuh.com) (SSH brute force today; more
  coming). Alerts render in Grafana alongside everything else.
- **Backs up** the customer's VMs via Proxmox Backup Server, and shows backup health,
  history, and live progress in Grafana.
- **Fuses the two** — catch an attack *and* recover from it, from one appliance. No
  other free or paid tool combines detection with backup.
- **Explains alerts in plain English** (planned, local via Ollama) for operators with
  no security training.

## Architecture

One VM/LXC on the customer's Proxmox host runs the stack in Docker Compose, beside a
native Wazuh install:

```
Proxmox host
└── LoNSeMonSy appliance (one guest)
    ├── Docker Compose
    │   ├── influxdb        time-series store (backups, audit)
    │   ├── grafana         the single front door (dashboards + Wazuh alerts)
    │   ├── backup-trigger  starts Proxmox backups on demand, reports progress
    │   └── audit-collector pulls Proxmox/Tailscale audit logs into InfluxDB
    └── Wazuh (native)      detection engine → alerts read by Grafana
```

Grafana is the only UI. It reads backup/audit data from InfluxDB and security alerts
straight from the Wazuh indexer (OpenSearch), so operators look in one place.

## Requirements

- A Proxmox VE host with a guest for the appliance (**≥ 8 GB RAM, 4 vCPU, ~80 GB disk**).
- Proxmox Backup Server reachable from the host.
- Docker + Docker Compose in the guest.

## Quick start (draft)

```bash
git clone git@github.com:LoNSeMonSy/Main.git
cd Main
./install.sh          # prompts for site values, generates secrets, brings the stack up
```

The installer writes `appliance/.env` (the only copy of your secrets — never committed).
See [`appliance/.env.example`](appliance/.env.example) for every setting.

## Repository layout

| Path | What |
|------|------|
| `install.sh` | First-run wizard (rough draft) |
| `VERSIONS` | Pinned versions of every component — reproducible installs |
| `appliance/docker-compose.yml` | The Dockerized services |
| `appliance/.env.example` | Every config key, no secrets |
| `appliance/grafana/provisioning/` | Datasources + dashboards as code |
| `wazuh/` | Custom detection rules, retention policy, testing guide |
| `testlab/` | Builds the staging "company" network (LXCs monitored by the appliance) |
| `docs/` | Design overview, decisions, roadmap, class diagram, environments |

## Design & environments

- **Class diagram** (conceptual, data-at-rest): [`docs/CLASS_DIAGRAM.md`](docs/CLASS_DIAGRAM.md)
- **Development environment**: [`docs/DEV.md`](docs/DEV.md)
- **Staging environment**: [`docs/STAGING.md`](docs/STAGING.md)

## Branches & environments

The branch structure maps to the deployment pipeline:

| Branch | Environment | What it is |
|--------|-------------|------------|
| `dev` | Development | the Docker Compose app stack developers iterate on (`docs/DEV.md`) |
| `staging` | Staging | the appliance + a company test network, where detection is validated (`docs/STAGING.md`) |
| `main` | Release | promoted after staging passes; a real customer appliance would be production |

Flow: feature work → `dev` → promote to `staging` for validation → merge to `main`.

## Versions

Pinned in [`VERSIONS`](VERSIONS). Two installs a month apart get the same stack.

## License

AGPL-3.0 — matches the copyleft of Wazuh and Grafana, which this builds on. See
[`LICENSE.md`](LICENSE.md).
