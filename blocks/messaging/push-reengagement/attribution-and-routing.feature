Feature: Attribution and deep-link routing
  As the live-ops owner
  I want to know which notifications were sent, opened and followed by a return, and I want a tap to land on the right screen
  So that I can tell whether the program works and the player is never sent somewhere wrong

  Background:
    Given the app is configured for tenant "tenant-001"
    And the profiles from fixtures/profiles.json exist
    And the defaults from fixtures/config-defaults.json
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario: A send is recorded as sent, not as delivered
    Given a delivery with id "7c1e0d4a-0000-4000-8000-000000000001" was accepted by APNs
    Then the delivery status is "sent" with sent_at "2026-10-21T12:00:00Z" and provider_message_id equal to its apns-id
    And delivered_at is empty
    When the device posts a receipt of kind "delivered" for that send_id
    Then the status becomes "delivered" and delivered_at is the server time of the receipt

  @happy
  Scenario: An opened receipt is stamped once with the server clock
    Given the delivery "7c1e0d4a-0000-4000-8000-000000000001" belongs to "acc-ann"
    When "acc-ann" sends POST /api/push/receipts with kind "opened" and at "2026-10-21T08:00:00Z"
    Then the response status is 204
    And opened_at on the delivery and on its intent is "2026-10-21T12:00:00Z", not the client's "at"
    When the same receipt is sent again
    Then nothing changes

  @security
  Scenario: A receipt for another account's send is ignored without telling
    When "acc-ben" sends POST /api/push/receipts with the send_id of a delivery of "acc-ann"
    Then the response status is 204
    And no row of "acc-ann" changes

  @happy
  Scenario: A session inside the return window marks the send as returned
    Given an intent of category "events" was dispatched to "acc-ann" at "2026-10-21T06:00:00Z"
    When "acc-ann" starts a session at "2026-10-21T12:00:00Z"
    Then the intent gets returned_at "2026-10-21T12:00:00Z" because 6 hours is inside the 24 hour window
    And push_returned fires with category "events" and since_s 21600

  @edge
  Scenario: A session after the window does not count
    Given an intent of category "events" was dispatched to "acc-ann" at "2026-10-19T06:00:00Z"
    When "acc-ann" starts a session at "2026-10-21T12:00:00Z"
    Then returned_at stays empty

  @edge
  Scenario: The comeback category has a 72 hour window
    Given a "comeback" intent was dispatched to "acc-ann" at "2026-10-18T13:00:00Z"
    When "acc-ann" starts a session at "2026-10-21T12:00:00Z"
    Then returned_at is set, because 71 hours is inside 72

  @edge
  Scenario: A reported local notification is counted and can be opened
    When "acc-ann" sends POST /api/push/session with local_fired of local_key "timers:energy:main:1792584000" and fire_at "2026-10-20T11:00:00Z"
    Then an intent with lane "local", source "local_report" and dedupe_key "local:acc-ann:timers:energy:main:1792584000:1792494000" exists
    When she sends an opened receipt with that local_key and fire_at
    Then opened_at is set on that intent and a replay changes nothing

  @edge
  Scenario: The holdout comparison uses the same measure on both groups
    Given 100 dispatched "lapse-d7" intents of which 30 have returned_at set
    And 20 held-out "lapse-d7" intents of which 4 have returned_at set
    Then returned share is 30 percent for the treated group and 20 percent for the held-out group
    And incremental_return for "lapse-d7" is 10 percentage points
    And both groups passed every decision rule before the holdout

  @edge
  Scenario: Repeating the session call returns the same answer
    Given "acc-ben" started session "s-ben-1" and received a comeback grant
    When "acc-ben" sends POST /api/push/session again with session_id "s-ben-1"
    Then last_session_at is unchanged and the answer repeats lapse_days and the grant status
    And no intent is stamped a second time

  @happy
  Scenario: A cold start routes after the app is ready
    Given the app was closed and the player taps a notification with route "event" and rp {"event_id":"spring-rush"}
    When the app launches
    Then launchTap returns the tap and routing waits until the session is restored and the config is loaded
    And the player lands on the event screen for "spring-rush"
    And the opened receipt is queued once and push_opened fires with cold_start true

  @happy
  Scenario: A warm start routes immediately
    Given the app is in the background and the player taps a notification with route "daily"
    When the tap is delivered to onTap
    Then the player lands on the daily screen and push_opened fires with cold_start false

  @edge
  Scenario: A duplicate tap delivery is handled once
    Given the platform delivers the same tap through both the launch hook and onTap
    Then the route is opened once and one opened receipt is queued
    And the key is stored in handled_taps

  @security
  Scenario Outline: A route outside the allow-list or with a bad parameter opens home
    When the tap payload is route "<route>" with rp <rp>
    Then the player lands on "home" and push_route_failed fires with reason "<reason>"

    Examples:
      | route                  | rp                                  | reason        |
      | https://example.test   | {}                                  | unknown_route |
      | ../settings            | {}                                  | unknown_route |
      | event                  | {"event_id":"a b; drop"}            | bad_param     |
      | event                  | not json                            | bad_param     |

  @edge
  Scenario: A target that has ended routes to its list with a notice
    Given the event "spring-rush" ended while the notification waited
    When the player taps a notification with route "event" and event_id "spring-rush"
    Then the player lands on the events list with the notice "That isn't available now."
    And push_route_failed fires with reason "unavailable"

  @security
  Scenario: A tap never changes a balance
    When any notification is tapped and its opened receipt is accepted
    Then the ledger receives no call and no reward is granted
