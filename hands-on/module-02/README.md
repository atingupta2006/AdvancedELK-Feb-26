# Module 02 – Data Ingestion & Indexing Pipelines

> **Stack Version**: Elasticsearch 9.x | Kibana 9.x | Filebeat 9.x | Logstash 9.x

Repo location used in class: `~/GH`

## 📖 Module Overview
In Module 01, we manually inserted JSON data. In the real world, you don't do that. You use **pipelines**. 

This module covers the "E" (Elasticsearch), "L" (Logstash), and "K" (Kibana) stack, plus "Beats". We will build a complete ingestion pipeline involving:
1.  **Filebeat**: The shipping agent.
2.  **Logstash**: The heavy processing engine.
3.  **Ingest Pipelines**: The lightweight processing engine inside Elasticsearch.
4.  **Data Streams**: The modern way to store logs.

---

## 🧠 Concepts & Architecture (Read First)

Before typing commands, understand the *objects* we are creating.

### 1. The Components
| Component | Role | Analogy | Use Case |
| :--- | :--- | :--- | :--- |
| **Filebeat** | **Shipper**. Reads files and sends them out. Lightweight. | The "Security Camera" that records and sends video. | Installed on every web server to read `/var/log/nginx/access.log`. |
| **Logstash** | **Processor**. Receives data, parses it, enhances it, sends it to ES. | The "Editing Studio" that cuts, colors, and labels the video. | masking PII (credit cards), looking up IP Geo-location, merging multi-line logs. |
| **Elasticsearch** | **Storage**. Indexes the data. | The "Library Archive" where video tapes are stored. | Storing expected 1TB of logs per day. |
| **Kibana** | **UI**. Visualizes the data. | The "TV Screen" to watch the video. | Dashboards, Alerts, Discovery. |

### 2. How Data is Stored: Index vs. Data Stream
The biggest confusion for beginners is "Where is my data?"

| Feature | **Index** | **Data Stream** |
| :--- | :--- | :--- |
| **Best For** | **Mutable Data**. Things that change. | **Immutable Data**. Things that never change. |
| **Examples** | User Profiles, Product Catalog, Inventory counts. | Web Logs, Metrics, Security Events, Application Traces. |
| **Updates?** | Yes, you can update ID: 123 ("John" -> "Johnny"). | No. You only append. You never go back and change a log from last Tuesday. |
| **Structure** | A single bucket (or manually managed rolling indices). | A virtual wrapper around many hidden backing indices (`.ds-logs-00001`). |
| **Why use it?** | Simple to manage for static datasets. | Handles massive scale automatically. Auto-deletes old data (ILM). |

### 3. The "Cookie Cutter": Index Templates
You cannot manually create every index for every day (`logs-2024-01-01`, `logs-2024-01-02`...).
*   **Index Template**: A rule that says "Any index starting with `logs-*` must have these mappings and settings."
*   **Why?**: Without a template, Elasticsearch guesses your data types (and often guesses wrong, treating numbers as text). **Data Streams REQUIRE a template to exist.**

### 4. The "Lens": Data Views
*   **Kibana Data View**: This does **not** store data. It is just a saved configuration that tells Kibana: *"When I click Discover, look at all indices matching `logs-*`."*

---

## Prerequisites (Module 00 → Module 01 completed)

- [Module 00](../module-00/README.md)
- [Module 01](../module-01/README.md)
- Elasticsearch: `http://127.0.0.1:9200`
- Kibana: `http://127.0.0.1:5601`

### Clean up Module 01 test data
> **Why?** The `app-logs` index created in Module 01 will conflict with the `app-logs-*` data view or stream we create here. We need a clean slate.

In Dev Tools (`Menu (☰) → Management → Dev Tools`):
```json
DELETE app-logs
```

---

## Lab 1: Configure Filebeat
**Use Case**: You have 100 web servers. You need to get their `access.log` files to a central place. You don't want to write scripts. You install Filebeat.

1. Go to Module 02 folder
```bash
cd ~/GH/hands-on/module-02
```
2. Install Filebeat + prepare data
> `dnf install` pulls Filebeat from the Elastic repo. We copy sample logs to simulate a real application writing to disk.

```bash
sudo dnf install -y filebeat
sudo mkdir -p /opt/elk-training/data/raw
sudo cp ../../data/raw/access.log /opt/elk-training/data/raw/
```
3. Install the provided Filebeat config
> **Concept**: `filebeat.yml` is the brain. It tells Filebeat *what* to read (inputs) and *where* to send it (output).

