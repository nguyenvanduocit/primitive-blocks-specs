# Backend Patterns — Shopify App Billing & Subscriptions

> Code snippets below are L3 illustrative — concrete TypeScript for one stack. Every snippet carries 4 markers (`PATTERN`, `PURPOSE`, `REFERENCE`, `ADAPT`) per `docs/SPEC_GUIDELINES.md` mục 6. The behavioral spec (WHAT) lives in the prose around each snippet; the code is reference only.
>
> **External contracts kept concrete** in this file: Shopify GraphQL mutation names (`appSubscriptionCreate`, `appUsageRecordCreate`), query field names (`appSubscription`, `node(id:)`, `confirmationUrl`, `lineItems`, `appRecurringPricingDetails`, `subscriptionLineItemId`, `currentPeriodEnd`, `trialDays`, `userErrors`), status enum values (`ACTIVE`, `DECLINED`, `CANCELLED`, `FROZEN`, `PENDING`), webhook topic `APP_SUBSCRIPTIONS_UPDATE`, callback param name `charge_id`, and GID format `gid://shopify/AppSubscription/{numeric}`. These are dictated by Shopify and merchant projects do **not** get to choose.

## API Endpoints

### Billing Flow

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `GET` | `/api/billing/plans` | List available plans | None (public) |
| `POST` | `/api/billing/subscribe` | Create subscription charge | Session token |
| `GET` | `/api/billing/callback` | Handle charge approval/decline redirect | `charge_id` matched against pending DB record |
| `GET` | `/api/billing/status` | Current shop's subscription status | Session token |
| `POST` | `/api/billing/usage` | Record a usage charge | Session token |

### Middleware

| Function | Purpose |
|----------|---------|
| `requireActivePlan(req, res, next)` | Gate route behind active subscription — 402 if none |
| `attachSubscription(req, res, next)` | Attach subscription + plan features to request context (no gate) |

---

## List Plans Handler

Returns plans with `active=true`, ordered by `sort_order` ascending. Public — no auth (merchants must see plans before installing).

<!-- PATTERN: billing-list-plans -->
<!-- PURPOSE: Return active billing plans for plan selection UI — public endpoint, no auth -->
<!-- REFERENCE: runtime=node20+ framework=generic dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - `req`/`json(...)`: framework-specific (Express `res.json`, Hono `c.json`, Fastify `reply.send`)
       - `db.query(SQL)`: ORM-specific — Drizzle `db.select().from(billingPlans).where(eq(billingPlans.active, true)).orderBy(billingPlans.sortOrder)`; Prisma `prisma.billingPlan.findMany({ where: { active: true }, orderBy: { sortOrder: "asc" } })`
       - SQL `ORDER BY ... ASC`: identical across postgres/mysql/sqlite -->

```typescript
// GET /api/billing/plans

async function handleListPlans(req: Request): Promise<Response> {
  const plans = await db.query(`
    SELECT id, name, slug, price_amount, price_currency, interval,
           trial_days, features, sort_order
    FROM billing_plans
    WHERE active = true
    ORDER BY sort_order ASC
  `);

  return json(200, { plans });
}
```

---

## Subscribe Handler

Subscribe flow chia 3 pattern độc lập, compose theo thứ tự: **lookup plan → submit Shopify mutation → persist pending record**. Mỗi pattern là 1 trách nhiệm rõ, dễ test riêng.

Behavioral contract (must hold across stacks):
1. Plan price NEVER read from request body — only fetched server-side by `planSlug`
2. `trial_days` from plan record overrides `BILLING_TRIAL_DAYS` config when `> 0`
3. Shopify GraphQL `userErrors` array (non-empty) → HTTP 422, no DB row inserted
4. On success: DB row with `status='pending'` inserted, `subscription.created` event emitted, `confirmationUrl` returned

### Pattern 1: Lookup plan by slug + resolve trial

<!-- PATTERN: billing-plan-lookup -->
<!-- PURPOSE: Server-side plan lookup by slug — never trust client-provided price; resolve trial duration -->
<!-- REFERENCE: runtime=node20+ dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - `db.query(SQL, params)`: Drizzle `db.select().from(billingPlans).where(and(eq(billingPlans.slug, slug), eq(billingPlans.active, true)))`; Prisma `prisma.billingPlan.findFirst({ where: { slug, active: true } })`
       - SQL placeholder `$1`: postgres-style; MySQL uses `?`; SQLite supports both
       - Error helper `HttpError`: project-specific (throw vs Result<T,E>) -->

