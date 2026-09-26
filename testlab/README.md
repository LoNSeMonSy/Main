# Test lab — a replica of a small company network

Purpose: demonstrate the LoNSeMonSy appliance protecting a realistic small business,
not just itself. It stands up a few lightweight machines the SIEM monitors, plus an
attacker, so detection can be shown end to end.

## How the "sync across VMs" actually works

There is **one** appliance (the SIEM). Every machine you want watched runs a **Wazuh
agent** that reports to it over the LAN. That agent→manager reporting *is* the sync —
there is no second appliance to keep in step, and nothing to clone. Add a machine to
the company by adding an agent; its events appear in the same Wazuh automatically.

```
        srv-files01 ─┐
        ws-reception ─┼─(Wazuh agents)─▶  appliance (192.168.12.112)  ─▶ Grafana
        (more as needed) ─┘                    the one SIEM / manager

        attacker ───────(no agent; it's the threat)──▶ attacks the company
```

## The company (minimal, extensible)

| Machine | Stands for | Monitored |
|---|---|---|
| srv-files01 | the company's server | yes |
| ws-reception | an employee PC | yes |
| kali-redteam | external/compromised host | no (adversary) |

Add more employees/servers by editing the `LAB=(...)` list at the top of
`build-company-lab.sh` — each line is one container.

## Running it

`build-company-lab.sh` runs **on the Proxmox host** (needs `pct`), not inside the
appliance. It creates the containers on `vmbr0`, installs Wazuh agents pointed at the
appliance, and puts attack tools on the attacker. It is re-runnable and prints the
demo attack + teardown commands at the end.

## What will and won't be detected (be honest in the writeup)

- **SSH brute force: detected.** Host-based, via the agent on srv-files01. This is
  the working scenario.
- **Port scan: not yet.** Needs network visibility (a mirror port) the appliance does
  not have — see docs/DECISIONS.md. The `nmap` step runs, but Wazuh won't flag it until
  that mirror exists. Present it as a known, scoped limitation, not a gap you missed.

## Footprint

3 LXCs ≈ 1.3 GB RAM configured (far less used) and ~12 GB disk on `local`. Fits
alongside the 8 GB appliance once WIZARDTEST is stopped.
