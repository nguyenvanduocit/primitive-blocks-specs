# Backend Patterns - Daily Streak

> Snippets are **L3 illustrative** (`docs/SPEC_GUIDELINES.md` section 6): at most 30 lines, four markers. `Ctx`, `db`, `ledger`, `cfg` and `HttpError` stand for the project's own request context, data layer, ledger client (`billing.virtual-currency`), configuration and error type. The behavior is the invariants INV-1 to INV-26 in `README.md` section 8; tests reference them by id. Time-zone arithmetic uses the project's tz library; the snippets use `Intl` only to show the shape.

## API Endpoints

All routes require a verified session; `account_id` and tenant come from it (INV-22). Bodies are JSON. A body containing any key not listed for the route, in particular `day_key`, `date`, `timestamp`, `claimed_at` or `account_id`, is rejected with 422 `unexpected_field` (INV-1). Every success body carries `server_now` (UTC instant, ISO 8601 with `Z`).

| Method | Path | Body | Purpose |
|--------|------|------|---------|
| `GET` | `/api/streak` | none | Settled view without writing (below). Returns `{ needs_timezone: true, server_now }` when no state exists |
| `PUT` | `/api/streak/timezone` | `{ timezone }` | First set creates the state (never counted); later changes are deferred and rate-limited (README section 3) |
| `POST` | `/api/streak/play` | `{ action, attempt_id }` | Only when `PLAY_REPORT_SOURCE = client`; otherwise the route does not exist and `recordPlay` is called by the host server. The proof comes from `PLAY_PROOF_SOURCE` either way |
| `POST` | `/api/streak/claim` | `{ repair?: "decline" }` | Claim today; idempotent |
| `POST` | `/api/streak/freeze` | `{ client_request_id }` | Buy a freeze (404 `not_purchasable` when the price is null) |
| `POST` | `/api/streak/repair` | `{ method: "currency" \| "play", client_request_id }` | Restore a lost streak |
| `POST` | `/api/streak/ack` | `{ kind: "notice" \| "loss_prompt" }` | Clear `unseen_notice`; count one proactive loss sheet |

### View payload (`GET /api/streak`)

| Field | Meaning |
|-------|---------|
| `timezone`, `pending_timezone`, `timezone_effective_at` | Zone in force and any deferred change |
| `today` | `{ day_key, status, ends_at, requirement, play_count, play_target, available_at? }`; `status` is `claimable`, `needs_play`, `claimed`, `waiting` (zone moved behind the last credited day) or `repair_decision` |
| `streak` | `{ current, longest, freezes_held, freeze_cap, at_risk }` computed from the settled state; `at_risk` is true when alive, unclaimed today and unprotected |
| `calendar` | `{ version, cycle_length, next_cycle_day, days: [{ day, lines, state }], milestones: [{ id, streak, lines, reached }] }`; `state` is `claimed`, `today` or `upcoming` |
| `repair_offer` | `{ streak_before, missed_days, expires_day_key, ends_at, methods: [{ method, price?, play_target?, play_count? }] }` or null. A paid method appears only when configured |
| `notice`, `loss_prompt` | `unseen_notice`, and `{ show }` where `show` is `prompts_shown < LOSS_PROMPT_CAP` |
| `claim` | Today's claim row when it exists (`kind`, `reward_lines`, `grant_status`) |

### Claim response

`200 { claim: { day_key, streak, cycle_day, reward_lines, milestone_ids, grant_status }, state, already_claimed, server_now }`. `grant_status = pending` is a normal success: the claim exists and delivery continues (INV-6).

### Errors

