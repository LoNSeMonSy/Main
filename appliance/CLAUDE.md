# LoNSeMonSy — Appliance VM

> **SAFETY RULE — READ FIRST**
> NEVER modify, delete, or reconfigure `vmbr0` or any Proxmox network bridge, and never run commands that could disrupt networking on the **Proxmox host** itself. This guest VM's own networking (netplan, Docker bridges, etc.) is fine to touch freely.
> Nothing that touches the Proxmox host's bridge config, host firewall rules, or anything that could cut off GUI/SSH access to `mainserver`, `backupserver`, `PBS`, or any other VM.
> If a task seems to require touching host-level networking, **STOP and ask Tim first.**

## Project

LoNSeMonSy — a local network security monitoring system. School project, CPSC 354, team of 3 (Tim, Avery, Logan). Currently in a **summer solo rebuild phase** (Tim only) before the team reconvenes in fall to build the detection layer.

## Architecture

This VM is the **appliance clone** — a fresh Ubuntu Server template with Docker + Docker Compose + Claude Code preinstalled. It runs the self-hosted LoNSeMonSy stack via Docker Compose:

- Path: `~/Main/appliance/` (i.e. `/home/lonsemonsy/Main/appliance/`) — part of the `Main` git repo (folded in from the old untracked `~/lonsemonsy/` in July 2026 so it has proper version history)
- `docker-compose.yml` — InfluxDB OSS 2.7 + Grafana OSS
- `.env` — **gitignored, mode 600, the only copy of credentials** (admin users/passwords, InfluxDB org/bucket/token). Never hardcode these elsewhere.
- `grafana/provisioning/datasources/influxdb.yml` — provisions the InfluxDB data source automatically on container start; pulls the token from the `INFLUXDB_TOKEN` env var (`$__env{INFLUXDB_TOKEN}`), itself sourced from `.env` via compose interpolation. No manual UI setup needed.
- Grafana → InfluxDB over the **Docker service name** `http://influxdb:8086`, never an IP or `localhost`.
- Both containers use `restart: unless-stopped`; Docker daemon is systemd-`enabled`, so the whole stack autostarts on VM boot (verified by restarting the Docker daemon and confirming both containers came back).

This is a **separate, from-scratch rebuild** of the original prototype. The original is still running **untouched** on other VMs, kept as a fallback during this rebuild — do not touch it:
- `mainserver` — 192.168.12.230
- `backupserver` — 192.168.12.130
- `PBS` — 192.168.12.131

### Backup-task push script — runs ON PBS, not on this VM

`/opt/pbs_backup_task.py` (on PBS, 192.168.12.131) reads the Proxmox Backup Server task archive from a **local file path** (`/var/log/proxmox-backup/tasks/archive`) and calls the local PVE nodes' APIs for VM names. Because it depends on local filesystem access, **it cannot move to this appliance VM** without rewriting its task-reading logic — so it stays on PBS, scheduled via PBS's own root crontab (`55 20 * * * python3 /opt/pbs_backup_task.py automatic >> /var/log/pbs_influx.log 2>&1`), unchanged.

