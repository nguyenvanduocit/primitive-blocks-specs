Feature: Progress ingestion
  As the objectives backend
  I want progress to come only from named, deduplicated, capped events
  So that a retry never counts twice and a forged stream cannot mint more than its caps allow

  Background:
    Given the app is configured for tenant "tenant-001"
    And the content set from fixtures/definitions.json is published
    And EVENT_MAX_AGE_SECONDS is 172800, EVENT_BATCH_MAX is 50 and ACCOUNT_EVENTS_PER_DAY_MAX is 5000
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And I am authenticated as "acct-001" in the state "preset" of fixtures/event-cases.json
    And the validator accepts event refs that start with "run-ok-"
    And the attempt hook returns the states of "attempts" in fixtures/event-cases.json
    And every client event for a play metric without an explicit attempt_id carries "att-confirmed"

  @happy
  Scenario: An event advances every active instance of its metric
    Given the case "counted-simple" in fixtures/event-cases.json
    When I send POST /api/objectives/events with the case events
    Then the response status is 200
    And the results and instances match the case "expected"
    And daily.win-3 and weekly.win-20 both advanced because both count match_won

  @edge
  Scenario: A repeated event id counts once
    Given the case "duplicate-event-id"
    When I send POST /api/objectives/events with the case events
    Then the results are "counted" then "duplicate"
    And the counter for match_won is 1
    When I send the same request again
    Then both results are "duplicate" and nothing changes

  @edge
  Scenario Outline: Amounts are clamped by the per-event cap and the day cap
    Given the case "<case>"
    When I send POST /api/objectives/events with the case events
    Then the results and counters match the case "expected"

    Examples:
      | case                      |
      | per-event-cap             |
      | day-cap-partial-then-zero |

  @edge
  Scenario: A max metric keeps the highest value
    Given the case "max-aggregation-keeps-the-highest"
    When I send POST /api/objectives/events with the case events
    Then progress of daily.score-5000 after each event is 4000, 4000 and 5000
    And daily.score-5000 is "completed"
    And the counter for run_score is 6000

  @edge
  Scenario: Progress never exceeds the target
    Given the case "completion-clamps-progress"
    When I send POST /api/objectives/events with the case events
    Then daily.win-3 is "completed" with progress 3 of 3
    And the counter for match_won is 5
    And weekly.win-20 has progress 7 of 20

  @happy
  Scenario: Another metric can stand in for the objective's own metric
    Given the case "alternate-source-substitutes-for-the-mission-metric"
    When I send POST /api/objectives/events with the case events
    Then daily.play-3-rounds has progress 2 of 3 because the win counted as a round and as a win
    And daily.win-3 has progress 1 of 3

  @happy
  Scenario: Finished tasks add board points and the whole board unlocks the bonus
    Given the case "board-ladder-and-completion-bonus"
    When I send the events of each step of the case in order
    Then after each step the board points, the completed ids and the ladder instances match the step "expected"
    And after the last step the board is done and claimable_count is 7
    And the ledger has received no grant

  @edge
  Scenario: A goal replaced by a reroll does not hold the board open
    Given the case "rerolled-away-task-does-not-hold-the-board-open"
    When I send POST /api/objectives/events with the case events
    Then the board is done and daily.board-cleared is "completed"

  @security
  Scenario Outline: Events the client may not or cannot report are rejected per event
    Given the case "<case>"
    When I send POST /api/objectives/events with the case events
    Then the response status is 200
    And the result for the event is "rejected" with the reason in the case "expected"
    And no counter changed

    Examples:
      | case                           |
      | server-only-metric-from-client |
      | unknown-metric                 |

  @security
  Scenario Outline: A malformed amount is rejected without failing the batch
    Given the case "invalid-amounts"
    When I send one event with the amount <amount> and a valid event id
    Then the result is "rejected" with reason "invalid_amount"
    And no event row is stored

    Examples:
      | amount |
      | 0      |
      | -1     |
      | 1.5    |
      | "3"    |
      | null   |

  @security
  Scenario: Play counts only with proof of play
    Given the case "proof-of-play"
    When I send POST /api/objectives/events with the case events
    Then the results match the case "expected"
    And attempts in state confirmed, won and failed are accepted
    And attempts in state open, cancelled, expired, rejected or unknown are rejected with reason "attempt_not_proven"
    And a play metric without an attempt_id is rejected with reason "attempt_required"
    And the metric item_collected, which does not require an attempt, is counted
    And the attempt check runs before the validator, so an open attempt with a valid run ref is rejected
    And the stored events keep the attempt ids named in the case

  @security
  Scenario: A client-validated metric counts only after the validator accepts it
    Given the case "client-validated-metric"
    When I send POST /api/objectives/events with the case events
    Then the results are "counted", "rejected" and "rejected" with reason "validation_failed"
    And weekly.clear-25-levels has progress 1 of 25

  @edge
  Scenario: The age limit is inclusive at 48 hours
    Given the case "event-age-boundary"
    When I send POST /api/objectives/events with the case events
    Then the event at exactly 48 hours old is "counted"
    And the events one second older and three days older are "rejected" with reason "event_too_old"

  @edge
  Scenario: A timestamp ahead of the server is stored as the receive time
    Given the case "future-timestamp-is-informational"
    When I send POST /api/objectives/events with the case events
    Then the event is "counted"
    And the stored occurred_at is "2026-10-21T12:00:00Z"

  @edge
  Scenario: Work counts when the server learns of it
    Given the case "event-after-midnight-counts-in-the-new-window"
    When the clock is "2026-10-25T17:00:30Z" and I send POST /api/objectives/events with the case events
    Then the event counts toward weekly.win-20 of window "2026-10-26"
    And weekly.win-20 of window "2026-10-19" is "expired" at 12 of 20

  @security
  Scenario: Item and queue events count only when no purchase or premium spend is behind them
    Given the case "items-and-queue-adapters-filter-paid-and-self-fed-events"
    When the sender calls ingest_server_event for each event of the case
    Then the results and counters match the case "expected"
    And a purchased grant is ignored with reason "paid_source"
    And a grant paid by this block's own reward is ignored with reason "self_feeding"
    And an upgrade paid with a premium currency is ignored with reason "paid_with_premium"
    And no adapter exists for speed-up use

  @edge
  Scenario Outline: Server-derived events are idempotent and do not feed on their own rewards
    Given the case "<case>"
    When the sender calls ingest_server_event for each event of the case
    Then the results and counters match the case "expected"

    Examples:
      | case                                       |
      | server-event-is-idempotent-by-source-ref   |
      | ledger-rewards-do-not-feed-themselves      |
      | queue-completions-count-through-a-server-event |

  @security
  Scenario Outline: Oversized and excessive requests are refused before anything is recorded
    Given the case "<case>"
    When I send the request of the case
    Then the response status and error match the case "expected"
    And no event row is stored

    Examples:
      | case               |
      | batch-too-large    |
      | account-rate-limit |

  @edge
  Scenario: The block records its own session and active-day events once
    When I send POST /api/objectives/sessions with session_id "s-1" twice
    Then the counter for session_started is 1
    And the counter for active_day is 1
    And the events "objectives.session:s-1" and "objectives.activity:2026-10-21" each exist once
