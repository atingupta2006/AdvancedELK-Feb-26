# Module 05 – Intermediate ELK: Production Readiness (Labs)

Prereq: Module 02 completed (`web-logs-*`, `app-logs-*` available in Kibana).

---

## Lab 1: Create Custom Mappings
Objective: Create an index with explicit mappings for application log fields

> **Mappings** define how fields are stored and indexed. Without explicit mappings, Elasticsearch uses dynamic mapping (auto-detects types), which often picks suboptimal types — e.g., a numeric string becomes `text` instead of `integer`. Explicit mappings give you control over field types, analyzers, and storage.

1. Kibana: Open Dev Tools
```
Menu (☰) → Management → Dev Tools
```
2. Create an index with explicit mappings

> `keyword` fields are for exact matching and aggregations (no text analysis). `text` fields enable full-text search. Multi-fields (`.keyword` sub-field) give you both capabilities on the same field.

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

> `number_of_replicas: 0` is appropriate for single-node training environments. In production, set replicas ≥ 1 for fault tolerance.

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

> Check Index Management to confirm field types match your mapping. If a field shows `text` when you expected `keyword`, the mapping wasn't applied correctly.

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

> **Index templates** apply predefined settings and mappings to any new index whose name matches the template pattern. **Component templates** are reusable building blocks — you define common fields once and compose them into multiple index templates.

1. Kibana: Open Dev Tools
```
Menu (☰) → Management → Dev Tools
```
2. Create a component template (common fields)

> Component templates hold shared configuration. Here we define fields common across all training indices — `@timestamp`, `level`, `service`.

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

> `composed_of` pulls in component templates. `priority` determines which template wins when multiple templates match the same index pattern — higher value wins.

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

> Creating an index matching `training-app-*` should automatically apply both the component template fields and the index template mappings.

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

> `codec => json` tells Logstash each line is a complete JSON object (NDJSON format) — no grok parsing needed. The `date` filter replaces `@timestamp` with the log's own timestamp. The conditional tags ERROR events for easy filtering in Kibana.

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
		hosts => ["http://127.0.0.1:9200"]
		index => "training-app-pipeline-%{+YYYY.MM.dd}"
	}
}
```

> `sincedb_path => "/dev/null"` forces Logstash to re-read the file from the beginning every restart — useful for training but never use in production.

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

> **Beats modules** are pre-built configurations for common data sources. The `system` module for Filebeat collects system messages and auth logs; the `system` module for Metricbeat collects CPU, memory, disk, and network metrics — all with zero custom configuration.

1. Install Filebeat and Metricbeat
```bash
sudo dnf install -y filebeat metricbeat
```
2. Configure Filebeat (create in VSCode, then copy)
```bash
code ~/module05-filebeat.yml
```
Paste this content:

> This config disables direct file inputs and uses modules instead. `setup.kibana` tells Filebeat where to install dashboards and data views.

```yaml
filebeat.inputs: []

filebeat.config.modules:
  path: ${path.config}/modules.d/*.yml
  reload.enabled: false

setup.kibana:
  host: "http://127.0.0.1:5601"

output.elasticsearch:
  hosts: ["http://127.0.0.1:9200"]
```
Copy into place:
```bash
sudo cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bak 2>/dev/null || true
sudo cp ~/module05-filebeat.yml /etc/filebeat/filebeat.yml
```
3. Enable the system module and enable filesets (in VSCode)

> `filebeat modules enable system` creates a YAML config in `modules.d/`. We then enable specific filesets — the system messages fileset for `/var/log/messages` and `auth` for authentication events.

```bash
sudo filebeat modules enable system
sudo cp /etc/filebeat/modules.d/system.yml ~/module05-system.yml
code ~/module05-system.yml
```
In `~/module05-system.yml`, set:
- Under the syslog fileset section: `enabled: true`
- Under the auth fileset section: `enabled: true`

> On CentOS Stream 9, the syslog fileset reads from `/var/log/messages` (not `/var/log/syslog`).

Then copy it back:
```bash
sudo cp ~/module05-system.yml /etc/filebeat/modules.d/system.yml
```
4. Setup and start Filebeat

> `filebeat setup` installs index templates, ingest pipelines, and Kibana dashboards for enabled modules. Run this once per module.

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

> **Lens** supports multi-layer charts (overlay different metrics on the same visualization) and formulas (computed metrics like ratios). **TSVB** (Time Series Visual Builder) offers advanced time-series features like color rules, annotations, and multiple panel types.

1. Lens: Multi-layer time series (Total vs Errors)

> Multi-layer Lens charts overlay different datasets. Layer 1 shows total events. Layer 2 applies a filter to show only errors — making it easy to spot error spikes relative to traffic.

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

> Lens formulas let you compute ratios, percentages, and other derived metrics. `count(kql='...') / count()` calculates the error rate as a percentage.

```
In the same Lens (or a new one)
Metric: Formula
Formula: count(kql='level : "ERROR"') / count()
Format: Percent

Save as: M05 - App Error Rate
```
3. TSVB: Time series + threshold

> TSVB color rules change the chart line color when a metric crosses a threshold — visual alerting built into the chart itself.

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

> **Annotations** overlay events from a different index on top of a time series. Here we mark application errors on the CPU chart to correlate error spikes with resource usage.

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

> **Kibana alerting** runs server-side checks at defined intervals. When conditions are met, it triggers **actions** via **connectors** (Slack, email, server log, etc.). Rules evaluate queries against indices — no external monitoring tool needed.

1. Kibana: Create a connector (Server log)

> Connectors define where alert actions send notifications. The "Server log" connector writes to Kibana's own log — simplest option for training.

```
Menu (☰) → Management → Stack Management → Connectors → Create connector
Type: Server log
Name: M05 - Server log connector
Save
```
2. Kibana: Create an Index threshold rule

> Index threshold rules query an index on a schedule. When the aggregation result crosses the threshold, the rule fires and executes its configured actions.

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
