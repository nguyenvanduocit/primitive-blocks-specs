Feature: Guest lifecycle, truthful return, reinstall and recovery
  As a returning player
  I want to be told the truth about my guest account and to get it back when I can
  So that I am never surprised by a silent loss and I know what protects my progress

  Background:
    Given the app is configured for tenant "tenant-001"
    And the accounts, credentials and tombstones of fixtures/accounts.json exist
    And the config of fixtures/lifecycle-cases.json applies
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario Outline: The sweep applies the idle rules
    Given the sweep case "<case>" of fixtures/lifecycle-cases.json sweep_cases
    When the lifecycle sweep runs
    Then the account ends as listed in "expected" with the listed events

    Examples:
      | case                                                |
      | recent launch                                       |
      | 89 days idle                                        |
      | exactly 90 days idle                                |
      | dormant, 364 days idle                              |
      | dormant, 365 days idle                              |
      | abandoned 29 days                                   |
      | abandoned 30 days                                   |
      | linked account idle 400 days                        |

  @edge
  Scenario: A guest with paid holdings is never purged for idleness
    Given the sweep case "dormant, 365 days idle, paid holding"
    When the lifecycle sweep runs
    Then the account stays dormant and guest_dormant had paid_hold true
    And no eraser is called

  @edge
  Scenario: A participant that cannot answer is treated as holding paid value
    Given the sweep case "dormant, 365 days idle, participant did not answer"
    When the lifecycle sweep runs
    Then the purge is skipped and the counter purge_skipped_unknown_holdings is incremented

  @edge
  Scenario: A launch during the purge cancels it
    Given the sweep case "launch while the purge transaction runs"
    When the lifecycle sweep runs
    Then last_active_at is re-read inside the purge transaction
    And the account stays and becomes active

  @happy
  Scenario: A dormant guest is reactivated and told how long it was idle
    Given fixtures/lifecycle-cases.json reactivation
    When the client exchanges "device-secret-example-0002"
    Then the response status is 200 with reactivated true and dormant_days 28
    And the account is "active" with dormant_at null
    And guest_reactivated is emitted with dormant_days 28
    And the welcome-back screen "reactivated" is shown with a Continue button as the primary action

  @happy
  Scenario Outline: Every exchange outcome shows its own truthful screen
    Given the exchange case "<case>" of fixtures/accounts.json exchange_cases
    When the client exchanges the secret
    Then the response matches the case
    And the welcome-back screen kind is "<screen>"
    And the unknown-credential screen claims no reason

    Examples:
      | case                                  | screen              |
      | secret retired by a link              | account_linked      |
      | secret retired by recovery            | credential_retired  |
      | secret of an abandoned guest          | account_abandoned   |
      | tombstone, inactive                   | purged              |
      | tombstone, deleted by the player      | purged              |
      | unknown secret, no reason claimed     | unknown_credential  |

  @edge
  Scenario: Tombstones expire and a swept tombstone claims nothing
    Given fixtures/lifecycle-cases.json tombstone_expiry
    When the sweep runs
    Then the tombstone expiring at "2026-10-27T11:00:00Z" is deleted
    And its secret now answers 401 "credential_invalid"
    And the tombstone expiring a day later still answers 410 "guest_purged"

  @happy
  Scenario: A purge goes through every block's eraser and leaves a tombstone without an account id
    Given the sweep case "dormant, 365 days idle"
    When the lifecycle sweep runs
    Then every registered block's deleteAccount is called for the account
    And the accounts row and its credentials, sessions and link attempts are deleted
    And a tombstone with reason "inactive" exists for each device credential hash and holds no account id
    And guest_purged is emitted without an account_id

  @happy
  Scenario: Recovery code restores the same account on a new device
    Given fixtures/accounts.json recovery_cases "valid code on a new device"
    When the player types the code in lower case with hyphens
    Then the response status is 200 with the same account_id
    And the old device credential is retired with reason "recovered" and the code with reason "used"
    And a new device credential and session are issued
    And the app prompts for a new recovery code
    And guest_recovered is emitted

  @edge
  Scenario Outline: Recovery inputs
    Given the recovery case "<case>" of fixtures/accounts.json recovery_cases
    When the code is submitted
    Then the response matches the case

    Examples:
      | case                                      |
      | look-alike letters are read as digits     |
      | code of an account that was linked        |
      | code already used                         |
      | wrong length is refused before any lookup |
      | unknown code                              |

  @security
  Scenario: Recovery attempts are rate limited
    Given 10 recovery attempts from one network bucket in an hour
    When an 11th arrives
    Then the response status is 429 "rate_limited"
    And the real code is not checked

  @edge
  Scenario: Device loss without a link or a code is stated plainly
    Given a guest with no recovery code and no linked provider
    When the player opens the save-your-progress prompt or the Settings account section
    Then the text says the game lives on this phone only and is lost with the phone
    And the Settings text states the idle period after which unused guest games are removed

  @edge
  Scenario: Reinstall works whether or not the platform kept the credential
    Given the app is reinstalled
    When secure storage still holds the credential
    Then the app exchanges it silently
    When secure storage holds no credential
    Then the app starts as a new player and creates a guest without assuming either outcome

  @edge
  Scenario: A credential restored on a second device leaves two devices on one account
    Given the same secret is on two devices
    When both exchange it
    Then each gets its own session for the same account_id
    When the player links the account on one device
    Then the secret answers 403 "account_linked" on both

  @security
  Scenario: Guest purge does not touch linked accounts
    Given the account "linked" has been idle for 400 days
    When the sweep runs
    Then it is not made dormant and not purged
