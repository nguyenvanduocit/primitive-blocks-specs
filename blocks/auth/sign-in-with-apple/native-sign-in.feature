Feature: Sign in with Apple (native iOS)
  As an iOS app user
  I want to sign in with the system Sign in with Apple sheet
  So that I can use the app without creating a password and without exposing my email

  Background:
    Given the app is configured with APPLE_BUNDLE_ID "com.example.myapp"
    And the app is running at "https://myapp.example.com"
    And Apple's signing keys are available to the backend

  @happy
  Scenario: New user signs in and the first-authorization name is stored
    Given Apple issues a valid identity token for sub "000111.mock-subject.0001" with email "alice@example.com"
    And no user with apple_id "000111.mock-subject.0001" exists
    When the client sends POST /api/auth/apple/native with the identity token, its raw nonce and display_name "Alice Johnson"
    Then the response status is 200 with user data
    And a new user exists with apple_id "000111.mock-subject.0001", email "alice@example.com", name "Alice Johnson" and role "user"
    And the user's domain is null and email_is_private is false
    And a new session is created with a 64-char hex token
    And a Set-Cookie header sets "session" as httpOnly, secure, sameSite=lax
    And a "user.created" event and a "user.logged_in" event are emitted with provider "apple"

  @happy
  Scenario: Returning user signs in without a name and keeps the stored name
    Given a user exists with apple_id "000111.mock-subject.0001" and name "Alice Johnson"
    And Apple issues a valid identity token for sub "000111.mock-subject.0001"
    When the client sends POST /api/auth/apple/native with the identity token, its raw nonce and no display_name
    Then the response status is 200 with the existing user
    And the user's name is still "Alice Johnson"
    And the user's last_login_at is updated to now
    And no new user row is created
    And only a "user.logged_in" event is emitted

  @happy
  Scenario: User who hides their email signs in with a relay address
    Given Apple issues a valid identity token for sub "000111.mock-subject.0002" with a private relay email and is_private_email "true" as a string
    And no user with that apple_id exists
    When the client sends POST /api/auth/apple/native with the identity token and its raw nonce
    Then the response status is 200
    And the user is stored with the relay address as email and email_is_private true
    And the user's domain is null

  @edge
  Scenario: Identity token without an email creates a user without an email
    Given Apple issues a valid identity token for sub "000111.mock-subject.0003" with no email claim
    When the client sends POST /api/auth/apple/native with the identity token and its raw nonce
    Then the response status is 200
    And the user is stored with email null, name null and domain null
    And the user's apple_id is "000111.mock-subject.0003"

  @edge
  Scenario: Name sent later does not overwrite an existing name, but fills an empty one
    Given a user exists with apple_id "000111.mock-subject.0003" and name null
    When the client sends POST /api/auth/apple/native with a valid token for that sub and display_name "Bob Lee"
    Then the user's name is "Bob Lee"
    When the client signs in again with display_name "Someone Else"
    Then the user's name is still "Bob Lee"

  @edge
  Scenario: Concurrent first sign-ins create a single user
    Given no user with apple_id "000111.mock-subject.0001" exists
    When two requests arrive simultaneously with valid tokens for that sub
    Then exactly one user row exists with that apple_id
    And two sessions are created, one per request

  @happy
  Scenario: Closing the system sheet is silent
    Given the iOS app shows the sign-in screen
    When the user closes the Sign in with Apple sheet
    Then no request is sent to the backend
    And no error message is shown
    And the sign-in screen is idle again

  @edge
  Scenario: Failed backend call keeps the first-authorization name for the retry
    Given the system sheet returned display_name "Alice Johnson" on the first authorization
    And the first POST /api/auth/apple/native fails with a network error
    When the user taps "Sign in with Apple" again and the sheet returns no name
    Then the retried request carries display_name "Alice Johnson"
