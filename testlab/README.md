# Test lab

A fake small-company network we attack in **staging** to prove detection works. It is for our testing only; customers don't need it.

| Machine | Plays | Monitored |
|---|---|---|
| `srv-files01` | the company's file server | yes, Wazuh agent |
| `ws-reception` | an employee PC | yes, Wazuh agent |
| `kali-redteam` | the attacker | no |

## Build it

The lab is three small [Proxmox containers](https://pve.proxmox.com/wiki/Linux_Container). On the Proxmox host, as root:

```bash
MANAGER_IP=<appliance-ip> bash build-company-lab.sh
```

## Run the attack

From `kali-redteam`, brute-force SSH on `srv-files01`, then watch the alert appear in Grafana and the attacker get blocked.

## Remove it

```bash
for id in 8101 8102 8103; do pct stop $id; pct destroy $id; done
```
