# Module 06 - Labs 09-11

## Integrations, Fleet, ES|QL Investigation

---

## Lab 9: Integrations & Streaming Pipelines

**Objective**: Understand Kafka integration patterns, JDBC enrichment, and compare ingestion tools

> Production ELK deployments rarely ingest logs directly from Filebeat to Elasticsearch. A **message broker** (Kafka) sits between producers and consumers, providing buffering, replay, and decoupling. This lab covers that architecture and walks through JDBC enrichment hands-on.

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

> **Note**: Kafka with Logstash gives you **at-least-once delivery**. Kafka tracks consumer group offsets, but Logstash may reprocess messages on restart, so duplicates are possible.

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

```
┌──────────────┐     ┌───────────┐     ┌──────────────┐     ┌──────────────┐
│  Log file    │────▶│ Logstash  │────▶│ Elasticsearch│────▶│   Kibana     │
│ (access.log) │     │  (filter) │     │  (storage)   │     │ (dashboards) │
└──────────────┘     └─────┬─────┘     └──────────────┘     └──────────────┘
                           │
                    jdbc_streaming
                     lookup per
                      event
                           │
                     ┌─────▼─────┐
                     │  SQLite   │
                     │ users.db  │
                     └───────────┘
```

> In this lab, we use **SQLite** (a file-based database) to demonstrate JDBC enrichment without needing external database setup.

5. Install SQLite and create database with sample user data

```bash
# Install SQLite (if not already installed)
sudo dnf install sqlite -y
# For Ubuntu/Debian: sudo apt install sqlite3 -y

# Create directory for database
sudo mkdir -p /opt/logstash/data

# Create SQLite database with sample users (sudo required — directory is root-owned)
sudo sqlite3 /opt/logstash/data/users.db << 'EOF'
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
sqlite3 /opt/logstash/data/users.db "SELECT * FROM users LIMIT 3;"
```

6. Download SQLite JDBC driver

```bash
# Download SQLite JDBC driver
sudo mkdir -p /opt/logstash/drivers
cd /opt/logstash/drivers
sudo curl -L -O https://repo1.maven.org/maven2/org/xerial/sqlite-jdbc/3.45.0.0/sqlite-jdbc-3.45.0.0.jar

# Fix permissions so logstash user can access the driver
sudo chown -R logstash:logstash /opt/logstash/

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

8. Verify JDBC streaming plugin is available

```bash
# The jdbc_streaming filter plugin is bundled with Logstash 9.x
# Verify it is available:
sudo /usr/share/logstash/bin/logstash-plugin list | grep jdbc_streaming

# If not listed (older Logstash versions), install it:
# sudo /usr/share/logstash/bin/logstash-plugin install logstash-filter-jdbc_streaming
```

9. Create Logstash configuration with JDBC enrichment

> **Important — Pipeline architecture on this VM**:
> All `.conf` files in `/etc/logstash/conf.d/` are merged into a **single pipeline**. The existing `elk-training.conf` already defines an Elasticsearch output that routes events by the `index_prefix` field:
> ```
> index => "%{[index_prefix]}-%{+YYYY.MM.dd}"
> ```
> So `jdbc-enrichment.conf` only needs input + filter + stdout output. The ES indexing happens automatically through `elk-training.conf`'s output when we set `index_prefix => "enriched-logs"`.

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

  # Check for JDBC connection/query failures first
  if "_jdbcstreamingfailure" in [tags] {
    mutate {
      add_field => { "enriched" => "false" }
      add_tag => ["jdbc_lookup_failed"]
      add_field => { "index_prefix" => "enriched-logs" }
    }
  }
  # Successful lookup — user_info array has at least one result with a name field
  else if [user_info] and [user_info][0] and [user_info][0][name] {
    mutate {
      add_field => { "enriched" => "true" }
      add_field => { "index_prefix" => "enriched-logs" }
    }
  }
  # User not found in database (user_info is [] or fields are empty)
  else {
    mutate {
      add_field => { "enriched" => "false" }
      add_tag => ["unknown_user"]
      add_field => { "index_prefix" => "enriched-logs" }
    }
  }
}

# elk-training.conf already defines the Elasticsearch output using %{[index_prefix]}.
# Keep only stdout here to avoid duplicate indexing when conf.d files are merged.
output {
  stdout { codec => rubydebug }
}
EOF
```

