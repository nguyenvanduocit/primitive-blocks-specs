Feature: Buying the one-time unlock
  As a learner who reached locked content
  I want to see the real price and buy once
  So that I own every item permanently

  Background:
    Given the purchases store is active and configured
    And the learner is signed in as account "account-uid-001"
    And the learner does not own "pro"
    And the current offering has one package "$rc_lifetime" with price string "$14.99"

  @happy
  Scenario: Tapping a locked item opens the paywall with the store price
    When the learner opens the locked item "q3"
    Then the paywall opens
    And the Buy button reads "Unlock for $14.99"
    And the price text comes from the package's product price string
    And the "Restore purchases" action is visible

  @happy
  Scenario: A successful purchase unlocks and closes the paywall
    Given the paywall is open and the offer is ready
    When the learner taps Buy
    And the store reports the entitlement "pro" active
    Then the paywall closes
    And one confirmation toast is shown
    And opening the locked item "q3" now plays it without opening the paywall

  @happy
  Scenario: The paywall never opens at launch
    Given the app starts with the learner not owning "pro"
    When no content entry has been used
    Then the paywall is closed
    And no gate call was made

  @error
  Scenario: A cancelled purchase is silent
    Given the paywall is open and the offer is ready
    When the learner taps Buy
    And the store answers error code "1"
    Then no message is shown
    And the paywall stays open
    And the learner does not own "pro"

  # Examples come from fixtures/store-errors.json
  @error
  Scenario Outline: A failed purchase says why and keeps the paywall open
    Given the paywall is open and the offer is ready
    When the learner taps Buy
    And the store answers error code "<code>"
    Then the problem is "<problem>"
    And a one-line message for "<problem>" is shown in an alert region
    And the paywall stays open
    And Buy and Restore are usable again

    Examples:
      | code    | problem     |
      | 10      | network     |
      | 3       | notAllowed  |
      | 20      | pending     |
      | 6       | owned       |
      | 5       | unavailable |
      | 999     | store       |

  @edge
  Scenario: The store has no product to sell
    Given the current offering has no package
    When the learner opens the paywall
    Then the offer state is "none"
    And no Buy button is shown
    And "Restore purchases" is still shown

  @edge
  Scenario: The store cannot be reached when loading the price
    Given the store answers a network error when the offerings are requested
    When the learner opens the paywall
    Then the offer state is "failed"
    And a "Try again" action is shown
    When the store becomes reachable and the learner taps "Try again"
    Then the offer state becomes "ready" and the price is shown

  @edge
  Scenario: A second tap while a purchase is running is ignored
    Given the paywall is open and a purchase is running
    When the learner taps Buy again
    Then no second purchase call is made
    And the busy state stays "buy" until the first call settles

  @edge
  Scenario: Resuming a stored session is not gated
    Given the learner started a session while it was gated
    When the app restarts and the learner resumes the stored session
    Then the session resumes without a gate call
    And the paywall stays closed
