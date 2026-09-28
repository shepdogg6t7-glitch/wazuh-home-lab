# Milestone 5 — Credential Rotation and Hardening

**Date:** 2026-09-27
**Status:** ✅ Complete

## Goal

Rotate the default Wazuh `admin` credentials (`admin` / `SecretPassword`)
to a strong, randomly-generated password. Store the new credential in
Vaultwarden. Document the process and the three gotchas encountered.

The default credentials are public knowledge — every Wazuh install
starts with them. Leaving them in place is the single most common
Wazuh misconfiguration in the wild.

## Environment

- Wazuh version: 4.9.0 (single-node Docker)
- New password: 32-character base64 (`openssl rand -base64 24`)
- Password storage: Vaultwarden (Project #3)
- Security config pushed via: `securityadmin.sh` inside the Indexer container

## Command

```bash
# 1. Generate a password directly to a file (no clipboard)
openssl rand -base64 24 > /tmp/wazuh-pass.txt

# 2. Generate the matching bcrypt hash from that same file
docker run --rm -e WAZUH_PASS="$(cat /tmp/wazuh-pass.txt)" \
  -v /tmp:/out wazuh/wazuh-indexer:4.9.0 bash -c \
  '/usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh \
   -p "$WAZUH_PASS" | tail -n 1 > /out/wazuh-hash.txt'

# 3. Apply the new hash to internal_users.yml (line 14 = admin)
sed -i "14s|.*|  hash: \"$(cat /tmp/wazuh-hash.txt)\"|" \
  config/wazuh_indexer/internal_users.yml

# 4. Apply the new plaintext to docker-compose.yml (lines 24, 81)
sed -i "s|SecretPassword|$(cat /tmp/wazuh-pass.txt)|g" docker-compose.yml

# 5. Restart the stack
docker compose down && docker compose up -d

# 6. Push the new security config into the running cluster
docker exec -it single-node-wazuh.indexer-1 bash -c '
  export INSTALLATION_DIR=/usr/share/wazuh-indexer
  export JAVA_HOME=$INSTALLATION_DIR/jdk
  CACERT=$INSTALLATION_DIR/certs/root-ca.pem
  KEY=$INSTALLATION_DIR/certs/admin-key.pem
  CERT=$INSTALLATION_DIR/certs/admin.pem
  bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
    -cd /usr/share/wazuh-indexer/opensearch-security/ \
    -nhnv -cacert $CACERT -cert $CERT -key $KEY -p 9200 -icl -h localhost
'
```

## Output

Final `securityadmin.sh` run:

```
Contacting opensearch cluster 'opensearch' and wait for YELLOW clusterstate ...
Clustername: opensearch
Clusterstate: GREEN
.opendistro_security index already exists, so we do not need to create one.
Populate config from /usr/share/wazuh-indexer/opensearch-security/
Will update '/internalusers' with .../internal_users.yml
   SUCC: Configuration for 'internalusers' created or updated
...
Done with success
```

After the push, the repeated `Authentication finally failed for admin`
warnings in the Indexer log stopped immediately. Login with the new
password from a fresh browser session succeeded.

## What I Learned

- **Wazuh's `admin` user is `reserved: true`.** The UI will not let you
  change its password — it returns a `Forbidden` error. This is by
  design, to prevent accidental lockout. The rotation must be done by
  editing `internal_users.yml` and pushing it with `securityadmin.sh`.
- **`securityadmin.sh` expects the config at a specific path.** On
  Wazuh 4.9.0 the correct path inside the Indexer container is
  `/usr/share/wazuh-indexer/opensearch-security/`, **not**
  `/usr/share/wazuh-indexer/plugins/opensearch-security/securityconfig/`.
  Pointing at the wrong path produces `FileNotFoundException` for every
  config file and `cannot upload configuration, see errors above`.
- **bcrypt hashes contain `$` characters.** Every attempt to paste a
  hash directly into a shell command failed because bash tries to
  expand `$2y$12$...` as environment variables. The fix is to write
  the hash to a file and reference it with `$(cat file)` — bash still
  expands `$(cat ...)` but the expansion result is treated as a literal
  string, not re-parsed for `$`.
- **`docker compose stop` vs `down`.** `stop` halts containers but
  preserves them. `down` removes them (volumes survive). For config
  changes that require a restart, `down && up -d` is the clean path
  because Compose re-reads the yml file.
- **The Indexer holds the security config in memory.** Editing
  `internal_users.yml` on disk does nothing to a running cluster.
  `securityadmin.sh` is what actually pushes the change into the live
  cluster state.

## Gotcha 1 — Reserved User Rejects UI Changes

Attempting to change the `admin` password via the Dashboard
(**Security → Internal users → admin → Password**) returns a plain
`Forbidden` error with no explanation.

**Root cause:** `admin` is defined with `reserved: true` in
`internal_users.yml`. The UI blocks edits to reserved users.

**Fix:** Edit the YAML directly, then push with `securityadmin.sh`.

## Gotcha 2 — Wrong Config Path in securityadmin.sh

The first attempt used the path from older Wazuh documentation:

```
-cd /usr/share/wazuh-indexer/plugins/opensearch-security/securityconfig/
```

which produced:

```
ERR: Seems .../securityconfig/config.yml is not in OpenSearch Security 7 format:
     java.io.FileNotFoundException: .../config.yml (No such file or directory)
ERR: cannot upload configuration, see errors above
```

**Root cause:** Wazuh 4.9.0 moved the security config to a different
location. The `plugins/.../securityconfig/` path is from older
versions.

**Fix:** Use `/usr/share/wazuh-indexer/opensearch-security/` as the
`-cd` argument.

## Gotcha 3 — Shell Interprets `$` in bcrypt Hashes

Multiple attempts to substitute the new hash failed with errors like:

```
$2y$12$...: command not found
```

**Root cause:** bash expands `$2y`, `$12`, and any other `$`-prefixed
sequence it sees. A bcrypt hash contains three `$` characters, so any
command that pastes the hash directly gets mangled by the shell.

**Fix:** Write the hash to a file, then use `$(cat /tmp/wazuh-hash.txt)`
inside the sed substitution. Bash expands `$(cat ...)` but treats the
result as literal text — it doesn't re-parse for `$`.

**This pattern is worth memorizing:** any time a secret contains shell
metacharacters, write it to a file and use `$(cat file)`. This is how
CI/CD pipelines handle secrets, for the same reason.

## Screenshot

- `screenshots/05-hardening/05-hardening_dashboard-post-rotation_2026-09-27.png`

## Next

Milestone 6 — Backup strategy and first agent onboarding.

→ [07-backup-strategy.md](07-backup-strategy.md)
