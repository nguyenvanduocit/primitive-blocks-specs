Feature: Metafield Definition Sync
  As an app developer
  I want to register metafield definitions with Shopify on install
  So that my app's custom fields are available on Shopify resources

  Background:
    Given the app is configured with namespace "myapp"
    And METAFIELD_DEFINITIONS contains:
      | key              | name             | type                    | ownerType |
      | warranty_period  | Warranty Period  | single_line_text_field  | PRODUCT   |
      | internal_score   | Internal Score   | number_integer          | PRODUCT   |
      | delivery_notes   | Delivery Notes   | multi_line_text_field   | ORDER     |
    And METAFIELD_PIN_TO_ADMIN is true
    And a shop "test-store.myshopify.com" is installed with session token auth

  @happy
  Scenario: Sync definitions on app install
    When POST /api/metafields/sync-definitions is called
    Then a metafieldDefinitionCreate mutation is sent to Shopify for each definition
    And each mutation includes namespace "myapp", key, name, type, ownerType, and pin: true
    And the response body contains synced count 3
    And 3 records are inserted into metafield_definitions with synced_at set
    And each record stores the shopify_gid returned by Shopify
    And a "metafield.synced" event is emitted with count 3

  @happy
  Scenario: Sync adds a new definition when config grows
    Given 2 definitions are already synced (warranty_period and internal_score for PRODUCT)
    And METAFIELD_DEFINITIONS now includes a new definition: cost_price (number_decimal, PRODUCT)
    When POST /api/metafields/sync-definitions is called
    Then a metafieldDefinitionCreate mutation is sent only for cost_price
    And the new record is inserted into metafield_definitions
    And the 2 existing records are not duplicated (upsert on conflict)
    And the response body contains synced count 3

  @happy
  Scenario: Sync handles definition that already exists in Shopify
    Given "warranty_period" definition was previously registered in Shopify
    And Shopify returns a TAKEN userError for that definition
    When POST /api/metafields/sync-definitions is called
    Then the TAKEN error is treated as success (definition already exists)
    And the local metafield_definitions record is still upserted with synced_at updated
    And no error is returned to the caller

  @happy
  Scenario: Sync with empty METAFIELD_DEFINITIONS config
    Given METAFIELD_DEFINITIONS is an empty array
    When POST /api/metafields/sync-definitions is called
    Then no Shopify mutations are sent
    And the response body contains synced count 0

  @happy
  Scenario: Re-sync updates synced_at timestamp
    Given all definitions are already synced
    When POST /api/metafields/sync-definitions is called again
    Then all metafield_definitions records have synced_at updated to now
    And no duplicate records are created

  @error
  Scenario: Sync fails when session token is missing
    When POST /api/metafields/sync-definitions is called without Authorization header
    Then the response status is 401
    And the response body contains error "missing_token"
    And no Shopify mutations are sent

  @error
  Scenario: Sync continues after non-TAKEN Shopify error on one definition
    Given Shopify returns a non-TAKEN userError for "internal_score" definition
    When POST /api/metafields/sync-definitions is called
    Then the error for "internal_score" is logged as a warning
    And sync continues for the remaining definitions
    And the response still returns a count for successfully synced definitions
