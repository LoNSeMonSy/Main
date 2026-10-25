#!/usr/bin/env bash
# LoNSeMonSy setup. Run it once on a fresh Ubuntu machine:  sudo ./setup/setup.sh
# Each step is a short script in setup/steps/, run in this order.
#
# Options (put them before ./setup/setup.sh):
#   SKIP_QUESTIONS=1   don't ask anything        SKIP_WAZUH=1      use a Wazuh server you already have
#   STATIC_IP=1        make the IP address static SKIP_SURICATA=1   no port-scan detection
#   SKIP_FIREWALL=1    leave the firewall alone
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail               # stop at the first error
cd "$(dirname "$0")/.." || exit 1   # work from the main folder

cat setup/banner.txt
echo "  setup, version $(cat VERSION 2>/dev/null || echo unknown)"
echo
if [ "$(id -u)" != 0 ]; then echo "  Run it with sudo:  sudo ./setup/setup.sh"; exit 1; fi

source setup/steps/helpers.sh     # small functions the steps use
source setup/steps/1-basics.sh    # settings file, curl and the firewall tool
source setup/steps/2-questions.sh # static IP or DHCP, and email for alarms
source setup/steps/3-docker.sh    # Docker, which runs Grafana, InfluxDB and NetAlertX
source setup/steps/4-settings.sh  # passwords, time zone, network to scan
source setup/steps/5-wazuh.sh     # the detection engine
source setup/steps/6-firewall.sh  # block everything except what's needed
source setup/steps/7-start.sh     # start everything and connect Grafana to Wazuh
source setup/steps/8-protect.sh   # auto-block, Docker and port-scan detection
source setup/steps/9-finish.sh    # update check, the lonsemonsy command, summary
