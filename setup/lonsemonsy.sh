#!/usr/bin/env bash
# The "lsmsy" command (setup links it to /usr/local/bin, so it works anywhere).
#   lsmsy             addresses, version and commands
#   lsmsy password    set a new Grafana, Wazuh or NetAlertX password
#   lsmsy status      is everything running?
#   lsmsy firewall    which ports are open
#   lsmsy update      update to the newest version
#   lsmsy backup      make a backup now            lsmsy restore   put it back
#   lsmsy users       see, add or remove Grafana accounts (adduser / deluser still work)
#   lsmsy test        send a fake alarm      lsmsy report   the weekly summary
#   lsmsy remote      HTTPS access from anywhere (Tailscale)
#   lsmsy ai          AI explanations of alarms: lsmsy ai on / off
dir=$(dirname "$(dirname "$(readlink -f "$0")")")   # the LoNSeMonSy folder
# Grafana's own user API, logged in as admin.
gapi() { curl -s -m 15 -H 'Content-Type: application/json' \
  -u "admin:$(sudo grep -E '^GRAFANA_ADMIN_PASSWORD=' "$dir/appliance/.env" | cut -d= -f2-)" "$@"; }
G=http://localhost:3000

# wait_between NAME SECONDS: commands that send alarms, make backups or change passwords
# can't be run again right away, so nobody can flood the server or the inbox with them.
# The time is kept where only root can change it. (The nightly backup isn't limited.)
wait_between() {
  local f=/var/lib/lonsemonsy/last-$1 now last left
  now=$(date +%s)
  last=$(sudo cat "$f" 2>/dev/null || echo 0)
  left=$((last + $2 - now))
  if [ "$left" -gt 0 ]; then
    echo "  lsmsy $1 was run a moment ago. Try again in $(( (left + 59) / 60 )) min."; exit 1
  fi
  sudo mkdir -p /var/lib/lonsemonsy && echo "$now" | sudo tee "$f" >/dev/null
}

# add_user NAME ROLE [EMAIL]: a new Grafana account with a made-up password.
add_user() {
  local name=$1 role=$2 email=${3:-} pw id
  wait_between adduser 30
  case "${role,,}" in viewer) role=Viewer ;; editor) role=Editor ;; admin) role=Admin ;;
    *) echo "  role must be viewer, editor or admin"; return 1 ;; esac
  pw=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-12)
  id=$(gapi -X POST $G/api/admin/users \
    -d "{\"name\":\"$name\",\"login\":\"$name\",\"email\":\"$email\",\"password\":\"$pw\"}" | jq -r '.id // empty')
  [ -n "$id" ] || { echo "  could not add $name (does it already exist?)"; return 1; }
  gapi -X PATCH $G/api/org/users/"$id" -d "{\"role\":\"$role\"}" >/dev/null
  echo "  added $name as $role, password: $pw"
  echo "  (they can change it in Grafana under Profile${email:+; Forgot your password? emails $email})"
}
# del_user NAME
del_user() {
  local id
  [ "$1" != admin ] || { echo "  the admin account can't be removed"; return 1; }
  id=$(gapi "$G/api/users/lookup?loginOrEmail=$1" | jq -r '.id // empty')
  [ -n "$id" ] || { echo "  no account called $1"; return 1; }
  gapi -X DELETE $G/api/admin/users/"$id" | jq -r '"  " + .message'
}

