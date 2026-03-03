# Before & After Comparison
## Configuration Changes for Elasticsearch Single-Node Setup

This document shows exactly what changes were made to fix the setup issues.

---

## File #1: /etc/elasticsearch/elasticsearch.yml

### BEFORE (Module 00 - Single Node Testing)

```yaml
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
cluster.name: elk-lab
node.name: node-1
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node              # ❌ THIS CAUSES PROBLEMS
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
```

### AFTER (Fixed for Automation)

```yaml
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
cluster.name: elk-lab
node.name: node-1
node.roles: [master, data]               # ✅ ADDED - explicitly set roles
network.host: 0.0.0.0
http.port: 9200
# discovery.type: single-node            # ✅ REMOVED - was line 8
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
```

### Changes Summary

| Change | Line | Why |
|--------|------|-----|
| Removed `discovery.type: single-node` | 8 | Prevents conflict with discovery.seed_hosts in multi-node setups. Single-node mode is implied if you don't specify discovery settings |
| Added `node.roles: [master, data]` | 5 | Explicitly tells ES this node can be master and hold data. Prevents role confusion |

### How to Apply This Fix

**Option 1: Edit file manually**
```bash
sudo nano /etc/elasticsearch/elasticsearch.yml
# Find line with: discovery.type: single-node
# Delete that entire line
# Add after network.host: node.roles: [master, data]
```

**Option 2: Use sed command**
```bash
# Comment out the single-node discovery line
sudo sed -i 's/^discovery.type: single-node/# discovery.type: single-node/' /etc/elasticsearch/elasticsearch.yml

# Add node.roles if it doesn't exist (check first)
grep -q "node.roles:" /etc/elasticsearch/elasticsearch.yml || \
  sudo sed -i '/node.name:/a node.roles: [master, data]' /etc/elasticsearch/elasticsearch.yml
```

---

## File #2: /etc/elasticsearch/jvm.options.d/heap.options

### BEFORE (does not exist)

```
File does not exist
↓
Elasticsearch auto-calculates: heap = 50% of available RAM
On 4.4GB VM → ~2.2GB heap (leaves only 2.2GB for OS/cache)
Result: Memory pressure, slow I/O, unstable cluster
```

### AFTER (NEW FILE)

```
/etc/elasticsearch/jvm.options.d/heap.options
────────────────────────────────────────────
-Xms1g
-Xmx1g
```

### Changes Summary

| Setting | Value | Why |
|---------|-------|-----|
| Minimum heap (-Xms) | 1GB | Initial JVM heap size. Matches max to prevent resize pauses |
| Maximum heap (-Xmx) | 1GB | Final JVM heap size. On 4.4GB VM = 22.7%, leaves 3.4GB for OS |

### How to Create This File

**Option 1: Copy-paste**
```bash
# Connect to VM
ssh -i ~/.ssh/id_rsa osboxes@192.168.56.101

# Create the file
sudo tee /etc/elasticsearch/jvm.options.d/heap.options > /dev/null <<'EOF'
-Xms1g
-Xmx1g
EOF

# Verify
cat /etc/elasticsearch/jvm.options.d/heap.options
```

**Option 2: Using echo**
```bash
echo "-Xms1g" | sudo tee /etc/elasticsearch/jvm.options.d/heap.options
echo "-Xmx1g" | sudo tee -a /etc/elasticsearch/jvm.options.d/heap.options
```

### Why This File Location?

The main `/etc/elasticsearch/jvm.options` file has this line:
```
11-# You may also want to add some more options for heap size
12-# settings, as the default JAVA_TOOL_OPTIONS was removed
13-# in JDK 9 - this syntax is supported from there onwards.
14-
15-## GC configuration
16-8-/opt/elasticsearch/config/jvm.options.d/*.options
```

So `/etc/elasticsearch/jvm.options.d/` is automatically included. This is the recommended way to set heap.

---

## Directory #3: /var/lib/elasticsearch/

### BEFORE (Contains Old Data)

