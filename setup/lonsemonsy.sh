#!/usr/bin/env bash
# The "lsmsy" command (setup links it to /usr/local/bin, so it works anywhere).
#   lsmsy             addresses, version and commands
#   lsmsy password    set a new Grafana, Wazuh or NetAlertX password
#   lsmsy status      is everything running?
#   lsmsy firewall    which ports are open
#   lsmsy update      update to the newest version
#   lsmsy backup      make a backup now            lsmsy restore   put it back
#   lsmsy users       Grafana accounts             lsmsy adduser / lsmsy deluser
#   lsmsy test        send a fake alarm      lsmsy report   the weekly summary
#   lsmsy remote      HTTPS access from anywhere (Tailscale)
dir=$(dirname "$(dirname "$(readlink -f "$0")")")   # the LoNSeMonSy folder
# Grafana's own user API, logged in as admin.
gapi() { curl -s -m 15 -H 'Content-Type: application/json' \
  -u "admin:$(sudo grep -E '^GRAFANA_ADMIN_PASSWORD=' "$dir/appliance/.env" | cut -d= -f2-)" "$@"; }
G=http://localhost:3000

case "${1:-}" in
  password)  sudo "$dir/setup/change-password.sh" "${2:-}" ;;
  passwords) echo "  Passwords are shown once, at the end of setup. To set a new one: lsmsy password grafana (or wazuh, netalertx)" ;;
  update)    sudo "$dir/setup/update.sh" ;;
  backup)    sudo "$dir/setup/backup.sh" "${2:-}" ;;
  restore)   sudo "$dir/setup/restore.sh" "${2:-}" ;;
  remote)    sudo "$dir/setup/remote.sh" ;;
  report)    sudo "$dir/setup/weekly-report.sh" print ;;
  firewall)  sudo ufw status verbose ;;
  users)
    gapi $G/api/org/users | jq -r '.[] | "  \(.login)\t\(.role)"' | column -t ;;
  adduser)
    name=${2:-}; role=${3:-viewer}
    [ -n "$name" ] || { echo "  usage: lsmsy adduser <name> [viewer|editor|admin]"; exit 1; }
    case "${role,,}" in viewer) role=Viewer ;; editor) role=Editor ;; admin) role=Admin ;;
      *) echo "  role must be viewer, editor or admin"; exit 1 ;; esac
    pw=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-14)
    id=$(gapi -X POST $G/api/admin/users -d "{\"name\":\"$name\",\"login\":\"$name\",\"password\":\"$pw\"}" | jq -r '.id // empty')
    [ -n "$id" ] || { echo "  could not add $name (does it already exist?)"; exit 1; }
    gapi -X PATCH $G/api/org/users/"$id" -d "{\"role\":\"$role\"}" >/dev/null
    echo "  added $name as $role"
    echo "  password: $pw   (they can change it in Grafana under Profile)" ;;
  deluser)
    name=${2:-}
    [ -n "$name" ] || { echo "  usage: lsmsy deluser <name>"; exit 1; }
    [ "$name" != admin ] || { echo "  the admin account can't be removed"; exit 1; }
    id=$(gapi "$G/api/users/lookup?loginOrEmail=$name" | jq -r '.id // empty')
    [ -n "$id" ] || { echo "  no account called $name"; exit 1; }
    gapi -X DELETE $G/api/admin/users/"$id" | jq -r '"  " + .message' ;;
  status)
    sudo docker ps --format '{{.Names}}: {{.Status}}' | sed 's/^/  /'
    for s in wazuh-manager wazuh-indexer wazuh-dashboard suricata; do
      echo "  $s: $(systemctl is-active "$s")"
    done ;;
  test)
    # 10 fake failed SSH logins from a documentation-only address (192.0.2.99).
    # Wazuh sees an SSH brute force, Grafana raises an alarm and emails it.
    for i in $(seq 10); do
      logger -p auth.notice -t sshd --id=$$ "Failed password for invalid user lsmsy-test from 192.0.2.99 port $((40000 + i)) ssh2"
      sleep 0.3
    done
    echo "  test alarm sent: 10 fake failed logins from 192.0.2.99"
    echo "  it shows on the Grafana Alarms page (and by email, if set up) in about a minute."
    echo "  192.0.2.99 also gets auto-blocked for 10 minutes; that is part of the test." ;;
  "")
    ip=$(ip -o -4 route get 1.1.1.1 | grep -oP 'src \K[0-9.]+')
    branch=$(git -c safe.directory="$dir" -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    case "$branch" in
      staging) environment=Staging ;; dev) environment=Development ;; *) environment="" ;;
    esac
    site=$( (grep -E '^SITE_NAME=' "$dir/appliance/.env" 2>/dev/null || sudo -n grep -E '^SITE_NAME=' "$dir/appliance/.env" 2>/dev/null) | cut -d= -f2-)
    cat "$dir/setup/banner.txt"
    echo "  Welcome${site:+, $site}!"
    echo "  Local Network Security Monitoring System"
    echo "  ${environment:+$environment · }version $(cat "$dir/setup/VERSION" 2>/dev/null || echo unknown)"
    echo
    echo "  Grafana:    http://$ip:3000"
    echo "  Wazuh:      https://$ip"
    echo "  NetAlertX:  http://$ip:20211"
    echo
    echo "  Installed in $dir"
    echo
    echo "  lsmsy password    set a new admin password: lsmsy password grafana (or wazuh, netalertx)"
    echo "  lsmsy status      is everything running?"
    echo "  lsmsy firewall    which ports are open"
    echo "  lsmsy users       list the Grafana accounts"
    echo "  lsmsy adduser     add one: lsmsy adduser sam viewer (or editor, admin)"
    echo "  lsmsy deluser     remove one: lsmsy deluser sam"
    echo "  lsmsy update      update to the newest version"
    echo "  lsmsy backup      make a backup now (lsmsy backup setup: add a cloud copy)"
    echo "  lsmsy restore     put the newest backup back (lsmsy restore cloud: from the cloud)"
    echo "  lsmsy report      this week's security summary (also emailed on Mondays)"
    echo "  lsmsy test        send a fake alarm to check alarms and email work"
    echo "  lsmsy remote      HTTPS access from anywhere with Tailscale (optional)" ;;
  *) echo "Unknown command: $1. Type lsmsy to see the commands."; exit 1 ;;
esac