```typescript
async function lookupPlanBySlug(planSlug: string): Promise<{
  plan: BillingPlan;
  trialDays: number;
}> {
  const plan = await db.query(
    `SELECT * FROM billing_plans WHERE slug = $1 AND active = true`,
    [planSlug]
  );
  if (!plan) throw new HttpError(404, "plan_not_found");

  // Plan-level trial overrides global config when > 0
  const trialDays = plan.trial_days > 0 ? plan.trial_days : config.BILLING_TRIAL_DAYS;
  return { plan, trialDays };
}
```

### Pattern 2: Submit `appSubscriptionCreate` mutation

External contract: mutation name `appSubscriptionCreate`, input fields `name`, `lineItems`, `returnUrl`, `test`, `trialDays`, response fields `appSubscription.id`, `appSubscription.status`, `confirmationUrl`, `userErrors[]` — all dictated by Shopify, KHÔNG đổi.

<!-- PATTERN: shopify-app-subscription-create -->
<!-- PURPOSE: Submit Shopify appSubscriptionCreate mutation with plan pricing; surface userErrors as 422 -->
<!-- REFERENCE: runtime=node20+ http=fetch-builtin -->
<!-- ADAPT:
       - `shopifyGraphQL(...)`: GraphQL client utility from auth.shopify-oauth block; swap with merchant's client (graphql-request, urql, raw fetch with `Content-Type: application/json` + `X-Shopify-Access-Token` header)
       - `price_amount.toString()`: external contract — Shopify `MoneyInput.amount` is a String; do NOT serialize as number
       - `appRecurringPricingDetails`/`interval`: external Shopify field names, KHÔNG đổi -->

```typescript
async function submitSubscriptionCreate(
  shopDomain: string, accessToken: string, plan: BillingPlan, trialDays: number
): Promise<{ chargeId: string; confirmationUrl: string }> {
  const mutation = APP_SUBSCRIPTION_CREATE_MUTATION; // see GraphQL section below
  const variables = {
    name: plan.name,
    lineItems: [{ plan: { appRecurringPricingDetails: {
      price: { amount: plan.price_amount.toString(), currencyCode: plan.price_currency },
      interval: plan.interval,
    } } }],
    returnUrl: `${config.APP_URL}/api/billing/callback`,
    test: config.BILLING_TEST_MODE || plan.is_test,
    trialDays: trialDays > 0 ? trialDays : undefined,
  };
  const result = await shopifyGraphQL(shopDomain, accessToken, mutation, variables);
  const { appSubscription, confirmationUrl, userErrors } = result.data.appSubscriptionCreate;
  if (userErrors.length > 0) throw new HttpError(422, "shopify_billing_error", { errors: userErrors });
  return { chargeId: appSubscription.id, confirmationUrl };
}
```

### Pattern 3: Persist pending subscription + emit event

<!-- PATTERN: billing-persist-pending -->
<!-- PURPOSE: Insert pending shop_subscriptions row, emit subscription.created event, return confirmationUrl -->
<!-- REFERENCE: runtime=node20+ dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - `db.query(INSERT ... RETURNING)`: postgres-specific; MySQL → `INSERT` then `SELECT LAST_INSERT_ID()` or pre-generate UUID app-side; SQLite supports `RETURNING` in 3.35+
       - `emit(eventName, payload)`: event bus project-specific (in-process EventEmitter, Redis pubsub, BullMQ, Inngest, etc.)
       - Status literal `'pending'`: local enum mirror of Shopify `PENDING` — keep lowercase in DB -->

```typescript
async function persistPendingSubscription(
  shopId: string, planId: string, chargeId: string, confirmationUrl: string, planSlug: string
): Promise<{ subscriptionId: string; confirmationUrl: string }> {
  const subscription = await db.query(`
    INSERT INTO shop_subscriptions (shop_id, plan_id, shopify_charge_id, status, confirmation_url)
    VALUES ($1, $2, $3, 'pending', $4) RETURNING *
  `, [shopId, planId, chargeId, confirmationUrl]);

  emit("subscription.created", {
    shopId, subscriptionId: subscription.id, planSlug, confirmationUrl,
  });
  return { subscriptionId: subscription.id, confirmationUrl };
}
```

### Composition (the actual handler)

