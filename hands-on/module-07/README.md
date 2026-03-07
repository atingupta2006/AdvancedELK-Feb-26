# Module 07 – Capstone Project & Final Assessment (Labs)

> **Stack Version**: Elasticsearch 9.x | Kibana 9.x | Logstash 9.x | Beats 9.x
> **Prereq**: Modules 01–06 completed. Labs 1, 2, 4, and 5 work with or without security. Lab 3 (alerting & RBAC) requires security enabled — see Module 06, Lab 7 in [labs-05-08-scale-security.md](../module-06/labs-05-08-scale-security.md).
> **ES Host**: All commands use `http://192.168.56.101:9200`. Elasticsearch is bound to this address, **not** `127.0.0.1`.
> **Data files**: Training data is at `/opt/elk-training/data/raw/` on the VM.

> This capstone ties together everything covered in Modules 01–06: ingestion pipelines, querying, visualization, performance tuning, and security. You will build a complete observability platform for an e-commerce application.

---

## Lab 1: End-to-End Data Ingestion Pipeline

**Estimated Time**: 20–30 minutes

**Objective**: Build a complete ingestion pipeline for e-commerce platform logs

> In production, data arrives from multiple sources simultaneously — web servers, application services, and system metrics. This lab creates a unified ingestion architecture using Logstash (for parsing) and Beats (for collection), feeding into template-backed indices.

1. Create project directory structure

```bash
mkdir -p ~/capstone/{configs,data}
cd ~/capstone
```

2. Prepare data sources

> We reuse the training dataset from `data/raw/` — web server logs (Apache format) and application logs (JSON format). These simulate a real e-commerce platform.

```bash
sudo mkdir -p /opt/capstone/data
sudo cp /opt/elk-training/data/raw/access.log /opt/capstone/data/
sudo cp /opt/elk-training/data/raw/app.log /opt/capstone/data/
```

3. Create index templates for all data sources

> Templates ensure consistent field types across all time-based indices. Component templates hold shared fields; index templates compose them with source-specific fields.

```
Menu (☰) → Management → Dev Tools
```

```json
PUT _component_template/capstone-common
{
  "template": {
    "settings": { "number_of_shards": 1, "number_of_replicas": 1 },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "source_type": { "type": "keyword" },
        "host": {
          "properties": {
            "name": { "type": "keyword" }
          }
        }
      }
    }
  }
}
```

```json
PUT _index_template/capstone-web
{
  "index_patterns": ["capstone-web-*"],
  "priority": 500,
  "composed_of": ["capstone-common"],
  "template": {
    "mappings": {
      "properties": {
        "client_ip": { "type": "ip" },
        "method": { "type": "keyword" },
        "path": { "type": "keyword" },
        "status": { "type": "integer" },
        "bytes": { "type": "integer" }
      }
    }
  }
}
```

```json
PUT _index_template/capstone-app
{
  "index_patterns": ["capstone-app-*"],
  "priority": 500,
  "composed_of": ["capstone-common"],
  "template": {
    "mappings": {
      "properties": {
        "level": { "type": "keyword" },
        "service": { "type": "keyword" },
        "message": {
          "type": "text",
          "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
        },
        "user_id": { "type": "keyword" },
        "order_id": { "type": "keyword" },
        "amount": { "type": "double" }
      }
    }
  }
}
```

Verify templates were created correctly:

```json
GET _component_template/capstone-common
GET _index_template/capstone-web
GET _index_template/capstone-app
```

> All three should return `200` with the mappings you defined above. If a template is missing, re-run the corresponding PUT command.

4. Create Logstash multi-pipeline config

> The web pipeline uses grok to extract structured fields from Apache log format. The `mutate` adds a `source_type` tag for cross-source dashboards.

> **Note**: If security is enabled, add `user => "elastic"` and `password => "Training123!"` (or your password from Module 06 Lab 7) to the output section. If security is disabled, those lines are not needed.

