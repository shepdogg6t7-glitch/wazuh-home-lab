# 10 — First Custom Alert: SSH Brute Force

**Completed:** 2026-10-07

**Analyst:** Kelvin

**Environment:** Wazuh 4.9.0 — single-node Docker stack

**Manager host:** `LeShepVoPro9` — Windows + WSL Ubuntu 22.04, Docker, IP `192.168.0.168`

**Agent host:** `G575-SOC` — Ubuntu, IP `192.168.0.189`

## Objective

Write, validate, deploy, and trigger a custom Wazuh rule detecting SSH
brute-force attempts against the G575-SOC agent, and confirm the alert
appears in the dashboard as rule `100100`.

## Definition of Done

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Custom rule written in `local_rules.xml` on the manager | Complete | Rule file screenshot |
| 2 | Validated with `wazuh-logtest` | Complete | Logtest screenshot |
| 3 | Manager restarted cleanly | Complete | Restart screenshot |
| 4 | Triggered for real and visible in the dashboard as rule `100100` | Complete | Dashboard screenshot and raw alert sample |

## 1. Architecture

```text
G575-SOC — 192.168.0.189                 LeShepVoPro9 — 192.168.0.168
Ubuntu — Wazuh agent                     Windows + WSL Ubuntu 22.04
                                        Docker: single-node-wazuh.manager
/var/log/auth.log ───── TCP 1514 ─────► /var/ossec/etc/rules/
                                        local_rules.xml
```

Manager container: `single-node-wazuh.manager-1`

The rule is stored on Docker volume `single-node_wazuh_etc`, mounted at
`/var/ossec/etc`, so it persists across container restarts.

## 2. Rule Design

The rule detects five or more SSH login attempts using non-existent
usernames from the same source IP within 60 seconds.

**Parent rule:** `5710` — “sshd: Attempt to login using a non-existent
user” (level 5), identified in
`/var/ossec/ruleset/rules/0095-sshd_rules.xml:89`.

Rule `5712` was deliberately not used as the parent: it is Wazuh's
built-in brute-force rule (eight attempts in 120 seconds, also parented
on `5710`). Using `5710` with a tighter window creates a distinct
detection rather than a redundant duplicate.

**MITRE ATT&CK:** `T1110.001` — Brute Force: Password Guessing
(Credential Access).

## 3. DoD #1 — Rule File

Path inside the manager container:
`/var/ossec/etc/rules/local_rules.xml`.

```xml
<group name="ssh,authentication_failed,attack,">
  <rule id="100100" level="12" frequency="5" timeframe="60">
    <if_matched_sid>5710</if_matched_sid>
    <same_source_ip />
    <description>SSH brute force: 5+ invalid-user logins in 60s from $(srcip)</description>
    <mitre>
      <id>T1110.001</id>
    </mitre>
  </rule>
</group>
```

Captured with:

```bash
docker exec -it single-node-wazuh.manager-1 \
  cat /var/ossec/etc/rules/local_rules.xml
```

The stock file was backed up as `local_rules.xml.bak` before it was
overwritten.

## 4. DoD #2 — `wazuh-logtest` Validation

```bash
docker exec -it single-node-wazuh.manager-1 \
  /var/ossec/bin/wazuh-logtest
```

Test input:

```text
Jan  1 00:00:00 yoga9 sshd[1]: Failed password for invalid user admin from 203.0.113.66 port 51000 ssh2
```

The test matched parent rule `5710` (level 5), then generated custom
rule `100100` (level 12). The `$(srcip)` variable was substituted with
`203.0.113.66`.

## 5. DoD #3 — Clean Restart

```bash
docker restart single-node-wazuh.manager-1
sleep 15
docker ps --filter name=wazuh.manager
```

The manager was up after restart and reloaded the rule without error.

## 6. DoD #4 — Real Trigger

From the manager host (`192.168.0.168`) against the agent
(`192.168.0.189`):

```bash
for i in $(seq 1 8); do
  (ssh -o StrictHostKeyChecking=no \
       -o PreferredAuthentications=password \
       -o PubkeyAuthentication=no \
       -o ConnectTimeout=3 \
       -o NumberOfPasswordPrompts=1 \
       baduser$i@192.168.0.189 </dev/null >/dev/null 2>&1) &
  sleep 0.3
done
wait
```

Eight invalid-user attempts reached the agent's `/var/log/auth.log`
within approximately three seconds. The agent forwarded them to the
manager at `192.168.0.168:1514/tcp`.

The raw alert log contained 14 matches for rule `100100`:

