<div align="center">

# LoNSeMonSy

**Local Network Security Monitoring System**

Security monitoring for small networks, on one Ubuntu machine you already own.

![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?logo=ubuntu&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Wazuh](https://img.shields.io/badge/Wazuh-4.14-3595F7)
![Grafana](https://img.shields.io/badge/Grafana-13-F46800?logo=grafana&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-2F855A)

</div>

---

## Features

- **Firewall on by default:** only the ports LoNSeMonSy needs are open, and only to your network
- **Attack detection** on every computer with a Wazuh agent (Windows, Linux, macOS): suspicious logins, attacks, changed system files, software with known vulnerabilities, crashes
- **Auto-block:** an address that keeps failing to log in over SSH is blocked for 10 minutes (your router and this machine never are)
- **New device alarm:** NetAlertX spots unknown devices joining the network
- **Port scan alarm:** Suricata flags scans of this machine (optional)
- **One dashboard:** Grafana's Active Alarms page, with five severity levels from Info to Critical
- **Email alarms** (optional, see below)
- **Update banner:** Grafana tells you when a new version is out

LoNSeMonSy is the *detection* layer: it finds problems and tells you within minutes. It doesn't replace your router's firewall, antivirus, strong passwords or updates.

### Email alarms

Setup asks where to send alarms, and which Gmail account sends them.

- **Send from a separate Gmail account made just for this** (for example `yourcompany.alarms@gmail.com`), not your own. Its password is stored on this machine. Alarms can still go to any address you read.
- That account needs an **app password**: a separate 16-character password Google makes for one program. It is *not* the account's normal password and can't be used to log in to Google. Make one at [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords) (the page only shows once 2-Step Verification is on), and delete it there any time to cut access.

## How it fits on your network

![How it fits in your network](./docs/customer_site_architecture.png)

More detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Requirements

| | Minimum | Recommended |
|---|---|---|
| CPU | 4 cores | 4 or more cores |
| Memory | 8 GB | 16 GB |
| Disk | 50 GB SSD | 100 GB SSD |
| System | Ubuntu Server 22.04 or 24.04 (setup installs Docker for you) | |

Sized for up to 25 monitored computers. No graphics card needed. Optional parts (email alerts, port-scan detection, agents) are listed in [setup/README.md](setup/README.md#optional-parts).

## Quick start

```bash
git clone https://github.com/LoNSeMonSy/Main.git lonsemonsy && cd lonsemonsy
sudo ./setup/setup.sh
```

Setup installs Docker and the [Wazuh server](https://documentation.wazuh.com/current/quickstart.html) for you (15-20 minutes), asks two optional questions (keep this machine's address fixed, and an email for alarms), and prints the Grafana address and password at the end. Full steps: [setup/README.md](setup/README.md)

## What's inside

| Component | Job | Docs |
|---|---|---|
| **Wazuh** | detection engine and agents | [documentation.wazuh.com](https://documentation.wazuh.com/current/index.html) |
| **Suricata** | spots port scans | [docs.suricata.io](https://docs.suricata.io/) |
| **NetAlertX** | finds devices on the network | [docs.netalertx.com](https://docs.netalertx.com/) |
| **Grafana** | dashboards and email alerts | [grafana.com/docs](https://grafana.com/docs/grafana/latest/) |
| **SMTP** | delivers Grafana's alert emails (e.g. Gmail) | [Grafana SMTP settings](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#smtp) |
| **InfluxDB** | stores metrics over time | [docs.influxdata.com](https://docs.influxdata.com/influxdb/v2/) |
| **ufw** | the machine's firewall | [Ubuntu ufw guide](https://documentation.ubuntu.com/server/how-to/security/firewalls/) |

Pinned versions live in [`VERSIONS`](VERSIONS).

## Repository layout

```
appliance/     docker-compose.yml, .env.example, Grafana dashboards + alerting, Suricata config
setup/         setup.sh (install) and update.sh
wazuh/         detection rules, auto-block config, adding a machine to monitor
testlab/       our test lab: a fake company network used in staging
systems/       every system we use and what it's for
docs/          architecture, environments, class diagram, roadmap, backups
```

## Branches

`dev` → `staging` → `main`. New work lands on **dev**, is tested on **staging** against the test lab, and is released on **main**. See [docs/ENVIRONMENTS.md](docs/ENVIRONMENTS.md).

## Team

Tim Smith · Avery Schmoyer · Logan Herndon, CPSC 355 Software Engineering II

## License

[MIT](LICENSE)
