# Acceptance — Items

Verification checklist Claude Code runs AFTER implementation, BEFORE reporting done. Every item must pass. Tests are generated from the six `.feature` files and the four JSON fixtures: create the test files in the project's own test framework, read the cases from `fixtures/` by name, and report any scenario that cannot run. Items marked **[client]** apply to the web-tech client; the rest are server items. Items marked **(manual)** cannot be checked from code and go into the report as "needs manual setup".

## Build and types

- [ ] The project's type check passes with zero errors
- [ ] The ledger is called only through `grant`, `spend` and `balance` of `billing.virtual-currency`; no code writes a balance table
- [ ] The pure functions (`resolveGrant`, `upgradePlan`, `nextStep`, `expiryAction`, the activation window, `afterCursor`) take values and return values with no I/O, and each has a unit test that reads its vectors from `fixtures/`
- [ ] No `any` types except with an explicit justification comment

## Data model

- [ ] The eight tables of `README.md` section 2 exist: `item_definitions`, `item_upgrade_costs`, `item_accounts`, `item_instances`, `item_equips`, `item_grants`, `item_activations`, `item_operations`
- [ ] The migration runs on a clean database and is idempotent on the project's dialect
- [ ] UNIQUE constraints exist on (`tenant_id`, `code`, `version`), (`tenant_id`, `account_id`, `source_ref`, `item_code`, `ordinal`), (`tenant_id`, `operation_key`), (`tenant_id`, `lock_key`), (`tenant_id`, `instance_id`) of `item_equips`, and (`tenant_id`, `account_id`, `target_key`, `slot`)
- [ ] The CHECK constraints for `level >= 1`, positive costs and the two single-table definition rules are enforced by the database
- [ ] Every table carries `tenant_id` and every query filters by it
- [ ] The item indexes of section 2 exist; the two inventory orders use an index (confirm with the engine's query plan on a table of at least 10,000 rows)

## Definitions and publishing

- [ ] `publish_definition` refuses each draft of `invalid_drafts` in `fixtures/definitions.json` with its `expect_error` and writes nothing to the ledger registry
- [ ] Publishing the catalog of `fixtures/definitions.json` registers exactly the rows of `expected_flows`, creates a `currencies` row (kind `item`) for each count code and none for any instance code
- [ ] Publishing the same draft twice changes nothing
- [ ] A published row cannot be updated or deleted (`definition_immutable`, `definition_in_use`)
- [ ] A new version supersedes the old row; instances keep `definition_version`; a quote uses the current version
- [ ] A retired definition rejects grants and allows equip, upgrade (unless `RETIRED_ALLOW_UPGRADE` is false), convert and discard
- [ ] The storage-mode rule is applied by the publish step, not by callers: kind, mode, per-copy features and the cross-table checks all run in one place

## Grants and duplicates

- [ ] `grant-and-duplicates.feature` passes, including the crash-and-retry case
- [ ] A replay of `(account_id, source_ref, item_code, ordinal)` returns the stored result; a different argument is `idempotency_conflict`
- [ ] The grant row, copy count, capacity check and instance insert commit in one transaction
- [ ] A duplicate is decided before capacity; `convert` and `trade_in` grant their lines through the ledger with reason `items.duplicate`; `cap` refuses only `fixed` sources and delivers `purchase` sources
- [ ] A `random` grant needs a `source_code` listed in the definition and an `odds_version`, and both are stored on the grant row and the instance
- [ ] A count grant forwards the caller's reason to the ledger and rejects a reason outside `faucet_reasons`
- [ ] A grant is never reachable from a device route

## Capacity and held grants

- [ ] `inventory-limits-and-reads.feature` passes
- [ ] A full bag and a stack at its cap hold the grant with `hold_reason`, `held_until` and a claim path; nothing is dropped
- [ ] A full held list rejects the grant with `held_limit_reached` and records nothing
- [ ] A held grant with a `convert_value` converts at `held_until` and leaves an `unseen` notice; one without stays held
- [ ] A merge ignores capacity; later grants are held while the account is over capacity

## Upgrade saga

- [ ] `upgrade-saga.feature` passes, including all six fault cases
- [ ] The operation row and its plan are written before the first ledger call; ledger keys derive from the operation id and the step
- [ ] The level never rises before the spend is recorded; a refund is issued only on the `reverting` path
- [ ] One in-flight operation per instance (`lock_key`); a second request answers `operation_in_progress` before any spend
- [ ] The compare-and-swap checks `version` and `level` and sets `last_operation_id`; recovery treats a matching `last_operation_id` as applied
- [ ] The recovery job is registered, uses `nextStep`, backs off per operation and alerts at `OPERATION_STUCK_ALERT_SECONDS`
- [ ] If the ledger writer runs inside the same database transaction (shared-database variant), the same feature passes with `operation_state` going from `pending` to `applied` in one commit, and the project states which variant it uses
- [ ] The cost the player confirms is compared to the current quote (`cost_changed`); a client body with a level or an amount is rejected

## Equip, consume, discard, convert

- [ ] `equip-consume-discard-convert.feature` passes
- [ ] One item per (target, slot) and one place per instance are enforced by the two UNIQUE constraints
- [ ] Discard and convert refuse an equipped instance; removing a unit removes the equip rows that point at it and keeps the gear
- [ ] A convert changes the state before the ledger grant and recovery completes the grant once
- [ ] A booster consume writes the spend and the activation under one operation id; a failed activation refunds with `items.consume-refund`
- [ ] A purchase-sourced grant uses `source_ref` `purchase:{store_transaction_id}`; a refunded purchase revokes the instance and a repeat returns the same result

## Expiry and activation

- [ ] `expiry-and-boosters.feature` passes; the thirteen expiry vectors and the eight activation vectors of `fixtures/expiry-and-merge-cases.json` match
- [ ] Usability ends at `expires_at` on the server clock; expiry never reads a device time
- [ ] A `convert` copy and a count stack pay their value at expiry; a count definition with outcome `remove` cannot be published
- [ ] A `remove` copy is removed only after the warning was shown plus the grace, or at the deferral maximum
- [ ] An inventory read inside the warning window sets `warned_at` once and emits `item_expiring_soon` once per copy
- [ ] The stack-expiry operation key is `expire:{account_id}:{item_code}:{expires_at epoch seconds}`; a retry converts once; a balance that changed meanwhile is re-planned
- [ ] The faucet rows of an expired count code are disabled; a lazy conversion runs on stacks reads, consume and grant

## Reads and pagination

- [ ] Both orders are total and end in `id`; the pages of `fixtures/account-states.json` `pagination` match
- [ ] A level change, a new grant and a discard between pages never repeat or skip an item
- [ ] A cursor for another order or other filters, or an edited cursor, answers `invalid_cursor`; `limit` is clamped to `PAGE_SIZE_MAX`
- [ ] An instance id of another account and a missing id answer identically

## Merge, holdings and erasure

- [ ] `definitions-merge-and-erasure.feature` passes
- [ ] The block is registered with `auth.guest-account` as a participant: `holdings`, `mergeAccounts(from, into, merge_id)` and `deleteAccount`; an unregistered block would count as holding nothing, so this is a release gate
- [ ] `mergeAccounts` is idempotent by `merge_id`, answers `already_merged` for a second `merge_id`, and fails with the retryable `merge_incomplete` while the guest has a non-terminal operation
- [ ] Every guest instance moves or converts; none is created; the instance count is conserved
- [ ] The equip rows of moved instances move with them; rows whose target did not move are removed; held grants and booster time move as the README states
- [ ] `holdings` returns up to three rows, each `carried`, writes nothing, and ignores terminal instances and ended activations
- [ ] `deleteAccount` removes every row of the account in one transaction, is safe to repeat and to resume, and leaves the ledger rows to `billing.virtual-currency`

## Ledger registration

- [ ] Every reason this block sends to the ledger has an enabled `currency_flows` row of the right direction for each currency it touches: `items.upgrade`, `items.upgrade-refund`, `items.consume`, `items.consume-refund`, `items.discard`, `items.expire`, `items.duplicate`, `items.convert`
- [ ] The flow audit job reports a faucet row of an item code whose reason is missing from `faucet_reasons`
- [ ] A purchase of a pack that contains a count item is delivered by the ledger and is not blocked by a stack cap

## Security

- [ ] The thirteen threats of `security.md` each have a passing scenario or a documented control
- [ ] No endpoint accepts `account_id`, `level`, `amount`, `state` or a time from the body; extra fields answer `invalid_request`
- [ ] The internal credential for `items.grant` is not in any client bundle, repository or log
- [ ] No log line carries `attributes`, a service credential or a request body beyond ids and versions

## Events

- [ ] Each event of `README.md` section 6 and `frontend.md` section 12 is emitted with its documented properties and the shared envelope; `item_granted` is emitted once per first application, not per replay
- [ ] No event carries a price or a money amount

## Client

- [ ] **[client]** The inventory shows the same rows in grid and list in one order and never reorders loaded rows when one changes
- [ ] **[client]** The upgrade sheet shows the quote's lines, the shortfall, and for each purchasable-currency line an approximate real-money value labeled "about" from the real-money helper; no money value is shown for soft or item lines
- [ ] **[client]** Each mutation reuses its `request_id` across retries and releases it on a terminal answer
- [ ] **[client]** Every countdown is computed from `server_now` and an absolute instant; a device clock change changes no result
- [ ] **[client]** The duplicate sentence and the odds link appear on the same surface for an item with a random source, before the player commits
- [ ] **[client]** The inventory-full sheet lists every held reward with its exits and never opens over a running session
- [ ] **[client]** Offline, every mutation control is disabled with the reason; no mutation is queued
- [ ] **[client]** Each screen of `frontend.md` handles its listed states and passes the accessibility notes (names, text labels, focus, reduced motion)
- [ ] **[client]** No copy uses loss framing, a countdown on a purchase, or a preselected destructive choice

## 3-stack mental test

Answer each question for stacks A (Node 20, Express, Postgres, Drizzle), B (Bun, Hono, SQLite) and C (Deno, Oak, Postgres, Prisma) and record the answers in the report.

- [ ] Data model: every logical type maps on all three; `json` columns on SQLite are validated in the app; unique constraints on nullable `lock_key` allow several NULLs on all three
- [ ] Snippets: each snippet has an equivalent on all three (only the SQL placeholder style and the timestamp text format change)
- [ ] External contracts: the platform facts (Apple 3.1.1, Google Payments policy) are concrete; the ledger contract is read from `billing.virtual-currency`
- [ ] Sequence flows: none depends on a framework feature; every cross-store step is an explicit journal row
- [ ] Acceptance: every item above is verifiable on all three stacks

## Manual (needs manual setup)

- [ ] **(manual)** The store product for each item sold for money exists in both stores as a non-consumable, and `ITEM_PRODUCTS` maps it to its item code
- [ ] **(manual)** The random source's odds screen exists and its `odds_ref` keys match the definitions' `random_sources`
- [ ] **(manual)** The report lists every manual step left and every `Assumption:` made
