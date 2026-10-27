# Acceptance - Daily Streak

Verification checklist Claude Code runs AFTER implementation, BEFORE reporting done. Every item must pass. Tests are generated from the `.feature` files and the JSON fixtures; there is no shipped `tests/` folder, so create the test files in the project's own test framework. Items tagged **[server]** apply to the Streak API and tables, **[client]** to the screens in `frontend.md`, **[core]** to the pure functions. A project without a ledger yet reports which scenarios need the `billing.virtual-currency` contract and runs them against a fake ledger that implements `grant` and `spend` with idempotency keys and `insufficient_balance`.

## Build & Types

- [ ] Type check passes with zero errors (`tsc --noEmit` or the project's equivalent)
- [ ] No `any` types except with an explicit justification comment
- [ ] The pure core (`dayKeyOf`, `dayIndex`, `dayStart`, `dayEnd`, `settle`, `resolveReward`, merge, `applyPendingZone`) has no import of a clock, storage, network or UI framework; each takes `now` or a day key as an argument (INV-10)

## Database [server]

- [ ] Migration runs on a clean database and is idempotent (twice without error)
- [ ] UNIQUE `(tenant_id, account_id)` on `streak_states`; UNIQUE `(tenant_id, account_id, day_key)` on `daily_claims` and `daily_play`; UNIQUE `(tenant_id, account_id, kind, client_request_id)` on `protection_orders` (INV-3)
- [ ] CHECK or equivalent: `current_streak >= 0`, `longest_streak >= current_streak`, `freezes_held >= 0`, enum value sets on `kind`, `grant_status`, `method`, `status`
- [ ] Insert of a second `daily_claims` row for the same account and day fails on the project's dialect
- [ ] `updated_at`, `claimed_at`, `changed_at` are assigned by the server and cannot be supplied by a request (INV-1)

## Pure core [core]

- [ ] Every row of `fixtures/timezone-vectors.json` `instant_to_day_key` returns its `day_key`
- [ ] Every row of `day_bounds` returns `starts_at`, `ends_at` and `hours`, including the 23-hour, 25-hour, 23.5-hour, 24.5-hour days and the zone whose day starts at 01:00 (INV-2)
- [ ] `day_index` values and `consecutive_pairs` differences match, including 2028-02-28 to 2028-03-01 equal to 2
- [ ] Every case in `fixtures/streak-vectors.json` matches `expected` field by field (status, streak fields, `settled_through_day_key`, `freezes_held`, `milestones_granted`, `repair_offer`, `cycle_day`, `reward_lines`, `milestone_ids`, `rows`, `notice`) (INV-8, INV-9, INV-11, INV-12)
- [ ] `settle` run twice at the same `today` returns the same state the second time (INV-10)
- [ ] The merge cases in `fixtures/account-cases.json` match `expected`; merging the result with an empty guest row changes nothing (INV-21)
- [ ] The downtime cases match per-day coverage and `expected`, in both zones (INV-20)
- [ ] The skipped-date vector (`Pacific/Apia`) yields zero missed days and streak 6 (INV-20)
- [ ] The three `timezone_switch` cases return the listed `effective_at`, new-zone date and excused dates (INV-19)
- [ ] Tz-dependent expectations were re-verified against the stack's tz data; a mismatch is reported as an outdated tz database, not a spec change

## Claim [server]

- [ ] `claim.feature` passes, including the concurrent two-device scenario: exactly one `daily_claims` row, one response with `already_claimed` false, one true, one set of ledger entries (INV-3, INV-4, INV-5)
- [ ] The state update carries the `version` predicate in the same transaction as the claim row; a concurrency test with 20 parallel claims yields one row and one reward per line
- [ ] A body containing `day_key`, `date`, `timestamp`, `claimed_at` or `account_id` gives 422 `unexpected_field` and changes nothing (INV-1, INV-22)
- [ ] `play_to_claim` with too little play gives 409 `requirement_not_met` with counts; `open_app` needs none
- [ ] Every event of `fixtures/account-cases.json` `play_counter` returns its `expect` block: `won`, `failed` and `confirmed` attempts count; `open`, `cancelled` and unknown attempts answer `play_not_proven`; a replayed attempt (also on the next day) and a play beyond the cap are not counted (INV-24)
- [ ] A call site of `attemptState` exists in the project's `recordPlay`; with `PLAY_PROOF_SOURCE = event` the report notes that play is not verified
- [ ] An open offer without `repair: "decline"` gives 409 `repair_decision_required` and writes nothing
- [ ] A claim row is committed before any ledger call: kill the process between commit and grant, restart, run the sweep, and find one entry per line (INV-6)
- [ ] Ledger idempotency keys equal `daily-streak:{account_id}:{day_key}:{line_no}` with 1-based positions counting every line; `fixtures/account-cases.json` `pending_grant` matches exactly
- [ ] A permanent ledger rejection sets `failed`, raises an alert, and leaves the streak intact

## Protection [server]

- [ ] `protection.feature` passes
- [ ] A freeze purchase and a paid repair create an order before the spend; a repeated `client_request_id` returns the stored order with one ledger entry (INV-7)
- [ ] `insufficient_balance` ends the order `rejected` with the streak unchanged
- [ ] A repair order that is invalid after the spend ends `refunded` with the `...:refund` key
- [ ] Repair by play makes no ledger call; at 2 of 3 plays it returns 409 `requirement_not_met`
- [ ] The loss sheet flag `loss_prompt.show` turns false after `LOSS_PROMPT_CAP` acknowledgements while `repair_offer` stays present (INV-16)
- [ ] The at-risk sweep emits one `armed` per `subject_key` and a `resolved` after the day is credited; none while protected (INV-17)
- [ ] A loss (reset, decay, expired offer) leaves `freezes_held`, held items and balances untouched and sends the ledger no spend, clawback or revoke; no freeze expires with time (INV-25)
- [ ] The `streak_at_risk` `params` hold only `streak_length`, `freezes_held`, `cycle_day`, `reward_code` and `reward_amount` (INV-26)
- [ ] Startup validation V1 to V5 each fail with their rule id on the configurations listed in `calendar-rewards.feature` and `protection.feature`

## Time zone and clock [server]

- [ ] `timezone-and-clock.feature` passes
- [ ] The first zone set creates the state and is not counted; the rate-limit sequence returns the listed answers and `next_change_at` (INV-19)
- [ ] A requested zone takes effect at `day_end` of the zone in force; the day in progress stays claimable (INV-19)
- [ ] A request with a far-future device clock or `Date` header produces the same `day_key` (INV-1)
- [ ] The sanity guard refuses a claim whose `day_key` is more than one day from the UTC date and raises an alert

## Calendar and rewards

- [ ] `calendar-rewards.feature` passes: cycle wrap, item line through the ledger with the item code as `currency`, `freeze` line applied to the inventory and never sent to the ledger, clipped line stored with `amount` 0 and `capped` true (INV-12, INV-13)
- [ ] A calendar edit after a claim leaves the stored lines and the retry amounts unchanged (INV-13)

## Lifecycle and sweeps [server]

- [ ] `account-lifecycle.feature` passes
- [ ] `holdings`, `mergeAccounts` and `deleteAccount` are not reachable from any client route; `POST /api/streak/merge` and `GET /api/streak/holdings` return 404 (INV-22)
- [ ] `mergeAccounts(from, into, merge_id)` follows `fixtures/account-cases.json` `merge_idempotency`: call 1 `merged`; the same `merge_id` again `already_merged` with no change; a tombstoned guest into another account fails `already_merged`; an unknown guest `nothing_to_merge`; `from = into` `invalid_request` (INV-21)
- [ ] Two concurrent merges with one `merge_id` end with one `merged` and one `already_merged`
- [ ] `holdings` returns the lists in `fixtures/account-cases.json` `holdings`, empty for no state and for a tombstone
- [ ] After `deleteAccount`, queries find zero rows for the account in all five tables, a merge tombstone included (INV-23)
- [ ] Pruning claims older than `CLAIM_RETENTION_DAYS` does not change `current_streak` or `longest_streak`
- [ ] Sweeps process bounded batches and use `FOR UPDATE SKIP LOCKED` or an equivalent so two sweepers never deliver the same claim twice with different keys

## API [server]

- [ ] Every route in `backend.md` rejects an unauthenticated request with 401
- [ ] Error bodies are `{ error, ... }` with no stack trace; every status in the Errors table is reachable by a test
- [ ] Every success body carries `server_now` and, where a day is shown, an absolute `ends_at`
- [ ] No request log contains request bodies, reward lines, balances or the time-zone identifier

## Screens [client]

- [ ] Every screen in `frontend.md` has a rendering or component test for each listed state (loading, offline, error, already-claimed where listed)
- [ ] A test changes the device clock and shows that no claim, loss or reward changes; the countdown is recomputed from `ends_at` and `server_now`
- [ ] The loss sheet shows the free options before or beside any paid option, with equal weight, and no paid option is pre-selected (INV-15)
- [ ] Every currency price of a freeze or a repair shows the `ApproxMoney` equivalent beside it (guide 15 check S1)
- [ ] Reminder copy (banner and push templates) names the waiting reward and the true end time and contains no loss wording (INV-26; guide 15 check S2)
- [ ] Color is not the only carrier of calendar tile state; claim and offline results reach a live region; the celebration respects reduced motion
- [ ] Analytics events fire with the properties in `README.md` section 6 and no more; no reward lines or zone identifiers appear in client events other than the listed ones

## Configuration

- [ ] Every key in `README.md` section 7 is exposed with its listed default
- [ ] A configuration that violates V1 to V5 refuses to start
- [ ] Defaults marked "design choice" are listed in the project's report as untested for retention effect

## Ethics review

- [ ] The owner records answers to the three tests of guide `06-design-ethics-and-compliance.md` (decision rule 2) for the shipped copy and defaults: would the player still choose it when shown exactly how it works and what it costs, does it work through obligation or through enjoyment, is the audience likely to include children
- [ ] For a child-directed or mixed audience, both price pairs are `null`
- [ ] The owner ticks the three daily-streak checks of guide 15 (`kits/game-engagement/guides/15-manipulation-and-the-line.md`): S1 a missed day is recoverable without paying and any paid repair is optional and priced in money terms, S2 reminder copy names a benefit, S3 a lost streak never removes purchased items

## Block-specific criteria

- [ ] Every INV-1 to INV-26 in `README.md` section 8 maps to at least one passing test; the report lists the mapping
- [ ] The report lists which parts could not be run on the project's stack and why
- [ ] **3-Stack mental test** (`docs/SPEC_GUIDELINES.md` section 7), the author's answers, not run on any stack: (1) data model: five tables with logical types `unique_id`, `external_id`, `text_short`, `integer`, `json`, `id_list`, `enum`, `timestamp` map on Postgres, MySQL and SQLite; `id_list` and `json` are JSON text where there is no array type - yes. (2) Snippets: the `Intl`-based day helpers differ per stack's tz library and the ADAPT lines name the replacements; the compare-and-swap is a version predicate that every dialect supports; SQLite writers serialize through a write transaction - yes. (3) External contract: the only external facts are the IANA identifier format and the ledger contract of the kit, both concrete - yes. (4) Sequence flows depend on a transaction, a unique constraint and an idempotent ledger, not on a framework feature - yes. (5) Acceptance: every item is checkable with a SQL database, a fake ledger, a controllable clock and a tz database; tz data version differences are called out - yes.
