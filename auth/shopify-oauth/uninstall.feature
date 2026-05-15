Feature: App Uninstall
  As the app backend
  I want to handle the APP_UNINSTALLED webhook
  So that I mark the shop as inactive and stop processing

  Background:
    Given the app is configured with API secret "test-api-secret"
    And a shop "example.myshopify.com" exists with an active installation

  @happy
  Scenario: Handle APP_UNINSTALLED webhook
    When Shopify sends POST /api/webhooks with topic "APP_UNINSTALLED"
    And the request body contains shop domain "example.myshopify.com"
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And the shop record for "example.myshopify.com" has uninstalled_at set to now
    And a "shop.uninstalled" event is emitted

  @error
  Scenario: Reject uninstall webhook with invalid HMAC
    When Shopify sends POST /api/webhooks with topic "APP_UNINSTALLED"
    And the X-Shopify-Hmac-Sha256 header is invalid
    Then the response status is 401
    And the shop record is not modified

  @edge
  Scenario: Uninstall webhook for unknown shop
    When Shopify sends POST /api/webhooks with topic "APP_UNINSTALLED"
    And the shop domain "unknown.myshopify.com" does not exist in the database
    Then the response status is 200
    And no error is thrown (idempotent behavior)

  @edge
  Scenario: Duplicate uninstall webhook
    Given the shop "example.myshopify.com" already has uninstalled_at set
    When Shopify sends POST /api/webhooks with topic "APP_UNINSTALLED" again
    Then the response status is 200
    And uninstalled_at is updated to the new timestamp