| Status | `error` | When |
|--------|---------|------|
| 401 | `unauthenticated` | No valid session |
| 409 | `timezone_required` | No state yet; set the zone first |
| 409 | `play_not_proven` | `PLAY_PROOF_SOURCE = attempt` and `attemptState` is null (`reason`: `attempt_unknown`) or not `confirmed`, `won` or `failed` (`reason`: `attempt_not_proven`) |
| 409 | `requirement_not_met` | `play_to_claim`, `play_count < PLAY_TARGET`; body has `play_count`, `play_target` |
| 409 | `repair_decision_required` | An offer is open and the body lacks `repair: "decline"`; body has the offer |
| 409 | `not_available_yet` | `today <= settled_through_day_key`; body has `available_at` |
| 409 | `insufficient_balance` | The ledger refused a `spend`; nothing changed |
| 409 | `freeze_cap_reached` | `freezes_held` plus pending freeze orders is at `FREEZE_CAP` |
| 409 | `repair_not_available` | body `reason`: `nothing_to_repair`, `window_closed` |
| 409 | `concurrent_update` | `MAX_CAS_RETRIES` exhausted; the client retries the same request |
| 404 | `not_purchasable` | Price is null for that item |
| 422 | `unexpected_field`, `invalid_timezone`, `unknown_action`, `invalid_request` | Validation |
| 429 | `timezone_rate_limited` | body has `next_change_at` |
| 429 | `rate_limited` | Per-account request limit (`security.md` T-9) |
| 202 | n/a | Purchase accepted and still pending (ledger unreachable); body `{ order: { status: "pending" } }` |

An error body is `{ error, ...fields }` with no stack trace.

---

## Pure core (no I/O, no clock)

Every function below takes `now` or a day key as an argument and has no import for a clock, storage or network. They are what the fixtures exercise without mocks.

### Day helpers

<!-- PATTERN: day-key-helpers -->
<!-- PURPOSE: Compute the local date of an instant, integer day arithmetic, and the start and end of a local day in any zone -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: replace Intl with the stack's tz library (java.time, Go time, Python zoneinfo, Temporal); keep the bisection definition of dayStart, which is correct for zones whose midnight does not exist; keep integer day_index subtraction -->

```typescript
const DAY_MS = 86_400_000;
export const dayIndex = (key: string): number => {
  const [y, m, d] = key.split("-").map(Number);
  return Date.UTC(y, m - 1, d) / DAY_MS;
};
export const keyOf = (index: number): string => new Date(index * DAY_MS).toISOString().slice(0, 10);
export const dayKeyOf = (ms: number, zone: string): string =>
  new Intl.DateTimeFormat("en-CA", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit" }).format(ms);

// Earliest instant whose local date is `key`; a zone that jumps from 23:59:59 to 01:00:00 starts that day at 01:00.
export function dayStart(zone: string, key: string): number {
  let lo = dayIndex(key) * DAY_MS - 3 * DAY_MS;
  let hi = dayIndex(key) * DAY_MS + 3 * DAY_MS;
  while (hi - lo > 1) {
    const mid = Math.floor((lo + hi) / 2);
    if (dayIndex(dayKeyOf(mid, zone)) >= dayIndex(key)) hi = mid;
    else lo = mid;
  }
  return hi;
}
export const dayEnd = (zone: string, key: string): number => dayStart(zone, keyOf(dayIndex(key) + 1));
```

Vectors: `fixtures/timezone-vectors.json` (`instant_to_day_key`, `day_bounds`, `day_index`, `consecutive_pairs`).

### Settlement

<!-- PATTERN: settle-missed-days -->
<!-- PURPOSE: Account for every local day before today: excuse, freeze, reset or decay, and open a repair offer -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: State, Cfg and Settled are the project's types (field names follow streak_states); existsInZone drops dates the zone skipped; excused(day) is built from DOWNTIME_WINDOWS with dayStart and dayEnd; notices are derived from the returned rows and the lowered streak -->

```typescript
export function settle(s: State, today: string, cfg: Cfg, excused: (day: number) => boolean): Settled {
  const out: Settled = { state: { ...s }, rows: [] };
  if (s.settledThrough === null) return out;
  const last = dayIndex(s.settledThrough);
  const t = dayIndex(today);
  if (t - 1 <= last) return out;                              // nothing to account for, or zone behind
  const missed = range(last + 1, t - 1).filter(existsInZone); // skipped dates are not missed
  const open = missed.filter((d) => !excused(d));
  missed.filter(excused).forEach((d) => out.rows.push({ kind: "excused", dayKey: keyOf(d) }));
  out.state.settledThrough = keyOf(t - 1);
  if (open.length === 0 || s.currentStreak === 0) return out;
  const lose = (after: number) => {
    out.state.currentStreak = after;
    const ok = s.currentStreak >= cfg.repairMinStreak && t - open[0] <= cfg.repairWindowDays;
    out.state.repairOffer = ok
      ? { streakBefore: s.currentStreak, gapFirst: keyOf(open[0]), expires: keyOf(open[0] + cfg.repairWindowDays), promptsShown: 0 }
      : null;
  };
  if (cfg.missPolicy === "decay") lose(Math.max(0, s.currentStreak - cfg.decayPerMissedDay * open.length));
  else if (cfg.missPolicy === "freeze_protected" && s.freezesHeld >= open.length) {
    out.state.freezesHeld -= open.length;                     // all or nothing (INV-9)
    open.forEach((d) => out.rows.push({ kind: "frozen", dayKey: keyOf(d) }));
  } else lose(0);
  return out;
}
```

