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

## Trigger service port is fixed at 5001 in the Grafana button code
The "Run Backup Now" button no longer hardcodes an address — its update code derives the
host from `window.location.hostname`, so it follows however the operator reached Grafana
(LAN, Tailscale, or hostname). What remains hardcoded is the **port**, `const port = 5001`
inside the panel's JS. If the wizard ever lets the operator move the trigger service off
5001, it has to rewrite that line in the dashboard JSON too, not just `.env` — the panel
code is not reading compose config. Flagged August 2026; originally logged as a hardcoded
LAN IP, narrowed to the port after the browser-derived-host fix.
## PVE_HOST / PVE_NODE assume a single named Proxmox node (backup-trigger service)
`.env` carries one `PVE_HOST` + `PVE_NODE` pair (currently `192.168.12.230` /
`mainserver`), and the trigger service starts vzdump on exactly that node. Same
underlying problem as the PVE_NODES entry above: a customer may have several nodes, or
one named something else, and the backup they want triggered may not live on the node
the wizard happened to prompt for. Related to, but not solved by, that earlier entry.
Flagged August 2026.

## BACKUP_STORAGE is the PVE-side storage ID, not the PBS datastore name
The trigger service passes `BACKUP_STORAGE` straight to `vzdump --storage`. This is the
**PVE storage ID** for the PBS target, which is frequently *not* the same string as the
PBS datastore name (`BackupStorage`, hardcoded in `pbs_storage_stats.py`). The wizard has
to prompt for both, or discover the PVE storage ID by querying `/storage` and matching on
the PBS datastore. Left blank in `.env` deliberately rather than guessed. Flagged
August 2026. **Confirmed on this site:** the PVE storage ID is `pbs-aws` while the PBS
datastore is `BackupStorage` — two different strings for the same target, so the wizard
cannot derive one from the other.

## CORS_ORIGIN defaults to "*" on the backup-trigger service
The trigger endpoint accepts cross-origin POSTs from anywhere so the Grafana button works
out of the box. Combined with `TRIGGER_TOKEN` being empty by default, anything that can
reach port 5001 can start a backup. Fine on a trusted LAN, not fine for a shipped
appliance — the wizard should set `CORS_ORIGIN` to the Grafana origin and generate a
`TRIGGER_TOKEN`. Flagged August 2026.

## alerts-feed has no auth at all, and CORS_ORIGIN defaults to "*"
The live security alerts feed (port 5002) serves the whole alert history in its rolling
window to anyone who can reach the port — no token, no login, unlike `backup-trigger`
which at least has `TRIGGER_TOKEN`. It is read-only, so nothing can be *changed* through
it, but a security-alert feed is exactly the thing an attacker would like to read: it
shows them which of their probes you detected and which you did not. It also shares the
trigger service's `CORS_ORIGIN=*` default. Fine on a trusted LAN during the rebuild, not
fine for a shipped appliance — the wizard should put it behind the same auth story as
Grafana and set a real CORS origin. Flagged August 2026.

## ALERTGEN_ENABLED must be false before anything ships
`alert-generator` writes fabricated alerts (tagged `mode=test`) into `security_alerts` on
a 15–30s timer. It defaults to off in `docker-compose.yml`, but `.env` currently sets it
to `true` for demo/UI work. If that `.env` value is ever carried into a customer image the
appliance invents security alerts forever. The wizard should either force it false or drop
the service from the shipped compose file entirely. Flagged August 2026.

## ALERTGEN_LAN_PREFIX defaults to this site's subnet
The fake "new device on the LAN" alerts are built from `ALERTGEN_LAN_PREFIX`, defaulting
to `192.168.12` — this site's subnet, hardcoded as the default in `alertgen/config.py` and
in the compose interpolation. Purely cosmetic (it only affects how demo rows look), and it
is already `.env`-driven, but the *default* is site-specific and should become whatever
subnet the wizard discovers. Flagged August 2026.

## alerts-feed container port 5002 is baked into the image, not just .env
`ALERTS_HOST_PORT` moves the **host-side** port, but the container-internal port is fixed
at 5002 in `alerts/Dockerfile` (both `EXPOSE` and the gunicorn `--bind`). Same shape as the
trigger-service port entry above: if the wizard ever needs to move the internal port it has
to rebuild the image, not just rewrite `.env`. Low priority — remapping the host port covers
almost every real conflict. Flagged August 2026.

