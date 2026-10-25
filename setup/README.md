# Setup

```bash
git clone https://github.com/LoNSeMonSy/Main.git lonsemonsy && cd lonsemonsy
sudo ./setup/setup.sh
```

Requirements are in the [main README](../README.md#requirements).

## What setup does, step by step

[`setup.sh`](setup.sh) runs these short scripts in order:

| Step | Script | What it does |
|---|---|---|
| 1 | [`1-basics.sh`](steps/1-basics.sh) | makes the settings file (`appliance/.env`), installs curl and the firewall tool, finds this machine's network |
| 2 | [`2-questions.sh`](steps/2-questions.sh) | asks: static IP or DHCP? Which email gets the alarms? Which bucket for cloud backup? |
| 3 | [`3-docker.sh`](steps/3-docker.sh) | installs Docker |
| 4 | [`4-settings.sh`](steps/4-settings.sh) | makes random passwords, sets the time zone and the network to scan |
| 5 | [`5-wazuh.sh`](steps/5-wazuh.sh) | installs Wazuh with Wazuh's own installer |
| 6 | [`6-firewall.sh`](steps/6-firewall.sh) | blocks everything except SSH and the ports below |
| 7 | [`7-start.sh`](steps/7-start.sh) | starts Grafana, InfluxDB and NetAlertX, connects Grafana to Wazuh |
| 8 | [`8-protect.sh`](steps/8-protect.sh) | turns on auto-block, Docker monitoring and Suricata |
| 9 | [`9-backup.sh`](steps/9-backup.sh) | cloud backup, if you gave a bucket: nightly at 1 AM, plus the first one now |
| 10 | [`10-finish.sh`](steps/10-finish.sh) | daily update check, the `lonsemonsy` command, prints the addresses and passwords |

Small shared functions are in [`helpers.sh`](steps/helpers.sh).

## Open ports

| Port | For | Open to |
|---|---|---|
| 22 | SSH | anyone |
| 3000 | Grafana | your network |
| 443 | Wazuh dashboard | your network |
| 20211 | NetAlertX | your network |
| 1514, 1515 | Wazuh agents | your network |

## Options

Put them in front: `sudo SKIP_QUESTIONS=1 ./setup/setup.sh`

| Option | Does |
|---|---|
| `SKIP_QUESTIONS=1` | asks nothing (DHCP, no email) |
| `STATIC_IP=1` | makes the IP address static without asking |
| `SKIP_WAZUH=1` | for when you already have a Wazuh server |
| `SKIP_SURICATA=1` | no port-scan detection |
| `SKIP_FIREWALL=1` | leaves the firewall alone |

Settings live in `appliance/.env`.

## Cloud backup

Encrypted with [Restic](https://restic.net), kept in your bucket: the settings, Grafana, NetAlertX, InfluxDB and Wazuh's settings (with the agents' keys). 7 daily, 4 weekly and 6 monthly copies. Setup prints a backup password once: save it somewhere else, because a backup can't be restored without it (`lonsemonsy passwords` shows it again).

On a new machine: run setup, put the same `BACKUP_*` lines into `appliance/.env`, then `lonsemonsy restore`.


## Updating

```bash
lonsemonsy update
```