case "${1:-}" in
  password)  wait_between password 60; sudo "$dir/setup/change-password.sh" "${2:-}" ;;
  passwords) echo "  Passwords are shown once, at the end of setup. To set a new one: lsmsy password grafana (or wazuh, netalertx)" ;;
  update)    wait_between update 300; sudo "$dir/setup/update.sh" ;;
  backup)
    if [ -z "${2:-}" ]; then wait_between backup 600; fi   # "backup time" and "backup setup" aren't limited
    sudo "$dir/setup/backup.sh" "${@:2}" ;;
  restore)   wait_between restore 300; sudo "$dir/setup/restore.sh" "${2:-}" ;;
  remote)    sudo "$dir/setup/remote.sh" ;;
  ai)
    if [ "${2:-status}" != status ]; then wait_between ai 120; fi
    sudo "$dir/setup/ai.sh" "${2:-status}" ;;
  report)    sudo "$dir/setup/weekly-report.sh" print ;;
  firewall)  sudo ufw status verbose ;;
  users)
    # The accounts, then add or remove one.
    while true; do
      echo "  Grafana accounts:"
      { echo "    NAME	ROLE	EMAIL"
        gapi $G/api/org/users | jq -r '.[] | "    \(.login)\t\(.role)\t\(.email)"'; } | column -t -s $'\t'
      echo
      read -r -p "  Add someone (a), remove someone (r), or Enter to finish: " what
      case "$what" in
        a|A)
          read -r -p "  Name to sign in with, like sam: " name
          [ -n "$name" ] || continue
          read -r -p "  Their email, for password resets (Enter to skip): " email
          read -r -p "  Role: viewer (looks only), editor or admin [viewer]: " role
          add_user "$name" "${role:-viewer}" "$email" ;;
        r|R)
          read -r -p "  Name to remove: " name
          [ -n "$name" ] || continue
          read -r -p "  Remove $name? [y/N]: " yes
          [[ $yes == [Yy]* ]] && del_user "$name" ;;
        *) break ;;
      esac
      echo
    done ;;
  adduser)   # older form, still works: lsmsy adduser sam viewer
    [ -n "${2:-}" ] || { echo "  usage: lsmsy users"; exit 1; }
    add_user "$2" "${3:-viewer}" ;;
  deluser)   # older form, still works: lsmsy deluser sam
    [ -n "${2:-}" ] || { echo "  usage: lsmsy users"; exit 1; }
    del_user "$2" ;;
  status)
    sudo docker ps --format '{{.Names}}: {{.Status}}' | sed 's/^/  /'
    for s in wazuh-manager wazuh-indexer wazuh-dashboard suricata; do
      echo "  $s: $(systemctl is-active "$s")"
    done ;;
  test)
    wait_between test 300
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
    remote=$( (grep -E '^GRAFANA_ROOT_URL=' "$dir/appliance/.env" 2>/dev/null || sudo -n grep -E '^GRAFANA_ROOT_URL=' "$dir/appliance/.env" 2>/dev/null) | cut -d= -f2-)
    if [[ $remote == https://* ]]; then echo "  Anywhere:   $remote   (Grafana, over Tailscale)"; fi
    echo
    echo "  Installed in $dir"
    echo
    echo "  Everyday"
    echo "    lsmsy status      is everything running?"
    echo "    lsmsy test        send a fake alarm to check alarms and email work"
    echo "    lsmsy report      this week's security summary (also emailed on Mondays)"
    echo "  Accounts and access"
    echo "    lsmsy users       see, add or remove Grafana accounts"
    echo "    lsmsy password    set a new password: lsmsy password grafana (or wazuh, netalertx)"
    echo "    lsmsy remote      open the dashboards from anywhere, with a 2-step sign-in"
    echo "  Upkeep"
    echo "    lsmsy update      update to the newest version"
    echo "    lsmsy backup      make a backup now (lsmsy backup local or cloud: just one;"
    echo "                      lsmsy backup time 11pm: change the time; lsmsy backup setup: add a cloud copy)"
    echo "    lsmsy restore     put the newest backup back (lsmsy restore cloud: from the cloud)"
    echo "    lsmsy firewall    which ports are open"
    echo "    lsmsy ai          AI notes on alarms: lsmsy ai on / off" ;;
  *) echo "Unknown command: $1. Type lsmsy to see the commands."; exit 1 ;;
esac
