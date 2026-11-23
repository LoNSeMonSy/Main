#!/usr/bin/env bash
# Every 5 minutes (lonsemonsy-remote-check timer): is remote access on, and which devices
# can open the dashboards. Saved in InfluxDB for the Devices page. A device not seen before
# also gets a remote_new_device point, which sets off the "New device can reach your
# dashboard" alarm.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ENV=appliance/.env
get() { grep -E "^$1=" "$ENV" | cut -d= -f2-; }
q() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }   # quoted Influx string

known=/var/lib/lonsemonsy/remote-devices   # IDs of devices already seen
first=0; [ -f "$known" ] || first=1        # first run: remember everyone, no alarm
mkdir -p "${known%/*}"; touch "$known"

if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1 &&
   tailscale serve status --json 2>/dev/null | jq -e 'has("TCP")' >/dev/null; then
  json=$(tailscale status --json)
  lines="remote_access on=1i,devices=$(jq '[.Peer[]?] | length' <<< "$json")i,address=$(q "https://$(jq -r '.Self.DNSName | rtrimstr(".")' <<< "$json"):8443")"
  while IFS=$'\t' read -r id host owner os online seen; do
    lines+=$'\n'"remote_device,id=$id name=$(q "$host"),owner=$(q "$owner"),os=$(q "$os"),online=${online}i,last_seen=$(q "$seen")"
    if ! grep -qx "$id" "$known"; then
      echo "$id" >> "$known"
      [ "$first" = 1 ] || lines+=$'\n'"remote_new_device,id=$id name=$(q "$host"),owner=$(q "$owner")"
    fi
  done < <(jq -r '. as $s | .Peer[]? | [.ID, .HostName, ($s.User[(.UserID|tostring)].LoginName // "unknown"),
             .OS, (if .Online then 1 else 0 end), (if .Online then "now" else (.LastSeen[:16] | sub("T"; " ")) + " UTC" end)] | @tsv' <<< "$json")
else
  lines="remote_access on=0i,devices=0i,address=$(q "")"
fi

curl -sf -X POST "http://127.0.0.1:8086/api/v2/write" \
  --url-query "org=$(get INFLUXDB_ORG)" --url-query "bucket=$(get INFLUXDB_BUCKET)" --url-query precision=s \
  -H "Authorization: Token $(get INFLUXDB_ADMIN_TOKEN)" --data-binary "$lines" ||
  { echo "Could not save to InfluxDB."; exit 1; }
