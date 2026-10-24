#!/usr/bin/env bash
# LoNSeMonSy setup. Creates appliance/.env, fills in passwords and your network,
# installs what's missing, turns on the firewall, then starts everything.
#
#   sudo ./setup/setup.sh                    normal install (asks one optional question)
#   sudo SKIP_FIREWALL=1 ./setup/setup.sh    same, but leave the firewall alone
#   sudo SKIP_QUESTIONS=1 ./setup/setup.sh   don't ask anything
#   sudo STATIC_IP=1 ./setup/setup.sh        keep this machine's address fixed without asking
set -euo pipefail              # stop at the first error instead of carrying on
cd "$(dirname "$0")/.."        # work from the main folder, wherever this was started from
ENV="appliance/.env"           # the settings file

echo "LoNSeMonSy setup"
[ "$(id -u)" = "0" ] || { echo "  Run with sudo:  sudo ./setup/setup.sh"; exit 1; }
owner=$(stat -c %U .)          # the person who downloaded this folder

# Settings file: made from the template the first time. Only its owner can read it.
if [ ! -f "$ENV" ]; then
  cp appliance/.env.example "$ENV"
  chown "$owner" "$ENV"; chmod 600 "$ENV"
  echo "  created $ENV"
fi

# get KEY: print one setting from the settings file (blank if it isn't there).
get() { grep -E "^$1=" "$ENV" | cut -d= -f2- || true; }

# set_env KEY VALUE: change one setting, or add it if it's missing.
# Passwords can contain characters like | & / that confuse sed, so awk does the
# replacing and gets KEY and VALUE through the environment, where nothing is special.
set_env() {
  K="$1" V="$2" awk '
    BEGIN { key = ENVIRON["K"]; value = ENVIRON["V"] }
    index($0, key "=") == 1 { print key "=" value; found = 1; next }  # the line to change
    { print }                                                          # every other line
    END { if (!found) print key "=" value }                            # missing: add it
  ' "$ENV" > "$ENV.tmp"
  cat "$ENV.tmp" > "$ENV" && rm -f "$ENV.tmp"   # cat keeps the file's owner and permissions
}

# Shows which part of the Wazuh install is running, plus the time so far. Wazuh's
# installer prints a line as each part starts, so this just watches its log for them.
wazuh_progress() {
  local pid=$1 log=/root/wazuh-install.log start=$SECONDS shown="" now step t
  local steps=(
    "Configuration files|[1/5] making the security certificates"
    "Starting Wazuh indexer installation|[2/5] installing the indexer (stores the alerts)"
    "Starting the Wazuh manager installation|[3/5] installing the manager (the detection engine)"
    "Starting Filebeat installation|[4/5] connecting the manager to the indexer"
    "Starting Wazuh dashboard installation|[5/5] installing the Wazuh dashboard"
  )
  while kill -0 "$pid" 2>/dev/null; do                  # until the installer finishes
    now="[0/5] getting ready (checks and downloads)"
    for step in "${steps[@]}"; do
      grep -q "${step%%|*}" "$log" 2>/dev/null && now="${step#*|}"
    done
    t=$(( SECONDS - start ))
    if [ "$now" != "$shown" ]; then                     # a new part started
      [ -n "$shown" ] && [ -t 1 ] && echo               # keep the last one on its own line
      [ -t 1 ] || echo "    $now"
      shown=$now
    fi
    [ -t 1 ] && printf '\r    %s  %d:%02d ' "$now" $(( t / 60 )) $(( t % 60 ))
    sleep 5
  done
  [ -t 1 ] && echo
  return 0
}

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
# The questions come first, so the rest can run on its own. Both are skipped when
# nobody is at the keyboard, or with SKIP_QUESTIONS=1.
ask=0; [ -t 0 ] && [ "${SKIP_QUESTIONS:-0}" != "1" ] && ask=1

