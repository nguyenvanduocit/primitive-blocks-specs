Feature: Bulk Result Processing
  As an app developer
  I want to download and process bulk operation JSONL results
  So that I can import large datasets efficiently with correct parent-child relationships

  Background:
    Given the app is configured with a valid Shopify API key and secret
    And a shop "test-store.myshopify.com" is installed with an active session token
    And a bulk_operations record "op-001" exists with status "completed" and a valid result_url

  @happy
  Scenario: Download and process completed bulk results
    When a GET request is sent to /api/bulk/results/op-001
    Then the app fetches the JSONL file from the result_url (server-side, not exposed to client)
    And the response status is 200
    And the response body contains "processedCount"
    And the response body contains "batchCount"
    And a "bulk.results_processed" event is emitted with processedCount and batchCount

  @happy
  Scenario: JSONL is parsed line by line (not loaded into memory all at once)
    Given the result JSONL file contains 5000 lines
    And BULK_RESULT_PROCESSING_BATCH_SIZE is 1000
    When a GET request is sent to /api/bulk/results/op-001
    Then the file is streamed and not fully buffered in memory
    And processing occurs in 5 batches of 1000 lines each
    And the processedCount in the response is 5000
    And the batchCount in the response is 5

  @happy
  Scenario: Flat objects (no __parentId) are processed correctly
    Given the result JSONL contains:
      """
      {"id":"gid://shopify/Product/1","title":"T-Shirt","vendor":"Acme"}
      {"id":"gid://shopify/Product/2","title":"Hoodie","vendor":"Acme"}
      {"id":"gid://shopify/Product/3","title":"Cap","vendor":"Acme"}
      """
    When the JSONL is parsed
    Then 3 root objects are produced with no children
    And each object has id, title, and vendor fields

  @happy
  Scenario: Nested objects with __parentId are grouped under their parent
    Given the result JSONL contains:
      """
      {"id":"gid://shopify/Product/1","title":"T-Shirt"}
      {"id":"gid://shopify/ProductVariant/10","price":"19.99","__parentId":"gid://shopify/Product/1"}
      {"id":"gid://shopify/ProductVariant/11","price":"24.99","__parentId":"gid://shopify/Product/1"}
      {"id":"gid://shopify/Product/2","title":"Hoodie"}
      {"id":"gid://shopify/ProductVariant/20","price":"49.99","__parentId":"gid://shopify/Product/2"}
      """
    When the JSONL is parsed with groupByParent
    Then 2 root objects are produced (Product/1 and Product/2)
    And Product/1 has 2 children (ProductVariant/10 and ProductVariant/11)
    And Product/2 has 1 child (ProductVariant/20)

  @happy
  Scenario: Multi-level nesting with __parentId
    Given the result JSONL contains products, variants, and metafields:
      """
      {"id":"gid://shopify/Product/1","title":"T-Shirt"}
      {"id":"gid://shopify/ProductVariant/10","sku":"TSHIRT-S","__parentId":"gid://shopify/Product/1"}
      {"id":"gid://shopify/Metafield/100","value":"organic","__parentId":"gid://shopify/ProductVariant/10"}
      """
    When the JSONL is parsed with groupByParent
    Then Product/1 has 1 child (ProductVariant/10)
    And ProductVariant/10 has 1 child (Metafield/100)

  @happy
  Scenario: Empty JSONL file (zero results) is handled gracefully
    Given the result JSONL file is empty (no lines)
    When a GET request is sent to /api/bulk/results/op-001
    Then the response status is 200
    And processedCount is 0
    And batchCount is 0
    And no error is thrown

  @happy
  Scenario: JSONL with blank lines in between is parsed correctly
    Given the result JSONL contains blank lines between records
    When the JSONL is parsed
    Then blank lines are skipped
    And only non-empty lines are counted in processedCount

  @happy
  Scenario: Last batch smaller than BULK_RESULT_PROCESSING_BATCH_SIZE is processed
    Given the result JSONL contains 2500 lines
    And BULK_RESULT_PROCESSING_BATCH_SIZE is 1000
    When a GET request is sent to /api/bulk/results/op-001
    Then processing occurs in 3 batches (1000 + 1000 + 500)
    And the processedCount is 2500
    And the batchCount is 3

  @error
  Scenario: Results requested for operation that is not completed
    Given a bulk_operations record "op-002" exists with status "running"
    When a GET request is sent to /api/bulk/results/op-002
    Then the response status is 409
    And the response body contains error "operation_not_completed"
    And the response body contains status "running"

  @error
  Scenario: Results requested for failed operation
    Given a bulk_operations record "op-003" exists with status "failed"
    When a GET request is sent to /api/bulk/results/op-003
    Then the response status is 409
    And the response body contains error "operation_not_completed"

  @error
  Scenario: Results requested for operation with expired result_url
    Given a bulk_operations record "op-004" exists with status "completed"
    And the result_url is null (expired after ~24 hours)
    When a GET request is sent to /api/bulk/results/op-004
    Then the response status is 410
    And the response body contains error "result_url_expired"

  @error
  Scenario: result_url download fails (GCS error)
    Given the result_url returns a non-200 HTTP status
    When a GET request is sent to /api/bulk/results/op-001
    Then the response status is 502
    And the response body contains error "result_download_failed"

  @error
  Scenario: Results requested for operation belonging to different shop
    Given a bulk_operations record "op-005" belongs to "other-store.myshopify.com"
    When a GET request is sent to /api/bulk/results/op-005 with session token for "test-store.myshopify.com"
    Then the response status is 404
    And the response body contains error "operation_not_found"

  @security
  Scenario: Result URL is never returned to the client
    When a GET request is sent to /api/bulk/results/op-001
    Then the response body does NOT contain the result_url field
    And the result_url is only used server-side to stream the JSONL

  @security
  Scenario: JSONL content is not logged
    Given the result JSONL contains sensitive merchant data
    When a GET request is sent to /api/bulk/results/op-001
    Then no log entry contains raw JSONL line content
    And only aggregate counts (processedCount, batchCount) are logged
