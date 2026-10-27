Feature: Claim the daily reward
  As a player
  I want to claim today's reward once, on any device, even when requests repeat or race
  So that I get exactly one reward per day and never lose a claim to a glitch

  Background:
    Given the app is configured for tenant "tenant-001"
    And the calendar and settings from fixtures/calendar-config.json
    And the clock is fixed at "2026-10-27T12:00:00Z"
    And account "acc-ann" is authenticated with timezone "Etc/UTC" and no streak state history

  @happy
  Scenario: The first claim starts the streak and grants through the ledger
    Given "acc-ann" has 1 qualifying "level_complete" action today
    When I send POST /api/streak/claim with an empty body
    Then the response status is 200 and already_claimed is false
    And the claim has day_key "2026-10-27", streak 1 and cycle_day 1
    And the ledger received grant("acc-ann", "coin", 100, "daily-streak.claim", <claim id>, "daily-streak:acc-ann:2026-10-27:1")
    And daily_claims holds one row with kind "claim" for "2026-10-27"
    And the claim ends with grant_status "granted"

  @happy
  Scenario: With claim_requirement open_app no play is needed
    Given CLAIM_REQUIREMENT is "open_app"
    When I send POST /api/streak/claim with an empty body
    Then the response status is 200 and the streak is 1

  @edge
  Scenario: play_to_claim without qualifying play is refused and changes nothing
    Given "acc-ann" has 0 qualifying actions today
    When I send POST /api/streak/claim with an empty body
    Then the response status is 409 with error "requirement_not_met", play_count 0 and play_target 1
    And no daily_claims row exists and the ledger received no call

  @edge
  Scenario: A repeated claim returns the original claim and grants nothing more
    Given "acc-ann" has 1 qualifying "level_complete" action today
    And I have claimed today
    When I send POST /api/streak/claim with an empty body again
    Then the response status is 200 and already_claimed is true
    And the claim id equals the first claim id
    And the ledger holds exactly one entry per grantable line for "2026-10-27"

  @edge
  Scenario: Two devices claim at the same moment
    Given "acc-ann" has 1 qualifying "level_complete" action today
    When device A and device B each send POST /api/streak/claim at the same instant
    Then exactly one daily_claims row exists for "2026-10-27"
    And exactly one response has already_claimed false and the other has already_claimed true
    And both responses carry the same claim id
    And the ledger holds exactly one entry per grantable line
    And current_streak is 1

  @edge
  Scenario: The ledger is unreachable after the claim commits
    Given "acc-ann" has 1 qualifying "level_complete" action today
    And the ledger times out on every grant
    When I send POST /api/streak/claim with an empty body
    Then the response status is 200 with grant_status "pending"
    And current_streak is 1
    When the ledger recovers and the recovery sweep runs after RECOVERY_GRACE_SECONDS
    Then the sweep calls grant with the same idempotency keys
    And the claim ends with grant_status "granted" and the ledger holds one entry per line

  @edge
  Scenario: The ledger rejects a currency code permanently
    Given "acc-ann" has 1 qualifying "level_complete" action today
    And the ledger rejects code "coin" as unknown
    When I send POST /api/streak/claim with an empty body
    Then the claim ends with grant_status "failed" and an operator alert is raised
    And current_streak is 1

  @edge
  Scenario: A play counts only from an attempt in a proof state
    Given PLAY_PROOF_SOURCE is "attempt" and PLAY_TARGET is 3
    And the attempt states and events in fixtures/account-cases.json play_counter
    When each event is recorded in order through recordPlay
    Then each answer equals the listed expect block
    And "att-003" (open), "att-006" (cancelled) and "att-099" (unknown) add no daily_play row
    And "att-001" replayed on "2026-10-28" is not counted again and play_count for that day is 0

  @security
  Scenario: A client cannot count a play without a proven attempt
    Given PLAY_REPORT_SOURCE is "client" and attemptState("acc-ann", "att-fake") is null
    When I send POST /api/streak/play with { "action": "level_complete", "attempt_id": "att-fake" }
    Then the response status is 409 with error "play_not_proven" and reason "attempt_unknown"
    And no daily_play row exists and POST /api/streak/claim answers "requirement_not_met"

  @security
  Scenario: A client cannot choose the day
    When I send POST /api/streak/claim with { "day_key": "2026-10-28" }
    Then the response status is 422 with error "unexpected_field"
    And no state or claim changes

  @security
  Scenario: A client cannot choose the account
    Given account "acc-ben" exists with a streak of 2
    When I authenticate as "acc-ann" and send POST /api/streak/claim with { "account_id": "acc-ben" }
    Then the response status is 422 with error "unexpected_field"
    And the streak of "acc-ben" is still 2
