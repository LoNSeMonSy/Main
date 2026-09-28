#!/bin/bash
# Enroll a Debian or Ubuntu machine as a Wazuh agent reporting to the appliance.
# Run as root ON THE HOST being enrolled:
#   bash enroll-host.sh <agent-name> [--no-active-response]
# Use --no-active-response on hypervisors (Proxmox): automatic IP blocking
# must never run iptables on a host that carries the whole network.
set -euo pipefail

NAME="${1:?usage: enroll-host.sh <agent-name> [--no-active-response]}"
NO_AR="${2:-}"
MANAGER="${WAZUH_MANAGER:?set WAZUH_MANAGER=<appliance-ip>}"
VER="${WAZUH_AGENT_VERSION:-4.14.8-1}"   # must match the manager's version

export DEBIAN_FRONTEND=noninteractive
command -v gpg >/dev/null || apt-get install -y -qq gnupg >/dev/null
curl -fsS https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --batch --yes --dearmor -o /usr/share/keyrings/wazuh.gpg
echo 'deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main' \
  > /etc/apt/sources.list.d/wazuh.list
apt-get update -qq
WAZUH_MANAGER="$MANAGER" WAZUH_AGENT_NAME="$NAME" apt-get install -y -qq "wazuh-agent=$VER" >/dev/null
apt-mark hold wazuh-agent >/dev/null   # upgrade together with the manager, never alone

CONF=/var/ossec/etc/ossec.conf
if [ "$NO_AR" = "--no-active-response" ] && ! grep -q 'no active response on this host' "$CONF"; then
  sed -i '0,/<\/ossec_config>/s//  <!-- no active response on this host -->\n  <active-response>\n    <disabled>yes<\/disabled>\n  <\/active-response>\n<\/ossec_config>/' "$CONF"
fi

systemctl daemon-reload
systemctl enable --now wazuh-agent
sleep 8
echo "wazuh-agent: $(systemctl is-active wazuh-agent)"
grep -E 'Connected to the server|ERROR' /var/ossec/logs/ossec.log | tail -3 || true
echo "On the appliance, confirm with: sudo /var/ossec/bin/agent_control -l"