Create the web pipeline config:

```bash
cat > ~/capstone/configs/pipeline-web.conf << 'WEBCONF'
input {
  file {
    path => "/opt/capstone/data/access.log"
    start_position => "beginning"
    sincedb_path => "/dev/null"
  }
}

filter {
  grok {
    match => { "message" => '%{IPORHOST:client_ip} %{USER:ident} %{USER:auth} \[%{HTTPDATE:timestamp}\] "(?:%{WORD:method} %{NOTSPACE:path}(?: HTTP/%{NUMBER:http_version})?|%{DATA:raw_request})" %{NUMBER:status:int} (?:%{NUMBER:bytes:int}|-)' }
  }
  date { match => ["timestamp", "dd/MMM/yyyy:HH:mm:ss Z"] target => "@timestamp" }
  mutate {
    add_field => { "source_type" => "web" }
    remove_field => ["message", "timestamp", "ident", "auth"]
  }
}

output {
  elasticsearch {
    hosts => ["http://192.168.56.101:9200"]
    index => "capstone-web-%{+YYYY.MM.dd}"
  }
}
WEBCONF
```

Create the app pipeline config:

```bash
cat > ~/capstone/configs/pipeline-app.conf << 'APPCONF'
input {
  file {
    path => "/opt/capstone/data/app.log"
    start_position => "beginning"
    sincedb_path => "/dev/null"
    codec => json
  }
}

filter {
  date { match => ["timestamp", "ISO8601"] target => "@timestamp" }
  if [level] == "ERROR" { mutate { add_tag => ["error_event"] } }
  mutate {
    add_field => { "source_type" => "app" }
    remove_field => ["timestamp"]
  }
}

output {
  elasticsearch {
    hosts => ["http://192.168.56.101:9200"]
    index => "capstone-app-%{+YYYY.MM.dd}"
  }
}
APPCONF
```

5. Configure pipelines.yml

```bash
cat > ~/capstone/configs/pipelines.yml << 'PYML'
- pipeline.id: capstone-web
  path.config: "/etc/logstash/conf.d/capstone-web.conf"
  queue.type: persisted
  pipeline.workers: 2

- pipeline.id: capstone-app
  path.config: "/etc/logstash/conf.d/capstone-app.conf"
  queue.type: persisted
  pipeline.workers: 2
PYML
```

6. Deploy and start pipelines

> This replaces the existing `pipelines.yml`, which points the default pipeline at `/etc/logstash/conf.d/*.conf`. Back it up first so you can restore it later if needed.

```bash
sudo cp /etc/logstash/pipelines.yml /etc/logstash/pipelines.yml.bak
sudo cp ~/capstone/configs/pipeline-web.conf /etc/logstash/conf.d/capstone-web.conf
sudo cp ~/capstone/configs/pipeline-app.conf /etc/logstash/conf.d/capstone-app.conf
sudo cp ~/capstone/configs/pipelines.yml /etc/logstash/pipelines.yml
sudo systemctl restart logstash
```

Verify Logstash is running:

```bash
sudo systemctl status logstash --no-pager
```

> You should see `Active: active (running)`. If it fails, check the log at `/var/log/logstash/logstash-plain.log` for configuration errors.

7. Configure Beats for system metrics (optional)

> If Metricbeat is installed on your VM, enable system metrics. If not, skip this step — the remaining labs do not depend on metricbeat data.

```bash
# Check if metricbeat is installed first:
rpm -q metricbeat || echo "Metricbeat not installed — skip this step"

# If installed:
sudo metricbeat modules enable system
sudo systemctl restart metricbeat
```

8. Kibana: Create data views and verify

```
Menu (☰) → Management → Stack Management → Data Views → Create data view

Data view 1:
  Name: capstone-web-*
  Index pattern: capstone-web-*
  Timestamp: @timestamp
  Save

Data view 2:
  Name: capstone-app-*
  Index pattern: capstone-app-*
  Timestamp: @timestamp
  Save

Menu (☰) → Analytics → Discover
Data view: capstone-web-*
Data view: capstone-app-*
```

