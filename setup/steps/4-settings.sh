# shellcheck shell=bash
# Step 4: fill in the settings nobody should have to type.

# Random passwords and keys, only where they're still blank.
for key in INFLUXDB_ADMIN_PASSWORD INFLUXDB_ADMIN_TOKEN GRAFANA_ADMIN_PASSWORD; do
  if [ -z "$(get $key)" ]; then
    set_env "$key" "$(openssl rand -hex 24)"
    echo "  generated $key"
  fi
done

# This machine's time zone.
if [ -z "$(get TZ)" ]; then
  set_env TZ "$(timedatectl show -p Timezone --value)"
  echo "  time zone: $(get TZ)"
fi

# The network NetAlertX scans for devices.
if [ -z "$(get SCAN_SUBNETS)" ]; then
  set_env SCAN_SUBNETS "$lan --interface=$iface"
  echo "  network scanner will scan $lan"
fi
