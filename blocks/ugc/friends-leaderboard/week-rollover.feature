Feature: Week rollover
  As an operator
  I want the weekly board to reset itself every Monday 00:00 UTC
  So that no cron job exists and no XP carries over between weeks

  Background:
    Given the app is configured for tenant "tenant-001"
    And the profiles from fixtures/profiles.json exist

  @happy
  Scenario Outline: The week starts on Monday in UTC
    When the week start is computed for the instant "<instant>"
    Then the result is <week_start_day>

    Examples:
      | instant              | week_start_day | note                    |
      | 2026-10-19T00:00:00Z | 20745          | Monday, first instant   |
      | 2026-10-21T12:00:00Z | 20745          | Wednesday               |
      | 2026-10-25T23:59:59Z | 20745          | Sunday, last second     |
      | 2026-10-26T00:00:00Z | 20752          | next Monday             |
      | 1970-01-01T00:00:00Z | -3             | Thursday, epoch day 0   |

  @happy
  Scenario: Last week's rows drop out of the weekly board without any job
    Given the clock is fixed at "2026-10-21T12:00:00Z"
    When I send GET /api/board?period=week without a session
    Then "prof-cara" (week_start_day 20738, week_xp 1500) is not present
    And the database still holds week_xp 1500 for "prof-cara"

  @happy
  Scenario: The same learner remains on the all-time board
    Given the clock is fixed at "2026-10-21T12:00:00Z"
    When I send GET /api/board?period=all without a session
    Then "prof-cara" is present with xp 8000

  @edge
  Scenario: The first report of a new week starts from zero
    Given the clock is fixed at "2026-10-21T12:00:00Z"
    And the case "new-week-no-carry-over" in fixtures/progress-reports.json
    When I send POST /api/board/me/report with the case report
    Then week_xp is 100, not 1600
    And week_start_day is 20745

  @edge
  Scenario: The boundary moves at Monday 00:00 UTC
    Given profile "prof-ann" has week_xp 900 and week_start_day 20745
    When the clock is "2026-10-25T23:59:59Z" and I send GET /api/board?period=week
    Then "prof-ann" is present with xp 900
    When the clock is "2026-10-26T00:00:00Z" and I send GET /api/board?period=week
    Then "prof-ann" is not present
    And the board is empty until a learner reports in the new week

  @security
  Scenario: A client cannot choose the week
    Given the clock is fixed at "2026-10-21T12:00:00Z"
    And I am authenticated as the owner of profile "prof-ann"
    When I send POST /api/board/me/report with a valid report and an extra field { "week_start_day": 20738 }
    Then the response status is 422
    And the response error is "invalid_stats"
    And week_start_day is still 20745
