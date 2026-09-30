# 08 — First Agent Onboarding (G575-SOC)

**Date:** 2026-09-28
**Status:** ✅ Complete

## Goal

Onboard a real endpoint to the Wazuh Manager. Until this milestone, the
dashboard only saw the Manager's own internal events — a SIEM with no
monitored assets.

This is the milestone that turns a Wazuh deployment into a functioning SOC.

## Environment

| Component | Value |
|-----------|-------|
| Manager | Wazuh 4.9.0 on Yoga 9 (WSL 2 Ubuntu 22.04) |
| Manager IP | 192.168.0.168 |
| Endpoint | Lenovo G575 |
| Endpoint OS | Ubuntu 22.04.5 LTS |
| Endpoint hostname | G575-SOC |
| Agent version | 4.9.0-1 (pinned to match Manager) |

## Commands

On the G575 (endpoint):

```bash
# Import GPG key
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | \
  gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && \
  sudo chmod 644 /usr/share/keyrings/wazuh.gpg

# Add repository
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | \
  sudo tee /etc/apt/sources.list.d/wazuh.list

# Install pinned version
sudo apt update
sudo WAZUH_MANAGER='192.168.0.168' apt install -y --allow-downgrades wazuh-agent=4.9.0-1

# Prevent auto-upgrade
sudo apt-mark hold wazuh-agent

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent

Output
Agent appears in the Wazuh dashboard under Server management → Endpoints Summary:

ID	Name	Status
000	single-node-wazuh.manager-1	Active
001	G575-SOC	Active
The Overview page now shows Agents Summary: Active (1) instead of "No results."

Screenshots
Agent active

Overview showing 1 active agent

What I Learned
A SIEM with no agents is just a web application. The dashboard's
value only appears once real endpoints are reporting events.

Version alignment is enforced, not suggested. The Manager rejects
any agent whose version is newer than its own. The check happens at
enrollment, and the error message is misleading.

apt install wazuh-agent without a version pin installs the latest
available version — which was 4.14.8, while the Manager was 4.9.0.

apt-mark hold is required to prevent future apt upgrade runs
from pulling the agent back up and breaking the connection again.

The endpoint's hostname becomes the agent name automatically. No
extra configuration needed — naming the machine G575-SOC during
Ubuntu install was sufficient.

Gotcha 1 — Agent Version Newer Than Manager
After running apt install -y wazuh-agent (no version pin), the agent
installed successfully but the log showed:

text
ERROR: Agent version must be lower or equal to manager version (from manager)
ERROR: Unable to add agent (from manager)
The installed agent was 4.14.8. The Manager was 4.9.0. Wazuh
enforces that agent version ≤ manager version, and the check happens at
enrollment — the agent will retry every 30 seconds forever and never
succeed.

Fix: pin the version explicitly and allow downgrade:

sudo apt install -y --allow-downgrades wazuh-agent=4.9.0-1
sudo apt-mark hold wazuh-agent

The hold prevents the problem from recurring on the next apt upgrade.

Gotcha 2 — syscollector Config Tag Incompatibility
After downgrading to 4.9.0-1, the service still refused to start:

ERROR: No such tag 'users' at module 'syscollector'.
ERROR: (1202): Configuration error at 'etc/ossec.conf'.

Root cause: the 4.14.8 install had written new config tags into
ossec.conf — <users>, <groups>, <services>, and
<browser_extensions> inside the <syscollector> block. Those tags were
added in newer Wazuh versions and don't exist in 4.9.0. The 4.9.0 agent
rejected its own config file.

Fix: strip the unsupported tags:

sudo sed -i '/<users>yes<\/users>/d; /<groups>yes<\/groups>/d; \
  /<services>yes<\/services>/d; /<browser_extensions>yes<\/browser_extensions>/d' \
  /var/ossec/etc/ossec.conf

Then restart:

sudo systemctl restart wazuh-agent

Verification

$ sudo grep "Connected to the server" /var/ossec/logs/ossec.log | tail -1
2026/09/28 16:02:20 wazuh-agentd: INFO: (4102): Connected to the server ([192.168.0.168]:1514/tcp).

$ dpkg -l wazuh-agent | tail -1
hi  wazuh-agent  4.9.0-1  amd64  ...

The h prefix means the package is held, i means installed.

Next
Milestone 9 — Generate a real security event on the endpoint and triage
it in the dashboard.

→ 09-first-alert.md


**Save:** `Ctrl + O`, `Enter`, `Ctrl + X`.

---

### ▶️ Step 2 — Verify

ls -la docs/08-agent-onboarding.md
wc -l docs/08-agent-onboarding.md


**Paste the output.**

---

### ⏸️ Pause After Step 2

Once the doc exists, we commit and push it, then we're done with the recovery.

**Create the doc. Save. Verify. Paste the output. Pause.**
















































































