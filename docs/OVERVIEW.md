# LoNSeMonSy: Overview

## What this is
A local network security monitoring system. Runs on a customer's own Proxmox host, 
watches their network for attacks, alerts them, and (unlike most free tools) also 
handles backup so they can recover if an attack succeeds.

## Who it's for
Primary target: small businesses with no IT staff. Not homelabbers, they build free 
alternatives themselves and won't pay a subscription. Homelabbers are our test/proving 
ground, not our paying customer.

## Why this market exists
Two extremes exist today, nothing serves the middle:
- **Enterprise tools** (SentinelOne, ~$45k/yr for 250 endpoints): powerful, way too 
  expensive for a small shop.
- **Free/open tools** (Security Onion): powerful, free, but built for SOC analysts. 
  Assumes a dedicated security team a small business doesn't have.

LoNSeMonSy sits in the gap: turnkey, affordable, no expert required.

## What makes it different
- **Backup + detection fused.** No competitor (free or paid) combines "catch the 
  attack" with "recover from it." This came directly from our working backup system.
- **Local-first.** All data stays on the customer's own hardware. No cloud dependency, 
  no vendor seeing their security events. (This is why we moved off InfluxDB Cloud / 
  Grafana Cloud this summer, see DECISIONS.md.)
- **Plain-English AI alert explainer** (optional, local via Ollama). Explains what an 
  alert means to someone without security training.
- **Lightweight.** Runs on a cheap mini PC, not a beefy dedicated server.

## Business model reference
Modeled loosely on Security Onion Solutions: core software stays free, revenue comes 
from prebuilt hardware and support, not a software subscription.
