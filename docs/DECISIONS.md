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

## Why VLAN quarantine and networking come last
Quarantine is an action taken in response to a detection. It can't be built or tested 
meaningfully before detection rules exist and reliably fire. Sequence: detect first, 
act second.

## Why we're not building a custom dashboard UI
Grafana already does what we need (time series graphs, table panels for NOC-style 
views). Building a custom frontend is real engineering scope we don't have time for 
in a 3-month fall window. Time is better spent on detection logic, the part that's 
actually new and hard.
