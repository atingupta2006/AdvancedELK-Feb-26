# Module 03 – Querying, Filtering & Analysis (Labs)

> **Stack Version**: Elasticsearch & Kibana 9.x

Prereq: Module 02 completed. These indices must exist:
- `web-logs-*`
- `app-logs-*`

---

## Lab 1: KQL Basics in Discover
**Objective**: Write basic KQL queries

1. Open Discover
```
Menu (☰) → Analytics → Discover
```
2. Select data view: `web-logs-*`
3. Set time picker: Last 30 days
4. Run these KQL queries
```
*
status : 200
method : GET
method : GET and status : 200
status >= 400 and status < 500
status : (401 or 403)
not status : 200
path : /api/*
```
5. Switch data view: `app-logs-*`
6. Run these KQL queries
```
level : ERROR
service : auth-service
service : auth-service and level : ERROR
message : "login"
```
**Success**: You can filter both datasets with KQL

---

## Lab 2: Advanced KQL Queries
**Objective**: Build multi-condition queries and filters

1. Discover → data view: `web-logs-*`
2. Combine conditions
```
(method : GET or method : POST) and status : 200
path : ("/api/products" or "/api/orders")
bytes >= 1000
```
3. Use wildcards
```
path : */products*
user_agent : *Chrome*
```
4. Add filters using the UI
```
Add filter → Field: status → Operator: is one of → Values: 500, 503
```
5. Save the search
```
Save → Name: M03 - Web Errors
```
**Success**: Saved search appears under Discover saved objects

---

## Lab 3: Query DSL in Dev Tools
**Objective**: Write Query DSL queries

1. Open Dev Tools
```
Menu (☰) → Management → Dev Tools
```
2. Count documents
```json
GET web-logs-*/_count
```
3. Match query (full text)
```json
GET web-logs-*/_search
{
  "query": {
    "match": {
      "path": "products"
    }
  }
}
```
4. Term query (exact)
```json
GET web-logs-*/_search
{
  "query": {
    "term": {
      "method": "GET"
    }
  }
}
```
5. Range query
```json
GET web-logs-*/_search
{
  "query": {
    "range": {
      "status": { "gte": 400 }
    }
  }
}
```
**Success**: You can run match/term/range queries in Dev Tools

---

## Lab 4: Bool Queries
**Objective**: Build complex bool queries

1. Dev Tools: Must + Filter
```json
GET web-logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "method": "GET" } }
      ],
      "filter": [
        { "range": { "status": { "gte": 200, "lt": 300 } } }
      ]
    }
  }
}
```
2. Should + minimum_should_match
```json
GET app-logs-*/_search
{
  "query": {
    "bool": {
      "should": [
        { "term": { "service": "auth-service" } },
        { "term": { "service": "payment-service" } }
      ],
      "minimum_should_match": 1,
      "filter": [
        { "term": { "level": "ERROR" } }
      ]
    }
  }
}
```
3. Exclude results (must_not)
```json
GET web-logs-*/_search
{
  "query": {
    "bool": {
      "filter": [
        { "range": { "status": { "gte": 400 } } }
      ],
      "must_not": [
        { "term": { "status": 404 } }
      ]
    }
  }
}
```
**Success**: Bool queries return expected filtered results

---

## Lab 5: Aggregations
**Objective**: Analyze data using metric and bucket aggregations

1. Top request paths (terms)
```json
GET web-logs-*/_search
{
  "size": 0,
  "aggs": {
    "top_paths": {
      "terms": { "field": "path.keyword", "size": 10 }
    }
  }
}
```
2. Status distribution
```json
GET web-logs-*/_search
{
  "size": 0,
  "aggs": {
    "status_codes": {
      "terms": { "field": "status", "size": 10 }
    }
  }
}
```
3. Errors over time (date histogram)
```json
GET app-logs-*/_search
{
  "size": 0,
  "query": {
    "term": { "level": "ERROR" }
  },
  "aggs": {
    "errors_over_time": {
      "date_histogram": {
        "field": "@timestamp",
        "fixed_interval": "30m"
      }
    }
  }
}
```
4. Kibana: Visualize one aggregation
```
Menu (☰) → Analytics → Visualize Library → Create visualization → Lens
Data view: web-logs-*
Visualization: Bar
Horizontal axis: path.keyword (Top values)
Vertical axis: Count
Save as: M03 - Top Paths
```
**Success**: Aggregations work in Dev Tools and you can visualize one result in Lens
