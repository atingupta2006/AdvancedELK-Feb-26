# 3-Node Elasticsearch Cluster

| Node   | IP           |
|--------|--------------|
| node-1 | 10.0.20.20   |
| node-2 | 10.0.20.26   |
| node-3 | 10.0.20.23   |

> **Hostname**: No need to change OS hostnames — Elasticsearch uses `node.name` from the config, not the OS hostname.

> **`/etc/hosts`**: No changes required — the config uses IP addresses directly in `discovery.seed_hosts`, so no DNS or hosts file lookups are needed.

---

## 1. Stop & Clean (All 3 Nodes)

```bash
sudo systemctl stop elasticsearch
sudo rm -rf /var/lib/elasticsearch/*
sudo rm -rf /var/log/elasticsearch/*
sudo chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
```

## 2. Configure (All 3 Nodes)

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

## 3. Verify Config (Each Node)

```bash
grep -E 'cluster\.name|node\.name|discovery\.|cluster\.initial' /etc/elasticsearch/elasticsearch.yml
```

## 4. Start Cluster

```bash
# Node-1 first
sudo systemctl start elasticsearch    # wait 30s

# Then node-2 and node-3
sudo systemctl start elasticsearch
```

## 5. Validate

```bash
curl -s http://10.0.20.20:9200/_cluster/health?pretty
curl -s http://10.0.20.20:9200/_cat/nodes?v
```

Expected: `number_of_nodes: 3`, status `green`/`yellow`.

## 6. Kibana (One Node Only)

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

## 7. Post-Setup (Optional)

Remove bootstrap setting after cluster is stable:

```bash
sudo sed -i '/cluster.initial_master_nodes/d' /etc/elasticsearch/elasticsearch.yml
```

---

### Quick Troubleshooting

| Issue | Fix |
|-------|-----|
| Nodes not joining | Check `discovery.seed_hosts` has all 3 IPs with `:9300` |
| Connection refused on 9300 | Ensure `network.host: 0.0.0.0`, no `discovery.type: single-node` |
| `master_not_discovered` | Start node-1 first; wait for 9200 response before others |
| Every node shows as master | Old data not cleared — see **"Fix: Every Node is Master"** below |
| Cluster red | Clear all 3 data dirs and re-form |
| Check logs | `sudo journalctl -u elasticsearch -n 100 --no-pager` |

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
