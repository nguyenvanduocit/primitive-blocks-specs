Feature: Guest to account merge
  As a player who started as a guest and then signed in
  I want my energy to follow me without doubling
  So that merging never gives or takes more than I held

  Background:
    Given the app is configured for tenant "tenant-001"
    And the meters and settings from fixtures/meter-config.json exist
    And "acct-0002" is a guest account and "acct-0001" is the signed-in account
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario: The higher value wins and the later boost is kept
    Given "acct-0001" has meter "energy" value 1 with anchor_at "2026-10-21T11:50:00Z"
    And "acct-0002" has meter "energy" value 3 with anchor_at "2026-10-21T11:58:20Z" and boost_ends_at "2026-10-21T12:10:00Z"
    When mergeAccounts("acct-0002", "acct-0001", "m1") runs
    Then "acct-0001" has value 3, next_tick_at "2026-10-21T12:28:20Z" and boost_ends_at "2026-10-21T12:10:00Z"
    And no meter row exists for "acct-0002"
    And fixtures/api-cases.json case "merge-takes-the-higher-value" matches

  @edge
  Scenario: Merging is idempotent per merge id
    Given the merge "m1" already ran
    When mergeAccounts("acct-0002", "acct-0001", "m1") runs again
    Then the result is the original and no value changes
    And exactly one entry with key "energy-lives:merge:m1" exists

  @edge
  Scenario: Points are never summed
    Given "acct-0001" has meter "energy" value 5 and "acct-0002" has value 5
    When the accounts are merged
    Then "acct-0001" has value 5

  @edge
  Scenario: Points above the cap survive when they are the higher value
    Given "acct-0001" has meter "energy" value 2 and "acct-0002" has value 8 earned through grants
    When the accounts are merged
    Then "acct-0001" has value 8 and next_tick_at is null

  @edge
  Scenario: Equal values keep the earlier anchor
    Given both accounts have value 2 with anchors "2026-10-21T11:50:00Z" and "2026-10-21T11:55:00Z"
    When the accounts are merged
    Then the merged anchor_at is "2026-10-21T11:50:00Z"

  @edge
  Scenario: The guest's open attempts end by their due-instant rules before the merge
    Given "acct-0002" has an unconfirmed attempt older than confirm_timeout_seconds
    When the accounts are merged
    Then the attempt ends "cancelled" with its refund applied to the guest meter first
    And the merged value reflects the refund

  @edge
  Scenario: A pending refill of the guest is completed before the merge
    Given "acct-0002" has a pending refill entry whose ledger spend applied
    When the accounts are merged
    Then the entry is "applied" under "acct-0002" and the merged value includes it

  @security
  Scenario: Accounts of another tenant are refused
    Given "acct-0002" belongs to tenant "tenant-002"
    When mergeAccounts("acct-0002", "acct-0001", "m9") runs in tenant "tenant-001"
    Then nothing is merged and the call reports "unknown_account"

  @security
  Scenario: A merge cannot be called from a player route
    When a player sends POST /api/energy/merge
    Then the response status is 404
