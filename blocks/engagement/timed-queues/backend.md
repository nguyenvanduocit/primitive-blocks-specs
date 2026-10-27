# Backend Patterns: Timed Queues

> Code snippets are L3 illustrative TypeScript with the four markers per `docs/SPEC_GUIDELINES.md` section 6. They show the pure core and the two orchestration patterns; the behavior (WHAT) is in the prose and in README sections 3 and 8. The core functions read no clock and no database; the shell passes `now` and rows in.

## Module map

| Unit | Responsibility | Kind |
|---|---|---|
| Definitions registry | Holds the active definition set; `publish_definitions` validates V1 to V9 and inserts the whole set in one transaction | Shell |
| Core: `effectiveState`, `remainingSeconds`, `reschedule`, `priceRaw`, `priceFinish`, `priceStep`, `refundLines`, `planStart`, `nudgeEligible` | Pure functions of rows, config and `now` | Core |
| Start service | Pre-check, reserve (T1), ledger spends, confirm (T2), undo | Shell |
| Collect service | Collect one, collect-all, resume after a refused grant | Shell |
| Speed-up service | Quotes, spend against a quote, time-item route, `reduce_remaining` | Shell |
| Cancel service | Refund record, ledger grants, lane reschedule | Shell |
| Slot service | Flag, currency and purchase unlocks, revoke on refund | Shell |
| Nudge service | Counters and the eligibility answer | Shell |
| Recovery sweep | Finishes rows stuck in a `pending` status | Shell |
| Hand-off emitter | `queue_item_ready` armed and resolved events | Shell |
| Participant | `holdings`, `mergeAccounts`, `deleteAccount` | Shell |

Every shell operation that writes an account's items in one queue runs inside the compare-and-swap wrapper below.

## 1. Request rules

- **Identity.** `account_id` and `tenant_id` come from the verified session. A request body or query that carries either is rejected `unexpected_field` (INV-23).
- **Strict bodies.** Each route accepts exactly the fields listed below. Any other field is rejected with `unexpected_field` and the field name; the time fields (`now`, `starts_at`, `ends_at`, `server_now`, `duration_seconds`, `price`, `amount`) are never accepted (INV-1).
- **Error body.** `{ "error": <code>, "message_key": <localization key>, "details": {...} }`. The server never sends display text. HTTP status is by class: 400 (`unexpected_field`, `invalid_request`), 401 (no session), 404 (`unknown_queue`, `unknown_job`, `item_not_found`), 409 (every business-rule refusal in section 3), 429 (`rate_limited`), 503 (a dependency is down; the request is retryable with the same `attempt_id`). The body `error` is the contract; the status is a convenience.
- **Idempotent replays answer 200.** A replay of a completed start, collect, cancel, speed-up or unlock returns the original body with `replayed: true` (or `already_collected`, `already_cancelled`, `already_unlocked`).
- **Every success body carries `server_now`** and, when items changed, `handoff[]` (README section 3, Hand-off).

## 2. Routes

