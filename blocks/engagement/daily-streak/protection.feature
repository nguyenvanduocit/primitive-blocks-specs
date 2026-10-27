Feature: Streak freeze and streak repair
  As a player
  I want protection I can earn by playing and a free way back after a loss
  So that missing a day never forces me to pay

  Background:
    Given the app is configured for tenant "tenant-001"
    And the calendar and settings from fixtures/calendar-config.json
    And the clock is fixed at "2026-10-27T12:00:00Z"
    And account "acc-ann" is authenticated with timezone "Etc/UTC"

  @happy
  Scenario: A freeze is earned by claiming cycle day 7
    Given the case "milestone-7-first-time" state_before is stored
    When I send POST /api/streak/claim with an empty body
    Then freezes_held is 1
    And a streak_freeze_earned event with source "calendar" is emitted

  @happy
  Scenario: A freeze purchase spends once and survives a retry
    Given FREEZE_PRICE_CURRENCY is "coin" and FREEZE_PRICE_AMOUNT is 120
    And "acc-ann" has 0 freezes and 500 coins
    When I send POST /api/streak/freeze with { "client_request_id": "req-001" }
    Then the ledger received spend("acc-ann", "coin", 120, "daily-streak.freeze-purchase", <order id>, "daily-streak:acc-ann:<order id>")
    And freezes_held is 1 and the order status is "completed"
    When I send the same request with "client_request_id" "req-001" again
    Then the response returns the same order and the ledger holds one spend entry

  @edge
  Scenario: A purchase with too little balance changes nothing
    Given FREEZE_PRICE_AMOUNT is 120 and "acc-ann" has 50 coins
    When I send POST /api/streak/freeze with { "client_request_id": "req-002" }
    Then the response status is 409 with error "insufficient_balance"
    And the order status is "rejected" and freezes_held is unchanged

  @edge
  Scenario: A freeze purchase at the cap is refused before any spend
    Given "acc-ann" holds 2 freezes and FREEZE_CAP is 2
    When I send POST /api/streak/freeze with { "client_request_id": "req-003" }
    Then the response status is 409 with error "freeze_cap_reached"
    And the ledger received no spend

  @edge
  Scenario: A freeze is not sold when no price is configured
    Given FREEZE_PRICE_AMOUNT is null
    When I send POST /api/streak/freeze with { "client_request_id": "req-004" }
    Then the response status is 404 with error "not_purchasable"

  @happy
  Scenario: Repair by play restores the streak for free
    Given the case "repair-two-days-keeps-freeze" state_before is stored
    And "acc-ann" has 3 qualifying "level_complete" actions today
    When I send POST /api/streak/repair with { "method": "play", "client_request_id": "req-005" }
    Then the result matches the case expected block
    And the ledger received no call and the order has method "play" and status "completed"

  @edge
  Scenario: Repair by play needs the full target
    Given the case "repair-one-day" state_before is stored with MISS_POLICY "reset"
    And "acc-ann" has 2 qualifying "level_complete" actions today
    When I send POST /api/streak/repair with { "method": "play", "client_request_id": "req-006" }
    Then the response status is 409 with error "requirement_not_met" and play_count 2
    And the streak is still lost and the offer is still open

  @happy
  Scenario: Repair by currency charges per missed day
    Given REPAIR_PRICE_CURRENCY is "coin" and REPAIR_PRICE_PER_MISSED_DAY is 40
    And the case "repair-two-days-keeps-freeze" state_before is stored and "acc-ann" has 200 coins
    When I send POST /api/streak/repair with { "method": "currency", "client_request_id": "req-007" }
    Then the ledger received spend("acc-ann", "coin", 80, "daily-streak.repair-purchase", <order id>, "daily-streak:acc-ann:<order id>")
    And current_streak is 8 and the order missed_day_keys are ["2026-10-25", "2026-10-26"]

  @edge
  Scenario: A repair that is invalid after the spend is refunded
    Given a paid repair order is pending after a successful spend of 80 coins
    And the offer expired before the apply step
    When the recovery sweep completes the order
    Then the ledger received grant("acc-ann", "coin", 80, "daily-streak.repair-refund", <order id>, "daily-streak:acc-ann:<order id>:refund")
    And the order status is "refunded" and the streak is unchanged

  @edge
  Scenario: Starting over is free and ends the offer
    Given the case "missed-one-day-reset-offer" state_before is stored
    When I send POST /api/streak/claim with { "repair": "decline" }
    Then the result matches the case "missed-one-day-reset-decline" expected block
    And no ledger spend occurred

  @edge
  Scenario: The claim is held while an offer is open
    Given the case "missed-one-day-reset-offer" state_before is stored
    When I send POST /api/streak/claim with an empty body
    Then the response status is 409 with error "repair_decision_required" and the offer in the body
    And no claim row exists

  @edge
  Scenario: The proactive loss sheet is shown at most LOSS_PROMPT_CAP times
    Given LOSS_PROMPT_CAP is 1 and an offer is open
    When I send GET /api/streak
    Then loss_prompt.show is true
    When I send POST /api/streak/ack with { "kind": "loss_prompt" }
    And I send GET /api/streak
    Then loss_prompt.show is false and repair_offer is still present

  @edge
  Scenario: The reminder hand-off fires once and is resolved by the claim
    Given "acc-ann" has a streak of 6 with streak_deadline_at "2026-10-27T23:00:00Z" and no freeze
    When the at-risk sweep runs at "2026-10-27T20:00:00Z" twice
    Then exactly one streak_at_risk event exists with state "armed", subject_key "streak:2026-10-27", expires_at "2026-10-27T23:00:00Z" and params streak_length 6, freezes_held 0, cycle_day 7, reward_code "coin" and reward_amount 500
    When "acc-ann" claims today
    Then a streak_at_risk event with state "resolved" and the same subject_key is emitted

  @security
  Scenario: Reminder variables name the reward and never a loss
    Given the at-risk sweep emits an armed event for "acc-ann"
    Then params contains only streak_length, freezes_held, cycle_day, reward_code and reward_amount
    And the frontend reminder copy states the waiting reward and the true end time, with no loss wording

  @security
  Scenario: A lost streak removes nothing that was bought or earned
    Given the case "freeze-insufficient-all-or-nothing" state_before is stored
    And "acc-ann" bought one freeze with 120 coins and holds the item "avatar-frame-gold" from a milestone
    When I send POST /api/streak/claim with { "repair": "decline" }
    Then freezes_held is still 1 and no freeze is removed or expired
    And the ledger received no spend, no clawback and no revoke from this block
    And the item "avatar-frame-gold" is still held

  @edge
  Scenario: No reminder while a freeze protects the streak
    Given "acc-ann" has a streak of 6 and 1 freeze under MISS_POLICY "freeze_protected"
    And AT_RISK_WHEN_PROTECTED is false
    When the at-risk sweep runs three hours before the day ends
    Then no streak_at_risk event is emitted

  @security
  Scenario: A paid-only repair configuration is refused at startup
    Given REPAIR_PRICE_PER_MISSED_DAY is 40 and REPAIR_PLAY_TARGET is 0
    When the service starts
    Then startup fails with rule "V2"

  @security
  Scenario: Two identical repair requests charge once
    Given the case "repair-one-day" state_before is stored with MISS_POLICY "reset"
    And REPAIR_PRICE_PER_MISSED_DAY is 40 and "acc-ann" has 200 coins
    When two POST /api/streak/repair requests with the same client_request_id "req-008" arrive at the same instant
    Then the ledger holds one spend of 40 coins and one order exists
