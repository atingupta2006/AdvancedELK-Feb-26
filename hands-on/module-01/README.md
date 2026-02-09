# Module 01 – ELK Fast-Track Foundations

> **Stack Version**: Elasticsearch & Kibana 9.x  
> **Prerequisite**: Complete [Module 00](../module-00/README.md) first

---

## Lab 1 – Verify ELK Stack Installation

**Objective**: Confirm Elasticsearch and Kibana are running

1. Check Elasticsearch service

```bash
sudo systemctl status elasticsearch --no-pager
```

2. Check Kibana service

```bash
sudo systemctl status kibana --no-pager
```

3. Access Kibana UI

```
http://localhost:5601
```

If you are accessing the VM from your laptop, use:

```
http://<VM-IP>:5601
```

> **Note**: If Kibana not ready, wait 1-2 minutes and refresh

4. Open Dev Tools

```
Menu (☰) → Management → Dev Tools
```

5. Verify cluster health

```json
GET _cluster/health
```

> **Expected**: Response shows `"status": "green"` or `"status": "yellow"`

**Success**: Cluster status shows `green` or `yellow`

---

## Lab 2 – Explore Kibana Interface

**Objective**: Navigate main Kibana UI areas

1. Open Discover

```
Menu (☰) → Analytics → Discover
```

2. Open Visualize Library

```
Menu (☰) → Analytics → Visualize Library
```

3. Open Dashboard

```
Menu (☰) → Analytics → Dashboard
```

4. Open Stack Management

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

0. (Optional) Reset from a previous run (only if you already created `app-logs` before)

```json
DELETE app-logs
```

1. Create index (make `timestamp` a date field)

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

```json
POST app-logs/_doc
{
  "timestamp": "2026-02-09T12:00:00Z",
  "level": "INFO",
  "service": "auth-service",
  "message": "User login successful",
  "user_id": "12345"
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

```json
POST app-logs/_refresh
```

5. Search documents

```json
GET app-logs/_search
```

> **Expected**: Returns 2 documents

6. Create data view

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
```

**Success**: Documents visible in Discover

---

## Lab 4 – Query and Search

**Objective**: Perform basic searches in Kibana Discover

1. Open Discover with app-logs data view

```
Menu (☰) → Analytics → Discover
Data view dropdown: Select app-logs
```

2. Set time range

```
Click time picker (top-right)
Select: Last 24 hours
Or select: Last 7 days (if documents not showing)
```

3. Search ERROR logs

```
level : "ERROR"
```

> **Expected**: Shows only ERROR level documents

4. Search by service

```
service : "payment-service"
```

5. Search message text

```
message : "failed"
```

6. Add filter

```
Click: + Add filter (below search bar)
Field: level
Operator: is
Value: ERROR
Click: Save
```

7. Add table column

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

```
JSON tab
```

**Success**: Can search, filter, and view document details
