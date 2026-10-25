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
if [ "${SKIP_FIREWALL:-0}" != 1 ]; then need ufw ufw; fi

# This machine's network card, IP address, router and network, e.g. eth0,
# 192.168.1.50, 192.168.1.1 and 192.168.1.0/24.
iface=$(ip -o -4 route show default | awk '{print $5; exit}')
cidr=$(ip -o -4 addr show dev "$iface" | awk '{print $4; exit}')
ip=${cidr%/*}
gw=$(ip -o -4 route show default | awk '{print $3; exit}')
lan=$(ip -o -4 route show dev "$iface" scope link | awk '{print $1; exit}')
if [ -z "$ip" ] || [ -z "$lan" ]; then
  echo "  Couldn't find this machine's network. Check that it's connected, then run setup again."
  exit 1
fi
