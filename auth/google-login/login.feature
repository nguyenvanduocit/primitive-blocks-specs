Feature: Google Login
  As a user
  I want to sign in with my Google account
  So that I can access the app without creating a password

  Background:
    Given the app is configured with GOOGLE_CLIENT_ID "test-client-id.apps.googleusercontent.com"
    And the app is configured with GOOGLE_CLIENT_SECRET "GOCSPX-test-secret"
    And the app is running at "https://myapp.example.com"

  @happy
  Scenario: New user logs in successfully
    Given the Google OAuth server returns valid tokens for "alice@example.com"
    And no user with google_id "google-uid-112233" exists in the database
    When the frontend redirects to Google OAuth with a CSRF state cookie
    And the user authenticates and Google redirects to /auth/callback with code "4/0AX4XfWh-valid-code" and matching state
    And the frontend sends POST /api/auth/google/callback with the code
    Then the backend exchanges the code for tokens with Google
    And the backend verifies the id_token signature, iss, aud, exp, and email_verified
    And a new user is created with email "alice@example.com" and google_id "google-uid-112233"
    And the user role is "user"
    And a new session is created with a 64-char hex token
    And the response status is 200 with user data
    And a Set-Cookie header sets "session" as httpOnly, secure, sameSite=lax
    And a "user.created" event is emitted with the new user id
    And a "user.logged_in" event is emitted

  @happy
  Scenario: Returning user logs in
    Given a user with google_id "google-uid-112233" and email "alice@example.com" already exists
    And the Google OAuth server returns valid tokens for "alice@example.com"
    When the frontend sends POST /api/auth/google/callback with code "4/0AX4XfWh-valid-code"
    Then no new user row is created
    And the existing user's last_login_at is updated to now
    And a new session is created
    And the response status is 200 with the existing user data
    And a "user.logged_in" event is emitted

  @happy
  Scenario: User with allowed domain logs in when domain restriction is active
    Given ALLOWED_DOMAINS is configured as ["company.com"]
    And the Google OAuth server returns valid tokens for "bob@company.com"
    When the frontend sends POST /api/auth/google/callback with code "4/0AX4XfWh-valid-code"
    Then the response status is 200 with user data
    And the user domain is "company.com"

  @error
  Scenario: Invalid auth code rejected by Google
    Given the Google OAuth server returns error "invalid_grant" for any code
    When the frontend sends POST /api/auth/google/callback with code "expired-code"
    Then the response status is 401
    And the response body contains error "google_auth_failed"
    And no session is created
    And no user is created

  @error
  Scenario: Google returns unverified email
    Given the Google OAuth server returns a token with email_verified=false for "unverified@example.com"
    When the frontend sends POST /api/auth/google/callback with code "4/0AX4XfWh-valid-code"
    Then the response status is 403
    And the response body contains error "email_not_verified"
    And no user is created

  @error
  Scenario: User domain not in allowed list
    Given ALLOWED_DOMAINS is configured as ["company.com"]
    And the Google OAuth server returns valid tokens for "alice@gmail.com"
    When the frontend sends POST /api/auth/google/callback with code "4/0AX4XfWh-valid-code"
    Then the response status is 403
    And the response body contains error "domain_not_allowed"
    And no user is created

  @security
  Scenario: CSRF state mismatch rejected
    Given the frontend has a CSRF state cookie with value "state-aaa"
    When Google redirects to /auth/callback with code "4/0AX4XfWh-valid-code" and state "state-bbb"
    Then the frontend does not send the code to the backend
    And the user sees an error message "Authentication failed. Please try again."
    And the frontend redirects to /login

  @security
  Scenario: Missing CSRF state cookie rejected
    Given the frontend has no CSRF state cookie
    When Google redirects to /auth/callback with code "4/0AX4XfWh-valid-code" and state "state-aaa"
    Then the frontend does not send the code to the backend
    And the user sees an error message "Authentication failed. Please try again."

  @error
  Scenario: Google returns error in callback
    When Google redirects to /auth/callback with error "access_denied"
    Then the frontend does not send any code to the backend
    And the user sees an error message "Google sign-in was cancelled or denied."
    And the frontend redirects to /login

  @edge
  Scenario: Concurrent login creates single user
    Given no user with google_id "google-uid-112233" exists
    And the Google OAuth server returns valid tokens for "alice@example.com"
    When two callback requests arrive simultaneously with valid codes for the same google_id
    Then exactly one user row exists with google_id "google-uid-112233"
    And two sessions are created (one per request)

  @security
  Scenario: ID token with wrong audience is rejected
    Given the Google OAuth server returns a token with aud "wrong-client-id.apps.googleusercontent.com"
    When the frontend sends POST /api/auth/google/callback with code "4/0AX4XfWh-valid-code"
    Then the response status is 401
    And the response body contains error "google_auth_failed"
