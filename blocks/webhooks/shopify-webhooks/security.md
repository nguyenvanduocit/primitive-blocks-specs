# Security — Shopify Webhook Management

## Threat Model

### 1. Forged Webhook Requests

**Impact**: Critical — an attacker could inject fake events (fake orders, fake uninstalls) causing the app to take unauthorized actions on merchant data.

**Mitigations**:
- **HMAC-SHA256** verification on every incoming request using `SHOPIFY_API_SECRET` as the signing key
- Verification covers the entire **raw request body** — any byte change invalidates the signature
- Expected signature carried in header **`X-Shopify-Hmac-Sha256`** (base64-encoded)
- **Constant-time comparison** (Node `crypto.timingSafeEqual` / Web Crypto manual XOR-accumulator) prevents timing-based HMAC bypass
- Requests failing HMAC verification receive **401** and are not logged in `webhook_deliveries`

### 2. Replay Attacks

**Impact**: High — replaying a legitimate webhook (e.g., `orders/create`) could cause duplicate order processing, duplicate emails, duplicate charges.

**Mitigations**:
- `webhook_id` (`X-Shopify-Webhook-Id` header) is UNIQUE in `webhook_deliveries` table
- `INSERT ... ON CONFLICT(webhook_id) DO NOTHING` — database constraint prevents any processing on duplicate delivery
- Even if an attacker captures and replays a valid webhook (with a valid HMAC from the original delivery), the constraint stops reprocessing
- Shopify's own retry system uses the same `X-Shopify-Webhook-Id` for retries — idempotency is correct by design

### 3. Timeout-Induced Retry Storm

**Impact**: Medium — if the app takes more than **5 seconds** to respond, Shopify marks the delivery failed and retries up to **19 times over 48 hours**. Slow processing cascades into a queue flood.

**Mitigations**:
- Respond `200 OK` immediately after HMAC verification — before any DB writes or processing
- All processing dispatched asynchronously after the HTTP response is sent
- Idempotency constraint (`webhook_id` UNIQUE) ensures retries during processing are safe
- Failed deliveries tracked in `webhook_deliveries` with `status = 'failed'` for monitoring

### 4. Missing Webhook Deliveries

**Impact**: Medium — Shopify stops retrying after 19 failed attempts. Silent gaps in event processing cause data drift (e.g., app shows order as pending when it was fulfilled).

**Mitigations**:
- `syncWebhooks(shopId)` reconciliation job detects topic gaps
- `webhook_deliveries.status` audit trail enables gap detection by topic + time range
- For critical topics, implement periodic reconciliation by comparing Shopify API data against local records

### 5. Payload Tampering in Transit

**Impact**: High — modified payload could change order amounts, customer details, or product data processed by the app.

**Mitigations**:
- HMAC covers the entire raw body — any modification of a single byte invalidates the signature
- `payload_hash` (SHA-256 hex of body) stored alongside delivery for forensic dedup
- HTTPS enforced on all webhook endpoints — TLS prevents in-transit modification

## Input Validation Rules

| Field | Validation | Error Code |
|-------|-----------|------------|
| `X-Shopify-Hmac-Sha256` header | Required, valid **HMAC-SHA256 base64** over raw body | `hmac_verification_failed` |
| `X-Shopify-Webhook-Id` header | Required, non-empty string | logged, delivery skipped |
| `X-Shopify-Topic` header | Required, non-empty string (slash form, e.g. `orders/create`) | logged, delivery skipped |
| `X-Shopify-Shop-Domain` header | Required, matches `*.myshopify.com` format | logged, delivery skipped |
| Request body | Raw bytes preserved for HMAC before any parsing | — |

## Secrets Management

| Secret | Storage | Rotation Impact |
|--------|---------|-----------------|
| `SHOPIFY_API_SECRET` | Environment variable | Rotation invalidates all pending HMAC verifications — coordinate with Shopify Partner Dashboard |
| Shop access tokens (for registration) | Database (encrypted, from `auth.shopify-oauth`) | No direct impact on webhook receiving |

## Webhook Endpoint Hardening

- The `POST /api/webhooks` endpoint must be excluded from CSRF protection middleware (Shopify sends no CSRF token)
- The endpoint must be excluded from session/JWT auth middleware (Shopify sends no bearer token)
- Rate limiting should be generous or disabled for this endpoint — Shopify can burst deliveries during merchant activity spikes
- Log the `X-Shopify-Webhook-Id` on every request for correlation, even before HMAC verification

## Raw Body Requirement (L1 invariant)

The HMAC verifier signs the **exact byte sequence** Shopify sent. Any transformation before HMAC check breaks verification:

- JSON body parsers re-serialize the payload → byte sequence differs from original (especially for non-ASCII chars and key ordering)
- Compression/decompression middleware that re-encodes the body breaks the byte sequence
- Character-encoding conversion (e.g., assuming UTF-8 and trimming BOM) breaks the byte sequence

**Invariant**: the raw body must be accessible as a byte buffer to the HMAC verifier, before any middleware that mutates or re-serializes the body. How each framework exposes the raw body is a HOW concern — see `backend.md` Pattern 1 `ADAPT` list for per-framework mechanisms.
