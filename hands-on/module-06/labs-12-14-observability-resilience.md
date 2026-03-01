# Module 06 - Labs 12-14

## Observability, Troubleshooting, and GenAI Agent Automation

---

## Lab 12: Observability Deep Dive

**Objective**: Explore distributed tracing concepts, logs-metrics-traces correlation, and observability tooling in Kibana

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

### Part 2: Exploring APM in Kibana

2. Navigate to Observability

```
Menu (☰) → Observability → Overview
```

> If you have Elastic Agent with APM integration enabled, this page shows service inventory, traces, and metrics. In our training environment, we may not have live APM data, but we can explore the UI.

3. Explore Service Map (if available)

```
Menu (☰) → Observability → APM → Service Map
```

> **Service Maps** auto-discover service dependencies from trace data. Each node is a service; edges show communication paths. Color indicates health.

> If no APM data exists, Kibana shows an empty map with setup instructions. This is expected in a training environment without instrumented applications.

4. Understand auto-instrumentation

> **Auto-instrumentation** adds tracing to an application **without code changes**. Elastic APM supports:
> - **Java**: `elastic-apm-agent.jar` attached at JVM startup
> - **Node.js**: `elastic-apm-node` imported at app start
> - **Python**: `elastic-apm` middleware
>
> The agent automatically creates spans for HTTP requests, database calls, and queue operations.

### Part 3: Correlating Logs, Metrics, and Traces

5. Check for correlated data in Discover

```
Menu (☰) → Analytics → Discover
```

> In a fully instrumented environment, log documents contain `trace.id` and `span.id` fields. You can filter: `trace.id : "abc123"` to see all logs from one user request across all services.

6. Review system metrics from Metricbeat

```
Menu (☰) → Analytics → Dashboard
Search: "[Metricbeat System] Host overview"
```

> This dashboard shows CPU, memory, disk, and network metrics. During an incident, correlating a CPU spike with error log timestamps helps identify resource-driven failures.

### Part 4: SLOs, SLAs, and AIOps Concepts

7. Understand SLO definitions

> | Term | Definition | Example |
> |------|-----------|---------|
> | **SLI** (Service Level Indicator) | A measured metric | 99.2% of requests return in < 200ms |
> | **SLO** (Service Level Objective) | The target | "99.5% of requests must return in < 200ms" |
> | **SLA** (Service Level Agreement) | The contract | "If SLO is violated, customer gets credit" |
> | **Error Budget** | Allowed failures | 0.5% of requests can fail before SLO breach |

8. Explore SLO features in Kibana (if available)

```
Menu (☰) → Observability → SLOs
```

> Kibana 8.x+ includes native SLO management. You define an SLI (e.g., percentage of requests with status < 500) and an SLO target (e.g., 99.5%). Kibana tracks the error budget over a rolling window.

9. AIOps and synthetic monitoring concepts

> **AIOps** applies machine learning to operations:
> - **Anomaly detection**: ML jobs in Kibana detect unusual patterns (e.g., sudden latency increase)
> - **Log rate analysis**: Identifies when log volume changes significantly
> - **Synthetic monitoring**: Simulated user journeys (e.g., "every 5 minutes, test the checkout flow") that detect issues before real users do
>
> In Kibana:
> ```
> Menu (☰) → Machine Learning → Anomaly Detection
> Menu (☰) → Observability → Synthetics
> ```

**Success**: You understand the three pillars of observability, can navigate APM/tracing UIs, and know how SLOs and AIOps fit into the monitoring strategy.

---

## Lab 13: Troubleshooting and Failure Handling

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

7. Rolling restart strategy (conceptual)

