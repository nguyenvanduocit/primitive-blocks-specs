Feature: Apple identity token verification
  As the backend
  I want every Apple identity token verified against Apple's contract
  So that only tokens issued by Apple for this app and this attempt create sessions

  Background:
    Given the app is configured with APPLE_BUNDLE_ID "com.example.myapp"
    And the app is configured with APPLE_SERVICES_ID "com.example.myapp.web"
    And Apple's signing keys are available to the backend

  @error
  Scenario Outline: Invalid identity token is rejected
    Given the identity token fails verification because of "<reason>"
    When the client sends POST /api/auth/apple/native with that token and a raw nonce
    Then the response status is 401
    And the response body contains error "apple_auth_failed"
    And no user is created and no session is created

    Examples:
      | reason                                  |
      | wrong audience (another app's bundle id) |
      | wrong issuer                             |
      | expired token                            |
      | signature does not match the signing key |
      | algorithm is none                        |
      | algorithm is HS256                       |
      | email present but email_verified false   |

  @security
  Scenario: Token with a nonce that does not match the raw nonce is rejected
    Given Apple issues a valid identity token whose nonce claim is the SHA-256 hex digest of "nonce-aaa"
    When the client sends POST /api/auth/apple/native with that token and raw_nonce "nonce-bbb"
    Then the response status is 401
    And the response body contains error "apple_auth_failed"
    And no session is created

  @error
  Scenario: Missing identity token or nonce is a bad request
    When the client sends POST /api/auth/apple/native without identity_token
    Then the response status is 400 with error "missing_identity_token"
    When the client sends POST /api/auth/apple/native with an identity_token but without raw_nonce
    Then the response status is 400 with error "missing_nonce"

  @error
  Scenario: Apple's signing keys cannot be fetched
    Given the backend has no cached signing keys and Apple's key endpoint is unreachable
    When the client sends POST /api/auth/apple/native with a well-formed token
    Then the response status is 502 with error "upstream_error"
    And no user is created and no session is created
