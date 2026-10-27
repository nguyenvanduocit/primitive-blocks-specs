Feature: Start an item
  As a player
  I want to start a build, craft, research or expedition and be charged once
  So that the item finishes while I am away and I never pay twice or lose an item

  Background:
    Given the app is configured for tenant "tenant-001"
    And the definition set and configuration from fixtures/catalog.json are published
    And account "acct-001" is signed in with timezone "Asia/Ho_Chi_Minh"
    And the wallet is the "balances" preset of fixtures/catalog.json
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario: Start a craft with one input line
    When I start job "craft.bread" in queue "craft" with attempt "att-001" on slot 0
    Then item "item-0001" is running with starts_at "2026-10-21T12:00:00Z" and ends_at "2026-10-21T12:15:00Z"
    And the ledger received one spend of 3 "flour" with reason "timed-queues.start" and key "timed-queues:acct-001:item-0001:start:1"
    And the "flour" balance is 6
    And the response carries an armed hand-off for "queue-item:item-0001" with fire_at "2026-10-21T12:15:00Z" and revision 1
    And the response carries server_now "2026-10-21T12:00:00Z"
    # fixture: fixtures/lifecycle-cases.json case "start-craft-bread"

  @happy
  Scenario: A second item chains behind the first and starts when the first ends
    Given item "item-0001" of "craft.bread" is running until "2026-10-21T12:15:00Z"
    And the clock is fixed at "2026-10-21T12:05:00Z"
    When I start job "craft.bread" in queue "craft" with attempt "att-002"
    Then item "item-0002" is queued with starts_at "2026-10-21T12:15:00Z" and ends_at "2026-10-21T12:30:00Z"
    And the "flour" balance is 3
    And no job or timer is scheduled to start item "item-0002"

  @happy
  Scenario: Two input lines are each spent once with their own key
    Given the wallet holds 1000 "coins" and 5 "berries"
    When I start job "craft.jam" in queue "craft" with attempt "att-010"
    Then the ledger received a spend of 40 "coins" with key "timed-queues:acct-001:item-0001:start:1"
    And the ledger received a spend of 5 "berries" with key "timed-queues:acct-001:item-0001:start:2"
    And the item has input_status "spent" and an input_snapshot of both lines

  @happy
  Scenario: A job with no input starts without a ledger call
    When I start job "expedition.short" in queue "expedition" with attempt "att-011"
    Then the item has input_status "none" and is running with ends_at "2026-10-21T13:00:00Z"
    And the ledger received no call

  @edge
  Scenario: The lane is full at its depth
    Given item "item-0001" is running and item "item-0002" is queued in craft slot 0
    When I start job "craft.bread" in queue "craft" with attempt "att-003"
    Then the response error is "lane_full"
    And the ledger received no call
    And the "flour" balance is unchanged
    # fixture: fixtures/lifecycle-cases.json case "chain-and-lane-depth"

  @edge
  Scenario: A short balance is rejected before anything is reserved or spent
    Given the wallet holds 1000 "coins" and 2 "berries"
    When I start job "craft.jam" in queue "craft" with attempt "att-011"
    Then the response error is "insufficient_balance" with currency "berries", needed 5, balance 2 and shortfall 3
    And no queue item row exists
    And the ledger received no call

  @edge
  Scenario: A later line that fails after an earlier line was spent returns the earlier line
    Given the wallet holds 1000 "coins" and 5 "berries"
    And another device spends 4 "berries" after the balance pre-check
    When I start job "craft.jam" in queue "craft" with attempt "att-012"
    Then the ledger received a spend of 40 "coins" with key "timed-queues:acct-001:item-0001:start:1"
    And the ledger rejected the spend of "berries" with "insufficient_balance"
    And the ledger received a grant of 40 "coins" with reason "timed-queues.cancel-refund" and key "timed-queues:acct-001:item-0001:start-undo:1"
    And item "item-0001" is cancelled with cancel_reason "input_rejected" and input_status "failed"
    And the slot is free and the "coins" balance is 1000
    And repeating attempt "att-012" returns the same refusal and no ledger call

  @edge
  Scenario: Repeating an attempt returns the original item and spends nothing
    Given I started job "craft.bread" with attempt "att-001"
    When I start job "craft.bread" in queue "craft" with attempt "att-001" on slot 0
    Then the response is the original item "item-0001" with replayed true
    And the ledger received no call
    And a "queue_item_started" event is written with replayed true

  @edge
  Scenario: The same attempt id with different arguments is a conflict
    Given I started job "craft.bread" with attempt "att-001"
    When I start job "craft.jam" in queue "craft" with attempt "att-001"
    Then the response error is "attempt_conflict"
    And the ledger received no call

  @edge
  Scenario: Two devices start at the same moment in the same slot
    Given the wallet holds 1000 "coins"
    When the phone starts "expedition.long" with attempt "att-030" on slot 0 and the tablet starts "expedition.long" with attempt "att-031" on slot 0 at the same instant
    Then exactly one item is created and the "coins" balance is 900
    And the tablet first receives "start_in_progress" and, on retry, "lane_full"
    And the tablet may start in slot 1 with its own attempt, which is a different lane
    # fixture: fixtures/lifecycle-cases.json case "two-devices-start-at-once"

  @edge
  Scenario: A crash after the spend leaves a record that recovery confirms
    Given a start of "craft.bread" with attempt "att-020" spent its input and the process died before the confirmation
    And the clock is fixed at "2026-10-21T12:01:10Z"
    When the recovery sweep runs
    Then the ledger replays the spend with key "timed-queues:acct-001:item-0001:start:1" and records no second entry
    And item "item-0001" is running with starts_at "2026-10-21T12:01:10Z" and ends_at "2026-10-21T12:16:10Z"
    And the "flour" balance is 6

  @edge
  Scenario: A crash before the spend and a balance that vanished cancels the reservation
    Given a start of "craft.bread" with attempt "att-021" was reserved and the process died before any spend
    And another device used all the flour
    And the clock is fixed at "2026-10-21T12:01:10Z"
    When the recovery sweep runs
    Then item "item-0001" is cancelled with cancel_reason "input_rejected"
    And the slot is free and the ledger received no entry

  @edge
  Scenario Outline: Unlock rules refuse a start in a fixed order
    Given the wallet holds 5000 "coins"
    When I start job "<job>" in queue "build" with attempt "<attempt>"
    Then the response is "<result>"

    Examples:
      | job            | attempt | result                                   |
      | build.farm.l3  | att-040 | job_locked reason prerequisite           |
      | build.farm.l2  | att-041 | item running                             |
      | build.farm.l2  | att-042 | job_locked reason max_active             |

  @edge
  Scenario: A job that is not repeatable cannot start again after it was collected
    Given "build.farm.l2" was started and collected
    When I start job "build.farm.l2" in queue "build" with attempt "att-043"
    Then the response error is "job_locked" with reason "not_repeatable"
    And starting "build.farm.l3" now succeeds
    # fixture: fixtures/lifecycle-cases.json case "prerequisites-and-repeatability"

  @edge
  Scenario: Stacked time in a lane is capped
    Given MAX_LANE_SECONDS is 30000 and "build.farm.l2" was collected
    And "build.farm.l3" is running in build slot 0 until "2026-10-21T20:00:00Z"
    When the clock is "2026-10-21T12:30:00Z" and I start "build.storage.l2" with attempt "att-051"
    Then the response error is "lane_time_cap" with projected_seconds 34200 and cap_seconds 30000
    When the clock is "2026-10-21T15:00:00Z" and I start "build.storage.l2" with attempt "att-052"
    Then the item is queued with starts_at "2026-10-21T20:00:00Z" and ends_at "2026-10-21T22:00:00Z"

  @edge
  Scenario: Too many finished items block a new start until the player collects
    Given READY_UNCOLLECTED_MAX is 2 and two craft items are ready and uncollected
    When I start job "craft.bread" in queue "craft" with attempt "att-060"
    Then the response error is "ready_uncollected_cap" with ready_count 2
    When I collect one of them and start again with attempt "att-061"
    Then the new item is running

  @edge
  Scenario: A retired job cannot be started but its running items finish
    Given item "item-0001" of "craft.old-recipe" is running until "2026-10-21T12:10:00Z"
    When I start job "craft.old-recipe" in queue "craft" with attempt "att-070"
    Then the response error is "job_retired"
    And collecting "item-0001" at "2026-10-21T12:11:00Z" grants 1 "bread"

  @edge
  Scenario: A locked slot refuses a start and names the unlock options
    When I start job "craft.bread" in queue "craft" with attempt "att-091" on slot 1
    Then the response error is "slot_locked" with reason "not_unlocked"
    And unlock_options are "flag:tier_2" and "store_product:slot_craft_plus"
    And the ledger received no call

  @edge
  Scenario: The start sheet shows no money figure for inputs in soft currencies
    When I open the start sheet for "craft.jam"
    Then the "coins" and "berries" lines show no ApproxMoney because neither is a purchasable currency
    And no input line is a premium currency

  @security
  Scenario Outline: A request that carries a time, a price or an account is rejected
    When I start job "craft.bread" with a body that also carries "<field>"
    Then the response status is 400 with error "unexpected_field" and field "<field>"
    And no queue item row exists and the ledger received no call

    Examples:
      | field            |
      | ends_at          |
      | starts_at        |
      | duration_seconds |
      | now              |
      | amount           |
      | account_id       |

  @security
  Scenario: Starting more often than the rate limit is refused
    Given STARTS_PER_MINUTE_MAX is 20
    When account "acct-001" sends 21 start requests within one minute
    Then the 21st response error is "rate_limited" with a retry_after_seconds value
    And no more than the earlier valid starts were charged

  @security
  Scenario: A start names only ids and the server reads the numbers
    When I start job "craft.bread" in queue "craft" with attempt "att-001"
    Then the item's duration_seconds is 900 and its input_snapshot is the definition's input
    And no value in the item came from the request body except job_id, queue_id, attempt_id and slot_index
