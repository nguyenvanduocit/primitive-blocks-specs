Feature: Trials, offers, plan changes, price increases and family sharing
  As a player
  I want the offers and plan changes the store allows to work with my entitlement
  So that access follows what I actually bought and consented to

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/plans-catalog.json exists
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: The trial hint is true for an account that never had a trial or introductory term in the group
    Given account "acct-003" has no chain
    When I send POST /api/subscriptions/intents with plan_code "vip-monthly-apple"
    Then "trial_eligible_hint" is true

  @edge
  Scenario: The trial hint is false after a trial in the same group, and the store still decides
    Given account "acct-001" has a chain in "vip-group" whose first term has phase "trial"
    When I send POST /api/subscriptions/intents with plan_code "vip-yearly-apple"
    Then "trial_eligible_hint" is false
    And the server never creates a trial itself: a trial exists only as a store transaction

  @happy
  Scenario: A free trial converts to a paid term and stipend slices start with the paid term
    Given sequence "apple_trial_converts_then_cancels" of fixtures/store-events.json
    When "apple_subscribed_free_trial" and "apple_did_renew_trial_converts" are delivered
    Then the first term has phase "trial" and its slices are skipped with reason "trial"
    And the second term has phase "regular" and its first slice is pending with due_at "2026-10-27T12:00:00Z"

  @happy
  Scenario Outline: A renewing free trial arms one hand-off reminder and resolves it when it stops applying
    Given the trial reminder case "<case>" in fixtures/state-matrix.json under "trial_reminders"
    And "TRIAL_REMINDER_LEAD_SECONDS" is 172800 and "TRIAL_REMINDER_MIN_NOTICE_SECONDS" is 21600
    When the reminder plan is evaluated at the case clock
    Then the hand-off events emitted equal the case's "expected_events"
    And every event has "subject_key", "state", and for "armed" also "fire_at", "expires_at" and "params"
    And "expires_at" of an armed event is the trial's end

    Examples:
      | case                                         | outcome                                              |
      | seven-day-trial-starts                       | armed, fire_at two days before the trial ends        |
      | three-day-trial-lead-capped-at-half-length   | armed, lead capped at half the trial length          |
      | already-armed-nothing-to-do                  | no event                                             |
      | player-cancels-during-trial                  | resolved                                             |
      | player-turns-renewal-back-on                 | armed under a new subject_key                        |
      | trial-converts-to-paid                       | resolved                                             |
      | trial-extended-by-the-store                  | resolved, then armed under a new subject_key         |
      | too-late-to-be-useful                        | no event                                             |
      | late-arming-fire-at-is-now                   | armed with fire_at at the clock                      |
      | paid-introductory-price-is-not-a-trial       | no event                                             |
      | family-shared-trial-pays-nothing             | no event                                             |
      | sandbox-trial                                | no event                                             |
      | price-unknown-omits-price-params             | armed without price params                           |

  @happy
  Scenario: Upgrade is immediate, downgrade waits for renewal, and a revert clears it
    Given sequence "apple_upgrade_downgrade_revert" of fixtures/store-events.json
    When the messages are delivered in order
    Then after each message the detail equals the matching "expected_detail" entry
    And after the downgrade message "vip-plus" is still active until "2026-11-15T09:00:00Z"

  @edge
  Scenario: A Google plan change creates a new linked chain and keeps access continuous
    Given account "acct-001" holds an active Google chain on "vip-monthly-google"
    When the store reports a new purchase token on "vip-plus-monthly-google" whose linkedPurchaseToken is the old token
    Then a second chain exists with "linked_chain_id" set to the first chain
    And the entitlement for "vip" and for "vip-plus" is active at every step
    When the old chain later reports "expired"
    Then its end_reason is "replaced" and the entitlement is unchanged

  @edge
  Scenario: Google refuses a plan change while the existing purchase is unacknowledged, so the claim acknowledges first
    Given an unacknowledged Google chain and a plan-change claim for the same account
    When the claim is processed
    Then the old chain is acknowledged before the new chain is acknowledged

  @happy
  Scenario: An Apple price increase that needs consent is recorded and does not change access
    Given sequence "apple_price_increase_consent" of fixtures/store-events.json
    When "apple_price_increase_pending" is delivered
    Then "price_change_state" is "pending_consent" and the state stays "active"
    When "apple_price_increase_accepted" is delivered
    Then "price_change_state" is "accepted"

  @edge
  Scenario: A price increase the player does not accept ends the subscription at the cycle end
    Given sequence "apple_price_increase_not_accepted" of fixtures/store-events.json
    When "apple_expired_price_increase_declined" is delivered
    Then the state is "expired" with end_reason "price_increase_not_accepted" and the entitlement is not active

  @edge
  Scenario: A Google opt-in price change is surfaced from the fetched state
    Given sequence "google_price_change_outstanding" of fixtures/store-events.json
    When "google_price_change_updated" is delivered with the scripted fetch
    Then "price_change_state" is "pending_consent" and the state stays "active"

  @happy
  Scenario: A win-back offer is returned to a lapsed player when the feature is on
    Given "WINBACK_ENABLED" is true and "WINBACK_MIN_LAPSE_DAYS" is 14
    And account "acct-001" has an "expired" chain that ended "2026-10-01T12:00:00Z" and the store lists an eligible offer
    When I send GET /api/subscriptions/offers
    Then an offer reference is returned

  @edge
  Scenario Outline: No win-back offer is returned outside its rules
    Given "WINBACK_ENABLED" is <enabled> and "WINBACK_MIN_LAPSE_DAYS" is 14
    And account "acct-001" has a chain in state "<state>" that ended "<ended>"
    When I send GET /api/subscriptions/offers
    Then the response is an empty object

    Examples:
      | enabled | state   | ended                | reason                  |
      | false   | expired | 2026-10-01T12:00:00Z | feature off             |
      | true    | expired | 2026-10-20T12:00:00Z | lapsed only 7 days      |
      | true    | revoked | 2026-10-01T12:00:00Z | refunded, not a lapse   |
      | true    | active  | 2026-12-01T12:00:00Z | still entitled          |

  @edge
  Scenario: An offer-code redemption is recorded on the term
    Given Apple sends a SUBSCRIBED notification whose transaction has offerType 3 and an offerIdentifier
    When it is delivered
    Then the term has offer_kind "offer_code" and the offer id

  @edge
  Scenario: Family Sharing grants entitlement but no stipend by default
    Given the snapshot "apple-family-shared" and "STIPEND_FOR_FAMILY_SHARED" is false
    When the term is first seen
    Then the entitlement is active with ownership "family_shared"
    And the term's slices are skipped with reason "family_shared"

  @edge
  Scenario: A Google resubscribe after expiry is a new chain
    Given account "acct-001" has an "expired" Google chain
    When the store reports a new purchase token for the same plan
    Then a new chain exists in state "active" and the old chain stays "expired"
    And the new purchase is acknowledged

  @security
  Scenario: A promotional-offer signature is created only on the server for a qualifying account
    Given "WINBACK_ENABLED" is true and account "acct-003" does not qualify
    When the client asks for an offer signature
    Then no signature is returned
    And the client never receives the signing key or a signature it could reuse for another account
