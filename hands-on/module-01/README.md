# Module 01 – ELK Fast-Track Foundations

> **Stack Version**: Elasticsearch & Kibana 9.x  
> **Prerequisite**: Complete [Module 00](../module-00/README.md) first

---

## Lab 1 – Verify ELK Stack Installation

**Objective**: Confirm Elasticsearch and Kibana are running

> Elasticsearch and Kibana run as systemd services on CentOS. Verifying both services are active is the first step before any hands-on work.

1. Check Elasticsearch service

```bash
sudo systemctl status elasticsearch --no-pager
```

> Look for `Active: active (running)`. This confirms the JVM started and the node is listening on port 9200.

2. Check Kibana service

```bash
sudo systemctl status kibana --no-pager
```

> Kibana connects to Elasticsearch on startup. If Elasticsearch is healthy, Kibana should also show `active (running)`.

3. Access Kibana UI

```
http://127.0.0.1:5601
```

If you are accessing the VM from your laptop, use:

```
http://<VM-IP>:5601
```

> **Note**: If Kibana not ready, wait 1-2 minutes and refresh

4. Open Dev Tools

> Dev Tools is Kibana's built-in REST API console. It lets you run Elasticsearch queries directly from the browser without curl.

```
Menu (☰) → Management → Dev Tools
```

5. Verify cluster health

```json
GET _cluster/health
```

> `_cluster/health` returns the overall cluster state. `green` means all primary and replica shards are allocated. `yellow` means replicas are unassigned (normal for single-node setups).

**Success**: Cluster status shows `green` or `yellow`

---

## Lab 2 – Explore Kibana Interface

**Objective**: Navigate main Kibana UI areas

> Kibana organizes features into sections: **Analytics** (Discover, Visualize, Dashboard) for data exploration, and **Management** (Stack Management, Dev Tools) for administration.

1. Open Discover

> Discover is where you search and filter indexed data using KQL or ES|QL.

```
Menu (☰) → Analytics → Discover
```

2. Open Visualize Library

> Visualize Library stores saved charts (bar, line, pie, etc.) that can be reused across dashboards.

```
Menu (☰) → Analytics → Visualize Library
```

3. Open Dashboard

```
Menu (☰) → Analytics → Dashboard
```

4. Open Stack Management

> Stack Management is the admin hub — index management, data views, connectors, and security settings live here.

```
Menu (☰) → Management → Stack Management
```

5. Return to Dev Tools

```
Menu (☰) → Management → Dev Tools
```

**Success**: All sections accessible

---

## Lab 3 – Index First Document

**Objective**: Create index and add document using Dev Tools

> An **index** in Elasticsearch is like a database table. It holds documents (JSON objects) and defines how fields are stored and searched through **mappings**.

> **Concept: Text vs. Keyword**
> *   **Text**: Used for full-text search (messages, descriptions). It is "analyzed" (broken into tokens/words).
> *   **Keyword**: Used for exact matching, sorting, and aggregations (status codes, user IDs, paths). It is "not analyzed" (stored as one single string).
> *   **Why this matters**: You cannot aggregate on a `text` field easily, and you cannot do a partial "word" search on a `keyword` field effectively. In our lab, we rely on automatic mapping for most fields, but defining the correct type is best practice.

0. (Optional) Reset from a previous run (only if you already created `app-logs` before)

```json
DELETE app-logs
```

1. Create index (make `timestamp` a date field)

> `PUT` creates a new index. Defining `timestamp` as type `date` enables time-based filtering and sorting in Discover.

```json
PUT app-logs
{
  "mappings": {
    "properties": {
      "timestamp": { "type": "date" }
    }
  }
}
```

2. Index document

> `POST index/_doc` adds a document. Elasticsearch auto-generates a unique `_id` for each document.

```json
POST app-logs/_doc
{
  "timestamp": "2026-02-09T12:00:00Z",
  "level": "INFO",
  "service": "auth-service",
  "message": "User login successful",
  "user_id": "user_12345"
}
```

3. Index second document

```json
POST app-logs/_doc
{
  "timestamp": "2026-02-09T12:00:01Z",
  "level": "ERROR",
  "service": "payment-service",
  "message": "Payment processing failed",
  "error": "Timeout"
}
```

4. Refresh index (so search shows documents immediately)

> By default, Elasticsearch refreshes every 1 second. `_refresh` forces an immediate refresh so newly indexed documents appear in search results right away.

```json
POST app-logs/_refresh
```

5. Search documents

```json
GET app-logs/_search
```

> **Expected**: Returns 2 documents

6. Create data view

> A **data view** (formerly index pattern) tells Kibana which Elasticsearch indices to query and which field to use as the timestamp for time-based filtering.

```
Menu (☰) → Management → Stack Management
Click: Kibana → Data Views
Click: Create data view

Fill in:
  Name: app-logs
  Index pattern: app-logs
  Timestamp field: timestamp
  
Click: Save data view to Kibana
```

7. Open Discover

```
Menu (☰) → Analytics → Discover
Select data view dropdown: app-logs
Time picker: Absolute (2026-02-08 to 2026-02-12)
```

**Success**: Documents visible in Discover

---

## Lab 4 – Query and Search

**Objective**: Perform basic searches in Kibana Discover

> **KQL** (Kibana Query Language) is the default search syntax in Discover. It supports field-based filtering, wildcards, and boolean operators.

1. Open Discover with app-logs data view

```
Menu (☰) → Analytics → Discover
Data view dropdown: Select app-logs
```

2. Set time range

> The time picker controls which documents are visible. Since our test documents use Feb 9 2026, we MUST set an absolute range.

```
Click time picker (top-right)
Select: Absolute → Start: 2026-02-08 → End: 2026-02-12
```

3. Search ERROR logs

> KQL syntax: `field : "value"` filters documents where the field exactly matches the value.

```
level : "ERROR"
```

> **Expected**: Shows only ERROR level documents

4. Search by service

```
service : "payment-service"
```

5. Search message text

> For `text` fields, KQL performs a full-text search — it matches on individual tokens, so `"failed"` matches `"Payment processing failed"`.

```
message : "failed"
```

6. Add filter

> Filters added via the UI persist across searches and can be toggled on/off without modifying the KQL query bar.

```
Click: + Add filter (below search bar)
Field: level
Operator: is
Value: ERROR
Click: Save
```

7. Add table column

> By default, Discover shows the `_source` field. Adding specific columns makes the table easier to scan.

```
Left sidebar: Available fields
Find: service
Click: + button next to service
```

8. Expand document

```
Click arrow on document row
```

9. View JSON

> The JSON tab shows the raw `_source` document exactly as stored in Elasticsearch.

```
JSON tab
```

**Success**: Can search, filter, and view document details
