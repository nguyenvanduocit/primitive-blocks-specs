# Shopify-Specific Primitive Blocks — Design Spec

**Date**: 2026-05-15
**Status**: Approved
**Scope**: 8 Shopify-specific blocks for embedded apps

## Context

The primitive-blocks-specs library contains 3 generic blocks (`auth.google-login`, `messaging.transactional-email`, `ugc.product-reviews`). This design adds 8 Shopify-specific blocks covering capabilities that the vast majority of embedded Shopify apps require.

**Target**: Embedded Shopify apps (run inside Shopify Admin iframe via App Bridge).

**Approach**: Composable blocks with explicit `prerequisites`. Each block is self-contained in its spec but declares dependencies via the `prerequisites` field in README frontmatter. `auth.shopify-oauth` is the foundation block.

**Category convention**: Organized by function (matching existing blocks), not under a `shopify.*` namespace. E.g., `auth.shopify-oauth`, `billing.shopify-charges`, `compliance.shopify-gdpr`.

## Dependency Graph

```
auth.shopify-oauth (foundation)
├── auth.shopify-session-token
│   ├── billing.shopify-charges
│   ├── data.shopify-metafields
│   └── operations.shopify-bulk
├── webhooks.shopify-webhooks
│   └── compliance.shopify-gdpr
└── integration.shopify-app-proxy
```

## Shared Patterns

These patterns are reused across multiple blocks. Each block spec references them; the first block that introduces a pattern owns its implementation.

### Shop Token Storage (owned by `auth.shopify-oauth`)

```sql
CREATE TABLE shops (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_domain   TEXT NOT NULL UNIQUE,  -- "example.myshopify.com"
  access_token  TEXT NOT NULL,          -- encrypted at rest
  scopes        TEXT NOT NULL,          -- comma-separated granted scopes
  installed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  uninstalled_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_shops_domain ON shops(shop_domain);
```

All blocks that need shop context query this table by `shop_domain` or `shops.id`.

### HMAC-SHA256 Verification (owned by `auth.shopify-oauth`)

Shopify signs OAuth callbacks, webhook payloads, and app proxy requests using HMAC-SHA256 with the app's API secret. Introduced in the OAuth block (first to need it), reused by all subsequent blocks. A shared utility:

```typescript
function verifyShopifyHmac(secret: string, data: string | Buffer, expectedHmac: string): boolean
```

Used by: `auth.shopify-oauth` (callback params), `webhooks.shopify-webhooks` (request body), `compliance.shopify-gdpr` (webhook body), `integration.shopify-app-proxy` (query params).

### GraphQL Admin API Client (owned by `auth.shopify-oauth`)

Authenticated GraphQL client with:
- Shop access token injection
- Rate limit handling (Shopify returns `X-Shopify-Shop-Api-Call-Limit` / cost-based throttling for GraphQL)
- Retry on 429 (respect `Retry-After`) and transient 5xx
- Request/response logging (redact tokens)

### Tenant Isolation

Every query includes `shop_id` (FK to `shops.id`) in WHERE clauses. Same pattern as `ugc.product-reviews`.

### Idempotent Webhook Processing (owned by `webhooks.shopify-webhooks`)

`webhook_deliveries.webhook_id` is UNIQUE — duplicate delivery returns 200 without reprocessing. Same concept as `messaging.transactional-email` idempotency key.

---

## Block Specifications

### 1. auth.shopify-oauth

| Field | Value |
|-------|-------|
| **ID** | `auth.shopify-oauth` |
| **Name** | Shopify App Installation & OAuth |
| **Version** | 1.0.0 |
| **Category** | auth |
| **Tags** | shopify, oauth, installation, access-token |
| **Prerequisites** | none |
| **Complexity** | medium |
| **Estimated effort** | ~45 min |

**Purpose**: Handle Shopify app installation flow — merchant clicks install, grants permissions, app receives offline access token for persistent API access.

**Data Model**:
- `shops` table (see Shared Patterns above)
- `oauth_nonces` — nonce (UNIQUE), shop_domain, expires_at (5 min TTL). Single-use CSRF protection.

