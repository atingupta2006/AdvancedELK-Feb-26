#!/bin/bash
# ============================================================
# GenAI Agent — One-Command Setup (Secure Variant)
# Creates ~/genai-agent, installs deps, copies script, writes .env
# with ES API key for authenticated access.
#
# Usage:  bash setup-agent-secure.sh <ES_HOST> <LLM_API_KEY> [ES_API_KEY]
# Example: bash setup-agent-secure.sh http://192.168.56.101:9200 sk-proj-xxx YWJjMTIzOnhlejc4OQ==
# ============================================================
set -e

ES_HOST="${1:-}"
LLM_KEY="${2:-}"
ES_API_KEY="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$HOME/genai-agent"

if [ -z "$ES_HOST" ]; then
    read -p "Elasticsearch host (e.g., http://192.168.56.101:9200): " ES_HOST
fi
if [ -z "$LLM_KEY" ]; then
    read -p "LLM API key (from instructor, or Enter to skip): " LLM_KEY
fi
if [ -z "$ES_API_KEY" ]; then
    read -p "ES API key (encoded value from POST _security/api_key, or Enter to skip): " ES_API_KEY
fi

echo ""
echo "=== GenAI Agent Setup (Secure) ==="
echo "ES Host:    $ES_HOST"
echo "ES API Key: ${ES_API_KEY:+set (hidden)}${ES_API_KEY:-not set}"
echo "Work Dir:   $WORK_DIR"
echo ""

echo "[1/4] Creating workspace..."
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "[2/4] Python environment..."
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi
source .venv/bin/activate
pip install -q openai requests python-dotenv

echo "[3/4] Copying agent script..."
cp "$SCRIPT_DIR/elk_agent.py" .

echo "[4/4] Writing .env..."
cat > .env << ENVFILE
ES_HOST=$ES_HOST
ES_API_KEY=$ES_API_KEY
LLM_API_KEY=$LLM_KEY
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4o-mini
ENVFILE

# Quick verification
python3 -c "import py_compile; py_compile.compile('elk_agent.py'); print('  Script syntax: OK')"
python3 -c "import openai, requests, dotenv; print('  Dependencies:  OK')"

# Verify ES connectivity with API key
if [ -n "$ES_API_KEY" ]; then
    echo "  ES connection: $(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: ApiKey $ES_API_KEY" "$ES_HOST/_cluster/health") (200=OK, 401=bad key)"
else
    echo "  ES connection: $(curl -s -o /dev/null -w '%{http_code}' "$ES_HOST/_cluster/health") (200=OK, 401=needs auth)"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Run the agent:"
echo "  cd $WORK_DIR && source .venv/bin/activate"
echo '  python3 elk_agent.py "An alert fired saying error count exceeded. Which service is failing?"'
