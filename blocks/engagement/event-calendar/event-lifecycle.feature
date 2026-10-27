Feature: Event lifecycle
  As an event owner
  I want an event's state to follow server time alone
  So that no job is needed to start or end an event and every client sees the same state

  Background:
    Given the app is configured for tenant "tenant-001"
    And the events from fixtures/events.json are published
    And the config values in fixtures/events.json are in effect

  @happy
  Scenario Outline: A weekly event moves through the five states by server time
    Given the clock is fixed at "<at>"
    When the state of "evt-weekly-sprint-w44" is derived
    Then the state is "<state>"

    Examples:
      | at                       | state       |
      | 2026-10-25T23:59:59.999Z | scheduled   |
      | 2026-10-26T00:00:00.000Z | live        |
      | 2026-10-31T23:59:59.999Z | live        |
      | 2026-11-01T00:00:00.000Z | ending-soon |
      | 2026-11-01T23:59:59.999Z | ending-soon |
      | 2026-11-02T00:00:00.000Z | ended       |
      | 2026-11-04T23:59:59.999Z | ended       |
      | 2026-11-05T00:00:00.000Z | archived    |

  @happy
  Scenario Outline: A seasonal event has a longer ending-soon window and claim grace
    Given the clock is fixed at "<at>"
    When the state of "evt-harvest-season" is derived
    Then the state is "<state>"

    Examples:
      | at                       | state       |
      | 2026-11-05T23:59:59.999Z | live        |
      | 2026-11-06T00:00:00.000Z | ending-soon |
      | 2026-11-09T00:00:00.000Z | ended       |
      | 2026-11-16T00:00:00.000Z | archived    |

  @edge
  Scenario: The ending-soon window is clamped to a quarter of a short event
    Given "evt-qa-short" runs from 11:00:00Z to 13:00:00Z and the weekly window is 86400 seconds
    When the timeline of "evt-qa-short" is derived
    Then the ending-soon window is 1800 seconds
    And ending_soon_at is "2026-10-27T12:30:00Z"
    And the state at "2026-10-27T12:29:59.999Z" is "live"
    And the state at "2026-10-27T12:30:00.000Z" is "ending-soon"

  @happy
  Scenario: Ending soon changes presentation and nothing else
    Given acc-ann has joined "evt-weekly-sprint-w44" with progress 120
    When I send GET /api/events as acc-ann at "2026-10-31T23:59:59.999Z"
    And I send GET /api/events as acc-ann at "2026-11-01T00:00:00.000Z"
    Then the item for "evt-weekly-sprint-w44" has state "live" in the first response and "ending-soon" in the second
    And its rewards, thresholds, grants, claim modes and progress_cap are identical in both responses

  @happy
  Scenario: The state does not wait for settlement
    Given acc-ann has joined "evt-weekly-sprint-w44" with progress 600
    And settlement has not run
    When I send GET /api/events as acc-ann at "2026-11-02T00:00:00.000Z"
    Then "evt-weekly-sprint-w44" is listed in recent with state "ended"
    And no write to event_definitions has happened since the event was published

  @happy
  Scenario: An archived event is not listed
    When I send GET /api/events as acc-ann at "2026-11-05T00:00:00.000Z"
    Then "evt-weekly-sprint-w44" is in neither events, upcoming, recent nor unavailable

  @edge
  Scenario: The end instant belongs to the next state
    Given acc-ann has joined "evt-weekly-sprint-w44" with progress 120
    When acc-ann reports progress 10 with source_ref "level-complete:lv-34:attempt-1" at "2026-11-01T23:59:59.999Z"
    Then the response status is 200
    When acc-ann reports progress 10 with source_ref "level-complete:lv-35:attempt-1" at "2026-11-02T00:00:00.000Z"
    Then the response status is 409
    And the response error is "event_ended"

  @edge
  Scenario: An extension moves the ending-soon instant later
    Given an operator extends "evt-weekly-sprint-w44" to "2026-11-03T00:00:00Z" with reason "server incident"
    Then ending_soon_at is "2026-11-02T00:00:00Z"
    And the state at "2026-11-01T12:00:00.000Z" is "live"
    And the state at "2026-11-02T00:00:00.000Z" is "ending-soon"
    And the state at "2026-11-03T00:00:00.000Z" is "ended"

  @edge
  Scenario Outline: Extensions are bounded and never shorten
    When an operator extends "<event>" to "<new_end>" with reason "test"
    Then the response status is <status>
    And the response error is "<error>"

    Examples:
      | event                  | new_end              | status | error                          |
      | evt-weekly-sprint-w44  | 2026-11-03T00:00:01Z | 422    | extension_too_long             |
      | evt-weekly-sprint-w44  | 2026-11-01T00:00:00Z | 422    | extension_must_be_later        |
      | evt-daily-1027         | 2026-10-29T00:00:00  | 422    | extend_local_window_unsupported |

  @edge
  Scenario: An ended event cannot return to live
    Given the clock is fixed at "2026-11-02T00:00:01Z"
    When an operator extends "evt-weekly-sprint-w44" to "2026-11-03T00:00:00Z" with reason "late request"
    Then the response status is 409
    And the response error is "event_ended"

  @security
  Scenario: A published event is frozen
    When an author sends PUT /admin/events for "evt-weekly-sprint-w45" with a changed reward table
    Then the response status is 409
    And the response error is "event_frozen"
    And the stored reward table is unchanged

  @happy
  Scenario: An extension is disclosed with the original end
    Given an operator extends "evt-weekly-sprint-w44" to "2026-11-02T12:00:00Z" with reason "server incident"
    And an operator extends it again to "2026-11-03T00:00:00Z" with reason "server incident, second part"
    When I send GET /api/events as acc-ann
    Then the item for "evt-weekly-sprint-w44" has ends_at "2026-11-03T00:00:00.000Z"
    And original_ends_at is "2026-11-02T00:00:00.000Z"
    And two audit rows of kind "extend" exist with their reasons

  @happy
  Scenario: An event that was never extended has no original end
    When I send GET /api/events as acc-ann
    Then original_ends_at is null for every item

  @security
  Scenario Outline: An end never restarts
    Given "evt-weekly-sprint-w44" ended at "2026-11-02T00:00:00Z"
    When the state of "evt-weekly-sprint-w44" is derived at "<at>"
    Then the state is "<state>" and is never "scheduled", "live" or "ending-soon"

    Examples:
      | at                       | state    |
      | 2026-11-02T00:00:00.000Z | ended    |
      | 2026-11-03T12:00:00.000Z | ended    |
      | 2026-11-05T00:00:00.000Z | archived |
      | 2027-01-01T00:00:00.000Z | archived |

  @security
  Scenario: The next occurrence is a different event with its own end
    When I send GET /api/events as acc-ann at "2026-11-02T00:00:00.000Z"
    Then "evt-weekly-sprint-w44" is in recent with state "ended" and ends_at "2026-11-02T00:00:00.000Z"
    And "evt-weekly-sprint-w45" is a different item with its own ends_at "2026-11-09T00:00:00.000Z"
    And the two items share no progress and no countdown
