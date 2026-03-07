# Module 06 — Labs 12–14: Observability, Troubleshooting & GenAI Agent Automation

> **Stack Version**: Elasticsearch 9.x | Kibana 9.x
> **Prereq**: Modules 01–05 and Labs 01–11 completed.
> **Cluster**: 3-node cluster (node-1, node-2, node-3) — security **OFF**.
> **ES Host**: Replace `<CLUSTER_NODE1_IP>` with the IP of any cluster node (provided by the instructor). Example: `http://<CLUSTER_NODE1_IP>:9200`.
> **Kibana**: `http://<CLUSTER_NODE1_IP>:5601`
> **Data state**: `enriched-logs-*` indices are populated from earlier labs. `web-logs-*` and `app-logs-*` should exist from Module 02; if they don't, Lab 14 includes a sample data seeding step to create them.
> **Shared environment**: Multiple students share the same cluster. Use **your name or initials** when creating test indices (e.g., `training-diag-test-jsmith`) to avoid conflicts.

> **Total estimated time**: 30–60 minutes. Automation scripts handle data seeding and agent environment setup — you focus on running queries and interpreting results.

> These three labs progress from observability concepts (Lab 12), through hands-on cluster troubleshooting (Lab 13), to automating investigation workflows with a Python-based GenAI agent (Lab 14). All labs run on the same 3-node cluster.

---

## Lab 12: Observability — Concepts, Correlation & Cluster Insights

**Estimated Time**: 10–15 minutes

**Objective**: Understand the three pillars of observability, explore Kibana's observability tooling, and run hands-on queries that demonstrate log correlation and SLI measurement using available cluster data.

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

> This shows which X-Pack features are enabled and have data. On a **basic license** (the default for training clusters), you will see:
> - `ml.available: false` — Machine Learning requires a **Platinum, Enterprise, or Trial** license
> - `ml.enabled: true` — the ML plugin is installed but not usable on the basic license
> - `data_streams` — shows count of active data streams
>
> **To activate a 30-day trial** (optional — enables ML, Watcher, and other platinum features):
> ```json
> POST _license/start_trial?acknowledge=true
> ```
> After activation, re-run the `_xpack/usage` query and `ml.available` will change to `true`. Trial licenses **cannot be restarted** once expired.

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

### Part 5: SLOs, SLAs, and AIOps Concepts

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

10. SLO management and AIOps features (concept overview)

> Kibana 9.x includes native **SLO management** and **AIOps** features that build on the SLI concepts above:
>
> | Feature | What it does | License Required |
> |---------|-------------|------------------|
> | **SLO Management** (`Observability → SLOs`) | Define SLI + target, track error budget over rolling window | Platinum / Enterprise / Trial + Security |
> | **Anomaly Detection** (`ML → Anomaly Detection`) | ML jobs detect unusual patterns (latency spikes, log volume changes) | Platinum / Enterprise / Trial |
> | **Log Rate Analysis** | Identifies when log volume changes significantly | Platinum / Enterprise / Trial |
> | **Synthetic Monitoring** (`Observability → Synthetics`) | Simulated user journeys that detect issues before real users do | Platinum / Enterprise / Trial |
>
> **Why we don't demo these in the UI**: These features require a **Platinum or Trial license** (our training cluster uses a basic license) and **security enabled with proper roles**. On a basic license, the SLO page shows a permissions error and ML shows an upgrade prompt. In production environments with the appropriate license, these are powerful tools.
>
> **To try them**: Activate a 30-day trial (`POST _license/start_trial?acknowledge=true`), enable security, and configure role permissions. Trial licenses cannot be restarted once expired — use them judiciously.
>
> The key takeaway: we just **computed an SLI manually** (Step 9) using aggregation queries. SLO management automates that same computation on a rolling window and alerts when the error budget is breached.

That covers the conceptual foundations with hands-on verification: three pillars of observability, distributed tracing and auto-instrumentation concepts, service map topology, log correlation using available data, SLI computation, and production tooling awareness.

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

> When you need to upgrade or restart nodes, follow this sequence to minimize disruption. The commands below are safe to run on a training cluster but will temporarily disrupt the cluster — **run them only if the instructor directs you to.**

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
> In our multi-node cluster, restarting one node will cause a brief yellow state while shards reallocate. The cluster should return to green within 30–60 seconds after re-enabling allocation.

8. Disaster recovery concepts

> | Strategy | RPO | RTO | Complexity |
> |----------|-----|-----|------------|
> | **Snapshots** (to S3/NFS) | Hours | Hours | Low |
> | **CCR** (Cross-Cluster Replication) | Seconds | Minutes | Medium |
> | **Multi-region active-active** | Near-zero | Near-zero | High |

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

