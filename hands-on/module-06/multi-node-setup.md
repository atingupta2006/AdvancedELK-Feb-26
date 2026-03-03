# 3-Node Elasticsearch Cluster

| Node   | IP           |
|--------|--------------|
| node-1 | 10.0.20.20   |
| node-2 | 10.0.20.26   |
| node-3 | 10.0.20.23   |

> **Hostname**: No need to change OS hostnames — Elasticsearch uses `node.name` from the config, not the OS hostname.

> **`/etc/hosts`**: Must be updated on all 3 nodes — see Step 2.

---

## 1. Stop & Clean (All 3 Nodes)

```bash
sudo systemctl stop elasticsearch
sudo rm -rf /var/lib/elasticsearch/*
sudo rm -rf /var/log/elasticsearch/*
sudo chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
```

## 2. Update `/etc/hosts` (All 3 Nodes)

Add these lines to `/etc/hosts` on **each** of the 3 nodes:

```bash
sudo vim /etc/hosts
```

Append:

```
10.0.20.20  node-1
10.0.20.26  node-2
10.0.20.23  node-3
```

This ensures nodes can resolve each other by name during cluster formation.

## 3. Configure (All 3 Nodes)

Your current single-node config (from Module 00) has these settings that **must change**:

| Setting | Single-Node (Module 00) | Multi-Node (Now) |
|---------|------------------------|-------------------|
| `cluster.name` | `elk-training` | `elk-training-cluster` |
| `node.name` | `node-1` (same on all) | Unique per node: `node-1`, `node-2`, `node-3` |
| `discovery.type` | `single-node` | **Remove this line entirely** |
| `discovery.seed_hosts` | _(not set)_ | `["10.0.20.20:9300", "10.0.20.26:9300", "10.0.20.23:9300"]` |
| `cluster.initial_master_nodes` | _(not set)_ | `["node-1", "node-2", "node-3"]` |

```bash
sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak
sudo vim /etc/elasticsearch/elasticsearch.yml
```

Paste on **each node** (only change `node.name`):

```yaml
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
cluster.name: elk-training-cluster
node.name: node-1            # node-2 on 2nd, node-3 on 3rd
network.host: 0.0.0.0
http.port: 9200
discovery.seed_hosts: ["10.0.20.20:9300", "10.0.20.26:9300", "10.0.20.23:9300"]
cluster.initial_master_nodes: ["node-1", "node-2", "node-3"]
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
```

**Make sure** `discovery.type: single-node` is **removed**.

## 4. Verify Config (Each Node)

```bash
grep -E 'cluster\.name|node\.name|discovery\.|cluster\.initial' /etc/elasticsearch/elasticsearch.yml
```

## 5. Start Cluster

```bash
# Node-1 first
sudo systemctl start elasticsearch    # wait 30s

# Then node-2 and node-3
sudo systemctl start elasticsearch
```

## 6. Validate

```bash
curl -s http://10.0.20.20:9200/_cluster/health?pretty
curl -s http://10.0.20.20:9200/_cat/nodes?v
```

Expected: `number_of_nodes: 3`, status `green`/`yellow`.

## 7. Kibana (One Node Only)

```bash
sudo vim /etc/kibana/kibana.yml
```

```yaml
elasticsearch.hosts: ["http://10.0.20.20:9200"]
```

```bash
sudo systemctl restart kibana
```

Open: `http://10.0.20.20:5601`

## 8. Post-Setup (Optional)

Remove bootstrap setting after cluster is stable:

```bash
sudo sed -i '/cluster.initial_master_nodes/d' /etc/elasticsearch/elasticsearch.yml
```

---

### Quick Troubleshooting

| Issue | Fix |
|-------|-----|
| Nodes not joining | Check `/etc/hosts` has all 3 entries, and `discovery.seed_hosts` has all 3 IPs with `:9300` |
| Connection refused on 9300 | Ensure `network.host: 0.0.0.0`, no `discovery.type: single-node` |
| `master_not_discovered` | Start node-1 first; wait for 9200 response before others |
| Every node shows as master | Old data not cleared — see **"Fix: Every Node is Master"** below |
| Cluster red | Clear all 3 data dirs and re-form |
| Check logs | `sudo journalctl -u elasticsearch -n 100 --no-pager` |

---

### Debugging: Node Not Communicating

Run these commands **on the problem node** to find the root cause.

**1. Check if Elasticsearch is running**

```bash
sudo systemctl status elasticsearch
```

**2. Check ES logs for errors**

```bash
sudo journalctl -u elasticsearch -n 200 --no-pager | grep -iE "error|exception|refused|failed|unreachable"
```

**3. Check if transport port 9300 is listening**

```bash
sudo ss -tlnp | grep 9300
```

If nothing shows, ES isn't binding to the transport port — check `network.host` in config.

**4. Test connectivity TO the other nodes**

```bash
# From the problem node, try reaching the other two on transport port:
curl -s http://10.0.20.20:9200    # Can I reach node-1?
curl -s http://10.0.20.26:9200    # Can I reach node-2?
curl -s http://10.0.20.23:9200    # Can I reach node-3?
```

**5. Test network-level connectivity (port 9300)**

```bash
# Check if transport port is reachable:
echo > /dev/tcp/10.0.20.20/9300 && echo "OK" || echo "FAIL"
echo > /dev/tcp/10.0.20.26/9300 && echo "OK" || echo "FAIL"
echo > /dev/tcp/10.0.20.23/9300 && echo "OK" || echo "FAIL"
```

**6. Check `/etc/hosts` is correct**

```bash
cat /etc/hosts | grep node
```

Should show all 3 entries.

**7. Check firewall isn't blocking**

```bash
sudo firewall-cmd --state          # Should say "not running"
sudo iptables -L -n | head -20    # Should show no REJECT/DROP rules
```

**8. Check full startup log**

```bash
sudo journalctl -u elasticsearch --since "10 minutes ago" --no-pager
```

**9. Check Elasticsearch log file directly**

```bash
sudo tail -100 /var/log/elasticsearch/elk-training-cluster.log
```

---

### Fix: Every Node is Master (Split-Brain)

If `_cat/nodes` shows each node as its own master (`*`), each node bootstrapped a separate cluster.

**1. Stop all 3 nodes**

```bash
sudo systemctl stop elasticsearch
```

**2. Check config — remove `discovery.type: single-node`**

```bash
# This should return NOTHING:
grep "discovery.type" /etc/elasticsearch/elasticsearch.yml

# If it returns a line, delete it from the file
```

**3. Clear data on ALL 3 nodes** (this is the key step)

```bash
sudo rm -rf /var/lib/elasticsearch/*
sudo chown -R elasticsearch:elasticsearch /var/lib/elasticsearch
```

**4. Test connectivity between nodes**

```bash
# From node-1, verify you can reach the others:
curl -s http://10.0.20.26:9200
curl -s http://10.0.20.23:9200
```

**5. Start node-1 FIRST, wait, then start others**

```bash
# On node-1 (10.0.20.20) ONLY:
sudo systemctl start elasticsearch

# Wait 30s, confirm it's up:
curl -s http://127.0.0.1:9200/_cluster/health?pretty

# THEN start node-2 and node-3:
sudo systemctl start elasticsearch
```

**6. Verify — only ONE master**

```bash
curl -s http://10.0.20.20:9200/_cat/nodes?v
```

You should see 3 rows, with only **one** node marked with `*` (master).
