Feature: Changing the rules mid-flight
  As a designer
  I want to change the cap or the interval while players hold half-finished intervals
  So that nobody loses points or progress because of the change

  Background:
    Given the app is configured for tenant "tenant-001"
    And meter "energy" has version 1 with cap 5, regen_amount 1 and regen_interval_seconds 1800, effective "2026-01-01T00:00:00Z"
    And I am authenticated as "acct-0001"
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And every expected value below is the matching case of fixtures/regen-cases.json

  @happy
  Scenario: Raising the cap does not grant points retroactively
    Given version 2 raises the cap to 8, effective "2026-10-21T12:00:00Z"
    And the stored meter is value 5 with anchor_at "2026-10-21T11:00:00Z"
    When I send GET /api/energy
    Then value is 5 and next_tick_at is "2026-10-21T12:30:00Z" and full_at is "2026-10-21T13:30:00Z"
    When the clock is fixed at "2026-10-21T13:00:00Z" and I send GET /api/energy
    Then value is 7

  @happy
  Scenario: Lowering the cap keeps every point the player holds
    Given version 2 lowers the cap to 3, effective "2026-10-21T12:00:00Z"
    And the stored meter is value 5 with anchor_at "2026-10-21T08:00:00Z"
    When the clock is fixed at "2026-10-21T13:00:00Z" and I send GET /api/energy
    Then value is 5 and next_tick_at is null
    And the 5 points are spendable
    Given the stored meter is value 2 with anchor_at "2026-10-21T12:10:00Z"
    When the clock is fixed at "2026-10-21T15:00:00Z" and I send GET /api/energy
    Then value is 3 and anchor_at is "2026-10-21T12:40:00Z"

  @edge
  Scenario: A longer interval does not stretch the tick already in flight
    Given version 2 sets regen_interval_seconds 3600, effective "2026-10-21T12:00:00Z"
    And the stored meter is value 2 with anchor_at "2026-10-21T11:50:00Z"
    When I send GET /api/energy
    Then value is 2 and next_tick_at is "2026-10-21T12:20:00Z" and full_at is "2026-10-21T14:20:00Z"
    When the clock is fixed at "2026-10-21T12:20:00Z" and I send GET /api/energy
    Then value is 3 and next_tick_at is "2026-10-21T13:20:00Z"
    When the clock is fixed at "2026-10-21T13:19:00Z" and I send GET /api/energy
    Then value is 3
    When the clock is fixed at "2026-10-21T13:20:00Z" and I send GET /api/energy
    Then value is 4

  @edge
  Scenario: A shorter interval ends the tick in flight at the earlier of its two ends
    Given version 2 sets regen_interval_seconds 900, effective "2026-10-21T12:00:00Z"
    And the stored meter is value 2 with anchor_at "2026-10-21T11:50:00Z"
    When the clock is fixed at "2026-10-21T12:00:00Z" and I send GET /api/energy
    Then value is 2 and next_tick_at is "2026-10-21T12:05:00Z"
    When the clock is fixed at "2026-10-21T12:05:00Z" and I send GET /api/energy
    Then value is 3 and next_tick_at is "2026-10-21T12:20:00Z"

  @edge
  Scenario: A tick that ended before the change completes under the old interval
    Given version 2 sets regen_interval_seconds 900, effective "2026-10-21T12:00:00Z"
    And the stored meter is value 2 with anchor_at "2026-10-21T11:20:00Z"
    When I send GET /api/energy
    Then value is 3 and anchor_at is "2026-10-21T11:50:00Z" and next_tick_at is "2026-10-21T12:05:00Z"

  @edge
  Scenario: Two points per tick clamp at the cap
    Given version 2 sets regen_amount 2, effective "2026-01-01T00:00:00Z"
    And the stored meter is value 4 with anchor_at "2026-10-21T11:00:00Z"
    When the clock is fixed at "2026-10-21T11:30:00Z" and I send GET /api/energy
    Then value is 5

  @edge
  Scenario: A version scheduled in the future changes nothing before its time
    Given version 2 raises the cap to 8, effective "2026-10-21T13:00:00Z"
    And the stored meter is value 5 with anchor_at "2026-10-21T04:30:00Z"
    When I send GET /api/energy
    Then value is 5 and next_tick_at is null and full_at is null

  @security
  Scenario: A version cannot be back-dated or edited
    When an admin publishes a version with effective_at "2026-10-21T11:59:59Z"
    Then it is refused with "effective_at_in_past"
    When an admin attempts an UPDATE of version 1
    Then the write is refused and version 1 is unchanged

  @security
  Scenario: A version cannot be scoped to one account or segment
    When an admin publishes a version that carries an "account_id" or a "segment" field
    Then it is refused with "invalid_request"
    And energy_meter_configs has no account column
    And "acct-0001" and "acct-0003" read the same cap, interval and attempt cost from version 1

  @edge
  Scenario: An open attempt keeps the mode and cost it started with
    Given version 2 changes consume_mode to "on_fail" and attempt_cost to 2, effective "2026-10-21T12:05:00Z"
    And I started attempt "att-0400" at "2026-10-21T12:00:00Z" under version 1 (on_start, cost 1)
    When I finish "att-0400" with outcome "fail" at "2026-10-21T12:10:00Z"
    Then the attempt keeps charged 1 and no extra point is taken
