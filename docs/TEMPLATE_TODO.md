# LoNSeMonSy: Template TODO

Running list of everything that's still personal/site-specific and needs to become
customer-configurable before this can ship as a template. Feeds directly into the
Phase 3 first-boot wizard/packaging work (see ROADMAP.md). Append new entries as
they're found — don't fix them silently, don't just mention them in passing.

Each entry: what's hardcoded, why it's not a simple value-swap for the wizard (if
it isn't), and when it was flagged.

---

## PVE_NODES structure (pbs_backup_task.py)
Hardcodes both IPs and node names (mainserver, backupserver) as a list. Not a simple
value-swap for the wizard, a customer's Proxmox nodes won't share these names. Wizard
needs to dynamically discover or prompt for node name+IP pairs as a set, not just
substitute fixed values. Flagged during the July 2026 site-specific-values audit.
