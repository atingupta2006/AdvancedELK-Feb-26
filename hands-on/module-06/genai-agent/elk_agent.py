"""
ELK Investigation Agent
Accepts a natural-language question, generates Elasticsearch queries,
executes them read-only, and produces a structured summary.
"""
import json
import os
import sys
import requests

# Load .env file if python-dotenv is available (optional)
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass  # python-dotenv not installed — use environment variables directly

# --- Configuration ---
ES_HOST = os.environ.get("ES_HOST", "http://localhost:9200")  # override via .env
ES_API_KEY = os.environ.get("ES_API_KEY", "")

# OpenAI-compatible endpoint (works with OpenAI, Azure OpenAI, or local models)
LLM_API_KEY = os.environ.get("LLM_API_KEY", "")
LLM_BASE_URL = os.environ.get("LLM_BASE_URL", "https://api.openai.com/v1")
LLM_MODEL = os.environ.get("LLM_MODEL", "gpt-4o-mini")

# --- Guardrails ---
ALLOWED_ES_ENDPOINTS = [
    "_search", "_count", "_query", "_cluster/health",
    "_cat/nodes", "_cat/shards", "_cat/indices",
    "_cat/allocation", "_cluster/allocation/explain",
    "_cluster/stats", "_cluster/settings", "_nodes/stats"
]

BLOCKED_METHODS = ["PUT", "DELETE", "PATCH"]

def es_request(method, path, body=None):
    """Execute a read-only Elasticsearch request with guardrails."""
    method = method.upper()

    if method in BLOCKED_METHODS:
        return {"error": f"Blocked: {method} is not allowed (read-only agent)"}

    endpoint = path.lstrip("/").split("?")[0]
    # Check if the endpoint matches any allowed pattern
    index_part = endpoint.split("/")[0] if "/" in endpoint else ""
    api_part = "/".join(endpoint.split("/")[1:]) if "/" in endpoint else endpoint

    allowed = any(api_part.startswith(ep.lstrip("/")) or endpoint.startswith(ep.lstrip("/"))
                  for ep in ALLOWED_ES_ENDPOINTS)
    if not allowed:
        return {"error": f"Blocked: endpoint '{path}' is not in the allowed list"}

    headers = {"Content-Type": "application/json"}
    if ES_API_KEY:
        headers["Authorization"] = f"ApiKey {ES_API_KEY}"

    url = f"{ES_HOST}/{path}"
    try:
        if method == "GET" and body:
            resp = requests.get(url, headers=headers, json=body, timeout=30)
        elif method == "POST" and body:
            resp = requests.post(url, headers=headers, json=body, timeout=30)
        else:
            resp = requests.get(url, headers=headers, timeout=30)

        try:
            payload = resp.json()
        except Exception:
            payload = {"raw_response": resp.text}

        if resp.status_code >= 400:
            return {
                "error": "Elasticsearch request failed",
                "status_code": resp.status_code,
                "path": path,
                "details": payload
            }

        return payload
    except Exception as e:
        return {"error": str(e)}


def ask_llm(system_prompt, user_message):
    """Send a prompt to the LLM and return the response text."""
    try:
        from openai import OpenAI
        client = OpenAI(api_key=LLM_API_KEY, base_url=LLM_BASE_URL)
        response = client.chat.completions.create(
            model=LLM_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message}
            ],
            temperature=0.2
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"LLM Error: {e}"


