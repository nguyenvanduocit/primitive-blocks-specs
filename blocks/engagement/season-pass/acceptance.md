# Acceptance — Season Pass

Verification checklist Claude Code runs AFTER implementation, BEFORE reporting done. Every item must pass. Items marked **(option)** apply only if that option is enabled in the project's configuration; items marked **(manual, store console)** cannot be checked from code and go into the report as "needs manual setup".

## Build & Types

- [ ] The project's type check passes with zero errors
- [ ] The ledger client and the purchase-record client are imported only from their adapter files, never from handlers' pure functions
- [ ] No `any` types except with an explicit justification comment

## Data model

- [ ] The seven migrations (`season_definitions`, `season_tiers`, `season_progress`, `xp_events`, `tier_claims`, `season_purchases`, `account_merges`) run on a clean database and are idempotent
- [ ] UNIQUE constraints exist exactly as listed in `README.md` section 2: (`tenant_id`, `season_id`); (`season_definition_id`, `tier`); (`tenant_id`, `account_id`, `season_definition_id`); (`tenant_id`, `premium_purchase_ref`) where not null; (`tenant_id`, `account_id`, `event_id`); (`tenant_id`, `account_id`, `source`, `attempt_id`) where not null; the 5-column UNIQUE on `tier_claims`; (`tenant_id`, `account_id`, `dedupe_key`) on `season_purchases`; (`tenant_id`, `merge_id`) and (`tenant_id`, `from_account_id`) on `account_merges`
- [ ] No column stores the tier, the claimable set or `xp_into_tier`
- [ ] Postgres only: the EXCLUDE constraint rejects an overlapping published interval; on other dialects the publish transaction performs the equivalent check (`clock-and-season-definition.feature`)
- [ ] `fixtures/season-2026-10.json`, `progress-states.json`, `xp-event-cases.json` and `purchase-records.json` load as test data without edits

## Pure core

- [ ] `tierFor` matches every vector in `fixtures/season-2026-10.json` `tier_derivation_cases`, including the repeat tiers and the final tier 15
- [ ] `xp_into_tier` and `xp_for_next_tier` match the same vectors (0 and null at the final tier)
- [ ] `applyCaps` names the cap with the smallest remaining allowance and breaks ties in the order `source_daily`, `source_season`, `total_daily`
- [ ] `catchUpXp` matches every vector in `catch_up_cases` using integer arithmetic
- [ ] `claimable` returns cells in ascending tier order, free before premium, and counts a `pending` claim row as claimed
- [ ] The pure functions take instants as arguments and read no clock

## XP ingestion

- [ ] Every case in `fixtures/xp-event-cases.json` produces its `expect` block
- [ ] A replayed `event_id` returns the first answer and writes no row, including after the first answer was a capped zero
- [ ] Cap check, boost and booking run in one transaction under the progress-row lock; a concurrency test with two events that together exceed a cap credits exactly the cap
- [ ] The caller cannot send an amount, a season, a day or a boost; each is rejected with `invalid_event`
- [ ] A source with `requires_attempt` accepts only an attempt that `attemptState` reports as `confirmed`, `won` or `failed` (every other state and an unknown id are `attempt_not_proven`); the attempt id is present exactly when the source requires it; one attempt credits one source once per account (INV-23)
- [ ] A replay of a booked event returns its first answer without calling `attemptState`
- [ ] `occurred_at` older than `INGEST_MAX_EVENT_AGE_SECONDS` is `event_too_old`
- [ ] The internal endpoint answers `unauthorized` without the service credential and is not reachable with a player session
- [ ] `no_active_season` is returned with status 200 and books nothing
- [ ] `day_key` is computed on the server from the account's timezone (UTC when unset)
- [ ] **(option)** `CATCH_UP_PERCENT` above 0 books the `catch-up:{season_id}` row once, before the triggering event

## Claims

- [ ] One cell, claim-all and settlement all go through the single `claimCell` path
- [ ] The ledger call uses reason `season-pass.tier-reward` and the key `season-pass:{account_id}:{season_id}:{track}:{tier}`
- [ ] Two simultaneous claims of one cell produce one ledger entry and one claim row
- [ ] A crash between the grant and the confirmation leaves a `pending` row that the next claim, the settlement, the read path or the reconcile job completes without a second entry
- [ ] A ledger outage on one cell leaves it `pending` and does not stop the others in claim-all
- [ ] The four claim rules run in order and a rejected cell creates no row and makes no ledger call
- [ ] Repeat tiers continue the numbering and use the repeat reward; a null repeat reward on a track yields `no_reward`
- [ ] A request body with `account_id`, `tenant_id` or `premium_state` is rejected with `invalid_request`
- [ ] The merge of a guest account keeps every claim once and makes no ledger call

