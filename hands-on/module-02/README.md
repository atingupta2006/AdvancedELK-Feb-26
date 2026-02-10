# Module 02 – Data Ingestion & Indexing Pipelines (Labs)

> **Stack Version**: Elasticsearch 9.x | Kibana 9.x | Filebeat 9.x | Logstash 9.x

Repo location used in class: `~/GH`

## Prerequisites (Module 00 → Module 01 completed)

Complete these first:

- [Module 00](../module-00/README.md)
- [Module 01](../module-01/README.md)

- Elasticsearch: `http://localhost:9200`
- Kibana: `http://localhost:5601`
- Security disabled (HTTP, no username/password)

---

## Lab 1: Configure Filebeat
**Objective**: Set up Filebeat to collect web server logs

> **Filebeat** is a lightweight log shipper from Elastic. It tails log files and sends events directly to Elasticsearch (or Logstash). It's the simplest way to get log data into the ELK stack.

1. Go to Module 02 folder
```bash
cd ~/GH/hands-on/module-02
```
2. Install Filebeat + prepare data

> `dnf install` pulls Filebeat from the Elastic repo configured in Module 00. We copy sample logs to a known path for Filebeat to monitor.

```bash
sudo dnf install -y filebeat
sudo mkdir -p /opt/elk-training/data/raw
sudo cp ../../data/raw/access.log /opt/elk-training/data/raw/
```
3. Install the provided Filebeat config

> We back up the default config first, then replace it with our pre-configured `filebeat.yml` that points to the sample log files.

```bash
sudo cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bak 2>/dev/null || true
sudo cp ./filebeat.yml /etc/filebeat/filebeat.yml
```
4. Enable and start Filebeat

> `enable --now` both enables the service on boot and starts it immediately.

```bash
sudo systemctl enable --now filebeat
```
5. Kibana: Data view + Discover

> Create a data view so Kibana knows which index pattern to query. Filebeat writes to indices matching `web-logs-*`.

```
Menu (☰) → Management → Stack Management → Data Views → Create data view
Name: web-logs-*
Index pattern: web-logs-*
Timestamp field: @timestamp
Save
Menu (☰) → Analytics → Discover
Data view: web-logs-*
Time picker: Last 24 hours
```
**Success**: Web logs appear in Discover

---

## Lab 2: Build Logstash Pipeline
**Objective**: Create Logstash pipeline for application logs

> **Logstash** is a server-side data processing pipeline. Unlike Filebeat (which ships raw logs), Logstash can parse, transform, and enrich data using filters before sending it to Elasticsearch.

1. Install Logstash
```bash
sudo dnf install -y logstash
```
2. Copy sample app log
```bash
sudo cp ../../data/raw/app.log /opt/elk-training/data/raw/
```
3. Open and review pipeline file

> A Logstash pipeline has three sections: `input` (where data comes from), `filter` (how to parse/transform), and `output` (where to send results).

```
Open: ~/GH/hands-on/module-02/logstash.conf
```
4. Install pipeline config
```bash
sudo cp ./logstash.conf /etc/logstash/conf.d/elk-training.conf
```
5. Enable and start Logstash
```bash
sudo systemctl enable --now logstash
```

6. Update Filebeat config in VS Code

> We reconfigure Filebeat to send app logs through Logstash instead of directly to Elasticsearch. This lets Logstash apply filters before indexing.

```bash
code ~/GH/hands-on/module-02/filebeat.yml
```
Change: app input enabled: false → true

Change: ship to Logstash (comment/uncomment)
  - Comment out the entire output.elasticsearch: block
  - Uncomment the output.logstash: block at the bottom
