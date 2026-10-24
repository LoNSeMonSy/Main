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

```bash
git clone https://github.com/LoNSeMonSy/Main.git lonsemonsy && cd lonsemonsy
sudo ./setup/setup.sh
```

That's it. Setup installs anything missing (Docker, the firewall, the [Wazuh server](https://documentation.wazuh.com/current/quickstart.html)), fills in passwords, your network and time zone, connects everything to Grafana, and starts it all. The Wazuh install takes 15-20 minutes ([why](#why-the-wazuh-install-takes-15-20-minutes)).

It asks two optional questions first, then runs on its own:

1. **Keep this machine's address fixed?** Protected computers send their alerts to this address, so it must not change. Reserving it on your router is best; setup can also fix it on the machine itself.
2. **An email address for alarms** (needs a Gmail [app password](https://myaccount.google.com/apppasswords)). Press Enter to skip.

At the end it prints the Grafana and Wazuh addresses and passwords, a copy-paste command to protect each Windows or Linux computer, and the commands to check on everything. Lost the passwords? `sudo ./setup/show-passwords.sh` shows them again.

Settings live in `appliance/.env` if you ever want to change them. Already run a Wazuh server somewhere else? Use `sudo SKIP_WAZUH=1 ./setup/setup.sh`.

## What setup does, step by step

| Step | What it does |
|---|---|
| 1. Settings | Makes `appliance/.env` from the template. Only its owner can read it. |
| 2. Missing tools | Installs curl, openssl, the ufw firewall and Docker if they aren't there. |
| 3. Passwords | Generates every password and key, so nobody types or reuses one. |
| 4. Two questions | Keep this machine's address fixed? And an email address for alarms. Both optional. |
| 5. Your network | Works out the network from the machine itself, so nothing is hardcoded. |
| 6. Wazuh | Installs the Wazuh server with Wazuh's own installer and shows which part it's on. |
| 7. Firewall | Turns on ufw: SSH, then only the ports the dashboards and agents use, only from your network. |
| 8. Start | Starts InfluxDB, Grafana and NetAlertX in Docker. |
| 9. Connect | Lets Grafana read Wazuh alerts, turns on auto-block, Docker monitoring and 90-day alert retention. |
| 10. Updates | Checks GitHub once a day so Grafana can show an update banner. |

## Why the Wazuh install takes 15-20 minutes

Wazuh isn't one program. Its installer sets up three large ones and connects them securely:

| Part | What it is | Size installed | Time (8 GB machine) |
|---|---|---|---|
| Checks and certificates | checks the hardware, adds Wazuh's package source, makes the TLS certificates the parts use to talk to each other | | 2 min |
| Indexer | stores and searches the alerts (built on OpenSearch, includes its own Java) | 1.05 GB | 2.5 min |
| Manager | the detection engine: receives logs from agents and applies the rules, including the vulnerability database | 1.1 GB | 6.5 min |
| Filebeat | carries the manager's alerts into the indexer | 70 MB | 0.5 min |
| Dashboard | Wazuh's own web interface (built on OpenSearch Dashboards) | 1.0 GB | 5.5 min |
| Passwords | replaces the default passwords with random ones | | 2 min |

That's about **3.2 GB** to download, unpack and start, and the Java-based indexer has to start and set up its security before the rest can connect. Machines with less than 8 GB of memory take longer. Setup shows which of the five parts it's on and how long it has been running.

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
