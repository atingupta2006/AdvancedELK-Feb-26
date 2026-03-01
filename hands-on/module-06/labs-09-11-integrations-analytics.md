# Module 06 - Labs 09-11

## Integrations, Fleet, ES|QL Investigation

---

## Lab 9: Integrations & Streaming Pipelines

**Objective**: Understand Kafka integration patterns, JDBC enrichment, and compare ingestion tools

> Production ELK deployments rarely use direct Filebeat→Elasticsearch flows. A **message broker** (Kafka) sits between producers and consumers, providing buffering, replay, and decoupling. This lab covers the architecture and demonstrates JDBC enrichment patterns.

### Part 1: Kafka Integration Architecture (Conceptual + Config Walkthrough)

> **Note**: Setting up a full Kafka cluster is outside the scope of this training environment. This section walks through the configuration patterns so you can recognize and build them in production.

1. Understand the Kafka-ELK architecture

```
┌──────────┐     ┌─────────┐     ┌───────────┐     ┌──────────────┐
│ Filebeat  │────▶│  Kafka  │────▶│  Logstash │────▶│Elasticsearch │
│ (shipper) │     │ (broker)│     │ (consumer)│     │  (storage)   │
└──────────┘     └─────────┘     └───────────┘     └──────────────┘
```

> **Why Kafka?**
> - **Buffering**: If Elasticsearch goes down, Kafka holds the data. Nothing is lost.
> - **Replay**: Need to re-process last week's data? Kafka can replay it.
> - **Fan-out**: One Kafka topic can feed multiple consumers (Logstash for ES, Spark for analytics, S3 for archival).

2. Review Kafka input configuration for Logstash

> This is the Logstash config pattern you would use in production:

```conf
# Logstash Kafka Consumer Pattern (reference)
input {
  kafka {
    bootstrap_servers => "kafka-broker-1:9092,kafka-broker-2:9092"
    topics => ["web-logs", "app-logs"]
    group_id => "elk-consumer-group"
    codec => json
    consumer_threads => 3
    decorate_events => true    # adds kafka metadata (topic, partition, offset)
  }
}

filter {
  if [@metadata][kafka][topic] == "web-logs" {
    # parse web logs
    grok { match => { "message" => '%{COMBINEDAPACHELOG}' } }
  }
  if [@metadata][kafka][topic] == "app-logs" {
    # parse app logs
    date { match => ["timestamp", "ISO8601"] }
  }
}

output {
  if [@metadata][kafka][topic] == "web-logs" {
    elasticsearch {
      hosts => ["http://elasticsearch:9200"]
      index => "web-logs-%{+YYYY.MM.dd}"
    }
  }
  if [@metadata][kafka][topic] == "app-logs" {
    elasticsearch {
      hosts => ["http://elasticsearch:9200"]
      index => "app-logs-%{+YYYY.MM.dd}"
    }
  }
}
```

> **Key config parameters**:
> | Parameter | Purpose |
> |-----------|---------|
> | `bootstrap_servers` | Kafka broker addresses for initial connection |
> | `group_id` | Consumer group — Kafka tracks offsets per group for exactly-once delivery |
> | `consumer_threads` | Parallelism — match to the number of Kafka partitions |
> | `decorate_events` | Adds `@metadata[kafka]` fields (topic, partition, offset) for routing |

3. Review Kafka output configuration for Filebeat

> Filebeat can write directly to Kafka instead of Logstash:

```yaml
# Filebeat Kafka Output Pattern (reference)
output.kafka:
  hosts: ["kafka-broker-1:9092", "kafka-broker-2:9092"]
  topic: "web-logs"
  partition.round_robin:
    reachable_only: true
  required_acks: 1
  compression: gzip
```

### Part 2: JDBC Enrichment Pattern

4. Understand the JDBC enrichment use case

> **Scenario**: Your logs contain `user_id: "U12345"` but no user name, department, or location. A relational database has this mapping. The `jdbc_streaming` filter enriches each event in real-time by querying the database.

5. Review JDBC filter configuration

```conf
# Logstash JDBC Enrichment Pattern (reference)
filter {
  jdbc_streaming {
    jdbc_driver_library => "/opt/logstash/drivers/mysql-connector-java.jar"
    jdbc_driver_class => "com.mysql.cj.jdbc.Driver"
    jdbc_connection_string => "jdbc:mysql://db-host:3306/users_db"
    jdbc_user => "readonly_user"
    jdbc_password => "${DB_PASSWORD}"
    statement => "SELECT name, department, location FROM users WHERE user_id = :uid"
    parameters => { "uid" => "user_id" }
    target => "user_info"
    cache_size => 1000
    cache_expiration => 300
  }
}
```

