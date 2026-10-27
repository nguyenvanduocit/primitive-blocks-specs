# Acceptance — Energy and Lives

Verification checklist Claude Code runs AFTER implementation, BEFORE reporting done. Every item must pass. Tests are generated from the `.feature` files and the JSON fixtures; there is no shipped `tests/` folder, so create the test files in the project's own test framework. Items tagged **[server]** apply to the API and tables, **[client]** to the shell UI, **[ledger]** to the integration with `billing.virtual-currency` (use a fake ledger that honors the contract if the real block is not built yet), **[optional]** to the gift extension.

## Build & Types

- [ ] Type check passes with zero errors (`tsc --noEmit` or the project's equivalent)
- [ ] No `any` types except with an explicit justification comment
- [ ] The pure core (`advance`, `spend`, `credit`, `settleDue`, projections) imports nothing from the HTTP framework, the database, the ledger client or the clock; it takes `now` as an argument
- [ ] `rg` finds no `setInterval`, scheduler, cron or queue worker that writes to `energy_meters` (INV-1)

## Database [server]

- [ ] Migration runs on a clean database and twice without error
- [ ] UNIQUE (`tenant_id`, `account_id`, `meter_code`) on `energy_meters`; UNIQUE (`tenant_id`, `account_id`, `attempt_id`) on `energy_attempts`; UNIQUE (`tenant_id`, `account_id`, `idempotency_key`) on `energy_entries`; UNIQUE (`tenant_id`, `meter_code`, `version`) on `energy_meter_configs`
- [ ] `value >= 0` is a CHECK on `energy_meters`
- [ ] `energy_meter_configs` has no UPDATE or DELETE path in application code (`rg` for writes to the table finds only INSERT)
- [ ] Timestamps are written by the server; no request field reaches any `*_at` column

## Pure core [server]

- [ ] Every case in `fixtures/regen-cases.json` returns exactly `expect` for value, anchor, `next_tick_at`, `full_at` (INV-1, INV-10)
- [ ] Property test: for random stored meters, versions and times `t1 <= t2`, `advance(advance(m, t1), t2)` equals `advance(m, t2)` (INV-2)
- [ ] Property test: with a single version the value never exceeds `max(cap, stored value)` and never decreases without a spend
- [ ] A read that completes no tick performs no write
- [ ] All scenarios in `lazy-regeneration.feature` pass

## Attempts [server]

- [ ] Every case in `fixtures/api-cases.json` whose id starts with `start-`, `on-fail-`, `last-unit-`, `cancel-`, `refund-`, `unconfirmed-`, `boost-makes`, `daily-refund`, `abandoned-` returns the listed status and body fields (INV-4, INV-5, INV-6)
- [ ] A concurrency test with two simultaneous starts on value 1 yields exactly one 201 and one 409, for `on_start` and `on_fail`, on the project's database (INV-4)
- [ ] A start at value 0 stores no attempt row
- [ ] Settlement of a due attempt uses its due instant: the abandoned lives case ends with value 4 and `next_tick_at` "2026-10-21T13:30:01Z" whether it is read at 13:06:40 or later (INV-3)
- [ ] A refund restores at most `charged`, within `max(cap, value_before)`, once, within the daily limit (INV-6)
- [ ] `attemptState` accepts only `confirmed`, `won`, `failed` as proof of play; a reward-paying block in the project calls it (list the call sites in the report) (INV-13)
- [ ] All scenarios in `attempt-spend.feature` pass

## Refills, grants, boosts [server] [ledger]

- [ ] The ledger is called through its contract only: `spend(account_id, currency, amount, 'energy-lives.refill', source_ref, idempotency_key)`; no balance is written by this block
- [ ] The only `reason` values sent to the ledger are `energy-lives.refill` (spend) and `energy-lives.refill-refund` (grant); `rg` over the ledger client calls finds no other; `energy-lives.ad-refill`, `energy-lives.gift`, `energy-lives.start-refund` and `energy-lives.merge` appear only as labels on `energy_entries`
- [ ] Same meter state, different spend history: two accounts get identical offers, costs, `next_tick_at` and `full_at`; `rg` finds no read of purchases, spend totals or segments in the quote, the config lookup or the empty-sheet code (INV-18)
- [ ] `publishMeterConfig` refuses a body with `account_id`, `segment` or any field outside the version columns; `energy_meter_configs` has no account column
- [ ] `refill-to-full`, `refill-price-changed`, `refill-when-full`, `refill-insufficient-balance`, `refill-crash-after-spend` pass; the ledger fake shows exactly one spend per `refill_id` (INV-7)
- [ ] The pending entry is committed before the ledger call; killing the process between the spend and the credit and replaying leaves one spend and one credit
- [ ] A pending entry is re-driven by `GET /api/energy`, at most `REDRIVE_MAX_PER_READ` per read
- [ ] `grant-above-ceiling-reports-the-rest`, `boost-stacks-additively`, `boost-stack-limit`, `paid-boost-stacks` pass (INV-8, INV-9)
- [ ] A repeated `idempotency_key` returns the original `applied_amount`, `unapplied_amount` and `balance` (the stored `value_after`)
- [ ] With `is_minor` true and `PAID_REFILL_FOR_MINORS` false: offers are `not_for_minors`, a refill is 403 `refill_not_available`, no ledger call (INV-16)
- [ ] All scenarios in `refill-paths.feature` pass

## Rewarded-ad contract [server]

- [ ] The ad route verifies the ECDSA SHA-256 signature over the query text before `&signature=`, exactly as received, with the key for `key_id`; keys are refreshed at least every 24 hours
- [ ] `ad-valid` grants once; `ad-forged-signature` and `ad-unknown-user` grant nothing; a repeated valid callback grants once; the sixth grant of a `day_key` is `daily_limit`
- [ ] Units come from `AD_GRANT_UNITS`; `reward_amount` is never read
- [ ] No client route grants an ad reward
- [ ] The report names what could not be verified: the signature encoding of `signature` against the network's current page, and the network's response rules

## Config versions [server]

- [ ] Publishing with `effective_at` in the past is refused; editing a version is impossible (INV-10)
- [ ] All scenarios in `config-change.feature` pass; every expected value equals the matching `regen-cases.json` case
- [ ] No per-player migration or job runs when a version is published

## Offline, clock and merge [server]

- [ ] `offline-queue-accepted` and `offline-queue-overdraft` pass; a rejected id stays rejected; a client-supplied start time is ignored
- [ ] With `OFFLINE_ATTEMPTS` false the reconcile route is 409 `offline_attempts_disabled`
- [ ] A request carrying `X-Client-Time` or `client_ts` far in the future gives the same result as one without (INV-12)
- [ ] With the server clock stepped back, no value decreases and no timer lengthens (`now-before-anchor`)
- [ ] `merge-takes-the-higher-value` passes; merge is never a sum; a replay with the same `merge_id` changes nothing (INV-11)
- [ ] All scenarios in `offline-and-clock.feature` and `account-merge.feature` pass

## Events [server] [client]

- [ ] The server writes `energy_spent`, `energy_attempt_cancelled`, `energy_refilled`, `energy_offline_reconciled` in the same transaction as the state change; the client writes `energy_empty_shown`, `energy_sheet_action`, `energy_refill_confirm_shown`, `energy_refill_failed`; names and properties equal README section 6
- [ ] Every event carries the shared envelope including `event_id` and `schema_version`
- [ ] `energy_full` is written to the outbox in the same transaction as the meter write with `subject_key` `energy:{meter_code}:{cycle_started_at epoch seconds}`, `state` `armed` or `resolved`, `fire_at`, `expires_at`, `params`; the block never calls the push block
- [ ] A spend from a full meter emits `armed`; a later spend re-emits `armed` with the same `subject_key` and a later `fire_at`; a bought refill to the cap emits `resolved`; regeneration to the cap emits nothing
- [ ] The client emits the same `energy_full` fields on its event bus after every response, with `fire_at` taken from the server's `full_at`

## Frontend [client]

- [ ] `rg` finds no code that adds to `value` or compares the device wall clock with `next_tick_at`; countdowns use the monotonic clock and `server_now`
- [ ] The countdown reaching zero shows "Checking..." and triggers one refresh; the value changes only from the response
- [ ] Returning from background refreshes before a countdown is shown as current
- [ ] HUD states loading, regenerating, full, empty, overflow, boost, offline, error each render as specified in `frontend.md`
- [ ] The empty sheet opens only from a player action; free rows precede paid rows; Close has the same visual weight as a paid action; no countdown or urgency styling on offers
- [ ] The refill sheet shows cost, currency and balance after; `expected_cost` equals the displayed cost; a changed price needs a new tap
- [ ] A start that failed to open shows the refunded message only when the refund applied
- [ ] `attempt_id` and `refill_id` persist in device storage and are reused on retry; `resume()` runs at app start
- [ ] No "ask a friend for energy" control exists
- [ ] The ticking countdown is not a live region; discrete changes are announced through one polite status element; touch targets are at least 24 by 24 CSS pixels; motion respects `prefers-reduced-motion`

## Security

- [ ] Threat model items T-1 to T-11 in `security.md` each have the listed mitigation implemented or an explicit decision recorded in the report
- [ ] A request for another account's attempt id is 404; a body `account_id` is ignored (A-1, A-2)
- [ ] The client's `expected_cost` can only stop a charge; no client field sets a price, unit count, ceiling or duration (A-3)
- [ ] The 11th refund of a day is refused with `refund_denied` (T-3) and the residual risk of T-3 is stated in the report for this project's level delivery
- [ ] 60 reads in a minute write nothing; the 61st is 429 with `retry_after_seconds`
- [ ] No secret in client bundles, fixtures or logs; ad callback signatures are not logged with their full query

## Configuration

- [ ] Every key in README section 7 is exposed as configuration or a documented constant with the listed default
- [ ] A publication tool prints `cap / regen_amount * regen_interval_seconds` (the longest free wait) for the approver (INV-15)
- [ ] Optional gift extension built only when `GIFTS_ENABLED`; its rules in `backend.md` pass `[optional]` scenarios

## Ethical review (answered in the report, not machine-checked)

- [ ] The waiting path is complete: with no payment and no ad the longest wait equals the printed lint value and the empty sheet states it (INV-15)
- [ ] Which softeners from the README table are on, and which are off with the reason
- [ ] The team can answer from analytics what share of paid refills and of first purchases follow `energy_empty_shown`, and has a stated reason why energy is not the only thing players pay for (guide 03, guide 06). No threshold is prescribed: no source in this kit gives one
- [ ] Minors: how `is_minor` is decided in this project (guide 06, interview 4)

## Block-specific criteria

- [ ] Every INV-1 .. INV-18 in README section 8 maps to at least one passing test; list the mapping in the report
- [ ] Items that could not be run on the project's stack are listed with the reason
- [ ] **3-Stack mental test** (`docs/SPEC_GUIDELINES.md` section 7), author's answers, not run on any stack: (1) data model: five tables with logical types `unique_id`, `external_id`, `text_short`, `integer`, `timestamp`, `boolean`, `enum` all map on Postgres, MySQL and SQLite; partial indexes need a plain-index substitute on MySQL (listed in the ADAPT lines) - yes; (2) snippets: the pure core is plain TypeScript with no runtime API beyond `Date.parse`; the compare-and-swap UPDATE differs only in placeholders and the rows-affected accessor; the ad verification snippet differs in the signature API (Node `crypto`, Web Crypto with DER conversion, Tink) and its ADAPT says so - yes; (3) external contracts: the AdMob parameters and signature rule are concrete and cited, the ledger contract is concrete, the signature encoding is flagged as unverified - yes with that flag; (4) sequence flow: nothing depends on a framework feature; atomicity is a row lock or compare-and-swap, both stated - yes; (5) acceptance: every item is checkable with a SQL database, a fake ledger and a fake clock - yes
