Feature: Season end, settlement and rollover
  As a player
  I want everything I earned delivered when the season ends, and a claim made in the last second to count
  So that the boundary between two seasons never costs me a reward

  Background:
    Given the app is configured for tenant "tenant-001"
    And the season from fixtures/season-2026-10.json is published
    And the next season "season-2026-11" from the same fixture is published
    And the players from fixtures/progress-states.json exist
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And every attempt presented with an XP event is in state "confirmed" unless the scenario says otherwise

  @happy
  Scenario: Under auto_claim the settlement delivers every earned, eligible, unclaimed reward
    Given UNCLAIMED_AT_END is "auto_claim"
    And the clock is fixed at "2026-11-01T00:00:00Z"
    When the settlement job runs for "season-2026-10"
    Then "acc-ann" receives free tiers 3, 4 and 5 with claim_source "season_end_auto"
    And "acc-bob" receives premium tiers 4, 5, 6 and 7 with claim_source "season_end_auto"
    And "acc-cy" receives free tier 7 and no premium reward
    And settled_at is set for each of them
    And a season_pass_settled event is fired with the policy "auto_claim"

  @edge
  Scenario: Running the settlement twice grants nothing the second time
    Given the settlement job ran for "season-2026-10"
    When the settlement job runs again
    Then every ledger key has exactly one entry
    And no new tier_claims row exists

  @edge
  Scenario: A settlement stopped midway resumes without duplicates
    Given SETTLE_BATCH_SIZE is 1
    And the settlement job stops after the first page
    When the settlement job runs again
    Then every account with due rewards is settled once
    And every ledger key has exactly one entry

  @edge
  Scenario: A player who opens the results before the job reaches them is settled on read
    Given the clock is fixed at "2026-11-01T00:00:05Z"
    And the settlement job has not reached "acc-ann"
    And I am authenticated as "acc-ann"
    When I send GET /api/season-pass/seasons/season-2026-10
    Then "acc-ann" is settled before the response is built
    And the response shows free tiers 3, 4 and 5 as "granted"
    And me.settled is true

  @edge
  Scenario: A pending claim is completed by the settlement
    Given the tier_claims row for free tier 4 of "acc-ann" is "pending" with its ledger grant applied
    And the clock is fixed at "2026-11-01T00:00:00Z"
    When the settlement job runs for "season-2026-10"
    Then the claim row is "granted" and no second ledger entry exists for its key

  @edge
  Scenario: A premium refund before the end means premium rewards are not auto-claimed
    Given "acc-eve" has premium through "txn-3001" and premium tier 3 unclaimed
    And the record "txn-3001" is "refunded" and "acc-eve" is "revoked"
    And the clock is fixed at "2026-11-01T00:00:00Z"
    When the settlement job runs for "season-2026-10"
    Then no premium cell of "acc-eve" is granted

  @happy
  Scenario: A claim in the last second of the season counts
    Given I am authenticated as "acc-ann"
    And the clock is fixed at "2026-10-31T23:59:59Z"
    When I claim free tier 3 for season "season-2026-10"
    Then the result is "granted"

  @edge
  Scenario: A claim that reaches the server just after the boundary is evaluated against the season it names
    Given I am authenticated as "acc-ann"
    And the clock is fixed at "2026-11-01T00:00:00.300Z"
    When I claim free tier 3 for season "season-2026-10"
    Then the response status is 200
    And the result is "granted" or "already_claimed" for season "season-2026-10"
    And season "season-2026-11" has no claim row for "acc-ann"

  @edge
  Scenario Outline: The claim window closes at claim_until, a half-open instant
    Given UNCLAIMED_AT_END is "forfeit"
    And I am authenticated as "acc-ann"
    And the clock is fixed at "<instant>"
    When I claim free tier 3 for season "season-2026-10"
    Then the outcome is "<outcome>"

    Examples:
      | instant              | outcome              | note                               |
      | 2026-11-01T00:09:59Z | granted              | one second before claim_until      |
      | 2026-11-01T00:10:00Z | claim_window_closed  | claim_until is ends_at plus 600 s  |

  @edge
  Scenario: Under forfeit nothing is granted after the window, and the results say so
    Given UNCLAIMED_AT_END is "forfeit"
    And the clock is fixed at "2026-11-01T00:10:00Z"
    And I am authenticated as "acc-ann"
    When the settlement job runs for "season-2026-10"
    Then no ledger call is made for "acc-ann"
    When I send GET /api/season-pass/seasons/season-2026-10
    Then the results list free tiers 3, 4 and 5 as not claimed in time
    And the season phase is "closed"

  @edge
  Scenario Outline: At the boundary instant exactly one season is active
    When the clock is fixed at "<instant>"
    And the trusted server ingests a "level.completed" event for "acc-bob"
    Then the credit goes to season "<season>"

    Examples:
      | instant              | season           |
      | 2026-10-31T23:59:59Z | season-2026-10   |
      | 2026-11-01T00:00:00Z | season-2026-11   |

  @edge
  Scenario: Between two seasons nothing is credited and the next season is announced
    Given the only published season after October starts at "2026-11-03T00:00:00Z"
    And the clock is fixed at "2026-11-01T12:00:00Z"
    And I am authenticated as "acc-ann"
    When I send GET /api/season-pass/current
    Then season is null and next_season is "season-2026-11" starting "2026-11-03T00:00:00Z"
    When the trusted server ingests a "level.completed" event for "acc-ann"
    Then the outcome is "no_active_season"

  @edge
  Scenario: Late XP never reopens an ended season
    Given the clock is fixed at "2026-11-01T00:00:00Z"
    When the trusted server ingests an event that occurred at "2026-10-31T23:59:58Z" for "acc-ann"
    Then the outcome is "no_active_season"
    And total_xp of "acc-ann" in "season-2026-10" is unchanged

  @edge
  Scenario: The results screen data reports what was delivered and how
    Given UNCLAIMED_AT_END is "auto_claim"
    And the settlement job ran for "season-2026-10"
    And I am authenticated as "acc-ann"
    When I send GET /api/season-pass/seasons/season-2026-10
    Then final tier is 5 and the delivered list names free tiers 1 (claimed by the player), 3, 4 and 5 (added at the season end)
    And the forfeited list is empty

  @security
  Scenario: Settlement cannot be triggered, or its arguments chosen, by a player
    Given I am authenticated as "acc-ann"
    When I send POST /api/season-pass/settle
    Then the response status is 404
    And no ledger call is made

  @security
  Scenario: A claim for an ended season outside the window is rejected, not redirected to the new season
    Given the clock is fixed at "2026-11-01T01:00:00Z"
    And I am authenticated as "acc-ann"
    When I claim free tier 3 for season "season-2026-10" under "forfeit"
    Then the error is "claim_window_closed"
    And no claim row is created in any season
