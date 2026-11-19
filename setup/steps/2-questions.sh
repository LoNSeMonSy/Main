# shellcheck shell=bash
# Step 2: the questions, asked first so the rest runs on its own. Nothing is saved until
# the answers are confirmed. "?" at any question shows its help (setup/HELP.md).
# Skipped when nobody is at the keyboard, or with SKIP_QUESTIONS=1.

ask=0
if [ -t 0 ] && [ "${SKIP_QUESTIONS:-0}" != 1 ]; then ask=1; fi
NETPLAN=/etc/netplan/60-lonsemonsy-static.yaml
dhcp=0
if [[ $(ip -o -4 addr show dev "$iface") == *dynamic* ]] && [ ! -f "$NETPLAN" ]; then dhcp=1; fi
has_tailscale() { tailscale status >/dev/null 2>&1; }

static=${STATIC_IP:-2}; site=""; to=""; from=""; apw=""; repo=""; bucket=""; key_id=""; secret=""; ts_key=""
n=0
question() { n=$((n + 1)); printf '\n  \033[1mQuestion %s: %s\033[0m\n' "$n" "$1"; }

ask_email() {
  while true; do
    ask to "Alarm emails" "Your email address, where alarms go (Enter to skip): "
    if [ -z "$to" ]; then return; fi
    if [[ $to != *@*.* ]]; then echo "  That isn't an email address."; continue; fi
    echo "  Alarms are sent from a Gmail account. A new one just for this works best."
    ask from "Alarm emails" "Gmail address to send from, e.g. acmealarms@gmail.com: "
    echo "  Gmail won't let LoNSeMonSy use that account's normal password. Instead Google gives"
    echo "  you a separate 16-letter password for it: https://myaccount.google.com/apppasswords"
    echo "  (signed in as $from). Type ? for step-by-step help."
    ask apw "Alarm emails" "The 16-letter password from Google (hidden): " hidden
    apw=${apw// /}                    # Google shows it with spaces; they aren't part of it
    echo "  checking with Gmail..."
    # Log in to Gmail once to check it (nothing is sent).
    if curl -s --max-time 20 --ssl-reqd --url smtp://smtp.gmail.com:587 --user "$from:$apw" -X NOOP -o /dev/null; then
      echo "  Gmail accepted it."
      return
    fi
    echo "  Gmail didn't accept that Gmail address and password."
    if ! confirm "Alarm emails" "Try again? [Y/n]: " Y; then to=""; return; fi
  done
}

questions() {
  n=0; site=""; to=""; repo=""; ts_key=""
  if [ "$dhcp" = 1 ] && [ -z "${STATIC_IP:-}" ]; then
    question "Server address"
    echo "  Other computers reach this server at $ip. The router could change that later."
    if confirm "Server address" "Keep it fixed at $ip? [Y/n]: " Y; then static=1; else static=2; fi
  fi
  if [ -z "$(get SITE_NAME)" ]; then
    question "Business name"
    echo "  Shown at the top of the dashboard and on alarm emails."
    ask site "Business name" "Business name, e.g. Acme Dental (Enter to skip): "
    site=${site//[\"\\]/}             # no quotes or backslashes
  fi
  if [ -z "$(get ALERT_EMAIL_TO)" ]; then
    question "Alarm emails"
    echo "  LoNSeMonSy emails you when something needs attention."
    echo "  Without this, you only see alarms when you open the dashboard."
    ask_email
  fi
  if [ -z "$(get BACKUP_REPO)" ]; then
    question "Backups"
    echo "  Every night LoNSeMonSy saves a copy of its settings and data on this server (always on)."
    echo "  If this server's disk dies, that copy is lost too. A cloud copy is kept somewhere else."
    if confirm Backups "Also send a copy to the cloud (Backblaze or Amazon S3)? [y/N]: " N; then ask_bucket; fi
  fi
  if ! has_tailscale; then
    question "Remote access"
    echo "  Open the dashboards away from the office, on a phone or laptop, with Tailscale (free)."
    if confirm "Remote access" "Set up remote access? [y/N]: " N; then
      echo "  Make a key: https://login.tailscale.com/admin/settings/keys > Generate auth key."
      while true; do
        ask ts_key "Remote access" "Paste the key (starts with tskey-, hidden, Enter to skip): " hidden
        if [ -z "$ts_key" ] || [[ $ts_key == tskey-* ]]; then break; fi
        echo "  That isn't a Tailscale key. It starts with tskey-."
      done
    fi
  fi
}

line() { printf '    %-16s %s\n' "$1" "$2"; }
summary() {
  echo
  echo "  Your answers:"
  if [ "$dhcp" = 1 ] && [ -z "${STATIC_IP:-}" ]; then
    if [ "$static" = 1 ]; then line "Server address" "fixed at $ip"; else line "Server address" "chosen by the router"; fi
  fi
  if [ -z "$(get SITE_NAME)" ]; then line "Business name" "${site:-(none)}"; fi
  if [ -z "$(get ALERT_EMAIL_TO)" ]; then
    if [ -n "$to" ]; then line "Alarm emails" "to $to, sent from $from"; else line "Alarm emails" "off"; fi
  fi
  if [ -z "$(get BACKUP_REPO)" ]; then
    if [ -n "$repo" ]; then line "Backups" "on this server and in the cloud ($bucket)"; else line "Backups" "on this server"; fi
  fi
  if ! has_tailscale; then
    if [ -n "$ts_key" ]; then line "Remote access" "on"; else line "Remote access" "off"; fi
  fi
}

if [ "$ask" = 1 ]; then
  echo "  Press Enter to take the answer in [brackets]. Type ? for help."
  while true; do
    questions
    if [ "$n" = 0 ]; then break; fi
    summary
    if confirm "" "Is this right? [Y/n]: " Y; then break; fi
    echo "  OK, once more."
  done
fi

# Save the answers.
if [ "$dhcp" = 1 ]; then
  if [ "$static" = 1 ]; then
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
    echo "  server address: fixed at $ip. Also reserve it on the router so no other device gets it."
  else
    echo "  server address: chosen by the router. Reserve $ip on the router ($gw) so it stays the same."
  fi
fi
if [ -n "$site" ]; then
  set_env SITE_NAME "$site"
  set_env SMTP_FROM_NAME "$site LoNSeMonSy"
fi
if [ -n "$to" ]; then
  set_env ALERT_EMAIL_TO "$to"
  set_env SMTP_ENABLED true
  set_env SMTP_USER "$from"
  set_env SMTP_FROM_ADDRESS "$from"
  set_env SMTP_PASSWORD "$apw"
  echo "  alarm emails: on (to $to)"
fi
if [ -n "$repo" ]; then
  set_env BACKUP_REPO "$repo"
  set_env BACKUP_KEY_ID "$key_id"
  set_env BACKUP_SECRET "$secret"
  echo "  cloud backup: on ($bucket)"
fi
if [ -n "$ts_key" ]; then TS_AUTHKEY=$ts_key; fi
