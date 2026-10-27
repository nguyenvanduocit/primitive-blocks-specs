Feature: Paywall disclosure, purchase states and subscription banners
  As a player
  I want to know exactly what I am buying and what is happening to my subscription
  So that nothing about price, renewal or cancellation surprises me

  Background:
    Given the app runs in a native shell on "ios" with the store adapter faked from the offers a test provides
    And the entitlement for "vip" is "none"
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: The paywall shows every disclosure before the store sheet
    Given the store offers "vip-monthly-apple" with price string "$9.99" and a 7-day free trial for an eligible player
    When I open the paywall from the "Get VIP" entry
    Then I see the plan name and duration and what VIP includes
    And I see the billed amount "$9.99" as the most prominent price
    And I see "Renews automatically every month at $9.99 until you cancel."
    And I see the trial length and the price billed after it
    And I see how to cancel before the trial ends with a link to the store's subscription settings
    And I see "Restore purchases", the Terms of Use link and the Privacy Policy link
    And I do not have to expand anything to read them

  @edge
  Scenario: Trial wording appears only for an offer the store reports as eligible
    Given the store reports the trial offer as not eligible for this player
    When I open the paywall
    Then no trial wording is shown anywhere, including the benefit lines
    And the billed amount and renewal text are shown

  @edge
  Scenario: Prices come from the store, never from a constant
    Given the store returns price string "9,99 EUR" for the same plan
    When I open the paywall
    Then the billed amount reads "9,99 EUR" and no price constant exists in the client code

  @edge
  Scenario: A longer plan shows the billed amount more prominently than a per-month equivalent
    Given the yearly plan has store price "$79.99" and a per-month equivalent is shown
    When I open the paywall
    Then "$79.99" is visually larger than the per-month text

  @edge
  Scenario: Close is as visible as Subscribe and no timer is shown without a store offer end date
    When I open the paywall
    Then the Close control is visible without scrolling
    And no countdown is shown unless the store offer provides an end date

  @edge
  Scenario: The paywall never opens at launch or for an entitled player
    When the app starts
    Then the paywall is closed
    Given the entitlement for "vip" is "active"
    When I tap "Get VIP"
    Then I see my status and Manage, and Subscribe is not shown

  @edge
  Scenario: A subscription held on the other store is explained, not sold again
    Given the server answers "already_entitled" because the entitled chain is on "google"
    When I open the paywall
    Then I see that I already have this subscription through Google Play and how to manage it there
    And Subscribe is not shown

  @edge
  Scenario Outline: Offer states
    Given the offer state is "<state>"
    When I open the paywall
    Then I see "<shown>"
    And "Restore purchases" is shown

    Examples:
      | state             | shown                                      |
      | loading           | price placeholders and Subscribe disabled  |
      | unavailable       | This subscription isn't available right now |
      | store_unreachable | Can't reach the store with Try again       |

  @happy
  Scenario: A successful purchase confirms access and the next date
    Given the store sheet completes and the server claim returns active with expires_at "2026-11-27T12:00:00Z" and will_renew true
    When the purchase finishes
    Then I see that VIP is on, the renewal date, the next stipend and a Manage link
    And the store transaction is finished only after the server confirmed

  @edge
  Scenario: A cancelled store sheet shows nothing
    Given I cancel the store sheet
    Then no message is shown and Subscribe is usable again

  @edge
  Scenario: A charged player whose claim fails sees "confirming", never an error
    Given the store charged me and the server claim fails with a network error
    Then I see "We're confirming your purchase. Your access appears as soon as it's done. You don't need to pay again."
    And the store transaction stays unfinished
    When the app returns to the foreground
    Then the claim is retried

  @edge
  Scenario: A pending purchase shows a waiting state without perks
    Given the store reports the purchase as pending approval or payment
    Then I see "Waiting for approval or payment" and VIP perks stay off
    And I can close the sheet and keep playing

  @happy
  Scenario Outline: One banner per state
    Given the entitlement is state "<state>" with expires_at "2026-10-30T12:00:00Z"
    When I open the home screen
    Then the primary banner is "<banner>"

    Examples:
      | state    | banner   |
      | grace    | grace    |
      | retry    | retry    |
      | paused   | paused   |
      | canceled | canceled |
      | expired  | expired  |
      | revoked  | revoked  |
      | pending  | pending  |

  @edge
  Scenario: The grace banner names the date and the way to fix payment
    Given the entitlement is state "grace" ending "2026-10-30T12:00:00Z"
    Then the banner says VIP stays on until that date while the store tries again and offers "Update payment method"
    And the action opens the store's payment page for the chain's platform

  @edge
  Scenario: Price-change banner appears next to the state banner
    Given the entitlement is active with price_change_state "pending_consent"
    Then the banners are "price_change" only
    Given the entitlement is state "grace" with price_change_state "pending_consent"
    Then the banners are "grace" and "price_change"

  @happy
  Scenario: The trial-ending banner shows the date and price whether or not push is on, and never sells
    Given the entitlement is state "trial" with detail.trial_ending ends_at "2026-11-03T12:00:00Z", price_milliunits 9990, currency_code "USD" and period "P1M"
    And push notifications are denied for this device
    When I open the home screen
    Then the primary banner is "trial_ending"
    And it names the end date and time in my locale and time zone and the price per month after the trial
    And its only actions are "Manage subscription" and "Dismiss"
    And it contains no offer, discount, "keep your perks", urgency wording, countdown or push-permission prompt
    When I tap "Dismiss"
    Then it is hidden for this session and returns in the next session while the window is open
    Given the player cancels during the trial
    Then the banner is "canceled" and says VIP ends on that date

  @edge
  Scenario: Active auto-renewing subscriptions show no banner
    Given the entitlement is active with will_renew true
    Then no banner is shown

  @edge
  Scenario: Manage opens the store of the chain, not the device's store
    Given the chain's platform is "apple" and the device is Android
    When I open Manage
    Then I see the instruction to manage it on an iPhone and no broken link
    Given the chain's platform is "google"
    When I open Manage on Android
    Then the system opens "https://play.google.com/store/account/subscriptions?sku=example_vip&package=com.example.game"

  @edge
  Scenario: After returning from the store's manage screen the client refreshes
    When I return from the store's manage screen
    Then the client calls POST /api/subscriptions/refresh and shows the new state

  @edge
  Scenario Outline: Restore results
    Given restore returns "<result>"
    Then I see "<copy>"

    Examples:
      | result           | copy                                                                  |
      | found            | Restored. VIP is active until the date                                 |
      | none             | We didn't find a subscription for this store account                  |
      | linked_elsewhere | This subscription is linked to another game account. Move it to this account? |
      | cooldown         | This subscription was moved recently. You can move it again on the date |
      | error            | Couldn't reach the store or the server                                |

  @security
  Scenario: The client never marks itself subscribed
    Given the store adapter reports an active subscription but the server says "none"
    When I open the paywall
    Then the server's answer is shown and perks that depend on the server stay off

  @security
  Scenario: No dark patterns in plan presentation
    When I open the paywall with two plans
    Then both plans have equal visual weight and none is pre-selected by a countdown
    And no plan is named "Free Trial" when it carries a recurring charge

  @security
  Scenario: Accessibility of the paywall
    When I open the paywall with a screen reader at the largest text size
    Then the plans are a radio group whose names carry plan, period and billed price
    And the disclosure is readable without truncation
    And a failed purchase is announced as an alert
