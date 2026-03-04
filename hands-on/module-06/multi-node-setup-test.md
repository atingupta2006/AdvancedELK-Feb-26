# Elasticsearch 9.x - Multi-Node Setup Test (3 Nodes, Minimal and Reliable)

This guide is intentionally simple and environment-independent.

Use variables below and replace only IP values for your target environment.

If you follow this document exactly, you will get a working 3-node cluster.

---

## 0) Variables (set once)

Use these values throughout this document:

```bash
export CLUSTER_NAME="elk-lab-cluster"
export ES_HEAP="1g"

export NODE1_NAME="node-1"
export NODE2_NAME="node-2"
export NODE3_NAME="node-3"

export NODE1_IP="192.168.56.101"
export NODE2_IP="192.168.56.102"
export NODE3_IP="192.168.56.103"
```

Notes:
- Keep `ES_HEAP=1g` for VM stability.
- Replace only the three `NODE*_IP` values in a different environment.

---

## 1) Prerequisites (all 3 VMs)

Run on all 3 VMs:

```bash
sudo -n true
java -version
rpm -qa | grep elasticsearch
free -h
```

Required on each node:
- Passwordless sudo works (`sudo -n true` succeeds)
- Elasticsearch RPM is installed
- At least about 4 GB RAM per VM (1 GB heap + OS headroom)

---

## 2) One-Time OS Setting (all 3 VMs)

```bash
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-elastic.conf
sudo sysctl --system | grep vm.max_map_count
```

Expected output includes `vm.max_map_count = 262144`.

---

## 3) Clean State (all 3 VMs)

```bash
sudo systemctl stop elasticsearch 2>/dev/null || true
sudo pkill -9 java 2>/dev/null || true
sleep 2

sudo rm -rf /var/lib/elasticsearch/*
sudo rm -rf /var/log/elasticsearch/*

sudo mkdir -p /var/lib/elasticsearch /var/log/elasticsearch /var/run/elasticsearch
sudo chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch /var/run/elasticsearch
```

---

## 4) Heap Configuration (all 3 VMs)

```bash
echo -e "-Xms${ES_HEAP}\n-Xmx${ES_HEAP}" | sudo tee /etc/elasticsearch/jvm.options.d/heap.options >/dev/null
sudo chmod 644 /etc/elasticsearch/jvm.options.d/heap.options
sudo cat /etc/elasticsearch/jvm.options.d/heap.options
```

Expected:
```text
-Xms1g
-Xmx1g
```

---

## 5) Elasticsearch Configuration

### 5.1 node-1 (`$NODE1_IP`)

Create `/etc/elasticsearch/elasticsearch.yml`:

```yaml
cluster.name: ${CLUSTER_NAME}
node.name: node-1

path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

network.host: ${NODE1_IP}
network.publish_host: ${NODE1_IP}
http.port: 9200
transport.port: 9300

discovery.seed_hosts: ["${NODE1_IP}", "${NODE2_IP}", "${NODE3_IP}"]
cluster.initial_master_nodes: ["${NODE1_NAME}", "${NODE2_NAME}", "${NODE3_NAME}"]

xpack.security.enabled: false
xpack.security.enrollment.enabled: false
```

### 5.2 node-2 (`192.168.56.102`)

Create `/etc/elasticsearch/elasticsearch.yml`:

```yaml
cluster.name: ${CLUSTER_NAME}
node.name: ${NODE2_NAME}

path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

network.host: ${NODE2_IP}
network.publish_host: ${NODE2_IP}
http.port: 9200
transport.port: 9300

discovery.seed_hosts: ["${NODE1_IP}", "${NODE2_IP}", "${NODE3_IP}"]
cluster.initial_master_nodes: ["${NODE1_NAME}", "${NODE2_NAME}", "${NODE3_NAME}"]

xpack.security.enabled: false
xpack.security.enrollment.enabled: false
```

### 5.3 node-3 (`$NODE3_IP`)

Create `/etc/elasticsearch/elasticsearch.yml`:

```yaml
cluster.name: ${CLUSTER_NAME}
node.name: ${NODE3_NAME}

path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

network.host: ${NODE3_IP}
network.publish_host: ${NODE3_IP}
http.port: 9200
transport.port: 9300

discovery.seed_hosts: ["${NODE1_IP}", "${NODE2_IP}", "${NODE3_IP}"]
cluster.initial_master_nodes: ["${NODE1_NAME}", "${NODE2_NAME}", "${NODE3_NAME}"]

xpack.security.enabled: false
xpack.security.enrollment.enabled: false
```

