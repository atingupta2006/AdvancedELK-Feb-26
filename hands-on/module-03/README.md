# Module 03 – Querying, Filtering & Analysis (Labs)

> **Stack Version**: Elasticsearch & Kibana 9.x

Prereq: Module 02 completed. These indices must exist:
- `web-logs-*`
- `app-logs-*`

---

## Lab 1: KQL Basics in Discover
**Objective**: Write basic KQL queries

> **KQL** (Kibana Query Language) is the default query syntax in Discover. It uses `field : value` syntax for exact matching and supports boolean operators (`and`, `or`, `not`).

1. Open Discover
```
Menu (☰) → Analytics → Discover
```
2. Select data view: `web-logs-*`
3. Set time picker: Last 30 days
4. Run these KQL queries

> Basic field matching — `field : value` filters documents where the field equals the value. Multiple values use `or`. Wildcards (`*`) match partial strings.

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

> For `keyword` fields, KQL does exact matching. For `text` fields, it performs full-text search on individual tokens.

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

> Parentheses group conditions. KQL evaluates `and` before `or`, so use parentheses to control precedence.

```
(method : GET or method : POST) and status : 200
path : ("/api/products" or "/api/orders")
bytes >= 1000
```
3. Use wildcards

> `*` matches zero or more characters. Useful for partial path matching or user agent filtering.

```
path : */products*
user_agent : *Chrome*
```
4. Add filters using the UI

> UI filters are separate from the KQL bar. They persist across searches and can be individually toggled, pinned, or inverted.

```
Add filter → Field: status → Operator: is one of → Values: 500, 503
```
5. Save the search

> Saved searches preserve the query, filters, selected columns, and sort order. They can be embedded in dashboards.

```
Save → Name: M03 - Web Errors
```
**Success**: Saved search appears under Discover saved objects

---

## Lab 3: Query DSL in Dev Tools
**Objective**: Write Query DSL queries

> **Query DSL** is Elasticsearch's JSON-based query language. Unlike KQL (Kibana-only), Query DSL works directly with the Elasticsearch REST API and offers full control over scoring, filtering, and aggregations.

1. Open Dev Tools
```
Menu (☰) → Management → Dev Tools
```
2. Count documents

> `_count` returns the total number of matching documents without returning the documents themselves.

```json
GET web-logs-*/_count
```
3. Match query (full text)

> `match` performs full-text search — it analyzes the query string and matches individual tokens. Use for `text` fields.

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

> `term` does exact matching with no analysis. Use for `keyword`, `integer`, and `boolean` fields. Do NOT use `term` on analyzed `text` fields — use the `.keyword` sub-field instead.

```json
GET web-logs-*/_search
{
  "query": {
    "term": {
      "method.keyword": "GET"
    }
  }
}
```
5. Range query

> `range` filters by numeric or date ranges. Supports `gte`, `gt`, `lte`, `lt` operators.

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

> A **bool query** combines multiple clauses: `must` (AND, affects score), `filter` (AND, no score — faster), `should` (OR), and `must_not` (NOT). Use `filter` over `must` when you don't need relevance scoring.

1. Dev Tools: Must + Filter

> `must` clauses contribute to the relevance score. `filter` clauses are cached and don't affect score — use them for exact matching on structured fields.

```json
GET web-logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "method.keyword": "GET" } }
      ],
      "filter": [
        { "range": { "status": { "gte": 200, "lt": 300 } } }
      ]
    }
  }
}
```
2. Should + minimum_should_match

> `should` clauses are optional by default. Setting `minimum_should_match: 1` requires at least one `should` clause to match.

```json
GET app-logs-*/_search
{
  "query": {
    "bool": {
      "should": [
        { "term": { "service.keyword": "auth-service" } },
        { "term": { "service.keyword": "payment-service" } }
      ],
      "minimum_should_match": 1,
      "filter": [
        { "term": { "level.keyword": "ERROR" } }
      ]
    }
  }
}
```
3. Exclude results (must_not)

> `must_not` excludes matching documents entirely. Here we get all 4xx+ errors except 404s.

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

> **Aggregations** analyze data across documents. **Bucket aggregations** (terms, date_histogram) group documents into buckets. **Metric aggregations** (avg, sum, count) compute values within those buckets. Setting `"size": 0` returns only aggregation results, not individual documents.

1. Top request paths (terms)

> `terms` aggregation groups documents by unique field values and counts each group. Like SQL `GROUP BY`.

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

> `date_histogram` groups documents into time-based buckets. Combined with a query filter, it shows trends like error rate over time.

```json
GET app-logs-*/_search
{
  "size": 0,
  "query": {
    "term": { "level.keyword": "ERROR" }
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

> Lens translates aggregations into visual charts. Picking "Top values" for an axis is equivalent to a `terms` aggregation.

```
Menu (☰) → Analytics → Visualize Library → Create visualization → Lens
Data view: web-logs-*
Visualization: Bar
Horizontal axis: path.keyword (Top values)
Vertical axis: Count
Save as: M03 - Top Paths
```
**Success**: Aggregations work in Dev Tools and you can visualize one result in Lens
