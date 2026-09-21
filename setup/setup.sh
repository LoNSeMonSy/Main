#!/usr/bin/env bash
# LoNSeMonSy setup — fills in any missing secrets in appliance/.env, then starts
# the stack. Config-first: you edit appliance/.env (see setup/README.md), run this.
set -euo pipefail
cd "$(dirname "$0")/.."
ENV="appliance/.env"

echo "LoNSeMonSy setup"
[ -f "$ENV" ] || { echo "  No $ENV found. First run:  cp appliance/.env.example $ENV  then edit it."; exit 1; }

# Generate any secret left blank, so nobody hand-types secrets. Existing values are
# never touched, so this is safe to re-run.
gen() { openssl rand -hex 24; }
for key in INFLUXDB_ADMIN_PASSWORD INFLUXDB_ADMIN_TOKEN GRAFANA_ADMIN_PASSWORD TRIGGER_TOKEN; do
  if grep -qE "^${key}=$" "$ENV"; then
    sed -i "s|^${key}=$|${key}=$(gen)|" "$ENV"
    echo "  generated ${key}"
  fi
done

echo "  starting the stack..."
( cd appliance && docker compose up -d )

ip=$(hostname -I | awk '{print $1}')
cat <<DONE

Done. Open Grafana:  http://${ip}:3000   (admin password is in ${ENV})

Configured later, not by this script — see setup/README.md:
  - Wazuh detection server   (its own installer)
  - Backups                  (fill the PVE_* values in ${ENV})
DONE
