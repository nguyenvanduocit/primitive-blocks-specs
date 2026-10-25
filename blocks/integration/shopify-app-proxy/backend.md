# Backend Patterns — Shopify App Proxy

## API Endpoints

### Proxy Handler

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `GET` | `/api/proxy/*` | Catch-all proxy handler for all storefront-forwarded requests | None (signature verified) |

### Internal (called by this block)

| Function | Purpose |
|----------|---------|
| `verifyProxySignature(secret, queryParams)` | Extract + verify Shopify App Proxy HMAC signature |
| `getShopByDomain(domain)` | Look up shop record (from `auth.shopify-oauth`) |
| `buildLiquidResponse(template)` | Return Liquid content with correct Content-Type |
| `buildJsonResponse(data)` | Return JSON with correct Content-Type |

---

## External Contract Reference (Shopify-dictated)

| Item | Concrete value | Differs from OAuth? |
|------|----------------|---------------------|
| Signature parameter name | `signature` | **Yes** — OAuth callback uses `hmac` |
| Algorithm | HMAC-SHA256 | Same |
| Output encoding | lowercase hex | Same as OAuth callback |
| Message construction | sort params alphabetically by key; concatenate `key=value` pairs **with no separator** | **Yes** — OAuth callback joins with `&` |
| Excluded params from HMAC | `signature` (self) | OAuth excludes `hmac` and `signature` |
| Always-forwarded params | `shop`, `path_prefix`, `timestamp`, `signature` | n/a |
| Comparison | constant-time | Same |
| Response Content-Type values | `application/liquid`, `application/json`, `text/html` | n/a |

> The `signature`-vs-`hmac` discrepancy is the most common implementation bug. Read it twice.

---

## Signature Verification — 2 sub-patterns

### Pattern: Build canonical signature message

<!-- PATTERN: shopify-proxy-canonical-message -->
<!-- PURPOSE: Build the byte string that HMAC will be computed over for App Proxy signature -->
<!-- REFERENCE: external-contract=shopify-app-proxy language=typescript -->
<!-- ADAPT:
       - Excluded key `signature`: external contract, KHÔNG đổi (App Proxy uses `signature`, NOT `hmac`)
       - No separator between `key=value` pairs: external contract, KHÔNG đổi (differs from OAuth callback which uses `&`)
       - Sort by ASCII (default `.sort()`): Shopify dictates alphabetical sort by key
       - For repeated params (arrays in query string): App Proxy treats them as comma-joined; if your runtime parses them into arrays, join with `,` before building the message -->

```typescript
function buildProxyCanonicalMessage(queryParams: Record<string, string>): string {
  const { signature: _omit, ...rest } = queryParams;
  return Object.keys(rest).sort()
    .map((k) => `${k}=${rest[k]}`)
    .join(""); // no separator between pairs — Shopify App Proxy contract
}
```

### Pattern: HMAC-SHA256 verify with constant-time compare

<!-- PATTERN: shopify-proxy-signature-verify -->
<!-- PURPOSE: Verify that a proxy request originated from Shopify, using constant-time HMAC-SHA256 compare -->
<!-- REFERENCE: runtime=node20+ crypto=node-builtin algorithm=hmac-sha256 -->
<!-- ADAPT:
       - `crypto.createHmac` / `timingSafeEqual`: edge/Workers/Deno → Web Crypto (`subtle.importKey` + `subtle.sign("HMAC", ...)`); manual constant-time compare via XOR-accumulator pattern
       - Output encoding `hex`: external contract — App Proxy signature is hex (lowercase)
       - Algorithm `sha256`: external contract — KHÔNG đổi -->

```typescript
function verifyProxySignature(secret: string, queryParams: Record<string, string>): boolean {
  const signature = queryParams.signature;
  if (!signature) return false;
  const message = buildProxyCanonicalMessage(queryParams);
  const computed = crypto.createHmac("sha256", secret).update(message).digest("hex");
  if (computed.length !== signature.length) return false;
  return crypto.timingSafeEqual(
    Buffer.from(computed, "hex"),
    Buffer.from(signature, "hex")
  );
}
```

### Key difference table

| Mechanism | Signs | Separator | Param name / Header |
|-----------|-------|-----------|---------------------|
| OAuth callback | Sorted query params | `&` between pairs | `hmac` query param |
| Webhook | Raw request body | N/A | `X-Shopify-Hmac-Sha256` header |
| **App Proxy** | **Sorted query params** | **None (direct concatenation)** | **`signature` query param** |