```
/var/lib/elasticsearch/
├── .ds-ilm-history-1-000001/
│   ├── 0/
│   │   ├── index/
│   │   │   ├── segment_1
│   │   │   ├── segment_2
│   │   │   └── _state/
│   │   └── translog/
│   │       └── translog.ckp
│   └── _state/
│       └── state-X.st
├── nodes/
│   └── 0/
│       ├── indices/
│       ├── node.lock
│       └── _state/
└── _state/
    └── metadata.st

❌ PROBLEM: Contains state from old ES runs
- Nodes think they belonged to different cluster
- Data indices have stale shard assignments
- Recovery process gets confused
```

### AFTER (Clean Slate)

```
/var/lib/elasticsearch/
(empty - directory is empty or just created)

✅ RESULT: Elasticsearch starts fresh
- New cluster metadata generated
- No shard recovery delays
- Clean node bootstrap
```

### How to Clean This

```bash
# Stop Elasticsearch first
sudo systemctl stop elasticsearch
sudo pkill -9 java  # Make sure all Java processes die

# Remove all data
sudo rm -rf /var/lib/elasticsearch/*

# Fix permissions
sudo chown -R elasticsearch:elasticsearch /var/lib/elasticsearch

# Now you're ready to start
sudo systemctl start elasticsearch
```

### Why This Is Necessary

When you:
1. Change `cluster.name`
2. Change `node.name`
3. Remove/add nodes
4. Change discovery settings

Elasticsearch checks `/var/lib/elasticsearch/_state/metadata.st` and thinks:
- "I don't recognize this cluster name"
- "I don't recognize these node IDs"
- "These shard assignments don't match"

Clean `/var/lib/elasticsearch/*` to force re-initialization.

---

## Directory #4: /var/log/elasticsearch/

### BEFORE (Contains Confusing Logs)

```
/var/log/elasticsearch/
├── elasticsearch.log (10+ MB)
├── elasticsearch-deprecation.log
├── elasticsearch-index-search-slowlog.log
└── elasticsearch-index-indexing-slowlog.log

From previous failed attempts:
"[node_connection_failed]: attempted to connect to..."
"[cluster_block_exception]: index..."
"[discovery_exception]: seed hosts..."
"[bootstrap_checks_failed]: memory pressure..."

❌ PROBLEM: Mixed logs from working + failed states
- Hard to tell which errors are current vs old
- Confusing timestamps
- Takes forever to read through
```

### AFTER (Fresh Logs)

```
/var/log/elasticsearch/
(empty or only contains fresh startup logs)

[2025-03-03T10:15:22,345][INFO ][o.e.e.NodeEnvironment] 
  [elk-lab] using [1] data paths, mounts [[]], net usable_space [14.8gb]...

[2025-03-03T10:15:23,456][INFO ][o.e.p.PluginService]
  [elk-lab] loaded plugin [repository-s3]

[2025-03-03T10:15:25,789][INFO ][o.e.x.PluginsService]
  [elk-lab] started - node started

✅ RESULT: Clean, readable logs from this startup only
```

### How to Clean This

```bash
# Stop Elasticsearch
sudo systemctl stop elasticsearch

# Remove old logs
sudo rm -f /var/log/elasticsearch/*

# Elasticsearch will auto-create new log files on startup
sudo systemctl start elasticsearch

# Check fresh logs
sudo tail -f /var/log/elasticsearch/elasticsearch.log
```

---

## Sudo Configuration: /etc/sudoers.d/osboxes-nopass

### BEFORE (Default - Requires Password)

```
No custom sudoers file
↓
Every sudo command prompts for password
↓
SSH scripts can't provide password (no TTY)
↓
Script fails: "sudo: a terminal is required"
```

### AFTER (Passwordless Sudo)

```
File: /etc/sudoers.d/osboxes-nopass
──────────────────────────────────
osboxes ALL=(ALL) NOPASSWD: ALL
```

### Changes Summary

| Component | Setting | Meaning |
|-----------|---------|---------|
| User(s) | osboxes | This rule applies to user "osboxes" |
| Host(s) | ALL | On all hosts |
| Run as | (ALL) | Can run as any user |
| Commands | ALL | Any command |
| Auth | NOPASSWD | Don't require password |

### How to Create This

