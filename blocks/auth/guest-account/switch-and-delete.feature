Feature: Sign out, switch accounts on a shared device, and delete
  As a person who may share a phone
  I want sign-out and deletion to do what they say
  So that nobody sees my progress and a guest can leave for good

  Background:
    Given the app is configured for tenant "tenant-001"
    And the accounts of fixtures/accounts.json and the deletion_cases of fixtures/lifecycle-cases.json exist
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: Signing out of a linked account ends only this device's session
    Given the account "linked" is signed in on two devices
    When the player signs out on device A
    Then device A's session is revoked and the account hint is cleared
    And device B is still signed in
    And device A stores guest.signed_out true
    And the next launch of device A shows the welcome screen with "Sign in" and "Play as guest"

  @happy
  Scenario: A guest is created after sign-out only on request
    Given device A shows the welcome screen after a sign-out
    Then no guest account is created at launch
    When the player taps "Play as guest"
    Then a guest is created as in guest-issuance.feature

  @happy
  Scenario: A guest switches account after a warning
    Given the player is a guest with no recovery code
    When the player opens "Switch account"
    Then the sheet offers "Save progress first", "Create a recovery code first" and "Switch anyway"
    When the player chooses "Switch anyway" and confirms "Switch and leave this guest game"
    Then the device secret is removed from this device
    And the server account stays until the idle rules purge it
    And the welcome screen opens

  @edge
  Scenario: A guest has no sign-out
    Given the player is a guest
    Then the Settings account section shows "Switch account" and no "Sign out"

  @security
  Scenario: A different person on the device never sees the previous person's progress
    Given the device holds data owned by "linked"
    When another account signs in on the device
    Then data.progress-sync replaces the device data after saving it aside
    And the first screen after sign-in does not show the previous data

  @edge
  Scenario: Signing in from the welcome screen is a normal sign-in
    Given the device has no guest and shows the welcome screen
    When the player signs in with Google for an existing account
    Then no link attempt and no conflict sheet are involved
    And the session belongs to the existing account

  @happy
  Scenario: A guest deletes the account from inside the app
    Given fixtures/lifecycle-cases.json deletion_cases "guest deletes the account"
    When the guest confirms deletion and the device secret is presented with the single-use deletion challenge
    Then every registered block's deleteAccount is called
    And the accounts row and its credentials, sessions and link attempts are deleted
    And a tombstone with reason "deleted" is written for each device credential hash
    And the client removes the secure-storage entry, the Block Store entry and the synchronizable Keychain item
    And a later exchange with the old secret answers 410 "guest_purged" with reason "deleted"
    And the player sees the deletion confirmation

  @security
  Scenario: Deletion needs the secret and a fresh single-use challenge
    Given the deletion cases "guest deletion with the wrong secret" and "guest deletion replayed with a used challenge"
    Then each answers 401 and nothing is deleted

  @happy
  Scenario: A linked account is deleted through the deletion block
    Given fixtures/lifecycle-cases.json deletion_cases "linked account deletion"
    When the player deletes the account with the provider proof
    Then the erasers run first
    And the users row is deleted, then the accounts row
    And tombstones with reason "deleted" are written for every retired device credential hash
    And Apple token revocation is left to auth.sign-in-with-apple

  @edge
  Scenario: A guest can request deletion on the web with a recovery code
    Given fixtures/lifecycle-cases.json deletion_cases "web deletion page for a guest"
    When a guest presents a valid recovery code on the deletion page
    Then the account is deleted as in the in-app path
    And a guest with no recovery code is told to use the in-app path

  @edge
  Scenario: Dormant and abandoned are not deletion
    Given a guest is dormant
    Then its data still exists and the credential still works
    And deletion removes the rows rather than marking them

  @security
  Scenario: A credential that survived an uninstall is still removed by deletion
    Given the credential survived an app reinstall
    When the player deletes the account
    Then every device copy of the credential is removed and the privacy text says deletion happens in Settings

  @edge
  Scenario: Purchase records follow the retention decision of the deletion block
    Given the guest bought a pack
    When the guest deletes the account
    Then purchase records are kept or erased exactly as compliance.account-deletion decides and disclosed there
