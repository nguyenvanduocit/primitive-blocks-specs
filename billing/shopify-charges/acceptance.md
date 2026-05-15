# Acceptance Checklist — Shopify App Billing & Subscriptions

Claude Code runs this checklist after implementation, before reporting done.

## Database

- [ ] Migration runs successfully (`billing_plans`, `shop_subscriptions`, `usage_records` tables created)
- [ ] `UNIQUE` constraint on `billing_plans.name` is active
- [ ] `UNIQUE` constraint on `billing_plans.slug` is active
- [ ] `UNIQUE` constraint on `usage_records.idempotency_key` is active
- [ ] Index `idx_sub_shop` on `shop_subscriptions(shop_id)` exists
- [ ] Index `idx_sub_status` on `shop_subscriptions(shop_id, status)` exists
- [ ] Index `idx_usage_shop` on `usage_records(shop_id)` exists
- [ ] FK `shop_subscriptions.shop_id` → `shops(id) ON DELETE CASCADE` is active
- [ ] FK `shop_subscriptions.plan_id` → `billing_plans(id)` is active
- [ ] FK `usage_records.subscription_id` → `shop_subscriptions(id)` is active

## Plan Listing

- [ ] GET /api/billing/plans returns only `active=true` plans
- [ ] Plans are ordered by `sort_order` ascending
- [ ] Endpoint works without Authorization header (public)
- [ ] Response includes: id, name, slug, price_amount, price_currency, interval, trial_days, features, sort_order
- [ ] Inactive plans are excluded from the response

## Subscribe Flow

- [ ] POST /api/billing/subscribe requires session token (401 without)
- [ ] Plan is fetched server-side by slug — client-provided price is ignored
- [ ] Inactive or missing plan slug returns 404 `plan_not_found`
- [ ] `appSubscriptionCreate` GraphQL mutation is called with correct name, lineItems, returnUrl, test flag
- [ ] Trial days from `billing_plans.trial_days` override `BILLING_TRIAL_DAYS` config when > 0
- [ ] `test: true` is set when `BILLING_TEST_MODE=true` or `plan.is_test=true`
- [ ] Pending `shop_subscriptions` record is created with `shopify_charge_id` and `confirmation_url`
- [ ] `subscription.created` event is emitted
- [ ] Response returns `confirmationUrl` for frontend to redirect

## Billing Callback

- [ ] GET /api/billing/callback with missing `charge_id` returns 400
- [ ] `charge_id` is matched against a `pending` subscription in `shop_subscriptions` — unknown IDs return 404
- [ ] App queries Shopify `appSubscription(id)` to verify status — callback query param alone is not trusted
- [ ] ACTIVE status: subscription updated to `active`, `activated_at` set, `current_period_end` set
- [ ] ACTIVE with trial: `trial_ends_at` computed and set correctly
- [ ] ACTIVE: `subscription.activated` event emitted, redirect to `BILLING_RETURN_PATH`
- [ ] DECLINED status: subscription updated to `declined`, redirect to plans page with `?declined=true`
- [ ] DECLINED: `subscription.declined` event emitted
- [ ] Already-active subscription with same `charge_id` returns 404 (cannot re-activate)

## Billing Status

- [ ] GET /api/billing/status requires session token (401 without)
- [ ] Returns most recent subscription record for the shop
- [ ] Includes `trialDaysRemaining` computed from `trial_ends_at` (0 if expired, null if no trial)
- [ ] Returns `{ status: "none", subscription: null }` when no subscription exists
- [ ] Response data scoped to requesting shop only (tenant isolation)

## Usage Billing

