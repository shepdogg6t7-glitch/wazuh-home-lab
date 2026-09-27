# Milestone 3 — Baseline and Deliberate Resource Management

**Date:** 2026-09-27
**Status:** ✅ Complete

## Goal

Before deploying Wazuh, capture what's running on the Docker host and
deliberately stop containers that aren't needed during the deployment.
This accomplishes three things:

1. Establishes a **documented baseline** for resource comparison
2. **Frees memory headroom** for Wazuh's Indexer, which spikes to 2–4 GB
   during startup
3. Forces a conscious decision about what belongs in the lab vs what is
   unrelated infrastructure

## Environment

- Docker host: WSL 2 Ubuntu 22.04 (12 GB RAM cap, 4 GB swap)
- Existing containers before cleanup: 8
- Existing containers after cleanup: 4

## Baseline Inventory (Before Cleanup)

| Container | Image | Memory | Role |
|---|---|---|---|
| nginx-proxy-manager | jc21/nginx-proxy-manager | 125 MB | Reverse proxy |
| vaultwarden | vaultwarden/server | 23 MB | Password vault |
| uptime-kuma | louislam/uptime-kuma | 136 MB | Uptime monitor |
| portainer | portainer/portainer-ce | 19 MB | Container management UI |
| atlasops-postgres | pgvector/pgvector:pg16 | 27 MB | Project database |
| atlasops-redis | redis:7 | 7 MB | Project cache |
| atlasops-redpanda | redpandadata/redpanda | 200 MB | Event streaming |
| atlasops-minio | quay.io/minio/minio | 74 MB | Object storage |

**Total:** ~610 MB across 8 containers.
**Host at baseline:** 1.8 Gi used, 9.6 Gi available.

## Decision Matrix — What Stays, What Stops

The rule: **containers that serve the Wazuh lab stay; containers from
unrelated projects stop.**

| Container | Decision | Reason |
|---|---|---|
| nginx-proxy-manager | **Keep** | Will expose Wazuh dashboard via hostname + TLS |
| vaultwarden | **Keep** | Stores Wazuh admin credentials (ties into Project #3) |
| uptime-kuma | **Keep** | Will monitor Wazuh dashboard uptime |
| portainer | **Keep** | Useful for inspecting Wazuh containers during debugging |
| atlasops-postgres | Stop | Unrelated project (AtlasOps) — preserves state |
| atlasops-redis | Stop | Unrelated project — preserves state |
| atlasops-redpanda | Stop | Unrelated project — heaviest container (200 MB) |
| atlasops-minio | Stop | Unrelated project — preserves state |

AtlasOps is a Compose-managed project, so stopping via
`docker compose stop` preserves containers and volumes for clean restart.

## Command

```bash
# Stop the AtlasOps stack (preserves containers, volumes, state)
cd ~/projects/atlasops
docker compose stop

# Verify: 4 running, 4 exited cleanly
docker ps --format "table {{.Names}}\t{{.Status}}"
docker ps -a --filter "name=atlasops"
```

## Output (After Cleanup)

```
=== Running containers ===
NAMES                 IMAGE                             STATUS
nginx-proxy-manager   jc21/nginx-proxy-manager:latest   Up 29 minutes
vaultwarden           vaultwarden/server:latest         Up 29 minutes (healthy)
uptime-kuma           louislam/uptime-kuma:1            Up 29 minutes (healthy)
portainer             portainer/portainer-ce:latest     Up 29 minutes

=== Resource snapshot ===
NAME                  CPU %     MEM USAGE / LIMIT
nginx-proxy-manager   0.05%     125.5MiB / 11.68GiB
vaultwarden           0.00%     23.03MiB / 11.68GiB
uptime-kuma           0.59%     136.7MiB / 11.68GiB
portainer             0.02%     19.68MiB / 11.68GiB

=== Host memory ===
Mem:  11Gi total, 1.5Gi used, 6.8Gi free, 9.9Gi available
Swap: 4.0Gi total, 0B used
```

## What I Learned

- **`docker compose stop` vs `docker compose down`.** Stop halts
  containers but preserves them, along with volumes and networks. Down
  removes everything. For a temporary pause, `stop` is correct.
- **`Exited (0)` is good.** A zero exit code means the container
  received SIGTERM and shut down gracefully. Non-zero codes indicate
  errors worth investigating.
- **Stopped containers still count against disk**, but not against RAM
  or CPU. The resource cost of a paused stack is effectively zero.
- **`docker stats --no-stream`** is the right way to snapshot resource
  usage non-interactively. The interactive `docker stats` runs forever
  and is useless for documentation.

## Gotcha — None

Clean Compose shutdown on first try.

## Screenshot

- `screenshots/03-resource-management/03-baseline-after-cleanup_2026-09-27.png`

## Next

Milestone 4 — Deploy the Wazuh single-node stack.

→ [05-deployment.md](05-deployment.md)
