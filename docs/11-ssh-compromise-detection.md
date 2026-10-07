# Checkpoint 6 — SSH Compromise Detection

**Completed:** 2026-10-07
**Analyst:** Kelvin
**Environment:** Wazuh 4.9.0 — single-node Docker stack
**Manager host:** `LeShepVoPro9` — Windows + WSL Ubuntu 22.04, Docker, IP `192.168.0.168`
**Agent host:** `G575-SOC` — Ubuntu, IP `192.168.0.189`
**Depends on:** Checkpoint 5 — rule `100100` (SSH brute force)

---

## Objective

Write, validate, deploy, and trigger a **second custom Wazuh rule** — `100101` — that detects a **successful SSH login immediately following an SSH brute-force burst from the same source IP**. This escalates the detection from *"someone was knocking"* to *"someone got in."*

---

## Definition of Done

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Rule `100101` written in `local_rules.xml` | ✅ | §3, `cat` output |
| 2 | Validated — manager loaded with no parse errors | ✅ | §4, `wazuh-logtest` clean start |
| 3 | Manager restarted cleanly | ✅ | §5, `docker ps` `Up` |
| 4 | Triggered for real — `100100` then `100101` fired | ✅ | §6, `alerts.json` grep |
| 5 | Visible in dashboard as `100101` at level 13 | ✅ | §7, `screenshots/11-ssh-compromise-detection/01-dashboard-100101.png` |

---

## 1. Rule design

**Detection concept:** a source IP produces a brute-force burst (matches `100100`), and then within 300 seconds successfully authenticates to the same host from the same IP.

**Parent rules:**
- `100100` — custom SSH brute-force rule (level 12), Checkpoint 5
- `5715` — Wazuh built-in *"sshd: authentication success"* (level 3), confirmed at `/var/ossec/ruleset/rules/0095-sshd_rules.xml:139`, matching `<match>^Accepted|authenticated.$</match>`

**Why not `5716`:** `5716` is *"sshd: authentication failed"* — the failure rule, not the success rule. Using it as the parent would have made `100101` fire on more failures, not successes.

**MITRE ATT&CK:** T1078 — Valid Accounts (Defense Evasion, Persistence, Privilege Escalation, Initial Access).

**Level:** 13 — one above `100100`, signaling escalation.

---

## 2. Rule XML

Final `/var/ossec/etc/rules/local_rules.xml`:

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

<group name="ssh,authentication_success,attack,">
  <rule id="100101" level="13" timeframe="300">
    <if_matched_sid>100100</if_matched_sid>
    <if_sid>5715</if_sid>
    <same_source_ip />
    <description>Possible SSH compromise: successful login from $(srcip) after brute-force burst</description>
    <mitre>
      <id>T1078</id>
    </mitre>
  </rule>
</group>
```

### Design notes

| Element | Value | Why |
|---|---|---|
| `frequency="1"` | **removed** | Wazuh rejects `frequency=1` (must be > 1). The correlation gate is `if_matched_sid`, not frequency. |
| `timeframe="300"` | 5 minutes | Gives the attacker time to try valid credentials after the burst |
| `<if_matched_sid>100100</if_matched_sid>` | parent correlation | "Burst happened" precondition |
| `<if_sid>5715</if_sid>` | successful login | "And then a login succeeded" |
| `<same_source_ip />` | source-IP correlation | Prevents unrelated success events from firing the rule |

---

## 3. DoD #1 — Rule file written

```bash
docker exec -it single-node-wazuh.manager-1 cat /var/ossec/etc/rules/local_rules.xml
```

Output confirmed both `100100` and `100101` present, XML well-formed, no invalid attributes.

---

## 4. DoD #2 — Manager validation

Restarted manager with the new rule. `wazuh-logtest` started cleanly with no errors (previously failed with `ERROR: rules_op: Invalid frequency: 1` before the `frequency` attribute was removed).

```bash
/var/ossec/bin/wazuh-logtest
```

Feeding a failed-login line:

```
Jan  1 00:00:00 yoga9 sshd[1]: Failed password for invalid user baduser1 from 203.0.113.99 port 51000 ssh2
```

Clean result — no error, `5710` matched as expected.

**Note on `wazuh-logtest` limits:** the tool does not maintain `if_matched_sid` state across separate input lines the way the live analysis engine does. Feeding 5 failed logins then 1 success does not demonstrate `100101` firing in logtest — this is a logtest limitation, not a rule problem. Live trigger was used to validate (§6).

---

## 5. DoD #3 — Manager restarted cleanly

```bash
docker restart single-node-wazuh.manager-1
sleep 20
docker ps --filter name=wazuh.manager
```

Result: `Up About a minute` — clean start, rule loaded.

---

## 6. DoD #4 — Live trigger

**Prerequisite:** a test user on the agent with a known password.

On the G575:

```bash
sudo useradd -m chk6test
echo 'chk6test:TestPass123!' | sudo chpasswd
```

**Trigger from the manager host (`192.168.0.168`) — burst first, then success:**

```bash
# 1. Burst — 8 failed logins
for i in $(seq 1 8); do
  sshpass -p 'wrongpw' ssh baduser$i@192.168.0.189 \
    -o StrictHostKeyChecking=no \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o ConnectTimeout=3 \
    -o NumberOfPasswordPrompts=1 2>/dev/null &
  sleep 0.3
