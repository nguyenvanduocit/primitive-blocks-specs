# Backend Patterns — Items

> The server decides every level, cost, state and clock reading. Behavior (WHAT) is in the prose; snippets are L3 illustrative TypeScript with the four markers per `docs/SPEC_GUIDELINES.md` section 6. Table and column names are those of `README.md` section 2. The ledger is `billing.virtual-currency`: this block calls `grant`, `spend` and `balance` and never writes a balance.

## API Endpoints

### Player (session; `account_id` comes from the verified session, never from the body)

| Method and path | Purpose | Body or query | Success |
|---|---|---|---|
| `GET /api/items/inventory` | One page of the player's `owned` instances | `order` (`newest` default, `rarity`), `bag`, `kind`, `cursor`, `limit` | `{server_now, inventory_version, items, definitions, capacity, next_cursor}` |
| `GET /api/items/stacks` | Count items with a balance above 0 | `cursor`, `limit` | `{server_now, stacks: [{item_code, balance, stack_cap, expires_at?}], definitions, next_cursor}` |
| `GET /api/items/instances/{id}` | One instance with its upgrade quote | | `{instance, definition, equipped, upgrade, convert}` |
| `GET /api/items/definitions/{code}` | The current definition, including a retired one, with its disclosure fields | | `{definition}` |
| `POST /api/items/instances/{id}/upgrade` | Pay the cost and raise the level by one | `{request_id, expected_version, expected_cost}` | `{instance, balances, operation_state}` |
| `POST /api/items/instances/{id}/equip` | Put the instance in its slot | `{request_id, target_id?}` (omit for an account slot) | `{equips, replaced_instance_id?}` |
| `POST /api/items/instances/{id}/unequip` | Take it out | `{request_id}` | `{equips}` |
| `POST /api/items/instances/{id}/discard` | Throw the instance away | `{request_id, expected_version}` | `{capacity}` |
| `POST /api/items/instances/{id}/convert` | Turn the instance into its `convert_value` | `{request_id, expected_version, expected_value}` | `{value_lines, balances, capacity}` |
| `POST /api/items/stacks/{code}/consume` | Spend a count item; a booster also starts an activation | `{request_id, quantity}` | `{balance, activation?}` |
| `POST /api/items/stacks/{code}/discard` | Spend a count item away | `{request_id, quantity}` | `{balance}` |
| `GET /api/items/active-effects` | Active boosters | | `{server_now, effects: [{item_code, starts_at, ends_at}]}` |
| `GET /api/items/held` | Held grants and the room left | | `{server_now, held: [{grant_id, item_code, held_quantity, hold_reason, held_until?, can_convert}], capacity}` |
| `POST /api/items/held/{grant_id}/claim` | Apply as much of the held quantity as fits | `{request_id}` | `{applied_quantity, held_quantity, instance_ids}` |
| `POST /api/items/held/{grant_id}/convert` | Convert the held quantity to its `convert_value` | `{request_id, expected_value}` | `{value_lines, balances}` |
| `GET /api/items/notices` | Outcomes the player did not start: expiry, automatic conversion, a reverted upgrade | | `{notices}` |
| `POST /api/items/notices/ack` | Mark notices seen | `{operation_ids}` | `{acknowledged}` |

Rules for every player endpoint:

- `request_id` is a `unique_id` the client generates once per user action and reuses on every retry of that action. The server records `request:{account_id}:{request_id}` as the operation key. A replay returns the stored result; the same id with a different body is `idempotency_conflict`.
- An instance id that is not the caller's answers `item_not_found`, the same as a missing id, so ids cannot be probed (`security.md`, T6).
- Mutations return the fields the screen needs (balances, capacity, the changed instance) so the client does not guess.
- A mutation on a retired item is allowed except where the endpoint says otherwise (`RETIRED_ALLOW_UPGRADE` for `upgrade`).

### Internal (service credential, never reachable from a device)