**Key Endpoints**:
- `GET /api/auth/shopify` — Generate install URL with scopes + nonce, redirect merchant to Shopify
- `GET /api/auth/shopify/callback` — Verify HMAC + nonce + shop domain format, exchange code for offline access token, upsert shop record, redirect to embedded app URL
- Webhook handler for `APP_UNINSTALLED` — mark shop as uninstalled, optionally cleanup

**Sequence — Install Flow**:
```
Merchant → App: GET /api/auth/shopify?shop=example.myshopify.com
App: Generate nonce, store in oauth_nonces with 5min TTL
App → Shopify: Redirect to https://{shop}/admin/oauth/authorize?client_id=...&scope=...&redirect_uri=...&state={nonce}
Merchant → Shopify: Grant permissions
Shopify → App: GET /api/auth/shopify/callback?code=...&hmac=...&shop=...&state=...&timestamp=...
App: Verify HMAC over all params (except hmac+signature), verify nonce matches + not expired, verify shop domain format
App → Shopify: POST https://{shop}/admin/oauth/access_token {client_id, client_secret, code}
Shopify → App: {access_token, scope}
App: Upsert shops record (encrypt token), delete nonce
App → Merchant: Redirect to https://{shop}/admin/apps/{api_key}
```

**Security Threats**:
1. **CSRF via forged callback** — nonce single-use + 5min TTL + HMAC verification
2. **Shop domain spoofing** — validate `*.myshopify.com` format, verify HMAC signed by Shopify
3. **Access token exposure** — encrypt at rest, never log, never return to client
4. **Replay attack** — nonce is deleted after use, timestamp within acceptable window
5. **Scope escalation** — validate granted scopes match requested scopes

**Configuration**:
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `SHOPIFY_API_KEY` | string | required | App API key from Partner Dashboard |
| `SHOPIFY_API_SECRET` | string | required | App API secret |
| `SHOPIFY_SCOPES` | string | required | Comma-separated scopes (e.g., `read_products,write_orders`) |
| `APP_URL` | string | required | Full app URL (e.g., `https://myapp.com`) |
| `OAUTH_NONCE_TTL_SECONDS` | number | 300 | Nonce expiry time |

**Events emitted**: `shop.installed`, `shop.uninstalled`, `shop.token_refreshed` (if scopes change on reinstall)

**Feature files**: `install-flow.feature`, `uninstall.feature`, `security.feature`

---

### 2. auth.shopify-session-token

| Field | Value |
|-------|-------|
| **ID** | `auth.shopify-session-token` |
| **Name** | Shopify Session Token Verification |
| **Version** | 1.0.0 |
| **Category** | auth |
| **Tags** | shopify, session-token, jwt, app-bridge, embedded |
| **Prerequisites** | `auth.shopify-oauth` |
| **Complexity** | low |
| **Estimated effort** | ~30 min |

**Purpose**: Verify Shopify App Bridge session tokens (JWT) on every API request from the embedded app. This is the ongoing authentication mechanism after initial OAuth install.

**Data Model**: No new tables. Uses `shops` from `auth.shopify-oauth`.

**Key Component**: Authentication middleware that:
1. Extracts `Authorization: Bearer <session_token>` header
2. Decodes JWT (base64url, no library needed for decode — but verify signature)
3. Verifies HMAC-SHA256 signature using `SHOPIFY_API_SECRET`
4. Validates claims: `iss` matches shop domain, `dest` matches shop domain, `aud` equals `SHOPIFY_API_KEY`, `exp` not expired, `nbf` not before, `iat` reasonable
5. Looks up shop in `shops` table by `dest` claim domain
6. Attaches `{ shopId, shopDomain, accessToken }` to request context

**JWT Structure** (Shopify App Bridge token):
```json
{
  "iss": "https://example.myshopify.com/admin",
  "dest": "https://example.myshopify.com",
  "aud": "SHOPIFY_API_KEY",
  "sub": "42",           // Shopify user ID
  "exp": 1234567890,
  "nbf": 1234567890,
  "iat": 1234567890,
  "jti": "unique-token-id",
  "sid": "session-id"
}
```

**Security Threats**:
1. **Token forgery** — HMAC-SHA256 signature verification with app secret
2. **Expired token** — strict `exp` check (tokens live ~1 min, App Bridge auto-refreshes)
3. **Wrong audience** — `aud` must equal app's API key
4. **Cross-shop attack** — `iss`/`dest` must match, shop must exist in `shops` table
5. **Token replay** — `jti` claim for optional replay protection (short expiry makes this low-risk)

