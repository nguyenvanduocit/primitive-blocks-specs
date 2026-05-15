# Backend Patterns — Shopify App Billing & Subscriptions

## API Endpoints

### Billing Flow

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `GET` | `/api/billing/plans` | List available plans | None (public) |
| `POST` | `/api/billing/subscribe` | Create subscription charge | Session token |
| `GET` | `/api/billing/callback` | Handle charge approval/decline redirect | HMAC (Shopify redirect) |
| `GET` | `/api/billing/status` | Current shop's subscription status | Session token |
| `POST` | `/api/billing/usage` | Record a usage charge | Session token |

### Middleware

| Function | Purpose |
|----------|---------|
| `requireActivePlan(req, res, next)` | Gate route behind active subscription — 402 if none |
| `attachSubscription(req, res, next)` | Attach subscription + plan features to request context (no gate) |

---

## List Plans Handler

<!-- PATTERN: billing-list-plans -->
<!-- PURPOSE: Return active billing plans for display in plan selection UI — public endpoint -->
<!-- ADAPT: Filter by test mode, add plan feature formatting -->

```typescript
// GET /api/billing/plans
// Public — no auth required (merchants need to see plans before installing)

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

<!-- PATTERN: billing-subscribe -->
<!-- PURPOSE: Create Shopify recurring charge via GraphQL, return confirmationUrl for merchant redirect -->
<!-- ADAPT: GraphQL client, trial days logic, test mode flag -->

```typescript
// POST /api/billing/subscribe
// Body: { planSlug: "pro" }
// Auth: session token (shopId in req.context)

async function handleSubscribe(req: Request): Promise<Response> {
  const { planSlug } = req.body;
  const { shopId, shopDomain } = req.context; // from session token middleware

  // 1. Look up plan server-side — never trust client-provided price
  const plan = await db.query(
    `SELECT * FROM billing_plans WHERE slug = $1 AND active = true`,
    [planSlug]
  );
  if (!plan) {
    return error(404, "plan_not_found");
  }

  // 2. Determine trial days (plan-level overrides global config)
  const trialDays = plan.trial_days > 0 ? plan.trial_days : config.BILLING_TRIAL_DAYS;

  // 3. Build GraphQL mutation
  const mutation = `
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
        appSubscription {
          id
          status
        }
        confirmationUrl
        userErrors {
          field
          message
        }
      }
    }
  `;

  const variables = {
    name: plan.name,
    lineItems: [{
      plan: {
        appRecurringPricingDetails: {
          price: { amount: plan.price_amount.toString(), currencyCode: plan.price_currency },
          interval: plan.interval,
        },
      },
    }],
    returnUrl: `${config.APP_URL}/api/billing/callback`,
    test: config.BILLING_TEST_MODE || plan.is_test,
    trialDays: trialDays > 0 ? trialDays : undefined,
  };

  const accessToken = await getShopToken(shopId);
  const result = await shopifyGraphQL(shopDomain, accessToken, mutation, variables);

  const { appSubscription, confirmationUrl, userErrors } = result.data.appSubscriptionCreate;

  if (userErrors.length > 0) {
    return error(422, "shopify_billing_error", { errors: userErrors });
  }

  // 4. Store pending subscription record
  const subscription = await db.query(`
    INSERT INTO shop_subscriptions (shop_id, plan_id, shopify_charge_id, status, confirmation_url)
    VALUES ($1, $2, $3, 'pending', $4)
    RETURNING *
  `, [shopId, plan.id, appSubscription.id, confirmationUrl]);

  emit("subscription.created", {
    shopId,
    subscriptionId: subscription.id,
    planSlug: plan.slug,
    confirmationUrl,
  });

  return json(200, { confirmationUrl });
}
```

---

## Billing Callback Handler

<!-- PATTERN: billing-callback -->
<!-- PURPOSE: After merchant approves/declines on Shopify, verify status and activate subscription -->
<!-- ADAPT: Query for verifying appSubscription status, redirect path -->

```typescript
// GET /api/billing/callback?charge_id=gid://shopify/AppSubscription/456
// No session token — this is a browser redirect from Shopify
// NOTE: Shopify does NOT sign this redirect — validate charge_id against pending DB records

