# Security — Shopify GDPR Mandatory Webhooks

## Threat Model

### 1. Forged GDPR Request

**Impact**: Critical — attacker could trigger data erasure for arbitrary customers or entire shops, destroying app data without a legitimate request.

**Mitigations**:
- HMAC-SHA256 verification on every incoming request using `SHOPIFY_API_SECRET` (reused from `auth.shopify-oauth`)
- Raw request body read before any parsing — HMAC covers the entire payload
- Constant-time comparison via `crypto.timingSafeEqual` prevents timing attacks
- Rejects any request where `X-Shopify-Hmac-Sha256` header is absent or incorrect

### 2. Incomplete Data Erasure

**Impact**: High — failing to erase all customer PII is a GDPR compliance violation with significant legal and financial risk. Shopify can revoke App Store listing.

**Mitigations**:
- Enumerate ALL database tables that store customer-identifiable data during implementation
- `customer-redact.feature` scenarios explicitly test each data category (reviews, profiles, order annotations)
- `acceptance.md` checklist requires sign-off that every table with PII is handled
- Consider a PII registry — a documented list of every field that contains personal data, updated whenever the schema changes

### 3. Audit Gap

**Impact**: Medium — without an audit trail, the app cannot demonstrate compliance to regulators or Shopify during a review.

**Mitigations**:
- `gdpr_requests` table logs every incoming request with `status`, `shopify_request_id`, and timestamps
- Status transitions (`received → processing → completed / failed`) are recorded
- `gdpr_requests` records are preserved even when shop data is deleted (use `ON DELETE SET NULL` on `shop_id` FK, or log to a separate compliance store before cascade delete)
- `completed_at` timestamp provides proof of timely processing

### 4. Race Condition / Duplicate Processing

**Impact**: Low — duplicate GDPR webhooks (Shopify retries on non-200 or network failures) could trigger double erasure or log noise.

**Mitigations**:
- `shopify_request_id` field enables idempotency check before processing
- Check for existing completed record before inserting new one
- Database-level: `shopify_request_id` index allows fast lookup

### 5. Shop Redact Destroys Audit Trail

**Impact**: Medium — cascade deleting the `shops` row could delete the `gdpr_requests` record that proves the shop_redact was processed.

**Mitigations**:
- `gdpr_requests.shop_id` FK uses `ON DELETE SET NULL` (not `ON DELETE CASCADE`) — records survive shop deletion with `shop_id = null`
- Alternatively: log the completed GDPR request to an append-only compliance store before executing the purge
- `gdpr_requests` table is excluded from the cascade delete chain

## Input Validation Rules

| Field | Validation | Error Code |
|-------|-----------|------------|
| `X-Shopify-Hmac-Sha256` header | Required, valid HMAC-SHA256 hex of raw body | `hmac_verification_failed` |
| `shop_domain` (payload) | Must match a known shop in `shops` table | Logged warning, processing skipped |
| `customer.id` (payload) | Bigint, required for `customers_*` types | Processing skipped if missing |
| `shop_id` (payload) | Numeric, informational — shop looked up by `shop_domain` | Not used directly for DB lookup |
| `orders_requested` / `orders_to_redact` | Array of bigints, nullable | Treated as empty array if absent |

## Secrets Management

| Secret | Storage | Rotation |
|--------|---------|----------|
| `SHOPIFY_API_SECRET` | Environment variable | Rotate via Shopify Partner Dashboard — invalidates all existing HMAC verification |
| `GDPR_NOTIFY_EMAIL` | Environment variable | Update whenever compliance contact changes |

## Compliance Notes

- Shopify requires a response within **5 seconds** — always respond 200 before processing
- Shopify expects erasure to be **complete within 30 days** of a redact request (best practice: implement immediate erasure, use `GDPR_DATA_RETENTION_DAYS=0`)
- The `customers/data_request` webhook does **not** require the app to return data to Shopify — it requires the app to be aware of and able to provide the data. Notification to the store owner via `GDPR_NOTIFY_EMAIL` is the standard compliance pattern
- `shop/redact` is sent **48 hours after uninstall** — not immediately. The app may still receive other webhooks in that window
