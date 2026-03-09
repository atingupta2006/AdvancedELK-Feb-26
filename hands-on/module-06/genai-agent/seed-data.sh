#!/bin/bash
# ============================================================
# Seed sample web-logs and app-logs for Lab 14 agent demos.
# Idempotent — skips if data already exists.
#
# Usage:  bash seed-data.sh [ES_HOST]
# Example: bash seed-data.sh http://10.20.1.10:9200
# ============================================================

ES_HOST="${1:-http://localhost:9200}"

# Portable JSON count extractor (no python dependency)
_count() { grep -o '"count":[0-9]*' | head -1 | cut -d: -f2; }

echo "=== Seeding Sample Data ==="
echo "Target: $ES_HOST"

# ---- Check existing data ----
WEB_COUNT=$(curl -s "$ES_HOST/web-logs-*/_count" 2>/dev/null | _count || echo "0")
APP_COUNT=$(curl -s "$ES_HOST/app-logs-*/_count" 2>/dev/null | _count || echo "0")

if [ "$WEB_COUNT" -gt 0 ] 2>/dev/null && [ "$APP_COUNT" -gt 0 ] 2>/dev/null; then
    echo "Data already exists: web-logs=$WEB_COUNT, app-logs=$APP_COUNT"
    echo "To re-seed: curl -X DELETE $ES_HOST/web-logs-2026.03.07 && curl -X DELETE $ES_HOST/app-logs-2026.03.07"
    exit 0
fi

# ---- Seed web-logs (12 docs) ----
echo ""
echo "[1/2] Seeding web-logs-2026.03.07 (12 documents)..."
curl -s -X POST "$ES_HOST/web-logs-2026.03.07/_bulk" \
  -H "Content-Type: application/json" \
  --data-binary @- << 'BULK'
{"index":{}}
{"@timestamp":"2026-03-07T08:01:12Z","client_ip":"10.20.1.50","method":"GET","path":"/api/products","status":200,"bytes":1234}
{"index":{}}
{"@timestamp":"2026-03-07T08:02:45Z","client_ip":"10.20.1.51","method":"GET","path":"/api/checkout","status":500,"bytes":0}
{"index":{}}
{"@timestamp":"2026-03-07T08:03:18Z","client_ip":"10.20.1.52","method":"POST","path":"/api/orders","status":201,"bytes":487}
{"index":{}}
{"@timestamp":"2026-03-07T08:04:55Z","client_ip":"10.20.1.50","method":"GET","path":"/api/checkout","status":500,"bytes":0}
{"index":{}}
{"@timestamp":"2026-03-07T08:05:33Z","client_ip":"10.20.1.53","method":"GET","path":"/api/products","status":200,"bytes":2048}
{"index":{}}
{"@timestamp":"2026-03-07T08:06:10Z","client_ip":"10.20.1.54","method":"GET","path":"/images/logo.png","status":404,"bytes":0}
{"index":{}}
{"@timestamp":"2026-03-07T08:07:42Z","client_ip":"10.20.1.55","method":"GET","path":"/api/checkout","status":500,"bytes":0}
{"index":{}}
{"@timestamp":"2026-03-07T08:08:19Z","client_ip":"10.20.1.51","method":"GET","path":"/api/products","status":200,"bytes":1567}
{"index":{}}
{"@timestamp":"2026-03-07T08:09:01Z","client_ip":"10.20.1.56","method":"POST","path":"/api/orders","status":201,"bytes":512}
{"index":{}}
{"@timestamp":"2026-03-07T08:10:28Z","client_ip":"10.20.1.50","method":"GET","path":"/api/users/profile","status":200,"bytes":890}
{"index":{}}
{"@timestamp":"2026-03-07T08:11:45Z","client_ip":"10.20.1.57","method":"GET","path":"/api/checkout","status":503,"bytes":0}
{"index":{}}
{"@timestamp":"2026-03-07T08:12:32Z","client_ip":"10.20.1.52","method":"GET","path":"/api/products","status":200,"bytes":1890}
BULK

sleep 1
WEB_RESULT=$(curl -s "$ES_HOST/web-logs-2026.03.07/_count" | _count)
echo "  → $WEB_RESULT documents indexed"