> **Performance considerations**:
> - `cache_size` and `cache_expiration` prevent hammering the database on every event
> - Use a read-only database user
> - Consider a materialized view or replica for lookup tables

### Part 3: Ingestion Tool Comparison

6. Review the comparison matrix

> When designing ingestion architecture, choose the right tool for the job:

| Feature | **Filebeat** | **Logstash** | **Fluent Bit** | **Elastic Agent** |
|---------|-------------|-------------|----------------|-------------------|
| **Weight** | ~30 MB RAM | ~500 MB+ RAM | ~5 MB RAM | ~100 MB RAM |
| **Parsing** | Basic (modules) | Advanced (grok, dissect, ruby) | Moderate (parsers) | Via integrations |
| **Buffering** | Disk-backed registry | Persistent queues | In-memory + disk | Fleet-managed |
| **Use case** | Ship logs from servers | Heavy parsing, routing, enrichment | Kubernetes sidecar, IoT | Unified agent, Fleet-managed |
| **Kafka support** | Output only | Input + Output | Output only | Via integrations |
| **Management** | Config files per host | Centralized configs | Config files / Helm | Fleet Server (UI) |

> **Decision framework**:
> - **Simple shipping**: Filebeat or Fluent Bit
> - **Complex parsing/enrichment**: Logstash
> - **Kubernetes**: Fluent Bit (low resource footprint)
> - **Centralized management**: Elastic Agent + Fleet

**Success**: You understand Kafka integration patterns, JDBC enrichment, and can choose the right ingestion tool for a given scenario.

---

## Lab 10: Elastic Agent and Fleet Management

**Objective**: Deploy and manage Elastic Agent via Fleet

> **Elastic Agent** is a unified agent that replaces individual Beats (Filebeat, Metricbeat, etc.). **Fleet** is the centralized management UI in Kibana that handles agent policies, integrations, and upgrades. One agent, one config, managed from one place.

> **Prerequisite**: Lab 7 (Security) must be completed — Fleet requires authentication.

1. Enable Fleet in Kibana

```
Menu (☰) → Management → Fleet
```

> First-time setup: Kibana prompts you to configure Fleet Server. Follow the on-screen setup wizard.

2. Add Fleet Server (if not already configured)

> Fleet Server is a special Elastic Agent instance that coordinates all other agents. In training, we run it on the same host as Elasticsearch.

```
Fleet → Settings → Add Fleet Server
Host URL: https://127.0.0.1:8220

Follow the enrollment instructions shown in Kibana UI
```

3. Install Elastic Agent on the host

```bash
cd /tmp
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-9.0.0-linux-x86_64.tar.gz
tar xzf elastic-agent-9.0.0-linux-x86_64.tar.gz
cd elastic-agent-9.0.0-linux-x86_64
```

> **Note**: Replace `9.0.0` with the version matching your installed Elastic Stack (`curl http://127.0.0.1:9200 | jq .version.number`).

> The enrollment command is generated by Kibana's Fleet UI. Copy the exact command shown — it contains the Fleet Server URL and enrollment token.

```bash
sudo ./elastic-agent install --url=<FLEET_SERVER_URL> --enrollment-token=<TOKEN>
```

4. Verify agent enrollment

```
Menu (☰) → Management → Fleet → Agents
```

> The agent should appear with status `Healthy`. If status is `Offline`, check network connectivity between the agent and Fleet Server.

5. Create agent policy with integrations

> An **agent policy** defines what data an agent collects. **Integrations** are pre-built data collection modules (like Beats modules but for Elastic Agent).

```
Fleet → Agent policies → Create agent policy
Name: Training-Policy
Description: Training environment data collection

Add integration:
  Search: System
  Add System integration
  Accept defaults → Save
```

6. Verify data collection

```
Menu (☰) → Analytics → Discover

Try data views:
  logs-system.*
  metrics-system.*
```

> Elastic Agent indexes into `logs-*` and `metrics-*` data streams by default (ECS-formatted). This is different from Filebeat/Metricbeat's `filebeat-*`/`metricbeat-*` patterns.

7. Review agent metrics

```
Fleet → Agents → Click agent name
Review: Agent status, uptime, integrations active
```

**Success**: Agent enrolled and reporting system logs + metrics to Elasticsearch

---

## Lab 11: ES|QL and Advanced Analytics

**Objective**: Use ES|QL for data analysis and multi-step investigation workflows

> **ES|QL** (Elasticsearch Query Language) is a piped query language — similar to Unix pipes or SPL (Splunk). Data flows through commands: `FROM` → `WHERE` → `STATS` → `SORT`. Unlike Query DSL (JSON), ES|QL is human-readable and designed for ad-hoc analysis.