| Call | Purpose |
|---|---|
| `items.grant`, `items.revoke`, `items.owned`, `items.active_effects` | The contract of `README.md` section 6 |
| `publish_definition(draft)`, `retire_definition(code)` | Definition pipeline (this file, "Publish and retire") |
| `holdings(account_id)`, `mergeAccounts(from, into, merge_id)`, `deleteAccount(account_id)` | The participant and eraser contract of `auth.guest-account` (`README.md` section 6) |
| `run_recovery()`, `run_expiry_sweep()`, `run_held_conversion()` | The jobs below; also exposed for an operator |

## Pure core (no I/O)

These functions take values and return values. They run in tests without a database or a ledger (Functional Core, Imperative Shell).

### Grant resolution

Inputs are the definition facts, what the account holds, and the capacity facts, all read inside the transaction that holds the account row. The output says what to apply, convert and hold, and which ledger lines the conversion needs.

<!-- PATTERN: resolve-grant -->
<!-- PURPOSE: decide applied, converted and held quantities for one grant from definition facts and account facts, with no I/O -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `Line` is `{currency, amount}`; read `owned`, `balance`, `bagUsed` and `held` inside the same transaction that locked the account row; keep the rule order (duplicate before capacity) -->
```typescript
type Line = { currency: string; amount: number };
type Def = { mode: "count" | "instance"; maxCopies: number | null; rule: "convert" | "trade_in" | "cap" | null;
  dupLines: Line[]; stackCap: number };
type Ctx = { owned: number; balance: number; bagUsed: number; bagCap: number; held: number; heldMax: number;
  source: "fixed" | "random" | "purchase" };
type Plan = { applied: number; converted: number; held: number; lines: Line[]; holdReason?: "bag_full" | "stack_cap" }
  | { reject: "at_cap" | "held_limit_reached" };

function resolveGrant(d: Def, c: Ctx, qty: number): Plan {
  if (d.mode === "count") {
    const applied = Math.min(qty, Math.max(0, d.stackCap - c.balance));
    const rest = qty - applied;
    if (rest > 0 && c.held >= c.heldMax) return { reject: "held_limit_reached" };
    return { applied, converted: 0, held: rest, lines: [], holdReason: rest ? "stack_cap" : undefined };
  }
  if (d.maxCopies !== null && c.owned >= d.maxCopies) {
    if (d.rule !== "cap") return { applied: 0, converted: 1, held: 0, lines: d.dupLines };
    if (c.source !== "purchase") return { reject: "at_cap" };
  }
  if (c.bagUsed < c.bagCap) return { applied: 1, converted: 0, held: 0, lines: [] };
  if (c.held >= c.heldMax) return { reject: "held_limit_reached" };
  return { applied: 0, converted: 0, held: 1, lines: [], holdReason: "bag_full" };
}
```

`bagUsed` is the number of `owned` instances whose definition has the same `bag` as the item; an item with a null `bag` never meets a limit. A `cap` duplicate from a `purchase` source is delivered above `max_copies` (a paid delivery is never refused); a full bag holds it like any other grant, and the player can claim it. `lines` for a duplicate are `duplicate_value` per copy.

### Upgrade quote and plan

The quote is the current definition's `item_upgrade_costs` rows for `level + 1`. A request carries `expected_cost`; the plan is built only when it equals the quote line for line. The plan names every ledger call before the first is made, with keys derived from the operation id.

<!-- PATTERN: upgrade-plan -->
<!-- PURPOSE: build the ordered ledger steps and their refunds for an upgrade with deterministic keys -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: persist the returned plan in `item_operations.plan` before the first ledger call; step index `i` is stable because cost lines are sorted by currency code first -->
```typescript
type Step = { op: "spend" | "grant"; currency: string; amount: number; reason: string; key: string };

function upgradePlan(opId: string, quote: Line[], expected: Line[]): { spends: Step[]; refunds: Step[] } | "cost_changed" {
  const sorted = [...quote].sort((a, b) => a.currency.localeCompare(b.currency));
  const want = [...expected].sort((a, b) => a.currency.localeCompare(b.currency));
  const same = sorted.length === want.length &&
    sorted.every((l, i) => l.currency === want[i].currency && l.amount === want[i].amount);
  if (!same) return "cost_changed";
  const step = (op: "spend" | "grant", reason: string, tag: string) => (l: Line, i: number): Step =>
    ({ op, currency: l.currency, amount: l.amount, reason, key: `items:${opId}:${tag}${i}` });
  return {
    spends: sorted.map(step("spend", "items.upgrade", "s")),
    refunds: sorted.map(step("grant", "items.upgrade-refund", "r")),
  };
}
```

