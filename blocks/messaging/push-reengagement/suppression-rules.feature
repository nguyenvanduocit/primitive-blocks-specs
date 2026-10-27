Feature: Suppression, caps, quiet hours and switches
  As a player
  I want notifications to stop when I opened the app, when I asked for quiet, and when I have had enough
  So that the ones I do get are few and welcome

  Background:
    Given the app is configured for tenant "tenant-001"
    And the profiles from fixtures/profiles.json exist
    And the defaults from fixtures/config-defaults.json
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario Outline: The decision pipeline answers each case of the fixture
    When decide runs for the case "<case>" of fixtures/profiles.json decision_cases
    Then the action is "<action>" and the reason is "<reason>"

    Examples:
      | case                              | action   | reason            |
      | D01-ladder-send                   | send     |                   |
      | D03-global-off                    | suppress | global_off        |
      | D04-minor                         | suppress | age_ineligible    |
      | D05-category-off                  | suppress | category_off      |
      | D06-no-device                     | suppress | no_device         |
      | D07-cap-day                       | suppress | cap_day           |
      | D08-cap-week                      | suppress | cap_week          |
      | D09-os-channel-blocked            | suppress | os_blocked        |
      | D12-promotional-with-consent      | send     |                   |
      | D13-promotional-without-consent   | suppress | category_off      |
      | D16-expired-before-due-check      | suppress | expired           |

  @edge
  Scenario Outline: A trial-ending service notice follows its own rules
    Given the event "subscription_trial_ending" is armed with fire_at due now and expires_at "2026-10-23T12:00:00Z"
    When decide runs for the case "<case>" of fixtures/profiles.json decision_cases
    Then the action is "<action>" and the reason is "<reason>"

    Examples:
      | case                                      | action   | reason         |
      | D17-service-ignores-marketing-cap         | send     |                |
      | D18-service-honours-global-off            | suppress | global_off     |
      | D20-service-never-held-out                | send     |                |
      | D21-service-default-off-when-not-adult    | suppress | category_off   |
      | D22-service-cap                           | suppress | cap_service    |
      | D23-service-never-bypasses-age            | suppress | age_ineligible |

  @edge
  Scenario: A service notice waits out quiet hours
    When decide runs for the case "D19-service-honours-quiet-hours"
    Then the action is "defer" and due_at is "2026-10-21T12:00:00Z"
    And if that instant were at or after the conversion instant the outcome would be "quiet_expired" and nothing is sent

  @edge
  Scenario: A service notice does not use up the marketing budget
    Given "acc-ann" has 1 marketing send in her local day and the day cap is 2
    When a "subscription" notice is dispatched to "acc-ann"
    Then the marketing day count is still 1 and the service count is 1
    And a "streak" intent due in the same tick is still sent
    When a second "subscription" notice is evaluated the same local day
    Then it is suppressed with reason "cap_service"

  @edge
  Scenario: The subscription category starts on for an adult and off for a profile not verified as an adult
    Given "acc-ann" is adult and has no stored preference for "subscription"
    Then GET /api/push/state shows the "subscription" category enabled with service_notice true
    Given "acc-ned" has age_status "unknown", UNKNOWN_AGE_POLICY is "allow" and no stored preference
    Then GET /api/push/state shows the "subscription" category disabled
    When "acc-ned" switches it on through PATCH /api/push/preferences
    Then no consent_text_version is required, because it is a service category

  @security
  Scenario Outline: A service template may not sell or pressure
    When the text "<text>" is saved as a template of the category "subscription"
    Then the lint reports <violations>

    Examples:
      | text                                         | violations |
      | Your free trial ends on {renewal_date}       | none       |
      | Upgrade now and save 40%                     | upsell     |
      | Special offer: stay for half price           | upsell     |
      | Don't lose your VIP perks!                   | guilt      |

  @edge
  Scenario: The global switch beats every category
    Given "acc-cara" has the "timers" category enabled and global_enabled false
    When a "rewards" intent is evaluated for "acc-cara"
    Then the decision is "suppress" with reason "global_off"
    When "acc-cara" turns the master switch on through PATCH /api/push/preferences
    Then the previous category choices are unchanged

  @edge
  Scenario: Turning a category off cancels what is already waiting
    Given "acc-ann" has 2 pending intents in the "events" category and 1 in "rewards"
    When "acc-ann" sends PATCH /api/push/preferences with categories.events.enabled false
    Then both "events" intents are "cancelled" with suppress_reason "category_off"
    And the "rewards" intent is still "pending"

  @edge
  Scenario Outline: Quiet hours are evaluated in the player's local time
    Given a profile in "<timezone>" with quiet hours <quiet>
    When the time is "<now>"
    Then in_quiet is <in_quiet>
    And the next allowed instant is "<next>"

    Examples:
      | case                      | timezone            | quiet        | now                  | in_quiet | next                 |
      | T01-hcm-inside-quiet      | Asia/Ho_Chi_Minh    | 22:00-08:00  | 2026-10-21T16:30:00Z | true     | 2026-10-22T01:00:00Z |
      | T02-hcm-at-quiet-start    | Asia/Ho_Chi_Minh    | 22:00-08:00  | 2026-10-21T15:00:00Z | true     | 2026-10-22T01:00:00Z |
      | T03-hcm-at-quiet-end      | Asia/Ho_Chi_Minh    | 22:00-08:00  | 2026-10-22T01:00:00Z | false    | 2026-10-22T01:00:00Z |
      | T04-ny-before-dst-end     | America/New_York    | 22:00-08:00  | 2026-10-31T11:30:00Z | true     | 2026-10-31T12:00:00Z |
      | T05-ny-after-dst-end      | America/New_York    | 22:00-08:00  | 2026-11-01T11:30:00Z | true     | 2026-11-01T13:00:00Z |
      | T06-berlin-after-dst-end  | Europe/Berlin       | 22:00-08:00  | 2026-10-25T06:30:00Z | true     | 2026-10-25T07:00:00Z |
      | T07-berlin-after-quiet    | Europe/Berlin       | 22:00-08:00  | 2026-10-25T07:30:00Z | false    | 2026-10-25T07:30:00Z |
      | T08-quiet-disabled        | Asia/Ho_Chi_Minh    | off          | 2026-10-21T16:30:00Z | false    | 2026-10-21T16:30:00Z |
      | T09-same-day-window       | Asia/Ho_Chi_Minh    | 13:00-15:00  | 2026-10-21T07:30:00Z | true     | 2026-10-21T08:00:00Z |

  @edge
  Scenario: A quiet-hours deferral waits for the window end, or is dropped when that is too late
    When decide runs for the case "D10-quiet-defer"
    Then the action is "defer" and due_at is "2026-10-21T12:00:00Z"
    When decide runs for the case "D11-quiet-expired"
    Then the action is "suppress" with reason "quiet_expired"
    And no intent is sent inside a quiet window

  @edge
  Scenario: A capped candidate is dropped, never queued for the morning
    Given "acc-ivy" has 2 sends in her local day "2026-10-21"
    When a "rewards" intent due now is evaluated
    Then it is "suppressed" with reason "cap_day"
    And no row remains pending for it after quiet hours end

  @edge
  Scenario: When one slot is left the higher-priority category wins
    Given "acc-ann" already has 1 send in her local day and the day cap is 2
    And a "comeback" intent and a "streak" intent are both due in the same tick
    When the dispatcher evaluates them
    Then the "streak" intent is "dispatched" because its category priority is 1
    And the "comeback" intent is "suppressed" with reason "cap_day"

  @edge
  Scenario: The week window counts the last seven local days including today
    Given "acc-jon" has 8 sends on the local dates 2026-10-16 to 2026-10-19 and none today
    Then the day cap is not reached and the week cap is
    When the local date becomes "2026-10-23"
    Then the sends of 2026-10-16 are outside the window and the week count is 6

  @edge
  Scenario: Local notifications count against the same caps once reported
    Given "acc-ann" fired 2 local notifications today and has not synced yet
    When "acc-ann" sends POST /api/push/session with those 2 entries in local_fired
    Then 2 intents with lane "local" and status "dispatched" exist with today's sent_day_key
    And a remote "events" candidate is suppressed with reason "cap_day"

  @edge
  Scenario: The holdout decides last, after every other rule
    Given "acc-ben" is in the holdout and has reached the day cap
    When her "comeback" step is evaluated
    Then the decision is "suppress" with reason "cap_day" and not "hold_out"
    And only an intent that passed every earlier rule can be held out

  @edge
  Scenario: Only the categories named for holdout are withheld
    Given "acc-ben" is in the holdout
    When an "events" intent that passes every rule is evaluated for her
    Then the decision is "send"

  @security
  Scenario: A profile that becomes a minor loses every route to a notification
    Given "acc-ann" has an active token, 2 pending intents and a local plan
    When the age gate calls set_age_status("acc-ann", "minor")
    Then the token row is inactive with inactive_reason "age_blocked"
    And both pending intents are "cancelled" and the ladder pointer is null
    And GET /api/push/state answers eligible false and local.allowed false
    And PATCH /api/push/preferences answers 403 age_not_eligible

  @edge
  Scenario: Opening the app cancels the reminders that the open makes pointless
    Given "acc-ann" has a pending "objective_reward_ready" intent whose event has cancel_on_session
    And a pending "event_ending_soon" intent whose event does not
    When "acc-ann" sends POST /api/push/session
    Then the "objective_reward_ready" intent is "cancelled" with reason "returned"
    And the "event_ending_soon" intent is still "pending"

  @edge
  Scenario: The app in the foreground shows no system banner
    Given the app is in the foreground and a remote notification arrives
    Then the platform handler shows no system notification
    And the app refreshes the state the message concerns

  @edge
  Scenario Outline: The copy language falls back from the exact tag to the language to the default
    When the profile locale is "<locale>" and the template is "<template>"
    Then the copy is taken from "<resolved>"

    Examples:
      | locale | template            | resolved |
      | en-GB  | streak.at_risk      | en-GB    |
      | en-AU  | streak.at_risk      | en       |
      | de-AT  | timers.energy_full  | de       |
      | ja     | timers.energy_full  | en       |

  @security
  Scenario Outline: The copy lint rejects guilt, fake urgency and false scarcity
    When the text "<text>" is saved as a template
    Then the lint reports <violations>

    Examples:
      | text                                    | violations                       |
      | Don't let your streak die!              | guilt                            |
      | Your pet is sad without you             | guilt                            |
      | Only 2 left, hurry!                     | false_scarcity and fake_urgency  |
      | Last chance to claim your gift          | fake_urgency                     |
      | {event_title} ends in {ends_in}         | none, with time_binding set      |
      | A welcome-back gift is ready            | none                             |

  @happy
  Scenario Outline: Each emitter's event renders from its declared params
    When the case "<case>" of fixtures/template-catalog.json handoff_param_cases is rendered
    Then the title and body equal the case's expect
    And the lane, the local_key or dedupe_key and the route with its parameters equal the case's values

    Examples:
      | case                              |
      | H1-streak_at_risk                 |
      | H2-energy_full                    |
      | H3-queue_item_ready               |
      | H4-event_ending_soon              |
      | H5-objective_reward_ready         |
      | H6-subscription_trial_ending      |

  @edge
  Scenario Outline: A param that is absent leaves copy that still reads correctly
    When the render case "<case>" of fixtures/template-catalog.json render_cases is rendered
    Then the outcome is "<outcome>"
    And the body is "<body>"

    Examples:
      | case                              | outcome        | body                                                                                            |
      | R4-streak-no-reward               | ok             | Play once today to keep it going.                                                               |
      | R5-streak-unknown-reward-code     | ok             | Play once today to keep it going.                                                               |
      | R8-trial-unknown-price            | ok             | The exact amount, which taxes can change, is on the store screen. Manage or cancel in Settings. |
      | R9-trial-no-renewal-date          | template_error | none, the notice is suppressed                                                                  |
      | R2-event-title-missing            | template_error | none, the notice is suppressed                                                                  |

  @edge
  Scenario Outline: The trial notice formats the price in the player's locale and states the exact amount is on the store screen
    When the render case "<case>" is rendered
    Then the title is "<title>"
    And the body is "<body>"

    Examples:
      | case                  | title                                    | body                                                                                                                                       |
      | R6-trial-price-en     | Your free trial ends on November 2, 2026 | About $4.99 per month after that. The exact amount, which taxes can change, is on the store screen. Manage or cancel in Settings.          |
      | R7-trial-price-en-gb  | Your free trial ends on 2 November 2026  | About £11.99 every 3 months after that. The exact amount, which taxes can change, is on the store screen. Manage or cancel in Settings.    |

  @edge
  Scenario: A template whose required variable is missing is suppressed, never rendered blank
    When the template "events.ending_soon" renders with params that lack event_title
    Then the intent is "suppressed" with reason "template_error"
    And a template given extra params it does not name renders normally
