Feature: Buying a consumable currency pack
  As a player who bought a pack in the App Store or Google Play
  I want the server to verify the purchase and credit it exactly once
  So that I get what I paid for and nobody gets currency without paying

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/catalog.json is loaded
    And the store payloads from fixtures/store-payloads.json are available as verified store facts
    And the clock is fixed at "2026-10-27T12:00:00Z"
    And "account-001" is signed in and has an empty wallet
    And "FIRST_PURCHASE_BONUS_SCOPE" is "product"
    And the host purchase policy for "account-001" enables purchases

  @happy
  Scenario: A verified Apple purchase credits the pack once and tells the client to finish
    When "account-001" submits the Apple transaction "gems_medium_purchase" to POST /api/purchases/verify
    Then the response is 200 with state "verified" and beneficiary "self"
    And the granted lines are gems 1050
    And "first_purchase_bonus_applied" is true
    And "finish_transaction" is true
    And "account-001" has 1050 "gems"
    And the purchase record has store_transaction_id "2000000100000001", environment "production", price_micros 4990000, price_currency "USD" and price_source "apple_payload"
    And the ledger entry has reason "virtual-currency.pack-purchase" and a purchase id
    And a "purchase_verified" event and a "currency_grant" event with the entry id are written

  @happy
  Scenario: A verified Google purchase credits the pack, then the server consumes it
    When "account-001" submits the Google purchase "gems_medium_purchased" with product "acme_gems_medium" and client price 4990000 "USD"
    Then the response is 200 with state "verified" and "finish_transaction" false
    And "account-001" has 1050 "gems"
    And the server called products.consume for token "google-token-0001" after the grant committed
    And the purchase record has store_finalized_at set, price_source "client_report" and store_order_id "GPA.0000-0000-0000-00001"

  @happy
  Scenario: A promo-code purchase without an order id is recorded by its purchase token
    When "account-001" submits the Google purchase "gems_medium_promo_no_order_id"
    Then the purchase record has store_transaction_id "google-token-0006" and no store_order_id
    And "account-001" has 1050 "gems"

  @edge
  Scenario: Submitting the same proof again returns the original result
    Given "account-001" submitted "gems_medium_purchase" and received 1050 "gems"
    When "account-001" submits the Apple transaction "gems_medium_purchase" again
    Then the response is 200 with the same purchase id and the same granted lines
    And "account-001" still has 1050 "gems"
    And the store was not called again

  @edge
  Scenario: Ten concurrent submissions credit the pack once
    When 10 requests submit the Apple transaction "gems_medium_purchase" at the same time
    Then every response carries the same purchase id
    And "account-001" has 1050 "gems"
    And the ledger holds 1 entry with reason "virtual-currency.pack-purchase"

  @happy
  Scenario Outline: Contents and the first-purchase bonus follow the catalog
    # fixtures/money-cases.json contents_and_bonus
    Given the scope is "<scope>" and the account has prior purchases "<prior>"
    When "account-001" buys "<product>"
    Then the credited gems are <gems>
    And "first_purchase_bonus_applied" is <bonus>

    Examples:
      | scope   | prior                      | product    | gems | bonus |
      | product |                            | gems_medium | 1050 | true  |
      | product | gems_medium verified       | gems_medium | 550  | false |
      | product | gems_medium verified       | gems_large  | 2600 | true  |
      | account | gems_medium verified       | gems_large  | 1400 | false |
      | product | gems_medium refunded       | gems_medium | 550  | false |
      | product | gems_medium pending        | gems_medium | 1050 | true  |

  @happy
  Scenario: The starter bundle credits three currencies and then disappears from the shop
    When "account-001" buys "starter_bundle"
    Then "account-001" has 300 "gems", 5000 "coins" and 3 "booster_shield"
    And "first_purchase_bonus_applied" is false
    When "account-001" calls GET /api/shop/packs
    Then "starter_bundle" is not in the list

  @edge
  Scenario: A paid repeat of the starter bundle is delivered in full
    Given "account-001" already bought "starter_bundle"
    When a second transaction for "acme_starter_bundle" is verified for "account-001"
    Then the full bundle is credited again
    And a "starter_repeat" log entry is written
    And the shop still hides the starter bundle

  @happy
  Scenario: The shop sends amounts and no price
    When "account-001" calls GET /api/shop/packs?platform=apple
    Then every pack lists contents as amounts with bonus and first-purchase bonus
    And no field of the response is a price, a price string or a currency symbol
    And "first_purchase_bonus_amount" is null for a product the account has already bought
    And the response carries "store_account_token" and "server_now"
    And the store account token equals the account id when "STORE_ACCOUNT_TOKEN_SOURCE" is "account_id"

  @edge
  Scenario: An external product is recorded without a grant
    When "account-001" submits the Apple transaction "season_premium_purchase"
    Then the response is 200 with state "verified"
    And the purchase record has product_code "season_premium" and product_kind "consumable"
    And no ledger entry is written
    And on_purchase_state_changed fires for "2000000100000010"
    And purchase_record("2000000100000010") returns state "verified" and account "account-001"

  @edge
  Scenario Outline: Authentic transactions the server will not deliver are recorded as rejected
    # fixtures/store-payloads.json expected_plans
    When "account-001" submits the Apple transaction "<payload>"
    Then the response is 409 "purchase_rejected" with reason "<reason>" and "finish_transaction" true
    And no ledger entry is written
    And the purchase record has state "rejected"

    Examples:
      | payload                 | reason               |
      | unknown_product         | unknown_product      |
      | gems_medium_wrong_type  | type_mismatch        |
      | gems_medium_quantity_2  | quantity_unsupported |

  @edge
  Scenario: A Google purchase with two line items is rejected and refunded, never consumed
    When "account-001" submits the Google purchase "two_line_items"
    Then the response is 409 "purchase_rejected" with reason "line_items_unsupported"
    And the server did not call products.consume or products.acknowledge for "google-token-0007"
    And the server called orders.refund for order "GPA.0000-0000-0000-00007" with revoke true

  @security
  Scenario: A transaction from another app fails verification and writes nothing
    When "account-001" submits the Apple transaction "other_bundle"
    Then the response is 422 "proof_invalid"
    And no purchase record exists for "2000000100000009"
    And no ledger entry is written
    And the response does not say which check failed

  @security
  Scenario: A tampered or foreign proof is rejected
    When "account-001" submits an Apple JWS whose payload was altered after signing
    Then the response is 422 "proof_invalid"
    When "account-001" submits an Apple JWS signed by a key outside the pinned Apple roots
    Then the response is 422 "proof_invalid"
    When "account-001" submits the Google token "made-up-token" for product "acme_gems_medium"
    Then the response is 422 "proof_invalid"
    And no ledger entry is written

  @edge
  Scenario Outline: Sandbox and test purchases follow configuration
    Given "<flag>" is <value>
    When "account-001" submits "<payload>"
    Then the outcome is "<outcome>"

    Examples:
      | flag                         | value | payload                                  | outcome                                  |
      | APPLE_ACCEPT_SANDBOX         | true  | apple_transactions.gems_medium_sandbox   | verified with environment sandbox        |
      | APPLE_ACCEPT_SANDBOX         | false | apple_transactions.gems_medium_sandbox   | rejected environment_not_accepted        |
      | GOOGLE_ACCEPT_TEST_PURCHASES | true  | google_purchases.gems_medium_test        | verified with environment sandbox        |
      | GOOGLE_ACCEPT_TEST_PURCHASES | false | google_purchases.gems_medium_test        | rejected environment_not_accepted        |

  @security
  Scenario: The grant goes to the owner of the account token, not to the submitter
    Given the Apple transaction "gems_medium_purchase" carries the token of "account-001"
    When "account-002" submits it
    Then the response to "account-002" has beneficiary "other_account" and no balances
    And "account-001" has 1050 "gems"
    And "account-002" has 0 "gems"

  @security
  Scenario: A token that belongs to no account is rejected
    When "account-001" submits the Apple transaction "gems_medium_unknown_token"
    Then the response is 409 "purchase_rejected" with reason "account_unknown"
    And no ledger entry is written

  @edge
  Scenario: A tokenless purchase binds to the submitting session
    Given "ACCOUNT_TOKEN_MISSING_POLICY" is "bind_to_session"
    When "account-001" submits the Apple transaction "gems_medium_no_token"
    Then "account-001" has 1050 "gems"
    And the purchase record has account_binding "session"

  @edge
  Scenario: A tokenless purchase seen first by notification waits as unclaimed
    When the Apple notification "one_time_charge" arrives for the tokenless transaction "gems_medium_no_token"
    Then the purchase record has state "unclaimed" and no account
    And no ledger entry is written
    When "account-001" submits the Apple transaction "gems_medium_no_token"
    Then the purchase record has state "verified" and account "account-001"
    And "account-001" has 1050 "gems"

  @edge
  Scenario: The store API is unavailable during verification
    Given the App Store Server API answers 503
    When "account-001" submits the Apple transaction "gems_medium_purchase"
    Then the response is 503 "store_unavailable" with no finish instruction
    And no purchase record exists
    When the API recovers and the client submits again
    Then "account-001" has 1050 "gems"

  @security
  Scenario: Verification is rate limited per account
    Given "VERIFY_RATE_LIMIT_PER_MINUTE" is 30
    When "account-001" sends 31 verify requests within a minute
    Then the 31st answers 429 "rate_limited"
    And requests for an already recorded transaction cause no store call

  @edge
  Scenario: The catalog check fails at startup on inconsistent rows
    # fixtures/catalog.json expected.startup_check_errors
    When the catalog contains a content row that names a missing currency
    Then startup fails with "unknown_currency_in_contents"
    When two products share one store product id
    Then startup fails with "duplicate_store_product_id"

  @security
  Scenario: With no purchase policy registered real-money spending is off
    Given the host registered no purchase policy
    When "account-001" calls GET /api/shop/packs
    Then purchase_policy has purchases_enabled false and reason "age"
    And POST /api/purchases/intent answers allowed false with reason "policy"
    When the store confirms the Apple transaction "gems_medium_purchase" for "account-001" anyway
    Then the purchase is verified and delivered

  @edge
  Scenario: A direct purchase for an exact price is listed beside the packs
    When "account-001" calls GET /api/shop/packs?platform=apple&codes=shield_direct
    Then the response lists "shield_direct" with empty contents
    And it uses the same intent, confirmation and verification path as a pack

  @edge
  Scenario: A product that sells a random reward carries its odds link
    When "account-001" calls GET /api/shop/packs?platform=apple&codes=chest_key
    Then the product has "random_reward" true and the "odds_url" "https://game.example.com/odds/chest"
    And a catalog row with random_reward true and no odds_url is rejected at startup with "random_reward_without_odds_url"
    And a ledger pack with random_reward true is rejected with "random_reward_on_ledger_pack"

  @edge
  Scenario: The catalog allows one purchasable hard currency
    Given "MAX_PURCHASABLE_CURRENCIES" is 1
    When the packs of the catalog grant two distinct hard currencies
    Then startup fails with "too_many_purchasable_currencies"
    And no ledger operation converts one currency into another
