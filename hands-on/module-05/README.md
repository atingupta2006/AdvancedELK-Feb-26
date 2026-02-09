# Module 05 – Intermediate ELK: Production Readiness (Labs)

Prereq: Module 02 completed (`web-logs-*`, `app-logs-*` available in Kibana).

---

## Lab 1: Create Custom Mappings
Objective: Create an index with explicit mappings for application log fields

1. Kibana: Open Dev Tools
```
Menu (☰) → Management → Dev Tools
```
2. Create an index with explicit mappings
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
			"order_id": { "type": "keyword" },
			"amount": { "type": "double" },
			"currency": { "type": "keyword" }
		}
	}
}
```
3. Index one sample document
```json
POST training-app-custom-000001/_doc
{
	"timestamp": "2026-02-09T10:15:28Z",
	"level": "ERROR",
	"service": "payment-service",
	"message": "Payment processing failed",
	"error": "Timeout",
	"order_id": "order_654",
	"amount": 99.99,
	"currency": "USD"
}
```
4. Kibana: Verify mapping and document
```
Menu (☰) → Management → Stack Management → Index Management → Indices
Open: training-app-custom-000001 → Mappings

Menu (☰) → Management → Stack Management → Data Views → Create data view
Name: training-app-custom-*
Index pattern: training-app-custom-*
Timestamp field: timestamp
Save

Menu (☰) → Analytics → Discover
Data view: training-app-custom-*
```
Success: Index exists with explicit field types

---

## Lab 2: Configure Index Templates
Objective: Apply consistent mappings/settings automatically to new indices

1. Kibana: Open Dev Tools
```
Menu (☰) → Management → Dev Tools
```
2. Create a component template (common fields)
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
3. Create an index template that uses the component template
```json
PUT _index_template/training-app-template
{
	"index_patterns": ["training-app-*"],
	"priority": 501,
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
4. Test: Create a new index that matches the pattern
```json
PUT training-app-test-000001
```
5. Kibana: Verify template application
```
Menu (☰) → Management → Stack Management → Index Management → Indices
Open: training-app-test-000001 → Mappings

Menu (☰) → Management → Stack Management → Index Management → Index Templates
Search: training-app-template
```
Success: New `training-app-*` indices inherit mappings/settings

---

## Lab 3: Build Advanced Logstash Pipeline
Objective: Parse NDJSON logs, add conditional enrichment, index into a template-backed index

1. Install Logstash and prepare app log
```bash
sudo dnf install -y logstash
sudo mkdir -p /opt/elk-training/data/raw
cd ~/GH
sudo cp ./data/raw/app.log /opt/elk-training/data/raw/
```
2. Create a Logstash pipeline config in VSCode
```bash
code ~/module05-logstash-advanced.conf
```
Paste this content:
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
	if [level] == "ERROR" { mutate { add_tag => ["error_event"] } }
}

output {
	elasticsearch {
		hosts => ["http://localhost:9200"]
		index => "training-app-pipeline-%{+YYYY.MM.dd}"
	}
}
```
3. Copy the pipeline into Logstash config directory
```bash
sudo cp ~/module05-logstash-advanced.conf /etc/logstash/conf.d/module05-advanced.conf
```
4. Start Logstash
```bash
sudo systemctl enable --now logstash
sudo systemctl restart logstash
```
5. Kibana: Verify parsed/enriched fields
```
Menu (☰) → Management → Stack Management → Data Views → Create data view
Name: training-app-pipeline-*
Index pattern: training-app-pipeline-*
Timestamp field: @timestamp
Save

Menu (☰) → Analytics → Discover
Data view: training-app-pipeline-*
KQL: tags : "error_event"
```
Success: Logs are parsed and enriched into `training-app-pipeline-*`

---

## Lab 4: Configure Beats for Monitoring
Objective: Ship system logs and metrics using Filebeat + Metricbeat modules

1. Install Filebeat and Metricbeat
```bash
sudo dnf install -y filebeat metricbeat
```
2. Configure Filebeat (create in VSCode, then copy)
```bash
code ~/module05-filebeat.yml
```
Paste this content:
```yaml
filebeat.inputs: []