# Question 1: keep this machine's address fixed? Every protected computer sends its
# alerts to this address, so if the router hands out a new one, they stop reporting.
iface=$(ip -o -4 route show default | awk '{print $5; exit}')
cidr=$(ip -o -4 addr show dev "$iface" | awk '{print $4; exit}')         # e.g. 192.168.1.50/24
gw=$(ip -o -4 route show default | awk '{print $3; exit}')
NETPLAN=/etc/netplan/60-lonsemonsy-static.yaml
if ip -o -4 addr show dev "$iface" | grep -q dynamic && [ ! -f "$NETPLAN" ]; then  # address came from DHCP
  fix="${STATIC_IP:-0}"
  if [ "$fix" != "1" ] && [ "$ask" = 1 ]; then
    echo
    echo "  This machine got its address (${cidr%/*}) from the router (DHCP), so it could change."
    echo "    1) Keep ${cidr%/*} fixed on this machine"
    echo "    2) Leave it. I've reserved it on my router, or will (best)"
    read -r -p "  Choose 1 or 2 [2]: " a
    [ "$a" = "1" ] && fix=1
  fi
  if [ "$fix" = "1" ]; then
    # DNS servers from the current lease (IPv4 only), or the router if there are none.
    dns=$(resolvectl dns "$iface" 2>/dev/null | cut -d: -f2- | tr ' ' '\n' | grep -E '^[0-9.]+$' | paste -sd' ' || true)
    dns=${dns:-$gw}
    cat > "$NETPLAN" <<NET
