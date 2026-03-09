# Module 06 — Labs 12–14: Observability, Troubleshooting & GenAI Agent Automation (Single-Node Secured Variant)

> **Stack Version**: Elasticsearch 9.x | Kibana 9.x
> **Prereq**: Modules 01–05 and Labs 01–11 completed. **Security enabled** and **trial license activated** (see Prerequisites below).
> **Cluster**: Single-node cluster (192.168.56.101) — security **ON** (`xpack.security.enabled: true`), trial license active.
> **ES Host**: `http://192.168.56.101:9200` — all shell `curl` commands require `-u elastic:<PASSWORD>`.
> **Kibana**: `http://192.168.56.101:5601` — log in with `elastic` / `<PASSWORD>`. Dev Tools queries work as-is (Kibana handles auth automatically).
> **Data state**: `enriched-logs-*` indices are populated from earlier labs. `web-logs-*` and `app-logs-*` should exist from Module 02; if they don't, Lab 14 includes a sample data seeding step to create them.

> **Total estimated time**: 40–70 minutes. This variant includes full hands-on SLO creation and ML anomaly detection (unlocked by the trial license and security).

> These three labs progress from observability concepts with hands-on SLO/ML demos (Lab 12), through hands-on cluster troubleshooting (Lab 13), to automating investigation workflows with a Python-based GenAI agent that authenticates via API key (Lab 14). All labs run on a single-node secured cluster.

---

## Prerequisites: Single-Node Security & Trial License Setup

> Complete these steps **before** starting the labs. If you already have security enabled and a trial license, skip to Lab 12.

### A. Enable security in `elasticsearch.yml`

SSH into the node (192.168.56.101) and edit the Elasticsearch configuration:

```bash
sudo vi /etc/elasticsearch/elasticsearch.yml
```

Ensure these settings are present:

```yaml
# Single-node discovery (no other nodes to find)
discovery.type: single-node

# Enable X-Pack security
xpack.security.enabled: true

# Transport SSL — not required for single-node (no inter-node traffic)
# xpack.security.transport.ssl.enabled: false
```

> On a single-node cluster, you do **not** need transport SSL because there is no inter-node communication. If you had a multi-node cluster, transport SSL would be mandatory when security is enabled.

Restart Elasticsearch:

```bash
sudo systemctl restart elasticsearch
```

Wait for it to come up (30–60 seconds):

```bash
# This should return 401 Unauthorized (security is working!)
curl -s http://192.168.56.101:9200
```

### B. Set the `elastic` superuser password

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i
```

> Enter a password you'll remember (e.g., `Training123!`). This is the `elastic` superuser — used for all admin operations.

Verify:

```bash
curl -u elastic:<PASSWORD> http://192.168.56.101:9200
```

> You should see the cluster info JSON with `"tagline" : "You Know, for Search"`.

### C. Configure Kibana for security

```bash
sudo vi /etc/kibana/kibana.yml
```

Add/uncomment:

```yaml
elasticsearch.username: "kibana_system"
server.publicBaseUrl: "http://192.168.56.101:5601"
```

> The `server.publicBaseUrl` setting is required for Kibana to generate correct redirect URLs. Without it, some browser redirects and SLO/Observability pages may not load properly.

Then store the `kibana_system` password in the Kibana keystore:

```bash
# First set the kibana_system password
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -i

# Then add it to the Kibana keystore
sudo /usr/share/kibana/bin/kibana-keystore add elasticsearch.password
```

Restart Kibana:

```bash
sudo systemctl restart kibana
```

> After ~30 seconds, open `http://192.168.56.101:5601` and log in with `elastic` / `<PASSWORD>`.

### D. Activate the 30-day trial license

In Dev Tools (`Menu ☰ → Management → Dev Tools`):

```json
POST _license/start_trial?acknowledge=true
```

Verify:

```json
GET _license
```

> You should see `"type": "trial"` and `"status": "active"`. This unlocks ML, SLOs, Watcher, and all Platinum features for 30 days. Trial licenses **cannot be restarted** once expired.

### E. Set cluster-wide default replicas to 0