Vectors: `fixtures/streak-vectors.json` (22 cases: claim, miss policies, freezes, milestones, repair) and `fixtures/account-cases.json` (`downtime`).

### Reward resolution

<!-- PATTERN: resolve-reward-lines -->
<!-- PURPOSE: Turn a streak step into calendar lines plus crossed milestones, clipping freeze lines to the cap -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: Calendar is the parsed CALENDAR configuration; item and currency lines pass through unchanged and are mapped to ledger codes at delivery; keep the crossing test (before < streak <= after) so repairs and merges never skip a milestone -->

```typescript
export function resolveReward(cal: Calendar, before: number, after: number, granted: string[], held: number, cap: number) {
  const cycleDay = ((after - 1) % cal.cycleLength) + 1;
  const lines = cal.days.find((d) => d.day === cycleDay)!.lines.map((l) => ({ ...l }));
  const crossed = cal.milestones.filter(
    (m) => m.streak > before && m.streak <= after && !(m.once && granted.includes(m.id)),
  );
  crossed.forEach((m) => lines.push(...m.lines.map((l) => ({ ...l }))));
  let room = cap - held;
  for (const l of lines) {
    if (l.kind !== "freeze") continue;
    const applied = Math.min(l.amount, Math.max(0, room));
    room -= applied;
    if (applied < l.amount) l.capped = true;
    l.amount = applied;
  }
  return { cycleDay, lines, milestoneIds: crossed.map((m) => m.id) };
}
```

---

## Claim

### Transaction (compare-and-swap, then grant)

1. One `server_now` per attempt. Load the state and today's claim row. If the claim row exists, return it with `already_claimed = true` (INV-4).
2. Apply a due `pending_timezone` (below), then `settle`. Run the gates in order: `today <= settled_through` gives `not_available_yet`; an open offer without `repair: "decline"` gives `repair_decision_required`; `play_to_claim` with `play_count < PLAY_TARGET` gives `requirement_not_met`. A decline clears the offer and records `streak_repair_declined`.
3. Resolve the lines from `streak_before` and `streak_after = current_streak + 1`; apply `freeze` lines to `freezes_held` here.
4. In **one transaction**: update the state row `WHERE id = ? AND version = ?` setting `version = version + 1`; insert the settlement rows (`frozen`, `excused`) and the claim row (`grant_status = pending`, or `none` when no line goes to the ledger). Zero rows updated or a unique violation on `(tenant, account, day_key)` is a lost race: roll back and go to step 1, at most `MAX_CAS_RETRIES` times, then `409 concurrent_update` (INV-3, INV-5).
5. After commit, deliver (below) and answer.

<!-- PATTERN: claim-compare-and-swap -->
<!-- PURPOSE: One credit per account and day under concurrent devices and retries -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: db.tx is the project's transaction helper; on SQLite use a write transaction (BEGIN IMMEDIATE) or the same version predicate; map the dialect's unique-violation error to the lost-race branch; throw the gate errors with the HTTP codes of the Errors table -->