---

## Timestamp Freshness Check (optional hardening)

<!-- PATTERN: shopify-proxy-timestamp-freshness -->
<!-- PURPOSE: Reject proxy requests whose timestamp is too far from now — narrows replay window -->
<!-- REFERENCE: language=typescript external-contract=shopify-app-proxy -->
<!-- ADAPT:
       - `timestamp` is unix seconds (Shopify-dictated) — parse as integer
       - Window default 300s (5 min) — tighten for sensitive endpoints; do not exceed 600s (Shopify CDN cache age can introduce skew)
       - Clock skew tolerance is symmetric (`Math.abs`) — accept both past and future drift -->

```typescript
function isTimestampFresh(timestamp: string, windowSeconds = 300): boolean {
  const ts = parseInt(timestamp, 10);
  if (!Number.isFinite(ts)) return false;
  const now = Math.floor(Date.now() / 1000);
  return Math.abs(now - ts) <= windowSeconds;
}
```

---

## Proxy Catch-All Handler — Compose verify → resolve → route

### Pattern: Resolve shop record from `shop` param

<!-- PATTERN: shopify-proxy-shop-resolve -->
<!-- PURPOSE: Look up shop record by domain from the verified `shop` query param -->
<!-- REFERENCE: dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - `getShopByDomain` is the shared utility from `auth.shopify-oauth` — adapt to your ORM
       - `uninstalled_at IS NULL` filter: avoid serving content for uninstalled shops
       - Return null → handler returns 404 -->

```typescript
async function resolveProxyShop(shopParam: string): Promise<Shop | null> {
  if (!shopParam) return null;
  return getShopByDomain(shopParam); // from auth.shopify-oauth shared utility
}
```

### Pattern: Catch-all proxy handler

<!-- PATTERN: shopify-proxy-handler -->
<!-- PURPOSE: Verify signature, resolve shop, route to sub-path handler, emit observability events -->
<!-- REFERENCE: framework=generic runtime=node20+ -->
<!-- ADAPT:
       - `Object.fromEntries(URL.searchParams.entries())`: framework helpers (Express `req.query`, Hono `c.req.queries()`, Fastify `req.query`) yield similar maps — be careful with array-valued params
       - `req.path` / `config.APP_PROXY_SUBPATH` prefix strip: adapt to router prefix conventions
       - Sub-path routing via `if/else`: replace with sub-router (`express.Router`, Hono `app.route`) for many handlers
       - Emit events only AFTER signature verify — never log unverified payloads -->

```typescript
async function handleProxyRequest(req: Request): Promise<Response> {
  const queryParams = Object.fromEntries(new URL(req.url).searchParams.entries());
  if (!verifyProxySignature(config.SHOPIFY_API_SECRET, queryParams)) {
    return error(401, "signature_verification_failed");
  }
  const shop = await resolveProxyShop(queryParams.shop);
  if (!shop) return error(404, "shop_not_found");
  emit("proxy.request_received", { shopDomain: shop.shop_domain, path: req.path });
  const subPath = req.path.replace(config.APP_PROXY_SUBPATH, "");
  const start = Date.now();
  const response = await routeProxySubPath(subPath, req, shop, queryParams);
  emit("proxy.request_served", {
    shopDomain: shop.shop_domain, path: req.path,
    responseType: response.headers.get("Content-Type"), durationMs: Date.now() - start,
  });
  return response;
}
```

### Pattern: Sub-path router

<!-- PATTERN: shopify-proxy-subpath-router -->
<!-- PURPOSE: Dispatch verified proxy request to a sub-path handler based on the trailing path -->
<!-- REFERENCE: framework=generic language=typescript -->
<!-- ADAPT:
       - Sub-path matching is intentionally simple — replace with framework router for many routes
       - Add app-specific sub-paths here (reviews, loyalty, forms, etc.)
       - Default fallback returns 404 `proxy_path_not_found` -->

```typescript
async function routeProxySubPath(
  subPath: string, req: Request, shop: Shop, q: Record<string, string>
): Promise<Response> {
  if (subPath.startsWith("/reviews")) return handleProxyReviews(req, shop, q);
  if (subPath.startsWith("/loyalty-points")) return handleProxyLoyaltyPoints(req, shop, q);
  if (subPath.startsWith("/form")) return handleProxyForm(req, shop, q);
  return error(404, "proxy_path_not_found");
}
```

