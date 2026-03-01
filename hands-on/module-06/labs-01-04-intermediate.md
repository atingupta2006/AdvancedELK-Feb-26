# Module 06 - Labs 01-04

## Querying, Visualizations, Logstash, Alert Workflows

---

## Lab 1: Advanced Querying & Optimization

**Objective**: Master complex bool queries, aggregation tuning, and query performance optimization

> In Module 03, we covered basic bool queries and aggregations. Production workloads demand deeper control: nested bool logic, filtered aggregations, and profiling slow queries to make data-driven tuning decisions.

1. Open Dev Tools

```
Menu (☰) → Management → Dev Tools
```

2. Complex nested bool query

> Real investigations require layered logic. This query says: "Give me all requests to the API that either failed (5xx) or were slow (large response body), but exclude health checks."

```json
GET web-logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "prefix": { "path.keyword": "/api" } }
      ],
      "should": [
        { "range": { "status": { "gte": 500 } } },
        { "range": { "bytes": { "gte": 5000 } } }
      ],
      "minimum_should_match": 1,
      "must_not": [
        { "term": { "path.keyword": "/api/health" } }
      ]
    }
  }
}
```

3. Aggregation with filters bucket

> `filters` aggregation lets you create named buckets for different conditions — like creating multiple KQL queries in one request.

```json
GET web-logs-*/_search
{
  "size": 0,
  "aggs": {
    "status_categories": {
      "filters": {
        "filters": {
          "success": { "range": { "status": { "gte": 200, "lt": 300 } } },
          "client_error": { "range": { "status": { "gte": 400, "lt": 500 } } },
          "server_error": { "range": { "status": { "gte": 500 } } }
        }
      }
    }
  }
}
```

4. Sub-aggregations (nested buckets + metrics)

> Sub-aggregations compute metrics inside each bucket. This answers: "For each HTTP method, what are the top 5 paths and their average response size?"

```json
GET web-logs-*/_search
{
  "size": 0,
  "aggs": {
    "by_method": {
      "terms": { "field": "method.keyword", "size": 5 },
      "aggs": {
        "top_paths": {
          "terms": { "field": "path.keyword", "size": 5 },
          "aggs": {
            "avg_bytes": { "avg": { "field": "bytes" } }
          }
        }
      }
    }
  }
}
```

5. Aggregation performance — `execution_hint` and `shard_size`

> **Aggregation tuning levers**:
> - `shard_size` controls how many term candidates each shard sends to the coordinating node. Higher = more accurate, slower.
> - `execution_hint: "map"` forces a different execution strategy that can be faster for low-cardinality fields.

```json
GET web-logs-*/_search
{
  "size": 0,
  "aggs": {
    "top_paths_tuned": {
      "terms": {
        "field": "path.keyword",
        "size": 10,
        "shard_size": 50,
        "execution_hint": "map"
      }
    }
  }
}
```

6. Profile a complex query

> `"profile": true` reveals the cost of each query clause in nanoseconds. Use it to identify and fix the slowest part of your bool queries.

```json
GET web-logs-*/_search
{
  "profile": true,
  "query": {
    "bool": {
      "must": [
        { "match": { "path": "products" } }
      ],
      "filter": [
        { "range": { "status": { "gte": 400 } } },
        { "range": { "@timestamp": { "gte": "2026-02-09T00:00:00Z", "lte": "2026-02-10T00:00:00Z" } } }
      ]
    }
  }
}
```

> Examine the `profile` section. Look at `time_in_nanos` for each collector. The clause with the highest time is your optimization target.

7. Query optimization strategies

> **Key principles**:
> - Place exact-match conditions in `filter` (cached, no scoring overhead)
> - Use `keyword` sub-fields for aggregations and term queries
> - Avoid leading wildcards (`*error`) — they force full index scans
> - Use `size: 0` when you only need aggregations

Run these two queries and compare response times:

**Slow (scoring context, wildcard):**
```json
GET web-logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "wildcard": { "path.keyword": "*products*" } },
        { "range": { "status": { "gte": 400 } } }
      ]
    }
  }
}
```

**Fast (filter context, prefix):**
```json
GET web-logs-*/_search
{
  "query": {
    "bool": {
      "filter": [
        { "prefix": { "path.keyword": "/api/products" } },
        { "range": { "status": { "gte": 400 } } }
      ]
    }
  }
}
```