### Part A: ES|QL Core Skills

1. Open Discover in ES|QL mode

```
Menu (☰) → Analytics → Discover
Click the language selector (next to the query bar)
Switch from KQL to ES|QL
```

2. Basic query — retrieve all documents

> `FROM` specifies the index. `LIMIT` caps the result count (default is 1000 in Discover).

```
FROM web-logs-*
| LIMIT 20
```

3. Filter with WHERE

> `WHERE` filters rows, like SQL. Use comparison operators (`==`, `!=`, `>`, `<`) and logical operators (`AND`, `OR`, `NOT`).

```
FROM web-logs-*
| WHERE status >= 400
| LIMIT 20
```

4. Sort results

```
FROM web-logs-*
| WHERE status >= 400
| SORT @timestamp DESC
| LIMIT 10
```

5. Select specific fields with KEEP

> `KEEP` controls which columns appear in the output — equivalent to `SELECT` in SQL.

```
FROM web-logs-*
| KEEP @timestamp, method, path, status, bytes
| SORT @timestamp DESC
| LIMIT 20
```

6. Aggregate with STATS

> `STATS ... BY` is the aggregation command. It groups data and computes metrics — equivalent to `GROUP BY` + aggregate functions in SQL.

```
FROM web-logs-*
| STATS count = COUNT(*) BY status
| SORT count DESC
```

7. Multi-field aggregation

```
FROM web-logs-*
| STATS request_count = COUNT(*), avg_bytes = AVG(bytes) BY method
| SORT request_count DESC
```

8. Computed fields with EVAL

> `EVAL` creates new computed columns from expressions. Useful for transformations, categorizations, and calculations.

```
FROM web-logs-*
| EVAL size_category = CASE(
    bytes < 500, "small",
    bytes < 2000, "medium",
    "large"
  )
| STATS count = COUNT(*) BY size_category
```

9. Time-based analysis

```
FROM app-logs-*
| WHERE level == "ERROR"
| STATS error_count = COUNT(*) BY service
| SORT error_count DESC
```

10. ES|QL via REST API (Dev Tools)

> ES|QL queries can also run via the `_query` REST endpoint. The response format differs from `_search` — results come back as columnar data.

```
Menu (☰) → Management → Dev Tools
```

```json
POST _query
{
  "query": "FROM web-logs-* | STATS count = COUNT(*) BY status | SORT count DESC"
}
```

### Part B: Advanced Investigation – Multi-Step Query Workflows

**Objective**: Use ES|QL to answer complex operational questions through systematic query sequences.

1. Open Discover in ES|QL mode

```
Menu (☰) → Analytics → Discover
Switch language from KQL to ES|QL
```

2. Step 1 — Identify error concentration by service

```
FROM app-logs-*
| WHERE level == "ERROR"
| STATS error_count = COUNT(*) BY service
| SORT error_count DESC
```

3. Step 2 — Correlate with failing HTTP endpoints

```
FROM web-logs-*
| WHERE status >= 500
| STATS error_count = COUNT(*) BY path
| SORT error_count DESC
| LIMIT 10
```

4. Step 3 — Pull latest error evidence for top service

```
FROM app-logs-*
| WHERE service == "payment-service" AND level == "ERROR"
| KEEP @timestamp, service, message, error, order_id
| SORT @timestamp DESC
| LIMIT 20
```

5. Step 4 — Estimate incident scope from web logs

```
FROM web-logs-*
| WHERE status >= 500
| STATS affected_clients = COUNT_DISTINCT(client_ip), total_5xx = COUNT(*)
```

6. Step 5 — Produce a standard investigation summary

Use this output structure:

```
Incident question: <what triggered the investigation>
Top failing service: <from step 1>
Top failing endpoints: <from step 2>
Latest evidence: <from step 3>
Impact estimate: <from step 4>
Next step: <focused follow-up query>
```

### Example follow-up query

```
FROM app-logs-*
| WHERE service == "payment-service" AND level == "ERROR"
| STATS count = COUNT(*) BY error
| SORT count DESC
```

### Ambiguity guardrails

> If a field does not exist in your index mapping, remove it from `KEEP`/`STATS` and rerun.

> When two services have similar error counts, report both and avoid a single-cause conclusion.

**Success**: You can convert a vague incident question into a deterministic ES|QL investigation chain and a clear next action.

> **Coming up**: In [Lab 14](./labs-12-14-observability-resilience.md#lab-14-automating-investigation-workflows-with-a-genai-agent), you will build a GenAI agent that automates this same multi-step investigation workflow. Keep your manual results — you will compare them against the agent's output.

---