## PVE_TRIGGER_AUTHIDS identifies manual runs by one hardcoded token name (pbs_backup_task.py)
`resolve_source()` decides a backup was manual when the authid in the vzdump UPID is in
`PVE_TRIGGER_AUTHIDS`, defaulting to the single literal `root@pam!backuptoken` (overridable
from `/opt/pbs_config.env`). That name is whatever the operator happened to call the PVE API
token when they ran `pveum user token add`, so it will not match on a customer site, and the
failure is silent: every backup quietly reads "automatic" and nothing errors. The wizard has
to write this value at the same moment it mints the token, and keep it in step with the
appliance's `PVE_TOKEN_ID` in `.env` — the two are the same string, currently maintained in
two places on two different hosts. Note the discriminator itself is sound and worth keeping:
PBS cannot distinguish manual from scheduled at all (every backup arrives as `root@pam`,
the credential in PVE's storage config), so the PVE-side authid is the only signal there is.
Flagged August 2026 during the manual/automatic labelling fix.

## PBS-side scripts are not in the repo
`/opt/pbs_backup_task.py` and `/opt/pbs_storage_stats.py` live only on PBS, edited in place
with `.bak.<timestamp>` copies beside them. They are now a real part of the product — the
labelling logic in `pbs_backup_task.py` is not something to re-derive from a backup file — so
packaging needs them under version control in `appliance/` and deployed to PBS from there,
rather than hand-edited over SSH. Flagged August 2026.

## GRAFANA_DASHBOARD_PATH defaults to this site's dashboard UID
The hub's "Backups" nav link points at `/d/e01512b5-eef3-48f4-9c5e-f5f512b6bb7f/lonsemonsy-backups`,
the UID Grafana generated for the dashboard on *this* appliance. It is `.env`-driven and the
host part is derived from `window.location.hostname` (so it follows LAN or Tailscale), but the
UID itself is site-specific: a freshly provisioned Grafana mints a different one, and the link
would 404. The wizard has to read the UID back from Grafana's API after creating the dashboard
and write it into `.env`, rather than shipping this literal. Flagged September 2026.

## The hub now serves Tailscale audit logs with the same no-auth story as the alerts feed
The `alerts-feed` container (port 5002) grew two more sections — a link out to Grafana and an
Audit Logs table — and the audit table is a materially more sensitive read than the alert feed
covered by the entry above: it lists who changed what in the tailnet, with actor login names,
device names and old/new values. Anything that can reach port 5002 can read 90 days of tailnet
administrative history, with no token and no login. Same fix as the alerts-feed entry (put it
behind real auth and a real `CORS_ORIGIN`), but higher priority now. Flagged September 2026.
**Updated September 2026:** the hub also now exposes `POST /api/audit/poll`, an unauthenticated
write-shaped endpoint — it changes nothing locally, but anything that can reach 5002 can make the
appliance call out to the Tailscale API on demand. The poller itself is unpublished and only
reachable from the compose network, so the hub is the whole exposure; fixing the hub fixes both.
**Updated again September 2026:** the tab now also carries Proxmox VE audit data and a profile
drawer that resolves any actor or target to its full history — who logged in, from which token,
against which guest, over 90 days. That is a materially richer read than a list of rows, and it
is still behind no authentication whatsoever. This is now the single highest-value unauthenticated
endpoint on the appliance.

## TSAUDIT credentials are a second, separate credential store to provision
`TAILSCALE_OAUTH_CLIENT_ID`/`_SECRET` (or `TAILSCALE_API_KEY`) are per-tailnet secrets that
cannot be derived from anything else on the appliance — the operator has to create them by hand
in the Tailscale admin console, and the OAuth client must be scoped to `logs:configuration:read`
alone. The wizard cannot mint these itself (creating an OAuth client is not exposed through the
Tailscale API), so this is a prompt-and-paste step, and the appliance has to degrade cleanly
when it is skipped — which it does: `TSAUDIT_ENABLED` defaults false and the container idles.
Flagged September 2026.

## The PVE audit source needs Sys.Audit on / , which the current token only has by accident
`audit-collector`'s Proxmox source reads `/cluster/log`, which requires **Sys.Audit on /**. It works
on this site because `PVE_TOKEN_ID` was created with `--privsep 0`, so the token inherits `root@pam`'s
full permissions and every check passes. A wizard that does the right thing and mints a *least-privilege*
token for backups alone would silently break this source — the failure is a 403 on one endpoint, not a
startup error, so the Audit Logs tab would just show no Proxmox rows. Whatever the wizard generates has
to include Sys.Audit on / explicitly, or the audit source has to be documented as requiring its own
token. Flagged September 2026.

## PVEAUDIT_LOG_MAX is a guess about event volume, not a measured value
`/cluster/log` cannot be filtered by time server-side (its `since` is a log index, not a timestamp), so
each poll pulls the most recent `PVEAUDIT_LOG_MAX` entries — default 500 — and discards what falls
outside the window. On a quiet two-node cluster that covers days. On a busy cluster, or after the
collector has been down for a while, 500 entries may not reach back to the cursor and events would be
**silently skipped** — no error, just a gap. The wizard should scale this to cluster size, or the poller
should grow the window until it sees an entry older than its cursor. Flagged September 2026.
