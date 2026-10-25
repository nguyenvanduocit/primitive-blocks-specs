Feature: Partial Failure and Re-runnable Deletion
  As a user whose deletion was interrupted
  I want to press Delete again and have it finish
  So that I am never stuck with an account I cannot delete or a half-deleted account that comes back

  Background:
    Given a user "alice@example.com" exists with id "user-001" and provider "google"
    And the user has the owned data described in fixtures/user-owned-data.json "seeded_user"
    And "user-001" has a valid session

  @error
  Scenario: The content erase fails as one unit and removes nothing
    Given the database fails during the content erase transaction
    When I send POST /api/account/deletion with a valid proof
    Then the response status is 500
    And the response body contains error "deletion_incomplete"
    And every row owned by "user-001" still exists
    And the account_deletions row for "user-001" has status "failed" and failed_step "content_erase"
    And the session for "user-001" still authenticates

  @error
  Scenario: The identity delete fails after the content was erased
    Given the database fails during the identity delete
    When I send POST /api/account/deletion with a valid proof
    Then the response status is 500
    And the response body contains error "deletion_incomplete"
    And no profile, snapshot, friendship or friend code row owned by "user-001" exists
    And the users row for "user-001" still exists
    And the account_deletions row for "user-001" has status "failed" and failed_step "identity_delete"
    And the session for "user-001" still authenticates

  @happy
  Scenario: Pressing Delete again finishes a failed deletion
    Given a previous deletion for "user-001" failed at "identity_delete"
    When "user-001" requests a new challenge and I send POST /api/account/deletion with a new valid proof
    Then the response status is 204
    And the content erase finds nothing left and raises no error
    And the users row for "user-001" does not exist
    And the account_deletions row for "user-001" does not exist

  @edge
  Scenario: A second request while one is running is refused
    Given a deletion for "user-001" is running with status "requested" updated 5 seconds ago
    When I send POST /api/account/deletion with a valid proof
    Then the response status is 409
    And the response body contains error "deletion_in_progress"
    And the running deletion is not disturbed

  @edge
  Scenario: An abandoned deletion is retaken after the stale window
    Given ACCOUNT_DELETION_STALE_AFTER_SECONDS is 300
    And a deletion for "user-001" has status "content_erased" and was updated 10 minutes ago
    When I send POST /api/account/deletion with a valid proof
    Then the response status is 204
    And the users row for "user-001" does not exist

  @edge
  Scenario: A half-deleted account is not repopulated at the next launch
    Given a previous deletion for "user-001" failed at "identity_delete"
    When "user-001" opens the app and the client calls GET /api/me
    Then the response contains deletionPending true
    And no profile row and no friend code is created for "user-001"
    And the client offers "Finish deleting your account"

  @security
  Scenario: A failure leaves no identifiers in events or logs
    Given the database fails during the identity delete
    When I send POST /api/account/deletion with a valid proof
    Then an "account.deletion_failed" event is emitted with failedStep "identity_delete"
    And the event payload contains no user id, email or subject
    And no log line contains the ID token, the authorization code or the nonce

  @security
  Scenario: Erasers delete only what the user owns
    Given the profile of "user-001" points at friend code "WXYZ6789"
    And the registry entry for "WXYZ6789" is owned by "user-002"
    When "user-001" completes a valid deletion
    Then the registry entry for "WXYZ6789" still exists and is owned by "user-002"
    And the profile and friendships of "user-002" are unchanged apart from the removal of "user-001" from their friend list