> The second query is faster because: (a) `filter` context skips scoring and enables caching, (b) `prefix` is more efficient than `wildcard`.

**Success**: You can build complex bool queries, tune aggregations, and profile/optimize slow queries.

---

## Lab 2: Advanced Kibana Visualizations

**Objective**: Create advanced visualizations using Lens, TSVB, Vega, and Canvas

> Module 04 covered basic Lens charts. This lab explores Kibana's four visualization engines, each with a different strength:
> - **Lens**: Drag-and-drop, fastest for 90% of use cases
> - **TSVB** (Time Series Visual Builder): Rich time-series with math expressions
> - **Vega**: Full programmatic control using a grammar of graphics
> - **Canvas**: Presentation-quality, pixel-perfect layouts

### Before you start: Set the time range

> All training data is from **February 9, 2026**. Kibana defaults to "Last 15 minutes", which will show no data.

```
Top-right corner of Kibana → Click the time picker (shows "Last 15 minutes")
→ Select "Absolute"
→ Start: Feb 9, 2026 @ 00:00:00.000
→ End:   Feb 10, 2026 @ 00:00:00.000
→ Click "Update"
```

> Keep this time range for the entire lab. If any visualization shows "No results found", check the time picker first.

### Part 1: Lens Deep Dive

1. Open the Visualize Library

```
Menu (☰) → Analytics → Visualize Library
```

> You should see a list of previously saved visualizations (if any). The "Create visualization" button is in the upper-right area.

2. Create a new Lens visualization

```
Click "Create visualization"
```

> This opens the **Lens editor**. You should see:
> - **Left panel**: A list of available fields from the selected data view
> - **Center**: An empty chart area with drag-drop zones
> - **Top-left**: A data view dropdown (may show a default data view)

3. Select the correct data view

```
Top-left dropdown → Click and select "web-logs-*"
```

> If `web-logs-*` does not appear in the list, create it first:
> `Menu (☰) → Management → Stack Management → Kibana → Data Views → Create data view`
> Name: `web-logs-*`, Index pattern: `web-logs-*`, Time field: `@timestamp`

4. Build Layer 1: Request volume over time

```
Chart type selector (top center of editor, shows "Bar vertical stacked" by default)
→ Click it → Select "Area"

Left panel: Drag "@timestamp" to the "Horizontal axis" drop zone
  (Lens auto-configures it as a Date histogram)

The "Vertical axis" defaults to "Count of records" — leave it as is.
```

> You should see an area chart with a spike showing all 30 requests in a narrow time band. This is expected — the training dataset covers only ~30 seconds.

5. Add Layer 2: Error rate overlay

```
Bottom of the layer configuration → Click "Add layer" → "Visualization"
```

> A second layer panel appears below the first.

```
Layer 2 settings:
  Chart type: Select "Line" from the chart type dropdown for this layer

  Horizontal axis: Click "Add or drag-and-drop a field" → Select "@timestamp"

  Vertical axis: Click "Add or drag-and-drop a field"
    → In the function dropdown, scroll down and click "Formula"
    → In the formula text box, type:
      count(kql='status >= 500') / count()
    → Click "Apply and close" (or press Enter)

  Right panel → Axis assignment: Select "Right" to use a separate Y-axis for this layer
```

> **What this formula does**: It calculates the percentage of requests that returned HTTP 500+ status codes at each time bucket. This is the **error rate**.

> You should now see two layers: an area (total requests) and a line (error rate). The line may show a noticeable spike for the two 500-status requests.

6. Save the visualization

```
Top-right → Click "Save"
Title: M06 - Traffic with Error Rate Overlay
Click "Save"
```

### Part 2: TSVB for Time-Series Analysis

> **TSVB** is a legacy visualization editor that excels at multi-series time-series analysis with math expressions. Lens has replaced TSVB for most use cases, but TSVB still offers unique math capabilities between series.

7. Create a new TSVB visualization

```
Menu (☰) → Analytics → Visualize Library → Create visualization
```

> Depending on your Kibana version, you will see either:
> - A type picker showing **Lens**, **TSVB**, **Maps**, etc. → Select **TSVB**
> - OR Lens opens directly → Click the back arrow or navigate to: `Analytics → Visualize Library → Create visualization → select "TSVB"` from the visualization type list

