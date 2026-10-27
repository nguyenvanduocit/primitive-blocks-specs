# Backend Patterns — Energy and Lives

> "Backend" is the server side of the block: the pure meter core, the atomic unit that wraps every operation, the attempt, refill, grant, boost, offline and merge operations, and the event hand-off. Snippets are L3 illustrative TypeScript or SQL with the markers required by `docs/SPEC_GUIDELINES.md` section 6; the behavior (WHAT) is in the prose around each one.
>
> **External contracts kept concrete**: the ledger operations of `billing.virtual-currency` (`grant`, `spend`, `{applied, balance, entry_id}`, `insufficient_balance`, the `reason` and `idempotency_key` forms), the AdMob server-side verification parameters and signature rule (section 5), and the shape of the `energy_full` event consumed by `messaging.push-reengagement`. Everything else is an internal choice the adopter may reshape.

## Endpoints

All player-facing routes need a verified session. `account_id` and `tenant_id` come from the session, never from the body (INV-17). Timestamps in bodies are UTC instants (ISO 8601 with `Z`). Every response that describes a meter carries `server_now`.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/energy` | All meters: `value`, `reserved`, `available`, `cap`, `overfill_max`, `regen_amount`, `regen_interval_seconds`, `next_tick_at`, `full_at`, `boost_ends_at`; re-drives pending refills first |
| POST | `/api/energy/attempts` | Start: `{ attempt_id, meter_code }`. 201 new, 200 replay |
| POST | `/api/energy/attempts/{attempt_id}/confirm` | The session began |
| POST | `/api/energy/attempts/{attempt_id}/finish` | `{ outcome: win|fail|abandon }` |
| POST | `/api/energy/attempts/{attempt_id}/cancel` | `{ reason: "start_failed" }`; allowed while `open` |
| GET | `/api/energy/attempts/{attempt_id}` | One attempt (own only; another account's id is 404) |
| POST | `/api/energy/attempts/reconcile` | Offline batch: `{ attempts: [{ attempt_id, meter_code, outcome }] }` |
| GET | `/api/energy/offers?meter_code=` | Offers with the cost computed for this player now, `available` and a `blocked` reason (`already_full`, `no_room`, `boost_stack_limit`, `not_for_minors`) |
| POST | `/api/energy/refills` | `{ refill_id, meter_code, offer_code, expected_cost }` |

In-process operations (callers are other blocks and the adopter's routes, not the network):

| Operation | Purpose |
|-----------|---------|
| `grantEnergy(account_id, meter_code, amount, reason, source_ref, idempotency_key)` | Credit with the ledger's call shape; returns `{applied, balance, entry_id, applied_amount, unapplied_amount}` |
| `grantBoost(account_id, meter_code, seconds, reason, source_ref, idempotency_key)` | Extend the boost window; returns `{applied, applied_seconds, unapplied_seconds, boost_ends_at, entry_id}` |
| `attemptState(account_id, attempt_id)` | `{state}` for blocks that pay a session reward (INV-13) |
| `mergeAccounts(from_account_id, into_account_id, merge_id)` | Section 7 |
| `publishMeterConfig(tenant_id, meter_code, fields, effective_at)` | Admin only; appends a version |

Optional gift routes are in the last section.

### Response shapes

```json
{
  "server_now": "2026-10-21T12:00:00Z",
  "meters": [{
    "meter_code": "energy", "value": 3, "reserved": 0, "available": 3,
    "cap": 5, "overfill_max": 5, "regen_amount": 1, "regen_interval_seconds": 1800,
    "next_tick_at": "2026-10-21T12:30:00Z", "full_at": "2026-10-21T13:00:00Z",
    "boost_ends_at": null
  }]
}
```

An attempt response adds `attempt_id`, `state`, `mode`, `charged`, `reserved`, `boost_free`, `refunded`, `refund_denied` (when set), and `replayed: true` on a replay. `next_tick_at` and `full_at` are null at or above the cap.

---

## 1. The pure core

`advance(meter, now, versions)` has no I/O and reads no clock. `versions` are the config versions of the meter ordered by `effective_at`. Rules are in README 3.1 and 3.6; this function is the whole of them.

<!-- PATTERN: lazy-advance -->
<!-- PURPOSE: derive the current meter from the stored value, its anchor, server time and the config versions, with no timer -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: `number` instants -> your date type (epoch milliseconds here; map the `timestamp` column in and out at the repository edge); `cfgs` -> read the versions of one meter from `energy_meter_configs`, cached per version because rows are immutable; for a meter with thousands of versions index by `effectiveAt` and binary search `at` -->
```typescript
type Cfg = { effectiveAt: number; cap: number; amount: number; intervalMs: number };
type Meter = { value: number; anchorAt: number };

