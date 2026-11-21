#!/bin/bash
#
# threat-intel-fetch.sh — Pull known-bad IOCs from free threat intel feeds.
#
# Feeds:
#   - Feodo Tracker IP blocklist (https://feodotracker.abuse.ch)
#   - Spamhaus DROP list (https://www.spamhaus.org)
#
# Output: deduplicated, cleaned IPv4 list to stdout (one IP per line).
# Writes a timestamped snapshot to $OUT_DIR for audit/rollback.
#
# Usage: ./threat-intel-fetch.sh [output_dir]
#

set -euo pipefail

OUT_DIR="${1:-$(dirname "$0")/../configs/threat-intel}"
FEEDS_FILE="${OUT_DIR}/feeds.txt"
DATE="$(date +%Y-%m-%d_%H-%M-%S)"

mkdir -p "${OUT_DIR}"

# ---- Feed definitions -------------------------------------------------------
# Each line: <name> <url> <skip_header_lines>
cat > "${FEEDS_FILE}" <<'FEEDS'
feodo-tracker https://feodotracker.abuse.ch/downloads/ipblocklist.csv 1
spamhaus-drop https://www.spamhaus.org/drop/drop.txt 0
FEEDS

# ---- Fetch ------------------------------------------------------------------

ALL_IPS="${OUT_DIR}/ips-raw-${DATE}.txt"
: > "${ALL_IPS}"

while read -r name url skip; do
  [ -z "${name}" ] && continue
  echo "[$(date +%H:%M:%S)] Fetching ${name} from ${url}..."
  if ! curl -fsSL --max-time 60 "${url}" 2>/dev/null | tail -n +$((skip + 1)) \
    | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' >> "${ALL_IPS}"; then
    echo "WARNING: feed ${name} failed, skipping." >&2
  fi
done < "${FEEDS_FILE}"

# ---- Clean & deduplicate ----------------------------------------------------

CLEAN_IPS="${OUT_DIR}/ips-${DATE}.txt"

grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "${ALL_IPS}" \
  | awk -F. '$1<=255 && $2<=255 && $3<=255 && $4<=255' \
  | sort -u \
  > "${CLEAN_IPS}"

COUNT="$(wc -l < "${CLEAN_IPS}")"
echo "[$(date +%H:%M:%S)] Collected ${COUNT} unique IOCs -> ${CLEAN_IPS}"

# Keep a "latest" symlink for the load script to consume.
ln -sf "${CLEAN_IPS}" "${OUT_DIR}/ips-latest.txt"

echo "${CLEAN_IPS}"