Only its InfluxDB write destination was repointed, from InfluxDB Cloud to this appliance VM over the LAN:
- `INFLUX_URL` → `http://192.168.12.112:8086` (this VM's LAN IP — **not** `localhost`, **not** the `influxdb` Docker service name, since PBS is a different host reaching in over the network)
- `INFLUX_ORG` → `LoNSeMonSy`, `INFLUX_BUCKET` → `monitoring`
- `INFLUX_TOKEN` (in `/opt/pbs_config.env` on PBS) → swapped to this appliance's token
- `PBS_PASSWORD`/`PVE_PASSWORD` and all task-parsing logic: **untouched**

Pre-change backups exist on PBS itself: `/opt/pbs_backup_task.py.bak.<timestamp>` and `/opt/pbs_config.env.bak.<timestamp>`, for rollback if ever needed.

SSH access from this VM to PBS is password-based (no key exchanged yet) — root password is known to Tim, not stored in any file on this VM.

To manually trigger a backup-task push (outside the daily cron run), SSH into PBS and run `pbs-backup-run` — a wrapper script at `/usr/local/bin/pbs-backup-run` on PBS that runs `python3 /opt/pbs_backup_task.py manual-test` (or pass a different label as `$1`, e.g. `pbs-backup-run automatic`).

### Storage-stats push script — also runs on PBS

`/opt/pbs_storage_stats.py` (new, added for the storage gauge panels) authenticates to the **PBS API** (`https://192.168.12.131:8007`, ticket auth, `root@pam`) and reads `/api2/json/admin/datastore/BackupStorage/status` for `total`/`used`/`avail` bytes, writing them as GB (plus computed `usage_pct`) to a new InfluxDB measurement `pbs_storage_stats` in the same `monitoring` bucket. Scheduled via PBS's root crontab every 15 minutes: `*/15 * * * * python3 /opt/pbs_storage_stats.py >> /var/log/pbs_storage_stats.log 2>&1`. Datastore name `BackupStorage` is hardcoded (only one datastore currently exists on PBS) — an audit-step candidate if this ever needs to move to `.env`.

## Grafana dashboard

Built via Grafana's HTTP API (not manual UI or provisioning YAML) so it's editable in the UI going forward — dashboard **"LoNSeMonSy - Backups"**, uid `e01512b5-eef3-48f4-9c5e-f5f512b6bb7f`, at `http://<VM-IP>:3000/d/e01512b5-eef3-48f4-9c5e-f5f512b6bb7f/lonsemonsy-backups` (also reachable over Tailscale at `http://100.75.238.78:3000/...`, tailnet name `grafana-influxdb`). Panels:
- **Total / Used / Available (GB)** and **Usage (%)** gauges — query `pbs_storage_stats`, last value in the past hour. GB gauges use a static max of 500 (current disk is ~372 GB total) — revisit if storage capacity changes. Usage % has green/yellow/red thresholds at 70/90.
- **Successful Backups (Last 30d)** / **Failed Backups (Last 30d)** stat panels — count `pbs_backup_main` points where `worker_type == "backup"` and `status == "ok"`/`"error"` respectively, `noValue: "0"` set so an empty Flux `count()` result reads as "0" instead of "No data".
- **Backup Tasks** table — Time (MM-DD-YYYY, 12-hour), VM ID, VM Name, Status, Manual/Automatic (`source` field), Duration (min). 90-day default range, 5-min auto-refresh.

## Template TODO

Whenever you find something hardcoded that's personal/site-specific and would need to be customer-configurable (IPs, node names, credentials, org/bucket names, anything like that), add an entry to `~/Main/docs/TEMPLATE_TODO.md` instead of just fixing it silently or mentioning it in passing. This is the running list for the fall wizard-design phase (Phase 3, see ROADMAP.md).

## Goal sequence

1. **Demo-parity** (in progress): self-hosted InfluxDB/Grafana working, backup-task script rewritten to push here instead of InfluxDB Cloud, dashboard rebuilt.
2. **Audit**: once (1) works, confirm ALL site-specific values (credentials, org, bucket, IPs) live only in `.env` — nothing hardcoded anywhere.
3. **Fall semester**: team builds a first-boot config wizard that prompts for those same `.env` fields.
4. **Only then**: build a clean, shippable template/install script with no personal credentials baked in.

## Current status

- InfluxDB OSS (2.7) and Grafana OSS running via `docker-compose.yml`, both healthy, autostart on boot confirmed.
- InfluxDB org `LoNSeMonSy`, bucket `monitoring`, credentials generated randomly into `.env`.
- Grafana InfluxDB data source provisioned as code, connection tested via Grafana's own `/api/datasources/uid/.../health` — confirmed working.
- `pbs_backup_task.py` on PBS rewritten to push here (see Architecture above) — real run confirmed 301 real PBS task points written to the `monitoring` bucket, queryable through Grafana's own `/api/ds/query`. Temporary sample test points from earlier verification have been deleted; the only data in the bucket now is real PBS task history.
- First manual test panel built in the Grafana UI (Time series, Flux query filtering `pbs_backup_main`/`duration_min`/`worker_type=="backup"`) — confirmed real backup durations rendering per VM. Data spans roughly late April 2026–present, so dashboards need a time range of at least ~90 days to show history.
- **Next up**: expand beyond the single test panel into a full dashboard (other task types — sync/prune/GC/verify, failure/error views, per-VM breakdowns), then move to goal-sequence step 2 (audit that nothing is hardcoded outside `.env`).