export function advance(m: Meter, now: number, cfgs: Cfg[]): Meter {
  const at = (t: number) => [...cfgs].reverse().find((c) => c.effectiveAt <= t) ?? cfgs[0];
  const tickEnd = (t: number) => {
    let end = t + at(t).intervalMs;
    for (const v of cfgs) {
      if (v.effectiveAt > t && v.effectiveAt < end) end = Math.min(end, Math.max(v.effectiveAt, t + v.intervalMs));
    }
    return end;
  };
  let { value, anchorAt: t } = m;
  for (;;) {
    if (value >= at(t).cap) {                       // nothing accrues at or above the cap
      const next = cfgs.find((v) => v.effectiveAt > t && v.effectiveAt <= now);
      if (!next) return { value, anchorAt: t };
      t = next.effectiveAt;                         // a later version may raise the cap
      continue;
    }
    const end = tickEnd(t);
    if (end > now) return { value, anchorAt: t };   // partial progress stays in anchorAt
    value = Math.max(value, Math.min(value + at(t).amount, at(end).cap));
    t = end;
  }
}
```

The loop ends: each pass either returns or completes a tick that adds at least one point or moves `t` to a later version; there are at most `cap` ticks and a few versions. A value above the cap passes through the first branch and returns.

**Projections.** After `advance`, `nextTickAt = tickEnd(anchorAt)` when `value < cap(now)`, else null. `fullAt` is found by applying the tick rule forward (with `tickEnd` and the clamp above) until the value reaches the cap in effect at a tick's end, over all known versions including ones scheduled in the future; it is null when `value >= cap(now)`. Neither is stored.

**Spend, credit, refund** are small pure helpers on the normalized meter:

<!-- PATTERN: meter-moves -->
<!-- PURPOSE: the three value changes with their cycle and ceiling rules, free of I/O -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: `cap` and `overfillMax` -> the version in effect at `now`; return the new row fields to your repository; `cycleStartedAt` is the column of that name -->
```typescript
type Row = { value: number; anchorAt: number; cycleStartedAt: number | null };

export function spend(r: Row, now: number, cap: number, cost: number): Row {
  const value = r.value - cost;                       // caller checked available >= cost
  const crossed = r.value >= cap && value < cap;      // a new cycle starts here
  return { value, anchorAt: crossed ? now : r.anchorAt, cycleStartedAt: crossed ? now : r.cycleStartedAt };
}

export function credit(r: Row, amount: number, ceiling: number, cap: number): { row: Row; applied: number } {
  const applied = Math.max(0, Math.min(amount, ceiling - r.value));
  const value = r.value + applied;
  return { row: { ...r, value, cycleStartedAt: value >= cap ? null : r.cycleStartedAt }, applied };
}

// ceilings: grant cap + overfillMax; bought refill cap; refund Math.max(cap, valueBefore)
```

`cycleStartedAt` is also set when an `advance` across a cap-raising version leaves the meter below the new cap: it takes that version's `effectiveAt`.

---

## 2. The atomic unit

Every operation runs the same unit per (`tenant_id`, `account_id`, `meter_code`):

1. Validate shapes: ids against `ID_PATTERN`, codes against the slug rule, integers in range. A failure is `invalid_request`.
2. Open a transaction and read the instant once (INV-12).
3. Load the config versions and the meter row. A missing row is created with `value = cap(now)` and `anchor_at = now` (insert, ignore a conflict, read again).
4. `now' = max(now, anchor_at, updated_at)` guards a backwards clock.
5. Load the meter's `open` and `confirmed` attempts. Settle due ones in due order (README 3.2): for each, `advance` to its due instant, apply, continue.
6. `advance` to `now'`.
7. Run the operation.
8. Write the row with the revision test, insert the attempt or entry rows, and write outbox rows for events.
9. Commit. A failed revision test rolls back and repeats from step 2, at most `MAX_CONFLICT_RETRIES` times, then answers `unavailable`.