### Recovery decision

Given a non-terminal operation and a snapshot of the instance, the next action is fixed by the data, so any number of recovery runs agree.

<!-- PATTERN: recovery-next-step -->
<!-- PURPOSE: choose the next action for a stuck upgrade from the journal state and the instance row -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `inst` is read inside the account-row transaction; `expectedVersion` is the version stored in the plan at request time -->
```typescript
type Snap = {
  state: "pending" | "debited" | "reverting";
  opId: string; expectedVersion: number;
  inst: { version: number; lastOperationId: string | null };
};
type Next = "run_spends" | "apply" | "mark_applied" | "run_refunds";

function nextStep(s: Snap): Next {
  if (s.state === "reverting") return "run_refunds";
  if (s.state === "pending") return "run_spends";
  if (s.inst.lastOperationId === s.opId) return "mark_applied";
  if (s.inst.version === s.expectedVersion) return "apply";
  return "run_refunds";
}
```

`run_spends` repeats every spend with its original key; each returns its original result or applies once. A spend that now answers `insufficient_balance` while earlier spends were applied moves the operation to `reverting`.

### Expiry decision

<!-- PATTERN: expiry-action -->
<!-- PURPOSE: decide what an expiring instance does at a given server instant, including the warning rule for removal -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: all values are epoch milliseconds read from the server clock; `warnedAt` is set by the inventory read that first showed the copy inside the warning window or after expiry -->
```typescript
type Copy = { expiresAt: number | null; warnedAt: number | null; outcome: "convert" | "remove" };
type Cfg = { removalGraceMs: number; deferMaxMs: number };

function expiryAction(c: Copy, now: number, cfg: Cfg): "none" | "unusable" | "convert" | "remove" {
  if (c.expiresAt === null || now < c.expiresAt) return "none";
  if (c.outcome === "convert") return "convert";
  const deferDue = c.expiresAt + cfg.deferMaxMs;
  const due = c.warnedAt === null
    ? deferDue
    : Math.min(deferDue, Math.max(c.expiresAt, c.warnedAt + cfg.removalGraceMs));
  return now >= due ? "remove" : "unusable";
}
```

`unusable` means the copy is expired in the player's eyes (every operation except `discard` and `convert` answers `item_expired`) but is not yet removed.

### Activation window

For a booster consume at server time `now` with the code's active rows (`ends_at > now`):

- `refuse`: if any row is active, reject `activation_refused` before spending. Otherwise `starts_at = now`.
- `extend`: `starts_at` is the latest `ends_at` among active rows of the code, or `now` when none. The consume is rejected `activation_limit` when `starts_at + activation_seconds - now` exceeds `ACTIVATION_MAX_REMAINING_SECONDS`.
- `ends_at = starts_at + activation_seconds`. The consume and the activation row share one operation id, so a replay creates no second row.

### Inventory ordering and cursor

Two sort orders exist, both total and both built only from columns that never change under a cursor:

| `order` | Sort key |
|---|---|
| `newest` (default) | `added_at` DESC, `id` DESC |
| `rarity` | `rarity_rank` DESC, `added_at` DESC, `id` DESC |

Level, name and other orders are applied by the client over the loaded rows: an account holds at most its bag capacities, which is a few pages. A level changes under an open cursor; sorting by it on the server would skip or repeat rows.