**Option 1: One command (most reliable)**
```bash
# SSH into VM first
ssh -i ~/.ssh/id_rsa osboxes@192.168.56.101

# Then run this (will prompt for password once):
echo "osboxes ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/osboxes-nopass > /dev/null
sudo chmod 440 /etc/sudoers.d/osboxes-nopass

# Verify
sudo -n true && echo "✓ Passwordless sudo works!"
```

**Option 2: Using visudo (safer for direct editing)**
```bash
sudo visudo -f /etc/sudoers.d/osboxes-nopass

# Then add this line and save:
osboxes ALL=(ALL) NOPASSWD: ALL
```

### Security Implications

⚠️ **WARNING**: This allows osboxes to run any command as root without password

**For Training/Lab**: ✅ OK - isolated VirtualBox, non-sensitive data

**For Production**: ❌ NEVER - only use for specific commands, e.g.:
```
osboxes ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /bin/rm
```

---

## Summary of All Changes

| File/Directory | Change Type | Before | After | Why |
|---|---|---|---|---|
| /etc/elasticsearch/elasticsearch.yml | Modified | Has `discovery.type: single-node` | Removed, add `node.roles` | Prevent split-brain, explicit roles |
| /etc/elasticsearch/jvm.options.d/heap.options | Created | Doesn't exist | `-Xms1g -Xmx1g` | Control memory, prevent OOM |
| /var/lib/elasticsearch/ | Cleanup | Contains old state | Empty | Force clean bootstrap |
| /var/log/elasticsearch/ | Cleanup | Mixed old/new logs | Fresh logs only | Clear diagnostic view |
| /etc/sudoers.d/osboxes-nopass | Created | Requires password | `NOPASSWD: ALL` | Enable SSH automation |

---

## How Students Can Replicate

### Approach 1: Automated (Run the Script)
```bash
bash auto-setup-diagnose.sh
# Does all 5 changes automatically
# Takes ~2-3 minutes
# Shows you what happened
```

### Approach 2: Manual (Copy-Paste Commands)

```bash
# 1. Set up passwordless sudo (one-time, one-liner)
echo "osboxes ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/osboxes-nopass > /dev/null

# 2. Stop services and clean data
sudo systemctl stop elasticsearch
sudo pkill -9 java
sudo rm -rf /var/lib/elasticsearch/* /var/log/elasticsearch/*

# 3. Create heap file
echo -e "-Xms1g\n-Xmx1g" | sudo tee /etc/elasticsearch/jvm.options.d/heap.options > /dev/null

# 4. Fix elasticsearch.yml
sudo sed -i 's/^discovery.type: single-node/# discovery.type: single-node/' /etc/elasticsearch/elasticsearch.yml
grep -q "node.roles:" /etc/elasticsearch/elasticsearch.yml || \
  sudo sed -i '/node.name:/a node.roles: [master, data]' /etc/elasticsearch/elasticsearch.yml

# 5. Start and verify
sudo systemctl start elasticsearch
sleep 30
curl http://127.0.0.1:9200/_cluster/health?pretty
```

### Approach 3: Understanding (Read TROUBLESHOOTING-SOLUTIONS.md)

See companion document for detailed explanation of each issue and fix.

---

## Verification Checklist

After applying changes, verify each one:

```bash
# Check 1: elasticsearch.yml doesn't have single-node mode
grep "discovery.type: single-node" /etc/elasticsearch/elasticsearch.yml
# Should return NOTHING (or be commented out with #)

# Check 2: Heap file exists and has correct values
cat /etc/elasticsearch/jvm.options.d/heap.options
# Should show:
# -Xms1g
# -Xmx1g

# Check 3: Data directory is empty
ls -la /var/lib/elasticsearch/
# Should be empty or show only: ., .., lost+found

# Check 4: Service is running
sudo systemctl is-active elasticsearch
# Should output: active

# Check 5: Heap is applied to running process
ps aux | grep elasticsearch | grep -oP '\-Xms\S+|\-Xmx\S+'
# Should show: -Xms1g -Xmx1g

# Check 6: Cluster is healthy
curl http://127.0.0.1:9200/_cluster/health?pretty | grep status
# Should show: "status" : "green"
```

If any check fails, refer back to the corresponding fix section above.

