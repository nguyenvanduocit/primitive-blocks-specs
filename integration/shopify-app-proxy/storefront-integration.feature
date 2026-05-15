Feature: Storefront Integration
  As a Shopify merchant
  I want app content to appear correctly within my storefront theme
  So that customers experience a seamless, on-brand interaction

  Background:
    Given the app is configured with API secret "test-api-secret"
    And a shop "example.myshopify.com" exists in the database
    And the app proxy subpath is configured as "/apps/myapp" in the Shopify Partner Dashboard
    And all proxy requests have a valid Shopify signature

  @happy
  Scenario: Liquid content renders within active theme layout
    Given a customer visits https://example-store.com/apps/myapp/reviews?product_id=123
    When Shopify forwards the request to GET /api/proxy/reviews?product_id=123&shop=example.myshopify.com&path_prefix=/apps/myapp&...
    Then the app returns application/liquid content
    And Shopify renders the Liquid within the store's active theme (including header, footer, CSS)
    And the customer sees the reviews widget styled consistently with the store theme

  @happy
  Scenario: Dynamic content is escaped in Liquid templates
    Given a review with author name containing HTML: "<script>alert('xss')</script>"
    When the proxy returns a Liquid template embedding the author name
    Then the Liquid template uses the escape filter: "{{ author_name | escape }}"
    And the rendered output shows the literal text "&lt;script&gt;alert('xss')&lt;/script&gt;"
    And no JavaScript executes in the customer's browser

  @happy
  Scenario: AJAX call from theme JavaScript — JSON response
    Given a merchant adds theme JavaScript that calls fetch('/apps/myapp/api/stats')
    When the browser sends GET https://example-store.com/apps/myapp/api/stats
    And Shopify proxies to GET /api/proxy/api/stats?shop=example.myshopify.com&...
    Then the app returns application/json
    And the fetch resolves with the JSON data
    And the theme JavaScript updates the DOM with the response

  @happy
  Scenario: Cache headers allow Shopify CDN to cache public content
    Given APP_PROXY_CACHE_TTL is 300
    When the proxy returns a Liquid response for a product reviews page
    Then the Cache-Control header is "s-maxage=300"
    And Shopify's CDN can serve subsequent requests from cache for 300 seconds

  @happy
  Scenario: Shop domain scopes cache correctly
    Given two shops: "shop-a.myshopify.com" and "shop-b.myshopify.com"
    When each shop's proxy request includes their own "shop" param in the query string
    Then Shopify's CDN uses the full URL (including shop param) as the cache key
    And shop-a's cached response is never served to shop-b's customers

  @happy
  Scenario: Proxy endpoint returns no PII
    Given a customer is browsing the storefront
    When the customer triggers a proxy request (e.g., views a reviews widget)
    Then the proxy response contains no customer email addresses
    And the proxy response contains no customer phone numbers
    And the proxy response contains no shipping addresses
    And the proxy response contains no order IDs or order details

  @happy
  Scenario: Uninstalled shop — proxy returns 404
    Given a shop "gone.myshopify.com" has uninstalled_at set (uninstalled)
    When Shopify forwards a proxy request with shop=gone.myshopify.com
    And the signature is valid
    Then the app returns 404
    And the response body contains error "shop_not_found"

  @edge
  Scenario: Proxy path with multiple segments — routed correctly
    Given a proxy request to /api/proxy/products/featured/list
    When the catch-all handler receives the request
    Then the sub-path "/products/featured/list" is extracted correctly
    And routed to the correct nested handler

  @edge
  Scenario: Partner Dashboard not configured — Shopify never forwards
    Given the app proxy is not configured in the Shopify Partner Dashboard
    When a customer visits https://example-store.com/apps/myapp/reviews
    Then Shopify returns a 404 to the customer (the app backend is never called)
    And no handler logic runs

  @edge
  Scenario: Proxy request for shop with limited scopes — app adapts response
    Given a shop has scopes "read_products" only (no read_customers)
    When a proxy handler tries to fetch customer-related data
    Then the handler gracefully returns available data only
    And no Shopify API call is made that requires missing scopes
