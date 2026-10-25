Feature: Restore, store user identity, and entitlement updates
  As a learner who bought on another device or signed in later
  I want my unlock to follow my account
  So that I never pay twice

  Background:
    Given the purchases store is active
    And the current offering has one package "$rc_lifetime"

  @happy
  Scenario: Restore finds the purchase
    Given the learner does not own "pro"
    And the paywall is open
    When the learner taps "Restore purchases"
    And the store reports the entitlement "pro" active
    Then the paywall closes
    And one confirmation toast is shown

  @edge
  Scenario: Restore finds nothing
    Given the learner does not own "pro"
    And the paywall is open
    When the learner taps "Restore purchases"
    And the store reports no active entitlements
    Then the text "no purchase found" is shown
    And the paywall stays open

  @happy
  Scenario Outline: Restore is visible in every offer state
    Given the offer state is "<state>"
    When the paywall is open
    Then "Restore purchases" is shown

    Examples:
      | state   |
      | loading |
      | ready   |
      | none    |
      | failed  |

  @happy
  Scenario: The store is configured with the account uid at start-up
    Given the learner is signed in as account "account-uid-001"
    When the app starts
    Then the store is configured once with app user id "account-uid-001"

  @happy
  Scenario: The store is configured anonymously when signed out
    Given the learner is signed out
    When the app starts
    Then the store is configured once with a null app user id

  @happy
  Scenario: Sign-in and sign-out switch the store user
    Given the store was configured anonymously
    When the learner signs in as account "account-uid-001"
    Then the store logs in as "account-uid-001"
    And "pro" follows the entitlement returned for that user
    When the learner signs out
    Then the store logs out to a fresh anonymous user
    And "pro" follows the entitlement returned for the anonymous user

  @edge
  Scenario: A store update unlocks and closes the paywall, a refund locks again
    Given the learner does not own "pro" and the paywall is open
    When the store pushes an update with "pro" active (a deferred payment was approved)
    Then the paywall closes and items unlock
    When the store pushes an update with no active entitlements (a refund)
    Then the next gate call locks the non-free items again

  @edge
  Scenario: A failed store start is retried by the next store action
    Given the first attempt to configure the store failed
    When the learner opens the paywall and taps Buy
    Then the store configuration is attempted again before the purchase
    And when it still fails the problem is "network" and no purchase call is made

  # Extrapolated rule: not exercised by the source project's tests.
  @security
  Scenario: The store user id is the opaque account uid, never the email
    Given the learner is signed in with email "learner@example.com" and uid "account-uid-001"
    When the store is configured or logged in
    Then the app user id sent to the store is "account-uid-001"
    And the email does not appear in any store call
