# Setup

LoNSeMonSy runs on one Ubuntu machine on your network: a mini PC, an old server, or a virtual machine.

## What you need

| | Minimum | Recommended |
|---|---|---|
| CPU | 4 cores | 4 or more cores |
| Memory | 8 GB | 16 GB |
| Disk | 50 GB SSD | 100 GB SSD |
| System | [Ubuntu Server](https://ubuntu.com/download/server) 22.04 or 24.04 | |
| Network | wired, on the same network as the computers it watches | a fixed IP (a DHCP reservation on your router) |

This covers up to 25 monitored computers and about 90 days of alerts. Wazuh uses most of the memory. See Wazuh's [sizing guide](https://documentation.wazuh.com/current/quickstart.html) for bigger networks. No graphics card is needed.

## Install

1. **Get LoNSeMonSy and check the settings:**
   ```bash
   git clone https://github.com/LoNSeMonSy/Main.git lonsemonsy && cd lonsemonsy
   cp appliance/.env.example appliance/.env
   nano appliance/.env
   ```
   The defaults work. Passwords and your network are filled in for you. Only fill in **Email alerts** if you want alerts by email.
2. **Run setup:**
   ```bash
   sudo ./setup/setup.sh
   ```
   It installs anything missing (Docker, the firewall, basic tools), installs the [Wazuh server](https://documentation.wazuh.com/current/quickstart.html) and connects it to Grafana, turns on the firewall and auto-blocking, and starts everything. The Wazuh install takes 10-15 minutes. Then open `http://<this-machine>:3000`.

   Already run a Wazuh server somewhere else? Use `sudo SKIP_WAZUH=1 ./setup/setup.sh` and put its read-only login in `appliance/.env`.

## Optional parts

| Part | Default | What it needs |
|---|---|---|
| Wazuh agent on your computers | recommended | install on each computer to protect it, about 35 MB of memory each ([wazuh/README.md](../wazuh/README.md)) |
| Email alerts | off | a mail account that allows SMTP, for example a Gmail app password |
| Port-scan detection (Suricata) | off | about 100 MB of memory: `sudo appliance/suricata/install-suricata.sh` |
| Wazuh dashboard | on | the advanced view for IT people. Grafana is the main dashboard. |
| Firewall (ufw) | on | skip with `SKIP_FIREWALL=1 sudo ./setup/setup.sh` |
| Network switch | none | any switch works |

## Updating

```bash
./setup/update.sh
```