> If you do not see TSVB listed, look for a link labeled **"Or, try other visualization options"** or **"Aggregation based"** below the Lens editor. In older versions, TSVB appears under "Legacy editors."

8. Configure TSVB panel options

> After TSVB opens, you see a time-series chart area and configuration tabs at the bottom.

```
Click the "Panel options" tab (at the bottom of the screen)
  Index pattern: web-logs-*
  Time field: @timestamp
  (Leave other settings as defaults)
```

9. Configure the data series

```
Click the "Data" tab
```

> You should see one series labeled "Count" with a colored circle.

```
Series 1 (already present):
  Label: Click the colored circle → type "Total Requests"
  Aggregation: Count (default — leave as is)
  Group by: Everything (default — leave as is)
```

10. Add a second series for the error rate

> Click the **"+"** button (or the "Add Series" icon) to create a second series.

```
Series 2:
  Label: Click the colored circle → type "Error Rate"

  Click on the "Aggregation" dropdown for this series:
    Select "Filter Ratio"
    
    Numerator: status >= 500
    Denominator: *  (asterisk = all documents)
```

> **Filter Ratio** is the easiest way to compute a rate in TSVB. It divides the count matching the Numerator filter by the count matching the Denominator filter.

> **Expected result**: The "Error Rate" line shows a value between 0 and 1. In the training data, approximately 2 out of 30 requests are 500s, so expect a value around 0.06–0.07.

11. Save the visualization

```
Top-right → Click "Save"
Title: M06 - TSVB Error Rate Trend
Click "Save"
```

### Part 3: Vega for Custom Visuals

> **Vega** is a JSON-based visualization grammar that gives full programmatic control over chart rendering. Use it when built-in chart types do not cover your requirement — for example, scatter plots with custom encodings.

12. Create a Vega visualization

```
Menu (☰) → Analytics → Visualize Library → Create visualization
```

> Look for **"Custom visualization"** or **"Vega"** in the visualization type list. In some Kibana versions, Vega appears under an **"Other types"** or **"Aggregation based"** section.

> The Vega editor opens with a default demo spec on the left and a preview on the right.

13. Replace the default spec with this Vega-Lite scatter plot

> Select all the text in the left editor panel (Ctrl+A) and replace it with:

```json
{
  "$schema": "https://vega.github.io/schema/vega-lite/v5.json",
  "title": "Response Size vs Status Code",
  "data": {
    "url": {
      "%context%": true,
      "%timefield%": "@timestamp",
      "index": "web-logs-*",
      "body": {
        "size": 500,
        "_source": ["status", "bytes", "method"]
      }
    },
    "format": { "property": "hits.hits" }
  },
  "transform": [
    { "calculate": "datum._source.status", "as": "status" },
    { "calculate": "datum._source.bytes", "as": "bytes" },
    { "calculate": "datum._source.method", "as": "method" }
  ],
  "mark": { "type": "circle", "opacity": 0.7 },
  "encoding": {
    "x": { "field": "status", "type": "quantitative", "title": "HTTP Status" },
    "y": { "field": "bytes", "type": "quantitative", "title": "Response Bytes" },
    "color": { "field": "method", "type": "nominal" },
    "size": { "value": 80 }
  }
}
```

> **How this works**:
> - `%context%: true` tells Kibana to inject the current time filter into the Elasticsearch query
> - `%timefield%` specifies which field to filter on
> - `_source` limits which fields are returned (keeps the response small)
> - `transform` extracts nested `_source` fields into flat columns for Vega
> - The chart plots each request as a circle: X = status code, Y = response bytes, Color = HTTP method

> **Expected result**: A scatter plot with dots clustered around status codes 200, 201, 204, 401, 403, 404, and 500. GET requests (blue) dominate. The 500-status dots should appear on the right side. Bytes range from 0 to ~3500.

14. Save the visualization

```
Top-right → Click "Save"
Title: M06 - Vega Scatter Plot
Click "Save"
```

### Part 4: Canvas for Storytelling

> **Canvas** creates presentation-ready, pixel-perfect layouts. Unlike Lens or TSVB which are data-exploration tools, Canvas is designed for wall-mounted NOC (Network Operations Center) displays and executive reports.

15. Open Canvas

```
Menu (☰) → Analytics → Canvas
Click "Create workpad"
```

> You should see a blank white page (the "workpad") with a toolbar at the top.