---

## Response Builders — One pattern per Shopify content-mode

### Pattern: Liquid response builder

<!-- PATTERN: shopify-proxy-liquid-response -->
<!-- PURPOSE: Return Liquid content that Shopify renders within the merchant's active theme layout -->
<!-- REFERENCE: external-contract=shopify-app-proxy framework=generic -->
<!-- ADAPT:
       - `Content-Type: application/liquid`: external contract — KHÔNG đổi (Shopify uses this header to enter Liquid-render mode)
       - `Cache-Control: s-maxage=N`: CDN cache age in seconds; default `APP_PROXY_CACHE_TTL`; set `no-store` for user-specific content
       - Replace `new Response(...)` with framework equivalent (Express `res.type(...).send(...)`, Hono `c.body(..., { headers })`)
       - Inside the Liquid string, use `{{ var | escape }}` for ALL user-supplied content — see XSS mitigation in security.md -->

```typescript
function buildLiquidResponse(
  liquidTemplate: string,
  cacheTtl: number = config.APP_PROXY_CACHE_TTL
): Response {
  return new Response(liquidTemplate, {
    status: 200,
    headers: {
      "Content-Type": "application/liquid",
      "Cache-Control": `s-maxage=${cacheTtl}`,
    },
  });
}
```

### Pattern: Liquid template rendering with escape

<!-- PATTERN: shopify-proxy-liquid-template-build -->
<!-- PURPOSE: Build a safe Liquid template string with all dynamic content escaped at the Liquid layer -->
<!-- REFERENCE: external-contract=shopify-liquid language=typescript -->
<!-- ADAPT:
       - `| escape` Liquid filter is MANDATORY for any user-supplied string interpolated into HTML context — never omit
       - Rendering strategy: this pattern pre-renders the HTML server-side and ships static Liquid blocks containing already-escaped values. This avoids depending on Liquid filters like `parse_json` (Online Store 2.0+ only) or `json` (theme context only) — works on legacy themes too.
       - If the merchant theme is Online Store 2.0+, you may instead emit `{% assign data = '<json>' | parse_json %}` and iterate — fewer bytes on the wire but requires OS 2.0
       - Prefer a Liquid-aware templating helper (e.g. LiquidJS) for complex templates; for simple lists, the per-row escape approach below is sufficient
       - Source data from app DB only — apply same access controls as direct API calls -->

```typescript
function escapeLiquidLiteral(s: string): string {
  // Escape so the string is safe to embed inside a Liquid double-quoted literal AND inside HTML.
  return String(s).replace(/[<>&"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

function renderReviewsLiquid(reviews: Array<{ author_name: string; body: string }>): string {
  if (reviews.length === 0) return `<p>No reviews yet.</p>`;
  const rows = reviews.map((r) => {
    const a = escapeLiquidLiteral(r.author_name);
    const b = escapeLiquidLiteral(r.body);
    return `<div class="review"><strong>${a}</strong><p>${b}</p></div>`;
  }).join("");
  return `<div class="app-reviews">${rows}</div>`;
}
```

### Pattern: Reviews sub-handler

<!-- PATTERN: shopify-proxy-reviews-handler -->
<!-- PURPOSE: Fetch approved reviews for a product and return a Liquid template -->
<!-- REFERENCE: dialect=postgres orm=raw-sql framework=generic -->
<!-- ADAPT:
       - `product_id` query param: validate as numeric / GID per app convention
       - DB query: ORM equivalent of `SELECT ... WHERE shop_id AND product_id AND status='approved'`
       - Limit `20`: tune to UX expectation
       - Only return public-visible columns (author_name, body, rating) — see security.md "Public Endpoint Checklist" -->

```typescript
async function handleProxyReviews(req: Request, shop: Shop, q: Record<string, string>): Promise<Response> {
  const productId = q.product_id;
  if (!productId) return error(400, "missing_product_id");
  const reviews = await db.query(
    `SELECT author_name, body, rating FROM reviews
     WHERE shop_id = $1 AND product_id = $2 AND status = 'approved'
     ORDER BY created_at DESC LIMIT 20`,
    [shop.id, productId]
  );
  return buildLiquidResponse(renderReviewsLiquid(reviews));
}
```

