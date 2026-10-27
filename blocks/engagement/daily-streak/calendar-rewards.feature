Feature: Reward calendar
  As a designer
  I want an escalating calendar with milestone bonuses and several reward types
  So that the reward grows with the streak and every line reaches the right place

  Background:
    Given the app is configured for tenant "tenant-001"
    And the calendar and settings from fixtures/calendar-config.json
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario Outline: The reward follows the cycle day
    Given an account whose streak after the claim is <streak>
    When the reward is resolved
    Then cycle_day is <cycle_day>
    And the coin line is <coins>

    Examples:
      | streak | cycle_day | coins |
      | 1      | 1         | 100   |
      | 2      | 2         | 150   |
      | 4      | 4         | 250   |
      | 6      | 6         | 400   |
      | 7      | 7         | 500   |
      | 8      | 1         | 100   |
      | 15     | 1         | 100   |

  @happy
  Scenario: Cycle day 5 pays an item through the ledger with the item code as currency
    Given the case "consecutive-increment" state with current_streak 4
    When the claim for streak 5 is delivered
    Then the ledger received grant("acc-ann", "booster-rocket", 1, "daily-streak.claim", <claim id>, "daily-streak:acc-ann:2026-10-27:2")

  @happy
  Scenario: Reaching streak 7 pays the milestone once
    Given the case "milestone-7-first-time" in fixtures/streak-vectors.json
    When the case action runs
    Then milestone_ids is ["m7"] and the reward lines end with the gem 30 line
    And milestones_granted contains "m7"
    When the case "milestone-7-already-granted" runs
    Then milestone_ids is empty

  @edge
  Scenario: A milestone is paid by crossing, not by landing exactly
    Given a stored streak of 3 and a repair that restores streak_before 29
    When the player claims and the streak becomes 31 through the repair arithmetic
    Then the milestone "m30" is paid because streak_before is below 30 and streak_after is 30 or more

  @edge
  Scenario: A freeze line is applied to the inventory, clipped to the cap, and never sent to the ledger
    Given the case "freeze-line-clipped-by-cap" in fixtures/streak-vectors.json
    When the case action runs
    Then the stored freeze line has amount 0 and capped true
    And freezes_held stays 2
    And no ledger call carries a freeze line

  @edge
  Scenario: A calendar edit does not change a claim that already exists
    Given "acc-ann" claimed today under calendar version "example-2026-10" with a coin line of 100
    And the calendar is replaced by version "example-2026-11" with a coin line of 900 for cycle day 1
    When the recovery sweep delivers a pending line of that claim
    Then the grant amount is 100 and the stored config_version is "example-2026-10"

  @security
  Scenario Outline: A calendar that breaks a rule is refused at startup
    Given the configuration "<change>"
    When the service starts
    Then startup fails with rule "<rule>"

    Examples:
      | change                                                      | rule |
      | MISS_POLICY freeze_protected and no freeze line in CALENDAR | V1   |
      | REPAIR_PRICE_PER_MISSED_DAY 40 and REPAIR_PLAY_TARGET 0     | V2   |
      | CLAIM_REQUIREMENT play_to_claim and PLAY_ACTIONS empty      | V3   |
      | CALENDAR days 1 to 6 only with cycle_length 7               | V4   |
      | a line with amount 0 or a negative amount                   | V4   |
      | FREEZE_CAP 0 with MISS_POLICY freeze_protected              | V5   |
