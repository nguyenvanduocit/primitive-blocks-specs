Feature: Streak arithmetic
  As a designer
  I want the streak to follow explicit rules for increments, missed days, freezes and repair
  So that every outcome can be predicted from the stored state and the date alone

  Background:
    Given the app is configured for tenant "tenant-001"
    And the calendar and settings from fixtures/calendar-config.json
    And the clock is fixed at "2026-10-27T12:00:00Z"
    And the account zone is "Etc/UTC" so that today is "2026-10-27"

  @happy
  Scenario Outline: Vectors for claim, miss policy, freeze, milestone and cycle rules
    Given the case "<case>" in fixtures/streak-vectors.json
    When the case action runs against the case state_before with the case settings_override
    Then the result matches the case expected block field by field, including rows and notice

    Examples:
      | case                               | rule shown                                          |
      | first-claim                        | first claim is streak 1 on cycle day 1              |
      | consecutive-increment              | a claim adds exactly 1                              |
      | missed-one-day-reset-offer         | reset policy holds the claim for a repair decision  |
      | missed-one-day-reset-decline       | start over keeps longest_streak                     |
      | missed-many-days-outside-window    | no offer beyond REPAIR_WINDOW_DAYS                  |
      | short-streak-no-offer              | no offer below REPAIR_MIN_STREAK                    |
      | decay-two-missed-days              | decay removes DECAY_PER_MISSED_DAY per missed day   |
      | freeze-covers-one-day              | one freeze holds one missed day                     |
      | freeze-covers-two-days             | freezes cover exactly the missed days               |
      | freeze-insufficient-all-or-nothing | a short inventory is kept, the streak resets        |
      | cycle-wrap                         | streak 8 is cycle day 1                             |

  @edge
  Scenario: A freeze holds the streak and does not increment it
    Given the case "freeze-covers-one-day" in fixtures/streak-vectors.json
    When the case action runs
    Then the frozen day "2026-10-26" is a daily_claims row with kind "frozen" and no reward
    And current_streak is 9, which is 8 held plus the claim of today

  @edge
  Scenario: Reading the view never writes
    Given the case "freeze-covers-two-days" state_before is stored
    When I send GET /api/streak
    Then the response shows current 8 and freezes_held 2 before settlement is persisted
    And streak_states.version and daily_claims are unchanged

  @edge
  Scenario: Settling twice at the same day changes nothing
    Given the case "decay-two-missed-days" state_before is stored
    When settle runs at "2026-10-27" and its result is persisted
    And settle runs again at "2026-10-27"
    Then the second run reports no change and the streak is decayed once

  @edge
  Scenario: A zone behind the last credited day gives no claim and no loss
    Given the case "not-available-yet" in fixtures/streak-vectors.json
    When the case action runs
    Then the status is "not_available_yet" and current_streak stays 4

  @edge
  Scenario: longest_streak never decreases
    Given the case "missed-many-days-outside-window" in fixtures/streak-vectors.json
    When the case action runs
    Then longest_streak is 12 while current_streak is 1

  @edge
  Scenario Outline: Repair restores the lost streak within the window
    Given the case "<case>" in fixtures/streak-vectors.json
    When the case action runs
    Then the result matches the case expected block

    Examples:
      | case                         |
      | repair-one-day               |
      | repair-two-days-keeps-freeze |
      | repair-then-claim            |
      | repair-after-window          |
