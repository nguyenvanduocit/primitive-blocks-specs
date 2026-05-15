# Security — Shopify App Proxy

## Threat Model

### 1. Forged Proxy Requests

**Impact**: High — attacker could trigger app logic, scrape data, or spam the proxy endpoint without going through Shopify's storefront.

**Mitigations**:
- HMAC-SHA256 signature verification on every request (mandatory, first check before any processing)
- Signature covers all query params (shop, path_prefix, timestamp, plus any forwarded params) — tampering any param invalidates the signature
- Constant-time comparison (`crypto.timingSafeEqual`) prevents timing oracle attacks
- Optional: timestamp freshness check (reject requests older than 5 minutes) narrows replay window

### 2. Sensitive Data in Public Responses

**Impact**: Critical — proxy endpoints are public (no customer authentication). Returning PII, order data, or admin-level data would expose it to any caller.

**Mitigations**:
- Proxy endpoints return only public or aggregate data (e.g., review counts, public product data)
- Never return customer email, phone, address, order details, or any data requiring authentication
- Code review gate: all proxy handler functions must be reviewed for data exposure before deployment
- Treat every proxy endpoint as if it were a public `/api/public/*` route — because it is

### 3. XSS via Liquid Injection

**Impact**: High — if user-supplied content (review text, names, custom fields) is embedded in Liquid templates without escaping, an attacker could inject Liquid expressions or HTML that executes in the customer's browser.

**Mitigations**:
- All dynamic content embedded in Liquid templates uses the `| escape` Liquid filter
- Never interpolate raw user input directly into Liquid template strings
- For JSON data passed into Liquid, use `json` filter: `{{ data | json }}`
- Content Security Policy headers on HTML responses limit script execution scope

### 4. Cache Poisoning

**Impact**: Medium — if Shopify's CDN caches a response without shop context, one shop's data could be served to another shop's customers.

**Mitigations**:
- Include `shop` domain in all cache keys (Shopify's proxy infrastructure uses the full URL as cache key — ensuring `shop` param is in the URL is sufficient)
- For user-specific or session-specific responses, set `Cache-Control: no-store`
- For public, shop-scoped data, set `Cache-Control: s-maxage=${APP_PROXY_CACHE_TTL}`
- Never set `Vary: *` or omit `Cache-Control` on cacheable responses

### 5. Timing Attacks on Signature Verification

**Impact**: Low-Medium — a timing oracle on HMAC comparison could theoretically allow an attacker to brute-force a valid signature incrementally.

**Mitigations**:
- Use `crypto.timingSafeEqual` for all HMAC comparisons — never use `===` or string equality
- Return the same error response (`401 signature_verification_failed`) for all verification failures — do not distinguish "missing signature" from "wrong signature" in the response body
- Verify signature before any database lookups or business logic to minimize timing variance from downstream operations

---

## Input Validation Rules

| Field | Validation | Error Code |
|-------|-----------|------------|
| `signature` (query param) | Required, valid hex string, HMAC-SHA256 verified | `signature_verification_failed` |
| `shop` (query param) | Required, forwarded by Shopify, matches `*.myshopify.com`, exists in `shops` table | `shop_not_found` |
| `timestamp` (query param) | Required, numeric, within freshness window (optional enforcement) | `stale_timestamp` |
| `path_prefix` (query param) | Forwarded by Shopify, informational — do not trust for routing | N/A |
| Sub-path handler params | Validated per handler (e.g., `product_id` must be numeric) | Handler-specific codes |

---

## Secrets Management

| Secret | Storage | Rotation |
|--------|---------|----------|
| `SHOPIFY_API_SECRET` | Environment variable (from `auth.shopify-oauth`) | Rotate via Shopify Partner Dashboard — invalidates all existing proxy signatures |

No additional secrets introduced by this block. The App Proxy signature uses the same `SHOPIFY_API_SECRET` as OAuth and webhook verification.

---

## Public Endpoint Checklist

Before shipping any proxy handler, verify:

- [ ] The response contains zero customer PII (email, phone, address, name tied to an account)
- [ ] The response contains zero order data (order IDs, line items, payment info)
- [ ] The response contains zero admin-level data (inventory quantities, cost prices, staff notes)
- [ ] All dynamic content in Liquid templates uses `| escape` or `| json` filters
- [ ] Cache headers include `shop` in the implicit cache key (i.e., `shop` param is in the query string)
- [ ] HMAC comparison uses `crypto.timingSafeEqual`, not `===`
