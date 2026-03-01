# Advanced ELK – Production Observability, Analytics & Security

**Duration:** 52 hours  
**Stack Version:** Elasticsearch & Kibana 9.x | Logstash 9.x | Beats 9.x  
**Platform:** CentOS Stream 9

---

## 🚀 Getting Started (Students)

**For CentOS Stream 9 environments:**

1. **Start here:** [Module 00 - Environment Setup](hands-on/module-00/README.md)
   - Step-by-step manual installation of Elasticsearch, Kibana, Logstash, Filebeat
   - System configuration and troubleshooting
   - Environment validation

2. **Then proceed to:**
   - [Module 01 - ELK Foundations Labs](hands-on/module-01/README.md)
   - [Module 02 - Data Ingestion Labs](hands-on/module-02/README.md)
   - [Module 03 - Querying & Analysis Labs](hands-on/module-03/README.md)
   - [Module 04 - Visualization & Dashboard Engineering](hands-on/module-04/README.md)
   - [Module 05 - Intermediate ELK: Production Readiness](hands-on/module-05/README.md)
   - [Module 06 - Advanced ELK: Scale, Observability & Security](hands-on/module-06/README.md)
   - [Module 07 - Capstone Project & Final Assessment](hands-on/module-07/README.md)

**Quick commands:**
```bash
# Clone this repository
git clone <repo-url>
cd GH

# Start with Module 00
cd hands-on/module-00
# Follow the README step-by-step
```

---

## 📁 Repository Structure

```
GH/
├── hands-on/                    # Student labs (start here!)
│   ├── module-00/              # Environment setup (REQUIRED FIRST)
│   ├── module-01/              # ELK foundations
│   ├── module-02/              # Data ingestion & indexing
│   ├── module-03/              # Querying & analysis
│   ├── module-04/              # Visualization & dashboard engineering
│   ├── module-05/              # Intermediate ELK: production readiness
│   ├── module-06/              # Advanced ELK: scale, observability & security
│   └── module-07/              # Capstone project & final assessment
├── data/raw/                    # Sample data files
└── docs/                        # Documentation
```

---

## Course Overview

This course provides a comprehensive, hands-on journey through the ELK (Elasticsearch, Logstash, Kibana) stack, focusing on production-grade observability, analytics, and security. It covers foundational concepts, advanced engineering, and real-world operational practices, culminating in a capstone project.

---

## Course Outline

### Module 00: Environment Setup (CentOS Stream 9)
- Manual step-by-step installation
- System configuration
- Service management
- Troubleshooting guide

### 1. ELK Fast-Track Foundations
A rapid alignment module to establish common ground before diving into advanced and production-grade topics.

#### 1.1 ELK / EFK Overview
- What is ELK / EFK and where it fits in modern observability stacks
- Core enterprise use cases: monitoring, analytics, observability, security
- High-level ELK architecture and component responsibilities
- End-to-end data flow: ingestion → processing → indexing → search → visualization

#### 1.2 Core Components Snapshot
- Elasticsearch essentials: index, document and field concepts
- JSON structure and REST API interaction overview
- Cluster concepts: nodes, shards and replicas
- Kibana orientation: Discover, Visualizations and Dashboards
- Role of Logstash, Beats and Elastic Agent in ingestion architectures

### 2. Data Ingestion & Indexing Pipelines
Designing scalable, fault-tolerant ingestion pipelines using trial-based Elastic environments.

#### 2.1 Ingestion Architecture & Design
- Beats → Logstash → Elasticsearch data flow
- Ingest pipelines vs Logstash pipelines
- Selecting ingestion strategies based on data type and volume

#### 2.2 Beats for Data Collection
- Filebeat and Metricbeat architecture
- Collecting application, system and infrastructure logs
- Modules vs custom configurations
- Multiline logs and structured formats

#### 2.3 Logstash Pipeline Design
- Input, filter and output stages in depth
- Grok, dissect and JSON parsing strategies
- Conditional routing and branching logic
- Error handling and resiliency patterns

#### 2.4 Indexing, Data Streams & Lifecycle
- Index creation strategies
- Data views and index patterns
- Data streams fundamentals
- Rollover and lifecycle basics

**Hands-On Labs:** Build and validate end-to-end ingestion pipelines using real application logs

### 3. Querying, Filtering & Analysis