filebeat.config.modules:
  path: ${path.config}/modules.d/*.yml
  reload.enabled: false

setup.kibana:
  host: "http://localhost:5601"

output.elasticsearch:
  hosts: ["http://localhost:9200"]
```
Copy into place:
```bash
sudo cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bak 2>/dev/null || true
sudo cp ~/module05-filebeat.yml /etc/filebeat/filebeat.yml
```
3. Enable the system module and enable filesets (in VSCode)
```bash
sudo filebeat modules enable system
sudo cp /etc/filebeat/modules.d/system.yml ~/module05-system.yml
code ~/module05-system.yml
```
In `~/module05-system.yml`, set:
- `syslog.enabled: true`
- `auth.enabled: true`

Then copy it back:
```bash
sudo cp ~/module05-system.yml /etc/filebeat/modules.d/system.yml
```
4. Setup and start Filebeat
```bash
sudo filebeat setup -e
sudo systemctl enable --now filebeat
```
5. Enable Metricbeat system module, setup, and start
```bash
sudo metricbeat modules enable system
sudo metricbeat setup -e
sudo systemctl enable --now metricbeat
```
6. Kibana: Verify system logs + metrics
```
Menu (☰) → Management → Stack Management → Data Views → Create data view
Name: filebeat-*
Index pattern: filebeat-*
Timestamp field: @timestamp
Save

Menu (☰) → Management → Stack Management → Data Views → Create data view
Name: metricbeat-*
Index pattern: metricbeat-*
Timestamp field: @timestamp
Save

Menu (☰) → Analytics → Discover
Data view: filebeat-*
Data view: metricbeat-*
```
Success: Filebeat + Metricbeat data is visible in Discover

---

## Lab 5: Advanced Visualizations with Lens and TSVB
Objective: Build a layered Lens chart and a TSVB time series with thresholds + annotations

1. Lens: Multi-layer time series (Total vs Errors)
```
Menu (☰) → Analytics → Visualize Library → Create visualization → Lens
Data view: training-app-pipeline-*

Visualization: Line
Horizontal axis: @timestamp (Date histogram)

Layer 1
Metric: Count of records

Layer 2
Metric: Count of records
Filter (layer): level : "ERROR"

Save as: M05 - App Events (Total vs Errors)
```
2. Lens: Formula (Error rate)
```
In the same Lens (or a new one)
Metric: Formula
Formula: count(kql='level : "ERROR"') / count()
Format: Percent

Save as: M05 - App Error Rate
```
3. TSVB: Time series + threshold
```
Menu (☰) → Analytics → Visualize Library → Create visualization → TSVB
Index pattern: metricbeat-*
Time field: @timestamp

Visualization type: Time Series
Series aggregation: Average
Field: system.cpu.total.norm.pct

Panel options → Color rules
Add rule: if value is above 0.80 then red

Save as: M05 - CPU Usage (TSVB)
```
4. TSVB: Add annotations from application errors
```
Edit: M05 - CPU Usage (TSVB)
Annotations → Add annotation
Index pattern: training-app-pipeline-*
Time field: @timestamp
Query: level : "ERROR"
Fields: message

Save
```
Success: Lens + TSVB visuals saved and show meaningful trends

---

## Lab 6: Configure Alerting Rules
Objective: Create a threshold-based rule that triggers on application errors and logs an action

1. Kibana: Create a connector (Server log)
```
Menu (☰) → Management → Stack Management → Connectors → Create connector
Type: Server log
Name: M05 - Server log connector
Save
```
2. Kibana: Create an Index threshold rule
```
Menu (☰) → Management → Stack Management → Rules → Create rule
Rule type: Index threshold
Name: M05 - App Errors Detected

Indices to query: training-app-pipeline-*
Time field: @timestamp

WHEN: count
OVER: all documents
THRESHOLD: is above 0
FOR THE LAST: 1 hour
KQL: level : "ERROR"
Check every: 1 minute
```
3. Add an action
```
Actions → Add action
Connector: M05 - Server log connector
Action frequency: On each check interval
Message: {{context.message}}
Save
```
4. Kibana: Verify alerts
```
Menu (☰) → Management → Stack Management → Rules
Open: M05 - App Errors Detected
Check: rule status and alerts
```
Success: Rule generates alerts based on existing error events