| Route | Body | Success body | Notes |
|---|---|---|---|
| `GET /api/queues` | none | `{ server_now, definition_version, config_version, queues[], time_items[], speedup, armed[] }` | `queues[]`: `{ queue_id, kind, depth, lanes[], jobs[], idle_slots[], ready_count, suggestions[], idle_nudge }`. A lane: `{ slot_index, status (active, locked, revoked), unlock_options[], items[] }`. An item carries the **effective** `state`, `starts_at`, `ends_at`, `duration_seconds`, `output`, `cancel_refund_fraction`, `sped_up`, `collect_status`, `schedule_version`, and for a queued or running item `refund_preview` (the lines a cancel would return now). A job: `{ job_id, duration_seconds, input, output, cancel_refund_fraction, can_start, locked_reason, missing[] }`. `speedup`: `{ currency, paid_allowed, free_finish_seconds, price_per_hour_cap, steps_seconds[] }`. A read writes nothing (INV-2) |
| `POST /api/queues/{queue_id}/items` | `{ job_id, attempt_id, slot_index? }` | `{ item, replayed }` | Start. Errors: section 3 |
| `POST /api/queues/items/{item_id}/collect` | `{}` | `{ item, lines[], already_collected, suggestions[] }` | `suggestions` is the "start again" answer of README section 3 |
| `POST /api/queues/collect-all` | `{ queue_id? }` | `{ results[], more, suggestions[] }` | At most `COLLECT_ALL_MAX` items, `ends_at` order |
| `POST /api/queues/items/{item_id}/cancel` | `{}` | `{ item, refund_lines[], already_cancelled }` | Queued: full refund; running: snapshot fraction |
| `POST /api/queues/items/{item_id}/speed-up-quotes` | `{}` | `{ remaining_seconds, quotes[], time_items[], paid_allowed }` | One `finish` quote and one `step` quote per configured step shorter than the remainder. Each quote: `{ quote_id, mode, step_seconds, price_currency, price_amount, free, valid_until, ends_at_after }`. A quote carries no money figure |
| `POST /api/queues/items/{item_id}/speed-ups` | `{ attempt_id, quote_id }` or `{ attempt_id, item_code, max_count }` | `{ item, seconds_applied, quoted, charged, cost_code, balance, replayed }` | The quote route needs no price from the client; the items route needs no quote |
| `POST /api/queues/slots/unlock` | `{ queue_id, slot_index, via }` | `{ slot, already_unlocked }` | `via = currency` only; flag unlocks are evaluated by the server, purchases by `claim-purchase` |
| `POST /api/queues/slots/claim-purchase` | `{ store_transaction_id }` | `{ slot, already_unlocked }` | Reads `purchase_record`; also runs from `on_purchase_state_changed` |
| `POST /api/queues/nudge` | `{ queue_id, event }` | `{ idle_nudge }` | `event` is `shown`, `dismissed` or `acted` |

Operator and internal operations (not routes a client can reach): `publish_definitions(set)`, `rebase_shorter(job_id, definition_version, reason)`, `reduce_remaining(account_id, item_id, seconds, source_ref, idempotency_key)`, `holdings`, `mergeAccounts`, `deleteAccount`, `on_purchase_state_changed`, `recovery_sweep`.

Rate limits (per account): `STARTS_PER_MINUTE_MAX` on starts, `QUOTES_PER_MINUTE_MAX` on quotes; over the limit answers `rate_limited` with `retry_after_seconds`.

## 3. Error taxonomy

| Error | When | Details |
|---|---|---|
| `unexpected_field`, `invalid_request` | A field outside the route's list; a malformed value | `field` |
| `unknown_queue`, `unknown_job`, `item_not_found` | Id not in the active set, or an item of another account (INV-23) | |
| `job_retired` | New start of a retired job | |
| `job_locked` | Start refused by an unlock rule | `reason`: `prerequisite` (with `missing[]`), `flag`, `max_active`, `not_repeatable`; checked in that order |
| `slot_locked` | The chosen slot is not unlocked or is revoked | `reason`: `not_unlocked` or `revoked`; `unlock_options[]` |
| `slot_out_of_order` | An unlock for an index above the next locked one | `next_unlockable_index` |
| `lane_full` | The lane holds `lane_depth` queued and running items | |
| `lane_time_cap` | Stacked time would pass `MAX_LANE_SECONDS` | `projected_seconds`, `cap_seconds` |
| `ready_uncollected_cap` | `READY_UNCOLLECTED_MAX` finished items wait in the queue | `ready_count` |
| `start_in_progress` | Another start is in flight for this account and queue | Retry with the same `attempt_id` |
| `attempt_conflict` | A known `attempt_id` with different arguments | |
| `insufficient_balance` | A ledger line is short | `currency`, `needed`, `balance`, `shortfall` |
| `invalid_transition` | An action the state does not allow (README section 5) | `state` |
| `not_ready` | Collect on a queued or running item | `ends_at` |
| `item_not_running` | Speed-up on a queued, ready or terminal item | `state` |
| `nothing_to_skip` | Quote on an item with no time left | |
| `quote_invalid` | Unknown quote id, another account's quote, or a quote for another item | |
| `quote_expired`, `quote_stale` | README section 3 (Speed-up) | `quotes[]` fresh set |
| `paid_speedup_disabled` | `PAID_SPEEDUP_ENABLED` false, or a flagged minor with `PAID_SPEEDUP_FOR_MINORS` false | |
| `collect_blocked_cap` | The ledger refused a grant for `balance_limit_exceeded` | `currency`, `room_needed` |
| `purchase_not_verified`, `purchase_mismatch`, `no_slot_for_product` | Slot purchase claim | `state` |
| `merge_blocked_pending` | A merge found pending rows after inline recovery | |
| `rate_limited` | Section 2 | `retry_after_seconds` |

