Feature: Store message intake, idempotency and ordering
  As a game server
  I want App Store and Google Play messages processed exactly once in effect
  So that late, duplicated and reordered deliveries never corrupt a subscription

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/plans-catalog.json exists
    And the shared receivers of billing.virtual-currency verify and dedupe messages and route the subscription family (family "subscription" for apple and google) to this block's handler
    And the messages of fixtures/store-events.json are available by name
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: An Apple notification applies the snapshot carried in the payload
    Given account "acct-001" has token "6f1f0a3e-8c52-4d0a-9d55-0a4f5f6e1a01"
    When "apple_subscribed_free_trial" is delivered
    Then a chain exists bound to "acct-001" in state "trial" with expires_at "2026-10-27T12:00:00Z"
    And one term exists for transaction "2000000000000001" with phase "trial"
    And one purchase record is written through record_verified_purchase with product kind "subscription_term"
    And the event row for "b0000000-0000-4000-8000-000000000001" has outcome "applied"
    And no call is made to the Apple API

  @happy
  Scenario: A Google message triggers a fetch because it carries only a token and a type
    Given account "acct-001" has token "6f1f0a3e-8c52-4d0a-9d55-0a4f5f6e1a01"
    And the fetch "fetch_trial_active" is what subscriptionsv2.get returns
    When "google_purchased" is delivered
    Then subscriptionsv2.get is called once for "example-purchase-token-001"
    And the chain is bound to "acct-001" in state "trial" with expires_at "2026-11-03T10:00:00Z"
    And the purchase is acknowledged after the chain and term are committed

  @edge
  Scenario: A duplicate delivery changes nothing and still succeeds
    Given sequence "apple_duplicate_delivery" of fixtures/store-events.json
    When the messages arrive in the listed order
    Then the outcomes are "applied" then "duplicate"
    And the chain state changed once and one event row exists
    And the handler returned success both times

  @edge
  Scenario: An out-of-order Apple message cannot flip the renewal flag back
    Given sequence "apple_out_of_order_renewal_flag" of fixtures/store-events.json
    When the messages arrive in the listed order
    Then the outcomes are "applied" then "stale"
    And the entitlement for "vip" is active with will_renew true and expires_at "2026-11-27T12:00:00Z"

  @edge
  Scenario: Google arrival order does not matter because every message fetches current state
    Given sequence "google_trial_cancel_restart_out_of_order" of fixtures/store-events.json
    When the messages arrive in the listed order with the scripted fetch results
    Then the outcomes are "applied" then "applied_no_change"
    And the entitlement for "vip" is active in state "trial" with will_renew true

  @edge
  Scenario: Of two concurrent Google fetches the one that started later wins
    Given sequence "google_concurrent_refresh_older_result_loses" of fixtures/store-events.json
    When the later fetch completes first and the earlier fetch completes second
    Then the outcomes are "stale" for the earlier fetch and "applied" for the later one
    And the entitlement for "vip" is active with will_renew true

  @edge
  Scenario: A Google revocation cannot be cleared by an expired fetch
    Given sequence "google_revoked_cannot_be_undone_by_expired_fetch" of fixtures/store-events.json
    When "google_revoked" and then "google_expired" are delivered
    Then the chain state is "revoked" after both messages
    And the entitlement for "vip" is not active

  @edge
  Scenario: A message for an unknown chain with no account token is stored unlinked
    Given sequence "google_unlinked_then_claimed" of fixtures/store-events.json
    When "google_purchased_without_account_ids" is delivered
    Then a chain exists with no account in state "active"
    And the event outcome is "unlinked" and the handler succeeded
    And no stipend is granted while the chain has no account

  @edge
  Scenario: A handler failure makes the receiver answer non-2xx and the redelivery completes the work
    Given subscriptionsv2.get fails with a transient error on the first attempt
    When "google_recovered" for "example-purchase-token-001" is delivered
    Then the handler fails and the receiver answers with a non-2xx status
    And the event row is not in a terminal outcome
    When the store redelivers the same message and the fetch succeeds
    Then the event row ends with outcome "applied" and "attempts" is 2

  @edge
  Scenario Outline: Types the block does not act on are acknowledged and recorded as ignored
    Given an Apple notification of type "<type>" for the configured bundle
    When it is delivered
    Then the event outcome is "ignored" and the handler succeeded
    And no chain changes

    Examples:
      | type                    |
      | RENEWAL_EXTENSION       |
      | RESCIND_CONSENT         |
      | EXTERNAL_PURCHASE_TOKEN |
      | METADATA_UPDATE         |
      | MIGRATION               |
      | PRICE_CHANGE            |

  @edge
  Scenario: An unlisted Google notification type is treated as a refresh
    Given a Google subscription notification with type 21 for a known chain
    When it is delivered
    Then subscriptionsv2.get is called and the chain is refreshed
    And the event outcome is "applied" or "applied_no_change"

  @edge
  Scenario: After an outage the Apple notification history is replayed through the same handler
    Given the server was down for two days and "CATCHUP_LOOKBACK_DAYS" is 7
    When the catch-up job reads Get Notification History from "2026-10-20T12:00:00Z" to the clock in pages of 20
    Then each record is processed by the handler
    And records older than the stored snapshot are "stale"
    And the final chain state equals the state of the newest record

  @edge
  Scenario: An Apple refund reaches the block through the purchase record, not the handler
    Given "REFUND" for a subscription term is handled by the receivers of billing.virtual-currency and never routed to this handler
    When the purchase record becomes "refunded" and on_purchase_state_changed fires for the term
    Then the chain is refreshed and, because the term is the newest, the state becomes "revoked"
    And the term's pending stipend slices are skipped with reason "revoked"

  @edge
  Scenario: A lost renewal message is found by the read-through refresh
    Given a chain "active" with expires_at "2026-10-27T11:59:00Z" and no renewal message received
    When "entitlement" is called
    Then the chain is refreshed from the store and the new term is created
    And the stipend slices of the new term are scheduled

  @edge
  Scenario: A Google purchase still unacknowledged is retried and alerted
    Given a Google chain entitled and unacknowledged since "2026-10-27T00:00:00Z" and "GOOGLE_ACK_ALERT_AFTER_HOURS" is 12
    When the reconcile job runs
    Then the acknowledge call is retried
    And an alert is raised because 12 hours have passed

  @edge
  Scenario: A Google purchase in the pending state is not acknowledged
    Given the fetch "fetch_pending" is what subscriptionsv2.get returns
    When a Google message for the token is delivered
    Then the chain state is "pending" and no entitlement is granted
    And no acknowledge call is made

  @security
  Scenario: A message for another app is ignored
    Given an Apple notification whose bundleId differs from "APPLE_BUNDLE_ID"
    When it is delivered
    Then the event outcome is "ignored", an alert is raised, and no chain is created

  @security
  Scenario: Sandbox messages are rejected when only production is accepted
    Given "ACCEPTED_ENVIRONMENTS" is "production"
    When an Apple notification with environment "Sandbox" is delivered
    Then the event outcome is "ignored" and no chain is created

  @security
  Scenario: Sandbox chains are stored flagged and receive no stipend
    Given "ACCEPTED_ENVIRONMENTS" is "production+sandbox" and "SANDBOX_STIPENDS" is false
    When a sandbox subscription is delivered and its first slice falls due
    Then the chain has environment "sandbox"
    And the slice is skipped with reason "sandbox"

  @security
  Scenario: A forged Google message grants nothing because state is fetched with server credentials
    Given a Pub/Sub message for a token that does not exist at Google
    When it is delivered through a receiver that accepted its transport token
    Then subscriptionsv2.get answers not found and no chain is created