<!-- PATTERN: billing-subscribe-compose -->
<!-- PURPOSE: Wire lookup → submit → persist into a single route handler -->
<!-- REFERENCE: runtime=node20+ framework=generic -->
<!-- ADAPT:
       - `req.body` / `req.context` / `Response`: framework-specific (Express, Hono `c.req.json()` + `c.get(...)`, Fastify `req.body` + `req.context`)
       - Function names match the 3 patterns above; rename locally if your codebase uses different conventions -->

```typescript
// POST /api/billing/subscribe — Body: { planSlug }, Auth: session token
async function handleSubscribe(req: Request): Promise<Response> {
  const { planSlug } = req.body;
  const { shopId, shopDomain } = req.context;
  const { plan, trialDays } = await lookupPlanBySlug(planSlug);
  const accessToken = await getShopToken(shopId);
  const { chargeId, confirmationUrl } = await submitSubscriptionCreate(
    shopDomain, accessToken, plan, trialDays
  );
  await persistPendingSubscription(shopId, plan.id, chargeId, confirmationUrl, plan.slug);
  return json(200, { confirmationUrl });
}
```

---

## Billing Callback Handler

Callback flow chia 3 pattern: **find pending → verify with Shopify → activate-or-decline**. Shopify does NOT cryptographically sign the callback redirect — the only authenticity check is matching `charge_id` against a `pending` row and re-querying Shopify for the true status.

Behavioral contract:
1. Missing `charge_id` → 400
2. `charge_id` not matching any `pending` row → 404 (already-active charges are also 404 — cannot re-activate)
3. Verify status by calling Shopify `node(id:)` query; trust only this response, never the redirect query string
4. Shopify `ACTIVE` → `status='active'`, set `activated_at`, `current_period_end`, optional `trial_ends_at`, emit `subscription.activated`, 302 → `BILLING_RETURN_PATH`
5. Shopify `DECLINED` → `status='declined'`, emit `subscription.declined`, 302 → `/billing/plans?declined=true`
6. Any other status → 502

### Pattern 1: Find pending subscription by `charge_id`

<!-- PATTERN: billing-find-pending-by-charge -->
<!-- PURPOSE: Match callback charge_id to a single pending shop_subscriptions row; reject unknown or already-active -->
<!-- REFERENCE: runtime=node20+ dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - SQL JOIN: 3-way join with shops + billing_plans — ORM equivalents: Drizzle multi-join via `.leftJoin(...)`, Prisma nested `include: { shop: true, plan: true }`
       - `req.query`: framework-specific (Express `req.query`, Hono `c.req.query()`)
       - `'pending'` literal: local DB enum mirror — case-sensitive match -->

```typescript
async function findPendingByChargeId(chargeId: string): Promise<PendingSubscription> {
  if (!chargeId) throw new HttpError(400, "missing_charge_id");
  const subscription = await db.query(`
    SELECT ss.*, bp.slug AS plan_slug, s.shop_domain
    FROM shop_subscriptions ss
    JOIN billing_plans bp ON bp.id = ss.plan_id
    JOIN shops s ON s.id = ss.shop_id
    WHERE ss.shopify_charge_id = $1 AND ss.status = 'pending'
  `, [chargeId]);
  if (!subscription) throw new HttpError(404, "subscription_not_found");
  return subscription;
}
```

### Pattern 2: Verify subscription status with Shopify

External contract: query the `node(id:)` field with `... on AppSubscription` inline fragment to retrieve `status`, `currentPeriodEnd`, `trialDays`. Status values are UPPERCASE Shopify enums.

<!-- PATTERN: shopify-app-subscription-verify -->
<!-- PURPOSE: Query Shopify for the true subscription status (do not trust callback redirect alone) -->
<!-- REFERENCE: runtime=node20+ http=fetch-builtin -->
<!-- ADAPT:
       - `shopifyGraphQL(...)`: same client utility as subscribe handler
       - GraphQL query string: external contract — `node(id: $id) { ... on AppSubscription { status currentPeriodEnd trialDays } }` is Shopify-dictated
       - Status string compare: UPPERCASE Shopify enum values (`ACTIVE`, `DECLINED`, `CANCELLED`, `FROZEN`) — KHÔNG lowercase -->

```typescript
async function verifyShopifyChargeStatus(
  shopDomain: string, accessToken: string, chargeId: string
): Promise<{ status: string; currentPeriodEnd: string; trialDays: number }> {
  const query = APP_SUBSCRIPTION_VERIFY_QUERY; // see GraphQL section below
  const result = await shopifyGraphQL(shopDomain, accessToken, query, { id: chargeId });
  const node = result.data.node;
  if (!node) throw new HttpError(502, "shopify_subscription_not_found");
  return {
    status: node.status,
    currentPeriodEnd: node.currentPeriodEnd,
    trialDays: node.trialDays,
  };
}
```