> **Expected result**: If `path.repo` is not configured in `elasticsearch.yml`, you will get: `"location [/tmp/es-snapshots] doesn't match any of the locations specified by path.repo because this setting is empty"`. This is expected — adding `path.repo: ["/tmp/es-snapshots"]` to all nodes' `elasticsearch.yml` and restarting would enable it.
>
> **If `path.repo` is already configured** (check with instructor), verify it worked:
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

> Record the current health state, node count, and any existing unassigned shards.

2. Ask Elasticsearch why a shard is unassigned (if any exist)

```json
GET _cluster/allocation/explain
```

> This is the highest-value API for this lab. It tells you exactly why allocation is blocked. If the cluster is already green with no unassigned shards, this will return an error — that's fine, we'll create an unassigned shard in the next step.

3. Classify severity with a simple rule

```
If only replica shards are unassigned and primaries are started:
  → Degraded redundancy, not immediate data-loss risk.

If any primary shard is unassigned:
  → Critical incident (possible data unavailability / loss risk).
```

4. Create a test index to reproduce the yellow health scenario

> First, check how many nodes are in the cluster:
> ```json
> GET _cat/nodes?h=name
> ```
> Count the nodes. To force a **yellow** state, you need **more replicas than (node_count - 1)**. On a 3-node cluster, `replicas: 2` stays green (primary + 2 replicas = 3 copies across 3 nodes). You need `replicas: 3` or higher.

> **Replace `<YOUR_INITIALS>` below** with your name/initials to avoid conflicts with other students.

```json
PUT training-diag-test-<YOUR_INITIALS>
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 3
  }
}
```

> With 3 replicas requested on a 3-node cluster: primary goes to node-1, replica-1 to node-2, replica-2 to node-3 — but replica-3 has **no node left**. Check:

```json
GET _cluster/health
GET _cat/shards/training-diag-test-<YOUR_INITIALS>?v
```

> You should see:
> - Primary: **STARTED** (on one node)
> - Replica 1: **STARTED** (on a second node)
> - Replica 2: **STARTED** (on a third node)
> - Replica 3: **UNASSIGNED**
> - Cluster health: **yellow**

5. Diagnose the unassigned replica

```json
GET _cluster/allocation/explain
```

> The response should identify the `decider` that blocked allocation — likely `same_shard` (cannot place two copies of the same shard on the same node) or `throttling`. This is exactly how you would diagnose an unassigned shard in production.

6. Apply the safe remediation

> Reduce replicas to match available nodes. On a 3-node cluster, `2` replicas is the maximum that can be fully assigned (primary + 2 replicas = 3 copies across 3 nodes). On a 2-node cluster, use `1`.

```json
PUT training-diag-test-<YOUR_INITIALS>/_settings
{
  "number_of_replicas": 2
}
```

> **Adjust the value**: Set `number_of_replicas` to `(node_count - 1)`. For 3 nodes → `2`. For 2 nodes → `1`.

7. Verify the fix

```json
GET _cluster/health
GET _cat/shards/training-diag-test-<YOUR_INITIALS>?v
```

> Cluster health should return to **green**. All shards (1 primary + N replicas) should show **STARTED**.

8. Clean up the test index

> **Important**: Only delete YOUR test index — not other students' indices.

```json
DELETE training-diag-test-<YOUR_INITIALS>
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
> - For training clusters, prefer index-level replica updates to broad wildcard updates.

That covers the diagnostic workflow. You can apply this same sequence to any yellow/red cluster alert.

> **Coming up**: In Lab 14 (next section), you'll build a GenAI agent that automates this same cluster diagnostic workflow. Keep your manual results — you'll compare them against the agent's output.

---

## Lab 14: Automating Investigation Workflows with a GenAI Agent

**Estimated Time**: 15–20 minutes

**Objective**: Build a working GenAI agent that automates the manual investigation workflows from Labs 4 (Alert Triage), 11 Part B (ES|QL Investigation), and 13 (Cluster Diagnostics)

> In the earlier labs, you ran multi-step investigation workflows manually — querying Elasticsearch, interpreting results, and producing structured summaries. This lab automates that entire process using a Python-based GenAI agent that:
> 1. Accepts a natural-language question
> 2. Generates a query plan (via LLM)
> 3. Executes queries against Elasticsearch (read-only, with guardrails)
> 4. Detects query failures and data gaps before summarizing
> 5. Produces a structured investigation summary
> 6. Waits for human approval before recommending any action

### Part A: API Keys and Read-Only Access (Concept Overview)

> In production, the agent should only read data — never write. You enforce this with a **restricted API key** that grants only `monitor` cluster privilege and `read` + `view_index_metadata` index privileges.
>
> **In our lab environment**: Security is **OFF** on the 3-node cluster, so no API key is needed — the agent works without one. Leave `ES_API_KEY` empty.
>
> **Production reference** — when security IS enabled, you would create a restricted API key:
>
> ```json
> POST _security/api_key
> {
>   "name": "genai-agent-readonly",
>   "expiration": "8h",
>   "role_descriptors": {
>     "readonly_agent": {
>       "cluster": ["monitor"],
>       "indices": [{ "names": ["web-logs-*", "app-logs-*", "enriched-logs-*"], "privileges": ["read", "view_index_metadata"] }]
>     }
>   }
> }
> ```

### Part B: One-Command Setup

4. Set up the agent environment with the automation script

> The setup script creates `~/genai-agent/`, installs Python dependencies, copies the agent script, and writes the `.env` configuration — all in one command.

```bash
bash ~/GH/hands-on/module-06/genai-agent/setup-agent.sh http://<CLUSTER_NODE1_IP>:9200 <LLM_API_KEY>
```

> Replace `<CLUSTER_NODE1_IP>` with the cluster IP and `<LLM_API_KEY>` with the key from the instructor. If you omit the arguments, the script prompts for them.
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
ES_HOST=http://<CLUSTER_NODE1_IP>:9200
ES_API_KEY=
LLM_API_KEY=<paste your API key here>
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4o-mini
ENVFILE
python3 -c "import py_compile; py_compile.compile('elk_agent.py'); print('Syntax OK')"
```

