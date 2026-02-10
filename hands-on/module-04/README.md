# Module 04 – Visualization & Dashboard Engineering Labs
> Stack Version: Elasticsearch & Kibana 9.x
Prereq: Module 02 ingested data into `web-logs-*` and `app-logs-*`.

## Lab 1: Create Core Visualizations (40 min)
Objective: Build line, bar, pie, and metric visualizations

> **Lens** is Kibana's primary visualization editor. It auto-suggests chart types based on your data and supports drag-and-drop field mapping. All visualizations created here can be saved and reused across dashboards.

1. Open Kibana

```
http://localhost:5601
```

If accessing from your laptop: `http://<VM-IP>:5601`

2. Open Visualize Library

```
Menu (☰) → Analytics → Visualize Library
```

3. Create line chart (response time over time)

> Line charts are ideal for time-series data. Here we use a formula to approximate response time from byte size. The date histogram on the x-axis groups data into time buckets.

```
Create visualization → Lens
Data view: web-logs-*
Metric: Formula → average(bytes) / 10
Metric name: Response time (ms)
X-axis: Date histogram → @timestamp → Auto
Title: Response Time Over Time
Save as: response_time_over_time
```

4. Create bar chart (top 10 request paths)

> `Terms` aggregation on `path.keyword` groups requests by URL path. Using `.keyword` ensures exact matching (not tokenized text analysis).

```
Create visualization → Bar
Data view: web-logs-*
Metric: Count
X-axis: Terms → path.keyword → Size 10 → Order Desc
Title: Top Request Paths
Save as: top_request_paths
```

5. Create pie chart (response codes distribution)

> Pie charts show proportional distribution. Each slice represents a unique `status` code bucket.

```
Create visualization → Pie
Data view: web-logs-*
Metric: Count
Buckets: Terms → status → Size 6
Title: HTTP Status Distribution
Save as: http_status_distribution
```

6. Create metric (total requests)

> Metric visualizations display a single aggregated number — useful for KPI panels on dashboards.

```
Create visualization → Metric
Data view: web-logs-*
Metric: Count
Title: Total Requests
Save as: total_requests
```

Success: 4 visualizations saved

## Lab 2: Advanced Aggregations (40 min)
Objective: Use complex aggregations

1. Create data table (terms + avg response size)

> Data tables combine multiple metrics in a tabular format. Here we split by request path and show both count and average byte size per path.

```
Create visualization → Data Table
Data view: web-logs-*
Split rows: Terms → path.keyword → Size 10
Metrics:
  Count
  Average → bytes
Title: Requests and Avg Bytes by Path
Save as: requests_avg_bytes_by_path
```

2. Create heat map (date histogram buckets)

> Heat maps use color intensity to show density. The intersection of time (x-axis) and path (y-axis) reveals traffic patterns — darker cells = more requests.

```
Create visualization → Heat map
Data view: web-logs-*
X-axis: Date histogram → @timestamp → 5m
Y-axis: Terms → path.keyword → Size 10
Metric: Count
Title: Request Density Heatmap
Save as: request_density_heatmap
```

3. Create metric with color ranges (application errors)

> Color ranges turn a metric into a status indicator: green/yellow/red based on thresholds. Useful for at-a-glance health checks.

```
Create visualization → Metric
Data view: app-logs-*
Filter: level : "ERROR"
Metric: Count
Ranges: 0-10 Green, 10-50 Yellow, 50-100 Red
Title: Application Error Count
Save as: app_error_count
```

Success: Aggregations saved and visible

## Lab 3: Build Operations Dashboard (45 min)
Objective: Create real-time monitoring dashboard

> A **dashboard** is a collection of visualizations on a single page. Dashboards share a common time range and filters — changing one affects all panels.

1. Create new dashboard

```
Menu (☰) → Analytics → Dashboard
Create dashboard
```

2. Add KPI panels

> "Add from library" reuses saved visualizations. Changes to the source visualization automatically update all dashboards using it.

```
Add from library:
  total_requests
  app_error_count
```

3. Add time-series and distribution panels

```
Add from library:
  response_time_over_time
  http_status_distribution
  top_request_paths
```

4. Create bar chart (error rate)

> Creating a visualization directly from the dashboard adds it to both the library and the current dashboard in one step.

```
Create visualization → Bar
Data view: web-logs-*
Filter (KQL): status >= 500 and status < 600
Metric: Count
X-axis: Terms → path.keyword → Size 10
Title: 5xx Errors by Path
Save as: errors_5xx_by_path
Add to dashboard
```

5. Configure auto-refresh and save

> Auto-refresh polls Elasticsearch at the set interval. Useful for live monitoring — but disable it for dashboards used in analysis to avoid unnecessary load.

```
Top right → Refresh every → 30 seconds
Save dashboard
Name: web_app_operations_dashboard
```

Success: Dashboard displays live operational metrics

## Lab 4: Add Interactivity and Filters (40 min)
Objective: Add controls and drilldowns

> **Controls** are interactive filters (dropdowns, sliders) embedded in the dashboard. They apply cross-panel filtering — selecting a value filters all visualizations simultaneously.

1. Open dashboard (edit)

```
Dashboard → web_app_operations_dashboard → Edit
```

2. Add time picker control

```
Controls → Add time slider control
Save dashboard
```

3. Add dropdown control (request method)

> Options list controls create a dropdown populated from unique field values. Users can select one or more values to filter the dashboard.

```
Dashboard → Controls → Add control
Control type: Options list
Data view: web-logs-*
Field: method.keyword
Title: Request Method
Save
```

4. Add range slider (response size)

> Range sliders filter by numeric range — useful for fields like byte size, response time, or status codes.

```
Dashboard → Controls → Add control
Control type: Range slider
Data view: web-logs-*
Field: bytes
Title: Response Size
Save
```

5. Configure drilldown link

> **Drilldowns** let users click a panel to navigate to Discover with the same filters applied — useful for investigating specific data points.

```
Edit panel: response_time_over_time (Lens)
Panel menu → Create drilldown
Open in Discover
Save
```

6. Test filter synchronization and save

```
Change Time Window
Select Request Method
Move Response Size slider
Save dashboard
```

Success: Controls filter all panels; drilldown works

## Lab 5: Optimize Dashboard Performance (35 min)
Objective: Improve dashboard loading

> Dashboard performance depends on: time range (smaller = faster), number of terms/buckets (fewer = faster), and refresh interval (off = no background load). Optimize all three for production dashboards.

1. Optimize time range

```
Time picker → Last 24 hours
Save dashboard
```

2. Reduce visualization complexity

> Reducing `size` (number of buckets) in terms aggregations and using wider histogram intervals decreases the number of Elasticsearch queries per panel.

```
Edit visualization: top_request_paths
Terms size: 10
Save
Edit visualization: request_density_heatmap
Y-axis size: 10
Interval: 5m
Save
```

3. Configure refresh and validate

```
Refresh every → Off
Browser refresh
```

Success: Dashboard loads quickly and remains responsive
