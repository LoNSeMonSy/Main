# LoNSeMonSy: Progress (Summer Rebuild)

Technical progress log for the summer solo rebuild phase (Tim). For the why behind
these choices, see DECISIONS.md. For what's next, see ROADMAP.md.

## Architecture as built so far

The appliance is a single VM (cloned from a clean Ubuntu Server template, Docker +
Docker Compose preinstalled) running the LoNSeMonSy stack via Docker Compose:

- **InfluxDB OSS 2.7** + **Grafana OSS**, defined in `~/lonsemonsy/docker-compose.yml`.
- All site-specific values (admin users/passwords, InfluxDB org/bucket/token) live in
  `~/lonsemonsy/.env` — gitignored, mode 600, the only copy of credentials. Nothing
  hardcoded in the compose file itself.
- Grafana's InfluxDB data source is provisioned as code
  (`~/lonsemonsy/grafana/provisioning/datasources/influxdb.yml`), pulling its token
  from the `INFLUXDB_TOKEN` env var (itself sourced from `.env` via compose
  interpolation) — no manual UI setup required to stand the stack back up.
- Grafana talks to InfluxDB over the Docker service name `http://influxdb:8086`
  internally.
- Both containers run with `restart: unless-stopped`; Docker itself is
  systemd-enabled. Verified the full stack autostarts after a Docker daemon restart
  (stand-in for a VM reboot) with no manual intervention.

## Setup steps completed

1. Stood up InfluxDB + Grafana via Docker Compose; fixed two bugs found along the way
   (InfluxDB bucket name can't start with `_`, so `_monitoring` → `monitoring`; org
   name typo `LoNeSyMonSy` → `LoNSeMonSy`).
2. Moved all credentials out of the compose file into `.env`, generated fresh random
   secrets (no more `changeme123` placeholders).
3. Provisioned the Grafana → InfluxDB data source as config, confirmed the connection
   via Grafana's own health-check API (`datasource is working. 3 buckets found`).
4. Verified end-to-end data flow with temporary sample points (written via
   `influx write`, queried back through Grafana's own `/api/ds/query`) before trusting
   the pipeline with real data. Sample points were deleted once confirmed.
5. Rewrote `/opt/pbs_backup_task.py` (the existing backup-task push script, which
   lives and runs **on PBS**, 192.168.12.131 — it reads the PBS task archive from a
   local file path, so it can't move to the appliance VM without rewriting that
   parsing logic, which was out of scope). Only its InfluxDB destination changed:
   InfluxDB Cloud → this appliance VM (`http://192.168.12.112:8086`, org
   `LoNSeMonSy`, bucket `monitoring`). PBS auth, PVE lookups, and all task-parsing
   logic were left untouched. Pre-change backups of the script and its config were
   made on PBS before deploying.
6. Ran the rewritten script for real: 301 real PBS task points (backup, sync, prune,
   garbage collection, verify) written successfully to the `monitoring` bucket.
7. Built the first manual test panel in the Grafana UI (Time series, Flux query
   filtering `pbs_backup_main` / `duration_min` / `worker_type == "backup"`) —
   confirmed real per-VM backup durations rendering. Data currently spans roughly
   late April 2026 through present.

## Current status

Demo-parity groundwork is in place: self-hosted database and dashboarding tool
running, real backup-task data flowing into it, one confirmed-working panel proving
the whole pipeline end to end (PBS → local archive parse → appliance InfluxDB →
Grafana).

## Not done yet

- Dashboard only has a single test panel so far — needs expansion to cover the other
  task types (sync, prune, garbage collection, verify), failure/error views, and a
  proper per-VM breakdown.
- Audit step not started: need to confirm every site-specific value (credentials,
  org, bucket, IPs) lives only in `.env`, with nothing hardcoded elsewhere, before
  this counts as portable to another Proxmox host.
- No first-boot config wizard yet, no install script, no detection layer — those are
  fall-semester, team scope (see ROADMAP.md).
