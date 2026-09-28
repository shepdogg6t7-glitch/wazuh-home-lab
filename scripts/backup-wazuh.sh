#!/bin/bash
#
# backup-wazuh.sh — Snapshot the Wazuh single-node Docker stack.
#
# Creates timestamped tarballs of the Wazuh Docker volumes and the
# compose/config directory, writes them to the external backup drive,
# and reports the result.
#
# Volume archiving is done inside short-lived Alpine containers so that
# we don't need filesystem access to the Docker Desktop VM (which is
# where the volumes actually live under WSL 2).
#
# Usage: ./backup-wazuh.sh
#

set -euo pipefail

# ---- Configuration ---------------------------------------------------------

BACKUP_DIR="/mnt/g/Wazuh-Backups"
WAZUH_DIR="${HOME}/wazuh-docker/single-node"
RETENTION_DAYS=30
DATE="$(date +%Y-%m-%d_%H-%M-%S)"

# All Wazuh volumes for the single-node compose project.
# Discovered via: docker volume ls | grep '^local *single-node_'
#
# NOTE: single-node_wazuh_queue is intentionally excluded. It holds
# transient event data awaiting ingestion by the Indexer. After an
# outage those events are either reprocessed from upstream or dropped
# anyway, so backing it up adds ~500 MB per run for no recovery value.
# On a fresh install it can account for >99% of the total backup size.
VOLUMES=(
  single-node_filebeat_etc
  single-node_filebeat_var
  single-node_wazuh-dashboard-config
  single-node_wazuh-dashboard-custom
  single-node_wazuh-indexer-data
  single-node_wazuh_active_response
  single-node_wazuh_agentless
  single-node_wazuh_api_configuration
  single-node_wazuh_etc
  single-node_wazuh_integrations
  single-node_wazuh_logs
  single-node_wazuh_var_multigroups
  single-node_wazuh_wodles
)

# ---- Preflight -------------------------------------------------------------

if [ ! -d "${BACKUP_DIR}" ]; then
  echo "ERROR: backup directory ${BACKUP_DIR} does not exist." >&2
  echo "Create it first: mkdir -p ${BACKUP_DIR}" >&2
  exit 1
fi

if [ ! -d "${WAZUH_DIR}" ]; then
  echo "ERROR: Wazuh directory ${WAZUH_DIR} does not exist." >&2
  exit 1
fi

if ! mountpoint -q /mnt/g 2>/dev/null && ! mount | grep -q "/mnt/g"; then
  echo "WARNING: /mnt/g does not appear to be mounted. Attempting anyway." >&2
fi

# ---- Capture compose and config state --------------------------------------

echo "[$(date +%H:%M:%S)] Starting Wazuh backup..."

CONFIG_TAR="${BACKUP_DIR}/wazuh-config-${DATE}.tar.gz"

echo "[$(date +%H:%M:%S)] Archiving compose + config..."
tar -czf "${CONFIG_TAR}" -C "$(dirname "${WAZUH_DIR}")" "$(basename "${WAZUH_DIR}")"
echo "  -> ${CONFIG_TAR} ($(du -h "${CONFIG_TAR}" | cut -f1))"

# ---- Capture Docker volumes via Alpine container ---------------------------

echo "[$(date +%H:%M:%S)] Stopping Wazuh stack (quiesce volumes)..."
cd "${WAZUH_DIR}"
docker compose stop

echo "[$(date +%H:%M:%S)] Archiving Docker volumes..."

# Build the docker run arguments dynamically.
# Each volume is mounted read-only into the Alpine container at /vol/<name>.
DOCKER_ARGS=()
for vol in "${VOLUMES[@]}"; do
  DOCKER_ARGS+=( -v "${vol}:/vol/${vol}:ro" )
done

docker run --rm \
  "${DOCKER_ARGS[@]}" \
  -v "${BACKUP_DIR}:/backup" \
  alpine sh -c '
    set -e
    cd /vol
    for d in */; do
      name="${d%/}"
      echo "  archiving ${name}..."
      tar -czf "/backup/wazuh-vol-${name}-'"${DATE}"'.tar.gz" -C "/vol/${name}" .
    done
  '

echo "[$(date +%H:%M:%S)] Restarting Wazuh stack..."
docker compose start

# ---- Prune old backups -----------------------------------------------------

echo "[$(date +%H:%M:%S)] Pruning backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "wazuh-*.tar.gz" -mtime "+${RETENTION_DAYS}" -print -delete || true

# ---- Summary ---------------------------------------------------------------

echo "[$(date +%H:%M:%S)] Backup complete."
echo ""
echo "Backups in ${BACKUP_DIR}:"
ls -lh "${BACKUP_DIR}"/wazuh-*.tar.gz 2>/dev/null | tail -n 20 || true
