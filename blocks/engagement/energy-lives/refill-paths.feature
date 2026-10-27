Feature: Refill paths
  As a player who is out of points
  I want to refill by currency, by a rewarded ad, by a gift or with a boost
  And I want to see the price first and be charged once

  Background:
    Given the app is configured for tenant "tenant-001"
    And the meters, offers and settings from fixtures/meter-config.json exist
    And the ledger of billing.virtual-currency is a fake with the balances of fixtures/meter-config.json
    And I am authenticated as "acct-0001" holding 25 gems
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And meter "energy" is stored with value 2 and anchor_at "2026-10-21T11:50:00Z"

  @happy
  Scenario: Refill to full is priced on the missing points and charged once
    When I send GET /api/energy/offers?meter_code=energy
    Then offer "refill-full" has units 3, cost 6, currency "gems" and no blocked reason
    When I send POST /api/energy/refills with refill_id "r1", offer_code "refill-full" and expected_cost 6
    Then the response status is 200
    And the ledger received spend of 6 gems with reason "energy-lives.refill" and key "energy-lives:acct-0001:refill:r1"
    And the meter has value 5 and the response balance is 19
    And an energy_refilled event with source "currency" is written
    When I send the same request at "2026-10-21T12:00:01Z"
    Then the response has replayed true and balance 19
    And the ledger has exactly one spend for key "energy-lives:acct-0001:refill:r1"
    And fixtures/api-cases.json case "refill-to-full" matches

  @edge
  Scenario: A price above what was shown is refused without a charge
    When I send POST /api/energy/refills with refill_id "r2", offer_code "refill-full" and expected_cost 4
    Then the response status is 409 and the error is "price_changed" with a quote of cost 6
    And the ledger received no spend

  @edge
  Scenario: Nothing is charged at the cap
    Given meter "energy" is stored with value 5 and anchor_at "2026-10-21T04:00:00Z"
    When I send POST /api/energy/refills with refill_id "r3", offer_code "refill-full" and expected_cost 0
    Then the response status is 409 and the error is "already_full"
    And the ledger received no spend

  @edge
  Scenario: An insufficient balance leaves the meter unchanged
    Given I hold 1 gem
    When I send POST /api/energy/refills with refill_id "r4", offer_code "refill-full" and expected_cost 6
    Then the response status is 409 and the error is "insufficient_balance"
    And the entry for "r4" has status "rejected" and the meter value is still 2

  @edge
  Scenario: A crash between the ledger spend and the credit is repaired on the next read
    Given the credit step fails after the ledger spend applied
    When I send POST /api/energy/refills with refill_id "r5", offer_code "refill-full" and expected_cost 6
    Then the response status is 503 and the entry for "r5" has status "pending"
    When I send GET /api/energy at "2026-10-21T12:00:01Z"
    Then the meter has value 5 and the entry for "r5" has status "applied"
    And the ledger has exactly one spend for key "energy-lives:acct-0001:refill:r5"
    And fixtures/api-cases.json case "refill-crash-after-spend" matches

  @edge
  Scenario: A fixed-price offer that does not fit is blocked
    Given meter "energy" is stored with value 5 and anchor_at "2026-10-21T04:00:00Z"
    When I send GET /api/energy/offers?meter_code=energy
    Then offer "refill-one" is blocked with "already_full"
    Given meter "energy" is stored with value 4 and anchor_at "2026-10-21T11:40:00Z"
    Then offer "refill-one" is available with cost 3

  @happy
  Scenario: A verified ad callback grants one point once
    When the ad route receives the callback "ad-valid" of fixtures/meter-config.json
    Then grantEnergy is called with amount 1, reason "energy-lives.ad-refill" and key "energy-lives:acct-0001:ad:0123456789ABCDEF0123456789ABCDEF"
    And the meter has value 3
    When the same callback arrives again
    Then the result is the original and the meter still has value 3
    And fixtures/api-cases.json case "ad-reward-grants-one-unit-once" matches

  @security
  Scenario: A callback with a bad signature or an unknown account grants nothing
    When the ad route receives the callback "ad-forged-signature"
    Then nothing is granted and the reason is "signature_invalid"
    When the ad route receives the callback "ad-unknown-user"
    Then nothing is granted and the reason is "unknown_account"

  @edge
  Scenario: The daily ad limit is five
    Given meter "energy" is stored with value 0 and anchor_at "2026-10-21T12:00:00Z"
    When five verified callbacks with different transaction ids arrive on the same day_key
    Then each grants 1 and the meter has value 5
    When a sixth verified callback arrives
    Then it is refused with "daily_limit" and the meter has value 5
    And fixtures/api-cases.json case "ad-daily-limit" matches

  @edge
  Scenario: A grant above the ceiling reports what did not fit
    Given meter "energy" is stored with value 5 and anchor_at "2026-10-21T04:00:00Z"
    When daily-streak grants 8 with key "daily-streak:acct-0001:2026-10-21"
    Then applied_amount is 5 and unapplied_amount is 3 and the value is 10
    When the same key is granted again
    Then the original result is returned and the value is still 10

  @edge
  Scenario: Boosts stack by adding time
    Given meter "energy" has boost_ends_at "2026-10-21T12:30:00Z"
    When a grant of a 3600 second boost arrives with key "event-calendar:acct-0001:evt-1:boost"
    Then boost_ends_at is "2026-10-21T13:30:00Z"

  @edge
  Scenario: A boost that would exceed the remaining-time cap is applied in part
    Given meter "energy" has boost_ends_at "2026-10-22T11:36:40Z"
    When a grant of a 3600 second boost arrives
    Then applied_seconds is 1400 and unapplied_seconds is 2200 and boost_ends_at is "2026-10-22T12:00:00Z"

  @happy
  Scenario: A bought boost stacks and is charged each time
    When I buy offer "boost-1h" with refill_id "rb1" and expected_cost 12
    Then boost_ends_at is "2026-10-21T13:00:00Z" and the balance is 13
    When I buy offer "boost-1h" again with refill_id "rb2" at "2026-10-21T12:00:01Z"
    Then boost_ends_at is "2026-10-21T14:00:00Z"
    And a second buy attempt that would not fit under 86400 seconds is refused with "boost_stack_limit" before any charge

  @security
  Scenario: Price and wait do not vary with spend history
    Given "acct-0001" has bought 3 refills today and holds 25 gems
    And "acct-0003" has never bought anything and holds 25 gems
    And both accounts have meter "energy" stored with value 2 and anchor_at "2026-10-21T11:50:00Z"
    When each account sends GET /api/energy/offers?meter_code=energy
    Then both see offer "refill-full" with units 3 and cost 6 gems, "refill-one" with cost 3 and "boost-1h" with cost 12
    When each account sends GET /api/energy
    Then both see next_tick_at "2026-10-21T12:20:00Z" and full_at "2026-10-21T13:20:00Z"
    And no quote, config lookup or sheet reads purchases, spend totals or segments

  @security
  Scenario: A minor account cannot buy a refill by default
    Given I am authenticated as "acct-0004" holding 100 gems and is_minor is true
    When I send GET /api/energy/offers?meter_code=energy
    Then every paid offer is blocked with "not_for_minors"
    When I send POST /api/energy/refills with offer_code "refill-full"
    Then the response status is 403 and the error is "refill_not_available"
    And the ledger received no spend

  @happy
  Scenario: A friend gift is claimed once (optional extension)
    Given GIFTS_ENABLED is true and "acct-0005" has been a friend of "acct-0001" since "2026-10-10T09:00:00Z"
    When "acct-0001" sends gift "gift-0001" to "acct-0005" for meter "energy"
    Then the gift has state "sent"
    When "acct-0005" claims "gift-0001"
    Then grantEnergy is called with reason "energy-lives.gift" and key "energy-lives:acct-0005:gift:gift-0001"
    And the gift has state "claimed"

  @security
  Scenario: Gift refusals reveal nothing about the recipient (optional extension)
    Given GIFTS_ENABLED is true and "acct-0006" has been a friend of "acct-0001" since "2026-10-21T11:30:00Z"
    When "acct-0001" sends a gift to "acct-0006"
    Then the response status is 409 and the error is "gift_not_available"
    And an opted-out recipient and a non-friend produce the same status and body
