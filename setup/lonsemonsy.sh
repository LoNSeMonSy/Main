#!/usr/bin/env bash
# The "lonsemonsy" command (setup links it to /usr/local/bin, so it works anywhere).
#   lonsemonsy             addresses, version and commands
#   lonsemonsy passwords   the Grafana and Wazuh passwords
#   lonsemonsy status      is everything running?
#   lonsemonsy firewall    which ports are open
#   lonsemonsy update      update to the newest version
dir=$(dirname "$(dirname "$(readlink -f "$0")")")   # the LoNSeMonSy folder

case "${1:-}" in
  passwords) sudo "$dir/setup/show-passwords.sh" ;;
  update)    sudo "$dir/setup/update.sh" ;;
  firewall)  sudo ufw status verbose ;;
  status)
    sudo docker ps --format '{{.Names}}: {{.Status}}' | sed 's/^/  /'
    for s in wazuh-manager wazuh-indexer wazuh-dashboard suricata; do
      echo "  $s: $(systemctl is-active "$s")"
    done ;;
  "")
    ip=$(ip -o -4 route get 1.1.1.1 | grep -oP 'src \K[0-9.]+')
    cat "$dir/setup/banner.txt"
    echo
    echo "  Grafana:    http://$ip:3000"
    echo "  Wazuh:      https://$ip"
    echo "  NetAlertX:  http://$ip:20211"
    echo
    echo "  Version $(cat "$dir/VERSION" 2>/dev/null || echo unknown), installed in $dir"
    echo
    echo "  lonsemonsy passwords   show the Grafana and Wazuh passwords"
    echo "  lonsemonsy status      is everything running?"
    echo "  lonsemonsy firewall    which ports are open"
    echo "  lonsemonsy update      update to the newest version" ;;
  *) echo "Unknown command: $1. Type lonsemonsy to see the commands."; exit 1 ;;
esac
