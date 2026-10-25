Feature: Bulk Query Operations
  As an app developer
  I want to submit bulk GraphQL queries for large datasets
  So that I can export thousands of records without hitting rate limits

  Background:
    Given the app is configured with a valid Shopify API key and secret
    And a shop "test-store.myshopify.com" is installed with an active session token
    And no bulk operations are currently running for this shop

  @happy
  Scenario: Submit a valid bulk query and receive operation ID
    When a POST request is sent to /api/bulk/query with:
      | query | { products { edges { node { id title } } } } |
    Then the response status is 202
    And the response body contains "operationId"
    And the response body contains "shopifyOperationId"
    And the response body contains status "created"
    And a bulk_operations record is created with type "query" and status "created"
    And a "bulk.started" event is emitted

  @happy
  Scenario: Bulk query completes via BULK_OPERATIONS_FINISH webhook
    Given a bulk query was submitted and returned operationId "op-001"
    And the shopify_operation_id is "gid://shopify/BulkOperation/123"
    When Shopify sends POST /api/webhooks with topic "BULK_OPERATIONS_FINISH"
    And the webhook payload contains admin_graphql_api_id "gid://shopify/BulkOperation/123"
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And the app queries Shopify for the final operation status
    And the bulk_operations record is updated with status "completed"
    And the result_url is stored in the bulk_operations record
    And the object_count is stored in the bulk_operations record
    And a "bulk.completed" event is emitted

  @happy
  Scenario: Bulk query completes via polling
    Given BULK_PREFER_WEBHOOK is false
    And a bulk query was submitted for shop "test-store.myshopify.com"
    When the polling loop queries currentBulkOperation
    And Shopify returns status "RUNNING" for the first 3 polls
    And Shopify returns status "COMPLETED" with url and objectCount on poll 4
    Then the bulk_operations record is updated with status "completed"
    And result_url and object_count are stored
    And a "bulk.completed" event is emitted

  @happy
  Scenario: Submit a bulk query for products with nested variants
    When a POST request is sent to /api/bulk/query with:
      | query | { products { edges { node { id title variants { edges { node { id price sku } } } } } } } |
    Then the response status is 202
    And the bulk_operations record stores the full query text
    And a shopifyOperationId is returned matching the Shopify GID format

  @error
  Scenario: Reject bulk query when another query is already running
    Given a bulk_operations record exists with type "query" and status "running"
    When a POST request is sent to /api/bulk/query with any query
    Then the response status is 409
    And the response body contains error "bulk_operation_in_progress"
    And the response body contains type "query"
    And no new Shopify API call is made

  @error
  Scenario: Reject bulk query when another query is in created state
    Given a bulk_operations record exists with type "query" and status "created"
    When a POST request is sent to /api/bulk/query with any query
    Then the response status is 409
    And the response body contains error "bulk_operation_in_progress"

  @error
  Scenario: Reject bulk query with missing query field
    When a POST request is sent to /api/bulk/query with an empty body
    Then the response status is 400
    And the response body contains error "missing_query"

  @error
  Scenario: Handle Shopify rejecting the bulk query
    Given Shopify returns userErrors on bulkOperationRunQuery
    When a POST request is sent to /api/bulk/query with a syntactically invalid query
    Then the response status is 422
    And the response body contains error "shopify_rejected_query"
    And no bulk_operations record is created

  @error
  Scenario: Bulk query fails with an error from Shopify
    Given a bulk query was submitted and returned operationId "op-002"
    When Shopify sends BULK_OPERATIONS_FINISH webhook with status "FAILED"
    And the errorCode is "TIMEOUT"
    Then the bulk_operations record is updated with status "failed"
    And the error_code "TIMEOUT" is stored
    And a "bulk.failed" event is emitted

  @edge
  Scenario: Concurrent bulk query allowed for different types
    Given a bulk_operations record exists with type "query" and status "running"
    When a POST request is sent to /api/bulk/mutation with a valid mutation and variables
    Then the response status is 202
    And a new bulk_operations record is created with type "mutation"

  @edge
  Scenario: Poll timeout marks operation as failed
    Given BULK_PREFER_WEBHOOK is false
    And BULK_MAX_POLL_ATTEMPTS is 3
    And a bulk query was submitted for "test-store.myshopify.com"
    When the polling loop runs 3 times and Shopify always returns status "RUNNING"
    Then the bulk_operations record is updated with status "failed"
    And the error_code is "poll_timeout"
    And a "bulk.failed" event is emitted