```bash
docker exec single-node-wazuh.manager-1 \
  grep -c 100100 /var/ossec/logs/alerts/alerts.json
# 14
```

Sample alert:

```json
{
  "timestamp": "2026-10-07T03:39:38.066+0000",
  "rule": {
    "level": 12,
    "description": "SSH brute force: 5+ invalid-user logins in 60s from 192.168.0.168",
    "id": "100100",
    "mitre": {
      "id": ["T1110.001"],
      "tactic": ["Credential Access"]
    },
    "frequency": 5,
    "firedtimes": 7,
    "groups": ["ssh", "authentication_failed", "attack"]
  },
  "agent": {
    "id": "001",
    "name": "G575-SOC",
    "ip": "192.168.0.189"
  },
  "data": {
    "srcip": "192.168.0.168",
    "srcport": "64744",
    "srcuser": "baduser4"
  }
}
```

## 7. Dashboard Visibility

In **Wazuh → Threat Hunting → Events**, the filter was set to
`rule.id` **is** `100100`, sorted newest first. The dashboard showed
rule `100100` at level 12 for agent `G575-SOC` (`192.168.0.189`), with
the description identifying source `192.168.0.168`. Parent `5710`
events (level 5) appeared in the same time window, showing the
aggregation chain.

## 8. Issues Encountered and Resolved

| Issue | Resolution |
|---|---|
| First draft used `if_matched_sid` `5712` | Confirmed `5712` is the built-in brute-force rule; reparented to `5710` with a tighter window to make `100100` distinct. |
| `wazuh-manager` inactive on G575 | Confirmed with `systemctl is-active` that G575 is agent-only; the manager runs in Docker on the Yoga 9. |
| SSH from G575 to Yoga 9 reset repeatedly | Used direct keyboard and Docker access instead; SSH was not required for the checkpoint. |
| Rule fired but dashboard showed nothing | `_cat/indices/wazuh-alerts-*` returned empty while Filebeat-to-Indexer ingestion was stalled. It recovered after a short wait; the root cause was not determined. |
| `docker exec -it ... > file` produced an empty file | Dropped `-t`; TTY allocation can corrupt redirected output. Use `docker exec -i` or plain `docker exec` for output capture. |
| OpenSSH was installed on G575 as a side task | It was not required for the checkpoint but later served as the remote source for the first confirmed firing. |

## 9. Lessons Learned

1. **Check host roles first.** `systemctl is-active wazuh-manager wazuh-agent`
   quickly distinguishes the manager from an agent-only host.
2. **Read the parent rule before writing a child.** Check whether a
   proposed parent makes the custom rule meaningful or redundant.
3. **Run manager operations inside the container.** `wazuh-logtest`,
   `local_rules.xml`, and `alerts.json` live inside
   `single-node-wazuh.manager-1`.
4. **Treat `alerts.json` as ground truth.** If the dashboard is empty
   while the raw log contains the alert, investigate
   Filebeat-to-Indexer ingestion rather than the detection rule.
5. **Use a realistic trigger source.** Loopback can prove a rule fires;
   a remote LAN IP provides stronger portfolio evidence.
6. **Do not use `-it` when redirecting output.** Use
   `docker exec <container> <command> > file`, not
   `docker exec -it <container> <command> > file`.

## 10. Evidence

The four screenshots and the 14-line raw alerts sample were not present
in the local files available when this document was prepared. Add them
to the paths below when available; no placeholder evidence files are
included.

| Artefact | Repository path |
|---|---|
| Rule file screenshot | `screenshots/10-first-custom-alert/01-rule-file.png` |
| Logtest screenshot | `screenshots/10-first-custom-alert/02-logtest.png` |
| Restart screenshot | `screenshots/10-first-custom-alert/03-restart.png` |
| Dashboard screenshot | `screenshots/10-first-custom-alert/04-dashboard.png` |
| Raw alerts sample | `notes/10-first-custom-alert-alerts-sample.json` |
| Rule file | `/var/ossec/etc/rules/local_rules.xml` (manager container) |
| Stock backup | `/var/ossec/etc/rules/local_rules.xml.bak` (manager container) |

## 11. Next Steps — Checkpoint 6 Preview

Add rule `100101` to detect a **successful** SSH login following a
brute-force burst from the same source IP. The proposed parent chain is
`5710 → 100100 → 100101`; MITRE ATT&CK `T1078` (Valid Accounts), level
13. This extends detection from repeated failed attempts to a
subsequent successful login.

**Checkpoint 5 status: Complete.**
