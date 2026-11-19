#!/usr/bin/env bash
# Backups with Restic (https://restic.net): encrypted copies of LoNSeMonSy's settings and
# data, kept on this server and, if a bucket is set up, in the cloud. Runs every night at
# 1 AM; by hand: lsmsy backup. Add or change the cloud bucket: lsmsy backup setup
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source-path=SCRIPTDIR/..
source setup/steps/helpers.sh   # get, set_env, ask_bucket

if [ "${1:-}" = setup ]; then
  ask_bucket
  if [ -z "$repo" ]; then echo "Nothing changed."; exit 0; fi
  set_env BACKUP_REPO "$repo"
  set_env BACKUP_KEY_ID "$key_id"
  set_env BACKUP_SECRET "$secret"
  source setup/steps/9-backup.sh   # turns on the nightly backup
  exec setup/backup.sh             # and makes one now
fi

export RESTIC_REPOSITORY RESTIC_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY B2_ACCOUNT_ID B2_ACCOUNT_KEY
RESTIC_PASSWORD=$(get BACKUP_PASSWORD)
AWS_ACCESS_KEY_ID=$(get BACKUP_KEY_ID)
AWS_SECRET_ACCESS_KEY=$(get BACKUP_SECRET)
B2_ACCOUNT_ID=$AWS_ACCESS_KEY_ID          # the same key, under Backblaze's names
B2_ACCOUNT_KEY=$AWS_SECRET_ACCESS_KEY
local_store=$(get BACKUP_LOCAL)
local_store=${local_store:-/var/backups/lonsemonsy-copies}
cloud=$(get BACKUP_REPO)

# Emails the result, when email alarms are set up.
report() {
  if [ "$(get SMTP_ENABLED)" != true ]; then return 0; fi
  printf 'From: %s <%s>\nTo: %s\nSubject: %s\n\n%s\n' \
    "$(get SMTP_FROM_NAME)" "$(get SMTP_FROM_ADDRESS)" "$(get ALERT_EMAIL_TO)" "$1" "$2" |
    curl -s --max-time 30 --ssl-reqd --url "smtp://$(get SMTP_HOST)" --user "$(get SMTP_USER):$(get SMTP_PASSWORD)" \
      --mail-from "$(get SMTP_FROM_ADDRESS)" --mail-rcpt "$(get ALERT_EMAIL_TO)" --upload-file - || true
}
trap 'report "Backup FAILED" "The backup did not finish. To see why, run on the server: sudo lsmsy backup"' ERR

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

# save STORE: back up to one store (made the first time), keeping 7 daily, 4 weekly and
# 6 monthly copies; older ones are deleted.
save() {
  RESTIC_REPOSITORY=$1
  restic cat config >/dev/null 2>&1 || restic init >/dev/null || return 1
  restic backup --quiet "${paths[@]}" || return 1
  restic forget --quiet --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || return 1
  restic snapshots --json | grep -o '"short_id"' | wc -l
}
mkdir -p "$local_store"
chmod 700 "$local_store"
result="On this server: OK, $(save "$local_store") copies kept"
failed=0
if [ -n "$cloud" ]; then
  if copies=$(save "$cloud"); then result+=$'\n'"In the cloud: OK, $copies copies kept"
  else result+=$'\n'"In the cloud: FAILED. To see why, run on the server: sudo lsmsy backup"; failed=1; fi
fi
echo "$result"
if [ "$failed" = 1 ]; then
  report "Backup FAILED (cloud)" "$result"
  exit 1
fi

# Tell Grafana it worked (the Updates page shows it; an alarm fires if it stops).
curl -sf -X POST "http://127.0.0.1:8086/api/v2/write" \
  --url-query "org=$(get INFLUXDB_ORG)" --url-query "bucket=$(get INFLUXDB_BUCKET)" --url-query precision=s \
  -H "Authorization: Token $(get INFLUXDB_ADMIN_TOKEN)" --data-binary "lonsemonsy_backup ok=1i" >/dev/null
report "Backup OK" "Backup finished $(date '+%A %b %-d at %-I:%M %p').
Saved: settings, Grafana, InfluxDB, NetAlertX and Wazuh settings.
$result"