### Pattern 3: Activate or decline locally based on Shopify status

<!-- PATTERN: billing-apply-callback-status -->
<!-- PURPOSE: Translate Shopify ACTIVE/DECLINED to local state mutation + event + redirect -->
<!-- REFERENCE: runtime=node20+ dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - `db.query(UPDATE ... WHERE id = $1)`: ORM equivalents — Drizzle `db.update(...).set(...).where(...)`; Prisma `prisma.shopSubscription.update({ where: { id }, data: {...} })`
       - `redirect(302, url)`: framework-specific (Express `res.redirect`, Hono `c.redirect`, Fastify `reply.redirect`)
       - Local status literals (`'active'`/`'declined'`): lowercase mirrors of Shopify UPPERCASE — case translation only -->

```typescript
async function applyCallbackStatus(
  sub: PendingSubscription, shopifyStatus: string, currentPeriodEnd: string, trialDays: number
): Promise<Response> {
  if (shopifyStatus === "ACTIVE") {
    const trialEndsAt = trialDays > 0 ? new Date(Date.now() + trialDays * 86400_000) : null;
    await db.query(`UPDATE shop_subscriptions SET status='active', activated_at=now(),
        trial_ends_at=$2, current_period_end=$3, updated_at=now() WHERE id=$1`,
      [sub.id, trialEndsAt, currentPeriodEnd]);
    emit("subscription.activated", { shopId: sub.shop_id, subscriptionId: sub.id,
      planSlug: sub.plan_slug, activatedAt: new Date() });
    return redirect(302, config.BILLING_RETURN_PATH);
  }
  if (shopifyStatus === "DECLINED") {
    await db.query(`UPDATE shop_subscriptions SET status='declined', updated_at=now() WHERE id=$1`, [sub.id]);
    emit("subscription.declined", { shopId: sub.shop_id, subscriptionId: sub.id, planSlug: sub.plan_slug });
    return redirect(302, `/billing/plans?declined=true`);
  }
  throw new HttpError(502, "unexpected_subscription_status", { status: shopifyStatus });
}
```

### Composition

<!-- PATTERN: billing-callback-compose -->
<!-- PURPOSE: Wire find-pending → verify-with-Shopify → apply-status into a single route handler -->
<!-- REFERENCE: runtime=node20+ framework=generic -->
<!-- ADAPT:
       - `req.query`: framework-specific (Express, Hono `c.req.query()`, Fastify `req.query`)
       - Error propagation: 3 helpers throw `HttpError`; framework error middleware should map to HTTP response -->

```typescript
// GET /api/billing/callback?charge_id=gid://shopify/AppSubscription/456
async function handleBillingCallback(req: Request): Promise<Response> {
  const { charge_id } = req.query;
  const sub = await findPendingByChargeId(charge_id);
  const accessToken = await getShopToken(sub.shop_id);
  const { status, currentPeriodEnd, trialDays } = await verifyShopifyChargeStatus(
    sub.shop_domain, accessToken, charge_id
  );
  return applyCallbackStatus(sub, status, currentPeriodEnd, trialDays);
}
```

---

## Billing Status Handler

Returns the most recent `shop_subscriptions` row for the requesting shop (or `{ status: "none", subscription: null }` if none). `trialDaysRemaining` is computed client-side from `trial_ends_at` (server pre-computes for convenience; floor at 0, never negative).

### Pattern 1: Compute trial days remaining

<!-- PATTERN: trial-days-remaining -->
<!-- PURPOSE: Pure function — convert trial_ends_at timestamp to integer days remaining, floored at 0 -->
<!-- REFERENCE: runtime=node20+ language=typescript -->
<!-- ADAPT:
       - `Date.now()` and `Math.ceil`: standard JS, identical across Node/Bun/Deno
       - `86400000`: ms per day; if using a date library (date-fns, luxon, dayjs) use its diff helper instead
       - Edge case `null` → return `null` (not `0`) to distinguish "no trial" from "trial just ended" -->

```typescript
function computeTrialDaysRemaining(trialEndsAt: Date | string | null): number | null {
  if (!trialEndsAt) return null;
  const endMs = new Date(trialEndsAt).getTime();
  return Math.max(0, Math.ceil((endMs - Date.now()) / 86400000));
}
```

