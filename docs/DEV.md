# Development Environment

The dev environment is the **Docker Compose app stack** — what a developer runs to build and
iterate on the LoNSeMonSy services. It is intentionally lightweight (no full Wazuh server),
so it runs on a laptop or the appliance without a second 8 GB VM. Work here happens on the
**`dev`** branch.

## What runs here

`appliance/docker-compose.yml` brings up four services:

| Service | Port | Role |
|---|---|---|
| `influxdb` | 8086 | time-series store (backups, audit) |
| `grafana` | 3000 | dashboards + the Wazuh datasource |
| `backup-trigger` | 5001 | starts Proxmox backups, reports progress |
| `audit-collector` | — | pulls Proxmox/Tailscale audit logs into InfluxDB |

## Prerequisites

- Docker + Docker Compose v2
- `openssl` (to generate secrets)

## Setup

```bash
cd appliance
cp .env.example .env          # then fill in the site values; secrets are generated
docker compose up -d
docker compose ps             # all services healthy
```

Grafana: http://localhost:3000 (admin password is in `.env`).

## Iterating on a service

Each Python service (`trigger/`, `audit/`) has its own Dockerfile. After changing code:

```bash
docker compose up -d --build backup-trigger    # rebuild just the one you changed
docker compose logs -f backup-trigger          # watch its logs
```

Config is read from `.env` only — never hardcode site values (see `docs/TEMPLATE_TODO.md`).

## Detection while developing

Full Wazuh detection is validated in **staging** (see `STAGING.md`), not here — the dev stack
is for the app services and dashboards. Grafana's Wazuh datasource reads a real indexer only
where one is running (the appliance).

## Branch

Feature work is committed to **`dev`**, then promoted to `staging` for validation.
