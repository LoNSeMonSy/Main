#!/usr/bin/env bash
# Puts the newest cloud backup back:  lonsemonsy restore
# On a new machine: run setup first, then put the same BACKUP_REPO, BACKUP_KEY_ID,
# BACKUP_SECRET and BACKUP_PASSWORD into appliance/.env, then run this.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
get() { grep -E "^$1=" appliance/.env | cut -d= -f2- || true; }

export RESTIC_REPOSITORY RESTIC_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
RESTIC_REPOSITORY=$(get BACKUP_REPO)
RESTIC_PASSWORD=$(get BACKUP_PASSWORD)
AWS_ACCESS_KEY_ID=$(get BACKUP_KEY_ID)
AWS_SECRET_ACCESS_KEY=$(get BACKUP_SECRET)

restic snapshots --compact
read -r -p "Put the newest backup back? This replaces the current settings and data. [y/N] " ok
if [ "$ok" != y ] && [ "$ok" != Y ]; then echo "Nothing changed."; exit 0; fi

# This machine's own Wazuh login for Grafana and InfluxDB key: kept, not replaced.
reader=$(get WAZUH_INDEXER_PASSWORD)
token=$(get INFLUXDB_ADMIN_TOKEN)

echo "stopping LoNSeMonSy..."
(cd appliance && docker compose stop >/dev/null 2>&1)
systemctl stop wazuh-manager || true

echo "copying the backup back..."
tmp=/var/tmp/lonsemonsy-restore
rm -rf "$tmp"
restic restore latest --target "$tmp" >/dev/null
# Each piece goes to where THIS machine keeps it (the backup may come from another folder).
cp "$(find "$tmp" -path '*/appliance/.env' | head -1)" appliance/.env
for volume in grafana-data netalertx-data; do
  from=$(find "$tmp" -type d -path "*/lonsemonsy_$volume/_data" | head -1)
  to=$(docker volume inspect -f '{{.Mountpoint}}' "lonsemonsy_$volume")
  if [ -n "$from" ]; then cp -a "$from/." "$to/"; fi
done
if [ -d "$tmp/var/ossec/etc" ]; then cp -a "$tmp/var/ossec/etc/." /var/ossec/etc/; fi

# Put this machine's Wazuh login back into the restored settings file.
sed -i "/^WAZUH_INDEXER_PASSWORD=/d" appliance/.env
echo "WAZUH_INDEXER_PASSWORD=$reader" >> appliance/.env

echo "restoring InfluxDB..."
(cd appliance && docker compose start influxdb >/dev/null 2>&1)
sleep 15
docker exec influxdb rm -rf /tmp/influx-restore
docker cp "$tmp/var/backups/lonsemonsy/influxdb" influxdb:/tmp/influx-restore
docker exec influxdb influx restore /tmp/influx-restore --full -t "$token" >/dev/null 2>&1

echo "starting LoNSeMonSy..."
(cd appliance && docker compose up -d >/dev/null 2>&1)
systemctl start wazuh-manager || true
rm -rf "$tmp"
echo "Restored. Give it a minute, then type lonsemonsy status"
