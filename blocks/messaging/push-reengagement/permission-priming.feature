Feature: Permission priming
  As a player
  I want the game to explain its reminders before the phone asks
  So that I can say yes or no at a moment when the benefit is clear, and keep control afterwards

  Background:
    Given the app is configured for tenant "tenant-001"
    And the defaults from fixtures/config-defaults.json
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And the player is signed in as "acc-ann" and GET /api/push/state answers eligible true
    And the platform permission is "not_determined" and the system dialog can still be shown

  @happy
  Scenario: The sheet opens on a benefit trigger after the first win and the system dialog follows only its primary button
    Given the player has completed the first win
    When the trigger "first_timer_started" fires
    Then nextPrimingAction returns "show_sheet"
    And the priming sheet is displayed with push_priming_shown trigger "first_timer_started" and showing_index 1
    And no system dialog has been requested yet
    When the player taps "Turn on notifications"
    Then the system dialog is requested once
    And when the platform answers "authorized" the sheet closes
    And PUT /api/push/tokens is sent with permission_state "authorized"
    And push_priming_accepted, push_system_prompt_result with result "authorized" and push_token_registered fire in that order

  @edge
  Scenario: No ask before the first win, whatever the trigger
    Given the player has not completed the first win
    When the trigger "first_timer_started" fires
    Then nextPrimingAction returns "none"
    And no sheet is displayed and no system dialog is requested

  @edge
  Scenario: The fallback trigger fires on the third session, not before
    Given the player has completed the first win
    And no timer has been started and the streak is below day 2
    When session 2 starts
    Then nextPrimingAction for trigger "session_3" returns "none"
    When session 3 starts
    Then nextPrimingAction for trigger "session_3" returns "show_sheet"

  @happy
  Scenario: Not now returns later, at most twice more, and then only Settings offers it
    Given the player has completed the first win
    When the sheet is shown and the player taps "Not now"
    Then push_priming_declined fires with showing_index 1
    And the same trigger in the next session returns "none"
    When 3 sessions have passed since the last showing and a trigger fires
    Then nextPrimingAction returns "show_sheet"
    When the player taps "Not now" and 3 more sessions pass and a trigger fires
    Then the sheet is shown a third time
    When the player taps "Not now" and 3 more sessions pass and a trigger fires
    Then nextPrimingAction returns "none"

  @edge
  Scenario: The system dialog is never requested twice in one session
    Given the player accepted the sheet earlier in this session and the platform answered "denied"
    When another configured trigger fires in the same session
    Then nextPrimingAction returns "none"

  @edge
  Scenario: After an iOS refusal no code path shows the system dialog again
    Given the platform is iOS and the permission is "denied"
    Then canPrompt is false
    When any configured trigger fires after the first win
    Then nextPrimingAction never returns "show_sheet" or "request_system"
    And the notification settings screen shows the denied banner with the action "Open settings"
    When the player taps "Open settings"
    Then the platform opens the notification settings page and push_system_settings_opened fires

  @edge
  Scenario: Android allows one more attempt after the first refusal and none after the second
    Given the platform is Android 13 and the player refused the system dialog once
    Then canPrompt is true
    And the sheet may be shown again under the Not now rules
    When the player refuses the system dialog a second time
    Then canPrompt is false
    And the denied banner replaces the sheet from then on

  @edge
  Scenario: The inline denied hint is rare and never opens system settings by itself
    Given the permission is "denied" and canPrompt is false
    When the trigger "first_timer_started" fires in session 6 and no hint was shown before
    Then nextPrimingAction returns "show_denied_hint"
    And the hint offers a link to the notification settings screen and a dismiss control
    When 5 sessions pass and the trigger fires again
    Then a second hint may be shown
    When 5 more sessions pass and the trigger fires again
    Then nextPrimingAction returns "none" because DENIED_HINT_MAX is 2

  @happy
  Scenario: Turning notifications on in system settings is picked up when the app returns
    Given the permission was "denied" and the denied banner is visible
    When the player enables notifications in the system settings and returns to the app
    Then permission() is "authorized" and push_permission_changed fires with from "denied", to "authorized", source "system_settings"
    And the token is uploaded and the banner disappears with a one-line confirmation

  @happy
  Scenario: A player flips a switch in Settings while not asked yet
    Given the permission is "not_determined"
    When the player taps "Turn on" in the permission status row
    Then nextPrimingAction with trigger "settings_toggle" returns "request_system"
    And no sheet is displayed, because the player acted on purpose

  @edge
  Scenario: Android 12 and lower has no runtime permission
    Given the platform is Android 12 and areNotificationsEnabled() is true
    Then permission() is "authorized" and no system dialog is requested
    And the token is uploaded at the next start
    And the priming sheet still explains the categories and records the promotional consent

  @edge
  Scenario: Channels exist before the first remote send on Android
    Given the platform is Android 13
    When the app starts
    Then ensureChannels creates the channels "streak.v1", "events.v1", "timers.v1", "rewards.v1" and "comeback.v1"
    And running it again at the next start changes nothing

  @edge
  Scenario: Provisional authorization registers a token without a dialog when enabled
    Given PROVISIONAL_FIRST is true and the platform is iOS
    When the app starts for the first time
    Then request is called with provisional true and no dialog is displayed
    And the permission is "provisional" and the token is uploaded
    And the settings status row says "Quiet delivery only"

  @security
  Scenario: The promotional switches are off by default and enabling them records the consent copy
    When the priming sheet is displayed
    Then the switches for "events" and "comeback" are unchecked
    When the player ticks "events" and taps "Turn on notifications"
    Then PATCH /api/push/preferences sends categories.events.enabled true with consent_text_version "v1"
    And the sheet copy promises no reward for enabling notifications

  @security
  Scenario: A player under the age threshold never sees the sheet
    Given GET /api/push/state answers eligible false with ineligible_reason "age_not_eligible"
    When any trigger fires
    Then nextPrimingAction returns "none"
    And the Settings menu has no notifications entry