9. Verify document counts in Dev Tools

```json
GET capstone-web-*/_count
GET capstone-app-*/_count
```

All data sources should now be ingested with correct mappings and visible in Discover. If the count is 0, wait 15–20 seconds for Logstash to finish starting and re-run the count.

---

## Lab 2: Advanced Dashboards and Analytics

**Estimated Time**: 25–35 minutes

**Objective**: Create comprehensive monitoring dashboards for the e-commerce platform

> This lab builds three dashboards: an executive overview (KPIs), an operations dashboard (real-time monitoring), and an analytics dashboard (trends and patterns). Each demonstrates different Kibana visualization techniques.

1. Create executive KPI visualizations

```
Menu (☰) → Analytics → Visualize Library
```

> **Metric** visualizations are ideal for KPIs — single numbers that convey status at a glance.

```
Create visualization → Metric
Data view: capstone-web-*
Metric: Count
Title: Total Web Requests
Save as: capstone_total_requests
```

```
Create visualization → Metric
Data view: capstone-app-*
Filter: level : "ERROR"
Metric: Count
Title: Application Errors
Save as: capstone_app_errors
```

```
Create visualization → Lens
Data view: capstone-app-*
Metric: Formula
Formula: count(kql='level : "ERROR"') / count()
Format: Percent
Title: Error Rate
Save as: capstone_error_rate
```

2. Create operational visualizations

> Time-series charts show trends and make anomalies visible. Combining total traffic with errors on one chart helps correlate issues.

```
Create visualization → Line
Data view: capstone-web-*
Metric: Count
X-axis: Date histogram → @timestamp
Title: Web Traffic Over Time
Save as: capstone_web_traffic

Create visualization → Bar
Data view: capstone-web-*
Filter: status >= 500
Metric: Count
X-axis: Terms → path → Size 10
Title: 5xx Errors by Path
Save as: capstone_5xx_by_path

Create visualization → Pie
Data view: capstone-web-*
Metric: Count
Slice by: Terms → status → Size 6
Title: HTTP Status Distribution
Save as: capstone_status_dist
```

3. Create analytics visualizations

```
Create visualization → Data Table
Data view: capstone-web-*
Split rows: Terms → path → Size 15
Metrics: Count, Average → bytes
Title: Request Analysis by Path
Save as: capstone_path_analysis

Create visualization → Heat map
Data view: capstone-web-*
X-axis: Date histogram → @timestamp → 10m
Y-axis: Terms → method → Size 5
Metric: Count
Title: Request Method Density
Save as: capstone_method_heatmap
```

4. Build Executive Dashboard

```
Menu (☰) → Analytics → Dashboard → Create dashboard

Add from library:
  capstone_total_requests
  capstone_app_errors
  capstone_error_rate
  capstone_web_traffic
  capstone_status_dist

Arrange: KPIs on top row, charts below
Save as: Capstone - Executive Overview
```

5. Build Operations Dashboard

```
Menu (☰) → Analytics → Dashboard → Create dashboard

Add from library:
  capstone_web_traffic
  capstone_5xx_by_path
  capstone_status_dist
  capstone_app_errors

Add Controls:
  Options list → method → Title: HTTP Method
  Range slider → status → Title: Status Code

Refresh: every 30 seconds
Save as: Capstone - Operations
```

6. Build Analytics Dashboard

```
Menu (☰) → Analytics → Dashboard → Create dashboard

Add from library:
  capstone_path_analysis
  capstone_method_heatmap
  capstone_error_rate

Save as: Capstone - Analytics
```

7. Add drilldown to Operations Dashboard

> Drilldowns let users click a chart to investigate further — opens Discover pre-filtered to the clicked data point.

