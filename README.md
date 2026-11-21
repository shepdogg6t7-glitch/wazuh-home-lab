# Wazuh Home Lab

A self-hosted Wazuh SIEM deployment in Docker on WSL 2, with a monitored Ubuntu endpoint, custom detection rules, credential hardening, scripted backups, and 10 documented milestones.

## Purpose

Build a functioning home SOC to practice SIEM operations: deploy Wazuh, onboard a real endpoint, write and validate custom detection rules, harden default credentials, and script volume backups — all on local hardware with no cloud services or paid offerings.

## What I Built

| Area | Detail |
|---|---|
| **SIEM stack** | Wazuh 4.9.0 single-node Docker stack: Indexer (OpenSearch), Manager, Dashboard |
| **Host** | Windows 11 + WSL 2 (Ubuntu 22.04), 12 GB RAM cap, 4 GB swap, `vm.max_map_count=262144` |
| **Endpoint** | Ubuntu 22.04 agent (`G575-SOC`), pinned to Wazuh 4.9.0-1, version hold via `apt-mark hold` |
| **Detection rules** | Custom rule `100100` (SSH brute force, 5+ invalid-user logins / 60s, T1110.001, level 12) and `100101` (successful SSH login after brute-force burst, T1078, level 13) |
| **Hardening** | Rotated default `admin` password via `internal_users.yml` + `securityadmin.sh`; documented 3 gotchas (reserved user, config path, bcrypt `$` shell expansion) |
| **Backups** | `scripts/backup-wazuh.sh` archives compose + configs + 14 Docker volumes to external drive; excludes transient `wazuh_queue` volume; ~30 s, ~1.2 MB, 30-day retention |
| **Documentation** | 10 milestone docs in `docs/` (pre-flight → SSH compromise detection) plus a WSL bind-mount caching gotcha |

## How I Verified It

- **Rule validation:** `wazuh-logtest` started cleanly with no parse errors (after removing invalid `frequency="1"`).
- **Live trigger:** Burst of 8 invalid-user SSH logins then a successful login from the same source IP; both `100100` (level 12) and `100101` (level 13) fired and appeared in `alerts.json` and the dashboard.
- **Agent onboarding:** Dashboard shows `G575-SOC` as Active; `ossec.log` confirms `Connected to the server`.
- **Hardening:** `securityadmin.sh` push returned `Done with success`; fresh browser login succeeded with the new password.
- **Backups:** Script ran end-to-end (~30 s, ~1.2 MB, 14 volumes; `wazuh_queue` excluded).
- **Tests/logs:** Raw alert samples saved in `configs/checkpoint5-alerts-sample.json` and `configs/checkpoint6-alerts-sample.json`.

## Evidence

| Artefact | Path |
|---|---|
| Milestone docs | `docs/02-preflight.md` through `docs/11-ssh-compromise-detection.md` |
| WSL bind-mount gotcha | `docs/09-wsl-mount-gotcha.md` |
| Screenshots | `screenshots/` (deployment, hardening, backup, agent onboarding, rules 100100/100101) |
| Alert samples | `configs/checkpoint5-alerts-sample.json`, `configs/checkpoint6-alerts-sample.json` |
| Backup script | `scripts/backup-wazuh.sh` |
| Rule file | `/var/ossec/etc/rules/local_rules.xml` (manager container) |

## Limitations

- **Single-node only:** No high availability or multi-manager clustering.
- **Local LAN scope:** Manager and agent on `192.168.0.x`; no internet-facing exposure.
- **Public copy redacted:** Hostnames, LAN IPs, account names, and a documented password were replaced with generic labels and TEST-NET-2 placeholders (`198.51.100.10` manager, `198.51.100.20` endpoint) for the public repository.
- **Screenshot gaps:** Two milestone screenshot sets were never captured (pre-flight, kernel/WSL tuning, resource management); command output is the primary evidence for those. One dashboard screenshot (`screenshots/11-ssh-compromise-detection/01-dashboard-100101.png`) exists locally but was deleted from the remote `main` branch (returns 404).
- **WSL bind-mount caveat:** `sed -i` edits can leave container bind mounts stale; files must be streamed into the container and verified by `md5sum` before `securityadmin.sh`.

## Cost Assumptions

- **$0 recurring.** Entirely local and self-hosted: Docker Desktop + WSL 2 on existing hardware (Lenovo Yoga 9, 16 GB RAM). External backup drive (WD My Passport 2 TB) already owned.
- **No paid services:** No cloud SIEM, no managed Wazuh, no SaaS dashboards.
- **Optional paid path not taken:** Wazuh has a commercial cloud offering; this lab deliberately uses the self-hosted open-source stack to keep cost at zero.

---
*Local-only lab. Not connected to any production network. Identifying details redacted for the public copy.*