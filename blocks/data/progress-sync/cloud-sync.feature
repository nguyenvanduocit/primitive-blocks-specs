Feature: Cloud sync
  As a signed-in user
  I want my progress backed up and joined across devices
  So that a new device or a bad connection never costs me data

  Background:
    Given SAVE_DELAY_MS is 3000 and RETRY_DELAY_MS is 30000 and MAX_CONFLICT_RETRIES is 5
    And SNAPSHOT_MAX_CHARS_CLIENT is 900000
    And a fake Snapshot API with accounts "acct-0001" and "acct-0002" and empty storage

  @happy
  Scenario: First sign-in on a device with guest progress sends it to the account
    Given the device holds 2 history entries and no owner marker
    When "acct-0001" signs in
    Then the client sends GET and receives 404 no_snapshot
    And the client sends PUT with base_revision 0 and a snapshot with 2 entries
    And the sync state becomes "synced"
    And store.data.cloud equals { uid: "acct-0001" }

  @happy
  Scenario: A second device receives the account's progress and adds its own
    Given account "acct-0001" holds a snapshot with 1 entry written by device A
    And device B holds 1 other entry and the owner marker "acct-0001"
    When device B syncs
    Then device B has 2 entries
    And the account snapshot has 2 entries

  @edge
  Scenario: A burst of changes is one write, and saving the merge causes no further write
    Given the sync state is "synced" and the client has made N PUT requests so far
    When the user records 3 entries within 1 second
    And 2999 ms pass since the last change
    Then no new PUT has been made
    When 2 more ms pass
    Then exactly 1 new PUT has been made and the snapshot has 3 more entries
    When 9000 ms pass with no further change
    Then no additional PUT is made

  @error
  Scenario: A failed save is reported, retried, and loses nothing
    Given the Snapshot API fails every request with a network error
    When "acct-0001" signs in with 1 local entry
    Then the sync state becomes "error"
    And the local entry is still present
    When the API recovers and 30000 ms pass
    Then the client retries and the sync state becomes "synced"

  @security
  Scenario: An unreadable cloud copy is never overwritten
    Given the account snapshot text is "{broken"
    And the device holds 1 entry
    When "acct-0001" signs in
    Then the sync state becomes "blocked"
    And no PUT is sent
    And the account snapshot text is still "{broken"
    And the device still holds 1 entry

  @edge
  Scenario: A merged snapshot over the client cap is not sent
    Given the device holds 50 notes of 20000 characters each
    When "acct-0001" signs in
    Then the sync state becomes "blocked"
    And no PUT is sent
    And the device data is unchanged

  @edge @extrapolated
  Scenario: A revision conflict triggers a re-read and re-merge
    Given device B read the snapshot at revision 4
    And device A writes revision 5 before device B writes
    When device B sends PUT with base_revision 4 and receives 409 revision_conflict
    Then device B sends GET, merges again against revision 5, and sends PUT with base_revision 5
    And the final snapshot contains the entries of both devices
    And device B made at most 5 attempts

  @edge
  Scenario: Signed out, the client makes no requests
    Given nobody is signed in
    When the user records 3 entries
    And 60000 ms pass
    Then the Snapshot API has received 0 requests
    And the sync state is "off"