#### 3.1 Kibana Query Language (KQL) in Practice
- Writing efficient KQL queries
- Field-based filtering and phrase searches
- Time picker behavior and time-series filtering

#### 3.2 Query DSL Fundamentals
- Query vs filter context
- Match, term and range queries
- Bool queries (must, should, must_not)
- Sorting and pagination

#### 3.3 Aggregations & Performance
- Metric and bucket aggregations
- Date histograms
- Aggregation performance considerations

### 4. Visualization & Dashboard Engineering

#### 4.1 Core Visualizations
- Line, bar and pie charts
- Choosing correct aggregations
- Common visualization mistakes

#### 4.2 Interactive Dashboards
- Building dashboards for operations and analytics
- Filters, controls and drill-downs
- Designing dashboards for different personas

#### 4.3 Scalable Dashboard Practices
- Performance-aware dashboard design
- Managing large dashboards at scale

### 5. Intermediate ELK – Production Readiness
Bridging the gap between basic usage and production-grade ELK deployments.

#### 5.1 Elasticsearch Mappings & Templates
- Keyword vs text fields
- Dynamic vs explicit mappings
- Index and component templates
- Custom analyzers and storage optimization

#### 5.2 Logstash Advanced Pipelines
- Advanced grok and dissect patterns
- Date, geo and enrichment filters
- Multi-output routing
- Dead-letter queues and error recovery

#### 5.3 Beats Deep Dive & Performance
- Enabling and tuning Beats modules
- Parsing complex application logs
- Performance tuning guidelines

#### 5.4 Advanced Querying & Optimization
- Complex bool queries
- Aggregation tuning
- Query performance optimization strategies

#### 5.5 Advanced Kibana Visualizations
- Lens deep dive
- TSVB for time-series analysis
- Vega for advanced custom visuals
- Canvas dashboards for storytelling

#### 5.6 Alerting & Operational Visibility
- Alert rules and connectors
- Threshold, metric and query-based alerts
- Notification strategies and alert hygiene
- GenAI-assisted alert triage workflows

### 6. Advanced ELK – Scale, Observability & Security
Advanced concepts delivered using trial clusters and controlled environments.

#### 6.1 Elasticsearch Internals & Performance Engineering
- Lucene internals and segment lifecycle
- Distributed search and sharding mechanics
- Shard sizing and segment merge behavior
- Advanced ILM and rollover strategies
- Translating internals into tuning decisions

#### 6.2 Logstash at Scale
- Persistent queues and backpressure handling
- Pipeline-to-pipeline communication patterns
- Multi-worker pipeline design
- JVM tuning principles
- Identifying and resolving pipeline bottlenecks

#### 6.3 Integrations & Streaming Pipelines
- Kafka input/output architecture
- JDBC integrations
- Data enrichment patterns
- Logstash vs Fluent Bit vs Beats (design comparison)

#### 6.4 Beats & Elastic Agent (Advanced)
- Fleet Server architecture
- Agent policies and enrollment
- Data streams with Fleet
- Sampling, processors and drop rules

#### 6.5 Advanced Analytics & Querying
- Discover vs KQL vs DSL vs ESQL
- ESQL joins, lookups and CASE expressions
- Aggregation windows and rollups
- Interpreting analytical results
- Automating investigation workflows with GenAI agents

#### 6.6 Observability Deep Dive
- Distributed tracing architecture
- Auto-instrumentation concepts
- Correlating logs, metrics and traces
- Service maps and topology views
- Defining SLOs and SLAs
- Applying AIOps concepts and synthetic monitoring

#### 6.7 Security & SIEM Concepts
- Elastic Security architecture
- Detection rules and threat intelligence integration
- Endpoint security concepts with Fleet
- Correlation logic and event chaining
- Investigation workflows and cases

#### 6.8 Troubleshooting & Failure Handling
- Unassigned shards and cluster health issues
- JVM GC pressure and memory tuning
- Query rejections and timeouts
- Node instability and rolling upgrades
- Disaster recovery and multi-region strategies
- GenAI-assisted cluster diagnostics

### 7. Capstone Project & Final Assessment
A guided, end-to-end project using trial clusters:
- Designing a complete ingestion and observability platform
- Building advanced dashboards and analytics
- Implementing alerting strategies
- Applying security controls and RBAC
- Performance tuning under simulated load
- Failure simulation and recovery exercises

---

**Hands-on labs and real-world scenarios are integrated throughout the course.**
