Feature: Extra slots earned or bought
  As a player
  I want more slots through play or, if I choose, through a purchase, with everything disclosed
  So that I can do more at once without ever being required to pay

  Background:
    Given the app is configured for tenant "tenant-001"
    And the definition set and configuration from fixtures/catalog.json are published
    And account "acct-001" is signed in with timezone "Asia/Ho_Chi_Minh"
    And the wallet is the "balances" preset of fixtures/catalog.json
    And the purchase records of fixtures/account-cases.json are served by billing.virtual-currency
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario: A progression slot unlocks on first sight and never relocks
    Given the host flag "tier_2" is false
    When I list the queues
    Then the craft queue has 1 active lane and slot 1 is locked with options "flag:tier_2" and "store_product:slot_craft_plus"
    When the host flag "tier_2" becomes true and I list the queues
    Then a slot_unlocks row exists for craft slot 1 with source "progression" and source_ref "tier_2"
    And a "queue_slot_unlocked" event is written
    When the host flag "tier_2" becomes false and I list the queues
    Then the craft queue still has 2 active lanes
    # fixture: fixtures/account-cases.json case "flag-unlock-persists"

  @happy
  Scenario: A slot bought with currency is one keyed spend
    Given craft slot 1 is unlocked and the wallet holds 200 "gems"
    When I unlock craft slot 2 with currency
    Then the ledger received a spend of 150 "gems" with reason "timed-queues.slot-unlock" and key "timed-queues:acct-001:slot:craft:2"
    And a slot_unlocks row exists for slot 2 with source "currency" and the "gems" balance is 50
    When the tablet repeats the unlock
    Then the response has already_unlocked true and the ledger received no second call

  @edge
  Scenario: Slots unlock in index order
    Given no slot above the base is unlocked and the wallet holds 200 "gems"
    When I unlock craft slot 2 with currency
    Then the response error is "slot_out_of_order" with next_unlockable_index 1
    And the ledger received no call

  @edge
  Scenario: A short balance names the shortfall and unlocks nothing
    Given craft slot 1 is unlocked and the wallet holds 100 "gems"
    When I unlock craft slot 2 with currency
    Then the response error is "insufficient_balance" with needed 150, balance 100 and shortfall 50
    And no slot_unlocks row exists for slot 2

  @happy
  Scenario: A verified store purchase unlocks one slot once
    Given the purchase record "txn-1001" is verified for account "acct-001" and product "slot_craft_plus"
    When billing.virtual-currency calls on_purchase_state_changed for "txn-1001"
    Then a slot_unlocks row exists for craft slot 1 with source "purchase" and store_transaction_id "txn-1001"
    When the client then calls claim-purchase for "txn-1001"
    Then the response has already_unlocked true and exactly one row exists for "txn-1001"
    And this block verified no receipt itself

  @edge
  Scenario: A purchase that belongs to another account unlocks nothing
    Given the purchase record "txn-1002" is verified for account "acct-002"
    When account "acct-001" claims "txn-1002"
    Then the response error is "purchase_mismatch" and no slot_unlocks row exists

  @edge
  Scenario: A pending purchase opens the slot only after it is verified
    Given the purchase record "txn-1003" is "pending" for account "acct-001"
    When I claim "txn-1003"
    Then the response error is "purchase_not_verified" with state "pending"
    When the record becomes "verified" and on_purchase_state_changed is called
    Then craft slot 1 is unlocked with source "purchase"

  @edge
  Scenario: A purchase of a product that is not a slot unlocks nothing
    Given the purchase record "txn-1004" is verified for product "gems_small" of kind "consumable"
    When I claim "txn-1004"
    Then the response error is "no_slot_for_product"

  @edge
  Scenario: A second purchase with no locked slot left is reported and not lost
    Given craft slot 1 is already unlocked by "txn-1001" and the purchase record "txn-1005" is verified for "slot_craft_plus"
    When I claim "txn-1005"
    Then the response error is "no_slot_for_product"
    And the unplaced purchase is reported to the operator and its record stays with billing.virtual-currency

  @edge
  Scenario: A refund stops new starts in the slot and never touches running work
    Given craft slot 1 is unlocked by "txn-1001" and item "item-0001" runs in it until "2026-10-21T12:30:00Z"
    When the purchase record "txn-1001" becomes "refunded" and on_purchase_state_changed is called
    Then the slot_unlocks row for slot 1 is "revoked" and a "queue_slot_revoked" event is written
    And item "item-0001" is still running with the same ends_at
    When I collect item "item-0001" after it finishes
    Then the item is collected
    When I start "craft.bread" in slot 1
    Then the response error is "slot_locked" with reason "revoked"
    When the refund is reversed and on_purchase_state_changed is called
    Then the slot is "active" again
    # fixture: fixtures/account-cases.json case "refund-revokes-new-starts-only"

  @edge
  Scenario: A start into a locked slot names every way to unlock it
    When I start "craft.bread" in craft slot 1
    Then the response error is "slot_locked" with reason "not_unlocked" and the unlock options of the definition
    And the free option "flag:tier_2" is listed before the store product

  @happy
  Scenario: A slot survives a reinstall and a second device
    Given craft slot 1 is unlocked by "txn-1001"
    When the same account lists the queues from a new install
    Then the craft queue has 2 active lanes without any restore call for the slot

  @edge
  Scenario: Lanes are the base slots plus the active unlocks, up to the maximum
    Given the craft queue has base_slots 1 and max_slots 3 and two active slot_unlocks rows
    Then the craft queue has 3 lanes
    And a further unlock request answers "already_unlocked" or "slot_out_of_order" and never exceeds max_slots

  @edge
  Scenario Outline: The non-paying path exists for every queue
    Then queue "<queue>" has at least one base slot
    And at least one job of queue "<queue>" has an empty input or inputs with an enabled faucet in the ledger registry
    And no job input of queue "<queue>" is a premium currency

    Examples:
      | queue      |
      | craft      |
      | build      |
      | research   |
      | expedition |

  @edge
  Scenario Outline: A slot option that breaks the product rules is not published
    When the operator publishes the set with slot product "slot_craft_plus" of kind "<kind>"
    Then publishing fails with "slot_product_invalid" and the previous set stays active

    Examples:
      | kind        |
      | consumable  |

  @edge
  Scenario: The currency option of a locked slot renders ApproxMoney and the store option the store's price string
    Given craft slot 2 offers "gems" 150 and craft slot 1 offers the store product "slot_craft_plus"
    When I open the unlock sheet
    Then the "gems" option renders ApproxMoney beside "150 gems" and hides it when the reference price is unavailable
    And the store option shows the store's localized price string and no price constant of the app
    And the sheet computes no money figure of its own

  @security
  Scenario: The block never verifies a receipt
    When a client sends a store receipt to claim-purchase
    Then the request is rejected with "unexpected_field"
    And the only accepted input is a store_transaction_id that billing.virtual-currency has already verified

  @security
  Scenario: One store transaction cannot unlock two slots
    Given "txn-1001" unlocked craft slot 1
    When two devices claim "txn-1001" at the same instant
    Then exactly one slot_unlocks row carries store_transaction_id "txn-1001"

  @security
  Scenario: A client cannot unlock a slot by naming a flag
    When I send unlock-slot with via "flag" for craft slot 1
    Then the response error is "invalid_request"
    And flag unlocks are decided only by the host hook unlock_flag on the server
