# Test lab

A fake small-company network we attack in staging to prove detection works. Customers don't need it.

| Machine | Plays | Wazuh agent |
|---|---|---|
| `srv-files01` | the file server | yes |
| `ws-reception` | an employee PC | yes |
| `kali-redteam` | the attacker | no |

**Build it** (three [Proxmox containers](https://pve.proxmox.com/wiki/Linux_Container); on the Proxmox host, as root):

```bash
MANAGER_IP=<lonsemonsy-ip> bash build-company-lab.sh
```

**Attack:** from `kali-redteam`, brute-force SSH on `srv-files01`. The alarm appears in Grafana and the attacker gets blocked.

**Remove it:** `for id in 8101 8102 8103; do pct stop $id; pct destroy $id; done`
