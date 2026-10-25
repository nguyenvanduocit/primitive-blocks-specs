Feature: Session Token Verification
  As the app backend
  I want to verify Shopify App Bridge session tokens on every request
  So that only authenticated merchants from installed shops can access the API

  Background:
    Given the app is configured with API key "test-api-key" and secret "test-api-secret"
    And a shop "example.myshopify.com" exists in the shops table with uninstalled_at null
    And the current timestamp is 1700000000

  @happy
  Scenario: Valid session token with all correct claims
    Given a session token with:
      | iss | https://example.myshopify.com/admin |
      | dest | https://example.myshopify.com |
      | aud | test-api-key |
      | sub | 42 |
      | exp | 1700000060 |
      | nbf | 1700000000 |
      | iat | 1700000000 |
      | jti | unique-token-id-001 |
      | sid | session-abc123 |
    And the token is signed with secret "test-api-secret"
    When the middleware processes GET /api/products with this token as Bearer
    Then the middleware calls next()
    And req.shopContext.shopId equals the shops.id for "example.myshopify.com"
    And req.shopContext.shopDomain equals "example.myshopify.com"
    And req.shopContext.shopifyUserId equals "42"

  @happy
  Scenario: Token with different Shopify user (sub) for same shop
    Given a session token for shop "example.myshopify.com" with sub "99" signed correctly
    When the middleware processes the request
    Then the middleware calls next()
    And req.shopContext.shopifyUserId equals "99"
    And req.shopContext.shopDomain equals "example.myshopify.com"

  @error
  Scenario: Missing Authorization header
    When GET /api/products is called with no Authorization header
    Then the response status is 401
    And the response body contains error "missing_token"

  @error
  Scenario: Authorization header present but not Bearer format
    When GET /api/products is called with Authorization "Basic dXNlcjpwYXNz"
    Then the response status is 401
    And the response body contains error "missing_token"

  @error
  Scenario: Malformed token — not 3 dot-separated parts
    When GET /api/products is called with Bearer token "notavalidjwt"
    Then the response status is 401
    And the response body contains error "invalid_token"

  @error
  Scenario: Malformed token — only 2 parts
    When GET /api/products is called with Bearer token "header.payload"
    Then the response status is 401
    And the response body contains error "invalid_token"

  @error
  Scenario: Invalid signature — token signed with wrong secret
    Given a session token with all valid claims for "example.myshopify.com"
    But the token is signed with secret "wrong-secret"
    When the middleware processes the request
    Then the response status is 401
    And the response body contains error "invalid_token"

  @error
  Scenario: Invalid signature — payload tampered after signing
    Given a valid session token for "example.myshopify.com"
    When an attacker modifies the payload to change dest to "victim.myshopify.com"
    And presents the token with the original signature
    Then the response status is 401
    And the response body contains error "invalid_token"

  @error
  Scenario: Expired token — exp is in the past
    Given a session token with exp 1699999900 (100 seconds ago)
    And all other claims are valid
    When the middleware processes the request
    Then the response status is 401
    And the response body contains error "expired_token"

  @error
  Scenario: Wrong audience — aud does not match API key
    Given a session token for "example.myshopify.com" with aud "other-app-api-key"
    And the token is signed with "test-api-secret"
    When the middleware processes the request
    Then the response status is 401
    And the response body contains error "invalid_audience"

  @error
  Scenario: Shop not found in database
    Given a session token for "unknown-store.myshopify.com" signed correctly
    And "unknown-store.myshopify.com" does not exist in the shops table
    When the middleware processes the request
    Then the response status is 401
    And the response body contains error "shop_not_found"

  @error
  Scenario: Shop is uninstalled
    Given a shop "uninstalled.myshopify.com" exists with uninstalled_at set to a past timestamp
    And a valid session token for "uninstalled.myshopify.com"
    When the middleware processes the request
    Then the response status is 401
    And the response body contains error "shop_not_found"

  @edge
  Scenario: Token with nbf in the future (issued for later)
    Given a session token with:
      | exp | 1700000120 |
      | nbf | 1700000060 |
    And the current time is 1700000000 (before nbf)
    When the middleware processes the request
    Then the response status is 401
    And the response body contains error "invalid_token"

  @edge
  Scenario: Token where iss and dest reference different shops
    Given a session token with:
      | iss | https://shop-a.myshopify.com/admin |
      | dest | https://shop-b.myshopify.com |
    And the token is signed with "test-api-secret"
    When the middleware processes the request
    Then the response status is 401
    And the response body contains error "invalid_token"

  @edge
  Scenario: Token with iss missing the /admin suffix
    Given a session token with iss "https://example.myshopify.com" (no /admin)
    When the middleware processes the request
    Then the response status is 401
    And the response body contains error "invalid_token"
