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

# Every 5 minutes: is remote access on, and which devices can reach it (Devices page + alarm).
cat > /etc/systemd/system/lonsemonsy-remote-check.service <<UNIT
[Service]
Type=oneshot
ExecStart=$(pwd)/setup/remote-check.sh
UNIT
printf '[Timer]\nOnBootSec=2min\nOnUnitActiveSec=5min\n\n[Install]\nWantedBy=timers.target\n' \
  > /etc/systemd/system/lonsemonsy-remote-check.timer
systemctl daemon-reload
systemctl enable --now lonsemonsy-remote-check.timer >/dev/null 2>&1

# Typing "lsmsy" (or "lonsemonsy") anywhere shows the addresses, version and commands.
ln -sf "$(pwd)/setup/lonsemonsy.sh" /usr/local/bin/lonsemonsy
ln -sf "$(pwd)/setup/lonsemonsy.sh" /usr/local/bin/lsmsy
rm -f /usr/local/bin/lm   # old name

for _ in $(seq 1 30); do          # Grafana may still be starting
  if curl -sf -m 5 http://localhost:3000/api/health -o /dev/null; then break; fi
  sleep 2
done
# The admin account gets the alarm email address, so "Forgot your password?" on
# Grafana's login page can send it a reset link.
if [ -n "$(get ALERT_EMAIL_TO)" ]; then
  curl -s -m 15 -u "admin:$(get GRAFANA_ADMIN_PASSWORD)" -X PUT -H 'Content-Type: application/json' \
    -d "{\"login\":\"admin\",\"name\":\"admin\",\"email\":\"$(get ALERT_EMAIL_TO)\"}" http://localhost:3000/api/users/1 -o /dev/null || true
fi
# The company or site name becomes Grafana's organization name.
if [ -n "$(get SITE_NAME)" ]; then
  curl -s -m 15 -u "admin:$(get GRAFANA_ADMIN_PASSWORD)" -X PUT -H 'Content-Type: application/json' \
    -d "{\"name\":\"$(get SITE_NAME)\"}" http://localhost:3000/api/org -o /dev/null || true
fi

# AI explanations, if turned on (also re-applied after an update).
if [ "$(get AI_ENABLED)" = true ]; then setup/ai.sh on || echo "  AI explanations didn't start; try again with: lsmsy ai on"; fi

# Remote access, if asked for in the questions (TS_AUTHKEY=tskey-... signs in without the link).
if [ -n "${remote:-}" ] || [ -n "${TS_AUTHKEY:-}" ]; then
  setup/remote.sh on || echo "  remote access didn't start; try again with: lsmsy remote"
fi
setup/remote-check.sh >/dev/null 2>&1 || true

echo
cat setup/banner.txt
echo "  Local Network Security Monitoring System"
echo "  ${environment:+$environment · }version $(cat setup/VERSION)"
site=$(get SITE_NAME)
printf '\n  \033[1mWelcome%s! LoNSeMonSy is installed and watching your network.\033[0m\n' "${site:+, $site}"
echo "  Setup took $(took "$setup_start")."
echo
grafana=http://$ip:3000; netalertx=http://$ip:20211; wazuh=https://$ip
if [[ $(get GRAFANA_ROOT_URL) == https://* ]]; then   # remote access: the addresses that need the sign-in
  grafana=$(get GRAFANA_ROOT_URL); netalertx=$(get NETALERTX_URL); wazuh=$(get WAZUH_URL)
fi
echo "  Grafana:    $grafana     user admin, password $(get GRAFANA_ADMIN_PASSWORD)"
echo "  NetAlertX:  $netalertx     password $(get NETALERTX_PASSWORD)"
if [ -s "$WPASS" ]; then
  echo "  Wazuh:      $wazuh     user admin, password $(wazuh_password admin)"
fi
echo "  Backups:    password $(get BACKUP_PASSWORD)   (a backup can't be restored without it)"
if [[ $grafana == https://* ]]; then
  if [ "$(get IP_ACCESS)" = off ]; then echo "  By IP address: off. If Tailscale isn't working: sudo lsmsy remote ip on"
  else echo "  By IP address, not recommended (skips the 2-step sign-in): http://$ip:3000"; fi
fi
echo
echo "  Grafana on your phone (scan with the camera):"
qr "$grafana"
echo
echo "  Save these passwords in a password manager now. They aren't shown again."
echo "  Forgot one, or someone else has it: lsmsy password grafana (or wazuh, netalertx)"
echo "  Not sure what something means: setup/HELP.md"
echo "  Protect a computer with a Wazuh agent: see wazuh/README.md"
echo "  Everything else: type lsmsy"

# The first install ends with one test alarm, so the first sign-in shows that alarms and email work.
if [ "${SKIP_TEST:-0}" != 1 ] && [ ! -e /var/lib/lonsemonsy/last-test ] && systemctl is-active -q wazuh-manager; then
  echo
  echo "  Sending a test alarm, so you can check that alarms work:"
  setup/lonsemonsy.sh test || echo "  it didn't send; try again with: lsmsy test"
fi
