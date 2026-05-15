# Acceptance Checklist — Shopify App Proxy

Claude Code runs this checklist after implementation, before reporting done.

## Shopify Partner Dashboard Setup

- [ ] App proxy subpath configured in Partner Dashboard (e.g., `myapp`)
- [ ] Proxy URL points to the correct backend endpoint (e.g., `https://myapp.com/api/proxy`)
- [ ] Storefront URL pattern confirmed: `https://{shop}/apps/{subpath}/*` → `{proxy_url}/*`

## Signature Verification

- [ ] `verifyProxySignature()` extracts `signature` param before computing HMAC
- [ ] Remaining params are sorted alphabetically by key
- [ ] Params are concatenated as `key=value` pairs with NO separator between pairs (not `&`)
- [ ] HMAC-SHA256 is computed using `SHOPIFY_API_SECRET`
- [ ] Comparison uses `crypto.timingSafeEqual` (not `===` or string equality)
- [ ] Missing `signature` param returns 401 `signature_verification_failed`
- [ ] Tampered params (any param changed) returns 401 `signature_verification_failed`
- [ ] Signature computed with wrong secret returns 401 `signature_verification_failed`

## Key Distinction: Proxy vs Webhook vs OAuth HMAC

- [ ] Proxy: signs sorted query params, concatenated WITHOUT `&`, param name is `signature`
- [ ] OAuth callback: signs sorted query params, joined WITH `&`, param name is `hmac`
- [ ] Webhooks: signs raw request body, signature in `X-Shopify-Hmac-Sha256` header

## Shop Lookup

- [ ] After signature verification, `shop` query param is used to look up shop record
- [ ] Uninstalled shops (uninstalled_at set) return 404 `shop_not_found`
- [ ] Unknown shop domains return 404 `shop_not_found`

## Response Types

- [ ] Liquid responses: `Content-Type: application/liquid` — Shopify renders within theme layout
- [ ] JSON responses: `Content-Type: application/json` — returned as-is for AJAX calls
- [ ] HTML responses: `Content-Type: text/html` — standalone, NOT wrapped in theme layout
- [ ] Unknown sub-paths return 404 `proxy_path_not_found`
- [ ] Missing required handler params return 400 with specific error code

## Cache Headers

- [ ] Liquid responses include `Cache-Control: s-maxage=${APP_PROXY_CACHE_TTL}`
- [ ] Public JSON responses include `Cache-Control: s-maxage=${APP_PROXY_CACHE_TTL}`
- [ ] Dynamic/user-specific JSON responses include `Cache-Control: no-store`
- [ ] HTML responses include `Cache-Control: no-store`
- [ ] `shop` param is present in all proxy request URLs (ensures CDN cache key is shop-scoped)

## Security

- [ ] No customer PII (email, phone, address, name) in any proxy response
- [ ] No order data in any proxy response
- [ ] No admin-level data (inventory, cost prices, staff notes) in any proxy response
- [ ] All dynamic content in Liquid templates uses `| escape` or `| json` filter
- [ ] User-supplied strings are never interpolated raw into Liquid template strings
- [ ] `proxy.request_received` event is only emitted after signature verification passes

## Events

- [ ] `proxy.request_received` emitted with `{ shopDomain, path, queryParams }` on valid request
- [ ] `proxy.request_served` emitted with `{ shopDomain, path, responseType, durationMs }` on success

## Type Safety & Build

- [ ] `tsc --noEmit` passes (or equivalent type check)
- [ ] No `any` types without justification
- [ ] Query params are validated at the handler boundary before use

## Configuration

- [ ] `APP_PROXY_SUBPATH` configured and used for sub-path routing
- [ ] `APP_PROXY_CACHE_TTL` defaults to 300 and applied to cacheable responses
- [ ] `SHOPIFY_API_SECRET` is the same secret as used in `auth.shopify-oauth` (no new secret needed)
- [ ] Required config keys fail fast on missing value at startup
