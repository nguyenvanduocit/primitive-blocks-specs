# Acceptance Checklist — Shopify App Installation & OAuth

Claude Code runs this checklist after implementation, before reporting done.

## Database

- [ ] Migration runs successfully (`shops` + `oauth_nonces` tables created)
- [ ] `UNIQUE` constraint on `shops.shop_domain` is active
- [ ] `UNIQUE` constraint on `oauth_nonces.nonce` is active
- [ ] Index on `oauth_nonces.expires_at` exists (for cleanup queries)
- [ ] All shop queries include tenant scoping where applicable

## Install Flow

- [ ] GET /api/auth/shopify?shop=valid.myshopify.com generates nonce and redirects to Shopify
- [ ] Redirect URL includes correct client_id, scope, redirect_uri, and state
- [ ] GET /api/auth/shopify?shop=invalid.com returns 400
- [ ] GET /api/auth/shopify without shop param returns 400
- [ ] Callback verifies HMAC over all query params (excluding hmac and signature)
- [ ] Callback verifies nonce exists in DB and is not expired
- [ ] Nonce is deleted after successful verification (single-use)
- [ ] Authorization code is exchanged for offline access token via POST to Shopify
- [ ] Access token is encrypted before storing in database
- [ ] Shop record is upserted (new install creates, reinstall updates)
- [ ] On reinstall, `uninstalled_at` is set to null and `installed_at` is updated
- [ ] `shop.installed` event is emitted on successful install
- [ ] Merchant is redirected to embedded app URL after install

## Uninstall

- [ ] APP_UNINSTALLED webhook sets `uninstalled_at` on shop record
- [ ] `shop.uninstalled` event is emitted
- [ ] Duplicate uninstall webhook is handled idempotently

## Security

- [ ] HMAC comparison uses constant-time comparison (timingSafeEqual)
- [ ] Nonces are generated with crypto.randomBytes
- [ ] Access token is never logged, never returned in responses
- [ ] Shop domain regex only allows `*.myshopify.com`
- [ ] Expired nonces are cleaned up periodically

## Shared Utilities

- [ ] `verifyShopifyHmac()` function works for both query param signing and body signing
- [ ] `getShopByDomain()` returns null for uninstalled shops
- [ ] `getShopToken()` returns decrypted token
- [ ] GraphQL Admin API client handles rate limiting (429) and retries on 5xx

## Type Safety & Build

- [ ] `tsc --noEmit` passes (or equivalent type check)
- [ ] No `any` types without justification
- [ ] Zod (or equivalent) validation at API boundary

## Configuration

- [ ] All config keys documented: SHOPIFY_API_KEY, SHOPIFY_API_SECRET, SHOPIFY_SCOPES, APP_URL, OAUTH_NONCE_TTL_SECONDS
- [ ] Required keys fail fast on missing value at startup
- [ ] OAUTH_NONCE_TTL_SECONDS defaults to 300
