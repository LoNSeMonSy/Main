# shellcheck shell=bash
# Step 1: the settings file, and the small tools the next steps need.

if [ ! -f "$ENV" ]; then
  cp appliance/.env.example "$ENV"
  chown "$owner" "$ENV"
  chmod 600 "$ENV"                    # only its owner can read it (it holds passwords)
  echo "  created $ENV"
fi

apt-get update -qq
need curl curl
need openssl openssl
need jq jq
if [ "${SKIP_FIREWALL:-0}" != 1 ]; then need ufw ufw; fi

# Wazuh needs about 8 GB of memory. With less and no swap, add a 4 GB swap file so it
# slows down instead of crashing.
if [ "$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)" -lt 7500 ] && [ -z "$(swapon --show --noheadings)" ]; then
  fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap -q /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "  added a 4 GB swap file (this machine has under 8 GB of memory)"
fi

# This machine's network card, IP address, router and network, e.g. eth0,
# 192.168.1.50, 192.168.1.1 and 192.168.1.0/24.
iface=$(ip -o -4 route show default | awk 'NR==1{print $5}')
cidr=$(ip -o -4 addr show dev "$iface" | awk 'NR==1{print $4}')
ip=${cidr%/*}
gw=$(ip -o -4 route show default | awk 'NR==1{print $3}')
lan=$(ip -o -4 route show dev "$iface" scope link | awk 'NR==1{print $1}')
if [ -z "$ip" ] || [ -z "$lan" ]; then
  echo "  Couldn't find this machine's network. Check that it's connected, then run setup again."
  exit 1
fi
