# shellcheck shell=bash
# Step 8: turn on Wazuh's extras. Each one is added to Wazuh's config as its own block,
# and Wazuh is restarted once at the end.

OSC=/var/ossec/etc/ossec.conf
restart=0

# Auto-block: an address that keeps failing to log in is blocked for 10 minutes.
# The router and this machine are never blocked.
if [ -f "$OSC" ] && ! grep -q 'LoNSeMonSy auto-block' "$OSC"; then
  {
    echo "<!-- LoNSeMonSy auto-block -->"
    echo "<ossec_config>"
    echo "  <global><white_list>$gw</white_list><white_list>$ip</white_list></global>"
    sed -n '/^<active-response>/,/^<\/active-response>/p' wazuh/active-response.xml
    echo "</ossec_config>"
  } >> "$OSC"
  restart=1
  echo "  wazuh: auto-block on"
fi

# Watch this machine's Docker containers, and add our rules (wazuh/lonsemonsy_rules.xml).
if [ -f "$OSC" ] && ! grep -q 'docker-listener' "$OSC"; then
  printf '<ossec_config>\n  <wodle name="docker-listener"><disabled>no</disabled></wodle>\n</ossec_config>\n' >> "$OSC"
  install -o wazuh -g wazuh -m 660 wazuh/lonsemonsy_rules.xml /var/ossec/etc/rules/
  restart=1
  echo "  wazuh: watching Docker containers"
fi

# Port-scan detection with Suricata (appliance/suricata/install-suricata.sh).
if [ -f "$OSC" ] && [ "${SKIP_SURICATA:-0}" != 1 ] && ! grep -q suricata/eve.json "$OSC"; then
  echo "  installing Suricata (port-scan detection)..."
  NO_WAZUH_RESTART=1 bash appliance/suricata/install-suricata.sh > /root/suricata-install.log 2>&1
  restart=1
  echo "  suricata: on"
fi

if [ "$restart" = 1 ]; then
  echo "  wazuh: restarting to load the changes..."
  wazuh_restart
fi

# Keep 90 days of alerts so the disk doesn't fill up (wazuh/ism-policy.json).
if [ -s "$WPASS" ]; then
  admin=$(wazuh_password admin)
  for _ in $(seq 1 30); do
    if curl -sk -u "admin:$admin" https://127.0.0.1:9200 -o /dev/null; then break; fi
    sleep 5
  done
  curl -sk -u "admin:$admin" -X PUT https://127.0.0.1:9200/_plugins/_ism/policies/lonsemonsy-alerts-retention \
    -H 'Content-Type: application/json' --data-binary @wazuh/ism-policy.json -o /dev/null
  echo "  wazuh: keeping 90 days of alerts"
fi
