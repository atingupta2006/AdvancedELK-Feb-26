# 3-Node Elasticsearch Cluster

| Node   | IP           |
|--------|--------------|
| node-1 | 10.0.20.20   |
| node-2 | 10.0.20.26   |
| node-3 | 10.0.20.23   |

> **Hostname**: No need to change OS hostnames — Elasticsearch uses `node.name` from the config, not the OS hostname.

---

## 1. Stop & Clean (All 3 Nodes)

```bash
sudo systemctl stop elasticsearch
sudo rm -rf /var/lib/elasticsearch/*
sudo rm -rf /var/log/elasticsearch/*
sudo chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch
```

## 2. Configure (All 3 Nodes)

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
| Cluster red | Clear all 3 data dirs and re-form |
| Check logs | `sudo journalctl -u elasticsearch -n 100 --no-pager` |