Publish-time errors (operator): `premium_input`, `duration_over_cap`, `input_without_faucet`, `curve_slope_over_cap`, `curve_not_monotone`, `curve_not_integer`, `curve_too_short`, `handoff_capacity_exceeded`, `prerequisite_cycle`, `refund_fraction_out_of_range`, `slot_product_invalid`, plus a code per remaining rule of V1 to V9.

## 4. Pure core

`now` is an instant the shell reads once per request from the server clock. Times below are in milliseconds for the sketch; the contract is "absolute instants and whole seconds".

### Effective state

<!-- PATTERN: effective-state -->
<!-- PURPOSE: derive the state of an item from its row and the server clock, so no timer job is needed and a read never writes -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: instants -> your timestamp type (epoch milliseconds shown); `Stored` -> the enum column of queue_items.state; keep the function free of I/O so tests run it without a database -->
```typescript
type Stored = "queued" | "running" | "ready" | "collected" | "cancelled";
interface Times { state: Stored; startsAt: number | null; endsAt: number | null }

function effectiveState(it: Times, now: number): Stored {
  if (it.state === "collected" || it.state === "cancelled") return it.state;
  if (it.startsAt === null || it.endsAt === null) return "queued"; // reserved, spend pending
  if (now < it.startsAt) return "queued";
  return now < it.endsAt ? "running" : "ready";
}

// whole seconds, rounded up: one definition for prices and countdowns
const remainingSeconds = (endsAt: number, now: number): number =>
  Math.max(0, Math.ceil((endsAt - now) / 1000));
```

### Price function

<!-- PATTERN: piecewise-price-round-up -->
<!-- PURPOSE: price a speed-up from remaining seconds with exact integer arithmetic and the named round-up rule -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: use your language's integer type (BigInt if units * seconds can pass 2^53); never use floating division then ceil, which misrounds at exact boundaries; anchors come from SPEEDUP_CURVE, the origin (0, 0) is implicit -->
```typescript
type Anchor = readonly [seconds: number, units: number];

function priceRaw(r: number, anchors: readonly Anchor[]): number {
  if (r <= 0) return 0;
  let [a, ua] = [0, 0];
  for (const [b, ub] of anchors) {
    if (r <= b) {
      const den = b - a;
      const num = ua * den + (ub - ua) * (r - a);  // units(r) * den, an integer
      return Math.floor((num + den - 1) / den);    // ceil without floats
    }
    [a, ua] = [b, ub];
  }
  throw new Error("remaining time above the last anchor: V5 failed");
}

const priceFinish = (r: number, anchors: readonly Anchor[], freeSeconds: number): number =>
  r <= freeSeconds ? 0 : priceRaw(r, anchors);

const priceStep = (r: number, s: number, anchors: readonly Anchor[]): number =>
  priceRaw(r, anchors) - priceRaw(Math.max(0, r - s), anchors);
```

`fixtures/price-vectors.json` holds the expected values; a test also sweeps `r` from 1 to the last anchor and checks that `priceRaw` never decreases and stays below `r / 3600 * SPEEDUP_PRICE_PER_HOUR_CAP + 1` (INV-11).

### Reschedule

