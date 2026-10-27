Feature: Definition rules and versions, guest merge, holdings and erasure
  As an operator and as a player who signs in to an existing account
  I want definitions that cannot break the rules, items that move once with me, and deletion that leaves nothing behind
  So that a retired item stays mine, a merge neither duplicates nor loses, and an erased account has no rows left

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/definitions.json is published
    And the accounts from fixtures/account-states.json exist
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: Publishing the catalog registers the ledger flows and no instance code
    When the definition case "publish-registers-flows" of fixtures/expiry-and-merge-cases.json runs
    Then the currency_flows rows equal expected_flows of fixtures/definitions.json
    And no currencies row exists for "sword_iron", "hero_ember", "hero_cinder", "frame_gold", "charm_trial" or "badge_event"

  @happy
  Scenario: Publishing the same draft twice changes nothing
    When the definition case "publish-is-idempotent" runs
    Then one definition row exists and each flow row is registered once

  @happy
  Scenario: A new version supersedes the old one and applies to later operations
    When the definition case "publish-new-version-supersedes" runs
    Then version 1 is "superseded" and version 2 is "active"
    And existing instances keep definition_version 1
    And the quote for level 3 uses version 2

  @edge
  Scenario: A max level may rise and existing copies can use it
    When the definition case "max-level-may-rise" runs
    Then a level 4 copy can upgrade to level 5

  @edge
  Scenario Outline: A draft that breaks a rule is refused and registers nothing
    When the draft "<draft>" of invalid_drafts in fixtures/definitions.json is published
    Then publishing is refused with the draft's expect_error
    And no currency or flow row is written to the ledger registry
    And the definition stays "draft"

    Examples:
      | draft                              |
      | count-with-level                   |
      | equipment-as-count                 |
      | convert-without-value              |
      | cap-on-random-source               |
      | random-without-duplicate-note      |
      | trade-in-fragment-unused           |
      | expiry-on-item-sold-for-money      |
      | gating-without-free-route          |
      | max-level-decrease                 |
      | mode-change-in-new-version         |
      | booster-without-activation         |
      | count-expiry-removes               |
      | instance-code-in-pack-contents     |
      | expiry-without-note                |

  @edge
  Scenario: Retiring a definition stops grants only
    When the definition case "retire-stops-grants-only" runs
    Then a grant is rejected with "item_retired"
    And equip, upgrade, convert and discard of an existing copy are allowed
    And the definition read returns the retired definition with its display keys

  @edge
  Scenario: A retired item stays in the inventory with its label
    When the definition case "retired-item-stays-in-inventory" runs
    Then "inst-r1" is listed with definition status "retired"

  @edge
  Scenario: A definition that is still referenced cannot be deleted
    When the definition case "delete-referenced-definition-refused" runs
    Then the deletion is refused with "definition_in_use"
    And the rows are unchanged

  @happy
  Scenario: A guest merge moves, converts and re-times
    Given the guest and target accounts of merge_cases in fixtures/expiry-and-merge-cases.json
    When the merge case "merge-moves-and-converts" runs
    Then "g-hero-ember" is "converted" and one ledger grant of 30 "shards_ember" with reason "items.duplicate" is made on the target
    And "g-sword-1", "g-sword-2", "g-frame" and "g-charm" belong to the target with added_at "2026-10-27T12:00:00Z"
    And the equip row of "g-sword-1" is removed and "g-sword-1" is still owned
    And "grant-g1" belongs to the target
    And the target has a booster activation from "2026-10-27T12:20:00Z" to "2026-10-27T12:30:00Z"
    And the guest account row points to "account-target-001"
    And the result is 4 moved, 1 converted, 1 held moved and 600 seconds of booster time

  @edge
  Scenario: Replaying the merge returns the first result
    When the merge case "merge-replay-same-merge-id" runs
    Then the result equals the first and the ledger has one entry for step "g0"
    And no instance moves twice

  @edge
  Scenario Outline: A second merge of the same guest fails
    When the merge case "<case>" runs
    Then the answer is "already_merged" and nothing changes

    Examples:
      | case                              |
      | merge-second-merge-id-fails       |
      | merge-into-another-account-fails  |

  @edge
  Scenario: A merge waits for the guest's unfinished operations
    When the merge case "merge-waits-for-guest-operation" runs
    Then the first answer is "merge_incomplete" and nothing changes
    And after recovery the same merge_id completes with the result of "merge-moves-and-converts"

  @edge
  Scenario Outline: Surplus and limit rules at merge
    When the merge case "<case>" runs
    Then the outcome matches the case's expect

    Examples:
      | case                         |
      | merge-surplus-convert-rule   |
      | merge-cap-rule-moves-both    |
      | merge-ignores-capacity       |
      | merge-guest-holds-nothing    |
      | merge-after-merge-resolves-pointer |

  @edge
  Scenario Outline: Holdings list what a guest would carry
    When the holdings case "<case>" runs
    Then the rows equal the case's expect

    Examples:
      | case                                  |
      | holdings-all-three                    |
      | holdings-instances-without-purchase   |
      | holdings-empty                        |
      | holdings-ignores-terminal-and-ended   |
      | holdings-writes-nothing               |

  @happy
  Scenario: Deleting an account removes every row of this block
    When the deletion case "delete-removes-everything" runs
    Then no row of the account remains in item_instances, item_equips, item_grants, item_activations, item_operations or item_accounts
    And this block does not touch the ledger rows

  @edge
  Scenario Outline: Deletion is safe to repeat and to resume
    When the deletion case "<case>" runs
    Then the outcome matches the case's expect

    Examples:
      | case                              |
      | delete-twice                      |
      | delete-resumes-after-partial-run  |
      | delete-unknown-account            |

  @security
  Scenario: A merge cannot stack unique items
    Given the guest and the target both hold "hero_ember"
    When the merge case "merge-moves-and-converts" runs
    Then the target holds exactly one "hero_ember"

  @security
  Scenario: A published definition row cannot be edited
    When an operator updates the published row of "sword_iron" version 1 in place
    Then the update is refused and the row is unchanged
