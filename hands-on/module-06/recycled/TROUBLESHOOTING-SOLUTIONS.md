# Elasticsearch Setup Troubleshooting Guide
## What Was Wrong & How to Fix It

**Purpose**: Document the real problems encountered and their solutions so students understand why automated setup failed and what to fix.

---

## Problem Summary

When trying to automate Elasticsearch setup on VirtualBox using a bash script with `sudo` commands, the script **fails immediately** at the first `sudo` command with:
```
sudo: a terminal is required to read the password
```

### Root Cause Analysis

**Issue 1: Passwordless Sudo Not Configured**
- **Problem**: SSH remote commands that call `sudo` require either:
  - A TTY (terminal) to be allocated, OR
  - Passwordless sudo configured in `/etc/sudoers.d/`
- **Why it happens**: When you run `ssh user@host "command"`, no TTY is allocated by default
- **Impact**: Script hangs/fails on first `sudo` command
- **Solution**: Configure passwordless sudo for the user

**Issue 2: Heap Configuration Not Applied**
- **Problem**: If you don't explicitly set JVM heap before starting Elasticsearch, it auto-configures to ~50% RAM
- **Why it matters**: On 4.4GB VM, this = 2.2GB heap, leaving only 2.2GB for OS and file cache
- **Result**: Memory contention, slow disk I/O, node instability
- **Fix**: Create `/etc/elasticsearch/jvm.options.d/heap.options` with fixed values BEFORE service start

**Issue 3: Single-Node Config Leftover in Multi-Node Setup**
- **Problem**: Module 00 uses `discovery.type: single-node` to skip bootstrap
- **Why it causes issues**: If this isn't removed when switching to multi-node, cluster formation fails or every node becomes master (split-brain)
- **Fix**: Remove or comment out `discovery.type: single-node` line

**Issue 4: Old Data Prevents Clean Cluster Formation**
- **Problem**: Elasticsearch stores cluster state in `/var/lib/elasticsearch/`
- **Why it causes issues**: Old data from previous runs makes nodes think they belonged to a different cluster
- **Fix**: Execute `sudo rm -rf /var/lib/elasticsearch/*` and `sudo rm -rf /var/log/elasticsearch/*` before modifying config

---

## Solution: Step-by-Step Fixes

### Fix #1: Configure Passwordless Sudo (ONE-TIME SETUP)

**What to do on VirtualBox VM** (to be done ONCE, manually):

```bash
# SSH into VirtualBox
ssh -i ~/.ssh/id_rsa osboxes@192.168.56.101

# Once logged in interactively, run:
echo "osboxes ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/osboxes-nopass > /dev/null
sudo chmod 440 /etc/sudoers.d/osboxes-nopass

# Verify it worked:
sudo -n true && echo "Passwordless sudo works!"
```

**Why**: This allows SSH remote commands to run `sudo` without prompting for password or requiring TTY.

**Student Instruction**:
> "Before automating anything on a Linux VM, you MUST configure passwordless sudo. Otherwise, remote scripts cannot run elevated commands. Log in once, add the rule, then verify with `sudo -n true`."

---

### Fix #2: Create Heap Configuration File

**Before** (original behavior):
```
# Default JVM options - Elasticsearch auto-calculates
# On 16GB VM: heap becomes ~8GB (50% of RAM)
# On 4.4GB VM: heap becomes ~2.2GB (50% of RAM)
# This causes memory pressure on OS and file cache
```

**After** (fixed):
```bash
# Create this file:
sudo tee /etc/elasticsearch/jvm.options.d/heap.options > /dev/null <<'EOF'
-Xms1g
-Xmx1g
EOF

# Verify it exists:
cat /etc/elasticsearch/jvm.options.d/heap.options
```

**Why this works**:
- `/etc/elasticsearch/jvm.options.d/` directory is included by the main config
- Values here OVERRIDE defaults
- 1GB heap on 4.4GB VM = 22.7% of RAM, leaves plenty for OS