</details>

> **What the script contains** (review the source at `~/GH/hands-on/module-06/genai-agent/elk_agent.py`):
> - `es_request()` — read-only Elasticsearch client with endpoint allowlist and blocked HTTP methods
> - `ask_llm()` — OpenAI-compatible LLM wrapper (works with GPT-4o-mini, Azure OpenAI, or local models)
> - `PLANNER_PROMPT` — system prompt that generates a JSON query plan from a natural-language question
> - `SUMMARIZER_PROMPT` — system prompt that produces a structured investigation summary
> - `_repair_json_array()` — robust JSON repair for malformed LLM output
> - `run_investigation()` — three-step pipeline: Plan → Execute → Summarize, with error/data-gap detection and a human approval gate
>
> For the full annotated source, see: [`genai-agent/elk_agent.py`](../genai-agent/elk_agent.py)

### Part C: Seed Data and Run the Agent

5. Seed sample data (if needed)

> The agent queries `web-logs-*`, `app-logs-*`, and `enriched-logs-*`. If `web-logs-*` or `app-logs-*` are empty or missing, run the seed script:

```bash
bash ~/GH/hands-on/module-06/genai-agent/seed-data.sh http://<CLUSTER_NODE1_IP>:9200
```

> This creates 12 `web-logs-*` documents and 10 `app-logs-*` documents via the `_bulk` API. The script is idempotent — it skips if data already exists. Expected result: `web-logs-*` → 12, `app-logs-*` → 10, `enriched-logs-*` → 28.
>
> **Alternative**: If you prefer Dev Tools, open [`genai-agent/seed-sample-data.md`](../genai-agent/seed-sample-data.md) and run the two `_bulk` requests manually.

6. Run the agent with the same question from Lab 4 (Alert Triage)

```bash
python3 elk_agent.py "An alert fired saying error count exceeded. Which service is failing, are users affected, and what should we do first?"
```

> **Expected output**: The agent generates a query plan (querying `app-logs-*` for error distribution, `web-logs-*` for HTTP 5xx correlation, `enriched-logs-*` for user impact, and `_cluster/health`), executes the queries, and produces a structured investigation summary. With all three indices seeded, the agent should identify `checkout-service` as the failing service with `ConnectionTimeoutError`, correlate it with 500/503 responses on `/api/checkout`, and produce a high-confidence summary.
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
│  │  • Read-only API key (when security is enabled)    │ │
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

10. Review the guardrails in the code

Open the script and identify the safety layers:

```bash
grep -n "BLOCKED\|ALLOWED\|Blocked\|approval\|query_errors\|data_gaps" elk_agent.py
```

> **Why guardrails matter**:
> - Without endpoint restrictions, the LLM might generate `DELETE /web-logs-*` or `PUT /_cluster/settings`
> - Without an API key restriction (in a secured cluster), the agent would have full cluster access
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
DELETE training-diag-test-<YOUR_INITIALS>
```

> If you seeded sample data in Lab 14 Step 5 and want to clean it up:
> ```json
> DELETE web-logs-2026.03.07
> DELETE app-logs-2026.03.07
> ```
> Only delete these if the data was created during this lab. If `web-logs-*` and `app-logs-*` were populated from Module 02, leave them intact.

> The `genai-agent/` folder in the course repository (`~/GH/hands-on/module-06/genai-agent/`) should be preserved — it is referenced by Module 07's capstone Lab 5.

That completes Labs 12–14. You've progressed from observability concepts and hands-on log correlation, through systematic cluster troubleshooting with real failure simulation, to building and running an automated GenAI investigation agent with production-grade guardrails.
