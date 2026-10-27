Feature: Premium unlock and refund
  As a player who buys the premium track
  I want every premium reward I already earned to be claimable at once, and a clear outcome if the store refunds me
  So that buying late costs me nothing and a refund is handled by stated rules

  Background:
    Given the app is configured for tenant "tenant-001"
    And the season from fixtures/season-2026-10.json is published
    And the players from fixtures/progress-states.json exist
    And the purchase records from fixtures/purchase-records.json exist in the purchase contract
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario: Buying premium at tier 7 makes the premium rewards of tiers 1 to 7 claimable
    Given I am authenticated as "acc-cy"
    When I send POST /api/season-pass/premium with { "season_id": "season-2026-10", "store_transaction_id": "txn-2001" }
    Then the response status is 200
    And premium_state is "active" with premium_purchase_ref "txn-2001"
    And already_active is false and claimable_premium_count is 7
    And no ledger call is made by the activation
    And a season_pass_premium_activated event is fired with claimable_premium_count 7 and tier 7
    When I send a claim-all request
    Then 8 cells are "granted": free tier 7 and premium tiers 1 to 7

  @happy
  Scenario: Premium rewards of later tiers become claimable as the tiers are reached
    Given "acc-cy" activated premium with "txn-2001"
    And all claimable cells of "acc-cy" were claimed
    When "acc-cy" reaches total_xp 1400
    Then the claimable cells are free tier 8 (hint-pack 2) and premium tier 8 (trail-oct 1)

  @happy
  Scenario: The offer lists both tracks in full before any purchase
    Given I am authenticated as "acc-ann"
    When I send GET /api/season-pass/seasons/season-2026-10/premium-offer
    Then tiers holds ten entries, one per tier 1 to 10, each with its free reward or null and its premium reward
    And the free rewards are those of tiers 1, 3, 4, 5, 7, 8 and 10 and null at tiers 2, 6 and 9
    And the premium reward is present at every tier 1 to 10
    And repeat has free null and premium gem 25
    And earned_count is 5
    And sale_open is true
    And unclaimed_policy is "auto_claim" and refund_policy is "keep_claimed"
    And the response carries no price

  @edge
  Scenario Outline: The offer states the fate of unclaimed rewards under each policy
    Given I am authenticated as "acc-ann"
    And UNCLAIMED_AT_END is "<policy>"
    When I send GET /api/season-pass/seasons/season-2026-10/premium-offer
    Then unclaimed_policy is "<policy>"

    Examples:
      | policy     |
      | auto_claim |
      | forfeit    |

  @edge
  Scenario: The offer carries no value figure by default
    Given PREMIUM_VALUE_FIGURE is false
    And I am authenticated as "acc-ann"
    When I send GET /api/season-pass/seasons/season-2026-10/premium-offer
    Then the response has no value_figure and no field named worth, value, save or reference_price

  @edge
  Scenario: An enabled value figure is computed from prices the shop actually charges
    Given PREMIUM_VALUE_FIGURE is true
    And billing.virtual-currency sells gem at its lowest price of 0.01 USD per unit and coin at 0.001 USD per unit
    And I am authenticated as "acc-ann"
    When I send GET /api/season-pass/seasons/season-2026-10/premium-offer
    Then value_figure is 1.20 USD for the premium rewards of tiers 1 to 10 that the shop sells
    And the basis lists 70 gem and 500 coin
    And the unsold rewards frame-oct, trail-oct and avatar-oct are listed as not sold separately
    And the repeat rewards are excluded from the figure
    And no reference price or discount percentage is returned

  @edge
  Scenario: An item that is not priced by the shop adds nothing to the figure
    Given PREMIUM_VALUE_FIGURE is true
    And billing.virtual-currency sells no gem and no coin
    When I send GET /api/season-pass/seasons/season-2026-10/premium-offer
    Then value_figure is absent

  @edge
  Scenario Outline: The sale closes in the last PREMIUM_SALE_MIN_REMAINING_SECONDS of the season
    Given I am authenticated as "acc-ann"
    And the clock is fixed at "<instant>"
    When I send GET /api/season-pass/seasons/season-2026-10/premium-offer
    Then sale_open is <sale_open>

    Examples:
      | instant              | sale_open | note                              |
      | 2026-10-31T22:59:59Z | true      | 3601 seconds remain               |
      | 2026-10-31T23:00:00Z | true      | exactly 3600 seconds remain       |
      | 2026-10-31T23:00:01Z | false     | 3599 seconds remain               |

  @edge
  Scenario: A premium holder is not offered the sale again
    Given I am authenticated as "acc-bob"
    When I send GET /api/season-pass/seasons/season-2026-10/premium-offer
    Then sale_open is false

  @edge
  Scenario: Confirming the same purchase twice is idempotent
    Given I am authenticated as "acc-cy"
    And "acc-cy" activated premium with "txn-2001"
    When I send the same premium confirmation again
    Then the response status is 200 and already_active is true
    And no field of season_progress changed

  @edge
  Scenario Outline: A record that cannot unlock premium is rejected and changes nothing
    Given I am authenticated as "<account>"
    When I send POST /api/season-pass/premium with { "season_id": "season-2026-10", "store_transaction_id": "<txn>" }
    Then the response status is <status>
    And the error is "<error>"
    And premium_state is still "none"

    Examples:
      | account | txn      | status | error                     | note                                        |
      | acc-cy  | txn-1001 | 403    | purchase_account_mismatch | the record names acc-bob                    |
      | acc-cy  | txn-9001 | 403    | purchase_account_mismatch | the record's account was erased (null)      |
      | acc-cy  | txn-4001 | 422    | purchase_product_mismatch | a currency pack, not the pass               |
      | acc-ann | txn-5001 | 409    | purchase_outside_season   | purchased_at is before any season window    |
      | acc-cy  | txn-9002 | 409    | purchase_not_valid        | state pending                               |
      | acc-ann | txn-7001 | 409    | purchase_not_valid        | state refunded                              |
      | acc-cy  | txn-0000 | 404    | purchase_not_found        | unknown transaction                         |

  @edge
  Scenario: A second paid transaction for an account that already has premium is reported, not swallowed
    Given a verified record "txn-1002" for "acc-bob" exists with product "season_pass_premium" and purchased_at "2026-10-21T11:00:00Z"
    And I am authenticated as "acc-bob"
    When I send POST /api/season-pass/premium with { "season_id": "season-2026-10", "store_transaction_id": "txn-1002" }
    Then the response status is 409
    And the error is "premium_already_active"
    And an operations alert is raised for the duplicate purchase
    And premium_purchase_ref is still "txn-1001"

  @edge
  Scenario: A purchase recorded after the claim window is still delivered, even under forfeit
    Given UNCLAIMED_AT_END is "forfeit"
    And I am authenticated as "acc-ann"
    And the clock is fixed at "2026-11-01T00:30:00Z"
    And the record "txn-6001" was purchased at "2026-10-31T23:59:50Z" and recorded at "2026-11-01T00:30:00Z"
    When the purchase contract fires on_purchase_state_changed for "txn-6001"
    Then premium_state of "acc-ann" in "season-2026-10" is "active"
    And settlement grants the premium cells of tiers 1 to 5 with claim_source "season_end_auto"
    And the grants are gem 10, coin 200, gem 10, frame-oct 1 and gem 15
    And the free cells of tiers 3, 4 and 5 stay unclaimed

  @edge
  Scenario: A refund revokes premium and keeps claimed rewards by default
    Given "acc-eve" has premium through "txn-3001" with premium tiers 1 and 2 claimed
    And REFUND_POLICY is "keep_claimed"
    When the purchase record "txn-3001" becomes "refunded" and the purchase contract fires on_purchase_state_changed
    Then premium_state of "acc-eve" is "revoked" and premium_revoked_at is set
    And the claim rows for premium tiers 1 and 2 stay "granted"
    And the ledger balances of "acc-eve" are unchanged: coin 500, gem 4
    And premium tier 3 (reached, unclaimed) is rejected with "premium_required"
    And the free track of "acc-eve" is unaffected

  @edge
  Scenario: Claw back takes only what the balance holds
    Given "acc-eve" has premium through "txn-3001" with premium tiers 1 and 2 claimed
    And REFUND_POLICY is "claw_back_unspent"
    When the purchase record "txn-3001" becomes "refunded" and the purchase contract fires on_purchase_state_changed
    Then the ledger receives spend(acc-eve, gem, 4, "season-pass.refund-clawback") with key "season-pass:acc-eve:season-2026-10:premium:1:clawback"
    And the ledger receives spend(acc-eve, coin, 200, "season-pass.refund-clawback") with key "season-pass:acc-eve:season-2026-10:premium:2:clawback"
    And clawed_back_amount is 4 for premium tier 1 and 200 for premium tier 2
    And the balances are coin 300 and gem 0, never negative

  @edge
  Scenario: A claw back that races a spend retries with the same key
    Given REFUND_POLICY is "claw_back_unspent"
    And "acc-eve" spends 3 gem between the balance read and the claw back
    When the claw back of premium tier 1 runs
    Then the ledger answers "insufficient_balance" once
    And the balance is read again and the spend is retried with the same key "season-pass:acc-eve:season-2026-10:premium:1:clawback"
    And the balance never goes below zero

  @edge
  Scenario Outline: A reversed refund restores premium, and the claw back under that policy
    Given "acc-eve" was refunded under REFUND_POLICY "<policy>" and premium tiers 1 and 2 were claimed
    When the purchase record "txn-3001" returns to "verified" and the purchase contract fires on_purchase_state_changed
    Then premium_state of "acc-eve" is "active"
    And premium tier 3 is claimable again
    And <restore>

    Examples:
      | policy             | restore                                                                                                                    |
      | keep_claimed       | no ledger call is made                                                                                                     |
      | claw_back_unspent  | grant(acc-eve, gem, 4, "season-pass.refund-restore") and grant(acc-eve, coin, 200, "season-pass.refund-restore") are made |

  @edge
  Scenario: A missed refund callback is caught by the recheck job
    Given "acc-eve" has premium through "txn-3001"
    And the record "txn-3001" becomes "refunded" and no callback is delivered
    When the recheck job runs after PREMIUM_RECHECK_SECONDS
    Then premium_state of "acc-eve" is "revoked"
    And a later claim of premium tier 3 is rejected with "premium_required"

  @edge
  Scenario: A refund signal for a transaction this block never saw does nothing
    When the purchase contract fires on_purchase_state_changed for "txn-0000"
    Then no season_progress row changes
    And no ledger call is made

  @security
  Scenario: One transaction cannot unlock two accounts or two seasons
    Given "acc-cy" activated premium with "txn-2001"
    When "acc-bob" sends POST /api/season-pass/premium with { "season_id": "season-2026-10", "store_transaction_id": "txn-2001" }
    Then the response status is 403
    And the error is "purchase_account_mismatch"
    And exactly one season_progress row has premium_purchase_ref "txn-2001"

  @security
  Scenario: The activation call reads the purchase record and verifies no receipt
    Given I am authenticated as "acc-cy"
    When I send POST /api/season-pass/premium with { "season_id": "season-2026-10", "store_transaction_id": "txn-2001", "receipt": "opaque-proof" }
    Then the response status is 422
    And the error is "invalid_request"
    And no call is made to any store API