<!-- PATTERN: keyset-after-cursor -->
<!-- PURPOSE: build the WHERE fragment that returns the rows strictly after a cursor in a total order -->
<!-- REFERENCE: language=typescript framework=agnostic dialect=postgres+sqlite+mysql -->
<!-- ADAPT: bind parameters with the driver's placeholder style; on SQLite compare `added_at` as ISO 8601 text with a fixed width and `Z`, which sorts like time; row-value comparison `(a, b) < (?, ?)` is an equivalent form on all three engines but the expanded form avoids engine-specific planner behavior -->
```typescript
type Key = { rank: number; addedAt: string; id: string };

function afterCursor(order: "newest" | "rarity", k: Key): { sql: string; params: unknown[] } {
  if (order === "newest") {
    return {
      sql: "(added_at < ?) OR (added_at = ? AND id < ?)",
      params: [k.addedAt, k.addedAt, k.id],
    };
  }
  return {
    sql: "(rarity_rank < ?) OR (rarity_rank = ? AND added_at < ?) OR (rarity_rank = ? AND added_at = ? AND id < ?)",
    params: [k.rank, k.rank, k.addedAt, k.rank, k.addedAt, k.id],
  };
}
```

The contract:

- `limit` defaults to `PAGE_SIZE_DEFAULT` and is clamped to `PAGE_SIZE_MAX`. The query reads `limit + 1` rows to know whether `next_cursor` exists.
- `next_cursor` is opaque to the client. It encodes the order, the last row's key, and a digest of the filters (`bag`, `kind`). A cursor sent with a different order or different filters is `invalid_cursor`.
- Every filter and order is applied together with `account_id` and `state = owned` from the session.
- No row is returned twice and no row that existed for the whole read is skipped. A row granted while the client pages appears at the top of `newest` on the next first-page read; the response carries `inventory_version`, and a client that sees a higher value than on page one refetches page one after the last page. A row that is discarded between pages simply does not appear. A row whose level changes keeps its position.
- A merge inserts rows with `added_at` equal to the merge time, which is the top of `newest`, so a merge cannot place rows behind an open cursor in that order.
- The `stacks` list orders by (`sort_order`, `code`) of the definition, both immutable for a published version, and uses the same cursor rules.
- Every inventory read evaluates expiry first: expired `convert` copies and stacks are settled (section "Expiry" below), and every copy inside the warning window gets `warned_at` set once.

## Writing

Every mutating operation follows one shape: **transaction 1** touches the `item_accounts` row first (incrementing `inventory_version`, which serializes the account), validates, writes local rows and the `item_operations` row with its plan; the **ledger steps** run outside any transaction with deterministic keys; **transaction 2** touches the account row again, applies the local change and marks the operation `applied`. Operations with no ledger step are one transaction.

### Grant

