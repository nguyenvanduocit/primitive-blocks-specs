Feature: Report progress
  As a learner's device
  I want to report derived stats after a sync
  So that the boards follow my progress, while a hand-made request cannot jump the week or lower anyone's totals

  Background:
    Given the app is configured for tenant "tenant-001"
    And BURST_XP is 500 and XP_PER_HOUR is 2000
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And, for a scenario that names a case from fixtures/progress-reports.json, I am authenticated as the owner of a profile seeded with that case's "prev" state

  @happy
  Scenario: The first report is a baseline and earns no weekly XP
    Given the case "first-report-baseline"
    When I send POST /api/board/me/report with the case report
    Then the response status is 200
    And the profile matches the case "after" (xp 3000, week_xp 0)

  @happy
  Scenario: A gain below the cap is credited to the week in full
    Given the case "gain-below-cap"
    When I send POST /api/board/me/report with the case report
    Then the profile matches the case "after" (xp 1400, week_xp 500)
    And updated_at is the server time "2026-10-21T12:00:00Z"

  @edge
  Scenario: A jump above the cap raises the all-time total but credits only the cap
    Given the case "gain-above-cap"
    When I send POST /api/board/me/report with the case report
    Then the response status is 200
    And xp is 5000
    And week_xp is 1500, not 4000

  @edge
  Scenario: Lower totals are folded away
    Given the case "lower-totals-are-ignored"
    When I send POST /api/board/me/report with the case report
    Then the response status is 200
    And xp is 5000, level is 6 and answered is 100
    And week_xp is unchanged at 700
    And streak_days is 2 and accuracy is 60

  @error
  Scenario Outline: Out-of-range or malformed reports are rejected
    When I send POST /api/board/me/report with the "invalid" case "<name>"
    Then the response status is 422
    And the response error is "invalid_stats"
    And the stored profile is unchanged

    Examples: (see fixtures/progress-reports.json "invalid")
      | name                  |
      | negative-xp           |
      | xp-over-max           |
      | level-zero            |
      | level-over-max        |
      | streak-over-max       |
      | accuracy-over-100     |
      | fractional-xp         |
      | string-xp             |
      | client-sent-week-xp   |
      | client-sent-account-id|

  @security
  Scenario: A report can only change the caller's own profile
    Given another learner "prof-ben" exists
    When I send POST /api/board/me/report with a body naming profile "prof-ben"
    Then the response status is 422
    And profile "prof-ben" is unchanged

  @error
  Scenario: Reporting before the profile exists
    Given I am authenticated as an account that has no profile
    When I send POST /api/board/me/report with a valid report
    Then the response status is 404
    And the response error is "profile_missing"

  @edge
  Scenario: Erase my data resets only to the zero state
    Given I am authenticated as the owner of profile "prof-ann"
    When I send POST /api/board/me/reset
    Then xp is 0, answered is 0, week_xp is 0 and level is 1
    And friend_code is still "K7MQ2XAD" and public_board is unchanged
    When I send POST /api/board/me/report with { "xp": 500, "level": 2, "streak_days": 1, "answered": 10, "accuracy": 60 }
    Then week_xp is 0 because the next report is a baseline again