> When you need to upgrade or restart nodes:
>
> **Step 1**: Disable shard allocation (prevent shard movement during restart)
> ```json
> PUT _cluster/settings
> {
>   "persistent": {
>     "cluster.routing.allocation.enable": "primaries"
>   }
> }
> ```
>
> **Step 2**: Flush all indices (reduce replay time on restart)
> ```json
> POST _flush
> ```
>
> **Step 3**: Restart the node (via systemd)
> ```bash
> sudo systemctl restart elasticsearch
> ```
>
> **Step 4**: Wait for node to rejoin, then re-enable allocation
> ```json
> PUT _cluster/settings
> {
>   "persistent": {
>     "cluster.routing.allocation.enable": "all"
>   }
> }
> ```

8. Disaster recovery concepts

> | Strategy | RPO | RTO | Complexity |
> |----------|-----|-----|------------|
> | **Snapshots** (to S3/NFS) | Hours | Hours | Low |
> | **CCR** (Cross-Cluster Replication) | Seconds | Minutes | Medium |
> | **Multi-region active-active** | Near-zero | Near-zero | High |
>
> Create a snapshot repository and take a snapshot:

```json
PUT _snapshot/training-backup
{
  "type": "fs",
  "settings": {
    "location": "/tmp/es-snapshots"
  }
}
```

> **Note**: The `path.repo` setting must include `/tmp/es-snapshots` in `elasticsearch.yml` for this to work. If not configured, this will return an error — that's expected in the training environment.

### Part B: Advanced Troubleshooting – Cluster Health Diagnostics

**Objective**: Build a systematic diagnostic workflow for cluster health alerts.

### Troubleshooting workflow

1. Run the baseline health checks

```json
GET _cluster/health
GET _cat/nodes?v&h=name,node.role,heap.percent,cpu,load_1m,disk.used_percent
GET _cat/shards?v&h=index,shard,prirep,state,docs,store,node&s=state
```

2. Ask Elasticsearch why a shard is unassigned

```json
GET _cluster/allocation/explain
```

> This is the highest-value API for this lab. It tells you exactly why allocation is blocked.

3. Classify severity with a simple rule

```
If only replica shards are unassigned and primaries are started:
  -> Degraded redundancy, not immediate data-loss incident.

If any primary shard is unassigned:
  -> Critical incident (possible data unavailability/loss risk).
```

4. Validate whether this is expected in single-node training

```json
GET _cluster/health
GET _cat/shards/training-scaling-test?v
```

> In single-node labs, `number_of_replicas: 1` can keep cluster health yellow because replicas cannot be placed on the same node as primaries.

5. Apply the safe training remediation

```json
PUT training-scaling-test/_settings
{
  "number_of_replicas": 0
}
```

6. Re-check health after remediation

```json
GET _cluster/health
GET _cat/shards/training-scaling-test?v
```

### Troubleshooting summary template

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

### Ambiguity guardrails

> Do not claim "no risk" until you confirm primaries are assigned.

> Do not use shell pipes like `grep` inside Dev Tools requests. Keep API calls valid JSON/REST only.

> For training clusters, prefer index-level replica updates to broad wildcard updates.

**Success**: You can diagnose yellow/red cluster alerts deterministically and produce a safe, command-ready remediation path.

> **Coming up**: In Lab 14 (next section), you will build a GenAI agent that automates this same cluster diagnostic workflow. Keep your manual results — you will compare them against the agent's output.

---

## Lab 14: Automating Investigation Workflows with a GenAI Agent

**Objective**: Build a working GenAI agent that automates the three manual investigation workflows from Labs 4, 11, and 13

> In Labs 4, 11 (Part B), and 13 (Part B), you ran multi-step investigation workflows manually — querying Elasticsearch, interpreting results, and producing structured summaries. This lab automates that entire process using a Python-based GenAI agent that:
> 1. Accepts a natural-language question
> 2. Generates a query plan
> 3. Executes queries against Elasticsearch (read-only)
> 4. Produces a structured investigation summary
> 5. Waits for human approval before recommending any action

### Prerequisites

- Labs 4, 11 (Part B), and 13 (Part B) completed (you understand the manual workflows)
- Security enabled (Lab 7) — the agent uses an API key
- Python 3.9+ installed on the training VM
- An OpenAI-compatible API key (provided by the instructor)

