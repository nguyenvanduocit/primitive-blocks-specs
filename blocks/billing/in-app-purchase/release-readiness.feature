Feature: Release readiness for purchases
  As the person shipping the app to the stores
  I want the store objects, keys, and reviewer access checked before upload
  So that version 1 sells, leaks no secret, and can be reviewed

  @happy
  Scenario: Store objects exist and agree across platforms
    Given a RevenueCat project has one app per platform
    When the offerings are fetched with the Android public key and with the iOS public key
    Then the current offering is "default"
    And it holds one package "$rc_lifetime"
    And that package maps to the product with the same identifier on both stores
    And the entitlement "pro" has that product attached

  @edge
  Scenario: The sold offering has exactly one package
    Given the current offering is "default"
    When the packages of the offering are listed
    Then there is exactly one package
    And the app sells the first package

  @error
  Scenario: A native release candidate without the store key is rejected
    Given a native release build was made without the key for its platform
    When the release check runs on the build
    Then the check fails with "purchases are inert in this build"
    And the build is not uploaded

  @happy
  Scenario: A keyed release candidate shows the paywall on locked content
    Given a native release build with the key for its platform
    And the learner does not own "pro"
    When the learner opens a locked item
    Then the paywall opens and shows a store price

  @security
  Scenario: The Test Store key is not in the uploaded build
    Given a build was made with the Test Store key for a screenshot
    When the final build is made with the real public key
    Then a search of the build for the Test Store key value finds nothing
    And the real public key is present

  @security
  Scenario: Secret files are ignored by version control
    Given the secrets folder holds the Play service-account JSON, the App Store IAP key file, and the promo codes
    When "git check-ignore" is run on each path
    Then every path is reported as ignored
    And none of the key id, issuer id, or file contents appears in tracked files

  @happy
  Scenario: Google Play reviewers can reach the paid content
    Given app access is declared as restricted
    When the "Sign in details" form is read
    Then it states that content is free and the unlock is paid
    And it lists one-time promo codes for the product that are valid on the review dates
    And the store listing text agrees with the declaration

  @happy
  Scenario: App Store reviewers can reach the paid content
    Given the in-app purchase is created with the same product identifier
    When the first app version is submitted
    Then the in-app purchase is added to the same submission
    And a screenshot of the paywall is attached to the in-app purchase
    And the paywall shows Restore purchases
