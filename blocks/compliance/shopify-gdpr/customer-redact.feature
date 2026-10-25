Feature: Customer Redact
  As the app backend
  I want to handle the customers/redact GDPR webhook
  So that I erase all personal data for a customer across all app tables

  Background:
    Given the app is configured with API secret "test-api-secret"
    And a shop "example.myshopify.com" exists in the database

  @happy
  Scenario: Valid redact request — customer PII deleted
    Given customer 12345 has the following data in the app:
      | Table             | Records |
      | reviews           | 2       |
      | customer_profiles | 1       |
      | order_annotations | 3       |
    When Shopify sends POST /api/gdpr/customers-redact with:
      | shop_id          | 1                         |
      | shop_domain      | example.myshopify.com     |
      | customer.id      | 12345                     |
      | customer.email   | customer@example.com      |
      | orders_to_redact | [1001, 1002, 1003]        |
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And a gdpr_requests record is created with request_type "customers_redact"
    And the gdpr_requests record has status "completed"
    And the customer_profiles record for customer 12345 is deleted
    And the order_annotations records for orders [1001, 1002, 1003] are deleted
    And a "gdpr.customer_redacted" event is emitted

  @happy
  Scenario: Customer with reviews — PII anonymized (records retained)
    Given customer 12345 has 3 reviews in the reviews table with author_name and author_email
    When Shopify sends POST /api/gdpr/customers-redact for customer 12345
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And each review for customer 12345 has author_name set to "Deleted User"
    And each review for customer 12345 has author_email set to null
    And each review for customer 12345 has author_phone set to null
    And the review records themselves are not deleted (ratings and body preserved)
    And the gdpr_requests record has status "completed"

  @happy
  Scenario: Customer with no data — 200 with no errors
    Given customer 99999 has no records in any app table for "example.myshopify.com"
    When Shopify sends POST /api/gdpr/customers-redact for customer 99999
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And no DELETE or UPDATE queries error out due to missing records
    And a gdpr_requests record is created with status "completed"
    And a "gdpr.customer_redacted" event is emitted

  @happy
  Scenario: Redact by email when customer_id is not present
    Given customer data is stored with email "legacy@example.com" and no shopify_customer_id
    When Shopify sends POST /api/gdpr/customers-redact with customer.email "legacy@example.com"
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And records matching author_email "legacy@example.com" are anonymized
    And the gdpr_requests record has status "completed"

  @error
  Scenario: Invalid HMAC — redact request rejected
    When Shopify sends POST /api/gdpr/customers-redact with an invalid X-Shopify-Hmac-Sha256 header
    Then the response status is 401
    And no gdpr_requests record is created
    And no customer data is modified or deleted

  @error
  Scenario: Missing HMAC header — request rejected
    When Shopify sends POST /api/gdpr/customers-redact with no X-Shopify-Hmac-Sha256 header
    Then the response status is 401
    And no customer data is touched

  @edge
  Scenario: Redact request for unknown shop
    When Shopify sends POST /api/gdpr/customers-redact for shop "ghost.myshopify.com"
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And a warning is logged about unknown shop
    And no data is modified

  @edge
  Scenario: Duplicate redact request — idempotent
    Given customer 12345 was already redacted (all PII anonymized/deleted)
    When Shopify resends POST /api/gdpr/customers-redact for customer 12345
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And UPDATE/DELETE queries run without error (no-ops on already-anonymized rows)
    And a new gdpr_requests record is logged for the duplicate

  @edge
  Scenario: Redact with empty orders_to_redact
    When Shopify sends POST /api/gdpr/customers-redact with orders_to_redact set to []
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And non-order customer data is still erased
    And no error is raised from the empty array

  @security
  Scenario: Redact does not expose which tables were affected in the response
    When Shopify sends POST /api/gdpr/customers-redact with a valid request
    Then the response body is empty (200 with no body)
    And internal table names and row counts are not disclosed in any response header
