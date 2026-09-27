# Milestone 1 — Pre-Flight Checks

**Date:** 2026-09-27
**Status:** ✅ Complete (with two deferred fixes)

## Goal

Before installing Wazuh, verify that the host environment is ready:
enough RAM visible to WSL, the external drive is writable, Docker is
reachable from within Ubuntu, and the user has the necessary group
memberships.

This milestone exists to catch problems *before* they turn into cryptic
container startup failures.

## Environment

- **Host:** Lenovo Yoga 9, Intel Core Ultra 7 155H (16 cores / 22 threads), 16 GB RAM
- **OS:** Windows 11 + WSL 2 (Ubuntu 22.04)
- **Container runtime:** Docker Desktop 29.8.0 with WSL integration
- **Backup target:** `G:\Wazuh-Backups\` (2 TB WD My Passport, NTFS)

## Command

```bash
echo "=== 1. WSL memory visible to Ubuntu ==="
free -h

echo ""
echo "=== 2. Kernel parameter (want 262144) ==="
sysctl vm.max_map_count

echo ""
echo "=== 3. Is G: mounted in WSL? ==="
mount | grep /mnt/g

echo ""
echo "=== 4. Can we read G:? ==="
ls /mnt/g/

echo ""
echo "=== 5. Ensure folder structure exists on G: ==="
mkdir -p /mnt/g/Wazuh-Backups /mnt/g/Wazuh-Archives /mnt/g/Victim-Logs
ls -la /mnt/g/

echo ""
echo "=== 6. Write test ==="
touch /mnt/g/Wazuh-Backups/.write-test && rm /mnt/g/Wazuh-Backups/.write-test && echo "WRITE OK"

echo ""
echo "=== 7. Docker sanity check ==="
docker --version
docker compose version
docker ps

echo ""
echo "=== 8. Docker group membership ==="
groups
```

## Output

See `notes/raw-outputs.md` for the full transcript. Summary:

| Check | Observed | Verdict |
|-------|----------|---------|
| WSL memory | 7.6 GiB total, 2 GiB swap | ⚠️ Too low — fix in M2 |
| `vm.max_map_count` | 65530 (Ubuntu default) | ❌ Wrong — fix in M2 |
| G: mount | `9p` type, rw, uid/gid 1000 | ✅ |
| G: read | Full directory listing returned | ✅ |
| Folder structure | `Wazuh-Backups`, `Wazuh-Archives`, `Victim-Logs` created | ✅ |
| Write test | `WRITE OK` | ✅ |
| Docker | `Docker version 29.8.0`, Compose v5.5.1 | ✅ (after fix below) |
| Docker group | `kelvi_f adm cdrom sudo dip plugdev docker` | ✅ |

## What I Learned

- **WSL 2's default memory cap is ~50% of Windows RAM.** With 16 GB
  physical, WSL sees ~7.6 GB. Wazuh's Indexer alone wants 2–4 GB, so
  this must be raised before deployment.
- **`vm.max_map_count` defaults to 65530 on Ubuntu 22.04.** The Wazuh
  Indexer (OpenSearch) refuses to start below 262144. This is a
  deployment-blocking parameter.
- **`/mnt/g` is a `drvfs`/`9p` mount, not a real Linux filesystem.**
  Permissions are synthesized from mount options (`uid=1000, gid=1000`),
  which means `chown` on `/mnt/g` is a no-op. Ownership issues on this
  drive are almost always Windows-side ACLs, not Linux permissions.
- **Docker Desktop's WSL integration can get stuck** and refuse to
  "Apply & Restart" even when the settings file is already correct.

## Gotcha — Docker Desktop WSL Integration Was Silently Off

`docker --version` failed inside WSL with:

```
The command 'docker' could not be found in this WSL 2 distro.
We recommend to activate the WSL integration in Docker Desktop settings.
```

The user was already in the `docker` group and `settings-store.json`
already listed `Ubuntu-22.04` under `IntegratedWslDistros`. But
toggling the integration switch and clicking "Apply & Restart" did
nothing — the button remained unresponsive.

**Root cause:** Docker Desktop's WSL integration agent was in a stuck
state. The settings file was correct, but the integration had never
actually been applied.

**Fix:**

1. Quit Docker Desktop entirely from the system tray.
2. `wsl --shutdown` in PowerShell.
3. Edit `%APPDATA%\Docker\settings-store.json`:
   ```json
   "IntegratedWslDistros": [],
   "EnableIntegrationWithDefaultWslDistro": false,
   ```
4. Save, then start Docker Desktop fresh.
5. Go to Settings → Resources → WSL Integration, toggle `Ubuntu-22.04` ON.
6. Click **Apply & Restart** and wait 30–60 seconds without re-clicking.
7. Close and reopen the Ubuntu terminal (PATH and socket are injected at
   shell startup).

**Watch out for:** Notepad appending `.txt` when saving via "Save As."
Use "All Files" mode, or edit the file in place with `Ctrl+S`.

## Screenshot

- `screenshots/01-preflight/01-preflight_memory-and-kernel_2026-09-27.png`
- `screenshots/01-preflight/01-preflight_write-ok_2026-09-27.png`

## Next

Milestone 2 — Raise WSL memory to 12 GB, set swap to 4 GB, make
`vm.max_map_count=262144` persistent.

→ [03-kernel-and-wsl.md](03-kernel-and-wsl.md)
