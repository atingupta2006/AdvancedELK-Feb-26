# Module 06 - Labs 05-08

## Cluster Scale, Performance, Security, Multi-Pipeline

---

## Lab 5: Cluster Architecture and Scaling

**Objective**: Understand cluster nodes, shard allocation, and replica configuration

> An Elasticsearch **cluster** is a group of one or more nodes. Each index is divided into **shards** (units of data), and each shard can have **replicas** (copies for fault tolerance). Understanding shard allocation is critical for production scaling.

1. Kibana: Open Dev Tools

```
Menu (☰) → Management → Dev Tools
```

2. Check cluster health

> `_cluster/health` shows overall cluster state, number of nodes, active shards, and any unassigned shards.

```json
GET _cluster/health
```

3. Check node information

> `_cat/nodes` lists all nodes with their roles, heap usage, CPU, and load. The `*` marks the current master node.

```json
GET _cat/nodes?v&h=name,node.role,heap.percent,cpu,load_1m
```

> Node roles: `m` = master-eligible, `d` = data, `i` = ingest, `l` = machine learning. A single-node cluster holds all roles.

4. Review shard allocation

> `_cat/shards` shows which node holds each shard, shard size, and state (STARTED, UNASSIGNED, RELOCATING).

```json
GET _cat/shards?v&h=index,shard,prirep,state,docs,store,node&s=index
```

5. Create index with specific shard settings

> `number_of_shards` is set at index creation and cannot be changed later. `number_of_replicas` can be updated anytime. For single-node setups, replicas stay UNASSIGNED (no second node to place them).

```json
PUT training-scaling-test
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 0
  },
  "mappings": {
    "properties": {
      "@timestamp": { "type": "date" },
      "message": { "type": "text" }
    }
  }
}
```

6. Verify shard distribution

```json
GET _cat/shards/training-scaling-test?v
```

> You should see 3 primary shards (p) all on the same node. With `replicas: 0`, there are no replica shards.

7. Update replica count

> Increasing replicas on a single-node cluster results in UNASSIGNED shards (yellow health). This is expected — replicas need a different node.

```json
PUT training-scaling-test/_settings
{
  "number_of_replicas": 1
}
```

8. Observe cluster health change

```json
GET _cluster/health
GET _cat/shards/training-scaling-test?v
```

> Cluster health turns `yellow` because replica shards cannot be allocated to the same node as their primary.

9. Review cluster statistics

> `_cluster/stats` provides aggregate metrics: total document count, store size, fielddata usage, and JVM stats across all nodes.

```json
GET _cluster/stats?human
```

10. Reset replicas to 0

```json
PUT training-scaling-test/_settings
{
  "number_of_replicas": 0
}
```

**Success**: Cluster health returns to `green`, shard allocation understood

---

## Lab 6: Performance Tuning

**Objective**: Optimize indexing and search performance

> Elasticsearch performance depends on three factors: **indexing speed** (how fast documents are written), **search speed** (how fast queries return), and **resource usage** (JVM heap, disk I/O). This lab covers the most impactful tuning parameters.

1. Kibana: Dev Tools

```
Menu (☰) → Management → Dev Tools
```

2. Create a test index for benchmarking

```json
PUT perf-test-000001
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "refresh_interval": "1s"
  },
  "mappings": {
    "properties": {
      "@timestamp": { "type": "date" },
      "level": { "type": "keyword" },
      "service": { "type": "keyword" },
      "message": { "type": "text" },
      "status": { "type": "integer" }
    }
  }
}
```

3. Bulk index documents

> `_bulk` API indexes multiple documents in a single HTTP request. It is significantly faster than individual `POST _doc` calls — aim for 5-15 MB per bulk request in production.