<!-- PATTERN: lane-reschedule-min-rule -->
<!-- PURPOSE: recompute a lane after a predecessor changed so that no start or end time ever moves later -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: pass only the queued and running items of ONE lane, in lane_seq order; ready, collected and cancelled items are left out; persist changed rows with schedule_version +1 and notice_revision +1 in the same transaction -->
```typescript
interface LaneItem { id: string; startsAt: number; endsAt: number; durationMs: number; reducedMs: number }

function reschedule(items: LaneItem[], now: number): LaneItem[] {
  let cursor = now;                                   // the first item has no predecessor
  return items.map((it) => {
    const startsAt = Math.min(it.startsAt, cursor);   // earlier or equal, never later
    const endsAt = Math.min(it.endsAt, startsAt + it.durationMs - it.reducedMs);
    cursor = endsAt;
    return { ...it, startsAt, endsAt };
  });
}
```

Items appended to a lane take `startsAt = max(now, endsAt of the last queued or running item)` and are not passed through `reschedule` until a predecessor changes.

### Other pure functions

- `refundLines(item, now)`: `floor(amount * fraction)` per input line; `fraction` is 1 when `effectiveState = queued`, else the item's snapshot. Lines that floor to 0 are omitted.
- `planStart(request, defs, laneRows, balances, now)`: returns the job snapshot (duration, input, output, refund fraction, definition version), the chosen lane, or the first refusal in this order: attempt replay or conflict, unknown or retired job, unlock rules, slot, depth, stacked time, ready-uncollected cap, balances. Order matters for the tests in `start-item.feature`.
- `nudgeEligible(...)`: the seven checks of README section 3 in order, returning `{ eligible, why }`.
- `quoteFor(item, mode, step, config, now)`: builds a quote without writing it (remaining, price, free flag, validity).
- `chargeFor(quote, itemNow, config, now)`: `min(quote.price_amount, priceNow)` while `now <= quote.valid_until` (inclusive), where `priceNow` uses the quote's mode and step; else the refusal.

## 5. Compare-and-swap wrapper

Every write to an account's items in one queue goes through one wrapper. It is what makes starts race-safe across devices (INV-6).

<!-- PATTERN: queue-state-cas -->
<!-- PURPOSE: serialize writes per account and queue with an optimistic version check, retrying a lost race -->
<!-- REFERENCE: language=typescript framework=agnostic orm=raw-sql -->
<!-- ADAPT: `db.transaction` -> your transaction API (SQLite: BEGIN IMMEDIATE); `bumpVersion` is UPDATE queue_states SET version = version + 1 WHERE id = ? AND version = ? and must report whether one row changed; a lost race must roll the transaction back (throw) so item writes do not persist -->
```typescript
class CasLost extends Error {}

async function withQueueLock<T>(db: Db, key: QueueKey, fn: (s: QueueState, tx: Tx) => Promise<T>): Promise<T> {
  for (let attempt = 0; attempt < MAX_CAS_RETRIES; attempt++) {
    try {
      return await db.transaction(async (tx) => {
        const state = await tx.getOrCreateQueueState(key);    // one row per account and queue
        const out = await fn(state, tx);                      // settle the lane, read, write items
        if (!(await tx.bumpVersion(state.id, state.version))) throw new CasLost();
        return out;
      });
    } catch (e) {
      if (!(e instanceof CasLost)) throw e;                   // a lost race re-reads and retries
    }
  }
  throw new AppError("start_in_progress");                    // retryable by the client
}
```

Inside `fn` the first step is always **settle**: advance the stored `state` of the lane's items to the effective state at `now`, so a write never builds on a lagging row.

## 6. Start orchestration

<!-- PATTERN: reserve-spend-confirm -->
<!-- PURPOSE: start an item whose input is spent through the ledger exactly once, surviving a crash between the reservation and the confirmation -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: ledger.spend -> the in-process call of billing.virtual-currency; tx.reserveItem / confirmItem -> two transactions through withQueueLock; fail() -> your error type; the keys follow README section 6 and must be built from item.id so a recovery run repeats them exactly -->
```typescript
async function start(req: StartReq, ctx: Ctx) {
  const known = await ctx.items.byAttempt(ctx.accountId, req.attemptId);
  if (known) return known.sameArgs(req) ? known.toResult(true) : fail("attempt_conflict");
  const plan = planStart(req, ctx.defs, await ctx.lanes(req.queueId), await ctx.balances(), ctx.now());
  if (plan.refusal) return fail(plan.refusal.code, plan.refusal.details);
  const item = await withQueueLock(ctx.db, plan.key, (s, tx) => tx.reserveItem(plan, s));   // T1
  const done: Line[] = [];
  for (const [i, line] of plan.input.entries()) {
    const r = await ctx.ledger.spend(ctx.accountId, line.currency, line.amount,
      "timed-queues.start", item.id, `timed-queues:${ctx.accountId}:${item.id}:start:${i + 1}`);
    if (r.error) { await undo(ctx, item, done); return fail(r.error, r.details); }
    done.push(line);
  }
  return withQueueLock(ctx.db, plan.key, (s, tx) => tx.confirmItem(item.id, ctx.now()));   // T2 stamps times
}
```