On Postgres a `SELECT ... FOR UPDATE` on the meter row in step 3 serializes the unit and the revision test never fails. On SQLite one writer at a time (`BEGIN IMMEDIATE`) has the same effect. The revision test is the portable form:

<!-- PATTERN: meter-compare-and-swap -->
<!-- PURPOSE: write the normalized meter only if nobody else wrote since it was read -->
<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: placeholders :name -> $1 style (pg, Drizzle sql template) or ? (SQLite raw SQL) or Prisma $executeRaw tagged template; timestamptz values -> ISO 8601 text on SQLite; "rows affected = 0" -> result.rowCount (pg), changes (bun:sqlite), the integer returned by $executeRaw (Prisma) -->
```sql
UPDATE energy_meters
   SET value = :value,
       anchor_at = :anchor_at,
       cycle_started_at = :cycle_started_at,
       boost_ends_at = :boost_ends_at,
       revision = revision + 1,
       updated_at = :now
 WHERE tenant_id = :tenant_id
   AND account_id = :account_id
   AND meter_code = :meter_code
   AND revision = :expected_revision;
-- rows affected = 0: another unit wrote first; roll back and retry
```

A **read** (`GET /api/energy`) runs steps 1 to 6 and writes only when step 5 settled something or a pending refill was re-driven; a read that only advanced the meter writes nothing (INV-2).

---

## 3. Attempts

**Start** (`POST /api/energy/attempts`). After the unit's steps 1 to 6:

1. If an attempt with this `attempt_id` exists: same meter returns it with `replayed: true` (200), another meter is `attempt_conflict`, a `rejected` one is `insufficient_energy` with `replayed: true`.
2. `boost = boost_ends_at > now'`. `cost = boost ? 0 : attempt_cost`.
3. `available = value - reserved`, where `reserved` sums `reserved` over the live attempts. If `cost > 0` and `available < cost`: `insufficient_energy` (409) with `value`, `available`, `next_tick_at`, `full_at`, `server_now`; nothing is stored.
4. `on_start`: apply `spend`; `charged = cost`. `on_fail`: `reserved = cost`, the row's value is unchanged.
5. Insert the attempt: `state open`, `value_before` the value before step 4, `confirm_deadline = now' + CONFIRM_TIMEOUT_SECONDS`, `mode` and `boost_free` as decided.
6. Emit `energy_full` when the cycle opened or `full_at` moved (section 8). Answer 201.

**Confirm.** `open` becomes `confirmed` with `expires_at = now' + ATTEMPT_TTL_SECONDS`. A confirmed attempt answers 200 again. A terminal one is `attempt_not_open` with its state.

**Finish.** Allowed from `open` (implicit confirm) and `confirmed`. `win` releases a reservation; `fail` and, when `ABANDON_COUNTS_AS_FAIL`, `abandon` take the reserved points through `spend` (so the cycle rule applies at that instant); `abandon` ends `expired`. A finish on a terminal attempt returns it with `replayed: true`.

