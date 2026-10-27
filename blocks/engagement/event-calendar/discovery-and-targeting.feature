Feature: Discovery and audience targeting
  As a player
  I want to see the events that are open to me and nothing else
  So that I can plan my play, and so that nobody is shown different terms because of what they spend

  Background:
    Given the app is configured for tenant "tenant-001"
    And the events from fixtures/events.json are published
    And the accounts from fixtures/accounts.json exist
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario Outline: Discovery returns the expected lists for each account
    When I send GET /api/events as <account> with the build and platform from fixtures/accounts.json
    Then the response status is 200
    And server_now is "2026-10-27T12:00:00.000Z"
    And events lists "<events>" in that order
    And upcoming lists "<upcoming>"
    And unavailable lists "<unavailable>"

    Examples:
      | account  | events                                                                      | upcoming        | unavailable                      |
      | acc-ann  | evt-daily-1027, evt-harvest-season, evt-weekly-sprint-w44                   | evt-weekend-rush |                                  |
      | acc-ben  | evt-daily-1027, evt-weekly-sprint-w44                                       | evt-weekend-rush | evt-harvest-season update_required |
      | acc-cara | evt-daily-1028, evt-harvest-season, evt-weekly-sprint-w44                   | evt-weekend-rush |                                  |
      | acc-dan  | evt-daily-1027, evt-harvest-season, evt-comeback-w44, evt-weekly-sprint-w44 | evt-weekend-rush |                                  |
      | acc-eve  | evt-daily-1027, evt-harvest-season, evt-welcome-w44, evt-weekly-sprint-w44  | evt-weekend-rush |                                  |
      | acc-fay  | evt-daily-1027, evt-harvest-season, evt-weekly-sprint-w44                   | evt-weekend-rush |                                  |
      | acc-qa-1 | evt-daily-1027, evt-harvest-season, evt-weekly-sprint-w44, evt-qa-short     | evt-weekend-rush |                                  |

  @happy
  Scenario: The response names the next boundary
    When I send GET /api/events as acc-ann
    Then next_boundary_at is "2026-10-27T16:00:00.000Z"
    And the item for "evt-daily-1027" has ending_soon_at "2026-10-27T16:00:00.000Z" and ends_at "2026-10-27T17:00:00.000Z"

  @happy
  Scenario: Items are ordered by priority, then end time, then start time, then id
    When I send GET /api/events as acc-dan
    Then the priorities of the items in events are 80, 70, 60, 50

  @edge
  Scenario: A teaser carries no reward amounts and one is shown per series
    When I send GET /api/events as acc-ann
    Then the upcoming item "evt-weekend-rush" has a title and a teaser and no rewards and no rules
    And "evt-weekly-sprint-w45" is not in upcoming because its series already has a live instance
    And the full terms of "evt-weekend-rush" are readable through GET /api/events/evt-weekend-rush

  @edge
  Scenario: The upcoming horizon is bounded
    Given the clock is fixed at "2026-10-23T12:00:00Z"
    When I send GET /api/events as acc-ann
    Then "evt-weekend-rush" is not in upcoming because it starts after the horizon of 604800 seconds

  @edge
  Scenario Outline: Segment targeting is decided by account facts
    When I send GET /api/events as <account>
    Then "<event>" is <listed> in events

    Examples:
      | account | event             | listed     |
      | acc-dan | evt-comeback-w44  | listed     |
      | acc-ann | evt-comeback-w44  | not listed |
      | acc-eve | evt-welcome-w44   | listed     |
      | acc-ann | evt-welcome-w44   | not listed |

  @edge
  Scenario: A lapsed player keeps the comeback event after returning
    Given acc-dan was listed "evt-comeback-w44" and has joined it with progress 1
    When the previous_session_ended_at of acc-dan becomes "2026-10-27T12:00:00Z"
    And I send GET /api/events as acc-dan
    Then "evt-comeback-w44" is still in events
    And acc-dan's progress is still 1

  @edge
  Scenario: A new player who was listed the welcome event keeps it after aging out
    Given acc-eve was listed "evt-welcome-w44" on "2026-10-27T12:00:00Z"
    And the clock is fixed at "2026-11-01T22:00:00Z"
    When I send GET /api/events as acc-eve
    Then "evt-welcome-w44" is in events with state "ending-soon"
    When I send GET /api/events as acc-gus
    Then "evt-welcome-w44" is not in events because acc-gus is past the new-player window and was never listed it

  @edge
  Scenario: A failed latch write answers an error, not a list that could change
    Given the participation write fails
    When I send GET /api/events as acc-dan
    Then the response status is 503
    And the response error is "latch_unavailable"

  @happy
  Scenario: The allow-list shows a QA event to listed accounts only
    When I send GET /api/events as acc-qa-1
    Then "evt-qa-short" is in events with state "live"
    When I send GET /api/events as acc-ann
    Then "evt-qa-short" is not in events

  @security
  Scenario: Unknown, draft and out-of-audience events are indistinguishable
    Given a draft event "evt-draft-x" exists
    When acc-ann sends GET /api/events/evt-qa-short
    And acc-ann sends GET /api/events/evt-draft-x
    And acc-ann sends GET /api/events/evt-does-not-exist
    And acc-ann sends GET /api/events/evt-comeback-w44
    Then every response has status 404 and the body { "error": "event_not_found" }

  @security
  Scenario: A player response never exposes operator or targeting data
    When I send GET /api/events as acc-qa-1
    Then no item contains allow_list, issuance_budget, eligibility_snapshot, audience, tenant_id or an operator id

  @edge
  Scenario: A client below min_app_version gets a stub and a deep link gets update_required
    When I send GET /api/events as acc-ben
    Then unavailable contains { "event_id": "evt-harvest-season", "reason": "update_required", "min_app_version": "2.4.0" }
    And the stub has no rewards, rules or config
    When acc-ben sends GET /api/events/evt-harvest-season
    Then the response status is 403
    And the response error is "update_required"

  @edge
  Scenario: Update stubs can be turned off
    Given UPDATE_STUBS_ENABLED is false
    When I send GET /api/events as acc-ben
    Then unavailable is empty
    When acc-ben sends GET /api/events/evt-harvest-season
    Then the response error is "update_required"

  @edge
  Scenario: The client hides an event it has no renderer for
    Given the response contains an item with type "mystery" and config_schema_version 3
    And the client registry has no renderer for "mystery@3"
    Then the item is not shown in the hub
    And one live_event_render_skipped event is recorded with reason "no_renderer"
    And the other items are shown

  @edge
  Scenario: The response uses one locale with a fallback to the default
    When acc-ann sends GET /api/events with Accept-Language "vi-VN"
    Then locale is "en" because no "vi" text exists and default_locale is "en"
    And each item's content holds only the "en" text

  @security
  Scenario: A player route has no time parameter
    When acc-ann sends GET /api/events?at=2026-11-02T00:00:00Z
    Then server_now is "2026-10-27T12:00:00.000Z"
    And the lists equal the lists for acc-ann without the parameter

  @happy
  Scenario: A recurring event is returned with a recurrence label
    When I send GET /api/events as acc-ann
    Then the item for "evt-daily-1027" has recurrence { "repeats": true, "next_starts_at": "2026-10-27T17:00:00Z" }
    And the item for "evt-weekly-sprint-w44" has recurrence { "repeats": true, "next_starts_at": "2026-11-02T00:00:00Z" }
    And the items for "evt-harvest-season" and the teaser "evt-weekend-rush" have recurrence null

  @edge
  Scenario: A series whose next instance is not published says the date is not set
    Given the series "weekly-sprint" has no published instance after "evt-weekly-sprint-w45"
    When I send GET /api/events as acc-ann at "2026-11-02T00:00:00.000Z"
    Then the item for "evt-weekly-sprint-w45" has recurrence { "repeats": true, "next_starts_at": null }
    And the client shows "This event repeats." and "The next date is not set yet."

  @happy
  Scenario: A season reference is display data and nothing else
    Given "evt-harvest-season" carries season_ref "season-2026-autumn"
    When I send GET /api/events as acc-ann
    Then the item for "evt-harvest-season" carries season_ref "season-2026-autumn"
    And no call is made to engagement.season-pass and no season window is read or changed
    When an operator holds and releases "evt-harvest-season"
    Then season_ref is unchanged and the pass window is untouched
    And an event without a season_ref returns season_ref null