```json
POST _bulk
{"index":{"_index":"perf-test-000001"}}
{"@timestamp":"2026-02-10T10:00:00Z","level":"INFO","service":"auth-service","message":"User login successful","status":200}
{"index":{"_index":"perf-test-000001"}}
{"@timestamp":"2026-02-10T10:00:01Z","level":"ERROR","service":"payment-service","message":"Payment timeout","status":500}
{"index":{"_index":"perf-test-000001"}}
{"@timestamp":"2026-02-10T10:00:02Z","level":"WARN","service":"inventory-service","message":"Stock running low","status":200}
{"index":{"_index":"perf-test-000001"}}
{"@timestamp":"2026-02-10T10:00:03Z","level":"INFO","service":"auth-service","message":"User logout","status":200}
{"index":{"_index":"perf-test-000001"}}
{"@timestamp":"2026-02-10T10:00:04Z","level":"ERROR","service":"auth-service","message":"Invalid credentials","status":401}
```

4. Increase refresh interval for faster indexing

> `refresh_interval` controls how often Elasticsearch makes new documents searchable. Setting it to `30s` (or `-1` to disable) during heavy indexing reduces I/O overhead dramatically.

```json
PUT perf-test-000001/_settings
{
  "refresh_interval": "30s"
}
```

5. Bulk index more documents, then restore refresh

```json
POST _bulk
{"index":{"_index":"perf-test-000001"}}
{"@timestamp":"2026-02-10T10:01:00Z","level":"INFO","service":"order-service","message":"Order placed","status":201}
{"index":{"_index":"perf-test-000001"}}
{"@timestamp":"2026-02-10T10:01:01Z","level":"ERROR","service":"payment-service","message":"Card declined","status":402}
{"index":{"_index":"perf-test-000001"}}
{"@timestamp":"2026-02-10T10:01:02Z","level":"INFO","service":"notification-service","message":"Email sent","status":200}
```

```json
PUT perf-test-000001/_settings
{
  "refresh_interval": "1s"
}
```

```json
POST perf-test-000001/_refresh
```

6. Profile a slow query

> `"profile": true` returns detailed timing for each query phase (query, collect, build_scorer). Use it to identify which clause is slowest.

```json
GET perf-test-000001/_search
{
  "profile": true,
  "query": {
    "bool": {
      "must": [
        { "match": { "message": "payment" } }
      ],
      "filter": [
        { "range": { "status": { "gte": 400 } } }
      ]
    }
  }
}
```

> Examine the `profile` section in the response. Look for `time_in_nanos` on each collector to find the most expensive operation.

7. Enable request caching

> Shard request cache stores aggregation results. Once cached, repeated identical queries return instantly. Cache is invalidated on refresh.

```json
PUT perf-test-000001/_settings
{
  "index.requests.cache.enable": true
}
```

8. Check index stats

> `_stats` shows indexing rate, search latency, cache hit ratio, and segment count — key metrics for performance monitoring.

```json
GET perf-test-000001/_stats?human
```

9. Force merge (reduce segments)

> Each refresh creates a new Lucene segment. Too many segments slow searches. `_forcemerge` consolidates segments. Only use on indices that are no longer being written to.

```json
POST perf-test-000001/_forcemerge?max_num_segments=1
```

**Success**: Bulk indexing works, query profiling shows timing breakdown, caching enabled

---

## Lab 7: Security and RBAC Configuration

**Objective**: Enable security features and implement role-based access control

> By default, our training environment runs with security disabled. This lab enables Elasticsearch security, creates users with different permission levels, and demonstrates how RBAC controls access to indices and Kibana features.

> **Important**: All subsequent labs (Lab 8 onward) require security to be enabled. Complete this lab fully before proceeding.

1. Enable security in Elasticsearch

```bash
code ~/elasticsearch-security.yml
```

> `xpack.security.enabled: true` activates authentication and authorization. `xpack.security.transport.ssl.enabled: false` is acceptable for single-node training — production requires TLS.

Paste this addition (to append to existing elasticsearch.yml):

```yaml
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: false
```

```bash
sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak
```

Open the actual config and update security settings:

> We use `sed` to replace `false` with `true` instead of appending, to avoid duplicate keys in the YAML file.

