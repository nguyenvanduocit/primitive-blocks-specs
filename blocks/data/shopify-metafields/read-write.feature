Feature: Metafield Read and Write
  As an embedded app
  I want to read and write metafield values on Shopify resources
  So that custom data persists in Shopify alongside the resource

  Background:
    Given the app is configured with namespace "myapp"
    And the following definitions are registered in metafield_definitions:
      | key             | type                   | ownerType |
      | warranty_period | single_line_text_field | PRODUCT   |
      | internal_score  | number_integer         | PRODUCT   |
      | delivery_notes  | multi_line_text_field  | ORDER     |
    And a shop "test-store.myshopify.com" is active with a valid session token
    And product GID is "gid://shopify/Product/123456789"
    And order GID is "gid://shopify/Order/987654321"

  @happy
  Scenario: Read a single metafield for a product
    Given Shopify has value "2 years" for product 123456789, namespace "myapp", key "warranty_period"
    When GET /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with query params namespace=myapp&key=warranty_period
    Then a GraphQL query is sent to Shopify for product(id) metafield(namespace, key)
    And the response status is 200
    And the response body contains:
      """
      { "metafields": [{ "namespace": "myapp", "key": "warranty_period", "value": "2 years", "type": "single_line_text_field" }] }
      """

  @happy
  Scenario: Read all metafields for a resource (namespace scoped)
    Given Shopify has 2 metafields in namespace "myapp" on product 123456789
    When GET /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with query param namespace=myapp
    Then the GraphQL query fetches metafields(first: 50, namespace: "myapp")
    And the response status is 200
    And the response body contains 2 metafields

  @happy
  Scenario: Read all metafields for a resource (no namespace filter)
    Given Shopify has 3 metafields across different namespaces on product 123456789
    When GET /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      without a namespace query param
    Then the GraphQL query fetches metafields(first: 50) with no namespace filter
    And the response status is 200
    And the response body contains 3 metafields

  @happy
  Scenario: Write a single metafield value to a product
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body:
      """
      { "namespace": "myapp", "key": "warranty_period", "value": "3 years" }
      """
    Then the app looks up type "single_line_text_field" from metafield_definitions for this shop
    And validates "3 years" is a valid single_line_text_field value
    And a metafieldsSet mutation is sent to Shopify with:
      | ownerId   | gid://shopify/Product/123456789 |
      | namespace | myapp                           |
      | key       | warranty_period                 |
      | type      | single_line_text_field          |
      | value     | 3 years                         |
    And the response status is 200
    And the response body contains the updated metafield
    And a "metafield.set" event is emitted

  @happy
  Scenario: Write an integer metafield value to a product
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body:
      """
      { "namespace": "myapp", "key": "internal_score", "value": "42" }
      """
    Then the app looks up type "number_integer" from metafield_definitions
    And validates "42" is a valid number_integer value
    And a metafieldsSet mutation is sent with type "number_integer" and value "42"
    And the response status is 200

  @happy
  Scenario: Write a metafield to an order
    When POST /api/metafields/ORDER/gid%3A%2F%2Fshopify%2FOrder%2F987654321 is called
      with body:
      """
      { "namespace": "myapp", "key": "delivery_notes", "value": "Leave at door" }
      """
    Then the app looks up type "multi_line_text_field" from metafield_definitions for ORDER owner type
    And a metafieldsSet mutation is sent to Shopify for the order resource
    And the response status is 200

  @happy
  Scenario: Delete a metafield value
    Given Shopify has a metafield with GID "gid://shopify/Metafield/111" on product 123456789
      for namespace "myapp" and key "warranty_period"
    When DELETE /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789/myapp/warranty_period is called
    Then a GraphQL query fetches the metafield GID from Shopify
    And a metafieldDelete mutation is sent with input.id "gid://shopify/Metafield/111"
    And the response status is 204
    And a "metafield.deleted" event is emitted

  @happy
  Scenario: Batch write up to 25 metafields in one call
    When POST /api/metafields/batch is called with 5 metafield entries for different products
    Then each entry's value is validated against its registered type
    And a single metafieldsSet mutation is sent with all 5 metafields
    And the response status is 200
    And the response body contains all 5 written metafields

  @error
  Scenario: Write fails when definition not registered
    When POST /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789 is called
      with body:
      """
      { "namespace": "myapp", "key": "unknown_field", "value": "anything" }
      """
    Then the response status is 404
    And the response body contains error "definition_not_found"
    And no Shopify API call is made

  @error
  Scenario: Delete fails when metafield does not exist on the resource
    Given Shopify returns null for the metafield query on product 123456789
    When DELETE /api/metafields/PRODUCT/gid%3A%2F%2Fshopify%2FProduct%2F123456789/myapp/warranty_period is called
    Then the response status is 404
    And the response body contains error "metafield_not_found"

  @error
  Scenario: Batch write rejected when more than 25 metafields
    When POST /api/metafields/batch is called with 26 metafield entries
    Then the response status is 400
    And the response body contains error "batch_size_exceeded"
    And no Shopify API call is made

  @error
  Scenario: Batch write rejected with empty array
    When POST /api/metafields/batch is called with an empty metafields array
    Then the response status is 400
    And the response body contains error "metafields_required"

  @error
  Scenario: Read with unsupported owner type
    When GET /api/metafields/UNKNOWN_TYPE/gid%3A%2F%2Fshopify%2FUnknown%2F1 is called
    Then the response status is 400
    And the response body contains error "unsupported_owner_type"

  @edge
  Scenario: Tenant isolation — shop A cannot read shop B's definition types
    Given shop A has definition for key "warranty_period" with type "single_line_text_field"
    And shop B has definition for key "warranty_period" with type "number_integer"
    When shop A's session token is used to write value "hello" for key "warranty_period"
    Then the type is looked up from shop A's metafield_definitions record only
    And the value "hello" is validated as single_line_text_field (not number_integer)
    And shop B's definitions are never queried