Set file permissions on all 3 VMs:

```bash
sudo chown root:elasticsearch /etc/elasticsearch/elasticsearch.yml
sudo chmod 640 /etc/elasticsearch/elasticsearch.yml
sudo chown root:elasticsearch /etc/elasticsearch
sudo chmod 2770 /etc/elasticsearch
```

Important: the `/etc/elasticsearch` permission above prevents keystore temp-file startup failures (common boot blocker).

---

## 6) Start Services (all 3 VMs)

Run on all 3 VMs:

```bash
sudo systemctl reset-failed elasticsearch 2>/dev/null || true
sudo systemctl restart elasticsearch
sudo systemctl is-active elasticsearch
```

Expected: `active` on all 3 nodes.

---

## 7) Validate Cluster (run from node-1)

```bash
curl -s http://${NODE1_IP}:9200/_cluster/health?pretty
curl -s http://${NODE1_IP}:9200/_cat/nodes?v
```

Must show:
- `"status" : "green"`
- `"number_of_nodes" : 3`
- All `${NODE1_IP}`, `${NODE2_IP}`, `${NODE3_IP}` in `_cat/nodes`

---

## 8) Post-Bootstrap Cleanup (recommended)

After cluster is green on all 3 nodes, remove bootstrap line from all 3 configs:

```bash
sudo sed -i '/^cluster\.initial_master_nodes:/d' /etc/elasticsearch/elasticsearch.yml
sudo systemctl restart elasticsearch
```

Then validate cluster health again from node-1.

---

## 9) Quick Troubleshooting

If service is not `active`:

```bash
sudo journalctl -u elasticsearch -n 80 --no-pager
```

If you see keystore temp-file error:

```bash
sudo chown root:elasticsearch /etc/elasticsearch
sudo chmod 2770 /etc/elasticsearch
sudo rm -f /etc/elasticsearch/elasticsearch.keystore.tmp
sudo systemctl restart elasticsearch
```

If cluster does not form:
- Confirm each node has unique `network.publish_host` (each node must publish its own IP)
- Confirm transport port `9300` reachable between nodes
- Confirm all nodes use same `cluster.name`

If memory pressure appears:
- Keep `ES_HEAP=1g`
- Stop Kibana/Logstash while forming cluster
- Recheck `free -h`

---

## 10) Success Criteria

Setup is successful when all are true:
- `systemctl is-active elasticsearch` is `active` on all 3 VMs
- `_cluster/health` is `green`
- `number_of_nodes` is `3`
- `_cat/nodes` lists all 3 node IPs

---

## 11) Copy-Paste Templates (Recommended)

Use the exact file content below per node and replace only node-specific values.

### node-1 template

```yaml
cluster.name: elk-lab-cluster
node.name: node-1

path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

network.host: 192.168.56.101
network.publish_host: 192.168.56.101
http.port: 9200
transport.port: 9300

discovery.seed_hosts: ["192.168.56.101", "192.168.56.102", "192.168.56.103"]
cluster.initial_master_nodes: ["node-1", "node-2", "node-3"]

xpack.security.enabled: false
xpack.security.enrollment.enabled: false
```

### node-2 template

```yaml
cluster.name: elk-lab-cluster
node.name: node-2

path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

network.host: 192.168.56.102
network.publish_host: 192.168.56.102
http.port: 9200
transport.port: 9300

discovery.seed_hosts: ["192.168.56.101", "192.168.56.102", "192.168.56.103"]
cluster.initial_master_nodes: ["node-1", "node-2", "node-3"]

xpack.security.enabled: false
xpack.security.enrollment.enabled: false
```

### node-3 template

```yaml
cluster.name: elk-lab-cluster
node.name: node-3

path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch

network.host: 192.168.56.103
network.publish_host: 192.168.56.103
http.port: 9200
transport.port: 9300

discovery.seed_hosts: ["192.168.56.101", "192.168.56.102", "192.168.56.103"]
cluster.initial_master_nodes: ["node-1", "node-2", "node-3"]

xpack.security.enabled: false
xpack.security.enrollment.enabled: false
```