### Part A: Create a Read-Only Elasticsearch API Key

> The agent must only read data — never write. We enforce this with an API key restricted to read-only operations.

1. Open Dev Tools

```
Menu (☰) → Management → Dev Tools
```

2. Create the restricted API key

```json
POST _security/api_key
{
  "name": "genai-agent-readonly",
  "expiration": "8h",
  "role_descriptors": {
    "readonly_agent": {
      "cluster": ["monitor"],
      "indices": [
        {
          "names": ["web-logs-*", "app-logs-*", "training-app-pipeline-*"],
          "privileges": ["read", "view_index_metadata"]
        }
      ]
    }
  }
}
```

3. Copy the API key from the response

> The response contains an `encoded` field — this is the Base64-encoded API key. Copy and save it. Example:

```json
{
  "id": "abc123...",
  "name": "genai-agent-readonly",
  "encoded": "YWJjMTIzOi0tLXNlY3JldC0tLQ==",
  "api_key": "---secret---"
}
```

> Save the `encoded` value. You will use it in the agent configuration.

### Part B: Install the Agent Dependencies

4. Set up the Python environment

```bash
cd ~
mkdir -p genai-agent && cd genai-agent
python3 -m venv .venv
source .venv/bin/activate
pip install openai requests
```

### Part C: Create the Agent Script

5. Create the agent script

