Feature: Kill switch, emergency end and preview
  As an event operator
  I want to stop a faulty event at once and treat players fairly
  So that a bug costs the economy little and costs no player what they earned

  Background:
    Given the app is configured for tenant "tenant-001"
    And the events from fixtures/events.json are published
    And the accounts from fixtures/accounts.json exist
    And the cases in fixtures/rewards-and-participation.json are loaded
    And the clock is fixed at "2026-10-27T12:00:00Z"
    And the operator "op-owner" has the operator role and "op-qa" has the preview role

  @happy
  Scenario: Hold withholds the event and keeps every row
    Given acc-ann has joined "evt-weekly-sprint-w44" with progress 120
    When "op-owner" holds "evt-weekly-sprint-w44" with reason "renderer crash"
    And I send GET /api/events as acc-ann
    Then "evt-weekly-sprint-w44" is not in events
    And unavailable contains { "event_id": "evt-weekly-sprint-w44", "reason": "held" }
    And acc-ann's progress and claims are unchanged

  @edge
  Scenario Outline: A held event refuses every write
    Given "evt-weekly-sprint-w44" is held and acc-ann has joined it with an earned manual reward
    When acc-ann sends <request>
    Then the response status is 409
    And the response error is "event_held"

    Examples:
      | request                                           |
      | POST /api/events/evt-weekly-sprint-w44/progress   |
      | POST /api/events/evt-weekly-sprint-w44/claim      |
      | POST /api/events/evt-weekly-sprint-w44/join       |

  @edge
  Scenario: A player who never joined a held event does not see it at all
    Given "evt-weekly-sprint-w44" is held
    When I send GET /api/events as acc-cara
    Then "evt-weekly-sprint-w44" is in neither events nor unavailable

  @edge
  Scenario: Settlement and the grant worker skip a held event
    Given "evt-weekly-sprint-w44" is held and its end instant has passed
    When settlement and the grant worker run
    Then no claim row is created and the ledger receives no call for the event

  @happy
  Scenario: Release restores the event and can return the lost time
    Given "evt-weekly-sprint-w44" was held for 2 hours
    When "op-owner" releases it with extend_seconds 7200 and reason "fixed"
    Then the event is listed again for acc-ann with its progress
    And its ends_at moved later by 7200 seconds
    And one audit row each exists for the hold, the release and the extension

  @security
  Scenario: A hold is never released automatically
    Given "evt-weekly-sprint-w44" has been held for longer than HOLD_ALERT_SECONDS
    Then an operator alert is raised
    And the event is still held

  @happy
  Scenario: Emergency end now settles as earned and pays clamped compensation
    When the case "end-now-with-compensation" runs
    Then the state of "evt-weekly-sprint-w44" is "ended" at "2026-10-27T12:00:00Z" and was never "ending-soon"
    And the compensation coins are 300 for acc-ann, 250 for acc-ben, 0 for acc-cara and 0 for acc-dan
    And no player's total coins from the event exceed 410

  @edge
  Scenario: Rewards earned before the end stand
    Given acc-ben had "m2" earned and unclaimed with progress 350
    When "op-owner" ends "evt-weekly-sprint-w44" now with reason "reward-table-defect"
    Then the claim for "m2" is still earned
    And acc-ben can claim it and the sweep grants it at the claim grace

  @edge
  Scenario: An emergency end with notice walks through ending-soon
    When "op-owner" ends "evt-weekly-sprint-w44" with closes_at "2026-10-28T12:00:00Z"
    Then ending_soon_at is "2026-10-27T12:00:00Z"
    And the state at "2026-10-28T12:00:00.000Z" is "ended"
    And the response items show closed_early true
    And the event_ending_soon hand-off is armed again with fire_at "2026-10-27T12:00:00Z" and expires_at "2026-10-28T12:00:00Z"

  @security
  Scenario: Compensation needs a currency that is in the reward table
    When "op-owner" ends "evt-weekly-sprint-w44" now with compensation [{ "currency": "gems", "amount": 5 }]
    Then the response status is 422
    And the response error is "compensation_currency_not_in_table"

  @edge
  Scenario: An emergency end cannot be undone and cannot be backdated
    Given "evt-weekly-sprint-w44" was ended now
    When "op-owner" extends it to "2026-11-03T00:00:00Z"
    Then the response status is 409
    When "op-owner" ends another event with closes_at "2026-10-27T11:00:00Z"
    Then the response status is 422

  @edge
  Scenario: An extension that would overlap an exclusive group is refused
    Given two events in group "weekend-tournament" end and start at "2026-11-01T00:00:00Z"
    When "op-owner" extends the first by 3600 seconds
    Then the response status is 409
    And the response error is "extension_conflict"

  @security
  Scenario: Every operator action is audited
    When "op-owner" holds, releases and ends events with reasons
    Then each action has an event_operations row with operator_id, kind, reason, before and after
    And an action without a reason is refused with status 422

  @happy
  Scenario: Preview shows the calendar at any instant for synthetic facts
    Given "op-qa" holds a preview token
    When the token is used for GET /admin/preview/events with at "2026-11-06T00:00:00Z", platform "ios", app_version "2.5.0", country "VN", timezone "Asia/Ho_Chi_Minh"
    Then server_now is "2026-11-06T00:00:00.000Z"
    And "evt-harvest-season" is in events with state "ending-soon"
    And the response has a preview object echoing the inputs and no participation
    And the response header Cache-Control is "no-store"

  @security
  Scenario Outline: A preview token cannot write
    Given "op-qa" holds a preview token
    When the token is used for <request>
    Then the response status is 403
    And the response error is "preview_read_only"

    Examples:
      | request                                               |
      | POST /api/events/evt-weekly-sprint-w44/join           |
      | POST /api/events/evt-weekly-sprint-w44/progress       |
      | POST /api/events/evt-weekly-sprint-w44/claim          |

  @security
  Scenario: A player session cannot reach preview and has no time parameter
    When acc-ann sends GET /admin/preview/events with at "2026-11-06T00:00:00Z"
    Then the response status is 401
    When acc-ann sends GET /api/events?at=2026-11-06T00:00:00Z
    Then server_now is "2026-10-27T12:00:00.000Z"

  @security
  Scenario: A preview token expires and drafts need the token
    Given a preview token issued at "2026-10-27T12:00:00Z" with PREVIEW_TOKEN_TTL_SECONDS 3600
    When the token is used at "2026-10-27T13:00:00Z"
    Then the response status is 401
    And include_drafts is honored only for a valid token

  @happy
  Scenario: A QA event exercises the real write path in real time
    Given acc-qa-1 is on the allow-list of "evt-qa-short"
    When acc-qa-1 joins, reports progress 1 and claims "q1"
    Then the ledger received grant(acc-qa-1, "coins", 1, "event-calendar.reward")
    And acc-ann cannot see or join "evt-qa-short"
