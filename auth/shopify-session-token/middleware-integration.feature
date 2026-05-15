Feature: Middleware Integration
  As a developer
  I want the session token middleware to integrate cleanly with my API routes
  So that authenticated endpoints receive shop context and unauthenticated endpoints remain open

  Background:
    Given the app is configured with API key "test-api-key" and secret "test-api-secret"
    And a shop "example.myshopify.com" exists in the shops table
    And another shop "other.myshopify.com" exists in the shops table

  @happy
  Scenario: Protected endpoint receives shopContext after valid token
    Given a valid session token for "example.myshopify.com" with user "42"
    When GET /api/orders is called with the token
    Then the route handler receives req.shopContext with:
      | shopDomain | example.myshopify.com |
      | shopifyUserId | 42 |
    And shopId is a valid UUID matching shops.id for "example.myshopify.com"

  @happy
  Scenario: Multiple concurrent requests from different shops get correct context
    Given a valid session token for "example.myshopify.com" with user "10"
    And a valid session token for "other.myshopify.com" with user "20"
    When both requests are processed concurrently
    Then the request for "example.myshopify.com" gets shopDomain "example.myshopify.com"
    And the request for "other.myshopify.com" gets shopDomain "other.myshopify.com"
    And neither request leaks the other's context

  @happy
  Scenario: Multiple requests from same shop with same token succeed
    Given a valid session token for "example.myshopify.com"
    When the same token is used for 5 consecutive requests within the expiry window
    Then all 5 requests succeed
    And each gets the same shopContext

  @edge
  Scenario: OPTIONS request (CORS preflight) bypasses middleware
    When OPTIONS /api/products is called with no Authorization header
    Then the response status is 204 (or 200)
    And no auth error is returned

  @edge
  Scenario: Public endpoint without middleware works without token
    Given /api/health is registered without the auth middleware
    When GET /api/health is called with no Authorization header
    Then the response status is 200
    And no auth error is returned

  @edge
  Scenario: Middleware applied globally — unprotected route still blocks without token
    Given the middleware is applied globally to /api/*
    And /api/internal/data has no explicit middleware exclusion
    When GET /api/internal/data is called with no Authorization header
    Then the response status is 401
    And the response body contains error "missing_token"
