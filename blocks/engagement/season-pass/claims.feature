Feature: Claiming tier rewards
  As a player
  I want each earned reward delivered exactly once, however I tap or retry
  So that a dropped connection, a second device or a race never loses or doubles a reward

  Background:
    Given the app is configured for tenant "tenant-001"
    And the season from fixtures/season-2026-10.json is published
    And the players from fixtures/progress-states.json exist
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario: Claiming one cell grants it through the ledger
    Given I am authenticated as "acc-ann"
    When I send POST /api/season-pass/claims with { "season_id": "season-2026-10", "items": [{ "track": "free", "tier": 3 }] }
    Then the response status is 200
    And the result for free tier 3 is "granted" with reward { "code": "coin", "amount": 150 }
    And the ledger received grant(acc-ann, coin, 150, "season-pass.tier-reward", "season-2026-10:free:3", "season-pass:acc-ann:season-2026-10:free:3")
    And the tier_claims row for free tier 3 is "granted" with claim_source "player"

  @happy
  Scenario: Claim-all delivers every claimable cell in tier order
    Given I am authenticated as "acc-ann"
    When I send POST /api/season-pass/claims with { "season_id": "season-2026-10", "all": true }
    Then the results are, in order, free tier 3 "granted" (coin 150), free tier 4 "granted" (hint-pack 1), free tier 5 "granted" (coin 200)
    And three ledger grants were made with reason "season-pass.tier-reward"
    And every claim row has claim_source "claim_all"
    And the claimable list in the response is empty

  @happy
  Scenario: A premium holder claims the premium cells already reached
    Given I am authenticated as "acc-bob"
    When I send POST /api/season-pass/claims with { "season_id": "season-2026-10", "all": true }
    Then the results are premium tier 4 (frame-oct 1), tier 5 (gem 15), tier 6 (coin 300), tier 7 (gem 15), all "granted"
    And no free-track cell is granted again

  @edge
  Scenario: Claiming the same cell again is already claimed and changes nothing
    Given I am authenticated as "acc-ann"
    And I claimed free tier 3 once
    When I send the same claim request again
    Then the result for free tier 3 is "already_claimed"
    And exactly one ledger entry exists for the key "season-pass:acc-ann:season-2026-10:free:3"
    And the response status is 200

  @edge
  Scenario: Two simultaneous claims of one cell produce one ledger entry
    Given I am authenticated as "acc-ann"
    When two requests claim free tier 4 at the same instant
    Then exactly one ledger entry exists for the key "season-pass:acc-ann:season-2026-10:free:4"
    And one tier_claims row exists for free tier 4
    And each response result is "granted" or "already_claimed"

  @edge
  Scenario: A crash between the ledger grant and the confirmation is completed by the retry
    Given I am authenticated as "acc-ann"
    And the process stops after the ledger applied the grant for free tier 3 and before the claim row was marked "granted"
    Then the tier_claims row for free tier 3 is "pending"
    When I send the claim for free tier 3 again
    Then the ledger replays the original result and no second entry exists
    And the claim row is "granted" with the original entry_id

  @edge
  Scenario: A ledger outage leaves a cell pending and does not stop the others
    Given I am authenticated as "acc-ann"
    And the ledger fails every call for the key "season-pass:acc-ann:season-2026-10:free:4"
    When I send a claim-all request
    Then the result for free tier 4 is "rejected" with reason "ledger_unavailable"
    And free tiers 3 and 5 are "granted"
    And the tier_claims row for free tier 4 is "pending"
    When the ledger recovers and the reconcile job runs after PENDING_RECONCILE_SECONDS
    Then the claim row for free tier 4 is "granted"

  @edge
  Scenario Outline: A cell that fails the claim rules is rejected without a row
    Given I am authenticated as "acc-ann"
    When I claim <track> tier <tier>
    Then the result is "rejected" with reason "<reason>"
    And no tier_claims row is created
    And no ledger call is made

    Examples:
      | track   | tier | reason           | note                                       |
      | free    | 7    | tier_not_reached | acc-ann is on tier 5                       |
      | free    | 2    | no_reward        | tier 2 has no free reward                  |
      | premium | 1    | premium_required | acc-ann has not bought premium             |
      | free    | 11   | tier_not_reached | repeat tier 11 needs total_xp 2300         |

  @edge
  Scenario: Repeat tiers continue the numbering and use the repeat reward
    Given I am authenticated as "acc-fay"
    When I claim premium tier 11
    Then the result is "granted" with reward { "code": "gem", "amount": 25 }
    And the ledger key is "season-pass:acc-fay:season-2026-10:premium:11"
    When I claim free tier 11
    Then the result is "rejected" with reason "no_reward"

  @edge
  Scenario: Claim-all covers the defined and repeat tiers
    Given I am authenticated as "acc-fay"
    When I send a claim-all request
    Then 19 cells are "granted": 7 free, 10 premium and 2 repeat premium
    And the fixture breakdown in progress-states.json matches

  @edge
  Scenario: Claim-all with nothing claimable makes no ledger call
    Given I am authenticated as "acc-bob"
    And every claimable cell of "acc-bob" was claimed
    When I send a claim-all request
    Then the results list is empty
    And no ledger call is made

  @edge
  Scenario: Another device sees a claimed cell as already claimed, not as an error
    Given I am authenticated as "acc-ann" on device A and device B
    And device A claimed free tier 5
    When device B, which still shows it claimable, claims free tier 5
    Then the result is "already_claimed"
    And device B shows the cell as claimed without a second reward animation

  @edge
  Scenario: Merging a guest account keeps every claim once and grants nothing
    Given "acc-guest" and "acc-ann" are as in fixtures/progress-states.json
    When mergeAccounts("acc-guest", "acc-ann", "merge-001") runs
    Then "acc-ann" has total_xp 1050 and tier 6
    And exactly one claim row exists for free tier 1 and it is "granted"
    And the merge makes no ledger call
    And free tiers 3, 4 and 5 are claimable
    And one account_merges row exists for from_account_id "acc-guest"

  @edge
  Scenario: A repeated merge id returns the first result and changes nothing
    Given mergeAccounts("acc-guest", "acc-ann", "merge-001") ran once
    When mergeAccounts("acc-guest", "acc-ann", "merge-001") runs again
    Then the result equals the stored result of the first call
    And total_xp of "acc-ann" is still 1050
    And no row changed

  @edge
  Scenario: A guest cannot be merged into a second account
    Given mergeAccounts("acc-guest", "acc-ann", "merge-001") ran once
    When mergeAccounts("acc-guest", "acc-bob", "merge-002") runs
    Then the error is "already_merged"
    And "acc-bob" is unchanged

  @edge
  Scenario: A merge completes the guest's pending rows before it re-keys anything
    Given the tier_claims row for free tier 3 of "acc-guest" is "pending" and the ledger fails its key
    When mergeAccounts("acc-guest", "acc-ann", "merge-003") runs
    Then the error is "pending_unresolved"
    And no season_progress row changed and no account_merges row exists
    When the ledger recovers and mergeAccounts("acc-guest", "acc-ann", "merge-003") runs again
    Then the pending claim is "granted" before the rows move and the merge succeeds

  @edge
  Scenario: Merging into an ended season settles it again
    Given the clock is fixed at "2026-11-01T00:05:00Z"
    And the settlement job ran for "season-2026-10" and settled_at of "acc-ann" is set
    When mergeAccounts("acc-guest", "acc-ann", "merge-004") runs
    Then settled_at of "acc-ann" is cleared
    And settlement runs again for "acc-ann" and every ledger key still has exactly one entry

  @edge
  Scenario: Two active premiums from different transactions keep the target's reference
    Given "acc-guest" has premium through "txn-1002" and "acc-bob" has premium through "txn-1001"
    When mergeAccounts("acc-guest", "acc-bob", "merge-005") runs
    Then premium_purchase_ref of "acc-bob" is still "txn-1001"
    And an operations alert is raised for the duplicate purchase "txn-1002"

  @happy
  Scenario: Holdings list what a merge would carry
    When holdings("acc-bob") is asked
    Then the list is [ { "category": "progress", "label_key": "season-pass.progress", "paid": false, "effect": "carried" }, { "category": "purchases", "label_key": "season-pass.premium", "paid": true, "effect": "carried" } ]
    When holdings("acc-dee") is asked
    Then the list is empty

  @edge
  Scenario: Deleting an account removes its season rows and is safe to repeat
    When deleteAccount("acc-bob") runs
    Then no season_progress, xp_events, tier_claims, season_purchases or account_merges row names "acc-bob"
    When deleteAccount("acc-bob") runs again
    Then it succeeds and changes nothing
    And a later refund signal for "txn-1001" finds no progress row and does nothing

  @security
  Scenario: The lifecycle operations are not reachable from a player route
    Given I am authenticated as "acc-ann"
    When I send POST /api/season-pass/merge with { "from_account_id": "acc-guest", "merge_id": "merge-009" }
    Then the response status is 404
    And no season_progress row changed

  @edge
  Scenario: A season the player never took part in does not exist for them
    Given I am authenticated as "acc-dee"
    When I send GET /api/season-pass/seasons/season-2026-10
    Then the response status is 404
    And the error is "season_not_found"

  @security
  Scenario: A claim body cannot name another account
    Given I am authenticated as "acc-ann"
    When I send POST /api/season-pass/claims with { "season_id": "season-2026-10", "account_id": "acc-bob", "items": [{ "track": "premium", "tier": 4 }] }
    Then the response status is 422
    And the error is "invalid_request"
    And no ledger call is made

  @security
  Scenario: A client-sent premium flag decides nothing
    Given I am authenticated as "acc-ann"
    When I send POST /api/season-pass/claims with { "season_id": "season-2026-10", "premium_state": "active", "items": [{ "track": "premium", "tier": 1 }] }
    Then the response status is 422
    When I claim premium tier 1 with a valid body
    Then the result is "rejected" with reason "premium_required"

  @security
  Scenario: Claiming needs a session
    When I send POST /api/season-pass/claims without a session
    Then the response status is 401
    And the error is "unauthorized"
