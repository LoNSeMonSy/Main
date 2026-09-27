# Enroll a host

Any Debian-based machine (including a Proxmox node) can report to the appliance by
installing a Wazuh agent. Copy `enroll-host.sh` to the host and run it as root:

```bash
scp wazuh/enroll-host.sh root@<host>:/root/ && ssh root@<host> 'bash /root/enroll-host.sh <name> --no-active-response'
```

- `<name>` is how the machine shows up in Wazuh and Grafana (e.g. `mainserver`).
- Use `--no-active-response` on Proxmox hosts. Automatic IP blocking is fine on a
  regular server, but on a hypervisor a wrong block can cut off every VM behind it.
- The agent version is pinned to match the manager (`4.14.8-1`) and held, so a routine
  `apt upgrade` on the host can't put it ahead of the appliance.

Check it registered, on the appliance:

```bash
sudo /var/ossec/bin/agent_control -l
```

## Our hosts

| Host | IP | Notes |
|---|---|---|
| mainserver | 192.168.12.230 | Proxmox node, run with `--no-active-response` |
| backupserver | 192.168.12.130 | Proxmox node (PBS runs in VM 101), run with `--no-active-response`. Reach it from mainserver: `ssh root@192.168.12.130` |

## Network switch

A switch can't run an agent. To get its logs in, point the switch's syslog at the
appliance (UDP 514) and add a `<remote>` syslog block to the manager's `ossec.conf`
allowing the switch's IP. See the
[Wazuh syslog docs](https://documentation.wazuh.com/current/user-manual/capabilities/log-data-collection/syslog.html).
