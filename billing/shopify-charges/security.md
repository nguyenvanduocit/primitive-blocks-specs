# Security — Shopify App Billing & Subscriptions

## Threat Model

### 1. Price Manipulation

**Impact**: Critical — merchant could subscribe to a paid plan while paying $0 or an arbitrary amount.

**Mitigations**:
- Plan price is NEVER accepted from the client — `POST /api/billing/subscribe` takes only `planSlug`
- Plan record (including price) is fetched server-side from `billing_plans` by slug
- The `appSubscriptionCreate` mutation uses the server-fetched price — client cannot influence it
- `is_test` flag is stored per-plan in the database — client cannot set it to bypass real charges

### 2. Fake Charge Confirmation

**Impact**: Critical — merchant could fake an approved charge and gain access without paying.

**Mitigations**:
- Callback endpoint queries Shopify's `appSubscription(id)` node to verify `status === "ACTIVE"` — the charge_id alone is not trusted
- `charge_id` from the callback is matched against a `pending` record in `shop_subscriptions` — unknown charge_ids return 404
- Only the transition `pending → active` is allowed via the callback — an already-active subscription cannot be re-activated
- Shopify signs the `appSubscription` response with the shop's access token — a forged response would fail authentication

### 3. Duplicate Usage Charges

**Impact**: High — merchants charged multiple times for the same event, causing billing disputes.

**Mitigations**:
- `usage_records.idempotency_key` has a `UNIQUE` constraint — duplicate keys are silently ignored
- `INSERT ... ON CONFLICT (idempotency_key) DO NOTHING` is used — no error, returns existing record
- Callers must provide an idempotency key derived from the business event (e.g., `order-{orderId}-usage-{date}`)
- Shopify's `appUsageRecordCreate` also accepts an `idempotencyKey` — double protection at API layer

### 4. Plan Bypass via Middleware Misconfiguration

**Impact**: High — unauthorized merchants access paid features without a subscription.

**Mitigations**:
- `requireActivePlan` middleware is applied at router/framework level — not inline in individual handlers
- Middleware checks DB for `status = 'active'` — in-memory state or JWT claims are not trusted
- `BILLING_REQUIRED` defaults to `true` — developer must explicitly opt out, not in
- `pending` status does NOT grant access — only `active` status passes the gate
- Middleware is tested independently of business logic (see `plan-gating.feature`)

### 5. Test Charges in Production

**Impact**: Medium — test charges appear real in the Shopify Partner Dashboard but don't collect real money, creating accounting confusion and potential App Store policy violations.

**Mitigations**:
- `BILLING_TEST_MODE` env var controls whether test charges are created — separate from code logic
- `billing_plans.is_test` is a per-plan flag — test plans cannot be subscribed to in production unless `BILLING_TEST_MODE=true`
- Test charges are visible in the Partner Dashboard with a "TEST" label — flag mismatches are detectable
- At startup, validate: if `NODE_ENV === 'production'` and `BILLING_TEST_MODE === true`, emit a warning log

## Input Validation Rules

| Field | Validation | Error Code |
|-------|-----------|------------|
| `planSlug` (subscribe body) | Required, string, matches `^[a-z0-9\-]+$`, exists in `billing_plans` | `plan_not_found` |
| `charge_id` (callback query) | Required, non-empty string, matches pending `shop_subscriptions` record | `subscription_not_found` |
| `description` (usage body) | Required, non-empty string, max 100 chars | `invalid_usage_params` |
| `amount` (usage body) | Required, number, > 0, max plan cap (if configured) | `invalid_usage_params` |
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
| `GET /api/billing/callback` | charge_id matched to DB record | Shop derived from subscription record |
| `GET /api/billing/status` | Session token (shopId) | Own shop only |
| `POST /api/billing/usage` | Session token (shopId) | Own shop only, active subscription required |
| Protected routes | `requireActivePlan` middleware | Active subscription per shop |

## Tenant Isolation

Every `shop_subscriptions` and `usage_records` query includes `shop_id` in the WHERE clause. Merchants cannot access other shops' subscription data. The `shopId` is always extracted from the verified session token — never from request body or query params.

```typescript
// Correct — shopId from verified session token context
const subscription = await db.query(
  `SELECT * FROM shop_subscriptions WHERE shop_id = $1 AND status = 'active'`,
  [req.context.shopId]  // session token middleware set this
);

// Wrong — shopId from request body (client-controlled)
const subscription = await db.query(
  `SELECT * FROM shop_subscriptions WHERE shop_id = $1`,
  [req.body.shopId]  // NEVER do this
);
```