```bash
sudo sed -i 's/xpack.security.enabled: false/xpack.security.enabled: true/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/xpack.security.enrollment.enabled: false/xpack.security.enrollment.enabled: true/' /etc/elasticsearch/elasticsearch.yml
```

2. Restart Elasticsearch and set built-in passwords

> `elasticsearch-reset-password` sets passwords for built-in users. The `elastic` superuser is needed to bootstrap Kibana access.

```bash
sudo systemctl restart elasticsearch
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i
```

> Enter a password when prompted (e.g., `Training123!`). Note this password — you'll need it for Kibana.

3. Update Kibana to use credentials

```bash
sudo cp /etc/kibana/kibana.yml /etc/kibana/kibana.yml.bak
```

```bash
sudo sed -i '$ a\\' /etc/kibana/kibana.yml
sudo sed -i '$ a\elasticsearch.username: "kibana_system"' /etc/kibana/kibana.yml
```

> Set the `kibana_system` user password:

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -i
```

```bash
sudo /usr/share/kibana/bin/kibana-keystore add elasticsearch.password
```

> Enter the kibana_system password when prompted.

```bash
sudo systemctl restart kibana
```

4. Log into Kibana with elastic superuser

```
http://127.0.0.1:5601
Username: elastic
Password: <password set in step 2>
```

5. Create custom roles in Kibana

> A **role** defines what indices a user can access and what Kibana features they can use. Index privileges control data access; Kibana privileges control UI features.

```
Menu (☰) → Management → Stack Management → Security → Roles → Create role

Role 1: web-logs-viewer
  Cluster privileges: monitor
  Index privileges:
    Indices: web-logs-*
    Privileges: read, view_index_metadata
  Kibana privileges:
    Space: Default
    Feature: Discover (Read), Dashboard (Read)
  Save

Role 2: app-logs-admin
  Cluster privileges: monitor
  Index privileges:
    Indices: app-logs-*, training-app-*
    Privileges: all
  Kibana privileges:
    Space: Default
    Feature: Discover (All), Dashboard (All), Visualize Library (All)
  Save
```

6. Create users with specific roles

```
Menu (☰) → Management → Stack Management → Security → Users → Create user

User 1:
  Username: viewer01
  Password: Viewer123!
  Roles: web-logs-viewer
  Save

User 2:
  Username: analyst01
  Password: Analyst123!
  Roles: app-logs-admin
  Save
```

7. Test user access restrictions

> Open a private/incognito browser window to test each user without logging out the elastic superuser.

```
New incognito window → http://127.0.0.1:5601
Login as: viewer01 / Viewer123!

Verify:
  - Can access Discover with web-logs-* ✓
  - Cannot see app-logs-* data ✓
  - Cannot create visualizations ✓

Login as: analyst01 / Analyst123!

Verify:
  - Can access Discover with app-logs-* ✓
  - Can create dashboards ✓
  - Cannot see web-logs-* data ✓
