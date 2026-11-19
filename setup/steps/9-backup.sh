# shellcheck shell=bash
# Step 9: backups (setup/backup.sh does the work). Every night at 1 AM to this server,
# and to the cloud too if a bucket was given (the Backups question).

need restic restic
if [ -z "$(get BACKUP_LOCAL)" ]; then set_env BACKUP_LOCAL /var/backups/lonsemonsy-copies; fi
# Every night at 1 AM, and right away if the machine was off at 1 AM.
cat > /etc/systemd/system/lonsemonsy-backup.service <<UNIT
[Service]
Type=oneshot
ExecStart=$(pwd)/setup/backup.sh
UNIT
printf '[Timer]\nOnCalendar=*-*-* 01:00\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n' \
  > /etc/systemd/system/lonsemonsy-backup.timer
systemctl daemon-reload
systemctl enable --now lonsemonsy-backup.timer >/dev/null 2>&1
where="on this server"
if [ -n "$(get BACKUP_REPO)" ]; then where="on this server and in the cloud"; fi
# The first backup, unless there is one already (setup run again, or an update).
if [ ! -f "$(get BACKUP_LOCAL)/config" ]; then
  run "Making the first backup ($where)" setup/backup.sh ||
    echo "  The first backup failed. It tries again tonight; to see why now: sudo lsmsy backup"
fi
echo "  backups: every night at 1 AM, $where"
