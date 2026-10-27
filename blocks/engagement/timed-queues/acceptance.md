# Acceptance: Timed Queues

Verification checklist Claude Code runs AFTER implementation, BEFORE reporting done. Every item must pass. Tests are generated from the `.feature` files and the JSON fixtures; there is no shipped `tests/` folder, so create the test files in the project's own test framework. Items tagged **[server]** need the database and a ledger fake or the real `billing.virtual-currency`; **[core]** items run on the pure functions with no I/O; **[client]** items need the client shell.

The fixtures are deterministic: the fixed clock is `2026-10-21T12:00:00Z`, the account is `acct-001` (timezone `Asia/Ho_Chi_Minh`), and item ids are assigned in creation order (`item-0001`, `item-0002`).

## Build and types

- [ ] Type check passes with zero errors (`tsc --noEmit` or the project's equivalent)
- [ ] No `any` types except with an explicit justification comment
- [ ] The pure core (`effectiveState`, `remainingSeconds`, `reschedule`, `priceRaw`, `priceFinish`, `priceStep`, `refundLines`, `planStart`, `nudgeEligible`, `quoteFor`, `chargeFor`) imports no clock, storage, network or UI framework; each takes `now` and rows as arguments (INV-2)
- [ ] Price arithmetic uses integer operations only; no floating division followed by a ceiling

## Database [server]

- [ ] Migration runs on a clean database and is idempotent (twice without error)
- [ ] UNIQUE `(tenant_id, account_id, queue_id)` on `queue_states`; UNIQUE `(tenant_id, account_id, attempt_id)` on `queue_items` and on `time_reductions`; UNIQUE `(tenant_id, account_id, queue_id, slot_index)` and UNIQUE `(tenant_id, store_transaction_id)` on `slot_unlocks`; UNIQUE `(tenant_id, merge_id)` on `merge_log`; UNIQUE `(tenant_id, queue_id, definition_version)` and `(tenant_id, job_id, definition_version)` on the definition tables
- [ ] CHECK or equivalent: `slot_index >= 0`, `duration_seconds >= 1`, `price_amount >= 0`, `cancel_refund_fraction` within 0 and 1, the enum value sets of `state`, `input_status` (including `refund_pending` and `refunded`), `collect_status`, `cancel_reason`, `source`, `status`
- [ ] A second `queue_items` row with the same account and `attempt_id` fails on the project's dialect
- [ ] `starts_at`, `ends_at`, `reserved_at`, `issued_at`, `valid_until` and `updated_at` are assigned by the server and cannot be supplied by a request (INV-1)
- [ ] The five `currency_flows` rows of README section 6 exist before the first ledger call (`timed-queues.start`, `.speed-up`, `.slot-unlock` as sinks; `.collect`, `.cancel-refund` as faucets)

## Pure core [core]

- [ ] `effectiveState` returns `queued` for a row with null times, `queued` before `starts_at`, `running` between, `ready` at and after `ends_at`, and returns `collected` and `cancelled` unchanged (README section 3)
- [ ] `priceRaw` and `priceFinish` reproduce every row of `fixtures/price-vectors.json` `price_vectors`; `priceStep` reproduces `step_vectors`; the sweep over every whole second from 1 to 604800 never decreases and stays below `r / 3600 * 20 + 1` (INV-11)
- [ ] For every `r` above the free threshold and `s` below `r`, `priceStep(r, s) + priceRaw(r - s) = priceRaw(r)` (INV-13)
- [ ] `reschedule` never returns a later `startsAt` or `endsAt` than its input, for a cancel, a finish, a rebase and an empty predecessor (INV-10)
- [ ] `refundLines` returns `floor(amount * fraction)` per line and fraction 1 for a queued item (INV-16)
- [ ] `chargeFor` returns `min(quote, current price)` while `now <= valid_until` (inclusive) and a refusal after it
- [ ] `nudgeEligible` returns the first failing check in the order of README section 3 (`no_idle_slot`, `nothing_affordable`, `suppressed`, `per_open`, `per_day`, `gap`)
- [ ] A validator rejects every set in `fixtures/catalog.json` `invalid_definitions` and every curve in `fixtures/price-vectors.json` `invalid_curves` with the listed error, and accepts the published set

## API and flows [server]

- [ ] Every route of `backend.md` section 2 exists and takes `account_id` and `tenant_id` only from the session; a body carrying either, or any time, price or duration field, answers `unexpected_field` (INV-1, INV-23)
- [ ] Every case of `fixtures/lifecycle-cases.json` passes with the listed ledger calls, keys, balances, times and hand-off events; a case that lists `ledger: []` makes no ledger call
- [ ] Every case of `fixtures/price-vectors.json` `quote_cases` and `time_item_cases` passes, including the charge that is lower than the quote, the expired quote, the stale quote, the new curve that cannot raise an open quote, the free finish at 300 seconds, and the flagged minor
- [ ] Every case of `fixtures/account-cases.json` `slot_cases`, `nudge_cases`, `handoff_cases`, `clock_cases` and `erasure_cases` passes
- [ ] Start: reserve before spend; a failure after an earlier line returns the earlier lines with the `start-undo` key; a replay of a failed attempt returns the same refusal; one start in flight per account and queue (INV-5, INV-6)
- [ ] Collect: `collected` is set only after every line is applied; a replay returns `already_collected`; a refused grant leaves the item `ready` with `collect_status = blocked_cap` and no output lost (INV-7, INV-8)
- [ ] Speed-up: only a running item; the reduction row is written before the ledger call; a spend whose item finished or was cancelled before the apply is granted back and the reduction is `refunded`
- [ ] Recovery sweep: finishes rows in `input_status = pending` or `refund_pending`, `collect_status = pending` and `time_reductions.status = pending` with the original keys; a pending row older than `RECOVERY_ALERT_MINUTES` raises an alert
- [ ] A read endpoint writes only a first-time progression slot row (INV-2)
- [ ] `holdings`, `mergeAccounts` (idempotent by `merge_id`, `merge_blocked_pending` while rows are pending) and `deleteAccount` (six tables, safe to repeat) follow `auth.guest-account` section 3.7

## Behavior (from the .feature files)

| Feature file | Covers | Key invariants |
|---|---|---|
| `start-item.feature` | Start, replay and conflict, two-device race, crash recovery, unlock rules, stacked time, ready cap, locked slot, request hygiene | INV-3 to INV-6, INV-9, INV-23 |
| `collect-and-lifecycle.feature` | Lazy completion, settle on write, collect once, collect-all, blocked cap, partial collect resume, effect lines, invalid transitions, no expiry, no penalty | INV-1, INV-2, INV-7, INV-8, INV-19 |
| `speed-up.feature` | Quote set, charge at most the quote, expired and stale quotes, new curve, free finish, price vectors, steps, time items, chain shift, minors, curve validation | INV-10 to INV-15, INV-17 |
| `slots-and-purchase.feature` | Progression, currency and store unlocks, order, refund revoke, reinstall, non-paying path, product validation | INV-17, INV-21 |
| `cancel-and-config-change.feature` | Cancel refund rules, snapshot, lengthen, rebase, retire, validation | INV-9, INV-10, INV-16 |
| `handoff-nudge-and-clock.feature` | `queue_item_ready` shape and lifecycle, nudge caps, clock handling, merge, holdings, erasure | INV-1, INV-20, INV-22, INV-25 |

- [ ] Every scenario tagged `@happy`, `@edge` or `@security` has a corresponding test that passes
- [ ] Each scenario with a `# fixture:` comment reads the named case from the fixture and asserts its `expect` block

## Ethical floor [server] [client]

- [ ] No job in the published set has a premium currency in `input` (V3); a test publishes one and sees `premium_input`
- [ ] Every queue has at least one base slot, and every input currency has an enabled faucet in the ledger registry (V4)
- [ ] A job's `duration_seconds` on an item equals the snapshot of its definition minus the account's own reductions; a test changes balance, spend history, payer status and time of day and sees no effect (INV-18)
- [ ] The speed-up curve passes V5 and every segment's slope is at most `SPEEDUP_PRICE_PER_HOUR_CAP`
- [ ] The charge never exceeds the quote in any test (INV-12)
- [ ] No `ends_at` moves later in any test, including cancel, finish, rebase and merge (INV-10)
- [ ] An idle slot, a full queue and an item left uncollected for a long time change no counter and lose no output (INV-19)
- [ ] The nudge never appears more than `IDLE_NUDGE_PER_DAY` times per account day, never more than once per open, and stops after `IDLE_NUDGE_DISMISS_LIMIT` dismissals in a row; it is never a modal, push or badge (INV-20)
- [ ] Paid speed-ups are refused for a flagged minor when `PAID_SPEEDUP_FOR_MINORS` is false, and the free options remain

## Frontend [client]

- [ ] The countdown uses `server_now` and `ends_at` with a monotonic timer; changing the device clock in a test does not move it; reaching zero triggers a refresh and never shows `ready` locally
- [ ] The start sheet shows time, cost with the player's balance, output, and the cancel terms as a percentage taken from the same response; no premium currency appears there
- [ ] The speed-up sheet shows waiting as an option with the same weight as the paid rows, the free finish when eligible, the time items with the count to be used, the price per step, `ApproxMoney` beside every price in a purchasable currency, and the balance after; the sheet computes no money figure; `ApproxMoney` is hidden for a soft currency and when the reference price is unavailable, and the paid rows stay usable
- [ ] A refreshed quote with a higher price shows "price updated" and needs a new tap; a lower or equal price updates silently; the success line shows the charged amount
- [ ] The cancel sheet states the refund, that elapsed time is not returned and, when sped up, that speed-ups are not returned; "Keep it going" and "Cancel item" have equal weight
- [ ] The completion toast appears once per refresh batch, never auto-collects, and persists for screen-reader users
- [ ] The unlock sheet lists every option with free options first, shows the store's price string (no price constant in the app), a "Restore purchases" control for a store product, and the refund consequence; no countdown, no preselected option
- [ ] Offline: cached state labelled as saved, countdowns dimmed, every money or reward action disabled with "Connect to ..."; nothing queued for later
- [ ] The client emits `queue_item_ready` for every `armed` and `resolved` entry after each response and replays `armed[]` on start and resume
- [ ] Accessibility: labelled regions per slot card, no per-second live announcements, state never by color alone, minimum touch targets, dialog focus management

## Security [server]

- [ ] Another account's item, quote or slot answers `item_not_found` or `quote_invalid`, with the same body as a nonexistent id (T-12)
- [ ] `max_count`, `slot_index` and similar fields reject zero, negative, fractional and string values (T-6)
- [ ] Rate limits answer `rate_limited` with `retry_after_seconds` (T-3)
- [ ] Definition tampering is impossible from a client route: `publish_definitions` and `rebase_shorter` are not routable (T-9)
- [ ] A store receipt in a request body is rejected; only a `store_transaction_id` already verified by `billing.virtual-currency` is accepted (T-11)

## Integration gates

- [ ] `billing.virtual-currency`: every price in a purchasable currency on any screen of this block renders its shared `ApproxMoney` component, and no other money computation exists in this block (the server sends no money figure or reference product)
- [ ] `billing.virtual-currency`: the five reasons are registered in `currency_flows`; every spend and grant uses the keys of README section 6; slot products exist with `product_kind = non_consumable`, `fulfilment = external`, `owner_block = engagement.timed-queues` (V8)
- [ ] `messaging.push-reengagement`: its `EVENT_ROUTES` carries `queue_item_ready` (category `timers`, local lane, route `queue`, parameter `queue_code`) and the template `timers.queue_item_ready`; the sum of `max_slots * lane_depth` is within its `LOCAL_MAX_PENDING` (V6)
- [ ] `engagement.objectives`: an adapter maps `queue_item_collected` to a server-derived metric if the game wants collection missions; no objective is defined on `queue_speedup_applied` or premium spend
- [ ] `auth.guest-account`: this block is registered as a participant (`holdings`, `mergeAccounts`, `deleteAccount`)
- [ ] `compliance.account-deletion`: the erasure registry lists the six account tables
- [ ] The host registers the flags named by `unlock_flag` and slot `flag` options, and `apply_effect` for `effect` output lines

## 3-stack mental test

Answer each for stacks A (Node 20, Express, Postgres, Drizzle), B (Bun, Hono, SQLite, raw SQL) and C (Deno, Oak, Postgres, Prisma), per `docs/SPEC_GUIDELINES.md` section 7:

1. **Data model.** Every column maps to a logical type of the guideline table. `id_list` columns (`prerequisite_job_ids`) are a text array on Postgres and JSON text on SQLite; `json` columns are JSONB on Postgres and JSON text on SQLite; `decimal` is `numeric(3,2)` on Postgres and `NUMERIC` on SQLite, with the range enforced by a CHECK and by `publish_definitions`. SQLite stores timestamps as ISO 8601 text with `Z`; compare only values written in that one format.
2. **Code snippets.** The five snippets (effective state, price, reschedule, CAS wrapper, start orchestration) use integer arithmetic and plain control flow; the `ADAPT` lines name the transaction API, the monotonic timer and the integer type. `BEGIN IMMEDIATE` on SQLite and `updateMany` with a count check on Prisma replace the version bump.
3. **External contracts.** The block depends on the ledger contract (`grant`, `spend`, `balance`, the error names), the purchase contract (`purchase_record`, `on_purchase_state_changed`), the guest-account participant contract and the push hand-off fields; each is concrete in README section 6. The store facts used (non-expiring purchased currency, restore mechanism for restorable purchases) are cited in the README and `frontend.md` with the Apple guideline number.
4. **Sequence flows.** No flow depends on a framework feature: transactions, a unique constraint and an optimistic version check exist on all three stacks; the recovery sweep is any scheduler that runs a function every `RECOVERY_SWEEP_SECONDS`.
5. **Acceptance.** Each item above is checkable on all three stacks with the fixtures and a ledger fake.

If any answer is "no", fix the spec before reporting done.

## Report back

State: which stack was used, which fixture cases passed, which items above were skipped and why, the open gates of "Integration gates", and every default of README section 7 the adopter changed.
