# shellcheck shell=bash
# Small functions the setup steps use.
ENV=appliance/.env                    # the settings file
owner=$(stat -c %U .)                 # the person who downloaded this folder

# get KEY: print one setting from the settings file.
get() { grep -E "^$1=" "$ENV" | cut -d= -f2- || true; }

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