### Pattern 2: Status query + response shape

<!-- PATTERN: billing-status -->
<!-- PURPOSE: Return current subscription joined with plan details for billing status UI -->
<!-- REFERENCE: runtime=node20+ dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - JOIN: ORM-specific (Drizzle `.leftJoin(billingPlans, ...)`; Prisma `include: { plan: true }`)
       - `ORDER BY ss.created_at DESC LIMIT 1`: SQL standard, identical across dialects
       - shopId scoped via `req.context.shopId`: NEVER read from request body or query — see security.md (Tenant Isolation) -->

```typescript
// GET /api/billing/status — Auth: session token
async function handleBillingStatus(req: Request): Promise<Response> {
  const { shopId } = req.context;
  const sub = await db.query(`
    SELECT ss.*, bp.name AS plan_name, bp.slug AS plan_slug,
           bp.price_amount, bp.price_currency, bp.interval, bp.features
    FROM shop_subscriptions ss
    JOIN billing_plans bp ON bp.id = ss.plan_id
    WHERE ss.shop_id = $1 ORDER BY ss.created_at DESC LIMIT 1
  `, [shopId]);
  if (!sub) return json(200, { status: "none", subscription: null });

  return json(200, { status: sub.status, subscription: {
    id: sub.id, planName: sub.plan_name, planSlug: sub.plan_slug,
    priceAmount: sub.price_amount, priceCurrency: sub.price_currency,
    interval: sub.interval, features: sub.features,
    activatedAt: sub.activated_at, trialEndsAt: sub.trial_ends_at,
    trialDaysRemaining: computeTrialDaysRemaining(sub.trial_ends_at),
    currentPeriodEnd: sub.current_period_end,
  } });
}
```

---

## Usage Charge Handler

Records a metered usage charge, idempotent on caller-provided `idempotencyKey`. Flow chia 4 pattern: **validate → find active sub → idempotent insert → submit Shopify mutation → persist Shopify GID**.

Behavioral contract:
1. Missing/invalid `description`, `amount ≤ 0`, or missing `idempotencyKey` → 422 `invalid_usage_params`
2. No active subscription → 402 `no_active_subscription` (frozen/cancelled/declined are also blocked)
3. Duplicate `idempotency_key`: return 200 `{ idempotent: true }`, Shopify mutation NOT re-called
4. Shopify `userErrors`: return 422, keep local row (mark `shopify_usage_id='ERROR'`) so retry with same key short-circuits

### Pattern 1: Validate usage request params

<!-- PATTERN: billing-usage-validate -->
<!-- PURPOSE: Reject malformed usage requests before any DB or Shopify call -->
<!-- REFERENCE: runtime=node20+ language=typescript -->
<!-- ADAPT:
       - Validation library: Zod (`z.object({ description: z.string().min(1).max(100), amount: z.number().positive(), idempotencyKey: z.string().min(1).max(255) })`), Yup, Valibot, or hand-rolled — same shape rules
       - Error helper `HttpError`: project-specific -->

```typescript
function validateUsageParams(body: unknown): {
  description: string; amount: number; idempotencyKey: string;
} {
  const { description, amount, idempotencyKey } = body as any;
  if (!description || typeof description !== "string" || description.length > 100) {
    throw new HttpError(422, "invalid_usage_params");
  }
  if (typeof amount !== "number" || amount <= 0) {
    throw new HttpError(422, "invalid_usage_params");
  }
  if (!idempotencyKey || typeof idempotencyKey !== "string") {
    throw new HttpError(422, "invalid_usage_params");
  }
  return { description, amount, idempotencyKey };
}
```

### Pattern 2: Find active subscription for shop

<!-- PATTERN: billing-find-active-subscription -->
<!-- PURPOSE: Look up the shop's single active subscription; reject if frozen/cancelled/declined/none -->
<!-- REFERENCE: runtime=node20+ dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - SQL JOIN + status filter: ORM-specific (Drizzle `.where(and(eq(ss.shopId, shopId), eq(ss.status, "active")))`; Prisma `where: { shopId, status: "active" }`)
       - `ORDER BY activated_at DESC LIMIT 1`: deterministic when shop has multiple subs (e.g., after upgrade); SQL standard
       - 402 status: HTTP semantic for "payment required" — same across frameworks -->