1. Validate: the code has a current definition (`unknown_item`); it is not `retired` (`item_retired`) and, for `absolute` expiry, `now < expires_at` (`item_expired`); `quantity` is valid; for count items `reason` is in `faucet_reasons` (`reason_not_allowed`); for `random`, `source_code` is listed in `random_sources` and `odds_version` is present (`source_not_allowed`); for `fixed` and `purchase` sources, `random_sources` places no limit (a game may hand out a pull-able item as a fixed reward).
2. Look up the grant row by `(account_id, source_ref, item_code, ordinal)`. Found with the same `request_digest`: return its stored result. Found with another digest: `idempotency_conflict`.
3. Transaction 1: touch the account row, read `owned`, `balance` (from the ledger `balance` call; a stale read is safe because the cap is a free-source soft limit), `bagUsed` and the held count, run `resolveGrant`, insert the grant row, insert the instance (when `applied` is 1), and insert the operation row with the plan when ledger lines are needed (count `applied` quantity as one ledger `grant` with the caller's reason; duplicate and conversion lines with `items.duplicate`). Commit.
4. Run the ledger steps in plan order with keys `items:{operation_id}:{step}`. A ledger `balance_limit_exceeded` on a count grant moves that quantity to `held` with `hold_reason` `stack_cap`.
5. Transaction 2: mark the operation `applied` and the grant `settled` or `held`. Emit `item_granted` once, plus `item_duplicate_converted` and `item_grant_held` as they apply.

A replay never repeats step 3 or 4: it returns the stored result of the first call.

### Upgrade

1. **Transaction 1**: touch the account row. Load the instance by id and account: `item_not_found`; `state` is `owned`; not expired (`item_expired`); `level < max_level` (`max_level_reached`); definition retired with `RETIRED_ALLOW_UPGRADE` false: `item_retired`; `version` equals `expected_version` (`version_conflict`); the quote equals `expected_cost` (`cost_changed`, returning the new quote); no other operation holds `instance:{id}` (`operation_in_progress`). Insert the operation with `state` `pending`, `lock_key` `instance:{id}` and the `upgradePlan` result; commit. A failed check inserts a `failed` operation row only when a `request_id` replay must return the same error; it spends nothing.
2. **Ledger spends**, in plan order. `insufficient_balance` on any spend: run the refunds of the spends already applied, set `reverting` then `reverted`, clear `lock_key`, answer `insufficient_balance` with the shortfall lines. Emit `item_upgrade_reverted` only when a refund ran.
3. Set `debited`.
4. **Transaction 2**: touch the account row; `UPDATE` the instance setting `level = level + 1`, `version = version + 1`, `last_operation_id`, `updated_at` where `id`, `account_id`, `state = owned`, `level = from_level` and `version = expected_version`. Zero rows updated: refund (`reverting`) and answer `version_conflict`. One row: set the operation `applied`, store `result`, clear `lock_key`. Emit `item_upgraded`.

Failure ordering, stated once: a crash before step 1 commits leaves nothing; between steps 1 and 3 leaves an operation `pending` that recovery re-drives (spends repeat with their keys); between 3 and 4 leaves `debited`, which recovery either applies or refunds. The player is never charged without one of those outcomes, and the level is never raised without a recorded spend.

**Shared-database variant.** When the ledger writer can run inside the caller's transaction and enforces its key uniqueness there, steps 1 to 4 are one transaction: the spends, the compare-and-swap and the journal row (written already `applied`) commit together; any failure rolls back and nothing is refunded because nothing was spent. The responses are identical to the saga's.

### Consume

- **Plain consumable** (count): one ledger `spend` with reason `items.consume`, key `items:{operation_id}:s0`. The response carries the ledger `entry_id` as `consumption_id`; the game applies the effect, keyed by it.
- **Booster**: steps 1 to 4 of the upgrade shape. Transaction 1 checks the policy against active rows (`activation_refused`, `activation_limit`) and writes the operation with the spend. After the spend, transaction 2 inserts the `item_activations` row with `starts_at` and `ends_at` from the server clock. A failure in transaction 2 refunds with reason `items.consume-refund`. The response carries `ends_at` and `server_now`.
- Consuming more than the balance: `insufficient_balance`, nothing recorded. An expired stack (`absolute` expiry passed): `item_expired`.

### Discard and convert

- **Discard an instance**: one transaction. The instance must be `owned`, not equipped (`equipped_instance`), `version` equal to `expected_version`. Set `state` `discarded`, bump `version`; a `unit` that wears items has those `item_equips` rows removed in the same transaction (the items stay owned).
- **Discard a stack**: a ledger `spend` with reason `items.discard`.
- **Convert an instance**: requires a `convert_value` (`no_conversion_value`), `expected_value` equal to it (`value_changed`), not equipped. Transaction 1 sets `state` `converted` and writes the operation with the grant lines (`items.convert`); the ledger grants follow; transaction 2 marks the operation `applied`. The state change comes first because a grant can only fail transiently and the journal drives it to completion; the instance cannot be converted twice because its state is terminal.
- **Convert a held grant**: the same, with the `held_quantity` times `convert_value`; the grant's `held_quantity` falls to 0 in transaction 1.

### Equip and unequip

One transaction. The instance is `owned`, not expired, its definition has a `slot`. For `equip_target` `unit` the body names `target_id`, an `owned` instance of kind `unit` of the same account (`target_invalid`); for `account`, no target. `equip_policy` is asked (`equip_refused` with its `reason_key`). The `item_equips` row for `(target_key, slot)` is upserted to the instance; if one existed, the replaced instance is reported and stays owned. If the instance was equipped elsewhere, that row is removed first (an instance has one place). `unequip` deletes the row.

### Claim a held grant

Operation `claim`, keyed by `request_id`. Transaction 1 re-runs `resolveGrant` for the held quantity against current capacity: instance items need room (`no_room` when none) and re-apply the duplicate rule if the account now owns `max_copies` (the held copy converts); count items apply `min(held_quantity, room)` through a ledger `grant` with the **original grant's reason** and key `items:{operation_id}:g0`. The grant row's `held_quantity` falls by the applied and converted amounts; at 0 the grant is `settled`. Held grants of a retired item stay claimable.

### Revoke

`items.revoke(account_id, source_ref)`: the instance with that `source_ref` and `source_kind` `purchase` becomes `revoked` in one transaction, its equip row is removed, the account row version bumps. Idempotent: a revoked instance is returned as is. Materials spent on its upgrades are not refunded (design; the refund policy of materials is the game's decision and is not specified here).

### Account merge

Operation `merge`, key `merge:{merge_id}`, called as `mergeAccounts(from, into, merge_id)` by `auth.guest-account` after the player confirmed. A repeat of the `merge_id` returns the stored result; a guest whose account row already carries `merged_into_account_id` with another `merge_id` fails `already_merged`.

1. Touch both account rows in a fixed order (lower `account_id` first) to avoid a lock cycle. If any of the guest's operations is non-terminal, fail with the retryable `merge_incomplete`; `auth.guest-account` resumes with the same `merge_id`.
2. Walk the guest's `owned` instances by level descending, then `granted_at` ascending. For each, decide **move** or **surplus** with the target's `owned` count of the code and `max_copies`. Move: `UPDATE` `account_id`, `added_at` = merge time, `version + 1`, `last_operation_id`. Surplus: `convert` and `trade_in` become `converted` with the lines in the operation plan; `cap` moves anyway.
3. Move held grants, activations (re-timed after the target's latest `ends_at` per code), and the equip rows whose target moved; delete the equip rows whose target did not.
4. Set `merged_into_account_id` on the guest's account row. Ledger lines of the plan run with keys `items:{operation_id}:{step}`. Mark `applied`; emit `items_merged`.

Later calls naming the guest id resolve to the target through the pointer.

### Holdings and erase

- `holdings(account_id)`: three counts in one read (`owned` instances and whether any has `source_kind` `purchase`; held grants with `held_quantity > 0`; activations with `ends_at > now`). It returns one row per non-empty count with the effect `carried`, and writes nothing.
- `deleteAccount(account_id)`: one transaction that touches the account row, then deletes `item_equips`, `item_activations`, `item_instances`, `item_grants`, `item_operations` and the `item_accounts` row for the account. It is safe to repeat: a missing account row is success. The ledger rows of the same account are erased by `billing.virtual-currency`, so a journaled operation that never finished leaves no charge behind.

## Jobs

| Job | Period | Work |
|---|---|---|
| Recovery | `OPERATION_RECOVERY_INTERVAL_SECONDS` | Select operations in `pending`, `debited` or `reverting` older than `OPERATION_RECOVERY_AFTER_SECONDS` whose `next_attempt_at` has passed. For each, take the account row, compute `nextStep`, run it, and set `attempts` and `next_attempt_at` with backoff on a transient ledger error. Emit `item_operation_recovered`. Alert at `OPERATION_STUCK_ALERT_SECONDS` |
| Expiry sweep | `EXPIRY_SWEEP_INTERVAL_SECONDS` | (a) Instances `owned` with `expires_at <= now`: run `expiryAction`; `convert` and `remove` set `state` `expired` and write an `expire` operation with the value lines; `unusable` does nothing. (b) Count items with `absolute` expiry passed: set the code's faucet rows `enabled = false` once, then convert each account's balance (below). (c) Copies entering the warning window: emit `item_expiring_soon` once per copy per window |
| Held conversion | `EXPIRY_SWEEP_INTERVAL_SECONDS` | Grants with `held_quantity > 0`, `held_until <= now` and a `convert_value`: run the held-grant convert as the system. The outcome is a notice |
| Flow audit | daily | Compare the reasons in operation plans of the last day with the `currency_flows` rows of the touched currencies and alert on a missing or disabled row |

**Stack expiry** per account is an `expire` operation keyed `expire:{account_id}:{item_code}:{expires_at epoch seconds}`: read the balance `b`; plan one ledger `spend` of `b` (reason `items.expire`) and the `expiry_value` lines times `b`; run in order. A spend that finds a lower balance (the player consumed meanwhile) plans again from the new balance on the next attempt. The sweep reaches accounts through two sources: the accounts in `item_grants` for the code, and the lazy check that every `stacks` read, consume and grant runs for the account. A ledger query that lists holders of a currency would make the sweep complete; the ledger contract does not offer one, and the lazy check covers every account that opens the game.

## Publish and retire

`publish_definition(draft)` is the only way a definition becomes `active`. In order:

1. **Validate** every rule in `README.md` "Choosing the storage mode", including the cross-table checks against `billing.virtual-currency` (`store_product_contents` for expiry and for instance codes).
2. **Register in the ledger registry** (idempotent upserts keyed by the registry's unique indexes): for a count code, one `currencies` row with `kind` `item`; then the `currency_flows` rows below. A failure leaves the draft untouched (`PUBLISH_REQUIRE_FLOW_ROWS`).
3. **Write this block's rows**: the definition with its `item_upgrade_costs`, `status` `active`, `published_at`; the previous version of the code, if any, becomes `superseded`. One transaction.
4. Emit `item_definition_published`.

| Direction | Reason | Currencies |
|---|---|---|
| faucet | each reason in `faucet_reasons` | the count code |
| sink | `items.consume` | a count `consumable` or `booster` code |
| sink | `items.discard` | the count code |
| sink and faucet | `items.expire` | sink: a count code with `absolute` expiry; faucet: each currency in `expiry_value` |
| faucet | `items.consume-refund` | a `booster` code |
| sink | `items.upgrade` | each currency in `item_upgrade_costs` |
| faucet | `items.upgrade-refund` | each currency in `item_upgrade_costs` |
| faucet | `items.duplicate` | each currency in `duplicate_value` |
| faucet | `items.convert` | each currency in `convert_value` |
| sink | `items.convert` | a count code with a `convert_value` |

Publish errors (the draft stays `draft`; nothing is registered in the ledger registry when validation fails):

| Code | Rule broken |
|---|---|
| `kind_mode_mismatch` | The kind does not allow the storage mode |
| `count_has_per_copy_feature` | A count definition sets `max_level` above 1, `max_copies`, `bag`, `slot` or a per-copy expiry |
| `instance_has_count_feature` | An instance definition sets `stack_cap` or `faucet_reasons` |
| `immutable_field_changed` | A new version changes `kind`, `stack_mode`, `slot` or `equip_target` |
| `max_level_decrease` | A new version lowers `max_level` |
| `activation_required` | A `booster` lacks `activation_seconds` or `activation_policy`, or another kind sets them |
| `duplicate_value_required` | `max_copies` is set without a rule, or `convert` has no line above zero |
| `trade_in_fragment_unused` | A `trade_in` fragment code appears in none of the item's upgrade cost rows |
| `cap_not_allowed_for_random_source` | `cap` on an item with `random_sources` |
| `duplicate_note_required` | `random_sources` and `max_copies` are set without `duplicate_note_key` |
| `expiry_note_required` | Expiry is set without `expiry_note_key`, or `convert` without `expiry_value` |
| `count_expiry_must_convert` | A count definition with expiry uses `remove` |
| `expiry_on_purchased_item` | An item with expiry appears in a `store_product_contents` row or is the item of a store product |
| `gating_requires_free_route` | `progress_gating` without `obtainable_free` |
| `instance_code_in_ledger_contents` | An instance code appears in `store_product_contents` |
| `upgrade_cost_missing` | A level from 2 to `max_level` has no cost row, or a level has more than `UPGRADE_MAX_COST_LINES` |
| `flow_registration_failed` | A required `currency_flows` row could not be registered (`PUBLISH_REQUIRE_FLOW_ROWS`) |
| `definition_immutable` | An update or a publish names a published (code, version) row; the change must be a new version |
| `definition_in_use` | A delete names a definition that an instance, a grant or a ledger balance still references |

`retire_definition(code)` sets the current row `retired` and emits `item_definition_published` with `status` `retired`. It deletes nothing and disables no registry row.

## Idempotency keys

| Operation | Key |
|---|---|
| Grant | `(account_id, source_ref, item_code, ordinal)` on `item_grants`; ledger: `items:{operation_id}:{step}` |
| Player operation | `request:{account_id}:{request_id}` on `item_operations` |
| Ledger call made here | `items:{operation_id}:{s or r or g}{index}` (at most `LEDGER_IDEMPOTENCY_KEY_MAX_LENGTH` characters; `operation_id` is a `unique_id`) |
| Stack expiry | `expire:{account_id}:{item_code}:{expires_at epoch seconds}` |
| Merge | `merge:{merge_id}` |
| Purchase-sourced grant | `source_ref` = `purchase:{store_transaction_id}` |

## Error Handling

| Code | HTTP | Meaning | Retry |
|---|---|---|---|
| `invalid_request` | 400 | A field is missing or malformed, or the client sent a field the server owns (`level`, `amount`, `account_id`) | No |
| `invalid_cursor` | 400 | The cursor does not match the order or filters, or was tampered with | Restart from page one |
| `item_not_found` | 404 | Unknown id, another account's id, or a terminal instance for an operation that needs `owned` | No |
| `unknown_item` | 404 | No current definition for the code | No |
| `idempotency_conflict` | 409 | Same key, different arguments | No |
| `version_conflict` | 409 | `expected_version` is stale | Reload, retry with a new `request_id` |
| `cost_changed` | 409 | The cost or value differs from the one shown; the body carries the new quote | Show the new quote |
| `operation_in_progress` | 409 | Another operation holds the instance | After a short delay |
| `merge_incomplete` | internal (retryable) | The guest has non-terminal operations; returned to `auth.guest-account`, which answers `503 import_incomplete` and resumes | Retry with the same `merge_id` |
| `already_merged` | internal | The guest was merged under another `merge_id` | No |
| `insufficient_balance` | 422 | The ledger rejected a spend; the body carries the shortfall lines | After earning |
| `item_expired` | 422 | The copy or stack is past `expires_at` | No |
| `item_retired` | 422 | The definition is retired and the action is a grant, or an upgrade with `RETIRED_ALLOW_UPGRADE` false | No |
| `max_level_reached`, `not_upgradable` | 422 | Level is at `max_level` | No |
| `equipped_instance` | 422 | Discard or convert of an equipped instance | Unequip first |
| `slot_mismatch`, `target_invalid`, `equip_refused` | 422 | Equip rules | No |
| `no_room` | 422 | Claim with a full bag | After making room |
| `no_conversion_value` | 422 | The definition has no `convert_value` | No |
| `activation_refused`, `activation_limit` | 422 | Booster policy | After it ends |
| `at_cap`, `held_limit_reached`, `reason_not_allowed`, `source_not_allowed`, `invalid_quantity`, `item_retired` | internal | Grant rejections returned to the calling block | Per `README.md` section 6 |
| `ledger_unavailable` | 503 | A ledger call failed transiently; the operation stays journaled and recovery completes it | Safe to retry with the same `request_id` |

A 5xx after transaction 1 has committed always leaves a journaled operation. The client retries with the same `request_id` and receives either `operation_in_progress` or the stored result.

## Anti-patterns

| Anti-pattern | Why it fails |
|---|---|
| Raising the level before the spend | A failed spend leaves a free level; only a clawback can repair it |
| Spending without a journal row | A crash between spend and apply loses the player's materials with nothing to recover from |
| Building ledger keys from time or a random value at call time | A retry repeats the effect. Keys derive from the operation id and the step |
| Accepting `level`, `amount` or `cost` from the client | Any client value becomes a free upgrade |
| Sorting inventory pages by level or by a mutable column | Rows skip or repeat when a level changes between pages |
| Storing the same code as a ledger count and as instances | The two disagree; one shape per code |
| Holding the account lock across a ledger call | The ledger call may be slow and every other mutation of the account waits behind it |
| Dropping a grant when the bag is full | The kit rule is a held grant with an exit (`kits/game-engagement/guides/14-rewards-resources-and-items.md`, Decision rule 12) |
| Removing an expired `remove` copy the player never saw | The player cannot act on a warning they did not get |
| Deleting a retired definition row | Instances that reference it lose their display and rules |