16. Add a "Total Requests" metric element

```
Click "Add element" (top toolbar) → Select "Metric"
```

> A metric element appears on the canvas showing sample/demo data.

```
Click on the metric element to select it.
Right sidebar → Click the "Data" tab
Change the data source from "Demo data" to "Elasticsearch SQL"

In the query box, type:
  SELECT COUNT(*) AS total FROM "web-logs-*"

Click "Save" or "Preview" to execute the query.
```

> The metric should now show **30** (the total number of access log records).

```
Right sidebar → Click the "Display" tab
  Label: Total Requests
  Font size: Drag the slider to 48 (or type 48)
```

> **Troubleshooting**: If you see 0 or an error, check:
> - The time picker covers Feb 9, 2026
> - The index `web-logs-*` exists (verify in Dev Tools: `GET _cat/indices/web-logs-*`)

17. Add a "Server Errors" metric element

```
Click "Add element" → Select "Metric"
```

> Position the new element next to the first one by dragging it.

```
Click on the new metric element to select it.
Right sidebar → "Data" tab → Change to "Elasticsearch SQL"

Query:
  SELECT COUNT(*) AS errors FROM "web-logs-*" WHERE status >= 500

Right sidebar → "Display" tab:
  Label: Server Errors
  Font size: 48
  Color: Click the color picker → select Red
```

> The value should show **2** (the two HTTP 500 requests in the access log: `/api/orders/history` and `/api/payment`).

18. Add a title using the Markdown element

```
Click "Add element" → Select "Markdown"
```

> A text box appears on the canvas.

```
Click on the Markdown element to select it.
Right sidebar → In the Markdown text editor, type:

  # Web Server Health Report
  Updated: February 9, 2026
```

> Drag the Markdown element to the top of the workpad and resize it to span the full width.

19. Save the workpad

```
Top-left → Click the workpad name (shows "My Canvas Workpad") → Rename to:
  M06 - Executive Health Report
```

> The workpad saves automatically. You can also click `File → Save` if auto-save is not active.

**Success**: You have created visualizations using all four Kibana engines — Lens (multi-layer area + line), TSVB (filter ratio for error rate), Vega (scatter plot), and Canvas (executive metric dashboard).

---

## Lab 3: Logstash Resiliency & Advanced Parsing

**Objective**: Handle multiline logs, dead-letter queues, custom analyzers, and error recovery

> Production log pipelines face messy data: Java stack traces span multiple lines, malformed events crash filters, and field type mismatches cause indexing failures. This lab covers the defensive patterns that keep pipelines running.

### Part 1: Multiline Log Handling

1. Create a sample multiline log file

> Java stack traces are the classic multiline problem — one logical event spans 5–20 lines. Without multiline handling, each line becomes a separate document.

```bash
sudo mkdir -p /opt/elk-training/data/raw
cat <<'EOF' | sudo tee /opt/elk-training/data/raw/multiline.log
2026-02-09 10:15:28 ERROR [main] com.app.PaymentService - Payment processing failed
java.lang.NullPointerException: null
    at com.app.PaymentService.process(PaymentService.java:42)
    at com.app.OrderController.checkout(OrderController.java:128)
    at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
2026-02-09 10:15:29 INFO [main] com.app.AuthService - User login successful
2026-02-09 10:15:30 ERROR [main] com.app.InventoryService - Stock check failed
java.io.IOException: Connection refused
    at com.app.InventoryService.checkStock(InventoryService.java:67)
    at com.app.OrderController.validate(OrderController.java:85)
2026-02-09 10:15:31 INFO [main] com.app.NotificationService - Email sent successfully
EOF
```

2. Create a Logstash pipeline with multiline codec

```bash
cat <<'PIPELINE' > ~/module06-multiline.conf
input {
  file {
    path => "/opt/elk-training/data/raw/multiline.log"
    start_position => "beginning"
    sincedb_path => "/dev/null"
    codec => multiline {
      pattern => "^%{TIMESTAMP_ISO8601}"
      negate => true
      what => "previous"
    }
  }
}

filter {
  grok {
    match => { "message" => "%{TIMESTAMP_ISO8601:timestamp} %{LOGLEVEL:level} \[%{DATA:thread}\] %{JAVACLASS:logger} - %{GREEDYDATA:log_message}" }
  }
  date {
    match => ["timestamp", "yyyy-MM-dd HH:mm:ss"]
    target => "@timestamp"
  }
  mutate {
    remove_field => ["timestamp"]
  }
}

output {
  elasticsearch {
    hosts => ["http://127.0.0.1:9200"]
    index => "training-multiline-%{+YYYY.MM.dd}"
  }
}
PIPELINE
```

