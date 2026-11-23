#!/usr/bin/env bash
# Sets a new admin password and signs everyone out:  lsmsy password grafana   (or wazuh, netalertx)
# Use it if a password is forgotten, or someone else may know it.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source-path=SCRIPTDIR/..
source setup/steps/helpers.sh   # get, set_env, short_pw, netalertx_login
[ "$(id -u)" = 0 ] || { echo "Run it with sudo:  sudo lsmsy password $*"; exit 1; }
only_one password "A password is already being changed. Try again when it's done."
what=${1:-}
case "$what" in grafana|wazuh|netalertx) ;; *) echo "  usage: lsmsy password grafana   (or wazuh, netalertx)"; exit 1 ;; esac

# Wazuh wants 8+ characters with upper and lower case letters, a number and one of . * + ? -
strong() { [[ ${#1} -ge 8 && $1 == *[A-Z]* && $1 == *[a-z]* && $1 == *[0-9]* && $1 == *[.*+?-]* ]]; }
echo "  New $what admin password: at least 8 characters with upper and lower case letters,"
echo "  a number and one of . * + ? -   Press Enter to have one made for you."
read -r -s -p "  New password (hidden): " pw; echo
if [ -z "$pw" ]; then
  pw="$(short_pw | cut -c1-8)-K7q"
  made=1
else
  strong "$pw" || { echo "  That password is too weak. Nothing changed."; exit 1; }
  read -r -s -p "  Same password again: " again; echo
  [ "$pw" = "$again" ] || { echo "  They don't match. Nothing changed."; exit 1; }
  made=0
fi

if [ "$what" = grafana ]; then
  docker exec grafana grafana cli admin reset-admin-password "$pw" >/dev/null
  set_env GRAFANA_ADMIN_PASSWORD "$pw"
  # Sign every account out, so anyone using a stolen login has to sign in again.
  for id in $(curl -s -m 15 -u "admin:$pw" http://localhost:3000/api/users | jq -r '.[].id'); do
    curl -s -m 15 -u "admin:$pw" -X POST "http://localhost:3000/api/admin/users/$id/logout" -o /dev/null
  done
  echo "  Grafana's admin password is changed and everyone is signed out."
elif [ "$what" = netalertx ]; then
  set_env NETALERTX_PASSWORD "$pw"
  set_env NETALERTX_PASSWORD_HASH "$(printf '%s' "$pw" | sha256sum | cut -d' ' -f1)"
  (cd appliance && docker compose up -d netalertx >/dev/null 2>&1)
  netalertx_login
  echo "  NetAlertX's password is changed."
else
  # Wazuh's own tool. It also updates Filebeat, which sends the alerts in as admin.
  run "Changing the Wazuh admin password" \
    /usr/share/wazuh-indexer/plugins/opensearch-security/tools/wazuh-passwords-tool.sh -u admin -p "$pw"
  echo "  Wazuh's admin password is changed."
fi
if [ "$made" = 1 ]; then echo "  New password: $pw   (save it in a password manager; it isn't shown again)"; fi
