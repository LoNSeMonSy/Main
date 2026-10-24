#!/usr/bin/env bash
# Checks GitHub for a newer LoNSeMonSy release and saves the result in InfluxDB, so
# Grafana can show the update banner and the Updates page. Runs once a day from the
# lonsemonsy-update-check timer (installed by setup.sh). Safe to run by hand.
set -uo pipefail
cd "$(dirname "$0")/.."
ENV="appliance/.env"
get() { grep -E "^$1=" "$ENV" | cut -d= -f2-; }

branch=$(get UPDATE_BRANCH); branch=${branch:-main}
repo=$(get UPDATE_REPO); repo=${repo:-$(git remote get-url origin 2>/dev/null)}
installed=$(cat VERSION 2>/dev/null || echo unknown)

# Download only the newest commit of the release branch into a small cache repo.
cache="${HOME:-/tmp}/.cache/lonsemonsy-updates"
mkdir -p "$cache" && git init -q --bare "$cache" 2>/dev/null
latest=unknown; ok=0; notes=""; reached=0
if git -C "$cache" fetch -q --depth 1 "$repo" "$branch" 2>/dev/null; then
  reached=1
  latest=$(git -C "$cache" show FETCH_HEAD:VERSION 2>/dev/null || echo unknown)
  # The bullet points of the newest section of CHANGELOG.md
  notes=$(git -C "$cache" show FETCH_HEAD:CHANGELOG.md 2>/dev/null | awk '/^## /{n++; next} n==1 && /^- /{sub(/^- /,""); print}')
  [ "$latest" != unknown ] && ok=1
fi

newer=0
if [ "$ok" = 1 ] && [ "$latest" != "$installed" ]; then
  # An install from before versions existed has no VERSION file: that's older too.
  if [ "$installed" = unknown ] || \
     [ "$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -1)" = "$latest" ]; then
    newer=1
  fi
fi

# InfluxDB line protocol: quote strings and escape " and \ inside them.
q() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
lines="lonsemonsy_version installed=$(q "$installed"),latest=$(q "$latest"),update_available=${newer}i,check_ok=${ok}i"
i=0
while IFS= read -r note; do
  [ -n "$note" ] || continue
  i=$((i + 1))
  lines+=$'\n'"lonsemonsy_changelog,line=$(printf '%02d' $i) version=$(q "$latest"),text=$(q "$note")"
done <<< "$notes"

# This machine's addresses, so Grafana's links to Wazuh and NetAlertX work from anywhere:
# Tailscale first (works away from home), then the local network address.
ts=$(ip -o -4 addr show dev tailscale0 2>/dev/null | awk '{print $4; exit}' | cut -d/ -f1)
lanif=$(ip -o -4 route show default | awk '{print $5; exit}')
lan=$(ip -o -4 addr show dev "$lanif" 2>/dev/null | awk '{print $4; exit}' | cut -d/ -f1)
[ -n "$ts" ]  && lines+=$'\n'"lonsemonsy_address,rank=1 value=$(q "$ts")"
[ -n "$lan" ] && lines+=$'\n'"lonsemonsy_address,rank=2 value=$(q "$lan")"
# Where Grafana's Wazuh links point. WAZUH_URL in .env overrides it, e.g. a name
# instead of an IP, which Okta sign-in needs (it only returns to the address it knows).
wazuh=$(get WAZUH_URL); first=${ts:-$lan}; wazuh=${wazuh:-${first:+https://$first}}
[ -n "$wazuh" ] && lines+=$'\n'"lonsemonsy_link,name=wazuh value=$(q "${wazuh%/}")"

curl -sf -X POST "http://127.0.0.1:8086/api/v2/write" \
  --url-query "org=$(get INFLUXDB_ORG)" --url-query "bucket=$(get INFLUXDB_BUCKET)" --url-query precision=s \
  -H "Authorization: Token $(get INFLUXDB_ADMIN_TOKEN)" --data-binary "$lines" \
  || { echo "Could not save the result to InfluxDB."; exit 1; }

if [ "$reached" = 0 ]; then echo "Could not reach $repo ($branch). Installed: $installed"
elif [ "$ok" = 0 ]; then echo "No release found on $repo ($branch) yet. Installed: $installed"
elif [ "$newer" = 1 ]; then echo "Update available: $latest (installed: $installed). Run: sudo ./setup/update.sh"
else echo "LoNSeMonSy $installed is up to date."; fi
