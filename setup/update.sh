#!/usr/bin/env bash
# Update LoNSeMonSy: pull the new release, pull new pinned images, restart the stack.
# Your .env and data volumes are preserved. Back up the machine first.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "LoNSeMonSy update"
echo "  Reminder: back up this machine first (that's your rollback)."

echo "  pulling the new release..."
git pull --ff-only

echo "  pulling new images + restarting (data + .env preserved)..."
( cd appliance && docker compose pull && docker compose up -d --build )

cat <<DONE

Docker stack updated.

Not updated by this script (deliberately):
  - Wazuh server/agents -> update via its own package manager, keeping manager,
    indexer, and agent versions matching. See docs/UPDATES.md.
DONE
