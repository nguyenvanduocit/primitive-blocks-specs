Feature: Upgrading an item as one unit across the ledger and the item table
  As a player
  I want an upgrade to either raise the level and spend the materials once, or return my materials
  So that a crash, a retry or a second tap never charges me for nothing or raises a level for free

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/definitions.json is published
    And the accounts from fixtures/account-states.json exist
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: A one-line upgrade spends first and then raises the level
    Given the config set "default"
    When the upgrade case "upgrade-happy" of fixtures/operation-cases.json runs
    Then one ledger spend of 200 "coins" with reason "items.upgrade" is made before the instance changes
    And "inst-002" is at level 3 and version 4
    And the operation is "applied" and its lock is cleared
    And the balance of "coins" is 140
    And one "item_upgraded" event is emitted

  @happy
  Scenario: A two-line upgrade spends in currency-code order
    Given the config set "default"
    When the upgrade case "upgrade-two-lines-applied" runs
    Then the ledger spends are "coins" 100 at step "s0" and "shards_ember" 20 at step "s1"
    And "inst-u1" is at level 3
    And the balances are 400 "coins" and 20 "shards_ember"

  @happy
  Scenario: The quote lists each line with its kind, balance and shortfall
    Given the config set "default"
    When the quote case "quote-two-lines" runs
    Then the lines carry kind "soft" for "coins" and "item" for "shards_ember"
    And the quote is not affordable with a shortfall of 15 "shards_ember"

  @edge
  Scenario: Replaying a completed upgrade returns the stored result
    Given the config set "default"
    When the upgrade case "upgrade-replay" runs
    Then the second result is the stored result of the first
    And exactly one ledger spend exists
    And "inst-002" is at level 3 and version 4

  @edge
  Scenario: The same request id with another body is a conflict
    Given the config set "default"
    When the upgrade case "upgrade-request-id-different-body" runs
    Then the second request is rejected with "idempotency_conflict"
    And exactly one ledger spend exists

  @edge
  Scenario Outline: A stale view or a changed cost spends nothing
    Given the config set "default"
    When the upgrade case "<case>" runs
    Then the request is rejected with "<error>"
    And no ledger call is made
    And the instance is unchanged

    Examples:
      | case                              | error            |
      | upgrade-cost-changed              | cost_changed     |
      | upgrade-cost-changed-by-publish   | cost_changed     |
      | upgrade-version-conflict          | version_conflict |
      | upgrade-max-level                 | max_level_reached |
      | upgrade-expired-instance          | item_expired     |

  @edge
  Scenario: A rejected second spend refunds the first
    Given the config set "default"
    When the upgrade case "upgrade-second-spend-rejected" runs
    Then the request is rejected with "insufficient_balance" and a shortfall of 15 "shards_ember"
    And the ledger calls are the spend of "coins", the rejected spend of "shards_ember" and a refund grant of 100 "coins" with reason "items.upgrade-refund"
    And the operation is "reverted" and its lock is cleared
    And the balances are 500 "coins" and 5 "shards_ember" and "inst-u1" is at level 2
    And one "item_upgrade_reverted" event is emitted

  @edge
  Scenario: A second request on a busy instance is refused before any spend
    Given the config set "default"
    When the upgrade case "upgrade-in-progress" runs
    Then the second request is rejected with "operation_in_progress"
    And the second request makes no ledger call

  @edge
  Scenario: Two devices upgrading at once spend once
    Given the config set "default"
    When the upgrade case "upgrade-parallel-two-devices" runs
    Then exactly one request is applied
    And the other answers "operation_in_progress" or "version_conflict"
    And exactly one ledger spend of 200 "coins" exists

  @edge
  Scenario Outline: A crash at any point ends in one of two states
    Given the config set "default"
    When the fault case "<case>" of upgrade_fault_cases runs
    Then after the recovery job the outcome matches the case's expectation
    And the player is never charged without a level or a refund

    Examples:
      | case                              |
      | crash-after-first-spend           |
      | crash-after-all-spends            |
      | crash-after-apply-before-mark     |
      | version-bumped-after-spend        |
      | ledger-unavailable-before-spend   |
      | recovery-runs-twice               |

  @edge
  Scenario: A retired item can be upgraded unless the config forbids it
    Given the config set "default"
    When the upgrade case "upgrade-retired-allowed" runs
    Then "inst-r1" is at level 2 and the balance of "coins" is 150
    When the config set is "retired_no_upgrade" and the upgrade case "upgrade-retired-blocked" runs
    Then the request is rejected with "item_retired"

  @security
  Scenario: A client cannot send a level
    Given the config set "default"
    When the upgrade case "upgrade-client-sends-level" runs
    Then the request is rejected with "invalid_request"
    And no ledger call is made
    And "inst-002" is still at level 2 and version 3

  @security
  Scenario: Another account's instance looks like a missing one
    Given the config set "default"
    When the case "other-accounts-instance" of discard_and_convert_cases runs
    Then both ids answer "item_not_found" with the same body shape
