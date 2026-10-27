Feature: Abuse controls on guest creation
  As the owner of a game economy
  I want guest creation to cost an attacker more than it costs the server
  So that bonus farming through free accounts is priced, without storing personal data

  Background:
    Given the app is configured for tenant "tenant-001"
    And the configuration of fixtures/abuse-vectors.json applies
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario Outline: Proof of work is verified with one hash
    Given the seed from fixtures/abuse-vectors.json pow
    When a creation presents counter "<counter>" for creation_request_id "<request>" at <bits> bits
    Then the proof is <outcome>

    Examples:
      | request  | counter | bits | outcome |
      | req-0001 | 75      | 8    | valid   |
      | req-0001 | 429     | 12   | valid   |
      | req-0001 | 11223   | 16   | valid   |
      | req-0001 | 428     | 12   | invalid |
      | req-0002 | 429     | 12   | invalid |
      | req-0001 | 0429    | 4    | invalid |

  @happy
  Scenario Outline: Difficulty rises with load and never passes the ceiling
    When powBits is computed for the case "<case>" of fixtures/abuse-vectors.json pow_bits
    Then the result equals the expected bits

    Examples:
      | case                             |
      | quiet                            |
      | just under half the network cap  |
      | half the network cap             |
      | global cap reached               |
      | both                             |
      | ceiling applies                  |

  @edge
  Scenario: Limits answer 429 on the request after the cap
    Given the counters of fixtures/abuse-vectors.json limits
    When the 61st creation in an hour comes from one network bucket
    Then the response status is 429 with error "rate_limited" and retry_after_seconds
    And no account is created
    And guest_create_throttled is emitted with scope "create_network_hour" and no account_id

  @edge
  Scenario: Load is shed only at twice the global cap
    Given the global minute counter holds 1199 hits
    Then a creation is allowed at the raised difficulty
    When the counter holds 1200 hits
    Then a creation answers 429 "rate_limited"

  @edge
  Scenario: An IPv6 address maps to its /64 bucket
    Given the cases of fixtures/abuse-vectors.json network_bucket
    When two creations come from addresses in the same /64
    Then both count in one bucket

  @security
  Scenario: A challenge is single use, expires and is tied to its network bucket
    Given a challenge issued to bucket A
    When a creation from bucket B presents it
    Then the response status is 410 "challenge_expired" and no account is created
    When a creation from bucket A uses it once and succeeds
    And a second creation presents the same challenge
    Then the response status is 410 "challenge_expired"
    And an expired challenge is refused with 410 "challenge_expired"

  @security
  Scenario: Cheap checks run before the expensive attestation check
    Given GUEST_ATTESTATION_MODE is "required"
    When a creation arrives over the network limit with an attestation token
    Then the response is 429 and the attestation verifier is not called
    When a creation arrives with an invalid proof of work and an attestation token
    Then the response is 422 and the attestation verifier is not called

  @edge
  Scenario Outline: Attestation modes decide what an unattested creation gets
    Given the cases of fixtures/abuse-vectors.json attestation_modes
    When the client reports "<client>" in mode "<mode>"
    Then the response matches the case for that mode and report

    Examples:
      | mode      | client      |
      | off       | absent      |
      | off       | valid       |
      | preferred | absent      |
      | preferred | unavailable |
      | preferred | invalid     |
      | preferred | valid       |
      | required  | absent      |
      | required  | unavailable |
      | required  | invalid     |
      | required  | valid       |

  @edge
  Scenario Outline: Play Integrity verdicts are read as inputs to a policy
    Given the verdict case "<case>" of fixtures/abuse-vectors.json android_verdict_cases
    When the backend decodes the token and applies the policy
    Then the result is as listed

    Examples:
      | case                                                       |
      | genuine device and recognized app                          |
      | empty device verdict                                       |
      | unevaluated app verdict (also the result of a reused token) |
      | request hash differs                                       |
      | activity level above the configured maximum                |

  @edge
  Scenario: A valid attestation skips the proof of work
    Given GUEST_ATTESTATION_MODE is "preferred" and GUEST_POW_SKIP_WHEN_ATTESTED is true
    When a creation carries a valid attestation and no proof of work
    Then the response status is 201 and accounts.creation_attestation is "passed"

  @edge
  Scenario: The device cap applies only where a device signal exists
    Given an attested iOS creation whose key identifier already created 3 accounts today
    When it creates a fourth
    Then the response status is 429 with error "device_limit"
    And an unattested creation is never refused with "device_limit"

  @security
  Scenario: Abuse records hold no personal data
    When a creation is throttled
    Then the log line has only the fields of fixtures/abuse-vectors.json log_line_examples allowed
    And no field of forbidden_fields appears in any log, counter row or event
    And abuse_counters keys are keyed hashes that change when the rotation period passes
    And abuse_counters rows are deleted after expires_at

  @security
  Scenario: Failed credential exchanges are counted per network bucket
    Given 20 failed exchanges from one network bucket in an hour
    When a 21st exchange arrives
    Then the response status is 429 "rate_limited"
