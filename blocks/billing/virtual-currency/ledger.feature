Feature: Wallet ledger
  As a block that gives or takes a virtual currency
  I want grant and spend with an idempotency key
  So that a retry never double-applies and a balance never goes below zero

  Background:
    Given the app is configured for tenant "tenant-001"
    And the currencies and flows from fixtures/catalog.json are registered
    And the clock is fixed at "2026-10-27T12:00:00Z"
    And "LEDGER_REQUIRE_REGISTERED_FLOW" is true
    And the accounts "account-001" and "account-002" exist with empty wallets

  @happy
  Scenario: A grant and a spend change the balance and return the contract result
    # fixtures/ledger-cases.json case grant_spend_replay
    When "account-001" is granted 100 "gems" with reason "daily-streak.claim" and key "daily-streak:account-001:2026-10-27"
    Then the result is applied true, balance 100 and an entry id
    When "account-001" spends 30 "gems" with reason "energy-lives.refill" and key "energy-lives:account-001:refill-1"
    Then the result is applied true, balance 70 and a second entry id
    And the ledger holds 2 entries for "account-001"
    And every entry carries the server time "2026-10-27T12:00:00Z"

  @happy
  Scenario: A replay of an applied key returns the original result and changes nothing
    Given "account-001" was granted 100 "gems" with key "daily-streak:account-001:2026-10-27" as entry "E1"
    And "account-001" then spent 30 "gems", leaving a balance of 70
    When the same grant is sent again with the same key and arguments
    Then the result is applied true, balance 100 and entry id "E1"
    And the balance is still 70
    And the ledger still holds 2 entries

  @edge
  Scenario: A rejected spend writes nothing and does not consume its key
    Given "account-001" has 70 "gems"
    When "account-001" spends 100 "gems" with reason "season-pass.tier-skip" and key "season-pass:account-001:s1:skip:p-1"
    Then the error is "insufficient_balance" and the balance is 70
    And the ledger holds 0 entries for "account-001"
    When "account-001" is granted 100 "gems" with reason "season-pass.tier-reward" and key "season-pass:account-001:s1:free:3"
    And "account-001" spends 100 "gems" with reason "season-pass.tier-skip" and key "season-pass:account-001:s1:skip:p-1"
    Then the second spend is applied with balance 70

  @edge
  Scenario: A spend of the exact balance reaches zero and the next spend is rejected
    Given "account-001" has 70 "gems"
    When "account-001" spends 70 "gems" with reason "energy-lives.refill" and key "energy-lives:account-001:refill-2"
    Then the balance is 0
    When "account-001" spends 1 "gems" with reason "energy-lives.refill" and key "energy-lives:account-001:refill-3"
    Then the error is "insufficient_balance"

  @edge
  Scenario: A key reused with different arguments is a conflict
    Given "account-001" spent 30 "gems" with key "energy-lives:account-001:refill-1"
    When "account-001" spends 31 "gems" with the same key
    Then the error is "idempotency_conflict"
    When "account-001" is granted 30 "gems" with the same key
    Then the error is "idempotency_conflict"
    And the balance is unchanged

  @security
  Scenario: Keys are unique per tenant, so another account cannot reuse them
    Given "account-001" spent 30 "gems" with key "energy-lives:account-001:refill-1"
    When "account-002" spends 30 "gems" with the same key
    Then the error is "idempotency_conflict"
    And the response contains no balance or entry id of "account-001"

  @edge
  Scenario: A subscription stipend key without an account id cannot mint a second grant after a rebind
    Given "account-001" was granted 50 "gems" with reason "subscriptions.stipend" and key "subscriptions.stipend:apple:3000000100000001:0"
    When "account-002" is granted 50 "gems" with reason "subscriptions.stipend" and the same key
    Then the error is "idempotency_conflict"
    And "account-002" has 0 "gems"

  @edge
  Scenario Outline: Amounts must be positive integers within the limit
    # fixtures/ledger-cases.json invalid_amounts
    When "account-001" is granted <amount> "gems" with reason "daily-streak.claim" and key "k-<n>"
    Then the error is "invalid_amount"
    And the ledger holds 0 entries for "account-001"

    Examples:
      | n | amount     |
      | 1 | 0          |
      | 2 | -5         |
      | 3 | 1.5        |
      | 4 | "10"       |
      | 5 | 1000000001 |

  @edge
  Scenario: The largest allowed amount is accepted
    When "account-001" is granted 1000000000 "coins" with reason "objectives.reward" and key "objectives:account-001:big"
    Then the result is applied true with balance 1000000000

  @edge
  Scenario: Unknown currencies and unregistered reasons are rejected
    When "account-001" is granted 5 "rubies" with reason "objectives.reward" and key "k-rubies"
    Then the error is "unknown_currency"
    When "account-001" is granted 5 "gems" with reason "rogue.grant" and key "k-rogue"
    Then the error is "unknown_reason"
    When "account-001" spends 5 "gems" with reason "daily-streak.claim" and key "k-wrong-direction"
    Then the error is "unknown_reason"
    And the ledger holds 0 entries for "account-001"

  @edge
  Scenario: Disabling a flow stops new entries and leaves history and replays alone
    Given "account-001" was granted 10 "gems" with reason "event-calendar.reward" and key "event-calendar:account-001:e1"
    When the flow "gems" faucet "event-calendar.reward" is disabled
    And "account-001" is granted 10 "gems" with reason "event-calendar.reward" and key "event-calendar:account-001:e2"
    Then the error is "unknown_reason"
    When the first grant is replayed with key "event-calendar:account-001:e1"
    Then the original result is returned

  @happy
  Scenario: Items are counts under the same contract
    When "account-001" is granted 3 "booster_shield" with reason "objectives.reward" and key "objectives:account-001:o-7"
    And "account-001" spends 1 "booster_shield" with reason "game-core.use-booster" and key "game-core:account-001:level-12"
    Then the balance of "booster_shield" is 2

  @edge
  Scenario: A grant that would pass the maximum balance is rejected
    Given "account-001" has 9007199254740991 "coins"
    When "account-001" is granted 1 "coins" with reason "objectives.reward" and key "objectives:account-001:o-9"
    Then the error is "balance_limit_exceeded"
    And the balance is 9007199254740991

  @edge
  Scenario: Ten concurrent spends from one balance apply exactly one
    # fixtures/ledger-cases.json concurrency ten_spends_one_balance
    Given "account-001" has 100 "gems"
    When 10 spends of 70 "gems" with distinct keys run at the same time
    Then exactly 1 spend is applied and 9 return "insufficient_balance"
    And the balance is 30
    And the ledger holds 1 spend entry

  @edge
  Scenario: Ten concurrent calls with one key apply one entry
    Given "account-001" has 100 "gems"
    When 10 spends of 10 "gems" with the same key run at the same time
    Then every call answers applied true with the same entry id
    And the balance is 90
    And the ledger holds 1 entry

  @security
  Scenario: Ledger rows cannot be updated or deleted
    Given "account-001" has a ledger entry
    When the application role tries to update the amount of that entry
    Then the database rejects the statement
    When the application role tries to delete that entry
    Then the database rejects the statement

  @security
  Scenario: No client request reaches the ledger writer except the verified purchase handler
    When the route table is listed
    Then no route accepts an account id, a currency, an amount or a reason from a client body and calls grant or spend
    And the only client route that leads to a grant is POST /api/purchases/verify, whose amounts come from the catalog

  @edge
  Scenario: A guest wallet merges into an account once
    Given the guest account "account-guest-001" has 40 "gems" and 2000 "coins"
    And "account-001" has 10 "gems"
    When mergeAccounts runs for the guest and "account-001" with merge_id "merge-001"
    Then "account-001" has 50 "gems" and 2000 "coins"
    And the guest account has 0 "gems" and 0 "coins"
    And the merge entries use the reasons "virtual-currency.wallet-merge-out" and "virtual-currency.wallet-merge-in"
    When mergeAccounts runs again with merge_id "merge-001" after a simulated crash
    Then the first result is returned and no balance changes
    When the same guest is merged into "account-002" with merge_id "merge-002"
    Then the error is "already_merged"
    And operations on "account-guest-001" resolve to "account-001"

  @happy
  Scenario: A player reads only their own history
    Given "account-001" and "account-002" each have ledger entries
    When "account-001" calls GET /api/wallet/history
    Then every row belongs to "account-001"
    And no row contains an idempotency key or a source reference

  @happy
  Scenario: holdings lists what an account carries, sorted
    Given "account-001" has 40 "gems" bought in a verified purchase, 2000 "coins" earned and 2 "booster_shield"
    When auth.guest-account calls holdings for "account-001"
    Then the list is sorted by category and label key
    And it contains currency "gems" with paid true and effect "carried"
    And it contains currency "coins" with paid false and effect "carried"
    And it contains items "booster_shield" with paid false and effect "carried"

  @edge
  Scenario: Idempotency keys never expire
    Given the oldest ledger entry of "account-001" is older than any claim grace and retry window
    When its grant is replayed with the same key and arguments
    Then the original result is returned and nothing changes

  @edge
  Scenario: A key already applied cannot be reused after a long delay
    Given an entry was applied with key "event-calendar:account-001:e1:r1:gems"
    When the same call arrives again after the claim grace plus the retry window
    Then the answer is applied true with the original entry id
    And no second grant exists

  @edge
  Scenario: Energy is not a ledger currency
    When "account-001" is granted 5 "energy" with reason "energy-lives.ad-refill" and key "energy-lives:account-001:ad:t1"
    Then the error is "unknown_currency"
    And energy grants go through grantEnergy of engagement.energy-lives

  @happy
  Scenario: holders lists the accounts that hold a code, in a stable order, page by page
    Given "account-001" holds 5 "booster_shield", "account-002" holds 0, "account-003" holds 2 and "account-004" holds 9
    When holders is read for "booster_shield" with limit 2 and no cursor
    Then the holders are "account-001" with 5 and "account-003" with 2
    And next_after_account_id is "account-003"
    When holders is read with the cursor "account-003" and limit 2
    Then the holders are "account-004" with 9
    And next_after_account_id is null

  @edge
  Scenario: holders rejects a bad limit or an unknown currency and is not a route
    When holders is read for "booster_shield" with limit 0 or a limit above HOLDERS_MAX_LIMIT
    Then the error is "invalid_amount"
    When holders is read for "rubies"
    Then the error is "unknown_currency"
    And no HTTP route calls holders