```typescript
export async function claim(ctx: Ctx, accountId: string, decline: boolean) {
  for (let attempt = 0; attempt < cfg.MAX_CAS_RETRIES; attempt++) {
    const now = ctx.clock.now();                                   // the only clock read
    const st = await ctx.db.getState(accountId);
    const zone = zoneInForce(st, now);
    const today = dayKeyOf(now, zone);
    const existing = await ctx.db.getClaim(accountId, today);
    if (existing) return { claim: existing, alreadyClaimed: true };
    const s = settle(applyPendingZone(st, now), today, cfg, excusedFor(zone));
    gates(s, today, decline, await ctx.db.getPlay(accountId, today)); // throws 409 errors
    const r = resolveReward(cfg.calendar, s.state.currentStreak, s.state.currentStreak + 1,
      s.state.milestonesGranted, s.state.freezesHeld, cfg.FREEZE_CAP);
    const won = await ctx.db.tx(async (tx) => {
      const n = await tx.updateStateIfVersion(st.id, st.version, nextState(s, r, today, now));
      if (n === 0) return false;                                    // another device committed first
      await tx.insertDays([...s.rows, claimRow(r, today, now)]);   // UNIQUE (tenant, account, day_key)
      return true;
    }).catch((e) => (isUniqueViolation(e) ? false : Promise.reject(e)));
    if (won) return deliver(ctx, await ctx.db.getClaim(accountId, today));
  }
  throw new HttpError(409, "concurrent_update");
}
```

### Delivery (record, then grant)

For each stored line at position `i` (1-based, counting every line): skip `freeze` lines and lines with `amount = 0`; call `grant(account_id, code, amount, "daily-streak.claim", claim.id, "daily-streak:{account_id}:{day_key}:{i}")`. When every call returned, set `grant_status = granted`, store the `entry_id` list and `granted_at`. A transient failure (timeout, 5xx) leaves `pending` and the response is still 200 with `grant_status = pending`. A permanent rejection (unknown currency code) sets `failed` and raises an operator alert; the claim and streak stand (INV-6). Replaying `grant` with the same key returns the original result (ledger contract), so a request handler and the recovery sweep may run at once.

<!-- PATTERN: deliver-claim-lines -->
<!-- PURPOSE: Grant each stored line through the ledger with a stable idempotency key and mark the claim delivered -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: ledger.grant is the billing.virtual-currency client; isTransient maps that client's retryable errors; keep the key format and the 1-based line position exactly -->

```typescript
export async function deliver(ctx: Ctx, claim: ClaimRow): Promise<ClaimRow> {
  const entries: string[] = [];
  try {
    for (const [i, line] of claim.rewardLines.entries()) {
      if (line.kind === "freeze" || line.amount === 0) continue;   // applied in the claim transaction
      const key = `daily-streak:${claim.accountId}:${claim.dayKey}:${i + 1}`;
      const res = await ctx.ledger.grant(claim.accountId, line.code, line.amount, "daily-streak.claim", claim.id, key);
      entries.push(res.entry_id);
    }
  } catch (e) {
    if (isTransient(e)) return claim;                              // stays pending; the sweep retries
    await ctx.db.markGrantFailed(claim.id);
    throw e;
  }
  return ctx.db.markGranted(claim.id, entries);
}
```

Vector: `fixtures/account-cases.json` `pending_grant` (three ledger calls with keys `:1`, `:2`, `:4`).

### Recovery sweep

Every `RECOVERY_SWEEP_SECONDS`: select `daily_claims` with `grant_status = pending` and `claimed_at` older than `RECOVERY_GRACE_SECONDS`, call `deliver`; select `protection_orders` with `status = pending` older than the same grace and complete or refund them (below). A row pending beyond `RECOVERY_ALERT_MINUTES` raises an alert.

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: $1 tenant, $2 now minus RECOVERY_GRACE_SECONDS; add FOR UPDATE SKIP LOCKED on Postgres and MySQL 8 when several sweepers run; SQLite runs one sweeper -->
```sql
SELECT id, account_id, day_key, reward_lines
FROM daily_claims
WHERE tenant_id = $1 AND grant_status = 'pending' AND claimed_at < $2
ORDER BY claimed_at
LIMIT 100;
```

---

## Play counter

`recordPlay(account_id, action, attempt_id)` (or `POST /api/streak/play { action, attempt_id }` when `PLAY_REPORT_SOURCE = client`):

