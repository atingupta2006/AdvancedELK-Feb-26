import argparse
import json
import os
import sys
import urllib.parse
import urllib.request


def _load_dotenv_if_present(dotenv_path: str) -> None:
    # Minimal .env loader (KEY=VALUE, ignores comments/blank lines)
    if not os.path.exists(dotenv_path):
        return
    with open(dotenv_path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            if key.startswith("export "):
                key = key[len("export ") :].strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value


def _load_dotenv_from_candidates(paths: list[str]) -> list[str]:
    checked: list[str] = []
    for path in paths:
        normalized = os.path.abspath(path)
        if normalized in checked:
            continue
        checked.append(normalized)
        _load_dotenv_if_present(normalized)
    return checked


def serpapi_search(
    query: str,
    *,
    top: int,
    engine: str,
    hl: str,
    gl: str,
    safe: str,
) -> dict:
    api_key = os.environ.get("SERPAPI_API_KEY")
    endpoint = os.environ.get("SERPAPI_ENDPOINT", "https://serpapi.com/search.json")
    if not api_key:
        raise RuntimeError("Missing SERPAPI_API_KEY (set it in environment or .env)")

    # SerpAPI docs: https://serpapi.com/search-api
    # Common params for Google engine: q, engine, api_key, num, hl, gl, safe
    params = {
        "engine": engine,
        "q": query,
        "api_key": api_key,
        "num": str(top),
        "hl": hl,
        "gl": gl,
        "safe": safe,
    }
    url = f"{endpoint}?{urllib.parse.urlencode(params)}"

    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read().decode("utf-8")
        return json.loads(data)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Web search (SerpAPI) -> JSON")
    parser.add_argument("query", help="Search query")
    parser.add_argument("--top", type=int, default=5, help="Number of results")
    parser.add_argument("--engine", default="google", help="SerpAPI engine, e.g. google")
    parser.add_argument("--hl", default="en", help="Host language, e.g. en")
    parser.add_argument("--gl", default="us", help="Geolocation, e.g. us")
    parser.add_argument(
        "--safe",
        default="active",
        choices=["active", "off"],
        help="SafeSearch (SerpAPI): active|off",
    )
    args = parser.parse_args(argv)

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    workspace_root = os.path.abspath(os.path.join(repo_root, ".."))
    checked_paths = _load_dotenv_from_candidates(
        [
            os.path.join(os.getcwd(), ".env"),
            os.path.join(repo_root, ".env"),
            os.path.join(workspace_root, ".env"),
        ]
    )

    try:
        result = serpapi_search(
            args.query,
            top=args.top,
            engine=args.engine,
            hl=args.hl,
            gl=args.gl,
            safe=args.safe,
        )
    except Exception as e:
        message = str(e)
        if "Missing SERPAPI_API_KEY" in message:
            message += "\nChecked .env locations:" + "".join(f"\n- {p}" for p in checked_paths)
        print(message, file=sys.stderr)
        return 2

    try:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    except BrokenPipeError:
        # Common when piping to `head`/`more` and the consumer exits early.
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
