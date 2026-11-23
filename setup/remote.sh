#!/usr/bin/env bash
# Remote access: open Grafana, NetAlertX and Wazuh from anywhere over HTTPS with Tailscale
# (tailscale.com, free for small teams). Nothing is opened to the internet: only devices
# signed in to your Tailscale can connect, and that sign-in (Google, Microsoft or GitHub)
# is where the 2-step verification happens.
#   lsmsy remote          is it on, which devices can connect, turn it on or off
#   setup/remote.sh on    turn it on (setup uses this; TS_AUTHKEY=tskey-... skips the sign-in link)
set -euo pipefail
cd "$(dirname "$0")/.."
source setup/steps/helpers.sh
[ "$(id -u)" = 0 ] || { echo "Run it with sudo:  sudo lsmsy remote"; exit 1; }

signed_in() { command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; }
serving()   { signed_in && tailscale serve status --json 2>/dev/null | jq -e 'has("TCP")' >/dev/null; }
https_on()  { [ "$(tailscale status --json | jq '.CertDomains // [] | length')" != 0 ]; }
name()      { tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")'; }
# qr TEXT: a QR code a phone can scan (the text is always printed too, for laptops).
qr() { if command -v qrencode >/dev/null; then qrencode -t ANSIUTF8 -m 2 "$1" | sed 's/^/  /'; fi; }

addresses() {
  local n; n=$(name)
  echo "    Grafana:    https://$n:8443"
  echo "    NetAlertX:  https://$n:8444"
  echo "    Wazuh:      https://$n:8445"
}

# The phones and laptops on your Tailscale (each one can open the dashboards).
devices() {
  tailscale status --json | jq -r '. as $s | [.Peer[]?] | sort_by(.HostName)[] |
    [.HostName, ($s.User[(.UserID|tostring)].LoginName // "?"),
     (if .Online then "online now" else "last seen " + (.LastSeen[:10]) end)] | @tsv' |
    column -t -s $'\t' | sed 's/^/    /'
}

turn_on() {
  if ! command -v tailscale >/dev/null; then
    run "Installing Tailscale" sh -c 'curl -fsSL https://tailscale.com/install.sh | sh'
  fi
  command -v qrencode >/dev/null || apt-get install -y -qq -o DPkg::Lock::Timeout=300 qrencode >/dev/null 2>&1 || true

  if ! signed_in; then
    if [ -n "${TS_AUTHKEY:-}" ]; then
      tailscale up --authkey="$TS_AUTHKEY" --hostname=lonsemonsy
    else
      echo
      echo "  Sign this server in to your Tailscale account (free at tailscale.com)."
      echo "  Use a Google, Microsoft or GitHub account with 2-step verification turned on:"
      echo "  that is the 2-step check for remote access. Also save that account's backup codes."
      echo "  Type the link below into a browser, or scan the code with your phone."
      echo
      tailscale up --qr --hostname=lonsemonsy --timeout=15m ||
        { echo "  Not signed in. Try again with: lsmsy remote"; return 1; }
    fi
  fi
  echo "  signed in to Tailscale as $(tailscale status --json | jq -r '.User[(.Self.UserID|tostring)].LoginName // "?"')"

  # The HTTPS addresses need one switch in Tailscale's settings.
  if ! https_on; then
    echo
    echo "  One more switch: HTTPS certificates. On any computer or phone, open"
    echo "    https://login.tailscale.com/admin/dns"
    echo "  and click Enable under HTTPS Certificates."
    qr https://login.tailscale.com/admin/dns
    echo "  Waiting for it... (press Enter to stop waiting)"
    until https_on; do
      if read -r -t 5 _; then echo "  Stopped. Run lsmsy remote once it's on."; return 1; fi
    done
  fi

  if command -v ufw >/dev/null; then ufw allow in on tailscale0 comment "Tailscale" >/dev/null; fi
  tailscale serve --bg --https=8443 http://localhost:3000 >/dev/null
  tailscale serve --bg --https=8444 http://localhost:20211 >/dev/null
  tailscale serve --bg --https=8445 https+insecure://localhost:443 >/dev/null
  local n; n=$(name)
  set_env GRAFANA_ROOT_URL "https://$n:8443"
  set_env NETALERTX_URL "https://$n:8444"
  set_env WAZUH_URL "https://$n:8445"
  (cd appliance && docker compose up -d grafana >/dev/null 2>&1)
  sudo -u "$owner" ./setup/check-update.sh >/dev/null 2>&1 || true   # Grafana's links use the new addresses
  setup/remote-check.sh >/dev/null 2>&1 || true

  echo
  echo "  Remote access is on. Open these on a phone or laptop signed in to the same Tailscale"
  echo "  account (install the Tailscale app first):"
  addresses
  echo "  Grafana on your phone:"
  qr "https://$n:8443"
  echo "  Recommended, at https://login.tailscale.com/admin/settings/device-management :"
  echo "    Device approval on, Key expiry 7 days (phones and laptops sign in again weekly),"
  echo "    and on the Machines page, Disable key expiry for this server. See setup/HELP.md."
}

turn_off() {
  tailscale serve reset >/dev/null 2>&1 || true
  tailscale logout >/dev/null 2>&1 || true      # this server leaves your Tailscale
  sed -i '/^NETALERTX_URL=/d; /^WAZUH_URL=/d' "$ENV"
  set_env GRAFANA_ROOT_URL "http://$(ip -o -4 route get 1.1.1.1 | grep -oP 'src \K[0-9.]+'):3000"
  (cd appliance && docker compose up -d grafana >/dev/null 2>&1)
  sudo -u "$owner" ./setup/check-update.sh >/dev/null 2>&1 || true
  setup/remote-check.sh >/dev/null 2>&1 || true
  echo "  Remote access is off. The dashboards only open from this network now."
}

if [ "${1:-}" = on ]; then turn_on; exit; fi

if serving; then
  echo "  Remote access is on (Tailscale account $(tailscale status --json | jq -r '.User[(.Self.UserID|tostring)].LoginName // "?"')):"
  addresses
  echo
  echo "  Devices that can open them:"
  devices
  echo "  Remove one at https://login.tailscale.com/admin/machines"
  echo
  if confirm "Remote access" "Turn remote access off? [y/N]: " N; then turn_off; fi
else
  echo "  Remote access is off: the dashboards only open from this network."
  echo "  Turn it on to open them from your phone or laptop anywhere, with a 2-step sign-in."
  if confirm "Remote access" "Turn it on? [y/N]: " N; then turn_on; fi
fi