**Configuration**: Reuses `SHOPIFY_API_KEY` and `SHOPIFY_API_SECRET` from OAuth block. No additional config.

**Feature files**: `session-token-verification.feature`, `middleware-integration.feature`

---

### 3. webhooks.shopify-webhooks

| Field | Value |
|-------|-------|
| **ID** | `webhooks.shopify-webhooks` |
| **Name** | Shopify Webhook Management |
| **Version** | 1.0.0 |
| **Category** | webhooks |
| **Tags** | shopify, webhooks, hmac, events, real-time |
| **Prerequisites** | `auth.shopify-oauth` |
| **Complexity** | medium |
| **Estimated effort** | ~60 min |

**Purpose**: Register webhook subscriptions via GraphQL Admin API, receive incoming webhooks, verify HMAC signatures, and process idempotently. The event backbone for Shopify apps.

**Data Model**:
```sql
CREATE TABLE webhook_subscriptions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id       UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  topic         TEXT NOT NULL,          -- e.g., "ORDERS_CREATE"
  callback_url  TEXT NOT NULL,
  graphql_id    TEXT,                   -- Shopify's GID for the subscription
  active        BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(shop_id, topic)
);

CREATE TABLE webhook_deliveries (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id       UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  topic         TEXT NOT NULL,
  webhook_id    TEXT NOT NULL,          -- X-Shopify-Webhook-Id header
  payload_hash  TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'received', -- received, processing, processed, failed
  error         TEXT,
  processed_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(webhook_id)                   -- idempotency
);
```

**Key Endpoints**:
- Internal: `registerWebhooks(shopId)` — called after install, registers all configured topics via `webhookSubscriptionCreate` GraphQL mutation
- `POST /api/webhooks` — Receive all webhook topics, verify HMAC, route to handler
- Internal: `syncWebhooks(shopId)` — compare registered vs configured, add/remove as needed

**Key Flows**:

*Registration (after install):*
```
App install completes → registerWebhooks(shopId)
For each topic in WEBHOOK_TOPICS:
  → webhookSubscriptionCreate mutation with callbackUrl
  → Store subscription record with graphql_id
```

*Receiving:*
```
Shopify → POST /api/webhooks
  Headers: X-Shopify-Topic, X-Shopify-Shop-Domain, X-Shopify-Webhook-Id, X-Shopify-Hmac-Sha256
App:
  1. Verify HMAC(body, SHOPIFY_API_SECRET) === X-Shopify-Hmac-Sha256
  2. Respond 200 immediately (Shopify times out at 5s)
  3. Check idempotency: INSERT webhook_deliveries ON CONFLICT(webhook_id) DO NOTHING
  4. If new: route to topic handler, process async, update status
  5. If duplicate: skip processing
```

**Security Threats**:
1. **Forged webhooks** — HMAC-SHA256 verification mandatory on every request
2. **Replay attacks** — `webhook_id` uniqueness constraint prevents reprocessing
3. **Timeout causing retry storm** — respond 200 before processing, process async
4. **Missing webhooks** — reconciliation job to detect gaps (compare Shopify orders vs local)
5. **Payload tampering** — HMAC covers entire body

**Configuration**:
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `WEBHOOK_TOPICS` | string[] | `["APP_UNINSTALLED"]` | Topics to register |
| `WEBHOOK_PATH` | string | `/api/webhooks` | Endpoint path for receiving |
| `WEBHOOK_PROCESS_ASYNC` | boolean | true | Process in background after 200 response |

**Events emitted**: `webhook.received`, `webhook.processed`, `webhook.failed`

**Feature files**: `webhook-registration.feature`, `webhook-receiving.feature`, `webhook-idempotency.feature`

---

### 4. compliance.shopify-gdpr

| Field | Value |
|-------|-------|
| **ID** | `compliance.shopify-gdpr` |
| **Name** | Shopify GDPR Mandatory Webhooks |
| **Version** | 1.0.0 |
| **Category** | compliance |
| **Tags** | shopify, gdpr, privacy, data-erasure, mandatory |
| **Prerequisites** | `webhooks.shopify-webhooks` |
| **Complexity** | low |
| **Estimated effort** | ~30 min |