> **Note on the connection string**: Do **not** append `?mode=ro` to the SQLite JDBC URL. The Sequel library used by Logstash's jdbc_streaming plugin does not support SQLite URI parameters — adding `?mode=ro` causes Sequel to open a blank in-memory database instead of the actual file, resulting in `[SQLITE_ERROR] no such table: users`. Use the plain path: `jdbc:sqlite:/opt/logstash/data/users.db`.

10. Validate and run Logstash with JDBC enrichment

> **Important**: The Logstash service loads **all** `.conf` files in `/etc/logstash/conf.d/` as a single pipeline. You cannot run a single config file with `-f` while the service is running — the service holds a lock on the data directory.

First, validate the configuration:

```bash
# Test configuration syntax (stop the service first to release the lock)
sudo systemctl stop logstash
sudo -u logstash /usr/share/logstash/bin/logstash \
  --config.test_and_exit \
  -f /etc/logstash/conf.d/ \
  --path.data /var/lib/logstash
```

> Expected output: `Configuration OK`

Now start the service to run the full pipeline:

```bash
# Restart Logstash — it will load both elk-training.conf and jdbc-enrichment.conf
sudo systemctl restart logstash

# View logs in real-time (Ctrl+C to stop watching)
sudo journalctl -u logstash -f

# Verify the service started successfully
sudo systemctl status logstash
```

> **What to watch for in the logs:**
> - `Pipeline started` — pipeline is running
> - `Connected to ES instance` — Elasticsearch output is connected
> - Enriched events printed to stdout via `rubydebug` codec
> - No `SQLITE_ERROR` or `_jdbcstreamingfailure` warnings

> Watch the output. You should see enriched documents with `user_info` containing name, department, location, and email for known user IDs (U12345-U12352). User ID U99999 will have `enriched: false` and `unknown_user` tag.

11. Verify enrichment in Elasticsearch

You can verify via Kibana Dev Tools or directly with `curl` from the command line:

```
Menu (☰) → Management → Dev Tools
```

```json
# Check document count
GET enriched-logs-*/_count
```

> Expected: **7 documents** (one per JSON line in access.log: 6 known users + 1 unknown user U99999).

```json
# Check enriched documents — should return users U12345-U12350
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
# Find documents with unknown users — should return U99999
GET enriched-logs-*/_search
{
  "query": {
    "term": { "enriched": "false" }
  }
}
```

Alternatively, verify with `curl` from the terminal:

```bash
# Count documents
curl -s http://192.168.56.101:9200/enriched-logs-*/_count | python3 -m json.tool

# Check enriched documents
curl -s 'http://192.168.56.101:9200/enriched-logs-*/_search?size=3&pretty' \
  -H 'Content-Type: application/json' \
  -d '{"query":{"term":{"enriched":"true"}},"_source":["user_id","action","user_info","enriched"]}'

# Find unknown users
curl -s 'http://192.168.56.101:9200/enriched-logs-*/_search?pretty' \
  -H 'Content-Type: application/json' \
  -d '{"query":{"term":{"enriched":"false"}}}'
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

12. Understand the enrichment results

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

At this point, your logs are enriched with user details from the SQLite database. The same pattern applies to MySQL, PostgreSQL, or any JDBC-compatible source.

### Part 3: Ingestion Tool Comparison

13. Review the comparison matrix

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

That wraps up Lab 9. You've walked through Kafka architecture, hands-on JDBC enrichment, and compared ingestion tools for different use cases.

---

## Lab 10: Elastic Agent and Fleet Management

**Objective**: Deploy and manage Elastic Agent via Fleet

> **Elastic Agent** is a unified agent that replaces individual Beats (Filebeat, Metricbeat, etc.). **Fleet** is the centralized management UI in Kibana that handles agent policies, integrations, and upgrades. One agent, one config, managed from one place.

```
┌────────────────────────────────┐
│           Kibana               │
│     ┌──────────────┐           │
│     │  Fleet UI    │           │
│     │ (policies +  │           │
│     │ integrations)│           │
│     └──────┬───────┘           │
└────────────┼───────────────────┘
             │ manages
             v
