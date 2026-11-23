# Setup help

Setup asks a few questions, then does the rest on its own. At any question, type `?` and press Enter to see its part of this page. Press Enter on its own to take the answer shown in [brackets].

## Server address

Other computers (and your browser) reach LoNSeMonSy at this server's IP address, e.g. `192.168.1.50`. Most routers hand out addresses that can change after a restart, and then the dashboard link and the Wazuh agents stop working.

- **Y** (recommended): keep the address it has now, for good.
- **n**: let the router choose. Then reserve the address in your router's settings (often called "DHCP reservation").

Either way, it's worth reserving it on the router too, so no other device gets the same address.

## Time zone

Only asked when the server's clock is on UTC (Ubuntu Server's default). The time zone sets when backups and the weekly report run, and the times on alarms. Type its name as `Region/City`:

| Where | Type |
|---|---|
| US Eastern | `America/New_York` (or `eastern`) |
| US Central | `America/Chicago` (or `central`) |
| US Mountain | `America/Denver` (or `mountain`) |
| US Pacific | `America/Los_Angeles` (or `pacific`) |
| UK | `Europe/London` |
| Keep UTC | `UTC` |

Any other city: run `timedatectl list-timezones` to see them all.

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

Every night LoNSeMonSy saves a copy of its settings and data on this server, in `/var/backups/lonsemonsy-copies`. This is always on: it keeps 7 daily, 4 weekly and 6 monthly copies, and it's what `lsmsy restore` puts back after a bad change.

**Time:** pick when the office is closed but the server is still online, typed e.g. `1am`, `11:30pm` or `23:30` (Enter = 1 AM). If the server was offline then, the backup runs as soon as it's back online. Change it later with `lsmsy backup time 11pm`.

That copy is gone if the server's disk dies, so you can also send a copy to the cloud. You need a bucket (online storage) at [Amazon S3](https://aws.amazon.com/s3/) or [Backblaze B2](https://www.backblaze.com/cloud-storage) (free up to 10 GB).

With Amazon S3:

1. In the AWS console, **S3 > Create bucket**, e.g. `acme-lonsemonsy` (Block all public access stays on). Note its region, e.g. `us-east-1`.
2. The endpoint is `s3.<region>.amazonaws.com`, e.g. `s3.us-east-1.amazonaws.com`.
3. **IAM > Users > Create user**, give it access to that bucket, then **Security credentials > Create access key**. Copy the `Access key ID` (Key ID) and `Secret access key` (secret key). The secret key is only shown once.

With Backblaze:

1. Sign up, then **Buckets > Create a Bucket**, private, e.g. `acme-lonsemonsy`.
2. The bucket's **Endpoint** is the bucket address, e.g. `s3.us-east-005.backblazeb2.com`.
3. **Application Keys > Add a New Application Key**, for that bucket. Copy its `keyID` (Key ID) and `applicationKey` (secret key). The secret key is only shown once.

Backups are encrypted with a backup password that setup makes and shows at the end. **Save it somewhere else** (a password manager): a backup can't be restored without it. Add or change the bucket later with `lsmsy backup setup`.

## Remote access

Opens the dashboards from anywhere (a phone, a laptop at home) using [Tailscale](https://tailscale.com). Nothing is opened to the internet: only devices signed in to your Tailscale account can reach it.

**Cost:** Tailscale's free plan is for personal use. A business needs a paid plan, billed per user, and changes its own account to it: see [Tailscale's prices](https://tailscale.com/pricing).

1. Best: use the Gmail account the alarm emails are sent from. Google only gives it an app password while its 2-step verification is on, and setup checks that you signed in with it. Without alarm emails, pick the Google, Microsoft or GitHub account you'll sign in with and turn on its 2-step verification ([Google](https://myaccount.google.com/signinoptions/two-step-verification), [Microsoft](https://account.microsoft.com/security), [GitHub](https://github.com/settings/security)). Neither LoNSeMonSy nor Tailscale forces this: without it, that account's password is enough to get in. Save its backup codes too, in case you lose your phone.
2. At the end of setup, LoNSeMonSy shows a sign-in link and a QR code. Type the link into a browser on any computer, or scan the code with your phone, and sign in. That makes a Tailscale account if you don't have one.
3. If asked, turn on **HTTPS Certificates** at https://login.tailscale.com/admin/dns (setup waits for it).
4. Install the Tailscale app on each phone or laptop that should reach the dashboards, signed in to the same account. Setup shows a QR code for Grafana's address.

Then change these in Tailscale (setup can't do it for you):

- On the [Machines](https://login.tailscale.com/admin/machines) page, open this server's **...** menu and pick **Disable key expiry**, so the server stays signed in.
- In [Device management](https://login.tailscale.com/admin/settings/device-management), set **Key expiry** to **1 day** instead of 180. Phones and laptops then sign in again every day. The 2-step check happens at that sign-in, not each time you open a dashboard.
- **Device approval** on, if your plan has it: a new phone or laptop can't connect until you approve it.

Once remote access works, the dashboards stop opening by IP address, so nobody on the office network skips the sign-in. If Tailscale stops working or you lose that account, SSH in from the office network (or use the server's own screen) and run `sudo lsmsy remote ip on`. Undo it with `sudo lsmsy remote ip off`. A new phone or laptop on the account sets off the alarm "New device can reach your dashboard".

Press Enter to skip; turn it on or off later with `lsmsy remote`.

## AI explanations

For each Medium or worse alarm, an AI writes a short note: what happened, how serious it is and what to do. It shows on the Alarms page and comes by email. The AI only explains; it never blocks or changes anything, and it can be wrong.

The AI (Google's Gemma 3, run by [Ollama](https://ollama.com)) runs on your own network, so alarm data never leaves it. Two choices:

- **On this server (press Enter):** needs about 2 GB more memory (Gemma 3 1B). With 12 GB of memory or more, setup uses the better Gemma 3 4B (about 5 GB). A note takes about a minute.
- **On another computer:** install Ollama there (https://ollama.com/download), make it listen on the network (`OLLAMA_HOST=0.0.0.0`), then type that computer's address, e.g. `192.168.1.60`. Setup downloads the model to it.

Turn it on or off later with `lsmsy ai on` or `lsmsy ai off`.

## Passwords

Setup shows the Grafana, Wazuh and backup passwords once, at the end. Save them in a password manager. They aren't shown again.

- **Forgot the Grafana password:** click **Forgot your password?** on Grafana's login page; the reset link goes to the alarm email address (this needs alarm emails set up).
- **Forgot one, or think someone else has it:** on the server, run `lsmsy password grafana`, `lsmsy password wazuh` or `lsmsy password netalertx`. It sets a new password and signs everyone out.
- **Other Grafana users** change their own password in Grafana: profile picture > **Change password**.
- **If you think you were hacked:** change both passwords, run `lsmsy users` to look for accounts you don't recognize, remove them with `lsmsy deluser <name>`, and check the Audit page for logins you don't recognize.
- **Backup password:** it can't be changed, but `sudo grep BACKUP_PASSWORD appliance/.env` shows it.
