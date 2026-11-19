# shellcheck shell=bash
# Step 8: turn on Wazuh's extras. Each one is added to Wazuh's config as its own block,
# and Wazuh is restarted once at the end.

# NetAlertX login (its password is shown at the end of setup).
netalertx_login && echo "  netalertx: login on" || echo "  netalertx: couldn't turn the login on; try: lsmsy password netalertx"

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
# Older installs: also block for the "lsmsy test" rule, so the test shows an auto-block.
if [ -f "$OSC" ] && grep -q '<rules_id>5712,5720,5763</rules_id>' "$OSC"; then
  sed -i 's#<rules_id>5712,5720,5763</rules_id>#<rules_id>5712,5720,5763,100910</rules_id>#' "$OSC"
  restart=1
fi

# Watch this machine's Docker containers, and add our rules (wazuh/lonsemonsy_rules.xml).
if [ -f "$OSC" ] && ! grep -q 'docker-listener' "$OSC"; then
  printf '<ossec_config>\n  <wodle name="docker-listener"><disabled>no</disabled></wodle>\n</ossec_config>\n' >> "$OSC"
  restart=1
  echo "  wazuh: watching Docker containers"
fi
if [ -f "$OSC" ] && ! cmp -s wazuh/lonsemonsy_rules.xml /var/ossec/etc/rules/lonsemonsy_rules.xml; then
  install -o wazuh -g wazuh -m 660 wazuh/lonsemonsy_rules.xml /var/ossec/etc/rules/
  restart=1
fi

# Port-scan detection with Suricata (appliance/suricata/install-suricata.sh).
if [ -f "$OSC" ] && [ "${SKIP_SURICATA:-0}" != 1 ] && ! grep -q suricata/eve.json "$OSC"; then
  wait_for_updates
  if ! run "Installing Suricata (port-scan detection)" env NO_WAZUH_RESTART=1 bash appliance/suricata/install-suricata.sh; then
    echo "  Suricata didn't install. Run setup again; it carries on from here."; exit 1
  fi
  restart=1
  echo "  suricata: on"
elif [ -f /etc/systemd/system/suricata-update.service ]; then
  # Older installs reloaded rules after the weekly refresh, which stopped scan detection.
  install -m 644 appliance/suricata/suricata-update.service /etc/systemd/system/
  systemctl daemon-reload
  sed -i '/copytruncate/d' /etc/logrotate.d/suricata   # see install-suricata.sh
fi

if [ "$restart" = 1 ]; then
  run "Restarting Wazuh to load the changes" wazuh_restart
fi

# Keep 90 days of alerts so the disk doesn't fill up (wazuh/ism-policy.json).
if [ -s "$WPASS" ]; then
  admin=$(wazuh_password admin)
  run "Waiting for Wazuh's indexer" bash -c 'for _ in $(seq 1 30); do curl -sfk -u "admin:$1" https://127.0.0.1:9200 -o /dev/null && exit 0; sleep 5; done' _ "$admin" || true
  curl -sk -u "admin:$admin" -X PUT https://127.0.0.1:9200/_plugins/_ism/policies/lonsemonsy-alerts-retention \
    -H 'Content-Type: application/json' --data-binary @wazuh/ism-policy.json -o /dev/null
  echo "  wazuh: keeping 90 days of alerts"
fi
