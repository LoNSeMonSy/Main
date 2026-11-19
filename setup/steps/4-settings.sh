# shellcheck shell=bash
# Step 4: fill in the settings nobody should have to type.

# Random passwords and keys, only where they're still blank.
# Long ones only the programs use; short ones for the logins people type.
for key in INFLUXDB_ADMIN_PASSWORD INFLUXDB_ADMIN_TOKEN BACKUP_PASSWORD; do
  if [ -z "$(get $key)" ]; then
    set_env "$key" "$(openssl rand -hex 24)"
    echo "  generated $key"
  fi
done
for key in GRAFANA_ADMIN_PASSWORD NETALERTX_PASSWORD; do
  if [ -z "$(get $key)" ]; then
    set_env "$key" "$(short_pw)"
    echo "  generated $key"
  fi
done
# NetAlertX keeps only a SHA-256 of its password.
set_env NETALERTX_PASSWORD_HASH "$(printf '%s' "$(get NETALERTX_PASSWORD)" | sha256sum | cut -d' ' -f1)"

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