```typescript
async function findActiveSubscription(shopId: string): Promise<ActiveSubscription> {
  const sub = await db.query(`
    SELECT ss.*, s.shop_domain FROM shop_subscriptions ss
    JOIN shops s ON s.id = ss.shop_id
    WHERE ss.shop_id = $1 AND ss.status = 'active'
    ORDER BY ss.activated_at DESC LIMIT 1
  `, [shopId]);
  if (!sub) throw new HttpError(402, "no_active_subscription");
  return sub;
}
```

### Pattern 3: Idempotent usage record insert

<!-- PATTERN: billing-usage-idempotent-insert -->
<!-- PURPOSE: INSERT ... ON CONFLICT (idempotency_key) DO NOTHING; if duplicate, return existing row -->
<!-- REFERENCE: runtime=node20+ dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - `INSERT ... ON CONFLICT (col) DO NOTHING`: postgres + SQLite 3.24+ syntax; MySQL → `INSERT IGNORE` or `INSERT ... ON DUPLICATE KEY UPDATE id=id`
       - Return shape: `{ id, isNew }` — caller branches on isNew to decide whether to call Shopify
       - Idempotency relies on UNIQUE constraint on `idempotency_key` — without it, this pattern silently allows duplicates -->

```typescript
async function insertUsageRecordIdempotent(
  shopId: string, subscriptionId: string, description: string,
  amount: number, idempotencyKey: string
): Promise<{ id: string; isNew: boolean; shopifyUsageId: string | null }> {
  const inserted = await db.query(`
    INSERT INTO usage_records (shop_id, subscription_id, description, amount, idempotency_key)
    VALUES ($1, $2, $3, $4, $5) ON CONFLICT (idempotency_key) DO NOTHING RETURNING id
  `, [shopId, subscriptionId, description, amount, idempotencyKey]);
  if (inserted) return { id: inserted.id, isNew: true, shopifyUsageId: null };

  const existing = await db.query(
    `SELECT id, shopify_usage_id FROM usage_records WHERE idempotency_key = $1`,
    [idempotencyKey]
  );
  return { id: existing.id, isNew: false, shopifyUsageId: existing.shopify_usage_id };
}
```

### Pattern 4: Submit `appUsageRecordCreate` + persist Shopify GID

External contract: mutation name `appUsageRecordCreate`, inputs `subscriptionLineItemId`, `description`, `price` (MoneyInput), `idempotencyKey` — Shopify-dictated, KHÔNG đổi. Shopify accepts its own `idempotencyKey` (double protection at API layer).

<!-- PATTERN: shopify-app-usage-record-create -->
<!-- PURPOSE: Submit usage record to Shopify; on userErrors mark local row as ERROR to keep idempotency -->
<!-- REFERENCE: runtime=node20+ http=fetch-builtin dialect=postgres -->
<!-- ADAPT:
       - `shopifyGraphQL(...)`: GraphQL client utility from auth.shopify-oauth
       - `currencyCode: "USD"`: TODO — should be plan's currency; pass currency through from active subscription record
       - On error path: DO NOT delete the local row — UNIQUE idempotency_key must be preserved so retries return idempotent=true -->

```typescript
async function submitUsageToShopify(
  shopDomain: string, accessToken: string, lineItemId: string,
  description: string, amount: number, idempotencyKey: string, usageRecordId: string
): Promise<string> {
  const mutation = APP_USAGE_RECORD_CREATE_MUTATION; // see GraphQL section below
  const result = await shopifyGraphQL(shopDomain, accessToken, mutation, {
    subscriptionLineItemId: lineItemId, description,
    price: { amount: amount.toString(), currencyCode: "USD" }, idempotencyKey,
  });
  const { appUsageRecord, userErrors } = result.data.appUsageRecordCreate;
  if (userErrors.length > 0) {
    await db.query(`UPDATE usage_records SET shopify_usage_id = 'ERROR' WHERE id = $1`, [usageRecordId]);
    throw new HttpError(422, "shopify_usage_error", { errors: userErrors });
  }
  await db.query(`UPDATE usage_records SET shopify_usage_id = $2 WHERE id = $1`,
    [usageRecordId, appUsageRecord.id]);
  return appUsageRecord.id;
}
```

### Composition

<!-- PATTERN: billing-usage-compose -->
<!-- PURPOSE: Wire validate → find-active → idempotent-insert → submit-to-shopify into a single route handler -->
<!-- REFERENCE: runtime=node20+ framework=generic -->
<!-- ADAPT:
       - `req.body` / `req.context`: framework-specific
       - Short-circuit on duplicate: returns 200 BEFORE calling Shopify — critical for idempotency, do not invert
       - 201 vs 200: 201 = new resource created in Shopify, 200 = existing record returned -->

