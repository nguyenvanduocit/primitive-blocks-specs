Feature: Claim rewards
  As a player
  I want finishing a goal and receiving its reward to be two separate steps
  So that a reward is paid exactly once, and a finished goal is never taken back

  Background:
    Given the app is configured for tenant "tenant-001"
    And the content set from fixtures/definitions.json is published
    And the clock is fixed at "2026-10-21T12:00:00Z"
    And I am authenticated as "acct-001" with timezone "Asia/Ho_Chi_Minh"
    And a fake ledger holds account "acct-001" with balances coins 0 and gems 0
    And every client event for a play metric carries attempt_id "att-confirmed", which the attempt hook reports as "confirmed"
    And the daily instance of daily.win-3 for window "2026-10-21" is "completed" with reward [{ coins: 40 }]

  @happy
  Scenario: Completion pays nothing
    Given the daily instance of daily.win-3 is "active" with progress 2 of 3
    When I send POST /api/objectives/events with one match_won event
    Then daily.win-3 is "completed"
    And the ledger has received no grant
    And the balance of coins is 0

  @happy
  Scenario: A claim grants through the ledger with a deterministic key
    When I send POST /api/objectives/{instance of daily.win-3}/claim
    Then the response status is 200 and the state is "claimed"
    And the ledger received one grant of 40 "coins" with reason "objectives.reward" and source_ref equal to the instance id
    And the idempotency key is "objectives:acct-001:daily.win-3:2026-10-21:0"
    And the balance of coins is 40
    And the response lists the ledger entry id

  @edge
  Scenario: Claiming twice pays once
    Given I have claimed the instance of daily.win-3
    When I send the same claim request again
    Then the response status is 200 and already_claimed is true
    And the balance of coins is still 40
    And the ledger received no second grant call for the instance

  @edge
  Scenario: Two simultaneous claims pay once
    When two devices send the claim request at the same moment
    Then both responses have status 200
    And exactly one of them has already_claimed false
    And the balance of coins is 40

  @error
  Scenario: A claim before completion is refused
    Given the daily instance of daily.win-3 is "active" with progress 2 of 3
    When I send POST /api/objectives/{instance of daily.win-3}/claim
    Then the response status is 409 and the error is "not_completed"
    And the ledger received no grant

  @edge
  Scenario: A claim that lost its answer is safe to retry
    Given the ledger recorded the grant for key "objectives:acct-001:daily.win-3:2026-10-21:0" but the instance is still "completed"
    When I send POST /api/objectives/{instance of daily.win-3}/claim
    Then the response status is 200 and the state is "claimed"
    And the ledger answered the repeated key with the original entry
    And the balance of coins is 40

  @error
  Scenario: A ledger outage leaves the instance claimable
    Given the ledger is unavailable
    When I send POST /api/objectives/{instance of daily.win-3}/claim
    Then the response status is 503 and the error is "ledger_unavailable"
    And the instance is still "completed"
    When the ledger recovers and I send the claim again
    Then the instance is "claimed" and the balance of coins is 40

  @error
  Scenario: A ledger rejection leaves the instance claimable
    Given the ledger rejects the grant with "balance_limit_exceeded"
    When I send POST /api/objectives/{instance of daily.win-3}/claim
    Then the response status is 409 and the error is "ledger_rejected" with reason "balance_limit_exceeded"
    And the instance is still "completed"
    When the ledger accepts grants again and I send the claim again
    Then the instance is "claimed"

  @edge
  Scenario: A reward with several lines pays each line once
    Given the completed instance of a definition with reward [{ coins: 50 }, { booster_small: 1 }]
    When I send the claim request twice
    Then the ledger received two grants with keys ending in ":0" and ":1"
    And the balance of coins is 50 and the count of "booster_small" is 1

  @edge
  Scenario: The reward paid is the snapshot taken at assignment
    Given the case "completed-reward-is-a-snapshot" in fixtures/merge-and-version-cases.json
    When I send the claim request
    Then the ledger grants match the case "expected"

  @edge
  Scenario: A finished goal of a closed window stays claimable
    Given the clock is "2026-10-22T01:00:00Z" and the window "2026-10-21" has closed
    When I send GET /api/objectives
    Then the instance of daily.win-3 for "2026-10-21" is still "completed" and claimable
    When I send the claim request
    Then the state is "claimed" and the balance of coins is 40

  @edge
  Scenario: Claim-all settles the completed instances and skips the rest
    Given three instances are "completed" and two are "active"
    When I send POST /api/objectives/claim-all
    Then the response has three results with state "claimed" and remaining 0
    And the two active instances are unchanged
    And the ledger received one grant per reward line of the three

  @edge
  Scenario: Claim-all stops at CLAIM_ALL_MAX
    Given CLAIM_ALL_MAX is 50 and 51 instances are "completed"
    When I send POST /api/objectives/claim-all
    Then 50 results have state "claimed"
    And the response says remaining 1
    And the 51st instance is still "completed"

  @edge
  Scenario: One failed claim in claim-all does not undo the others
    Given three instances are "completed" and the ledger fails for the second one
    When I send POST /api/objectives/claim-all
    Then the first and third results are "claimed"
    And the second result carries the error "ledger_unavailable" and its instance is still "completed"

  @edge
  Scenario: Claiming resolves the push hand-off
    Given the completion armed an objective_reward_ready hand-off with subject_key "objective:daily.win-3:2026-10-21"
    When I send the claim request
    Then an objective_reward_ready event with the same subject_key and state "resolved" is emitted

  @security
  Scenario: Another account's instance is not found
    Given the completed instance "inst-of-acct-002" belongs to "acct-002"
    When I send POST /api/objectives/inst-of-acct-002/claim
    Then the response status is 404 and the error is "not_found"
    And the ledger received no grant

  @security
  Scenario: The request cannot choose the reward
    When I send POST /api/objectives/{instance of daily.win-3}/claim with the body { "reward": [{ "currency": "gems", "amount": 9999 }] }
    Then the response status is 422 and the error is "invalid_request"
    And the ledger received no grant

  @security
  Scenario: A claim is unavailable without a session
    When I send the claim request without a session
    Then the response status is 401
