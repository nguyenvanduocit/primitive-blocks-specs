Feature: Periodic stipends for subscribers, exactly once per slice
  As a subscriber
  I want the currency that comes with my subscription to arrive on schedule without tapping anything
  So that I get what I paid for, once

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/plans-catalog.json exists
    And the cases in fixtures/stipend-schedule.json are available by id
    And "currency_flows" has a faucet row for "subscriptions.stipend" for currency "gems"
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: A monthly plan has one slice per term, due at the term start
    Given the case "monthly-plan-one-slice-per-term"
    When the term is first seen
    Then one slice row exists with due_at "2026-10-27T12:00:00Z" and amount 300 in "gems"
    When the stipend runner runs
    Then the ledger receives grant with reason "subscriptions.stipend" and key "subscriptions.stipend:apple:2000000000000002:0"
    And the slice status is "applied" with the returned entry id

  @happy
  Scenario: A yearly plan is split into thirty-day slices and slice 1 is due exactly at the clock
    Given the case "yearly-plan-thirty-day-slices"
    When the term is first seen
    Then 12 slice rows exist and the due slices are 0 and 1
    When the stipend runner runs
    Then two grants are made with keys ending ":0" and ":1"
    And slices 2 to 11 stay "pending"

  @happy
  Scenario: The stipend arrives without any player action
    Given an entitled subscriber with a due slice
    When the stipend runner runs
    Then the grant is made with no claim request from the client

  @edge
  Scenario: A term shorter than one slice still yields one slice
    Given the case "term-shorter-than-one-slice-still-gets-one"
    When the term is first seen
    Then exactly one slice row exists

  @edge
  Scenario: A free trial grants no stipend by default
    Given the case "free-trial-term-skipped" and "STIPEND_DURING_TRIAL" is false
    When the term is first seen
    Then the slice row is "skipped" with reason "trial" and no grant is made

  @edge
  Scenario: A trial stipend is granted when the project turns it on
    Given the case "free-trial-term-skipped" and "STIPEND_DURING_TRIAL" is true
    When the term is first seen and the runner runs
    Then the slice is "applied"

  @edge
  Scenario: Family-shared access grants no stipend by default
    Given the case "family-shared-term-skipped" and "STIPEND_FOR_FAMILY_SHARED" is false
    When the term is first seen
    Then the slice row is "skipped" with reason "family_shared"

  @edge
  Scenario: A revoked term stops future slices and keeps slices already granted
    Given the case "revoked-term-stops-future-slices"
    When the clock is "2026-12-01T12:00:00Z" and the runner runs
    Then slices 0 and 1 remain "applied"
    And slices 2 and later are "skipped" with reason "revoked"
    And no debit is made because "STIPEND_REVERSAL" is "none"

  @edge
  Scenario: Two workers granting the same slice change the balance once
    Given the replay case "same-slice-granted-twice-by-two-workers"
    When both workers call grant with the same key and arguments
    Then the second call returns the original result
    And the balance rises by 300 once and one slice row is "applied"

  @edge
  Scenario: A chain moved to another account cannot mint a second grant for a granted slice
    Given the replay case "slice-after-chain-moves-to-another-account"
    When the runner calls grant for "acct-002" with the key already applied for "acct-001"
    Then the ledger answers "idempotency_conflict"
    And the slice row is "skipped" with reason "already_granted"
    And the balance of "acct-002" is unchanged

  @edge
  Scenario: A renewal that fails creates no term and so no slice
    Given sequence "apple_billing_failure_then_recovery" of fixtures/store-events.json
    When "apple_fail_to_renew_grace" and "apple_grace_period_expired" are delivered
    Then no new term and no new slice row exist
    When "apple_did_renew_billing_recovery" is delivered
    Then a new term exists with its slice rows

  @edge
  Scenario: Slices of an unlinked chain wait and are granted once an account claims it
    Given an unlinked chain with a due pending slice
    When the runner runs
    Then the slice stays "pending"
    When account "acct-002" claims the chain and the runner runs
    Then the slice is "applied" for "acct-002"

  @edge
  Scenario: Canceled subscribers keep receiving stipends until the paid term ends
    Given a yearly term in state "canceled" with due slices
    When the runner runs
    Then due slices are granted

  @edge
  Scenario: A missing currency_flows row leaves the slice pending and raises an alert
    Given "currency_flows" has no row for "subscriptions.stipend" for currency "gems"
    When the runner calls grant and the ledger answers "unknown_reason"
    Then the slice stays "pending" and an alert is raised

  @edge
  Scenario: Optional reversal debits only what the balance still holds
    Given "STIPEND_REVERSAL" is "spend_clamped" and slice 0 of a term was applied for 300 gems
    And the account balance is 120 gems and "currency_flows" has a sink row for "subscriptions.stipend-reversal"
    When the term is revoked and the runner runs
    Then spend is called for 120 gems with reason "subscriptions.stipend-reversal" and key "subscriptions.stipend-reversal:apple:2000000000000002:0"
    And "reversal_entry_id" is stored on the slice row

  @edge
  Scenario: A zero balance skips the reversal
    Given "STIPEND_REVERSAL" is "spend_clamped" and the account balance is 0
    When the term is revoked and the runner runs
    Then no spend is called and the slice has no reversal entry

  @security
  Scenario: Sandbox chains receive no stipend unless the project allows it
    Given a sandbox chain with a due slice and "SANDBOX_STIPENDS" is false
    When the runner runs
    Then the slice is "skipped" with reason "sandbox"

  @security
  Scenario: Accounts with repeated revoked terms are held
    Given "STIPEND_HOLD_AFTER_REVOKES" is 2 and the account has 2 revoked terms
    When a new slice falls due
    Then the slice is "skipped" with reason "held" and a person reviews the account

  @security
  Scenario: A slice is never granted for a term that was never verified
    Given a slice row whose term has no purchase record in "verified" state
    When the runner runs
    Then no grant is made for that slice
