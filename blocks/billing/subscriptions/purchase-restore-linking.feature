Feature: Purchase claim, restore, and linking a store subscription to an app account
  As a player
  I want my subscription attached to the right game account and to survive a new phone
  So that I never pay twice and nobody else can take it

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog and accounts from fixtures/plans-catalog.json exist
    And account "acct-001" is signed in
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: An intent returns the account token and the store ids, never a price
    When I send POST /api/subscriptions/intents with plan_code "vip-monthly-apple"
    Then the response status is 200
    And "store_account_token" is "6f1f0a3e-8c52-4d0a-9d55-0a4f5f6e1a01"
    And "store_product_id" is "example.vip.monthly" and "store_base_plan_id" is null
    And the response has no price field

  @happy
  Scenario: A claim after an Apple purchase binds the chain and returns the entitlement
    Given the store reports a verified transaction "2000000000000001" for "example.vip.monthly" carrying the token of "acct-001"
    When I send POST /api/subscriptions/claims with platform "apple" and that signed transaction
    Then the response status is 200 and "linked" is true
    And the entitlement for "vip" is active
    And one term and one purchase record exist for transaction "2000000000000001"
    And slice rows for the term are scheduled

  @happy
  Scenario: A claim after a Google purchase acknowledges it once the grant is stored
    Given the store reports an unacknowledged purchase for token "example-purchase-token-001" carrying the token of "acct-001"
    When I send POST /api/subscriptions/claims with platform "google" and that purchase token
    Then the entitlement for "vip" is active
    And the purchase is acknowledged exactly once after the commit

  @happy
  Scenario: Restore on a new phone finds the subscription already on this account
    Given "acct-001" already holds the chain from the claim above
    When I send POST /api/subscriptions/restores with the proof the store holds
    Then the result outcome is "already_linked"
    And the entitlement is unchanged and nothing is written twice

  @edge
  Scenario: Claiming the same proof twice creates one term and one purchase record
    When I send the same POST /api/subscriptions/claims twice
    Then both responses are 200
    And exactly one term, one purchase record and one set of slice rows exist

  @edge
  Scenario: A store account used by two game accounts never moves silently
    Given the chain of "acct-001" is bound since "2026-10-20T12:00:00Z"
    And I am now signed in as "acct-002"
    When I send POST /api/subscriptions/restores with the proof of that chain
    Then the result outcome is "linked_to_other_account"
    And the response names no detail of "acct-001"
    And "acct-001" still has the entitlement

  @edge
  Scenario: A confirmed transfer moves the chain, ends the other account's access and tells it
    Given "acct-002" received "linked_to_other_account" for the chain of "acct-001"
    And "TRANSFER_COOLDOWN_DAYS" is 30 and the chain was bound at "2026-09-01T12:00:00Z"
    When "acct-002" sends POST /api/subscriptions/claims with confirm_transfer true
    Then the chain is bound to "acct-002" and "bound_at" is "2026-10-27T12:00:00Z"
    And the entitlement for "vip" is active for "acct-002" and not active for "acct-001"
    And "acct-001" is notified and "subscription_transfer_completed" is recorded

  @edge
  Scenario: A transfer inside the cooldown is refused
    Given the chain was bound to "acct-001" at "2026-10-20T12:00:00Z" and "TRANSFER_COOLDOWN_DAYS" is 30
    When "acct-002" sends POST /api/subscriptions/claims with confirm_transfer true
    Then the response status is 429 with error "transfer_cooldown"
    And the chain stays bound to "acct-001"

  @edge
  Scenario: A chain whose message arrived first is unlinked until the right account claims it
    Given sequence "google_unlinked_then_claimed" of fixtures/store-events.json delivered the purchase without account ids
    When "acct-002" claims the token "example-purchase-token-002"
    Then the chain is bound to "acct-002" and the entitlement is active
    And slices that fell due while unlinked are granted to "acct-002"
    When "acct-003" then claims the same token without transfer
    Then the response is 409 with error "linked_to_other_account"

  @edge
  Scenario: A later renewal message never rebinds a bound chain from its token
    Given the chain is bound to "acct-002" after a transfer and the store still echoes the token of "acct-001"
    When a renewal message for the chain is delivered
    Then the chain stays bound to "acct-002"

  @edge
  Scenario: Merging a guest into a signed-in account moves its chains without a transfer
    Given guest account "acct-003" holds a chain and "acct-001" is the account it merges into
    When account_merged is called with from "acct-003" and to "acct-001"
    Then the chain is bound to "acct-001" and the cooldown is not started
    And the token row of "acct-003" is deleted

  @edge
  Scenario: Deleting an account detaches its chain and keeps receiving store messages
    Given "acct-001" holds an active chain
    When account_deleted is called for "acct-001"
    Then the chain has no account and the token row is deleted
    And a later renewal message still updates the chain
    And no stipend is granted while the chain has no account

  @edge
  Scenario: An intent for a plan in a group where the account is already entitled is refused
    Given "acct-001" holds an entitled chain on "google" in group "vip-group"
    When I send POST /api/subscriptions/intents with plan_code "vip-monthly-apple"
    Then the response status is 409 with error "already_entitled"

  @edge
  Scenario: A claim for a store product that matches no plan is refused
    Given the store reports a verified transaction for product "example.unknown.monthly"
    When I send POST /api/subscriptions/claims with platform "apple"
    Then the response status is 422 with error "product_unknown" and nothing is stored

  @edge
  Scenario: A family member binds shared access through restore and loses it when sharing stops
    Given the store reports a family-shared transaction for "example.vipplus.monthly"
    When "acct-002" restores it
    Then the chain has ownership "family_shared" and the entitlement for "vip-plus" is active
    When a REVOKE notification arrives for the chain
    Then the state is "revoked" and the entitlement is not active

  @edge
  Scenario: Restore includes suspended Google subscriptions
    Given a Google chain in account hold for the store account
    When the client collects proofs with suspended subscriptions included and restores
    Then the chain is bound and the state is "retry"

  @edge
  Scenario: Restore with nothing found says so
    Given the store holds no subscription for the store account
    When I send POST /api/subscriptions/restores with an empty proof list
    Then the response lists no result and the client shows the "none found" message

  @security
  Scenario: The account always comes from the session
    When I send POST /api/subscriptions/claims with a body field "account_id" of "acct-002"
    Then the field is ignored and the chain binds to "acct-001"

  @security
  Scenario: Claims and restores are rate limited
    Given "CLAIM_RATE_LIMIT_PER_HOUR" is 10 and "acct-001" has made 10 claims in the last hour
    When I send another POST /api/subscriptions/claims
    Then the response status is 429 with error "rate_limited"

  @security
  Scenario: A chain whose token belongs to another account cannot be claimed without the transfer path
    Given a chain unbound in our table whose transaction carries the token of "acct-002"
    When "acct-001" claims it without confirm_transfer
    Then the response is 409 with error "linked_to_other_account"

  @security
  Scenario: Proofs and chain references never appear in logs or responses
    When any claim or restore completes or fails
    Then no log line, response body or analytics event contains the purchase token, the signed transaction or the original transaction id

  @security
  Scenario: A claim with an unverifiable proof stores nothing
    Given the store does not confirm the proof
    When I send POST /api/subscriptions/claims
    Then the response status is 422 with error "proof_invalid" and no chain, term or purchase record is written