**Purpose**: Handle the 3 mandatory GDPR/privacy webhooks required by ALL Shopify App Store apps. Without these, app review will be rejected.

**Data Model**:
```sql
CREATE TABLE gdpr_requests (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id           UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  request_type      TEXT NOT NULL,  -- 'customers_data_request' | 'customers_redact' | 'shop_redact'
  shopify_request_id TEXT,
  customer_id       BIGINT,         -- Shopify customer ID (null for shop_redact)
  customer_email    TEXT,           -- for data lookup (null for shop_redact)
  orders_requested  BIGINT[],      -- order IDs to include in data request
  status            TEXT NOT NULL DEFAULT 'received', -- received, processing, completed, failed
  completed_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_gdpr_shop ON gdpr_requests(shop_id);
```

**3 Mandatory Endpoints**:

1. **`POST /api/gdpr/customers-data-request`** — Shopify asks app to provide all data stored for a customer
   - Payload: `{ shop_id, shop_domain, customer: { id, email, phone }, orders_requested: [id...] }`
   - Action: Query all app tables for customer data, package into response or email to shop owner
   - Response: 200 (acknowledge receipt, process async)

2. **`POST /api/gdpr/customers-redact`** — Shopify orders app to erase customer's personal data
   - Payload: `{ shop_id, shop_domain, customer: { id, email, phone }, orders_to_redact: [id...] }`
   - Action: Delete or anonymize all PII for this customer across app tables
   - Response: 200

3. **`POST /api/gdpr/shop-redact`** — Shopify orders app to erase ALL data for a shop (48h after uninstall)
   - Payload: `{ shop_id, shop_domain }`
   - Action: Purge all shop data — cascade delete from `shops` table or explicit purge per table
   - Response: 200

**Security Threats**:
1. **Forged GDPR request** — HMAC verification (reuse from webhooks block)
2. **Incomplete data erasure** — enumerate ALL tables with customer/shop data, verify purge completeness
3. **Audit gap** — `gdpr_requests` table provides compliance audit trail
4. **Race condition** — idempotent processing by `shopify_request_id`

**Configuration**:
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `GDPR_DATA_RETENTION_DAYS` | number | 0 | Days to retain data after erasure request (0 = immediate) |
| `GDPR_NOTIFY_EMAIL` | string | null | Email to notify on data requests |

**Events emitted**: `gdpr.data_requested`, `gdpr.customer_redacted`, `gdpr.shop_redacted`

**Feature files**: `data-request.feature`, `customer-redact.feature`, `shop-redact.feature`

---

### 5. billing.shopify-charges

| Field | Value |
|-------|-------|
| **ID** | `billing.shopify-charges` |
| **Name** | Shopify App Billing & Subscriptions |
| **Version** | 1.0.0 |
| **Category** | billing |
| **Tags** | shopify, billing, subscriptions, charges, monetization |
| **Prerequisites** | `auth.shopify-session-token` |
| **Complexity** | high |
| **Estimated effort** | ~90 min |

**Purpose**: Monetize Shopify apps via recurring subscriptions, one-time charges, and usage-based billing using Shopify's Billing API (GraphQL).

