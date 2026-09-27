# Milestone 2 — Host Tuning: WSL Memory and Kernel Parameters

**Date:** 2026-09-27
**Status:** ✅ Complete

## Goal

Two host-level defaults are incompatible with Wazuh's resource profile:

1. **WSL 2 caps memory at ~50% of Windows RAM** (7.6 GB on a 16 GB
   machine). Wazuh's Indexer alone wants 2–4 GB, plus Manager and
   Dashboard, plus whatever other stacks are running.
2. **Ubuntu 22.04 ships with `vm.max_map_count=65530`.** The Wazuh
   Indexer (OpenSearch) refuses to start below `262144` and exits
   with a cryptic error.

Both are fixed here, once, permanently.

## Environment

- Host RAM: 16 GB
- WSL 2 default cap observed: 7.6 GiB
- Ubuntu default `vm.max_map_count`: 65530

## Command

```bash
# 1. Create .wslconfig on the Windows side
cat > /mnt/c/Users/kelvi_f/.wslconfig << 'EOF'
[wsl2]
memory=12GB
processors=8
swap=4GB

[experimental]
autoMemoryReclaim=gradual
EOF

# 2. Make vm.max_map_count persistent inside Ubuntu
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-wazuh.conf
```

Then from PowerShell (Windows side):

```powershell
wsl --shutdown
```

Reopen Ubuntu and verify:

```bash
free -h
sysctl vm.max_map_count
cat /mnt/c/Users/kelvi_f/.wslconfig
```

## Output

```
=== Memory ===
               total        used        free      shared  buff/cache   available
Mem:            11Gi       921Mi       8.8Gi        60Mi       2.0Gi        10Gi
Swap:          4.0Gi          0B       4.0Gi

=== Kernel parameter ===
vm.max_map_count = 262144

=== .wslconfig ===
[wsl2]
memory=12GB
processors=8
swap=4GB

[experimental]
autoMemoryReclaim=gradual
```

## What I Learned

- **WSL 2 memory is not dynamic by default.** Without `.wslconfig`, it
  reserves ~50% of host RAM as a hard ceiling. Editing `.wslconfig` on
  the *Windows* side is the only way to change it — there's no
  `wsl.conf` equivalent inside the distro.
- **`.wslconfig` changes require `wsl --shutdown`.** Not `exit`,
  not closing the terminal. A full VM shutdown is the only thing that
  re-reads the file.
- **`vm.max_map_count` is a kernel-level setting, not a service
  setting.** It has to be applied per-boot unless persisted. Ubuntu
  reads `/etc/sysctl.d/*.conf` at boot, so a file there is enough.
- **The 262144 number is not arbitrary.** Each memory-mapped region
  consumes one entry in a per-process map. OpenSearch
  (which Wazuh's Indexer wraps) needs ~130k mappings at startup, and
  the default 65530 causes a hard failure before the JVM even
  finishes booting.

## Gotcha — None (this time)

Unlike Milestone 1, this one went cleanly. Both changes applied on
first try after `wsl --shutdown`. Worth noting that "clean" milestones
should still be documented — a full portfolio doesn't only show the
problems you overcame, it shows the process you follow when things
work.

## Screenshot

- `screenshots/02-kernel-and-wsl/02-memory-and-kernel-post-fix_2026-09-27.png`
- `screenshots/02-kernel-and-wsl/02-wslconfig-file_2026-09-27.png`

## Next

Milestone 3 — Stop non-essential Docker stacks and establish a
baseline before Wazuh deployment.

→ [04-resource-management.md](04-resource-management.md)
