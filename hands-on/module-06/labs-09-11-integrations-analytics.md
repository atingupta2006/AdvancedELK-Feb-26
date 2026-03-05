# Module 06 - Labs 09-11

## Integrations, Fleet, ES|QL Investigation

---

## Lab 9: Integrations & Streaming Pipelines

**Objective**: Understand Kafka integration patterns, JDBC enrichment, and compare ingestion tools

> Production ELK deployments rarely use direct Filebeat→Elasticsearch flows. A **message broker** (Kafka) sits between producers and consumers, providing buffering, replay, and decoupling. This lab covers the architecture and demonstrates JDBC enrichment patterns.

### Part 1: Kafka Integration Architecture (Conceptual + Config Walkthrough)

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
> | `group_id` | Consumer group — Kafka tracks offsets per group for at-least-once delivery |
> | `consumer_threads` | Parallelism — match to the number of Kafka partitions |
> | `decorate_events` | Adds `@metadata[kafka]` fields (topic, partition, offset) for routing |

> **Note**: Kafka with Logstash provides **at-least-once delivery semantics**. Kafka tracks consumer group offsets, but Logstash may reprocess messages on restart or failure, so messages may be delivered more than once.

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

### Part 2: JDBC Enrichment Pattern (Hands-On)

4. Understand the JDBC enrichment use case

> **Scenario**: Your logs contain `user_id: "U12345"` but no user name, department, or location. A relational database has this mapping. The `jdbc_streaming` filter enriches each event in real-time by querying the database.

> In this lab, we'll use **SQLite** (an in-memory/file-based database) to demonstrate JDBC enrichment without needing external database setup.

5. Install SQLite and create database with sample user data

```bash
# Install SQLite (if not already installed)
sudo dnf install sqlite -y
# For Ubuntu/Debian: sudo apt install sqlite3 -y

# Create directory for database
sudo mkdir -p /opt/logstash/data
cd /opt/logstash/data

# Create SQLite database with sample users
sqlite3 users.db << 'EOF'
CREATE TABLE users (
  user_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  department TEXT NOT NULL,
  location TEXT NOT NULL,
  email TEXT
);

INSERT INTO users (user_id, name, department, location, email) VALUES
  ('U12345', 'Alice Johnson', 'Engineering', 'New York', 'alice.j@company.com'),
  ('U12346', 'Bob Smith', 'Marketing', 'San Francisco', 'bob.s@company.com'),
  ('U12347', 'Carol White', 'Engineering', 'Austin', 'carol.w@company.com'),
  ('U12348', 'David Brown', 'Finance', 'Chicago', 'david.b@company.com'),
  ('U12349', 'Eve Davis', 'Operations', 'Seattle', 'eve.d@company.com'),
  ('U12350', 'Frank Miller', 'Engineering', 'Boston', 'frank.m@company.com'),
  ('U12351', 'Grace Lee', 'HR', 'Denver', 'grace.l@company.com'),
  ('U12352', 'Henry Wilson', 'Sales', 'Miami', 'henry.w@company.com');

SELECT 'Database created with ' || COUNT(*) || ' users' FROM users;
.quit
EOF

# Verify data
sqlite3 users.db "SELECT * FROM users LIMIT 3;"
```

6. Download SQLite JDBC driver

```bash
# Download SQLite JDBC driver
sudo mkdir -p /opt/logstash/drivers
cd /opt/logstash/drivers
sudo curl -L -O https://repo1.maven.org/maven2/org/xerial/sqlite-jdbc/3.45.0.0/sqlite-jdbc-3.45.0.0.jar

# Verify download
ls -lh sqlite-jdbc-*.jar
```

7. Create test log file with user IDs