```
Open: Capstone - Operations → Edit
Panel: capstone_web_traffic → Panel menu → Create drilldown
Type: Open in Discover
Save
```

That covers the dashboard layer — three views covering executive, operational, and analytics use cases.

---

## Lab 3: Alerting and Security Controls

**Estimated Time**: 20–25 minutes

**Objective**: Set up alerting for production scenarios and verify RBAC controls

> **Prerequisite**: This lab requires `xpack.security.enabled: true`. If security is disabled on your VM, enable it first — see Module 06, Lab 7 in [labs-05-08-scale-security.md](../module-06/labs-05-08-scale-security.md). Steps 1–5 (alerting) may work without security, but steps 6–8 (RBAC) require it.

> Production observability requires automated alerting. This lab creates threshold-based rules for error rates and combines them with the RBAC setup from Module 06 Lab 7 to ensure proper access control.

1. Create connectors for alert actions

```
Menu (☰) → Management → Stack Management → Connectors → Create connector

Connector 1:
  Type: Server log
  Name: Capstone - Server Log
  Save
```

2. Create error rate alert

> This rule checks every minute whether the error count in the last hour exceeds the threshold. When triggered, it logs a message via the Server log connector.

```
Menu (☰) → Management → Stack Management → Rules → Create rule

Rule type: Index threshold
Name: Capstone - High Error Rate

Indices: capstone-app-*
Time field: @timestamp

WHEN: count
OVER: all documents
IS ABOVE: 5
FOR THE LAST: 1 hour
KQL: level : "ERROR"

Check every: 1 minute
```

3. Add action to the rule

```
Actions → Add action
Connector: Capstone - Server Log
Action frequency: On each check interval
Message: High error rate detected: {{context.message}}
Save
```

4. Create 5xx alert for web logs

```
Menu (☰) → Management → Stack Management → Rules → Create rule

Rule type: Index threshold
Name: Capstone - 5xx Errors

Indices: capstone-web-*
Time field: @timestamp

WHEN: count
OVER: all documents
IS ABOVE: 3
FOR THE LAST: 30 minutes
KQL: status >= 500

Check every: 1 minute

Actions → Add action
Connector: Capstone - Server Log
Message: 5xx errors above threshold: {{context.message}}
Save
```

5. Verify alerts are firing

```
Menu (☰) → Management → Stack Management → Rules
Check: both rules show "Active" status with triggered alerts
```

6. Create capstone-specific roles

> These roles demonstrate field-level access control — the viewer can see web traffic data but not application-internal fields.

```
Menu (☰) → Management → Stack Management → Security → Roles → Create role

Role: capstone-viewer
  Cluster privileges: monitor
  Index privileges:
    Indices: capstone-web-*
    Privileges: read, view_index_metadata
  Kibana privileges:
    Space: Default
    Feature: Discover (Read), Dashboard (Read)
  Save

Role: capstone-analyst
  Cluster privileges: monitor
  Index privileges:
    Indices: capstone-web-*, capstone-app-*
    Privileges: read, view_index_metadata
  Kibana privileges:
    Space: Default
    Feature: Discover (All), Dashboard (All), Visualize Library (All)
  Save
```

7. Create capstone users

```
Menu (☰) → Management → Stack Management → Security → Users → Create user

User: capstone-viewer01
  Password: CapView123!
  Roles: capstone-viewer
  Save

User: capstone-analyst01
  Password: CapAnalyst123!
  Roles: capstone-analyst
  Save
```

8. Test access control

```
New incognito window → http://192.168.56.101:5601

Test capstone-viewer01:
  - Can view Capstone - Executive Overview dashboard ✓
  - Cannot access capstone-app-* data ✓
  - Cannot edit dashboards ✓

Test capstone-analyst01:
  - Can view all capstone dashboards ✓
  - Can access both web and app data ✓
  - Can create new visualizations ✓
```

That completes the alerting and access control layer for the capstone.

