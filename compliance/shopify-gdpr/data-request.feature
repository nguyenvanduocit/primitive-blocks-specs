Feature: Customer Data Request
  As the app backend
  I want to handle the customers/data_request GDPR webhook
  So that I acknowledge receipt of customer data access requests and collect their data

  Background:
    Given the app is configured with API secret "test-api-secret"
    And a shop "example.myshopify.com" exists in the database

  @happy
  Scenario: Valid data request — customer with data
    Given customer 12345 has 3 reviews and 2 order annotations in the app database
    When Shopify sends POST /api/gdpr/customers-data-request with:
      | shop_id        | 1                         |
      | shop_domain    | example.myshopify.com     |
      | customer.id    | 12345                     |
      | customer.email | customer@example.com      |
      | orders_requested | [1001, 1002]            |
    And the X-Shopify-Hmac-Sha256 header is valid for the request body
    Then the response status is 200
    And a gdpr_requests record is created with request_type "customers_data_request"
    And the gdpr_requests record has status "completed"
    And the gdpr_requests record has customer_id 12345
    And the gdpr_requests record has customer_email "customer@example.com"
    And orders_requested contains [1001, 1002]
    And a "gdpr.data_requested" event is emitted with shopId, customerId, and customerEmail
    And GDPR_NOTIFY_EMAIL receives a notification if configured

  @happy
  Scenario: Valid data request — unknown customer (no data in app)
    Given customer 99999 has no data in any app table for "example.myshopify.com"
    When Shopify sends POST /api/gdpr/customers-data-request with:
      | shop_id        | 1                         |
      | shop_domain    | example.myshopify.com     |
      | customer.id    | 99999                     |
      | customer.email | ghost@example.com         |
      | orders_requested | []                      |
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And a gdpr_requests record is created with status "completed"
    And no error is raised (no data found is a valid outcome)
    And a "gdpr.data_requested" event is emitted

  @happy
  Scenario: Duplicate data request — idempotent processing
    Given a gdpr_requests record already exists with shopify_request_id "req-abc-123" and status "completed"
    When Shopify resends POST /api/gdpr/customers-data-request with data_request.id "req-abc-123"
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And no duplicate processing occurs
    And the existing gdpr_requests record is not modified

  @error
  Scenario: Invalid HMAC — forged request rejected
    When Shopify sends POST /api/gdpr/customers-data-request with an invalid X-Shopify-Hmac-Sha256 header
    Then the response status is 401
    And no gdpr_requests record is created
    And no customer data is queried

  @error
  Scenario: Missing HMAC header — request rejected
    When Shopify sends POST /api/gdpr/customers-data-request with no X-Shopify-Hmac-Sha256 header
    Then the response status is 401
    And no gdpr_requests record is created

  @edge
  Scenario: Data request for unknown shop
    When Shopify sends POST /api/gdpr/customers-data-request for shop "ghost.myshopify.com"
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And a warning is logged about unknown shop "ghost.myshopify.com"
    And no gdpr_requests record is created (no shop_id to associate with)
    And no error is thrown

  @edge
  Scenario: Data request with empty orders_requested array
    When Shopify sends POST /api/gdpr/customers-data-request with orders_requested set to []
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And the gdpr_requests record has orders_requested as empty array
    And customer data queries still run (non-order tables)

  @security
  Scenario: HMAC verification uses raw body before JSON parsing
    Given a valid request body
    When the X-Shopify-Hmac-Sha256 header contains the HMAC of the raw body bytes
    Then HMAC verification succeeds
    And JSON parsing happens after HMAC verification (not before)
