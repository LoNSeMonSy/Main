# shellcheck shell=bash
# Step 10: daily update check, the lsmsy command, and the summary.

# Check GitHub for a new version once a day (shown on Grafana's Updates page).
cat > /etc/systemd/system/lonsemonsy-update-check.service <<UNIT
[Service]
Type=oneshot
User=$owner
ExecStart=$(pwd)/setup/check-update.sh
UNIT
printf '[Timer]\nOnBootSec=5min\nOnUnitActiveSec=1d\n\n[Install]\nWantedBy=timers.target\n' \
  > /etc/systemd/system/lonsemonsy-update-check.timer
systemctl daemon-reload
systemctl enable --now lonsemonsy-update-check.timer >/dev/null 2>&1
systemctl start lonsemonsy-update-check.service || true

# Typing "lsmsy" (or "lonsemonsy") anywhere shows the addresses, version and commands.
ln -sf "$(pwd)/setup/lonsemonsy.sh" /usr/local/bin/lonsemonsy
ln -sf "$(pwd)/setup/lonsemonsy.sh" /usr/local/bin/lsmsy
rm -f /usr/local/bin/lm   # old name

# The company or site name becomes Grafana's organization name.
if [ -n "$(get SITE_NAME)" ]; then
  for _ in $(seq 1 30); do          # Grafana may still be starting
    if curl -sf -m 5 http://localhost:3000/api/health -o /dev/null; then break; fi
    sleep 2
  done
  curl -s -m 15 -u "admin:$(get GRAFANA_ADMIN_PASSWORD)" -X PUT -H 'Content-Type: application/json' \
    -d "{\"name\":\"$(get SITE_NAME)\"}" http://localhost:3000/api/org -o /dev/null || true
fi

echo "Done."
echo "  Grafana:    http://$ip:3000     user admin, password $(get GRAFANA_ADMIN_PASSWORD)"
echo "  NetAlertX:  http://$ip:20211    no login"
if [ -s "$WPASS" ]; then
  echo "  Wazuh:      https://$ip         user admin, password $(wazuh_password admin)"
fi
if [ -n "$(get BACKUP_REPO)" ]; then
  echo "  Backup:     password $(get BACKUP_PASSWORD)   save it somewhere else: without it a backup can't be restored"
fi
echo
echo "  Change the Grafana password: click your profile picture > Change password."
echo "  See the passwords again: lsmsy passwords"
echo "  Protect a computer with a Wazuh agent: see wazuh/README.md"
echo "  Everything else: type lsmsy"
