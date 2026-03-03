# 🚀 VirtualBox Multi-Node Test — Manual Execution Guide

**VM**: 192.168.56.101  
**User**: osboxes  
**Password**: osboxes.org  
**Memory**: 4.4 GB (use 1g heap)

---

## Step 1: SSH into VirtualBox

```bash
ssh osboxes@192.168.56.101
# Password: osboxes.org
```

---

## Step 2: System Precheck (Once logged in)

```bash
free -h
nproc
df -h
```

**Expected**: ~4.4GB RAM, 2 CPUs, 236GB disk

If RAM < 2GB, stop here.

---

## Step 3: Stop Services

```bash
sudo systemctl stop elasticsearch
sudo systemctl stop kibana
sudo pkill -9 java 2>/dev/null || true
sleep 5
```

---

## Step 4: Clean Data & Logs

```bash
sudo rm -rf /var/lib/elasticsearch/*
sudo rm -rf /var/log/elasticsearch/*
sudo rm -rf /var/lib/kibana/* 2>/dev/null || true
sudo rm -rf /var/log/kibana/* 2>/dev/null || true

sudo chown -R elasticsearch:elasticsearch /var/lib/elasticsearch
sudo chown -R elasticsearch:elasticsearch /var/log/elasticsearch
sudo chown -R kibana:kibana /var/lib/kibana 2>/dev/null || true
sudo chown -R kibana:kibana /var/log/kibana 2>/dev/null || true
```

---

## Step 5: Set Low Heap (1GB for VirtualBox)

```bash
echo -e "-Xms1g\n-Xmx1g" | sudo tee /etc/elasticsearch/jvm.options.d/heap.options
cat /etc/elasticsearch/jvm.options.d/heap.options
```

Should show:
```
-Xms1g
-Xmx1g
```

---

## Step 6: Configure Elasticsearch (Single-Node for Testing)

```bash
# Backup original
sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.backup.$(date +%F)

# Write clean config
sudo tee /etc/elasticsearch/elasticsearch.yml > /dev/null <<'EOF'
# Paths
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

# Cluster and node
cluster.name: elk-lab
node.name: node-1

# Network
network.host: 0.0.0.0
http.port: 9200

# Single-node mode
discovery.type: single-node

# Security disabled
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
EOF
```

---

## Step 7: Verify Config

```bash
grep -E 'cluster\.name|node\.name|discovery\.type' /etc/elasticsearch/elasticsearch.yml
```

Should show:
```
cluster.name: elk-lab
node.name: node-1
discovery.type: single-node
```

---

## Step 8: Start Elasticsearch

```bash
sudo systemctl start elasticsearch
sleep 30
```

---

## Step 9: Verify Running

```bash
sudo systemctl status elasticsearch
```

Should show `active (running)`.

---

## Step 10: Test API

```bash
curl -s http://127.0.0.1:9200/_cluster/health?pretty
```

Expected:
```json
{
  "cluster_name" : "elk-lab",
  "status" : "green",
  "timed_out" : false,
  "number_of_nodes" : 1,
  "number_of_data_nodes" : 1,
  ...
}
```

---

## Step 11: Check Memory Usage

```bash
ps aux | grep elasticsearch | grep -oP '\-Xms\S+|\-Xmx\S+'
```

Should show:
```
-Xms1g
-Xmx1g
```

---

## ✅ If all tests pass:

1. ES is running on single-node
2. Heap is limited to 1GB (safe for VirtualBox)
3. Ready for multi-node testing (create 2 more instances on separate VMs or ports)

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Permission denied" on `sudo` | Add to sudoers: `echo "osboxes ALL=(ALL) NOPASSWD: ALL" \| sudo tee /etc/sudoers.d/osboxes-nopass` |
| ES won't start | Check logs: `sudo journalctl -u elasticsearch -n 50 --no-pager` |
| Heap not applied | Restart ES: `sudo systemctl restart elasticsearch` then verify |
| Port 9200 in use | Check: `sudo ss -tlnp \| grep 9200` |

---

## Next: Multi-Node Setup

Once single-node works, edit the config to add discovery settings for 3 nodes (or test on 3 separate VMs).

See: `multi-node-setup.md`
