Feature: Free slice and the single gate
  As a learner who has not bought the unlock
  I want to use a meaningful free part of the app at full quality
  So that I can judge the product before I pay

  # Catalog data: fixtures/free-slice-catalog.json
  # Scopes in order: scope-01 .. scope-06. Items q1 .. q8 as in the fixture.

  Background:
    Given the purchases store is active
    And the catalog has 6 scopes in order scope-01 to scope-06
    And FREE_SCOPE_COUNT is 3 and FREE_RULE is "every"
    And the free item ids are "q1", "q2", "q7"

  @happy
  Scenario: A learner without the unlock can play only the free items
    Given the learner does not own "pro"
    When the gate receives the candidate ids "q1", "q2", "q3", "q4", "q7"
    Then the gate returns "q1", "q2", "q7" in that order
    And the paywall stays closed

  @happy
  Scenario: Locked items are dropped before the session is cut to length
    Given the learner does not own "pro"
    When a session of size 2 is requested from the candidates "q4", "q1", "q3", "q2", "q7"
    Then the gate runs on the full candidate list before truncation
    And the session contains "q1", "q2"
    And the session has length 2

  @happy
  Scenario: A learner who owns the unlock can play everything in the caller's order
    Given the learner owns "pro"
    When the gate receives the candidate ids "q4", "q1", "q3"
    Then the gate returns "q4", "q1", "q3"
    And the returned list is a new array

  @edge
  Scenario: No candidate is playable, so the paywall opens and the entry reports failure
    Given the learner does not own "pro"
    When a session is started from the candidates "q3", "q4", "q8"
    Then the gate returns an empty list
    And the paywall opens
    And the entry answers false and starts no session

  @edge
  Scenario: An empty request does not open the paywall
    Given the learner does not own "pro"
    When the gate receives an empty candidate list
    Then the gate returns an empty list
    And the paywall stays closed

  @edge
  Scenario: An item with no scopes or with an unknown scope is locked
    Given the learner does not own "pro"
    When the gate receives the candidate ids "q5", "q6"
    Then the gate returns an empty list
    And the paywall opens

  @edge
  Scenario Outline: FREE_SCOPE_COUNT moves the line
    Given FREE_SCOPE_COUNT is <count>
    When the free item ids are computed
    Then the free item ids are <free>

    Examples:
      | count | free                   |
      | 0     | none                   |
      | 3     | q1, q2, q7             |
      | 6     | q1, q2, q3, q4, q7, q8 |

  @edge
  Scenario: Difficulty never gates
    Given item "q7" has difficulty "hard" and its scope is free
    And item "q4" has difficulty "easy" and its scope is locked
    When the free item ids are computed
    Then "q7" is free
    And "q4" is locked
