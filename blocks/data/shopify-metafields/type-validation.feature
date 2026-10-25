Feature: Metafield Type Validation
  As the app backend
  I want to validate metafield values against their registered types before sending to Shopify
  So that type errors are caught locally with clear messages instead of cryptic Shopify API errors

  Background:
    Given the app is configured with namespace "myapp"
    And the following definitions are registered:
      | key            | type                   | ownerType |
      | score          | number_integer         | PRODUCT   |
      | price          | number_decimal         | PRODUCT   |
      | is_featured    | boolean                | PRODUCT   |
      | launch_date    | date                   | PRODUCT   |
      | last_synced    | date_time              | PRODUCT   |
      | metadata       | json                   | PRODUCT   |
      | website        | url                    | PRODUCT   |
      | brand_color    | color                  | PRODUCT   |
      | label          | single_line_text_field | PRODUCT   |
      | tags_list      | list.single_line_text_field | PRODUCT |
      | scores_list    | list.number_integer    | PRODUCT   |
    And a valid session token is present for "test-store.myshopify.com"
    And product GID is "gid://shopify/Product/123456789"

  # --- number_integer ---

  @happy
  Scenario: Valid integer value passes validation
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "score", "value": "42" }
    Then validation passes for type "number_integer"
    And a metafieldsSet mutation is sent to Shopify
    And the response status is 200

  @error
  Scenario: String value rejected for integer type
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "score", "value": "hello" }
    Then the response status is 400
    And the response body contains error "type_mismatch"
    And the response body contains expected type "number_integer"
    And no Shopify API call is made

  @error
  Scenario: Decimal value rejected for integer type
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "score", "value": "3.14" }
    Then the response status is 400
    And the response body contains error "type_mismatch"
    And the response body contains expected type "number_integer"
    And no Shopify API call is made

  # --- number_decimal ---

  @happy
  Scenario: Valid decimal value passes validation
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "price", "value": "19.99" }
    Then validation passes for type "number_decimal"
    And a metafieldsSet mutation is sent to Shopify
    And the response status is 200

  @error
  Scenario: Non-numeric string rejected for decimal type
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "price", "value": "not-a-number" }
    Then the response status is 400
    And the response body contains error "type_mismatch"
    And no Shopify API call is made

  # --- boolean ---

  @happy
  Scenario: Valid boolean "true" passes validation
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "is_featured", "value": "true" }
    Then validation passes for type "boolean"
    And the response status is 200

  @happy
  Scenario: Valid boolean "false" passes validation
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "is_featured", "value": "false" }
    Then validation passes for type "boolean"
    And the response status is 200

  @error
  Scenario: Non-boolean string rejected for boolean type
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "is_featured", "value": "yes" }
    Then the response status is 400
    And the response body contains error "type_mismatch"
    And the response body indicates expected "true" or "false"
    And no Shopify API call is made

  # --- date ---

  @happy
  Scenario: Valid ISO date passes validation
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "launch_date", "value": "2025-06-15" }
    Then validation passes for type "date"
    And the response status is 200

  @error
  Scenario: Non-ISO date string rejected for date type
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "launch_date", "value": "June 15 2025" }
    Then the response status is 400
    And the response body contains error "type_mismatch"
    And the response body indicates expected format "YYYY-MM-DD"
    And no Shopify API call is made

  # --- json ---

  @happy
  Scenario: Valid JSON object passes validation
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "metadata", "value": "{\"color\":\"red\",\"size\":\"L\"}" }
    Then validation passes for type "json"
    And a metafieldsSet mutation is sent to Shopify
    And the response status is 200

  @happy
  Scenario: Valid JSON array passes validation
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "metadata", "value": "[1,2,3]" }
    Then validation passes for type "json"
    And the response status is 200

  @error
  Scenario: Invalid JSON syntax rejected for json type
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "metadata", "value": "{color: red}" }
    Then the response status is 400
    And the response body contains error "type_mismatch"
    And the response body indicates "Invalid JSON"
    And no Shopify API call is made

  @error
  Scenario: Plain string rejected for json type
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "metadata", "value": "just a string" }
    Then the response status is 400
    And the response body contains error "type_mismatch"
    And no Shopify API call is made

  # --- url ---

  @happy
  Scenario: Valid URL passes validation
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "website", "value": "https://example.com/product" }
    Then validation passes for type "url"
    And the response status is 200

  @error
  Scenario: Invalid URL rejected for url type
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "website", "value": "not-a-url" }
    Then the response status is 400
    And the response body contains error "type_mismatch"
    And no Shopify API call is made

  # --- color ---

  @happy
  Scenario: Valid hex color passes validation
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "brand_color", "value": "#FF5733" }
    Then validation passes for type "color"
    And the response status is 200

  @error
  Scenario: Non-hex color string rejected for color type
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "brand_color", "value": "red" }
    Then the response status is 400
    And the response body contains error "type_mismatch"
    And the response body indicates expected format "#rrggbb"
    And no Shopify API call is made

  # --- list types ---

  @happy
  Scenario: Valid JSON array passes validation for list type
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "tags_list", "value": "[\"sale\",\"new\",\"featured\"]" }
    Then validation passes for type "list.single_line_text_field"
    And a metafieldsSet mutation is sent to Shopify with the JSON array as value
    And the response status is 200

  @error
  Scenario: Non-array value rejected for list type
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "tags_list", "value": "sale" }
    Then the response status is 400
    And the response body contains error "type_mismatch"
    And the response body indicates list type requires a JSON array
    And no Shopify API call is made

  @error
  Scenario: Invalid JSON array rejected for list type
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body: { "namespace": "myapp", "key": "scores_list", "value": "[1, 2," }
    Then the response status is 400
    And the response body contains error "type_mismatch"
    And no Shopify API call is made

  # --- batch type validation ---

  @error
  Scenario: Batch write fails if any entry has a type mismatch
    When POST /api/metafields/batch is called with 3 entries where the second has type mismatch:
      | key         | type                   | value     | valid? |
      | label       | single_line_text_field | My Label  | yes    |
      | score       | number_integer         | not-a-num | NO     |
      | is_featured | boolean                | true      | yes    |
    Then the response status is 400
    And the response body contains error "type_mismatch" for key "score"
    And no Shopify API call is made for any of the 3 entries