---

## Lab 4: Performance Tuning and Review

**Estimated Time**: 20–25 minutes

**Objective**: Optimize the capstone system and review the complete architecture

> This final lab focuses on production readiness: ensuring queries are fast, indices are sized correctly, and ILM (Index Lifecycle Management) handles data retention automatically.

1. Review index sizes and health

```
Menu (☰) → Management → Dev Tools
```

```json
GET _cat/indices/capstone-*?v&h=index,health,docs.count,store.size&s=index
```

2. Check shard allocation balance

```json
GET _cat/shards/capstone-*?v&h=index,shard,prirep,state,docs,store,node&s=index
```

3. Profile a complex query

> Use profiling to identify the most expensive query clause. In production, this helps decide which fields need optimization (e.g., adding `.keyword` sub-field).

```json
GET capstone-web-*/_search
{
  "profile": true,
  "query": {
    "bool": {
      "must": [
        { "prefix": { "path": "/api" } }
      ],
      "filter": [
        { "range": { "status": { "gte": 400 } } },
        { "range": { "@timestamp": { "gte": "now-24h" } } }
      ]
    }
  },
  "size": 0,
  "aggs": {
    "errors_by_path": {
      "terms": { "field": "path", "size": 10 }
    }
  }
}
```

4. Optimize refresh interval for write-heavy indices

```json
PUT capstone-web-*/_settings
{
  "refresh_interval": "5s"
}
```

> Increasing from 1s to 5s reduces refresh frequency by 80%, which can significantly lower I/O load with minimal impact on search freshness for monitoring use cases.

5. Create an ILM policy

> **Index Lifecycle Management** (ILM) automates index transitions through phases. This ensures old data is managed without manual intervention.

> Since our Logstash output creates date-stamped indices (not data streams), we skip the `rollover` action and use time-based phase transitions instead.

