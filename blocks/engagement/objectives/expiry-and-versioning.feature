Feature: Expiry, reset and definition versioning
  As a designer and as a player
  I want windows to end predictably, a missed day to cost nothing, and edits to content never to change goals in flight
  So that the rules are stated, fair, and safe to change

  Background:
    Given the app is configured for tenant "tenant-001"
    And the content set from fixtures/definitions.json is published
    And CARRY_OVER_MIN_PERCENT is 80 and UNCLAIMED_AT_RESET is "stay_claimable"
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And I am authenticated as "acct-001" with timezone "Asia/Ho_Chi_Minh"
    And a fake ledger holds account "acct-001" with no balances
    And every client event for a play metric carries attempt_id "att-confirmed", which the attempt hook reports as "confirmed"

  @happy
  Scenario: An unfinished daily goal expires with its final count
    Given the daily instance of daily.collect-20 for window "2026-10-21" is "active" with progress 8 of 20
    When the clock is "2026-10-21T17:00:01Z" and I send GET /api/objectives?scope=daily
    Then the instance is "expired" with progress 8 of 20 and its window_key is "2026-10-21"
    And a new daily window "2026-10-22" is assigned
    And an objective_expired event is fired with progress_percent 40 and carried false

  @edge
  Scenario: Expiry needs no scheduled job
    Given no sweep job has run
    When the clock is "2026-10-21T17:00:01Z" and I send any authenticated request
    Then the earlier daily window is already closed and its unfinished instances are "expired"

  @edge
  Scenario: A finished goal of a closed window stays claimable
    Given the daily instance of daily.win-3 for window "2026-10-21" is "completed"
    When the clock is "2026-10-22T01:00:00Z" and I send GET /api/objectives
    Then the instance is still "completed" and has no deadline
    And the response rules show unclaimed_at_reset "stay_claimable"

  @edge
  Scenario: With auto_grant the server claims finished goals when the window closes
    Given UNCLAIMED_AT_RESET is "auto_grant"
    And the case "auto-grant-pays-at-reset" in fixtures/merge-and-version-cases.json unclaimed_at_reset
    When the clock is "2026-10-22T01:00:00Z" and I send GET /api/objectives twice
    Then the instance is "claimed" with claim_source "auto"
    And the ledger key and call counts match the case "expected"
    And the response rules show unclaimed_at_reset "auto_grant"

  @edge
  Scenario Outline: Carry-over moves progress once, and only near completion
    Given the case "<case>" in fixtures/merge-and-version-cases.json carry_over
    When the clock is "2026-10-25T17:00:01Z" and I send GET /api/objectives?scope=weekly
    Then the old and next instances match the case "expected"

    Examples:
      | case                            |
      | at-threshold-carries            |
      | below-threshold-forfeits        |
      | almost-complete-carries         |
      | completed-does-not-carry        |
      | carried-progress-carries-once   |

  @edge
  Scenario: Distinct-day goals forfeit even with a high count
    Given weekly.active-5-days is "active" with progress 4 of 5 and reset_policy "forfeit"
    When the clock is "2026-10-25T17:00:01Z" and I send GET /api/objectives?scope=weekly
    Then it is "expired" and the new window's instance starts at 0 with carried_in 0

  @edge
  Scenario: A missed day takes nothing
    Given the case "missed-day-costs-nothing" in fixtures/assignment-cases.json bank_cases
    When the player returns on window "2026-10-23"
    Then no instance exists for window "2026-10-22" and no expiry event was fired for it
    And no currency was deducted and the reroll bank did not shrink

  @happy
  Scenario: An in-flight instance keeps the version it was assigned under
    Given the case "in-flight-instance-keeps-its-version" in fixtures/merge-and-version-cases.json versioning
    When version 2 is published and the match_won event arrives
    Then the in-flight instance and the next window's assignment match the case "expected"

  @edge
  Scenario: A retired objective is never assigned again but finishes where it runs
    Given the case "retired-definition" in fixtures/merge-and-version-cases.json versioning
    When the objective is retired and the next daily window is assigned
    Then the result matches the case "expected"

  @edge
  Scenario Outline: A retroactive migration may only favor the player
    Given the case "<case>" in fixtures/merge-and-version-cases.json migrations
    When the migration is applied
    Then the outcome matches the case "expected"

    Examples:
      | case                         |
      | lower-target-is-allowed      |
      | raise-reward-is-allowed      |
      | raise-target-is-rejected     |
      | lower-reward-is-rejected     |
      | metric-change-needs-a-new-id |

  @edge
  Scenario Outline: Publishing a content set that breaks a rule fails and changes nothing
    Given the change named "<name>" in fixtures/definitions.json invalid_definitions
    When the changed set is published
    Then publishing fails with the error "<error>"
    And the active set is unchanged

    Examples:
      | name                              | error                                   |
      | premium-on-client-reported-metric | premium_reward_requires_trusted_metric  |
      | premium-via-alt-source            | premium_reward_requires_trusted_metric  |
      | premium-reward-scalable           | premium_reward_not_scalable             |
      | forbidden-metric-source           | forbidden_metric_source                 |
      | unreachable-daily-target          | target_exceeds_metric_cap               |
      | unreachable-weekly-target         | target_exceeds_metric_cap               |
      | prerequisite-cycle                | prerequisite_cycle                      |
      | prerequisite-outside-plan         | prerequisite_outside_plan               |
      | window-scope-lifetime-counting    | counting_not_allowed_for_scope          |
      | hidden-objective                  | hidden_requires_achievement             |
      | achievement-that-resets           | achievement_scope                       |
      | carry-over-in-pool                | carry_over_in_pool                      |
      | scope-reset-mismatch              | reset_policy_scope_mismatch             |
      | validator-missing                 | validator_missing                       |
      | empty-reward                      | reward_empty                            |
      | non-positive-target               | target_not_positive                     |
      | unknown-metric                    | unknown_metric                          |
      | pool-draw-too-large               | draw_count_exceeds_groups               |
      | tier-out-of-range                 | tier_out_of_range                       |
      | chain-tier-descends               | chain_tier_descends                     |
      | occupies-in-fixed-plan            | occupies_requires_skippable_board       |
      | daily-plan-without-normal-play    | plan_without_normal_play_objective      |
      | alt-source-on-max-metric          | alt_source_not_allowed                  |
      | milestone-with-points             | milestone_points_not_allowed            |
      | ladder-not-below-task-points      | ladder_not_below_task_points            |
      | ladder-rung-wrong-kind            | ladder_rung_kind                        |
      | reward-flow-not-registered        | reward_flow_not_registered              |
      | objective-id-too-long             | objective_id_too_long                   |
      | speedup-metric-source             | forbidden_metric_source                 |
      | invitation-to-buy-metric-source   | forbidden_metric_source                 |
      | social-invite-in-fixed-plan       | social_invite_requires_skippable_board  |
      | attempt-hook-missing              | attempt_hook_missing                    |
      | reroll-bank-below-earn            | reroll_bank_invalid                     |

  @happy
  Scenario: The unchanged set publishes with its warnings
    When the content set from fixtures/definitions.json is published
    Then publishing succeeds
    And the warnings equal "expected_publish_warnings" with "pool_narrow" for plan "daily"

  @security
  Scenario: A player cannot publish content
    When I send a publish request with my player session
    Then no such route exists or the response status is 401 or 403
    And the active set is unchanged

  @edge
  Scenario: The board footer states what happens to unclaimed rewards
    When I send GET /api/objectives?scope=daily
    Then the response carries rules.unclaimed_at_reset
    And the value is "stay_claimable" when the configuration is stay_claimable and "auto_grant" when it is auto_grant
