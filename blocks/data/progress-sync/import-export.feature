Feature: Export and import
  As a user who wants a backup or a move to a new device
  I want a file I can export and import
  So that a good file restores my data and a bad file changes nothing

  Background:
    Given the base record is fixtures/local-record.json
    And MAX_IMPORT_CHARS is 5242880
    And fixtures/invalid-imports.json lists the invalid cases

  @happy
  Scenario: Export then import round-trips, keeping unknown keys
    Given a store whose data is the base record
    When I export, reset the store, and import the exported text
    Then the result is { ok: true }
    And data equals the base record plus any defaults the current schema adds on import, including feature_x and the per-device sections
    And the exported text is pretty-printed JSON

  @error
  Scenario Outline: An invalid file is refused whole with an error path
    Given a store whose data is the base record
    When I import the text built by fixtures/invalid-imports.json case "<case>"
    Then the result is { ok: false, error: "<error>" }
    And store.data is exactly what it was before the import
    And the stored text is exactly what it was before the import
    And no exception is thrown

    Examples:
      | case                               | error                      |
      | root-is-array                      | not an object              |
      | malformed-json                     | not valid JSON             |
      | history-over-cap                   | history.entries            |
      | entry-seq-not-position             | history.entries[1].seq     |
      | entry-grade-mismatch               | history.entries[0].ok      |
      | entry-unknown-ref                  | history.entries[2].ref     |
      | entry-duration-over-one-day        | history.entries[0].ms      |
      | entry-time-back-more-than-a-day    | history.entries[2].at      |
      | count-mismatch                     | history.seq mismatch       |
      | marks-duplicate                    | marks duplicate            |
      | collection-duplicate-source        | collection[0].sources      |
      | collection-duplicate-normalized-key| collection[1] duplicate    |
      | collection-key-too-long            | collection[0].key          |
      | note-over-limit                    | notes.q-002                |
      | prefs-unknown-language             | prefs.lang                 |

  @security
  Scenario: Oversized text is refused before it is parsed
    Given a store whose data is the base record
    When I import a text of 5242881 characters
    Then the result is { ok: false, error: "too large" }
    And JSON.parse was not called on that text

  @error
  Scenario: Storage cannot hold the imported data
    Given a store whose storage rejects values longer than 1500 characters
    And the store holds a small valid record
    When I import a valid file whose text is 5000 characters
    Then the result is { ok: false, error: "quota" }
    And store.data is the record held before the import
    And store.persistent has the value it had before the import
    And the stored text is unchanged

  @edge
  Scenario Outline: Values exactly at a limit are accepted
    Given a store whose data is the base record
    When I import the text built by fixtures/invalid-imports.json case "<case>"
    Then the result is { ok: true }

    Examples:
      | case                          |
      | note-at-limit                 |
      | entry-time-back-within-a-day  |

  @edge
  Scenario: A section from a newer client version is accepted untouched
    Given a store whose data is the base record
    When I import the base record with milestones { v: 2, anything: ["a", "b"] }
    Then the result is { ok: true }
    And store.data.milestones equals { v: 2, anything: ["a", "b"] }

  @edge
  Scenario: Retired fields in an old export are dropped, unknown keys are kept
    Given an exported file that contains a field the current schema retired, prefs.theme = "dark"
    And an unknown top-level key "feature_y" = 1
    When I import it
    Then the result is { ok: true }
    And data.prefs has no "theme"
    And data.feature_y equals 1
