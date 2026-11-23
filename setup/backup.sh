#!/usr/bin/env bash
# Backups with Restic (https://restic.net): encrypted copies of LoNSeMonSy's settings and
# data, kept on this server and, if a bucket is set up, in the cloud. Runs every night
# (1 AM unless changed); by hand: lsmsy backup. Cloud bucket: lsmsy backup setup
# Change the time: lsmsy backup time 11pm
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source-path=SCRIPTDIR/..
source setup/steps/helpers.sh   # get, set_env, ask_bucket
only_one backup "A backup or restore is already running. Try again when it's done."

if [ "${1:-}" = time ]; then
  if ! when=$(to_24h "${2:-}"); then echo "  usage: lsmsy backup time 11pm   (or 1:30am, 23:30)"; exit 1; fi
  set_env BACKUP_TIME "$when"
  source setup/steps/9-backup.sh   # rewrites the nightly timer
  exit 0
fi

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
  if [ "$(get SMTP_ENABLED)" != true ] || [ "${NO_EMAIL:-0}" = 1 ]; then return 0; fi
  printf 'From: %s <%s>\nTo: %s\nSubject: =?UTF-8?B?%s?=\nContent-Type: text/plain; charset=UTF-8\n\n%s\n' \
    "$(get SMTP_FROM_NAME)" "$(get SMTP_FROM_ADDRESS)" "$(get ALERT_EMAIL_TO)" "$(printf '%s' "$1" | base64 -w0)" "$2" |
    curl -s --max-time 30 --ssl-reqd --url "smtp://$(get SMTP_HOST)" --user "$(get SMTP_USER):$(get SMTP_PASSWORD)" \
      --mail-from "$(get SMTP_FROM_ADDRESS)" --mail-rcpt "$(get ALERT_EMAIL_TO)" --upload-file - || true
}
# Who started it: the Backups page's button leaves the Grafana user's name here.
by=$(cat /run/lonsemonsy-backup-by 2>/dev/null || true); rm -f /run/lonsemonsy-backup-by
if [ -z "$by" ]; then if [ -t 0 ]; then by="${SUDO_USER:-root} (lsmsy)"; else by=schedule; fi; fi
# Just one of the two: "lsmsy backup local" / "lsmsy backup cloud", or the page's buttons.
only=$(cat /run/lonsemonsy-backup-only 2>/dev/null || true); rm -f /run/lonsemonsy-backup-only
case "${1:-}" in local|cloud) only=$1 ;; esac
if [ "$only" = cloud ] && [ -z "$cloud" ]; then
  echo "  Cloud backup isn't set up. To add it: sudo lsmsy backup setup"; exit 1
fi

# record STORE OK: one line per backup for the Backups page (and the "Backup is out of date" alarm).
record() {
  curl -sf -X POST "http://127.0.0.1:8086/api/v2/write" \
    --url-query "org=$(get INFLUXDB_ORG)" --url-query "bucket=$(get INFLUXDB_BUCKET)" --url-query precision=s \
    -H "Authorization: Token $(get INFLUXDB_ADMIN_TOKEN)" \
    --data-binary "lonsemonsy_backup,store=$1 ok=$2i,copies=${copies:-0}i,size=${size:-0}i,seconds=${secs:-0}i,by=\"${by//\"/}\"" >/dev/null || true
}
# Audit page: Wazuh reads this from the system log.
audit() {
  local what=${only:-local}
  if [ -z "$only" ] && [ -n "$cloud" ]; then what="local and cloud"; fi
  logger -t lonsemonsy-backup "{\"lonsemonsy\":\"backup\",\"action\":\"$1\",\"what\":\"$what\",\"by\":\"${by//\"/}\"}"
}
trap 'record "${only:-local}" 0; audit failed; report "❌ Backup failed" "The backup did not finish. To see why, run on the server: sudo lsmsy backup"' ERR

# InfluxDB makes its own clean copy first (copying its files while it runs isn't safe).
rm -rf /var/backups/lonsemonsy
mkdir -p /var/backups/lonsemonsy
docker exec influxdb rm -rf /tmp/influx-backup
docker exec influxdb influx backup /tmp/influx-backup -t "$(get INFLUXDB_ADMIN_TOKEN)" >/dev/null
docker cp influxdb:/tmp/influx-backup /var/backups/lonsemonsy/influxdb
docker exec influxdb rm -rf /tmp/influx-backup
# The export is only needed while backing up; don't leave a second copy lying around.
trap 'rm -f "$WPASS"; rm -rf /var/backups/lonsemonsy' EXIT   # keeps helpers.sh's own cleanup too

# What's backed up: the settings file, InfluxDB's copy, Grafana and NetAlertX's data, and
# Wazuh's settings (with the agents' keys, so protected computers keep reporting).
paths=(appliance/.env /var/backups/lonsemonsy)
for volume in grafana-data netalertx-data; do
  paths+=("$(docker volume inspect -f '{{.Mountpoint}}' "lonsemonsy_$volume")")
done
if [ -d /var/ossec/etc ]; then paths+=(/var/ossec/etc); fi

saved=$(for p in "${paths[@]}"; do
  case "$p" in
    *.env) n="LoNSeMonSy's settings and passwords (.env)" ;;   */lonsemonsy) n="Health and backup history (InfluxDB)" ;;
    *grafana*) n="Grafana: accounts and dashboards" ;;         *netalertx*) n="NetAlertX: the device list" ;;
    *) n="Wazuh: settings, rules and agent keys" ;;
  esac
  echo "- $n, $(du -shL "$p" | cut -f1)"
done)

# save STORE: back up to one store (made the first time), keeping 7 daily, 4 weekly and
# 6 monthly copies; older ones are deleted. Sets copies, size (bytes) and secs.
save() {
  RESTIC_REPOSITORY=$1
  local start=$SECONDS
  copies=0 size=0 secs=0
  restic cat config >/dev/null 2>&1 || restic init >/dev/null || return 1
  summary=$(restic backup --json "${paths[@]}" | grep '"message_type":"summary"') || return 1
  files=$(jq -r '"\(.total_files_processed) files: \(.files_new) new, \(.files_changed) changed, \(.files_unmodified) the same"' <<< "$summary")
  restic forget --quiet --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || return 1
  copies=$(restic snapshots --json | jq length)
  size=$(restic stats --mode raw-data --json | jq .total_size)
  secs=$((SECONDS - start))
}
failed=0 result=""
if [ "$only" != cloud ]; then
  mkdir -p "$local_store"
  chmod 700 "$local_store"
  if save "$local_store"; then record local 1; result="Local backup: OK, $copies copies kept ($files)"
  else record local 0; result="Local backup: FAILED. To see why, run on the server: sudo lsmsy backup"; failed=1; fi
fi
if [ -n "$cloud" ] && [ "$only" != local ]; then
  if save "$cloud"; then record cloud 1; result+=${result:+$'\n'}"Cloud backup: OK, $copies copies kept ($files)"
  else record cloud 0; result+=${result:+$'\n'}"Cloud backup: FAILED. To see why, run on the server: sudo lsmsy backup"; failed=1; fi
fi
echo "$result"
if [ "$failed" = 1 ]; then
  audit failed
  report "❌ Backup failed" "$result"
  exit 1
fi
audit finished
report "✅ Backup finished: $(date '+%A %b %-d at %-I:%M %p')" "$result

What was saved:
$saved"
