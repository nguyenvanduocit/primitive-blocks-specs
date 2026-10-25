Feature: Apple and Google identities on one account
  As a user who already has an account
  I want Apple to be attached only when I prove I own the account
  So that nobody can take over my account by presenting my email

  Background:
    Given the app is running at "https://myapp.example.com"
    And a user "user-001" exists with google_id "google-uid-112233" and email "alice@example.com" and no apple_id

  @security
  Scenario: Apple email matching a Google account is not merged
    Given Apple issues a valid, email-verified identity token for sub "000111.mock-subject.0005" with email "alice@example.com"
    When the client sends POST /api/auth/apple/native with the token and its raw nonce
    Then the response status is 409
    And the response body contains error "account_exists_with_different_provider"
    And user "user-001" still has no apple_id
    And no new user is created and no session is created

  @happy
  Scenario: Signed-in user links Apple
    Given I am signed in as "user-001"
    And Apple issues a valid identity token for sub "000111.mock-subject.0005"
    When I send POST /api/auth/apple/link with the token and its raw nonce
    Then the response status is 200
    And user "user-001" has apple_id "000111.mock-subject.0005"
    And a "user.identity_linked" event is emitted with provider "apple"
    And no new session is created

  @happy
  Scenario: After linking, Apple sign-in reaches the same account
    Given user "user-001" has apple_id "000111.mock-subject.0005"
    And Apple issues a valid identity token for sub "000111.mock-subject.0005" with email "alice@example.com"
    When the client sends POST /api/auth/apple/native with the token and its raw nonce
    Then the response status is 200 with user "user-001"
    And no new user row is created

  @error
  Scenario: Linking an Apple identity that belongs to another user
    Given another user "user-002" has apple_id "000111.mock-subject.0005"
    And I am signed in as "user-001"
    When I send POST /api/auth/apple/link with a valid token for sub "000111.mock-subject.0005"
    Then the response status is 409 with error "apple_id_in_use"
    And user "user-001" still has no apple_id

  @error
  Scenario: Linking when the account already has Apple
    Given user "user-001" has apple_id "000111.mock-subject.0005"
    And I am signed in as "user-001"
    When I send POST /api/auth/apple/link with a valid token for sub "000111.mock-subject.0006"
    Then the response status is 409 with error "already_linked"
    And user "user-001" still has apple_id "000111.mock-subject.0005"

  @security
  Scenario: Linking requires a session
    When I send POST /api/auth/apple/link without a session cookie
    Then the response status is 401
    And no apple_id is written

  @edge
  Scenario: A relay address never triggers a collision
    Given Apple issues a valid identity token for sub "000111.mock-subject.0007" with a private relay email
    When the client sends POST /api/auth/apple/native with the token and its raw nonce
    Then the response status is 200
    And a new user is created, separate from "user-001"
