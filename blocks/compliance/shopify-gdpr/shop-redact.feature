Feature: Shop Redact
  As the app backend
  I want to handle the shop/redact GDPR webhook
  So that all data for a merchant's shop is permanently purged after uninstall

  Background:
    Given the app is configured with API secret "test-api-secret"
    And a shop "example.myshopify.com" exists in the database with shop_id "shop-001"
    And the shop was uninstalled 48 hours ago

  @happy
  Scenario: Valid shop redact — all shop data purged
    Given the shop "example.myshopify.com" has the following data:
      | Table                  | Records |
      | reviews                | 47      |
      | webhook_subscriptions  | 5       |
      | webhook_deliveries     | 312     |
      | gdpr_requests          | 2       |
    When Shopify sends POST /api/gdpr/shop-redact with:
      | shop_id     | 1                     |
      | shop_domain | example.myshopify.com |
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And the shops record for "example.myshopify.com" is deleted
    And a "gdpr.shop_redacted" event is emitted with shopId and shopDomain

  @happy
  Scenario: Cascade delete removes all dependent table records
    Given the shop has records in every FK-dependent table
    When the shop_redact webhook is processed successfully
    Then all reviews for the shop are deleted (CASCADE)
    And all webhook_subscriptions for the shop are deleted (CASCADE)
    And all webhook_deliveries for the shop are deleted (CASCADE)
    And no orphan records remain in any table referencing the deleted shop_id

  @happy
  Scenario: Audit trail preserved after shop deletion
    Given a gdpr_requests record exists for the shop_redact request with id "gdpr-req-001"
    When the shop_redact webhook is processed
    Then the shops record is deleted
    And the gdpr_requests record "gdpr-req-001" still exists with shop_id set to null
    And the gdpr_requests record has status "completed" and completed_at set
    And the audit trail survives the shop deletion

  @happy
  Scenario: Shop redact for shop with no dependent data
    Given the shop "empty.myshopify.com" exists but has no reviews, webhooks, or other records
    When Shopify sends POST /api/gdpr/shop-redact for "empty.myshopify.com"
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And the shops record is deleted without error
    And a "gdpr.shop_redacted" event is emitted

  @error
  Scenario: Invalid HMAC — shop redact rejected
    When Shopify sends POST /api/gdpr/shop-redact with an invalid X-Shopify-Hmac-Sha256 header
    Then the response status is 401
    And no shop data is deleted
    And no gdpr_requests record is created

  @error
  Scenario: Missing HMAC header — request rejected
    When Shopify sends POST /api/gdpr/shop-redact with no X-Shopify-Hmac-Sha256 header
    Then the response status is 401
    And no shop data is touched

  @edge
  Scenario: Shop redact for unknown shop
    When Shopify sends POST /api/gdpr/shop-redact for shop "ghost.myshopify.com"
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And a warning is logged about unknown shop "ghost.myshopify.com"
    And no error is thrown (idempotent — shop already gone)

  @edge
  Scenario: Duplicate shop redact webhook
    Given the shop "example.myshopify.com" was already deleted by a previous shop_redact
    When Shopify resends POST /api/gdpr/shop-redact for "example.myshopify.com"
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And no error is thrown (shop already absent)
    And the handler exits gracefully with a warning log

  @edge
  Scenario: Shop redact received before uninstall webhook
    Given the shop "example.myshopify.com" still has uninstalled_at = null (active install)
    When Shopify sends POST /api/gdpr/shop-redact for the shop
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And all shop data is purged regardless of install status
    And a "gdpr.shop_redacted" event is emitted

  @security
  Scenario: Shop redact uses constant-time HMAC comparison
    When POST /api/gdpr/shop-redact is called with any HMAC value
    Then HMAC comparison uses constant-time comparison (not string equality)
    And the comparison time does not vary based on how many bytes match
