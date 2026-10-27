Feature: Subscription states and the entitlement contract
  As a game server
  I want the state of a subscription computed from verified store snapshots
  So that every block can ask one question and get a correct, time-aware answer

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/plans-catalog.json exists
    And "ACCEPTED_ENVIRONMENTS" is "production+sandbox" and "ENTITLEMENT_LAG_ALLOWANCE_SECONDS" is 3600
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario Outline: A verified snapshot maps to a state, an entitlement flag and a renewal flag
    Given the snapshot "<row>" from fixtures/state-matrix.json rows
    When the snapshot is normalized
    Then the state is "<state>"
    And "active" is <active>
    And "will_renew" is <will_renew>

    Examples:
      | row                              | state    | active | will_renew |
      | apple-active                     | active   | true   | true       |
      | apple-free-trial                 | trial    | true   | true       |
      | apple-intro-pay-as-you-go        | active   | true   | true       |
      | apple-canceled-but-active        | canceled | true   | false      |
      | apple-canceled-during-trial      | canceled | true   | false      |
      | apple-billing-grace-period       | grace    | true   | true       |
      | apple-billing-retry              | retry    | false  | true       |
      | apple-expired-voluntary          | expired  | false  | false      |
      | apple-revoked-refund             | revoked  | false  | false      |
      | google-active                    | active   | true   | true       |
      | google-free-trial                | trial    | true   | true       |
      | google-canceled-but-active       | canceled | true   | false      |
      | google-grace-period              | grace    | true   | true       |
      | google-account-hold              | retry    | false  | true       |
      | google-paused                    | paused   | false  | true       |
      | google-pending-purchase          | pending  | false  | false      |
      | google-revoked-by-notification   | revoked  | false  | false      |

  @happy
  Scenario: Grace keeps access, retry removes it, recovery restores it
    Given account "acct-002" with the messages of sequence "apple_billing_failure_then_recovery" in fixtures/store-events.json delivered in order
    Then at each checkpoint of the sequence the entitlement for "vip" matches the checkpoint
    And at "2026-10-21T00:00:00Z" the entitlement is active in state "grace" ending "2026-10-23T12:00:00Z"
    And at "2026-10-24T00:00:00Z" the entitlement is not active in state "retry"
    And at "2026-10-27T12:00:00Z" the entitlement is active in state "active" ending "2026-11-26T08:00:00Z"

  @happy
  Scenario: Canceling keeps access until the paid period ends
    Given account "acct-001" with the messages of sequence "apple_trial_converts_then_cancels" delivered in order
    Then the states after each message are "trial", "active", "canceled"
    And the entitlement for "vip" is active with will_renew false and expires_at "2026-11-27T12:00:00Z"

  @happy
  Scenario: A refund removes access and its reversal restores it with the same expiry
    Given account "acct-001" with the messages through "apple_did_renew_trial_converts" applied
    When the purchase record of the term becomes "refunded" and on_purchase_state_changed fires with the refund snapshot "apple_refund"
    Then the entitlement for "vip" is not active and the state is "revoked"
    When the record returns to "verified" and the hook fires with the snapshot "apple_refund_reversed"
    Then the entitlement for "vip" is active in state "active" with expires_at "2026-11-27T12:00:00Z"

  @edge
  Scenario: Past expiry the read refreshes from the store before answering
    Given the read-time rule "stored-entitled-past-expiry-store-says-renewed" in fixtures/state-matrix.json
    When "entitlement" is called for account "acct-001" and product "vip"
    Then the chain is refreshed once
    And the answer is active with expires_at "2026-11-27T11:59:00Z"

  @edge
  Scenario Outline: When the store cannot be reached access lasts only for the lag allowance
    Given the read-time rule "<rule>" in fixtures/state-matrix.json
    When "entitlement" is called
    Then "active" is <active>

    Examples:
      | rule                                                         | active |
      | stored-entitled-past-expiry-store-unreachable-inside-allowance  | true   |
      | stored-entitled-past-expiry-store-unreachable-outside-allowance | false  |

  @edge
  Scenario: A canceled chain whose refresh says expired ends access at once
    Given the read-time rule "stored-canceled-past-expiry-store-says-expired"
    When "entitlement" is called
    Then the answer is not active in state "expired"

  @edge
  Scenario: A pause that is only scheduled does not remove access
    Given the snapshot "google-pause-scheduled-still-active"
    When the snapshot is normalized
    Then the state is "active" and "active" is true
    When the snapshot "google-paused" is applied afterwards
    Then the state is "paused" and "active" is false
    And "auto_resume_at" is "2026-11-10T12:00:00Z"

  @edge
  Scenario: A canceled Google chain with an expiry already in the past is expired
    Given the snapshot "google-canceled-expiry-in-the-past"
    When the snapshot is normalized
    Then the state is "expired" and "active" is false

  @edge
  Scenario: Organization-assigned Apple access is not granted by this block
    Given the snapshot "apple-assigned-by-organization"
    When the snapshot is normalized
    Then no chain is created and the message is recorded as ignored

  @edge
  Scenario: Terminal states do not leave on stale data
    Given a chain in state "expired" with snapshot_at "2026-10-27T11:00:00Z"
    When a snapshot observed at "2026-10-27T10:00:00Z" says "active"
    Then the outcome is "stale" and the chain stays "expired"
    When a snapshot observed at "2026-10-27T11:30:00Z" says "active" with a transaction the chain has not seen
    Then the chain becomes "active"

  @edge
  Scenario Outline: Composition picks the right chain for the asked product
    Given the composition case "<case>" in fixtures/state-matrix.json
    When "entitlement" is asked for each product of the case
    Then each answer equals the expected object of the case

    Examples:
      | case                                              |
      | two-stores-higher-level-wins-for-lower-product    |
      | lower-level-does-not-satisfy-higher-product       |
      | retry-outranks-expired-when-nothing-is-entitled   |
      | grace-keeps-access                                |
      | revoked-outranks-expired                          |
      | no-chain-at-all                                   |

  @security
  Scenario: The contract returns four fields and never a store reference
    Given account "acct-001" holds an active chain
    When "entitlement" is called and GET /api/subscriptions/status is requested
    Then the contract object has exactly the keys "active", "state", "expires_at", "will_renew"
    And no response contains the chain reference, a purchase token or an original transaction id

  @security
  Scenario: The client cannot assert an entitlement
    Given account "acct-003" has no chain
    When the client sends a body claiming "state": "active" to any subscription endpoint
    Then the entitlement for "vip" stays inactive in state "none"
