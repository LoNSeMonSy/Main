#!/usr/bin/env bash
# Update LoNSeMonSy to the newest release, then restart the stack.
# Your .env and data volumes are kept. Back up the machine first (that's your rollback).
#   sudo ./setup/update.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Second half, run by the new copy after the download (see the end of this file).
if [ "${1:-}" = --apply ]; then
  after=$(cat setup/VERSION 2>/dev/null || echo unknown)
  echo "  applying the update (a minute or two)..."
  if ! SKIP_QUESTIONS=1 ./setup/setup.sh > /var/log/lonsemonsy-update.log 2>&1; then
    tail -15 /var/log/lonsemonsy-update.log
    echo "  The update didn't finish. The whole log: /var/log/lonsemonsy-update.log"; exit 1
  fi
  (cd appliance && docker compose up -d --remove-orphans >/dev/null 2>&1 && docker compose restart grafana >/dev/null 2>&1)  # grafana reloads new dashboards and alarms
  echo
  echo "LoNSeMonSy updated: ${2:-unknown} -> ${after} ($(git -c safe.directory="$PWD" log -1 --format=%cd --date=format:'%b %-d')). What changed: setup/CHANGELOG.md"
  exit 0
fi

# Run git as the folder's owner. Git refuses to work as root in a folder another
# user owns, and the owner is the one with access to GitHub.
owner=$(stat -c %U .)
as_owner() { if [ "$(id -u)" = 0 ] && [ "$owner" != root ]; then sudo -u "$owner" "$@"; else "$@"; fi; }

branch=$(grep -E '^UPDATE_BRANCH=' appliance/.env | cut -d= -f2- || true)
branch=${branch:-$(as_owner git rev-parse --abbrev-ref HEAD 2>/dev/null)}; branch=${branch:-main}   # follow this copy's own branch
repo=$(grep -E '^UPDATE_REPO=' appliance/.env | cut -d= -f2- || true); repo=${repo:-origin}
before=$(cat setup/VERSION 2>/dev/null || cat VERSION 2>/dev/null || echo unknown)

echo "LoNSeMonSy update (installed: ${before})"
echo "  Reminder: back up this machine first (that's your rollback)."

echo "  downloading the newest release from GitHub (${branch})..."
as_owner git fetch -q "$repo" "$branch"
as_owner git reset -q --hard FETCH_HEAD      # appliance/.env isn't tracked by git, so it's kept

# Run setup again from the new copy (no questions). It only does what's missing:
# new services, rules and commands. --apply is the new copy taking over.
exec setup/update.sh --apply "$before"
