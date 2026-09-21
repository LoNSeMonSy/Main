# Setup

Set up LoNSeMonSy in three steps. It's config-first: you fill in a small file, then
run one command. For whoever installs it (owner, IT contractor, or MSP) — comfortable
with IPs and running a server, no security expertise needed.

**Before you start:** [Docker + Docker Compose](https://docs.docker.com/compose/install/).

---

## 1. Copy the config template

```bash
cp appliance/.env.example appliance/.env
```

## 2. Edit the config

```bash
nano appliance/.env
```

Fill in the values for your site. You only need a few:

| Setting | What it is | Fill now? |
|---|---|---|
| `SCAN_SUBNETS` | your network, e.g. `192.168.1.0/24 --interface=eth0` | ✅ yes |
| `PVE_HOST`, `PVE_NODE` | your Proxmox host IP and node name | for backups |
| `PVE_TOKEN_ID`, `PVE_TOKEN_SECRET` | a Proxmox API token — [how to create one](https://pve.proxmox.com/pve-docs/pve-admin-guide.html#pveum_tokens) | for backups |
| `BACKUP_STORAGE` | your PBS storage ID in Proxmox | for backups |
| everything with a blank secret | passwords/tokens | ❌ leave blank — generated for you |

Backups are optional — skip the `PVE_*` rows for now and add them later.

## 3. Run setup

```bash
./setup/setup.sh
```

It generates the blank secrets and starts the stack. When it finishes, open **Grafana**
at the address it prints (`http://<your-ip>:3000`) — that's the dashboard.

---

## Advanced (optional)

- **Detection server (Wazuh):** installed separately with Wazuh's own installer —
  [Wazuh installation guide](https://documentation.wazuh.com/current/installation-guide/).
- **Network scanner (NetAlertX):** runs automatically; its own UI is at
  `http://<your-ip>:20211` — [NetAlertX docs](https://docs.netalertx.com/).
- **Dashboards (Grafana):** [Grafana docs](https://grafana.com/docs/grafana/latest/).
