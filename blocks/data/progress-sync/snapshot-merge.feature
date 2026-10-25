Feature: Snapshot merge
  As a user with progress on two devices
  I want the two copies joined deterministically
  So that nothing is lost, deletions hold, and repeating the merge changes nothing

  Background:
    Given device A is fixtures/snapshot-device-a.json
    And device B is fixtures/snapshot-device-b.json
    And MAX_HISTORY is 20000 and MILESTONE_IDS order is ["first-star","streak-3","streak-7"]
    And the merge is the pure function merge(local, remote) of README section 3

  @happy
  Scenario: Merging B into A produces the expected copy
    When I compute merge(local = A, remote = B)
    Then the result equals fixtures/snapshot-merged-a-local.json
    And history has 6 entries with refs ["q-009","q-001","q-002","q-004","q-003","q-005"] and seq 1..6
    And marks equals ["q-002","q-003","q-004"]
    And the collection keys are "Quotient" and "ratio", and "ratio" has sources ["glossary","api"]
    And settings is { reviewInterval: 10 } and prefs is { lang: "vi" }
    And milestones is { v: 1, level: 3, badges: ["first-star","streak-3"] }

  @happy
  Scenario: Swapping local and remote gives the same sets
    When I compute merge(local = B, remote = A)
    Then the result equals fixtures/snapshot-merged-b-local.json
    And its history, edits, settings, prefs and milestones equal those of the A-local result
    And its marks and collection keys are equal as sets
    And only the order of marks, the order of collection entries and sources, and the "q-001" note differ

  @edge
  Scenario: Repeating the merge changes nothing; a missing remote returns local
    Given M = merge(A, B)
    When I compute merge(M, B)
    Then serialize(M merged with B) equals serialize(M)
    When I compute merge(A, null)
    Then the result contains only the synced sections of A
    And per-device sections cache, session, cloud, and unknown keys are absent

  @edge
  Scenario: The same entry on both sides counts once, identical entries in one copy count each
    Given local history has two identical entries { ref: "q-001", value: "B", ms: 1000 } without "at"
    And remote history has one identical entry
    When I compute merge(local, remote)
    Then history has 2 entries
    Given remote history has two identical entries and local has one
    Then history has 2 entries
    Given local has two and remote has two
    Then history has 2 entries

  @edge
  Scenario: A removed bookmark is not brought back, a later re-add stands
    Given local marks [] with edits.marks q-001 { at: 300, on: false }
    And remote marks ["q-001","q-002"] with edits.marks q-001 { at: 100, on: true }
    When I compute merge(local, remote) and merge(remote, local)
    Then marks equals ["q-002"] in both results
    Given local marks ["q-001"] with edits.marks q-001 { at: 500, on: true }
    And remote marks [] with edits.marks q-001 { at: 300, on: false }
    Then marks contains "q-001" in both results
    Given both sides have edits.marks q-001 at 400, one with on true and one with on false
    Then the merged mark is { at: 400, on: true }

  @edge
  Scenario: A deleted word stays deleted unless saved again afterwards
    Given local has no word and edits.collection { "quotient": 200 } written for " quotient "
    And remote has { key: "Quotient", savedAt: 100 }
    Then merge(local, remote) and merge(remote, local) both have an empty collection
    Given remote has { key: "Quotient", savedAt: 300 }
    Then both results contain the entry with savedAt 300
    Given remote has { key: "Quotient", savedAt: 200 } and the tombstone is 200
    Then both results have an empty collection

  @edge
  Scenario: Stamped sections follow the later stamp; unstamped loses; ties keep local
    Given A.settings is { reviewInterval: 7 } with edits.settings 500 and B.settings is { reviewInterval: 40 } with edits.settings 200
    Then merge(A, B) and merge(B, A) both give settings { reviewInterval: 7 }
    Given neither side has a stamp
    Then merge(A, B) keeps A's settings and merge(B, A) keeps B's
    Given edits.prefs on the remote side is the string "soon" and edits.marks has an entry { at: "x", on: 1 }
    Then those malformed edit entries are ignored and the rest of the merge is unaffected

  @edge
  Scenario: Undated entries come first, and the cap keeps the newest
    Given local has 3 entries without "at" and remote has 2 entries without "at"
    When I compute merge(local, remote)
    Then the first 5 entries are the undated ones in the order found (local first)
    Given local has 15000 dated entries and remote has 15000 other dated entries
    When I compute merge(local, remote)
    Then history has 20000 entries, the newest by "at", with seq 1..20000
