Feature: Subscription Lifecycle
  As the app backend
  I want to handle the full subscription state machine
  So that merchant access accurately reflects their billing status

  Background:
    Given the app is configured with BILLING_TEST_MODE=true
    And a shop "shop-001" exists for "test-store.myshopify.com"
    And a "pro" billing plan exists with price 29.00 and 14 trial days

  # ─── CALLBACK / ACTIVATION ───────────────────────────────────────────────

  @happy
  Scenario: Merchant approves charge — subscription activates
    Given shop "shop-001" has a pending subscription with shopify_charge_id "gid://shopify/AppSubscription/456"
    And Shopify reports the subscription status as "ACTIVE" with currentPeriodEnd "2026-06-15T00:00:00Z"
    When Shopify redirects to GET /api/billing/callback?charge_id=gid://shopify/AppSubscription/456
    Then the response is a 302 redirect to BILLING_RETURN_PATH
    And the shop_subscriptions record for charge "gid://shopify/AppSubscription/456" is updated:
      | status       | active                    |
      | activated_at | (current timestamp)       |
      | current_period_end | 2026-06-15T00:00:00Z |
    And a "subscription.activated" event is emitted with shopId "shop-001"

  @happy
  Scenario: Merchant approves charge with trial — trial_ends_at is set
    Given shop "shop-001" has a pending subscription with shopify_charge_id "gid://shopify/AppSubscription/789"
    And Shopify reports the subscription as "ACTIVE" with trialDays=14
    When Shopify redirects to GET /api/billing/callback?charge_id=gid://shopify/AppSubscription/789
    Then the shop_subscriptions record has trial_ends_at set to approximately 14 days from now
    And activated_at is set to now

  @happy
  Scenario: Merchant declines charge — subscription marked declined
    Given shop "shop-001" has a pending subscription with shopify_charge_id "gid://shopify/AppSubscription/456"
    And Shopify reports the subscription status as "DECLINED"
    When Shopify redirects to GET /api/billing/callback?charge_id=gid://shopify/AppSubscription/456
    Then the response is a 302 redirect to "/billing/plans?declined=true"
    And the shop_subscriptions record is updated:
      | status | declined |
    And a "subscription.declined" event is emitted with shopId "shop-001"
    And activated_at remains null

  # ─── CALLBACK ERRORS ─────────────────────────────────────────────────────

  @error
  Scenario: Callback with missing charge_id param
    When Shopify redirects to GET /api/billing/callback (without charge_id)
    Then the response status is 400
    And the response body contains error "missing_charge_id"

  @error
  Scenario: Callback with unknown charge_id — no matching pending subscription
    When Shopify redirects to GET /api/billing/callback?charge_id=gid://shopify/AppSubscription/UNKNOWN
    Then the response status is 404
    And the response body contains error "subscription_not_found"

  @error
  Scenario: Callback for already-activated subscription — cannot re-activate
    Given shop "shop-001" has an active subscription with shopify_charge_id "gid://shopify/AppSubscription/456"
    When Shopify redirects to GET /api/billing/callback?charge_id=gid://shopify/AppSubscription/456
    Then the response status is 404
    And the response body contains error "subscription_not_found"
    And the existing active subscription is unchanged

  @error
  Scenario: Shopify node query returns null — charge no longer exists
    Given shop "shop-001" has a pending subscription with shopify_charge_id "gid://shopify/AppSubscription/456"
    And Shopify returns null for node query with id "gid://shopify/AppSubscription/456"
    When Shopify redirects to GET /api/billing/callback?charge_id=gid://shopify/AppSubscription/456
    Then the response status is 502
    And the response body contains error "shopify_subscription_not_found"

  # ─── CANCELLATION ────────────────────────────────────────────────────────

  @happy
  Scenario: Active subscription is cancelled
    Given shop "shop-001" has an active subscription (id "sub-001")
    When the app calls cancel for subscription "sub-001" on behalf of "shop-001"
    Then the shop_subscriptions record is updated:
      | status       | cancelled           |
      | cancelled_at | (current timestamp) |
    And a "subscription.cancelled" event is emitted

  @happy
  Scenario: Shopify APP_SUBSCRIPTIONS_UPDATE webhook cancels subscription
    Given shop "shop-001" has an active subscription with shopify_charge_id "gid://shopify/AppSubscription/456"
    When Shopify sends a webhook with topic "APP_SUBSCRIPTIONS_UPDATE" and status "CANCELLED"
    Then the shop_subscriptions record status is updated to "cancelled"
    And cancelled_at is set to now

  # ─── FREEZE / UNFREEZE ───────────────────────────────────────────────────

  @happy
  Scenario: Payment failure freezes subscription
    Given shop "shop-001" has an active subscription with shopify_charge_id "gid://shopify/AppSubscription/456"
    When Shopify sends a webhook with topic "APP_SUBSCRIPTIONS_UPDATE" and status "FROZEN"
    Then the shop_subscriptions record status is updated to "frozen"
    And activated_at remains unchanged (freeze does not reset activation)

  @happy
  Scenario: Payment recovered unfreezes subscription
    Given shop "shop-001" has a frozen subscription with shopify_charge_id "gid://shopify/AppSubscription/456"
    When Shopify sends a webhook with topic "APP_SUBSCRIPTIONS_UPDATE" and status "ACTIVE"
    Then the shop_subscriptions record status is updated to "active"
    And a "subscription.activated" event is emitted

  # ─── STATUS ENDPOINT ─────────────────────────────────────────────────────

  @happy
  Scenario: Get billing status — active subscription
    Given shop "shop-001" has an active "pro" subscription with trial ending in 5 days
    When I send GET /api/billing/status with session token for "shop-001"
    Then the response status is 200
    And the response body includes:
      | status              | active     |
      | planSlug            | pro        |
      | trialDaysRemaining  | 5          |
    And the response includes priceAmount, priceCurrency, interval, features, activatedAt, currentPeriodEnd

  @happy
  Scenario: Get billing status — no subscription
    Given shop "shop-001" has no subscription records
    When I send GET /api/billing/status with session token for "shop-001"
    Then the response status is 200
    And the response body is:
      | status       | none |
      | subscription | null |

  @happy
  Scenario: Get billing status — trial ended, subscription still active
    Given shop "shop-001" has an active "pro" subscription with trial_ends_at in the past
    When I send GET /api/billing/status with session token for "shop-001"
    Then trialDaysRemaining is 0 (not negative)

  @edge
  Scenario: Multiple subscriptions — most recent is returned
    Given shop "shop-001" has a declined subscription created 2 days ago
    And shop "shop-001" has an active subscription created 1 day ago
    When I send GET /api/billing/status with session token for "shop-001"
    Then the response returns the active subscription (most recent)

  # ─── TENANT ISOLATION ────────────────────────────────────────────────────

  @edge
  Scenario: Cannot access another shop's subscription via status endpoint
    Given shop "shop-002" has an active subscription
    When I send GET /api/billing/status with session token for "shop-001"
    Then the response reflects shop-001's subscription (none), not shop-002's
