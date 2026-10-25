Feature: Sign in with Apple (web redirect)
  As a web user
  I want to sign in with Apple from the browser
  So that I can use the app with my Apple ID

  Background:
    Given the app is configured with APPLE_SERVICES_ID "com.example.myapp.web"
    And the app is running at "https://myapp.example.com"
    And APPLE_SIGN_IN_PLATFORMS includes "web"

  @happy
  Scenario: Start endpoint redirects to Apple with state and a nonce hash
    When the browser requests GET /auth/apple/start
    Then the response is a 302 redirect to "https://appleid.apple.com/auth/authorize"
    And the redirect carries client_id "com.example.myapp.web", redirect_uri "https://myapp.example.com/auth/apple/callback", response_type "code id_token", response_mode "form_post", scope "name email"
    And the redirect carries a random state and a nonce that is the SHA-256 hex digest of the raw nonce
    And a pre-auth cookie holds the state and the raw nonce as httpOnly, secure, SameSite=None with a 5 minute lifetime
    And the raw nonce does not appear in the redirect URL

  @happy
  Scenario: New user returns from Apple and is signed in
    Given the browser holds a pre-auth cookie with state "state-aaa" and a raw nonce
    And Apple issues a valid identity token for sub "000111.mock-subject.0004" whose nonce matches that raw nonce
    When Apple posts the form to /auth/apple/callback with code, that id_token, state "state-aaa" and a user field with first name "Carol" and last name "Diaz"
    Then a new user exists with apple_id "000111.mock-subject.0004" and name "Carol Diaz"
    And the response is a 302 redirect to LOGIN_REDIRECT_PATH
    And a Set-Cookie header sets "session" as httpOnly, secure, sameSite=lax
    And the pre-auth cookie is deleted

  @happy
  Scenario: Returning user posts no user field
    Given a user exists with apple_id "000111.mock-subject.0004" and name "Carol Diaz"
    When Apple posts a valid callback form without a user field
    Then the user is signed in with the name "Carol Diaz"

  @security
  Scenario: State mismatch is rejected
    Given the browser holds a pre-auth cookie with state "state-aaa"
    When Apple posts the form to /auth/apple/callback with state "state-bbb" and an otherwise valid id_token
    Then the response is a 302 redirect to "/login?error=apple_auth_failed"
    And no user is created and no session is created
    And the pre-auth cookie is deleted

  @security
  Scenario: Missing pre-auth cookie is rejected
    Given the browser holds no pre-auth cookie
    When Apple posts the form to /auth/apple/callback with state "state-aaa" and a valid id_token
    Then the response is a 302 redirect to "/login?error=apple_auth_failed"
    And no session is created

  @security
  Scenario: Token issued for the native bundle id is not accepted by the web callback
    Given the browser holds a valid pre-auth cookie
    And the id_token audience is the iOS bundle id instead of the Services ID
    When Apple posts the form to /auth/apple/callback
    Then the response is a 302 redirect to "/login?error=apple_auth_failed"

  @error
  Scenario: User cancels on Apple's page
    When Apple posts the form to /auth/apple/callback with error "user_cancelled_authorize"
    Then the response is a 302 redirect to "/login?error=apple_cancelled"
    And no user is created and no session is created

  @security
  Scenario: Malformed or oversized user field never fails the sign-in
    Given the browser holds a valid pre-auth cookie and the id_token is valid
    When Apple posts a callback whose user field is not valid JSON
    Then the user is signed in
    And the stored name is null
