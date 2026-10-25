#!/usr/bin/env bash
# Shows the LoNSeMonSy login passwords again:  sudo ./setup/show-passwords.sh
# Wazuh's is the one it was installed with. If you changed it since, use your new one.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" = "0" ] || { echo "Run with sudo:  sudo ./setup/show-passwords.sh"; exit 1; }
echo "Grafana:  user admin, password $(grep -E '^GRAFANA_ADMIN_PASSWORD=' appliance/.env | cut -d= -f2-)"
if [ -f /root/wazuh-install-files.tar ]; then
  pw=$(tar -O -xf /root/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt \
       | grep -A1 "indexer_username: 'admin'" | grep -oP "indexer_password: '\K[^']+")
  echo "Wazuh:    user admin, password ${pw}"
fi
backup=$(grep -E '^BACKUP_PASSWORD=' appliance/.env | cut -d= -f2-)
if grep -qE '^BACKUP_REPO=.' appliance/.env; then
  echo "Backup:   password $backup  (keep a copy somewhere else: backups can't be restored without it)"
fi