async function handleBillingCallback(req: Request): Promise<Response> {
  const { charge_id } = req.query;

  if (!charge_id) {
    return error(400, "missing_charge_id");
  }

  // 1. Find pending subscription matching this charge_id
  const subscription = await db.query(`
    SELECT ss.*, bp.slug AS plan_slug, s.shop_domain, s.id AS shop_id_val
    FROM shop_subscriptions ss
    JOIN billing_plans bp ON bp.id = ss.plan_id
    JOIN shops s ON s.id = ss.shop_id
    WHERE ss.shopify_charge_id = $1 AND ss.status = 'pending'
  `, [charge_id]);

  if (!subscription) {
    return error(404, "subscription_not_found");
  }

  // 2. Verify actual status with Shopify (don't trust query param alone)
  const query = `
    query getSubscription($id: ID!) {
      node(id: $id) {
        ... on AppSubscription {
          id
          status
          currentPeriodEnd
          trialDays
        }
      }
    }
  `;

  const accessToken = await getShopToken(subscription.shop_id);
  const result = await shopifyGraphQL(subscription.shop_domain, accessToken, query, { id: charge_id });
  const shopifySubscription = result.data.node;

  if (!shopifySubscription) {
    return error(502, "shopify_subscription_not_found");
  }

  if (shopifySubscription.status === "ACTIVE") {
    // 3a. Activate subscription
    const trialEndsAt = shopifySubscription.trialDays > 0
      ? new Date(Date.now() + shopifySubscription.trialDays * 86400 * 1000)
      : null;

    await db.query(`
      UPDATE shop_subscriptions SET
        status = 'active',
        activated_at = now(),
        trial_ends_at = $2,
        current_period_end = $3,
        updated_at = now()
      WHERE id = $1
    `, [subscription.id, trialEndsAt, shopifySubscription.currentPeriodEnd]);

    emit("subscription.activated", {
      shopId: subscription.shop_id,
      subscriptionId: subscription.id,
      planSlug: subscription.plan_slug,
      activatedAt: new Date(),
    });

    return redirect(302, config.BILLING_RETURN_PATH);
  }

  if (shopifySubscription.status === "DECLINED") {
    // 3b. Mark as declined
    await db.query(`
      UPDATE shop_subscriptions SET status = 'declined', updated_at = now() WHERE id = $1
    `, [subscription.id]);

    emit("subscription.declined", {
      shopId: subscription.shop_id,
      subscriptionId: subscription.id,
      planSlug: subscription.plan_slug,
    });

    return redirect(302, `/billing/plans?declined=true`);
  }

  // Unexpected status
  return error(502, "unexpected_subscription_status", { status: shopifySubscription.status });
}
```

---

## Billing Status Handler

<!-- PATTERN: billing-status -->
<!-- PURPOSE: Return current subscription and plan details for the billing status UI -->
<!-- ADAPT: Add plan feature details, trial countdown computation -->

```typescript
// GET /api/billing/status
// Auth: session token

async function handleBillingStatus(req: Request): Promise<Response> {
  const { shopId } = req.context;

  const subscription = await db.query(`
    SELECT ss.*, bp.name AS plan_name, bp.slug AS plan_slug,
           bp.price_amount, bp.price_currency, bp.interval, bp.features
    FROM shop_subscriptions ss
    JOIN billing_plans bp ON bp.id = ss.plan_id
    WHERE ss.shop_id = $1
    ORDER BY ss.created_at DESC
    LIMIT 1
  `, [shopId]);

  if (!subscription) {
    return json(200, { status: "none", subscription: null });
  }

  const trialDaysRemaining = subscription.trial_ends_at
    ? Math.max(0, Math.ceil((new Date(subscription.trial_ends_at).getTime() - Date.now()) / 86400000))
    : null;

  return json(200, {
    status: subscription.status,
    subscription: {
      id: subscription.id,
      planName: subscription.plan_name,
      planSlug: subscription.plan_slug,
      priceAmount: subscription.price_amount,
      priceCurrency: subscription.price_currency,
      interval: subscription.interval,
      features: subscription.features,
      activatedAt: subscription.activated_at,
      trialEndsAt: subscription.trial_ends_at,
      trialDaysRemaining,
      currentPeriodEnd: subscription.current_period_end,
    },
  });
}
```

---

## Usage Charge Handler

<!-- PATTERN: billing-usage -->
<!-- PURPOSE: Record metered usage charge against active subscription, idempotent by caller-provided key -->
<!-- ADAPT: Validate usage cap if plan has one, currency/amount limits -->

```typescript
// POST /api/billing/usage
// Body: { description: string, amount: number, idempotencyKey: string }
// Auth: session token

