# Module 05 – Intermediate ELK: Production Readiness (Labs)

> **Stack Version**: Elasticsearch 9.x | Kibana 9.x | Logstash 9.x | Beats 9.x

Repo location used in class: `~/GH`

## 📖 Module Overview
In the previous modules, we learned the basics of ingestion and visualization. Now we move to **Production Readiness**.

This module bridges the gap between "it works on my laptop" and "it runs in production". We will cover:
1.  **Explicit Mappings**: Stop letting Elasticsearch guess your data types.
2.  **Templates**: Automate your index settings.
3.  **Advanced Logstash**: Conditional parsing and error handling.
4.  **Beats Modules**: The "Easy Button" for System and Metric data.
5.  **Alerting**: Moving from "Looking at Dashboards" to "Getting Notified".

---

## 🧠 Concepts & Architecture (Read First)

### 1. The "Mapping" Problem
*   **Dynamic Mapping (Default)**: Elasticsearch guesses.
    *   `"id": "123"` -> Guessed as `text`. Bad for sorting.
    *   `"ip": "10.0.0.1"` -> Guessed as `text`. Cannot do CIDR searches.
*   **Explicit Mapping (Production)**: You define the rules.
    *   `"id"` -> `keyword`.
    *   `"ip"` -> `ip`.

### 2. Component Templates
Think of these as "LEGO blocks" for your indices.
*   **Block A**: `settings-production` (1 replica, 30s refresh).
*   **Block B**: `mappings-web-logs` (IP, Status, Method).
*   **Index Template**: Combines `Block A` + `Block B` to engage whenever an index matching `logs-web-*` is created.

### 3. Monitoring Architecture
We will install **Filebeat** (Logs) and **Metricbeat** (CPU/RAM) on the Linux server. They will ship data to Elasticsearch, and we will use pre-built dashboards to visualize it.

---

## Prerequisites
- [Module 02](../module-02/README.md) completed.
- Kibana: `http://127.0.0.1:5601`

---

## Lab 1: Create Custom Mappings
**Use Case**: You have a JSON log with an `amount` field. Dynamic mapping guesses it is `text`, so you cannot calculate the "Average Amount". You must fix this.

1. **Open Dev Tools**
   *   Menu (☰) → **Management** → **Dev Tools**.

2. **Define the Mapping**
   *   **Concept**: We are telling ES exactly what each field is. "keyword" for exact match (Ids, status), "text" for search (messages), "double" for math (money).

```json
PUT training-app-custom-000001
{
  "settings": { "number_of_shards": 1, "number_of_replicas": 0 },
  "mappings": {
    "properties": {
      "timestamp": { "type": "date" },
      "level": { "type": "keyword" },
      "service": { "type": "keyword" },
      "message": {
        "type": "text",
        "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
      },
      "error": { "type": "keyword" },
      "amount": { "type": "double" },
      "currency": { "type": "keyword" }
    }
  }
}
```

3. **Index a Document**
   *   We verify it works by adding data.

```json
POST training-app-custom-000001/_doc
{
  "timestamp": "2026-02-09T10:15:28Z",
  "level": "ERROR",
  "service": "payment-service",
  "message": "Payment processing failed",
  "error": "Timeout",
  "amount": 99.99,
  "currency": "USD"
}
```

4. **Verify in Kibana**
   *   Go to **Stack Management** → **Index Management**.
   *   Click `training-app-custom-000001` → **Mappings**.
   *   **Check**: Does `amount` show as `double`? If yes, Success.

---

## Lab 2: Configure Index Templates
**Use Case**: You don't want to run that `PUT` command every day for `logs-2026-01-01`, `logs-2026-01-02`. You want it automatic.

1. **Create Component Template (The "Base")**
   *   This block holds settings common to ALL your apps.

```json
PUT _component_template/training-app-common
{
  "template": {
    "settings": { "number_of_shards": 1, "number_of_replicas": 0 },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "level": { "type": "keyword" },
        "service": { "type": "keyword" }
      }
    }
  }
}
```

2. **Create Index Template (The "Rule")**
   *   This rule says: "Any index starting with `training-app-*` gets the common settings AND these specific message mappings."

