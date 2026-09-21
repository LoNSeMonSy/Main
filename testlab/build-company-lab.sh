#!/usr/bin/env bash
#
# Build a minimal "company" test network as LXC containers, all monitored by the
# LoNSeMonSy appliance (Wazuh manager). Replicates a small business: a server, a
# workstation, and an external attacker.
#
#   RUN THIS ON THE PROXMOX HOST (mainserver), as root:  bash build-company-lab.sh
#   It needs `pct`, which only exists on the host — not inside the appliance VM.
#
# Safe to re-run: it skips containers that already exist. It attaches NICs to the
# existing vmbr0 bridge but NEVER reconfigures the bridge itself.
#
set -euo pipefail

MANAGER_IP="192.168.12.112"     # the appliance (Wazuh manager). Change if it moves.
TEMPLATE="local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
STORAGE="local"                 # local-lvm is full; local has ~23G
BRIDGE="vmbr0"                  # same LAN as the appliance
WAZUH_MAJOR="4.x"               # agent track; matches the 4.x manager
ROOTPW="lab-$(openssl rand -hex 6)"   # one shared lab password, printed at the end

# vmid : hostname : memory(MB) : role(agent|attacker)
LAB=(
  "8101:corp-fileserver:512:agent"
  "8102:corp-workstation:384:agent"
  "8103:attacker:384:attacker"
)

say(){ printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }

install_agent() {   # $1 = vmid
  pct exec "$1" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq curl gnupg apt-transport-https >/dev/null
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
    echo 'deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/${WAZUH_MAJOR}/apt/ stable main' > /etc/apt/sources.list.d/wazuh.list
    apt-get update -qq
    WAZUH_MANAGER='${MANAGER_IP}' apt-get install -y -qq wazuh-agent >/dev/null
    systemctl daemon-reload && systemctl enable --now wazuh-agent
    echo '    agent installed, pointing at ${MANAGER_IP}'
  "
}

install_attacker() {   # $1 = vmid
  pct exec "$1" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq nmap hydra sshpass >/dev/null
    echo '    attack tools installed (nmap, hydra, sshpass)'
  "
}

for entry in "${LAB[@]}"; do
  IFS=: read -r vmid host mem role <<< "$entry"
  say "[$vmid] $host ($role, ${mem}MB)"
  if pct status "$vmid" >/dev/null 2>&1; then
    echo "    already exists, skipping create"
  else
    pct create "$vmid" "$TEMPLATE" \
      --hostname "$host" --memory "$mem" --cores 1 \
      --rootfs "${STORAGE}:4" \
      --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp" \
      --password "$ROOTPW" --unprivileged 1 --features nesting=1 \
      --onboot 0 --start 1
    echo "    created + started"
    sleep 8   # let DHCP + sshd come up
  fi
  case "$role" in
    agent)    install_agent "$vmid" ;;
    attacker) install_attacker "$vmid" ;;
  esac
done

say "Done. The company lab is up and reporting to the appliance."
cat <<DONE

  Lab root password (all containers): ${ROOTPW}
  Save it somewhere; it is not stored anywhere else.

  Check agents registered (on the appliance):
    sudo /var/ossec/bin/agent_control -l

  Run the demo attack (from the attacker container):
    pct exec 8103 -- bash -c '
      TARGET=\$(getent hosts corp-fileserver | awk "{print \\\$1}")
      # brute force SSH — Wazuh should fire 5710/5712 for corp-fileserver
      hydra -l root -P <(printf "bad1\nbad2\nbad3\nbad4\nbad5\nbad6\nbad7\nbad8\n") \
        ssh://\$TARGET -t 4 || true
      nmap -sS \$TARGET      # port scan (needs network visibility to be *detected*)
    '

  Then watch it in Grafana (Wazuh datasource) or the Wazuh dashboard.

  Tear the lab down when done (frees RAM/disk):
    for id in 8101 8102 8103; do pct stop \$id; pct destroy \$id; done
DONE
