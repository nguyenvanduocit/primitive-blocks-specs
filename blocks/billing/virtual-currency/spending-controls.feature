Feature: Spending controls and real-money legibility
  As a player
  I want to see what a purchase costs in real money, confirm it deliberately, and cap my own spending
  So that I never pay more than I meant to and can always learn what my gems cost

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/catalog.json is loaded
    And the store product details on the device come from "device_store_prices" in fixtures/catalog.json
    And the clock is fixed at "2026-10-27T12:00:00Z"
    And "account-001" is signed in
    And "SPEND_LIMIT_PERIOD_SECONDS" is 2592000 and "SPEND_LIMIT_COOL_OFF_SECONDS" is 86400
    And "PURCHASE_CONFIRMATION" is "always"

  @happy
  Scenario: Every pack card shows the store's price string
    When "account-001" opens the shop
    Then the card for "gems_medium" shows "$4.99" beside the Buy control
    And the string is the display price returned by the store
    And no price is computed, rounded or cached from an earlier session
    And no pack is preselected or highlighted by default

  @edge
  Scenario: The shop shows no prices when the store cannot load them
    Given the store cannot return product details
    When "account-001" opens the shop
    Then the cards show no Buy control
    And the text says prices could not be loaded and offers Try again

  @happy
  Scenario: A confirmation step precedes the store sheet
    When "account-001" taps the pack "gems_medium"
    Then the intent check runs and returns allowed true
    And the confirmation sheet shows 500 gems, 50 bonus and 500 first-purchase bonus as separate numbers
    And the Buy button reads "Buy for $4.99"
    And "Not now" has the same size and weight as Buy
    And the store sheet has not opened yet
    When "account-001" taps "Buy for $4.99"
    Then the store sheet opens with the account token
    And the events "purchase_confirm_shown", "purchase_confirmed" and "purchase_started" are written in that order

  @happy
  Scenario: Not now sends nothing to the store
    When "account-001" taps the pack "gems_medium" and then "Not now"
    Then no store purchase call is made
    And the event "purchase_confirm_dismissed" is written
    And the shop is shown again with nothing selected

  @edge
  Scenario: With confirmation off the intent check still runs
    Given "PURCHASE_CONFIRMATION" is "off"
    When "account-001" taps Buy on the pack "gems_medium"
    Then the intent check runs first
    And the store sheet opens without a confirmation sheet

  @edge
  Scenario: A guest is told the purchase stays on this device's profile
    Given "account-001" is a guest account
    When "account-001" opens the confirmation sheet for "gems_medium"
    Then the sheet says the purchase stays on this profile and offers Sign in
    And Buy is not disabled

  @happy
  Scenario: The receipt and the history show what was charged
    Given "account-001" bought "gems_medium" and the store reported 4990000 "USD"
    When the receipt is shown
    Then it lists "1,050 gems: 500 + 50 bonus + 500 first purchase bonus"
    And it shows "Charged: $4.99" and a reference for support
    When "account-001" opens the spending screen
    Then the history row shows the pack, the date, the credited lines and "Charged $4.99"

  @edge
  Scenario: A purchase with no known price says to see the store receipt
    Given a recovered Google purchase has no reported price
    When the receipt is shown
    Then it says "See your store receipt for the amount charged"
    And the purchase counts as zero toward a spend limit

  @happy
  Scenario Outline: A gem price shows an approximate real-money value at the undiscounted rate
    # fixtures/catalog.json approx_money_cases
    Given the reference pack for "gems" is "gems_small" with base amount 100
    When an item costing <amount> "gems" is shown with the reference price <ref>
    Then the text reads "about <expected>"

    Examples:
      | amount | ref                     | expected |
      | 120    | 990000 micros USD       | $1.19    |
      | 100    | 990000 micros USD       | $0.99    |
      | 1      | 990000 micros USD       | $0.01    |
      | 120    | 150000000 micros JPY    | ¥180     |

  @edge
  Scenario: Without a reference price the value is hidden and Pack prices is offered
    Given the reference pack price has not loaded
    When an item costing 120 "gems" is shown
    Then no money value is shown
    And a "Pack prices" link opens the shop
    And the event "price_info_opened" is written when it is used

  @edge
  Scenario: A soft currency never shows a real-money value
    When an item costing 500 "coins" is shown
    Then no money value and no Pack prices link are shown

  @happy
  Scenario: The insufficient-balance sheet states the shortfall and routes to the shop
    Given "account-001" has 40 "gems"
    When a feature needs 160 "gems" and the spend is rejected with "insufficient_balance"
    Then the sheet says "You need 120 more gems" and shows the balance 40
    And it shows "about $1.19" for the missing 120 gems
    And "See packs" and "Not now" have equal weight
    When "account-001" taps "See packs"
    Then the shop opens with packs whose gems contents cover 120 marked "Covers what you need"
    And no pack is preselected
    And the events "insufficient_balance_shown" and "insufficient_balance_routed" are written

  @edge
  Scenario: The shop never opens by itself
    When the app starts, a level ends, or a session ends
    Then the shop and the insufficient-balance sheet stay closed
    And they open only after a player action

  @edge
  Scenario Outline: The intent check applies the spend limit
    # fixtures/money-cases.json spend_limit.check
    Given the limit is 20000000 micros USD and the counted purchases are <purchases>
    When the intent check runs for a price of <candidate>
    Then the answer is <answer>

    Examples:
      | purchases                                           | candidate        | answer                                                          |
      | verified 4990000 and verified 4990000               | 4990000 USD      | allowed with 5030000 remaining                                  |
      | verified 9990000 and verified 7010000               | 4990000 USD      | limit_reached with 3000000 remaining                            |
      | verified 15010000                                   | 4990000 USD      | allowed with 0 remaining                                        |
      | none                                                | 4990000 EUR      | limit_currency_mismatch                                         |
      | refunded 15010000                                   | 4990000 USD      | allowed with 15010000 remaining                                 |
      | pending 15010000                                    | 4990000 USD      | allowed with 0 remaining                                        |
      | unknown price                                       | 4990000 USD      | allowed with 15010000 remaining                                 |

  @edge
  Scenario: next_room_at is the first instant the candidate fits, not when the oldest purchase leaves
    # fixtures/money-cases.json spend_limit.check, ids two_purchases_must_leave and tie_leaves_together
    Given the limit is 20000000 micros USD
    And counted purchases of 3000000 at "2026-10-10T09:00:00Z", 4000000 at "2026-10-12T09:00:00Z" and 8000000 at "2026-10-20T09:00:00Z"
    When the intent check runs for 9990000 USD
    Then the answer is limit_reached with 5000000 remaining
    And next_room_at is "2026-11-11T09:00:00Z"
    And at "2026-11-09T09:00:00Z" when only the first purchase has left the candidate still does not fit

  @edge
  Scenario: Purchases that leave at the same instant leave together
    Given the limit is 20000000 micros USD
    And counted purchases of 4000000 and 4000000 both at "2026-10-12T09:00:00Z" and 8000000 at "2026-10-20T09:00:00Z"
    When the intent check runs for 9990000 USD
    Then next_room_at is "2026-11-11T09:00:00Z"

  @edge
  Scenario: A price above the limit never fits
    Given the limit is 20000000 micros USD
    When the intent check runs for 25000000 USD
    Then the answer is limit_reached
    And next_room_at is null
    And the pack card says the pack is above the limit and shows no time

  @edge
  Scenario: A purchase exactly one period old is not counted
    Given the limit is 20000000 micros USD
    And purchases at "2026-09-27T12:00:00Z" for 9990000 USD and at "2026-09-27T12:00:01Z" for 5000000 USD
    When the intent check runs for 4990000 USD
    Then the answer is allowed with 10010000 remaining

  @happy
  Scenario: Setting a first limit and lowering a limit apply at once
    Given "account-001" has no limit
    When "account-001" sets a limit of 10000000 USD
    Then the limit in force is 10000000 USD and nothing is pending
    When "account-001" lowers it to 5000000 USD
    Then the limit in force is 5000000 USD at once

  @security
  Scenario: Raising, changing the currency of and removing a limit wait out the cool-off
    # fixtures/money-cases.json spend_limit.change
    Given "account-001" has a limit of 20000000 USD
    When "account-001" raises it to 50000000 USD
    Then the limit in force is still 20000000 USD
    And a pending change takes effect at "2026-10-28T12:00:00Z"
    When "account-001" asks to remove the limit
    Then the pending change is a removal taking effect at "2026-10-28T12:00:00Z"
    When "account-001" changes the limit currency to EUR
    Then the pending change is 20000000 EUR taking effect at "2026-10-28T12:00:00Z"

  @security
  Scenario: A pending change takes effect only after the cool-off by the server clock
    Given "account-001" has a limit of 20000000 USD and a pending raise to 50000000 USD effective at "2026-10-28T12:00:00Z"
    When the limit is read at "2026-10-28T11:59:59Z"
    Then the limit in force is 20000000 USD
    When the limit is read at "2026-10-28T12:00:00Z"
    Then the limit in force is 50000000 USD
    When the limit is read at "2026-10-29T12:00:00Z"
    Then the limit in force is still 50000000 USD

  @edge
  Scenario: A new request restarts the cool-off and lowering clears a pending raise
    Given "account-001" has a limit of 20000000 USD and a pending raise to 50000000 USD effective at "2026-10-28T12:00:00Z"
    And the clock is "2026-10-27T18:00:00Z"
    When "account-001" requests a raise to 60000000 USD
    Then the pending change is 60000000 USD effective at "2026-10-28T18:00:00Z"
    When "account-001" lowers the limit to 10000000 USD
    Then the limit in force is 10000000 USD and nothing is pending

  @edge
  Scenario: The player can cancel a pending change
    Given "account-001" has a pending raise
    When "account-001" calls DELETE /api/spend-limit/pending
    Then nothing is pending and the limit in force is unchanged

  @edge
  Scenario: A changed store currency pauses buying until the limit is set again
    Given "account-001" has a limit of 20000000 USD
    When the store reports prices in EUR
    Then the intent check answers "limit_currency_mismatch"
    And the spending screen says the limit is in USD and the store now charges in EUR
    And the event "purchase_blocked" with reason "limit_currency_mismatch" is written

  @security
  Scenario: A purchase made outside the shop is delivered and counted
    Given "account-001" has a limit of 5000000 USD and nothing counted
    When the store confirms a purchase of "gems_medium" for 4990000 USD that did not pass the intent check
    Then "account-001" receives the pack
    And the purchase counts toward the limit
    And the next intent check for 4990000 USD answers "limit_reached"

  @security
  Scenario: Price under-reporting by a modified client is a documented residual risk
    Given a modified client reports a price of 1 USD to the intent check for a pack that costs 4990000 USD
    When the purchase completes through the store
    Then the recorded price for an Apple purchase is the payload price
    And for a Google purchase the recorded price is the client's report with price_source "client_report"
    And the spec states the limit is a self-protection control and not an anti-fraud control

  @security
  Scenario: A parental gate precedes the intent check and any limit change
    Given purchase_policy for "account-001" has parental_gate_required true
    When "account-001" taps a pack
    Then the parental gate is shown before any intent call
    When the gate is failed or dismissed
    Then no request is sent and the shop is shown again
    When "account-001" tries to raise the limit
    Then the gate is shown first

  @edge
  Scenario: Purchases disabled by policy keep the shop visible with the reason
    Given purchase_policy for "account-001" has purchases_enabled false with reason "age"
    When "account-001" opens the shop
    Then the cards are visible and Buy is disabled with the text "Purchases are off for this profile"
    And POST /api/purchases/intent answers allowed false with reason "policy"

  @edge
  Scenario: A countdown appears only when it is real and allowed
    Given the starter bundle has a window ending at "2026-10-28T12:00:00Z"
    And countdown_offers_allowed is true
    When the shop is open at "2026-10-27T12:00:00Z" by the server clock with a device clock 2 hours ahead
    Then the card shows a time left of 24 hours counted from server_now
    Given countdown_offers_allowed is false
    Then the offer is shown without any countdown
