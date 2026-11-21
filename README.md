# Wazuh Home Lab

A local, single-node Wazuh SIEM lab built with Docker on Windows 11 + WSL 2 (Ubuntu 22.04), with an Ubuntu endpoint enrolled as an agent. The project documents deployment, credential hardening, backups, endpoint onboarding, and a tested SSH detection chain.

**Status:** Core lab and detection checkpoints complete  
**Cost model:** Runs on existing local hardware with free/open-source software. No cloud account or paid hosting is required. Hardware, electricity, internet access, and optional external backup storage are not included in that claim.  
**Scope:** Learning lab only; not a production or highly available SIEM.

## What this demonstrates

- Deploy and verify the Wazuh 4.9.0 single-node Docker stack (Indexer, Manager, Dashboard).
- Rotate the default Indexer credentials and document configuration pitfalls.
- Back up Wazuh configuration and Docker volumes to local external storage.
- Enroll and verify a separate Ubuntu 22.04 endpoint.
- Create and validate custom detections, then confirm alerts in both raw alert records and the dashboard.
- Document troubleshooting, platform limitations, and validation evidence rather than presenting a checklist alone.

## Detection walkthrough

The lab generates controlled SSH test activity against the enrolled endpoint and verifies this sequence:

| Rule | Detection | ATT&CK | Validation |
|---|---|---|---|
| `100100` | Five or more invalid-user SSH attempts from one source within 60 seconds | T1110.001 — Password Guessing | `wazuh-logtest`, manager restart, raw alerts, and dashboard |
| `100101` | Successful SSH login from the same source following the brute-force alert | T1078 — Valid Accounts | Live test sequence, raw alerts, and dashboard |

This is authorized, synthetic activity in the owner's lab—not activity against third-party systems. Start with the [first custom alert](docs/10-first-custom-alert.md), then read the [SSH compromise detection](docs/11-ssh-compromise-detection.md). A dashboard screenshot for rule `100101` is in [`screenshots/11-ssh-compromise-detection/`](screenshots/11-ssh-compromise-detection/).

## Architecture

```text
Ubuntu 22.04 endpoint
Wazuh agent 4.9.0
        |
        | agent events over the local network
        v
Windows 11 host / WSL 2 Ubuntu 22.04 / Docker Desktop
  ├── Wazuh Manager 4.9.0
  ├── Wazuh Indexer 4.9.0
  └── Wazuh Dashboard 4.9.0
```

The stack is intended for local lab access. Do not expose the dashboard or agent ports directly to the public internet.

## Start here

This repository is a project record, not a turnkey Compose bundle. Deployment instructions use the official Wazuh Docker repository pinned to `v4.9.0`; review the preflight and resource notes before launching the stack.

1. [Preflight checks](docs/02-preflight.md)
2. [Kernel and WSL notes](docs/03-kernel-and-wsl.md)
3. [Resource management](docs/04-resource-management.md)
4. [Deploy the single-node stack](docs/05-deployment.md)
5. [Credential rotation and hardening](docs/06-hardening.md)
6. [Backup strategy](docs/07-backup-strategy.md)
7. [Agent onboarding](docs/08-agent-onboarding.md)
8. [WSL mount troubleshooting](docs/09-wsl-mount-gotcha.md)
9. [First custom alert: SSH brute force](docs/10-first-custom-alert.md)
10. [Follow-on detection: successful login after brute force](docs/11-ssh-compromise-detection.md)

## Repository map

- [`docs/`](docs/) — milestone writeups, setup, troubleshooting, and detection validation
- [`configs/`](configs/) — sanitized sample alert records; not deployment secrets or a complete stack configuration
- [`scripts/backup-wazuh.sh`](scripts/backup-wazuh.sh) — local backup helper; inspect its paths and volume list before use
- [`screenshots/`](screenshots/) — available visual evidence

## Limitations and safe use

- This is a single-node lab on WSL 2 with one monitored endpoint; it does not demonstrate high availability, enterprise-scale ingestion, or production alert operations.
- Wazuh is pinned to 4.9.0 for reproducibility. Review upstream support and security advisories before using any version outside an isolated lab.
- The included detection tests are controlled demonstrations. Do not reuse test accounts or sample passwords in real environments.
- Review public documentation and screenshots for personal details, hostnames, LAN addresses, credentials, and tokens before adding or refreshing evidence.
- Backups are written to local storage; this repository does not provide hosted storage or an automated cloud backup service.

## License

This repository is distributed under the [MIT License](LICENSE).
