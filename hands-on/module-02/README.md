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

1. Go to Module 02 folder
```bash
cd ~/GH/hands-on/module-02
```
2. Install Filebeat + prepare data
```bash
sudo dnf install -y filebeat
sudo mkdir -p /opt/elk-training/data/raw
sudo cp ../../data/raw/access.log /opt/elk-training/data/raw/
```
3. Install the provided Filebeat config
```bash
sudo cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bak 2>/dev/null || true
sudo cp ./filebeat.yml /etc/filebeat/filebeat.yml
```
4. Enable and start Filebeat
```bash
sudo systemctl enable --now filebeat
```
5. Kibana: Data view + Discover
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

1. Install Logstash
```bash
sudo dnf install -y logstash
```
2. Copy sample app log
```bash
sudo cp ../../data/raw/app.log /opt/elk-training/data/raw/
```
3. Open and review pipeline file
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

```
Open: ~/GH/hands-on/module-02/filebeat.yml
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

1. Edit the Logstash pipeline in VSCode
```bash
sudo cp /etc/logstash/conf.d/elk-training.conf ~/module02-elk-training.conf
code ~/module02-elk-training.conf
```
2. Replace the `filter { ... }` section with this
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

1. Kibana: Dev Tools
```
Menu (☰) → Management → Dev Tools
```
2. Create index template
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
```json
PUT _data_stream/training-web
```
4. Ingest one event
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

1. Kibana: Dev Tools
```
Menu (☰) → Management → Dev Tools
```
2. Create ingest pipeline

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
