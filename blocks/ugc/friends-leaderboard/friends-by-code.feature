Feature: Friends by code
  As a learner
  I want to add a friend by typing their short code
  So that I can compare this week's XP with people I know, without asking them to approve

  Background:
    Given the app is configured for tenant "tenant-001"
    And the profiles from fixtures/profiles.json exist
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And I am authenticated as the owner of profile "prof-eve"

  @happy
  Scenario: Add a friend by code
    When I send POST /api/friends with { "code": "K7MQ2XAD" }
    Then the response status is 201
    And the response is the public projection of profile "prof-ann"
    And the response contains display_name "Ann" and level 12
    And a friend link from "prof-eve" to "prof-ann" exists
    And no friend link from "prof-ann" to "prof-eve" exists
    And a "friend.added" event is emitted

  @happy
  Scenario: A pasted code with lower case and a dash is accepted
    When I send POST /api/friends with { "code": "  k7mq-2xad " }
    Then the response status is 201
    And a friend link from "prof-eve" to "prof-ann" exists

  @security
  Scenario: A learner hidden from the board can still be added by code
    Given profile "prof-dan" has public_board false
    When I send POST /api/friends with { "code": "S8JFG5XK" }
    Then the response status is 201
    And the response contains display_name "Dan"
    And the response does not contain "answered", "public_board", "account_id", "tenant_id" or any timestamp

  @error
  Scenario Outline: Malformed codes are rejected before any lookup
    When I send POST /api/friends with { "code": "<input>" }
    Then the response status is 422
    And the response error is "invalid_friend_code"
    And no database lookup by friend_code was made
    And no friend link was created

    Examples: (see fixtures/friend-codes.json "rejected")
      | input     |
      |           |
      | K7MQ2XA   |
      | K7MQ2XAD9 |
      | K7MQ2XA0  |
      | K7MQ2XAO  |
      | K7MQ2XAU  |
      | K7MQ_2XA  |

  @error
  Scenario: A well-formed code that nobody owns
    When I send POST /api/friends with { "code": "Y5EGD7PA" }
    Then the response status is 404
    And the response error is "friend_not_found"
    And no friend link was created

  @error
  Scenario: Adding your own code
    When I send POST /api/friends with { "code": "N2DPW9QT" }
    Then the response status is 422
    And the response error is "cannot_add_self"

  @edge
  Scenario: Adding the same friend twice
    Given a friend link from "prof-eve" to "prof-ann" exists
    When I send POST /api/friends with { "code": "K7MQ2XAD" }
    Then the response status is 409
    And the response error is "already_friends"
    And exactly one friend link from "prof-eve" to "prof-ann" exists

  @edge
  Scenario: The friend list is capped
    Given MAX_FRIENDS is configured as 2
    And friend links from "prof-eve" to "prof-ann" and to "prof-ben" exist
    When I send POST /api/friends with { "code": "R4VNE6YB" }
    Then the response status is 409
    And the response error is "friends_full"
    And "prof-eve" still has exactly 2 friend links
