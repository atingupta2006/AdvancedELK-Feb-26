# tools/

Local helper scripts. This folder is intentionally **not committed** (except this README).

## Web search helper (API key required)

Create a `.env` file at the repo root (it is ignored by git):

- `SERPAPI_API_KEY=...`
- `SERPAPI_ENDPOINT=https://serpapi.com/search.json` (optional)

Run the script:

- `python tools/search_web.py "your query" --top 5`

Notes:
- This uses SerpAPI (requires a key).
- Results are printed as JSON to stdout.
