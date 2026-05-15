---
id: "auth.shopify-oauth"
name: "Shopify App Installation & OAuth"
version: "1.0.0"
category: "auth"
tags: [shopify, oauth, installation, access-token, embedded-app]
prerequisites: []
complexity: medium
estimated_effort: "~45 min"
files:
  - README.md
  - backend.md
  - security.md
  - install-flow.feature
  - uninstall.feature
  - security.feature
  - fixtures/oauth-callback.json
  - fixtures/shop-records.json
  - acceptance.md
---

# Shopify App Installation & OAuth

## 1. Overview

### Problem Statement

Every Shopify app must implement the OAuth handshake to get installed on a merchant's store. The merchant clicks "Install" → Shopify redirects to the app with a permission prompt → the merchant grants access → Shopify returns an authorization code → the app exchanges it for an offline access token. This token persists and gives the app API access to the store's data. Without this flow, the app cannot read products, process orders, or do anything useful.

### User Stories

- **Merchant**: I found an app in the Shopify App Store, I want to install it on my store so it can access my store data and provide its features
- **Merchant**: I want to reinstall an app I previously uninstalled, and have it recognize my store
- **Merchant**: I want to uninstall an app and trust that it stops accessing my store data
- **Developer**: I want a secure, spec-compliant OAuth flow that handles edge cases like reinstalls, scope changes, and concurrent installations

### When to use this block

- App needs to be installed on Shopify stores
- User mentions: "shopify app", "install app", "oauth", "access token", "app installation"
- App needs to call Shopify Admin API on behalf of a merchant

### When NOT to use

- Building a Shopify theme (no OAuth needed)
- Building a sales channel (uses different auth flow)
- Need ongoing request authentication for embedded app → use `auth.shopify-session-token` (which depends on this block)

---

