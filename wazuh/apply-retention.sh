#!/usr/bin/env bash
# Apply the Wazuh alert retention policy. Run with sudo (needs indexer admin).
#   sudo bash wazuh/apply-retention.sh
# Edit the "90d" window in ism-policy.json first if you want a different retention.
set -euo pipefail
POLICY="$(dirname "$0")/ism-policy.json"
IDX="https://127.0.0.1:9200"
PID="lonsemonsy-alerts-retention"
ADMINPW=$(grep -oP 'indexer_password: .\K[^'"'"']+' /root/wazuh-secrets/wazuh-passwords.txt | head -1)

echo "[1/2] Creating/updating ISM policy '$PID'..."
curl -sk -u "admin:$ADMINPW" -X PUT "$IDX/_plugins/_ism/policies/$PID" \
  -H 'Content-Type: application/json' --data-binary @"$POLICY" \
  -w '\n  -> HTTP %{http_code}\n' -o /dev/null

echo "[2/2] Attaching it to existing wazuh-alerts-* indices..."
curl -sk -u "admin:$ADMINPW" -X POST "$IDX/_plugins/_ism/add/wazuh-alerts-*" \
  -H 'Content-Type: application/json' -d "{\"policy_id\":\"$PID\"}" \
  -w '\n  -> HTTP %{http_code}\n' -o /dev/null

echo "Done. New daily indices inherit it automatically (ism_template)."
echo "Check status: sudo curl -sk -u admin:<pw> $IDX/_plugins/_ism/explain/wazuh-alerts-* | jq"
