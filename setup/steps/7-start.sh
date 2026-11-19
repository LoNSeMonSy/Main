# shellcheck shell=bash
# Step 7: start Grafana, InfluxDB and NetAlertX, then let Grafana reach Wazuh.

run "Downloading Grafana, InfluxDB and NetAlertX" docker compose -f appliance/docker-compose.yml --progress plain pull
run "Starting them" docker compose -f appliance/docker-compose.yml up -d

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
  run "Restarting Wazuh's indexer so Grafana can reach it" systemctl restart wazuh-indexer
fi
