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

utc=0
case "$(timedatectl show -p Timezone --value)" in UTC|Etc/UTC|Etc/Universal|"") utc=1 ;; esac
static=${STATIC_IP:-2}; tz=""; backup_time=""; site=""; to=""; from=""; apw=""; repo=""; bucket=""; key_id=""; secret=""; remote=""; ai=""; ai_url=""
# Which questions get asked: each is skipped once answered, or when it doesn't apply.
q_address() { [ "$dhcp" = 1 ] && [ -z "${STATIC_IP:-}" ]; }
q_timezone() { [ "$utc" = 1 ]; }
q_name() { [ -z "$(get SITE_NAME)" ]; }
q_email() { [ -z "$(get ALERT_EMAIL_TO)" ]; }
q_backup() { [ -z "$(get BACKUP_TIME)" ]; }
q_remote() { ! has_tailscale; }
q_ai() { [ "$(get AI_ENABLED)" != true ]; }
total=0
for q in q_address q_timezone q_name q_email q_backup q_remote q_ai; do
  if $q; then total=$((total + 1)); fi
done
n=0

# question TITLE: a heading like "── Question 2 of 7: Time zone ─────" with space around it.
question() {
  local head
  n=$((n + 1))
  head="Question $n of $total: $1"
  printf '\n\n  \033[1m── %s %s\033[0m\n\n' "$head" "$(printf '%*s' $((58 - ${#head})) '' | sed 's/ /─/g')"
}
# say LINE...: lines of explanation, then a blank line.
say() { printf '  %s\n' "$@"; echo; }

