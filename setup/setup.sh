#!/usr/bin/env bash
# LoNSeMonSy setup. Run it once on a fresh Ubuntu machine:  sudo ./setup/setup.sh
# Each step is a short script in setup/steps/, run in this order.
#
# Options (put them before ./setup/setup.sh):
#   SKIP_QUESTIONS=1   don't ask anything        SKIP_WAZUH=1      use a Wazuh server you already have
#   STATIC_IP=1        make the IP address static SKIP_SURICATA=1   no port-scan detection
#   SKIP_FIREWALL=1    leave the firewall alone
#   Cloud copy of the backups: answer the Backups question, or fill in BACKUP_REPO, BACKUP_KEY_ID, BACKUP_SECRET in appliance/.env
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail               # stop at the first error
cd "$(dirname "$0")/.." || exit 1   # work from the main folder

cat setup/banner.txt
# Which branch this copy came from. Customers (main) see no label.
branch=$(git -c safe.directory="$PWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
case "$branch" in
  staging) environment=Staging ;;
  dev)     environment=Development ;;
  *)       environment="" ;;
esac
echo "  ${environment:+$environment · }setup, version $(cat setup/VERSION 2>/dev/null || echo unknown)"
if [ "$(id -u)" != 0 ]; then echo "  Run it with sudo:  sudo ./setup/setup.sh"; exit 1; fi
setup_start=$SECONDS
echo
echo "  Setup takes about 20-30 minutes on a new machine (Wazuh is most of it)."
echo "  First a few questions (about 2 minutes), then it runs by itself."
echo "  Not sure what to answer? Type ? and press Enter at any question."

source setup/steps/helpers.sh     # small functions the steps use
only_one setup "Setup is already running in another window. Wait for it to finish."
step 1 "Getting ready";        source setup/steps/1-basics.sh    # settings file, curl and the firewall tool
step 2 "Questions";            source setup/steps/2-questions.sh # fixed IP, business name, alarm emails, cloud backup, remote access, AI
step 3 "Docker";               source setup/steps/3-docker.sh    # runs Grafana, InfluxDB and NetAlertX
step 4 "Settings";             source setup/steps/4-settings.sh  # passwords, time zone, network to scan
step 5 "Wazuh";                source setup/steps/5-wazuh.sh     # the detection engine
step 6 "Firewall";             source setup/steps/6-firewall.sh  # block everything except what's needed
step 7 "Starting everything";  source setup/steps/7-start.sh     # and connect Grafana to Wazuh
step 8 "Protection";           source setup/steps/8-protect.sh   # auto-block, Docker and port-scan detection
step 9 "Backups";              source setup/steps/9-backup.sh    # nightly, on this server and in the cloud if a bucket was given
step 10 "Finishing";           source setup/steps/10-finish.sh   # update check, the lsmsy command, AI, remote access, summary
