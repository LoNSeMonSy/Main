# shellcheck shell=bash
# Step 7: start Grafana, InfluxDB and NetAlertX, then let Grafana reach Wazuh.

echo "  starting Grafana, InfluxDB and NetAlertX..."
# Docker's own messages go to a log; they're only shown if something goes wrong.
if ! (cd appliance && docker compose up -d --quiet-pull > /tmp/lonsemonsy-start.log 2>&1); then
  cat /tmp/lonsemonsy-start.log
  exit 1
fi

# Grafana runs in Docker, so the Wazuh indexer also listens on Docker's own network
# (172.20.0.1, set in docker-compose.yml), never on the LAN.
OSD=/etc/wazuh-indexer/opensearch.yml
if [ -f "$OSD" ] && ! grep -q '^network.bind_host:' "$OSD"; then
  sed -i 's/^network.host:/# network.host:/' "$OSD"
  echo 'network.bind_host: ["127.0.0.1", "172.20.0.1"]' >> "$OSD"
  echo 'network.publish_host: "127.0.0.1"' >> "$OSD"
  # At boot: the indexer waits for Docker (which makes 172.20.0.1), and Wazuh gets
  # 5 minutes to start instead of 45 seconds, which isn't enough on a busy machine.
  mkdir -p /etc/systemd/system/wazuh-indexer.service.d /etc/systemd/system/wazuh-manager.service.d
  printf '[Unit]\nAfter=docker.service\n\n[Service]\nTimeoutStartSec=600\n' > /etc/systemd/system/wazuh-indexer.service.d/lonsemonsy.conf
  printf '[Service]\nTimeoutSec=300\n' > /etc/systemd/system/wazuh-manager.service.d/lonsemonsy.conf
  systemctl daemon-reload
  systemctl restart wazuh-indexer
  echo "  wazuh: connected to grafana"
fi