1. `action` must be in `PLAY_ACTIONS`, else 422 `unknown_action`.
2. **Proof** (INV-24). With `PLAY_PROOF_SOURCE = attempt`, call `attemptState(account_id, attempt_id)` of `engagement.energy-lives` (in-process; the account id comes from the session or from the calling server, never from a body). `null` answers 409 `play_not_proven` with `reason = attempt_unknown`. A state other than `confirmed`, `won` or `failed` (an `open`, `cancelled`, `expired` or `rejected` attempt) answers `reason = attempt_not_proven`; an `open` attempt proves nothing, which is what makes a refunded start safe. With `PLAY_PROOF_SOURCE = event` the id is the host's own server-verified play id and is trusted as given.
3. Today's `day_key` from the server clock and the zone in force. If a `daily_play` row with this `play_key` exists for the account on any day, change nothing and return `counted: false` with `reason: already_counted`; a concurrent duplicate that hits the UNIQUE `(tenant, account, play_key)` is the same answer. If today's rows already number `max(PLAY_TARGET, REPAIR_PLAY_TARGET)`, return `counted: false` with `reason: cap_reached`. Otherwise insert the row.
4. Return `{ play_count, qualified, counted }` where `play_count` is today's row count and `qualified = play_count >= PLAY_TARGET`.

Vector: `fixtures/account-cases.json` `play_counter` (attempt states `won`, `failed`, `confirmed` count; `open`, `cancelled` and an unknown attempt do not; a replayed attempt does not count again, not even on the next day). With `PLAY_PROOF_SOURCE = event` the count is bounded and replay-safe, not trustworthy (`security.md` T-7).

## Time zone

- **Validation**: the identifier must exist in the server's tz database, compared as written; offsets (`+02:00`), abbreviations and free text give 422 `invalid_timezone` (`fixtures/timezone-vectors.json` `timezone_validation`).
- **First set**: creates the state with `settled_through_day_key = null`; no `timezone_changes` counting (the row has `from_timezone = null`).
- **Later change**: same zone as in force or as pending is a no-op. Otherwise count `timezone_changes` rows of the account with `changed_at > now - TIMEZONE_WINDOW_DAYS`; at or above `TIMEZONE_CHANGES_PER_WINDOW` answer 429 `timezone_rate_limited` with `next_change_at` = the oldest counted row's `changed_at` plus the window. Else insert the row and set `pending_timezone` and `timezone_effective_at = day_end(zone in force, today)`. A second request while one is pending replaces it and counts again.
- **`applyPendingZone(state, now)`**: when `now >= timezone_effective_at`, settle in the old zone up to the end of that day, switch the zone, record `excused` rows for dates skipped by the move (README section 3), clear the pending fields, and continue with the new zone. Reads call it without persisting; writes persist it.
- **`zoneInForce(state, now)`**: the pending zone when `now >= timezone_effective_at`, otherwise `timezone`.
- **Deadline**: after every write set `streak_deadline_at = day_end(zone in force, settled_through + 1)` (null when the streak is 0).

Vectors: `timezone_rate_limit` and `timezone_switch` in `fixtures/timezone-vectors.json`.

## Freeze and repair orders

Both follow one order saga so a retry is a replay and a crash is recoverable (INV-7).

1. **Create** (transaction, CAS on the state): validate. Freeze: price configured, `freezes_held` plus pending freeze orders below `FREEZE_CAP`. Repair: an open offer, `today <= expires_day_key`, and for `method = play` today's `play_count >= REPAIR_PLAY_TARGET`. Insert the order (`pending`, price snapshot, repair `missed_day_keys`). A repeated `client_request_id` returns the stored order.
2. **Spend** (`method = currency` only): `spend(account_id, currency, amount, "daily-streak.freeze-purchase" | "daily-streak.repair-purchase", order_id, "daily-streak:{account_id}:{order_id}")`. `insufficient_balance` sets the order `rejected` and ends. A transient error leaves it `pending` and answers 202.
3. **Apply** (transaction, CAS): re-check validity. Freeze: `freezes_held + 1`. Repair: `current_streak = streak_before`, `repaired` rows for each gap day that has no row yet, `settled_through = today - 1`, offer cleared. Set the order `completed`. A repair price is `REPAIR_PRICE_PER_MISSED_DAY * missed days`; `method = play` has no price and no ledger call.
4. **Refund**: when step 3 finds the order invalid after a successful spend, `grant(account_id, currency, amount, "daily-streak.repair-refund", order_id, "daily-streak:{account_id}:{order_id}:refund")` and set `refunded`.

