#!/usr/bin/env bash
# Puts the newest cloud backup back:  lsmsy restore
# On a new machine: run setup first, then this. It asks for the bucket and the backup password.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source-path=SCRIPTDIR/..
source setup/steps/helpers.sh   # get, set_env, ask_bucket

# A new machine has no bucket in its settings yet: ask (the same answers as on the old machine).
if [ -z "$(get BACKUP_REPO)" ]; then
  ask_bucket
  if [ -z "$repo" ]; then echo "Nothing changed."; exit 0; fi
  read -r -s -p "  Backup password (lsmsy passwords shows it on the old machine): " password; echo
  set_env BACKUP_REPO "$repo"
  set_env BACKUP_KEY_ID "$key_id"
  set_env BACKUP_SECRET "$secret"
  set_env BACKUP_PASSWORD "$password"
fi

export RESTIC_REPOSITORY RESTIC_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY B2_ACCOUNT_ID B2_ACCOUNT_KEY
RESTIC_REPOSITORY=$(get BACKUP_REPO)
RESTIC_PASSWORD=$(get BACKUP_PASSWORD)
AWS_ACCESS_KEY_ID=$(get BACKUP_KEY_ID)
AWS_SECRET_ACCESS_KEY=$(get BACKUP_SECRET)
B2_ACCOUNT_ID=$AWS_ACCESS_KEY_ID          # the same key, under Backblaze's names
B2_ACCOUNT_KEY=$AWS_SECRET_ACCESS_KEY

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
cp "$(find "$tmp" -path '*/appliance/.env' -print -quit)" appliance/.env
for volume in grafana-data netalertx-data; do
  from=$(find "$tmp" -type d -path "*/lonsemonsy_$volume/_data" -print -quit)
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
echo "Restored. Give it a minute, then type lsmsy status"
