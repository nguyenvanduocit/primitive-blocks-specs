Feature: App Proxy Response Types
  As the app backend
  I want to return correctly typed responses for each proxy use case
  So that Shopify renders them appropriately on the storefront

  Background:
    Given the app is configured with API secret "test-api-secret"
    And a shop "example.myshopify.com" exists in the database
    And all proxy requests have a valid Shopify signature

  @happy
  Scenario: Liquid response — rendered within theme layout
    Given a proxy request to GET /api/proxy/reviews?product_id=123&shop=example.myshopify.com&...
    When the reviews handler returns a Liquid template
    Then the response status is 200
    And the Content-Type header is "application/liquid"
    And the response body contains valid Liquid markup
    And Shopify renders the Liquid within the active store theme layout
    And the Liquid has access to theme objects (shop, cart, customer)

  @happy
  Scenario: JSON response — returned as-is for AJAX calls
    Given a proxy request to GET /api/proxy/api/stats?shop=example.myshopify.com&...
    When the stats handler returns aggregate data
    Then the response status is 200
    And the Content-Type header is "application/json"
    And the response body is valid JSON
    And Shopify passes the JSON response directly to the requesting JavaScript

  @happy
  Scenario: HTML response — standalone, not rendered in theme
    Given a proxy request to GET /api/proxy/embed?shop=example.myshopify.com&...
    When the embed handler returns an HTML document
    Then the response status is 200
    And the Content-Type header is "text/html"
    And the response body is a complete HTML document
    And Shopify does NOT wrap the response in the theme layout

  @happy
  Scenario: Liquid response cache headers set correctly
    Given APP_PROXY_CACHE_TTL is 300
    When the proxy returns an application/liquid response
    Then the Cache-Control header is "s-maxage=300"

  @happy
  Scenario: JSON response for dynamic data — no caching
    When the proxy returns an application/json response for user-specific data
    Then the Cache-Control header is "no-store"

  @happy
  Scenario: JSON response for public aggregate data — cacheable
    Given APP_PROXY_CACHE_TTL is 300
    When the proxy returns an application/json response for public shop-wide stats
    Then the Cache-Control header is "s-maxage=300"

  @error
  Scenario: Unknown sub-path — 404 response
    Given a proxy request to GET /api/proxy/nonexistent?shop=example.myshopify.com&...
    When no handler is registered for the sub-path
    Then the response status is 404
    And the response body contains error "proxy_path_not_found"

  @error
  Scenario: Missing required query param for handler — 400 response
    Given a proxy request to GET /api/proxy/reviews without product_id
    When the reviews handler requires product_id
    Then the response status is 400
    And the response body contains error "missing_product_id"

  @edge
  Scenario: Empty Liquid template — valid response
    Given a proxy request where no data is found for the query
    When the handler returns an empty Liquid template
    Then the response status is 200
    And the Content-Type header is "application/liquid"
    And the response body is an empty string or minimal Liquid markup

  @edge
  Scenario: Large JSON payload — handled without truncation
    Given a proxy request returns 100 review records as JSON
    Then the full payload is returned without truncation
    And the Content-Type header is "application/json"
