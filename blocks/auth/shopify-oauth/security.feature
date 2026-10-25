Feature: OAuth Security
  As the app backend
  I want to enforce security controls on the OAuth flow
  So that the installation is protected against attacks

  Background:
    Given the app is configured with API key "test-api-key" and secret "test-api-secret"

  @security
  Scenario: HMAC uses constant-time comparison
    Given a valid callback request
    When HMAC verification runs
    Then the comparison uses crypto.timingSafeEqual (not === operator)

  @security
  Scenario: Nonces are cryptographically random
    When a nonce is generated
    Then it uses crypto.randomBytes (not Math.random)
    And it is 32 characters of hex

  @security
  Scenario: Access token is never logged
    When a successful OAuth flow completes
    Then no log entry contains the plaintext access token
    And no log entry contains an access token prefix

  @security
  Scenario: Access token is never returned in API responses
    When any API endpoint is called
    Then no response body contains the access_token field with a real value

  @security
  Scenario: Shop domain regex prevents open redirect
    When the shop parameter is "evil.com/admin/oauth/authorize?redirect_uri=http://evil.com&shop=legit.myshopify.com"
    Then the validation rejects it as invalid_shop_domain

  @security
  Scenario: Callback params excluding hmac and signature are HMAC-verified
    Given callback params: code=ABC, shop=x.myshopify.com, state=NONCE, timestamp=123
    When HMAC is computed
    Then it covers the sorted string "code=ABC&shop=x.myshopify.com&state=NONCE&timestamp=123"
    And the "hmac" and "signature" params are excluded from the HMAC input