done
wait

# 2. Wait for 100100 to fire
sleep 10

# 3. Successful login — same source IP
sshpass -p 'TestPass123!' ssh chk6test@192.168.0.189 \
  -o StrictHostKeyChecking=no \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  'echo login-ok; exit'
```

### Result

`100100` fired at level 12 (multiple times) on the burst:

```json
{"timestamp":"2026-10-07T17:06:42.815+0000",
 "rule":{"level":12,
         "description":"SSH brute force: 5+ invalid-user logins in 60s from 192.168.0.168",
         "id":"100100",
         "firedtimes":4},
 "agent":{"id":"001","name":"G575-SOC","ip":"192.168.0.189"},
 "data":{"srcip":"192.168.0.168","srcuser":"baduser4"}}
```

`100101` fired at level 13 on the successful login:

```json
{"timestamp":"2026-10-07T17:07:16.732+0000",
 "rule":{"level":13,
         "description":"Possible SSH compromise: successful login from 192.168.0.168 after brute-force burst",
         "id":"100101",
         "frequency":2,
         "firedtimes":1},
 "agent":{"id":"001","name":"G575-SOC","ip":"192.168.0.189"},
 "data":{"srcip":"192.168.0.168","srcport":"64698","dstuser":"chk6test"}}
```

**Full alert sample:** `configs/checkpoint6-alerts-sample.json` (2 lines)

---

## 7. DoD #5 — Dashboard visibility

Filter: `rule.id` **is** `100101`, Last 1 hour.

| timestamp | agent.name | rule.description | rule.level | rule.id |
|---|---|---|---|---|
| Oct 7, 2026 @ 12:07:16.753 | G575-SOC | Possible SSH compromise: successful login from 192.168.0.168 after brute-force burst | 13 | **100101** |
| Oct 7, 2026 @ 12:07:16.732 | G575-SOC | Possible SSH compromise: successful login from 192.168.0.168 after brute-force burst | 13 | **100101** |

**Screenshot:** `screenshots/11-ssh-compromise-detection/01-dashboard-100101.png`

---

## 8. Agent-side log evidence

From `/var/log/auth.log` on G575-SOC — the full sequence:

```
# Burst — 8 invalid-user attempts (12:06:39–12:06:41)
Oct 7 12:06:39 G575-SOC sshd[11555]: Invalid user baduser1 from 192.168.0.168 port 64708
Oct 7 12:06:39 G575-SOC sshd[11557]: Invalid user baduser2 from 192.168.0.168 port 64718
Oct 7 12:06:40 G575-SOC sshd[11559]: Invalid user baduser3 from 192.168.0.168 port 64720
Oct 7 12:06:40 G575-SOC sshd[11561]: Invalid user baduser4 from 192.168.0.168 port 64732
Oct 7 12:06:40 G575-SOC sshd[11563]: Invalid user baduser5 from 192.168.0.168 port 64744
Oct 7 12:06:41 G575-SOC sshd[11565]: Invalid user baduser6 from 192.168.0.168 port 64750
Oct 7 12:06:41 G575-SOC sshd[11567]: Invalid user baduser7 from 192.168.0.168 port 64752
Oct 7 12:06:41 G575-SOC sshd[11569]: Invalid user baduser8 from 192.168.0.168 port 64764

# Failed passwords — matching rule 5710
Oct 7 12:06:42 G575-SOC sshd[11555]: Failed password for invalid user baduser1 from 192.168.0.168 port 64708 ssh2
Oct 7 12:06:42 G575-SOC sshd[11557]: Failed password for invalid user baduser2 from 192.168.0.168 port 64718 ssh2
...
Oct 7 12:06:43 G575-SOC sshd[11569]: Failed password for invalid user baduser8 from 192.168.0.168 port 64764 ssh2