```typescript
// POST /api/billing/usage — Body: { description, amount, idempotencyKey }, Auth: session token
async function handleRecordUsage(req: Request): Promise<Response> {
  const { description, amount, idempotencyKey } = validateUsageParams(req.body);
  const { shopId } = req.context;
  const sub = await findActiveSubscription(shopId);
  const inserted = await insertUsageRecordIdempotent(
    shopId, sub.id, description, amount, idempotencyKey
  );
  if (!inserted.isNew) return json(200, { usageRecordId: inserted.id, idempotent: true });
  const accessToken = await getShopToken(shopId);
  await submitUsageToShopify(sub.shop_domain, accessToken, sub.shopify_charge_id,
    description, amount, idempotencyKey, inserted.id);
  emit("usage.recorded", { shopId, subscriptionId: sub.id, amount, description, idempotencyKey });
  return json(201, { usageRecordId: inserted.id, idempotent: false });
}
```

---

## requireActivePlan Middleware

Gates a route behind an active subscription. Order matters: session-token middleware runs FIRST (missing/invalid token → 401), then this middleware (no active sub → 402).

Behavioral contract:
1. `BILLING_REQUIRED=false` → skip DB query, call `next()` immediately
2. Look up most recent `status='active'` subscription for `req.context.shopId`
3. Found → attach `{ id, planSlug, features, trialEndsAt, currentPeriodEnd }` to `req.context.subscription`, call `next()`
4. Not found → respond 402 with `{ error: "subscription_required", plansUrl }`, do NOT call `next()`

<!-- PATTERN: require-active-plan -->
<!-- PURPOSE: Gate downstream handlers behind status='active' subscription; attach plan features to context -->
<!-- REFERENCE: runtime=node20+ framework=generic dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - Middleware signature `(req, res, next)`: Express-style; Hono → `(c, next) => {...}` returning Response or calling next(); Fastify → preHandler hook
       - `res.status(402).json(...)`: framework-specific terminator; Hono `return c.json({...}, 402)`; do NOT call next() on 402
       - DB query: ORM-equivalent to subscribe handler's `findActiveSubscription` — could reuse that helper
       - Wiring example (Express): `router.use('/api/dashboard', authenticateShopifyRequest, requireActivePlan)` — different framework, same intent: chain after session-token middleware -->

```typescript
async function requireActivePlan(req: Request, res: Response, next: NextFunction): Promise<void> {
  if (!config.BILLING_REQUIRED) return next();
  const { shopId } = req.context;
  const sub = await db.query(`
    SELECT ss.*, bp.features, bp.slug AS plan_slug
    FROM shop_subscriptions ss
    JOIN billing_plans bp ON bp.id = ss.plan_id
    WHERE ss.shop_id = $1 AND ss.status = 'active'
    ORDER BY ss.activated_at DESC LIMIT 1
  `, [shopId]);
  if (!sub) {
    res.status(402).json({
      error: "subscription_required",
      message: "An active subscription is required to access this resource",
      plansUrl: `${config.APP_URL}/api/billing/plans`,
    });
    return;
  }
  req.context.subscription = { id: sub.id, planSlug: sub.plan_slug, features: sub.features,
    trialEndsAt: sub.trial_ends_at, currentPeriodEnd: sub.current_period_end };
  next();
}
```

---

## Shopify GraphQL — Key Operations

External contracts — field names, argument names, response shapes are dictated by Shopify Admin GraphQL API. Do NOT modify.

### `appSubscriptionCreate` mutation

<!-- PATTERN: graphql-app-subscription-create -->
<!-- PURPOSE: Canonical Shopify GraphQL mutation string for creating an app subscription charge -->
<!-- REFERENCE: api=shopify-admin-graphql api-version=2024-10+ -->
<!-- ADAPT:
       - api-version: pin to a specific Admin API version in your GraphQL client (URL `/admin/api/2024-10/graphql.json` or later); selecting older versions may reject these field names
       - Field/input names: external contract — KHÔNG đổi (`appSubscription`, `confirmationUrl`, `userErrors`, etc.)
       - Codegen: if using graphql-codegen with introspection, regenerate types whenever you bump api-version -->

