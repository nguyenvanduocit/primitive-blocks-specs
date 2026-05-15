Feature: Usage-Based Billing
  As the app backend
  I want to record metered usage charges against active subscriptions
  So that merchants are billed accurately for what they consume

  Background:
    Given a shop "shop-001" exists for "test-store.myshopify.com"
    And shop "shop-001" has an active subscription (id "sub-001") with shopify_charge_id "gid://shopify/AppSubscription/456"
    And Shopify returns a successful appUsageRecordCreate response with id "gid://shopify/AppUsageRecord/789"

  # ─── HAPPY PATH ──────────────────────────────────────────────────────────

  @happy
  Scenario: Record a usage charge successfully
    When I send POST /api/billing/usage with session token for "shop-001":
      | description    | Processed 50 API calls           |
      | amount         | 0.50                              |
      | idempotencyKey | order-12345-api-calls-2026-05-15  |
    Then the response status is 201
    And the response body includes:
      | usageRecordId | (new uuid)  |
      | idempotent    | false       |
    And a usage_records row is created with:
      | shop_id         | shop-001                         |
      | subscription_id | sub-001                          |
      | description     | Processed 50 API calls           |
      | amount          | 0.50                             |
      | idempotency_key | order-12345-api-calls-2026-05-15 |
      | shopify_usage_id| gid://shopify/AppUsageRecord/789 |
    And a "usage.recorded" event is emitted with amount 0.50

  @happy
  Scenario: Idempotent — duplicate idempotency key returns existing record
    Given a usage_records row already exists with idempotency_key "order-12345-api-calls-2026-05-15"
    When I send POST /api/billing/usage with session token for "shop-001":
      | description    | Processed 50 API calls           |
      | amount         | 0.50                              |
      | idempotencyKey | order-12345-api-calls-2026-05-15  |
    Then the response status is 200
    And the response body includes:
      | idempotent | true |
    And no new usage_records row is created
    And the appUsageRecordCreate Shopify mutation is NOT called again

  @happy
  Scenario: Multiple distinct usage charges — each creates a separate record
    When I send POST /api/billing/usage with session token for "shop-001":
      | description    | Email batch — January week 1  |
      | amount         | 1.20                           |
      | idempotencyKey | email-batch-2026-w01           |
    And I send POST /api/billing/usage with session token for "shop-001":
      | description    | Email batch — January week 2  |
      | amount         | 0.80                           |
      | idempotencyKey | email-batch-2026-w02           |
    Then 2 usage_records rows exist for shop "shop-001" and subscription "sub-001"
    And the Shopify mutation is called twice with different idempotencyKeys

  # ─── VALIDATION ERRORS ───────────────────────────────────────────────────

  @error
  Scenario: Reject usage charge with missing description
    When I send POST /api/billing/usage with session token for "shop-001":
      | amount         | 1.00                  |
      | idempotencyKey | test-key-001          |
    Then the response status is 422
    And the response body contains error "invalid_usage_params"
    And no usage_records row is created

  @error
  Scenario: Reject usage charge with zero amount
    When I send POST /api/billing/usage with session token for "shop-001":
      | description    | Free event — should not bill |
      | amount         | 0                             |
      | idempotencyKey | free-event-001                |
    Then the response status is 422
    And the response body contains error "invalid_usage_params"

  @error
  Scenario: Reject usage charge with negative amount
    When I send POST /api/billing/usage with session token for "shop-001":
      | description    | Refund attempt  |
      | amount         | -5.00            |
      | idempotencyKey | refund-001       |
    Then the response status is 422
    And the response body contains error "invalid_usage_params"

  @error
  Scenario: Reject usage charge with missing idempotency key
    When I send POST /api/billing/usage with session token for "shop-001":
      | description | Charge without idempotency |
      | amount      | 2.00                        |
    Then the response status is 422
    And the response body contains error "invalid_usage_params"

  # ─── SUBSCRIPTION STATE ERRORS ───────────────────────────────────────────

  @error
  Scenario: Reject usage charge when shop has no active subscription
    Given shop "shop-001" has no active subscription (subscription is pending or absent)
    When I send POST /api/billing/usage with session token for "shop-001":
      | description    | API usage                |
      | amount         | 1.00                      |
      | idempotencyKey | api-usage-2026-05-15      |
    Then the response status is 402
    And the response body contains error "no_active_subscription"
    And no usage_records row is created

  @error
  Scenario: Reject usage charge when subscription is frozen
    Given shop "shop-001" has a frozen subscription
    When I send POST /api/billing/usage with session token for "shop-001":
      | description    | API usage                |
      | amount         | 1.00                      |
      | idempotencyKey | api-usage-frozen-001      |
    Then the response status is 402
    And the response body contains error "no_active_subscription"

  @error
  Scenario: Reject usage charge when subscription is cancelled
    Given shop "shop-001" has a cancelled subscription
    When I send POST /api/billing/usage with session token for "shop-001":
      | description    | API usage                  |
      | amount         | 1.00                        |
      | idempotencyKey | api-usage-cancelled-001     |
    Then the response status is 402
    And the response body contains error "no_active_subscription"

  # ─── SHOPIFY API ERRORS ──────────────────────────────────────────────────

  @error
  Scenario: Shopify returns userErrors on usage record create
    Given Shopify returns userErrors for appUsageRecordCreate:
      | field  | message                                  |
      | price  | Price exceeds the usage billing cap      |
    When I send POST /api/billing/usage with session token for "shop-001":
      | description    | Charge exceeding cap      |
      | amount         | 999.99                    |
      | idempotencyKey | over-cap-charge-001       |
    Then the response status is 422
    And the response body contains error "shopify_usage_error"
    And the usage_records row exists (idempotency key is preserved, shopify_usage_id = 'ERROR')
    And a retry with the same idempotencyKey returns idempotent=true without re-calling Shopify

  # ─── AUTH ────────────────────────────────────────────────────────────────

  @error
  Scenario: Reject usage charge without session token
    When I send POST /api/billing/usage without Authorization header:
      | description    | API usage     |
      | amount         | 1.00           |
      | idempotencyKey | no-auth-001    |
    Then the response status is 401
    And the response body contains error "missing_token"

  # ─── EDGE CASES ──────────────────────────────────────────────────────────

  @edge
  Scenario: Concurrent duplicate requests — DB constraint ensures only one is created
    Given two concurrent POST /api/billing/usage requests arrive simultaneously for "shop-001"
    Both with idempotencyKey "concurrent-test-001" and amount 5.00
    Then exactly one usage_records row is created with idempotency_key "concurrent-test-001"
    And one response returns idempotent=false, the other returns idempotent=true (or both return 200)
    And the Shopify mutation is called exactly once

  @edge
  Scenario: Usage charge on trial subscription — allowed
    Given shop "shop-001" has an active subscription in trial period (trial_ends_at in the future)
    When I send POST /api/billing/usage with session token for "shop-001":
      | description    | Trial period usage     |
      | amount         | 0.10                    |
      | idempotencyKey | trial-usage-001         |
    Then the response status is 201
    And the usage record is created (trial does not block usage charges)
