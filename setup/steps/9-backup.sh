# shellcheck shell=bash
# Step 9: backups (setup/backup.sh does the work). Every night (1 AM unless set) to this server,
# and to the cloud too if a bucket was given (the Backups question).

need restic restic
if [ -z "$(get BACKUP_LOCAL)" ]; then set_env BACKUP_LOCAL /var/backups/lonsemonsy-copies; fi
# Every night at BACKUP_TIME, and right away if the machine was off then.
when=$(get BACKUP_TIME); when=${when:-01:00}
cat > /etc/systemd/system/lonsemonsy-backup.service <<UNIT
[Service]
Type=oneshot
ExecStart=$(pwd)/setup/backup.sh
UNIT
printf '[Timer]\nOnCalendar=*-*-* %s\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n' "$when" \
  > /etc/systemd/system/lonsemonsy-backup.timer
# The Backups page's "Back up now" button (setup/backup-api.sh). Only Grafana can reach it.
cat > /etc/systemd/system/lonsemonsy-backup-api.socket <<UNIT
[Socket]
ListenStream=172.20.0.1:5002
FreeBind=yes
Accept=yes

[Install]
WantedBy=sockets.target
UNIT
cat > /etc/systemd/system/lonsemonsy-backup-api@.service <<UNIT
[Service]
ExecStart=$(pwd)/setup/backup-api.sh
StandardInput=socket
StandardOutput=socket
StandardError=journal
UNIT
systemctl daemon-reload
systemctl enable --now lonsemonsy-backup-api.socket >/dev/null 2>&1
systemctl enable lonsemonsy-backup.timer >/dev/null 2>&1
systemctl restart lonsemonsy-backup.timer   # picks up a new time
# The Backups page shows the time.
curl -sf -X POST "http://127.0.0.1:8086/api/v2/write" \
  --url-query "org=$(get INFLUXDB_ORG)" --url-query "bucket=$(get INFLUXDB_BUCKET)" --url-query precision=s \
  -H "Authorization: Token $(get INFLUXDB_ADMIN_TOKEN)" \
  --data-binary "lonsemonsy_backup_schedule at=\"$(date -d "$when" '+%-I:%M %p')\"" >/dev/null || true
where="on this server"
if [ -n "$(get BACKUP_REPO)" ]; then where="on this server and in the cloud"; fi
# The first backup, unless there is one already (setup run again, or an update).
if [ ! -f "$(get BACKUP_LOCAL)/config" ]; then
  run "Making the first backup ($where)" setup/backup.sh ||
    echo "  The first backup failed. It tries again tonight; to see why now: sudo lsmsy backup"
fi
echo "  backups: every night at $(date -d "$when" '+%-I:%M %p'), $where"