> On a single-node cluster, replicas can never be assigned (there's no second node). Set the default to `0` so all new indices start green:

```json
PUT _settings
{
  "index.number_of_replicas": 0
}
```

> This updates **all existing indices** to 0 replicas. For new indices, set the template default:

```json
PUT _index_template/single-node-defaults
{
  "index_patterns": ["*"],
  "priority": 1,
  "template": {
    "settings": {
      "number_of_replicas": 0
    }
  }
}
```

Verify the cluster is green:

```json
GET _cluster/health
```

> You should see: `"status": "green"`, `"number_of_nodes": 1`, `"unassigned_shards": 0`.

---

## Lab 12: Observability — Concepts, Correlation & Cluster Insights

**Estimated Time**: 15–20 minutes

**Objective**: Understand the three pillars of observability, explore Kibana's observability tooling, run hands-on queries for log correlation and SLI measurement, and **create a real SLO and ML anomaly detection job** using the trial license.

> **Observability** goes beyond monitoring. Monitoring tells you "something is broken." Observability tells you **why** it's broken by correlating three signals: **logs** (what happened), **metrics** (how the system behaved), and **traces** (what path a request took through services).

### Part 1: Observability Architecture

1. Understand the three pillars

```
┌────────────────────────────────────────────────────────┐
│                    Request Journey                       │
│                                                          │
│  User → API Gateway → Auth Service → Payment Service    │
│                                                          │
│  ┌──────┐  ┌─────────┐  ┌────────┐                     │
│  │ LOGS │  │ METRICS │  │ TRACES │                      │
│  │      │  │         │  │        │                      │
│  │Error │  │CPU: 85% │  │Span A  │                      │
│  │in svc│  │Heap:90% │  │ └Span B│ ← shows which       │
│  │      │  │Latency: │  │  └SpanC│   service was slow   │
│  │      │  │  200ms  │  │        │                      │
│  └──────┘  └─────────┘  └────────┘                      │
│                                                          │
│  Correlation: trace.id links all three together          │
└────────────────────────────────────────────────────────┘
```

> In production, **trace.id** is injected by observability agents into every log line, metric sample, and span. Clicking a trace ID in Kibana shows the full request path across all services.

### Part 2: Checking Feature Availability

2. Check which observability features are active on this cluster

```
Menu (☰) → Management → Dev Tools
```

```json
GET _xpack/usage?filter_path=ml,data_streams
```

> With the **trial license active**, you should see:
> - `ml.available: true` — Machine Learning is fully available
> - `ml.enabled: true` — the ML plugin is installed and usable
> - `data_streams` — shows count of active data streams
>
> If `ml.available` shows `false`, verify your trial license is active: `GET _license`. If it expired, you need a new cluster — trial licenses cannot be restarted.

3. Understand how observability data flows into Kibana

> **Why the Observability UI pages are empty on this cluster**: Kibana's Observability UI is populated by **Elastic integrations** — observability agents (Filebeat, Metricbeat, Elastic Agent) that write to data streams following naming conventions (`logs-*`, `metrics-*`, `traces-*`). Our training cluster uses custom indices, so those dashboards are empty.
>
> In production, you would see:
> - **Trace data**: Distributed traces from instrumented services (`traces-*` data streams)
> - **Infrastructure metrics**: CPU, memory, disk from Metricbeat (`metrics-system.*`)
> - **Log streams**: Application logs from Filebeat (`logs-*`)
> - **Service Map**: Auto-generated dependency graph from distributed traces
>
> In this lab, we work directly with the **Elasticsearch APIs** in Dev Tools — which is what matters for troubleshooting and investigation.

4. Auto-instrumentation concepts

> **Auto-instrumentation** means an observability agent automatically captures telemetry (traces, metrics, logs) from your application without requiring code changes to every function. You add the agent library once, and it intercepts HTTP requests, database calls, and inter-service communication.
>
> **How it works**:
> - The agent **monkey-patches** HTTP libraries (e.g., `requests`, `http.client`) to inject `traceparent` headers into outgoing calls
> - Each service reports its spans to a central collector, which correlates them into a **distributed trace** using the shared `trace.id`
> - Framework integrations exist for Python (Django, FastAPI), Java (Spring Boot), Node.js (Express), Go, .NET, and more
> - **Zero code changes** to business logic — the agent handles all instrumentation automatically
>
> This is what makes distributed tracing practical at scale — you don't need to manually add trace context to every service call.

5. Service maps and topology views

> When instrumented services report trace data, Kibana automatically discovers service dependencies and draws a **service map** — a live topology view.

```
┌─────────────────────────────────────────────────────────────┐
│              Service Map (Kibana → Observability)             │
│                                                              │
│  ┌────────────┐       ┌─────────────────┐                   │
│  │  Frontend   │──────▶│  API Gateway    │                   │
│  │  (React)    │       │  (Node.js)      │                   │
│  └────────────┘       └──────┬──────────┘                   │
│                              │                               │
│              ┌───────────────┼───────────────┐               │
│              ▼               ▼               ▼               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Auth Service  │  │ Order Service│  │Product Service│      │
│  │  (Python)     │  │  (Java)      │  │  (Go)        │      │
│  └──────────────┘  └──────┬───────┘  └──────────────┘       │
│                           │                                  │
│                           ▼                                  │
│                   ┌──────────────┐                           │
│                   │Payment Service│                          │
│                   │  (Python)     │ ← high error rate        │
│                   └──────────────┘                           │
│                                                              │
│  Edge color: 🟢 Green = healthy  🔴 Red = errors detected    │
│  Node color: indicates service health (latency + error %)   │
└─────────────────────────────────────────────────────────────┘
```

> **How topology discovery works**:
> - Each instrumented service reports its name and outgoing HTTP calls
> - The `traceparent` header links caller → callee across service boundaries
> - The trace collector correlates spans into distributed traces and builds the dependency graph
> - Kibana renders the map from `traces-*` data streams
>
> **What service maps reveal in production**:
> - **Bottlenecks**: A red node with high latency shows which service is slowing down the chain
> - **Cascading failures**: If Payment Service is failing, the map shows Order Service is affected (it depends on Payment)
> - **Unknown dependencies**: Services calling unexpected endpoints are immediately visible
> - **Blast radius**: Click a failing service to see all upstream callers that are impacted
>
> In our training environment, we don't have instrumented services running, so the service map would be empty. The diagram above represents what you would see in a production microservices environment.

6. Check for data streams on the cluster

```json
GET _data_stream/*?filter_path=data_streams.name
```

> This shows all data streams currently on the cluster. If no integrations are configured, this returns an empty array — that's expected for a training cluster where we use standard indices instead of data streams.

### Part 4: Hands-On Log Correlation Using Enriched Logs

> In a fully instrumented environment, you would correlate logs using `trace.id`. In this training environment, we demonstrate the same **principle** — cross-field correlation — using `user_id` to trace a user's actions across documents in `enriched-logs-*`.

6. Correlate user activity across enriched logs

```json
GET enriched-logs-*/_search
{
  "size": 0,
  "aggs": {
    "by_user": {
      "terms": { "field": "user_id.keyword", "size": 5 },
      "aggs": {
        "actions": {
          "terms": { "field": "action.keyword", "size": 10 }
        },
        "status_breakdown": {
          "terms": { "field": "status.keyword", "size": 5 }
        }
      }
    }
  }
}
```

> This shows each user's actions and success/failure distribution. In production observability, the same pattern applies with `trace.id` — group by trace ID, aggregate spans and logs, identify which service call failed.

7. Identify users with failed actions

```json
GET enriched-logs-*/_search
{
  "size": 5,
  "query": {
    "term": { "status.keyword": "failed" }
  },
  "sort": [{ "@timestamp": "desc" }],
  "_source": ["@timestamp", "user_id", "action", "status", "user_info.name", "user_info.department"]
}
```

> This is the observability equivalent of "find the failing requests" — but using enriched business data instead of HTTP status codes. The enrichment fields (`user_info.name`, `user_info.department`) provide context that raw logs don't have.

### Part 5: SLOs, SLAs, AIOps — Hands-On with Trial License

8. Understand SLO definitions

> | Term | Definition | Example |
> |------|-----------|---------|
> | **SLI** (Service Level Indicator) | A measured metric | 99.2% of requests return in < 200ms |
> | **SLO** (Service Level Objective) | The target | "99.5% of requests must return in < 200ms" |
> | **SLA** (Service Level Agreement) | The contract | "If SLO is violated, customer gets credit" |
> | **Error Budget** | Allowed failures | 0.5% of requests can fail before SLO breach |

9. Compute a pseudo-SLI from enriched logs

> SLIs are measurable metrics. Let's compute one: the **success rate** of user actions in `enriched-logs-*` — treating it as our service's SLI.

```json
GET enriched-logs-*/_search
{
  "size": 0,
  "aggs": {
    "total_actions": { "value_count": { "field": "status.keyword" } },
    "successful_actions": {
      "filter": { "term": { "status.keyword": "success" } },
      "aggs": {
        "count": { "value_count": { "field": "status.keyword" } }
      }
    }
  }
}
```

> **Reading the result**: Divide `successful_actions.count.value` by `total_actions.value` to get the success rate. For example, 24 successes out of 28 total = 85.7% SLI. If your SLO target is 95%, you've breached the error budget.

10. Hands-on: Create an SLO in Kibana

> With the trial license and security enabled, SLO management is **fully available**. Let's create a real SLO based on the SLI we just computed.

**Step 10a**: Navigate to the SLO management page:

```
Menu (☰) → Observability → SLOs → Create SLO
```

**Step 10b**: Configure the SLO:

> | Field | Value |
> |-------|-------|
> | **Name** | `enriched-logs-success-rate` |
> | **SLI type** | Custom KQL |
> | **Index** | `enriched-logs-*` |
> | **Timestamp field** | `@timestamp` |
> | **Good query (KQL)** | `status: success` |
> | **Total query (KQL)** | `*` |
> | **Target** | `95%` |
> | **Time window** | Rolling, 30 days |
> | **Budgeting method** | Occurrences |

Click **Create SLO**.

<details>
<summary><strong>Alternative: Create the SLO via API (curl / command line)</strong></summary>

> If you prefer the command line or want to automate SLO creation, use the **Kibana SLO API** directly. Run this from a terminal (replace `<PASSWORD>` with your `elastic` password):

```bash
curl -s -u "elastic:<PASSWORD>" \
  -X POST "http://192.168.56.101:5601/api/observability/slos" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "enriched-logs-success-rate",
    "description": "Success rate of user actions in enriched logs",
    "indicator": {
      "type": "sli.kql.custom",
      "params": {
        "index": "enriched-logs-*",
        "timestampField": "@timestamp",
        "good": "status: success",
        "total": "*",
        "filter": ""
      }
    },
    "timeWindow": {
      "duration": "30d",
      "type": "rolling"
    },
    "budgetingMethod": "occurrences",
    "objective": {
      "target": 0.95
    }
  }'
```

> **Expected response**: A JSON object with the SLO `id`:
> ```json
> {"id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"}
> ```
>
> Verify the SLO was created:
> ```bash
> curl -s -u "elastic:<PASSWORD>" \
>   "http://192.168.56.101:5601/api/observability/slos" \
>   -H "kbn-xsrf: true" | python3 -m json.tool
> ```
>
> The SLO transform needs ~30 seconds to process. After that, the SLI value, status, and error budget will be populated.

</details>

> **What you should see**: The SLO dashboard shows your SLO with:
> - **Current SLI**: ~85.7% (24 out of 28 — matches our manual calculation from Step 9)
> - **Target**: 95%
> - **Status**: **Violated** — the SLI is below the target
> - **Error budget remaining**: Negative (already breached)
> - **Error budget burn rate**: How fast the budget is depleting
>
> This is exactly what SLO management automates: the same aggregation we ran manually in Step 9, computed continuously on a rolling window, with alerting when the error budget approaches zero.

> **Troubleshooting**: If you see a permissions error, verify: (1) trial license is active (`GET _license`), (2) you're logged in as the `elastic` superuser, (3) security is enabled (`xpack.security.enabled: true`).

11. Hands-on: Create an ML Anomaly Detection Job

> Machine Learning anomaly detection uses unsupervised learning to detect unusual patterns in time-series data. With the trial license, ML is fully available.

**Step 11a**: Navigate to ML:

```
Menu (☰) → Analytics → Machine Learning → Anomaly Detection → Create job
```

**Step 11b**: Select the data source:

> Select `web-logs-*` as the index pattern. If prompted, select the `@timestamp` field as the time field.

**Step 11c**: Choose **Single metric** job:

> | Field | Value |
> |-------|-------|
> | **Aggregation** | Count |
> | **Bucket span** | `15m` |
> | **Job ID** | `web-logs-count-anomaly` |

Click **Create job** → **Start job** → **View results**.

<details>
<summary><strong>Alternative: Create the ML job via API (Dev Tools / curl)</strong></summary>

> You can create and start the ML anomaly detection job entirely through the Elasticsearch API. Run these in Dev Tools or via `curl -u "elastic:<PASSWORD>"`:

**Create the job:**

```json
PUT _ml/anomaly_detectors/web-logs-count-anomaly
{
  "analysis_config": {
    "bucket_span": "15m",
    "detectors": [
      {
        "function": "count"
      }
    ]
  },
  "data_description": {
    "time_field": "@timestamp"
  },
  "analysis_limits": {
    "model_memory_limit": "10mb"
  }
}
```

**Create the datafeed:**

```json
PUT _ml/datafeeds/datafeed-web-logs-count-anomaly
{
  "job_id": "web-logs-count-anomaly",
  "indices": ["web-logs-*"],
  "query": {
    "match_all": {}
  }
}
```

**Open the job and start the datafeed:**

```json
POST _ml/anomaly_detectors/web-logs-count-anomaly/_open

POST _ml/datafeeds/datafeed-web-logs-count-anomaly/_start
```

> **Verify job status:**
> ```json
> GET _ml/anomaly_detectors/web-logs-count-anomaly/_stats
> ```
>
> You should see `"state": "opened"` and `"datafeed_state": "started"` with a non-zero `processed_record_count`.
>
> **Check for anomalies (after the job has run):**
> ```json
> GET _ml/anomaly_detectors/web-logs-count-anomaly/results/buckets?sort=anomaly_score&desc=true&size=5
> ```

</details>

> **What to expect with limited data**: Our seeded data covers only a short time window (~10 minutes). ML jobs need hours or days of data to build a reliable baseline. With this small dataset:
> - The job will run but may not detect statistically significant anomalies
> - The Anomaly Explorer may show a flat line or "no anomalies found"
> - This is **correct behavior** — the model needs more data to learn what's "normal"
>
> **In production**: With continuous data ingest (days/weeks), the ML model learns the normal pattern (e.g., "1000 requests/15min during business hours, 200/15min at night") and alerts when the actual count deviates significantly (e.g., sudden spike to 5000 or drop to 0).

**Step 11d**: Review ML Job Management:

```
Menu (☰) → Analytics → Machine Learning → Anomaly Detection → Job Management
```

> Here you can see:
> - **Job state**: opened/closed
> - **Datafeed state**: started/stopped
> - **Documents processed**: how many documents the model has analyzed
> - **Memory usage**: model memory consumption

12. Feature availability summary

> With the trial license and security enabled, all these features are now **available and functional**:
>
> | Feature | Status | Where to find it |
> |---------|--------|-----------------|
> | **SLO Management** | ✅ Available | `Observability → SLOs` |
> | **Anomaly Detection** | ✅ Available | `Analytics → Machine Learning → Anomaly Detection` |
> | **Log Rate Analysis** | ✅ Available | `AIOps → Log Rate Analysis` |
> | **Synthetic Monitoring** | ✅ Available (requires Elastic Agent) | `Observability → Synthetics` |
> | **Watcher Alerting** | ✅ Available | `Management → Stack Management → Watcher` |
> | **API Key Management** | ✅ Available | `Management → Stack Management → API Keys` |
>
> The key takeaway: we **computed an SLI manually** (Step 9), then **created a real SLO** (Step 10) that automates that same computation on a rolling window. We also **created an ML job** (Step 11) that would detect anomalies in log volume over time. These are production-ready features.

That covers the conceptual foundations with hands-on verification: three pillars of observability, distributed tracing and auto-instrumentation concepts, service map topology, log correlation using available data, SLI computation, and live SLO/ML demos using the trial license.

---

## Lab 13: Troubleshooting and Failure Handling

**Estimated Time**: 15–20 minutes

**Objective**: Diagnose common Elasticsearch cluster issues using systematic diagnostic workflows

> Production clusters fail in predictable ways: unassigned shards, JVM heap pressure, query timeouts, and node instability. This lab teaches you to diagnose and resolve each one using cluster APIs.

### Part A: Cluster Troubleshooting

1. Open Dev Tools

```
Menu (☰) → Management → Dev Tools
```

2. Diagnose unassigned shards

> Unassigned shards are the #1 cause of `yellow` or `red` cluster health. The `_cluster/allocation/explain` API tells you **why** a shard is not assigned.

```json
GET _cluster/health
```

If cluster is `yellow`:

```json
GET _cluster/allocation/explain
```

> Common reasons:
> - **No matching node**: Shard requires a node role that doesn't exist
> - **Disk watermark exceeded**: Node disk usage > 85% (flood stage at 95%)
> - **Max retries exceeded**: Previous allocation failed too many times
> - **Allocation filter**: An index-level setting forces allocation to a non-existent node

3. Check disk watermarks

```json
GET _cat/allocation?v
```

```json
GET _cluster/settings?include_defaults&filter_path=defaults.cluster.routing.allocation.disk
```

> **Key thresholds**:
> - `low`: 85% — no new shards allocated to this node
> - `high`: 90% — shards start relocating away
> - `flood_stage`: 95% — indices go read-only

4. JVM heap pressure analysis

> High heap usage causes GC pauses, which cause search timeouts and indexing delays.

```json
GET _nodes/stats/jvm?human
```

> Look for:
> - `heap_used_percent` — over 75% is concerning, over 85% is critical
> - `gc.collectors.old.collection_count` — frequent old GC collections indicate heap pressure
> - `gc.collectors.old.collection_time` — long GC pauses (>1s) cause request timeouts

```json
GET _cat/nodes?v&h=name,heap.percent,heap.max,cpu,load_1m
```

5. Diagnose query rejections and timeouts

> When thread pools are exhausted, Elasticsearch rejects requests. The `rejected` counter is cumulative and never resets.

```json
GET _cat/thread_pool/search?v&h=node_name,active,queue,rejected
GET _cat/thread_pool/write?v&h=node_name,active,queue,rejected
```

> If `rejected` is non-zero:
> - **Search rejections**: Too many concurrent searches — reduce dashboard auto-refresh rates, add caching
> - **Write rejections**: Indexing too fast — increase `refresh_interval`, use bulk API, or add data nodes

6. Check pending tasks and hot threads

```json
GET _cluster/pending_tasks
GET _nodes/hot_threads
```

> `pending_tasks` shows queued cluster state changes (e.g., creating indices, moving shards). A long queue means the master node is overloaded.
> `hot_threads` shows what each node's threads are doing — helps identify long-running operations.

7. Rolling restart strategy

> **⚠️ Single-node warning**: On a single-node cluster, restarting the node means **total downtime** — there are no other nodes to serve traffic. Rolling restarts are a **multi-node concept**. The procedure below is shown for reference and learning — in production, you would perform this on a multi-node cluster where other nodes handle requests while one node is down.

> When you need to upgrade or restart nodes in a **multi-node** cluster, follow this sequence to minimize disruption:

> **Step 1**: Disable shard allocation (prevents shard movement during the restart)
> ```json
> PUT _cluster/settings
> {
>   "persistent": {
>     "cluster.routing.allocation.enable": "primaries"
>   }
> }
> ```

> **Step 2**: Flush all indices (reduces replay time on restart)
> ```json
> POST _flush
> ```

> **Step 3**: Restart the target node (via systemd on the VM)
> ```
> sudo systemctl restart elasticsearch
> ```

> **Step 4**: Wait for the node to rejoin, then re-enable allocation
> ```json
> PUT _cluster/settings
> {
>   "persistent": {
>     "cluster.routing.allocation.enable": "all"
>   }
> }
> ```

> **Step 5**: Verify cluster recovers to green
> ```json
> GET _cluster/health
> ```
>
> On a single-node cluster, the cluster goes completely offline during Step 3 and returns to green immediately when the node starts — there are no shards to reallocate between nodes.

8. Disaster recovery concepts

> | Strategy | RPO | RTO | Complexity | Single-Node? |
> |----------|-----|-----|------------|--------------|
> | **Snapshots** (to S3/NFS) | Hours | Hours | Low | ✅ Yes |
> | **CCR** (Cross-Cluster Replication) | Seconds | Minutes | Medium | ❌ Requires a second cluster |
> | **Multi-region active-active** | Near-zero | Near-zero | High | ❌ Requires multiple clusters |

Register a snapshot repository (requires `path.repo` configured in `elasticsearch.yml`):

```json
PUT _snapshot/training-backup
{
  "type": "fs",
  "settings": {
    "location": "/tmp/es-snapshots"
  }
}
```

> **Expected result**: If `path.repo` is not configured in `elasticsearch.yml`, you will get: `"location [/tmp/es-snapshots] doesn't match any of the locations specified by path.repo because this setting is empty"`. This is expected — adding `path.repo: ["/tmp/es-snapshots"]` to `elasticsearch.yml` and restarting would enable it.
>
> **If `path.repo` is already configured**, verify it worked:
> ```json
> GET _snapshot/training-backup
> ```
>
> Then take a snapshot:
> ```json
> PUT _snapshot/training-backup/snapshot-1?wait_for_completion=true
> ```
>
> Snapshots are the simplest disaster recovery strategy. For production, use S3 or GCS instead of filesystem.

### Part B: Hands-On Failure Simulation — Cluster Health Diagnostics

**Objective**: Create a real cluster health issue, diagnose it using the APIs from Part A, and resolve it.

#### Diagnostic workflow

1. Run the baseline health checks

```json
GET _cluster/health
GET _cat/nodes?v&h=name,node.role,heap.percent,cpu,load_1m,disk.used_percent
GET _cat/shards?v&h=index,shard,prirep,state,docs,store,node&s=state
```

> Record the current health state. On a single-node cluster, you should see:
> - `"number_of_nodes": 1`
> - `"status": "green"` (if you set the cluster-wide default replicas to 0 in the prerequisites)
> - All shards in `STARTED` state — no replicas

2. Ask Elasticsearch why a shard is unassigned (if any exist)

```json
GET _cluster/allocation/explain
```

> If the cluster is green with no unassigned shards, this will return an error — that's fine, we'll create an unassigned shard in the next step.

3. Classify severity with a simple rule

```
If only replica shards are unassigned and primaries are started:
  → Degraded redundancy, not immediate data-loss risk.

If any primary shard is unassigned:
  → Critical incident (possible data unavailability / loss risk).
```

4. Create a test index to reproduce the yellow health scenario

> On a single-node cluster, **any replica > 0 forces yellow** because there is no second node to host the replica. Even `replicas: 1` creates an unassignable shard.

```json
PUT training-diag-test
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 1
  }
}
```

> With 1 replica requested on a single-node cluster: the primary goes to node-1 (the only node), but replica-1 has **no other node** to be placed on. Check:

```json
GET _cluster/health
GET _cat/shards/training-diag-test?v
```

> You should see:
> - Primary: **STARTED** (on node-1)
> - Replica 1: **UNASSIGNED**
> - Cluster health: **yellow**

5. Diagnose the unassigned replica

```json
GET _cluster/allocation/explain
```

> The response should identify the `decider` that blocked allocation — `same_shard` (cannot place two copies of the same shard on the same node). The allocation explain output will show every node considered and why it was rejected. Since there's only one node, there's nowhere to put the replica.

6. Apply the safe remediation

> On a single-node cluster, replicas provide **no redundancy benefit** — there's only one node, so the replica can never be assigned. Set replicas to **0**:

```json
PUT training-diag-test/_settings
{
  "number_of_replicas": 0
}
```

> **General rule**: Set `number_of_replicas` to `(node_count - 1)` or less. For a single node → `0`. For 2 nodes → `1`. For 3 nodes → `2`.

7. Verify the fix

```json
GET _cluster/health
GET _cat/shards/training-diag-test?v
```

> Cluster health should return to **green**. The single primary shard should show **STARTED** with no replicas.

8. Clean up the test index

```json
DELETE training-diag-test
```

Verify cleanup:

```json
GET _cluster/health
```

> Health should still be green after cleanup.

#### Troubleshooting summary template

Use this format for a structured troubleshooting note:

```
Alert: <health state and trigger>
Finding 1: <unassigned shard count>
Finding 2: <primary vs replica status>
Finding 3: <allocation explain reason>
Risk level: <critical/high/medium/low>
Recommended action: <exact next command>
Verification: <post-action health check>
```

#### Guardrails

> - Do not claim "no risk" until you confirm primaries are assigned.
> - Do not use shell pipes like `grep` inside Dev Tools requests. Keep API calls as valid JSON/REST only.
> - On a single-node cluster, yellow health from unassigned replicas is **expected and normal** — the real risk is unassigned **primaries**.

That covers the diagnostic workflow. You can apply this same sequence to any yellow/red cluster alert.

> **Coming up**: In Lab 14 (next section), you'll build a GenAI agent that automates this same cluster diagnostic workflow. Keep your manual results — you'll compare them against the agent's output.

---

## Lab 14: Automating Investigation Workflows with a GenAI Agent

**Estimated Time**: 15–20 minutes

**Objective**: Build a working GenAI agent that automates the manual investigation workflows from Labs 4 (Alert Triage), 11 Part B (ES|QL Investigation), and 13 (Cluster Diagnostics)

> In the earlier labs, you ran multi-step investigation workflows manually — querying Elasticsearch, interpreting results, and producing structured summaries. This lab automates that entire process using a Python-based GenAI agent that:
> 1. Accepts a natural-language question
> 2. Generates a query plan (via LLM)
> 3. Executes queries against Elasticsearch (read-only, **authenticated via API key**)
> 4. Detects query failures and data gaps before summarizing
> 5. Produces a structured investigation summary
> 6. Waits for human approval before recommending any action

### Part A: Create a Restricted API Key

> With security enabled, the agent needs authentication. Instead of using the `elastic` superuser (which has full admin access), we create a **restricted API key** that grants only read access — a real production best practice.

1. Create the API key in Dev Tools:

```json
POST _security/api_key
{
  "name": "genai-agent-readonly",
  "expiration": "8h",
  "role_descriptors": {
    "readonly_agent": {
      "cluster": ["monitor"],
      "indices": [{ "names": ["web-logs-*", "app-logs-*", "enriched-logs-*"], "privileges": ["read", "view_index_metadata"] }]
    }
  }
}
```

> **Save the response**. You need the `encoded` value — this is the base64-encoded API key that the agent uses:
>
> ```json
> {
>   "id": "abc123...",
>   "name": "genai-agent-readonly",
>   "api_key": "xyz789...",
>   "encoded": "YWJjMTIzOnhlejc4OQ==..."   ← copy THIS value
> }
> ```

> **Why a restricted key**: This key can only `monitor` the cluster and `read` from the three log indices. It **cannot** create or delete indices, change settings, or write data. If the LLM hallucinates a `DELETE` command, the guardrails block it. If someone bypasses the guardrails, the API key itself still prevents writes.

2. Verify the API key works:

> In a terminal on the VM (or from your workstation):

```bash
curl -s -H "Authorization: ApiKey <ENCODED_KEY>" http://192.168.56.101:9200/_cluster/health | python3 -m json.tool
```

> Replace `<ENCODED_KEY>` with your `encoded` value. You should see cluster health JSON.

3. Verify the key is read-only (optional but educational):

```bash
curl -s -X PUT -H "Authorization: ApiKey <ENCODED_KEY>" -H "Content-Type: application/json" \
  http://192.168.56.101:9200/test-write-attempt -d '{"settings":{"number_of_shards":1}}'
```

> This should return a `403 Forbidden` security error — proving the API key cannot write.

### Part B: One-Command Setup

4. Set up the agent environment with the automation script

> The setup script creates `~/genai-agent/`, installs Python dependencies, copies the agent script, and writes the `.env` configuration — all in one command.

```bash
bash ~/GH/hands-on/module-06/genai-agent/setup-agent-secure.sh http://192.168.56.101:9200 <LLM_API_KEY> <ENCODED_ES_API_KEY>
```

> Replace `<LLM_API_KEY>` with the key from the instructor and `<ENCODED_ES_API_KEY>` with the API key from Step 1. If you omit the arguments, the script prompts for them.
>
> If `python3 -m venv` fails on CentOS: `sudo dnf install python3-pip python3-devel -y`, then re-run.
>
> **If no LLM API key is available**: The instructor will demonstrate this step live. You can still review the script to understand the architecture.

Activate the environment:

```bash
cd ~/genai-agent && source .venv/bin/activate
```

<details>
<summary><strong>Manual setup (if the script doesn't work on your environment)</strong></summary>

```bash
cd ~ && mkdir -p genai-agent && cd genai-agent
python3 -m venv .venv && source .venv/bin/activate
pip install openai requests python-dotenv
cp ~/GH/hands-on/module-06/genai-agent/elk_agent.py .
cat > .env << 'ENVFILE'
ES_HOST=http://192.168.56.101:9200
ES_API_KEY=<paste your ENCODED API key here>
LLM_API_KEY=<paste your LLM API key here>
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4o-mini
ENVFILE
python3 -c "import py_compile; py_compile.compile('elk_agent.py'); print('Syntax OK')"
```

</details>

> **What the script contains** (review the source at `~/GH/hands-on/module-06/genai-agent/elk_agent.py`):
> - `es_request()` — read-only Elasticsearch client with endpoint allowlist, blocked HTTP methods, and **API key authentication**
> - `ask_llm()` — OpenAI-compatible LLM wrapper (works with GPT-4o-mini, Azure OpenAI, or local models)
> - `PLANNER_PROMPT` — system prompt that generates a JSON query plan from a natural-language question
> - `SUMMARIZER_PROMPT` — system prompt that produces a structured investigation summary
> - `_repair_json_array()` — robust JSON repair for malformed LLM output
> - `run_investigation()` — three-step pipeline: Plan → Execute → Summarize, with error/data-gap detection and a human approval gate
>
> **How auth works in the agent**: When `ES_API_KEY` is set in `.env`, the agent sends `Authorization: ApiKey <key>` in every Elasticsearch request. This is handled automatically — no code changes needed.
>
> For the full annotated source, see: [`genai-agent/elk_agent.py`](../genai-agent/elk_agent.py)

### Part C: Seed Data and Run the Agent

5. Seed sample data (if needed)

> The agent queries `web-logs-*`, `app-logs-*`, and `enriched-logs-*`. If `web-logs-*` or `app-logs-*` are empty or missing, run the seed script:

```bash
bash ~/GH/hands-on/module-06/genai-agent/seed-data-secure.sh http://192.168.56.101:9200 <ENCODED_ES_API_KEY>
```

> **Note**: The secure seed script uses the API key for authentication. However, the read-only agent API key cannot write data. You have two options:
> 1. **Use the `elastic` superuser** for seeding: `bash seed-data-secure.sh http://192.168.56.101:9200 elastic:<PASSWORD>`
> 2. **Use Dev Tools** (Kibana handles auth): Open [`genai-agent/seed-sample-data.md`](../genai-agent/seed-sample-data.md) and run the two `_bulk` requests manually.
>
> Expected result: `web-logs-*` → 12, `app-logs-*` → 10, `enriched-logs-*` → 28.

6. Run the agent with the same question from Lab 4 (Alert Triage)

```bash
python3 elk_agent.py "An alert fired saying error count exceeded. Which service is failing, are users affected, and what should we do first?"
```

> **Expected output**: The agent generates a query plan (querying `app-logs-*` for error distribution, `web-logs-*` for HTTP 5xx correlation, `enriched-logs-*` for user impact, and `_cluster/health`), executes the queries **using the API key for auth**, and produces a structured investigation summary. With all three indices seeded, the agent should identify `checkout-service` as the failing service with `ConnectionTimeoutError`, correlate it with 500/503 responses on `/api/checkout`, and produce a high-confidence summary.
>
> Compare the output with your manual Lab 4 results:
>
> | Step | Lab 4 (Manual) | Lab 14 (Automated) |
> |------|---------------|-------------------|
> | Error distribution by service | You typed the query | Agent generated it |
> | HTTP 5xx correlation | You typed the query | Agent generated it |
> | Cluster health check | You typed the query | Agent generated it |
> | Impact assessment | You wrote the summary | Agent produced it automatically |

7. Run the agent with the same question from Lab 11 Part B (ES|QL Investigation)

```bash
python3 elk_agent.py "Which services are producing the most errors and which endpoints are affected?"
```

> The agent uses Query DSL (`_search` API) rather than ES|QL syntax, but answers the same questions: error concentration → endpoint correlation → evidence → impact scope. With seeded data, it should identify `checkout-service` (5 errors) and `auth-service` (1 error), plus the `/api/checkout` path from `web-logs-*`.

8. Run the agent with the same question from Lab 13 (Cluster Diagnostics)

```bash
python3 elk_agent.py "The cluster health alert is yellow. What is the root cause and what is the safe fix?"
```

> The agent should query `_cluster/health`, `_cat/shards`, and `_cluster/allocation/explain` — the same APIs you used manually in Lab 13. Since the cluster is currently green (you cleaned up the test index), the agent should report "cluster is green" with high confidence.

### Part D: Understanding the Agent Architecture

9. Review the three-layer design

```
┌──────────────────────────────────────────────────────┐
│                  Agent Architecture                    │
│                                                        │
│  ┌──────────┐   ┌──────────────┐   ┌──────────────┐  │
│  │ PLANNER  │──▶│  EXECUTOR    │──▶│ SUMMARIZER   │  │
│  │ (LLM)    │   │ (Read-only)  │   │ (LLM)        │  │
│  │          │   │              │   │              │  │
│  │ Input:   │   │ Input:       │   │ Input:       │  │
│  │ Question │   │ Query plan   │   │ Results      │  │
│  │          │   │              │   │              │  │
│  │ Output:  │   │ Output:      │   │ Output:      │  │
│  │ Query    │   │ JSON results │   │ Summary +    │  │
│  │ plan     │   │              │   │ next steps   │  │
│  └──────────┘   └──────────────┘   └──────────────┘  │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              GUARDRAILS (Always Active)            │ │
│  │  • Read-only API key (security enforced)          │ │
│  │  • Endpoint allowlist (only _search, _cat, etc.)  │ │
│  │  • Blocked HTTP methods (PUT, DELETE, PATCH)      │ │
│  │  • HTTP error detection (4xx/5xx → flagged)       │ │
│  │  • Data gap detection (0-shard → flagged)         │ │
│  │  • Human approval gate (no auto-remediation)      │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              HUMAN APPROVAL GATE                  │ │
│  │  Agent recommends → Human reviews → Human acts    │ │
│  └──────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

> **Security layers on this cluster**: The agent has **two layers of write protection**:
> 1. **Application-level guardrails** — `BLOCKED_METHODS` list prevents PUT/DELETE/PATCH at the code level
> 2. **Elasticsearch-level API key** — even if guardrails are bypassed, the API key only has `monitor` + `read` privileges; ES itself rejects any write attempt with `403 Forbidden`
>
> This defense-in-depth is exactly how production GenAI agents should be secured.

10. Review the guardrails in the code

Open the script and identify the safety layers:

```bash
grep -n "BLOCKED\|ALLOWED\|Blocked\|approval\|query_errors\|data_gaps" elk_agent.py
```

> **Why guardrails matter**:
> - Without endpoint restrictions, the LLM might generate `DELETE /web-logs-*` or `PUT /_cluster/settings`
> - Without an API key restriction, the agent would have full cluster access
> - Without error/gap detection, the agent silently sends failed query results to the LLM, which produces nonsensical summaries
> - Without human approval, a wrong recommendation executes automatically
> - These are not optional — they are mandatory in any production GenAI + Elasticsearch integration

### How the earlier labs connect to this lab

| Manual Lab | What you learned | What the agent automates |
|-----------|-----------------|------------------------|
| **Lab 4** (Alert Triage) | Multi-query investigation: errors → HTTP correlation → cluster health → impact | Planner generates the same queries from a natural-language alert description |
| **Lab 11 Part B** (ES\|QL Investigation) | Multi-step ES\|QL investigation: error concentration → endpoints → evidence → scope | Planner generates equivalent Query DSL from a vague incident question |
| **Lab 13 Parts A & B** (Cluster Diagnostics) | Systematic cluster diagnostic: health → shards → allocation explain → classify → fix → verify | Planner generates cluster API queries from a health alert trigger |

> The manual labs teach the investigation **logic**. This lab wraps that same logic in an automated pipeline. If you cannot produce the manual summary, the agent's output will not make sense to you either.

---

## Cleanup & Teardown

After completing all three labs, clean up the resources:

```bash
# Remove the genai-agent working directory (course repo copy stays intact)
deactivate 2>/dev/null
rm -rf ~/genai-agent
```

Clean up any remaining test indices (in Dev Tools):

```json
DELETE training-diag-test
```

Clean up the ML job (if created):

```
Menu (☰) → Analytics → Machine Learning → Anomaly Detection → Job Management
```

> Select `web-logs-count-anomaly` → Stop datafeed → Close job → Delete job.

<details>
<summary><strong>Alternative: Delete ML job via API</strong></summary>

```json
POST _ml/datafeeds/datafeed-web-logs-count-anomaly/_stop

POST _ml/anomaly_detectors/web-logs-count-anomaly/_close

DELETE _ml/datafeeds/datafeed-web-logs-count-anomaly

DELETE _ml/anomaly_detectors/web-logs-count-anomaly?force=true
```

</details>

Clean up the SLO (if created):

```
Menu (☰) → Observability → SLOs
```

> Click the SLO → Delete.

<details>
<summary><strong>Alternative: Delete SLO via API</strong></summary>

> First, list all SLOs to get the ID:
> ```bash
> curl -s -u "elastic:<PASSWORD>" \
>   "http://192.168.56.101:5601/api/observability/slos" \
>   -H "kbn-xsrf: true" | python3 -m json.tool
> ```
>
> Then delete by ID:
> ```bash
> curl -s -u "elastic:<PASSWORD>" \
>   -X DELETE "http://192.168.56.101:5601/api/observability/slos/<SLO_ID>" \
>   -H "kbn-xsrf: true"
> ```
>
> Replace `<SLO_ID>` with the `id` from the list response.

</details>

Revoke the API key:

```json
DELETE _security/api_key
{
  "name": "genai-agent-readonly"
}
```

> If you seeded sample data in Lab 14 Step 5 and want to clean it up:
> ```json
> DELETE web-logs-2026.03.07
> DELETE app-logs-2026.03.07
> ```
> Only delete these if the data was created during this lab. If `web-logs-*` and `app-logs-*` were populated from Module 02, leave them intact.

> The `genai-agent/` folder in the course repository (`~/GH/hands-on/module-06/genai-agent/`) should be preserved — it is referenced by Module 07's capstone Lab 5.

That completes Labs 12–14 (Single-Node Secured Variant). You've progressed from observability concepts with hands-on SLO creation and ML anomaly detection, through systematic cluster troubleshooting with real failure simulation, to building and running an automated GenAI investigation agent with production-grade security — API key authentication and defense-in-depth guardrails.
