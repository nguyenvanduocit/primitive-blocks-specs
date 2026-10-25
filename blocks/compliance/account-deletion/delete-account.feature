Feature: Delete Account
  As a signed-in user
  I want to delete my account from inside the app
  So that my data and my sign-in are erased and the app stops holding anything about me

  Background:
    Given a user "alice@example.com" exists with id "user-001" and provider "google"
    And the user has the owned data described in fixtures/user-owned-data.json "seeded_user"
    And a user "bob@example.com" exists with id "user-002" with the same kinds of owned data
    And "user-001" has a valid session
    And "user-001" holds a challenge nonce "nonce-abc" issued 30 seconds ago to this session

  @happy
  Scenario: Google user deletes the account with a fresh proof
    When I send POST /api/account/deletion with the "google_valid" proof from fixtures/reauth-proofs.json
    Then the response status is 204
    And the response body is empty
    And no row owned by "user-001" remains in any registered table
    And the users row for "user-001" does not exist
    And the session for "user-001" no longer authenticates
    And the response clears the session cookie
    And an "account.deleted" event is emitted with provider "google" and revocation "not_applicable"
    And the event payload contains no user id, email or subject

  @happy
  Scenario: Apple user deletes the account and the app's Apple tokens are revoked
    Given "user-001" signed in with provider "apple"
    When I send POST /api/account/deletion with the "apple_valid_with_code" proof
    Then the response status is 204
    And exactly one revocation request is made with the authorization code from the proof
    And the revocation request is made after the content erase and before the identity delete
    And an "account.deleted" event is emitted with provider "apple" and revocation "done"

  @happy
  Scenario: Public presence disappears from every read path
    Given "user-001" is listed on the public leaderboard with 4200 XP
    And "user-002" has "user-001" in their friend list
    When "user-001" completes a valid deletion
    Then the leaderboard list does not contain "user-001"
    And reading the profile of "user-001" by id returns not found
    And looking up the friend code of "user-001" returns not found
    And the friend list of "user-002" no longer contains "user-001"
    And the rows of "user-002" are otherwise unchanged

  @error
  Scenario: Proof for a different account is rejected and nothing is deleted
    When I send POST /api/account/deletion with the "google_other_subject" proof
    Then the response status is 403
    And the response body contains error "wrong_account"
    And every row owned by "user-001" still exists
    And the session for "user-001" still authenticates

  @error
  Scenario: Proof older than the allowed age is rejected
    Given ACCOUNT_DELETION_REAUTH_MAX_AGE_SECONDS is 300
    When I send POST /api/account/deletion with the "google_stale" proof issued 20 minutes ago
    Then the response status is 401
    And the response body contains error "reauth_required"
    And every row owned by "user-001" still exists

  @error
  Scenario: Replaying a used nonce is rejected
    Given the proof "google_valid" was already used once and its account_deletions attempt failed
    When I send POST /api/account/deletion with the same proof again
    Then the response status is 401
    And the response body contains error "reauth_required"

  @error
  Scenario: Request without a session is rejected
    When I send POST /api/account/deletion with no session cookie and the "google_valid" proof
    Then the response status is 401
    And the response body contains error "no_session"
    And no row is deleted

  @edge
  Scenario: Failed token revocation does not keep the account alive
    Given the Apple revocation endpoint answers with an error
    And "user-001" signed in with provider "apple"
    When I send POST /api/account/deletion with the "apple_valid_with_code" proof
    Then the response status is 204
    And the users row for "user-001" does not exist
    And an "account.deleted" event is emitted with revocation "failed"
