# Setup help

Setup asks a few questions, then does the rest on its own. At any question, type `?` and press Enter to see its part of this page. Press Enter on its own to take the answer shown in [brackets].

## Server address

Other computers (and your browser) reach LoNSeMonSy at this server's IP address, e.g. `192.168.1.50`. Most routers hand out addresses that can change after a restart, and then the dashboard link and the Wazuh agents stop working.

- **Y** (recommended): keep the address it has now, for good.
- **n**: let the router choose. Then reserve the address in your router's settings (often called "DHCP reservation").

Either way, it's worth reserving it on the router too, so no other device gets the same address.

## Business name

Shown at the top of the dashboard and as the sender of alarm emails, e.g. `Acme Dental`. Press Enter to skip; nothing else depends on it.

## Alarm emails

LoNSeMonSy emails you when something needs attention: an attack, a new device on the network, a full disk. Without email you only see alarms when you open the dashboard.

1. **Your email address:** where alarms go, e.g. `owner@acmedental.com`. Any email works.
2. **A Gmail address to send from:** make a new free Gmail account just for this, e.g. `acmealarms@gmail.com`.
3. **The 16-letter password from Google.** Google doesn't let programs use your normal Gmail password, so it makes a separate one for each program (Google calls it an "app password"):
   1. Sign in to the sending Gmail account.
   2. Turn on 2-Step Verification: https://myaccount.google.com/signinoptions/twosv
   3. Go to https://myaccount.google.com/apppasswords, type `LoNSeMonSy` as the name, click **Create**.
   4. Copy the 16 letters it shows (spaces don't matter) and paste them into setup.

Setup checks the password with Gmail before going on. Press Enter at the first question to skip; set it up later by running setup again.

## Backups

Every night at 1 AM, LoNSeMonSy saves a copy of its settings and data on this server, in `/var/backups/lonsemonsy-copies`. This is always on: it keeps 7 daily and 4 weekly copies, and it's what `lsmsy restore` puts back after a bad change.

That copy is gone if the server's disk dies, so you can also send a copy to the cloud. You need a bucket (online storage) at [Backblaze B2](https://www.backblaze.com/cloud-storage) (free up to 10 GB) or Amazon S3. With Backblaze:

1. Sign up, then **Buckets > Create a Bucket**, private, e.g. `acme-lonsemonsy`.
2. The bucket's **Endpoint** is the bucket address, e.g. `s3.us-east-005.backblazeb2.com`.
3. **Application Keys > Add a New Application Key**, for that bucket. Copy its `keyID` (Key ID) and `applicationKey` (secret key). The secret key is only shown once.

Backups are encrypted with a backup password that setup makes and shows at the end. **Save it somewhere else** (a password manager): a backup can't be restored without it. Add or change the bucket later with `lsmsy backup setup`.

## Remote access

Opens the dashboards from anywhere (a phone, a laptop at home) using [Tailscale](https://tailscale.com) (free for up to 3 users). Nothing is opened to the internet: only devices signed in to your Tailscale account can reach it, and that sign-in (Google, Microsoft or GitHub) uses their 2-step verification.

1. Make a free account at https://login.tailscale.com. Turn on 2-step verification in that Google, Microsoft or GitHub account: it's the only 2-step check.
2. Go to https://login.tailscale.com/admin/dns and turn on **HTTPS Certificates** (the dashboard addresses need it).
3. Go to https://login.tailscale.com/admin/settings/keys, click **Generate auth key**, leave **Reusable** off, then **Generate key**.
4. Copy the key (it starts with `tskey-`) and paste it into setup.
5. Install the Tailscale app on each phone or laptop that should reach the dashboard, signed in to the same account.

Then, in https://login.tailscale.com/admin/settings/device-management:

- **Device approval** on: a new phone or laptop can't connect until you approve it.
- **Key expiry** 7 days: phones and laptops have to sign in again (with 2-step) every week.
- On the Machines page, open this server's **...** menu and pick **Disable key expiry**, so remote access doesn't stop by itself.

Press Enter to skip; turn it on later with `lsmsy remote`.

## Passwords

Setup shows the Grafana, Wazuh and backup passwords once, at the end. Save them in a password manager. They aren't shown again.

- **Forgot one, or think someone else has it:** on the server, run `lsmsy password grafana`, `lsmsy password wazuh` or `lsmsy password netalertx`. It sets a new password and signs everyone out.
- **Other Grafana users** change their own password in Grafana: profile picture > **Change password**.
- **If you think you were hacked:** change both passwords, run `lsmsy users` to look for accounts you don't recognize, remove them with `lsmsy deluser <name>`, and check the Audit page for logins you don't recognize.
- **Backup password:** it can't be changed, but `sudo grep BACKUP_PASSWORD appliance/.env` shows it.
