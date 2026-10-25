Feature: Session Management
  As a logged-in user
  I want my session to persist and be secure
  So that I stay authenticated across page loads and my account is protected

  Background:
    Given a user "alice@example.com" exists with id "user-001"

  @happy
  Scenario: Valid session returns user data
    Given a session exists with token "abc123def456" for user "user-001" expiring in 29 days
    When I send GET /api/me with cookie session="abc123def456"
    Then the response status is 200
    And the response body contains user id "user-001", email "alice@example.com"

  @happy
  Scenario: App boot checks session automatically
    Given a session exists with token "abc123def456" for user "user-001" expiring in 29 days
    When the frontend loads and calls GET /api/me
    Then currentUser is set to the user data
    And isAuthenticated is true
    And the app renders the authenticated view

  @happy
  Scenario: Logout destroys session
    Given a session exists with token "abc123def456" for user "user-001" expiring in 29 days
    When I send POST /api/auth/logout with cookie session="abc123def456"
    Then the session row with token "abc123def456" is deleted from the database
    And the response clears the "session" cookie (Set-Cookie with expires in the past)
    And the response status is 200
    And a "user.logged_out" event is emitted with userId "user-001"

  @error
  Scenario: Expired session returns 401
    Given a session exists with token "expired-token" for user "user-001" that expired 1 hour ago
    When I send GET /api/me with cookie session="expired-token"
    Then the response status is 401
    And the response body contains error "session_expired"

  @error
  Scenario: Invalid session token returns 401
    Given no session exists with token "nonexistent-token"
    When I send GET /api/me with cookie session="nonexistent-token"
    Then the response status is 401
    And the response body contains error "invalid_session"

  @error
  Scenario: Missing session cookie returns 401
    When I send GET /api/me with no session cookie
    Then the response status is 401
    And the response body contains error "no_session"

  @happy
  Scenario: Frontend handles 401 by redirecting to login
    Given the frontend has currentUser set
    When GET /api/me returns 401
    Then currentUser is set to null
    And isAuthenticated is false
    And the frontend redirects to /login
    And the session cookie is cleared client-side

  @edge
  Scenario: Multiple active sessions for same user
    Given a session exists with token "session-desktop" for user "user-001" with user_agent "Chrome/Desktop"
    And a session exists with token "session-mobile" for user "user-001" with user_agent "Safari/Mobile"
    When I send GET /api/me with cookie session="session-desktop"
    Then the response status is 200
    When I send POST /api/auth/logout with cookie session="session-desktop"
    Then only the "session-desktop" session is deleted
    And the "session-mobile" session remains valid

  @edge
  Scenario: Session for deleted user returns 401
    Given a session exists with token "orphan-token" for user "user-001"
    And user "user-001" is deleted from the database
    When I send GET /api/me with cookie session="orphan-token"
    Then the response status is 401
    And the response body contains error "invalid_session"

  @security
  Scenario: Session token is not exposed in response body
    Given a session exists with token "abc123def456" for user "user-001" expiring in 29 days
    When I send GET /api/me with cookie session="abc123def456"
    Then the response body does not contain the string "abc123def456"
    And the session token is only in the Set-Cookie header

  @security
  Scenario: Session cookie attributes are secure
    When a new session is created for user "user-001"
    Then the Set-Cookie header for "session" includes httpOnly
    And the Set-Cookie header for "session" includes secure
    And the Set-Cookie header for "session" includes sameSite=lax
    And the Set-Cookie header for "session" includes path=/
    And the Set-Cookie header for "session" does NOT include the domain attribute

  @edge
  Scenario: Expired sessions are cleaned up
    Given 50 sessions exist that expired more than 24 hours ago
    And 10 sessions exist that are still valid
    When the session cleanup job runs
    Then the 50 expired sessions are deleted
    And the 10 valid sessions remain