**Data Model**:
```sql
CREATE TABLE billing_plans (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL UNIQUE,
  slug          TEXT NOT NULL UNIQUE,   -- URL-safe identifier
  price_amount  DECIMAL(10,2) NOT NULL,
  price_currency TEXT NOT NULL DEFAULT 'USD',
  interval      TEXT NOT NULL DEFAULT 'EVERY_30_DAYS', -- EVERY_30_DAYS | ANNUAL
  trial_days    INTEGER NOT NULL DEFAULT 0,
  is_test       BOOLEAN NOT NULL DEFAULT false,
  features      JSONB NOT NULL DEFAULT '[]',  -- feature flags for this plan
  sort_order    INTEGER NOT NULL DEFAULT 0,
  active        BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE shop_subscriptions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id         UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  plan_id         UUID NOT NULL REFERENCES billing_plans(id),
  shopify_charge_id TEXT,               -- Shopify's charge GID
  status          TEXT NOT NULL DEFAULT 'pending',
    -- pending → active, pending → declined, active → cancelled, active → frozen, frozen → active
  confirmation_url TEXT,                -- URL merchant must visit to approve
  trial_ends_at   TIMESTAMPTZ,
  activated_at    TIMESTAMPTZ,
  cancelled_at    TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sub_shop ON shop_subscriptions(shop_id);
CREATE INDEX idx_sub_status ON shop_subscriptions(shop_id, status);

CREATE TABLE usage_records (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id         UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  subscription_id UUID NOT NULL REFERENCES shop_subscriptions(id),
  description     TEXT NOT NULL,
  amount          DECIMAL(10,2) NOT NULL,
  idempotency_key TEXT UNIQUE,          -- prevent duplicate charges
  shopify_usage_id TEXT,                -- Shopify's usage record GID
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**Key Endpoints**:
- `GET /api/billing/plans` — List available plans (public, no auth needed for plan display)
- `POST /api/billing/subscribe` — Create subscription: `appSubscriptionCreate` mutation → return `confirmationUrl`
- `GET /api/billing/callback` — After merchant approves, Shopify redirects here with `charge_id` → activate subscription
- `GET /api/billing/status` — Current shop's subscription status + plan features
- `POST /api/billing/usage` — Record usage charge against active subscription
- Middleware: `requireActivePlan` — gate app access behind active subscription

**Sequence — Subscribe Flow**:
```
Merchant → App: POST /api/billing/subscribe { planSlug: "pro" }
App: Lookup plan, build lineItems
App → Shopify: appSubscriptionCreate mutation {
  name, lineItems: [{ plan: { appRecurringPricingDetails: { price, interval } } }],
  returnUrl: APP_URL/api/billing/callback,
  test: plan.is_test,
  trialDays: plan.trial_days
}
Shopify → App: { confirmationUrl, id (charge GID) }
App: Create shop_subscriptions record (status: pending, confirmation_url, shopify_charge_id)
App → Merchant: Redirect to confirmationUrl

Merchant approves on Shopify:
Shopify → App: GET /api/billing/callback?charge_id=...
App: Verify charge_id matches pending subscription
App → Shopify: Query appSubscription(id) to confirm ACTIVE status
App: Update subscription status → active, set activated_at
App → Merchant: Redirect to app dashboard
```

**Status State Machine**:
```
pending → active (merchant approves)
pending → declined (merchant declines)
active → cancelled (merchant or app cancels)
active → frozen (payment failed)
frozen → active (payment recovered)
```

**Security Threats**:
1. **Price manipulation** — plan lookup server-side by slug, price from DB not client
2. **Fake charge confirmation** — verify charge status via Shopify API after redirect
3. **Duplicate usage charges** — idempotency_key on usage_records
4. **Plan bypass** — `requireActivePlan` middleware on all protected routes
5. **Test charge in production** — `is_test` flag per plan, validate against environment

**Configuration**:
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `BILLING_REQUIRED` | boolean | true | Gate app behind active subscription |
| `BILLING_TRIAL_DAYS` | number | 7 | Default trial period |
| `BILLING_TEST_MODE` | boolean | false | Create test charges (for development) |
| `BILLING_RETURN_PATH` | string | `/` | Redirect path after charge approval |

**Events emitted**: `subscription.created`, `subscription.activated`, `subscription.declined`, `subscription.cancelled`, `usage.recorded`

**Feature files**: `plan-selection.feature`, `subscription-lifecycle.feature`, `usage-billing.feature`, `plan-gating.feature`

**Frontend**: `frontend.md` — Plan selection UI, billing status display, upgrade/downgrade flow.

---

### 6. data.shopify-metafields

| Field | Value |
|-------|-------|
| **ID** | `data.shopify-metafields` |
| **Name** | Shopify Metafields |
| **Version** | 1.0.0 |
| **Category** | data |
| **Tags** | shopify, metafields, custom-data, graphql |
| **Prerequisites** | `auth.shopify-session-token` |
| **Complexity** | medium |
| **Estimated effort** | ~60 min |

**Purpose**: Read/write metafields on Shopify resources (products, orders, customers, shop). Standard pattern for apps that extend Shopify's data model with custom fields.

**Data Model**:
```sql
-- Local registry of metafield definitions (mirrors Shopify's, used for validation + sync)
CREATE TABLE metafield_definitions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id       UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  namespace     TEXT NOT NULL,
  key           TEXT NOT NULL,
  owner_type    TEXT NOT NULL,       -- PRODUCT, ORDER, CUSTOMER, SHOP, etc.
  type          TEXT NOT NULL,       -- single_line_text_field, number_integer, json, etc.
  name          TEXT NOT NULL,       -- human-readable name
  description   TEXT,
  shopify_gid   TEXT,                -- Shopify's GID for the definition
  synced_at     TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(shop_id, namespace, key, owner_type)
);
```

Note: Metafield **values** live in Shopify, not in the app's DB. The app only stores definitions for validation and sync purposes.

**Key Endpoints**:
- `POST /api/metafields/sync-definitions` — Register/sync metafield definitions with Shopify via `metafieldDefinitionCreate`
- `GET /api/metafields/:ownerType/:ownerId` — Read metafields for a resource via GraphQL
- `POST /api/metafields/:ownerType/:ownerId` — Set metafield values via `metafieldsSet` mutation
- `DELETE /api/metafields/:ownerType/:ownerId/:namespace/:key` — Delete a metafield value
- `GET /api/metafield-definitions` — List registered definitions for current shop

**Key Flows**:

*Definition sync (on install or config change):*
```
App → Shopify: metafieldDefinitionCreate mutation per configured definition
  { namespace, key, name, description, type, ownerType, pin: true }