```graphql
mutation appSubscriptionCreate(
  $name: String!
  $lineItems: [AppSubscriptionLineItemInput!]!
  $returnUrl: URL!
  $test: Boolean
  $trialDays: Int
) {
  appSubscriptionCreate(
    name: $name
    lineItems: $lineItems
    returnUrl: $returnUrl
    test: $test
    trialDays: $trialDays
  ) {
    appSubscription { id status }
    confirmationUrl
    userErrors { field message }
  }
}
```

### `appUsageRecordCreate` mutation

<!-- PATTERN: graphql-app-usage-record-create -->
<!-- PURPOSE: Canonical Shopify GraphQL mutation string for recording a metered usage charge -->
<!-- REFERENCE: api=shopify-admin-graphql api-version=2024-10+ -->
<!-- ADAPT:
       - `idempotencyKey` argument: Shopify-supported optional argument — pass through from caller so retries are safe at both DB and API layers
       - `MoneyInput`: `{ amount: String, currencyCode: CurrencyCode }` — amount is String (not Float); currencyCode enum (e.g., `USD`, `EUR`)
       - Field names: external contract — KHÔNG đổi -->

```graphql
mutation appUsageRecordCreate(
  $subscriptionLineItemId: ID!
  $description: String!
  $price: MoneyInput!
  $idempotencyKey: String
) {
  appUsageRecordCreate(
    subscriptionLineItemId: $subscriptionLineItemId
    description: $description
    price: $price
    idempotencyKey: $idempotencyKey
  ) {
    appUsageRecord { id }
    userErrors { field message }
  }
}
```

### `appSubscription` verify-status query (via `node(id:)`)

<!-- PATTERN: graphql-app-subscription-verify -->
<!-- PURPOSE: Canonical Shopify GraphQL query to read AppSubscription status during callback verification -->
<!-- REFERENCE: api=shopify-admin-graphql api-version=2024-10+ -->
<!-- ADAPT:
       - `node(id:)` with `... on AppSubscription` fragment: this is THE way to fetch a subscription by GID in Admin API; do not substitute with a non-existent `appSubscription(id:)` root field
       - `lineItems` block: optional — drop if you don't need pricing details on the verify path; keep for audit logging
       - Status enum values returned (`ACTIVE`, `DECLINED`, `CANCELLED`, `FROZEN`, `PENDING`): external contract, compare case-sensitive -->

```graphql
query getSubscription($id: ID!) {
  node(id: $id) {
    ... on AppSubscription {
      id
      status
      currentPeriodEnd
      trialDays
      lineItems {
        id
        plan {
          pricingDetails {
            ... on AppRecurringPricing {
              price { amount currencyCode }
              interval
            }
          }
        }
      }
    }
  }
}
```

---

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `plan_not_found` | 404 | `planSlug` not found or plan inactive |
| `shopify_billing_error` | 422 | Shopify returned `userErrors` on `appSubscriptionCreate` |
| `missing_charge_id` | 400 | Callback missing `charge_id` query param |
| `subscription_not_found` | 404 | No pending subscription matches `charge_id` (or already activated) |
| `shopify_subscription_not_found` | 502 | Shopify `node(id:)` query returned null |
| `unexpected_subscription_status` | 502 | Shopify returned status other than `ACTIVE`/`DECLINED` |
| `no_active_subscription` | 402 | Usage charge attempted with no active subscription |
| `invalid_usage_params` | 422 | Missing description, zero/negative amount, or no idempotency key |
| `shopify_usage_error` | 422 | Shopify returned `userErrors` on `appUsageRecordCreate` |
| `subscription_required` | 402 | `requireActivePlan` middleware — no active plan |

## Anti-patterns

**DON'T** look up plan price from the client request body. Always fetch plan details server-side by slug. Client-provided prices are ignored — price manipulation must be impossible.

**DON'T** trust the `charge_id` callback redirect as proof of approval. Always query Shopify's `appSubscription` node to verify `status === "ACTIVE"` before activating the local record.

**DON'T** record usage charges without an idempotency key. Retries (network failures, timeouts) will create duplicate charges without the `UNIQUE` constraint on `idempotency_key`.

**DON'T** allow access to protected routes based solely on a `pending` subscription status. Only `active` status grants access — `pending` means the merchant hasn't approved yet.

**DON'T** set `test: false` in production if the plan's `is_test` flag is true. Test charges only appear to real merchants in non-production stores and should not be used in live environments.

**DON'T** block the callback redirect waiting for async operations. If emitting events or syncing features takes time, do it in the background — the merchant is waiting for the redirect.
