Feature: Inventory limits, held grants, the claim path and stable reads
  As a player
  I want a full bag to hold my reward, and an inventory that lists the same way every time
  So that I can make room and claim, and the list never skips or repeats an item

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/definitions.json is published
    And the accounts from fixtures/account-states.json exist
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: A grant on a full bag is held with the reason and a time limit
    Given the config set "small_bags"
    When items.grant runs the case "grant-bag-full-held" of fixtures/operation-cases.json
    Then the outcome is "held" with held_quantity 1 and hold_reason "bag_full"
    And the grant row is "held" with held_until "2026-11-26T12:00:00Z"
    And "item_granted" and "item_grant_held" are emitted

  @happy
  Scenario: Making room and claiming creates the instance
    Given the config set "small_bags"
    When the held case "claim-after-making-room" runs
    Then one instance is created for the held grant
    And the grant row is "settled" with held_quantity 0
    And "item_held_resolved" is emitted with path "claim"

  @happy
  Scenario: A held reward with a conversion value can be converted
    Given the config set "small_bags"
    When the held case "held-convert" runs
    Then one ledger grant of 40 "coins" with reason "items.convert" is made
    And the grant row is "settled" with held_quantity 0

  @edge
  Scenario: Claiming with no room says so and changes nothing
    Given the config set "small_bags"
    When the held case "claim-no-room" runs
    Then the claim is rejected with "no_room"
    And the grant row is still "held" with held_quantity 1

  @edge
  Scenario: A full held list rejects the grant and the caller keeps its claim
    Given the config set "small_bags"
    When items.grant runs the case "grant-held-limit-rejected"
    Then the call is rejected with "held_limit_reached"
    And no grant row is created

  @edge
  Scenario: A held grant converts by itself at its time limit and leaves a notice
    Given the config set "small_bags"
    When the held case "held-auto-convert" runs with the clock at "2026-11-26T12:00:00Z"
    Then "grant-h1" and "grant-h2" are "settled" with held_quantity 0
    And each has one ledger grant with reason "items.convert"
    And each notice is "unseen" and "item_held_resolved" is emitted with path "auto_convert"

  @edge
  Scenario: A held reward without a conversion value waits until it is claimed
    Given the config set "default"
    When the held case "held-without-value-stays" runs with the clock at "2026-12-27T12:00:00Z"
    Then the grant row is still "held" with held_quantity 1

  @edge
  Scenario: A held stack quantity is claimed as far as the cap allows
    Given the config set "default"
    When the held case "claim-stack-cap-partial" runs
    Then one ledger grant of 4 "booster_double_xp" with reason "objectives.reward" is made
    And the balance of "booster_double_xp" is 94

  @edge
  Scenario: A held duplicate converts at claim time
    Given the config set "small_bags"
    When the held case "claim-duplicate-after-hold" runs
    Then no instance is created
    And one ledger grant of 150 "coins" with reason "items.duplicate" is made

  @edge
  Scenario: A held grant of a retired item stays claimable
    Given the config set "default"
    When the held case "claim-held-of-retired-item" runs
    Then one instance is created

  @happy
  Scenario Outline: The inventory lists in a total order that pages without gaps
    Given the account "account-001" and a page size of 3
    When the client reads the pages of order "<order>"
    Then the ids on each page match fixtures/account-states.json pagination.<order>.pages
    And the discarded instance "inst-008" is never listed
    And the last page has no next cursor

    Examples:
      | order  |
      | newest |
      | rarity |

  @edge
  Scenario Outline: Changes between pages never repeat or skip an item
    Given the account "account-001" and a page size of 3
    And page 1 of order "newest" was read
    When the change "<change>" of fixtures/account-states.json pagination.concurrent_changes happens
    And the remaining pages are read
    Then the outcome matches the case's expect text

    Examples:
      | change                          |
      | level-changes-between-pages     |
      | row-granted-between-pages       |
      | row-discarded-between-pages     |

  @edge
  Scenario: Items tied on added_at are ordered by id
    Given the account "account-001"
    When the newest order is read
    Then "inst-004" comes before "inst-003" although both were added at "2026-10-22T10:00:00Z"

  @edge
  Scenario: A discarded or converted copy frees its bag slot
    Given the config set "default"
    When the case "discard-instance" of discard_and_convert_cases runs
    Then the equipment bag shows 2 of 200
    And the instance is "discarded" with version 2

  @edge
  Scenario: Stacks list by definition order with the same cursor rules
    Given the account "account-001"
    When the stacks are read with a page size of 2
    Then the rows are ordered by sort_order then code
    And a cursor from the inventory read is rejected with "invalid_cursor"

  @security
  Scenario: A forged cursor or a changed filter is rejected
    Given the account "account-001"
    When the client sends a cursor with one edited character
    Then the answer is "invalid_cursor"
    When the client sends a cursor issued for order "newest" with order "rarity"
    Then the answer is "invalid_cursor"

  @security
  Scenario: An oversized limit is clamped
    Given the account "account-001" and the config set "default"
    When the client requests limit 500
    Then at most 100 items are returned

  @security
  Scenario: Another account's instance id looks like a missing one
    Given the account "account-001"
    When the client reads the instance "inst-f1" of "account-full" and an id that does not exist
    Then both answers are "item_not_found" with the same body shape and the same response class
