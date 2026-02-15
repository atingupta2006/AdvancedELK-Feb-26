# Module 04 – Visualizations & Dashboard Engineering

> **Stack Version**: Elasticsearch 9.x | Kibana 9.x

Repo location used in class: `~/GH`

## 📖 Module Overview
Data in Elasticsearch is useless if you can't see it. **Kibana** is the window into your data.

In this module, we transition from "Engineers" (ingesting logs) to "Analysts" (visualizing logs). You will build a complete **Operational Dashboard** that a Site Reliability Engineer (SRE) would use to monitor the health of the web servers we set up in Module 02.

---

## 🧠 Concepts & Architecture (Read First)

### 1. The Visualization Pyramid
Building a dashboard is a 3-step process. You cannot skip steps.

| Layer | Component | Analogy | Description |
| :--- | :--- | :--- | :--- |
| **Top** | **Dashboard** | The Cockpit | A collection of visualizations on one screen. |
| **Middle** | **Visualization** | The Gauge | A single chart (Line, Bar, Metric). Answers *one* specific question. |
| **Base** | **Aggregation** | The Math | The query logic: `count()`, `sum()`, `average()`. |

### 2. Aggregations: Buckets vs. Metrics
Kibana "Lens" hides the complexity, but you must understand what is happening under the hood.

*   **Buckets (The "X-Axis")**: How do you want to group data?
    *   *Examples*: `terms` (group by URL), `date_histogram` (group by hour), `range` (group by size 0-1kb, 1kb+).
*   **Metrics (The "Y-Axis")**: What do you want to calculate in each group?
    *   *Examples*: `count` (how many hits?), `average` (how slow was it?), `percentile` (what is the 99th percentile latency?).

### 3. Lens vs. Classic
*   **Kibana Lens**: The modern, drag-and-drop builder. **We will use this.**
*   **Classic Visualizations**: The older, strict builders (Pie, Vertical Bar). Legacy modes.

---

## Prerequisites

- [Module 02](../module-02/README.md) completed (Data ingested into `web-logs-*` and `app-logs-*`).
- Kibana: `http://127.0.0.1:5601`

---

## Lab 1: Core Visualizations
**Use Case**: Your manager asks: *"How is traffic trending? What are our top errors? Which pages are most popular?"* You need distinct charts for each answer.