```bash
# Create sample access logs with user IDs
sudo mkdir -p /var/log/app
sudo tee /var/log/app/access.log > /dev/null << 'EOF'
{"timestamp":"2026-03-05T10:15:23Z","user_id":"U12345","action":"login","status":"success"}
{"timestamp":"2026-03-05T10:16:45Z","user_id":"U12346","action":"purchase","status":"success","amount":49.99}
{"timestamp":"2026-03-05T10:17:12Z","user_id":"U12347","action":"view_page","status":"success","page":"/products"}
{"timestamp":"2026-03-05T10:18:33Z","user_id":"U12348","action":"download","status":"success","file":"report.pdf"}
{"timestamp":"2026-03-05T10:19:01Z","user_id":"U99999","action":"login","status":"failed"}
{"timestamp":"2026-03-05T10:20:15Z","user_id":"U12349","action":"logout","status":"success"}
{"timestamp":"2026-03-05T10:21:47Z","user_id":"U12350","action":"api_call","status":"success","endpoint":"/api/v1/data"}
EOF

# Make readable
sudo chmod 644 /var/log/app/access.log
```

8. Create Logstash configuration with JDBC enrichment

```bash
sudo tee /etc/logstash/conf.d/jdbc-enrichment.conf > /dev/null << 'EOF'
input {
  file {
    path => "/var/log/app/access.log"
    start_position => "beginning"
    sincedb_path => "/dev/null"  # Always read from start for testing
    codec => json
  }
}

filter {
  # JDBC Streaming lookup to enrich user data
  jdbc_streaming {
    jdbc_driver_library => "/opt/logstash/drivers/sqlite-jdbc-3.45.0.0.jar"
    jdbc_driver_class => "org.sqlite.JDBC"
    jdbc_connection_string => "jdbc:sqlite:/opt/logstash/data/users.db"
    jdbc_user => ""  # SQLite doesn't require user/password for file database
    jdbc_password => ""
    statement => "SELECT name, department, location, email FROM users WHERE user_id = :uid"
    parameters => { "uid" => "user_id" }
    target => "user_info"
    
    # Performance tuning - cache results to reduce database queries
    cache_size => 1000
    cache_expiration => 300  # Cache entries expire after 300 seconds (5 minutes)
  }
  
  # Add a flag for enriched vs non-enriched events
  # jdbc_streaming creates an empty array when no results found, so check if array has elements
  if [user_info] and [user_info][0] {
    mutate {
      add_field => { "enriched" => "true" }
    }
  } else {
    # User not found in database (user_info is [] or doesn't exist)
    mutate {
      add_field => { "enriched" => "false" }
      add_tag => ["unknown_user", "jdbc_lookup_failed"]
    }
  }
}

output {
  elasticsearch {
    hosts => ["http://127.0.0.1:9200"]
    index => "enriched-logs-%{+YYYY.MM.dd}"
    user => "elastic"
    password => "${ELASTIC_PASSWORD}"
    # Remove user/password lines if security is disabled (xpack.security.enabled=false)
  }
  
  # Debug output to console
  stdout {
    codec => rubydebug
  }
}
EOF
```

9. Run Logstash with JDBC enrichment

```bash
# Test configuration first
sudo /usr/share/logstash/bin/logstash -f /etc/logstash/conf.d/jdbc-enrichment.conf --config.test_and_exit

# Run Logstash (Ctrl+C to stop after processing)
sudo /usr/share/logstash/bin/logstash -f /etc/logstash/conf.d/jdbc-enrichment.conf
```

> Watch the console output. You should see enriched documents with `user_info` containing name, department, location, and email for known user IDs (U12345-U12352). User ID U99999 will have `enriched: false` and `unknown_user` tag.

10. Verify enrichment in Elasticsearch

```
Menu (☰) → Management → Dev Tools
```

```json
# Check enriched documents
GET enriched-logs-*/_search
{
  "size": 3,
  "query": {
    "term": { "enriched": "true" }
  },
  "_source": ["user_id", "action", "user_info", "enriched"]
}
```

```json
# Find documents with unknown users
GET enriched-logs-*/_search
{
  "query": {
    "term": { "enriched": "false" }
  }
}
```

