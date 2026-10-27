Feature: Calendar authoring checks
  As an event owner
  I want mistakes caught before an event can go live
  So that no overlap, overpayment or unfair audience reaches players

  Background:
    Given the app is configured for tenant "tenant-001"
    And the events from fixtures/events.json are published
    And the config values in fixtures/events.json are in effect
    And the clock is fixed at "2026-10-27T12:00:00Z"
    And the operator "op-owner" has the author, publisher and operator roles

  @happy
  Scenario: A valid draft passes with a reach and issuance estimate
    Given a draft copy of "evt-weekend-rush" with a new window
    And REACH_ACTIVE_WINDOW_SECONDS is 604800
    When the author sends POST /admin/events/{id}/check
    Then ok is true and problems is empty
    And reach_estimate is 7, the accounts in fixtures/accounts.json whose last session ended within 7 days
    And max_issuance is 2870 for "coins", 7 for "booster-hint" and 7 for "frame-sprint"

  @edge
  Scenario Outline: Each rule from the authoring cases is reported with its code
    Given the authoring case "<case>" in fixtures/events.json
    When the author sends POST /admin/events/{id}/check
    Then ok is false
    And problems contain the code "<code>" with severity "error"

    Examples:
      | case                         | code                         |
      | ends-before-starts           | ends_not_after_starts        |
      | exclusive-overlap            | exclusive_group_overlap      |
      | reward-cap-exceeded          | reward_cap_exceeded          |
      | reward-cap-missing           | reward_cap_missing           |
      | spend-based-audience         | audience_key_not_allowed     |
      | unreleased-version           | min_app_version_unreleased   |
      | local-window-shared-outcome  | local_window_shared_outcome  |
      | thresholds-not-increasing    | reward_trigger_invalid       |
      | asset-origin-not-allowed     | asset_origin_not_allowed     |

  @edge
  Scenario: Publish needs the lead time
    Given the authoring case "lead-time-too-short"
    When the publisher sends POST /admin/events/{id}/publish
    Then the response status is 422
    And problems contain "lead_time_too_short"

  @edge
  Scenario: A test event for allow-listed accounts is exempt from the lead time and the layer duration but not from a length limit
    Given a draft "allow_list_only" event of 7200 seconds starting in 60 seconds
    Then the check reports neither "lead_time_too_short" nor "duration_out_of_range"
    Given a draft "allow_list_only" event of 172800 seconds
    Then the check reports "allow_list_event_too_long"

  @security
  Scenario Outline: Audience keys about spending, value or price are refused
    Given a draft whose audience contains the key "<key>"
    When the author sends POST /admin/events/{id}/check
    Then problems contain "audience_key_not_allowed" for the path "audience.<key>"

    Examples:
      | key                |
      | lifetime_spend_min |
      | payer_status       |
      | purchase_count     |
      | predicted_value    |
      | price_tier         |
      | device_value_tier  |

  @security
  Scenario: One event has one reward table whatever the audience
    Given a draft with audience segment "lapsed_player" and a second reward table keyed by segment
    When the author sends POST /admin/events/{id}/check
    Then problems contain "reward_trigger_invalid" or "config_invalid"
    And no field of the definition makes a grant depend on the audience

  @edge
  Scenario: Rank rewards need a rank source that freezes final ranks
    Given a draft with a "rank" reward and no RankSource configured
    When the author sends POST /admin/events/{id}/check
    Then problems contain "rank_source_missing"

  @edge
  Scenario: A budget below reach times the table maximum is an error
    Given a draft of "evt-weekend-rush" with issuance_budget coins 1000
    When the author sends POST /admin/events/{id}/check
    Then problems contain "budget_exceeded" for "coins"

  @edge
  Scenario: Warnings must be acknowledged to publish
    Given a draft that would be the sixth live event for one audience at one instant
    When the author sends POST /admin/events/{id}/check
    Then ok is true and problems contain the warning "density_over_cap"
    When the publisher sends POST /admin/events/{id}/publish without acknowledge_warnings
    Then the response status is 422
    When the publisher sends POST /admin/events/{id}/publish with acknowledge_warnings true
    Then the response status is 200

  @happy
  Scenario: The calendar view reports a gap in a required layer
    Given the daily series has instances for 2026-10-27 and 2026-10-28 and none for 2026-10-29
    And REQUIRED_LAYERS is ["daily"]
    When the author sends GET /admin/calendar for the next 14 days
    Then the health list contains "layer_gap" for layer "daily" from "2026-10-29T12:00:00Z"

  @edge
  Scenario: Many events ending within an hour raise a cluster warning
    Given four events end between 2026-11-09T00:00:00Z and 2026-11-09T00:50:00Z and END_CLUSTER_MAX is 3
    When the author sends GET /admin/calendar
    Then the health list contains "end_cluster"

  @edge
  Scenario: A series expands into drafts once
    When the author sends POST /admin/events/series for "daily-jackpot" with three local days starting 2026-10-29
    Then three drafts exist with occurrence_index values in sequence
    When the same request is sent again
    Then no draft is added
    And a request for more than 60 instances answers "series_instances_exceeded"

  @edge
  Scenario: Exclusive-group overlap uses the outer bounds of local windows
    Given two local-window events in group "daily-bonus" whose resolved windows never overlap in one zone but whose outer bounds do
    When the author checks the second
    Then problems contain "exclusive_group_overlap"

  @security
  Scenario: Publishing freezes the event and records who did it
    When the publisher publishes a valid draft with reason "weekly plan"
    Then the event_operations table has a row of kind "publish" with the operator "op-owner" and the reason
    And a later PUT on the event answers 409 "event_frozen"

  @security
  Scenario: A second approver is required when configured
    Given PUBLISH_REQUIRES_SECOND_APPROVER is true and the draft was created by "op-owner"
    When "op-owner" sends POST /admin/events/{id}/publish
    Then the response status is 422
    And problems contain "second_approver_required"

  @edge
  Scenario: Unpublish works only before the start and without participation
    When the publisher unpublishes "evt-weekly-sprint-w45"
    Then the event is a draft again
    When the publisher unpublishes "evt-weekly-sprint-w44"
    Then the response status is 409

  @security
  Scenario: Authoring routes refuse a player session and a preview token
    When a player session sends POST /admin/events
    Then the response status is 401
    When a preview token sends POST /admin/events
    Then the response status is 403

  @edge
  Scenario Outline: A season reference is accepted only on a seasonal event and in a plain format
    Given a draft in layer "<layer>" with season_ref "<ref>"
    When the author sends POST /admin/events/{id}/check
    Then the code "season_ref_invalid" is <reported>

    Examples:
      | layer    | ref                                                              | reported     |
      | seasonal | season-2026-autumn                                               | not reported |
      | weekly   | season-2026-autumn                                               | reported     |
      | seasonal | season 2026 autumn                                               | reported     |
      | seasonal | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa | reported     |

  @security
  Scenario: The calendar does not look the season up in the pass
    Given a draft seasonal event with season_ref "season-that-the-pass-does-not-know"
    When the author sends POST /admin/events/{id}/check
    Then no call is made to engagement.season-pass
    And the check passes for that field

  @edge
  Scenario: A new event that repeats an earlier one without a series gets a warning
    Given the authoring case "repeat-without-series"
    When the author sends POST /admin/events/{id}/check
    Then problems contain the warning "repeat_without_series"
    And the message asks the author to link the event to a series so players are told it repeats

  @security
  Scenario: No reward trigger depends on a purchase
    Given the authoring case "purchase-trigger"
    When the author sends POST /admin/events/{id}/check
    Then problems contain "reward_trigger_invalid" for the trigger_kind "purchase"
    And the accepted trigger kinds are milestone, completion, participation, rank and compensation
