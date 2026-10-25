# Backups (our own servers)

How the team backs up its own machines. Not part of the customer install.

Proxmox backs up every machine nightly to **Proxmox Backup Server**, which copies them to **AWS S3**. Each copy keeps backups on a grandfather-father-son (GFS) schedule:

| | Daily | Weekly | Monthly | Cleanup |
|---|---|---|---|---|
| **Local (PBS)** | 7 | 4 | 3 | prune daily, garbage collection nightly |
| **AWS S3** | — | 8 | 6 | prune and garbage collection weekly |

- Only backups that pass PBS's integrity check are copied to S3.
- Deleting a backup locally never deletes the S3 copy.
- Restore recent mistakes from PBS (fast). Use S3 if PBS itself is lost.
- Grafana's Backups page shows where each backup is kept, and has **Run Backup Now** and **Send to AWS S3** buttons.
