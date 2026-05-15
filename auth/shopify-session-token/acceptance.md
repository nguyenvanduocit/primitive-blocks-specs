# Acceptance Checklist — Shopify Session Token Verification

Claude Code runs this checklist after implementation, before reporting done.

## Middleware

- [ ] `authenticateShopifyRequest` middleware function exists and is exportable
- [ ] Middleware extracts `Authorization: Bearer <token>` header correctly
- [ ] Middleware returns 401 `missing_token` when header is absent
- [ ] Middleware returns 401 `missing_token` when header is not `Bearer ...` format
- [ ] Middleware correctly splits JWT into 3 dot-separated parts
- [ ] Middleware returns 401 `invalid_token` for malformed tokens (< 3 or > 3 parts)

## Signature Verification

- [ ] HMAC-SHA256 signature is computed over `base64url(header) + "." + base64url(payload)` (the raw encoded parts, not decoded bytes)
- [ ] Signing key is `SHOPIFY_API_SECRET` (not `SHOPIFY_API_KEY`)
- [ ] Comparison uses `crypto.timingSafeEqual` (not `===`)
- [ ] Invalid signature returns 401 `invalid_token`
- [ ] Payload is decoded AFTER signature is verified (not before)

## Claim Validation

- [ ] `exp` claim is required and checked: `exp > Math.floor(Date.now() / 1000)`
- [ ] Expired token returns 401 `expired_token` (not `invalid_token`)
- [ ] `nbf` claim is checked if present: `nbf <= now` (token not yet valid)
- [ ] `aud` claim must exactly equal `SHOPIFY_API_KEY`
- [ ] Wrong audience returns 401 `invalid_audience`
- [ ] `iss` claim must match format `https://*.myshopify.com/admin`
- [ ] `dest` claim must match format `https://*.myshopify.com`
- [ ] Shop extracted from `iss` and `dest` must be the same — cross-shop mismatch returns 401 `invalid_token`

## Shop Lookup

- [ ] Shop domain is extracted from `dest` claim (not `iss`, not `sub`)
- [ ] Database query uses `shop_domain = dest AND uninstalled_at IS NULL`
- [ ] Shop not found returns 401 `shop_not_found`
- [ ] Uninstalled shop returns 401 `shop_not_found`

## Request Context

- [ ] `req.shopContext.shopId` is set to `shops.id` (UUID) for the verified shop
- [ ] `req.shopContext.shopDomain` is set to the shop domain string
- [ ] `req.shopContext.shopifyUserId` is set to the `sub` claim value (Shopify user ID, not shop ID)
- [ ] Context is not shared between concurrent requests from different shops

## Security

- [ ] Signature comparison uses `crypto.timingSafeEqual` (constant-time)
- [ ] Session tokens are never logged in plaintext
- [ ] `shopContext` is never populated from unverified claims
- [ ] Middleware does not apply to webhook endpoints (those use HMAC body signing)

## Integration

- [ ] Works with Express / Hono / Fastify middleware pattern (or equivalent for chosen framework)
- [ ] CORS preflight (OPTIONS) requests bypass or pass through the middleware without auth error
- [ ] Public endpoints registered without middleware work without token
- [ ] Downstream route handlers can read `req.shopContext` without additional lookups

## Type Safety & Build

- [ ] `tsc --noEmit` passes (or equivalent type check)
- [ ] `ShopContext` interface is typed — no `any` for shopId, shopDomain, shopifyUserId
- [ ] JWT payload is validated at runtime (claims checked, not assumed)
- [ ] Zod (or equivalent) schema validates JWT payload shape after decode

## Configuration

- [ ] `SHOPIFY_API_KEY` used for `aud` check — clearly documented
- [ ] `SHOPIFY_API_SECRET` used for signature verification — clearly documented
- [ ] No additional config keys required (reuses `auth.shopify-oauth` config)
- [ ] Startup fails fast if `SHOPIFY_API_KEY` or `SHOPIFY_API_SECRET` is missing
