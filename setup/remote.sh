#!/usr/bin/env bash
# Optional: open Grafana, NetAlertX and Wazuh from anywhere over HTTPS with Tailscale
# (tailscale.com, free for small teams). Nothing is opened to the internet: only devices
# signed in to your Tailscale account can connect, and that sign-in (Google, Microsoft
# or GitHub) brings its own 2-step verification.
#   sudo ./setup/remote.sh     (or: lsmsy remote)
set -euo pipefail
cd "$(dirname "$0")/.."
source setup/steps/helpers.sh

if ! command -v tailscale >/dev/null; then
  echo "  installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh >/dev/null
fi
if ! tailscale status >/dev/null 2>&1; then
  key=${TS_AUTHKEY:-}
  if [ -z "$key" ]; then
    echo "  Make a key: https://login.tailscale.com/admin/settings/keys > Generate auth key"
    read -r -s -p "  Tailscale auth key: " key; echo
  fi
  if [ -z "$key" ]; then echo "  remote access: skipped"; exit 0; fi
  tailscale up --authkey="$key" --hostname=lonsemonsy
fi
if command -v ufw >/dev/null; then ufw allow in on tailscale0 >/dev/null; fi

# HTTPS addresses with a real certificate. Tailscale only gives one when "HTTPS Certificates" is on.
if [ "$(tailscale status --json | jq '.CertDomains // [] | length')" = 0 ]; then
  echo "  Turn on HTTPS first: https://login.tailscale.com/admin/dns > HTTPS Certificates > Enable."
  echo "  Then run: lsmsy remote"
  exit 1
fi
tailscale serve --bg --https=8443 http://localhost:3000 >/dev/null
tailscale serve --bg --https=8444 http://localhost:20211 >/dev/null
tailscale serve --bg --https=8445 https+insecure://localhost:443 >/dev/null
name=$(tailscale status --json | jq -r .Self.DNSName); name=${name%.}

set_env GRAFANA_ROOT_URL "https://$name:8443"
set_env NETALERTX_URL "https://$name:8444"
set_env WAZUH_URL "https://$name:8445"
(cd appliance && docker compose up -d grafana >/dev/null 2>&1)
sudo -u "$owner" ./setup/check-update.sh >/dev/null 2>&1 || true   # Grafana's links use the new addresses

echo "  Remote access is on. From any device signed in to your Tailscale:"
echo "    Grafana:    https://$name:8443"
echo "    NetAlertX:  https://$name:8444"
echo "    Wazuh:      https://$name:8445"
echo "  In Tailscale's admin page, also turn on Device approval, set Key expiry to 7 days and"
echo "  disable key expiry for this server (see setup/HELP.md, Remote access)."
