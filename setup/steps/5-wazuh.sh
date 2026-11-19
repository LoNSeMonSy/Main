# shellcheck shell=bash
# Step 5: the Wazuh server (the detection engine), installed with Wazuh's own installer:
# https://documentation.wazuh.com/current/quickstart.html

if [ "${SKIP_WAZUH:-0}" = 1 ]; then
  echo "  wazuh: skipped"
elif [ -d /var/ossec ]; then
  echo "  wazuh: already installed"
else
  ver=$(grep '^WAZUH=' setup/PINNED_VERSIONS | cut -d= -f2 | cut -d. -f1,2)   # e.g. 4.14
  ignore=""
  if [ "$(free -g | awk '/Mem/{print $2}')" -lt 7 ]; then
    echo "  note: Wazuh wants 8 GB of memory. It will run on less, but slowly."
    ignore="-i"                       # tell Wazuh's installer not to stop on that
  fi
  echo "  Wazuh's installer adds the indexer (stores alerts), the manager (finds attacks),"
  echo "  Filebeat (connects the two) and the Wazuh dashboard. It takes 15-20 minutes."
  curl -fsSo /root/wazuh-install.sh "https://packages.wazuh.com/$ver/wazuh-install.sh"
  run "Installing Wazuh $ver" bash -c "cd /root && bash wazuh-install.sh -a $ignore"
fi

# Grafana reads the alerts with Wazuh's built-in read-only user "readall".
if [ -f "$BUNDLE" ]; then
  tar -O -xf "$BUNDLE" wazuh-install-files/wazuh-passwords.txt > "$WPASS"
  if [ -z "$(get WAZUH_INDEXER_PASSWORD)" ]; then
    set_env WAZUH_INDEXER_USER readall
    set_env WAZUH_INDEXER_PASSWORD "$(wazuh_password readall)"
    echo "  grafana will read Wazuh alerts as the read-only user 'readall'"
  fi
fi
