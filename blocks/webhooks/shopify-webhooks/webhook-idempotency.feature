Feature: Webhook Idempotency
  As the app backend
  I want to process each webhook delivery exactly once
  So that Shopify's retry behavior does not cause duplicate side effects

  Background:
    Given the app is configured with API secret "test-api-secret"
    And a shop "example.myshopify.com" with id "shop-001" is active in the database
    And WEBHOOK_TOPICS includes "ORDERS_CREATE"

  @happy
  Scenario: First delivery of a webhook is processed normally
    Given no webhook_deliveries row exists for webhook_id "wh-first-001"
    When Shopify sends POST /api/webhooks with:
      | X-Shopify-Webhook-Id  | wh-first-001                               |
      | X-Shopify-Topic       | orders/create                              |
      | X-Shopify-Hmac-Sha256 | valid-hmac-for-body                        |
    Then the response status is 200
    And a webhook_deliveries row is created for webhook_id "wh-first-001" with status "received"
    And the orders/create handler is dispatched
    And after handler completion the status is "processed"

  @happy
  Scenario: Duplicate delivery with same webhook_id is skipped
    Given a webhook_deliveries row already exists for webhook_id "wh-dup-001" with status "processed"
    When Shopify retries POST /api/webhooks with:
      | X-Shopify-Webhook-Id  | wh-dup-001                                 |
      | X-Shopify-Topic       | orders/create                              |
      | X-Shopify-Hmac-Sha256 | valid-hmac-for-body                        |
    Then the response status is 200
    And no new webhook_deliveries row is created for "wh-dup-001"
    And the orders/create handler is NOT dispatched a second time
    And the existing delivery row status remains "processed"

  @happy
  Scenario: Duplicate delivery skipped even when first is still processing
    Given a webhook_deliveries row already exists for webhook_id "wh-inprog-001" with status "processing"
    When Shopify retries POST /api/webhooks with:
      | X-Shopify-Webhook-Id  | wh-inprog-001                              |
      | X-Shopify-Topic       | orders/create                              |
      | X-Shopify-Hmac-Sha256 | valid-hmac-for-body                        |
    Then the response status is 200
    And no new webhook_deliveries row is created
    And no second handler is dispatched

  @happy
  Scenario: Different webhook_id for same topic and shop is processed independently
    Given a webhook_deliveries row exists for webhook_id "wh-order-001" with status "processed"
    When Shopify sends a new ORDERS_CREATE with webhook_id "wh-order-002"
    And the HMAC is valid
    Then the response status is 200
    And a new webhook_deliveries row is created for "wh-order-002"
    And the handler is dispatched for the new delivery
    And 2 separate delivery rows exist for shop "shop-001" with topic "orders/create"

  @edge
  Scenario: Concurrent duplicate deliveries — only one is processed
    Given no webhook_deliveries row exists for webhook_id "wh-concurrent-001"
    When two requests arrive simultaneously for webhook_id "wh-concurrent-001"
    And both requests have valid HMAC signatures
    Then both requests return 200
    And exactly 1 webhook_deliveries row is created for "wh-concurrent-001"
    And the handler is dispatched exactly once
    And the UNIQUE(webhook_id) constraint in the database enforces this

  @edge
  Scenario: Retry after handler failure is treated as a new delivery attempt
    Given a webhook_deliveries row exists for webhook_id "wh-failed-001" with status "failed"
    When Shopify retries POST /api/webhooks with webhook_id "wh-failed-001"
    And the HMAC is valid
    Then the response status is 200
    And the INSERT ON CONFLICT DO NOTHING skips re-insertion
    And no second handler is dispatched
    And the failed delivery remains failed (retry handling is a separate recovery mechanism)

  @edge
  Scenario: Idempotency is enforced at the database layer not application layer
    Given the application idempotency check is bypassed
    When two simultaneous INSERT attempts occur for webhook_id "wh-race-001"
    Then the database UNIQUE constraint on webhook_id rejects the second insert
    And only one row exists for "wh-race-001"
    And no duplicate processing occurs

  @edge
  Scenario: webhook_id from header is the idempotency key, not payload hash
    Given a webhook_deliveries row exists for webhook_id "wh-same-id-001" with status "processed"
    When Shopify sends a request with webhook_id "wh-same-id-001" but a different payload body
    And the HMAC is valid for the new body
    Then the response status is 200
    And the delivery is skipped (webhook_id match takes precedence over payload difference)
    And no handler is dispatched
