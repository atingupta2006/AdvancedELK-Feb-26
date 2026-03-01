# Elasticsearch Data Types & Schema Design

Understanding how Elasticsearch stores data (the "schema" or **Mapping**) is the single most important factor for search speed, accuracy, and storage efficiency.

---

## 1. Core Data Types

### **Text** (The "Analyzed" String)
*   **Purpose**: Full-text search (searching *inside* a sentence or log message).
*   **Behavior**: It is "shredded" (Analyzed). It removes punctuation, lowercases everything, and breaks words into tokens.
*   **Scenario**: Log messages, descriptions, broad search bars.
*   **Performance**: Heavier to index. Slower to search because it calculates "relevance" (BM25 score).

### **Keyword** (The "Structured" String)
*   **Purpose**: Exact matching, filtering, sorting, and aggregations (charts).
*   **Behavior**: It is Not Analyzed. It is stored as one solid "snapshot".
*   **Scenario**: Status codes (200, 404), User IDs, hostnames, tags.
*   **Performance**: Very fast for filtering. Highly efficient storage. In filter context, scoring is skipped entirely. In query context, `term` queries return a constant score (no variable BM25 math).

### **Boolean**
*   **Purpose**: True/false flags.
*   **Behavior**: Stored as `true` or `false`. Also accepts `"true"`, `"false"`, `""` (false), `1` (true), `0` (false).
*   **Scenario**: `is_active`, `enabled`, feature flags.
*   **Performance**: Extremely lightweight. Treat like a keyword with only two possible values.

### **Numeric (long, integer, double)**
*   **Purpose**: Range searches and mathematical calculations.
*   **Scenario**: Response bytes, prices, counts, execution time.
*   **Performance**: Extremely fast for range queries (e.g., `bytes > 1000`) due to specialized BKD tree storage and **Doc Values**.

### **Date**
*   **Purpose**: Time-series analysis.
*   **Scenario**: `@timestamp`.
*   **Behavior**: Stored internally as a long integer (milliseconds since epoch), but searchable via human-readable strings.

---

## 2. Multi-Fields (The "Best of Both Worlds")
In our labs, you see `path` and `path.keyword`. This is a **Multi-field**.
Elasticsearch indexes the same data twice:
1.  As **Text** (`path`): For searching "products".
2.  As **Keyword** (`path.keyword`): For exact filters and bar charts.

**Rule of Thumb**: If you need to search *and* aggregate, use a Multi-field.

---

## 3. Advanced Schema Types

| Type | Scenario | Why use it? |
| :--- | :--- | :--- |
| **IP** | `client_ip` | Allows CIDR searches (e.g., `192.168.1.0/24`) which regular strings cannot do. |
| **Geo-point** | `location` | Enables distance searches ("Find errors within 10km of London") and Map visualizations. |
| **Object** | Nested JSON | Standard JSON hierarchy. Fields are flattened. |
| **Nested** | Arrays of objects | Prevents "cross-object" matching in arrays. Keeps items in an array independent. |

---

## 4. Performance Checklist

| Feature | Use This Type | Why? |
| :--- | :--- | :--- |
| **Filtering (AND/OR)** | `keyword` | Binary match, results are cached in memory. |
| **Searching (Ranked)** | `text` | Calculates which doc is "more relevant". |
| **Sorting** | `keyword`, `date`, `numeric` | Cannot sort by `text` efficiently (requires fielddata). |
| **Aggregations (Charts)** | `keyword`, `numeric` | `text` fields cannot be used for charts. |

---

## 5. Summary Glossary

*   **Mapping**: The "Schema" definition in Elasticsearch.
*   **Inverted Index**: The core data structure of Elasticsearch. It's like the index at the back of a book. It maps **tokens** to **document IDs**.
*   **Doc Values**: A secondary data structure (columnar storage) used for sorting and aggregations. It's highly efficient for reading thousands of field values at once.
*   **Analysis**: The process of "shredding" text into tokens.
*   **Dynamic Mapping**: When ES guesses the data type (Dangerous for production!).
*   **Explicit Mapping**: When you define the type yourself (Best practice).
