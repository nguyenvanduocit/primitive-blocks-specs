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

## Signature Verification

<!-- PATTERN: shopify-proxy-signature-verify -->
<!-- PURPOSE: Verify that a proxy request originated from Shopify, not a forged request -->
<!-- ADAPT: Crypto library -->
<!-- NOTE: App Proxy signature is DIFFERENT from webhook HMAC. Webhooks sign the request body.
           App Proxy signs the query params (excluding the signature param itself). -->

```typescript
function verifyProxySignature(secret: string, queryParams: Record<string, string>): boolean {
  // 1. Extract the signature param — this is what we verify against
  const { signature, ...remainingParams } = queryParams;

  if (!signature) return false;

  // 2. Sort the remaining params alphabetically by key
  const sortedKeys = Object.keys(remainingParams).sort();

  // 3. Concatenate as key=value pairs (no & separator in the input string)
  const message = sortedKeys.map(key => `${key}=${remainingParams[key]}`).join("");

  // 4. HMAC-SHA256 with the app's API secret
  const computed = crypto
    .createHmac("sha256", secret)
    .update(message)
    .digest("hex");

  // 5. Constant-time comparison to prevent timing attacks
  if (computed.length !== signature.length) return false;
  return crypto.timingSafeEqual(
    Buffer.from(computed, "hex"),
    Buffer.from(signature, "hex")
  );
}
```

**Key difference from OAuth/webhook HMAC**:

| Mechanism | Signs | Separator | Param name |
|-----------|-------|-----------|------------|
| OAuth callback | Sorted query params | `&` between pairs | `hmac` param |
| Webhook | Raw request body | N/A | `X-Shopify-Hmac-Sha256` header |
| App Proxy | Sorted query params | None (direct concatenation) | `signature` param |

---

## Proxy Catch-All Handler

<!-- PATTERN: shopify-proxy-handler -->
<!-- PURPOSE: Verify signature, resolve shop, route to sub-path handler, return typed response -->
<!-- ADAPT: Router framework, sub-path routing strategy -->

```typescript
// GET /api/proxy/*
// Shopify appends: shop, path_prefix, timestamp, signature to all forwarded requests

async function handleProxyRequest(req: Request): Promise<Response> {
  const queryParams = Object.fromEntries(new URL(req.url).searchParams.entries());

  // 1. Verify Shopify App Proxy signature
  if (!verifyProxySignature(config.SHOPIFY_API_SECRET, queryParams)) {
    return error(401, "signature_verification_failed");
  }

  // 2. Emit received event (after verification — don't log unverified requests)
  const { shop, path_prefix } = queryParams;
  emit("proxy.request_received", { shopDomain: shop, path: req.path, queryParams });

  // 3. Look up the shop
  const shopRecord = await getShopByDomain(shop);
  if (!shopRecord) {
    return error(404, "shop_not_found");
  }

  // 4. Route to sub-path handler
  const subPath = req.path.replace(config.APP_PROXY_SUBPATH, "");
  const startTime = Date.now();

  let response: Response;
  if (subPath.startsWith("/reviews")) {
    response = await handleProxyReviews(req, shopRecord, queryParams);
  } else if (subPath.startsWith("/form")) {
    response = await handleProxyForm(req, shopRecord, queryParams);
  } else {
    response = error(404, "proxy_path_not_found");
  }

  emit("proxy.request_served", {
    shopDomain: shop,
    path: req.path,
    responseType: response.headers.get("Content-Type"),
    durationMs: Date.now() - startTime,
  });

  return response;
}
```

---

## Response Builders

<!-- PATTERN: shopify-proxy-response-types -->
<!-- PURPOSE: Return correctly typed responses for each Shopify App Proxy content mode -->
<!-- ADAPT: Response construction for your framework -->

### Liquid Response (renders within theme)