```bash
sudo cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bak 2>/dev/null || true
sudo cp ./filebeat.yml /etc/filebeat/filebeat.yml
sudo chown root:root /etc/filebeat/filebeat.yml
sudo chmod 600 /etc/filebeat/filebeat.yml
```
4. Enable and start Filebeat
```bash
sudo systemctl enable --now filebeat
```
5. Kibana: Data view + Discover
> **Concept**: Filebeat is sending data to `web-logs-2026.02.15`. We create a Data View `web-logs-*` to see it.

```
Menu (☰) → Management → Stack Management → Data Views → Create data view
Name: web-logs-*
Index pattern: web-logs-*
Timestamp field: @timestamp
Save
Menu (☰) → Analytics → Discover
Data view: web-logs-*
Time picker: Last 7 days (Ensure it covers Feb 9, 2026)
```
**Success**: Web logs appear in Discover. **Note**: They are unparsed (the whole line is in `message`).

---

## Lab 2: Build Logstash Pipeline
**Use Case**: Your logs are messy. You have "Web Logs" (Combined Apache Format) and "App Logs" (JSON). You need to separate them and parse them differently. Filebeat is too simple for this logic. Enter Logstash.

1. Install Logstash
```bash
sudo dnf install -y logstash
```
2. Copy sample app log
```bash
sudo cp ../../data/raw/app.log /opt/elk-training/data/raw/
```
3. Open and review pipeline file
> **Concept**: A Logstash pipeline has 3 stages:
> 1.  **Input**: Receive data (from Filebeat on port 5044).
> 2.  **Filter**: The magic. Use `grok` to extract fields, `date` to fix timestamps.
> 3.  **Output**: Send to Elasticsearch (or S3, or Kafka).

```
Open: ~/GH/hands-on/module-02/logstash.conf
```
4. Install pipeline config
```bash
sudo cp ./logstash.conf /etc/logstash/conf.d/elk-training.conf
sudo chown logstash:logstash /etc/logstash/conf.d/elk-training.conf
```
5. Enable and start Logstash
```bash
sudo systemctl enable --now logstash
```

6. Re-configure Filebeat to ship to Logstash
> **Why?**: We are changing the architecture. Instead of Filebeat -> Elasticsearch, we now do Filebeat -> Logstash -> Elasticsearch.

```bash
code ~/GH/hands-on/module-02/filebeat.yml
```
*   Change: `id: app-json` input enabled: `false` → `true`
*   Change outputs:
    *   **Comment out** the entire `output.elasticsearch:` block.
    *   **Uncomment** the `output.logstash:` block at the bottom.

7. Install updated Filebeat config & Restart
```bash
sudo cp ./filebeat.yml /etc/filebeat/filebeat.yml
sudo systemctl restart filebeat
```
8. Kibana: Data view + Discover
> Create a view for the new app logs.
```
Menu (☰) → Management → Stack Management → Data Views → Create data view
Name: app-logs-*
Index pattern: app-logs-*
Timestamp field: @timestamp
Save
Menu (☰) → Analytics → Discover
Data view: app-logs-*
```
**Success**: You now see parsed application logs.

---

## Lab 3: Advanced Logstash Filters
**Use Case**: "Parsing" isn't enough. You want **Enrichment**.
*   **GeoIP**: Convert "192.168.1.5" into "location: Paris, France".
*   **User Agent**: Convert "Mozilla/5.0..." into "Browser: Chrome, OS: Windows".
*   **Business Logic**: "If status is 500, tag it as 'critical_failure'".

1. Edit the Logstash pipeline in VSCode
```bash
sudo cp /etc/logstash/conf.d/elk-training.conf ~/module02-elk-training.conf
code ~/module02-elk-training.conf
```
2. Replace the `filter { ... }` section with this code:

> **What this does**:
> *   `if [log_type] == "web"`: Only apply the expensive GeoIP lookup to web traffic.
> *   `grok`: Extracts IP, Method, URL from the raw text line.
> *   `geoip`: Adds location data based on the IP.
> *   `mutate`: Removes the raw `message` field to save disk space (since we extracted the data).

