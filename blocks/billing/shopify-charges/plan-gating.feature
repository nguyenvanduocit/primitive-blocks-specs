Feature: Plan Gating Middleware
  As the app backend
  I want to gate protected routes behind an active subscription
  So that merchants without a valid plan cannot access paid features

  Background:
    Given the app has a protected endpoint GET /api/dashboard that uses requireActivePlan middleware
    And the app has a public endpoint GET /api/billing/plans that does NOT use requireActivePlan

  # ─── BILLING_REQUIRED=true (default) ─────────────────────────────────────

  @happy
  Scenario: Active subscription grants access
    Given BILLING_REQUIRED is true
    And shop "shop-001" has an active "pro" subscription
    When I send GET /api/dashboard with session token for "shop-001"
    Then the response status is 200
    And req.context.subscription is populated with:
      | planSlug | pro        |
      | features | (pro features array) |

  @happy
  Scenario: Active trial subscription grants access
    Given BILLING_REQUIRED is true
    And shop "shop-001" has an active "pro" subscription in trial (trial_ends_at in future)
    When I send GET /api/dashboard with session token for "shop-001"
    Then the response status is 200
    And req.context.subscription.trialEndsAt is set

  @happy
  Scenario: Public endpoint bypasses plan gating — no subscription needed
    Given BILLING_REQUIRED is true
    And shop "shop-001" has no subscription
    When I send GET /api/billing/plans without Authorization header
    Then the response status is 200
    And the plans list is returned

  # ─── BLOCKED STATES ──────────────────────────────────────────────────────

  @error
  Scenario: No subscription blocks access when BILLING_REQUIRED=true
    Given BILLING_REQUIRED is true
    And shop "shop-001" has no subscription records
    When I send GET /api/dashboard with session token for "shop-001"
    Then the response status is 402
    And the response body contains error "subscription_required"
    And the response body includes plansUrl pointing to "/api/billing/plans"

  @error
  Scenario: Pending subscription blocks access — merchant has not approved yet
    Given BILLING_REQUIRED is true
    And shop "shop-001" has a pending subscription (not yet approved)
    When I send GET /api/dashboard with session token for "shop-001"
    Then the response status is 402
    And the response body contains error "subscription_required"

  @error
  Scenario: Declined subscription blocks access
    Given BILLING_REQUIRED is true
    And shop "shop-001" has a declined subscription
    When I send GET /api/dashboard with session token for "shop-001"
    Then the response status is 402
    And the response body contains error "subscription_required"

  @error
  Scenario: Cancelled subscription blocks access
    Given BILLING_REQUIRED is true
    And shop "shop-001" has a cancelled subscription
    When I send GET /api/dashboard with session token for "shop-001"
    Then the response status is 402
    And the response body contains error "subscription_required"

  @error
  Scenario: Frozen subscription blocks access
    Given BILLING_REQUIRED is true
    And shop "shop-001" has a frozen subscription
    When I send GET /api/dashboard with session token for "shop-001"
    Then the response status is 402
    And the response body contains error "subscription_required"

  # ─── BILLING_REQUIRED=false ───────────────────────────────────────────────

  @happy
  Scenario: BILLING_REQUIRED=false bypasses gating entirely
    Given BILLING_REQUIRED is false
    And shop "shop-001" has no subscription records
    When I send GET /api/dashboard with session token for "shop-001"
    Then the response status is 200
    And the handler processes normally without subscription check

  @happy
  Scenario: BILLING_REQUIRED=false — middleware skips DB query
    Given BILLING_REQUIRED is false
    When I send GET /api/dashboard with session token for "shop-001"
    Then no query is made to the shop_subscriptions table
    And req.context.subscription is undefined (not populated)

  # ─── SESSION TOKEN REQUIRED BEFORE PLAN GATE ─────────────────────────────

  @error
  Scenario: Missing session token — 401 before plan gate check
    Given BILLING_REQUIRED is true
    When I send GET /api/dashboard without Authorization header
    Then the response status is 401
    And the response body contains error "missing_token"
    And no query is made to the shop_subscriptions table

  @error
  Scenario: Invalid session token — 401 before plan gate check
    Given BILLING_REQUIRED is true
    When I send GET /api/dashboard with an expired session token
    Then the response status is 401
    And the response body contains error "expired_token"

  # ─── MIDDLEWARE ORDERING ──────────────────────────────────────────────────

  @edge
  Scenario: Middleware order — session token runs before requireActivePlan
    Given BILLING_REQUIRED is true
    When I send GET /api/dashboard without any Authorization header
    Then the response status is 401 (session token failure, not 402)
    And the error is "missing_token" not "subscription_required"

  @edge
  Scenario: Multiple shops — each has independent gating
    Given BILLING_REQUIRED is true
    And shop "shop-001" has an active subscription
    And shop "shop-002" has no subscription
    When I send GET /api/dashboard with session token for "shop-001"
    Then the response status is 200
    When I send GET /api/dashboard with session token for "shop-002"
    Then the response status is 402

  # ─── PLAN FEATURE CONTEXT ─────────────────────────────────────────────────

  @happy
  Scenario: Plan features are attached to request context for downstream use
    Given BILLING_REQUIRED is true
    And shop "shop-001" has an active "pro" subscription
    And the "pro" plan has features: ["advanced_analytics", "priority_support", "api_access"]
    When I send GET /api/dashboard with session token for "shop-001"
    Then the response status is 200
    And req.context.subscription.features contains "advanced_analytics"
    And req.context.subscription.features contains "api_access"

  @edge
  Scenario: After re-subscription following a decline — active plan grants access
    Given shop "shop-001" had a declined subscription for "pro" created 2 days ago
    And shop "shop-001" has a new active subscription for "pro" created 1 day ago
    When I send GET /api/dashboard with session token for "shop-001"
    Then the response status is 200
    And the active subscription is used (not the declined one)