> **How multiline works**: The `pattern` matches the start of a new log event (a timestamp). Lines that do NOT match (`negate => true`) are appended to the `previous` event. So the entire stack trace becomes one document.

3. Deploy and test

```bash
sudo cp ~/module06-multiline.conf /etc/logstash/conf.d/multiline.conf
sudo systemctl restart logstash
sleep 30
```

4. Verify in Dev Tools

```json
GET training-multiline-*/_search
{
  "query": { "match_all": {} },
  "sort": [{ "@timestamp": "asc" }]
}
```

> **Expected**: 4 documents (not 11 lines). The ERROR documents should contain the full stack trace in the `message` field.

### Part 2: Dead-Letter Queue and Error Recovery

5. Enable Dead-Letter Queue

> When a document fails to index (e.g., type mismatch — a string sent to an `integer` field), it is normally lost. The **Dead-Letter Queue (DLQ)** catches failed events so you can inspect and replay them.

```bash
cat <<'PIPELINE' > ~/module06-dlq-demo.conf
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
}

output {
  elasticsearch {
    hosts => ["http://127.0.0.1:9200"]
    index => "training-dlq-test"
  }
}
PIPELINE
```

6. Update `pipelines.yml` to enable DLQ for this pipeline

```bash
cat <<'YAML' > ~/module06-dlq-pipelines.yml
- pipeline.id: dlq-demo
  path.config: "/etc/logstash/conf.d/dlq-demo.conf"
  dead_letter_queue.enable: true
  dead_letter_queue.max_bytes: 1024mb
YAML

sudo cp ~/module06-dlq-demo.conf /etc/logstash/conf.d/dlq-demo.conf
sudo cp ~/module06-dlq-pipelines.yml /etc/logstash/pipelines.yml
sudo systemctl restart logstash
```

7. Check DLQ directory

```bash
ls -la /var/lib/logstash/dead_letter_queue/
```

> If events fail indexing, they appear here as `.log` segment files. In production, you would create a separate "DLQ reader" pipeline that reads from this queue, fixes the data, and re-indexes it.

8. Understand the DLQ reader pattern (conceptual)

> A DLQ reader pipeline uses the `dead_letter_queue` input plugin:
> ```conf
> input {
>   dead_letter_queue {
>     path => "/var/lib/logstash/dead_letter_queue/dlq-demo"
>     commit_offsets => true
>   }
> }
> ```
> This is the production pattern for recovering failed events without data loss.

### Part 3: Custom Analyzers

9. Create an index with a custom analyzer

> **Custom analyzers** let you control how text is tokenized and filtered. This is critical for log messages where you want to search for paths like `/api/v2/users` without them being split on `/`.

```json
PUT training-custom-analyzer
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "analysis": {
      "analyzer": {
        "path_analyzer": {
          "type": "custom",
          "tokenizer": "path_hierarchy"
        },
        "lowercase_keyword": {
          "type": "custom",
          "tokenizer": "keyword",
          "filter": ["lowercase"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "url_path": {
        "type": "text",
        "analyzer": "path_analyzer",
        "fields": {
          "keyword": { "type": "keyword" }
        }
      },
      "service_name": {
        "type": "text",
        "analyzer": "lowercase_keyword"
      }
    }
  }
}
```

10. Test the analyzer

> `_analyze` API lets you see exactly how text is tokenized — essential for debugging search issues.

```json
POST training-custom-analyzer/_analyze
{
  "analyzer": "path_analyzer",
  "text": "/api/v2/users/profile"
}
```

> **Expected tokens**: `/api`, `/api/v2`, `/api/v2/users`, `/api/v2/users/profile` — enabling hierarchical path searches.

```json
POST training-custom-analyzer/_analyze
{
  "analyzer": "lowercase_keyword",
  "text": "Auth-Service"
}
```

> **Expected token**: `auth-service` — the entire string kept as one token but lowercased.

11. Index test documents and search

