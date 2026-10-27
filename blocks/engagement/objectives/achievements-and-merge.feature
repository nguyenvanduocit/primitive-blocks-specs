Feature: Achievements and account merge
  As a player
  I want lifetime achievements that never reset, secrets that stay secret until I earn them, and my guest progress to join my account
  So that long-term effort is honored and nothing is lost or paid twice when I sign in

  Background:
    Given the app is configured for tenant "tenant-001"
    And the content set from fixtures/definitions.json is published
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And I am authenticated as "acct-001" with timezone "Asia/Ho_Chi_Minh"
    And a fake ledger holds account "acct-001" with no balances
    And the validator accepts event refs that start with "run-ok-"
    And every client event for a play metric carries attempt_id "att-confirmed", which the attempt hook reports as "confirmed"

  @happy
  Scenario: Achievements never reset
    Given ach.levels.1 is "claimed" and ach.levels.2 is "active" with progress 30 of 50
    When the clock moves to "2026-11-30T12:00:00Z" and I send GET /api/objectives?scope=lifetime
    Then every achievement instance is unchanged
    And no achievement instance has state "expired" and all have ends_at null
    And the daily, weekly and seasonal windows have rolled without touching them

  @happy
  Scenario: A tier shows the true lifetime total
    Given the account's counter for level_completed is 60 before the lifetime plan is first assigned
    When I send GET /api/objectives?scope=lifetime
    Then ach.levels.1 and ach.levels.2 are "completed"
    And ach.levels.3 is "active" with progress 60 of 250
    And the ledger has received no grant

  @happy
  Scenario: Completing a tier unlocks the next on completion, not on claim
    Given ach.levels.1 is "active" with progress 9 of 10 and ach.levels.2 is "locked"
    When I send POST /api/objectives/events with one level_completed event, ref "run-ok-1"
    Then ach.levels.1 is "completed"
    And ach.levels.2 is "active" with progress 10 of 50
    And the instance of ach.levels.1 is not claimed

  @edge
  Scenario: A server-derived maximum completes a lifetime achievement
    When the daily-streak adapter calls ingest_server_event with source "engagement.daily-streak", source_ref "streak-7", metric streak_length, amount 7
    Then ach.streak-7 is "completed"

  @edge
  Scenario: A hidden achievement is absent from every response until earned
    Given ach.secret-high-score is "active" and the best run_score so far is 7000
    When I send GET /api/objectives?scope=lifetime
    Then no item has objective_id "ach.secret-high-score"
    And the raw response body does not contain the text "ach.secret-high-score" or "9000"
    And claimable_count and every total exclude it

  @edge
  Scenario: Earning a hidden achievement reveals it with full details
    Given ach.secret-high-score is "active"
    When I send POST /api/objectives/events with one run_score event of amount 9500
    Then the response lists ach.secret-high-score in completed
    And GET /api/objectives?scope=lifetime now returns it as "completed" with its title key, target 9000 and reward
    And it can be claimed like any objective

  @edge
  Scenario: A lifetime_total objective published later back-fills from the true counter
    Given the account's counter for level_completed is 60
    When a new definition "ach.levels.new" with counting "lifetime_total" and target 40 becomes active and the lifetime plan is settled
    Then its instance is "completed"
    And a definition with the same target and counting "since_activation" would start at progress 0

  @security
  Scenario: A client cannot unlock an achievement by reporting a server-derived metric
    When I send POST /api/objectives/events with one streak_length event of amount 7
    Then the result is "rejected" with reason "metric_not_client_reportable"
    And ach.streak-7 is not "completed"

  @happy
  Scenario: Merging a guest account joins counters, rows and banks
    Given the case "merge" in fixtures/merge-and-version-cases.json is seeded for "acct-guest-001" and "acct-001"
    When the guest-account block calls mergeAccounts("acct-guest-001", "acct-001", "merge-001")
    Then the counters, the listed instances and the reroll banks match the case "expected"
    And no instance remains for "acct-guest-001"

  @security
  Scenario: A merge pays nothing
    Given the case "merge" is seeded
    When the guest-account block calls mergeAccounts("acct-guest-001", "acct-001", "merge-001")
    Then the ledger has received no grant and no spend
    And the instance of starter.finish-level stays "claimed" and is not paid again

  @edge
  Scenario: Replaying a merge changes nothing
    Given merge "merge-001" was applied
    When the guest-account block calls mergeAccounts("acct-guest-001", "acct-001", "merge-001") again
    Then the result equals the first and no row changed

  @security
  Scenario: A guest account merges at most once
    Given merge "merge-001" was applied
    When the guest-account block calls mergeAccounts("acct-guest-001", "acct-002", "merge-002")
    Then the call fails with "already_merged"
    And the rows of "acct-002" are unchanged

  @edge
  Scenario: An earned hidden achievement stays earned after a merge
    Given the guest account earned ach.secret-high-score and the receiving account did not
    When the guest-account block calls mergeAccounts("acct-guest-001", "acct-001", "merge-003")
    Then ach.secret-high-score is "completed" for "acct-001"

  @edge
  Scenario: Achievements completed by the combined total complete after a merge
    Given the case "merge" is seeded
    When the guest-account block calls mergeAccounts("acct-guest-001", "acct-001", "merge-001")
    Then ach.levels.1 and ach.levels.2 are "completed" and ach.levels.3 is "active" with progress 52 of 250

  @security
  Scenario: A player session cannot merge accounts
    When I send a request to merge "acct-guest-001" into "acct-001" with my player session
    Then no such route exists or the response status is 401 or 403
    And no rows changed

  @happy
  Scenario Outline: Holdings tell the player what a conflict choice keeps
    Given the guest account of the case "<case>" in fixtures/merge-and-version-cases.json holdings
    When the guest-account block calls holdings for it
    Then the result equals the case "expected"
    And every entry has paid false

    Examples:
      | case          |
      | pristine-guest |
      | played-guest  |

  @edge
  Scenario: Deleting the account deletes its objective rows
    Given "acct-001" has instances, counters, events, a reroll bank and a merge record
    When compliance.account-deletion or the guest purge calls deleteAccount("acct-001") twice
    Then no row keyed by "acct-001" remains in any objective table
    And the second call changes nothing
