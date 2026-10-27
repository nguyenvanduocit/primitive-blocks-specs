Feature: Reconciliation, account erasure and restore
  As an operator and as a player
  I want drift caught, my data deleted on request, and my balance to follow my account
  So that the books stay true, deletion is complete, and a new phone shows my currency

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/catalog.json is loaded
    And the store payloads from fixtures/store-payloads.json are available as verified store facts
    And the clock is fixed at "2026-10-27T12:00:00Z"
    And "RECONCILE_INTERVAL_SECONDS" is 3600

  @happy
  Scenario: A clean ledger reconciles without alerts
    Given every balance equals its newest balance_after and credits minus debits
    When the reconciliation job runs
    Then it reports ledger drift 0 and orphan reasons 0

  @security
  Scenario: Ledger drift raises an alert and nothing is edited
    Given "account-001" has a wallet balance of 90 "gems" while the ledger sums to 70
    When the reconciliation job runs
    Then an alert names "account-001", "gems", 90 and 70
    And no ledger row and no balance is changed by the job
    When an operator runs rebuild_balance for "account-001" and "gems"
    Then the balance is 70 and an audit record names the operator, the old and the new value
    And the next run reports ledger drift 0

  @edge
  Scenario: A reason missing from the registry is reported
    Given "LEDGER_REQUIRE_REGISTERED_FLOW" was false and an entry with reason "rogue.grant" exists
    When the reconciliation job runs
    Then the registry audit lists the orphan reason "rogue.grant"

  @happy
  Scenario: The flow report shows faucets and sinks per currency per reason
    Given grants and spends exist for "gems" with several reasons on "2026-10-26"
    When the reconciliation job publishes the flow report
    Then each reason lists its faucet or sink total and the net flow per currency for the day

  @edge
  Scenario: Missed Apple notifications are recovered from the notification history
    Given the server was down when the Apple notification "refund" was sent
    When the reconciliation job reads Get Notification History for the last 604800 seconds
    Then the missing notification is processed and the purchase is refunded
    And notifications already in store_notifications are not processed twice

  @edge
  Scenario: A missed Google void is recovered from the voided purchases list
    # fixtures/store-payloads.json google_voided_purchases
    Given the real-time notification for "google-token-0001" never arrived
    When the reconciliation job reads voidedpurchases.list with a start time not older than 30 days
    Then the purchase "google-token-0001" is refunded and clawed back
    And the unacknowledged purchase "google-token-0009" is refunded with voidedReason 8
    And the job polls again sooner while new voids are being found

  @edge
  Scenario: Pending and unclaimed purchases are re-read
    Given a purchase has been "pending" for more than 3600 seconds
    When the reconciliation job runs
    Then it re-reads the purchase at the store and applies the allowed transition
    And it raises an alert when a purchase has been pending for 604800 seconds

  @edge
  Scenario: Unfinalized Google purchases are retried and reported
    Given a verified Google purchase has no store_finalized_at
    When the reconciliation job runs
    Then products.consume or products.acknowledge is retried according to the product kind
    And the report lists the oldest unfinalized age

  @security
  Scenario: Only one reconciliation runs at a time
    Given two instances start the job together
    When both try to take the lease
    Then one runs and the other skips the run

  @edge
  Scenario: A verified purchase without grant entries is repaired through the idempotent writer
    Given a verified ledger purchase has no grant entries after a manual repair
    When the reconciliation job runs the delivery audit
    Then the grants are issued with the purchase-derived keys
    And running it again changes nothing

  @happy
  Scenario: Account erasure deletes wallet data and de-links purchases
    # fixtures/catalog.json and the erasure registration in README section 6
    Given "account-001" has balances, ledger entries, a spend limit and 2 purchases
    When compliance.account-deletion or the guest purge calls deleteAccount for "account-001"
    Then wallet_balances, wallet_accounts, spend_controls and ledger_entries for "account-001" are deleted
    And both purchase rows remain with account_id null and no other change
    And a second run changes nothing

  @edge
  Scenario: Erasure can delete the purchase rows when configured
    Given "ERASURE_PURCHASE_RECORDS" is "delete"
    When deleteAccount runs for "account-001"
    Then no store_purchases row for "account-001" remains

  @edge
  Scenario: The deletion confirmation lists the balances that will be lost
    Given "account-001" has 1240 "gems" and 2000 "coins"
    When the player opens the delete-account confirmation
    Then it says the balances will be deleted and are not refunded by the game
    And it says refunds of store purchases are handled by the store

  @security
  Scenario: The append-only guard allows the erasure delete and nothing else
    When the erasure routine deletes ledger rows with the erasure flag set
    Then the delete succeeds
    When any other session deletes or updates a ledger row
    Then the database rejects it

  @happy
  Scenario: The balance follows the account to a new device
    Given "account-001" has 1240 "gems" and bought packs on an old phone
    When "account-001" signs in on a new phone
    Then GET /api/wallet shows 1240 "gems"
    And no store restore was needed

  @edge
  Scenario: The shop has no Restore purchases button for packs
    When "account-001" opens the shop and the spending screen
    Then neither screen shows a Restore purchases action for consumable packs
    And the help text says balances belong to the account and return when the player signs in

  @edge
  Scenario: The stores do not return consumables on restore
    Given the store reports current entitlements for "account-001"
    Then a consumable pack never appears in them
    And Google's owned-purchases query returns only purchases that were not consumed

  @edge
  Scenario: Recovery of an unfinished purchase is not a restore
    Given a paid but unfinished transaction exists on the device
    When the app launches
    Then the transaction is submitted automatically without any player action
    And submitting it twice credits it once

  @edge
  Scenario: A guest purchase is not lost when the guest signs in to an existing account
    Given the guest account "account-guest-001" bought "gems_medium" and has 550 "gems"
    When the guest signs in to "account-001"
    Then the wallet merge moves 550 "gems" to "account-001"
    And a later refund of the guest purchase claws back from "account-001"

  @edge
  Scenario: A guest who never signs in is warned before buying
    Given "account-guest-001" is a guest account
    When the confirmation sheet is shown
    Then it says purchases stay on this device's profile until the player signs in
    And Buy stays enabled

  @edge
  Scenario: The store token survives a guest merge
    Given "STORE_ACCOUNT_TOKEN_SOURCE" is "account_id"
    And the guest "account-guest-001" paid for a pack with a transaction that echoes the guest id as the account token
    When the guest is merged into "account-001" with mergeAccounts
    And the store sends a refund notification for that transaction
    Then the token resolves through the merge pointer to "account-001"
    And the clawback is taken from "account-001"
