#!/usr/bin/env bash
# LoNSeMonSy -- port-scan detection (Suricata IDS -> Wazuh -> Grafana).
#
# One command, idempotent, safe to re-run:
#     sudo appliance/suricata/install-suricata.sh
#
# Nothing here is specific to one network. HOME_NET is DERIVED from
# whatever interface the appliance actually has, at every service start, so the
# same repo installs correctly at a customer on 10.4.0.0/16 with no edits.
#
# Passive by design: Suricata only sniffs. It never changes routing, never touches
# vmbr0, and no active-response/auto-ban is configured. Fully reversible -- see the
# "Rollback" section of docs/PORTSCAN.md.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> installing suricata"
DEBIAN_FRONTEND=noninteractive apt-get install -y suricata >/dev/null

echo "==> site config (policy only -- no network literals)"
install -m 755 "$HERE/lonsemonsy-homenet"            /usr/local/sbin/lonsemonsy-homenet
[ -e /etc/default/lonsemonsy-suricata ] || \
  install -m 644 "$HERE/lonsemonsy-suricata.default" /etc/default/lonsemonsy-suricata

echo "==> scan-only ruleset (full ET Open is ~69k rules; we keep ~367)"
install -m 644 "$HERE/disable.conf" /etc/suricata/disable.conf
install -m 644 "$HERE/enable.conf"  /etc/suricata/enable.conf
suricata-update --quiet

echo "==> tuning suricata.yaml (eve.json = alerts only, stats interval)"
python3 - <<'PY'
import re
p = "/etc/suricata/suricata.yaml"
s = open(p).read()
# eve.json: stock config logs flow/dns/tls/http for every packet (~120 MB/day) and
# would flood the Wazuh indexer for zero detection benefit. Scan rules emit 'alert'.
if "LoNSeMonSy: alerts only" not in s:
    new = ("      types:\n"
           "        # LoNSeMonSy: alerts only. See docs/PORTSCAN.md.\n"
           "        - alert:\n"
           "            tagged-packets: yes\n")
    s = re.sub(r"^      types:\n(?:(?:        .*|\s*)\n)*?(?=  - [a-z]|  # a line based)",
               new + "\n", s, count=1, flags=re.M)
# stats.log at the stock 8s interval is ~94 MB/day on an appliance disk.
s = re.sub(r"^(stats:\n(?:.*\n)*?  interval:) 8$", r"\1 600", s, count=1, flags=re.M)
open(p, "w").write(s)
PY

echo "==> systemd: derive HOME_NET at start, weekly rule refresh"
mkdir -p /etc/systemd/system/suricata.service.d
install -m 644 "$HERE/10-lonsemonsy-homenet.conf" /etc/systemd/system/suricata.service.d/
install -m 644 "$HERE/suricata-update.service"    /etc/systemd/system/
install -m 644 "$HERE/suricata-update.timer"      /etc/systemd/system/

echo "==> log rotation (packaged file ships no frequency, so it inherited weekly)"
if ! grep -q '^[[:space:]]*daily' /etc/logrotate.d/suricata; then
  sed -i '0,/^{$/s/^{$/{\n\tdaily\n\tmaxsize 50M/' /etc/logrotate.d/suricata
fi

echo "==> wazuh: ingest eve.json (native json decoder, stock rules 86600/86601)"
if ! grep -qi suricata /var/ossec/etc/ossec.conf; then
  cp -a /var/ossec/etc/ossec.conf "/var/ossec/etc/ossec.conf.pre-suricata-$(date +%Y%m%d%H%M)"
  python3 - <<'PY'
p = "/var/ossec/etc/ossec.conf"
s = open(p).read()
s = s.replace("\n</ossec_config>", """
  <!-- LoNSeMonSy: Suricata IDS. eve.json is trimmed to 'alert' events only. -->
  <localfile>
    <log_format>json</log_format>
    <location>/var/log/suricata/eve.json</location>
  </localfile>

</ossec_config>""", 1)
open(p, "w").write(s)
PY
fi

echo "==> validating before restart"
suricata -T -c /etc/suricata/suricata.yaml \
  --set vars.address-groups.HOME_NET="[$(/usr/local/sbin/lonsemonsy-homenet)]" >/dev/null

systemctl daemon-reload
systemctl enable --now suricata-update.timer >/dev/null
systemctl enable suricata >/dev/null
systemctl restart suricata
systemctl restart wazuh-manager

echo
echo "HOME_NET   : [$(/usr/local/sbin/lonsemonsy-homenet)]  (policy: derived, not hardcoded)"
echo "rules      : $(grep -c '^alert' /var/lib/suricata/rules/suricata.rules || echo '?') enabled"
echo "suricata   : $(systemctl is-active suricata)"
echo "wazuh      : $(systemctl is-active wazuh-manager)"
echo
echo "Verify with a scan from another host on the LAN, then watch:"
echo "  sudo tail -f /var/ossec/logs/alerts/alerts.json | grep -i suricata"
