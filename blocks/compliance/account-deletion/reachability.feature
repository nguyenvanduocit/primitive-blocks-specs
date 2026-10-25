Feature: Delete Account Reachability and Confirmation
  As a user and as a store reviewer
  I want to find and complete account deletion inside the app
  So that deletion is demonstrable on a device without contacting support

  Background:
    Given the app is launched on a device
    And a user "alice@example.com" is signed in and the account is confirmed online

  @happy
  Scenario: Delete account is reachable from Settings
    When I open Settings
    Then the account card shows a "Delete account" control with test hook "account-delete"
    And reaching it needs no link out of the app and no email

  @happy
  Scenario: The confirm dialog states what is deleted and what stays
    When I tap "account-delete"
    Then a dialog opens with a Cancel action "account-delete-cancel" and a Delete action "account-delete-confirm"
    And the dialog text names the profile and leaderboard place, the friend code and friend list, the progress saved in the account and the sign-in
    And the dialog says the deletion cannot be undone
    And the dialog says I will be asked to confirm it is me
    And the dialog says that data on this device stays when ACCOUNT_DELETION_WIPE_LOCAL_DATA is false

  @happy
  Scenario: Confirming re-authenticates from the click and signs me out
    Given the SDK of the sign-in provider is already loaded
    When I tap "account-delete-confirm"
    Then the provider confirmation opens as the first asynchronous step of the click
    When I confirm with the same account
    Then the app shows the signed-out sign-in card
    And a success message "Your account was deleted" is shown
    And the cached account identity is removed from device storage
    And the on-device study data still exists
    And the on-device data has no account owner marker

  @happy
  Scenario: Wiping on-device content when the merchant chose to
    Given ACCOUNT_DELETION_WIPE_LOCAL_DATA is true
    When I complete a valid deletion
    Then the on-device study data no longer exists
    And the dialog shown earlier said that data on this device is erased too

  @error
  Scenario: Cancelling the dialog does nothing
    When I tap "account-delete" and then "account-delete-cancel"
    Then no request is sent to the deletion endpoint
    And I am still signed in

  @error
  Scenario: Closing the provider sheet is not an error
    When I tap "account-delete-confirm" and close the provider sheet
    Then no error message is shown
    And I am still signed in
    And the Delete account control is enabled again

  @error
  Scenario: Confirming with a different account shows a specific message
    When I tap "account-delete-confirm" and sign in with a different account
    Then the element "account-delete-error" shows the "different account" message
    And I am still signed in

  @edge
  Scenario: Deletion is not offered when the account cannot be reached
    Given the app cannot reach the account service
    When I open Settings
    Then the account card shows the retry control
    And the "Delete account" control is absent