**Student Instruction**:
> "Always set JVM heap explicitly. Never rely on auto-calculation. Create `/etc/elasticsearch/jvm.options.d/heap.options` with `-Xms` and `-Xmx` BEFORE starting the service."

---

### Fix #3: Remove Single-Node Discovery Type

**Before** (from Module 00):
```yaml
# This was correct for single-node testing:
discovery.type: single-node
xpack.security.enabled: false
```

**After** (for multi-node or clean single-node):
```yaml
# Remove the line entirely for single-node cluster or multi-node
# DO NOT include discovery.type: single-node in production configs
# It conflicts with bootstrap discovery settings
node.roles: [master, data]  # Explicitly set roles instead
```

**Why this matters**:
- `discovery.type: single-node` tells ES: "Don't wait for other nodes, form cluster with just me"
- If you leave it in place and later add `discovery.seed_hosts`, they conflict
- Remove it to use normal cluster discovery process

**Student Instruction**:
> "If you see `discovery.type: single-node` in a config file, remove it UNLESS you're specifically testing single-node mode. This line should not be in any shared or production config."

---

### Fix #4: Clean Data and Logs Before Reconfiguring

**Before** (trying to restart with new config):
```
# Old data in /var/lib/elasticsearch/ still references old cluster state
# Old logs in /var/log/elasticsearch/ show confusing errors from previous runs
# Elasticsearch won't fully reinitialize if data exists
```

**After** (explicit cleanup):
```bash
# Stop services
sudo systemctl stop elasticsearch kibana
sudo pkill -9 java  # Force kill any zombie processes

# Clean everything
sudo rm -rf /var/lib/elasticsearch/*
sudo rm -rf /var/log/elasticsearch/*
sudo rm -rf /var/lib/kibana/*

# Fix permissions
sudo chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch

# Now reconfigure and restart
```

**Why this works**:
- Elasticsearch initializes fresh with new cluster metadata
- Old logs don't interfere with diagnosis
- Permissions are correct

**Student Instruction**:
> "When debugging cluster issues, the first step is always: stop → clean data → clean logs → restart. Don't skip this; old data prevents proper troubleshooting."

---

## Automated Solution: The Complete Script

**File**: `auto-setup-diagnose.sh`

**What it does**:
1. **Checks prerequisites**: SSH key accessible, VM reachable
2. **Detects sudo status**: Tests if passwordless sudo is configured, sets it up if not
3. **System check**: Verifies RAM, CPU, disk available
4. **Cleanup phase**: Stops services, kills zombies, removes old data
5. **Heap config**: Creates `/etc/elasticsearch/jvm.options.d/heap.options` with 1GB
6. **Write config**: Generates clean `elasticsearch.yml` with correct settings for single-node
7. **Startup**: Starts Elasticsearch and waits for it to be ready (60 seconds)
8. **Validation**: Tests cluster health, verifies heap, checks port listening
9. **Diagnostics**: Pulls logs and config for manual review

**How to use it**:

```bash
# On your local machine (where you run the script):
bash auto-setup-diagnose.sh

# It will:
# - Check your SSH key at ~/.ssh/id_rsa
# - Connect to 192.168.56.101
# - Run all fixes automatically
# - Show you the results
```

**Expected output**:
```
✓ SSH key available
✓ VM reachable at 192.168.56.101
✓ Passwordless sudo already configured
✓ System resources check passed
✓ Cleanup complete
✓ Heap configured to 1GB
✓ Config written
✓ Service active
✓ Port 9200 listening

Test 1: Cluster Health
{
  "cluster_name" : "elk-lab",
  "status" : "green",
  "number_of_nodes" : 1,
  ...
}
```

---

## Minimal Manual Fix (If Script Doesn't Work)

If the automated script encounters issues, apply fixes manually:

```bash
# Step 1: SSH to VM (one-time)
ssh -i ~/.ssh/id_rsa osboxes@192.168.56.101

# Step 2: Disable security (if not already)
sudo sed -i 's/^xpack.security.enabled: true/xpack.security.enabled: false/' /etc/elasticsearch/elasticsearch.yml

# Step 3: Stop and clean
sudo systemctl stop elasticsearch
sudo pkill -9 java
sudo rm -rf /var/lib/elasticsearch/*
sudo rm -rf /var/log/elasticsearch/*

# Step 4: Set heap
echo -e "-Xms1g\n-Xmx1g" | sudo tee /etc/elasticsearch/jvm.options.d/heap.options > /dev/null

# Step 5: Start
sudo systemctl start elasticsearch

# Step 6: Verify (wait 30 seconds, then run this)
curl http://127.0.0.1:9200/_cluster/health?pretty
```

---

## Why This Matters for Students

| Problem | Impact | Fix | Time to Apply |
|---------|--------|-----|----------------|
| Passwordless sudo not set up | Script fails immediately | One 1-line config on VM | 1 minute |
| Heap not configured | Memory pressure, slow cluster | Create heap.options file | 2 minutes |
| Single-node discovery type left in | Split-brain, node formation fails | Remove 1 line from config | 1 minute |
| Old data not cleaned | Stale cluster state blocks formation | `rm -rf /var/lib/elasticsearch/*` | 1 minute |

**Total issue resolution time**: ~5 minutes

**Total time to debug without understanding**: Hours of log-reading and Googling

---

## Replication Checklist for Students

When they encounter "Elasticsearch won't start" or "cluster health is red":

- [ ] Passwordless sudo configured? (`sudo -n true` returns success)
- [ ] Heap file exists? (`cat /etc/elasticsearch/jvm.options.d/heap.options`)
- [ ] `discovery.type: single-node` removed? (`grep discovery.type /etc/elasticsearch/elasticsearch.yml`)
- [ ] Old data cleaned? (`ls -la /var/lib/elasticsearch/` is empty or doesn't exist)
- [ ] Service started cleanly? (`sudo systemctl status elasticsearch`)
- [ ] Port 9200 listening? (`sudo ss -tlnp | grep 9200`)
- [ ] Cluster health green? (`curl http://127.0.0.1:9200/_cluster/health`)

If ANY of the first 4 are "no", apply the corresponding fix above.

---

## Files Modified

1. **Original**: `/etc/elasticsearch/elasticsearch.yml`
   - Removed: `discovery.type: single-node`
   - Kept: All other settings from Module 00
   - Added: Explicit cluster.name and node.roles

2. **Created**: `/etc/elasticsearch/jvm.options.d/heap.options`
   - Content: `-Xms1g` and `-Xmx1g`

3. **Cleaned**: `/var/lib/elasticsearch/*` (deleted)

4. **Cleaned**: `/var/log/elasticsearch/*` (deleted)

5. **Created**: `/etc/sudoers.d/osboxes-nopass` (one-time, before automation)
   - Content: `osboxes ALL=(ALL) NOPASSWD: ALL`

---

## Testing the Fix

After running the automated script or applying fixes manually:

```bash
# From your local machine, test cluster is accessible:
curl http://192.168.56.101:9200/_cluster/health?pretty

# Expected: status is "green" (not yellow or red)
```

If status is **yellow** or **red**, run diagnostics:
```bash
curl http://192.168.56.101:9200/_cat/nodes?v
curl http://192.168.56.101:9200/_cat/shards?v
curl http://192.168.56.101:9200/_cluster/health?pretty
```

---

## Next Steps for Students

1. **Understand**: Read this document top-to-bottom
2. **Replicate**: Follow "Replication Checklist" on a fresh VM
3. **Troubleshoot**: If any step fails, check corresponding section above
4. **Document**: Write down what YOU did differently (variations in paths, versions, etc.)
5. **Multi-Node**: Once single-node works, apply same fixes to multi-node setup (see `MULTI-NODE-CLUSTER-SETUP.md`)
