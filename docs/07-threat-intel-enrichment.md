# Milestone 7 — Threat Intel Enrichment

**Completed:** 2026-11-21
**Analyst:** SOC analyst
**Environment:** Wazuh 4.9.0 — single-node Docker stack

## Objective

Enrich every Wazuh alert with threat intelligence: if an alert's `srcip` matches a known-bad IP from a public threat feed, fire rule `200100` (level 12, MITRE T1194). This turns generic alerts into actionable intel — an SSH brute force from a known C2 IP is a higher-confidence incident than one from an unknown IP.

## Components

| File | Purpose |
|------|---------|
| `scripts/threat-intel-fetch.sh` | Pulls IOCs from Feodo Tracker + Spamhaus DROP, deduplicates, writes a timestamped snapshot |
| `scripts/threat-intel-load.sh` | Converts IOCs to Wazuh CDB list format (`ip -> 1`), deploys to manager container, restarts manager |
| `configs/threat-intel-list-fragment.xml` | `ossec.conf` `<list>` block referencing the CDB list by field `srcip` |
| `configs/threat-intel.rules.xml` | Rule `200100` — fires when any alert's `srcip` is in the threat-intel CDB list |

## Feed sources

- **Feodo Tracker IP blocklist** — `https://feodotracker.abuse.ch/downloads/ipblocklist.csv`
- **Spamhaus DROP list** — `https://www.spamhaus.org/drop/drop.txt`

Both are free, require no API key, and return plain IPv4 lists.

## Rule design

Rule `200100` is parented on rule `1` (every alert) and uses a CDB list lookup:

```xml
<group name="threat-intel,attack,">
  <rule id="200100" level="12" frequency="1">
    <if_sid>1</if_sid>
    <list field="srcip" lookup="address_match">threat-intel-ips</list>
    <description>Connection from known-bad IP $(srcip) on threat intel blocklist</description>
    <mitre>
      <id>T1194</id>
    </mitre>
  </rule>
</group>
```

**Design notes:**

| Element | Value | Why |
|---------|-------|-----|
| `<if_sid>1</if_sid>` | Parent on rule 1 | Fires on any alert that has a `srcip` field |
| `<list field="srcip" lookup="address_match">` | CDB address match | Wazuh resolves `srcip` against the `threat-intel-ips` CDB list |
| Level `12` | Elevated | Known-bad IP involvement raises confidence |
| MITRE `T1194` | Compromise Infrastructure Client | Known-bad IP communication |

## Workflow

### Step 1 — Fetch IOCs

```bash
./scripts/threat-intel-fetch.sh
```

Output: `configs/threat-intel/ips-YYYY-MM-DD_HH-MM-SS.txt` plus a `ips-latest.txt` symlink.

### Step 2 — Load into Wazuh manager

```bash
./scripts/threat-intel-load.sh
```

This:
1. Converts the IP list to `ip -> 1` CDB format
2. Copies `threat-intel-ips.txt` into the manager container at `/var/ossec/etc/lists/`
3. Restarts the manager so Wazuh compiles `.cdb` and loads the list

### Step 3 — Add the `ossec.conf` list reference

Append the contents of `configs/threat-intel-list-fragment.xml` to `/var/ossec/etc/ossec.conf` inside the `<ruleset>` block on the manager, then restart:

```bash
docker exec -it single-node-wazuh.manager-1 \
  bash -c 'cat /var/ossec/etc/rules/local_rules.xml'
```

Restart:

```bash
docker restart single-node-wazuh.manager-1
sleep 15
```

### Step 4 — Add the detection rule

Append `configs/threat-intel.rules.xml` to `/var/ossec/etc/rules/local_rules.xml` on the manager, then restart:

```bash
docker restart single-node-wazuh.manager-1
sleep 15
```

## Validation

1. **`wazuh-logtest`**: Feed an alert line with a known-bad srcip. Rule `200100` should fire alongside the original rule.
   - Note: logtest may not resolve CDB lists the same way the live engine does; a live trigger is the real test.

2. **Live trigger**: From an IP not on the blocklist, generate an alert (e.g., SSH brute force → rule `100100`). Then from a blocklisted IP, generate any alert. Both should fire rule `200100` in addition to their parent rule.

3. **Dashboard**: Filter Threat Hunting → Events by `rule.id` **is** `200100`. You should see alerts from blocklisted IPs tagged with MITRE T1194 at level 12.

## Maintenance

- **Refresh cadence:** Run `threat-intel-fetch.sh` + `threat-intel-load.sh` daily (cron or systemd timer) to keep IOCs current.
- **Retention:** Snapshots are kept under `configs/threat-intel/`; prune old files manually or add a `find -mtime +30 -delete` step.
- **False positives:** If a legitimate IP appears on a feed, remove it from `ips-latest.txt` and re-run `threat-intel-load.sh`.

## Limitations

- **Single-node only:** CDB list lives on the manager container volume; in a multi-manager cluster you'd need to sync the list to every manager.
- **No reciprocal enrichment:** This only checks `srcip` against the list. It does not check `dstip`, domains, or file hashes.
- **Feed quality:** Free feeds have varying coverage and false-positive rates. Tune the level or add per-feed weighting as you gain operational experience.

## Next

Milestone 8 — Active response (auto-block IPs that trigger rule `200100` or `100100` via iptables/nftables on the manager or agent).