```bash
cat <<'AGENT' > elk_agent.py
"""
ELK Investigation Agent
Accepts a natural-language question, generates Elasticsearch queries,
executes them read-only, and produces a structured summary.
"""
import json
import os
import sys
import requests

# --- Configuration ---
ES_HOST = os.environ.get("ES_HOST", "http://127.0.0.1:9200")
ES_API_KEY = os.environ.get("ES_API_KEY", "")

# OpenAI-compatible endpoint (works with OpenAI, Azure OpenAI, or local models)
LLM_API_KEY = os.environ.get("LLM_API_KEY", "")
LLM_BASE_URL = os.environ.get("LLM_BASE_URL", "https://api.openai.com/v1")
LLM_MODEL = os.environ.get("LLM_MODEL", "gpt-4o-mini")

# --- Guardrails ---
ALLOWED_ES_ENDPOINTS = [
    "_search", "_count", "_query", "_cluster/health",
    "_cat/nodes", "_cat/shards", "_cat/indices",
    "_cat/allocation", "_cluster/allocation/explain",
    "_cluster/stats", "_nodes/stats"
]

BLOCKED_METHODS = ["PUT", "DELETE", "PATCH"]

def es_request(method, path, body=None):
    """Execute a read-only Elasticsearch request with guardrails."""
    method = method.upper()

    if method in BLOCKED_METHODS:
        return {"error": f"Blocked: {method} is not allowed (read-only agent)"}

    endpoint = path.lstrip("/").split("?")[0]
    # Check if the endpoint matches any allowed pattern
    index_part = endpoint.split("/")[0] if "/" in endpoint else ""
    api_part = "/".join(endpoint.split("/")[1:]) if "/" in endpoint else endpoint

    allowed = any(api_part.startswith(ep.lstrip("/")) or endpoint.startswith(ep.lstrip("/"))
                  for ep in ALLOWED_ES_ENDPOINTS)
    if not allowed:
        return {"error": f"Blocked: endpoint '{path}' is not in the allowed list"}

    headers = {"Content-Type": "application/json"}
    if ES_API_KEY:
        headers["Authorization"] = f"ApiKey {ES_API_KEY}"

    url = f"{ES_HOST}/{path}"
    try:
        if method == "GET" and body:
            resp = requests.get(url, headers=headers, json=body, timeout=30)
        elif method == "POST" and body:
            resp = requests.post(url, headers=headers, json=body, timeout=30)
        else:
            resp = requests.get(url, headers=headers, timeout=30)
        return resp.json()
    except Exception as e:
        return {"error": str(e)}


def ask_llm(system_prompt, user_message):
    """Send a prompt to the LLM and return the response text."""
    try:
        from openai import OpenAI
        client = OpenAI(api_key=LLM_API_KEY, base_url=LLM_BASE_URL)
        response = client.chat.completions.create(
            model=LLM_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message}
            ],
            temperature=0.2
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"LLM Error: {e}"


# --- System Prompts ---
PLANNER_PROMPT = """You are an Elasticsearch investigation planner.
Given a natural-language question, generate a JSON array of Elasticsearch queries to answer it.

Rules:
- Only use read-only operations: GET with _search, _count, _query, _cluster/health, _cat/*.
- Available indices: web-logs-*, app-logs-*, training-app-pipeline-*.
- Available fields in web-logs-*: @timestamp, client_ip, method, path, status (integer), bytes (integer).
- Available fields in app-logs-*/training-app-pipeline-*: @timestamp, level, service, message, user_id, order_id, amount, error, session_id, product_id, quantity.
- Return ONLY valid JSON. No markdown, no explanation.

Output format:
[
  {"step": 1, "description": "...", "method": "GET", "path": "web-logs-*/_search", "body": {...}},
  {"step": 2, "description": "...", "method": "GET", "path": "app-logs-*/_search", "body": {...}}
]
"""

SUMMARIZER_PROMPT = """You are an incident investigation summarizer.
Given the original question and query results, produce a structured summary.

Output format:
## Investigation Summary
**Question**: <original question>
**Findings**:
1. <finding from query 1>
2. <finding from query 2>
...
**Impact Assessment**: <scope and severity>
**Likely Root Cause**: <based on evidence>
**Recommended Next Step**: <specific action — but state that human approval is required>
**Confidence**: <high/medium/low with explanation>
"""


def run_investigation(question):
    """Run the full investigation pipeline."""
    print(f"\n{'='*60}")
    print(f"QUESTION: {question}")
    print(f"{'='*60}")

    # Step 1: Generate query plan
    print("\n[Step 1] Generating query plan...")
    plan_text = ask_llm(PLANNER_PROMPT, question)
    print(f"Query plan:\n{plan_text}")

    try:
        query_plan = json.loads(plan_text)
    except json.JSONDecodeError:
        # Try to extract JSON from markdown code blocks
        import re
        json_match = re.search(r'\[.*\]', plan_text, re.DOTALL)
        if json_match:
            query_plan = json.loads(json_match.group())
        else:
            print("ERROR: Could not parse query plan as JSON")
            return

    # Step 2: Execute queries (read-only)
    print(f"\n[Step 2] Executing {len(query_plan)} queries (read-only)...")
    results = []
    for step in query_plan:
        desc = step.get("description", f"Step {step.get('step', '?')}")
        method = step.get("method", "GET")
        path = step.get("path", "")
        body = step.get("body")

        print(f"  Running: {desc}")
        print(f"    {method} {path}")

        result = es_request(method, path, body)

        # Trim large results for the LLM context
        result_str = json.dumps(result, indent=2)
        if len(result_str) > 3000:
            result_str = result_str[:3000] + "\n... (truncated)"

        results.append({
            "step": step.get("step"),
            "description": desc,
            "result": result_str
        })

    # Step 3: Summarize findings
    print(f"\n[Step 3] Generating investigation summary...")
    context = f"Original question: {question}\n\nQuery results:\n"
    for r in results:
        context += f"\n--- Step {r['step']}: {r['description']} ---\n{r['result']}\n"

    summary = ask_llm(SUMMARIZER_PROMPT, context)
    print(f"\n{'='*60}")
    print("INVESTIGATION SUMMARY")
    print(f"{'='*60}")
    print(summary)

    # Step 4: Human approval gate
    print(f"\n{'='*60}")
    print("HUMAN APPROVAL REQUIRED")
    print("Review the summary above. The agent will NOT take any")
    print("action without your explicit confirmation.")
    print(f"{'='*60}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        question = " ".join(sys.argv[1:])
    else:
        question = input("Enter your investigation question: ")
    run_investigation(question)
AGENT
```

