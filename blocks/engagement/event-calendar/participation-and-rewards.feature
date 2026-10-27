Feature: Participation and exactly-once rewards
  As a player
  I want every reward I earn to arrive once, however I claim it and whatever fails along the way
  So that I can trust the event and the economy stays intact

  Background:
    Given the app is configured for tenant "tenant-001"
    And the events from fixtures/events.json are published
    And the accounts from fixtures/accounts.json exist
    And the cases in fixtures/rewards-and-participation.json are loaded
    And the clock is fixed at "2026-10-27T12:00:00Z"

  @happy
  Scenario: Joining an opt-in event is idempotent
    When acc-ann sends POST /api/events/evt-weekly-sprint-w44/join
    And acc-ann sends POST /api/events/evt-weekly-sprint-w44/join again
    Then both responses have status 200 and the same joined_at
    And one participation row exists

  @edge
  Scenario: An opt-in event refuses progress before a join
    When the case "opt-in-event-needs-a-join" runs
    Then the response status is 409
    And the response error is "not_joined"
    And no entry exists for acc-ben

  @happy
  Scenario: An auto event joins the player at the first progress and pays an auto milestone
    When acc-ann reports progress 1 to "evt-daily-1027" with source_ref "level-complete:lv-9:attempt-1"
    Then the response status is 200
    And acc-ann has joined "evt-daily-1027"
    And the ledger received grant(acc-ann, "coins", 20, "event-calendar.reward") with idempotency key "event-calendar:acc-ann:evt-daily-1027:win-1:coins"

  @happy
  Scenario: Crossing an auto milestone records the claim and pays through the ledger
    When the case "crosses-m1" runs
    Then progress is 120
    And a claim for "m1" exists with status "granted" and grant_path "milestone_auto"
    And the ledger received exactly the grants listed in the case

  @happy
  Scenario: A manual milestone is earned and not paid
    When the case "manual-milestone-is-earned-not-paid" runs
    Then a claim for "m2" exists with status "earned"
    And the ledger received no grant

  @edge
  Scenario: Progress stops at the cap
    When the case "progress-is-capped" runs
    Then progress is 600
    And applied_amount is 40
    And capped is true
    And a claim for "m3" exists with status "earned"

  @edge
  Scenario: A repeated source_ref counts once
    When the case "same-source-ref-counts-once" runs
    Then the second response has duplicate true
    And progress is 150
    And the ledger received no grant

  @security
  Scenario: An increment above the per-call bound is refused
    When the case "increment-above-the-per-call-bound" runs
    Then the response status is 422
    And the response error is "invalid_progress"
    And progress is 0

  @security
  Scenario: Client progress calls are rate limited
    When acc-ann sends 61 progress requests within one minute
    Then the 61st response has status 429 and the error "rate_limited"

  @happy
  Scenario: A manual claim pays every grant line once
    When the case "manual-claim-grants-every-line-once" runs
    Then the claim for "m2" has status "granted" and grant_path "player_claim"
    And the ledger received the two grants in the case with their idempotency keys

  @security
  Scenario: A replayed and a parallel claim pay once
    Given the claim for "m2" of acc-ann is "earned"
    When acc-ann sends the same claim request twice at the same time
    Then both responses have status 200 and the same ledger entry ids
    And the ledger applied each grant line once
    When acc-ann sends the claim request again
    Then the response status is 200 and the ledger has no new effect

  @edge
  Scenario: Claiming a reward that is not earned is refused
    When the case "claim-before-earning" runs
    Then the response status is 409
    And the response error is "reward_not_earned"

  @edge
  Scenario: A ledger outage leaves the claim earned and the retry uses the same key
    When the case "ledger-unavailable-then-recovers" runs
    Then the first response has status 503 and the error "grant_pending"
    And the claim status is "earned" with attempts 1
    And after the retry the claim status is "granted" with attempts 2
    And both ledger calls carried the same idempotency key

  @edge
  Scenario: A ledger answer that is not an applied grant is not recorded as granted
    Given the ledger answers { "applied": false } for the grant
    When the grant worker pays the claim
    Then the claim stays "earned"
    And attempts increases by 1

  @edge
  Scenario: A crash after the ledger call and before the status update is repaired without a second grant
    Given the ledger applied the grant for "m1" of acc-ann and the process stopped before the claim was marked granted
    When the grant worker runs
    Then the ledger returns the original result for the same idempotency key
    And the claim becomes "granted" and the balance changed once

  @happy
  Scenario: Settlement at the end instant creates the end-of-event claims once
    When the case "settlement-at-the-end-instant" runs
    Then the claims match the case for acc-ann, acc-ben and acc-cara
    And acc-cara is marked settled with no claims
    When settlement runs a second time
    Then no claim row is added and the ledger receives no call

  @edge
  Scenario Outline: Manual rewards are granted by the sweep when the claim grace ends
    Given the claim for "m2" of acc-ann is "earned" and was never claimed
    When the clock is fixed at "<at>" and the grant worker runs
    Then the claim status is "<status>"

    Examples:
      | at                   | status  |
      | 2026-11-04T23:59:59Z | earned  |
      | 2026-11-05T00:00:00Z | granted |

  @edge
  Scenario: The sweep uses the same idempotency key as a claim
    Given acc-ann claimed "m2" on a second device a moment before the sweep
    When the sweep runs
    Then the ledger has one grant line per currency for "m2" and the claim has one grant_path

  @edge
  Scenario: A write at the end instant is refused and a trusted late report inside the grace is accepted
    Given PROGRESS_GRACE_SECONDS is 300
    When the cases in time-cases.json "trusted_late_progress" run
    Then each result matches its row
    And settlement does not start before "2026-11-02T00:05:00Z"

  @edge
  Scenario: A guest account merges into a signed-in account without a second grant
    When mergeAccounts(acc-guest-9, acc-ann, "merge-0001") runs for the case "guest-into-signed-in"
    Then progress is 220
    And the claim for "m1" is "granted" with grant_path "milestone_auto"
    And the ledger receives no new call
    And no participation row remains for acc-guest-9
    And the result is { "events_moved": 0, "events_merged": 1, "claims_kept": 0, "claims_moved": 1 }

  @edge
  Scenario: A repeated merge returns the first result and changes nothing
    Given mergeAccounts(acc-guest-9, acc-ann, "merge-0001") has run
    When mergeAccounts(acc-guest-9, acc-ann, "merge-0001") runs again
    Then the stored result is returned
    And no row changes and the ledger receives no call

  @security
  Scenario: A guest is merged once
    Given mergeAccounts(acc-guest-9, acc-ann, "merge-0001") has run
    When mergeAccounts(acc-guest-9, acc-ben, "merge-0002") runs
    Then it fails with "already_merged"
    And acc-ben has no participation row from acc-guest-9

  @edge
  Scenario: A guest row moves to an account that has no row
    When the case "guest-moves-into-an-account-without-a-row" runs
    Then acc-ben has progress 100 and the claim for "m1" is "granted"
    And the ledger receives no call

  @security
  Scenario: Equal unpaid claims on both sides leave one row and no second grant
    When the case "unpaid-claim-moves-and-an-equal-claim-on-the-target-wins" runs
    Then one claim row for "m2" exists on acc-ann with status "earned"
    And a later claim or the sweep pays it once

  @happy
  Scenario Outline: Holdings list what the account holds in a stable order
    When holdings is called for the case "<case>"
    Then the list equals the expected list in fixtures/rewards-and-participation.json
    And every entry has paid false and effect "carried"

    Examples:
      | case                                    |
      | progress-only                           |
      | unpaid-rewards-add-currency-and-items   |
      | nothing-held                            |

  @security
  Scenario: deleteAccount erases everything and is safe to repeat
    When deleteAccount(acc-ann) runs
    Then no participation, progress entry, claim or merge record remains for acc-ann
    And the ledger entries are untouched
    And the armed event_ending_soon hand-offs of acc-ann are resolved
    When deleteAccount(acc-ann) runs again
    Then it succeeds and changes nothing

  @happy
  Scenario: A joined player is armed for the ending-soon notice
    Given acc-ann joins "evt-weekly-sprint-w44"
    Then the outbox holds an event_ending_soon with state "armed" for acc-ann
    And its subject_key is "event:evt-weekly-sprint-w44", fire_at is "2026-11-01T00:00:00Z" and expires_at is "2026-11-02T00:00:00Z"
    And a player who never joined has no such event

  @edge
  Scenario: Reaching every milestone resolves the notice
    Given acc-ann has an armed event_ending_soon for "evt-weekly-sprint-w44"
    When acc-ann reaches progress 600
    Then the outbox holds an event_ending_soon with state "resolved" and the same subject_key
