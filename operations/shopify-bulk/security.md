# Security — Shopify Bulk Operations

## Threat Model

### 1. Result URL Exposure

**Impact**: High — result URLs are signed by Shopify and grant unauthenticated read access to the full JSONL file, which may contain sensitive merchant data (prices, customer references, metafields).

**Mitigations**:
- Result URLs are never returned to the frontend client — always proxied server-side
- `result_url` column in `bulk_operations` is internal-only; the `/api/bulk/results/:id` endpoint streams and processes the file server-side
- Result URLs expire after ~24 hours; the app tracks this via the `completed_at` timestamp
- If `result_url` is null (expired), the endpoint returns `410 Gone` rather than a misleading error

### 2. Staging Upload Abuse

**Impact**: Medium — an attacker who can trigger bulk mutations could upload malicious JSONL to Shopify's staging storage or exhaust staging quota.

**Mitigations**:
- All bulk mutation endpoints require a valid session token (authenticated shop context)
- JSONL content is validated and serialized server-side from the API request body — the client never touches the staged upload URL
- Variables array is validated as a non-empty array of objects before serialization
- File size is reported in `stagedUploadsCreate` input — Shopify enforces limits on its side

### 3. Resource Exhaustion

**Impact**: Medium — submitting many bulk operations could exhaust Shopify's per-shop limit, causing cancellations and data loss.

**Mitigations**:
- App enforces one-per-type-per-shop constraint before calling Shopify: a `409 Conflict` is returned if `created` or `running` operation of same type already exists
- This mirrors Shopify's own enforcement, so the app and Shopify stay in sync
- Poll loop is bounded by `BULK_MAX_POLL_ATTEMPTS` to prevent infinite resource consumption on timed-out operations
- All operations are scoped to `shop_id` — one shop cannot interfere with another's operations

### 4. Sensitive Data in Results

**Impact**: High — bulk results may contain PII or confidential pricing data. If processed incorrectly, this data could be logged or leaked.

**Mitigations**:
- Results are processed server-side only — never forwarded raw to clients
- JSONL lines are not logged; only aggregate counts (`processedCount`, `batchCount`) are logged
- Application-specific processing (`processBatch`) applies the same access controls and data filters as direct API calls
- Batch processing limits memory footprint, reducing risk of data accumulation

### 5. Incomplete Processing

**Impact**: Medium — if JSONL processing fails mid-stream (network error, OOM, crash), data may be partially processed, causing inconsistencies.

**Mitigations**:
- `object_count` is stored on the operation record — processors can verify all lines were handled
- `bulk.results_processed` event carries `processedCount` for comparison against `object_count`
- Processing is idempotent where possible (upsert patterns, not insert-only)
- Batch size is configurable via `BULK_RESULT_PROCESSING_BATCH_SIZE` to balance throughput vs. memory risk
- If processing fails, the operation record status remains `completed` — the caller can retry `GET /api/bulk/results/:id` as long as `result_url` has not expired

## Input Validation Rules

| Field | Validation | Error Code |
|-------|-----------|------------|
| `query` (POST /api/bulk/query body) | Required, non-empty string | `missing_query` |
| `mutation` (POST /api/bulk/mutation body) | Required, non-empty string | `missing_mutation_or_variables` |
| `variables` (POST /api/bulk/mutation body) | Required, non-empty array of objects | `missing_mutation_or_variables` |
| `operationId` (path param) | UUID format, must exist in `bulk_operations` for requesting shop | `operation_not_found` |
| Session token | Valid App Bridge JWT, shop must be installed | `invalid_token` / `shop_not_found` |
| Webhook HMAC | HMAC-SHA256 of raw body matches `X-Shopify-Hmac-Sha256` header | Drop / 401 |

## Secrets Management

| Secret | Storage | Rotation |
|--------|---------|----------|
| `SHOPIFY_API_KEY` | Environment variable | Reuses from `auth.shopify-oauth` |
| `SHOPIFY_API_SECRET` | Environment variable | Reuses from `auth.shopify-oauth` (used for webhook HMAC) |
| Shop access tokens | Database (encrypted) | Managed by `auth.shopify-oauth` |
| Shopify result URLs | Database (`result_url` column) | Time-limited (~24h), not a long-term secret |
| Staged upload URLs | In-memory only | Single-use, not persisted |

## Tenant Isolation

All database queries include `shop_id` in the `WHERE` clause. A session token from Shop A cannot access bulk operations belonging to Shop B:

```sql
-- Correct: always scope to shop_id from session token context
SELECT * FROM bulk_operations WHERE id = $1 AND shop_id = $2;

-- Wrong: missing shop_id scope allows cross-tenant access
SELECT * FROM bulk_operations WHERE id = $1;
```

The `shop_id` is extracted from the verified session token, not from a client-supplied parameter.
