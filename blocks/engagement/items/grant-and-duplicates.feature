Feature: Granting items, duplicates and the random source hook
  As a game block that gives item rewards
  I want one idempotent grant call that applies, converts or holds an item
  So that a retry never double-grants and a reward is never dropped

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/definitions.json is published
    And the accounts from fixtures/account-states.json exist
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: A fixed instance grant creates one instance
    Given the config set "default"
    When items.grant runs the case "grant-sword-applied" of fixtures/operation-cases.json
    Then the outcome is "applied" with applied_quantity 1 and no ledger call
    And "account-001" owns one more "sword_iron" and the equipment bag shows 4 of 200
    And one "item_granted" event is emitted with source_kind "fixed"

  @happy
  Scenario: A count grant goes through the ledger with the caller's reason
    Given the config set "default"
    When items.grant runs the case "grant-count-applied"
    Then one ledger grant of 2 "booster_double_xp" with reason "objectives.reward" is made
    And the balance of "booster_double_xp" is 5
    And no instance row exists for "booster_double_xp"

  @happy
  Scenario: A duplicate of a trade-in item becomes fragments of the same hero
    Given the config set "default"
    When items.grant runs the case "grant-duplicate-trade-in"
    Then the outcome is "converted" with converted_quantity 1 and no new instance
    And one ledger grant of 30 "shards_ember" with reason "items.duplicate" is made
    And the grant row records source_code "gacha_main" and odds_version "2026-10-v3"
    And the balance of "shards_ember" is 70

  @happy
  Scenario: A duplicate of a convert item pays its disclosed value
    Given the config set "default"
    When items.grant runs the case "grant-duplicate-convert"
    Then one ledger grant of 150 "coins" with reason "items.duplicate" is made
    And "account-001" still owns exactly one "hero_cinder"

  @edge
  Scenario: Replaying a grant returns the original result and changes nothing
    Given the config set "default"
    When items.grant runs the case "grant-replay-same"
    Then the second result equals the first
    And exactly one instance exists for that source_ref
    And the inventory_version is unchanged by the second call

  @edge
  Scenario: The same key with a different argument is a conflict
    Given the config set "default"
    When items.grant runs the case "grant-replay-conflict"
    Then the second call is rejected with "idempotency_conflict"
    And exactly one instance exists for that source_ref

  @edge
  Scenario: A duplicate converts even when the bag is full
    Given the config set "small_bags"
    When items.grant runs the case "grant-duplicate-while-bag-full"
    Then the outcome is "converted" and held_quantity is 0
    And no held grant is created

  @edge
  Scenario: A cap item refuses a fixed source and records nothing
    Given the config set "default"
    When items.grant runs the case "grant-cap-fixed-refused"
    Then the call is rejected with "at_cap"
    And no grant row and no instance is created
    And the caller keeps its own claim open

  @edge
  Scenario: A purchase is delivered above the copy cap
    Given the config set "default"
    When items.grant runs the case "grant-cap-purchase-delivered"
    Then the outcome is "applied"
    And "account-001" owns 2 copies of "frame_gold"

  @edge
  Scenario Outline: Count and instance grants reject what the definition does not allow
    Given the config set "default"
    When items.grant runs the case "<case>"
    Then the call is rejected with "<error>"
    And no grant row is created

    Examples:
      | case                            | error              |
      | grant-count-reason-not-allowed  | reason_not_allowed |
      | grant-retired-rejected          | item_retired       |
      | grant-instance-quantity-two     | invalid_quantity   |

  @edge
  Scenario: A stack at its cap applies what fits and holds the rest
    Given the config set "default"
    When items.grant runs the case "grant-count-partial-stack-cap"
    Then the outcome is "partial" with applied_quantity 1 and held_quantity 4
    And the hold_reason is "stack_cap"
    And the balance of "booster_double_xp" is 99

  @edge
  Scenario: A grant of a stack past its absolute expiry is rejected
    Given the config set "default"
    When items.grant runs the case "grant-expired-stack-rejected" with the clock at "2026-10-30T00:00:00Z"
    Then the call is rejected with "item_expired"
    And no ledger call is made

  @edge
  Scenario: A crash after the ledger call completes once
    Given the config set "default"
    When items.grant runs the case "grant-crash-after-ledger-call"
    Then replaying the call returns the converted outcome with one ledger entry for step "g0"
    And after the recovery job the operation is "applied" and the grant is "settled"

  @security
  Scenario Outline: A random grant must come from a source the definition lists, with an odds version
    Given the config set "default"
    When items.grant runs the case "<case>"
    Then the call is rejected with "source_not_allowed"
    And no grant row is created

    Examples:
      | case                                 |
      | grant-random-unlisted-source         |
      | grant-random-no-odds-version         |
      | grant-random-for-item-without-sources |

  @security
  Scenario: A grant is reachable only by a service credential
    Given a player session for "account-001"
    When the session calls items.grant over HTTP for "sword_iron"
    Then no such route exists for a device and the call is rejected
    And no grant row is created
