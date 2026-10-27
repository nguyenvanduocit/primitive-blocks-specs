Feature: Assignment and reroll
  As a player
  I want the same goals on every device, a free way to swap one I dislike, and goals that are fair to my play
  So that the board feels like mine and never turns into a chore or a sales channel

  Background:
    Given the app is configured for tenant "tenant-001"
    And the content set from fixtures/definitions.json is published
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And I am authenticated as "acct-001" with timezone "Asia/Ho_Chi_Minh"
    And the account has unlocked no features unless the scenario says otherwise

  @happy
  Scenario Outline: A window follows the account's local calendar
    Given the vector "<name>" in fixtures/assignment-cases.json window_vectors
    When the window for scope "<scope>" is computed at the vector instant
    Then window_key, starts_at and ends_at equal the vector

    Examples:
      | name                   | scope  |
      | vn-daily-midday        | daily  |
      | vn-daily-last-second   | daily  |
      | vn-daily-first-second  | daily  |
      | vn-weekly-midweek      | weekly |
      | vn-weekly-last-second  | weekly |
      | vn-weekly-first-second | weekly |
      | ny-daily-25-hour-day   | daily  |
      | ny-weekly-across-dst   | weekly |

  @happy
  Scenario: A fixed plan assigns every member
    When I send GET /api/objectives?scope=weekly
    Then the items are weekly.active-5-days, weekly.win-20 and weekly.clear-25-levels in tier order
    And each has ends_at "2026-10-25T17:00:00Z"

  @happy
  Scenario Outline: A pool plan draws the board by its rules
    Given the case "<case>" in fixtures/assignment-cases.json draw_cases
    When the daily window "2026-10-21" is assigned
    Then the drawn set satisfies the case "expected"
    And the response also holds the ladder milestones daily.ladder-20, daily.ladder-40, daily.ladder-60 and daily.board-cleared

    Examples:
      | case                                    |
      | draw-no-history-shop-locked             |
      | draw-no-history-shop-unlocked           |
      | avoid-repeat-leaves-exactly-three       |
      | avoid-repeat-fills-from-repeats         |
      | normal-play-slot-falls-back-to-repeats  |
      | occupying-objectives-are-capped         |

  @edge
  Scenario: Two devices see the same set
    Given the case "same-inputs-same-set"
    When device A and device B both send GET /api/objectives?scope=daily
    Then both responses contain the same instance ids in the same order
    And exactly one assignment window exists for window_key "2026-10-21"

  @edge
  Scenario: Two simultaneous first requests produce one set
    When two requests for the first list of the day run at the same moment
    Then one of them inserts the window and the other reads it
    And the account holds exactly the drawn number of task instances plus four ladder instances

  @edge
  Scenario: Every board holds an objective that closes by normal play
    When the daily window is assigned for 50 different window keys
    Then every drawn set contains daily.play-3-rounds or daily.clear-3-levels

  @happy
  Scenario: The list is ordered easy to hard
    When I send GET /api/objectives?scope=daily
    Then the task items are ordered by tier ascending, then sort_order
    And the order is identical on every call

  @happy
  Scenario: A reroll replaces one goal with one of the same tier
    Given the case "reroll-replaces-one-objective-of-the-same-tier" in fixtures/assignment-cases.json reroll_cases
    When I send POST /api/objectives/{instance of daily.win-3}/reroll
    Then the response status is 200
    And the old instance is "replaced" with progress 2 and the replacement is daily.clear-3-levels at progress 0
    And the reroll bank balance is 0
    And daily.win-3 is not drawn again in this window

  @edge
  Scenario Outline: A reroll that cannot happen costs nothing
    Given the case "<case>" in fixtures/assignment-cases.json reroll_cases
    When I send the reroll request of the case
    Then the response status and error match the case "expected"
    And the board and the bank are unchanged

    Examples:
      | case                                  |
      | reroll-without-bank-balance           |
      | same-tier-without-candidate           |
      | completed-objective-cannot-be-rerolled |
      | fixed-plan-cannot-be-rerolled         |

  @edge
  Scenario: Under the any-tier policy a reroll may change the reward tier
    Given the case "any-tier-policy-may-change-the-reward-tier"
    When I send the reroll request of the case
    Then the replacement is one of daily.win-5, daily.clear-3-levels and daily.score-5000
    And the response carries from_tier and to_tier

  @edge
  Scenario: Repeating a reroll returns the same replacement
    Given the case "repeat-request-is-idempotent"
    When I send the reroll request of the case
    Then the response is the original replacement and the bank balance is unchanged

  @security
  Scenario: Another account's instance cannot be rerolled
    Given the case "other-accounts-instance"
    When I send the reroll request of the case
    Then the response status is 404 and the error is "not_found"

  @happy
  Scenario Outline: The reroll bank earns per window and caps
    Given the case "<case>" in fixtures/assignment-cases.json bank_cases
    When the daily window is assigned
    Then the bank row matches the case "expected"

    Examples:
      | case                                           |
      | first-window-credits-one                       |
      | away-for-five-days-fills-the-bank-to-the-cap   |
      | bank-never-exceeds-the-cap                     |
      | missed-day-costs-nothing                       |
      | plans-without-a-bank-have-none                 |

  @edge
  Scenario: A new timezone day key closes the earlier window of the plan
    Given the case "new-day-key-closes-the-previous-window" in fixtures/assignment-cases.json timezone_change
    When the timezone change is applied and I send GET /api/objectives?scope=daily
    Then the new window and the old window instances match the case "expected"
    And only one live window exists for plan "daily"

  @happy
  Scenario Outline: Difficulty scaling is bounded and keeps reward per effort
    Given SCALING_ENABLED is true and the daily plan has scaling_enabled
    And the case "<case>" in fixtures/assignment-cases.json scaling_cases
    When daily.collect-20 is assigned
    Then factor, target and reward match the case "expected"

    Examples:
      | case                              |
      | heavy-history-is-capped-at-max    |
      | above-nominal                     |
      | fractional-factor                 |
      | at-nominal                        |
      | light-history-is-floored-at-min   |
      | too-little-history                |
      | median-not-mean                   |
      | scaling-switched-off              |

  @happy
  Scenario: The scaling input can be the player level
    Given SCALING_INPUT is "player_level" and the case "player-level-input"
    When daily.collect-20 is assigned for each level of the case
    Then factor, target and reward match each level's "expected"

  @security
  Scenario: Spending and entitlements are not scaling inputs
    Given the case "payer-state-is-not-an-input"
    When daily.collect-20 is assigned to both accounts
    Then the targets and rewards are identical for both accounts

  @edge
  Scenario: A scaled target is frozen for the window
    Given the case "scaled-target-is-frozen"
    When the window is re-read after new history exists
    Then the stored target, reward and scale_factor match the case "expected"

  @edge
  Scenario: Objectives that are not scalable keep their nominal values
    Given the case "unscalable-definitions-keep-nominal"
    When daily.win-3 is assigned
    Then its target is 3 and its reward is 40 coins
