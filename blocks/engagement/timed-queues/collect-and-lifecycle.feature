Feature: Lazy completion, collect and the item lifecycle
  As a player
  I want finished items to be ready when I return and collected exactly once
  So that the queue works while I am away and no output is duplicated or lost

  Background:
    Given the app is configured for tenant "tenant-001"
    And the definition set and configuration from fixtures/catalog.json are published
    And account "acct-001" is signed in with timezone "Asia/Ho_Chi_Minh"
    And the wallet is the "balances" preset of fixtures/catalog.json
    And item "item-0001" of "craft.bread" runs from "2026-10-21T12:00:00Z" to "2026-10-21T12:15:00Z" in craft slot 0
    And item "item-0002" of "craft.bread" is queued from "2026-10-21T12:15:00Z" to "2026-10-21T12:30:00Z" in craft slot 0
    And the clock is fixed at "2026-10-21T12:20:00Z"

  @happy
  Scenario: Time passing completes items with no write and no job
    When I list the queues
    Then the effective state of "item-0001" is "ready" and of "item-0002" is "running"
    And the stored state of "item-0001" is still "running" and of "item-0002" is still "queued"
    And the list wrote zero rows
    And no scheduled job exists for either item
    # fixture: fixtures/lifecycle-cases.json case "lazy-completion-no-writes"

  @happy
  Scenario: A write to the lane settles the stored states first
    Given the clock is fixed at "2026-10-21T13:00:00Z"
    When I start job "craft.bread" with attempt "att-004"
    Then the stored states of "item-0001" and "item-0002" are "ready" before the new item is written
    And the new item "item-0003" is running from "2026-10-21T13:00:00Z" to "2026-10-21T13:15:00Z"
    And finished items do not hold the lane

  @happy
  Scenario: Collect grants each output line once
    When I collect item "item-0001"
    Then the ledger received a grant of 2 "bread" with reason "timed-queues.collect" and key "timed-queues:acct-001:item-0001:collect:1"
    And item "item-0001" is collected with collect_status "granted"
    And the "bread" balance is 2
    And a "queue_item_collected" event is written with queue_kind "craft", job_id "craft.bread", sped_up false and replayed false
    And the hand-off for "queue-item:item-0001" is resolved

  @edge
  Scenario: Collecting again returns the original result and grants nothing
    Given I collected item "item-0001"
    When I collect item "item-0001" again
    Then the response has already_collected true
    And the ledger received no call and the "bread" balance is 2
    And a "queue_item_collected" event is written with replayed true

  @edge
  Scenario: Collecting a running item is refused with its end time
    When I collect item "item-0002"
    Then the response error is "not_ready" with ends_at "2026-10-21T12:30:00Z"
    And the ledger received no call

  @happy
  Scenario: Collect all takes every ready item in end order
    Given the clock is fixed at "2026-10-21T13:00:00Z"
    When I collect all
    Then the results are "item-0001" collected then "item-0002" collected and more is false
    And the "bread" balance is 4
    And the response suggests starting "craft.bread" again
    When I collect all again
    Then the results list is empty and the ledger received no call
    # fixture: fixtures/lifecycle-cases.json case "collect-all"

  @edge
  Scenario: One item's failure does not undo another item's collect
    Given the clock is fixed at "2026-10-21T13:00:00Z"
    And the "bread" balance is 99999 and LEDGER_MAX_BALANCE is 100000
    And item "item-0002" pays "jam" and not "bread"
    When I collect all
    Then "item-0002" is collected
    And "item-0001" has status "blocked_cap" and stays ready

  @edge
  Scenario: A grant refused for the balance limit leaves the item ready
    Given item "item-0001" is ready and the "bread" balance is 99999 and LEDGER_MAX_BALANCE is 100000
    When I collect item "item-0001"
    Then the response error is "collect_blocked_cap" with currency "bread" and room_needed 1
    And item "item-0001" is ready with collect_status "blocked_cap"
    And no output is lost
    When the player spends 10 "bread" and collects again
    Then the ledger received a grant of 2 "bread" with key "timed-queues:acct-001:item-0001:collect:1"
    And item "item-0001" is collected
    # fixture: fixtures/lifecycle-cases.json case "collect-blocked-by-balance-limit"

  @edge
  Scenario: A ledger outage in the middle of a two-line collect resumes with the same keys
    Given item "item-0001" is an expedition with output 400 "coins" and 1 "booster_small" and it is ready
    And the ledger is unavailable for the second line
    When I collect item "item-0001"
    Then the response status is 503 and item "item-0001" is ready with collect_status "pending"
    And the grant of 400 "coins" with key "timed-queues:acct-001:item-0001:collect:1" was applied
    When the clock is fixed at "2026-10-21T12:21:10Z" and the recovery sweep runs
    Then the first grant is replayed with no second entry and 1 "booster_small" is granted with key "timed-queues:acct-001:item-0001:collect:2"
    And item "item-0001" is collected
    # fixture: fixtures/lifecycle-cases.json case "collect-with-two-lines-resumes"

  @edge
  Scenario: An effect output line calls the host once per item
    Given "build.farm.l2" was collected by account "acct-001"
    Then the host hook apply_effect was called once with code "farm.level", amount 2 and idempotency key "item-0001"
    And collecting the item again does not call the hook

  @edge
  Scenario Outline: Actions the state does not allow answer invalid_transition
    Given an item in state "<state>"
    When I attempt to "<action>" it
    Then the response is "<answer>" and the row and the ledger are unchanged

    Examples:
      | state     | action            | answer                      |
      | ready     | cancel            | invalid_transition          |
      | collected | cancel            | invalid_transition          |
      | cancelled | collect           | invalid_transition          |
      | cancelled | speed up          | item_not_running            |
      | collected | collect           | already_collected           |
      | cancelled | cancel            | already_cancelled           |
      | queued    | collect           | not_ready                   |

  @edge
  Scenario: A finished item never expires and costs nothing to leave
    Given item "item-0001" has been ready for 90 days
    When I list the queues
    Then item "item-0001" is ready with its full output
    And no counter, reward, streak or score changed because it waited
    And collecting it grants the output from the item's snapshot

  @edge
  Scenario: An empty slot and a full queue carry no penalty
    Given the craft queue has had an idle slot for 30 days
    Then no state, reward or other feature changed because the slot was idle
    And the only effect is that an in-app nudge may be eligible within its caps

  @security
  Scenario: Another account's item cannot be addressed
    Given account "acct-002" owns item "item-9001"
    When account "acct-001" collects item "item-9001"
    Then the response error is "item_not_found"
    And the ledger received no call
    And the response is identical to collecting an id that does not exist

  @security
  Scenario: Two devices collect at the same moment
    Given item "item-0001" is ready
    When the phone and the tablet both collect item "item-0001"
    Then exactly one grant of 2 "bread" is applied
    And the second response has already_collected true with the same body

  @security
  Scenario: The client's countdown reaching zero does not make an item collectable
    Given the device clock is one day ahead of the server
    When the client collects item "item-0002" because its local countdown shows zero
    Then the response error is "not_ready" and the ledger received no call