┌────────────────────┐       ┌──────────────────┐
│   Fleet Server     │◀──────│  Elastic Agent   │
│ (coordination)     │       │  (on each host)  │
└────────┬───────────┘       └────────┬─────────┘
         │                            │
         v                            v
┌──────────────────┐       logs, metrics, etc.
│  Elasticsearch   │◀────────────────┘
└──────────────────┘
```

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
ES_VERSION=$(curl -s http://192.168.56.101:9200 | jq -r .version.number)
echo "Using Elasticsearch version: $ES_VERSION"
```

> Now download the matching Elastic Agent version:

```bash
ES_VERSION=$(curl -s http://192.168.56.101:9200 | jq -r .version.number)
cd /tmp
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${ES_VERSION}-linux-x86_64.tar.gz
tar xzf elastic-agent-${ES_VERSION}-linux-x86_64.tar.gz
cd elastic-agent-${ES_VERSION}-linux-x86_64
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

If the agent shows `Healthy` and data appears in Discover, Lab 10 is complete.

---

## Lab 11: ES|QL and Advanced Analytics

**Objective**: Use ES|QL for data analysis and multi-step investigation workflows

> **Prerequisite**: This lab queries `web-logs-*` and `app-logs-*` indices populated in **Module 02** (Filebeat + Logstash labs). If you skipped Module 02, those indices will be empty and queries will return no results.
>
> **Quick check** — run in Dev Tools before starting:
> ```json
> GET web-logs-*/_count
> GET app-logs-*/_count
> ```
> If either returns `0` or `index_not_found`, complete Module 02 Labs 1-2 first, or substitute `enriched-logs-*` from Lab 9 to practice ES|QL syntax (adjust field names accordingly).

> **ES|QL** (Elasticsearch Query Language) is a piped query language — think Unix pipes or Splunk's SPL. Data flows through commands: `FROM` → `WHERE` → `STATS` → `SORT`. Unlike Query DSL (JSON-based), ES|QL reads left-to-right and is built for ad-hoc investigation.

### ES|QL Mental Model (Read This First)

Think of ES|QL as a **left-to-right data pipeline**. Each command receives a table, transforms it, and passes a new table to the next.

```
Raw documents
  |
  v
FROM index-pattern
  |
  v
WHERE (row filtering)
  |
  v
EVAL (new/calculated columns)
  |
  v
STATS ... BY ... (group + aggregate)
  |
  v
KEEP / RENAME (shape final output)
  |
  v
SORT + LIMIT (presentation)
```

Practical rule:
- Put **volume-reduction** commands early (`WHERE`, `LIMIT` for preview).
- Put **expensive grouping** later (`STATS`) after filtering.
- Put **presentation** commands at the end (`KEEP`, `SORT`, `LIMIT`).

### ES|QL Statements and Concepts (Quick Reference)

| Statement | Purpose | When to use it | Typical mistake |
|-----------|---------|----------------|-----------------|
| `FROM` | Select source indices/data streams | Always first command | Using a pattern that matches no data |
| `WHERE` | Filter rows by conditions | Early in pipeline to reduce data | Comparing wrong field type (string vs number) |
| `EVAL` | Create computed/derived fields | Categorization, normalization, flags | Reusing a field name unintentionally |
| `STATS ... BY ...` | Aggregate metrics by group | Count/summarize patterns | Grouping by high-cardinality field accidentally |
| `KEEP` | Keep only listed columns | Output cleanup for readability | Removing fields needed by later commands |
| `SORT` | Order result rows | Highlight top/bottom values | Sorting text version of numeric fields |
| `LIMIT` | Restrict returned rows | Preview queries and dashboards | Assuming `LIMIT` changes underlying data |

### ES|QL Output Shape Flow

Watch how the result shape changes at each stage:

```
START: Raw event rows (document-level)

