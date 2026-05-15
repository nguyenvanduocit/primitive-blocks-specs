Feature: Webhook Registration
  As the app backend
  I want to register webhook subscriptions with Shopify after a shop installs
  So that Shopify delivers real-time event notifications to my endpoint

  Background:
    Given the app is configured with API secret "test-api-secret"
    And the app URL is "https://myapp.example.com"
    And WEBHOOK_TOPICS is ["ORDERS_CREATE", "PRODUCTS_UPDATE", "APP_UNINSTALLED"]
    And WEBHOOK_PATH is "/api/webhooks"
    And a shop "example.myshopify.com" with id "shop-001" has just completed OAuth install

  @happy
  Scenario: Register all configured topics after install
    When registerWebhooks("shop-001") is called
    Then the app calls webhookSubscriptionCreate mutation for topic "ORDERS_CREATE"
    And the app calls webhookSubscriptionCreate mutation for topic "PRODUCTS_UPDATE"
    And the app calls webhookSubscriptionCreate mutation for topic "APP_UNINSTALLED"
    And each mutation uses callbackUrl "https://myapp.example.com/api/webhooks"
    And 3 rows exist in webhook_subscriptions for shop "shop-001"
    And each row has active = true
    And each row stores the graphql_id returned by Shopify

  @happy
  Scenario: Re-register updates existing subscription record
    Given a webhook_subscriptions row already exists for shop "shop-001" and topic "ORDERS_CREATE"
    And the callback_url has changed to "https://myapp.example.com/api/webhooks"
    When registerWebhooks("shop-001") is called
    Then the app calls webhookSubscriptionCreate for topic "ORDERS_CREATE"
    And the existing webhook_subscriptions row is updated (not duplicated)
    And callback_url and graphql_id are updated
    And active is set to true

  @happy
  Scenario: Sync adds missing topics
    Given webhook_subscriptions contains only "APP_UNINSTALLED" for shop "shop-001"
    And WEBHOOK_TOPICS now includes "ORDERS_CREATE" and "PRODUCTS_UPDATE"
    When syncWebhooks("shop-001") is called
    Then webhookSubscriptionCreate is called for "ORDERS_CREATE"
    And webhookSubscriptionCreate is called for "PRODUCTS_UPDATE"
    And 3 active subscriptions exist for shop "shop-001"

  @happy
  Scenario: Sync deactivates stale topics removed from config
    Given webhook_subscriptions contains "ORDERS_CREATE", "PRODUCTS_UPDATE", "CUSTOMERS_CREATE" for shop "shop-001"
    And WEBHOOK_TOPICS no longer includes "CUSTOMERS_CREATE"
    When syncWebhooks("shop-001") is called
    Then the "CUSTOMERS_CREATE" subscription row has active = false
    And the "ORDERS_CREATE" and "PRODUCTS_UPDATE" subscriptions remain active

  @error
  Scenario: Registration continues when one topic returns a GraphQL user error
    When registerWebhooks("shop-001") is called
    And the webhookSubscriptionCreate mutation for "ORDERS_CREATE" returns a userErrors array
    Then the error is logged for "ORDERS_CREATE"
    And registration continues for "PRODUCTS_UPDATE" and "APP_UNINSTALLED"
    And those 2 topics are stored in webhook_subscriptions
    And no exception is thrown to the caller

  @error
  Scenario: Registration logs and continues when GraphQL call throws a network error
    When registerWebhooks("shop-001") is called
    And the GraphQL call for "PRODUCTS_UPDATE" throws a network error
    Then the error is logged for "PRODUCTS_UPDATE"
    And registration continues for remaining topics
    And no exception is thrown to the caller

  @edge
  Scenario: Register single mandatory topic APP_UNINSTALLED when WEBHOOK_TOPICS is empty
    Given WEBHOOK_TOPICS defaults to ["APP_UNINSTALLED"]
    When registerWebhooks("shop-001") is called
    Then exactly 1 webhookSubscriptionCreate mutation is called
    And 1 subscription row exists for shop "shop-001" with topic "APP_UNINSTALLED"

  @edge
  Scenario: Registration is idempotent when called twice
    When registerWebhooks("shop-001") is called a first time
    And registerWebhooks("shop-001") is called a second time
    Then no duplicate rows exist in webhook_subscriptions
    And the UNIQUE(shop_id, topic) constraint is satisfied
    And each topic has exactly 1 active subscription
