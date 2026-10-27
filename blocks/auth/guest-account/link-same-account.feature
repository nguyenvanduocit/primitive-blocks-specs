Feature: Link a guest to Google or Apple on the same account
  As a player who wants my progress saved
  I want to attach my Google or Apple account to the game I already have
  So that nothing is copied, moved or lost

  Background:
    Given the app is configured for tenant "tenant-001"
    And the same_account_link_cases and config of fixtures/link-conflict-cases.json apply
    And the guest "guest" has a valid guest session and holds the device secret
    And the login blocks' verifiers are replaced by test doubles that return verified claims
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: Linking keeps the account_id and re-keys nothing
    Given the Google identity is not on any users row
    When the player starts a link with provider "google" and completes the provider flow with the attempt nonce
    Then the response status is 200 with the same account_id, kind "linked" and linked_at "2026-10-27T12:00:00Z"
    And a users row exists with id equal to the account_id and the verified google_id
    And accounts.kind is "linked" and accounts.status is "active"
    And the device credential and the recovery credential are retired with reason "linked"
    And the guest sessions are revoked and a login-block session is returned
    And no row in any other block changed its account_id
    And no participant mergeAccounts was called
    And account_linked is emitted with provider "google"

  @happy
  Scenario: The client deletes its stored secret after the link
    When the link succeeds
    Then the device secret is removed from secure storage
    And the settings row shows the linked state and the provider
    And the game itself looks unchanged

  @happy
  Scenario: A guest with local progress keeps it when linking and the snapshot starts after the link
    Given fixtures/link-conflict-cases.json progress_sync_cases "same-account link keeps the device data and starts the snapshot"
    And the device holds 2 history entries and no owner marker because a guest never syncs a snapshot
    When the guest links Google on the same account
    Then data.progress-sync starts now that the account is signed in
    And its first sync receives 404 "no_snapshot" and writes the 2 entries with base_revision 0
    And the owner marker becomes the unchanged account_id
    And the device data is not replaced and the previous-data backup slot stays empty

  @happy
  Scenario: Purchases and entitlements follow the account_id with no code
    Given the guest bought a pack and a subscription as a guest
    When the guest links Google on the same account
    Then the ledger entries and the entitlement are still keyed by the same account_id
    And a later store notification maps to the same account through the transaction's app account token or obfuscated account id

  @edge
  Scenario: A lost response is recovered by a provider sign-in
    Given fixtures/link-conflict-cases.json same_account_link_cases "lost response"
    When the client exchanges the old secret
    Then the response status is 403 with error "account_linked"
    And the client shows "Your game is saved. Sign in with the account you saved it to."
    When the player signs in with the same provider
    Then the session belongs to the same account_id

  @security
  Scenario: Two attempts for one provider identity cannot both link
    Given two guests race with the same Google identity
    Then exactly one link succeeds and the kind of that account changes once
    And the other receives 409 "link_conflict" with reason "credential_owned"

  @security
  Scenario: The proof must carry this attempt's nonce
    Given fixtures/link-conflict-cases.json same_account_link_cases "proof carries the nonce of another attempt"
    When the proof of another attempt is presented
    Then the response status is 401 and nothing changes
    And the link attempt is still usable until it expires

  @security
  Scenario: Starting a link needs the device secret, not only the session
    When link start is called with a valid guest session and no device secret
    Then the response status is 401 with error "credential_invalid"
    And no link_attempts row is created

  @edge
  Scenario: A link attempt expires
    Given the attempt was created at "2026-10-27T11:50:00Z" and LINK_NONCE_TTL_SECONDS is 300
    When the proof is presented
    Then the response status is 401 and the attempt is marked "expired"
    And the client shows "That took too long. Try again."

  @edge
  Scenario: Only an active guest can link
    Given the account is already linked
    When link start is called
    Then the response status is 409 with error "not_a_guest"

  @edge
  Scenario: Link starts are rate limited per account
    Given 10 link starts by one account in an hour
    When an 11th arrives
    Then the response status is 429 "rate_limited"

  @edge
  Scenario: Apple is offered with equal prominence where Google is offered on iOS
    Given the app runs on iOS and offers Google sign-in
    When the link screen is shown
    Then an Apple button is shown with the same size and weight

  @edge
  Scenario: Apple relay email and a name delivered once are handled by the Apple block
    Given the Apple identity token carries a private relay email and the name arrives only with the first authorization
    When the guest links Apple
    Then the users row is created by the rules of auth.sign-in-with-apple and the account_id is unchanged

  @happy
  Scenario: The save-your-progress prompt follows its timing rules
    Given the player has not won yet
    Then the prompt is not due
    When the player wins the first level and the game is at a result screen
    Then the prompt is due once
    When the player taps "Not now"
    Then the prompt is not due again for LINK_PROMPT_COOLDOWN_DAYS
    And after LINK_PROMPT_MAX_DISMISSALS dismissals only the Settings entry offers linking
