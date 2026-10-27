Feature: Link conflict, the credential already belongs to another account
  As a player whose Google or Apple account already has a game
  I want to be told what each choice keeps and what it removes
  So that nothing is lost or merged until I confirm exactly what I was shown

  Background:
    Given the app is configured for tenant "tenant-001"
    And the participants, holdings_sets and config of fixtures/link-conflict-cases.json apply
    And the guest "guest" and the existing linked account "existing" exist
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario Outline: Weight, default and digest come from the holdings
    Given the holdings set "<set>"
    When the guest links a credential that belongs to "existing"
    Then the response status is 409 with error "link_conflict" and reason "credential_owned"
    And guest_weight is "<weight>" and default_choice is "<default>"
    And preview_digest equals the digest of the case in fixtures/link-conflict-cases.json weight_cases
    And link_conflict is emitted without the id of the existing account

    Examples:
      | set                     | weight   | default       |
      | played                  | played   | keep_existing |
      | played_currency_carried | played   | keep_existing |
      | paid                    | paid     | none          |

  @happy
  Scenario: A pristine guest signs in without a sheet
    Given the holdings set "empty"
    When the guest links a credential that belongs to "existing"
    Then no conflict sheet is shown
    And the client is signed in to "existing" and sees "Signed in. The new guest game on this phone was empty, so nothing was lost."
    And the guest is abandoned and no participant mergeAccounts was called

  @happy
  Scenario: Keep the existing account and import the guest's progress
    Given the holdings set "played" and the conflict sheet is shown with "Use my saved game" suggested
    When the player confirms with import on and the digest of the shown list
    Then each participant that lists a holding is called with mergeAccounts(guest, existing, "link:<link_attempt_id>")
    And the guest is "abandoned" with merged_into_account_id set, its credentials retired "abandoned" and its sessions revoked
    And the attempt is "kept_existing"
    And the response carries a login-block session for "existing"
    And the coins listed with effect "left_behind" are not in the existing account
    And link_conflict_resolved is emitted with choice "keep_existing" and imported true

  @happy
  Scenario: Keep the existing account without importing
    Given the holdings set "played"
    And fixtures/link-conflict-cases.json progress_sync_cases "declined import saves the device data aside and resets it"
    When the player confirms keep_existing with import off
    Then no participant is called and the guest is abandoned with merged_into_account_id null
    And the client saved the device data aside with the previous-data backup of data.progress-sync and reset the local record before signing in
    And no owner-less device data is merged into the existing account

  @happy
  Scenario: A guest with local progress signs in to an existing account, the device data merges and nothing is replaced
    Given fixtures/link-conflict-cases.json progress_sync_cases "guest data merges into the existing account, nothing is replaced"
    And the device holds 2 history entries and no owner marker because a guest never syncs a snapshot
    And the existing account's snapshot holds 1 other entry at revision 4
    When the player confirms keep_existing with import on
    Then the device data is merged into the existing account's snapshot by the merge rules of data.progress-sync
    And the device holds 3 history entries and the snapshot is written with base_revision 4
    And the owner marker is the existing account_id after the first sync
    And the previous-data backup slot is still empty
    And the device data was not replaced

  @edge
  Scenario: A guest never wrote a snapshot before the conflict
    Given fixtures/link-conflict-cases.json progress_sync_cases "a guest never writes a snapshot"
    When the guest plays and the app is online
    Then no snapshot request is sent and the owner marker stays absent

  @happy
  Scenario: Keep the guest account and refuse the link
    Given the holdings set "played"
    When the player chooses "Keep my guest game"
    Then the response status is 200 and the account is still a guest and active
    And the attempt is "kept_guest" and nothing was destroyed
    And link_conflict_resolved is emitted with choice "keep_guest"

  @security
  Scenario: A paid guest has no default and must acknowledge each paid holding
    Given the holdings set "paid"
    Then the sheet shows no preselected choice and no "Suggested" label
    When the player confirms keep_existing and acknowledges only "currency:gems"
    Then the response status is 400 "invalid_request" and nothing changes
    When the player acknowledges "currency:gems" and "purchases:subscription_pro" and confirms
    Then the response status is 200
    And the confirm button text names the loss and is never "OK"

  @security
  Scenario: A confirmation applies to exactly what was shown
    Given the sheet showed the holdings set "played"
    And the guest's currency is then carried by billing so the holdings equal "played_currency_carried"
    When the player confirms with the old digest
    Then the response status is 409 "preview_changed" with the new digest
    And no participant was called and the guest is unchanged
    And the sheet shows "Your guest progress changed. Please review again."

  @edge
  Scenario: The digest does not depend on the order of the list
    Given fixtures/link-conflict-cases.json digest_order_independence
    Then the digest of the reordered list equals the digest of the original

  @edge
  Scenario: An interrupted import resumes without double-applying
    Given fixtures/link-conflict-cases.json conflict case "import interrupted after the first participant"
    When the first resolve request fails after engagement.daily-streak
    Then the response status is 503 "import_incomplete" and the attempt is "importing" and the guest is still active
    When the player retries the same request
    Then each participant has applied the merge once and the guest becomes abandoned

  @security
  Scenario: A guest is merged into at most one account
    Given the guest was already merged into "existing"
    When a second merge of the same guest into another account is requested
    Then the participant answers "already_merged"

  @security
  Scenario: Imports into one account are bounded per day
    Given 3 imports into "existing" were accepted today
    When a fourth guest asks to import into "existing"
    Then the response status is 429 "rate_limited" and nothing changes
    And keeping the guest is still allowed

  @edge
  Scenario: The email already belongs to an account with another provider
    Given fixtures/link-conflict-cases.json conflict case "email owned by another provider"
    When the guest links Google with an email that an Apple account already holds
    Then the response status is 409 "link_conflict" with reason "email_owned_by_other_provider" and no items
    And the sheet offers "Sign in with Apple" and "Stay as guest" and no import
    When the player signs in with Apple
    Then a new attempt becomes a "credential_owned" conflict

  @edge
  Scenario: The conflict expires
    Given the conflict was recorded at "2026-10-27T11:45:00Z" and LINK_CONFLICT_TTL_SECONDS is 600
    When the player confirms
    Then the response status is 401 and nothing changes
    And the sheet shows "That took too long. Start again."

  @security
  Scenario: A paid subscription is called out and nothing is transferred silently
    Given the holdings set "paid" includes "purchases:subscription_pro" with effect "left_behind"
    Then the confirm step says the subscription is billed by the store and stays with the guest account
    And it names the store's subscription settings
    And no entitlement or balance is moved by this block

  @security
  Scenario: A block that did not register is a release failure, not a silent loss
    Given a block that keys rows by account_id has neither registered holdings nor declared no_holdings
    When the release gate of acceptance.md runs
    Then the gate fails and names the block

  @security
  Scenario: The conflict body reveals nothing about the other account
    When the conflict response is built
    Then it carries no id, email, name or creation time of the existing account
