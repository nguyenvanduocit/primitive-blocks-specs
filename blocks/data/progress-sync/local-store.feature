Feature: Local store - load, persist, recover
  As a user who may never create an account
  I want my progress to survive reloads, damaged storage, and unavailable storage
  So that the app always opens and never loses what it can still read

  Background:
    Given STORE_KEY is "myapp-v1"
    And MAX_HISTORY is 20000 and MAX_ELAPSED_MS is 86400000
    And the base record is fixtures/local-record.json

  @happy
  Scenario: Empty storage starts from defaults
    Given storage holds no value under "myapp-v1"
    When the store loads
    Then store.persistent is true
    And history.seq is 0 and history.entries is empty
    And marks is empty and prefs.lang is "en"
    And no exception is thrown

  @happy
  Scenario: An update is persisted and a new store reads it back
    Given an empty store on shared fake storage
    When I update the store to append history entry { ref: "q-001", value: "B", ok: true, ms: 1200, at: 1790000000000, seq: 1 }
    And I create a second store on the same storage
    Then the second store has history.entries with 1 entry with ref "q-001"
    And the stored text parses as JSON and passes validate()

  @error
  Scenario: Unparsable stored text falls back to defaults
    Given storage holds the text "{\"history\": " under "myapp-v1"
    When the store loads
    Then history.seq is 0 and collection is empty
    And no exception is thrown
    And the broken text stays in storage until the next save overwrites it

  @edge
  Scenario Outline: A damaged part is repaired and the rest is kept
    Given storage holds the record from fixtures/load-repair-cases.json case "<case>"
    When the store loads
    Then the properties listed in that case's expect hold
    And no exception is thrown

    Examples:
      | case                              |
      | entry-with-unknown-ref-dropped    |
      | entry-regraded                    |
      | duration-capped                   |
      | backward-time-dropped             |
      | marks-repaired                    |
      | collection-repaired               |
      | prefs-invalid-falls-back-alone    |
      | note-over-limit-dropped           |

  @edge
  Scenario: History above the cap keeps the newest entries and nothing else is reset
    Given storage holds a record with 20003 valid history entries and marks ["q-002"]
    When the store loads
    Then history.entries has 20000 entries
    And the first kept entry is the 4th stored entry
    And entry seq values are 1 through 20000 and history.seq is 20000
    And marks is still ["q-002"]

  @edge
  Scenario: Unknown keys and newer-version sections survive load
    Given storage holds the base record plus milestones { v: 2, anything: ["a", "b"] }
    When the store loads
    Then data.feature_x equals { opened: true }
    And data.milestones equals { v: 2, anything: ["a", "b"] }

  @error
  Scenario: Unusable storage at start runs from memory
    Given storage throws on every setItem
    When the store is created
    Then store.persistent is false
    And update() still applies changes to store.data
    And nothing is written to storage

  @error
  Scenario: A failed write keeps the in-memory change
    Given a store whose storage rejects values longer than 1500 characters
    When I update the store with a 5000-character note on "q-001"
    Then save() returns false and store.persistent is false
    And store.data.notes["q-001"] still has 5000 characters
    And no exception is thrown
