#!/usr/bin/env bash
# Remote access: open Grafana, NetAlertX and Wazuh from anywhere over HTTPS with Tailscale
# (tailscale.com, free for small teams). Nothing is opened to the internet: only devices
# signed in to your Tailscale can connect. The 2-step check is the one on the Google,
# Microsoft or GitHub account you sign in with: turn it on there, Tailscale doesn't force it.
#   lsmsy remote          is it on, which devices can connect, turn it on or off
#   lsmsy remote ip on    open the dashboards by IP address too, if Tailscale isn't working (ip off: undo)
#   setup/remote.sh on    turn it on (setup uses this; TS_AUTHKEY=tskey-... skips the sign-in link)
set -euo pipefail
cd "$(dirname "$0")/.."
source setup/steps/helpers.sh
[ "$(id -u)" = 0 ] || { echo "Run it with sudo:  sudo lsmsy remote"; exit 1; }

signed_in() { command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; }
serving()   { signed_in && tailscale serve status --json 2>/dev/null | jq -e 'has("TCP")' >/dev/null; }
https_on()  { [ "$(tailscale status --json | jq '.CertDomains // [] | length')" != 0 ]; }
name()      { tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")'; }
iface=$(ip -o -4 route show default | awk 'NR==1{print $5}')
lan=$(ip -o -4 route show dev "$iface" scope link | awk 'NR==1{print $1}')
account()   { tailscale status --json | jq -r '.User[(.Self.UserID|tostring)].LoginName // "?"' | tr '[:upper:]' '[:lower:]'; }
firewall_on() { command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; }

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

  # The Gmail account the alarms are sent from: signing in with it means 2-step is on
  # (Google only gives out app passwords then).
  local sender; sender=$(get SMTP_USER)
  if [ "$(get SMTP_ENABLED)" != true ]; then sender=""; fi
  while ! signed_in; do
    if [ -n "${TS_AUTHKEY:-}" ]; then
      tailscale up --authkey="$TS_AUTHKEY" --hostname=lonsemonsy
    else
      echo
      if [ -n "$sender" ]; then
        echo "  Sign this server in to Tailscale with Google, as $sender"
        echo "  (the account the alarm emails are sent from). Its app password only works while"
        echo "  2-step verification is on, so that account always has it."
      else
        echo "  Sign this server in to Tailscale with a Google, Microsoft or GitHub account."
        echo "  Turn on 2-step verification for that account FIRST. Nothing forces it: without it,"
        echo "  its password alone gets someone in. For Google: myaccount.google.com/security"
      fi
      echo "  Type the link below into a browser, or scan the code with your phone."
      echo
      small=()   # the same size as the other codes, if this Tailscale can do that
      if tailscale up --help 2>&1 | grep -q -- --qr-format; then small=(--qr-format=small); fi
      tailscale up --qr "${small[@]}" --hostname=lonsemonsy --timeout=15m ||
        { echo "  Not signed in. Try again with: lsmsy remote"; return 1; }
      if [ -n "$sender" ] && [ "$(account)" != "${sender,,}" ]; then
        echo "  That was $(account), not $sender. 2-step may not be on for it."
        if confirm "Remote access" "Sign in again as $sender? [Y/n] > " Y; then tailscale logout; fi
      fi
    fi
  done
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
  mkdir -p /var/lib/lonsemonsy && touch /var/lib/lonsemonsy/remote-on   # when it was turned on
  setup/remote-check.sh >/dev/null 2>&1 || true

  echo
  echo "  Remote access is on. Open these on a phone or laptop signed in to the same Tailscale"
  echo "  account (install the Tailscale app first):"
  addresses
  echo
  echo "  Do these two now, at login.tailscale.com (they can't be set from here):"
  echo "    1. Machines > this server's ... menu > Disable key expiry, so it stays signed in."
  echo "    2. Settings > Device management > Key expiry: change 180 days to 1 day. Phones and"
  echo "       laptops then sign in again (with 2-step) every day."
  if firewall_on && [ "$(get IP_ACCESS)" != off ] && [ "$(get IP_ACCESS_KEEP)" != 1 ]; then
    echo
    echo "  The dashboards can now open only over Tailscale, not by IP address, so nobody on this"
    echo "  network skips the sign-in. If Tailscale stops working, SSH in from this network (or use"
    echo "  this screen) and run: sudo lsmsy remote ip on"
    ip_access off "$lan" "$iface"
  fi
}

turn_off() {
  if firewall_on; then ip_access on "$lan" "$iface"; fi   # first, so there's always a way in
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
if [ "${1:-}" = ip ]; then
  firewall_on || { echo "  The firewall is off, so nothing is blocked."; exit 1; }
  case "${2:-}" in
    on)  ip_access on "$lan" "$iface"; set_env IP_ACCESS_KEEP 1
         echo "  The dashboards also open by IP address, from this network (not recommended:"
         echo "  it skips the 2-step sign-in). To undo: sudo lsmsy remote ip off" ;;
    off) serving || { echo "  Remote access isn't on, so this would lock you out. Nothing changed."; exit 1; }
         ip_access off "$lan" "$iface"; set_env IP_ACCESS_KEEP 0
         echo "  The dashboards only open over Tailscale now." ;;
    *)   echo "  usage: lsmsy remote ip on   (or off)"; exit 1 ;;
  esac
  exit
fi

if serving; then
  echo "  Remote access is on (Tailscale account $(tailscale status --json | jq -r '.User[(.Self.UserID|tostring)].LoginName // "?"')):"
  addresses
  if [ "$(get IP_ACCESS)" = off ]; then echo "  By IP address: off. If Tailscale isn't working: sudo lsmsy remote ip on"
  else echo "  By IP address: on, from this network (not recommended). To turn it off: sudo lsmsy remote ip off"; fi
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
