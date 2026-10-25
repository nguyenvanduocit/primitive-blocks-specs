Feature: Bulk Operation Status Tracking
  As an app developer
  I want to track the status of bulk operations
  So that I know when they complete, fail, or can be cancelled

  Background:
    Given the app is configured with a valid Shopify API key and secret
    And a shop "test-store.myshopify.com" is installed with an active session token

  @happy
  Scenario: Check status of a created bulk operation
    Given a bulk_operations record exists with id "op-001" and status "created"
    When a GET request is sent to /api/bulk/status/op-001
    Then the response status is 200
    And the response body contains status "created"
    And the response body contains the shopify_operation_id
    And the response body contains the type field

  @happy
  Scenario: Check status of a running bulk operation
    Given a bulk_operations record exists with id "op-002" and status "running"
    When a GET request is sent to /api/bulk/status/op-002
    Then the response status is 200
    And the response body contains status "running"
    And started_at is present in the response

  @happy
  Scenario: Check status of a completed bulk operation
    Given a bulk_operations record exists with id "op-003" and status "completed"
    And the record has object_count 4521, file_size 892341, and result_url set
    When a GET request is sent to /api/bulk/status/op-003
    Then the response status is 200
    And the response body contains status "completed"
    And the response body contains object_count 4521
    And the response body contains file_size 892341
    And the response body does NOT contain the result_url (internal only)

  @happy
  Scenario: Check status of a failed bulk operation
    Given a bulk_operations record exists with id "op-004" and status "failed"
    And the record has error_code "TIMEOUT" and error_message set
    When a GET request is sent to /api/bulk/status/op-004
    Then the response status is 200
    And the response body contains status "failed"
    And the response body contains error_code "TIMEOUT"

  @happy
  Scenario: Cancel a running bulk operation
    Given a bulk_operations record exists with id "op-005" and status "running"
    And the shopify_operation_id is "gid://shopify/BulkOperation/789"
    When a POST request is sent to /api/bulk/cancel/op-005
    Then the app calls bulkOperationCancel mutation with id "gid://shopify/BulkOperation/789"
    And the response status is 200
    And the bulk_operations record status is updated to "cancelled"

  @happy
  Scenario: Status transitions from created to running
    Given a bulk_operations record exists with status "created"
    When Shopify sends BULK_OPERATIONS_FINISH webhook (status RUNNING is intermediate)
    And the app polls and sees status "RUNNING" from Shopify
    Then the bulk_operations record is updated with status "running"
    And started_at is set to the current time

  @happy
  Scenario: Status transitions from running to completed
    Given a bulk_operations record exists with status "running"
    When Shopify sends BULK_OPERATIONS_FINISH webhook with status "COMPLETED"
    Then the bulk_operations record status is updated to "completed"
    And completed_at is set to the completion timestamp from Shopify
    And result_url is set
    And object_count and file_size are set

  @happy
  Scenario: Status transitions from running to failed
    Given a bulk_operations record exists with status "running"
    When Shopify sends BULK_OPERATIONS_FINISH webhook with status "FAILED" and errorCode "ACCESS_DENIED"
    Then the bulk_operations record status is updated to "failed"
    And error_code is set to "ACCESS_DENIED"
    And completed_at is set

  @happy
  Scenario: Status transitions from running to cancelled via webhook
    Given a bulk_operations record exists with status "running"
    When Shopify sends BULK_OPERATIONS_FINISH webhook with status "CANCELLED"
    Then the bulk_operations record status is updated to "cancelled"
    And completed_at is set

  @error
  Scenario: Status check for non-existent operation
    When a GET request is sent to /api/bulk/status/non-existent-id
    Then the response status is 404
    And the response body contains error "operation_not_found"

  @error
  Scenario: Status check for operation belonging to different shop
    Given a bulk_operations record "op-006" belongs to shop "other-store.myshopify.com"
    When a GET request is sent to /api/bulk/status/op-006 with session token for "test-store.myshopify.com"
    Then the response status is 404
    And the response body contains error "operation_not_found"

  @error
  Scenario: Cancel a completed operation is rejected
    Given a bulk_operations record exists with id "op-007" and status "completed"
    When a POST request is sent to /api/bulk/cancel/op-007
    Then the response status is 409
    And the response body contains error "operation_not_cancellable"
    And the response body contains status "completed"
    And no Shopify API call is made

  @error
  Scenario: Cancel a failed operation is rejected
    Given a bulk_operations record exists with id "op-008" and status "failed"
    When a POST request is sent to /api/bulk/cancel/op-008
    Then the response status is 409
    And the response body contains error "operation_not_cancellable"

  @error
  Scenario: Webhook with invalid HMAC is rejected
    When Shopify sends POST /api/webhooks with topic "BULK_OPERATIONS_FINISH"
    And the X-Shopify-Hmac-Sha256 header is invalid
    Then the webhook is rejected with status 401
    And no bulk_operations record is updated

  @edge
  Scenario: Webhook for unknown shopify_operation_id is ignored silently
    When Shopify sends BULK_OPERATIONS_FINISH webhook with admin_graphql_api_id "gid://shopify/BulkOperation/999"
    And no bulk_operations record has shopify_operation_id matching "gid://shopify/BulkOperation/999"
    Then the response status is 200
    And no error is thrown

  @edge
  Scenario: Duplicate BULK_OPERATIONS_FINISH webhook is handled idempotently
    Given a bulk_operations record "op-009" has status "completed"
    When Shopify sends BULK_OPERATIONS_FINISH webhook for "op-009" again
    Then the response status is 200
    And the bulk_operations record is updated with the same final values
    And no duplicate events are emitted
