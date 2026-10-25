# Wazuh

LoNSeMonSy uses [Wazuh](https://documentation.wazuh.com/current/index.html) as its detection engine.

| File | What it is |
|---|---|
| `local_rules.xml` | our own detection rules |
| `lonsemonsy_rules.xml` | rules every install gets (for example, ignore routine Docker health checks) |
| `active-response.xml` | auto-block for SSH brute force |
| `ism-policy.json` | keeps 90 days of alerts |
| `enroll-host.sh` | adds a Linux computer |

## Protect a computer

Install a Wazuh agent on it, pointed at the LoNSeMonSy machine's IP address.

**Windows** (PowerShell as administrator):

```powershell
Invoke-WebRequest -Uri https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.8-1.msi -OutFile $env:tmp\wazuh-agent.msi; msiexec.exe /i $env:tmp\wazuh-agent.msi /q WAZUH_MANAGER='<lonsemonsy-ip>' WAZUH_AGENT_NAME='<pc-name>'; Start-Sleep 20; NET START WazuhSvc
```

**Linux** (copy `enroll-host.sh` to it first):

```bash
sudo WAZUH_MANAGER=<lonsemonsy-ip> bash enroll-host.sh <pc-name>
```

**macOS:** follow Wazuh's [agent guide](https://documentation.wazuh.com/current/installation-guide/wazuh-agent/index.html), or use *Agents > Deploy new agent* in the Wazuh dashboard.

## Test it

From another computer, fail to log in over SSH ten times:

```bash
for i in $(seq 1 10); do ssh -o BatchMode=yes baduser@<lonsemonsy-ip> true; done
```

An alarm shows up in Grafana, and that computer is blocked for 10 minutes.