```

7. Install updated Filebeat config
```bash
sudo cp ./filebeat.yml /etc/filebeat/filebeat.yml
```

8. Restart Filebeat
```bash
sudo systemctl restart filebeat
```
9. Kibana: Data view + Discover
```
Menu (☰) → Management → Stack Management → Data Views → Create data view
Name: app-logs-*
Index pattern: app-logs-*
Timestamp field: @timestamp
Save
Menu (☰) → Analytics → Discover
Data view: app-logs-*
Time picker: Last 24 hours
```
**Success**: Parsed application logs appear in Discover

---

## Lab 3: Advanced Logstash Filters
**Objective**: Apply multiple filters for data enrichment

> Logstash filters transform raw log data into structured fields. **Grok** extracts fields using patterns, **date** parses timestamps, **geoip** adds geographic data from IP addresses, and **mutate** renames/removes fields.

1. Edit the Logstash pipeline in VSCode
```bash
sudo cp /etc/logstash/conf.d/elk-training.conf ~/module02-elk-training.conf
code ~/module02-elk-training.conf
```
2. Replace the `filter { ... }` section with this

> This filter uses conditionals (`if [log_type]`) to apply different parsing logic per log type. Web logs get grok + geoip; app logs get date parsing + error tagging.

```conf
filter {
  if [log_type] == "web" {
    grok { match => { "message" => '%{IPORHOST:client_ip} %{USER:ident} %{USER:auth} \[%{HTTPDATE:timestamp}\] "(?:%{WORD:method} %{NOTSPACE:path}(?: HTTP/%{NUMBER:http_version})?|%{DATA:raw_request})" %{NUMBER:status:int} (?:%{NUMBER:bytes:int}|-) %{QS:referrer} %{QS:user_agent}' } }
    date { match => ["timestamp", "dd/MMM/yyyy:HH:mm:ss Z"] target => "@timestamp" }
    geoip { source => "client_ip" }
    mutate { remove_field => ["message", "timestamp"] add_field => { "index_prefix" => "web-logs" } }
  }
  if [log_type] == "app" {
    date { match => ["timestamp", "ISO8601"] target => "@timestamp" }
    if [level] == "ERROR" { mutate { add_tag => ["error_event"] } }
    mutate { remove_field => ["timestamp"] add_field => { "index_prefix" => "app-logs" } }
  }
}
```
3. Copy the updated file back and restart Logstash
```bash
sudo cp ~/module02-elk-training.conf /etc/logstash/conf.d/elk-training.conf
sudo systemctl restart logstash
```
4. Restart Filebeat
```bash
sudo systemctl restart filebeat
```
5. Kibana: Verify enrichment
```
Menu (☰) → Analytics → Discover
Data view: web-logs-*
Add columns: client_ip, status
Data view: app-logs-*
KQL: tags : "error_event"
```
**Success**: Enriched fields and tags visible in Discover

---

## Lab 4: Create Data Stream
**Objective**: Set up data stream for time-series data

> A **data stream** is an append-only abstraction over multiple backing indices. It's designed for time-series data (logs, metrics) where you write new events but rarely update old ones. Elasticsearch handles index rollover automatically.

1. Kibana: Dev Tools
```
Menu (☰) → Management → Dev Tools
```
2. Create index template

> Data streams require an index template with `"data_stream": {}` enabled. The template defines mappings that apply to all backing indices.

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
3. Create data stream

> `PUT _data_stream/<name>` initializes the data stream and creates the first backing index.

```json
PUT _data_stream/training-web
```
4. Ingest one event

> Data streams only support `op_type=create` (append). You cannot use `PUT` or update individual documents — by design, they are immutable.

```json
POST training-web/_doc?op_type=create
{
  "@timestamp": "2026-02-09T10:15:23Z",
  "client_ip": "192.168.1.100",
  "message": "data stream test"
}
```
5. Kibana: Data view + Discover
```
Menu (☰) → Management → Stack Management → Data Views → Create data view
Name: training-web
Index pattern: training-web
Timestamp field: @timestamp
Save
Menu (☰) → Analytics → Discover
Data view: training-web
```
**Success**: Data stream visible in Stack Management and Discover

---

## Lab 5: Build Ingest Pipeline
**Objective**: Create and use ingest pipeline in Elasticsearch

> **Ingest pipelines** run inside Elasticsearch (not Logstash). They apply processors (grok, date, set, etc.) to documents at index time. They're lighter than Logstash and useful when you don't need Logstash's input/output flexibility.

1. Kibana: Dev Tools
```
Menu (☰) → Management → Dev Tools
```
2. Create ingest pipeline

> Each processor in the pipeline runs sequentially. Here: grok extracts fields from the raw message, date parses the timestamp, and set adds a tag.

```json
PUT _ingest/pipeline/web-access-pipeline
```

```
Paste the JSON body from: ~/GH/hands-on/module-02/ingest-pipeline.json
```

Optional (curl) apply pipeline from file
```bash
curl -s -H 'Content-Type: application/json' -X PUT \
  http://localhost:9200/_ingest/pipeline/web-access-pipeline \
  --data-binary @ingest-pipeline.json | cat
```
3. Simulate

> `_simulate` tests the pipeline against sample documents without actually indexing. Use this to debug processor logic before going live.

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
4. Index using pipeline

> `?pipeline=web-access-pipeline` tells Elasticsearch to run this document through the pipeline before indexing.

```json
POST web-logs-ingest/_doc?pipeline=web-access-pipeline
{
  "message": "192.168.1.100 - - [09/Feb/2026:10:15:23 +0000] \"GET /api/products HTTP/1.1\" 200 1234 \"-\" \"Mozilla/5.0\""
}
```
5. Kibana: Data view + Discover
```
Menu (☰) → Management → Stack Management → Data Views → Create data view
Name: web-logs-ingest*
Index pattern: web-logs-ingest*
Timestamp field: @timestamp
Save
Menu (☰) → Analytics → Discover
Data view: web-logs-ingest*
```
**Success**: Data processed through ingest pipeline and visible in Discover
