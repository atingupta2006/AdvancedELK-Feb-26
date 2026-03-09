# Seed Sample Data for web-logs and app-logs

> These commands create realistic sample documents matching the field schemas the agent expects.
> Run them in **Dev Tools** (`Menu → Management → Dev Tools`).
>
> Only run these if `web-logs-*` or `app-logs-*` return `0` or `index_not_found`.

---

## Seed `web-logs-*`

Web server access logs with a mix of 200, 404, and 500 status codes:

```json
POST web-logs-2026.03.07/_bulk
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
```

> 12 documents: 5 × 200/201, 4 × 500/503 (checkout service failures), 1 × 404, 2 × other. This gives the agent enough data to detect the `/api/checkout` error concentration.

---

## Seed `app-logs-*`

Application service logs with errors across multiple services:

```json
POST app-logs-2026.03.07/_bulk
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
```

> 10 documents: 5 × ERROR (4 in checkout-service, 1 in auth-service), 1 × WARN, 4 × INFO. The checkout-service payment gateway timeout is the dominant error — this is what the agent should identify.

---

## Verify

After seeding, run the count check in Dev Tools:

```json
GET web-logs-*/_count
GET app-logs-*/_count
GET enriched-logs-*/_count
```

> Expected: `web-logs-*` → 12, `app-logs-*` → 10, `enriched-logs-*` → 28.