### Part D: Configure and Run the Agent

6. Set environment variables

```bash
export ES_HOST="http://127.0.0.1:9200"
export ES_API_KEY="<paste the encoded API key from step 3>"
export LLM_API_KEY="<API key provided by instructor>"
export LLM_MODEL="gpt-4o-mini"
```

> **If no LLM API key is available**: The instructor will demonstrate this step live. You can still review the script to understand the architecture.

7. Run the agent with the same question from Lab 4 (Alert Triage)

```bash
python elk_agent.py "An alert fired saying error count exceeded. Which service is failing, are users affected, and what should we do first?"
```

> **Expected output**: The agent generates a query plan (same pattern as Lab 4), executes the queries, and produces a structured summary. Compare the output with your manual Lab 4 results:
>
> | Step | Lab 4 (Manual) | Lab 14 (Automated) |
> |------|---------------|-------------------|
> | Error distribution by service | You typed the query | Agent generated it |
> | HTTP 5xx correlation | You typed the query | Agent generated it |
> | Cluster health check | You typed the query | Agent generated it |
> | Impact assessment | You typed the query | Agent generated it |
> | Summary | You filled in the template | Agent produced it automatically |

8. Run the agent with the same question from Lab 11 Part B (ES|QL Investigation)

```bash
python elk_agent.py "Which services are producing the most errors and which endpoints are affected?"
```

> Compare the agent's output with your manual Lab 11 Part B results. The agent should follow a similar multi-step pattern: error concentration → endpoint correlation → evidence → impact scope.

9. Run the agent with the same question from Lab 13 Part B (Cluster Diagnostics)

```bash
python elk_agent.py "The cluster health alert is yellow. What is the root cause and what is the safe fix?"
```

> The agent should query `_cluster/health`, `_cat/shards`, and `_cluster/allocation/explain` — the same APIs you used manually in Lab 13 Part B.

### Part E: Understanding the Agent Architecture

10. Review the three-layer design

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
│  │  • Read-only API key (no write access)            │ │
│  │  • Endpoint allowlist (only _search, _cat, etc.)  │ │
│  │  • Blocked HTTP methods (PUT, DELETE, PATCH)      │ │
│  │  • Human approval gate (no auto-remediation)      │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │              HUMAN APPROVAL GATE                  │ │
│  │  Agent recommends → Human reviews → Human acts    │ │
│  └──────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

11. Review the guardrails in the code

Open the script and identify the four safety layers:

```bash
grep -n "BLOCKED\|ALLOWED\|Blocked\|approval" elk_agent.py
```

> **Why guardrails matter**:
> - Without endpoint restrictions, the LLM might generate `DELETE /web-logs-*` or `PUT /_cluster/settings`
> - Without the API key restriction, the agent has full cluster access
> - Without human approval, a wrong recommendation executes automatically
> - These are not optional — they are mandatory in any production GenAI + Elasticsearch integration

### How Labs 4, 11, and 13 connect to this lab

| Manual Lab | What you learned | What the agent automates |
|-----------|-----------------|------------------------|
| **Lab 4** (Alert Triage) | 4-query investigation chain: errors → HTTP correlation → cluster health → impact | Planner generates the same 4 queries from a natural-language alert description |
| **Lab 11 Part B** (ES\|QL Investigation) | 5-step ES\|QL investigation: error concentration → endpoints → evidence → scope → summary | Planner generates equivalent ES\|QL or Query DSL from a vague incident question |
| **Lab 13 Part B** (Cluster Diagnostics) | 6-step cluster diagnostic: health → shards → allocation explain → classify → fix → verify | Planner generates cluster API queries from a health alert trigger |

> The manual labs teach the investigation **logic**. This lab wraps that same logic in an automated pipeline. If you cannot produce the manual summary, the agent's output will not make sense to you either.

**Success**: You can deploy a read-only GenAI investigation agent, understand its three-layer architecture, verify its output against manual workflows, and explain why human approval is mandatory.
