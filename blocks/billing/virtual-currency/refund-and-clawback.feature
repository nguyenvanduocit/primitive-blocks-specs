Feature: Refunds, revocations and clawback
  As an operator and as a player
  I want a store refund to take back what the purchase granted, no more than exists
  So that refunds do not become free currency and balances never go negative

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/catalog.json is loaded
    And the store payloads from fixtures/store-payloads.json are available as verified store facts
    And the clock is fixed at "2026-10-27T12:00:00Z"
    And "account-001" is signed in
    And the clawback rule is the minimum of the balance and the granted amount per currency

  @happy
  Scenario Outline: A refund takes back at most what the purchase granted
    # fixtures/money-cases.json clawback
    Given "account-001" bought "<purchase>" and was granted <granted>
    And the current balances are <balances>
    When the store refunds the purchase
    Then the clawback takes <take>
    And the unrecovered shortfall is <shortfall>
    And the balances become <after>
    And <entries> clawback entries with reason "virtual-currency.pack-refund" are written
    And no balance is negative

    Examples:
      | purchase       | granted           | balances                         | take                            | shortfall                       | after                        | entries |
      | gems_medium    | gems 550          | gems 550                         | gems 550                        | gems 0                          | gems 0                       | 1       |
      | gems_medium    | gems 550          | gems 200                         | gems 200                        | gems 350                        | gems 0                       | 1       |
      | gems_medium    | gems 550          | gems 0                           | gems 0                          | gems 550                        | gems 0                       | 0       |
      | gems_medium    | gems 550          | gems 900                         | gems 550                        | gems 0                          | gems 350                     | 1       |
      | gems_medium    | gems 1050         | gems 1050                        | gems 1050                       | gems 0                          | gems 0                       | 1       |
      | starter_bundle | gems 300, coins 5000, booster_shield 3 | gems 300, coins 1200, booster_shield 1 | gems 300, coins 1200, booster_shield 1 | gems 0, coins 3800, booster_shield 2 | gems 0, coins 0, booster_shield 0 | 3 |

  @happy
  Scenario: An Apple REFUND notification refunds the purchase and claws back
    Given "account-001" holds a verified purchase "gems_medium_purchase" that granted 550 "gems" and has 550 "gems"
    When the Apple notification "refund" arrives for the refunded transaction
    Then the server re-reads the transaction and finds revocationDate set
    And the purchase record has state "refunded", refunded_at "2026-10-26T08:00:00Z" and refund_reason "apple:0"
    And "account-001" has 0 "gems"
    And a "purchase_refunded" event with clawed_total 550 and shortfall_total 0 is written
    And on_purchase_state_changed fires for the transaction
    And the response is 200

  @happy
  Scenario: A Google voided purchase notification refunds the purchase
    Given "account-001" holds a verified Google purchase "google-token-0001" that granted 550 "gems" and has 200 "gems"
    When the Google notification "voided_full_refund" arrives with a valid push token
    Then the purchase record has state "refunded"
    And "account-001" has 0 "gems"
    And the shortfall of 350 "gems" is reported in the "purchase_refunded" event

  @edge
  Scenario: Apple REFUND_REVERSED reinstates what was taken, once
    # fixtures/money-cases.json reinstatement
    Given a refund of "gems_medium" took 200 "gems" and left a shortfall of 350
    When the Apple notification "refund_reversed" arrives and the transaction has no revocationDate
    Then the purchase record has state "verified" and no refunded_at
    And "account-001" has 200 "gems"
    And one reinstatement entry with reason "virtual-currency.pack-refund-reversed" is written
    When the same notification is delivered again
    Then no further entry is written

  @edge
  Scenario: A second refund after a reversal uses a new key
    Given a refund and a reversal already happened for the purchase
    When the store refunds the purchase again
    Then the clawback key ends with the cycle number 2
    And the clawback is computed from the current balance

  @edge
  Scenario: A duplicate notification changes nothing
    Given the Apple notification "refund" was processed
    When the same notificationUUID arrives again
    Then the answer is 200 and no entry is written
    And the store_notifications row is not duplicated

  @edge
  Scenario: Notifications that arrive out of order end in the store's real state
    Given the store state of the transaction is "not revoked"
    When the Apple notification "refund" is delivered late, after a reversal
    Then the server re-reads the transaction and finds no revocationDate
    And the purchase record stays "verified"
    And no clawback is written

  @edge
  Scenario: A declined refund request changes no state
    When the Apple notification "refund_declined" arrives
    Then the notification is "processed" and the purchase record is unchanged

  @edge
  Scenario: A refund of an external product changes the record and no balance
    Given "account-001" holds a verified purchase "season_premium_purchase"
    When the store refunds it
    Then the purchase record has state "refunded"
    And on_purchase_state_changed fires and purchase_record returns state "refunded" with refunded_at set
    And no ledger entry is written

  @security
  Scenario: A forged refund notification is rejected
    When an unsigned body is posted to POST /api/store/apple/notifications
    Then the response is 401 and nothing is changed
    When the Apple notification "wrong_bundle" is posted
    Then the response is 401 and nothing is changed
    When a Google push without a valid token posts "voided_full_refund"
    Then the response is 401 and nothing is changed

  @security
  Scenario: A validly signed refund for a purchase the store still shows as paid changes nothing
    Given the store state of "gems_medium_purchase" is "not revoked"
    When a validly signed Apple notification "refund" arrives for it
    Then the server re-reads the transaction and finds no revocationDate
    And the purchase record stays "verified"

  @edge
  Scenario Outline: Google push authentication checks the signed claims
    # fixtures/store-payloads.json google_push_auth_cases
    When a Google push arrives with email "<email>", email_verified "<verified>" and audience "<aud>"
    Then the response is <status>

    Examples:
      | email    | verified | aud                                                  | status |
      | push-sa  | true     | https://game.example.com/api/store/google/notifications | 200    |
      | other-sa | true     | https://game.example.com/api/store/google/notifications | 401    |
      | push-sa  | false    | https://game.example.com/api/store/google/notifications | 401    |
      | push-sa  | true     | https://elsewhere.example.com/hook                   | 401    |

  @edge
  Scenario: A notification for another package is acknowledged without action
    When the Google notification "other_package" arrives with a valid push token
    Then the response is 200
    And no purchase state changes and the event is logged

  @happy
  Scenario: The player sees a refund notice once, with exact amounts
    Given the Apple refund took 200 "gems" with a shortfall of 350 from "gems_medium"
    When "account-001" calls GET /api/wallet
    Then refund_notices lists the purchase with clawed gems 200 and shortfall gems 350
    When "account-001" posts POST /api/wallet/refund-notices/seen
    Then the next GET /api/wallet lists no refund notices

  @edge
  Scenario: Three refunds in the window put the account on review without stopping deliveries
    # fixtures/money-cases.json refund_review
    Given "account-001" has refunded purchases at "2026-09-01T09:00:00Z", "2026-10-20T09:00:00Z" and "2026-10-25T09:00:00Z"
    When "account-001" calls GET /api/shop/packs
    Then purchase_policy has purchases_enabled false and reason "review"
    And a purchase the store confirms for "account-001" is still verified and delivered

  @edge
  Scenario Outline: The review window counts refunds later than the boundary only
    Given "account-001" has refunded purchases at <times>
    When "account-001" calls GET /api/shop/packs
    Then the policy reason is <reason>

    Examples:
      | times                                                                       | reason |
      | "2026-09-01T09:00:00Z", "2026-10-20T09:00:00Z", "2026-10-25T09:00:00Z"        | review |
      | "2026-10-20T09:00:00Z", "2026-10-25T09:00:00Z"                                | none   |
      | "2026-04-29T12:00:00Z", "2026-10-20T09:00:00Z", "2026-10-25T09:00:00Z"        | none   |
      | "2026-04-30T12:00:00Z", "2026-10-20T09:00:00Z", "2026-10-25T09:00:00Z"        | none   |

  @edge
  Scenario: A refund after account erasure is recorded and claws back nothing
    Given "account-001" was erased and its purchase "gems_medium_purchase" is de-linked
    When the Apple notification "refund" arrives for that transaction
    Then the purchase record has state "refunded" and no account
    And no ledger entry is written

  @happy
  Scenario: A consumption request is answered with consent and the share spent
    # fixtures/money-cases.json consumption_percentage
    Given "account-001" consented to share consumption data
    And the purchase granted 1050 "gems" and 525 "gems" were spent since verification
    When the Apple notification "consumption_request" arrives
    Then the server calls PUT /inApps/v2/transactions/consumption/2000000100000001
    And the body has customerConsented true, deliveryStatus "DELIVERED", sampleContentProvided true and consumptionPercentage 50000
    And the notification is "processed"

  @edge
  Scenario: A consumption request without consent sends nothing
    Given "account-001" did not consent to share consumption data
    When the Apple notification "consumption_request" arrives
    Then no consumption call is made
    And the notification is "processed" and the decision is logged

  @edge
  Scenario Outline: The consumption percentage is a capped share in milliunits
    Given the purchase granted <granted> "gems" and <spent> were spent since verification
    Then the consumptionPercentage is <expected>

    Examples:
      | granted | spent | expected |
      | 1050    | 0     | 0        |
      | 1050    | 525   | 50000    |
      | 1050    | 1     | 95       |
      | 1050    | 2000  | 100000   |

  @edge
  Scenario: A fully consumed purchase can carry a decline preference when configured
    Given "CONSUMPTION_REFUND_PREFERENCE" is "decline_if_consumed"
    And all 1050 granted gems were spent
    When the consumption request is answered
    Then the body carries refundPreference "DECLINE"

  @edge
  Scenario: A refund an operator initiates for an unauthorized purchase does not count toward the review hold
    Given "account-001" has two store refunds in the window
    When an operator refunds a Google purchase of "account-001" with orders.refund and revoke true as "operator:unauthorized"
    And the Google voided notification arrives
    Then the purchase record has state "refunded" and refund_reason "operator:unauthorized"
    And the balance is clawed back as for any refund
    And "account-001" has purchases_enabled true because only two refunds count