```typescript
function buildLiquidResponse(liquidTemplate: string, cacheTtl: number = config.APP_PROXY_CACHE_TTL): Response {
  return new Response(liquidTemplate, {
    status: 200,
    headers: {
      "Content-Type": "application/liquid",
      // Shopify renders Liquid in the active theme layout
      // Cache at CDN layer — include shop in cache key upstream
      "Cache-Control": `s-maxage=${cacheTtl}`,
    },
  });
}

// Example: Product reviews widget
async function handleProxyReviews(req: Request, shop: Shop, params: Record<string, string>): Promise<Response> {
  const productId = params.product_id;
  if (!productId) {
    return error(400, "missing_product_id");
  }

  const reviews = await db.query(
    `SELECT * FROM reviews WHERE shop_id = $1 AND product_id = $2 AND status = 'approved' ORDER BY created_at DESC LIMIT 20`,
    [shop.id, productId]
  );

  // Sanitize all dynamic content before embedding in Liquid
  // Use Liquid's escape filter for any user-supplied content in the template
  const liquid = `
{% assign reviews_count = ${reviews.length} %}
{% if reviews_count > 0 %}
  <div class="app-reviews">
    {% for review in reviews %}
      <div class="review">
        <span class="review-author">{{ ${JSON.stringify(reviews.map(r => r.author_name))}[forloop.index0] | escape }}</span>
        <p class="review-body">{{ ${JSON.stringify(reviews.map(r => r.body))}[forloop.index0] | escape }}</p>
      </div>
    {% endfor %}
  </div>
{% else %}
  <p>No reviews yet.</p>
{% endif %}
  `.trim();

  return buildLiquidResponse(liquid);
}
```

### JSON Response (for AJAX calls from theme JS)

```typescript
function buildJsonResponse(data: unknown, cacheTtl: number = 0): Response {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      // Most JSON endpoints are dynamic — default no-store
      // Set cacheTtl > 0 for public, shop-keyed aggregate data
      "Cache-Control": cacheTtl > 0 ? `s-maxage=${cacheTtl}` : "no-store",
    },
  });
}

// Example: Loyalty points AJAX endpoint
async function handleProxyLoyaltyPoints(req: Request, shop: Shop, params: Record<string, string>): Promise<Response> {
  // App Proxy endpoints are PUBLIC — no customer auth available
  // Only return aggregate/public data, never PII or customer-specific data
  const stats = await db.query(
    `SELECT COUNT(*) as total_members, AVG(points) as avg_points FROM loyalty_accounts WHERE shop_id = $1`,
    [shop.id]
  );

  return buildJsonResponse({
    total_members: stats.total_members,
    avg_points: Math.round(stats.avg_points),
  }, config.APP_PROXY_CACHE_TTL);
}
```

### HTML Response (standalone, not rendered in theme)

```typescript
function buildHtmlResponse(html: string): Response {
  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html",
      // text/html is NOT rendered within the theme layout
      // Useful for iframe embeds or standalone app pages
      "Cache-Control": "no-store",
    },
  });
}
```

---

## Timestamp Freshness Check (optional hardening)

<!-- PATTERN: proxy-timestamp-check -->
<!-- PURPOSE: Reject proxy requests with stale timestamps to narrow replay window -->
<!-- ADAPT: Acceptable window based on your use case -->

```typescript
function isTimestampFresh(timestamp: string, windowSeconds: number = 300): boolean {
  const ts = parseInt(timestamp, 10);
  if (isNaN(ts)) return false;
  const now = Math.floor(Date.now() / 1000);
  return Math.abs(now - ts) <= windowSeconds;
}

// Use in handler before routing:
if (!isTimestampFresh(queryParams.timestamp)) {
  return error(401, "stale_timestamp");
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

---

## Anti-patterns

**DON'T** expose customer PII, order details, or any admin-level data in proxy responses. Proxy endpoints are publicly accessible — anyone can call them if they know the URL (signature only proves the request came via Shopify, not that the caller is authenticated).

**DON'T** use the `hmac` param name for the signature. App Proxy uses `signature`, not `hmac`. Confusing the two will cause all requests to fail verification.

**DON'T** include the `signature` param itself in the HMAC input. It must be removed from `queryParams` before computing. Including it produces a wrong digest.

**DON'T** join sorted params with `&` in the HMAC input. App Proxy concatenates `key=value` pairs directly with no separator. This differs from OAuth callback HMAC which uses `&`.

**DON'T** return sensitive Shopify Admin API data (inventory levels, customer records, order details) in proxy responses. These are public endpoints.

**DON'T** set `Cache-Control: s-maxage=X` without including `shop` in the cache key. Without it, one shop's response can be served to another shop's customers.