```json
PUT _index_template/training-app-template
{
  "index_patterns": ["training-app-*"],
  "priority": 500,
  "composed_of": ["training-app-common"],
  "template": {
    "mappings": {
      "properties": {
        "message": {
          "type": "text",
          "fields": {
            "keyword": { "type": "keyword", "ignore_above": 256 }
          }
        }
      }
    }
  }
}
```

3. **Test It**
   *   Create a *new* index that matches the pattern.

```json
PUT training-app-test-000001
```

4. **Verify**
   *   Get the mapping. It should have `level` (from component) and `message` (from template).

```json
GET training-app-test-000001/_mapping
```

---

## Lab 3: Build Advanced Logstash Pipeline
**Use Case**: Complex logic. "If the log is ERROR, tag it 'urgent'. If it is DEBUG, drop it."

1. **Prepare Data**
```bash
# Ensure logstash is installed
sudo dnf install -y logstash
# Copy sample log
sudo cp ~/GH/data/raw/app.log /opt/elk-training/data/raw/
```

2. **Create Pipeline Config**
```bash
code ~/module05-advanced.conf
```
   *   **Logic**:
       *   `input`: Read the file. `codec => json` because it is NDJSON.
       *   `filter`: Parse the date. **Conditional**: If level is ERROR, add a tag.
       *   `output`: Send to ES with a dynamic index name `training-app-pipeline-YYYY.MM.dd`.

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
    mutate { add_tag => ["urgent_attention"] }
  }
}

output {
  elasticsearch {
    hosts => ["http://127.0.0.1:9200"]
    index => "training-app-pipeline-%{+YYYY.MM.dd}"
  }
}
```

3. **Deploy & Run**
```bash
sudo cp ~/module05-advanced.conf /etc/logstash/conf.d/
sudo systemctl restart logstash
```

4. **Verify in Kibana**
   *   Create Data View `training-app-pipeline-*`.
   *   Discover: Filter for `tags: urgent_attention`.
   *   **Success**: Only ERROR logs appear.

---

## Lab 4: Configure Beats & Modules
**Use Case**: "I want to see CPU usage and System Logs. I don't want to write a config file." -> Use Modules.

1. **Install Beats**
```bash
sudo dnf install -y filebeat metricbeat
```

2. **Configure Output (Filebeat)**
   *   We point Filebeat to Kibana (for dashboards) and ES (for data).
```bash
# Backup default
sudo cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bak
```

- Edit /etc/filebeat/filebeat.yml

```yaml
filebeat.config.modules:
  path: ${path.config}/modules.d/*.yml
  reload.enabled: false

setup.kibana:
  host: "http://127.0.0.1:5601"

output.elasticsearch:
  hosts: ["http://127.0.0.1:9200"]
```

3. **Enable System Module**
   *   This turns on the "System" collector (syslog + auth).
```bash
sudo filebeat modules enable system
```

4. **Setup & Start**
   *   `setup` loads the pre-built Dashboards into Kibana.
```bash
sudo filebeat setup
sudo systemctl enable --now filebeat
```

5. **Repeat for Metricbeat (CPU/Ram)**
```bash
sudo metricbeat modules enable system
sudo metricbeat setup
sudo systemctl enable --now metricbeat
```

6. **Verify**
   *   Kibana → **Analytics** → **Dashboard**.
   *   Search **"[Metricbeat System] Host overview"**.
   *   **Success**: You see live CPU/Memory graphs of your VM.

---

## Lab 5: Alerting
**Use Case**: "Email me if Error Rate > 5%".

1. **Create Connector**
   *   Menu (☰) → **Stack Management** → **Connectors**.
   *   Create wrapper **Server Log**
   *   Name: `Server Log Output`.

2. **Create Rule**
   *   Menu (☰) → **Stack Management** → **Rules**.
   *   **Create rule**.
   *   Name: `High Error Rate`.
   *   Type: **Index threshold**.
   *   Index: `training-app-pipeline-*`.
   *   **Condition**:
       *   WHEN `count`
       *   OF `level.keyword: ERROR` (Use KQL)
       *   IS ABOVE `0` (For testing: alert on ANY error).
       *   FOR THE LAST `5 minutes`.

3. **Action**
   *   Add Action → Select `Server Log Output`.
   *   Message: `ALERT: Errors detected in application logs!`.

4. **Test**
   *   Wait 1 minute.
   *   Check Rule details in UI to see "Active Alerts".

**Success**: You have built a full monitoring loop: Ingest -> Visualize -> Alert.
