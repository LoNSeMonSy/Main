#!/usr/bin/env bash
# One-time wiring so Grafana can read the Wazuh indexer. Safe to re-run.
#
# It (1) recreates the compose stack to create the pinned 172.20.0.0/24 network,
# install the OpenSearch plugin, and pick up the datasource + creds, then
# (2) binds the indexer to the bridge gateway 172.20.0.1 (NOT the LAN) so the
# Grafana container can reach it. Run from ~/Main/appliance.
#
# Prereqs: set WAZUH_INDEXER_PASSWORD in .env first (see .env.example).
set -euo pipefail
cd "$(dirname "$0")/../appliance"

OSD=/etc/wazuh-indexer/opensearch.yml
GW=172.20.0.1

grep -q '^WAZUH_INDEXER_PASSWORD=.\+' .env \
  || { echo "Set WAZUH_INDEXER_PASSWORD in .env first (see .env.example)."; exit 1; }

echo "[1/4] Recreating compose stack (creates pinned network, installs plugin)..."
docker compose up -d --remove-orphans

echo "[2/4] Binding the Wazuh indexer to localhost + ${GW} (not the LAN)..."
sudo cp -n "$OSD" "${OSD}.bak.$(date +%Y%m%d%H%M%S)"
sudo sed -i -E 's/^\s*network\.host\s*:.*/# &  (superseded by bind_host below)/' "$OSD"
if ! grep -q '^network.bind_host:' "$OSD"; then
  printf 'network.bind_host: ["127.0.0.1", "%s"]\nnetwork.publish_host: "127.0.0.1"\n' "$GW" \
    | sudo tee -a "$OSD" >/dev/null
fi
sudo systemctl restart wazuh-indexer

echo "[3/4] Waiting for the indexer on ${GW}:9200..."
for i in $(seq 1 30); do
  if curl -sk "https://${GW}:9200" -o /dev/null; then echo "  up."; break; fi
  sleep 3
done

echo "[4/4] Checking Grafana can query the datasource..."
sleep 5
docker exec grafana wget -qO- --no-check-certificate \
  "http://localhost:3000/api/health" >/dev/null && echo "  Grafana up."
echo
echo "Done. In Grafana: Connections -> Data sources -> Wazuh -> Save & test."
echo "If it fails, check: WAZUH_INDEXER_PASSWORD in .env, and 'ss -ltn | grep 9200'"
echo "shows ${GW}:9200 listening."
