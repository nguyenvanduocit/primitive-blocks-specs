Feature: Local and remote delivery lanes
  As a player
  I want reminders for my own timers to come from my device and reminders about the live game to come from the server
  So that each one is accurate, cancellable when the state changes, and never sent twice

  Background:
    Given the app is configured for tenant "tenant-001"
    And the profiles from fixtures/profiles.json exist
    And the defaults from fixtures/config-defaults.json
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And the device clock is 90 seconds behind the server clock and the last server answer said so

  @happy
  Scenario: An energy timer becomes one local notification computed from server time
    Given the permission is "authorized", the "timers" category is enabled and GET /api/push/state answers local.allowed true
    When the energy block emits "energy_full" armed with subject_key "energy:main:1792584000", fire_at "2026-10-21T14:00:00Z" and expires_at "2026-10-21T20:00:00Z"
    Then one local notification is scheduled with local_key "timers:energy:main:1792584000"
    And its delay is 7200 seconds from now, the gap between the server's fire_at and the server's current time
    And a platform that takes an absolute device time is given "2026-10-21T13:58:30Z", fire_at minus the 90 seconds the device clock is behind
    And push_local_scheduled fires with category "timers"

  @happy
  Scenario: Resolving the state cancels the notification and re-arming replaces it
    Given the local notification "timers:energy:main:1792584000" is scheduled
    When the energy block emits "energy_full" armed again with the same subject_key and fire_at "2026-10-21T15:00:00Z"
    Then the pending notification with that key is replaced, not duplicated
    When the energy block emits "energy_full" resolved with the same subject_key
    Then the notification is cancelled and push_local_cancelled fires with reason "resolved"

  @edge
  Scenario: Nothing is scheduled for a moment the player is already looking at
    When the energy block emits "energy_full" armed with fire_at "2026-10-21T11:59:00Z"
    Then no local notification is scheduled, because the fire time has passed while the app is open

  @edge
  Scenario: A queue item uses ends_at as its fire time and stays on the local lane
    Given EVENT_ROUTES maps "queue_item_ready" to category "timers", lane "local" and route "queue"
    When the timed-queue block emits "queue_item_ready" armed with subject_key "queue-item:item-7f3a", ends_at "2026-10-21T13:00:00Z", revision 3, params queue_code "queue-chests", queue_kind "chest", job_id "job-1", slot_index 1 and no fire_at
    Then a local notification is scheduled with local_key "timers:queue-item:item-7f3a" for ends_at
    And the server ingest of the same event is dropped with reason "lane_mismatch" and creates no intent

  @edge
  Scenario: The device keeps at most 20 pending local notifications, soonest first
    Given 25 distinct armed timers with increasing fire times are known to the client
    When the local plan is built
    Then pendingLocal holds exactly the 20 soonest keys
    And the other 5 are not scheduled

  @edge
  Scenario: A session start rebuilds the plan from fresh state
    Given 3 local notifications are scheduled and the server state now says the category "timers" is disabled
    When the next session starts and GET /api/push/state is read
    Then every local notification is cancelled first
    And the plan is rebuilt and holds none of the "timers" keys

  @edge
  Scenario Outline: Anything that makes a local reminder wrong cancels it
    Given the local notification "timers:energy:main:1792584000" is scheduled
    When <change>
    Then the notification is cancelled with push_local_cancelled reason "<reason>"

    Examples:
      | change                                              | reason         |
      | the player switches the "timers" category off       | category_off   |
      | the player switches the master switch off           | global_off     |
      | the platform permission becomes "denied"            | permission     |
      | the player logs out                                 | logout         |
      | GET /api/push/state answers eligible false          | age_ineligible |
      | the profile timezone changes                        | timezone       |

  @happy
  Scenario: A remote hand-off becomes a pending intent and is cancelled when resolved
    Given "acc-ann" has an active token and the "events" category enabled with consent
    When the event block emits "event_ending_soon" armed with subject_key "event:spring-rush", fire_at "2026-10-21T15:00:00Z", expires_at "2026-10-21T18:00:00Z" and params event_id "spring-rush", event_title "Spring Rush"
    Then one notification_intents row exists with lane "remote", source "handoff", status "pending", due_at "2026-10-21T15:00:00Z" and route "event" with route_params event_id "spring-rush"
    When the event block emits the same event with state "resolved"
    Then the row is "cancelled" with suppress_reason "resolved" and nothing is sent

  @happy
  Scenario: A trial-ending notice is a remote hand-off that is cancelled when the player cancels
    Given "acc-ann" has an active token and the "subscription" category enabled
    When the subscription block emits "subscription_trial_ending" armed with subject_key "trial:term-42:1", fire_at "2026-10-30T12:00:00Z", expires_at "2026-11-02T12:00:00Z" and params plan_code "vip-monthly", product_code "vip.monthly", platform "ios", period "P1M", renews_at "2026-11-02T12:00:00Z", price_milliunits 4990, currency_code "USD"
    Then one notification_intents row exists with lane "remote", category "subscription", status "pending", route "subscription" and due_at "2026-10-30T12:00:00Z"
    When the subscription block emits the same event with state "resolved" because the player cancelled
    Then the row is "cancelled" with suppress_reason "resolved" and nothing is sent

  @edge
  Scenario Outline: A re-armed event is ordered by its revision
    Given a queue item notice is stored with revision <stored>
    When the same subject_key arrives armed with revision <incoming> and a new fire_at
    Then the outcome is "<outcome>"

    Examples:
      | stored | incoming | outcome   |
      | 3      | 4        | replaced  |
      | 3      | 3        | unchanged |
      | 3      | 2        | ignored   |

  @edge
  Scenario: The energy meter orders its events by meter_revision
    Given a pending "energy_full" notice is stored with params.meter_revision 41
    When the same subject_key arrives armed with params.meter_revision 40
    Then the event is ignored and counted and the stored fire_at is unchanged

  @edge
  Scenario: Params an emitter adds beyond its declared set are dropped
    When the event block emits "event_ending_soon" armed with params event_id "spring-rush", event_title "Spring Rush" and an undeclared param "debug"
    Then the row's params hold event_id and event_title only

  @edge
  Scenario: Re-arming a pending hand-off moves the same row
    Given a pending intent with dedupe_key "handoff:acc-ann:events:event:spring-rush"
    When the event block emits "event_ending_soon" armed with the same subject_key and fire_at "2026-10-21T16:00:00Z"
    Then the same row now has due_at "2026-10-21T16:00:00Z"
    And no second row exists for that dedupe_key

  @edge
  Scenario: A dispatched occurrence is never re-armed
    Given the intent for subject_key "event:spring-rush" is "dispatched"
    When the event block replays "event_ending_soon" armed with the same subject_key
    Then nothing changes
    And a new subject_key "event:spring-rush-2" creates a new pending row

  @edge
  Scenario: A hand-off for an account that never opened a session is dropped
    When the event block emits "event_ending_soon" armed for an account with no push profile
    Then no row is created

  @edge
  Scenario: A looping emitter cannot fill the table
    Given "acc-ann" already has 50 pending intents
    When the event block emits an armed event with a new subject_key
    Then the event is dropped and counted
    And the 50 existing rows are unchanged

  @edge
  Scenario: Route parameters are validated before they enter the row
    When the event block emits "event_ending_soon" armed with params event_id "spring rush; drop"
    Then the row's route_params has no event_id
    And the route falls back to "home"

  @security
  Scenario: A client cannot post hand-off events
    When I send POST /api/push/handoff as an authenticated player
    Then the response status is 404
    And no intent row is created
