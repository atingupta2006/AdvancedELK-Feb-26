# High-Priority Improvement Plan (Modules 01–03)

**STATUS: ✅ COMPLETED**

Date: 2026-02-09  
Scope: **Only** improvements required to make the **hands-on labs** for **Modules 01–03** work reliably on **CentOS Stream 9** with full admin access.

---

## Execution Summary

All planned improvements have been implemented:

### ✅ Module 00 Created
- **NEW**: `hands-on/module-00/README.md` - Complete manual setup guide
- Students execute commands step-by-step for better understanding
- Includes troubleshooting for each component
- Covers all prerequisites: Elasticsearch, Kibana, Logstash, Filebeat

### ✅ Scripts Created
- `scripts/bootstrap-centos9.sh` - Automated bootstrap (optional, kept as reference)
- `scripts/validate.sh` - Environment validation script
- (Removed) Automated Module 02 setup script — students follow the Module 02 README labs.

### ✅ Sample Data Added
- `data/raw/access.log` - 30 web server access logs
- `data/raw/app.log` - 30 application JSON logs

### ✅ Configuration Files Created
- `hands-on/module-02/filebeat.yml` - Filebeat configuration
- `hands-on/module-02/logstash.conf` - Logstash pipeline
- `hands-on/module-02/ingest-pipeline.json` - Elasticsearch ingest pipeline

### ✅ Module Updates
- **Module 00**: New manual setup guide (step-by-step for students)
- **Module 01**: Updated prerequisites, references Module 00
- **Module 02**: Updated with CentOS commands, automated setup option
- **Module 03**: Added prerequisites, verified all queries match Module 02 data

### ✅ Repository Fixes
- Renamed `commands.sh` to `commands.bat` (was Windows batch syntax)

---

## Files Created/Modified

**New files:**
```
hands-on/module-00/README.md
scripts/bootstrap-centos9.sh
scripts/validate.sh
(Removed) hands-on/module-02/run.sh
hands-on/module-02/filebeat.yml
hands-on/module-02/logstash.conf
hands-on/module-02/ingest-pipeline.json
data/raw/access.log
data/raw/app.log
```

**Modified files:**
```
hands-on/module-01/README.md
hands-on/module-02/README.md
hands-on/module-03/README.md
commands.sh → commands.bat (renamed)
```

---

## Goals Achieved
- A fresh CentOS Stream 9 VM can run a **single bootstrap** and then complete the labs for Modules 01–03 without improvisation.
- Labs fail fast with clear messages when prerequisites are missing.
- Datasets and configuration artifacts are versioned in the repo so Module 03 queries match the data created in Module 02.

## Highest-Priority Risks (must fix)
1. **Linux setup script is currently Windows batch**
   - `GH/commands.sh` contains Windows batch syntax (e.g., `@echo off`, `REM`, backslash paths) and will fail on CentOS.

2. **No deterministic CentOS Stream 9 bootstrap**
   - Module 01 hands-on assumes Elasticsearch and Kibana already exist and are running.

3. **Security/auth workflow not documented**
   - Modern Elastic defaults often require credentials/enrollment and may use TLS by default.

4. **No lab validator**
   - There is no standard “pre-flight” to verify services, ports, credentials, and health.

5. **Module 02/03 assets likely incomplete**
   - Module 02 needs sample logs + ingestion configs committed.
   - Module 03 needs queries that match the actual fields produced in Module 02.

---

## Plan Overview (execute in order)

### Phase A — Reproducible CentOS Stream 9 environment (blocks everything)
**Deliverables**
- Replace/repair setup scripts:
  - Rename current `GH/commands.sh` to `GH/commands.bat` (or similar) and keep it Windows-only.
  - Create a real bash `GH/commands.sh` (or better: move Linux automation to `GH/scripts/*.sh`).

- Add `GH/scripts/bootstrap-centos9.sh` (idempotent):
  - Install prerequisites via `dnf` (e.g., `curl`, `jq`, `unzip`, `tar`, etc.).
  - Configure OS requirements (notably `vm.max_map_count`).
  - Install Elasticsearch + Kibana (and Logstash/Filebeat only if Module 02 uses them).
  - `systemctl enable --now` the services.
  - Open required firewall ports when appropriate (`firewall-cmd`) or document that firewall is disabled.
  - Print:
    - Kibana URL
    - Elasticsearch URL
    - Credential instructions (elastic password / enrollment token)
    - Location of CA cert if TLS is enabled

- Add `GH/scripts/validate.sh`:
  - Check services: `systemctl is-active elasticsearch kibana`
  - Check ports: 9200 and 5601 reachable locally
  - Check cluster health via API (and assert not `red`)
  - Print actionable errors (what to start/fix)

**Acceptance criteria (Phase A)**
- Fresh CentOS Stream 9 VM → run bootstrap → `validate.sh` passes with no manual steps beyond providing credentials when required.

---

### Phase B — Module 01 hands-on must be self-contained
**Work items**
- Update `GH/hands-on/module-01/README.md`:
  - Add a “One-time setup (CentOS Stream 9)” section pointing to `bootstrap-centos9.sh` and `validate.sh`.
  - Add a “Credentials / Login” subsection that matches the chosen security mode.
  - Ensure all curl examples match the chosen mode:
    - If TLS+auth: include `--cacert` and `-u elastic:...`
    - If non-secure training mode: explicitly document the exact config changes and restarts

**Acceptance criteria (Module 01)**
- Student can complete labs 1–3 using only documented commands.
- Dev Tools can run: `GET _cluster/health` and returns successfully.
- Index creation + Discover steps work with a known dataset.

---

### Phase C — Module 02 ingestion is deterministic and versioned
**Work items**
- Ensure required sample data exists in repo:
  - Add small, realistic sample logs under `GH/data/raw/` (include multiline samples if taught).

- Add versioned ingestion assets (as applicable to the module):
  - Filebeat config: `GH/hands-on/module-02/filebeat.yml`
  - Logstash pipeline: `GH/hands-on/module-02/logstash.conf`
  - Ingest pipeline JSON: `GH/hands-on/module-02/ingest-pipeline.json`
  - Templates / component templates / index templates if needed

- (Removed) Add an automated `run.sh` for Module 02.
  - Load pipeline/templates
  - Start shipper / run Logstash
  - Validate data arrived with `_count` and a sample `_search`

**Acceptance criteria (Module 02)**
- Validation is done by following the Module 02 README labs and verifying in Kibana Discover.
- Required fields exist for Module 03 queries.

---

### Phase D — Module 03 queries match the dataset from Module 02
**Work items**
- Update Module 03 docs so every example query matches real fields produced in Module 02.
- Add a short reset procedure (delete/recreate index/datastream) so results are repeatable.

**Acceptance criteria (Module 03)**
- Every query in the hands-on returns non-empty results on the seeded dataset.
- Sorting/pagination examples behave as described.
- Aggregations produce expected buckets/metrics without needing extra data.

---

## Guardrails (keep scope tight)
- Do not add extra UX, tooling, or “nice-to-haves” beyond what’s required for Modules 01–03 hands-on reliability.
- Prefer scripts that are:
  - idempotent
  - readable
  - explicit about assumptions

## Notes
- `GH/github.bat` performs risky actions (e.g., removing `.gitignore`, committing with `-`). Treat as secondary unless it blocks classroom execution.
