Feature: Lazy regeneration
  As a player
  I want my energy to refill with time, up to a cap, whether or not the app is open
  So that the number I see is right on every device and nothing runs on a timer per player

  Background:
    Given the app is configured for tenant "tenant-001"
    And the meters and settings from fixtures/meter-config.json exist
    And meter "energy" has cap 5, regen_amount 1 and regen_interval_seconds 1800
    And I am authenticated as "acct-0001"
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario: A partial interval is kept and the next point is projected
    Given the stored meter is value 2 with anchor_at "2026-10-21T11:50:00Z"
    When I send GET /api/energy
    Then the response status is 200
    And the energy meter has value 2, available 2, cap 5
    And next_tick_at is "2026-10-21T12:20:00Z" and full_at is "2026-10-21T13:20:00Z"
    And server_now is "2026-10-21T12:00:00Z"
    And no row was written

  @happy
  Scenario: A tick completes at its end instant
    Given the stored meter is value 2 with anchor_at "2026-10-21T11:50:00Z"
    And the clock is fixed at "2026-10-21T12:20:00Z"
    When I send GET /api/energy
    Then the energy meter has value 3
    And next_tick_at is "2026-10-21T12:50:00Z"

  @edge
  Scenario: Regeneration stops at the cap after a long absence
    Given the stored meter is value 0 with anchor_at "2026-10-21T02:00:00Z"
    When I send GET /api/energy
    Then the energy meter has value 5
    And next_tick_at is null and full_at is null
    And fixtures/regen-cases.json case "long-absence-stops-at-cap" matches

  @edge
  Scenario: A value above the cap does not regenerate
    Given the stored meter is value 8 with anchor_at "2026-10-21T01:00:00Z"
    When I send GET /api/energy
    Then the energy meter has value 8
    And next_tick_at is null

  @edge
  Scenario: Spending from a full meter starts the cycle at the spend
    Given the stored meter is value 5 with anchor_at "2026-10-21T04:00:00Z"
    When I send POST /api/energy/attempts with attempt_id "att-0100" and meter_code "energy"
    Then the response status is 201
    And the energy meter has value 4
    And next_tick_at is "2026-10-21T12:30:00Z" and full_at is "2026-10-21T12:30:00Z"
    And cycle_started_at is "2026-10-21T12:00:00Z"
    And an energy_full event with state "armed", subject_key "energy:energy:1792584000" and fire_at "2026-10-21T12:30:00Z" is written to the outbox

  @edge
  Scenario: Spending while below the cap keeps the progress already made
    Given the stored meter is value 2 with anchor_at "2026-10-21T11:50:00Z"
    When I send POST /api/energy/attempts with attempt_id "att-0101" and meter_code "energy"
    Then the energy meter has value 1
    And next_tick_at is still "2026-10-21T12:20:00Z"

  @edge
  Scenario: Normalization composes
    Given every case in fixtures/regen-cases.json
    When the meter is advanced to a time between its stored time and the case time and then to the case time
    Then the result equals the direct advance to the case time

  @security
  Scenario: A forged client time changes nothing
    Given the stored meter is value 2 with anchor_at "2026-10-21T11:50:00Z"
    When I send GET /api/energy with the header "X-Client-Time: 2030-01-01T00:00:00Z"
    Then the energy meter has value 2 and next_tick_at "2026-10-21T12:20:00Z"

  @security
  Scenario: A server clock that steps back changes no value
    Given the stored meter is value 2 with anchor_at "2026-10-21T12:10:00Z"
    And fixtures/regen-cases.json case "now-before-anchor" holds
    When I send GET /api/energy
    Then the energy meter has value 2 and anchor_at is not moved earlier

  @edge
  Scenario: A new account starts full
    Given no meter row exists for "acct-0003"
    When "acct-0003" sends GET /api/energy
    Then the energy meter has value 5 and next_tick_at is null
