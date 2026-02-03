# Module 01 – ELK Fast-Track Foundations (Hands-On Labs)

---

## Lab 1 – Verify ELK Stack Installation

**Objective**: Confirm Elasticsearch and Kibana are running

1. Check Elasticsearch service

```bash
sudo systemctl status elasticsearch
```

2. Start Elasticsearch if not running

```bash
sudo systemctl start elasticsearch
```

3. Check Kibana service

```bash
sudo systemctl status kibana
```

4. Start Kibana if not running

```bash
sudo systemctl start kibana
```

5. Open browser

```
http://localhost:5601
```

6. Login to Kibana if prompted

7. Open Kibana Dev Tools

```
Kibana → Dev Tools
```

8. Run cluster health request

```json
GET _cluster/health
```

**Success**: Status shows `"green"`

---

## Lab 2 – Explore Kibana Interface

**Objective**: Navigate main Kibana UI areas

1. Open Discover

```
Kibana → Discover
```

2. Return to home

```
Kibana logo (top left)
```

3. Open Visualize Library

```
Kibana → Visualize Library
```

4. Return to home

```
Kibana logo
```

5. Open Dashboard

```
Kibana → Dashboard
```

6. Return to home

```
Kibana logo
```

7. Open Stack Management

```
Kibana → Stack Management
```

8. Open Index Management

```
Stack Management → Index Management
```

9. Return to home

```
Kibana logo
```

10. Open Dev Tools

```
Kibana → Dev Tools
```

**Success**: All sections open successfully

---

## Lab 3 – Index First Document

**Objective**: Create index and add document using Kibana Dev Tools

1. Open Dev Tools

```
Kibana → Dev Tools
```

2. Create index

```json
PUT app-logs
```

3. Index first document

```json
POST app-logs/_doc
{
  "timestamp": "2024-01-01T12:00:00Z",
  "level": "INFO",
  "service": "auth-service",
  "message": "User login successful",
  "user_id": "12345"
}
```

4. Index second document

```json
POST app-logs/_doc
{
  "timestamp": "2024-01-01T12:00:01Z",
  "level": "ERROR",
  "service": "payment-service",
  "message": "Payment processing failed",
  "error": "Timeout"
}
```

5. Retrieve documents

```json
GET app-logs/_search
```

6. Open Discover

```
Kibana → Discover
```

7. Create data view

```
Create data view
Name: app-logs
Index pattern: app-logs*
Timestamp field: timestamp
Save
```

8. Select data view

```
Data view dropdown → app-logs
```

**Success**: Documents visible in Discover

---

## Lab 4 – Query and Search

**Objective**: Perform basic searches in Kibana Discover

1. Open Discover

```
Kibana → Discover
```

2. Select data view

```
app-logs
```

3. Set time range

```
Time picker → Last 24 hours
```

4. Search ERROR logs

```
level : "ERROR"
```

5. Search by service

```
service : "auth-service"
```

6. Search by text

```
message : "failed"
```

7. Add filter

```
Add filter
Field: level
Operator: is
Value: ERROR
Save
```

8. Remove filter

```
Filter bar → Delete filter
```

9. Add column

```
Field list → service → Add to table
```

10. Expand a document

```
Click arrow on left side of row
```

11. View JSON

```
JSON tab
```

**Success**: Can search, filter, and view documents
