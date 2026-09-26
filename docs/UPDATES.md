# Updates

LoNSeMonSy is several systems (InfluxDB, Grafana, Wazuh, NetAlertX, plus our own
services), so "update" has to cover all of them coherently. The design makes this simple:
**every version is pinned in `VERSIONS` and tracked in git, so an update is a `git pull` +
redeploy.** Your config (`.env`) and data (Docker volumes) are preserved across updates.

## How each part updates

| Part | How it updates | Data safe? |
|---|---|---|
| Docker services (InfluxDB, Grafana, NetAlertX) | `docker compose pull && docker compose up -d` pulls the new pinned images | ✅ volumes persist |
| Our services (backup-trigger, audit-collector) | rebuilt from the new repo code (`up -d --build`) | ✅ |
| Wazuh (server + agents) | its **own** package manager — see caveat below | ✅ |

## The one command

```bash
./setup/update.sh
```

It pulls the new release from GitHub, pulls the new pinned images, and restarts the stack —
keeping `.env` and all data. (Wazuh is handled separately; see below.)

## Who does it, and when

Per SRS 5.4: updates ship through the **GitHub repository**, and the customer (owner or their
IT/MSP) pulls and applies them, on a **quarterly** cadence. Config-first + pinned versions is
what makes "pull the new release, re-run one command" reliable — nothing about the customer's
setup changes except the version numbers.

## Do this first, every time

**Snapshot the appliance VM in Proxmox before updating.** That is your rollback: if an update
misbehaves, restore the snapshot and you're back in seconds. Ideally test the new release in
staging before touching a production site.

## Honest caveats

- **Wazuh is the exception to the one command.** It installs natively (not in Compose), so it
  updates through its own package manager, and its **manager, indexer, and agents must stay on
  matching versions**. A Wazuh version bump is a deliberate, separate step — see the
  [Wazuh upgrade guide](https://documentation.wazuh.com/current/upgrade-guide/).
- **Breaking changes need release notes.** A pinned-version bump that changes a config format
  (e.g. a Grafana dashboard schema) should be called out in the release so operators know.
