Feature: Spending points on attempts
  As a player
  I want starting a session to cost me at most once and never when the session fails to open
  So that two devices, a retry or a crash cannot take a point twice or give one away

  Background:
    Given the app is configured for tenant "tenant-001"
    And the meters and settings from fixtures/meter-config.json exist
    And I am authenticated as "acct-0001"
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And meter "energy" is stored with value 3 and anchor_at "2026-10-21T12:00:00Z"

  @happy
  Scenario: Spend on start, confirm, finish
    When I send POST /api/energy/attempts with attempt_id "att-0001" and meter_code "energy"
    Then the response status is 201
    And the attempt has state "open", charged 1, value 2, available 2
    And next_tick_at is "2026-10-21T12:30:00Z" and full_at is "2026-10-21T13:30:00Z"
    When I confirm "att-0001" at "2026-10-21T12:00:05Z"
    Then the attempt state is "confirmed"
    When I finish "att-0001" with outcome "win" at "2026-10-21T12:01:00Z"
    Then the attempt state is "won" and value is still 2
    And fixtures/api-cases.json case "start-spends-on-start" matches

  @happy
  Scenario: Lives are reserved at start and taken only on a fail
    Given meter "lives" uses consume_mode "on_fail"
    When I start attempt "att-0002" on meter "lives"
    Then the attempt has charged 0, reserved 1, value 3, available 2
    When I finish "att-0002" with outcome "fail" at "2026-10-21T12:01:30Z"
    Then the attempt state is "failed", charged 1, value 2
    And fixtures/api-cases.json cases "on-fail-reserves-then-charges-on-fail" and "on-fail-win-releases" match

  @edge
  Scenario: The same attempt id returns the original and changes nothing
    Given I started attempt "att-0001" on meter "energy"
    When I send the same start again at "2026-10-21T12:00:01Z"
    Then the response status is 200 and replayed is true and value is still 2
    When I send a start with attempt_id "att-0001" and meter_code "lives"
    Then the response status is 409 and the error is "attempt_conflict"

  @edge
  Scenario: A spend never goes below zero
    Given meter "energy" is stored with value 0 and anchor_at "2026-10-21T11:50:00Z"
    When I start attempt "att-0004" on meter "energy"
    Then the response status is 409 and the error is "insufficient_energy"
    And the body has value 0, next_tick_at "2026-10-21T12:20:00Z", full_at "2026-10-21T14:20:00Z"
    And no attempt row exists for "att-0004"

  @edge
  Scenario: Two devices race for the last point
    Given meter "energy" is stored with value 1 and anchor_at "2026-10-21T12:00:00Z"
    When devices A and B start attempts "att-A" and "att-B" at the same instant
    Then exactly one response is 201 and the other is 409 "insufficient_energy"
    And the stored value is 0
    Given meter "lives" with value 1 uses consume_mode "on_fail"
    When devices A and B start attempts on meter "lives" at the same instant
    Then exactly one has reserved 1 and the other is 409 "insufficient_energy"

  @happy
  Scenario: A start that failed to open is refunded once
    Given I started attempt "att-0005" on meter "energy"
    When I send POST /api/energy/attempts/att-0005/cancel with reason "start_failed" at "2026-10-21T12:00:20Z"
    Then the attempt state is "cancelled", refunded 1 and value is 3
    When I send the same cancel at "2026-10-21T12:00:30Z"
    Then the response is the same with replayed true and value is still 3

  @edge
  Scenario: A refund cannot exceed what the player held before the spend
    Given the config confirm_timeout_seconds is 3600
    And meter "energy" is stored with value 5 and anchor_at "2026-10-21T11:00:00Z"
    And I started attempt "att-0006" on meter "energy" at "2026-10-21T12:00:00Z"
    And the meter has regenerated to 5 at "2026-10-21T12:30:00Z"
    When I cancel "att-0006" with reason "start_failed" at "2026-10-21T12:40:00Z"
    Then the attempt state is "cancelled", refunded 0 and value is 5

  @edge
  Scenario: A start that is never confirmed is refunded as of its deadline
    Given I started attempt "att-0007" on meter "energy" at "2026-10-21T12:00:00Z"
    When I send GET /api/energy at "2026-10-21T12:03:00Z"
    Then value is 3
    And attempt "att-0007" has state "cancelled" with cancel_reason "start_timeout" and settled_at "2026-10-21T12:02:00Z"

  @edge
  Scenario: A confirmed attempt cannot be cancelled
    Given I started and confirmed attempt "att-0008"
    When I cancel "att-0008" with reason "start_failed"
    Then the response status is 409 and the error is "attempt_not_cancellable" with state "confirmed"

  @edge
  Scenario: An abandoned lives attempt is charged at its expiry, not at the later read
    Given meter "lives" uses consume_mode "on_fail"
    And I started attempt "att-0010" on meter "lives" at "2026-10-21T12:00:00Z" and confirmed it at "2026-10-21T12:00:01Z"
    When I send GET /api/energy at "2026-10-21T13:06:40Z"
    Then value is 4 and next_tick_at is "2026-10-21T13:30:01Z"
    And attempt "att-0010" has state "expired" and settled_at "2026-10-21T13:00:01Z"

  @edge
  Scenario: A boost makes the start free
    Given meter "energy" has boost_ends_at "2026-10-21T13:00:00Z"
    When I start attempt "att-0009" on meter "energy"
    Then the attempt has charged 0, boost_free true and value 3

  @edge
  Scenario: The daily refund limit holds
    Given start_refund_limit_per_day is 2
    And meter "energy" is stored with value 5 and anchor_at "2026-10-21T01:00:00Z"
    When I start and cancel "att-r1", "att-r2" and "att-r3" in order
    Then the first two end "cancelled" with refunded 1
    And the third ends "expired" with refunded 0 and refund_denied "daily_limit" and value 4

  @security
  Scenario: Another account's attempt id is not found
    Given "acct-0002" started attempt "att-0200"
    When I send GET /api/energy/attempts/att-0200
    Then the response status is 404 and the error is "attempt_not_found"

  @security
  Scenario: Reward blocks see only played attempts
    Given attempt "att-0300" is "open" and attempt "att-0301" is "confirmed"
    When attemptState is asked for both
    Then "att-0300" is reported as "open" and is not accepted as proof of play
    And "att-0301" is reported as "confirmed" and is accepted
