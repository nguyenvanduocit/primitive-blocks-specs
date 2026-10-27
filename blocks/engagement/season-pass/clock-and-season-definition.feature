Feature: Clock authority and season definition
  As an operator
  I want season boundaries to be absolute server-side instants and a published season to be fixed
  So that no device clock, timezone or edit can change who owns which reward

  Background:
    Given the app is configured for tenant "tenant-001"
    And the season from fixtures/season-2026-10.json is published
    And the players from fixtures/progress-states.json exist
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And every attempt presented with an XP event is in state "confirmed" unless the scenario says otherwise

  @happy
  Scenario: The state response carries the server clock and the absolute boundaries
    Given I am authenticated as "acc-ann"
    When I send GET /api/season-pass/current
    Then server_now is "2026-10-21T12:00:00Z"
    And season.starts_at is "2026-10-01T00:00:00Z", ends_at is "2026-11-01T00:00:00Z" and claim_until is "2026-11-01T00:10:00Z"
    And season.phase is "active"

  @happy
  Scenario Outline: The phase follows the server instant and the half-open boundaries
    Given I am authenticated as "acc-ann"
    And the clock is fixed at "<instant>"
    When I send GET /api/season-pass/seasons/season-2026-10
    Then the phase is "<phase>"

    Examples:
      | instant              | phase        | note                                    |
      | 2026-10-01T00:00:00Z | active       | starts_at is inclusive                  |
      | 2026-10-31T23:59:59Z | active       | last second                             |
      | 2026-11-01T00:00:00Z | claim_window | ends_at is exclusive                    |
      | 2026-11-01T00:09:59Z | claim_window | last second of the grace                |
      | 2026-11-01T00:10:00Z | closed       | claim_until is exclusive                |

  @edge
  Scenario: A device clock that runs ahead changes only the display
    Given I am authenticated as "acc-ann"
    And the device clock is 600 seconds ahead of the server
    And the server instant is "2026-10-31T23:55:00Z"
    When the client loads the pass
    Then the displayed remaining time is 300 seconds, computed from server_now and ends_at
    When I claim free tier 3
    Then the server evaluates the claim at its own instant and the result is "granted"

  @edge
  Scenario: A device clock set back does not extend anything
    Given the device clock is set 7 days back
    And the server instant is "2026-11-01T00:10:00Z"
    When I claim free tier 3 for season "season-2026-10" under "forfeit"
    Then the error is "claim_window_closed"

  @edge
  Scenario: The countdown reaching zero reloads state and decides nothing
    Given the client shows a countdown of 2 seconds
    When the countdown reaches zero
    Then the client requests GET /api/season-pass/current
    And no cell is marked claimed, claimable or expired by the client

  @edge
  Scenario: Offline, the pass shows the absolute end time and no ticking countdown
    Given the device is offline and the last state is cached
    Then the pass screen shows the absolute end time and no ticking countdown
    And claim, skip, boost and purchase controls are disabled

  @edge
  Scenario: The pass window comes only from season_definitions, never from the calendar
    Given engagement.event-calendar holds a seasonal-layer entry with season_ref "season-2026-10" and an end time of "2026-10-30T00:00:00Z"
    And I am authenticated as "acc-ann"
    When I send GET /api/season-pass/current
    Then season.ends_at is "2026-11-01T00:00:00Z"
    And no call is made to engagement.event-calendar
    When the calendar entry is moved to end at "2026-11-05T00:00:00Z"
    Then the pass window is unchanged and XP is still credited only inside [starts_at, ends_at)

  @edge
  Scenario: A calendar entry that names no season here changes nothing in the pass
    Given engagement.event-calendar holds an entry with season_ref "season-2027-01" that this block does not know
    When I send GET /api/season-pass/current
    Then the response is the same as without the entry
    And no season_definitions row is created

  @edge
  Scenario: Season boundaries do not move with the player's timezone
    Given "acc-ann" is in "Asia/Ho_Chi_Minh" and "acc-bob" is in "America/Los_Angeles"
    When both load the pass at "2026-10-31T23:00:00Z"
    Then both see ends_at "2026-11-01T00:00:00Z"
    And both see the same remaining time of 3600 seconds

  @edge
  Scenario Outline: A season is published only when every rule holds
    Given an operator submits a draft season "<draft>"
    When the operator publishes it
    Then the outcome is "<outcome>"
    And published_at is <published_at>

    Examples:
      | draft                                                                    | outcome               | published_at |
      | window 2026-12-01T00:00:00Z to 2026-12-31T00:00:00Z, 10 valid tiers      | published             | set          |
      | window starting at the instant the previous season ends (touching)       | published             | set          |
      | ends_at equal to starts_at                                               | invalid_season_window | null         |
      | window 2026-10-31T00:00:00Z to 2026-11-15T00:00:00Z (overlaps October)   | season_overlap        | null         |
      | tiers 1, 2 and 4 (tier 3 missing)                                        | invalid_tier_table    | null         |
      | a tier with xp_cost 0                                                    | invalid_tier_table    | null         |
      | repeat_tier_xp 300 with repeat_tier_max 0                                | invalid_tier_table    | null         |
      | a reward with code "coin" and amount 0                                   | invalid_tier_table    | null         |
      | a reward code that the ledger does not know                              | unknown_reward_code   | null         |
      | published after its own starts_at                                        | late_publish          | null         |
      | no premium reward in any tier                                            | empty_premium_track   | null         |

  @edge
  Scenario: A published season cannot be edited
    When an operator tries to change an xp_cost, a reward, the window or the premium product code of "season-2026-10"
    Then the change is rejected
    And the tiers of "season-2026-10" are unchanged

  @edge
  Scenario: Two active seasons are a configuration error and credit nothing
    Given a database bypass created a second published season overlapping "season-2026-10"
    When the trusted server ingests a "level.completed" event for "acc-ann"
    Then the response status is 500 and the error is "season_config_error"
    And no xp_events row is written
    And an operations alert is raised

  @edge
  Scenario: A season_id is short enough for the ledger keys
    When an operator submits a season with a 65-character season_id
    Then the publish is rejected with "invalid_season_id"
    And a season_id of 64 characters produces a longest ledger key of at most 200 characters

  @security
  Scenario: Players never see an unpublished season
    Given a draft season "season-2026-12-draft" exists with no published_at
    And I am authenticated as "acc-ann"
    When I send GET /api/season-pass/seasons/season-2026-12-draft
    Then the response status is 404
    And the error is "season_not_found"

  @security
  Scenario: Publishing is not reachable from the player API
    Given I am authenticated as "acc-ann"
    When I send POST /api/season-pass/publish
    Then the response status is 404
