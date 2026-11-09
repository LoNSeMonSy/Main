# shellcheck shell=bash
# Step 2: the questions, asked first so the rest runs on its own.
# Skipped when nobody is at the keyboard, or with SKIP_QUESTIONS=1.

ask=0
if [ -t 0 ] && [ "${SKIP_QUESTIONS:-0}" != 1 ]; then ask=1; fi

# Question 1: static IP or DHCP. Only asked when the router gave the address (DHCP).
NETPLAN=/etc/netplan/60-lonsemonsy-static.yaml
if [[ $(ip -o -4 addr show dev "$iface") == *dynamic* ]] && [ ! -f "$NETPLAN" ]; then
  answer=${STATIC_IP:-2}
  if [ "$ask" = 1 ] && [ "$answer" != 1 ]; then
    echo "  How should this machine get its IP address?"
    echo "    1) Static: always use $ip (recommended: the logins and agents use this address)"
    echo "    2) DHCP: obtain an IP address from the router ($gw)"
    read -r -p "  Choose 1 or 2 [1]: " answer
    answer=${answer:-1}
  fi
  if [ "$answer" = 1 ]; then
    dns=$(resolvectl dns "$iface" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    cat > "$NETPLAN" <<NET
# Written by LoNSeMonSy setup. To go back to DHCP: sudo rm $NETPLAN && sudo netplan apply
network:
  version: 2
  ethernets:
    $iface:
      dhcp4: false
      addresses: [$cidr]
      routes: [{to: default, via: $gw}]
      nameservers: {addresses: [${dns:-$gw}]}
NET
    chmod 600 "$NETPLAN"
    netplan apply
    echo "  IP address: static ($ip). Also reserve it on the router so no other device gets it."
  else
    echo "  IP address: DHCP. Reserve $ip on the router ($gw) so it stays the same."
  fi
fi

# Question 2: email alarms, sent from a Gmail account with an app password.
if [ "$ask" = 1 ] && [ -z "$(get ALERT_EMAIL_TO)" ]; then
  echo "  Email alarms (optional)"
  to=""
  while true; do
    read -r -p "  Send alarms TO which address? (Enter to skip): " to
    if [ -z "$to" ]; then break; fi
    read -r -p "  Send them FROM which Gmail account? " from
    read -r -p "  Send from $from to $to? [Y/n]: " ok
    if [ "$ok" = n ] || [ "$ok" = N ]; then continue; fi
    read -r -s -p "  Gmail app password (myaccount.google.com/apppasswords): " apw; echo
    apw=${apw// /}                    # Google shows it with spaces; they aren't part of it
    # Log in to Gmail once to check it (nothing is sent).
    if curl -s --max-time 20 --ssl-reqd --url smtp://smtp.gmail.com:587 --user "$from:$apw" -X NOOP -o /dev/null; then
      break
    fi
    echo "  Gmail didn't accept that. Let's try again (or press Enter to skip)."
  done
  if [ -n "$to" ]; then
    set_env ALERT_EMAIL_TO "$to"
    set_env SMTP_ENABLED true
    set_env SMTP_USER "$from"
    set_env SMTP_FROM_ADDRESS "$from"
    set_env SMTP_PASSWORD "$apw"
    echo "  email alarms: on (from $from to $to)"
  else
    echo "  email alarms: skipped"
  fi
fi

# Question 3: cloud backup, encrypted nightly copies in a bucket (Restic).
if [ "$ask" = 1 ] && [ -z "$(get BACKUP_REPO)" ]; then
  echo "  Cloud backup (optional)"
  ask_bucket
  if [ -n "$repo" ]; then
    set_env BACKUP_REPO "$repo"
    set_env BACKUP_KEY_ID "$key_id"
    set_env BACKUP_SECRET "$secret"
    echo "  cloud backup: on"
  else
    echo "  cloud backup: skipped"
  fi
fi