**Cancel** (`start_failed`). Only from `open`, else `attempt_not_cancellable`. `on_start`: refund per README 3.2 through `credit` with the ceiling `max(cap, value_before)`; count the account's applied refund entries for today's `day_key` first; at `START_REFUND_LIMIT_PER_DAY` the attempt ends `expired` with `refund_denied = daily_limit` and nothing is credited. `on_fail`: release the reservation. A refund writes an `energy_entries` row of kind `refund`, reason `energy-lives.start-refund` (a label on this block's log, never sent to the ledger), key `energy-lives:{account_id}:attempt:{attempt_id}:refund`, which also makes the cancel idempotent. A boost-free attempt has `charged = 0` and refunds nothing.

**Due settlement** (unit step 5) applies the same cancel and abandon logic at the due instant: `confirm_deadline` for an `open` attempt (reason `start_timeout`), `expires_at` for a `confirmed` one. It never calls the ledger and never emits a player-visible error.

<!-- PATTERN: due-settlement-order -->
<!-- PURPOSE: apply lazy settlements at their own instants so results do not depend on read time -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: `applyDue` -> your cancel/abandon routine from this section (it receives the meter normalized to `dueAt`); `Attempt` -> the row type of energy_attempts; run it inside the unit's transaction -->
```typescript
type Attempt = { state: "open" | "confirmed"; confirmDeadline: number; expiresAt: number | null };

export function settleDue(m: Meter, live: Attempt[], now: number, cfgs: Cfg[],
                          applyDue: (m: Meter, a: Attempt, dueAt: number) => Meter): Meter {
  const due = live
    .map((a) => ({ a, dueAt: a.state === "open" ? a.confirmDeadline : (a.expiresAt as number) }))
    .filter((d) => d.dueAt <= now)
    .sort((x, y) => x.dueAt - y.dueAt);
  let cur = m;
  for (const d of due) cur = applyDue(advance(cur, d.dueAt, cfgs), d.a, d.dueAt);
  return advance(cur, now, cfgs);
}
```

**attemptState(account_id, attempt_id)** returns `{state}` or null. Reward-paying blocks accept `confirmed`, `won`, `failed` only (INV-13).

---

## 4. Refills (currency)

**Quote** (`GET /api/energy/offers`). For each offer of the meter, from the advanced meter: `to_full` has `units = max(0, cap - value)` and `cost = units * amount`, blocked `already_full` when `units = 0`; `units` has `cost = amount`, blocked `already_full` at the cap and `no_room` when `value + units > cap`; `boost` has `cost = amount`, blocked `boost_stack_limit` when `seconds` does not fit in `BOOST_MAX_REMAINING_SECONDS`. Offers are blocked `not_for_minors` for accounts flagged `is_minor` unless `PAID_REFILL_FOR_MINORS`.

**Refill** (`POST /api/energy/refills`). The unit runs steps 1 to 6, then:

1. Replay: an entry with key `energy-lives:{account_id}:refill:{refill_id}` and status `applied` answers its stored result with `replayed: true`; status `pending` continues at step 5 with the stored quote.
2. Unknown offer is `unknown_offer`; a minor without permission is `refill_not_available` (403).
3. Apply the quote rules above; a blocked offer answers its blocking error and charges nothing.
4. If the computed cost exceeds `expected_cost`, answer `price_changed` (409) with the new quote and charge nothing. A lower computed cost is charged as computed.
5. Insert the entry `pending` with `requested`, `cost_currency`, `cost_amount` snapshotted. Commit this step on its own so the intent is durable before money moves.
6. Call the ledger `spend(account_id, currency, cost, 'energy-lives.refill', refill_id, key)`. `insufficient_balance` marks the entry `rejected` and answers 409. Any other failure leaves the entry `pending` and answers `unavailable`.
7. In a new unit: credit (`to_full`: `value = max(value, cap)`; `units`: `+units` within the cap; `boost`: `grantBoost` rule) and mark the entry `applied` with `ledger_entry_id`, `balance_after`, `value_after`, in the same transaction as the meter write.

<!-- PATTERN: refill-saga -->
<!-- PURPOSE: charge the ledger once and credit the meter once, whatever crashes between them -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic api=virtual-currency-ledger -->
<!-- ADAPT: `ledger` -> the in-process client of billing.virtual-currency; `store` -> your repository with one transaction per call; `redrive` is also called for every pending entry at the start of GET /api/energy, at most REDRIVE_MAX_PER_READ -->
```typescript
export async function refill(req: Refill, ledger: Ledger, store: Store) {
  const key = `energy-lives:${req.accountId}:refill:${req.refillId}`;
  const entry = (await store.findEntry(req.accountId, key)) ?? (await store.quoteAndInsertPending(req, key));
  if ("error" in entry) return entry;                     // already_full, price_changed, no_room ...
  if (entry.status === "applied") return { ...entry.result, replayed: true };
  const paid = await ledger.spend(req.accountId, entry.costCurrency, entry.costAmount,
    "energy-lives.refill", req.refillId, key);            // a replay returns the original result
  if (!paid.applied) { await store.mark(entry.id, "rejected"); return { error: "insufficient_balance" }; }
  return store.creditAndMarkApplied(entry.id, paid);      // one transaction: meter write + status
}

export const redrive = (accountId: string, ledger: Ledger, store: Store) =>
  store.pendingEntries(accountId).then((list) =>
    Promise.all(list.map((e) => refill(e.asRequest(), ledger, store))));
```

**Prices and waits have no per-account input (INV-18).** The quote reads the offer, the config version in effect and the meter's own state; it never reads the account's purchases, spend totals, segment or any risk signal. `GET /api/energy/offers` returns the same offers and the same cost for every account with the same meter state; the only account-dependent difference is the disclosed block `not_for_minors`.

**Undeliverable refill.** A `pending` entry whose meter definition was removed or whose account was erased cannot be credited. The block replays the spend (it returns the original result, or applies it now), then calls the ledger `grant(account_id, currency, cost, 'energy-lives.refill-refund', refill_id, 'energy-lives:{account_id}:refill:{refill_id}:refund')` and marks the entry `refunded`. Abandoning a pending entry without this is not allowed (INV-7).

**Known limit.** The cost is computed from the points missing at step 3; points that regenerate before step 7 (milliseconds normally, the length of an outage when re-driven) are not refunded. `units` and `boost` offers have a fixed price and are unaffected.

---

## 5. Grants, boosts and the rewarded-ad contract

**grantEnergy.** The unit runs steps 1 to 6, then inserts the entry with `INSERT ... ON CONFLICT (tenant_id, account_id, idempotency_key) DO NOTHING`. If the insert did nothing, read the existing entry and return `{applied, balance: value_after, entry_id, applied_amount, unapplied_amount: requested - applied_amount}` with `replayed: true`. Otherwise credit to the ceiling `cap + overfill_max`, store `applied_amount` and `value_after`, and return the same shape. `amount` must be a positive integer (`invalid_request`). `reason` has the form `<block-slug>.<action>`.

**grantBoost.** Same idempotency. `base = max(now', boost_ends_at ?? 0)`, `room = BOOST_MAX_REMAINING_SECONDS - (base - now')`, `applied_seconds = max(0, min(seconds, room))`, `boost_ends_at = base + applied_seconds`. The excess is `unapplied_seconds` (INV-9).

**Rewarded-ad grant.** The ad network is the only party that can prove a video was watched, so the grant starts at a server-to-server callback and never at a client request. For AdMob server-side verification (HIGH, [AdMob SSV](https://developers.google.com/admob/android/ssv)):

- The callback carries `ad_network`, `ad_unit`, `custom_data`, `key_id`, `reward_amount`, `reward_item`, `signature`, `timestamp`, `transaction_id` and `user_id`; `signature` and `key_id` are always last, in that order.
- The signed content is every query parameter before `&signature=`, exactly as received, unmodified and in order. The signature is ECDSA with SHA-256 and DER encoding.
- Public keys are downloaded from `gstatic.com/admob/reward/verifier-keys.json` (a JSON object with a `keys` array whose entries have `keyId`, `pem` and `base64`) and may be cached for at most 24 hours; Google rotates them.
- `transaction_id` is a unique hex identifier per reward grant event. The page does not say how to guard against replay, so the idempotency key below does.
- `user_id` is set by the app (`setUserId`) and is absent if unset; `custom_data` is set by the app before the ad shows, percent-escaped.

The adopter's ad route does the following, then calls `grantEnergy`:

<!-- PATTERN: ad-callback-grant -->
<!-- PURPOSE: turn a verified rewarded-ad callback into at most one grant per transaction -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic algorithm=ecdsa-sha256 api=admob-ssv -->
<!-- ADAPT: `keys` -> the cached verifier-keys.json (refresh at least every 24 hours); the encoding of `signature` -> confirm on the current AdMob page (the page read for this spec does not state it; base64url is assumed here); `verify` -> Node `crypto.createVerify`, Web Crypto `subtle.verify` with a DER-to-P1363 conversion on Deno or Bun, or a Tink port; other ad networks -> their own callback fields and signature rule -->
```typescript
export async function onAdCallback(rawQuery: string, keys: Map<string, string>, grant: GrantEnergy) {
  const cut = rawQuery.lastIndexOf("&signature=");
  if (cut < 0) return { ok: false, reason: "signature_missing" };
  const signed = rawQuery.slice(0, cut);                       // exactly as received
  const p = new URLSearchParams(rawQuery);
  const pem = keys.get(p.get("key_id") ?? "");
  if (!pem || !verifyEcdsaSha256(signed, p.get("signature") ?? "", pem))
    return { ok: false, reason: "signature_invalid" };
  const accountId = p.get("user_id");
  const tx = p.get("transaction_id");
  if (!accountId || !tx || !(await accountExists(accountId))) return { ok: false, reason: "unknown_account" };
  const key = `energy-lives:${accountId}:ad:${tx}`;
  const prior = await findEntry(accountId, key);                // a repeated callback returns the original
  if (prior) return { ok: true, granted: prior.applied_amount, replayed: true };
  if ((await adGrantsToday(accountId)) >= AD_GRANTS_PER_DAY) return { ok: true, granted: 0, reason: "daily_limit" };
  const r = await grant(accountId, "energy", AD_GRANT_UNITS, "energy-lives.ad-refill", tx, key);
  return { ok: true, granted: r.applied_amount };
}
```

Units come from `AD_GRANT_UNITS`, never from `reward_amount`. The daily count is the number of applied `energy-lives.ad-refill` entries for the account and today's `day_key`; a refused callback still writes a `rejected` entry with the key so a repeat does not count twice. The route answers the network according to the network's own callback rules (not verified here). `user_id` is chosen by the client, so a forged `user_id` can only gift points to another account, and each point needs a real signed callback.

---

## 6. Offline reconcile

`POST /api/energy/attempts/reconcile` answers `offline_attempts_disabled` (409) unless `OFFLINE_ATTEMPTS`. A batch longer than `OFFLINE_MAX_ATTEMPTS` is `invalid_request`. The unit runs once for the batch (steps 1 to 6), then for each item in order:

1. Known `attempt_id`: report its state with `replayed: true`.
2. Otherwise run the start rules at the server's now. `insufficient_energy` stores the attempt as `rejected` (`offline = true`) and reports it.
3. Otherwise confirm and finish with the item's `outcome`; the attempt is stored with `offline = true`.

The response lists `{ attempt_id, state, charged | error, replayed? }` per item and the meter fields after the batch. The server never accepts the client's claimed start time.

---

## 7. Account merge

`mergeAccounts(from, into, merge_id)` runs one unit over both rows of each meter (lock in a fixed order, smaller `account_id` first, so two merges cannot deadlock): settle both, advance both to now, write the row of `into` with `value = max`, the anchor and cycle of the higher row (earlier anchor on a tie) and `boost_ends_at = max`, delete the row of `from`, insert the `merge` entry with reason `energy-lives.merge` and key `energy-lives:merge:{merge_id}` under `into`. Re-drive the source's pending refills before the unit. A replay with the same `merge_id` returns the original result. A `from` that does not exist merges nothing and succeeds.

---

## 8. The `energy_full` hand-off

After the write of step 8, compare the meter before and after the operation (both advanced to `now'`):

| Before | After | Emit |
|--------|-------|------|
| any | below cap, cycle new or `full_at` changed | `armed`, `subject_key = energy:{meter_code}:{cycle_started_at epoch seconds}`, `fire_at = full_at`, `expires_at = full_at + FULL_NOTICE_TTL_SECONDS`, `params = {meter_code, cap, value, meter_revision}` |
| below cap, cycle open | at or above cap by a refill, grant, refund or merge | `resolved` with the same `subject_key` |
| below cap | at cap by regeneration, observed at a later touch | nothing: the notification was armed with that `fire_at` and fires on its own |

Write the event to an outbox table in the same transaction as the meter (or use the project's equivalent); deliver at least once. The consumer upserts by (account, event, `subject_key`), so duplicates are harmless. This block never calls the push block.

---

## 9. Config publication (admin)

`publishMeterConfig` appends a version: `version = max + 1`, `effective_at` must be at or after the server's now (`effective_at_in_past` otherwise), field ranges as in the data model. Nothing else touches the table. The call takes no account selector: a body with `account_id`, `segment` or any field outside the version columns is `invalid_request` (INV-18). A published version affects each player at that player's next touch: no per-player migration runs (INV-1, INV-10). Review the lint before publishing: `full_wait = cap / regen_amount * regen_interval_seconds` is the longest free wait (INV-15); show it to the person who approves the change.

---

## Optional extension: friend gifts

Built only when `GIFTS_ENABLED`. Gifts are sent by the giver; there is no request or "ask for energy" route, because a request is an obligation placed on a friend (guide 06, tendency table).

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/energy/gifts` | Own inbox: `sent` gifts to claim |
| POST | `/api/energy/gifts` | `{ gift_id, recipient_handle, meter_code }` |
| POST | `/api/energy/gifts/{gift_id}/claim` | Claim into the meter |
| POST | `/api/energy/gifts/{gift_id}/decline` | Decline |
| PUT | `/api/energy/gift-settings` | `{ accept_gifts }` |

Send rules, all checked server-side in one unit: a friend link between sender and recipient exists (`ugc.friends-leaderboard` or the adopter's friend model) and is at least `GIFT_MIN_FRIEND_AGE_SECONDS` old; the recipient accepts gifts; the sender has sent fewer than `GIFTS_SENT_PER_DAY` today; the recipient's `sent` gifts are fewer than `GIFT_INBOX_MAX`; at most one gift per sender and recipient per `day_key`. A recipient who opted out, a non-friend and a too-new link all answer the same `gift_not_available`, so the answer reveals nothing about the recipient. Sending costs the sender nothing; the gift expires at `created_at + GIFT_TTL_SECONDS`.

Claim: `grantEnergy(recipient, meter, GIFT_UNITS, 'energy-lives.gift', gift_id, 'energy-lives:{recipient}:gift:{gift_id}')`. If nothing fits under the ceiling the gift stays `sent` and the response is `no_room` (409); a partly applied gift is claimed. An expired gift is `gift_expired`.

---

## Error Handling

Error bodies are `{ "error": code, ... }` with no stack traces. A retry of the same request with the same id is always safe.

| Code | HTTP | Extra fields | When |
|------|------|--------------|------|
| `invalid_request` | 422 | `field` | shape, range or `ID_PATTERN` violation |
| `unknown_meter`, `unknown_offer` | 404 | | |
| `attempt_not_found` | 404 | | another account's id is also 404 |
| `insufficient_energy` | 409 | `value`, `available`, `next_tick_at`, `full_at`, `server_now` | start cannot be afforded |
| `attempt_conflict` | 409 | | same id, other meter |
| `attempt_not_open` | 409 | `state` | confirm on a terminal attempt |
| `attempt_not_cancellable` | 409 | `state` | cancel after confirm |
| `already_full` | 409 | | refill at the cap |
| `no_room` | 409 | | `units` offer or gift claim does not fit |
| `price_changed` | 409 | `quote` | computed cost above `expected_cost` |
| `insufficient_balance` | 409 | `balance` | ledger refused |
| `boost_stack_limit` | 409 | | boost does not fit |
| `refill_not_available` | 403 | | minor without permission |
| `offline_attempts_disabled` | 409 | | |
| `gift_not_available`, `gift_expired`, `gift_inbox_full` | 409 | | optional extension |
| `rate_limited` | 429 | `retry_after_seconds` | `security.md` T-10 |
| `unavailable` | 503 | | retry with the same id |

## Anti-patterns

- A per-player or global job that adds points. It breaks INV-1 and adds a write per player per interval.
- Trusting a client timestamp, or letting the client increment the value when its countdown reaches zero.
- Spending with `UPDATE ... SET value = value - 1` without the `available` check inside the unit, or checking in application memory and writing later.
- Charging the ledger before the pending entry is durable, or crediting before the spend is known applied.
- Computing a refund from the current value alone: the ceiling needs `value_before`.
- Editing a config row in place. Back-dated or edited versions change values players already saw.
- Summing two meters on merge.
- Granting an ad reward on the client's say-so.
