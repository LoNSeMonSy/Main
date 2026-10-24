#!/usr/bin/env bash
# Update LoNSeMonSy to the newest release, then restart the stack.
# Your .env and data volumes are kept. Back up the machine first (that's your rollback).
#   sudo ./setup/update.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Run git as the folder's owner. Git refuses to work as root in a folder another
# user owns, and the owner is the one with access to GitHub.
owner=$(stat -c %U .)
as_owner() { if [ "$(id -u)" = 0 ] && [ "$owner" != root ]; then sudo -u "$owner" "$@"; else "$@"; fi; }

branch=$(grep -E '^UPDATE_BRANCH=' appliance/.env | cut -d= -f2- || true); branch=${branch:-main}
repo=$(grep -E '^UPDATE_REPO=' appliance/.env | cut -d= -f2- || true); repo=${repo:-origin}
before=$(cat VERSION 2>/dev/null || echo unknown)

echo "LoNSeMonSy update (installed: ${before})"
echo "  Reminder: back up this machine first (that's your rollback)."

echo "  downloading the newest release from GitHub (${branch})..."
as_owner git fetch -q "$repo" "$branch"
as_owner git reset -q --hard FETCH_HEAD      # appliance/.env isn't tracked by git, so it's kept
after=$(cat VERSION 2>/dev/null || echo unknown)

echo "  pulling new images and restarting (data and .env kept)..."
( cd appliance && docker compose pull -q && docker compose up -d && docker compose restart grafana >/dev/null )  # grafana reloads new dashboards and alarms

# Refresh the update banner in Grafana straight away.
as_owner ./setup/check-update.sh >/dev/null 2>&1 || true

cat <<DONE

LoNSeMonSy updated: ${before} -> ${after}. What changed: CHANGELOG.md

Not updated by this script (on purpose): the Wazuh server and agents. Update those with
Wazuh's own upgrade guide, keeping versions matching:
  https://documentation.wazuh.com/current/upgrade-guide/index.html
DONE
