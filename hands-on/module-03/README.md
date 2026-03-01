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
3. Set time picker: **Absolute range (2026-02-08 to 2026-02-12)**
   * *Note: Our training data is static. If you use "Last 15 minutes", you will see no data.*
4. Run these KQL queries
```bash
# Verify data exists via terminal (optional)
curl -s "http://127.0.0.1:9200/web-logs-*,app-logs-*/_count?pretty"
```

> Basic field matching — `field : value` filters documents where the field equals the value. Multiple values use `or`. Wildcards (`*`) match partial strings.

```
*
status : 200
method : GET
method : GET and status : 200
status >= 400 and status < 500
status : (401 or 403)
not status : 200
path.keyword : /api/*
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

*Try these queries individually:*

```kql
(method : GET or method : POST) and status : 200
```
```kql
path.keyword : ("/api/products" or "/api/orders")
```
```kql
bytes >= 1000
```
3. Use wildcards

> `*` matches zero or more characters. Useful for partial path matching or user agent filtering. Always use the `.keyword` sub-field when your values contain special characters like slashes.

*Run these separately in the search bar:*

```kql
path.keyword : */products*
user_agent.keyword : *Chrome*
user_agent.keyword : *Mozilla*
```
4. Add filters using the UI

> **Conceptual Note: Performance & Caching**
> *   **KQL Bar**: Generally uses the **Query context**. It calculates "relevance scores" (how well a doc matches) and is not always cached by Elasticsearch.
> *   **UI Filters**: These use the **Filter context**. They are binary (Yes/No), do **not** calculate scores, and their results are **automatically cached** by Elasticsearch. 
> *   **Best Practice**: Use the KQL bar for ad-hoc searching and full-text searches. Use UI filters for structured data (status codes, levels, IDs) because they make your dashboards and repeated searches much faster.

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

> **Concept: Shredder vs. Snapshot**
> *   **The Index (Storage)**: When you use the `text` type, Elasticsearch **shreds the data** during indexing. For example, `/api/products` is stored as `["api", "products"]`.
> *   **The Match Query**: This query **also shreds** your search term. If you search for `/api/products`, it looks for the pieces `api` and `products`. This is why `match` works on `text` fields!
> *   **The Term Query**: This query **NEVER shreds**. It takes your search word as a single, solid piece (snapshot).
> *   **The Failure (Test C)**: When you run a `term` query against a `text` field, you are looking for **one solid piece** (`/api/products`) in a list of **separate pieces** (`api`, `products`). They will never match.
### 🔬 Side-by-Side Comparison
Run these three tests to see the "Shredder" in action:

**Test A: The Match Query (Finds all paths containing "products")**
```json
GET web-logs-*/_search
{
  "query": { "match": { "path": "products" } }
}
```

**Test B: The Term Query (Finds ONLY the exact snapshot)**
```json
GET web-logs-*/_search
{
  "query": { "term": { "path.keyword": "/api/products" } }
}
```

**Test C: The "Broken" Query (Returns 0 hits)**
```json
GET web-logs-*/_search
{
  "query": { "term": { "path": "/api/products" } }
}
```
*Proof: Test C fails because the `path` field was shredded. The string "/api/products" no longer exists as a single piece in that field.*

**Summary of the lesson:**
*   **Test A (Match)**: Searches for the "shredded pieces".
*   **Test B (Term + .keyword)**: Searches for the "exact snapshot".
*   **Test C (Term + text)**: Fails because you can't find a snapshot in a pile of shredded pieces.

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

## Lab 4: The Logic of "Bool" Queries
**Objective**: Combine multiple questions into one complex query

> **Concept**: Real-world questions are rarely simple. You don't ask "Find errors". You ask "Find **errors** (must) in **production** (filter) from **yesterday** (filter), but **ignore** 404s (must_not), and maybe prioritize **critical** ones (should)."
>
> The `bool` query is the container for this logic. It has 4 clauses:
> 1.  **`must` (AND)**: "It HAS to match, and I care about *how well* it matches (score)." (Use for: Full-text search).
> 2.  **`filter` (AND)**: "It HAS to match, but I don't care about score." (Use for: Exact IDs, Dates, Status Codes). **Much faster because it is cached.**
> 3.  **`should` (OR)**: "It's nice if it matches." (Use for: Boosting relevance or "A OR B" logic).
> 4.  **`must_not` (NOT)**: "It must NOT match." (Use for: Exclusion).

1. **Scenario A: "The Specific Search" (Must + Filter)**
   *   *Goal*: Find logs where the message contains "login" (text search) AND the status is 200 (exact filter).
   *   *Why*: We use `must` for "login" because we want to find the word. We use `filter` for "200" because a status is either 200 or it isn't; there is no "partial 200".

```json
GET web-logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "message": "login" } }
      ],
      "filter": [
        { "term": { "status": 200 } }
      ]
    }
  }
}
```

2. **Scenario B: "The List Search" (Should)**
   *   *Goal*: Find logs from EITHER "auth-service" OR "payment-service".
   *   *Why*: In a `bool` query, if you only have `should` clauses, at least one must match (Logic: A OR B).

```json
GET app-logs-*/_search
{
  "query": {
    "bool": {
      "should": [
        { "term": { "service.keyword": "auth-service" } },
        { "term": { "service.keyword": "payment-service" } }
      ],
      "minimum_should_match": 1
    }
  }
}
```

3. **Scenario C: "The Noise Filter" (Must Not)**
   *   *Goal*: Show me all Server Errors (500+), but hide the "Maintenance" events I already know about.

```json
GET web-logs-*/_search
{
  "query": {
    "bool": {
      "filter": [
        { "range": { "status": { "gte": 500 } } }
      ],
      "must_not": [
        { "match": { "message": "maintenance" } }
      ]
    }
  }
}
```
**Success**: You can express complex business logic (AND, OR, NOT) using JSON structure.

---

## Lab 5: Aggregations
**Objective**: Analyze data using metric and bucket aggregations

> **Aggregations** analyze data across documents.
> *   **Bucket aggregations** (terms, date_histogram) group documents into buckets.
> *   **Metric aggregations** (avg, sum, count) compute values within those buckets.
> *   Setting `"size": 0` tells Elasticsearch to **only** return the aggregation results, skipping the individual hits.
>
> **Aggregation Anatomy**:
> `"aggs": { "MY_CUSTOM_NAME": { "AGG_TYPE": { "field": "MY_FIELD" } } }`

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
