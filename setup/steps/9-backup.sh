# shellcheck shell=bash
# Step 9: cloud backup, only if a bucket was given (question 3). setup/backup.sh does the work.

if [ -n "$(get BACKUP_REPO)" ]; then
  need restic restic
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
  echo "  cloud backup: making the first backup..."
  if setup/backup.sh > /root/lonsemonsy-backup.log 2>&1; then
    echo "  cloud backup: on, every night at 1 AM"
  else
    echo "  cloud backup: the first backup failed, see /root/lonsemonsy-backup.log"
  fi
fi
