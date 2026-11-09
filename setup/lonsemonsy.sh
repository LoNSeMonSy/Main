#!/usr/bin/env bash
# The "lsmsy" command (setup links it to /usr/local/bin, so it works anywhere).
#   lsmsy             addresses, version and commands
#   lsmsy passwords   the Grafana and Wazuh passwords
#   lsmsy status      is everything running?
#   lsmsy firewall    which ports are open
#   lsmsy update      update to the newest version
#   lsmsy backup      make a cloud backup now      lsmsy restore   put it back
#   lsmsy users       Grafana accounts             lsmsy adduser / lsmsy deluser
dir=$(dirname "$(dirname "$(readlink -f "$0")")")   # the LoNSeMonSy folder
# Grafana's own user API, logged in as admin.
gapi() { curl -s -m 15 -H 'Content-Type: application/json' \
  -u "admin:$(sudo grep -E '^GRAFANA_ADMIN_PASSWORD=' "$dir/appliance/.env" | cut -d= -f2-)" "$@"; }
G=http://localhost:3000

case "${1:-}" in
  passwords) sudo "$dir/setup/show-passwords.sh" ;;
  update)    sudo "$dir/setup/update.sh" ;;
  backup)    sudo "$dir/setup/backup.sh" "${2:-}" ;;
  restore)   sudo "$dir/setup/restore.sh" ;;
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
    gapi -X PATCH $G/api/org/users/$id -d "{\"role\":\"$role\"}" >/dev/null
    echo "  added $name as $role"
    echo "  password: $pw   (they can change it in Grafana under Profile)" ;;
  deluser)
    name=${2:-}
    [ -n "$name" ] || { echo "  usage: lsmsy deluser <name>"; exit 1; }
    [ "$name" != admin ] || { echo "  the admin account can't be removed"; exit 1; }
    id=$(gapi "$G/api/users/lookup?loginOrEmail=$name" | jq -r '.id // empty')
    [ -n "$id" ] || { echo "  no account called $name"; exit 1; }
    gapi -X DELETE $G/api/admin/users/$id | jq -r '"  " + .message' ;;
  status)
    sudo docker ps --format '{{.Names}}: {{.Status}}' | sed 's/^/  /'
    for s in wazuh-manager wazuh-indexer wazuh-dashboard suricata; do
      echo "  $s: $(systemctl is-active "$s")"
    done ;;
  "")
    ip=$(ip -o -4 route get 1.1.1.1 | grep -oP 'src \K[0-9.]+')
    branch=$(git -c safe.directory="$dir" -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    case "$branch" in
      staging) environment=Staging ;; dev) environment=Development ;; *) environment="" ;;
    esac
    cat "$dir/setup/banner.txt"
    echo "  ${environment:+$environment · }version $(cat "$dir/setup/VERSION" 2>/dev/null || echo unknown)"
    echo
    echo "  Grafana:    http://$ip:3000"
    echo "  Wazuh:      https://$ip"
    echo "  NetAlertX:  http://$ip:20211"
    echo
    echo "  Installed in $dir"
    echo
    echo "  lsmsy passwords   show the Grafana and Wazuh passwords"
    echo "  lsmsy status      is everything running?"
    echo "  lsmsy firewall    which ports are open"
    echo "  lsmsy users       list the Grafana accounts"
    echo "  lsmsy adduser     add one: lsmsy adduser sam viewer (or editor, admin)"
    echo "  lsmsy deluser     remove one: lsmsy deluser sam"
    echo "  lsmsy update      update to the newest version"
    echo "  lsmsy backup      make a cloud backup now (lsmsy backup setup: choose the bucket)"
    echo "  lsmsy restore     put the newest cloud backup back" ;;
  *) echo "Unknown command: $1. Type lsmsy to see the commands."; exit 1 ;;
esac
