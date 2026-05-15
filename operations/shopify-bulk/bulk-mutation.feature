Feature: Bulk Mutation Operations
  As an app developer
  I want to submit bulk GraphQL mutations for large datasets
  So that I can update thousands of records in a single async operation

  Background:
    Given the app is configured with a valid Shopify API key and secret
    And a shop "test-store.myshopify.com" is installed with an active session token
    And no bulk mutation is currently running for this shop

  @happy
  Scenario: Submit a valid bulk mutation through the full staged upload flow
    Given a mutation string "mutation ($input: ProductInput!) { productUpdate(input: $input) { product { id } } }"
    And a variables array with 500 product update objects
    When a POST request is sent to /api/bulk/mutation with the mutation and variables
    Then the app calls stagedUploadsCreate to get a staged upload URL
    And the app serializes the variables to JSONL (one JSON object per line)
    And the app uploads the JSONL file to the staged URL via multipart POST
    And the app calls bulkOperationRunMutation with the mutation string and stagedUploadPath
    Then the response status is 202
    And the response body contains "operationId"
    And a bulk_operations record is created with type "mutation" and status "created"
    And a "bulk.started" event is emitted

  @happy
  Scenario: Bulk mutation JSONL is correctly serialized
    Given a variables array containing:
      | id                              | price  |
      | gid://shopify/ProductVariant/10 | 19.99  |
      | gid://shopify/ProductVariant/11 | 24.99  |
      | gid://shopify/ProductVariant/12 | 29.99  |
    When the app serializes the variables to JSONL
    Then the JSONL has exactly 3 lines
    And each line is a valid JSON object
    And no line contains a newline character within the JSON

  @happy
  Scenario: Bulk mutation completes via BULK_OPERATIONS_FINISH webhook
    Given a bulk mutation was submitted and returned operationId "op-003"
    And the shopify_operation_id is "gid://shopify/BulkOperation/456"
    When Shopify sends POST /api/webhooks with topic "BULK_OPERATIONS_FINISH"
    And the webhook payload contains admin_graphql_api_id "gid://shopify/BulkOperation/456"
    And the X-Shopify-Hmac-Sha256 header is valid
    Then the response status is 200
    And the bulk_operations record is updated with status "completed"
    And a "bulk.completed" event is emitted

  @happy
  Scenario: stagedUploadPath is correctly extracted from resourceUrl
    Given Shopify returns a staged target with resourceUrl "https://storage.googleapis.com/shopify/bulk-mutations/abc123/bulk-variables.jsonl"
    When the app extracts the stagedUploadPath
    Then the stagedUploadPath is "bulk-mutations/abc123/bulk-variables.jsonl"

  @error
  Scenario: Reject bulk mutation when another mutation is already running
    Given a bulk_operations record exists with type "mutation" and status "running"
    When a POST request is sent to /api/bulk/mutation with any mutation and variables
    Then the response status is 409
    And the response body contains error "bulk_operation_in_progress"
    And the response body contains type "mutation"
    And no stagedUploadsCreate call is made

  @error
  Scenario: Reject bulk mutation with missing variables
    When a POST request is sent to /api/bulk/mutation with only a mutation string and no variables
    Then the response status is 400
    And the response body contains error "missing_mutation_or_variables"

  @error
  Scenario: Reject bulk mutation with empty variables array
    When a POST request is sent to /api/bulk/mutation with mutation string and empty variables array
    Then the response status is 400
    And the response body contains error "missing_mutation_or_variables"

  @error
  Scenario: Handle stagedUploadsCreate failure
    Given Shopify returns userErrors on stagedUploadsCreate
    When a POST request is sent to /api/bulk/mutation with valid mutation and variables
    Then the response status is 422
    And the response body contains error "staged_upload_failed"
    And no JSONL is uploaded

  @error
  Scenario: Handle staged upload PUT failure
    Given Shopify returns a valid staged upload URL
    And the PUT to the staged URL returns a non-2xx status
    When a POST request is sent to /api/bulk/mutation with valid mutation and variables
    Then the response status is 502
    And the response body contains error "staged_upload_upload_failed"
    And no bulkOperationRunMutation call is made

  @error
  Scenario: Handle Shopify rejecting the bulk mutation
    Given stagedUploadsCreate and the upload both succeed
    And Shopify returns userErrors on bulkOperationRunMutation
    When a POST request is sent to /api/bulk/mutation
    Then the response status is 422
    And the response body contains error "shopify_rejected_mutation"
    And no bulk_operations record is created

  @edge
  Scenario: Concurrent bulk mutation allowed alongside running query
    Given a bulk_operations record exists with type "query" and status "running"
    When a POST request is sent to /api/bulk/mutation with valid mutation and variables
    Then the response status is 202
    And a new bulk_operations record is created with type "mutation"

  @edge
  Scenario: Large variables array is serialized correctly to JSONL
    Given a variables array with 10000 product update objects
    When a POST request is sent to /api/bulk/mutation
    Then the JSONL file has exactly 10000 lines
    And the file is uploaded to the staged URL in a single multipart POST
