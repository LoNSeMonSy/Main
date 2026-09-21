# LoNSeMonSy: Key Decisions and Why

## Why we moved off InfluxDB Cloud / Grafana Cloud
Our pitch is "your data stays local." Sending security events to a cloud vendor 
contradicted that directly. Summer rebuild swaps both for self-hosted OSS versions 
running in Docker on the appliance VM.

## Why Docker
The product has to be shippable to a customer's own Proxmox host, on their own subnet, 
without us configuring anything by hand. Docker Compose turns the whole stack into one 
file. Packaging becomes "copy this file, run one command" instead of a manual install 
per customer.

## Why one appliance VM/guest, not our whole lab
Our original prototype is two physical Proxmox hosts with hardcoded IPs 
(192.168.12.x). That can't be shipped, it only works on our specific network. 
The shippable unit is a single guest (VM or LXC) that runs on top of whatever Proxmox 
the customer already has. Internal services talk over localhost/Docker service names. 
External connections read from a config file, not hardcoded values.

## Why local-first isn't the whole business pitch
Homelabbers value local-first but won't pay for it, they'd build it free themselves. 
Small businesses will pay, but for convenience and support, not for the local-first 
angle specifically. Local-first is a real technical/ethical stance, not the revenue 
driver. Revenue comes from turnkey delivery to people with no time to self-host.

## Why detection is the real fall-semester priority
Demo day backups worked but didn't impress, because backups alone aren't "security 
monitoring." Detection (catching an actual attack) is what makes the product live up 
to its name. Everything else (wizard, packaging, VLAN quarantine) depends on detection 
existing first.

## Why the first-boot wizard only targets security config, not general IT literacy
The wizard removes security configuration complexity, not general IT literacy — 
we're not building for a zero-technical-knowledge user. It assumes the person running 
it (owner, part-time IT contractor, or MSP) is comfortable with basic sysadmin/
networking concepts like IP addresses and running a server. What it removes is having 
to know security-specific things: how to write detection rules, harden services, or 
configure alerting correctly. See OVERVIEW.md for the full target-user definition.

## Why VLAN quarantine and networking come last
Quarantine is an action taken in response to a detection. It can't be built or tested 
meaningfully before detection rules exist and reliably fire. Sequence: detect first, 
act second.

## Why we're not building a custom dashboard UI
Grafana already does what we need (time series graphs, table panels for NOC-style 
views). Building a custom frontend is real engineering scope we don't have time for 
in a 3-month fall window. Time is better spent on detection logic, the part that's 
actually new and hard.

## Why we're deploying Wazuh rather than writing the detection layer ourselves
Detection rules in Wazuh are declarative XML in `ossec.conf` and its rule files, and
SSH brute-force is covered by decoders it already ships with. That makes the fall
detection work configuration and tuning rather than new application code, which is
both faster for a 3-month window and something every member of the team can read and
explain. It also brings its own dashboard, so we are not maintaining a display either.
The cost is honest: Wazuh covers one of our three scenarios out of the box, and its
documented all-in-one minimum is well above what the appliance VM has today.

## Why the appliance VM is being resized rather than kept lightweight
`mainserver` has 16 GB total, and we are allocating 8 GB of it to the appliance guest
to meet Wazuh's documented all-in-one minimum. This is a real concession: OVERVIEW.md
sells "runs on a cheap mini PC", and an 8 GB floor raises the bill of materials for a
shipped appliance. We are accepting it for the school project because the alternative
is writing the detection layer ourselves, which we cannot defend as our own work. If
the product is ever taken further, a headless Wazuh manager without the indexer and
dashboard is the path back to a small footprint.

## Why network visibility, and port-scan detection with it, is deferred
The appliance is an ordinary bridged guest on `vmbr0`: one `eth0`, no promiscuous mode,
and it is not the gateway. It therefore sees only traffic addressed to it, so port-scan
detection cannot work no matter which SIEM we run — this is not a tool-choice problem.
Fixing it means a mirror/SPAN on the Proxmox bridge or making the appliance the gateway,
both of which touch host networking and are Tim's call under the safety rule in
appliance/CLAUDE.md. Deferred rather than dropped: Wazuh is host-based and gives us
scenario 1 without it, and Suricata can be added later as configuration once the mirror
exists. If it never does, port scan comes out of Phase 2 and we document why.