```conf
filter {
  if [log_type] == "web" {
    grok { match => { "message" => '%{IPORHOST:client_ip} %{USER:ident} %{USER:auth} \[%{HTTPDATE:timestamp}\] "(?:%{WORD:method} %{NOTSPACE:path}(?: HTTP/%{NUMBER:http_version})?|%{DATA:raw_request})" %{NUMBER:status:int} (?:%{NUMBER:bytes:int}|-) %{QS:referrer} %{QS:user_agent}' } }
    date { match => ["timestamp", "dd/MMM/yyyy:HH:mm:ss Z"] target => "@timestamp" }
    geoip {
      source => "client_ip"
      target => "geoip"
      ecs_compatibility => disabled
    }
    mutate { remove_field => ["message", "timestamp"] add_field => { "index_prefix" => "web-logs" } }
  }
  if [log_type] == "app" {
    date { match => ["timestamp", "ISO8601"] target => "@timestamp" }
    if [level] == "ERROR" { mutate { add_tag => ["error_event"] } }
    mutate { remove_field => ["timestamp"] add_field => { "index_prefix" => "app-logs" } }
  }
}
```

3. Copy back and restart
```bash
sudo cp ~/module02-elk-training.conf /etc/logstash/conf.d/elk-training.conf
sudo systemctl restart logstash
# Restart Filebeat to force it to re-send or pick up new files if configured
sudo systemctl restart filebeat
```
4. Kibana Verify
*   Go to Discover.
*   Look at `web-logs-*`. Expand a document.
*   **Success**: You should see a `geoip` object with city/country names.

---

## Lab 4: Create Data Stream
**Use Case**: You are now logging 1TB/day. A single index `web-logs-2026.02.15` is too big. You need to split it into smaller chunks (`00001`, `00002`) automatically. You want to delete data older than 30 days automatically. **You need Data Streams.**

1. Kibana: Create Index Template (MANDATORY)
> **Why?** A Data Stream is just a name. It needs a template to know how to create the backing indices. The key line is `"data_stream": {}`. This template acts as the blueprint for any newly created backing index.

```json
PUT _index_template/training-web-ds
{
  "index_patterns": ["training-web"],
  "data_stream": {},
  "template": {
    "mappings": {
      "properties": {
        "@timestamp": {"type": "date"},
        "client_ip": {"type": "ip"}
      }
    }
  }
}
```
2. Create data stream
> Only after the template exists can we initialize the stream.
```json
PUT _data_stream/training-web
```
3. Ingest one event
> **Critical Concept**: You cannot update documents in a data stream easily. You MUST use `POST` (append only). And `op_type=create` forces a new document creation.
```json
POST training-web/_doc?op_type=create
{
  "@timestamp": "2026-02-09T10:15:23Z",
  "client_ip": "192.168.1.100",
  "message": "data stream test"
}
```
4. Verify
*   Go to **Stack Management > Index Management > Data Streams**.
*   You will see `training-web` is GREEN.
*   Click it to see the backing index name (e.g., `.ds-training-web-2026.02.15-000001`). This confirms the abstraction is working; you wrote to `training-web` but the data landed in a managed backing index.

---

## Lab 5: Build Ingest Pipeline
**Use Case**: You realize Logstash is heavy. It uses lots of RAM. You want to do simple parsing (like breaking a line into fields) *inside* Elasticsearch to save money and complexity.

> **Ingest Pipeline vs. Logstash**:
> *   **Ingest Pipeline**: Runs on the Elasticsearch node. Fast, simple, no extra servers to manage. Great for cloud setups.
> *   **Logstash**: Runs separately. Infinite flexibility, buffers data to protect ES from overload, can crash without stopping ES.

1. Create ingest pipeline
> This defines a series of processors (grok -> date -> set) that happen *before* the document is written to disk.
```json
PUT _ingest/pipeline/web-access-pipeline
```
(Paste the JSON body from `~/GH/hands-on/module-02/ingest-pipeline.json` into the request body)

2. Simulate
> **Why?** Debugging regex is hard. `_simulate` lets you test your pipeline against one fake document to see if it works without polluting your real index.
```json
POST _ingest/pipeline/web-access-pipeline/_simulate
{
  "docs": [
    {
      "_source": {
        "message": "192.168.1.100 - - [09/Feb/2026:10:15:23 +0000] \"GET /api/products HTTP/1.1\" 200 1234 \"-\" \"Mozilla/5.0\""
      }
    }
  ]
}
```
3. Index using pipeline
> Note the URL parameter `?pipeline=web-access-pipeline`. This tells ES "Do not just store this JSON. Run it through the pipeline first."
```json
POST web-logs-ingest/_doc?pipeline=web-access-pipeline
{
  "message": "192.168.1.100 - - [09/Feb/2026:10:15:23 +0000] \"GET /api/products HTTP/1.1\" 200 1234 \"-\" \"Mozilla/5.0\""
}
```
4. Verify in Discover
*   Create Data View `web-logs-ingest*`.
*   You will see parsed fields, just like Logstash produced, but done entirely inside Elasticsearch.
