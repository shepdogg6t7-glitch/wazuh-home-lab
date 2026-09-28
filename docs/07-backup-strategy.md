# Milestone 6 — Backup Strategy

**Date:** 2026-09-27
**Status:** ✅ Complete

## Goal

Build a reproducible backup script for the Wazuh single-node stack that
captures the compose file, configs, certificates, and Docker volumes to
an external drive — and documents two non-obvious gotchas discovered
during development.

The backup must be:
- **Restorable** — a fresh Wazuh install should be able to recover from it
- **Fast** — under a minute, so it can run nightly without disruption
- **Resource-conscious** — no 500 MB of transient data in every snapshot

## Environment

- Backup target: `G:\Wazuh-Backups\` (WD My Passport 2 TB, NTFS, USB)
- Source: `~/wazuh-docker/single-node` + 14 named Docker volumes
- Volume archiving method: temporary `alpine` container with `-v` mounts
- Retention: 30 days (managed by `find -mtime +30 -delete`)

## Command

```bash
./scripts/backup-wazuh.sh
```

The script:
1. Archives `~/wazuh-docker/single-node` (compose, configs, certs)
2. Stops the Wazuh stack (quiesces volumes)
3. Archives each volume via a short-lived Alpine container
4. Restarts the Wazuh stack
5. Prunes tarballs older than 30 days
6. Prints a summary

## Output

Final run (post-optimization):

```
[19:54:40] Starting Wazuh backup...
[19:54:40] Archiving compose + config...
  -> /mnt/g/Wazuh-Backups/wazuh-config-2026-09-27_19-54-40.tar.gz (20K)
[19:54:41] Stopping Wazuh stack (quiesce volumes)...
[19:55:04] Archiving Docker volumes...
  archiving single-node_filebeat_etc...
  ... (13 volumes total)
[19:55:07] Restarting Wazuh stack...
[19:55:10] Pruning backups older than 30 days...
[19:55:11] Backup complete.
```

Total time: **~30 seconds**. Total size: **~1.2 MB**.

## What I Learned

- **Docker Desktop on WSL 2 hides volumes from the WSL filesystem.**
  `docker volume inspect` reports a path like
  `/var/lib/docker/volumes/...`, but that path lives **inside the
  Docker Desktop VM**, not in the Ubuntu distro. Attempting to `ls` it
  from WSL — even as root — returns "No such file or directory."
- **The fix is to archive via a container.** A one-shot `alpine`
  container with `-v <volume>:/data:ro -v /mnt/g/Wazuh-Backups:/backup`
  can tar the volume contents directly to the external drive without
  ever touching the host filesystem.
- **`wazuh_queue` is transient and huge.** On an idle install with no
  agents connected, the Manager still generates its own internal
  events and queues them in this volume. It grew to **506 MB in a few
  hours** — over 99% of the total backup size. Excluding it drops the
  backup from 507 MB to 1.2 MB and from 4 minutes to 30 seconds.
- **`find -mtime +N` respects retention without extra tooling.**
  For a lab, a one-line prune is enough — no need for a backup
  rotation framework.

## Gotcha 1 — Volume Paths Aren't Visible From WSL

The first version of the script tried to read volumes directly:

```bash
vol_path="/var/lib/docker/volumes/${vol}/_data"
if [ -d "${vol_path}" ]; then
  VOLUME_PATHS+=("${vol_path}")
fi
```

Every volume was reported as missing:

```
(skipping missing volume: single-node_wazuh_etc)
...
WARNING: no volume paths found. Skipping volume archive.
```

**Root cause:** Docker Desktop on WSL 2 stores volumes inside its own
VM. The path `/var/lib/docker/volumes/` doesn't exist in the Ubuntu
distro — even `sudo ls /var/lib/docker/volumes/` returns "No such file
or directory."

**Fix:** archive from inside a container that has the volume mounted.

## Gotcha 2 — `wazuh_queue` Is 99% of the Backup

The first successful backup produced 15 tarballs totaling 507 MB. Of
that, **506 MB** was a single volume: `single-node_wazuh_queue`. This
volume holds events the Manager has queued but not yet indexed. On a
fresh install with no agents, it accumulates the Manager's own internal
events indefinitely.

**Why this matters:**
- Backups take 4 minutes instead of 30 seconds
- The external drive fills up 400× faster than necessary
- In a disaster, replaying the queue contents provides no recovery value
  — those events were already (or will be) reprocessed by the Manager

**Fix:** exclude `wazuh_queue` from the `VOLUMES` array with a comment
explaining why. This is documented in the script itself, not just here,
because the next person to edit the script needs to know it was a
deliberate choice.

## Result

| Metric | Before optimization | After |
|---|---|---|
| Files backed up | 15 | 14 |
| Total size | 507 MB | 1.2 MB |
| Runtime | ~4 min | ~30 sec |
| Queue volume included | yes | no (excluded) |
| Backup directory visible in Explorer | yes | yes |

## Screenshot

![Wazuh backup script running to completion](screenshots/06-backup/06-backup_successful-run_2026-09-27.png)

## Next

Milestone 7 — Onboard the first Wazuh agent (the Lenovo G575).

→ [08-agent-onboarding.md](08-agent-onboarding.md)
