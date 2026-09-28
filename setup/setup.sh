#!/usr/bin/env bash
# LoNSeMonSy setup. Fills in any missing secrets in appliance/.env, turns on the
# firewall, then starts the stack. Edit appliance/.env first (see setup/README.md).
#
#   sudo ./setup/setup.sh                    normal install
#   sudo SKIP_FIREWALL=1 ./setup/setup.sh    same, but leave the firewall alone
set -euo pipefail
cd "$(dirname "$0")/.."
ENV="appliance/.env"

echo "LoNSeMonSy setup"
[ "$(id -u)" = "0" ] || { echo "  Run with sudo:  sudo ./setup/setup.sh"; exit 1; }
[ -f "$ENV" ] || { echo "  No $ENV found. First run:  cp appliance/.env.example $ENV  then edit it."; exit 1; }

# 0. Install anything missing. Needs an apt-based system (Ubuntu or Debian).
need=()
command -v curl    >/dev/null || need+=(curl)
command -v openssl >/dev/null || need+=(openssl)
command -v ip      >/dev/null || need+=(iproute2)
[ "${SKIP_FIREWALL:-0}" = "1" ] || command -v ufw >/dev/null || need+=(ufw)
if [ ${#need[@]} -gt 0 ]; then
  command -v apt-get >/dev/null || { echo "  Missing: ${need[*]}. Install them and run this again."; exit 1; }
  echo "  installing: ${need[*]}"
  apt-get update -qq && apt-get install -y -qq "${need[@]}" >/dev/null
fi
if ! command -v docker >/dev/null; then
  echo "  installing Docker (https://docs.docker.com/engine/install/)..."
  curl -fsSL https://get.docker.com | sh >/dev/null
fi
if ! docker compose version >/dev/null 2>&1; then
  # Docker from the distro's own packages (docker.io) comes without the compose plugin.
  echo "  installing the Docker Compose plugin..."
  apt-get update -qq >/dev/null 2>&1 || true
  apt-get install -y -qq docker-compose-v2 >/dev/null 2>&1 \
    || apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1 \
    || curl -fsSL https://get.docker.com | sh >/dev/null   # Docker's own packages include compose
  docker compose version >/dev/null 2>&1 || { echo "  Could not install Docker Compose. See https://docs.docker.com/compose/install/linux/"; exit 1; }
fi
systemctl enable --now docker >/dev/null 2>&1 || true

# 1. Generate any secret left blank, so nobody hand-types secrets. Existing values
#    are never touched, so this is safe to re-run.
gen() { openssl rand -hex 24; }
# InfluxDB refuses passwords shorter than 8 characters and won't start, so replace a
# too-short one with a generated password instead of failing later.
key=INFLUXDB_ADMIN_PASSWORD
pw=$(grep -E "^${key}=" "$ENV" | cut -d= -f2-)
if [ -n "$pw" ] && [ ${#pw} -lt 8 ]; then
  sed -i "s|^${key}=.*|${key}=|" "$ENV"
  echo "  ${key} was shorter than 8 characters, generating a new one"
fi
for key in INFLUXDB_ADMIN_PASSWORD INFLUXDB_ADMIN_TOKEN GRAFANA_ADMIN_PASSWORD; do
  if grep -qE "^${key}=$" "$ENV"; then
    sed -i "s|^${key}=$|${key}=$(gen)|" "$ENV"
    echo "  generated ${key}"
  fi
done

# 2. Work out this machine's network from its default route, so nothing about the
#    customer's site is hardcoded. Example result: 192.168.1.0/24 on eth0.
iface=$(ip -o -4 route show default | awk '{print $5; exit}')
lan=$(ip -o -4 route show dev "$iface" scope link | awk '{print $1; exit}')
echo "  this machine's network: ${lan} on ${iface}"

if grep -qE '^SCAN_SUBNETS=$' "$ENV"; then
  sed -i "s|^SCAN_SUBNETS=$|SCAN_SUBNETS=${lan} --interface=${iface}|" "$ENV"
  echo "  network scanner will scan ${lan}"
fi

# 3. Wazuh server (the detection engine), installed with Wazuh's own installer:
#    https://documentation.wazuh.com/current/quickstart.html
#    Skip with SKIP_WAZUH=1 if you already run a Wazuh server somewhere else.
WPASS=/root/lonsemonsy-wazuh-passwords.txt
if [ "${SKIP_WAZUH:-0}" = "1" ]; then
  echo "  wazuh: skipped (SKIP_WAZUH=1)"
elif [ -x /var/ossec/bin/wazuh-control ]; then
  echo "  wazuh: already installed"
else
  mem_gb=$(awk '/MemTotal/{printf "%d", $2/1024/1024+0.5}' /proc/meminfo)
  ignore=""
  if [ "$mem_gb" -lt 8 ]; then
    echo "  note: this machine has ${mem_gb} GB of memory. Wazuh wants 8 GB; it will run, but slowly."
    ignore="-i"   # tell Wazuh's installer to skip its own hardware check
  fi
  ver=$(grep '^WAZUH=' VERSIONS | cut -d= -f2 | cut -d. -f1,2)
  echo "  installing the Wazuh server ${ver} (about 10-15 minutes, log: /root/wazuh-install.log)..."
  ( cd /root && curl -sO "https://packages.wazuh.com/${ver}/wazuh-install.sh" && bash wazuh-install.sh -a $ignore ) \
    > /root/wazuh-install.log 2>&1 || { echo "  Wazuh install failed. See /root/wazuh-install.log"; exit 1; }
  tar -O -xf /root/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt > "$WPASS"
  chmod 600 "$WPASS"
  echo "  wazuh: installed (passwords saved in ${WPASS})"
fi

# Grafana reads alerts with Wazuh's built-in read-only user "readall".
if [ -f "$WPASS" ] && grep -qE '^WAZUH_INDEXER_PASSWORD=$' "$ENV"; then
  rp=$(grep -A1 "indexer_username: 'readall'" "$WPASS" | grep -oP "indexer_password: '\K[^']+")
  sed -i "s|^WAZUH_INDEXER_USER=.*|WAZUH_INDEXER_USER=readall|" "$ENV"
  sed -i "s|^WAZUH_INDEXER_PASSWORD=$|WAZUH_INDEXER_PASSWORD=${rp}|" "$ENV"
  echo "  grafana will read Wazuh alerts as the read-only user 'readall'"
fi

# 3. Firewall (Ubuntu's built-in ufw). Only the ports people and agents actually
#    use are open, and only to this network. Everything else is blocked.
#    Docker bypasses ufw, which is why InfluxDB is bound to 127.0.0.1 in
#    docker-compose.yml instead of being opened here.
if [ "${SKIP_FIREWALL:-0}" = "1" ]; then
  echo "  firewall: skipped (SKIP_FIREWALL=1)"
else
  ufw allow 22/tcp                                  # SSH first, so we can't lock ourselves out
  ufw allow from "$lan" to any port 3000 proto tcp  # Grafana dashboard
  ufw allow from "$lan" to any port 1514 proto tcp  # Wazuh agents send logs
  ufw allow from "$lan" to any port 1515 proto tcp  # Wazuh agents sign up
  ufw allow from "$lan" to any port 443 proto tcp   # Wazuh dashboard
  ufw allow from "$lan" to any port 20211 proto tcp # NetAlertX device list
  ufw default deny incoming
  ufw --force enable
  echo "  firewall: on"
fi

# 4. Start the stack.
echo "  starting the stack..."
( cd appliance && docker compose up -d )
ip=$(hostname -I | awk '{print $1}')

# 5. Connect Wazuh to Grafana. Grafana runs in Docker, so the Wazuh indexer also
#    listens on the Docker network's gateway (172.20.0.1, set in docker-compose.yml),
#    never on the LAN. At boot the indexer waits for Docker, which creates that address.
OSD=/etc/wazuh-indexer/opensearch.yml
if [ -f "$OSD" ] && ! grep -q '^network.bind_host:' "$OSD"; then
  sed -i -E 's/^\s*network\.host\s*:.*/# &/' "$OSD"
  printf 'network.bind_host: ["127.0.0.1", "172.20.0.1"]\nnetwork.publish_host: "127.0.0.1"\n' >> "$OSD"
  mkdir -p /etc/systemd/system/wazuh-indexer.service.d
  printf '[Unit]\nAfter=docker.service\nWants=docker.service\n' > /etc/systemd/system/wazuh-indexer.service.d/after-docker.conf
  systemctl daemon-reload
  systemctl restart wazuh-indexer
  echo "  wazuh: connected to grafana"
fi

# 6. Auto-block SSH brute force (wazuh/active-response.xml). The router and this
#    machine are never blocked.
OSC=/var/ossec/etc/ossec.conf
if [ -f "$OSC" ] && ! grep -q 'LoNSeMonSy auto-block' "$OSC"; then
  gw=$(ip -o -4 route show default | awk '{print $3; exit}')
  sed -i "0,/<white_list>127.0.0.1<\/white_list>/s//&\n    <white_list>${gw}<\/white_list>\n    <white_list>${ip}<\/white_list>/" "$OSC"
  { echo "  <!-- LoNSeMonSy auto-block -->"; sed -n '/^<active-response>/,/^<\/active-response>/p' wazuh/active-response.xml; } > /tmp/lons-ar.xml
  awk '!done && /<\/ossec_config>/ {while ((getline l < "/tmp/lons-ar.xml") > 0) print l; done=1} {print}' "$OSC" > "$OSC.new"
  cat "$OSC.new" > "$OSC" && rm -f "$OSC.new" /tmp/lons-ar.xml
  systemctl restart wazuh-manager
  echo "  wazuh: auto-block on (router ${gw} and this machine are never blocked)"
fi

# 7. Keep 90 days of alerts (wazuh/ism-policy.json), so the disk doesn't fill up.
if [ -f "$WPASS" ]; then
  ap=$(grep -A1 "indexer_username: 'admin'" "$WPASS" | grep -oP "indexer_password: '\K[^']+")
  for i in $(seq 1 30); do curl -sk -u "admin:${ap}" https://127.0.0.1:9200 -o /dev/null && break; sleep 5; done
  curl -sk -u "admin:${ap}" -X PUT https://127.0.0.1:9200/_plugins/_ism/policies/lonsemonsy-alerts-retention \
    -H 'Content-Type: application/json' --data-binary @wazuh/ism-policy.json -o /dev/null && echo "  wazuh: keeping 90 days of alerts"
fi

cat <<DONE

Done. Open Grafana:          http://${ip}:3000     user admin, password: GRAFANA_ADMIN_PASSWORD in ${ENV}
     Wazuh (advanced view):  https://${ip}         user admin, password in ${WPASS}

Next: install the Wazuh agent on each computer you want to protect (wazuh/README.md).
DONE
