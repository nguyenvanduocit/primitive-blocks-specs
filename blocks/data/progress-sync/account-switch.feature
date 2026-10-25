Feature: Accounts on a shared device and erase
  As a person who may share a device
  I want my progress kept apart from other people's
  So that signing in never mixes two people's data, and erase really erases

  Background:
    Given a fake Snapshot API with accounts "acct-0001" and "acct-0002"
    And the previous-data backup slot PREVIOUS_KEY is empty

  @security
  Scenario: Another account's data on this device is replaced, not merged, and kept aside
    Given the device holds 2 entries, prefs.lang "vi", and the owner marker "acct-0002"
    And account "acct-0001" has an empty snapshot
    When "acct-0001" signs in
    Then the device has 0 history entries
    And the account snapshot has 0 entries (nothing of acct-0002's data was sent)
    And prefs.lang is still "vi"
    And the PREVIOUS_KEY slot holds an export with the 2 original entries
    And store.data.cloud equals { uid: "acct-0001" }

  @happy
  Scenario: The same account on the same device merges
    Given account "acct-0001" holds a snapshot with 1 entry
    And the device holds 1 other entry and the owner marker "acct-0001"
    When "acct-0001" signs in
    Then the device has 2 entries

  @happy
  Scenario: Guest data (no owner) joins the first account that signs in
    Given the device holds 2 entries and no owner marker
    And account "acct-0001" holds a snapshot with 1 other entry
    When "acct-0001" signs in
    Then the device has 3 entries
    And store.data.cloud equals { uid: "acct-0001" }

  @edge
  Scenario: An import clears the owner so imported data joins the account
    Given the device is owned by "acct-0002"
    When I import a valid file
    And the app clears the owner marker
    Then store.data.cloud is absent
    When "acct-0001" signs in
    Then the imported entries are merged into "acct-0001", not replaced

  @security @extrapolated
  Scenario: If the backup cannot be written, the replacement does not happen
    Given the device holds 2 entries and the owner marker "acct-0002"
    And writing PREVIOUS_KEY fails
    When "acct-0001" signs in
    Then the sync state becomes "error"
    And the device still holds the 2 entries and the owner marker "acct-0002"

  @happy
  Scenario: Erase while signed in removes the cloud copy first
    Given "acct-0001" is signed in and the account snapshot has 3 entries
    When the user confirms Erase all data
    Then the client sends DELETE /api/progress/snapshot and receives 204
    And only then is the local record erased
    And a later sync finds 404 no_snapshot and does not bring the data back

  @error
  Scenario: A failed remote erase erases nothing locally
    Given "acct-0001" is signed in with 3 local entries
    And the Snapshot API cannot be reached
    When the user confirms Erase all data
    Then the local record still has 3 entries
    And the user sees a message that nothing was erased

  @edge
  Scenario: Erase without an account is local only
    Given nobody is signed in and the device holds 3 entries
    When the user confirms Erase all data
    Then the local record is reset to defaults
    And the Snapshot API has received 0 requests
