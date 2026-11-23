# shellcheck shell=bash
# Step 6: the firewall (Ubuntu's ufw). Everything coming in is blocked except SSH and
# the ports the dashboards and Wazuh agents use, and those only from this network.

if [ "${SKIP_FIREWALL:-0}" = 1 ]; then
  echo "  firewall: skipped"
else
  # SSH only from this network and Tailscale (first, so SSH never gets cut off).
  # SSH_ANYWHERE=1 in appliance/.env keeps it open to everyone, like before.
  ufw allow from "$lan" to any port 22 proto tcp comment "SSH" >/dev/null
  ufw allow in on tailscale0 to any port 22 proto tcp comment "SSH over Tailscale" >/dev/null
  if [ "$(get SSH_ANYWHERE)" = 1 ]; then
    ufw allow 22/tcp comment "SSH" >/dev/null
  else
    ufw delete allow 22/tcp >/dev/null 2>&1 || true            # older installs had it open to everyone
  fi
  ufw allow from "$lan" to any port 1514 proto tcp comment "Wazuh agents (logs)" >/dev/null
  ufw allow from "$lan" to any port 1515 proto tcp comment "Wazuh agents (sign up)" >/dev/null
  ufw allow from 172.20.0.0/24 to 172.20.0.1 port 9200 proto tcp comment "Grafana reads Wazuh" >/dev/null
  ufw allow from 172.20.0.0/24 to 172.20.0.1 port 5002 proto tcp comment "Grafana backup button" >/dev/null
  ufw default deny incoming >/dev/null
  ufw --force enable >/dev/null
  # The dashboards: open to this network, unless remote access turned that off.
  if [ "$(get IP_ACCESS)" = off ]; then ip_access off "$lan" "$iface"; else ip_access on "$lan" "$iface"; fi
  echo "  firewall: on. Everything is blocked except these, only from $lan:"
  echo "    Port 22 (SSH), 1514 and 1515 (Wazuh agents)"
  if [ "$(get IP_ACCESS)" = off ]; then echo "    The dashboards only open over Tailscale (lsmsy remote)."
  else echo "    Port 3000 (Grafana), 443 (Wazuh dashboard), 20211 (NetAlertX)"; fi
fi