A repair covers exactly the days listed in its order; a later day that has passed since is settled by the normal rules.

## Sweeps

**At-risk sweep** every `AT_RISK_SWEEP_MINUTES` when `AT_RISK_ENABLED`: candidates are states with `current_streak >= AT_RISK_MIN_STREAK`, `streak_deadline_at` between now and now plus `AT_RISK_LEAD_HOURS`, `at_risk_day_key` different from the day being protected (`settled_through + 1`), and (unless `AT_RISK_WHEN_PROTECTED`) no freeze held under `freeze_protected`. For each: emit `streak_at_risk` with `state = armed`, `subject_key = streak:{day_key}`, `fire_at = now`, `expires_at = streak_deadline_at`, `params = { streak_length, freezes_held, cycle_day, reward_code, reward_amount }` (the last three come from `resolveReward` for the next claim: its cycle day and its first ledger-bound line; no loss wording or variable, INV-26), then set `at_risk_day_key` (INV-17). When a claim, freeze consumption or repair credits that day and `at_risk_day_key` equals its key, emit `resolved` with the same `subject_key`.

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: $1 tenant, $2 now, $3 now plus AT_RISK_LEAD_HOURS, $4 AT_RISK_MIN_STREAK; the day key being protected is computed per row in the app because it depends on the zone; MySQL needs a full index in place of the partial one -->
```sql
SELECT id, account_id, current_streak, freezes_held, settled_through_day_key, streak_deadline_at, at_risk_day_key
FROM streak_states
WHERE tenant_id = $1 AND current_streak >= $4
  AND streak_deadline_at > $2 AND streak_deadline_at <= $3
ORDER BY streak_deadline_at
LIMIT 500;
```

**Retention**: delete `daily_claims` and `daily_play` rows older than `CLAIM_RETENTION_DAYS` (a pruned play id could be counted again only if `attemptState` still reports that attempt as proof, so keep the retention at least as long as the attempt block keeps its attempts); `current_streak` lives in `streak_states` and is unaffected. Terminal `protection_orders` and `timezone_changes` older than the window may be pruned the same way.

## Participant operations

All three are in-process calls from `auth.guest-account`, the guest purge and `compliance.account-deletion`; none is a client route (INV-22).

- `holdings(account_id)`: read the row and return `[]` when it is absent or a tombstone. Otherwise return `{ category: "progress", label_key: "daily_streak.streak", paid: false, effect: "carried" }` when `current_streak > 0` and `{ category: "items", label_key: "daily_streak.freezes", paid: false, effect: "carried" }` when `freezes_held > 0`.
- `mergeAccounts(from_account_id, into_account_id, merge_id)`, one-way and idempotent by `merge_id`:
  1. Reject `from = into` with 422 `invalid_request`. Load the `from` row. No row: return `{ status: "nothing_to_merge" }`. A tombstone with the same `merge_id`: return `{ status: "already_merged", into }` and change nothing. A tombstone with another `merge_id`: fail `already_merged`.
  2. One transaction: load both rows, settle both at the `into` account's `today`, apply the section 3 merge table to the `into` row with a compare-and-swap on its `version`, turn the `from` row into a tombstone (`merged_into_account_id`, `merge_id`, counters zeroed) and delete the `from` account's rows in `daily_claims`, `daily_play`, `protection_orders` and `timezone_changes`. Two concurrent calls with one `merge_id` end with one winner; the other sees the tombstone (UNIQUE `(tenant, merge_id)`) and returns `already_merged`.
  3. Return `{ status: "merged", into }` where `into` is the merged summary.
- `deleteAccount(account_id)`: delete the account's rows in `streak_states` (a merge tombstone included), `daily_claims`, `daily_play`, `protection_orders`, `timezone_changes` (INV-23). Ledger entries belong to `billing.virtual-currency`.

Vectors: `fixtures/account-cases.json` `merge_cases`, `merge_idempotency` and `holdings`.