# --- System Prompts ---
PLANNER_PROMPT = """You are an Elasticsearch investigation planner.
Given a natural-language question, generate a JSON array of Elasticsearch queries to answer it.

Rules:
- Only use read-only operations: GET with _search, _count, _cluster/health, _cat/*. Use POST for _query (ES|QL).
- Available indices: web-logs-*, app-logs-*, training-app-pipeline-*, enriched-logs-*.
- Available fields in web-logs-*: @timestamp, client_ip, method, path, status (integer), bytes (integer).
- Available fields in app-logs-*/training-app-pipeline-*: @timestamp, level, service, message, user_id, order_id, amount, error, session_id, product_id, quantity.
- Available fields in enriched-logs-*: @timestamp, user_id (text, use user_id.keyword for aggs/terms), action (text, use action.keyword), status (text, use status.keyword; values "success" or "failed"), amount (float), page (text, use page.keyword), file (text, use file.keyword), endpoint (text, use endpoint.keyword), user_info.name (text, use user_info.name.keyword), user_info.department (text, use user_info.department.keyword), enriched.
- IMPORTANT: All string fields in enriched-logs-* use dynamic mapping (type: text with .keyword sub-field). Always use the .keyword sub-field for ALL aggregation types (terms, value_count, cardinality, etc.), term queries, and sorting — never use the bare text field name in any aggregation or term query.
- Return ONLY valid JSON. No markdown, no explanation.

Output format:
[
  {"step": 1, "description": "...", "method": "GET", "path": "web-logs-*/_search", "body": {...}},
  {"step": 2, "description": "...", "method": "GET", "path": "app-logs-*/_search", "body": {...}}
]
"""

SUMMARIZER_PROMPT = """You are an incident investigation summarizer.
Given the original question and query results, produce a structured summary.

Output format:
## Investigation Summary
**Question**: <original question>
**Findings**:
1. <finding from query 1>
2. <finding from query 2>
...
**Impact Assessment**: <scope and severity>
**Likely Root Cause**: <based on evidence>
**Recommended Next Step**: <specific action — but state that human approval is required>
**Confidence**: <high/medium/low with explanation>
"""


def _repair_json_array(raw):
    """Attempt to repair malformed JSON arrays from LLM output.
    Common issues: extra closing braces, missing commas, trailing commas.
    """
    import re
    # Strategy 1: direct parse
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        pass

    # Strategy 2: fix each object in the array individually
    # Find individual step objects and parse them separately
    # Match top-level { ... } blocks separated by commas
    steps = []
    depth = 0
    start = None
    for i, ch in enumerate(raw):
        if ch == '{' and depth == 0:
            start = i
            depth = 1
        elif ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0 and start is not None:
                candidate = raw[start:i+1]
                try:
                    steps.append(json.loads(candidate))
                    start = None
                except json.JSONDecodeError:
                    # Try trimming trailing braces one at a time
                    for trim in range(1, 4):
                        try:
                            steps.append(json.loads(raw[start:i+1-trim]))
                            start = None
                            break
                        except json.JSONDecodeError:
                            continue
                    if start is not None:
                        start = None  # skip unparseable object
            elif depth < 0:
                # Extra closing brace — reset and try to recover
                depth = 0
                if start is not None:
                    candidate = raw[start:i]
                    try:
                        steps.append(json.loads(candidate))
                    except json.JSONDecodeError:
                        pass
                    start = None

    if steps:
        return steps

    # Strategy 3: simple brace reduction (legacy)
    repaired = re.sub(r'\}\}\}\}', '}}}', raw)
    repaired = re.sub(r'\}\}\}', '}}', repaired)
    try:
        return json.loads(repaired)
    except json.JSONDecodeError:
        return None