Shopify → App: { id (GID) }
App: Upsert metafield_definitions record with shopify_gid
```

*Read metafields:*
```
App → Shopify: query product(id) { metafield(namespace, key) { value, type } }
  or: query product(id) { metafields(first: 50, namespace: "myapp") { edges { node { ... } } } }
```

*Write metafields:*
```
App → Shopify: metafieldsSet mutation {
  metafields: [{ ownerId, namespace, key, type, value }]
}
```

**Supported Metafield Types**:
- Text: `single_line_text_field`, `multi_line_text_field`, `rich_text_field`
- Numeric: `number_integer`, `number_decimal`
- Boolean: `boolean`
- Date/time: `date`, `date_time`
- Structured: `json`, `url`, `color`
- Reference: `product_reference`, `variant_reference`, `collection_reference`, `file_reference`
- Lists: `list.single_line_text_field`, `list.number_integer`, etc.

**Security Threats**:
1. **Scope mismatch** — validate required scopes exist (`read_products`/`write_products` etc.) before API calls
2. **Namespace collision** — use app-specific namespace prefix (e.g., `$app:myapp` or custom namespace)
3. **Type mismatch** — validate value against type before sending to Shopify (prevent 422s)
4. **Data leakage via storefront** — metafields are private by default; explicit `storefrontAccess` grant required
5. **Rate limiting** — batch metafield writes via `metafieldsSet` (up to 25 per call)

**Configuration**:
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `METAFIELD_NAMESPACE` | string | app handle | Namespace prefix for all metafields |
| `METAFIELD_DEFINITIONS` | object[] | [] | Array of { key, name, type, ownerType, description } |
| `METAFIELD_PIN_TO_ADMIN` | boolean | true | Pin definitions in Shopify admin UI |

**Events emitted**: `metafield.synced`, `metafield.set`, `metafield.deleted`

**Feature files**: `definition-sync.feature`, `read-write.feature`, `type-validation.feature`

---

### 7. integration.shopify-app-proxy

| Field | Value |
|-------|-------|
| **ID** | `integration.shopify-app-proxy` |
| **Name** | Shopify App Proxy |
| **Version** | 1.0.0 |
| **Category** | integration |
| **Tags** | shopify, app-proxy, storefront, liquid |
| **Prerequisites** | `auth.shopify-oauth` |
| **Complexity** | medium |
| **Estimated effort** | ~45 min |

**Purpose**: Serve custom content within the storefront context via Shopify App Proxy. Shopify forwards storefront requests to the app, which responds with HTML, JSON, or Liquid (rendered within the active theme).

**Data Model**: No new tables. Uses `shops` from `auth.shopify-oauth` for shop lookup.

**Key Endpoints**:
- `GET /api/proxy/*` — Catch-all handler for proxied requests
- Each sub-path maps to a specific feature (e.g., `/api/proxy/reviews` → product reviews widget, `/api/proxy/form` → custom form)

**Key Flows**:

*Proxy request:*
```
Customer visits: https://example-store.com/apps/myapp/reviews?product_id=123
Shopify → App: GET /api/proxy/reviews?product_id=123&shop=example.myshopify.com
  &path_prefix=/apps/myapp&timestamp=...&signature=...
App:
  1. Extract signature from query params
  2. Sort remaining params alphabetically
  3. Build HMAC-SHA256 of sorted params using SHOPIFY_API_SECRET
  4. Compare computed HMAC with signature
  5. Look up shop by shop param
  6. Process request, return response
```

**Response Types**:
- `application/liquid` — Liquid template rendered within the store's theme layout. Access to `shop`, `cart`, `customer` Liquid objects.
- `application/json` — Raw JSON for AJAX calls from theme JavaScript.
- `text/html` — Standalone HTML (not rendered within theme).

**Security Threats**:
1. **Forged proxy requests** — HMAC signature verification on query params (required)
2. **Sensitive data in public responses** — proxy endpoints are public (no customer auth). Never expose PII, order details, or admin data.
3. **XSS via Liquid injection** — sanitize all dynamic content inserted into Liquid templates. Use Liquid's `| escape` filter.
4. **Cache poisoning** — include `shop` in cache keys, set appropriate `Cache-Control` headers
5. **Timing attacks** — use constant-time comparison for HMAC verification

**Configuration**:
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `APP_PROXY_SUBPATH` | string | `/api/proxy` | Base path for proxy handler |
| `APP_PROXY_CACHE_TTL` | number | 300 | Cache TTL in seconds for proxy responses |

**Events emitted**: `proxy.request_received`, `proxy.request_served`

**Feature files**: `signature-verification.feature`, `response-types.feature`, `storefront-integration.feature`

---

### 8. operations.shopify-bulk

| Field | Value |
|-------|-------|
| **ID** | `operations.shopify-bulk` |
| **Name** | Shopify Bulk Operations |
| **Version** | 1.0.0 |
| **Category** | operations |
| **Tags** | shopify, bulk, graphql, async, large-datasets, jsonl |
| **Prerequisites** | `auth.shopify-session-token` |
| **Complexity** | high |
| **Estimated effort** | ~75 min |

**Purpose**: Execute async bulk queries and mutations for large datasets via Shopify's `bulkOperationRunQuery` and `bulkOperationRunMutation`. Process results from JSONL downloads.

**Data Model**:
```sql
CREATE TABLE bulk_operations (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id             UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  shopify_operation_id TEXT UNIQUE,     -- Shopify's bulk operation GID
  type                TEXT NOT NULL,    -- 'query' | 'mutation'
  status              TEXT NOT NULL DEFAULT 'created',
    -- created → running → completed | failed | cancelled
  query_text          TEXT NOT NULL,    -- the GraphQL query/mutation
  result_url          TEXT,             -- JSONL download URL (time-limited)
  error_code          TEXT,
  error_message       TEXT,
  object_count        BIGINT,          -- number of objects in result
  file_size           BIGINT,          -- result file size in bytes
  started_at          TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_bulk_shop ON bulk_operations(shop_id);
CREATE INDEX idx_bulk_status ON bulk_operations(shop_id, status);
```

**Key Endpoints**:
- `POST /api/bulk/query` — Submit a bulk query, return operation ID
- `POST /api/bulk/mutation` — Upload JSONL staging file + submit bulk mutation
- `GET /api/bulk/status/:operationId` — Check operation status
- `POST /api/bulk/cancel/:operationId` — Cancel a running operation
- `GET /api/bulk/results/:operationId` — Download + parse JSONL results
- Webhook handler for `BULK_OPERATIONS_FINISH` — update status, trigger result processing

**Key Flows**:

*Bulk Query:*
```
App → Shopify: bulkOperationRunQuery mutation {
  query: "{ products { edges { node { id title variants { edges { node { id price } } } } } } }"
}
Shopify → App: { bulkOperation { id, status: CREATED } }
App: Store in bulk_operations (status: created)

Option A — Webhook (preferred):
  Shopify → App: BULK_OPERATIONS_FINISH webhook { admin_graphql_api_id, ... }
  App: Query currentBulkOperation for result URL

Option B — Polling:
  App → Shopify: query currentBulkOperation { id, status, url, objectCount }
  Repeat until status = COMPLETED or FAILED

App: Download JSONL from result URL
App: Parse line by line, process each JSON object
App: Update bulk_operations record (status, object_count, file_size)
```

*Bulk Mutation:*
```
App → Shopify: stagedUploadsCreate mutation { resource: BULK_MUTATION_VARIABLES, ... }
Shopify → App: { stagedTargets: [{ url, parameters }] }
App: Upload JSONL file to staged URL (multipart form)
App → Shopify: bulkOperationRunMutation mutation {
  mutation: "mutation ($input: ProductInput!) { productUpdate(input: $input) { product { id } } }",
  stagedUploadPath: "..."
}
App: Poll or webhook for completion
```

**Constraints**:
- One bulk query and one bulk mutation per shop at a time
- Results available for a limited time (~24h)
- JSONL format: one JSON object per line, nested objects have `__parentId` field
- Maximum query complexity limits apply

**Security Threats**:
1. **Result URL exposure** — URLs are time-limited and signed by Shopify, but never expose to client
2. **Staging upload abuse** — validate JSONL content before upload, enforce size limits
3. **Resource exhaustion** — limit concurrent bulk operations per shop, respect Shopify's 1-per-type limit
4. **Sensitive data in results** — process results server-side, apply same access controls as direct API
5. **Incomplete processing** — track object_count, verify all lines processed, handle partial failures

**Configuration**:
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `BULK_PREFER_WEBHOOK` | boolean | true | Use webhook instead of polling for completion |
| `BULK_POLL_INTERVAL_MS` | number | 2000 | Polling interval (if not using webhook) |
| `BULK_MAX_POLL_ATTEMPTS` | number | 500 | Max polling attempts before timeout |
| `BULK_RESULT_PROCESSING_BATCH_SIZE` | number | 1000 | Lines to process per batch from JSONL |

**Events emitted**: `bulk.started`, `bulk.completed`, `bulk.failed`, `bulk.results_processed`

**Feature files**: `bulk-query.feature`, `bulk-mutation.feature`, `status-tracking.feature`, `result-processing.feature`

---

## Per-Block File Structure

Each block follows the standard primitive-block interface:

```
{category}/{feature-slug}/
├── README.md                 # Frontmatter + architecture
├── backend.md                # API endpoints, core patterns, error handling
├── security.md               # Threat model, validation, secrets
├── *.feature                 # Gherkin BDD scenarios (1 per feature area)
├── fixtures/*.json           # Test data, mock API responses
├── tests/unit.ts             # Unit test patterns
├── tests/integration.ts      # E2E test patterns
└── acceptance.md             # Post-implementation checklist
```

Blocks with merchant-facing UI also include:
- `frontend.md` — UI components, state management, UX patterns

Applies to: `billing.shopify-charges` (plan selection UI), `data.shopify-metafields` (metafield editor UI).

## Implementation Order

Based on dependencies, the recommended build order:

1. **auth.shopify-oauth** — foundation, everything depends on it
2. **auth.shopify-session-token** — enables all embedded app API calls
3. **webhooks.shopify-webhooks** — event backbone
4. **compliance.shopify-gdpr** — mandatory for App Store, depends on webhooks
5. **billing.shopify-charges** — monetization, most complex block
6. **data.shopify-metafields** — very common, medium complexity
7. **integration.shopify-app-proxy** — storefront integration
8. **operations.shopify-bulk** — advanced, for data-heavy apps

Blocks 5-8 can be built in parallel after 1-4 are complete.

## Decisions Deferred to Implementation

- Exact Shopify API version to target (latest stable at implementation time)
- Specific ORM/query builder for SQL (Drizzle, Prisma, raw SQL — depends on merchant stack)
- Token encryption method (AES-256-GCM recommended, but depends on runtime)
- Background job framework for async webhook processing (depends on merchant stack)
- Whether to use `@shopify/shopify-api` library or raw HTTP/GraphQL calls
