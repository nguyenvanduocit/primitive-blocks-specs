Feature: Hand-off, idle-slot nudge, clock and account lifecycle
  As a player
  I want to hear when something finishes, be offered a next step a few times at most, and never be fooled by a clock
  So that the queue keeps me busy between sessions without pressure or surprises

  Background:
    Given the app is configured for tenant "tenant-001"
    And the definition set and configuration from fixtures/catalog.json are published
    And account "acct-001" is signed in with timezone "Asia/Ho_Chi_Minh"
    And the wallet is the "balances" preset of fixtures/catalog.json
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario: Starting an item arms a queue_item_ready notice for its end
    When I start "craft.bread" with attempt "att-001"
    Then the response carries a hand-off event with event_name "queue_item_ready" and subject_key "queue-item:item-0001"
    And the event has state "armed", ends_at "2026-10-21T12:15:00Z", fire_at "2026-10-21T12:15:00Z", expires_at "2026-10-21T18:15:00Z" and revision 1
    And the params are queue_code "craft", queue_kind "craft", job_id "craft.bread" and slot_index 0
    And the queue_code matches the pattern "^[A-Za-z0-9._:-]{1,64}$"
    # fixture: fixtures/account-cases.json "handoff_cases" event-shape

  @edge
  Scenario: A reserved item whose spend is not confirmed is not armed
    Given a start of "craft.bread" is reserved with input_status "pending"
    Then no hand-off event exists for it

  @happy
  Scenario: A speed-up re-arms the same subject with a larger revision
    Given item "item-0002" is queued until "2026-10-21T12:30:00Z" behind a running item
    When the running item is finished by a speed-up at "2026-10-21T12:06:00Z"
    Then "queue-item:item-0002" is armed again with fire_at "2026-10-21T12:21:00Z" and revision 2
    And the consumer upserts by account, event and subject_key and keeps revision 2

  @happy
  Scenario Outline: A resolved notice cancels the pending notification
    When "<cause>" happens to item "item-0001"
    Then a hand-off event for "queue-item:item-0001" with state "resolved" is produced

    Examples:
      | cause                                             |
      | the item is collected                             |
      | the item is cancelled                             |
      | a speed-up finishes it while the player is in app |

  @edge
  Scenario: The list endpoint returns the armed set so a device can rebuild its schedule
    Given items "item-0001" and "item-0002" are running and item "item-0000" is ready
    When I list the queues
    Then armed contains "queue-item:item-0001" and "queue-item:item-0002" with their fire_at and revisions
    And armed does not contain "queue-item:item-0000"

  @edge
  Scenario: Items are bounded by the push block's local notification capacity
    Given the sum of max_slots times lane_depth over all queues is 18 and LOCAL_MAX_PENDING is 20
    Then the definition set is valid
    When a set raises the sum to 24
    Then publishing fails with "handoff_capacity_exceeded"

  @edge
  Scenario: A remote-lane deployment receives the same events at least once
    Given EVENT_ROUTES maps queue_item_ready to the remote lane
    When item "item-0001" is armed twice because of a retry
    Then the consumer keeps one pending notice for "queue-item:item-0001" at the highest revision

  @happy
  Scenario: An idle slot with an affordable job is offered a nudge within its caps
    Given the craft slot is idle and the wallet holds 9 "flour"
    When I list the queues at open 1
    Then idle_nudge is eligible for slot 0 and job "craft.bread"
    When the client reports "shown"
    Then nudge_shown_today is 1
    # fixture: fixtures/account-cases.json case "caps-per-open-gap-and-day"

  @edge
  Scenario Outline: The nudge caps are checked in a fixed order
    Given the craft slot is idle and the wallet holds 9 "flour" and 1 nudge was shown at "2026-10-21T12:00:01Z"
    When I list the queues at "<time>" in open <open>
    Then idle_nudge eligible is <eligible> with why "<why>"

    Examples:
      | time                 | open | eligible | why      |
      | 2026-10-21T12:05:00Z | 1    | false    | per_open |
      | 2026-10-21T13:00:00Z | 2    | false    | gap      |
      | 2026-10-21T16:00:01Z | 3    | true     |          |

  @edge
  Scenario: The day cap holds and then resets on the account's local day
    Given two nudges were shown on the local day "2026-10-21"
    When I list the queues at "2026-10-21T16:59:00Z"
    Then idle_nudge is not eligible with why "per_day"
    When I list the queues at "2026-10-21T17:00:01Z"
    Then the day_key is "2026-10-22" and nudge_shown_today is 0
    And idle_nudge is not eligible with why "gap" because four hours have not passed
    When I list the queues at "2026-10-21T20:00:03Z"
    Then idle_nudge is eligible

  @edge
  Scenario: Three dismissals in a row suppress the nudge for a week
    Given the craft slot is idle and the wallet holds 9 "flour"
    When the player dismisses the nudge at "2026-10-21T12:00:00Z", "2026-10-21T16:00:01Z" and "2026-10-22T12:00:00Z"
    Then nudge_suppressed_until is "2026-10-29T12:00:00Z"
    And idle_nudge is not eligible with why "suppressed" on "2026-10-25T12:00:00Z"
    And idle_nudge is eligible on "2026-10-29T12:00:00Z"

  @edge
  Scenario: Acting on a nudge resets the dismissal run
    Given nudge_dismissals_in_row is 2
    When the client reports "acted"
    Then nudge_dismissals_in_row is 0 and nudge_suppressed_until is empty

  @edge
  Scenario: Nothing affordable means no nudge and a stated way forward
    Given the craft slot is idle and the wallet holds 0 "flour", 0 "coins" and 0 "berries"
    When I list the queues
    Then idle_nudge is not eligible with why "nothing_affordable"
    And the response lists the missing input for "craft.bread" as 3 "flour" with balance 0
    And the panel is not a dead end because every input has an enabled faucet

  @edge
  Scenario: A busy queue gets no nudge
    Given every unlocked craft lane has a queued or running item
    When I list the queues
    Then idle_nudge is not eligible with why "no_idle_slot"

  @security
  Scenario: The nudge counters live on the server and hold across devices
    Given IDLE_NUDGE_PER_DAY is 1 and the phone reported "shown" at "2026-10-21T12:00:00Z"
    When the tablet lists the queues at "2026-10-21T16:00:00Z"
    Then idle_nudge is not eligible with why "per_day"

  @edge
  Scenario: An idle slot sends no push and no badge
    Given the craft slot is idle with an affordable job
    Then no hand-off event is produced for the idle slot
    And queue_item_ready is the only event this block hands to messaging.push-reengagement

  @happy
  Scenario: The countdown is computed from the server's clock offset
    Given a response with server_now "2026-10-21T12:00:00Z" arrived when the device clock read "2026-10-21T12:00:30Z"
    Then the offset is -30 seconds
    And at device time "2026-10-21T12:01:30Z" an item ending "2026-10-21T12:15:00Z" shows 840 seconds left

  @security
  Scenario: A device clock one day ahead makes nothing collectable
    Given item "item-0001" ends at "2026-10-21T12:15:00Z" and the server time is "2026-10-21T12:01:00Z"
    When a client whose clock reads "2026-10-22T12:01:00Z" collects item "item-0001"
    Then the response error is "not_ready" with ends_at "2026-10-21T12:15:00Z" and the ledger received no call

  @edge
  Scenario: A device clock set back delays nothing the server owes
    Given item "item-0001" ended at "2026-10-21T12:15:00Z" and the server time is "2026-10-21T12:16:00Z"
    When a client whose clock reads "2026-10-20T12:01:00Z" collects item "item-0001"
    Then the item is collected

  @edge
  Scenario: A correction larger than the threshold is reported
    Given a displayed countdown of 840 seconds and a response that gives 820
    Then the client fires "queue_countdown_corrected" with drift_seconds 20 because the threshold is 5

  @edge
  Scenario: Zero on the countdown asks the server
    Given the corrected countdown of item "item-0001" reaches zero
    Then the client requests the queue list
    And the item is shown as ready only if the server's effective state is ready

  @happy
  Scenario: A guest merges into an account and the busier lane survives
    Given guest "guest-9" has a running craft item ending "2026-10-21T12:10:00Z" and a ready item
    And account "acct-001" has a running craft item ending "2026-10-21T13:00:00Z" in the same slot
    When mergeAccounts runs from "guest-9" into "acct-001" with merge_id "merge-1"
    Then the ready item and the account's running item are kept
    And the guest's running item is cancelled with a full refund and cancel_reason "operator"
    And the hand-off for the cancelled item is resolved
    When mergeAccounts runs again with merge_id "merge-1"
    Then the first result is returned and nothing changes
    # fixture: fixtures/lifecycle-cases.json case "merge-keeps-the-busier-lane"

  @edge
  Scenario: A merge with pending rows is refused
    Given guest "guest-9" has a queued item with input_status "pending" that recovery cannot finish
    When mergeAccounts runs from "guest-9" into "acct-001"
    Then the response error is "merge_blocked_pending" and nothing changed

  @edge
  Scenario: Holdings list what a merge would carry
    Given guest "guest-9" has a ready item and a slot bought with money
    When holdings is called for "guest-9"
    Then it returns an "items_in_progress" holding with paid false and effect "carried"
    And it returns a "paid_slots" holding with paid true and effect "carried"

  @security
  Scenario: Deleting an account erases every row of this block and can be repeated
    Given account "acct-001" has rows in queue_states, queue_items, slot_unlocks, speed_up_quotes, time_reductions and merge_log
    When deleteAccount runs for "acct-001"
    Then all six tables hold no row for "acct-001" and the definition tables are untouched
    And armed hand-offs for the account are resolved
    When deleteAccount runs again
    Then nothing changes and no error is raised
    # fixture: fixtures/account-cases.json "erasure_cases"
