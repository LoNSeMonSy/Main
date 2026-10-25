#!/usr/bin/env bash
# Cloud backup with Restic (https://restic.net): encrypted copies of LoNSeMonSy's settings
# and data, kept in your bucket. Runs every night at 1 AM; by hand: lonsemonsy backup
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
get() { grep -E "^$1=" appliance/.env | cut -d= -f2- || true; }

export RESTIC_REPOSITORY RESTIC_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
RESTIC_REPOSITORY=$(get BACKUP_REPO)
RESTIC_PASSWORD=$(get BACKUP_PASSWORD)
AWS_ACCESS_KEY_ID=$(get BACKUP_KEY_ID)
AWS_SECRET_ACCESS_KEY=$(get BACKUP_SECRET)
if [ -z "$RESTIC_REPOSITORY" ]; then
  echo "No cloud backup set up. Fill in BACKUP_REPO, BACKUP_KEY_ID and BACKUP_SECRET in appliance/.env."
  exit 1
fi

# The first time, create the backup store in the bucket.
if ! restic cat config >/dev/null 2>&1; then restic init; fi

# InfluxDB makes its own clean copy first (copying its files while it runs isn't safe).
rm -rf /var/backups/lonsemonsy
mkdir -p /var/backups/lonsemonsy
docker exec influxdb rm -rf /tmp/influx-backup
docker exec influxdb influx backup /tmp/influx-backup -t "$(get INFLUXDB_ADMIN_TOKEN)" >/dev/null
docker cp influxdb:/tmp/influx-backup /var/backups/lonsemonsy/influxdb

# What's backed up: the settings file, InfluxDB's copy, Grafana and NetAlertX's data, and
# Wazuh's settings (with the agents' keys, so protected computers keep reporting).
paths=(appliance/.env /var/backups/lonsemonsy)
for volume in grafana-data netalertx-data; do
  paths+=("$(docker volume inspect -f '{{.Mountpoint}}' "lonsemonsy_$volume")")
done
if [ -d /var/ossec/etc ]; then paths+=(/var/ossec/etc); fi
restic backup --quiet "${paths[@]}"

# Keep 7 daily, 4 weekly and 6 monthly copies; older ones are deleted.
restic forget --quiet --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6

# Tell Grafana it worked (the Updates page shows it; an alarm fires if it stops).
curl -sf -X POST "http://127.0.0.1:8086/api/v2/write" \
  --url-query "org=$(get INFLUXDB_ORG)" --url-query "bucket=$(get INFLUXDB_BUCKET)" --url-query precision=s \
  -H "Authorization: Token $(get INFLUXDB_ADMIN_TOKEN)" --data-binary "lonsemonsy_backup ok=1i" >/dev/null
echo "Cloud backup done. Copies kept: $(restic snapshots --json | grep -o '"short_id"' | wc -l)"