# Written by LoNSeMonSy setup: keeps this machine's address fixed.
# To go back to DHCP: sudo rm $NETPLAN && sudo netplan apply
network:
  version: 2
  ethernets:
    ${iface}:
      dhcp4: false
      addresses: [${cidr}]
      routes:
        - to: default
          via: ${gw}
      nameservers:
        addresses: [${dns// /, }]
NET
    chmod 600 "$NETPLAN"
    netplan generate && netplan apply
    echo "  address: ${cidr%/*} is now fixed (also reserve it on your router so nothing else gets it)"
  fi
fi

# Question 2 (optional): where to email alarms. They're sent from a Gmail account, which
# needs an app password (a separate password Google makes for one program, not the real one).
if [ "$ask" = 1 ] && [ -z "$(get ALERT_EMAIL_TO)" ]; then
  echo
  echo "  Email alarms (optional). They're sent from a Gmail account: use a separate one"
  echo "  made just for this, not your own, because its app password is stored here."
  read -r -p "  Send alarms TO which address? (Enter to skip): " to
  if [ -n "$to" ]; then
    read -r -p "  Send them FROM which Gmail account? (e.g. yourcompany.alarms@gmail.com): " from
  fi
  if [ -n "$to" ] && [ -n "$from" ]; then
    echo "  That account needs an app password, not its normal password. Make one at"
    echo "  https://myaccount.google.com/apppasswords (needs 2-Step Verification turned on)."
    read -r -s -p "  App password (hidden): " apw; echo
    apw=${apw// /}   # Google shows it with spaces; they aren't part of it
    set_env ALERT_EMAIL_TO "$to"
    set_env SMTP_ENABLED true
    set_env SMTP_USER "$from"
    set_env SMTP_FROM_ADDRESS "$from"
    set_env SMTP_PASSWORD "$apw"
    echo "  email alarms: on (sent from $from to $to)"
  else
    echo "  email alarms: skipped (add them later in $ENV)"
  fi
  echo
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

# Time zone: use the machine's own, unless someone already picked one.
tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
[ -n "$tz" ] || tz=$(cat /etc/timezone 2>/dev/null || true)
tz=${tz:-UTC}
cur=$(get TZ)
if [ -z "$cur" ] || [ "$cur" = "America/New_York" ]; then
  [ "$cur" = "$tz" ] || { set_env TZ "$tz"; echo "  time zone: $tz"; }
fi

# 2. Work out this machine's network from its default route, so nothing about the
#    customer's site is hardcoded. Example result: 192.168.1.0/24 on eth0.
iface=$(ip -o -4 route show default | awk '{print $5; exit}')
lan=$(ip -o -4 route show dev "$iface" scope link | awk '{print $1; exit}')
ip=$(ip -o -4 addr show dev "$iface" | awk '{split($4, a, "/"); print a[1]; exit}')
[ -n "$lan" ] && [ -n "$ip" ] || { echo "  Couldn't find this machine's network (no default route?). Fix networking and run this again."; exit 1; }
echo "  this machine's network: ${lan} on ${iface}"

if grep -qE '^SCAN_SUBNETS=$' "$ENV"; then
  sed -i "s|^SCAN_SUBNETS=$|SCAN_SUBNETS=${lan} --interface=${iface}|" "$ENV"
  echo "  network scanner will scan ${lan}"
fi

# 3. Wazuh server (the detection engine), installed with Wazuh's own installer:
#    https://documentation.wazuh.com/current/quickstart.html
#    Skip with SKIP_WAZUH=1 if you already run a Wazuh server somewhere else.
# Wazuh's passwords live in the bundle its installer leaves (/root/wazuh-install-files.tar,
# only root can read it). Setup copies them to a temporary file while it needs them and
# deletes it at the end, so no passwords file is left lying around.
BUNDLE=/root/wazuh-install-files.tar
WPASS=$(mktemp); chmod 600 "$WPASS"
trap 'rm -f "$WPASS"' EXIT
rm -f /root/lonsemonsy-wazuh-passwords.txt          # left behind by older versions of setup
wazuh_passwords() { [ -f "$BUNDLE" ] && tar -O -xf "$BUNDLE" wazuh-install-files/wazuh-passwords.txt > "$WPASS"; }
if [ "${SKIP_WAZUH:-0}" = "1" ]; then
  echo "  wazuh: skipped (SKIP_WAZUH=1)"
elif [ -x /var/ossec/bin/wazuh-control ]; then
  echo "  wazuh: already installed"
  wazuh_passwords || echo "  wazuh: couldn't find its install bundle ($BUNDLE), so Grafana can't be connected to it automatically"
else
  mem_gb=$(awk '/MemTotal/{printf "%d", $2/1024/1024+0.5}' /proc/meminfo)
  ignore=""
  if [ "$mem_gb" -lt 8 ]; then
    echo "  note: this machine has ${mem_gb} GB of memory. Wazuh wants 8 GB; it will run, but slowly."
    ignore="-i"   # tell Wazuh's installer to skip its own hardware check
  fi
  ver=$(grep '^WAZUH=' VERSIONS | cut -d= -f2 | cut -d. -f1,2)
  echo "  installing the Wazuh server ${ver} (about 15-20 minutes, log: /root/wazuh-install.log)..."
  curl -fsSo /root/wazuh-install.sh "https://packages.wazuh.com/${ver}/wazuh-install.sh" \
    || { echo "  Could not download Wazuh's installer. Check the internet connection."; exit 1; }
  ( cd /root && exec bash wazuh-install.sh -a $ignore ) > /root/wazuh-install.log 2>&1 &
  wazuh_pid=$!                                          # it runs in the background...
  trap 'kill "$wazuh_pid" 2>/dev/null; echo; echo "  stopped"; exit 1' INT TERM   # Ctrl+C stops it too
  wazuh_progress "$wazuh_pid"                           # ...while this shows its progress
  wait "$wazuh_pid" || { echo "  Wazuh install failed. See /root/wazuh-install.log"; exit 1; }
  trap - INT TERM
  wazuh_passwords
  echo "  wazuh: installed"
fi

# Grafana reads alerts with Wazuh's built-in read-only user "readall".
if [ -s "$WPASS" ] && grep -qE '^WAZUH_INDEXER_PASSWORD=$' "$ENV"; then
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
  # Grafana (in Docker) reads alerts from the Wazuh indexer on the Docker network's
  # gateway. That address isn't reachable from the LAN.
  ufw allow from 172.20.0.0/24 to 172.20.0.1 port 9200 proto tcp
  ufw default deny incoming
  ufw --force enable
  echo "  firewall: on"
fi

# 4. Start the stack.
echo "  starting the stack..."
( cd appliance && docker compose up -d )

# 5. Connect Wazuh to Grafana. Grafana runs in Docker, so the Wazuh indexer also
#    listens on the Docker network's gateway (172.20.0.1, set in docker-compose.yml),
#    never on the LAN. At boot the indexer waits for Docker, which creates that address.
OSD=/etc/wazuh-indexer/opensearch.yml
if [ -f "$OSD" ] && ! grep -q '^network.bind_host:' "$OSD"; then
  sed -i -E 's/^\s*network\.host\s*:.*/# &/' "$OSD"
  printf 'network.bind_host: ["127.0.0.1", "172.20.0.1"]\nnetwork.publish_host: "127.0.0.1"\n' >> "$OSD"
  mkdir -p /etc/systemd/system/wazuh-indexer.service.d
  printf '[Unit]\nAfter=docker.service\nWants=docker.service\n\n[Service]\nTimeoutStartSec=600\n' > /etc/systemd/system/wazuh-indexer.service.d/lonsemonsy.conf
  # Wazuh's manager only gets 45 s to start. At boot, with everything starting at
  # once, that's too short: it gets marked failed while still running.
  mkdir -p /etc/systemd/system/wazuh-manager.service.d
  printf '[Service]\nTimeoutSec=300\n' > /etc/systemd/system/wazuh-manager.service.d/lonsemonsy.conf
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

# Also let Wazuh watch this machine's Docker containers (started, stopped, crashed).
# Shows in the Wazuh dashboard under Docker.
if [ -f "$OSC" ] && ! grep -q 'docker-listener' "$OSC"; then
  printf '  <wodle name="docker-listener">\n    <disabled>no</disabled>\n  </wodle>\n' > /tmp/lons-docker.xml
  awk '!done && /<\/ossec_config>/ {while ((getline l < "/tmp/lons-docker.xml") > 0) print l; done=1} {print}' "$OSC" > "$OSC.new"
  cat "$OSC.new" > "$OSC" && rm -f "$OSC.new" /tmp/lons-docker.xml
  # Our shipped rules (ignore routine container health checks, etc.)
  install -o wazuh -g wazuh -m 660 wazuh/lonsemonsy_rules.xml /var/ossec/etc/rules/lonsemonsy_rules.xml
  systemctl restart wazuh-manager
  echo "  wazuh: watching Docker containers"
fi

# 7. Keep 90 days of alerts (wazuh/ism-policy.json), so the disk doesn't fill up.
if [ -s "$WPASS" ]; then
  ap=$(grep -A1 "indexer_username: 'admin'" "$WPASS" | grep -oP "indexer_password: '\K[^']+")
  for i in $(seq 1 30); do curl -sk -u "admin:${ap}" https://127.0.0.1:9200 -o /dev/null && break; sleep 5; done
  curl -sk -u "admin:${ap}" -X PUT https://127.0.0.1:9200/_plugins/_ism/policies/lonsemonsy-alerts-retention \
    -H 'Content-Type: application/json' --data-binary @wazuh/ism-policy.json -o /dev/null && echo "  wazuh: keeping 90 days of alerts"
fi

# 8. Check for LoNSeMonSy updates once a day, so Grafana can show an update banner.
#    Runs as the folder's owner, who has access to GitHub.
cat > /etc/systemd/system/lonsemonsy-update-check.service <<UNIT
[Unit]
Description=Check for LoNSeMonSy updates
After=network-online.target docker.service

[Service]
Type=oneshot
User=${owner}
ExecStart=$(pwd)/setup/check-update.sh
UNIT
cat > /etc/systemd/system/lonsemonsy-update-check.timer <<'UNIT'
[Unit]
Description=Check for LoNSeMonSy updates every day

[Timer]
OnBootSec=5min
OnUnitActiveSec=1d

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now lonsemonsy-update-check.timer >/dev/null 2>&1
systemctl start lonsemonsy-update-check.service 2>/dev/null \
  && echo "  update check: on (daily)" \
  || echo "  update check: on, but it couldn't reach GitHub yet (the banner will say so)"

gpw=$(get GRAFANA_ADMIN_PASSWORD)
echo
echo "Done."
echo "  Grafana (main dashboard):  http://${ip}:3000   user admin, password ${gpw}"
if [ -d /var/ossec ]; then
  wpw=$(grep -A1 "indexer_username: 'admin'" "$WPASS" 2>/dev/null | grep -oP "indexer_password: '\K[^']+" || true)
  echo "  Wazuh (advanced view):     https://${ip}       user admin, password ${wpw:-see below}"
  wver=$(grep '^WAZUH=' VERSIONS | cut -d= -f2)
  cat <<AGENTS

Protect a computer: paste one of these on it (change pc-name to its name).
  Windows, in PowerShell as administrator:
    Invoke-WebRequest -Uri https://packages.wazuh.com/4.x/windows/wazuh-agent-${wver}-1.msi -OutFile \$env:tmp\\wazuh-agent.msi; msiexec.exe /i \$env:tmp\\wazuh-agent.msi /q WAZUH_MANAGER='${ip}' WAZUH_AGENT_NAME='pc-name'; Start-Sleep 20; NET START WazuhSvc
  Linux (copy wazuh/enroll-host.sh to it first):
    sudo WAZUH_MANAGER=${ip} bash enroll-host.sh pc-name
  Or in the Wazuh dashboard: Agents > Deploy new agent.
AGENTS
fi
cat <<NEXT

Next steps (run these in this folder):
  See the passwords again:      sudo ./setup/show-passwords.sh
  Check the firewall:           sudo ufw status verbose
  Check everything is running:  docker ps
                                systemctl is-active wazuh-manager wazuh-indexer wazuh-dashboard
  Update LoNSeMonSy later:      sudo ./setup/update.sh
NEXT
