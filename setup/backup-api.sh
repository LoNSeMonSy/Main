#!/usr/bin/env bash
# The Backups page's "Local backup now" and "Cloud backup now" buttons. systemd runs this once per request
# (lonsemonsy-backup-api.socket); only Grafana can call it, because Grafana adds the
# BACKUP_API_TOKEN and the name of the signed-in user (X-Grafana-User).
# Only Grafana Admins may start a backup; every press is written to the Audit page.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source-path=SCRIPTDIR/..
source setup/steps/helpers.sh   # get

reply() {   # reply STATUS MESSAGE
  local body="{\"message\":\"$2\"}"
  printf 'HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
    "$1" "${#body}" "$body"
  exit 0
}
audit() { logger -t lonsemonsy-backup "{\"lonsemonsy\":\"backup\",\"action\":\"$1\",\"what\":\"${which:-}\",\"by\":\"$user\"}"; }

read -r -t 5 method path _ || exit 0
token="" user=""
for _ in $(seq 40); do                       # headers, up to the blank line
  IFS= read -r -t 5 line || break
  line=${line%$'\r'}
  [ -z "$line" ] && break
  case "${line,,}" in
    x-backup-token:*) token=${line#*: } ;;
    x-grafana-user:*) user=${line#*: } ;;
  esac
done
user=${user//[^A-Za-z0-9@._-]/}              # a login name, nothing else

if [ -z "$token" ] || [ "$token" != "$(get BACKUP_API_TOKEN)" ]; then reply "403 Forbidden" "Not allowed."; fi
case "$method $path" in
  "POST /backup/local") which=local ;;
  "POST /backup/cloud") which=cloud ;;
  *) reply "404 Not Found" "Unknown request." ;;
esac

role=$(curl -s -m 10 -u "admin:$(get GRAFANA_ADMIN_PASSWORD)" \
  "http://127.0.0.1:3000/api/org/users/search?query=$user" | jq -r --arg u "$user" '.orgUsers[] | select(.login == $u) | .role')
if [ -z "$user" ] || [ "$role" != Admin ]; then
  audit denied
  reply "403 Forbidden" "Only admins can start backups."
fi
if [ "$which" = cloud ] && [ -z "$(get BACKUP_REPO)" ]; then
  reply "409 Conflict" "Cloud backup isn't set up. To add it, run sudo lsmsy backup setup on the server."
fi
if systemctl is-active --quiet lonsemonsy-backup.service; then
  reply "409 Conflict" "A backup is already running."
fi
echo "$user" > /run/lonsemonsy-backup-by
echo "$which" > /run/lonsemonsy-backup-only
systemctl start --no-block lonsemonsy-backup.service
audit started
reply "200 OK" "The $which backup started. It takes a few minutes; this page shows the result when it's done."
