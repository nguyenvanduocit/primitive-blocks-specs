Feature: Expiry on the server clock, offline fairness and booster activation
  As a player
  I want timed items to end on the server clock without losing value I never saw expire, and boosters to last exactly as long as stated
  So that being offline never costs me an item silently and a changed device clock changes nothing

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/definitions.json is published
    And the accounts from fixtures/account-states.json exist
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario Outline: The expiry decision follows the server instant and the warning
    Given the expiry config from fixtures/expiry-and-merge-cases.json expiry_action_config
    When the expiry action is computed for the vector "<vector>"
    Then the action equals the vector's expect

    Examples:
      | vector                                          |
      | no-expiry                                       |
      | before-expiry                                   |
      | convert-at-expiry                               |
      | convert-ignores-warning                         |
      | remove-warned-before-expiry                     |
      | remove-warned-before-expiry-one-second-early    |
      | remove-never-warned-after-expiry                |
      | remove-never-warned-last-second                 |
      | remove-never-warned-defer-max                   |
      | remove-first-shown-after-expiry-before-grace    |
      | remove-first-shown-after-expiry-at-grace        |
      | remove-shown-at-expiry-instant                  |
      | remove-shown-so-late-defer-max-wins             |

  @happy
  Scenario: A convert copy pays its value at expiry and leaves a notice
    Given the config set "default"
    When the expiry case "convert-copy-expires" runs
    Then "inst-e1" is "expired" with version 2
    And one ledger grant of 25 "coins" with reason "items.expire" is made
    And the notice is "unseen" and "item_expired" is emitted

  @happy
  Scenario: A stack that expires converts its whole balance
    Given the config set "default"
    When the expiry case "stack-expires-converts" runs with the clock at "2026-10-30T00:00:00Z"
    Then the operation key is "expire:account-expiry-004:key_frost:1793318400"
    And the ledger calls are a spend of 12 "key_frost" and a grant of 60 "coins", both with reason "items.expire"
    And the balances are 0 "key_frost" and 60 "coins"
    And the faucet rows of "key_frost" are disabled

  @edge
  Scenario: Sweeping twice converts once
    Given the config set "default"
    When the expiry cases "sweep-twice-converts-once" and "stack-expiry-twice-once" run
    Then each conversion has one ledger entry per step

  @edge
  Scenario: A stack is converted on the next read when no sweep ran
    Given the config set "default"
    When the expiry case "stack-expiry-lazy-on-read" runs with the clock at "2026-10-31T10:00:00Z"
    Then the stacks list is empty
    And the balance of "coins" is 15

  @edge
  Scenario: A player who consumed meanwhile is converted from the new balance
    Given the config set "default"
    When the expiry case "stack-expiry-player-consumed-meanwhile" runs
    Then the first spend of 12 is rejected and writes nothing
    And the plan is rebuilt with a spend of 11 "key_frost" and a grant of 55 "coins"

  @edge
  Scenario: A crash between the spend and the grant completes once
    Given the config set "default"
    When the expiry case "stack-expiry-crash-between-spend-and-grant" runs
    Then after recovery the balances are 0 "key_frost" and 60 "coins"
    And each step has exactly one ledger entry

  @edge
  Scenario: An inventory read inside the warning window records the warning once
    Given the config set "default"
    When the expiry case "inventory-read-sets-warned-at" runs
    Then "inst-e3" is returned with expiring true and warned_at "2026-10-28T00:00:00Z"
    And the second read leaves warned_at unchanged
    And exactly one "item_expiring_soon" event is emitted

  @edge
  Scenario: A read before the warning window does not warn
    Given the config set "default"
    When the expiry case "read-outside-warning-window-does-not-warn" runs
    Then warned_at is empty and expiring is false

  @edge
  Scenario: A remove copy the player never saw stays unusable but is not removed
    Given the config set "default"
    When the expiry case "remove-copy-never-warned-stays" runs
    Then "inst-e3" is still "owned" and every action except discard and convert answers "item_expired"

  @edge
  Scenario: An offline player gets a grace period after the first sight of an expired copy
    Given the config set "default"
    When the expiry case "offline-player-returns-after-expiry" runs
    Then the read records warned_at "2026-11-05T09:00:00Z"
    And the sweep one second before the grace ends leaves "inst-e3" owned
    And the sweep at the grace end moves "inst-e3" to "expired"

  @edge
  Scenario: A warned copy is removed at its expiry
    Given the config set "default"
    When the expiry case "remove-copy-warned" runs
    Then "inst-e2" is "expired" and no ledger call is made

  @edge
  Scenario: A count definition cannot remove at expiry
    Given the config set "default"
    When the expiry case "expired-stack-not-removed-without-value" runs
    Then publishing is refused with "count_expiry_must_convert"

  @happy
  Scenario Outline: Booster windows follow the policy and the server clock
    Given the activation vector "<vector>" of fixtures/expiry-and-merge-cases.json
    When the activation window is computed
    Then the result equals the vector's expect

    Examples:
      | vector                       |
      | none-active                  |
      | extend-after-active          |
      | extend-uses-latest-of-several |
      | extend-past-limit            |
      | extend-exactly-at-limit      |
      | refuse-while-active          |
      | refuse-after-end             |

  @happy
  Scenario: Using a booster spends one and starts the window
    Given the config set "default"
    When the consume case "consume-booster-start" runs
    Then one ledger spend of 1 "booster_double_xp" with reason "items.consume" is made
    And the activation runs from "2026-10-27T12:00:00Z" to "2026-10-27T12:30:00Z"
    And "item_consumed" and "item_activated" are emitted

  @edge
  Scenario Outline: Booster rules reject before spending
    Given the config set "<config>"
    When the consume case "<case>" runs
    Then the request is rejected with "<error>"
    And no ledger call is made

    Examples:
      | config                | case                       | error                |
      | default               | consume-booster-refuse     | activation_refused   |
      | short_activation_limit | consume-booster-limit     | activation_limit     |
      | default               | consume-expired-stack      | item_expired         |

  @edge
  Scenario: An activation that cannot be written refunds the spend
    Given the config set "default"
    When the consume case "consume-activation-insert-fails" runs
    Then the ledger calls are the spend and a refund grant with reason "items.consume-refund"
    And the balance is 3 and no activation row exists

  @edge
  Scenario: Replaying a consume creates one activation
    Given the config set "default"
    When the consume case "consume-replay" runs
    Then one activation row exists and the balance is 2

  @security
  Scenario: A device clock a day ahead changes nothing
    Given the activation vector "client-clock-a-day-ahead"
    When the activation window is computed
    Then the window starts at "2026-10-27T12:00:00Z"
    And the request carries no time field the server reads
