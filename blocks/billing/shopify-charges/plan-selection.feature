Feature: Plan Selection
  As a Shopify merchant
  I want to view and select a billing plan
  So that I can subscribe to the app and access its features

  Background:
    Given the app is configured with BILLING_TEST_MODE=true
    And the following billing plans exist:
      | slug       | name         | price | interval       | trial_days | active |
      | free       | Free Plan    | 0.00  | EVERY_30_DAYS  | 0          | true   |
      | pro        | Pro Plan     | 29.00 | EVERY_30_DAYS  | 14         | true   |
      | enterprise | Enterprise   | 99.00 | EVERY_30_DAYS  | 0          | true   |
      | legacy     | Legacy Plan  | 19.00 | EVERY_30_DAYS  | 0          | false  |
    And a shop "shop-001" exists for "test-store.myshopify.com" with a valid session token

  @happy
  Scenario: List active plans — public endpoint, no auth required
    When I send GET /api/billing/plans without an Authorization header
    Then the response status is 200
    And the response contains 3 plans (free, pro, enterprise)
    And the "legacy" plan is not included (active=false)
    And each plan includes: id, name, slug, price_amount, price_currency, interval, trial_days, features, sort_order
    And plans are ordered by sort_order ascending

  @happy
  Scenario: Subscribe to Pro plan — happy path
    Given shop "shop-001" has no active subscription
    And Shopify returns a successful appSubscriptionCreate response:
      | confirmationUrl | https://test-store.myshopify.com/admin/charges/456/confirm_recurring_application_charge |
      | chargeId        | gid://shopify/AppSubscription/456                                                        |
    When I send POST /api/billing/subscribe with session token for "shop-001":
      | planSlug | pro |
    Then the response status is 200
    And the response body contains confirmationUrl
    And a shop_subscriptions record is created with:
      | shop_id          | shop-001                                  |
      | plan_id          | (pro plan's uuid)                         |
      | shopify_charge_id| gid://shopify/AppSubscription/456         |
      | status           | pending                                   |
      | confirmation_url | https://test-store.myshopify.com/...      |
    And a "subscription.created" event is emitted

  @happy
  Scenario: Subscribe to Enterprise plan — no trial
    Given shop "shop-001" has no active subscription
    And Shopify returns a successful appSubscriptionCreate response for enterprise
    When I send POST /api/billing/subscribe with session token for "shop-001":
      | planSlug | enterprise |
    Then the response status is 200
    And the appSubscriptionCreate mutation was called WITHOUT trialDays parameter
    And the mutation was called WITH test=true (BILLING_TEST_MODE is true)

  @happy
  Scenario: Subscribe to Pro plan — trial applied
    Given shop "shop-001" has no active subscription
    And BILLING_TRIAL_DAYS is configured as 7
    And Shopify returns a successful appSubscriptionCreate response for pro
    When I send POST /api/billing/subscribe with session token for "shop-001":
      | planSlug | pro |
    Then the appSubscriptionCreate mutation was called WITH trialDays=14
    And the plan's own trial_days (14) takes precedence over BILLING_TRIAL_DAYS (7)

  @happy
  Scenario: Upgrade plan — create new subscription while one is active
    Given shop "shop-001" has an active "free" subscription
    And Shopify returns a successful appSubscriptionCreate response for pro
    When I send POST /api/billing/subscribe with session token for "shop-001":
      | planSlug | pro |
    Then the response status is 200
    And a new pending shop_subscriptions record is created for "pro"
    And the existing "free" subscription record is NOT cancelled in the database
    And Shopify handles the old subscription cancellation automatically on approval

  @error
  Scenario: Subscribe with invalid plan slug
    When I send POST /api/billing/subscribe with session token for "shop-001":
      | planSlug | nonexistent-plan |
    Then the response status is 404
    And the response body contains error "plan_not_found"
    And no shop_subscriptions record is created
    And no Shopify GraphQL mutation is called

  @error
  Scenario: Subscribe with inactive plan
    When I send POST /api/billing/subscribe with session token for "shop-001":
      | planSlug | legacy |
    Then the response status is 404
    And the response body contains error "plan_not_found"

  @error
  Scenario: Shopify returns userErrors on subscription create
    Given shop "shop-001" has no active subscription
    And Shopify returns a userErrors response for appSubscriptionCreate:
      | field   | message                     |
      | lineItems | Price must be greater than 0 |
    When I send POST /api/billing/subscribe with session token for "shop-001":
      | planSlug | free |
    Then the response status is 422
    And the response body contains error "shopify_billing_error"
    And no shop_subscriptions record is created

  @error
  Scenario: Subscribe without session token
    When I send POST /api/billing/subscribe without Authorization header:
      | planSlug | pro |
    Then the response status is 401
    And the response body contains error "missing_token"

  @edge
  Scenario: Price is always fetched server-side — client cannot influence it
    Given Shopify returns a successful appSubscriptionCreate response for pro
    When I send POST /api/billing/subscribe with session token for "shop-001":
      | planSlug      | pro   |
      | price_amount  | 0.01  |
      | is_test       | false |
    Then the appSubscriptionCreate mutation uses price_amount from the database (29.00)
    And the client-provided price_amount (0.01) is ignored
