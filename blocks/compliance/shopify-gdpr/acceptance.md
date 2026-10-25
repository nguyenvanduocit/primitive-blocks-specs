# Acceptance Checklist — Shopify GDPR Mandatory Webhooks

Claude Code runs this checklist after implementation, before reporting done.

## Database

- [ ] Migration runs successfully (`gdpr_requests` table created)
- [ ] Index on `gdpr_requests.shop_id` exists
- [ ] Index on `gdpr_requests.shopify_request_id` exists (for idempotency lookups)
- [ ] `gdpr_requests.shop_id` FK uses `ON DELETE SET NULL` (not CASCADE) — audit trail survives shop deletion
- [ ] All tables that store customer PII have `shop_id` FK with `ON DELETE CASCADE` to support shop_redact

## Customer Data Request (POST /api/gdpr/customers-data-request)

- [ ] Returns 200 immediately before any processing
- [ ] Verifies HMAC using `X-Shopify-Hmac-Sha256` header against raw request body
- [ ] Returns 401 when HMAC is invalid or missing
- [ ] Logs request to `gdpr_requests` with `request_type = 'customers_data_request'`
- [ ] Queries ALL app tables that store customer PII for the customer_id and customer_email
- [ ] Handles unknown customer gracefully (no data = valid, no error)
- [ ] Sends notification to `GDPR_NOTIFY_EMAIL` if configured
- [ ] Updates `gdpr_requests.status` to `completed` when done
- [ ] Sets `completed_at` timestamp on completion
- [ ] Emits `gdpr.data_requested` event
- [ ] Idempotent: duplicate `shopify_request_id` does not reprocess

## Customer Redact (POST /api/gdpr/customers-redact)

- [ ] Returns 200 immediately before any processing
- [ ] Verifies HMAC using `X-Shopify-Hmac-Sha256` header against raw request body
- [ ] Returns 401 when HMAC is invalid or missing
- [ ] Logs request to `gdpr_requests` with `request_type = 'customers_redact'`
- [ ] Deletes or anonymizes ALL PII for the customer across every app table
- [ ] Reviews: author_name → "Deleted User", author_email → null, author_phone → null (record kept for integrity)
- [ ] Customer profiles: record deleted
- [ ] Order-specific data: records deleted for `orders_to_redact` IDs
- [ ] Handles customer with no data gracefully (no error)
- [ ] Handles redact by email when customer_id is absent
- [ ] Updates `gdpr_requests.status` to `completed` when done
- [ ] Emits `gdpr.customer_redacted` event
- [ ] Response body is empty (200 with no body — do not leak internal details)

## Shop Redact (POST /api/gdpr/shop-redact)

- [ ] Returns 200 immediately before any processing
- [ ] Verifies HMAC using `X-Shopify-Hmac-Sha256` header against raw request body
- [ ] Returns 401 when HMAC is invalid or missing
- [ ] Logs request to `gdpr_requests` BEFORE deleting shop (so record exists for audit)
- [ ] Deletes shop record from `shops` table — CASCADE removes all dependent rows
- [ ] Verifies no orphan records remain after cascade delete
- [ ] `gdpr_requests` record survives with `shop_id = null` (audit trail preserved)
- [ ] Handles unknown shop gracefully (shop already gone = no error)
- [ ] Handles duplicate shop_redact webhook idempotently
- [ ] Updates `gdpr_requests.status` to `completed` when done
- [ ] Emits `gdpr.shop_redacted` event

## Data Completeness

- [ ] Every database table containing customer PII is enumerated in the customer redact handler
- [ ] Every database table with a `shop_id` FK is verified to have `ON DELETE CASCADE` or explicit delete in shop_redact handler
- [ ] No PII table is silently skipped during erasure
- [ ] A comment in the codebase lists all PII-containing tables (living documentation)

## Audit Trail

- [ ] All 3 GDPR request types are logged to `gdpr_requests` before processing
- [ ] `status` transitions are recorded: `received → processing → completed / failed`
- [ ] Failed processing updates status to `failed` (not silently swallowed)
- [ ] `shop_redact` audit record survives shop deletion (shop_id = null after delete)
- [ ] `completed_at` is set for every successful completion

## Security

- [ ] HMAC verification uses **constant-time comparison** (Node `crypto.timingSafeEqual` / Web Crypto manual XOR-accumulator) — never `===` or `==`
- [ ] Raw body is read before JSON parsing for HMAC check
- [ ] No GDPR endpoint processes data before responding 200
- [ ] Processing errors are logged but never returned in responses (already 200)
- [ ] No internal table names or row counts disclosed in responses

## Configuration

- [ ] `SHOPIFY_API_SECRET` is used for HMAC verification (inherited from `auth.shopify-oauth`)
- [ ] `GDPR_DATA_RETENTION_DAYS` defaults to `0` (immediate erasure)
- [ ] `GDPR_NOTIFY_EMAIL` is optional — handler works correctly when not set
- [ ] Missing `SHOPIFY_API_SECRET` causes startup failure

## Type Safety & Build

- [ ] `tsc --noEmit` passes (or equivalent type check)
- [ ] `GdprPayload` type covers all 3 webhook payload shapes
- [ ] No `any` types without justification
- [ ] Zod (or equivalent) validation at each endpoint boundary

## App Store Compliance

- [ ] All 3 GDPR endpoints are registered in Shopify Partner Dashboard under "Privacy webhooks"
- [ ] Endpoints respond within 5 seconds (Shopify timeout) — verified in load test or review
- [ ] Customer erasure completes within Shopify's required 30-day window (immediate with `GDPR_DATA_RETENTION_DAYS=0`)
- [ ] App Store submission includes GDPR webhook URLs pointing to the 3 implemented endpoints