```

8. Enable audit logging

> Audit logging records all authentication and authorization events — who accessed what, when, and the outcome (granted/denied). Essential for compliance.

```bash
sudo sed -i '$ a\xpack.security.audit.enabled: true' /etc/elasticsearch/elasticsearch.yml
sudo systemctl restart elasticsearch
```

9. Review audit logs

```bash
sudo tail -20 /var/log/elasticsearch/*_audit.json | head -40
```

> Audit entries include `user`, `action`, `indices`, and `request.name`. Look for `authentication_success` and `access_denied` events.

**Success**: Security enabled, RBAC working, audit logging capturing access events

---

## Lab 8: Logstash Multi-Pipeline Architecture

**Objective**: Configure Logstash with multiple independent pipelines and persistent queues

> In production, a single Logstash pipeline handling all log types becomes a bottleneck. **Multi-pipeline** architecture runs separate pipelines for each data source — isolated processing, independent scaling, and fault isolation.

1. Create pipeline configs directory

```bash
sudo mkdir -p /etc/logstash/pipelines
```

2. Create web logs pipeline

```bash
code ~/module06-pipeline-web.conf
```

Paste this content:

> This pipeline reads web access logs, parses them with grok, and indexes into `web-logs-advanced-*`. The `user` and `password` must match the `elastic` credentials from Lab 7.

```conf
input {
  file {
    path => "/opt/elk-training/data/raw/access.log"
    start_position => "beginning"
    sincedb_path => "/dev/null"
    type => "web"
  }
}

filter {
  grok {
    match => { "message" => '%{IPORHOST:client_ip} %{USER:ident} %{USER:auth} \[%{HTTPDATE:timestamp}\] "(?:%{WORD:method} %{NOTSPACE:path}(?: HTTP/%{NUMBER:http_version})?|%{DATA:raw_request})" %{NUMBER:status:int} (?:%{NUMBER:bytes:int}|-)' }
  }
  date {
    match => ["timestamp", "dd/MMM/yyyy:HH:mm:ss Z"]
    target => "@timestamp"
  }
  mutate { remove_field => ["message", "timestamp"] }
}

output {
  elasticsearch {
    hosts => ["http://127.0.0.1:9200"]
    index => "web-logs-advanced-%{+YYYY.MM.dd}"
    user => "elastic"
    password => "Training123!"
  }
}
```

3. Create app logs pipeline

```bash
code ~/module06-pipeline-app.conf
```

Paste this content:

```conf
input {
  file {
    path => "/opt/elk-training/data/raw/app.log"
    start_position => "beginning"
    sincedb_path => "/dev/null"
    codec => json
  }
}

filter {
  date {
    match => ["timestamp", "ISO8601"]
    target => "@timestamp"
  }
  if [level] == "ERROR" {
    mutate { add_tag => ["error_event"] }
  }
}

output {
  elasticsearch {
    hosts => ["http://127.0.0.1:9200"]
    index => "app-logs-advanced-%{+YYYY.MM.dd}"
    user => "elastic"
    password => "Training123!"
  }
}
```

4. Copy pipeline configs

```bash
sudo cp ~/module06-pipeline-web.conf /etc/logstash/pipelines/web.conf
sudo cp ~/module06-pipeline-app.conf /etc/logstash/pipelines/app.conf
```

5. Configure pipelines.yml

> `pipelines.yml` is the master config that tells Logstash which pipelines to run. Each entry defines a pipeline ID, config path, and optional settings like queue type and workers.

```bash
sudo cp /etc/logstash/pipelines.yml /etc/logstash/pipelines.yml.bak 2>/dev/null || true
code ~/module06-pipelines.yml
```

Paste this content:

> `queue.type: persisted` writes events to disk before processing, preventing data loss if Logstash crashes mid-pipeline. `pipeline.workers` controls parallelism.

```yaml
- pipeline.id: web-pipeline
  path.config: "/etc/logstash/pipelines/web.conf"
  queue.type: persisted
  pipeline.workers: 2

- pipeline.id: app-pipeline
  path.config: "/etc/logstash/pipelines/app.conf"
  queue.type: persisted
  pipeline.workers: 2
```

```bash
sudo cp ~/module06-pipelines.yml /etc/logstash/pipelines.yml
```

6. Enable persistent queue storage

> Persistent queues need a dedicated data directory. Logstash writes incoming events here before filter processing — acts as a buffer.

```bash
sudo mkdir -p /var/lib/logstash/queue
sudo chown logstash:logstash /var/lib/logstash/queue
```

7. Restart Logstash

```bash
sudo systemctl restart logstash
```

8. Monitor pipeline status via API

> Logstash exposes a monitoring API on port 9600. `_node/pipelines` shows each pipeline's status, event throughput, and filter performance.

```bash
curl -s http://127.0.0.1:9600/_node/pipelines?pretty
```

9. Kibana: Verify both pipelines

```
Menu (☰) → Management → Dev Tools

GET web-logs-advanced-*/_count
GET app-logs-advanced-*/_count
```

**Success**: Both pipelines running independently with persistent queues

---

