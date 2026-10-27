Feature: Lapsed-player ladder and comeback reward
  As the live-ops owner
  I want a short, finite ladder of true messages for players who stopped playing, and a gift when they return
  So that returning is easy, the gift never depends on notification settings, and the effect can be measured

  Background:
    Given the app is configured for tenant "tenant-001"
    And the profiles from fixtures/profiles.json exist
    And the defaults from fixtures/config-defaults.json
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And the ledger answers every grant with applied true and a new entry_id

  @happy
  Scenario: The first step is due on its local day and is sent
    Given "acc-ann" last started a session at "2026-10-18T05:00:00Z" and her ladder pointer is step "lapse-d3"
    Then the pointer's due time is "2026-10-21T11:04:00Z", 18:00 local plus her 4 minute offset
    When the dispatcher ticks at "2026-10-21T12:00:00Z"
    Then the decision is the case "D01-ladder-send" of fixtures/profiles.json
    And one intent exists with source "ladder", category "comeback", template "comeback.reminder" and status "dispatched"
    And ladder_unopened_sends of "acc-ann" is 1 and the pointer moves to "lapse-d7"

  @edge
  Scenario: Starting a session resets the pointer and cancels what was waiting
    Given "acc-ann" has the pointer at step "lapse-d7" and a pending intent whose event has cancel_on_session
    When "acc-ann" sends POST /api/push/session with a new session_id
    Then the pointer is anchored to the new last_session_at with next step "lapse-d3"
    And the pending cancel_on_session intent is cancelled with reason "returned"

  @happy
  Scenario: Returning after seven local days grants the day-7 reward through the ledger once
    Given "acc-ben" last started a session at "2026-10-14T16:00:00Z" and has never received a comeback reward
    When "acc-ben" sends POST /api/push/session with session_id "s-ben-1" at "2026-10-21T22:30:00Z"
    Then the response has lapse_days 7 and comeback status "granted", step_id "lapse-d7", currency "coin", amount 50
    And the ledger receives grant with reason "push-reengagement.comeback-reward", amount 50 and idempotency_key "push-reengagement:acc-ben:1791993600:lapse-d7"
    And one comeback_grants row exists with status "applied" and last_comeback_granted_at is set
    When the same request is sent again with session_id "s-ben-1"
    Then the response is identical and the ledger receives no second grant

  @edge
  Scenario Outline: The reward is a function of lapse length
    Given the cooldown is <cooldown>
    When a player returns after <lapse> local days
    Then the selected step is <step>

    Examples:
      | lapse | cooldown | step      |
      | 2     | clear    | none      |
      | 3     | clear    | none      |
      | 6     | clear    | none      |
      | 7     | clear    | lapse-d7  |
      | 20    | clear    | lapse-d7  |
      | 27    | clear    | lapse-d7  |
      | 28    | clear    | lapse-d28 |
      | 90    | clear    | lapse-d28 |
      | 91    | clear    | none      |
      | 10    | active   | none      |

  @edge
  Scenario: Lapse counts local calendar days, not UTC dates
    Given "acc-ann" had a session at "2026-10-14T23:30:00Z" and her timezone is "Asia/Ho_Chi_Minh"
    When she returns at "2026-10-21T16:30:00Z"
    Then lapse_days is 6 as in case "L01-local-day-not-utc-day"
    And no comeback grant is created, although the UTC dates are 7 days apart

  @edge
  Scenario: Rewards do not stack
    When a player returns after 28 local days with the cooldown clear
    Then exactly one grant is created for step "lapse-d28" with amount 100
    And no grant is created for "lapse-d7"

  @security
  Scenario: The reward does not depend on notification settings, delivery or holdout
    Given "acc-cara" has global_enabled false and last started a session at "2026-10-12T10:00:00Z"
    When "acc-cara" returns at "2026-10-21T12:00:00Z"
    Then a grant for step "lapse-d7" is created and applied
    Given "acc-ben" is in the holdout and no push was ever sent to her
    When "acc-ben" returns after 7 local days
    Then the same grant is created and applied

  @edge
  Scenario: A step that names a reward is not sent when the return grant would fail
    Given "acc-lou" received a comeback reward on "2026-10-05T05:00:00Z"
    When the dispatcher evaluates "lapse-d7" for "acc-lou" at "2026-10-21T12:00:00Z"
    Then the decision is the case "D14-reward-in-cooldown" with reason "reward_unavailable"
    And no push naming the reward is sent

  @edge
  Scenario: A failed ledger call is retried with the same key and credits once
    Given the ledger times out on the first grant for "acc-ben"
    When the session call completes
    Then the comeback_grants row is "pending" and the response says comeback status "pending"
    When the dispatcher retries the pending grant with the same idempotency_key
    Then the ledger returns the original result for any replay and the balance is credited once
    And the row becomes "applied"

  @edge
  Scenario: The ladder stops after the final step
    Given the pointer of a profile is at "lapse-d28"
    When the dispatcher evaluates that step
    Then the pointer becomes null after the decision whatever it is
    And no further step is evaluated until the next session start

  @edge
  Scenario: The stop rule ends a ladder the player keeps ignoring
    Given "acc-moe" has ladder_unopened_sends 6 and the pointer at "lapse-d7"
    When the dispatcher evaluates the step
    Then the decision is the case "D15-ladder-stopped" and the pointer becomes null
    When "acc-moe" taps any notification and the opened receipt is accepted
    Then ladder_unopened_sends is 0

  @edge
  Scenario: Overdue steps are not replayed as a burst after an outage
    Given the dispatcher was down and the due times of "lapse-d3" and "lapse-d7" both passed for a profile
    When the dispatcher resumes
    Then it skips to the highest step whose time has passed
    And only that step is evaluated

  @edge
  Scenario: The ladder is planned only for eligible, enabled profiles with a device
    Then a session start leaves the pointer null for "acc-dan" (minor), "acc-cara" (global off), "acc-eve" (comeback off) and "acc-hal" (no active token)

  @happy
  Scenario: A held-out profile is measured on the same moment
    Given "acc-ben" is in the holdout and her step "lapse-d7" is due at "2026-10-21T22:07:00Z"
    When the dispatcher evaluates it at "2026-10-21T22:10:00Z"
    Then the decision is the case "D02-holdout-last" with status "held_out" and no delivery
    When "acc-ben" starts a session at "2026-10-22T09:00:00Z"
    Then that intent gets returned_at "2026-10-22T09:00:00Z", inside the 72 hour comeback window from due_at

  @edge
  Scenario: A subscription notice is never a ladder step
    Given "acc-ann" has the ladder pointer at "lapse-d3" and ladder_unopened_sends 2
    When the subscription block emits "subscription_trial_ending" armed and the dispatcher sends it
    Then the intent has source "handoff" and category "subscription"
    And the ladder pointer and ladder_unopened_sends are unchanged
    And the holdout rule is never applied to it even when "acc-ann" is in the holdout

  @security
  Scenario: A tap grants nothing
    When a ladder notification is opened and the opened receipt is accepted
    Then no ledger call is made and no comeback_grants row is created
