Feature: Tier skips and XP boosts
  As a player
  I want to see the price and the effect before I spend, and to pay exactly that
  So that buying progress is honest, and a crash or a double tap never costs me twice

  Background:
    Given the app is configured for tenant "tenant-001"
    And the season from fixtures/season-2026-10.json is published
    And the players from fixtures/progress-states.json exist
    And TIER_SKIP_PRICE and XP_BOOST_CATALOG are set as in fixtures/season-2026-10.json
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And every attempt presented with an XP event is in state "confirmed" unless the scenario says otherwise

  @happy
  Scenario: The quote shows the price, the effect and the balance after
    Given I am authenticated as "acc-ann"
    When I send GET /api/season-pass/seasons/season-2026-10/skip-quote?count=2
    Then the quote has from_tier 5, to_tier 7, xp_granted 450 and price { "currency": "gem", "amount": 80 }
    And balance is 100 and balance_after is 20
    And nothing is spent

  @happy
  Scenario: Buying a skip spends the quoted price and adds the XP of the skipped tiers
    Given I am authenticated as "acc-ann"
    When I send POST /api/season-pass/skips with { "season_id": "season-2026-10", "from_tier": 5, "count": 2, "price_shown": 80 }
    Then the response status is 200
    And the ledger received spend(acc-ann, gem, 80, "season-pass.tier-skip") with a key "season-pass:acc-ann:season-2026-10:skip:<purchase_id>"
    And an xp_events row exists with source "tier_skip", event_id "skip:<purchase_id>", credited_xp 450 and boost_percent 100
    And total_xp is 1200, the tier is 7 and xp_into_tier is 50
    And the gem balance is 20
    And the season_purchases row is "applied"

  @edge
  Scenario: A skip adds XP and keeps the progress inside the tier
    Given "acc-ann" has total_xp 750
    When "acc-ann" buys a 1-tier skip from tier 5
    Then xp_granted is 200 and total_xp is 950
    And the tier is 6 and xp_into_tier is 50

  @edge
  Scenario: Skip XP is not reduced by the daily or season caps
    Given "acc-ann" has used 300 of 300 daily XP for "objective.completed" and 1500 of 3000 season XP
    When "acc-ann" buys a 2-tier skip from tier 5
    Then xp_granted is 450 in full
    And no capped_by is recorded on the skip row

  @edge
  Scenario: A changed price is rejected with the fresh quote and nothing is spent
    Given I am authenticated as "acc-ann"
    And the price per tier is raised to 50 gem after the quote was shown
    When I send POST /api/season-pass/skips with { "season_id": "season-2026-10", "from_tier": 5, "count": 2, "price_shown": 80 }
    Then the response status is 409
    And the error is "price_changed"
    And the error body carries a quote with price 100
    And no ledger call is made and no season_purchases row exists

  @edge
  Scenario: Moving up a tier while the sheet is open returns a fresh quote
    Given I am authenticated as "acc-ann"
    And "acc-ann" reached tier 6 after the quote for from_tier 5 was shown
    When I send POST /api/season-pass/skips with { "season_id": "season-2026-10", "from_tier": 5, "count": 2, "price_shown": 80 }
    Then the response status is 409
    And the error is "tier_changed"
    And the error body carries a quote with from_tier 6, price 80 and xp_granted 500
    And no ledger call is made

  @edge
  Scenario: Too little balance fails cleanly and a later attempt starts fresh
    Given I am authenticated as "acc-ann"
    And the gem balance of "acc-ann" is 50
    When I send POST /api/season-pass/skips with { "season_id": "season-2026-10", "from_tier": 5, "count": 2, "price_shown": 80 }
    Then the response status is 409
    And the error is "insufficient_balance"
    And the season_purchases row is "failed" with dedupe_key null
    And total_xp is still 750
    When the gem balance of "acc-ann" becomes 100 and I send the same request
    Then a new season_purchases row is created with a new purchase_id
    And the skip is applied once

  @edge
  Scenario: A repeated request completes the same purchase and spends once
    Given I am authenticated as "acc-ann"
    And I sent a valid skip request for from_tier 5 and count 2
    When I send the same request again
    Then exactly one ledger spend exists for the purchase
    And the response is the same applied state
    And total_xp is 1200

  @edge
  Scenario: A crash between the spend and the XP is completed by the retry
    Given I am authenticated as "acc-ann"
    And the process stops after the ledger applied the spend and before the XP row was written
    Then the season_purchases row is "pending"
    When I send the same skip request again
    Then the existing purchase is completed with the same ledger key
    And total_xp is 1200 and exactly one spend entry exists

  @edge
  Scenario: A pending skip from before the season end is completed after the end
    Given the season_purchases row for a skip by "acc-ann" is "pending" and was created at "2026-10-31T23:59:59Z"
    And the clock is fixed at "2026-11-01T00:05:00Z"
    When the reconcile job runs
    Then the XP is booked, the purchase is "applied" and settled_at of "acc-ann" is cleared
    And settlement runs again for "acc-ann"

  @edge
  Scenario: A retry with a different count while an intent exists is a conflict
    Given a "pending" skip intent for from_tier 5 and count 2 exists for "acc-ann"
    When "acc-ann" sends a skip request for from_tier 5 and count 3
    Then the response status is 409
    And the error is "purchase_conflict"

  @edge
  Scenario Outline: Limits on how many tiers can be skipped
    Given "acc-ann" has total_xp <total_xp>
    When "acc-ann" requests a skip of <count> tiers
    Then the response status is <status>
    And the error is "<error>"

    Examples:
      | total_xp | count | status | error              | note                                         |
      | 750      | 0     | 422    | invalid_request    | count below 1                                |
      | 750      | 11    | 409    | skip_not_available | above MAX_SKIP_TIERS_PER_REQUEST of 10       |
      | 1700     | 2     | 409    | skip_not_available | tier 9 to 11 passes the last defined tier 10 |
      | 2000     | 1     | 409    | skip_not_available | already on the last defined tier             |

  @edge
  Scenario: Skips can be switched off, or limited to premium holders
    Given TIER_SKIP_PRICE is unset
    When "acc-ann" requests a skip of 1 tier
    Then the error is "skip_not_available"
    Given TIER_SKIP_PRICE is set and TIER_SKIP_REQUIRES_PREMIUM is true
    When "acc-ann" requests a skip of 1 tier
    Then the response status is 403 and the error is "premium_required"
    When "acc-bob" requests a skip of 1 tier and sends the quoted price
    Then the skip is applied

  @edge
  Scenario: Nothing can be bought outside the season
    Given the clock is fixed at "2026-11-01T00:00:00Z"
    When "acc-ann" sends a skip request for season "season-2026-10"
    Then the response status is 409 and the error is "season_not_active"

  @happy
  Scenario: Buying a boost spends the price and opens a window of the stated length
    Given I am authenticated as "acc-ann"
    When I send POST /api/season-pass/boosts with { "season_id": "season-2026-10", "boost_code": "boost-x2-24h", "price_shown": 60 }
    Then the ledger received spend(acc-ann, gem, 60, "season-pass.xp-boost") with a key "season-pass:acc-ann:season-2026-10:boost:<purchase_id>"
    And the boost window is from "2026-10-21T12:00:00Z" to "2026-10-22T12:00:00Z"
    And the gem balance is 40

  @edge
  Scenario Outline: The boost applies inside its window and not at its end instant
    Given "acc-ann" bought "boost-x2-24h" at "2026-10-21T12:00:00Z"
    And the clock is fixed at "<instant>"
    When the trusted server ingests a "level.completed" event for "acc-ann"
    Then boost_percent is <boost_percent> and credited_xp is <credited>

    Examples:
      | instant              | boost_percent | credited |
      | 2026-10-22T11:59:59Z | 200           | 40       |
      | 2026-10-22T12:00:00Z | 100           | 20       |

  @edge
  Scenario: Only one boost runs at a time
    Given "acc-ann" has an applied boost running
    When "acc-ann" sends a boost purchase for "boost-x2-24h"
    Then the response status is 409 and the error is "boost_active"
    And no ledger call is made

  @edge
  Scenario Outline: A boost is sold only when its whole duration fits before the season ends
    Given the clock is fixed at "<instant>"
    When "acc-ann" sends a boost purchase for "boost-x2-24h" with the quoted price
    Then the outcome is "<outcome>"

    Examples:
      | instant              | outcome               | note                                         |
      | 2026-10-31T00:00:00Z | applied               | window ends exactly at ends_at               |
      | 2026-10-31T00:00:01Z | boost_exceeds_season  | window would end one second after ends_at    |

  @edge
  Scenario: A changed boost price is rejected like a skip price
    Given the price of "boost-x2-24h" is raised to 80 gem after the card was shown
    When "acc-ann" sends a boost purchase with price_shown 60
    Then the error is "price_changed" and the error body carries the new price
    And no ledger call is made

  @security
  Scenario Outline: Price and quantity come from the server, never from the request
    Given I am authenticated as "acc-ann"
    When I send POST <path> with <body>
    Then the response status is <status>
    And the error is "<error>"
    And no ledger call is made

    Examples:
      | path                    | body                                                                                                          | status | error           |
      | /api/season-pass/skips  | { "season_id": "season-2026-10", "from_tier": 5, "count": 2, "price_shown": 1 }                               | 409    | price_changed   |
      | /api/season-pass/skips  | { "season_id": "season-2026-10", "from_tier": 5, "count": -1, "price_shown": 80 }                             | 422    | invalid_request |
      | /api/season-pass/skips  | { "season_id": "season-2026-10", "from_tier": 5, "count": 2, "price_shown": 80, "xp_granted": 9000 }         | 422    | invalid_request |
      | /api/season-pass/boosts | { "season_id": "season-2026-10", "boost_code": "boost-x9-90d", "price_shown": 60 }                            | 422    | invalid_request |
      | /api/season-pass/boosts | { "season_id": "season-2026-10", "boost_code": "boost-x2-24h", "price_shown": 60, "account_id": "acc-bob" } | 422    | invalid_request |
