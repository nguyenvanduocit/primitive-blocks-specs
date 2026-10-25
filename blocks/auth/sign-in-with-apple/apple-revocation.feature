Feature: Apple authorization revoked on account deletion
  As a user deleting my account
  I want the app's Apple authorization removed as well
  So that the app no longer appears as authorized for my Apple ID

  Background:
    Given a user "user-001" exists with apple_id "000111.mock-subject.0001"
    And the app is configured with APPLE_BUNDLE_ID, APPLE_TEAM_ID, APPLE_KEY_ID and APPLE_PRIVATE_KEY
    And compliance.account-deletion is the caller of these capabilities

  @happy
  Scenario: Fresh re-authentication, then revoke
    Given the user re-authenticated with Apple and the client holds a fresh authorization code
    And Apple issues a valid identity token for sub "000111.mock-subject.0001"
    When verifyAppleReauthentication runs for "user-001" with that token and its raw nonce
    Then it succeeds
    When revokeAppleAuthorization runs with the authorization code and platform "ios"
    Then the backend POSTs the code to Apple's token endpoint with client_id equal to APPLE_BUNDLE_ID and an ES256 client secret
    And the backend POSTs the returned refresh token to Apple's revoke endpoint with token_type_hint "refresh_token"
    And it returns ok true
    And a "user.apple_revoked" event is emitted with ok true

  @happy
  Scenario: Web platform uses the Services ID as client id
    When revokeAppleAuthorization runs with a fresh authorization code and platform "web"
    Then the token and revoke requests carry client_id equal to APPLE_SERVICES_ID

  @security
  Scenario: Re-authentication with a different Apple account stops the deletion
    Given Apple issues a valid identity token for sub "000111.mock-subject.0099"
    When verifyAppleReauthentication runs for "user-001" with that token
    Then it fails with status 403 and error "wrong_account"
    And revokeAppleAuthorization is not called
    And user "user-001" is not deleted

  @error
  Scenario: Revoke failure does not keep the account alive
    Given Apple's revoke endpoint responds with an error
    When revokeAppleAuthorization runs with a fresh authorization code
    Then it returns ok false
    And a "user.apple_revoked" event is emitted with ok false
    And the caller proceeds with the account deletion

  @error
  Scenario: Expired or already used authorization code
    Given Apple's token endpoint answers "invalid_grant" for the code
    When revokeAppleAuthorization runs with that code
    Then it returns ok false
    And the revoke endpoint is not called

  @security
  Scenario: Secrets never appear in logs
    When revokeAppleAuthorization runs and fails
    Then the logs contain no authorization code, no refresh token, no client secret and no private key

  @edge
  Scenario: User without an Apple identity
    Given user "user-002" has no apple_id
    When the deletion flow checks whether Apple revocation applies
    Then verifyAppleReauthentication and revokeAppleAuthorization are not called
