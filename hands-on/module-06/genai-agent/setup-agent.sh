#!/bin/bash
# ============================================================
# GenAI Agent — One-Command Setup
# Creates ~/genai-agent, installs deps, copies script, writes .env.
#
# Usage:  bash setup-agent.sh <ES_HOST> [LLM_API_KEY]
# Example: bash setup-agent.sh http://10.20.1.10:9200 sk-proj-xxx
# ============================================================
set -e

ES_HOST="${1:-}"
LLM_KEY="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$HOME/genai-agent"

if [ -z "$ES_HOST" ]; then
    read -p "Elasticsearch host (e.g., http://10.20.1.10:9200): " ES_HOST
fi
if [ -z "$LLM_KEY" ]; then
    read -p "LLM API key (from instructor, or Enter to skip): " LLM_KEY
fi

echo ""
echo "=== GenAI Agent Setup ==="
echo "ES Host:  $ES_HOST"
echo "Work Dir: $WORK_DIR"
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
ES_API_KEY=
LLM_API_KEY=$LLM_KEY
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4o-mini
ENVFILE

# Quick verification
python3 -c "import py_compile; py_compile.compile('elk_agent.py'); print('  Script syntax: OK')"
python3 -c "import openai, requests, dotenv; print('  Dependencies:  OK')"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Run the agent:"
echo "  cd $WORK_DIR && source .venv/bin/activate"
echo '  python3 elk_agent.py "An alert fired saying error count exceeded. Which service is failing?"'
