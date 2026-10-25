Feature: Public board privacy
  As a learner
  I want to decide whether I appear on the public board and know what strangers can see
  So that my name and numbers are shown only on terms I understand

  Background:
    Given the app is configured for tenant "tenant-001"
    And the profiles from fixtures/profiles.json exist
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario: A new profile is listed by default and gets a friend code
    Given PUBLIC_BOARD_DEFAULT is true
    And I am authenticated as a new account "acc-new" with sign-in name "  Nia   Tran "
    When I send PUT /api/board/me
    Then the response status is 201
    And display_name is "Nia Tran"
    And public_board is true
    And friend_code is 8 characters from the friend-code alphabet
    And xp is 0, level is 1 and week_start_day is 20745

  @happy
  Scenario: Creating the profile twice is idempotent
    Given I am authenticated as the owner of profile "prof-ann"
    When I send PUT /api/board/me
    Then the response status is 200
    And friend_code is still "K7MQ2XAD"

  @happy
  Scenario: Opting out removes me from every board and from rank counts
    Given I am authenticated as the owner of profile "prof-ann"
    When I send PATCH /api/board/me with { "public_board": false }
    Then the response status is 200
    When I send GET /api/board?period=week without a session
    Then "prof-ann" is not present
    And "prof-ben" has rank 1 and "prof-gus" has rank 2
    When I send GET /api/board/me?period=week
    Then the response has listed false and rank null

  @security
  Scenario: A hidden profile cannot be reached by id or by scanning
    When I send GET /api/profiles/prof-dan with a valid session
    Then the response status is 404
    And no endpoint accepts a profile id and returns a profile that is not listed or not in my friends
    When I send GET /api/board?period=all&public_board=false without a session
    Then the response status is 200
    And the rows are identical to expected.all_board and "prof-dan" is not present

  @security
  Scenario: Hiding from the board does not revoke friends who already added me
    Given a friend link from "prof-eve" to "prof-ann" exists
    And I am authenticated as the owner of profile "prof-ann"
    When I send PATCH /api/board/me with { "public_board": false }
    And I authenticate as the owner of profile "prof-eve" and send GET /api/friends
    Then the rows still include "prof-ann"

  @security
  Scenario: Responses never expose server-only or private fields
    When I send GET /api/board?period=all without a session
    Then no row contains account_id, tenant_id, answered, public_board, created_at or updated_at
    And each row contains exactly id, rank, display_name, level, xp, streak_days, accuracy, friend_code

  @security
  Scenario: Anonymous callers cannot use signed-in endpoints
    When I send GET /api/friends without a session
    Then the response status is 401
    When I send POST /api/friends with { "code": "K7MQ2XAD" } without a session
    Then the response status is 401
    When I send GET /api/board/me without a session
    Then the response status is 401

  @edge
  Scenario: Deleting the account removes the profile, the links and the code
    Given a friend link from "prof-eve" to "prof-ann" exists
    When the account "acc-ann" is deleted
    Then profile "prof-ann" no longer exists
    And no friend link references "prof-ann" in either direction
    And "prof-eve" can add a new friend without that link counting toward MAX_FRIENDS
    And POST /api/friends with { "code": "K7MQ2XAD" } returns 404 "friend_not_found"