```json
# Aggregation: count actions by department
GET enriched-logs-*/_search
{
  "size": 0,
  "aggs": {
    "by_department": {
      "terms": {
        "field": "user_info.department.keyword"
      },
      "aggs": {
        "actions": {
          "terms": {
            "field": "action.keyword"
          }
        }
      }
    }
  }
}
```

11. Understand the enrichment results

> **Before enrichment**:
> ```json
> {
>   "timestamp": "2026-03-05T10:15:23Z",
>   "user_id": "U12345",
>   "action": "login",
>   "status": "success"
> }
> ```

> **After enrichment**:
> ```json
> {
>   "timestamp": "2026-03-05T10:15:23Z",
>   "user_id": "U12345",
>   "action": "login",
>   "status": "success",
>   "user_info": [
>     {
>       "name": "Alice Johnson",
>       "department": "Engineering",
>       "location": "New York",
>       "email": "alice.j@company.com"
>     }
>   ],
>   "enriched": "true"
> }
> ```
>
> **Note**: `jdbc_streaming` returns results as an array. For unknown users, `user_info` will be an empty array `[]`.

> **Performance considerations**:
> - `cache_size` (1000) and `cache_expiration` (300 seconds = 5 minutes) prevent querying the database for every event with the same user_id
> - First lookup for each user_id hits the database; subsequent lookups within 5 minutes use cached results
> - Use conditional logic (`if [user_info] and [user_info][0]`) to identify and handle lookup failures (jdbc_streaming returns empty array when no results found)
> - For production with MySQL/PostgreSQL, use a read-only database user
> - Consider a materialized view or replica for lookup tables to avoid impacting production databases

**Success**: Logs are enriched with user information from SQLite database, demonstrating real-time JDBC enrichment patterns.

### Part 3: Ingestion Tool Comparison

12. Review the comparison matrix

> When designing ingestion architecture, choose the right tool for the job:

| Feature | **Filebeat** | **Logstash** | **Fluent Bit** | **Elastic Agent** |
|---------|-------------|-------------|----------------|-------------------|
| **Weight** | ~20–80 MB RAM | ~1 GB+ RAM (JVM recommended) | ~5–15 MB RAM | ~150–300 MB RAM |
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
```

> **Important**: The Fleet UI generates **two different commands**:
> - **Fleet Server installation command** — installs the Fleet Server itself
> - **Agent enrollment command** — enrolls regular agents to Fleet
>
> Run the **Fleet Server command first**. Copy the exact command shown in the UI and keep it ready for the next step.

3. Install Elastic Agent on the host

> **Important**: The agent version **must exactly match** your Elasticsearch version. Check your version first:

```bash
curl -s http://127.0.0.1:9200 | jq -r .version.number
```

> Now download the matching Elastic Agent version. Replace `9.0.0` below with your actual version:

```bash
cd /tmp
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-9.0.0-linux-x86_64.tar.gz
tar xzf elastic-agent-9.0.0-linux-x86_64.tar.gz
cd elastic-agent-9.0.0-linux-x86_64
```

> The enrollment command is generated by Kibana's Fleet UI. **Go to Fleet UI now** and copy the exact command shown — it contains the Fleet Server URL and enrollment token.

```bash
sudo ./elastic-agent install --url=<FLEET_SERVER_URL> --enrollment-token=<TOKEN>
```

> The Fleet Server will start automatically after installation. Wait 10-20 seconds before enrolling additional agents.

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

> Elastic Agent writes to **data streams** following the pattern:
> ```
> logs-<dataset>-<namespace>
> metrics-<dataset>-<namespace>
> ```
>
> Examples:
> - `logs-system.auth-default`
> - `logs-system.syslog-default`
> - `metrics-system.cpu-default`
> - `metrics-system.memory-default`
>
> This is different from traditional indices like `filebeat-*` or `metricbeat-*`. Data streams provide better lifecycle management and performance for time-series data.

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