```json
POST training-custom-analyzer/_doc
{
  "url_path": "/api/v2/users/profile",
  "service_name": "Auth-Service"
}

POST training-custom-analyzer/_doc
{
  "url_path": "/api/v2/orders/checkout",
  "service_name": "Payment-Service"
}
```

```json
GET training-custom-analyzer/_search
{
  "query": {
    "match": { "url_path": "/api/v2/users" }
  }
}
```

> **Expected**: Returns the first document because `path_hierarchy` tokenizer created a token for `/api/v2/users`.

**Success**: You can handle multiline logs, configure dead-letter queues for error recovery, and build custom analyzers.

---

## Lab 4: Advanced Alert Triage

**Objective**: Build a practical, reproducible triage flow for alert response.

### Why this lab exists

When an alert says "error count exceeded," the on-call engineer still has to answer:
1. Which service is failing?
2. Is user traffic affected?
3. Is this an application issue or cluster issue?
4. What is the first action to take?

A systematic triage workflow runs these checks in a fixed order and produces a concise analysis.

### Step-by-step triage workflow

1. Open Dev Tools

```
Menu (☰) → Management → Dev Tools
```

2. Find error distribution by service

```json
GET training-app-pipeline-*/_search
{
  "size": 0,
  "query": {
    "bool": {
      "filter": [
        { "term": { "level.keyword": "ERROR" } },
        { "range": { "@timestamp": { "gte": "2026-02-09T00:00:00Z", "lte": "2026-02-10T00:00:00Z" } } }
      ]
    }
  },
  "aggs": {
    "by_service": {
      "terms": { "field": "service.keyword", "size": 10 },
      "aggs": {
        "top_messages": {
          "terms": { "field": "message.keyword", "size": 5 }
        }
      }
    }
  }
}
```

> **Note**: In production, you would use `now-1h` for recent alerts. We use a fixed date range here because the training data is from February 9, 2026.

> Use this to identify the primary failing service and the most common error text.

3. Correlate with HTTP 5xx traffic

```json
GET web-logs-*/_search
{
  "size": 0,
  "query": {
    "bool": {
      "filter": [
        { "range": { "status": { "gte": 500 } } },
        { "range": { "@timestamp": { "gte": "2026-02-09T00:00:00Z", "lte": "2026-02-10T00:00:00Z" } } }
      ]
    }
  },
  "aggs": {
    "failing_paths": {
      "terms": { "field": "path.keyword", "size": 10 }
    }
  }
}
```

> If the same time window shows 5xx spikes on business paths (for example `/api/checkout`), the incident is user-facing.

4. Rule out Elasticsearch cluster pressure

```json
GET _cluster/health
GET _cat/nodes?v&h=name,heap.percent,cpu,load_1m
```

> If cluster status is `green`/`yellow` and heap/cpu are stable, the likely root cause is application-side, not Elasticsearch capacity.

5. Measure user-impact scope quickly

```json
GET web-logs-*/_search
{
  "size": 0,
  "query": {
    "bool": {
      "filter": [
        { "range": { "status": { "gte": 500 } } },
        { "range": { "@timestamp": { "gte": "2026-02-09T00:00:00Z", "lte": "2026-02-10T00:00:00Z" } } }
      ]
    }
  },
  "aggs": {
    "unique_clients": { "cardinality": { "field": "client_ip.keyword" } },
    "top_paths": { "terms": { "field": "path.keyword", "size": 5 } }
  }
}
```

6. Produce the incident explanation (template)

Use this structure for the incident summary:

```
Alert summary: <what fired>
Top failing service: <service from query 1>
Top failing endpoint(s): <paths from query 2>
Cluster status: <health + node stats from query 3>
User impact: <unique clients + top paths from query 4>
Likely cause: <application-side or cluster-side>
Immediate action: <owner + next command/check>
```

### Ambiguity guardrails

> This training dataset is small and static. Counts may be low. Focus on the triage **method**, not exact production volumes.

> The workflow is still valid for production: same query sequence, larger data windows, and real alert payload context.

**Success**: You can run a repeatable 4-step triage chain and convert raw alerts into a clear "what happened + what to do next" report.

> **Coming up**: In [Lab 14](./labs-12-14-observability-resilience.md#lab-14-automating-investigation-workflows-with-a-genai-agent), you will build a GenAI agent that automates this same 4-step triage workflow. Keep your manual results — you will compare them against the agent's output.

