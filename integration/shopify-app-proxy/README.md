---
id: "integration.shopify-app-proxy"
name: "Shopify App Proxy"
version: "1.0.0"
category: "integration"
tags: [shopify, app-proxy, storefront, liquid]
prerequisites: ["auth.shopify-oauth"]
complexity: medium
estimated_effort: "~45 min"
files:
  - README.md
  - backend.md
  - security.md
  - signature-verification.feature
  - response-types.feature
  - storefront-integration.feature
  - fixtures/proxy-requests.json
  - acceptance.md
---

# Shopify App Proxy

## 1. Overview

### Problem Statement

Shopify apps run in the admin iframe, but merchants often need app-generated content surfaced on their storefront — a loyalty widget, a review feed, a custom form. The App Proxy is Shopify's mechanism for this: Shopify forwards storefront requests to the app, and the app responds with HTML, JSON, or Liquid that Shopify renders within the active theme. Without App Proxy, apps have no legitimate way to inject dynamic content into the merchant's storefront under the store's own domain.

### User Stories

- **Merchant**: I want my app's product review widget to appear on my storefront under my store's domain, not a third-party URL
- **Merchant**: I want customers to be able to submit forms (loyalty sign-up, custom inquiries) powered by the app, from within my theme
- **Developer**: I want to serve Liquid templates that access theme context (cart, shop, customer) without managing a separate frontend deployment
- **Developer**: I want AJAX calls from theme JavaScript to hit a secure, Shopify-verified endpoint and get JSON back

### When to use this block

- App needs to surface content on the storefront (not just the admin)
- User mentions: "storefront widget", "liquid template", "app proxy", "theme integration", "/apps/ URL"
- App needs to serve content under the merchant's own domain via Shopify's proxy infrastructure

### When NOT to use

- Content only needed in the admin — use Admin API / embedded app instead
- Building a Headless storefront — use Storefront API directly
- Need customer authentication on the proxied endpoint — App Proxy requests are always public; use Storefront API + customer tokens instead

---

## 2. Data Model

No new tables. This block uses the `shops` table from `auth.shopify-oauth` to look up shop records by the `shop` query parameter Shopify forwards with every proxy request.

```mermaid
erDiagram
    shops {
        uuid id PK "gen_random_uuid()"
        text shop_domain UK "example.myshopify.com"
        text access_token "Encrypted at rest"
        text scopes "Comma-separated granted scopes"
        timestamptz installed_at
        timestamptz uninstalled_at "null if active"
        timestamptz created_at
        timestamptz updated_at
    }
```

### Shop Lookup

Every proxy request includes `shop=example.myshopify.com` as a query parameter. After signature verification, the handler looks up the shop:

```sql
SELECT * FROM shops WHERE shop_domain = $1 AND uninstalled_at IS NULL
```

---

## 3. Data Flow

```mermaid
flowchart TD
    A[Customer visits store URL with /apps/myapp/ path] --> B[Shopify intercepts request]
    B --> C[Shopify forwards to app: GET /api/proxy/*<br/>+ appends shop, path_prefix, timestamp, signature params]
    C --> D{Extract signature from query params}
    D --> E[Sort remaining params alphabetically]
    E --> F[Concatenate as key=value pairs]
    F --> G[HMAC-SHA256 with SHOPIFY_API_SECRET]
    G --> H{Computed == extracted signature?}
    H -->|No| I[401 Unauthorized]
    H -->|Yes| J[Look up shop by shop param]
    J -->|Not found| K[404 Shop not found]
    J -->|Found| L[Route to sub-path handler]
    L --> M{Determine response type}
    M -->|application/liquid| N[Return Liquid template<br/>Shopify renders in theme]
    M -->|application/json| O[Return JSON<br/>for AJAX calls]
    M -->|text/html| P[Return standalone HTML]
```

---

## 4. Sequence Diagrams

### Proxy Request — Happy Path (Liquid response)