# ---- Seed app-logs (10 docs) ----
echo ""
echo "[2/2] Seeding app-logs-2026.03.07 (10 documents)..."
curl -s -X POST "$ES_HOST/app-logs-2026.03.07/_bulk" \
  -H "Content-Type: application/json" \
  --data-binary @- << 'BULK'
{"index":{}}
{"@timestamp":"2026-03-07T08:01:30Z","level":"ERROR","service":"checkout-service","message":"Payment gateway timeout after 30s","user_id":"U12345","order_id":"ORD-9001","amount":149.99,"error":"ConnectionTimeoutError","session_id":"sess-abc-101","product_id":"PROD-42","quantity":2}
{"index":{}}
{"@timestamp":"2026-03-07T08:02:15Z","level":"ERROR","service":"checkout-service","message":"Payment gateway timeout after 30s","user_id":"U12346","order_id":"ORD-9002","amount":89.50,"error":"ConnectionTimeoutError","session_id":"sess-abc-102","product_id":"PROD-17","quantity":1}
{"index":{}}
{"@timestamp":"2026-03-07T08:03:45Z","level":"ERROR","service":"checkout-service","message":"Payment processing failed - upstream 503","user_id":"U12347","order_id":"ORD-9003","amount":225.00,"error":"ServiceUnavailableError","session_id":"sess-abc-103","product_id":"PROD-08","quantity":3}
{"index":{}}
{"@timestamp":"2026-03-07T08:04:10Z","level":"WARN","service":"inventory-service","message":"Stock level below threshold for PROD-42","user_id":"","order_id":"","amount":0,"error":"","session_id":"","product_id":"PROD-42","quantity":0}
{"index":{}}
{"@timestamp":"2026-03-07T08:05:00Z","level":"INFO","service":"auth-service","message":"User login successful","user_id":"U12345","order_id":"","amount":0,"error":"","session_id":"sess-abc-101","product_id":"","quantity":0}
{"index":{}}
{"@timestamp":"2026-03-07T08:06:22Z","level":"ERROR","service":"checkout-service","message":"Payment gateway timeout after 30s","user_id":"U12348","order_id":"ORD-9004","amount":67.25,"error":"ConnectionTimeoutError","session_id":"sess-abc-104","product_id":"PROD-33","quantity":1}
{"index":{}}
{"@timestamp":"2026-03-07T08:07:05Z","level":"INFO","service":"product-service","message":"Product catalog refreshed","user_id":"","order_id":"","amount":0,"error":"","session_id":"","product_id":"","quantity":0}
{"index":{}}
{"@timestamp":"2026-03-07T08:08:33Z","level":"ERROR","service":"auth-service","message":"Failed login attempt - account locked","user_id":"U99999","order_id":"","amount":0,"error":"AccountLockedException","session_id":"sess-xyz-001","product_id":"","quantity":0}
{"index":{}}
{"@timestamp":"2026-03-07T08:09:18Z","level":"INFO","service":"checkout-service","message":"Order completed successfully","user_id":"U12349","order_id":"ORD-9005","amount":312.00,"error":"","session_id":"sess-abc-105","product_id":"PROD-12","quantity":5}
{"index":{}}
{"@timestamp":"2026-03-07T08:10:47Z","level":"ERROR","service":"checkout-service","message":"Payment gateway timeout after 30s","user_id":"U12350","order_id":"ORD-9006","amount":45.00,"error":"ConnectionTimeoutError","session_id":"sess-abc-106","product_id":"PROD-55","quantity":1}
BULK

sleep 1
APP_RESULT=$(curl -s "$ES_HOST/app-logs-2026.03.07/_count" | _count)
echo "  → $APP_RESULT documents indexed"

# ---- Verification ----
echo ""
ENR_COUNT=$(curl -s "$ES_HOST/enriched-logs-*/_count" | _count || echo "0")

echo "=== Verification ==="
echo "  web-logs-*:      $WEB_RESULT (expected: 12)"
echo "  app-logs-*:      $APP_RESULT (expected: 10)"
echo "  enriched-logs-*: $ENR_COUNT  (expected: 28)"
echo ""
echo "Done! All indices are ready for the GenAI agent."
