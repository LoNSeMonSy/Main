# Environments

| | Branch | Where it runs | Used for |
|---|---|---|---|
| **Dev** | `dev` | any machine with Docker (`docker compose up -d`) | building and trying changes |
| **Staging** | `staging` | a separate copy of the appliance, plus the [test lab](../testlab/README.md) | testing a change against real attacks before release |
| **Production** | `main` | a customer's appliance | the released version |

## How a change moves

1. Commit to **dev** and try it locally.
2. Merge into **staging**, install it on the staging appliance, run the test lab attacks, check Grafana.
3. If it passes, merge into **main**. Appliances update with `lonsemonsy update`.

## Staging today

- The test lab is three small containers: `srv-files01` (server), `ws-reception` (PC) and `kali-redteam` (attacker).
- We take a backup before changing an appliance, so any change can be rolled back.
- Next: a dedicated mini PC as the staging appliance, fully separate from everything else.
