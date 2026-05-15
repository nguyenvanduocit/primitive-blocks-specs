Feature: Webhook Receiving
  As the app backend
  I want to securely receive and process webhook deliveries from Shopify
  So that I can react to merchant store events in real time

  Background:
    Given the app is configured with API secret "test-api-secret"
    And a shop "example.myshopify.com" with id "shop-001" is active in the database
    And WEBHOOK_PATH is "/api/webhooks"

  @happy
  Scenario: Receive valid ORDERS_CREATE webhook and respond 200 immediately
    When Shopify sends POST /api/webhooks with:
      | X-Shopify-Topic        | orders/create                              |
      | X-Shopify-Shop-Domain  | example.myshopify.com                     |
      | X-Shopify-Webhook-Id   | a1b2c3d4-e5f6-7890-abcd-ef1234567890      |
      | X-Shopify-Hmac-Sha256  | valid-hmac-for-body                        |
      | X-Shopify-Api-Version  | 2025-01                                    |
    And the request body is a valid ORDERS_CREATE payload
    Then the response status is 200
    And the response is sent before any payload processing begins
    And a webhook_deliveries row is created with status "received"
    And the delivery is routed to the orders/create handler asynchronously
    And a "webhook.received" event is emitted

  @happy
  Scenario: Receive valid PRODUCTS_UPDATE webhook and process asynchronously
    When Shopify sends POST /api/webhooks with:
      | X-Shopify-Topic        | products/update                            |
      | X-Shopify-Shop-Domain  | example.myshopify.com                     |
      | X-Shopify-Webhook-Id   | b2c3d4e5-f6a7-8901-bcde-f12345678901      |
      | X-Shopify-Hmac-Sha256  | valid-hmac-for-body                        |
    And the request body is a valid PRODUCTS_UPDATE payload
    Then the response status is 200
    And the products/update handler is dispatched asynchronously
    And after the handler completes successfully the delivery status is "processed"
    And a "webhook.processed" event is emitted

  @happy
  Scenario: Receive APP_UNINSTALLED webhook and mark shop inactive
    When Shopify sends POST /api/webhooks with:
      | X-Shopify-Topic        | app/uninstalled                            |
      | X-Shopify-Shop-Domain  | example.myshopify.com                     |
      | X-Shopify-Webhook-Id   | c3d4e5f6-a7b8-9012-cdef-123456789012      |
      | X-Shopify-Hmac-Sha256  | valid-hmac-for-body                        |
    And the request body is a valid APP_UNINSTALLED payload
    Then the response status is 200
    And the app/uninstalled handler is dispatched
    And the shop "example.myshopify.com" has uninstalled_at set to now

  @error
  Scenario: Reject webhook with invalid HMAC
    When Shopify sends POST /api/webhooks with:
      | X-Shopify-Topic        | orders/create                              |
      | X-Shopify-Shop-Domain  | example.myshopify.com                     |
      | X-Shopify-Webhook-Id   | d4e5f6a7-b8c9-0123-defa-234567890123      |
      | X-Shopify-Hmac-Sha256  | 0000000000000000000000000000000000000000000000000000000000000000 |
    And the request body is an ORDERS_CREATE payload
    Then the response status is 401
    And no webhook_deliveries row is created
    And no handler is dispatched
    And no event is emitted

  @error
  Scenario: Reject webhook with missing HMAC header
    When Shopify sends POST /api/webhooks with:
      | X-Shopify-Topic        | orders/create                              |
      | X-Shopify-Shop-Domain  | example.myshopify.com                     |
      | X-Shopify-Webhook-Id   | e5f6a7b8-c9d0-1234-efab-345678901234      |
    And the X-Shopify-Hmac-Sha256 header is absent
    Then the response status is 401
    And no webhook_deliveries row is created

  @error
  Scenario: Accept webhook for unknown topic and log warning
    When Shopify sends POST /api/webhooks with:
      | X-Shopify-Topic        | inventory_levels/update                    |
      | X-Shopify-Shop-Domain  | example.myshopify.com                     |
      | X-Shopify-Webhook-Id   | f6a7b8c9-d0e1-2345-fabc-456789012345      |
      | X-Shopify-Hmac-Sha256  | valid-hmac-for-body                        |
    And the request body is an INVENTORY_LEVELS_UPDATE payload
    And no handler is registered for "inventory_levels/update"
    Then the response status is 200
    And a webhook_deliveries row is created with status "processed"
    And a warning is logged for the unknown topic
    And no handler is dispatched

  @error
  Scenario: Accept webhook for unknown shop and log warning
    When Shopify sends POST /api/webhooks with:
      | X-Shopify-Topic        | orders/create                              |
      | X-Shopify-Shop-Domain  | unregistered.myshopify.com                |
      | X-Shopify-Webhook-Id   | a7b8c9d0-e1f2-3456-abcd-567890123456      |
      | X-Shopify-Hmac-Sha256  | valid-hmac-for-body                        |
    And the shop "unregistered.myshopify.com" does not exist in the database
    Then the response status is 200
    And a warning is logged for the unknown shop domain
    And no webhook_deliveries row is created
    And no handler is dispatched

  @error
  Scenario: Handler failure marks delivery as failed and emits event
    Given the orders/create handler throws an unhandled error
    When Shopify sends a valid ORDERS_CREATE webhook for "example.myshopify.com"
    Then the response status is 200
    And after the async handler fails the delivery status is "failed"
    And the error field contains the exception message
    And a "webhook.failed" event is emitted with the error

  @edge
  Scenario: Large payload processed correctly
    When Shopify sends POST /api/webhooks with an ORDERS_CREATE payload of 500KB
    And the HMAC is valid for that body
    Then the response status is 200
    And HMAC verification passes over the full raw body bytes
    And the payload is processed without truncation

  @edge
  Scenario: Webhook received for recently uninstalled shop
    Given the shop "example.myshopify.com" has uninstalled_at set
    When Shopify sends a valid ORDERS_CREATE webhook for "example.myshopify.com"
    Then the response status is 200
    And a warning is logged
    And no handler is dispatched
