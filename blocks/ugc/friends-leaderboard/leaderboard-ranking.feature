Feature: Leaderboard ranking
  As a learner
  I want a weekly and an all-time board with fair ranks
  So that I can see where I stand, including when I am far below the top

  Background:
    Given the app is configured for tenant "tenant-001"
    And the profiles from fixtures/profiles.json exist
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario: Weekly board lists only listed learners with XP this week
    When I send GET /api/board?period=week without a session
    Then the response status is 200
    And week_start_day is 20745
    And the rows match fixtures/profiles.json expected.week_board in order
    And "prof-dan" (hidden), "prof-fay" (0 XP) and "prof-cara" (last week's XP only) are not present

  @happy
  Scenario: All-time board ranks by total XP
    When I send GET /api/board?period=all without a session
    Then the rows match fixtures/profiles.json expected.all_board in order
    And "prof-cara" is present with xp 8000

  @edge
  Scenario: Equal XP shares a rank and the next rank skips
    When I send GET /api/board?period=week without a session
    Then "prof-ann" and "prof-ben" both have rank 1
    And "prof-ann" is listed before "prof-ben" because her effective streak 5 is longer than 3
    And "prof-gus" has rank 3

  @edge
  Scenario: Ties on XP and streak are ordered by name, then by id
    Given profiles "prof-x1" named "Zed" and "prof-x2" named "amy" both have 200 week XP and effective streak 1
    When I send GET /api/board?period=week without a session
    Then "prof-x2" is listed before "prof-x1"
    And both have the same rank

  @edge
  Scenario: Streak counts only while it can still be alive
    When I send GET /api/board?period=all without a session
    Then the row for "prof-cara" has streak_days 0 although 9 is stored
    And the row for "prof-ben" has streak_days 3

  @security
  Scenario: Accuracy is hidden below the answer threshold
    When I send GET /api/board?period=week without a session
    Then the row for "prof-eve" has accuracy null although 100 is stored
    And the row for "prof-ann" has accuracy 82
    And no row order depends on accuracy

  @happy
  Scenario: Own rank when below the returned rows
    Given BOARD_SIZE is configured as 3
    And I am authenticated as the owner of profile "prof-eve"
    When I send GET /api/board?period=week
    Then the response has 3 rows and none is "prof-eve"
    When I send GET /api/board/me?period=week
    Then the response has listed true, count_above 3 and rank 4

  @edge
  Scenario: Opted-in learner with no XP this period has no rank
    Given I am authenticated as the owner of profile "prof-fay"
    When I send GET /api/board/me?period=week
    Then the response has listed true and rank null
