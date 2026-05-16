# Security — Shopify App Billing & Subscriptions

## Threat Model

### 1. Price Manipulation

**Impact**: Critical — merchant could subscribe to a paid plan while paying $0 or an arbitrary amount.

**Mitigations**:
- Plan price is NEVER accepted from the client — `POST /api/billing/subscribe` body contains only `planSlug`
- Plan record (including price) is fetched server-side from the `billing_plans` table by slug, in a single statement: `SELECT * FROM billing_plans WHERE slug = $slug AND active = true`
- The `appSubscriptionCreate` mutation uses the server-fetched `price_amount` and `price_currency` — client cannot influence them
- `is_test` flag is stored per-plan in the database — client cannot set it to bypass real charges
- Any extra fields in the request body (`price_amount`, `is_test`, etc.) are silently dropped at validation time

### 2. Fake Charge Confirmation

**Impact**: Critical — merchant could fake an approved charge and gain access without paying.

**Mitigations**:
- Callback endpoint queries Shopify's `appSubscription(id)` node to verify `status === "ACTIVE"` — the `charge_id` query param alone is not trusted
- `charge_id` from the callback is matched against a `pending` row in `shop_subscriptions` — unknown `charge_id`s return 404
- Only the transition `pending → active` is allowed via the callback — an already-`active` subscription cannot be re-activated (callback returns 404)
- The Shopify GraphQL response is authenticated with the shop's access token via the `X-Shopify-Access-Token` header — a forged response would fail Shopify's mTLS / token check

### 3. Duplicate Usage Charges

**Impact**: High — merchants charged multiple times for the same event, causing billing disputes.

**Mitigations**:
- `usage_records.idempotency_key` has a `UNIQUE` constraint — duplicate keys are rejected at the DB layer
- Insert pattern is "insert-or-do-nothing on conflict": no error path on duplicate, returns existing row to the caller
- Callers must provide an idempotency key derived from the business event (e.g., `order-{orderId}-usage-{date}`); the spec rejects requests with a missing/empty key (422)
- Shopify's `appUsageRecordCreate` mutation also accepts an `idempotencyKey` argument — double protection at API layer
- On Shopify `userErrors`, the local row is preserved with `shopify_usage_id = 'ERROR'` so retries with the same key short-circuit at the DB layer (do NOT re-call Shopify)

### 4. Plan Bypass via Middleware Misconfiguration

**Impact**: High — unauthorized merchants access paid features without a subscription.

**Mitigations**:
- `requireActivePlan` middleware is applied at router/framework level — not inline in individual handlers
- Middleware checks DB for `status = 'active'` — in-memory caches or JWT claims are not trusted
- `BILLING_REQUIRED` defaults to `true` — developer must explicitly opt out, not in
- `pending`, `declined`, `cancelled`, `frozen` statuses do NOT grant access — only `active` passes the gate
- Middleware is tested independently of business logic (see `plan-gating.feature`)
- Session-token middleware runs **before** `requireActivePlan` — missing/invalid token returns 401, not 402

### 5. Test Charges in Production

**Impact**: Medium — test charges appear real in the Shopify Partner Dashboard but don't collect real money, creating accounting confusion and potential App Store policy violations.

**Mitigations**:
- `BILLING_TEST_MODE` env var controls whether test charges are created — separate from code logic
- `billing_plans.is_test` is a per-plan flag — test plans should not be subscribable in production unless `BILLING_TEST_MODE=true`
- Test charges are visible in the Partner Dashboard with a "TEST" label — flag mismatches are detectable
- At startup, validate: if app's environment indicator (e.g. `NODE_ENV === 'production'`, `DENO_ENV`, or merchant-defined) AND `BILLING_TEST_MODE === true`, emit a warning log

## Input Validation Rules

| Field | Validation | Error Code |
|-------|-----------|------------|
| `planSlug` (subscribe body) | Required, string, matches `^[a-z0-9\-]+$`, exists in `billing_plans` with `active=true` | `plan_not_found` |
| `charge_id` (callback query) | Required, non-empty string, matches `pending` row in `shop_subscriptions` | `subscription_not_found` |
| `description` (usage body) | Required, non-empty string, max 100 chars | `invalid_usage_params` |
| `amount` (usage body) | Required, number, `> 0`, max plan cap (if configured) | `invalid_usage_params` |
| `idempotencyKey` (usage body) | Required, non-empty string, max 255 chars | `invalid_usage_params` |

## Secrets Management

| Secret | Storage | Rotation |
|--------|---------|----------|
| `SHOPIFY_API_SECRET` | Environment variable | Inherited from `auth.shopify-oauth` |
| Shop access tokens | Database (encrypted) | Inherited from `auth.shopify-oauth` |
| `BILLING_TEST_MODE` | Environment variable | Toggle — no cryptographic material |

## Authorization Model

| Endpoint | Auth Method | Scope Check |
|----------|-------------|-------------|
| `GET /api/billing/plans` | None (public) | — |
| `POST /api/billing/subscribe` | Session token (shopId) | Shop must be installed and active |
| `GET /api/billing/callback` | `charge_id` matched to `pending` DB row | Shop derived from the matched subscription row |
| `GET /api/billing/status` | Session token (shopId) | Own shop only |
| `POST /api/billing/usage` | Session token (shopId) | Own shop only, active subscription required |
| Protected routes | `requireActivePlan` middleware | Active subscription per shop |

## Tenant Isolation

Every `shop_subscriptions` and `usage_records` query includes `shop_id` in the WHERE clause. Merchants cannot access other shops' subscription data. The `shopId` is **always** extracted from the verified session token context — never from request body or query params.

<!-- PATTERN: billing-tenant-isolation-query -->
<!-- PURPOSE: Illustrate the only safe shopId source (session-token context) vs the unsafe source (request body) -->
<!-- REFERENCE: runtime=node20+ dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - `req.context.shopId`: shape of session-token context object is set by auth.shopify-session-token middleware — name may differ in merchant project (e.g., `req.locals.shopId`, `c.get("shopId")`)
       - SQL placeholder `$1`: postgres-style; MySQL uses `?`; SQLite supports both
       - The wrong example below is a CODE SMELL the reviewer should grep for: any `req.body.shopId` / `req.query.shopId` reference in a WHERE clause -->

```typescript
// Correct — shopId from verified session token context
const subscription = await db.query(
  `SELECT * FROM shop_subscriptions WHERE shop_id = $1 AND status = 'active'`,
  [req.context.shopId]   // set by session-token middleware
);

// Wrong — shopId from request body (client-controlled, never trust)
const subscription = await db.query(
  `SELECT * FROM shop_subscriptions WHERE shop_id = $1`,
  [req.body.shopId]      // NEVER do this — tenant boundary violation
);
```
