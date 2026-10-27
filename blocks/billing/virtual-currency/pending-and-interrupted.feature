Feature: Pending and interrupted purchases
  As a player whose payment needs approval or whose app was closed mid-purchase
  I want the pack to arrive once the store confirms, and never twice
  So that an interruption never costs me money or gives me double

  Background:
    Given the app is configured for tenant "tenant-001"
    And the catalog from fixtures/catalog.json is loaded
    And the store payloads from fixtures/store-payloads.json are available as verified store facts
    And the clock is fixed at "2026-10-27T12:00:00Z"
    And "account-001" is signed in and has an empty wallet

  @happy
  Scenario: A Google pending purchase grants nothing and is neither acknowledged nor consumed
    When "account-001" submits the Google purchase "gems_medium_pending"
    Then the response is 200 with state "pending" and "finish_transaction" false
    And the purchase record has state "pending"
    And "account-001" has 0 "gems"
    And the server did not call products.consume or products.acknowledge for "google-token-0002"
    And the client shows the pending state and the player can keep playing

  @happy
  Scenario: A pending purchase completes through the real-time notification
    Given the purchase "google-token-0002" is recorded as "pending"
    And the store now reports "gems_medium_pending_completed"
    When the Google notification "one_time_purchased" arrives with a valid push token
    Then the server re-reads the purchase with productsv2
    And the purchase record has state "verified"
    And "account-001" has 1050 "gems"
    And the server called products.consume after the grant committed
    When "account-001" opens the app
    Then GET /api/wallet shows 1050 "gems"

  @edge
  Scenario: A pending purchase completes through a client resubmission
    Given the purchase "google-token-0002" is recorded as "pending"
    And the store now reports "gems_medium_pending_completed"
    When the client recovers unconsumed purchases on resume and submits the token
    Then the purchase record has state "verified"
    And "account-001" has 1050 "gems"

  @edge
  Scenario: A pending purchase is canceled
    Given the purchase "google-token-0003" is recorded as "pending"
    When the Google notification "one_time_canceled" arrives
    Then the purchase record has state "canceled"
    And no ledger entry is written
    And the first-purchase bonus is not consumed

  @edge
  Scenario: Apple Ask to Buy produces no server record until approval
    Given the store reports the purchase as pending on the device
    Then no purchase record exists
    When the parent approves and the client receives the transaction "gems_medium_purchase" through its update stream
    And the client submits it
    Then "account-001" has 1050 "gems"
    And the response has "finish_transaction" true

  @happy
  Scenario: The app was killed after payment and recovers the purchase at launch
    Given the store charged "account-001" for "gems_medium_purchase" and the app was killed before submitting
    When the app starts and runs recovery
    Then the unfinished transaction is submitted once
    And "account-001" has 1050 "gems"
    And the client finishes the transaction only after the server answers "finish_transaction" true
    And a "purchase_recovered" event with source "launch" is written

  @edge
  Scenario: The response was lost after the grant and the client submits again
    Given the server granted "gems_medium_purchase" but the client never received the response
    When the client submits the same proof again
    Then the response carries the original purchase id and granted lines
    And "account-001" has 1050 "gems"

  @edge
  Scenario: The server is unreachable and the client keeps the transaction unfinished
    Given the server answers 503 to POST /api/purchases/verify
    When the client delivers "gems_medium_purchase"
    Then the client retries after 2, 5, 15 and 60 seconds and then every 60 seconds while the app is open
    And the Apple transaction stays unfinished
    When the server recovers
    Then "account-001" has 1050 "gems"
    And the client finishes the transaction

  @edge
  Scenario: A failed consume is retried inside the acknowledge window
    Given the purchase "google-token-0001" was granted and products.consume failed
    Then the purchase record has state "verified" and no store_finalized_at
    When the retry job runs every 300 seconds
    Then products.consume is called again until it succeeds
    And an alert is raised when the purchase is still unconsumed 86400 seconds after verification
    And the alert fires well before the three-day acknowledge deadline

  @security
  Scenario: A crash between the commit and the consume loses nothing
    Given the server crashes after committing the grant for "google-token-0001" and before calling products.consume
    When the retry job runs
    Then the purchase is consumed and store_finalized_at is set
    And "account-001" has 1050 "gems" exactly once

  @edge
  Scenario: A Google purchase consumed by a client is still delivered
    Given no local record exists for "google-token-0004"
    When the Google notification for "gems_medium_consumed_by_client" is processed
    Then "account-001" has 1050 "gems"
    And the purchase is flagged "consumed_by_other" in the logs and the reconciliation report
    And the server does not try to consume it again

  @edge
  Scenario: An Apple transaction finished too early is recovered by the notification
    Given the client finished "gems_medium_purchase" before the server delivered it
    When the Apple notification "one_time_charge" arrives
    Then the server verifies the transaction and credits "account-001" with 1050 "gems"

  @edge
  Scenario: A transaction left on a signed-out device does not enrich the next user
    Given "account-001" paid for "gems_medium_purchase" and signed out before delivery
    When "account-002" signs in on the same device and the client submits the unfinished transaction
    Then "account-001" has 1050 "gems"
    And "account-002" has 0 "gems" and sees only "other_account"
    And the client finishes the transaction

  @edge
  Scenario: A restored session does not pay out a rejected purchase twice
    Given "gems_medium_quantity_2" was rejected once
    When the client submits it again
    Then the response is 409 "purchase_rejected" again
    And no ledger entry is written
