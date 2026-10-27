Feature: Equip, unequip, discard, convert and consume
  As a player
  I want to wear, drop, convert and use my items with clear rules
  So that nothing I own changes by accident and every change is applied once

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/definitions.json is published
    And the accounts from fixtures/account-states.json exist
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: Equipping into an occupied slot replaces the item and keeps it owned
    Given the config set "default"
    When the equip case "equip-sword-on-hero-replaces" of fixtures/operation-cases.json runs
    Then the slot "weapon" of "inst-003" holds "inst-001"
    And "inst-005" is returned as replaced and is still "owned"
    And "item_equipped" is emitted

  @happy
  Scenario: A cosmetic equips to the account with no target
    Given the config set "default"
    When the equip case "equip-cosmetic-on-account" runs
    Then the account slot "avatar_frame" holds "inst-007"

  @happy
  Scenario: Equipping an item that is worn elsewhere moves it
    Given the config set "default"
    When the equip case "equip-moves-between-targets" runs
    Then "inst-005" is worn only by "inst-004" and the row of "inst-003" is gone

  @happy
  Scenario: Unequipping empties the slot and keeps the item
    Given the config set "default"
    When the equip case "unequip" runs
    Then no equip row remains and "inst-005" is "owned"
    And "item_unequipped" is emitted

  @edge
  Scenario Outline: Equip rules reject the wrong target, slot or policy
    Given the config set "default"
    When the equip case "<case>" runs
    Then the request is rejected with "<error>"
    And the equips are unchanged

    Examples:
      | case                          | error           |
      | equip-sword-without-target    | target_invalid  |
      | equip-cosmetic-with-target    | target_invalid  |
      | equip-target-not-a-unit       | target_invalid  |
      | equip-item-without-slot       | slot_mismatch   |
      | equip-policy-refused          | equip_refused   |

  @happy
  Scenario: Discarding an instance throws it away and bumps its version
    Given the config set "default"
    When the case "discard-instance" of discard_and_convert_cases runs
    Then "inst-001" is "discarded" with version 2
    And no ledger call is made

  @edge
  Scenario: Discarding a unit unequips its gear but keeps the gear
    Given the config set "default"
    When the case "discard-unit-unequips-gear" runs
    Then "inst-003" is "discarded"
    And no equip row remains and "inst-005" is "owned"

  @edge
  Scenario Outline: Discard and convert refuse equipped items and stale views
    Given the config set "default"
    When the case "<case>" runs
    Then the request is rejected with "<error>"
    And the instance is unchanged

    Examples:
      | case                         | error             |
      | discard-equipped-rejected    | equipped_instance |
      | discard-version-conflict     | version_conflict  |
      | convert-equipped-rejected    | equipped_instance |
      | convert-no-value             | no_conversion_value |
      | convert-value-changed        | value_changed     |

  @happy
  Scenario: Converting an instance pays its value once
    Given the config set "default"
    When the case "convert-instance" runs
    Then "inst-001" is "converted"
    And one ledger grant of 40 "coins" with reason "items.convert" is made
    And the balance of "coins" is 380
    And "item_converted" is emitted

  @edge
  Scenario: A crash after the instance became converted still pays once
    Given the config set "default"
    When the case "convert-crash-after-state-change" runs
    Then after recovery one ledger entry exists for step "g0" and the balance of "coins" is 380
    And a second convert of the same instance is refused

  @happy
  Scenario: Consuming a booster spends one
    Given the config set "default"
    When the consume case "consume-booster-start" runs
    Then the balance of "booster_double_xp" is 2

  @edge
  Scenario: Consuming with nothing in the stack is rejected without an activation
    Given the config set "default"
    When the consume case "consume-insufficient" runs
    Then the request is rejected with "insufficient_balance"
    And no activation row is created

  @edge
  Scenario: Discarding part of a stack spends with the discard reason
    Given the config set "default"
    When the consume case "discard-stack" runs
    Then one ledger spend of 1 "booster_double_xp" with reason "items.discard" is made

  @edge
  Scenario: A purchase delivers a cosmetic once and a refund revokes it
    Given the config set "default"
    When the purchase case "purchase-grants-cosmetic" runs
    Then one instance exists with source_ref "purchase:txn-6001" and replays create no second one
    When the purchase case "refund-revokes-cosmetic" runs
    Then "inst-007" is "revoked" and has no equip row
    And a second revoke returns the same result

  @security
  Scenario: Every player operation answers a replay with the stored result
    Given the config set "default"
    When the same request_id is sent twice for "discard-instance"
    Then the second answer is the stored result and no second state change happens

  @security
  Scenario: The server never reads a state, level or amount from the body
    Given the config set "default"
    When an equip, discard or convert body carries the extra field "state"
    Then the request is rejected with "invalid_request"