### Pattern: JSON response builder

<!-- PATTERN: shopify-proxy-json-response -->
<!-- PURPOSE: Return JSON for AJAX calls from theme JavaScript -->
<!-- REFERENCE: external-contract=shopify-app-proxy framework=generic -->
<!-- ADAPT:
       - `Content-Type: application/json`: external contract value
       - Default `Cache-Control: no-store` for user-specific data; set `s-maxage=N` for public aggregate data
       - Never include customer PII, order details, or admin-level fields — see security.md
       - Replace `new Response(...)` with framework JSON helper -->

```typescript
function buildJsonResponse(data: unknown, cacheTtl: number = 0): Response {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": cacheTtl > 0 ? `s-maxage=${cacheTtl}` : "no-store",
    },
  });
}
```

### Pattern: Loyalty (JSON) sub-handler

<!-- PATTERN: shopify-proxy-loyalty-handler -->
<!-- PURPOSE: Return public aggregate loyalty stats (no PII) for theme JS -->
<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT:
       - Only aggregate/public data — proxy endpoints are PUBLIC, no customer auth available
       - Cache TTL via `APP_PROXY_CACHE_TTL`: tune to data freshness needs
       - For customer-specific loyalty, use Storefront API + customer access token, NOT App Proxy -->

```typescript
async function handleProxyLoyaltyPoints(req: Request, shop: Shop, _q: Record<string, string>): Promise<Response> {
  const stats = await db.query(
    `SELECT COUNT(*) as total_members, AVG(points) as avg_points
     FROM loyalty_accounts WHERE shop_id = $1`,
    [shop.id]
  );
  return buildJsonResponse(
    { total_members: stats.total_members, avg_points: Math.round(stats.avg_points) },
    config.APP_PROXY_CACHE_TTL
  );
}
```

### Pattern: HTML response builder (standalone, NOT rendered in theme)

<!-- PATTERN: shopify-proxy-html-response -->
<!-- PURPOSE: Return standalone HTML — Shopify does NOT inject this into the theme layout -->
<!-- REFERENCE: external-contract=shopify-app-proxy framework=generic -->
<!-- ADAPT:
       - `Content-Type: text/html`: external contract value — Shopify treats this as standalone, not Liquid-rendered
       - Use case: iframe embed targets, standalone app pages reached via /apps/ URL
       - Always set `Cache-Control: no-store` unless content is shop-public + version-stable -->

```typescript
function buildHtmlResponse(html: string): Response {
  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html",
      "Cache-Control": "no-store",
    },
  });
}
```

---

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `signature_verification_failed` | 401 | Signature param missing or HMAC does not match |
| `shop_not_found` | 404 | `shop` param not in database or shop is uninstalled |
| `proxy_path_not_found` | 404 | Sub-path has no registered handler |
| `missing_product_id` | 400 | Required query param absent for sub-path handler |
| `stale_timestamp` | 401 | Timestamp too far from current time (optional) |

> Return the **same** error response (`401 signature_verification_failed`) for any signature failure — do not distinguish "missing signature" from "wrong signature" to avoid information leak.

---

## Anti-patterns

**DON'T** expose customer PII, order details, or any admin-level data in proxy responses. Proxy endpoints are publicly accessible — anyone can call them if they know the URL (signature only proves the request came via Shopify, not that the caller is authenticated).

**DON'T** use the `hmac` param name for the App Proxy signature. App Proxy uses `signature`, not `hmac`. Confusing the two will cause all requests to fail verification.

**DON'T** include the `signature` param itself in the HMAC input. It must be removed from `queryParams` before computing. Including it produces a wrong digest.

**DON'T** join sorted params with `&` in the HMAC input. App Proxy concatenates `key=value` pairs directly with no separator. This differs from OAuth callback HMAC which uses `&`.

**DON'T** use `===` for HMAC comparison. Use a constant-time compare (`crypto.timingSafeEqual` or equivalent) — short-circuit string equality leaks timing information.

**DON'T** return sensitive Shopify Admin API data (inventory levels, customer records, order details) in proxy responses. These are public endpoints.

**DON'T** set `Cache-Control: s-maxage=X` without including `shop` in the cache key. Without it, one shop's response can be served to another shop's customers.

**DON'T** trust `path_prefix` from the query string for routing decisions. It's informational; route on the path portion of the URL within your configured `APP_PROXY_SUBPATH`.
