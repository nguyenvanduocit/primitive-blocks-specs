Feature: Inert by default
  As a developer or a web visitor
  I want builds without a store to work with everything unlocked
  So that development, tests, and the web never depend on store credentials

  @happy
  Scenario: The web build has everything unlocked and never calls the store
    Given the app runs in a browser, not on a native platform
    When the app starts and the learner opens a locked item "q3"
    Then the purchases store is inactive
    And the item opens
    And no store SDK call is made
    And the paywall is not rendered

  @happy
  Scenario: A native build without a store key behaves like the web
    Given the app runs on a native platform
    And no store key is present for that platform
    When the learner opens the locked item "q3"
    Then the purchases store is inactive
    And the item opens
    And no store SDK call is made

  @happy
  Scenario Outline: A native build uses the key of its own platform
    Given the app runs on the "<platform>" native platform
    And the iOS key is "<ios>" and the Android key is "<android>"
    When the purchases port is created
    Then the store is "<state>"

    Examples:
      | platform | ios     | android     | state    |
      | ios      | key-ios | absent      | active   |
      | android  | absent  | key-android | active   |
      | ios      | absent  | key-android | inactive |
      | android  | key-ios | absent      | inactive |

  @edge
  Scenario: Tests inject a fake store and bypass the real one
    Given a test boots the app with a fake purchases port that is active
    When the learner opens the locked item "q3"
    Then the gate uses the fake port's answers
    And no real SDK module is loaded

  @edge
  Scenario: A browser build never evaluates the store SDK module
    Given the app runs in a browser
    When the app starts and the learner uses every content entry
    Then the store SDK module is never imported
