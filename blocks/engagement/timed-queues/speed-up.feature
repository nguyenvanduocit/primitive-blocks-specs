Feature: Speed-ups, quotes and the price function
  As a player
  I want to see the price of skipping time before I pay and never be charged more than I saw
  So that a speed-up is a choice I can predict and the free path stays open

  Background:
    Given the app is configured for tenant "tenant-001"
    And the definition set and configuration from fixtures/catalog.json are published
    And account "acct-001" is signed in with timezone "Asia/Ho_Chi_Minh"
    And the preset items and wallet of fixtures/price-vectors.json exist
    And SPEEDUP_CURVE is [[3600,20],[86400,260],[604800,1000]] with FREE_FINISH_SECONDS 300 and QUOTE_TTL_SECONDS 60
    And the clock is fixed at "2026-10-21T12:00:00Z"

  @happy
  Scenario: A quote set shows the finish price and the price per step
    When I request quotes for running item "item-run-1"
    Then remaining_seconds is 7200
    And the "finish" quote costs 31 "gems" and the "step" quote of 3600 seconds costs 11 "gems"
    And both quotes are valid until "2026-10-21T12:01:00Z" and none is free
    And the "finish" quote shows ends_at_after "2026-10-21T12:00:00Z" and the "step" quote "2026-10-21T13:00:00Z"
    And the quotes carry no money figure and no reference product
    # fixture: fixtures/price-vectors.json case "quote-two-modes"

  @happy
  Scenario: The charge is never more than the quote and falls as time passes
    Given I hold a "finish" quote of 21 "gems" for item "item-run-2" issued at "2026-10-21T12:00:00Z"
    And the clock is fixed at "2026-10-21T12:01:00Z"
    When I spend against the quote with attempt "su-010"
    Then the current price is 20 and the response has quoted 21 and charged 20
    And the ledger received a spend of 20 "gems" with reason "timed-queues.speed-up"
    And the item is ready and the "gems" balance is 80
    # fixture: fixtures/price-vectors.json case "charge-is-lower-than-quote"

  @edge
  Scenario: An expired quote never charges and returns a fresh one
    Given I hold a "finish" quote for item "item-run-2" issued at "2026-10-21T12:00:00Z"
    And the clock is fixed at "2026-10-21T12:01:01Z"
    When I spend against the quote with attempt "su-011"
    Then the response error is "quote_expired" with a fresh "finish" quote of 20 "gems" valid until "2026-10-21T12:02:01Z"
    And the ledger received no call and the "gems" balance is 100

  @edge
  Scenario: A quote is stale after another device changed the item
    Given I hold a quote set for item "item-run-1" issued at "2026-10-21T12:00:00Z"
    And at "2026-10-21T12:00:30Z" the tablet applied the 3600-second step and the item ends at "2026-10-21T13:00:00Z"
    And the clock is fixed at "2026-10-21T12:00:40Z"
    When the phone spends against its "finish" quote
    Then the response error is "quote_stale" with a fresh "finish" quote of 20 "gems" for 3560 seconds
    And no step quote is offered because 3600 seconds is not shorter than the remainder
    And the ledger received no call

  @edge
  Scenario: A new curve cannot raise the price of an open quote
    Given I hold a "finish" quote of 21 "gems" for item "item-run-2" issued at "2026-10-21T12:00:00Z"
    And at "2026-10-21T12:00:30Z" the operator publishes SPEEDUP_CURVE [[3600,40],[86400,520],[604800,2000]] with a cap of 40
    And the clock is fixed at "2026-10-21T12:00:40Z"
    When I spend against the quote
    Then the price under the new curve is 41 and the charge is 21
    And quotes requested after the change use the new curve

  @happy
  Scenario: A remainder at or below the free threshold finishes for free
    When I request quotes for running item "item-run-3"
    Then the "finish" quote is free with price 0
    When I spend against it
    Then the ledger received no call and a time reduction with source "free_finish" is recorded
    And the item is ready

  @edge
  Scenario: One second above the free threshold costs the rounded-up price
    Given the clock is fixed at "2026-10-21T11:59:59Z"
    When I request quotes for running item "item-run-3"
    Then remaining_seconds is 301 and the "finish" quote costs 2 "gems" and is not free

  @edge
  Scenario Outline: The price function rounds up to a whole unit
    Then price_raw for <remaining> remaining seconds is <price>
    And finish_price for <remaining> remaining seconds is <finish>

    Examples:
      | remaining | price | finish |
      | 301       | 2     | 2      |
      | 600       | 4     | 4      |
      | 1800      | 10    | 10     |
      | 3600      | 20    | 20     |
      | 3601      | 21    | 21     |
      | 7200      | 31    | 31     |
      | 14400     | 52    | 52     |
      | 86400     | 260   | 260    |
      | 172800    | 384   | 384    |
      | 604800    | 1000  | 1000   |
      | 300       | 2     | 0      |
    # fixture: fixtures/price-vectors.json "price_vectors"

  @edge
  Scenario Outline: Steps telescope so partial skips never cost more in total than finishing
    Then the step price for <remaining> seconds with a step of 3600 is <step>
    And the step price plus the finish price after the step equals the finish price at the start

    Examples:
      | remaining | step |
      | 5400      | 16   |
      | 7200      | 11   |
      | 14400     | 11   |
      | 43200     | 10   |
      | 86400     | 10   |
      | 172800    | 5    |
    # fixture: fixtures/price-vectors.json "step_vectors"

  @edge
  Scenario: The price never decreases with remaining time and stays under the per-hour bound
    When price_raw is evaluated for every whole second from 1 to 604800
    Then the price never decreases as remaining time grows
    And for every remaining time r the price is below r divided by 3600 times 20 plus 1

  @happy
  Scenario: Time items remove time without a quote and never more than needed
    Given the wallet holds 2 "speedup_1h"
    When I use item "speedup_1h" with max_count 5 on item "item-run-1"
    Then used is 2 and seconds_applied is 7200
    And the ledger received a spend of 2 "speedup_1h" with reason "timed-queues.speed-up"
    And the item is ready and the "speedup_1h" balance is 0
    # fixture: fixtures/price-vectors.json "time_item_cases"

  @edge
  Scenario: One time item removes one hour from a longer wait
    Given the wallet holds 2 "speedup_1h"
    When I use item "speedup_1h" with max_count 1 on item "item-run-1"
    Then used is 1 and the item ends at "2026-10-21T13:00:00Z" and is still running

  @edge
  Scenario: The count consumed never exceeds the count needed
    Given the clock is fixed at "2026-10-21T12:30:00Z" and item "item-run-1" ends at "2026-10-21T13:30:00Z"
    And the wallet holds 2 "speedup_1h"
    When I use item "speedup_1h" with max_count 5
    Then used is 1 and the "speedup_1h" balance is 1

  @edge
  Scenario: A short balance returns the exact shortfall and releases the quote
    Given the wallet holds 10 "gems"
    And I hold a "finish" quote of 31 "gems" for item "item-run-1"
    When I spend against the quote
    Then the response error is "insufficient_balance" with needed 31, balance 10 and shortfall 21
    And the reduction is rejected and the quote is not consumed
    And the item is still running

  @edge
  Scenario: A queued item cannot be sped up
    When I request quotes for queued item "item-queued-1"
    Then the response error is "item_not_running" and nothing is charged

  @edge
  Scenario: A speed-up that finishes an item moves its followers earlier and re-arms them
    Given item "item-0001" runs until "2026-10-21T12:15:00Z" and item "item-0002" is queued behind it until "2026-10-21T12:30:00Z"
    And the clock is fixed at "2026-10-21T12:06:00Z"
    When I spend against a "finish" quote of 3 "gems" for item "item-0001"
    Then item "item-0001" is ready at "2026-10-21T12:06:00Z" and item "item-0002" runs from "2026-10-21T12:06:00Z" to "2026-10-21T12:21:00Z"
    And the hand-off for "queue-item:item-0001" is resolved and "queue-item:item-0002" is armed again with revision 2
    And no ends_at moved later
    # fixture: fixtures/lifecycle-cases.json case "speed-up-shifts-the-chain"

  @edge
  Scenario: A speed-up request that is repeated returns the original reduction
    Given I spent against a quote with attempt "su-020"
    When I send the same speed-up with attempt "su-020"
    Then the response has replayed true and the same charged amount
    And the ledger received no second call

  @edge
  Scenario: The item finished or was cancelled between the spend and the apply
    Given the ledger spend for a speed-up succeeded
    And the item was cancelled on another device before the reduction was applied
    When the reduction is applied
    Then the spend is granted back with reason "timed-queues.cancel-refund"
    And the reduction is "refunded" and the response error is "item_not_running"

  @edge
  Scenario: Paid speed-ups are off for a flagged minor and free options remain
    Given account "acct-001" is flagged as a minor and PAID_SPEEDUP_FOR_MINORS is false
    When I request quotes for running item "item-run-1"
    Then no paid quote is offered
    And spending on a paid mode answers "paid_speedup_disabled"
    And time items remain usable and a free finish remains available at or below 300 seconds

  @edge
  Scenario Outline: A curve that breaks the price rules is not published
    When the operator publishes SPEEDUP_CURVE <anchors> with a cap of 20
    Then publishing fails with "<error>" and the previous set stays active

    Examples:
      | anchors                               | error                 |
      | [[3600,25],[86400,260],[604800,1000]] | curve_slope_over_cap  |
      | [[3600,20],[86400,10],[604800,1000]]  | curve_not_monotone    |
      | [[3600,20]]                           | curve_too_short       |
      | [[3600,20.5]]                         | curve_not_integer     |

  @edge
  Scenario Outline: Every price in a purchasable currency carries the shared ApproxMoney component
    Given the speed-up sheet shows a row priced in "<currency>"
    And the reference price is <reference>
    Then the row renders ApproxMoney "<shown>" beside the price
    And the sheet computes no money figure of its own
    And the paid row stays usable

    Examples:
      | currency | reference   | shown   |
      | gems     | available   | visible |
      | gems     | unavailable | hidden, with a "pack prices" link |
      | coins    | not needed  | hidden  |

  @security
  Scenario: A quote cannot be used by another account or on another item
    Given account "acct-002" holds a quote for its own item
    When account "acct-001" spends against that quote id
    Then the response error is "quote_invalid" and nothing is charged
    When account "acct-001" spends its quote for "item-run-1" against "item-run-2"
    Then the response error is "quote_invalid"

  @security
  Scenario: The client cannot name its own price
    When I send a speed-up with a body that also carries "price" or "amount"
    Then the response error is "unexpected_field" and nothing is charged

  @security
  Scenario Outline: Counts that are not positive integers are refused
    When I use item "speedup_1h" with max_count <count> on item "item-run-1"
    Then the response error is "invalid_request" and the ledger received no call

    Examples:
      | count |
      | 0     |
      | -1    |
      | 1.5   |
      | "3"   |