- **T1 (`reserveItem`)** re-checks depth, stacked time and the in-flight guard inside the compare-and-swap (the plan above ran on a read), writes the item with `state = queued`, `input_status = pending` (`none` when the job has no input), null times, the snapshot, the next `lane_seq`, and sets `queue_states.start_in_flight_item_id` and `start_in_flight_since`.
- **T2 (`confirmItem`)** stamps `starts_at = max(now, ends_at of the lane's last queued or running item)`, `ends_at = starts_at + duration_seconds`, `schedule_version = 1`, `notice_revision = 1`, sets `input_status = spent`, the stored `state` (`running` when `starts_at <= now`, else `queued`), clears the in-flight fields, and writes the `armed` hand-off and `queue_item_started`.
- **`undo`** grants back the lines already spent (`timed-queues.cancel-refund`, key `...:{item_id}:start-undo:{line_no}`), sets `input_status = failed`, `state = cancelled`, `cancel_reason = input_rejected`, clears the in-flight fields, and emits `queue_item_start_rejected`. The replayed `attempt_id` returns this result.
- A ledger error that is not `insufficient_balance` (`unknown_currency`, `unknown_reason`, `idempotency_conflict`) is a deployment fault: undo, answer 503, alert.

## 7. Collect orchestration

1. Settle; require `effective_state = ready` (else `not_ready` or `invalid_transition`); a `collected` item returns `already_collected`.
2. T1: `collect_status = pending`.
3. For each output line in order: `currency` and `item` lines call `grant(..., "timed-queues.collect", item.id, "timed-queues:{account_id}:{item_id}:collect:{line_no}")`; an `effect` line calls the host hook `apply_effect(account_id, item)` once after the ledger lines. `balance_limit_exceeded` stops the loop, sets `collect_status = blocked_cap` and answers `collect_blocked_cap`; any other ledger error answers 503 and leaves `pending` for the sweep.
4. T2: `state = collected`, `collect_status = granted`, `collected_at`, `last_collected_job_id` on `queue_states`, the `resolved` hand-off, `queue_item_collected`.

Lines applied before a failure are never undone: a replay repeats them with the same keys and the ledger returns the originals.

Collect-all selects effective-ready items of the account (optionally one queue) ordered by `ends_at`, at most `COLLECT_ALL_MAX`, and runs the collect above per item; it does not hold one transaction across items.

## 8. Speed-up orchestration

