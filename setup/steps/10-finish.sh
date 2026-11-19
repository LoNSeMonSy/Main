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

# Weekly security report by email, Mondays at 8 AM (skipped while email alarms are off).
cat > /etc/systemd/system/lonsemonsy-weekly-report.service <<UNIT
[Service]
Type=oneshot
ExecStart=$(pwd)/setup/weekly-report.sh
UNIT
printf '[Timer]\nOnCalendar=Mon *-*-* 08:00\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n' \
  > /etc/systemd/system/lonsemonsy-weekly-report.timer
systemctl daemon-reload
systemctl enable --now lonsemonsy-weekly-report.timer >/dev/null 2>&1

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

# Remote access, if a Tailscale key was given in question 5.
if [ -n "${TS_AUTHKEY:-}" ]; then TS_AUTHKEY="$TS_AUTHKEY" ./setup/remote.sh || echo "  remote access didn't start; try again with: lsmsy remote"; fi

echo
cat setup/banner.txt
site=$(get SITE_NAME)
printf '\n  \033[1mWelcome%s! LoNSeMonSy is installed and watching your network.\033[0m\n' "${site:+, $site}"
echo "  Setup took $(took "$setup_start"). Version $(cat setup/VERSION)."
echo
echo "  Grafana:    http://$ip:3000     user admin, password $(get GRAFANA_ADMIN_PASSWORD)"
echo "  NetAlertX:  http://$ip:20211    password $(get NETALERTX_PASSWORD)"
if [ -s "$WPASS" ]; then
  echo "  Wazuh:      https://$ip         user admin, password $(wazuh_password admin)"
fi
echo "  Backups:    password $(get BACKUP_PASSWORD)   (a backup can't be restored without it)"
echo
echo "  Save these passwords in a password manager now. They aren't shown again."
echo "  Forgot one, or someone else has it: lsmsy password grafana (or wazuh, netalertx)"
echo "  Not sure what something means: setup/HELP.md"
echo "  Protect a computer with a Wazuh agent: see wazuh/README.md"
echo "  Everything else: type lsmsy"
