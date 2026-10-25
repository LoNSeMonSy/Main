# shellcheck shell=bash
# Step 6: the firewall (Ubuntu's ufw). Everything coming in is blocked except SSH and
# the ports the dashboards and Wazuh agents use, and those only from this network.

if [ "${SKIP_FIREWALL:-0}" = 1 ]; then
  echo "  firewall: skipped"
else
  ufw allow 22/tcp comment "SSH" >/dev/null                      # first, so SSH never gets cut off
  ufw allow from "$lan" to any port 3000 proto tcp comment "Grafana" >/dev/null
  ufw allow from "$lan" to any port 443 proto tcp comment "Wazuh dashboard" >/dev/null
  ufw allow from "$lan" to any port 20211 proto tcp comment "NetAlertX" >/dev/null
  ufw allow from "$lan" to any port 1514 proto tcp comment "Wazuh agents (logs)" >/dev/null
  ufw allow from "$lan" to any port 1515 proto tcp comment "Wazuh agents (sign up)" >/dev/null
  ufw allow from 172.20.0.0/24 to 172.20.0.1 port 9200 proto tcp comment "Grafana reads Wazuh" >/dev/null
  ufw default deny incoming >/dev/null
  ufw --force enable >/dev/null
  echo "  firewall: on. Everything is blocked except:"
  echo "    Port 22 (SSH), from anywhere"
  echo "    Port 3000 (Grafana), 443 (Wazuh dashboard), 20211 (NetAlertX),"
  echo "    1514 and 1515 (Wazuh agents), only from $lan"
fi