ask_email() {
  while true; do
    say "Where should alarm emails go? Any email address works." "Format: name@example.com, e.g. owner@acmedental.com"
    ask to "Alarm emails" "Your email (Enter to skip) > "
    if [ -z "$to" ]; then return; fi
    if [[ $to != *@*.* ]]; then echo "  That isn't an email address."; echo; continue; fi
    echo
    say "Alarms are sent from a Gmail account. A new one just for this works best." "Format: name@gmail.com, e.g. acmealarms@gmail.com"
    while true; do
      ask from "Alarm emails" "Gmail address > "
      if [[ $from == *@*.* ]]; then break; fi
      echo "  That isn't an email address."
    done
    echo
    say "Gmail won't let LoNSeMonSy use that account's normal password. Instead," \
        "Google gives you a separate 16-letter password just for LoNSeMonSy:" \
        "  https://myaccount.google.com/apppasswords   (signed in as $from)" \
        "Format: 16 letters, e.g. abcd efgh ijkl mnop. Type ? for step-by-step help."
    ask apw "Alarm emails" "16-letter password (hidden) > " hidden
    apw=${apw// /}                    # Google shows it with spaces; they aren't part of it
    echo "  checking with Gmail..."
    # Log in to Gmail once to check it (nothing is sent).
    if curl -s --max-time 20 --ssl-reqd --url smtp://smtp.gmail.com:587 --user "$from:$apw" -X NOOP -o /dev/null; then
      echo "  ✓ Gmail accepted it."
      return
    fi
    echo "  ✗ Gmail didn't accept that Gmail address and password."
    echo
    if ! confirm "Alarm emails" "Try again? [Y/n] > " Y; then to=""; return; fi
    echo
  done
}

questions() {
  n=0; tz=""; backup_time=""; site=""; to=""; repo=""; remote=""; ai=""; ai_url=""
  if q_address; then
    question "Server address"
    say "Other computers reach this server at $ip." "The router could change that address later, which breaks the links."
    if confirm "Server address" "Keep it fixed at $ip? [Y/n] > " Y; then static=1; else static=2; fi
  fi
  if q_timezone; then
    question "Time zone"
    say "This server's clock is on UTC, so backups and reports would run" "at the wrong local time." \
        "Format: Region/City, e.g. America/New_York or America/Chicago." "Type ? for the common ones."
    while true; do
      ask tz "Time zone" "Time zone [America/New_York] > "
      case "${tz,,}" in
        "") tz=America/New_York ;;
        eastern) tz=America/New_York ;;  central) tz=America/Chicago ;;
        mountain) tz=America/Denver ;;   pacific) tz=America/Los_Angeles ;;
      esac
      if timedatectl list-timezones | grep -qx "$tz"; then break; fi
      echo "  That isn't a time zone name. Type ? to see the common ones."
    done
  fi
  if q_name; then
    question "Business name"
    say "Shown at the top of the dashboard and on alarm emails." "Format: any name, e.g. Acme Dental."
    ask site "Business name" "Business name (Enter to skip) > "
    site=${site//[\"\\]/}             # no quotes or backslashes
  fi
  if q_email; then
    question "Alarm emails"
    say "LoNSeMonSy emails you when something needs attention." "Without this, you only see alarms when you open the dashboard." \
        "The same address gets Grafana's reset link if the admin password is forgotten."
    ask_email
  fi
  if q_backup; then
    question "Backups"
    say "Every night LoNSeMonSy saves a copy of its settings and data on this" "server. This is always on." \
        "Pick a time when the office is closed but this server is still online." "Format: e.g. 1am, 11:30pm or 23:30."
    while true; do
      ask backup_time Backups "Backup time [1am] > "
      if backup_time=$(to_24h "${backup_time:-1am}"); then break; fi
      echo "  That isn't a time. Type it as e.g. 1am, 11:30pm or 23:30."
    done
    echo
    say "If this server's disk dies, the copy on it is lost too." "A cloud copy is kept somewhere else: Amazon S3 or Backblaze B2."
    if confirm Backups "Also send a copy to the cloud? [y/N] > " N; then echo; ask_bucket; fi
  fi
  if q_remote; then
    question "Remote access"
    say "Open the dashboards from your phone or laptop anywhere, with a 2-step sign-in." \
        "It uses Tailscale. At the end of setup you sign in with a Google, Microsoft or" \
        "GitHub account. The dashboards then only open on devices signed in to Tailscale." \
        "Cost: free for personal use. A business needs a paid plan, billed per user:" \
        "see tailscale.com/pricing"
    if confirm "Remote access" "Set up remote access? [y/N] > " N; then
      remote=1
      echo
      if [ -n "${to:-}$(get ALERT_EMAIL_TO)" ]; then
        say "Use the Gmail account the alarms are sent from: it already has 2-step verification." \
            "While setup runs, get the Tailscale app on your phone. Scan this for the steps:"
      else
        say "While setup runs: turn on 2-step verification for that account, and get the" \
            "Tailscale app on your phone. Scan this for the steps:"
      fi
      qr "$GUIDE#remote-access"
    fi
  fi
  if q_ai; then
    question "AI explanations"
    say "An AI adds a short note to each serious alarm: what happened and what" "to do. It runs on your own network. On this server it needs about" "2 GB more memory."
    if confirm "AI explanations" "Turn on AI explanations? [y/N] > " N; then
      ai=1
      echo
      say "It can run on this server, or on another computer running Ollama." "Format: that computer's IP address, e.g. 192.168.1.60."
      ask ai_url "AI explanations" "Other computer (Enter = this server) > "
      if [ -n "$ai_url" ]; then
        [[ $ai_url == http* ]] || ai_url="http://$ai_url"
        [[ ${ai_url#*://} == *:* ]] || ai_url="$ai_url:11434"
      fi
    fi
  fi
}

line() { printf '    %-18s %s\n' "$1" "$2"; }
summary() {
  local saved=" (saved before)" r
  printf '\n\n  \033[1m── Your answers %s\033[0m\n\n' "$(printf '%*s' 47 '' | sed 's/ /─/g')"
  if q_address; then
    if [ "$static" = 1 ]; then line "Server address" "fixed at $ip"; else line "Server address" "chosen by the router"; fi
  elif [ -f "$NETPLAN" ]; then line "Server address" "fixed at $ip$saved"
  fi
  if q_timezone; then line "Time zone" "$tz"
  else line "Time zone" "$(timedatectl show -p Timezone --value)$saved"
  fi
  if q_name; then line "Business name" "${site:-(none)}"
  else line "Business name" "$(get SITE_NAME)$saved"
  fi
  if q_email; then
    if [ -n "$to" ]; then line "Alarm emails" "to $to, sent from $from"; else line "Alarm emails" "off"; fi
  else line "Alarm emails" "to $(get ALERT_EMAIL_TO), sent from $(get SMTP_FROM_ADDRESS)$saved"
  fi
  if q_backup; then
    when="every night at $(date -d "$backup_time" '+%-I:%M %p')"
    if [ -n "$repo" ]; then line "Backups" "$when, here and in the cloud ($bucket)"; else line "Backups" "$when, on this server"; fi
  else
    when="every night at $(date -d "$(get BACKUP_TIME)" '+%-I:%M %p' 2>/dev/null || echo "1:00 AM")"
    r=$(get BACKUP_REPO); r=${r#b2:}; r=${r#s3:*/}; r=${r%%:*}
    if [ -n "$r" ]; then line "Backups" "$when, here and in the cloud ($r)$saved"; else line "Backups" "$when, on this server$saved"; fi
  fi
  if q_remote; then
    if [ -n "$remote" ]; then line "Remote access" "on (you sign in at the end)"; else line "Remote access" "off"; fi
  else line "Remote access" "on$saved"
  fi
  if q_ai; then
    if [ -n "$ai" ]; then line "AI explanations" "on (${ai_url:-on this server})"; else line "AI explanations" "off"; fi
  else r=$(get OLLAMA_URL); line "AI explanations" "on, ${r:-on this server}$saved"
  fi
  echo
}

if [ "$ask" = 1 ]; then
  echo "  Press Enter to take the answer in [brackets]. Type ? for help."
  while true; do
    questions
    if [ "$n" = 0 ]; then summary; break; fi
    summary
    if confirm "" "Is this right? [Y/n] > " Y; then echo; break; fi
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
if [ -n "$tz" ]; then
  timedatectl set-timezone "$tz"
  set_env TZ "$tz"
  echo "  time zone: $tz"
fi
if [ -n "$backup_time" ]; then set_env BACKUP_TIME "$backup_time"; fi
if [ -n "$site" ]; then
  set_env SITE_NAME "$site"
  set_env SMTP_FROM_NAME "$site via LoNSeMonSy"
fi
# Older installs: the emails' sender name.
if [ "$(get SMTP_FROM_NAME)" = "$(get SITE_NAME) LoNSeMonSy" ]; then set_env SMTP_FROM_NAME "$(get SITE_NAME) via LoNSeMonSy"; fi
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
if [ -n "$ai" ]; then
  set_env AI_ENABLED true
  set_env OLLAMA_URL "$ai_url"
fi
