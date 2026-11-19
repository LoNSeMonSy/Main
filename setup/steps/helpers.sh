# shellcheck shell=bash
# Small functions the setup steps use.
ENV=appliance/.env                    # the settings file
owner=$(stat -c %U .)                 # the person who downloaded this folder

# get KEY: print one setting from the settings file.
get() { grep -E "^$1=" "$ENV" | cut -d= -f2- || true; }

LOG=/var/log/lonsemonsy-setup.log   # everything the installers print goes here (only root can read it)
touch "$LOG" 2>/dev/null && chmod 600 "$LOG" 2>/dev/null || true

# step N TITLE: the heading each step starts with, e.g. "[3/10] ███░░░░░░░ Docker".
step() {
  local bar
  bar=$(printf '%*s' "$1" '' | sed 's/ /█/g')$(printf '%*s' $((10 - $1)) '' | sed 's/ /░/g')
  if [ -t 1 ]; then printf '\n\033[1m[%s/10] %s %s\033[0m\n' "$1" "$bar" "$2"; else printf '\n[%s/10] %s\n' "$1" "$2"; fi
}

# run "WHAT" COMMAND...: run COMMAND with its output going to the log, while showing a
# spinner, the time so far and the newest log line. If it fails, show the end of the log.
run() {
  local what=$1 start=$SECONDS i=0 width line pid from
  local spin=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  shift
  echo "== $what ($(date))" >> "$LOG"
  from=$(wc -l < "$LOG")
  "$@" >> "$LOG" 2>&1 &
  pid=$!
  if [ -t 1 ]; then
    while kill -0 "$pid" 2>/dev/null; do
      width=$(( $(tput cols 2>/dev/null || echo 80) - ${#what} - 16 ))
      line=$(tail -n1 "$LOG" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r' | tr -s ' ' | cut -c1-$(( width > 1 ? width : 1 )))
      printf '\r\033[K  %s %s (%s)  \033[2m%s\033[0m' "${spin[i++ % 10]}" "$what" "$(took "$start")" "$line"
      sleep 0.2
    done
    printf '\r\033[K'
  else
    echo "  $what..."
  fi
  if wait "$pid"; then
    echo "  ✓ $what ($(took "$start"))"
  else
    echo "  ✗ $what failed. The end of the log ($LOG):"
    tail -n +"$((from + 1))" "$LOG" | tail -n 15 | sed 's/^/      /'
    return 1
  fi
}
took() { local s=$((SECONDS - $1)); printf '%d:%02d' $((s / 60)) $((s % 60)); }

# ask VAR TOPIC PROMPT [hidden]: read an answer into VAR. "?" shows TOPIC's part of setup/HELP.md.
ask() {
  local _answer
  while true; do
    if [ "${4:-}" = hidden ]; then read -r -s -p "  $3" _answer; echo; else read -r -p "  $3" _answer; fi
    if [ "$_answer" != "?" ]; then printf -v "$1" '%s' "$_answer"; return 0; fi
    show_help "$2"
  done
}

# confirm TOPIC PROMPT DEFAULT: true when the answer (or DEFAULT, Y or N) is yes.
confirm() {
  local answer
  ask answer "$1" "$2"
  [[ ${answer:-$3} == [Yy]* ]]
}

# show_help TOPIC: print the "## TOPIC" part of setup/HELP.md, without the Markdown marks.
show_help() {
  echo
  if [ -z "$1" ]; then
    echo "    Y keeps these answers. n goes through the questions again."
  else
    awk -v t="## $1" '$0 == t {on = 1; next} on && /^## / {exit} on' setup/HELP.md |
      sed -E 's/\*\*//g; s/`//g; s/\[([^]]*)\]\(([^)]*)\)/\1 (\2)/g; s/^/    /'
  fi
  echo
}

# set_env KEY VALUE: remove the old line and add the new one at the end.
# (Safe for any characters in VALUE, like the | & / in passwords.)
set_env() {
  sed -i "/^$1=/d" "$ENV"
  echo "$1=$2" >> "$ENV"
}

# wait_for_updates: after a reboot Ubuntu installs its own updates in the background,
# and nothing else can install packages until they finish.
updating() { pgrep -f '/usr/bin/unattended-upgrade$' >/dev/null || pgrep -x dpkg >/dev/null; }
wait_for_updates() {
  if updating; then
    run "Waiting for Ubuntu's automatic updates to finish (can take 10-20 minutes)" \
      bash -c 'while pgrep -f "/usr/bin/unattended-upgrade$" >/dev/null || pgrep -x dpkg >/dev/null; do tail -n1 /var/log/unattended-upgrades/unattended-upgrades-dpkg.log 2>/dev/null; sleep 5; done'
  fi
}

# need PROGRAM PACKAGE: install PACKAGE with apt if PROGRAM is missing.
need() {
  if ! command -v "$1" >/dev/null; then
    if ! run "Installing $2" env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=1800 install -y "$2"; then
      echo "  Couldn't install $2. Check the internet connection and run setup again."; exit 1
    fi
  fi
}

# ask_bucket: asks where cloud backups go and checks that the bucket answers.
# Sets repo (empty if skipped), bucket, key_id and secret.
ask_bucket() {
  repo=""
  echo "  Type ? at any of these to see where Backblaze shows them."
  while true; do
    ask endpoint Backups "Bucket endpoint, e.g. s3.us-east-005.backblazeb2.com (Enter to skip): "
    endpoint=${endpoint#https://}; endpoint=${endpoint#s3:}; endpoint=${endpoint%/}
    if [ -z "$endpoint" ]; then return; fi
    if [[ $endpoint == */* ]]; then bucket=${endpoint#*/}; endpoint=${endpoint%%/*}   # name pasted too
    else ask bucket Backups "Bucket name: "; fi
    ask key_id Backups "Key ID (Backblaze calls it keyID): "
    ask secret Backups "Secret key (Backblaze calls it applicationKey, hidden): " hidden
    # Backblaze: its own connection (b2:), which takes any of its keys. Others: S3.
    if [[ $endpoint == *backblazeb2.com ]]; then repo="b2:$bucket:lonsemonsy"; else repo="s3:$endpoint/$bucket"; fi
    need restic restic
    echo "  checking the bucket..."
    # An empty bucket answers "does not exist" (Backblaze: 404), one with backups "wrong password".
    out=$(RESTIC_REPOSITORY=$repo RESTIC_PASSWORD=check AWS_ACCESS_KEY_ID=$key_id AWS_SECRET_ACCESS_KEY=$secret \
      B2_ACCOUNT_ID=$key_id B2_ACCOUNT_KEY=$secret timeout 60 restic cat config 2>&1 || true)
    if grep -qiE "repository does not exist|key does not exist|file_by_name: 404|wrong password|no key found" <<<"$out"; then
      return
    fi
    echo "$out" > /var/log/lonsemonsy-bucket-check.log   # restic's whole answer (no keys in it)
    echo "  The bucket didn't answer: $(grep -m1 -iE 'fatal|error|denied' <<<"$out" | cut -c1-160)"
    if ! confirm Backups "Check the endpoint, bucket name and keys. Try again? [Y/n]: " Y; then repo=""; return; fi
  done
}

# Wazuh's passwords are in the bundle its installer leaves (only root can read it).
# Setup copies them to a temporary file while it needs them; it's deleted at the end.
BUNDLE=/root/wazuh-install-files.tar
WPASS=$(mktemp)
trap 'rm -f "$WPASS"' EXIT
wazuh_password() {   # wazuh_password USER: print that Wazuh user's password
  grep -A1 "indexer_username: '$1'" "$WPASS" | grep -oP "indexer_password: '\K[^']+" || true
}

# Restart Wazuh cleanly: wait for its old API to close first. On a slow machine a quick
# restart can leave the old API holding port 55000, and Wazuh's dashboard then can't log in.
wazuh_restart() {
  systemctl stop wazuh-manager
  for _ in $(seq 1 30); do
    if ! pgrep -f "[w]azuh_apid" >/dev/null; then break; fi
    sleep 2
  done
  pkill -9 -f "[w]azuh_apid" || true
  systemctl start wazuh-manager
}