```mermaid
sequenceDiagram
    actor C as Customer
    participant S as Shopify Storefront
    participant A as App Backend
    participant DB as Database

    C->>S: GET https://example-store.com/apps/myapp/reviews?product_id=123
    S->>A: GET /api/proxy/reviews?product_id=123&shop=example.myshopify.com&path_prefix=/apps/myapp&timestamp=1700000000&signature=abc123
    A->>A: Extract signature from query params
    A->>A: Sort remaining params: path_prefix, product_id, shop, timestamp
    A->>A: Concatenate: "path_prefix=/apps/myapp&product_id=123&shop=example.myshopify.com&timestamp=1700000000"
    A->>A: HMAC-SHA256 with SHOPIFY_API_SECRET → verify equals signature
    A->>DB: SELECT * FROM shops WHERE shop_domain = 'example.myshopify.com' AND uninstalled_at IS NULL
    DB-->>A: shop record
    A->>A: Fetch reviews for product_id=123 from database
    A-->>S: 200 OK, Content-Type: application/liquid<br/>{% assign reviews = ... %}...
    S->>S: Render Liquid within active theme layout
    S-->>C: Fully themed HTML with reviews widget
```

### Proxy Request — AJAX JSON Response

```mermaid
sequenceDiagram
    actor C as Customer Browser
    participant S as Shopify Storefront
    participant A as App Backend

    C->>S: fetch('/apps/myapp/api/loyalty-points', { headers: { Accept: 'application/json' } })
    S->>A: GET /api/proxy/api/loyalty-points?shop=example.myshopify.com&path_prefix=/apps/myapp&timestamp=...&signature=...
    A->>A: Verify signature
    A-->>S: 200 OK, Content-Type: application/json<br/>{ "points": 150, "tier": "gold" }
    S-->>C: JSON response
```

### Proxy Request — Invalid Signature

```mermaid
sequenceDiagram
    participant X as Attacker
    participant A as App Backend

    X->>A: GET /api/proxy/reviews?shop=example.myshopify.com&signature=forged
    A->>A: Sort params, compute HMAC
    A->>A: Computed HMAC ≠ forged signature
    A-->>X: 401 Unauthorized — signature_verification_failed
```

---

## 5. State Management

This block is backend-only. No client-side state — the proxy is a request/response cycle.

| State | Storage | Survives Reload | Notes |
|-------|---------|-----------------|-------|
| Shop context | Database (`shops` table, read-only) | Yes | Looked up per-request by `shop` param |
| Response cache | HTTP cache headers | Configurable | Set `Cache-Control: s-maxage=APP_PROXY_CACHE_TTL` |

### Cache Strategy

Proxy responses can be cached by Shopify's CDN. Cache keys must include `shop` to prevent cross-shop cache poisoning. Dynamic user-specific content should set `Cache-Control: no-store`.

---

## 6. Integration Points

### Inbound

| Caller | How | Purpose |
|--------|-----|---------|
| Shopify Storefront (proxy) | GET /api/proxy/* | Customer visits /apps/{subpath}/* on storefront |
| Theme JavaScript | GET /api/proxy/* via fetch | AJAX call from storefront theme code |

### Outbound

| Target | How | Purpose |
|--------|-----|---------|
| Database | SQL | Look up shop record by domain |
| Internal data sources | Function calls | Fetch content to render (e.g., reviews, loyalty data) |

### Events

| Event | Payload | When |
|-------|---------|------|
| `proxy.request_received` | `{ shopDomain, path, queryParams }` | Valid signature verified, before processing |
| `proxy.request_served` | `{ shopDomain, path, responseType, durationMs }` | Response sent successfully |

### Shopify Partner Dashboard Setup

The app proxy must be configured in the Shopify Partner Dashboard before requests are forwarded:

1. App setup → App proxy
2. Set subpath (e.g., `myapp`) — storefront URL becomes `/apps/myapp/*`
3. Set proxy URL (e.g., `https://myapp.com/api/proxy`)
4. Shopify forwards requests with `shop`, `path_prefix`, `timestamp`, `signature` appended

---

## 7. Configuration Surface

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `APP_PROXY_SUBPATH` | `string` | required | Base path for proxy handler (e.g., `/api/proxy`) |
| `APP_PROXY_CACHE_TTL` | `number` | `300` | Cache TTL in seconds for proxy responses (`s-maxage`) |
| `SHOPIFY_API_SECRET` | `string` | required | Used for HMAC signature verification (from `auth.shopify-oauth`) |