1. **Quotes.** Settle; require `running`; compute `remaining_seconds`; apply the minor rule (`PAID_SPEEDUP_FOR_MINORS`); build the `finish` quote and a `step` quote per configured step below the remainder; insert `speed_up_quotes` rows with `valid_until = now + QUOTE_TTL_SECONDS`; emit `queue_speedup_quoted` per quote. A `finish` quote at or below `FREE_FINISH_SECONDS` has `free = true` and `price_amount = 0`.
2. **Spend against a quote.** Under `withQueueLock`: load the quote (`quote_invalid` when not the caller's or not for this item), return the original result for a known `attempt_id`, require `consumed_at` null, `now <= valid_until` and `item.schedule_version = quote.item_schedule_version` (else `quote_expired` or `quote_stale` with a fresh quote set and no charge), compute `charge = chargeFor(...)`, insert `time_reductions` (`pending`, `quoted_amount`, `cost_amount = charge`), set `consumed_at`.
3. **Ledger.** When `charge > 0`: `spend(account, SPEEDUP_CURRENCY, charge, "timed-queues.speed-up", reduction.id, "timed-queues:{account_id}:{reduction_id}:speed-up")`. `insufficient_balance`: set the reduction `rejected`, clear `consumed_at`, answer with the shortfall. A free finish makes no ledger call.
4. **Apply** under `withQueueLock`: re-settle; if the item is not `running` at that point, grant the spend back with `timed-queues.cancel-refund` (key `...:{reduction_id}:refund`), set the reduction `refunded` and answer `item_not_running`. Otherwise `reduced_seconds += seconds_applied`, `ends_at = max(now, ends_at - seconds_applied)`, `sped_up = true`, `schedule_version + 1`, `notice_revision + 1`; `reschedule` the lane; reduction `completed`; hand-off `resolved` when the item became `ready`, else re-armed; followers re-armed.
5. **Time-item route.** `used = min(max_count, ceil(remaining / item_seconds))`, `seconds_applied = min(remaining, used * item_seconds)`, ledger `spend(account, item_code, used, "timed-queues.speed-up", ...)`; then step 4. `used` never exceeds `max_count`.
6. **`reduce_remaining`** (internal) skips steps 1 to 3: it inserts a `time_reductions` row with `source = external`, `attempt_id = idempotency_key`, applies step 4, and returns the item; a replay returns the first result.

## 9. Cancel orchestration

Settle; a `ready`, `collected` or `cancelled` item answers per the transition table (`already_cancelled` for a repeat). Under `withQueueLock`: compute `refund_lines`, set `state = cancelled`, `cancel_reason = player`, `cancelled_at`, store `refund_lines`, `input_status = refund_pending` (or `refunded` when no line is refundable), `reschedule` the lane, write the hand-off `resolved` for the item and re-armed events for followers. Then grant each line (`timed-queues.cancel-refund`, key `...:{item_id}:refund:{line_no}`) and set `input_status = refunded` in a second transaction; the sweep finishes a refund whose request died.

## 10. Slot orchestration

- **Evaluation on read.** For each locked slot in index order with a `flag` option, call `unlock_flag(account_id, flag)`; the first true result inserts the `slot_unlocks` row (`progression`) under the unique (account, queue, slot). The read endpoint writes only this, and only once per slot.
- **Currency.** Require the next locked index (`slot_out_of_order`), run `spend` with `timed-queues.slot-unlock`, insert the row with the ledger `entry_id` as `source_ref`. The insert is the race guard: a duplicate returns `already_unlocked` and, when this request had spent, the spend is the same keyed entry (a replay), so no second charge occurs.
- **Purchase.** `claim-purchase` and `on_purchase_state_changed` share one function: read `purchase_record(store_transaction_id)`; require `state = verified`, `account_id` equal to the session account (or the hook's account), `product_kind = non_consumable` and a product named by the next locked slot's options; insert the row with `store_transaction_id`. A record that becomes `refunded` sets `status = revoked`; a reversed refund returns it to `active`.
- **Capacity of lanes.** `lanes = base_slots + count(active slot_unlocks)`; a `revoked` row counts for existing items and not for new starts.

## 11. Recovery sweep

Runs every `RECOVERY_SWEEP_SECONDS`; every action repeats the original ledger call with its original key.

| Row | Condition | Action |
|---|---|---|
| `queue_items` with `input_status = pending` | `reserved_at` older than `RECOVERY_GRACE_SECONDS` | Repeat the spends; on success T2; on `insufficient_balance` undo and cancel (`input_rejected`) |
| `queue_items` with `input_status = refund_pending` | older than the grace | Apply the stored `refund_lines`; set `refunded` |
| `queue_items` with `collect_status = pending` | `updated_at` older than the grace | Resume at the first line not applied; T2 |
| `time_reductions` with `status = pending` | older than the grace | Repeat the spend; apply or refund as in section 8 step 4 |
| `queue_states` with a stale in-flight id | the item is not `pending` | Clear the fields |
| `speed_up_quotes` | older than `QUOTE_RETENTION_DAYS` | Delete |

A row still pending after `RECOVERY_ALERT_MINUTES` raises an operator alert. Terminal `queue_items` older than `ITEM_RETENTION_DAYS` may be deleted, except `collected` items of a job with `repeatable = false`.

## 12. Definition publishing and operator actions

- **`publish_definitions(set)`** validates V1 to V9 against the set, the ledger registry (`currencies`, `currency_flows`), the pack catalog and the push block's `LOCAL_MAX_PENDING`; on any failure it returns the error codes and changes nothing; on success it inserts every queue and job row under `definition_version = max + 1` in one transaction and emits `queue_definitions_published`. Rolling back is publishing the older content again.
- **`rebase_shorter(job_id, definition_version, reason)`** lowers `duration_seconds` to `min(duration_seconds, new_duration)` for every queued and running item of the job, recomputes `ends_at` (never later), reschedules the affected lanes, bumps the versions, re-arms the hand-offs, and emits `queue_item_rebased`. It is idempotent and never lengthens (INV-10).
- **Registering the ledger flows.** The block's migration adds the five `currency_flows` rows of README section 6 (the registry needs a row per reason and direction before the first call).

## 13. Reference Migration, remaining tables

#### `queue_definitions` and `job_definitions` tables

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: `uuid ... gen_random_uuid()` -> MySQL `BINARY(16)` with UUID_TO_BIN(UUID()), SQLite `TEXT` with a uuid4 generated in the app; `timestamptz` -> MySQL `DATETIME(6)`, SQLite `TEXT` ISO 8601 with `Z`; `jsonb` -> MySQL `JSON`, SQLite `TEXT`; `numeric(3,2)` -> MySQL `DECIMAL(3,2)`, SQLite `NUMERIC`; `text[]` -> MySQL `JSON` array, SQLite `TEXT` (JSON array); the CHECK lists work unchanged on all three dialects -->
```sql
CREATE TABLE IF NOT EXISTS queue_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL,
  queue_id varchar(64) NOT NULL, definition_version bigint NOT NULL,
  kind text NOT NULL CHECK (kind IN ('build','craft','research','expedition')),
  base_slots bigint NOT NULL CHECK (base_slots >= 1), max_slots bigint NOT NULL,
  lane_depth bigint NOT NULL CHECK (lane_depth >= 1), slot_unlocks jsonb NOT NULL,
  sort_order bigint NOT NULL DEFAULT 0, published_at timestamptz NOT NULL,
  CHECK (max_slots >= base_slots),
  UNIQUE (tenant_id, queue_id, definition_version)
);
CREATE TABLE IF NOT EXISTS job_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL,
  job_id varchar(64) NOT NULL, definition_version bigint NOT NULL, queue_id varchar(64) NOT NULL,
  duration_seconds bigint NOT NULL CHECK (duration_seconds >= 1),
  input jsonb NOT NULL DEFAULT '[]', output jsonb NOT NULL,
  prerequisite_job_ids text[] NOT NULL DEFAULT '{}', unlock_flag varchar(64),
  repeatable boolean NOT NULL DEFAULT true, max_active_per_account bigint,
  cancel_refund_fraction numeric(3,2) NOT NULL DEFAULT 0.50
    CHECK (cancel_refund_fraction >= 0 AND cancel_refund_fraction <= 1),
  retired boolean NOT NULL DEFAULT false, sort_order bigint NOT NULL DEFAULT 0,
  published_at timestamptz NOT NULL,
  UNIQUE (tenant_id, job_id, definition_version)
);
CREATE INDEX IF NOT EXISTS job_definitions_queue ON job_definitions (tenant_id, queue_id, definition_version);
```

#### `slot_unlocks` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: same type mapping as above; the UNIQUE on `store_transaction_id` allows many NULL rows on Postgres, SQLite and MySQL; `external_id` -> `text` -->
```sql
CREATE TABLE IF NOT EXISTS slot_unlocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL,
  account_id text NOT NULL, queue_id varchar(64) NOT NULL, slot_index bigint NOT NULL,
  source text NOT NULL CHECK (source IN ('progression','currency','purchase','operator')),
  source_ref varchar(255), store_transaction_id text,
  status text NOT NULL CHECK (status IN ('active','revoked')),
  unlocked_at timestamptz NOT NULL, revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, account_id, queue_id, slot_index),
  UNIQUE (tenant_id, store_transaction_id)
);
```

#### `speed_up_quotes` and `time_reductions` tables

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: same type mapping as above; the partial index works on Postgres and SQLite, on MySQL index (tenant_id, created_at) and filter by status in the query -->
```sql
CREATE TABLE IF NOT EXISTS speed_up_quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL,
  account_id text NOT NULL, item_id uuid NOT NULL,
  mode text NOT NULL CHECK (mode IN ('finish','step')), step_seconds bigint,
  remaining_seconds bigint NOT NULL, price_currency varchar(64),
  price_amount bigint NOT NULL CHECK (price_amount >= 0), free boolean NOT NULL,
  config_version varchar(64) NOT NULL, item_schedule_version bigint NOT NULL,
  issued_at timestamptz NOT NULL, valid_until timestamptz NOT NULL, consumed_at timestamptz
);
CREATE INDEX IF NOT EXISTS speed_up_quotes_item ON speed_up_quotes (tenant_id, account_id, item_id, issued_at);
CREATE TABLE IF NOT EXISTS time_reductions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL,
  account_id text NOT NULL, item_id uuid NOT NULL, attempt_id varchar(64) NOT NULL,
  source text NOT NULL CHECK (source IN ('currency','items','free_finish','external')),
  quote_id uuid, seconds_applied bigint, cost_currency varchar(64), cost_amount bigint,
  quoted_amount bigint,
  status text NOT NULL CHECK (status IN ('pending','completed','rejected','refunded')),
  reject_reason varchar(64), created_at timestamptz NOT NULL, completed_at timestamptz,
  UNIQUE (tenant_id, account_id, attempt_id)
);
CREATE INDEX IF NOT EXISTS time_reductions_pending ON time_reductions (tenant_id, created_at) WHERE status = 'pending';
```

#### `merge_log` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: `jsonb` -> MySQL `JSON`, SQLite `TEXT`; `uuid` and `timestamptz` as above -->
```sql
CREATE TABLE IF NOT EXISTS merge_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL,
  merge_id varchar(128) NOT NULL, from_account_id text NOT NULL, into_account_id text NOT NULL,
  result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, merge_id)
);
```

## 14. Operations

| Signal | Alert when | Meaning |
|---|---|---|
| Rows with `input_status = pending`, `collect_status = pending` or `time_reductions.status = pending` older than `RECOVERY_ALERT_MINUTES` | Any | The ledger is down or a bug blocks recovery |
| `queue_speedup_rejected` with `quote_expired` over a share of rejections | Sustained | `QUOTE_TTL_SECONDS` is too short for the sheet, or the client does not refresh |
| `start_in_progress` over a share of starts | Sustained | Clients retry too eagerly or the ledger is slow |
| `queue_collect_blocked` per day | Rising | A currency or item cap sits below what jobs pay |
| `queue_definitions_published` | Every publish | Audit trail with `definition_version` and `config_version` |
| `queue_item_rebased` | Every rebase | Audit trail with the operator's reason |

## 15. 3-stack notes

- **Stack A (Node 20, Express, Postgres, Drizzle).** `withQueueLock` maps to `db.transaction` with the version bump as an UPDATE with a `WHERE version` guard; the partial indexes and `text[]` columns are native.
- **Stack B (Bun, Hono, SQLite, raw SQL).** Use `BEGIN IMMEDIATE` so the version check and the item writes share one writer; store `id_list` and `json` columns as JSON text; partial indexes are supported; timestamps are ISO 8601 text with `Z`, compared as text only when written in the same fixed format (or store epoch milliseconds).
- **Stack C (Deno, Oak, Postgres, Prisma).** Prisma has no partial index syntax in the schema; add the three partial indexes in a raw migration; the CAS update is `updateMany` with `where: { id, version }` and a count check.
- The core functions are plain integer arithmetic and run unchanged on all three runtimes.