# Success — the login that triggers rule 100101
Oct 7 12:07:15 G575-SOC sshd[11574]: Accepted password for chk6test from 192.168.0.168 port 64698 ssh2
Oct 7 12:07:15 G575-SOC sshd[11574]: pam_unix(sshd:session): session opened for user chk6test(uid=1001)
Oct 7 12:07:16 G575-SOC systemd-logind[458]: New session 18 of user chk6test.
Oct 7 12:07:17 G575-SOC sshd[11574]: pam_unix(sshd:session): session closed for user chk6test
```

---

## 9. Timezone note

| Host | Time shown | Zone |
|---|---|---|
| G575-SOC (agent) | `12:06–12:07` | CDT (UTC−5) |
| Manager (alerts.json) | `17:06–17:07` | UTC |

**Same events, consistent 5-hour offset.** Wazuh's correlation engine uses arrival time at the manager for window calculations, so `timeframe` rules work correctly regardless of the agent's local clock. But when correlating agent logs with manager alerts manually, apply the 5-hour offset.

---

## 10. Issues encountered and resolved

| Issue | Resolution |
|---|---|
| First rule draft included `frequency="1"` | Wazuh rejects `frequency=1`. Removed the attribute entirely — `if_matched_sid` provides the correlation gate, not frequency. |
| Initially planned parent was `5716` | `5716` is *"sshd: authentication failed"* — wrong signal. Found the correct success rule `5715` by grepping for `Accepted`. |
| `wazuh-logtest` never showed `100101` firing | Known logtest limitation — doesn't maintain `if_matched_sid` state across input lines. Validated with live trigger instead. |
| First live attempt had success **before** burst | `100101` requires burst → success order. Re-ran with correct sequence. |
| PowerShell vs bash confusion during trigger | `for i in $(seq ...)` and `sshpass` are bash-only. Moved to WSL for the burst loop. |
| Line-ending noise in git status | Windows CRLF vs WSL LF. Staged only the two real files; deferred .gitattributes fix. |

---

## 11. Lessons learned

1. **Parent rule selection matters.** Always verify the parent's `<match>` and `<description>` — do not assume from the rule ID alone.
2. **Wazuh rejects `frequency=1`.** Correlation rules use `if_matched_sid` as the trigger condition, not frequency.
3. **Order matters for escalation rules.** Burst first, success second. Reversed, no fire.
4. **`wazuh-logtest` cannot fully validate correlation rules** that depend on prior-event state. Live triggers are the real test.
5. **Same-source-IP correlation** (`<same_source_ip />`) is what makes an escalation rule meaningful — otherwise any successful login anywhere fires it.
6. **Timezone awareness** — agent logs in local time, manager alerts in UTC. Not a bug, but a trap for manual correlation.

---

## 12. Final ruleset

Two custom rules now form a complete SSH attack detection chain:

```
5710  (single invalid-user attempt, level 5)
  └── 100100  (5+ attempts / 60s from same IP, level 12, T1110.001)
                └── 100101  (successful login after burst, level 13, T1078)
```

Narrative: **reconnaissance → attempted intrusion → probable compromise.**

---

## 13. Artefacts

| Artefact | Path |
|---|---|
| Rule file | `/var/ossec/etc/rules/local_rules.xml` (manager container) |
| Alert sample (`100101`) | `configs/checkpoint6-alerts-sample.json` |
| Dashboard screenshot | `screenshots/11-ssh-compromise-detection/01-dashboard-100101.png` |
| Agent log excerpt | `/var/log/auth.log` on G575-SOC |
| Trigger command | §6, bash loop |

---

**Checkpoint 6 status: ✅ COMPLETE**

---

## How to finish this

1. **Save the file** as `docs/11-ssh-compromise-detection.md` in your repo clone:
   - **In WSL:** `nano "/mnt/c/Users/kelvi_f/Downloads/wazuh-home-lab-checkpoint5/docs/11-ssh-compromise-detection.md"` — paste, `Ctrl+O`, Enter, `Ctrl+X`
   - **In VSCode:** open the file, paste, save
   - **In PowerShell:** `notepad "C:\Users\kelvi_f\Downloads\wazuh-home-lab-checkpoint5\docs\11-ssh-compromise-detection.md"` — paste, save

2. **Stage, commit, push:**
   ```powershell
   cd "C:\Users\kelvi_f\Downloads\wazuh-home-lab-checkpoint5"
   git add docs/11-ssh-compromise-detection.md
   git status
   git commit -m "docs: add checkpoint 6 write-up — SSH compromise detection (rule 100101)"
   git push origin main
   ```

3. **Then Checkpoint 6 is fully closed** — evidence + write-up both on GitHub.

Paste the `git status` before committing if you want a sanity check. Otherwise — that's the doc.
