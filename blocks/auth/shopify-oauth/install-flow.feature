Feature: App Installation Flow
  As a Shopify merchant
  I want to install a Shopify app via OAuth
  So that the app can access my store data and provide its features

  Background:
    Given the app is configured with API key "test-api-key" and secret "test-api-secret"
    And the app URL is "https://myapp.example.com"
    And the requested scopes are "read_products,write_orders"

  @happy
  Scenario: Successful first-time installation
    When a merchant visits GET /api/auth/shopify?shop=example.myshopify.com
    Then the app generates a nonce and stores it in oauth_nonces with a 5-minute TTL
    And the merchant is redirected to "https://example.myshopify.com/admin/oauth/authorize"
    And the redirect URL includes client_id "test-api-key"
    And the redirect URL includes scope "read_products,write_orders"
    And the redirect URL includes state matching the stored nonce

    When Shopify calls GET /api/auth/shopify/callback with:
      | code      | auth-code-123              |
      | hmac      | valid-hmac-for-params      |
      | shop      | example.myshopify.com      |
      | state     | matching-nonce             |
      | timestamp | current-timestamp          |
    Then the app verifies the HMAC signature
    And the app verifies the nonce exists and is not expired
    And the nonce is deleted from oauth_nonces
    And the app exchanges the code for an offline access token
    And a shop record is created with domain "example.myshopify.com"
    And the access token is stored encrypted
    And a "shop.installed" event is emitted
    And the merchant is redirected to "https://example.myshopify.com/admin/apps/test-api-key"

  @happy
  Scenario: Reinstall after previous uninstall
    Given a shop "example.myshopify.com" exists with uninstalled_at set
    When the merchant completes the OAuth flow for "example.myshopify.com"
    Then the existing shop record is updated (not duplicated)
    And access_token is updated with the new token
    And uninstalled_at is set to null
    And installed_at is updated to now
    And a "shop.reinstalled" event is emitted

  @happy
  Scenario: Reinstall with different scopes
    Given a shop "example.myshopify.com" exists with scopes "read_products"
    And the app now requests scopes "read_products,write_orders"
    When the merchant completes the OAuth flow
    Then the shop record scopes are updated to "read_products,write_orders"
    And the access token is replaced with the new one

  @error
  Scenario: Invalid shop domain format
    When a merchant visits GET /api/auth/shopify?shop=evil.example.com
    Then the response status is 400
    And the response body contains error "invalid_shop_domain"
    And no nonce is created

  @error
  Scenario: Missing shop parameter
    When a merchant visits GET /api/auth/shopify without a shop parameter
    Then the response status is 400
    And the response body contains error "invalid_shop_domain"

  @error
  Scenario: HMAC verification fails on callback
    When Shopify calls GET /api/auth/shopify/callback with a tampered hmac
    Then the response status is 401
    And the response body contains error "hmac_verification_failed"
    And no shop record is created or updated

  @error
  Scenario: Expired nonce on callback
    Given a nonce was created 6 minutes ago (past the 5-minute TTL)
    When Shopify calls GET /api/auth/shopify/callback with the expired nonce as state
    Then the response status is 401
    And the response body contains error "invalid_or_expired_state"

  @error
  Scenario: Nonce already used (replay attempt)
    Given a nonce was already used and deleted
    When Shopify calls GET /api/auth/shopify/callback with the used nonce as state
    Then the response status is 401
    And the response body contains error "invalid_or_expired_state"

  @error
  Scenario: Token exchange fails with Shopify
    Given the HMAC and nonce are valid
    When the app exchanges the code and Shopify returns a 400 error
    Then the response status is 502
    And the response body contains error "token_exchange_failed"
    And no shop record is created
