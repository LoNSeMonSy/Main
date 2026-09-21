# Testing the SSH brute-force detection

Phase A needs **no new VMs**. The Wazuh manager already monitors this appliance's
own auth log as agent 000, so a failed-login loop against this host exercises the
whole chain: sshd -> Wazuh decoder -> rule -> alert -> (later) Grafana panel.

## 1. Generate failed logins
From ANY OTHER machine on the LAN (not the appliance itself), aim at the appliance
and let each attempt fail:

    for i in $(seq 1 10); do ssh baduser@192.168.12.112; done   # wrong user, will fail

Only ever target your own lab hosts. Never a real machine, never off your subnet.

## 2. Watch the alert fire
On the appliance:

    sudo tail -f /var/ossec/logs/alerts/alerts.json | grep -iE 'ssh|5710|5712|5716|100100'

You will see stock rules 5710/5716 per failure, then 5712 once the threshold trips.

## 3. Tune your rule, then prove it
Edit wazuh/local_rules.xml (fill in the TODOs), deploy and restart:

    sudo cp wazuh/local_rules.xml /var/ossec/etc/rules/local_rules.xml
    sudo systemctl restart wazuh-manager

Re-run step 1 and confirm rule **100100** now fires with YOUR level and wording.
That before/after — stock behaviour vs your tuned rule — is the thing to demo.

## Safety
No active-response (auto-ban) is configured, so this will not lock anyone out.
Before you ever enable active-response, whitelist your admin IP and the Tailscale
range first, or a demo can ban you from your own appliance.
