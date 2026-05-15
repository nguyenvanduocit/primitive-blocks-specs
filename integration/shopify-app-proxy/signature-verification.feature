Feature: App Proxy Signature Verification
  As the app backend
  I want to verify that every proxy request was forwarded by Shopify
  So that forged or replayed requests are rejected before any business logic runs

  Background:
    Given the app is configured with API secret "test-api-secret"
    And a shop "example.myshopify.com" exists in the database

  @happy
  Scenario: Valid signature — request processed
    Given Shopify forwards a proxy request with params:
      | path_prefix | /apps/myapp              |
      | shop        | example.myshopify.com   |
      | timestamp   | 1700000000               |
      | signature   | valid-computed-signature |
    When the app receives GET /api/proxy/reviews?product_id=123&...
    Then the signature is verified successfully
    And the request is routed to the reviews sub-path handler
    And a "proxy.request_received" event is emitted

  @happy
  Scenario: Correct signature computation — sorted params, no separator
    Given query params: path_prefix=/apps/myapp, product_id=123, shop=example.myshopify.com, timestamp=1700000000
    When the app computes the expected signature
    Then the HMAC input is "path_prefix=/apps/myappproduct_id=123shop=example.myshopify.comtimestamp=1700000000"
    And the params are sorted alphabetically by key
    And the params are concatenated without any separator between pairs
    And the "signature" param is excluded from the input

  @error
  Scenario: Missing signature param — rejected
    Given Shopify forwards a proxy request with no signature param
    When the app receives GET /api/proxy/reviews?shop=example.myshopify.com&timestamp=1700000000
    Then the response status is 401
    And the response body contains error "signature_verification_failed"
    And no business logic runs

  @error
  Scenario: Tampered query param — signature mismatch
    Given a valid proxied request from Shopify with product_id=123
    When an attacker changes product_id to 999 without updating the signature
    Then the recomputed HMAC does not match the signature param
    And the response status is 401
    And the response body contains error "signature_verification_failed"

  @error
  Scenario: Forged request — wrong secret used
    Given an attacker generates a signature using a wrong secret "wrong-secret"
    When the app verifies using "test-api-secret"
    Then the HMACs do not match
    And the response status is 401
    And the response body contains error "signature_verification_failed"

  @error
  Scenario: Signature param included in HMAC input — verification fails
    Given a request where the "signature" param is accidentally included in the HMAC input
    Then the computed HMAC will not match Shopify's expected value
    And verification fails

  @security
  Scenario: Signature comparison uses constant-time equality
    Given a valid proxy request
    When the HMAC comparison runs
    Then it uses crypto.timingSafeEqual (not === or string equality)

  @edge
  Scenario: Extra query params forwarded by merchant theme — still verifiable
    Given a merchant theme passes extra params: utm_source=instagram, ref=homepage
    When Shopify forwards the request with all params included in signature
    Then all params (including utm_source, ref) are included in the sorted HMAC input
    And the signature is valid
    And the request is processed normally

  @edge
  Scenario: Stale timestamp — rejected when freshness check enabled
    Given the app enforces a 300-second timestamp freshness window
    And Shopify's forwarded timestamp is 600 seconds in the past
    When the app checks timestamp freshness
    Then the response status is 401
    And the response body contains error "stale_timestamp"
