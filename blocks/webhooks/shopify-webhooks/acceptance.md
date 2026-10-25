# Acceptance Checklist — Shopify Webhook Management

Claude Code runs this checklist after implementation, before reporting done.

## Database

- [ ] Migration runs successfully (`webhook_subscriptions` + `webhook_deliveries` tables created)
- [ ] `UNIQUE(shop_id, topic)` constraint on `webhook_subscriptions` is active
- [ ] `UNIQUE(webhook_id)` constraint on `webhook_deliveries` is active — this is the idempotency guarantee
- [ ] Index on `webhook_subscriptions(shop_id)` exists
- [ ] Index on `webhook_deliveries(shop_id)` exists
- [ ] Index on `webhook_deliveries(shop_id, status)` exists for monitoring queries
- [ ] `ON DELETE CASCADE` from `shops.id` propagates correctly

## Registration

- [ ] `registerWebhooks(shopId)` is called automatically after `shop.installed` event
- [ ] Each topic in `WEBHOOK_TOPICS` results in a `webhookSubscriptionCreate` GraphQL mutation
- [ ] Callback URL uses `APP_URL + WEBHOOK_PATH` from config
- [ ] `graphql_id` returned by Shopify is stored in `webhook_subscriptions`
- [ ] Re-running `registerWebhooks` on the same shop upserts without duplicating rows
- [ ] A single topic GraphQL error does not abort registration of remaining topics
- [ ] `syncWebhooks(shopId)` adds topics in config but not registered
- [ ] `syncWebhooks(shopId)` deactivates topics registered but no longer in config

## Receiving — HTTP Layer

- [ ] `POST WEBHOOK_PATH` responds `200 OK` before any processing begins
- [ ] Response time is well under 5 seconds (Shopify timeout threshold)
- [ ] Raw request body is read as `Buffer` before any body-parsing middleware
- [ ] `X-Shopify-Hmac-Sha256` header is verified against raw body using `SHOPIFY_API_SECRET`
- [ ] HMAC mismatch returns `401` and stops processing
- [ ] Missing HMAC header returns `401`
- [ ] Valid HMAC returns `200` and proceeds to async processing

## Idempotency

- [ ] `webhook_id` from `X-Shopify-Webhook-Id` header is used as the idempotency key
- [ ] `INSERT webhook_deliveries ON CONFLICT (webhook_id) DO NOTHING` is used — not application-level check
- [ ] Duplicate delivery (same `webhook_id`) returns `200` without dispatching the handler again
- [ ] Concurrent duplicate deliveries are handled by the DB constraint (not a race condition in app code)
- [ ] Delivery `status` transitions: `received` → `processing` → `processed` or `failed`

## Processing

- [ ] Topic handlers are dispatched asynchronously after the `200` response is sent (when `WEBHOOK_PROCESS_ASYNC=true`)
- [ ] Unknown topics receive `200`, delivery is logged as `processed`, no handler dispatched
- [ ] Webhook for unknown shop domain receives `200`, warning is logged, no delivery row created
- [ ] Webhook for uninstalled shop receives `200`, warning is logged, no handler dispatched
- [ ] Handler success: delivery status updated to `processed`, `processed_at` set, `webhook.processed` emitted
- [ ] Handler failure: delivery status updated to `failed`, `error` field set, `webhook.failed` emitted
- [ ] `webhook.received` event emitted for each new (non-duplicate) delivery

## Security

- [ ] HMAC verification uses **constant-time comparison** (Node `crypto.timingSafeEqual` / Web Crypto manual XOR-accumulator) — never `===` or `==`
- [ ] Raw body buffer is used for HMAC — not re-serialized JSON
- [ ] Webhook endpoint is excluded from CSRF protection middleware
- [ ] Webhook endpoint is excluded from session/JWT authentication middleware
- [ ] `SHOPIFY_API_SECRET` is read from environment variable, never hardcoded

## Shared Utilities

- [ ] `verifyShopifyHmac(secret, rawBody, hmacHeader)` from `auth.shopify-oauth` is reused
- [ ] GraphQL Admin API client from `auth.shopify-oauth` is used for `webhookSubscriptionCreate`
- [ ] `getShopByDomain(domain)` returns `null` for uninstalled shops (delivery is logged and skipped)

## Type Safety & Build

- [ ] `tsc --noEmit` passes (or equivalent type check)
- [ ] No `any` types on webhook payload handlers without justification
- [ ] Topic handler map is typed — unknown topics handled at runtime

## Configuration

- [ ] `WEBHOOK_TOPICS` defaults to `["APP_UNINSTALLED"]` when not set
- [ ] `WEBHOOK_PATH` defaults to `"/api/webhooks"` when not set
- [ ] `WEBHOOK_PROCESS_ASYNC` defaults to `true` when not set
- [ ] App fails fast at startup if `SHOPIFY_API_SECRET` is missing
- [ ] `APP_URL` from `auth.shopify-oauth` config is used to build callback URL