FROM web-logs-*
  Output shape: many rows, many fields
  Example row: {@timestamp, method, path, status, bytes, client_ip, ...}

    |
    v

WHERE status >= 400
  Output shape: fewer rows, same fields
  Meaning: row filter only (no aggregation yet)

    |
    v

EVAL is_server_error = status >= 500
  Output shape: same row count, +1 new computed field
  Meaning: enrichment inside query result only

    |
    v

STATS error_count = COUNT(*) BY path
  Output shape: grouped summary rows
  Example row: {path, error_count}
  Meaning: switched from event-level to aggregate-level

    |
    v

SORT error_count DESC
  Output shape: same grouped rows, ordered by importance

    |
    v

LIMIT 10
  Output shape: top 10 grouped rows (final investigation view)
```

Quick interpretation:
- Before `STATS`: rows are usually individual events.
- After `STATS`: rows are aggregate buckets.
- Add `KEEP` before final `SORT`/`LIMIT` when you want a cleaner report-style output.

### ES|QL Investigation Map

Use this as a template when investigating incidents — each query answers one specific question.

```
Question: "Users report failed checkouts"
         |
         v
    [Step 1: Scope the issue]
    FROM app-logs-* | WHERE level == "ERROR"
    | STATS error_count = COUNT(*) BY service
         |
         v
    [Step 2: Find blast area]
    FROM web-logs-* | WHERE status >= 500
    | STATS error_count = COUNT(*) BY path
         |
         v
    [Step 3: Collect evidence]
    FROM app-logs-* | WHERE service == "payment-service"
    | KEEP @timestamp, message, error, order_id
    | SORT @timestamp DESC | LIMIT 20
         |
         v
    [Step 4: Estimate impact]
    FROM web-logs-* | WHERE status >= 500
    | STATS affected_clients = COUNT_DISTINCT(client_ip)
         |
         v
    Decision: mitigation + next focused query
```

### Reading ES|QL Results

- `STATS COUNT(*) BY field` answers "how many events per category".
- `COUNT_DISTINCT(field)` estimates uniqueness (users, hosts, IPs).
- If `STATS` returns empty results, first verify your `FROM` pattern and `WHERE` time window/conditions.
- For noisy incidents, add a narrow filter early (for example `service == "payment-service"`) before deeper analysis.

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

> **Concept note**:
> - `EVAL` does not change stored documents in Elasticsearch.
> - It only creates temporary columns for the current query result.
> - You can use `EVAL` multiple times to build logic step-by-step.

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

> **Why this matters**: `_query` is often easier for automation scripts because response columns are explicit and aligned with ES|QL output, while `_search` returns full JSON documents/hits format.

```
Menu (☰) → Management → Dev Tools
```

```json
POST /_query
{
  "query": "FROM web-logs-* | STATS count = COUNT(*) BY status | SORT count DESC"
}
```

### Part B: Advanced Investigation – Multi-Step Query Workflows

**Objective**: Use ES|QL to answer complex operational questions through a systematic, step-by-step query chain.

### Investigation Principles

- One step, one question: each query should answer one thing clearly.
- Gather raw evidence first (`KEEP`, `SORT`), then summarize (`STATS`).
- Don't jump to conclusions early — rank services/endpoints first, then drill in.
- End every investigation with a "next focused query" that confirms or rules out your hypothesis.

1. Switch to ES|QL mode in Discover (same as Part A, Step 1)

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

That's the full investigation workflow. Practice converting vague questions into structured query chains — it's the core skill for on-call incident analysis.

> **Coming up**: In [Lab 14](./labs-12-14-observability-resilience.md#lab-14-automating-investigation-workflows-with-a-genai-agent), you'll build a GenAI agent that automates this same investigation workflow. Keep your manual results — you'll compare them against the agent's output.

---

