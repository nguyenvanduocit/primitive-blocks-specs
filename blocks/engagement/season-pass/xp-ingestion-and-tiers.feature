Feature: XP ingestion and tier derivation
  As a game operator
  I want XP to enter the pass only from trusted server events, once each, within caps
  So that the tier is a pure function of total XP and nothing a device sends can move it

  Background:
    Given the app is configured for tenant "tenant-001"
    And the season from fixtures/season-2026-10.json is published
    And the players from fixtures/progress-states.json exist
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And every attempt presented with an XP event is in state "confirmed" unless the scenario says otherwise

  @happy
  Scenario Outline: The tier is derived from total XP and the tier table
    When the tier is derived for total_xp <total_xp>
    Then the tier is <tier>
    And xp_into_tier is <xp_into_tier>
    And xp_for_next_tier is <xp_for_next_tier>

    Examples:
      | total_xp | tier | xp_into_tier | xp_for_next_tier | note                                  |
      | 0        | 0    | 0            | 100              | nothing earned                        |
      | 99       | 0    | 99           | 100              | one XP short of tier 1                |
      | 100      | 1    | 0            | 100              | threshold is inclusive                |
      | 349      | 2    | 149          | 150              | one XP short of tier 3                |
      | 750      | 5    | 50           | 200              | fixture player acc-ann                |
      | 1999     | 9    | 299          | 300              | one XP short of the last defined tier |
      | 2000     | 10   | 0            | 300              | last defined tier                     |
      | 2300     | 11   | 0            | 300              | first repeat tier                     |
      | 3499     | 14   | 299          | 300              | one XP short of the final tier        |
      | 3500     | 15   | 0            | null             | final tier, repeat_tier_max reached   |
      | 9999     | 15   | 0            | null             | XP keeps counting, the tier stays     |

  @happy
  Scenario: A credited event adds its XP and returns the new standing
    Given the case "plain-credit" in fixtures/xp-event-cases.json
    When the trusted server ingests the case event for "acc-ann"
    Then the outcome is "credited" with credited_xp 20
    And total_xp is 770 and the tier is 5
    And one xp_events row exists for event_id "evt-0001" with day_key "2026-10-21"

  @happy
  Scenario: Crossing a tier boundary reports both tiers
    Given "acc-ann" has total_xp 890
    When the trusted server ingests a "level.completed" event "evt-1000" for "acc-ann"
    Then total_xp is 910
    And the response has tier_before 5 and tier_after 6
    And a season_pass_tier_reached event is fired with from_tier 5, to_tier 6 and via "play"

  @edge
  Scenario: A replayed event id credits nothing the second time
    Given the case "replay-of-evt-0001" in fixtures/xp-event-cases.json
    And event "evt-0001" was already ingested for "acc-ann"
    When the trusted server ingests the same event again
    Then the response repeats the first answer with duplicate true
    And total_xp is still 770
    And no new xp_events row exists

  @edge
  Scenario Outline: Caps reduce the base XP and name the cap that bound it
    Given the case "<case>" in fixtures/xp-event-cases.json
    When the trusted server ingests the case event for the case account
    Then requested_xp is <requested>, allowed_xp is <allowed> and credited_xp is <credited>
    And capped_by is <capped_by>
    And total_xp is <total_after>

    Examples:
      | case                                            | requested | allowed | credited | capped_by       | total_after |
      | source-daily-cap-partial                        | 50        | 20      | 20       | source_daily    | 770         |
      | source-season-cap-partial                       | 80        | 40      | 40       | source_season   | 790         |
      | fully-capped-today                              | 50        | 0       | 0        | source_daily    | 1150        |

  @edge
  Scenario: A boost multiplies the allowed base, so a cap never swallows it
    Given the case "source-daily-cap-with-boost-caps-base-not-credit" in fixtures/xp-event-cases.json
    And "acc-ann" has an applied boost "boost-x2-24h" from "2026-10-21T11:00:00Z" to "2026-10-22T11:00:00Z"
    When the trusted server ingests the case event for "acc-ann"
    Then allowed_xp is 20 and boost_percent is 200 and credited_xp is 40
    And total_xp is 790

  @edge
  Scenario: A fully capped event is booked with zero credit and replays to the same answer
    Given the case "fully-capped-today" in fixtures/xp-event-cases.json
    When the trusted server ingests the case event for "acc-bob"
    Then the outcome is "capped" and credited_xp is 0
    And an xp_events row exists for "evt-0005" with credited_xp 0
    When the same event is ingested again
    Then the response repeats the first answer with duplicate true

  @edge
  Scenario Outline: The daily cap follows the account's local calendar date
    Given the case "<case>" in fixtures/xp-event-cases.json
    And the clock is fixed at "<instant>"
    When the trusted server ingests the case event for "<account>"
    Then day_key is "<day_key>"
    And the outcome is "<outcome>"

    Examples:
      | case                                                | instant              | account  | day_key    | outcome  |
      | day-key-unchanged-one-second-before-local-midnight  | 2026-10-21T16:59:59Z | acc-ann  | 2026-10-21 | capped   |
      | day-key-resets-at-local-midnight-for-ann            | 2026-10-21T17:00:00Z | acc-ann  | 2026-10-22 | credited |
      | same-instant-other-timezone-still-same-day          | 2026-10-21T17:00:00Z | acc-bob  | 2026-10-21 | capped   |

  @edge
  Scenario: An account with no timezone counts days in UTC
    Given "acc-dee" has no timezone set
    And the clock is fixed at "2026-10-21T23:59:59Z"
    When the trusted server ingests a "level.completed" event "evt-1001" for "acc-dee"
    Then day_key is "2026-10-21"

  @edge
  Scenario: The optional total daily cap binds across sources
    Given the case "total-daily-cap-enabled" in fixtures/xp-event-cases.json
    And DAILY_XP_CAP_TOTAL is 500
    When the trusted server ingests the case event for "acc-ann"
    Then allowed_xp is 20 and capped_by is null
    When the trusted server ingests a "level.completed" event "evt-1002" for "acc-ann"
    Then allowed_xp is 0 and credited_xp is 0
    And capped_by is "total_daily"

  @edge
  Scenario: The season is the one active at the server instant of ingestion
    Given the case "event-in-last-second-credited" in fixtures/xp-event-cases.json
    When the trusted server ingests the case event for "acc-ann" at "2026-10-31T23:59:59Z"
    Then the outcome is "credited" and total_xp is 770
    Given the case "event-after-season-end-not-credited" in fixtures/xp-event-cases.json
    When the trusted server ingests the case event for "acc-ann" at "2026-11-01T00:00:00Z"
    Then the outcome is "no_active_season" and credited_xp is 0
    And no xp_events row exists for "evt-0013"

  @edge
  Scenario: The catch-up option grants late joiners XP once, before their first event
    Given the case "first-event-with-catch-up" in fixtures/xp-event-cases.json
    And CATCH_UP_PERCENT is 50
    When the trusted server ingests the case event for "acc-dee"
    Then an xp_events row exists with event_id "catch-up:season-2026-10", source "catch_up" and credited_xp 661
    And the event credits 20
    And total_xp is 681 and the tier is 4
    When the trusted server ingests a "level.completed" event "evt-1003" for "acc-dee"
    Then no second catch_up row exists and total_xp is 701

  @edge
  Scenario Outline: Catch-up XP is integer arithmetic on elapsed season time
    Given CATCH_UP_PERCENT is <percent>
    When catch-up XP is computed for a first event at "<first_event_at>"
    Then the result is <catch_up_xp>

    Examples:
      | percent | first_event_at       | catch_up_xp |
      | 50      | 2026-10-21T12:00:00Z | 661         |
      | 50      | 2026-10-11T00:00:00Z | 322         |
      | 50      | 2026-10-01T00:00:00Z | 0           |
      | 0       | 2026-10-21T12:00:00Z | 0           |

  @security
  Scenario Outline: Play-session XP needs an attempt that proves the play
    Given the case "<case>" in fixtures/xp-event-cases.json
    When the trusted server ingests the case event for "acc-ann"
    Then <result>
    And <rows>

    Examples:
      | case                                | result                                                | rows                           |
      | attempt-won-credited                | the outcome is "credited" with credited_xp 20         | one xp_events row is written   |
      | attempt-failed-credited             | the outcome is "credited" with credited_xp 20         | one xp_events row is written   |
      | attempt-open-rejected               | the response status is 422 and the error is "attempt_not_proven" | no xp_events row is written |
      | attempt-cancelled-rejected          | the response status is 422 and the error is "attempt_not_proven" | no xp_events row is written |
      | attempt-expired-rejected            | the response status is 422 and the error is "attempt_not_proven" | no xp_events row is written |
      | attempt-rejected-state-rejected     | the response status is 422 and the error is "attempt_not_proven" | no xp_events row is written |
      | attempt-unknown-rejected            | the response status is 422 and the error is "attempt_not_proven" | no xp_events row is written |

  @security
  Scenario Outline: The attempt field is present exactly when the source requires it
    Given the case "<case>" in fixtures/xp-event-cases.json
    When the trusted server ingests the case event for "acc-ann"
    Then the response status is 422 and the error is "invalid_event"
    And no xp_events row is written

    Examples:
      | case                                              | note                                        |
      | attempt-missing-rejected                          | level.completed without an attempt_id       |
      | attempt-on-source-without-requirement-rejected    | objective.completed with an attempt_id      |

  @security
  Scenario: One attempt credits one source once, under any event id
    Given the case "attempt-already-credited-under-another-event-id" in fixtures/xp-event-cases.json
    And attempt "att-0001" already credited "level.completed" through "evt-0001"
    When the trusted server ingests the case event for "acc-ann"
    Then the outcome is "attempt_already_credited" and credited_xp is 0
    And no xp_events row is written and total_xp is 770

  @edge
  Scenario: The same attempt may credit a different source
    Given the case "same-attempt-other-source-allowed" in fixtures/xp-event-cases.json
    And attempt "att-0001" already credited "level.completed" through "evt-0001"
    When the trusted server ingests the case event for "acc-ann"
    Then the outcome is "credited" with credited_xp 40 and capped_by "source_season"

  @edge
  Scenario: A replay returns the first answer even after the attempt changed state
    Given the case "replay-after-attempt-expired-keeps-the-first-answer" in fixtures/xp-event-cases.json
    And event "evt-0001" was booked while attempt "att-0001" was "confirmed"
    And attempt "att-0001" is now "expired"
    When the trusted server ingests the case event for "acc-ann"
    Then the response repeats the first answer with duplicate true
    And attemptState is not asked again
    And total_xp is still 770

  @security
  Scenario: A source that another block already gates needs no attempt here
    Given XP_SOURCES marks "objective.completed" with requires_attempt false
    When the trusted server ingests an "objective.completed" event "evt-1004" for "acc-ann" with no attempt_id
    Then the outcome is "credited"

  @security
  Scenario Outline: The ingest endpoint rejects anything a caller could use to choose the XP
    Given the case "<case>" in fixtures/xp-event-cases.json
    When the trusted server ingests the case event for "acc-ann"
    Then the response status is <status>
    And the error is "<error>"
    And no xp_events row is written

    Examples:
      | case                                  | status | error          |
      | client-supplied-xp-amount-rejected    | 422    | invalid_event  |
      | unknown-source-rejected               | 422    | unknown_source |
      | units-above-max-rejected              | 422    | invalid_event  |
      | event-older-than-max-age-rejected     | 422    | event_too_old  |

  @security
  Scenario: Only a caller with the service credential can ingest XP
    When a request without the service credential posts an event to /internal/season-pass/xp
    Then the response status is 401
    And the error is "unauthorized"
    And no xp_events row is written
    When a player session posts an event to /internal/season-pass/xp
    Then the response status is 401

  @security
  Scenario: The caller cannot name the season, the day or the boost
    When the trusted server ingests a "level.completed" event for "acc-ann" with the extra fields { "season_id": "season-2026-11", "day_key": "2026-10-01", "boost_percent": 500 }
    Then the response status is 422
    And the error is "invalid_event"
    And no xp_events row is written