1. **Open Kibana Lens**
   *   Menu (☰) → **Analytics** → **Visualize Library**
   *   Click **Create visualization** button.
   *   Select **Lens** (or just click "Lens" if it's the default).

2. **Chart A: Traffic Trend (Line Chart)**
   *   *Question*: "Is traffic spiking?"
   *   **Data View**: Ensure `web-logs-*` is selected.
   *   **Horizontal axis** (X): Drag `@timestamp` field.
   *   **Vertical axis** (Y): Drag `Records` (Count of documents).
   *   **Visualization Type**: Change from "Bar" to "Line".
   *   **Save As**: `Web - Traffic Trend`.

3. **Chart B: Top Patterns (Bar Chart)**
   *   *Question*: "Which HTTP methods are most common?"
   *   **Horizontal axis** (X): Drag `client_ip` to the workspace.
       *   *Note*: Lens might auto-select "Date Histogram". Change it to "Top values" if needed.
   *   **Refinement**: `client_ip` is too random. Let's look at Status Codes instead.
       *   **Remove** `client_ip`.
       *   **Drag** `status` field to the Horizontal axis.
   *   **Breakdown by**: Drag `method.keyword` to the "Breakdown by" field (right side).
   *   **Visualization Type**: Ensure it is set to **Stacked Bar**.
   *   **Save As**: `Web - Status Codes by Method`.

4. **Chart C: Response Distribution (Pie Chart)**
   *   *Question*: "What is the ratio of success (200) vs error (500)?"
   *   **Slice by**: Drag `status` field.
   *   **Size by**: `Records`.
   *   **Visualization Type**: Donut / Pie.
   *   **Save As**: `Web - Status Distribution`.

5. **Chart D: Total Hits (Metric)**
   *   *Question*: "How many total requests today?"
   *   **Metric**: Drag `Records` to the middle.
   *   **Visualization Type**: Metric (Big Number).
   *   **Save As**: `Web - Total Hits`.

**Success**: You now have 4 independent saved objects in the library.

---

## Lab 2: Advanced Aggregations (Heat Maps)
**Use Case**: A line chart shows "when" traffic happened. A bar chart shows "who". But you need to see "When did Who do What?" combined.

1. **Create New Visualization (Lens)**
   *   Data View: `web-logs-*`.

2. **Build a Heat Map**
   *   *Concept*: A standard operational view. X=Time, Y=Status Code, Color=Count.
   *   **Visualization Type**: Select **Heatmap**.
   *   **Horizontal axis**: `@timestamp`.
   *   **Vertical axis**: Drag `status` field.
   *   **Cell value**: `Records` (Count).

3. **Refine the Logic**
   *   **Configure**: In the right panel, find "Cell value" (Records).
   *   Click on the **Color palette** dropdown (it likely shows blue gradient).
   *   Select **"Temperature"** (Blue to Red) or **"Red-Yellow-Green"** (and click "Invert" if needed so Red is high).
   *   *Why*: We want high error counts (hotspots) to look alarming (Red), not calm (Blue).

4. **Save As**: `Web - Heatmap Status over Time`.

**Success**: You can visually spot a cluster of 500 errors occurring at 2:00 PM.

---

## Lab 3: Build Operations Dashboard
**Use Case**: You cannot open 5 diverse charts one by one during an outage. You need a "Single Pane of Glass".

1. **Create Dashboard**
   *   Menu (☰) → **Analytics** → **Dashboard**.
   *   Click **Create dashboard**.

2. **Add Visualizations**
   *   Click **Add from library**.
   *   Select the 5 visualizations you created in Lab 1 & 2:
       1.  `Web - Total Hits`
       2.  `Web - Traffic Trend`
       3.  `Web - Status Codes by Method`
       4.  `Web - Status Distribution`
       5.  `Web - Heatmap Status over Time`

3. **Layout & Design (The "SRE" Layout)**
   *   **Concept**: Metrics on top (fast read), Timelines in middle (trends), Details at bottom (investigation).
   *   *Action*:
       *   Resize `Total Hits` to be a small box at the top left.
       *   Put `Traffic Trend` next to it, spanning the rest of the width.
       *   Place `Heatmap` below the trend.
       *   Place `Pie` and `Bar` charts side-by-side at the bottom.

4. **Save Dashboard**
   *   Title: `[Ops] Web Server Monitor`.
   *   Description: "L1 Support Dashboard for Nginx Logs".
   *   Store time with dashboard: **Off** (We want it to default to "Now", not "Last 15 minutes fixed").

**Success**: You have a fully functional operational dashboard.

---

## Lab 4: Add Interactivity & Filters
**Use Case**: The dashboard shows a spike in errors. You need to investigate. You want to click "500" and have the whole dashboard filter to just 500 errors.

1. **Drill-down (Native)**
   *   This works out of the box in Kibana Lens.
   *   *Action*: Specific click test.
   *   Click the "500" slice in your Pie Chart.
   *   **Result**: Watch the "Filter Bar" (top left) automatically add `status: 500`.
   *   **Result**: Watch the Traffic Trend line chart change to show *only* the error trend.
   *   *Action*: Remove the filter to reset.

2. **Add Input Controls (The "Slicer")**
   *   These are dropdown menus that sit at the top of the dashboard.
   *   Click **Edit** on the dashboard.
   *   Click **Controls** (Top menu bar, near "Cancel/Save").
   *   **Add control** -> **Options list**.
   *   **Field**: `method.keyword` (or `client_ip` for per-client filtering).
   *   Click **Add**.
   *   *Test*: Select "POST". Watch every chart update to show only "POST" traffic.
   *   Click to close the control panel.

3. **Configure Time Range**
   *   By default, it might be "Last 15 minutes".
   *   Change Time Picker to **"Last 7 days"** to see the test data we loaded.

4. **Save Changes**.

**Success**: You can now filter the entire extensive dashboard by simply selecting a Country or IP from the dropdown, without writing a single KQL query.

---

## Lab 5: Optimize for Performance
**Use Case**: Your dashboard takes 10 seconds to load. Users stop using it. You need to make it fast.

1. **Inspect Performance**
   *   Click **Edit**.
   *   Click the **Gear Icon** (Panel options) on the Heatmap.
   *   Select **Inspect**.
   *   Switch tab to **Requests**.
   *   Look at **Request duration**. (e.g., 50ms).

2. **Optimization Strategy: Refresh Rate**
   *   *Problem*: If 100 users have this open, and it auto-refreshes every 5 seconds, your cluster dies.
   *   *Action*: Click the **Arrow** next to the Refresh button.
   *   Set specific Auto-refresh: **Off** or **1 hour**.
   *   *Why*: Operational dashboards need live data (5s), but Executive dashboards do not (1h). Be intentional.

3. **Optimization Strategy: Precision**
   *   *Action*: Edit the "Traffic Trend".
   *   Look for "Auto interval".
   *   If you force "Seconds" bucket on a "Year" view, you generate millions of buckets.
   *   **Verification**: Ensure it is set to "Auto" so Kibana adjusts buckets dynamically.

**Success**: You understand how to debug slow panels and protect the cluster from "Dashboard DoS".