async function handleRecordUsage(req: Request): Promise<Response> {
  const { description, amount, idempotencyKey } = req.body;
  const { shopId } = req.context;

  if (!description || amount <= 0 || !idempotencyKey) {
    return error(422, "invalid_usage_params");
  }

  // 1. Find active subscription
  const subscription = await db.query(`
    SELECT ss.*, s.shop_domain
    FROM shop_subscriptions ss
    JOIN shops s ON s.id = ss.shop_id
    WHERE ss.shop_id = $1 AND ss.status = 'active'
    ORDER BY ss.activated_at DESC
    LIMIT 1
  `, [shopId]);

  if (!subscription) {
    return error(402, "no_active_subscription");
  }

  // 2. Insert usage record — idempotency_key UNIQUE prevents duplicates
  const insertResult = await db.query(`
    INSERT INTO usage_records (shop_id, subscription_id, description, amount, idempotency_key)
    VALUES ($1, $2, $3, $4, $5)
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING id
  `, [shopId, subscription.id, description, amount, idempotencyKey]);

  // If conflict (duplicate), return idempotent success
  if (!insertResult) {
    const existing = await db.query(
      `SELECT id, shopify_usage_id FROM usage_records WHERE idempotency_key = $1`,
      [idempotencyKey]
    );
    return json(200, { usageRecordId: existing.id, idempotent: true });
  }

  const usageRecordId = insertResult.id;

  // 3. Create usage record in Shopify
  const mutation = `
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
        appUsageRecord {
          id
        }
        userErrors {
          field
          message
        }
      }
    }
  `;

  const accessToken = await getShopToken(shopId);
  const result = await shopifyGraphQL(subscription.shop_domain, accessToken, mutation, {
    subscriptionLineItemId: subscription.shopify_charge_id,
    description,
    price: { amount: amount.toString(), currencyCode: "USD" },
    idempotencyKey,
  });

  const { appUsageRecord, userErrors } = result.data.appUsageRecordCreate;

  if (userErrors.length > 0) {
    // Mark local record as failed — don't delete (preserve idempotency key)
    await db.query(
      `UPDATE usage_records SET shopify_usage_id = 'ERROR' WHERE id = $1`,
      [usageRecordId]
    );
    return error(422, "shopify_usage_error", { errors: userErrors });
  }

  // 4. Store Shopify's GID
  await db.query(
    `UPDATE usage_records SET shopify_usage_id = $2 WHERE id = $1`,
    [usageRecordId, appUsageRecord.id]
  );

  emit("usage.recorded", { shopId, subscriptionId: subscription.id, amount, description, idempotencyKey });

  return json(201, { usageRecordId, idempotent: false });
}
```

---

## requireActivePlan Middleware

<!-- PATTERN: require-active-plan -->
<!-- PURPOSE: Gate any route behind an active subscription — 402 with plans URL if no active sub -->
<!-- ADAPT: Plan feature checking for tiered access, trial period grace -->

```typescript
async function requireActivePlan(req: Request, res: Response, next: NextFunction): Promise<void> {
  // Skip gating if billing is not required (free tier or disabled)
  if (!config.BILLING_REQUIRED) {
    return next();
  }

  const { shopId } = req.context; // set by authenticateShopifyRequest middleware

  const subscription = await db.query(`
    SELECT ss.*, bp.features, bp.slug AS plan_slug
    FROM shop_subscriptions ss
    JOIN billing_plans bp ON bp.id = ss.plan_id
    WHERE ss.shop_id = $1 AND ss.status = 'active'
    ORDER BY ss.activated_at DESC
    LIMIT 1
  `, [shopId]);

  if (!subscription) {
    res.status(402).json({
      error: "subscription_required",
      message: "An active subscription is required to access this resource",
      plansUrl: `${config.APP_URL}/api/billing/plans`,
    });
    return;
  }

  // Attach subscription context for feature-gating downstream
  req.context.subscription = {
    id: subscription.id,
    planSlug: subscription.plan_slug,
    features: subscription.features,
    trialEndsAt: subscription.trial_ends_at,
    currentPeriodEnd: subscription.current_period_end,
  };

  next();
}

// Usage: apply to all protected routes
// router.use('/api/dashboard', authenticateShopifyRequest, requireActivePlan);
// router.use('/api/products', authenticateShopifyRequest, requireActivePlan);
```

---

## Shopify GraphQL — Key Mutations

### appSubscriptionCreate

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
    appSubscription {
      id
      status
    }
    confirmationUrl
    userErrors {
      field
      message
    }
  }
}
```

### appUsageRecordCreate

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
    appUsageRecord {
      id
    }
    userErrors {
      field
      message
    }
  }
}
```

### appSubscription (verify status on callback)

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
| `plan_not_found` | 404 | planSlug not found or plan inactive |
| `shopify_billing_error` | 422 | Shopify returned userErrors on subscription create |
| `missing_charge_id` | 400 | Callback missing charge_id query param |
| `subscription_not_found` | 404 | No pending subscription matches charge_id |
| `shopify_subscription_not_found` | 502 | Shopify node query returned null |
| `unexpected_subscription_status` | 502 | Shopify returned status other than ACTIVE/DECLINED |
| `no_active_subscription` | 402 | Usage charge attempted with no active subscription |
| `invalid_usage_params` | 422 | Missing description, zero/negative amount, or no idempotency key |
| `shopify_usage_error` | 422 | Shopify returned userErrors on usage record create |
| `subscription_required` | 402 | requireActivePlan middleware — no active plan |

## Anti-patterns

**DON'T** look up plan price from the client request body. Always fetch plan details server-side by slug. Client-provided prices are ignored — price manipulation must be impossible.

**DON'T** trust the charge_id callback redirect as proof of approval. Always query Shopify's `appSubscription` node to verify `status === "ACTIVE"` before activating the local record.

**DON'T** record usage charges without an idempotency key. Retries (network failures, timeouts) will create duplicate charges without the `UNIQUE` constraint on `idempotency_key`.

**DON'T** allow access to protected routes based solely on a `pending` subscription status. Only `active` status grants access — `pending` means the merchant hasn't approved yet.

**DON'T** set `test: false` in production if the plan's `is_test` flag is true. Test charges only appear to real merchants in non-production stores and should not be used in live environments.

**DON'T** block the callback redirect waiting for async operations. If emitting events or syncing features takes time, do it in the background — the merchant is waiting for the redirect.
