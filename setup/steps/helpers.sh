# shellcheck shell=bash
# Small functions the setup steps use.
ENV=appliance/.env                    # the settings file
owner=$(stat -c %U .)                 # the person who downloaded this folder

# get KEY: print one setting from the settings file.
get() { grep -E "^$1=" "$ENV" | cut -d= -f2- || true; }

# step N TITLE: the heading each step starts with, e.g. "[3/10] Docker" (bold on a screen).
step() {
  if [ -t 1 ]; then printf '\n\033[1m[%s/10] %s\033[0m\n' "$1" "$2"; else printf '\n[%s/10] %s\n' "$1" "$2"; fi
}

# set_env KEY VALUE: remove the old line and add the new one at the end.
# (Safe for any characters in VALUE, like the | & / in passwords.)
set_env() {
  sed -i "/^$1=/d" "$ENV"
  echo "$1=$2" >> "$ENV"
}

# need PROGRAM PACKAGE: install PACKAGE with apt if PROGRAM is missing.
need() {
  if ! command -v "$1" >/dev/null; then
    echo "  installing $2..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$2" >/dev/null 2>&1; then
      echo "  couldn't install $2. Check the internet connection and run setup again."; exit 1
    fi
  fi
}

# ask_bucket: asks where cloud backups go and checks that the bucket answers.
# Sets repo (empty if skipped), key_id and secret.
ask_bucket() {
  repo=""
  while true; do
    read -r -p "  Bucket endpoint, e.g. s3.us-east-005.backblazeb2.com (Enter to skip): " endpoint
    endpoint=${endpoint#https://}; endpoint=${endpoint#s3:}; endpoint=${endpoint%/}
    if [ -z "$endpoint" ]; then return; fi
    if [[ $endpoint == */* ]]; then bucket=${endpoint#*/}; endpoint=${endpoint%%/*}   # name pasted too
    else read -r -p "  Bucket name: " bucket; fi
    read -r -p "  Access key ID (Backblaze: keyID): " key_id
    read -r -s -p "  Secret access key (Backblaze: applicationKey, hidden): " secret; echo
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
    echo "  Check the endpoint, bucket name and key, and try again (or press Enter to skip)."
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
