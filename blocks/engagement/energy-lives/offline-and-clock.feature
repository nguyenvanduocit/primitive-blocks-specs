Feature: Offline play, device clocks and two devices
  As a player on a flaky connection or a second phone
  I want the game to stay usable and honest
  So that the point count is the same everywhere and nobody gets or loses points by accident

  Background:
    Given the app is configured for tenant "tenant-001"
    And the meters and settings from fixtures/meter-config.json exist
    And I am authenticated as "acct-0001"
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And meter "energy" is stored with value 2 and anchor_at "2026-10-21T11:50:00Z"

  @happy
  Scenario: The client shows the last values with their age and never adds a point itself
    Given the client received a response with server_now "2026-10-21T12:00:00Z" and next_tick_at "2026-10-21T12:20:00Z"
    And the device goes offline
    When 31 minutes pass on the device's monotonic clock
    Then the HUD state is "offline"
    And the displayed value is still 2
    And the countdown text is "Reconnect to update"
    And no request was sent

  @security
  Scenario: A device clock set six hours ahead changes nothing
    Given the device wall clock is set to "2026-10-21T18:00:00Z" while the server clock reads "2026-10-21T12:00:00Z"
    When the client refreshes
    Then the displayed value is 2 and the countdown equals next_tick_at minus server_now
    And the server response is identical to the response before the change

  @edge
  Scenario: Returning from a suspend always refreshes before showing a countdown as current
    Given the app was suspended for 40 minutes
    When the app returns to the foreground
    Then the client sends GET /api/energy before the HUD shows a countdown as current
    And the HUD value comes from the response

  @edge
  Scenario: With offline attempts off, Start asks for a connection
    Given OFFLINE_ATTEMPTS is false and the device is offline
    When the player taps Start
    Then no attempt is created and the message says a connection is needed
    And non-energy screens stay available

  @happy
  Scenario: Offline attempts are reconciled in order and are idempotent
    Given OFFLINE_ATTEMPTS is true and OFFLINE_MAX_ATTEMPTS is 3
    And the client queued attempts "off-1" (win) and "off-2" (fail) while offline against available 2
    When the device reconnects and sends POST /api/energy/attempts/reconcile with both
    Then "off-1" is "won" charged 1 and "off-2" is "failed" charged 1
    And the meter has value 0
    When the same batch is sent again at "2026-10-21T12:00:01Z"
    Then both results have replayed true and the meter still has value 0
    And fixtures/api-cases.json case "offline-queue-accepted" matches

  @edge
  Scenario: An offline attempt the server cannot afford is rejected and stays rejected
    Given OFFLINE_ATTEMPTS is true
    And meter "energy" is stored with value 1 because another device spent a point
    When the client reconciles "off-1" (win) and "off-2" (win)
    Then "off-1" is "won" and "off-2" is "rejected" with error "insufficient_energy"
    And the client drops the rewards of "off-2" and shows the notice
    When the client sends a start with attempt_id "off-2" at "2026-10-21T12:30:00Z"
    Then the response status is 409 with replayed true
    And fixtures/api-cases.json case "offline-queue-overdraft" matches

  @edge
  Scenario: The offline queue is bounded
    Given OFFLINE_ATTEMPTS is true and OFFLINE_MAX_ATTEMPTS is 3
    When the client tries to queue a fourth attempt offline
    Then the client refuses it locally
    And a batch of four sent by a modified client is refused with 422 "invalid_request"

  @security
  Scenario: Offline attempts are refused when the setting is off
    Given OFFLINE_ATTEMPTS is false
    When a client sends POST /api/energy/attempts/reconcile with one attempt
    Then the response status is 409 and the error is "offline_attempts_disabled"

  @security
  Scenario: A client-claimed start time is ignored
    Given OFFLINE_ATTEMPTS is true
    When the client reconciles "off-9" with a body field started_at "2026-10-20T00:00:00Z"
    Then the attempt's started_at is "2026-10-21T12:00:00Z"

  @edge
  Scenario: A timeout with no answer is retried with the same id
    Given the request for attempt "att-0500" timed out and the server did apply it
    When the client retries with attempt_id "att-0500"
    Then the response status is 200 with replayed true and the meter was charged once

  @edge
  Scenario: A server restart with every scheduler disabled returns the right value
    Given no background job or timer is running on the server
    And the stored meter is value 0 with anchor_at "2026-10-21T10:30:00Z"
    When I send GET /api/energy
    Then the meter has value 3

  @security
  Scenario: Repeated reads write nothing and are rate limited
    When I send GET /api/energy 60 times at "2026-10-21T12:00:00Z"
    Then the meter row was written 0 times
    When I send the 61st request within the same minute
    Then the response status is 429 with retry_after_seconds
