Feature: Local windows and clock correction
  As a player in any time zone
  I want my daily event to start at my own midnight and my timers to be right
  So that the day I play is the day the event counts

  Background:
    Given the app is configured for tenant "tenant-001"
    And the events from fixtures/events.json are published
    And the accounts from fixtures/accounts.json exist
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario Outline: A local wall-clock time resolves in the account's zone
    When the local time "<local>" is resolved in "<zone>"
    Then the UTC instant is "<utc>"

    Examples:
      | zone               | local               | utc                  | case                         |
      | Asia/Ho_Chi_Minh   | 2026-10-28T00:00:00 | 2026-10-27T17:00:00Z |                              |
      | Asia/Kolkata       | 2026-10-28T00:00:00 | 2026-10-27T18:30:00Z |                              |
      | America/New_York   | 2026-10-28T00:00:00 | 2026-10-28T04:00:00Z |                              |
      | Pacific/Kiritimati | 2026-10-28T00:00:00 | 2026-10-27T10:00:00Z |                              |
      | Pacific/Pago_Pago  | 2026-10-28T00:00:00 | 2026-10-28T11:00:00Z |                              |
      | America/New_York   | 2026-03-08T02:30:00 | 2026-03-08T07:30:00Z | does not occur: offset before the gap |
      | America/New_York   | 2026-11-01T01:30:00 | 2026-11-01T05:30:00Z | occurs twice: first occurrence |

  @edge
  Scenario Outline: A local calendar day is 23, 24 or 25 hours long
    When the local day "<day>" is resolved in "<zone>"
    Then it starts at "<starts_at>" and ends at "<ends_at>"
    And it lasts <seconds> seconds

    Examples:
      | zone             | day        | starts_at            | ends_at              | seconds |
      | America/New_York | 2026-03-08 | 2026-03-08T05:00:00Z | 2026-03-09T04:00:00Z | 82800   |
      | America/New_York | 2026-11-01 | 2026-11-01T04:00:00Z | 2026-11-02T05:00:00Z | 90000   |
      | Europe/Berlin    | 2026-10-25 | 2026-10-24T22:00:00Z | 2026-10-25T23:00:00Z | 90000   |

  @happy
  Scenario: The same daily instance has different states for different players at one instant
    When I send GET /api/events as acc-ann
    And I send GET /api/events as acc-cara
    Then for acc-ann "evt-daily-1027" is "live" with window 2026-10-26T17:00:00Z to 2026-10-27T17:00:00Z
    And for acc-cara "evt-daily-1027" is not listed because her window ended at "2026-10-27T10:00:00Z"
    And acc-cara has "evt-daily-1028" live with window 2026-10-27T10:00:00Z to 2026-10-28T10:00:00Z

  @edge
  Scenario: The outer bounds of a local window contain every zone's resolution
    When the stored bounds of "evt-daily-1027" are read
    Then starts_at is "2026-10-26T10:00:00Z", the local start read as UTC minus 14 hours
    And ends_at is "2026-10-28T12:00:00Z", the local end read as UTC plus 12 hours

  @edge
  Scenario: A local window is latched at first listing and does not move
    Given acc-ann was first listed "evt-daily-1027" with window ending "2026-10-27T17:00:00Z"
    When the account timezone of acc-ann changes to "America/New_York"
    And I send GET /api/events as acc-ann
    Then the window of "evt-daily-1027" for acc-ann still ends at "2026-10-27T17:00:00Z"
    And the next instance "evt-daily-1028" is resolved in the zone in effect at its first listing

  @edge
  Scenario Outline: Version comparison is numeric per component
    When a client on "<client>" is checked against min_app_version "<min>"
    Then supported is <supported>

    Examples:
      | client     | min   | supported |
      | 2.5.0      | 2.4.0 | true      |
      | 2.4.0      | 2.4.0 | true      |
      | 2.3.5      | 2.4.0 | false     |
      | 2.10.0     | 2.9.0 | true      |
      | 2.9.0      | 2.10.0| false     |
      | 2.4        | 2.4.0 | true      |
      | 2.4.0-beta | 2.4.0 | false     |
      |            | 2.4.0 | false     |

  @happy
  Scenario: A fast device clock does not change the countdown
    Given a response with server_now "2026-10-27T12:00:00.000Z" was received when the device wall clock read "2026-10-27T12:05:00.000Z"
    And the round trip was instant
    When 10 minutes pass on the monotonic clock
    Then the remaining time to "2026-10-27T17:00:00Z" is 4 hours 50 minutes

  @security
  Scenario: Moving the device clock forward gains nothing
    Given a response with server_now "2026-10-27T12:00:00.000Z" was received
    When the player sets the device clock to "2026-10-28T09:00:00Z" and 10 minutes pass on the monotonic clock
    Then the countdown still shows 4 hours 50 minutes
    And a Join request is still judged by the server's clock

  @edge
  Scenario: A countdown that reaches zero asks the server and decides nothing
    Given the countdown of "evt-daily-1027" reaches zero on the monotonic estimate
    Then the card shows "Checking..."
    And a discovery request is sent after a random delay between 0 and 5 seconds
    And the card changes state only when the response arrives

  @edge
  Scenario: After a restart the countdown is approximate
    Given the app was restarted and the monotonic origin was lost
    When the persisted snapshot is shown
    Then the end time is shown as an absolute time labelled approximate
    And no ticking countdown is shown until a new response arrives

  @edge
  Scenario: A stale snapshot disables writes
    Given the last response was received 901 seconds ago
    Then the hub shows the last-updated notice
    And Join and Claim are disabled until a fresh response arrives

  @security
  Scenario: A refetch rebuilds the countdown from ends_at and never restarts it
    Given the countdown of "evt-daily-1027" for acc-ann shows 3 hours 30 minutes
    When a new response arrives with the same ends_at "2026-10-27T17:00:00Z"
    Then the countdown shows the time left to "2026-10-27T17:00:00Z" on the new server estimate
    And it never shows the event's full length
