Feature: Onboarding, outages, guest merge and account deletion
  As an operator and as a player
  I want first claims, downtime, linking and deletion to behave fairly
  So that nobody is punished for our outage and nothing outlives a deleted account

  Background:
    Given the app is configured for tenant "tenant-001"
    And the calendar and settings from fixtures/calendar-config.json
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: A new account sets its zone and claims for the first time
    Given account "acc-new" has no streak state
    When I send GET /api/streak
    Then the response is { "needs_timezone": true } with server_now
    When I send PUT /api/streak/timezone with { "timezone": "Europe/Berlin" }
    Then streak_states exists with current_streak 0 and settled_through_day_key null
    And no timezone_changes row counts toward the limit
    When "acc-new" completes 1 "level_complete" action and claims
    Then current_streak is 1, cycle_day is 1 and longest_streak is 1

  @happy
  Scenario: A claim before the zone is set is refused
    Given account "acc-new" has no streak state
    When I send POST /api/streak/claim with an empty body
    Then the response status is 409 with error "timezone_required"

  @edge
  Scenario Outline: Downtime excuses missed days that the outage covered
    Given the downtime windows in fixtures/account-cases.json downtime
    And the case "<case>" state_before is stored with MISS_POLICY "reset"
    When the claim runs at the case clock
    Then the per-day coverage equals the case per_day values
    And the result matches the case expected block

    Examples:
      | case                       |
      | downtime-etc-utc           |
      | downtime-pacific-kiritimati |

  @edge
  Scenario: Excused days cost no freeze
    Given "acc-ann" holds 1 freeze and the downtime-etc-utc case state_before
    When the claim runs
    Then both missed days are recorded with kind "excused"
    And freezes_held is still 1

  @edge
  Scenario: Rewards stuck after an outage are delivered with their original keys
    Given the pending_grant claim in fixtures/account-cases.json
    When the recovery sweep runs
    Then the ledger receives exactly the expected_ledger_calls, in order
    And the freeze line is not sent

  @happy
  Scenario Outline: Guest progress joins the account without inflating the streak
    Given the merge case "<case>" in fixtures/account-cases.json merge_cases
    When mergeAccounts(from guest, into account, <merge_id>) runs
    Then the result status is "merged" and the into row equals the case expected block
    And the guest row is a tombstone with merged_into_account_id and merge_id set
    And the guest rows in daily_claims, daily_play, protection_orders and timezone_changes are deleted

    Examples:
      | case                | merge_id   |
      | guest-streak-wins   | merge-0001 |
      | account-streak-wins | merge-0002 |
      | tie-keeps-account   | merge-0003 |

  @edge
  Scenario: A second merge with the same merge_id changes nothing
    Given the sequence merge_idempotency in fixtures/account-cases.json
    When call 1 runs and then call 2 with the same merge_id "merge-0100"
    Then call 2 returns status "already_merged"
    And the into row, its version and the tombstone are unchanged

  @edge
  Scenario: A tombstoned guest cannot be merged into another account
    Given the sequence merge_idempotency in fixtures/account-cases.json after call 1
    When call 3 runs with merge_id "merge-0101" into "acc-ben"
    Then it fails with error "already_merged" and no row changes

  @edge
  Scenario: Missing and self merges are refused or empty
    Given the sequence merge_idempotency in fixtures/account-cases.json
    When call 4 runs for "acc-never-played" and call 5 runs with from equal to into
    Then call 4 returns status "nothing_to_merge" and call 5 fails with error "invalid_request"

  @edge
  Scenario: Two concurrent merges with one merge_id end with one winner
    Given a guest with a streak of 4 and an account with a streak of 3
    When two mergeAccounts calls with merge_id "merge-0200" run at the same instant
    Then exactly one returns "merged" and the other returns "already_merged"
    And the into row version rose once

  @happy
  Scenario Outline: The link preview lists what the account holds
    Given the holdings case "<account>" in fixtures/account-cases.json holdings
    When holdings(account) is called
    Then the result equals the case expected list

    Examples:
      | account          |
      | acc-guest-1      |
      | acc-guest-2      |
      | acc-guest-3      |
      | acc-never-played |
      | acc-guest        |

  @edge
  Scenario: A guest claim today does not create or remove a grant at merge
    Given the guest claimed "2026-10-27" and the account row has not
    When the accounts are merged
    Then the ledger receives no call from this block
    And today is claimable once for the merged account

  @security
  Scenario: A client cannot trigger a merge or read holdings
    When I send POST /api/streak/merge with { "from": "acc-guest", "into": "acc-ann" }
    Then the response status is 404
    And GET /api/streak/holdings also answers 404 and no row changes

  @security
  Scenario: Account deletion removes every row of the account
    Given "acc-ann" has rows in streak_states, daily_claims, daily_play, protection_orders and timezone_changes
    When compliance.account-deletion calls deleteAccount("acc-ann")
    Then none of those tables holds a row with account_id "acc-ann"
    And rows of "acc-ben" are untouched

  @edge
  Scenario: The guest purge removes the merge tombstone
    Given the merge_idempotency sequence ran call 1 and "acc-guest" is a tombstone
    When the guest purge calls deleteAccount("acc-guest")
    Then streak_states holds no row for "acc-guest"

  @edge
  Scenario: Pruning old claims does not change the streak
    Given "acc-ann" has current_streak 450 and daily_claims rows older than CLAIM_RETENTION_DAYS
    When retention runs
    Then the old rows are deleted
    And current_streak and longest_streak are unchanged
