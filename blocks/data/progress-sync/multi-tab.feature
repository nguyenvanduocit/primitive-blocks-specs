Feature: Two tabs share one store
  As a user with the app open in two tabs
  I want each tab to add to what the other wrote
  So that no answer is lost and a Reset in one tab is not undone by the other

  Background:
    Given two stores A and B on the same fake storage under "myapp-v1"
    And each store has its own in-memory data
    And "recording an answer" means update() appending one history entry

  @happy
  Scenario: Tabs answering alternately keep every answer, with or without storage events
    When A records "q-001", B records "q-002", A records "q-003", B records "q-004", A records "q-005"
    Then the stored record has 5 entries with refs ["q-001","q-002","q-003","q-004","q-005"]
    And B's entry seq values are [1,2,3,4,5]
    And the stored text passes validate()

  @edge
  Scenario: Independent-judge finding - a tab that heard no event does not wipe the other's answers
    When B records "q-001" and "q-002"
    And A, which received no storage event, records "q-003"
    Then storage holds 3 entries
    And a new store created on the same storage has refs ["q-001","q-002","q-003"]

  @edge
  Scenario: Reset in one tab reaches the other and is not undone by its next answer
    Given A and B both hold 2 entries
    And A has a subscriber
    When B calls reset()
    And A receives the storage event for "myapp-v1"
    Then A has 0 entries
    And A's subscriber was called once with { reset: true }
    When A records "q-003"
    Then storage holds exactly 1 entry with ref "q-003"

  @edge
  Scenario: Independent-judge finding - a Reset that A has not heard about yet is not undone either
    Given A holds 1 entry and B has adopted it
    When B calls reset()
    And A records "q-002" without any storage event
    Then storage holds exactly 1 entry with ref "q-002"

  @edge
  Scenario: A settings change in one tab and an answer in the other both survive
    When B updates prefs.lang to "vi" and notes["q-001"] to "n"
    And A records "q-001"
    Then A.data.prefs.lang is "vi"
    And storage holds notes { "q-001": "n" } and exactly 1 history entry

  @error
  Scenario: An invalid external value is ignored and repaired by the next save
    Given storage text under "myapp-v1" is replaced by "{\"history\": 5}" by another writer
    When A refreshes
    Then the result is null and A keeps its data
    And no exception is thrown
    When A records "q-001"
    Then the stored text passes validate()

  @edge
  Scenario Outline: Which events cause a refresh
    When the window receives "<event>"
    Then a refresh <happens>

    Examples:
      | event                                  | happens        |
      | storage event for key "myapp-v1"       | happens        |
      | storage event with key null (cleared)  | happens        |
      | storage event for key "other"          | does not happen|
      | pageshow                               | happens        |
      | visibilitychange, state visible        | happens        |
      | visibilitychange, state hidden         | does not happen|

  @error
  Scenario: A failed write in one tab does not adopt older storage over newer memory
    Given A's storage rejects values longer than 1500 characters
    And A holds 1 entry
    When A's data gains a 5000-character note and save() is called
    Then save() returns false
    When A records "q-002"
    Then A.data has 2 entries and still has the 5000-character note
    And A.persistent is false
