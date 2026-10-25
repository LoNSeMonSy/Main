# shellcheck shell=bash
# Step 5: the Wazuh server (the detection engine), installed with Wazuh's own installer:
# https://documentation.wazuh.com/current/quickstart.html

if [ "${SKIP_WAZUH:-0}" = 1 ]; then
  echo "  wazuh: skipped"
elif [ -d /var/ossec ]; then
  echo "  wazuh: already installed"
else
  ver=$(grep '^WAZUH=' PINNED_VERSIONS | cut -d= -f2 | cut -d. -f1,2)   # e.g. 4.14
  ignore=""
  if [ "$(free -g | awk '/Mem/{print $2}')" -lt 7 ]; then
    echo "  note: Wazuh wants 8 GB of memory. It will run on less, but slowly."
    ignore="-i"                       # tell Wazuh's installer not to stop on that
  fi
  echo "  installing Wazuh $ver (15-20 minutes, log: /root/wazuh-install.log)"
  curl -fsSo /root/wazuh-install.sh "https://packages.wazuh.com/$ver/wazuh-install.sh"
  (cd /root && bash wazuh-install.sh -a $ignore > /root/wazuh-install.log 2>&1) &
  pid=$!
  # Show each part as Wazuh's installer reaches it.
  shown=""
  while kill -0 "$pid" 2>/dev/null; do
    part=$(grep -oE "Starting (Wazuh indexer|the Wazuh manager|Filebeat|Wazuh dashboard) installation" /root/wazuh-install.log | tail -1)
    if [ "$part" != "$shown" ]; then
      case "$part" in
        *indexer*)   echo "    [1/4] the indexer (stores the alerts)" ;;
        *manager*)   echo "    [2/4] the manager (the detection engine)" ;;
        *Filebeat*)  echo "    [3/4] Filebeat (connects the two)" ;;
        *dashboard*) echo "    [4/4] the Wazuh dashboard" ;;
      esac
      shown=$part
    fi
    sleep 5
  done
  if ! wait "$pid"; then echo "  Wazuh install failed. See /root/wazuh-install.log"; exit 1; fi
  echo "  wazuh: installed"
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