## 2. Data Model

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

    oauth_nonces {
        uuid id PK "gen_random_uuid()"
        text nonce UK "Random 32-char hex"
        text shop_domain "Which shop initiated"
        timestamptz expires_at "5 min TTL"
        timestamptz created_at
    }

    shops ||--o{ oauth_nonces : "generates during install"
```

### Table: `shops`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, default `gen_random_uuid()` | |
| `shop_domain` | `text` | NOT NULL, UNIQUE | `example.myshopify.com` format |
| `access_token` | `text` | NOT NULL | Encrypted at rest |
| `scopes` | `text` | NOT NULL | Comma-separated, e.g. `read_products,write_orders` |
| `installed_at` | `timestamptz` | NOT NULL, default `now()` | |
| `uninstalled_at` | `timestamptz` | nullable | Set on `APP_UNINSTALLED` webhook |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | |
| `updated_at` | `timestamptz` | NOT NULL, default `now()` | |

### Table: `oauth_nonces`

Single-use CSRF tokens for the OAuth callback. Deleted immediately after use.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, default `gen_random_uuid()` | |
| `nonce` | `text` | NOT NULL, UNIQUE | Random 32-char hex string |
| `shop_domain` | `text` | NOT NULL | Which shop initiated the flow |
| `expires_at` | `timestamptz` | NOT NULL | 5 minutes from creation |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | |

### Migration (reference)

```sql
CREATE TABLE IF NOT EXISTS shops (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_domain text NOT NULL UNIQUE,
  access_token text NOT NULL,
  scopes text NOT NULL,
  installed_at timestamptz NOT NULL DEFAULT now(),
  uninstalled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_shops_domain ON shops(shop_domain);

CREATE TABLE IF NOT EXISTS oauth_nonces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nonce text NOT NULL UNIQUE,
  shop_domain text NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_nonces_expires ON oauth_nonces(expires_at);
```

---

## 3. Data Flow

```mermaid
flowchart TD
    A[Merchant clicks Install in App Store] --> B[GET /api/auth/shopify?shop=example.myshopify.com]
    B --> C[Validate shop domain format]
    C -->|Invalid| D[400 Bad Request]
    C -->|Valid| E[Generate nonce, store in oauth_nonces with 5min TTL]
    E --> F[Redirect to Shopify OAuth authorize URL]
    F --> G[Merchant reviews permissions on Shopify]
    G -->|Grants| H[Shopify redirects to callback with code + HMAC]
    G -->|Denies| I[Merchant stays on Shopify]
    H --> J[GET /api/auth/shopify/callback?code=...&hmac=...&shop=...&state=...&timestamp=...]
    J --> K{Verify HMAC signature}
    K -->|Invalid| L[401 Unauthorized]
    K -->|Valid| M{Verify nonce matches + not expired}
    M -->|Invalid| N[401 Invalid state]
    M -->|Valid| O{Validate shop domain format}
    O -->|Invalid| P[400 Invalid shop]
    O -->|Valid| Q[Exchange code for offline access token]
    Q --> R[POST https://shop/admin/oauth/access_token]
    R --> S[Receive access_token + scopes]
    S --> T[Upsert shop record, encrypt token]
    T --> U[Delete used nonce]
    U --> V[Emit shop.installed event]
    V --> W[Redirect to embedded app URL]

    X[APP_UNINSTALLED webhook] --> Y[Verify HMAC]
    Y --> Z[Set shop.uninstalled_at = now]
    Z --> AA[Emit shop.uninstalled event]
```

---

## 4. Sequence Diagrams

### Install Flow (happy path)

```mermaid
sequenceDiagram
    actor M as Merchant
    participant S as Shopify
    participant A as App Backend
    participant DB as Database

    M->>A: GET /api/auth/shopify?shop=example.myshopify.com
    A->>A: Validate shop domain (*.myshopify.com)
    A->>DB: INSERT oauth_nonces (nonce, shop_domain, expires_at=now+5min)
    A->>S: Redirect to https://example.myshopify.com/admin/oauth/authorize<br/>?client_id=API_KEY&scope=SCOPES&redirect_uri=CALLBACK_URL&state=NONCE
    M->>S: Review and grant permissions
    S->>A: GET /api/auth/shopify/callback?code=AUTH_CODE&hmac=HMAC&shop=example.myshopify.com&state=NONCE&timestamp=TS
    A->>A: Verify HMAC over query params using SHOPIFY_API_SECRET
    A->>DB: SELECT nonce FROM oauth_nonces WHERE nonce=$1 AND expires_at > now()
    DB-->>A: nonce found
    A->>DB: DELETE FROM oauth_nonces WHERE nonce=$1
    A->>S: POST https://example.myshopify.com/admin/oauth/access_token<br/>{client_id, client_secret, code}
    S-->>A: {access_token: "ACCESS_TOKEN", scope: "read_products,write_orders"}
    A->>A: Encrypt access_token
    A->>DB: INSERT shops ON CONFLICT(shop_domain) DO UPDATE SET access_token, scopes, installed_at, uninstalled_at=null
    A->>A: Emit shop.installed event
    A->>M: Redirect to https://example.myshopify.com/admin/apps/API_KEY
```

### Install Flow (HMAC verification failure)

```mermaid
sequenceDiagram
    actor M as Merchant
    participant S as Shopify
    participant A as App Backend

    S->>A: GET /api/auth/shopify/callback?code=xxx&hmac=TAMPERED&shop=example.myshopify.com&state=NONCE
    A->>A: Compute HMAC over query params
    A->>A: Computed HMAC ≠ received HMAC
    A->>M: 401 Unauthorized — HMAC verification failed
```

### Uninstall Flow

```mermaid
sequenceDiagram
    participant S as Shopify
    participant A as App Backend
    participant DB as Database

    S->>A: POST /api/webhooks (topic: APP_UNINSTALLED)
    A->>A: Verify HMAC on request body
    A->>DB: UPDATE shops SET uninstalled_at=now() WHERE shop_domain=$1
    A->>A: Emit shop.uninstalled event
    A-->>S: 200 OK
```

---

## 5. State Management

This block is backend-only. No frontend state — the OAuth flow uses server-side redirects.

| State | Storage | Survives Reload | Notes |
|-------|---------|-----------------|-------|
| `shop` | Database (`shops` table) | Yes | Persistent shop record with encrypted token |
| `nonce` | Database (`oauth_nonces` table) | Yes (5min TTL) | Deleted after single use |
| `install redirect` | HTTP redirect chain | No | Browser follows redirects |

### State transitions

```
Initial → GET /api/auth/shopify → nonce created → redirect to Shopify
Shopify → callback → nonce verified + deleted → code exchanged → shop upserted
APP_UNINSTALLED webhook → shop.uninstalled_at set
Reinstall → same flow, upsert overwrites token + clears uninstalled_at
```

---

## 6. Integration Points

### Inbound

| Caller | How | Purpose |
|--------|-----|---------|
| Shopify App Store / Manual URL | HTTP redirect | Initiate install flow |
| Shopify OAuth server | HTTP redirect | Return authorization code |
| Shopify webhook system | POST /api/webhooks | APP_UNINSTALLED notification |

### Outbound

| Target | How | Purpose |
|--------|-----|---------|
| Shopify OAuth endpoint | POST `https://{shop}/admin/oauth/access_token` | Exchange code for token |
| Database | SQL | Store shop + nonce records |

### Events

| Event | Payload | When |
|-------|---------|------|
| `shop.installed` | `{ shopId, shopDomain, scopes }` | OAuth flow completes, shop record upserted |
| `shop.uninstalled` | `{ shopId, shopDomain }` | APP_UNINSTALLED webhook received |
| `shop.reinstalled` | `{ shopId, shopDomain, previousScopes, newScopes }` | Shop reinstalls (upsert detects existing record) |

### Shared Utilities Introduced

This block introduces two shared utilities used by downstream blocks:

1. **HMAC-SHA256 verification** — `verifyShopifyHmac(secret, data, expectedHmac)` — constant-time comparison, used by webhooks, GDPR, app proxy blocks
2. **GraphQL Admin API client** — authenticated client with rate limiting, retry on 429/5xx, token injection from `shops` table

---

## 7. Configuration Surface

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `SHOPIFY_API_KEY` | `string` | required | App API key from Shopify Partner Dashboard |
| `SHOPIFY_API_SECRET` | `string` | required | App API secret (used for HMAC + token exchange) |
| `SHOPIFY_SCOPES` | `string` | required | Comma-separated scopes, e.g. `read_products,write_orders` |
| `APP_URL` | `string` | required | Full app URL (e.g. `https://myapp.com`) for redirect_uri |
| `OAUTH_NONCE_TTL_SECONDS` | `number` | `300` | Nonce expiry time (5 min default) |