- [ ] POST /api/billing/usage requires session token (401 without)
- [ ] 402 returned when no active subscription exists for the shop
- [ ] 402 returned when subscription is frozen or cancelled (not just pending/declined)
- [ ] Missing `description` returns 422 `invalid_usage_params`
- [ ] Zero or negative `amount` returns 422 `invalid_usage_params`
- [ ] Missing `idempotencyKey` returns 422 `invalid_usage_params`
- [ ] New usage record: `INSERT ... ON CONFLICT (idempotency_key) DO NOTHING` pattern used
- [ ] Duplicate `idempotencyKey`: returns 200 with `idempotent: true`, Shopify mutation NOT called again
- [ ] Successful new charge: `appUsageRecordCreate` mutation called, `shopify_usage_id` stored
- [ ] `usage.recorded` event emitted on new charge
- [ ] Shopify `userErrors` on usage create: 422 returned, local record preserved (idempotency key retained)

## Plan Gating Middleware

- [ ] `requireActivePlan` middleware returns 402 with `subscription_required` when no active subscription
- [ ] Response includes `plansUrl` pointing to plans endpoint
- [ ] Only `status='active'` grants access — `pending`, `declined`, `cancelled`, `frozen` all return 402
- [ ] `BILLING_REQUIRED=false` bypasses DB query entirely — no subscription check performed
- [ ] Session token middleware runs BEFORE `requireActivePlan` — missing token → 401, not 402
- [ ] Middleware attaches `subscription` + `features` to `req.context` for downstream handlers
- [ ] Middleware is applied at router level, not inline in individual handlers
- [ ] Public endpoints (e.g., GET /api/billing/plans) do NOT have `requireActivePlan` applied

## Subscription State Machine

- [ ] `pending → active` transition works via callback (ACTIVE status from Shopify)
- [ ] `pending → declined` transition works via callback (DECLINED status from Shopify)
- [ ] `active → cancelled` transition works via cancellation webhook or explicit cancel
- [ ] `active → frozen` transition works via APP_SUBSCRIPTIONS_UPDATE webhook (status=FROZEN)
- [ ] `frozen → active` transition works via APP_SUBSCRIPTIONS_UPDATE webhook (status=ACTIVE)
- [ ] Invalid transitions (e.g., `declined → active`) are not possible via normal flows

## Security

- [ ] Plan price NEVER sourced from client request — always from `billing_plans` table
- [ ] Charge status verified with Shopify API on callback — charge_id alone is not trusted
- [ ] `usage_records.idempotency_key` UNIQUE constraint prevents duplicate charges at DB level
- [ ] All subscription/usage queries filter by `shop_id` from verified session token
- [ ] `shopId` is never accepted from request body or query params — only from session token context
- [ ] `BILLING_TEST_MODE=true` in production logs a startup warning

## Frontend

- [ ] Plan selection page fetches GET /api/billing/plans on mount
- [ ] Subscribe button calls POST /api/billing/subscribe and redirects using `window.top.location.href`
- [ ] `window.top.location.href` used (not `window.location.href`) for iframe break-out
- [ ] Billing status banner renders correct state: trial countdown, frozen notice, subscription required
- [ ] Trial days remaining computed client-side from API response (not hardcoded)
- [ ] Plan cards disabled during subscription submission (prevent double-submit)
- [ ] Upgrade/downgrade uses same subscribe flow — Shopify cancels old subscription automatically
- [ ] Cancel button shows confirmation dialog before proceeding

## Configuration

- [ ] `BILLING_REQUIRED` defaults to `true` — opt-out requires explicit `false`
- [ ] `BILLING_TRIAL_DAYS` defaults to `7` and is overridden by per-plan `trial_days` when > 0
- [ ] `BILLING_TEST_MODE` defaults to `false`
- [ ] `BILLING_RETURN_PATH` defaults to `"/"`
- [ ] All config keys validated at startup — missing required values fail fast

## Type Safety & Build

- [ ] `tsc --noEmit` passes (or equivalent type check)
- [ ] No `any` types without justification
- [ ] Zod (or equivalent) validation on all API request bodies (subscribe, usage)
- [ ] GraphQL response shapes typed — not treated as `any`
