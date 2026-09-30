# 09 — WSL 2 Bind Mount Caching Gotcha

**Date:** 2026-09-30
**Context:** Second Wazuh admin password rotation

## Symptom

After rotating the admin password a second time, the following were all true:

- `internal_users.yml` on the host showed the new hash
- The container's bind mount pointed at the file correctly
- `securityadmin.sh` returned `Done with success`
- **But the browser login rejected the new password**
- **And the old password still worked**

## Root Cause

Docker Desktop on WSL 2 uses bind mounts to share files between the host
and container. When `sed -i` edits a file, it doesn't modify the file in
place — it **creates a new file and renames it over the old one**, giving
the file a new inode.

The container's bind mount was still attached to the **old inode** — the
original file. The container silently read stale content even though the
host file was correct.

**Affects:** single-file bind mounts specifically. Directory mounts are
usually unaffected because the mount points at a directory, not a file.

## Fix

Force the file into the container via a stream, bypassing the mount:

```bash
docker exec -i single-node-wazuh.indexer-1 tee \
  /usr/share/wazuh-indexer/opensearch-security/internal_users.yml \
  < ~/wazuh-docker/single-node/config/wazuh_indexer/internal_users.yml \
  > /dev/null

Then verify host and container MD5s match before running securityadmin.sh:

# Host
sed -n "14p" ~/wazuh-docker/single-node/config/wazuh_indexer/internal_users.yml | md5sum

# Container
docker exec single-node-wazuh.indexer-1 sed -n "14p" \
  /usr/share/wazuh-indexer/opensearch-security/internal_users.yml | md5sum

They must be identical. If they differ, the mount is stale and the push
will silently fail.

Fix: verify actual mount points with:

ERR: An unexpected IllegalArgumentException occured: Could not find
certificate file /usr/share/wazuh-indexer/config/certs/root-ca.pem

docker inspect single-node-wazuh.indexer-1 --format \
  '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'

Use the destination paths the container actually has, not the paths
from generic documentation.

Working Sequence
Edit internal_users.yml on the host with sed -i

Force the file into the container with docker exec -i ... tee

Verify host and container MD5s match — do not skip this

Run securityadmin.sh with the correct cert paths

Test via API before browser:

docker exec single-node-wazuh.indexer-1 curl -sk \
  -u admin:PASSWORD https://localhost:9200/_cluster/health

Then verify browser login

Steps 2 and 3 are the ones most people skip, and they're exactly the steps
that catch the bind mount issue.

What I Learned
Docker Desktop on WSL 2 has known bind-mount caching quirks.
Single-file mounts can go stale after sed -i because the inode changes.

Done with success from securityadmin.sh is not proof that the
config was updated in the running cluster. The script reads the
container's view of the file, which may be stale.

Always verify the file the container actually sees before running
any configuration push. md5sum is the fastest way.

Direct API tests (curl -u admin:password) are faster than browser
login for verifying credentials. They also isolate the credential
from browser cache issues.


**Save:** `Ctrl + O`, `Enter`, `Ctrl + X`.

---

### ⏸️ Pause After Step 4

**Run Steps 1–4. Paste the `ls` output from Step 3.**

Then we commit the gotcha doc and close this out.

**Save the password. Clean up. Verify. Paste the `ls` output. Pause.**






























