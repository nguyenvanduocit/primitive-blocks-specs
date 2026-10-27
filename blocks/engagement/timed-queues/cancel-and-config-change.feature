Feature: Cancel and refund, and config changes while items run
  As a player
  I want to know what a cancel returns before I start, and to keep the numbers I was shown
  So that changing my mind costs only what was stated and an update never lengthens or shrinks my work

  Background:
    Given the app is configured for tenant "tenant-001"
    And the definition set and configuration from fixtures/catalog.json are published
    And account "acct-001" is signed in with timezone "Asia/Ho_Chi_Minh"
    And the wallet is the "balances" preset of fixtures/catalog.json
    And item "item-0001" of "craft.bread" runs from "2026-10-21T12:00:00Z" to "2026-10-21T12:15:00Z" in craft slot 0
    And the clock is fixed at "2026-10-21T12:05:00Z"

  @happy
  Scenario: Cancelling a queued item returns every input line
    Given item "item-0002" of "craft.bread" is queued behind item "item-0001" and the "flour" balance is 3
    And the clock is fixed at "2026-10-21T12:05:30Z"
    When I cancel item "item-0002"
    Then the ledger received a grant of 3 "flour" with reason "timed-queues.cancel-refund" and key "timed-queues:acct-001:item-0002:refund:1"
    And item "item-0002" is cancelled with cancel_reason "player" and input_status "refunded"
    And the "flour" balance is 6
    And the hand-off for "queue-item:item-0002" is resolved
    # fixture: fixtures/lifecycle-cases.json case "cancel-queued-full-refund"

  @happy
  Scenario: Cancelling a running item returns the snapshot fraction of each line, rounded down
    Given item "item-0001" is "craft.jam" started with 40 "coins" and 5 "berries" and a snapshot fraction of 0.50
    And the clock is fixed at "2026-10-21T12:10:00Z"
    When I cancel item "item-0001"
    Then the refund lines are 20 "coins" and 2 "berries"
    And the ledger received grants with keys "timed-queues:acct-001:item-0001:refund:1" and "timed-queues:acct-001:item-0001:refund:2"
    And the "coins" balance is 980 and the "berries" balance is 2
    # fixture: fixtures/lifecycle-cases.json case "cancel-running-by-snapshot-fraction"

  @edge
  Scenario: Repeating a cancel returns the original result and refunds nothing more
    Given I cancelled item "item-0002"
    When I cancel item "item-0002" again
    Then the response has already_cancelled true
    And the ledger received no call

  @edge
  Scenario: A finished item cannot be cancelled
    Given the clock is fixed at "2026-10-21T12:16:00Z"
    When I cancel item "item-0001"
    Then the response error is "invalid_transition" with state "ready"
    And the ledger received no call

  @edge
  Scenario: Cancelling a running item moves its queued followers earlier
    Given item "item-0002" is queued from "2026-10-21T12:15:00Z" to "2026-10-21T12:30:00Z"
    When I cancel item "item-0001"
    Then item "item-0002" runs from "2026-10-21T12:05:00Z" to "2026-10-21T12:20:00Z"
    And the hand-off for "queue-item:item-0002" is armed again with a larger revision and an earlier fire_at
    And no start or end time moved later

  @edge
  Scenario: Speed-ups already paid are not returned by a cancel
    Given item "item-0001" was sped up by 3600 seconds with a charge of 11 "gems"
    When I cancel item "item-0001"
    Then the refund lines cover only the input lines
    And the "gems" balance is unchanged by the cancel

  @edge
  Scenario: A refund comes from the item's snapshot and not from the current definition
    Given the operator publishes version 2 with "craft.bread" input of 6 "flour", output of 3 "bread" and cancel_refund_fraction 1.00
    And the clock is fixed at "2026-10-21T12:03:00Z"
    When I cancel item "item-0001"
    Then the refund lines are 1 "flour" because floor(3 times 0.50) comes from the snapshot
    # fixture: fixtures/lifecycle-cases.json case "snapshot-keeps-refund-input-and-output"

  @edge
  Scenario: Collecting pays the output snapshot and not the current definition
    Given the operator publishes version 2 with "craft.bread" output of 3 "bread"
    And the clock is fixed at "2026-10-21T12:20:00Z"
    When I collect item "item-0001"
    Then the ledger received a grant of 2 "bread" with key "timed-queues:acct-001:item-0001:collect:1"

  @happy
  Scenario: A longer duration applies to new items only
    Given the operator publishes version 2 with "craft.bread" duration_seconds 1800
    Then no existing item changed
    When the clock is "2026-10-21T12:14:59Z" and I list the queues
    Then item "item-0001" is running with ends_at "2026-10-21T12:15:00Z" and definition_version 1
    When the clock is "2026-10-21T12:16:00Z" and I start "craft.bread" with attempt "att-080"
    Then the new item has definition_version 2, duration_seconds 1800 and ends_at "2026-10-21T12:46:00Z"
    # fixture: fixtures/lifecycle-cases.json case "config-lengthen-leaves-running-items-alone"

  @happy
  Scenario: An operator rebase shortens running and queued items and never lengthens
    Given item "item-0002" of "craft.bread" is queued from "2026-10-21T12:15:00Z" to "2026-10-21T12:30:00Z"
    And the operator publishes version 2 with "craft.bread" duration_seconds 600
    When the operator runs rebase_shorter for "craft.bread" at version 2 with a reason
    Then item "item-0001" ends at "2026-10-21T12:10:00Z" and item "item-0002" runs from "2026-10-21T12:10:00Z" to "2026-10-21T12:20:00Z"
    And both items have schedule_version 2 and notice_revision 2 and both hand-offs are armed again
    And a "queue_item_rebased" event is written with the operator's reason
    When the operator runs the same rebase again
    Then no item changed
    When the operator publishes version 3 with duration_seconds 1200 and runs rebase_shorter at version 3
    Then no item changed because a rebase takes the minimum
    # fixture: fixtures/lifecycle-cases.json case "operator-rebase-shortens-only"

  @edge
  Scenario: A retired job finishes its running items
    Given the operator publishes a version that retires "craft.bread"
    Then item "item-0001" still runs to "2026-10-21T12:15:00Z" and collects its snapshot output
    And starting "craft.bread" answers "job_retired"

  @edge
  Scenario: Lowering the slot maximum never removes an unlocked slot or an item
    Given craft slot 1 is unlocked and a version lowers craft max_slots to 1
    Then craft slot 1 stays active with its items
    And the new maximum bounds only new unlocks and new starts

  @edge
  Scenario: A set that fails validation leaves the previous set active
    When the operator publishes a version in which "craft.jam" needs 1 "gems" as input
    Then publishing fails with "premium_input" and the active definition_version is 1
    And no event "queue_definitions_published" is written

  @edge
  Scenario Outline: Each validation rule refuses its own bad set
    When the operator publishes the set with the change "<change>"
    Then publishing fails with "<error>" naming validation "<rule>"

    Examples:
      | change                                              | error                         | rule |
      | expedition.long duration_seconds is 50000           | duration_over_cap             | V2   |
      | craft.jam gains a gems input                        | premium_input                 | V3   |
      | craft.bread gains a moonstone input with no faucet  | input_without_faucet          | V4   |
      | craft max_slots is 6                                | handoff_capacity_exceeded     | V6   |
      | build.farm.l2 requires build.farm.l3                | prerequisite_cycle            | V7   |
      | craft.bread cancel_refund_fraction is 1.5           | refund_fraction_out_of_range  | V7   |
      | slot_craft_plus becomes a consumable product        | slot_product_invalid          | V8   |
    # fixture: fixtures/catalog.json "invalid_definitions"

  @edge
  Scenario: The cancel terms are shown before the start and match the snapshot
    When I open the start sheet for "craft.jam"
    Then the sheet states that a waiting item returns everything and a running item returns 50 percent
    And an item started now snapshots cancel_refund_fraction 0.50

  @security
  Scenario: A client cannot change what a cancel returns
    When I send a cancel with a body that carries "refund_lines" or "fraction"
    Then the response error is "unexpected_field" and nothing is refunded

  @security
  Scenario: Another account's item cannot be cancelled
    Given account "acct-002" owns a running item "item-9001"
    When account "acct-001" cancels item "item-9001"
    Then the response error is "item_not_found" and the ledger received no call