```json
PUT _ilm/policy/capstone-lifecycle
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {}
      },
      "warm": {
        "min_age": "30d",
        "actions": {
          "forcemerge": { "max_num_segments": 1 }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

> This policy keeps data **hot** (active indexing), moves to **warm** after 30 days (force-merges segments for faster searches and smaller storage), and **deletes** after 90 days.

6. Apply ILM policy to index template

```json
PUT _index_template/capstone-web
{
  "index_patterns": ["capstone-web-*"],
  "priority": 500,
  "composed_of": ["capstone-common"],
  "template": {
    "settings": {
      "index.lifecycle.name": "capstone-lifecycle"
    },
    "mappings": {
      "properties": {
        "client_ip": { "type": "ip" },
        "method": { "type": "keyword" },
        "path": { "type": "keyword" },
        "status": { "type": "integer" },
        "bytes": { "type": "integer" }
      }
    }
  }
}
```

Apply the same ILM policy to the app template:

```json
PUT _index_template/capstone-app
{
  "index_patterns": ["capstone-app-*"],
  "priority": 500,
  "composed_of": ["capstone-common"],
  "template": {
    "settings": {
      "index.lifecycle.name": "capstone-lifecycle"
    },
    "mappings": {
      "properties": {
        "level": { "type": "keyword" },
        "service": { "type": "keyword" },
        "message": {
          "type": "text",
          "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
        },
        "user_id": { "type": "keyword" },
        "order_id": { "type": "keyword" },
        "amount": { "type": "double" }
      }
    }
  }
}
```

7. Verify ILM policy in Kibana

```
Menu (☰) → Management → Stack Management → Index Lifecycle Policies
Open: capstone-lifecycle
Review: phase transitions and actions
```

Verify the policy is applied to existing indices:

```json
GET capstone-web-*/_settings/index.lifecycle.name
```

> Each index should display `"index.lifecycle.name": "capstone-lifecycle"`. Existing indices created before the template update need a manual policy assignment — newly created indices pick it up automatically.

8. Force merge completed indices

> Only force merge indices that are no longer being written to. This reduces segment count and improves search speed. In production, you would exclude the current (active write) index from the wildcard. For this training exercise with static data, applying to all capstone indices is acceptable.

```json
POST capstone-web-*/_forcemerge?max_num_segments=1
```

Verify segment count after merge:

```json
GET _cat/segments/capstone-web-*?v&h=index,shard,segment,docs.count
```

> Each shard should show only one segment after the force merge completes.

9. Review ES|QL analytics on capstone data

```
Menu (☰) → Analytics → Discover → Switch to ES|QL
```

```
FROM capstone-web-*
| EVAL is_error = CASE(status >= 500, 1, null)
| STATS total = COUNT(*), errors = COUNT(is_error) BY method
| EVAL error_pct = CASE(total > 0, ROUND(errors * 100.0 / total, 2), 0.0)
| SORT total DESC
```

```
FROM capstone-app-*
| WHERE level == "ERROR"
| STATS error_count = COUNT(*) BY service
| SORT error_count DESC
```

10. Architecture summary review

> At this point, the complete architecture includes:
> - **Ingestion**: Logstash multi-pipeline (web + app) + Metricbeat *(if installed)*
> - **Storage**: Template-backed indices with ILM lifecycle policies
> - **Querying**: KQL in Discover, Query DSL in Dev Tools, ES|QL for analytics
> - **Visualization**: Three dashboards (Executive, Operations, Analytics)
> - **Alerting**: Threshold rules on error rates with server log actions
> - **Security** *(if enabled)*: RBAC with viewer/analyst roles

```json
GET _cluster/health
GET _cat/indices/capstone-*?v&h=index,health,docs.count,store.size
GET _cat/nodes?v&h=name,node.role,heap.percent,cpu
```

The system is now tuned, ILM is in place, and the architecture is ready for the failure simulation in Lab 5.

---

## Lab 5: Failure Simulation and Agentic AI Demonstration

**Estimated Time**: 25–35 minutes

**Objective**: Simulate a pipeline failure, recover, and demonstrate one Agentic AI use case

> Real production ELK clusters face failures — pipeline crashes, network partitions, resource exhaustion. This lab tests your ability to detect, diagnose, and recover from a failure, then explores how AI agents can enhance operational workflows.

---

### Part A: Failure Simulation and Recovery

1. Check current data flow baseline

> Before introducing a failure, capture current state so you can compare after recovery.

```
Menu (☰) → Analytics → Discover → capstone-web-*
```

Note the most recent document timestamp and total document count.

```json
GET capstone-web-*/_count
```

2. Simulate a Logstash pipeline failure

> Stopping Logstash simulates a pipeline crash. Any new log lines written to access.log during the outage will queue on disk until Logstash resumes — Filebeat handles retry automatically, but Logstash reading directly from file will resume from its sincedb position.

```bash
sudo systemctl stop logstash
```

Verify Logstash is stopped:

```bash
sudo systemctl status logstash
```

3. Observe the data gap in Kibana

```
Menu (☰) → Analytics → Discover → capstone-web-*
```

> Set the time picker to the last 15 minutes. You should see no new documents arriving after Logstash was stopped. This is the "data gap" — a common indicator of pipeline failure in production.

4. Diagnose the issue using cluster health

```json
GET _cluster/health
GET _cat/indices/capstone-*?v&h=index,health,docs.count,store.size
```

```bash
sudo systemctl status logstash
sudo journalctl -u logstash --no-pager -n 20
```

> In production, you would also check Logstash dead letter queues, JVM heap, and pipeline metrics. Here the issue is straightforward — the service is stopped.

5. Recover the pipeline

```bash
sudo systemctl start logstash
```

Wait 30 seconds for Logstash to initialize, then verify:

```bash
sudo systemctl status logstash
sudo journalctl -u logstash --no-pager -n 10
```

6. Verify data integrity after recovery

```json
GET capstone-web-*/_count
```

```
Menu (☰) → Analytics → Discover → capstone-web-*
```

> **Important**: Because the Lab 1 pipeline configs use `sincedb_path => "/dev/null"`, Logstash does not remember its file read position across restarts. On recovery, it re-reads the entire log file from the beginning, so you will see the document count roughly **double**. This is expected training behavior — in production, you would use a persistent sincedb path so Logstash resumes from where it left off, preventing duplicates.
>
> To observe the duplication, compare the count against the baseline from step 1. In a real environment, you would check for missing events using timestamp gap analysis.

Check for any pipeline processing errors on the Logstash side:

```bash
sudo ls -la /var/lib/logstash/dead_letter_queue/
```

> Dead letter queues are stored on the **Logstash filesystem**, not as Elasticsearch indices. An empty directory (or one containing only empty pipeline folders) means no documents failed processing — clean recovery.

---

### Part B: Agentic AI Demonstration

> **Agentic AI** refers to AI agents that can autonomously investigate, analyze, and explain operational events. In the ELK context, this means AI that can read logs, correlate events, and produce human-readable summaries — reducing mean time to resolution.

> **Already built an agent?** If you completed Module 06 Labs 12–14 ([labs-12-14-observability-resilience.md](../module-06/labs-12-14-observability-resilience.md)), you already have a working read-only investigation agent in `module-06/genai-agent/`. You can reuse it here by pointing it at the capstone indices — update the `PLANNER_PROMPT` index patterns from `web-logs-*` / `app-logs-*` to `capstone-web-*` / `capstone-app-*`.

Choose **one** of the following options to demonstrate:

---

#### Option A: Agent-Assisted ES|QL Investigation

> This option demonstrates how an AI agent could use ES|QL to investigate anomalies. You'll run the queries manually, then document how an agent would automate the workflow.

7a. Run an ES|QL investigation query

```
Menu (☰) → Analytics → Discover → Switch to ES|QL
```

```
FROM capstone-web-*
| WHERE status >= 400
| STATS error_count = COUNT(*), paths = COUNT_DISTINCT(path) BY status
| SORT error_count DESC
```

```
FROM capstone-web-*
| STATS avg_bytes = AVG(bytes), p95_bytes = PERCENTILE(bytes, 95) BY method
| SORT avg_bytes DESC
```

```
FROM capstone-app-*
| WHERE level == "ERROR"
| STATS count = COUNT(*) BY service, message
| SORT count DESC
```

> These three queries represent an investigation workflow: (1) identify error patterns, (2) check for anomalous traffic volumes, (3) correlate application errors. An AI agent would chain these queries automatically, analyze the results, and produce a summary like: "High 404 rate detected on /api/checkout (23 errors in 1 hour), correlated with auth-service ERROR spike — likely a deployment issue."

---

#### Option B: Agent-Generated Alert Explanation

> This option demonstrates how an AI agent could generate human-readable explanations of triggered alerts, making them actionable for on-call engineers.

7b. Review an existing alert (from Lab 3)

```
Menu (☰) → Management → Stack Management → Rules → (select the error rate alert from Lab 3)
```

> Look at the alert history. Each triggered alert contains raw data — threshold values, timestamps, index names. An AI agent would take this raw alert data and generate a narrative explanation.

Document how an agent would transform this alert data:

**Raw alert data** (example — use the actual values from your Lab 3 alert):
```
Rule: Capstone - High Error Rate
Triggered: <timestamp from your alert history>
Condition: count of level : "ERROR" in last 1h > 5
Actual value: <actual triggered value>
Index: capstone-app-*
```

**Agent-generated explanation** (example):
```
"The application logged 12 ERROR-level events in the last hour, exceeding
the threshold of 5. Breakdown by service: auth-service (7 errors),
payment-service (5 errors). Cross-referencing capstone-web-* reveals a
correlated spike in HTTP 500 responses on /api/checkout and /api/payment.
Recommended action: check auth-service health and recent deployments —
the web errors appear to be downstream symptoms of the auth-service failures."
```

> The value of Agentic AI here is context enrichment — the agent doesn't just repeat the alert, it investigates related data (capstone-web-*) and suggests next steps. The explanation starts from the alert source (app errors), then enriches with correlated web data.

---

#### Option C: Custom Agentic AI Use Case

7c. If you have a different AI use case relevant to the capstone scenario, document it with:
- Problem statement
- Agent workflow (what data it reads, what queries it runs)
- Expected inputs and outputs
- How it reduces manual investigation time

---

8. Document the chosen Agentic AI approach

> Regardless of which option you chose, write a brief summary (in a text file or Kibana Canvas) that captures the use case.

Create a summary document:

```bash
cat <<'EOF' > ~/capstone/agentic-ai-summary.md
# Agentic AI Use Case — Capstone

