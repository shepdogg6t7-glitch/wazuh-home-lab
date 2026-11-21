#!/bin/bash
#
# threat-intel-load.sh — Load threat-intel IOCs into the Wazuh manager as a CDB list.
#
# Converts a plain IP list to Wazuh CDB list format (ip -> 1), copies it into
# the manager container at /var/ossec/etc/lists/threat-intel-ips.txt, and
# restarts the manager so Wazuh compiles the .cdb and loads the list.
#
# Prerequisites:
#   - Wazuh manager container named single-node-wazuh.manager-1 (adjustable via $CONTAINER)
#   - threat-intel-fetch.sh has been run at least once (ips-latest.txt exists)
#
# Usage: ./threat-intel-load.sh [ips_file] [container_name]

set -euo pipefail

IPS_FILE="${1:-$(dirname "$0")/../configs/threat-intel/ips-latest.txt}"
CONTAINER="${2:-single-node-wazuh.manager-1}"
LIST_NAME="threat-intel-ips"
LIST_PATH_IN_CONTAINER="/var/ossec/etc/lists/${LIST_NAME}.txt"
LIST_TMP="$(mktemp)"

# ---- Validate input ---------------------------------------------------------

if [ ! -f "${IPS_FILE}" ]; then
  echo "ERROR: IOC file ${IPS_FILE} not found." >&2
  echo "Run scripts/threat-intel-fetch.sh first." >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "ERROR: container ${CONTAINER} not running." >&2
  exit 1
fi

COUNT="$(wc -l < "${IPS_FILE}")"
if [ "${COUNT}" -eq 0 ]; then
  echo "ERROR: IOC file is empty." >&2
  exit 1
fi

# ---- Convert to Wazuh CDB list format --------------------------------------
# Format: ip.address -> 1  (address_match lookup resolves to value "1")
echo "[$(date +%H:%M:%S)] Converting ${COUNT} IOCs to Wazuh CDB format..."
while IFS= read -r ip; do
  [ -z "${ip}" ] && continue
  echo "${ip} -> 1"
done < "${IPS_FILE}" > "${LIST_TMP}"

# ---- Deploy to manager container -------------------------------------------
echo "[$(date +%H:%M:%S)] Deploying list to ${CONTAINER}:${LIST_PATH_IN_CONTAINER}..."
docker cp "${LIST_TMP}" "${CONTAINER}:${LIST_PATH_IN_CONTAINER}"
rm -f "${LIST_TMP}"

# ---- Ensure lists directory is writable / list is owned by root ------------
docker exec "${CONTAINER}" chown root:root "${LIST_PATH_IN_CONTAINER}"
docker exec "${CONTAINER}" chmod 644 "${LIST_PATH_IN_CONTAINER}"

# ---- Restart manager to compile .cdb and load list -------------------------
echo "[$(date +%H:%M:%S)] Restarting Wazuh manager to compile CDB list..."
docker restart "${CONTAINER}"
sleep 15

# ---- Verify -----------------------------------------------------------------
if docker exec "${CONTAINER}" test -f "${LIST_PATH_IN_CONTAINER}.cdb"; then
  CDB_COUNT="$(docker exec "${CONTAINER}" wc -l < "${LIST_PATH_IN_CONTAINER}")"
  echo "[$(date +%H:%M:%S)] CDB list compiled: ${LIST_PATH_IN_CONTAINER}.cdb"
  echo "[$(date +%H:%M:%S)] Source entries: ${CDB_COUNT}"
else
  echo "WARNING: .cdb file not found after restart. Wazuh may compile on first rule match." >&2
fi

echo "[$(date +%H:%M:%S)] Threat intel list deployed. Add the detection rule to local_rules.xml and restart the manager to enable alerting."
