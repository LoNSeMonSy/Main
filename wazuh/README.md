# Wazuh

LoNSeMonSy uses [Wazuh](https://documentation.wazuh.com/current/index.html) as its detection engine.

| File | What it is |
|---|---|
| `local_rules.xml` | our own detection rules |
| `lonsemonsy_rules.xml` | rules every install gets (for example, ignoring routine Docker health checks) |
| `active-response.xml` | automatic blocking of SSH brute-force attackers |
| `ism-policy.json` | how long alerts are kept |
| `enroll-host.sh` | adds a Linux machine to monitoring |

## Monitor another machine

Copy `enroll-host.sh` to the machine and run it as root, with the appliance's IP and the name the machine should show in the dashboard:

```bash
sudo WAZUH_MANAGER=<appliance-ip> bash enroll-host.sh <machine-name>
```

For Windows and macOS, use Wazuh's [agent install guide](https://documentation.wazuh.com/current/installation-guide/wazuh-agent/index.html).

## Test detection

From another machine on the network, fail to log in over SSH ten times:

```bash
for i in $(seq 1 10); do ssh -o BatchMode=yes baduser@<appliance-ip> true; done
```

The alert shows up in Grafana, and that machine is blocked for 10 minutes.