## Premium and refunds

- [ ] Activation reads `purchase_record` and checks state, account, season by `purchased_at`, product and the unused reference, in that order
- [ ] Activation grants nothing and clears `settled_at`; every premium reward of a reached tier is claimable afterwards (INV-10)
- [ ] `premium_already_active` is returned for a second transaction and raises an alert
- [ ] A purchase recorded after `claim_until` is delivered by settlement even under `forfeit` (INV-11)
- [ ] `sync_premium_state` makes `premium_state` follow the record, is idempotent, and handles refund and reversal
- [ ] `REFUND_POLICY = keep_claimed` leaves claimed rewards and balances untouched
- [ ] **(option)** `REFUND_POLICY = claw_back_unspent` spends `min(balance, reward)` with the `:clawback` key, retries once on `insufficient_balance` with the same key, never goes below zero, and re-grants with the `:restore` key on reversal
- [ ] The recheck job re-reads every active premium row of a running season every `PREMIUM_RECHECK_SECONDS`
- [ ] The premium-offer response lists both tracks in full (every tier's free and premium reward and the repeat rewards of both) and contains no price
- [ ] The offer carries no "worth", "value" or "save" figure unless `PREMIUM_VALUE_FIGURE` is on, and then the figure is computed from prices the shop charges, lists unsold rewards as not sold separately, and returns no reference price (INV-26)

## Skips and boosts

- [ ] The quote matches the fixture: tier 5 to 7 for 2 tiers is 450 XP for 80 gem
- [ ] A request whose `price_shown` differs from the server price is `price_changed` with the fresh quote and no ledger call
- [ ] The purchase row is written `pending` before the spend; an `insufficient_balance` marks it `failed` and clears `dedupe_key`
- [ ] A repeated request completes the same purchase; a different `count` is `purchase_conflict`
- [ ] Skip XP is booked as an `xp_events` row with source `tier_skip` and is not reduced by caps or increased by a boost
- [ ] A boost is rejected when it would end after `ends_at` (an end exactly at `ends_at` is allowed) or when one is running
- [ ] The boost window is half-open: applied at 11:59:59 of its last second, not at its end instant
- [ ] **(option)** skips off when `TIER_SKIP_PRICE` is unset; `TIER_SKIP_REQUIRES_PREMIUM` enforced

## End of season and clock

- [ ] Every boundary row of the phase table in `clock-and-season-definition.feature` passes
- [ ] Settlement is idempotent, resumable by pages and order-independent with player claims
- [ ] A read after `ends_at` settles the caller first
- [ ] A claim names its season and is evaluated against that season's window and table after rollover
- [ ] `UNCLAIMED_AT_END = auto_claim` delivers every earned, eligible reward; **(option)** `forfeit` delivers nothing after `claim_until` and the results list the forfeited cells
- [ ] No endpoint, field or header lets a client choose the season, the clock or the policy
- [ ] The publish validations reject each bad draft in `clock-and-season-definition.feature`; a published season cannot be edited
- [ ] Two active seasons produce `season_config_error` and credit nothing

## Account lifecycle and season window

- [ ] `holdings`, `mergeAccounts(from_account_id, into_account_id, merge_id)` and `deleteAccount(account_id)` are registered as the season pass's participant of `auth.guest-account`; none is reachable from a player route
- [ ] `holdings` returns the progress and premium entries described in `README.md` section 3 and an empty list for an account with nothing
- [ ] `mergeAccounts` is idempotent by `merge_id`, returns the stored first result on a repeat, fails `already_merged` for a second target, completes the guest's pending rows first (`pending_unresolved` otherwise), grants nothing, deletes no claim, sums `total_xp`, keeps the target's row on a collision, and clears `settled_at`
- [ ] `deleteAccount` removes the account's rows in the four per-account tables and the `account_merges` rows naming it, and is safe to repeat
- [ ] `season_definitions` is the only source of `starts_at` and `ends_at`; no code path reads `engagement.event-calendar`; a `season_ref` from the calendar changes nothing here (INV-24)

## Ledger and purchase-contract integration

- [ ] The flows `season-pass.tier-reward`, `season-pass.refund-restore` (faucets) and `season-pass.tier-skip`, `season-pass.xp-boost`, `season-pass.refund-clawback` (sinks) are registered with the ledger for every currency used; a write with an unregistered reason is rejected by the ledger and the publish validation catches unknown reward codes first
- [ ] No code path in this block writes a balance
- [ ] No code path in this block calls a store API or verifies a receipt
- [ ] The premium product exists in the `store_products` catalog of `billing.virtual-currency` with `fulfilment = external` **(manual, store console)**

## Frontend

- [ ] The pass screen derives every cell view from the server answer; no tier or claimability is computed from XP on the device
- [ ] The countdown uses `server_now` and `ends_at`; at zero the client reloads and marks nothing
- [ ] Offline shows the cached pass read-only with the absolute end time and disabled write controls
- [ ] The premium sheet lists every premium reward, the store price string, the end date, the unclaimed-rewards line for the configured policy, the refund line for the configured policy, the one-time-purchase line and, for a guest, the account line
- [ ] No price constant for premium exists in the client
- [ ] Skip and boost sheets show price, effect and balance after, with a separate confirm control labelled with the price; a `price_changed` is never retried automatically
- [ ] The ending-soon banner appears only inside `ENDING_SOON_WINDOW_SECONDS`, carries the policy line, offers no purchase and is dismissible per season
- [ ] The results screen lists delivered rewards, labels auto-claimed ones, and lists forfeited ones under `forfeit`
- [ ] The premium sheet never opens at launch or after a claim
- [ ] Controls have names that include their state; state is never color alone; sheets trap and return focus
- [ ] The client events in `README.md` section 6 fire once per action

## Security

- [ ] The service credential is read from secrets configuration, compared in constant time, and absent from logs and client bundles
- [ ] Every query filters by the session's tenant and account
- [ ] A player cannot read another account's progress or learn whether it exists (`season_not_found`)
- [ ] Logs hold error codes and ids, not receipts or credentials
- [ ] Account erasure deletes the account's rows in all four per-account tables

## Tests

- [ ] Unit tests pass for `tierFor`, `applyCaps`, `catchUpXp`, `claimable`, the cell view and the countdown
- [ ] Integration tests pass for every scenario in the six `.feature` files, using a fake ledger, a fake purchase-record client and a fake `attemptState`
- [ ] At least one test kills the process between the ledger call and the confirmation for a claim and for a skip
- [ ] At least one concurrency test claims one cell from two requests and one test sends two events that together exceed a cap

## Configuration

- [ ] Every key in `README.md` section 7 exists as named configuration with the documented default, including `requires_attempt` on every `XP_SOURCES` entry and `PREMIUM_VALUE_FIGURE` false
- [ ] The app starts with `TIER_SKIP_PRICE` and `XP_BOOST_CATALOG` unset (skips and boosts off) and with `CATCH_UP_PERCENT` 0
- [ ] `CATCH_UP_PERCENT` above 50 fails at start-up
- [ ] `XP_EVENT_RETENTION_DAYS` is not below `INGEST_MAX_EVENT_AGE_SECONDS`
- [ ] The report lists every manual step left (store console items above) and every `Assumption:` made

## 3-Stack mental test

This is a mental test, not a run: no stack has executed this block.

| Question (`docs/SPEC_GUIDELINES.md` section 7) | Stack A: Node 20, Express, Postgres, Drizzle | Stack B: Bun, Hono, SQLite | Stack C: Deno, Oak, Postgres, Prisma |
|---|---|---|---|
| 1. Data model maps on all dialects | `uuid`, `timestamptz`, `jsonb`, CHECK enums as in the migration | `TEXT` ids and ISO timestamps, `TEXT` JSON, CHECK enums, nulls distinct in UNIQUE | as A; Prisma needs the EXCLUDE constraint as a raw migration |
| 2. Snippets have equivalents | row lock by `SELECT ... FOR UPDATE` | single-writer transaction serializes | as A |
| 3. External contracts are concrete | store signals and ledger contract are named and cited | same | same |
| 4. Flows do not depend on one framework | handlers are plain functions over the transaction | same | same |
| 5. Acceptance is verifiable on all three | integration tests with fakes; concurrency test needs two connections on A and C and two overlapping transactions on B | yes | yes |

The one stack-specific construct is the overlap guard: Postgres enforces it in the database; SQLite and MySQL enforce it inside the publish transaction (`README.md` migration notes).
