Feature: Starter objectives
  As a new player
  I want a guided first session that ends with a short, a medium and a long goal
  So that I always know what to do next and see the true progress of every goal

  Background:
    Given the app is configured for tenant "tenant-001"
    And the content set from fixtures/definitions.json is published
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And I am authenticated as the new account "acct-001" with timezone "Asia/Ho_Chi_Minh" and no objective rows
    And the validator accepts event refs that start with "run-ok-"
    And every client event for a play metric carries attempt_id "att-confirmed", which the attempt hook reports as "confirmed"
    And a fake ledger holds account "acct-001" with no balances

  @happy
  Scenario: The first list call assigns the starter plan
    When I send GET /api/objectives?scope=starter
    Then the response status is 200
    And the items are the six starter objectives in the order starter.finish-level, starter.spend-coins, starter.clear-three-levels, starter.goal-short, starter.goal-medium, starter.goal-long
    And starter.finish-level is "active" with progress 0 of 1
    And the other five are "locked" and are returned because their visibility is "preview"
    And every starter item has ends_at null
    And the response has starter total 6, claimed 0 and done false
    And next_goal is the instance of starter.finish-level
    And exactly one assignment window with window_key "starter" exists for "acct-001"

  @happy
  Scenario: Completing a step unlocks the next step without a claim
    When I send POST /api/objectives/events with one level_completed event, ref "run-ok-1"
    Then starter.finish-level is "completed" with progress 1 of 1
    And starter.spend-coins is "active"
    And the ledger has received no grant
    And the response lists starter.finish-level in completed

  @happy
  Scenario: A step counted from a lifetime total starts at the true count
    Given starter.finish-level is completed by one level_completed event with ref "run-ok-1"
    When the ledger adapter calls ingest_server_event with source "ledger.soft-spend", source_ref "entry-1", metric soft_currency_spent, amount 50
    Then starter.spend-coins is "completed"
    And starter.clear-three-levels is "active" with progress 1 of 3
    And the item shows chain id "starter-steps", position 3 of 3

  @happy
  Scenario: The last tutorial step reveals the short, medium and long goals
    Given starter.finish-level and starter.spend-coins are completed
    When I send POST /api/objectives/events with one level_completed event of amount 2, ref "run-ok-2"
    Then starter.clear-three-levels is "completed"
    And starter.goal-short is "active" with progress 3 of 8 and horizon "short"
    And starter.goal-medium is "active" with progress 1 of 3 and horizon "medium"
    And starter.goal-long is "active" with progress 3 of 30 and horizon "long"

  @edge
  Scenario: The medium goal counts today as an active day
    Given starter.clear-three-levels is completed
    Then the counter for metric active_day is 1
    And starter.goal-medium shows progress 1 of 3

  @edge
  Scenario: Starter objectives never expire
    Given starter.finish-level is "active" with progress 0 of 1
    When the clock moves to "2026-11-30T12:00:00Z" and I send GET /api/objectives?scope=starter
    Then starter.finish-level is still "active" with ends_at null
    And no starter instance has state "expired"

  @edge
  Scenario: Two devices see one starter set
    When device A and device B both send GET /api/objectives?scope=starter at "2026-10-21T12:00:00Z"
    Then both responses contain the same six instance ids
    And exactly one assignment window with window_key "starter" exists
    And exactly six starter instances exist

  @security
  Scenario: A client cannot complete the spend step by reporting a server-derived metric
    Given starter.finish-level is completed
    When I send POST /api/objectives/events with one soft_currency_spent event, amount 50
    Then the result for the event is "rejected" with reason "metric_not_client_reportable"
    And starter.spend-coins is still "active" with progress 0 of 50

  @edge
  Scenario: The starter plan is done when every starter instance is claimed
    Given every starter instance is "completed"
    When I send POST /api/objectives/claim-all with scope "starter"
    Then every starter instance is "claimed"
    And the response of GET /api/objectives?scope=starter has starter done true
    And the ledger holds grants for the reward lines of all six starter objectives