## Option Chosen: [A / B / C]

## Problem Statement
[What operational challenge does this address?]

## Agent Workflow
1. [Step 1 — what data the agent accesses]
2. [Step 2 — what analysis it performs]
3. [Step 3 — what output it produces]

## Expected Inputs
- [Data sources, alert data, log indices]

## Expected Outputs
- [Human-readable summary, recommended actions, correlation report]

## Value
[How this reduces MTTR or improves operational efficiency]
EOF
```

9. Final capstone architecture review

> Review the complete architecture built across all 5 labs.

```json
GET _cluster/health
GET _cat/indices/capstone-*?v&h=index,health,docs.count,store.size
GET _cat/nodes?v&h=name,node.role,heap.percent,cpu
```

```
Menu (☰) → Management → Stack Management → Index Management → Index Templates
```

Verify all capstone components:

| Component | Status Check |
|-----------|-------------|
| **Ingestion** | Logstash multi-pipeline running (web + app) |
| **Beats** | Metricbeat collecting system metrics *(if installed — see Lab 1 step 7)* |
| **Templates** | capstone-web, capstone-app templates applied |
| **ILM** | capstone-lifecycle policy active |
| **Dashboards** | Executive, Operations, Analytics dashboards |
| **Alerts** | Error rate threshold rule active |
| **Security** | RBAC roles (viewer/analyst) enforced *(if security enabled — see Lab 3)* |
| **Audit** | Audit logging capturing events *(if configured in Module 06)* |
| **Recovery** | Pipeline failure simulated and recovered |
| **Agentic AI** | One use case documented |

That wraps up the capstone. You have simulated and recovered from a pipeline failure, demonstrated an Agentic AI use case, and reviewed the complete architecture.

---

## Cleanup & Teardown

After completing all labs, clean up the capstone resources:

```bash
# Restore original Logstash pipelines.yml
sudo cp /etc/logstash/pipelines.yml.bak /etc/logstash/pipelines.yml
sudo rm -f /etc/logstash/conf.d/capstone-web.conf /etc/logstash/conf.d/capstone-app.conf
sudo systemctl restart logstash

# Remove capstone data and configs
rm -rf ~/capstone
sudo rm -rf /opt/capstone
```

Delete capstone indices and ILM policy (in Dev Tools):

```json
DELETE capstone-web-*
DELETE capstone-app-*
DELETE _ilm/policy/capstone-lifecycle
DELETE _index_template/capstone-web
DELETE _index_template/capstone-app
DELETE _component_template/capstone-common
```

> **Optional**: If you created RBAC roles/users in Lab 3 and want to remove them:
>
> ```json
> DELETE _security/role/capstone_viewer
> DELETE _security/role/capstone_analyst
> DELETE _security/user/capstone-viewer
> DELETE _security/user/capstone-analyst
> ```

> **Note**: Kibana dashboards, data views, and alert rules must be removed from the Kibana UI (Stack Management → Saved Objects / Rules).
