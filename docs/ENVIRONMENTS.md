# Environments

| | Branch | Where it runs | Used for |
|---|---|---|---|
| **Dev** | `dev` | any machine with Docker | building and trying changes |
| **Staging** | `staging` | a test copy of LoNSeMonSy | testing a change before release |
| **Production** | `main` | a customer's machine | the released version |

## How a change moves

1. Commit to **dev** and try it.
2. Merge into **staging**, install it on the test machine, check Grafana and Wazuh.
3. If it passes, merge into **main**. Installs update with `lonsemonsy update`.

## Our test machines

- **fakedata:** a small machine with a Wazuh agent, so a test install always has real alerts to show.
- **attacker:** used to test brute-force detection and auto-block.
