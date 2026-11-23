#!/usr/bin/env bash
# Emails a short summary of the past week (setup runs it every Monday at 8 AM).
# Test without sending:  sudo ./setup/weekly-report.sh print
set -euo pipefail
ENV=${LONSEMONSY_ENV:-$(dirname "$(readlink -f "$0")")/../appliance/.env}
get() { grep -m1 "^$1=" "$ENV" | cut -d= -f2- | tr -d "\"'"; }

# Count or group Wazuh alerts from the last 7 days.
search() {
  curl -sk --max-time 30 -u "$(get WAZUH_INDEXER_USER):$(get WAZUH_INDEXER_PASSWORD)" \
    -H 'Content-Type: application/json' "https://127.0.0.1:9200/$1/_search" -d "$2"
}
week='{"range":{"timestamp":{"gte":"now-7d"}}}'
count() { search 'wazuh-alerts-*' "{\"size\":0,\"track_total_hits\":true,\"query\":{\"bool\":{\"filter\":[$week,{\"query_string\":{\"query\":\"$1\"}}]}}}" | jq '.hits.total.value // 0'; }
top() {   # top 5 values of a field, as "  count  value" lines
  search 'wazuh-alerts-*' "{\"size\":0,\"query\":{\"bool\":{\"filter\":[$week,{\"query_string\":{\"query\":\"$1\"}}]}},\"aggs\":{\"t\":{\"terms\":{\"field\":\"$2\",\"size\":5}}}}" |
    jq -r '.aggregations.t.buckets[] | "\(.doc_count)\t\(.key)"' | awk -F'\t' '{ printf "  %6d  %s\n", $1, $2 }'
}

all=$(count '*')
serious=$(count 'rule.level:>=8')
scans=$(count 'rule.id:86601')
blocked=$(top 'rule.id:651' data.srcip | wc -l)
new_devices=$(docker exec netalertx sqlite3 /data/db/app.db \
  "SELECT count(*) FROM Devices WHERE devFirstConnection >= datetime('now','-7 days')" 2>/dev/null || echo "?")
vulns=$(search 'wazuh-states-vulnerabilities-*' '{"size":0,"aggs":{"s":{"terms":{"field":"vulnerability.severity"}}}}' |
  jq -r '[.aggregations.s.buckets[] | {(.key): .doc_count}] | add // {} |
    [("Critical", "High", "Medium", "Low") as $k | "\($k) \(.[$k] // 0)"] | join(", ")')

subject="Weekly security report: $serious serious alert$([ "$serious" = 1 ] || echo s)"
message="LoNSeMonSy weekly report, $(date -d '-7 days' '+%b %-d') to $(date '+%b %-d')

  Serious alerts (Medium or worse):  $serious
  All alerts:                        $all
  Port scans seen:                   $scans
  Attacker IPs blocked:              $blocked
  New devices on the network:        $new_devices

Most common serious alerts:
$(top 'rule.level:>=8' rule.description)

Machines with the most alerts:
$(top '*' agent.name)

Open vulnerabilities: ${vulns:-none found}

Dashboard: $(get GRAFANA_ROOT_URL | sed 's:/*$::')/d/lons-sec-overview?from=now-7d&to=now"

if [ "${1:-}" = print ]; then printf 'Subject: %s\n\n%s\n' "$subject" "$message"; exit 0; fi
[ "$(get SMTP_ENABLED)" = true ] || { echo "email alarms are off; nothing sent"; exit 0; }

rcpt=()
for address in $(get ALERT_EMAIL_TO | tr ',;' '  '); do rcpt+=(--mail-rcpt "$address"); done
printf 'From: %s <%s>\nTo: %s\nSubject: %s\n\n%s\n' \
  "$(get SMTP_FROM_NAME)" "$(get SMTP_FROM_ADDRESS)" "$(get ALERT_EMAIL_TO)" "$subject" "$message" |
  curl -sS --max-time 30 --ssl-reqd --url "smtp://$(get SMTP_HOST)" --user "$(get SMTP_USER):$(get SMTP_PASSWORD)" \
    --mail-from "$(get SMTP_FROM_ADDRESS)" "${rcpt[@]}" --upload-file -