def run_investigation(question):
    """Run the full investigation pipeline."""
    print(f"\n{'='*60}")
    print(f"QUESTION: {question}")
    print(f"{'='*60}")

    # Step 1: Generate query plan
    print("\n[Step 1] Generating query plan...")
    plan_text = ask_llm(PLANNER_PROMPT, question)
    print(f"Query plan:\n{plan_text}")

    try:
        query_plan = json.loads(plan_text)
    except json.JSONDecodeError:
        # Try to extract JSON from markdown code blocks or raw text
        import re
        json_match = re.search(r'\[.*\]', plan_text, re.DOTALL)
        if json_match:
            query_plan = _repair_json_array(json_match.group())
            if query_plan is None:
                print("ERROR: Could not parse query plan as JSON (even after repair)")
                print(f"Raw plan text:\n{plan_text}")
                return
        else:
            print("ERROR: Could not parse query plan as JSON")
            return

    # Step 2: Execute queries (read-only)
    print(f"\n[Step 2] Executing {len(query_plan)} queries (read-only)...")
    results = []
    query_errors = []
    data_gaps = []
    for step in query_plan:
        desc = step.get("description", f"Step {step.get('step', '?')}")
        method = step.get("method", "GET")
        path = step.get("path", "")
        body = step.get("body")

        print(f"  Running: {desc}")
        print(f"    {method} {path}")

        result = es_request(method, path, body)

        if isinstance(result, dict) and "error" in result:
            query_errors.append({
                "step": step.get("step"),
                "description": desc,
                "path": path,
                "error": result.get("error"),
                "status_code": result.get("status_code")
            })
            print(f"    WARNING: Query failed for {path}")
        elif isinstance(result, dict) and "_shards" in result:
            shard_info = result.get("_shards", {})
            total_shards = shard_info.get("total")
            if isinstance(total_shards, int) and total_shards == 0:
                data_gaps.append({
                    "step": step.get("step"),
                    "description": desc,
                    "path": path,
                    "reason": "No matching shards/indices for this query"
                })
                print(f"    WARNING: No matching shards for {path}")

        # Trim large results for the LLM context
        result_str = json.dumps(result, indent=2)
        if len(result_str) > 3000:
            result_str = result_str[:3000] + "\n... (truncated)"

        results.append({
            "step": step.get("step"),
            "description": desc,
            "result": result_str
        })

    # Step 3: Summarize findings
    print(f"\n[Step 3] Generating investigation summary...")

    # Determine how many queries actually succeeded
    total_queries = len(query_plan)
    failed_count = len(query_errors) + len(data_gaps)
    succeeded_count = total_queries - failed_count

    if failed_count > 0 and succeeded_count == 0:
        # ALL queries failed — no data for the LLM to work with
        print(f"\n{'='*60}")
        print("INVESTIGATION SUMMARY")
        print(f"{'='*60}")
        print("## Investigation Summary")
        print(f"**Question**: {question}")
        print("**Findings**:")
        print("1. Investigation evidence is incomplete — all queries failed or returned no data.")

        idx = 2
        for err in query_errors:
            status = err.get("status_code")
            status_text = f" (status {status})" if status else ""
            print(f"{idx}. Step {err.get('step')}: {err.get('path')} failed{status_text}.")
            idx += 1

        for gap in data_gaps:
            print(f"{idx}. Step {gap.get('step')}: {gap.get('path')} had no matching shards/indices.")
            idx += 1

        print("**Impact Assessment**: Inconclusive — no usable query results.")
        print("**Recommended Next Step**: Check that the target indices exist and contain data. Human approval is required before any remediation.")
        print("**Confidence**: Low - no evidence collected.")

        print(f"\n{'='*60}")
        print("HUMAN APPROVAL REQUIRED")
        print("Review the summary above. The agent will NOT take any")
        print("action without your explicit confirmation.")
        print(f"{'='*60}")
        return

    # Build context — include both successes and failures for the LLM
    context = f"Original question: {question}\n\nQuery results:\n"
    for r in results:
        context += f"\n--- Step {r['step']}: {r['description']} ---\n{r['result']}\n"

    if query_errors:
        context += "\n--- Query Errors (some queries failed) ---\n"
        for err in query_errors:
            status = err.get("status_code")
            status_text = f" (HTTP {status})" if status else ""
            context += f"  Step {err.get('step')} ({err.get('path')}): {err.get('error')}{status_text}\n"
        context += "Note: a 400 from _cluster/allocation/explain means there are no unassigned shards — this is expected when the cluster is green.\n"

    if data_gaps:
        context += "\n--- Data Gaps (indices with no matching shards) ---\n"
        for gap in data_gaps:
            context += f"  Step {gap.get('step')} ({gap.get('path')}): {gap.get('reason')}\n"
        context += "Note: missing indices may mean those log types were not configured. Base your assessment on the data that IS available.\n"

    summary = ask_llm(SUMMARIZER_PROMPT, context)
    print(f"\n{'='*60}")
    print("INVESTIGATION SUMMARY")
    print(f"{'='*60}")
    print(summary)

    # Step 4: Human approval gate
    print(f"\n{'='*60}")
    print("HUMAN APPROVAL REQUIRED")
    print("Review the summary above. The agent will NOT take any")
    print("action without your explicit confirmation.")
    print(f"{'='*60}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        question = " ".join(sys.argv[1:])
    else:
        question = input("Enter your investigation question: ")
    run_investigation(question)
