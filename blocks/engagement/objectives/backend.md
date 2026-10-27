# Backend Patterns — Objectives, Missions and Achievements

> Snippets below are **L3 illustrative** (see `docs/SPEC_GUIDELINES.md` section 6). Each is at most 30 lines with the four markers. `db`, `ledger`, `config`, `HttpError` and `Ctx` are placeholders for the project's own data layer, the `billing.virtual-currency` client, config module, error type and request context (`ctx.tenantId`, `ctx.accountId` from the verified session, `ctx.now` from the server clock). The rules the handlers enforce are the invariants INV-1..INV-30 in `README.md` section 8 and the threats in `security.md`; reference them in tests by id.

## API Endpoints

### Signed-in player (session required; the account always comes from the session, never from a body)

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/api/objectives?scope=` | The caller's list: items, board state, starter progress, claimable count, next goal. `scope` is optional (one of the six scopes) |
| `POST` | `/api/objectives/sessions` | Open or continue a play session `{ session_id }`; idempotent per `session_id`; assigns the `session` plan within `SESSIONS_WITH_OBJECTIVES_PER_DAY` |
| `POST` | `/api/objectives/events` | Report client events `{ events: [{ event_id, metric, amount, occurred_at, ref?, attempt_id? }] }`, at most `EVENT_BATCH_MAX`; `attempt_id` is required for metrics with `requires_attempt` |
| `POST` | `/api/objectives/:instance_id/claim` | Claim one completed instance |
| `POST` | `/api/objectives/claim-all` | Claim up to `CLAIM_ALL_MAX` completed instances `{ scope? }` |
| `POST` | `/api/objectives/:instance_id/reroll` | Replace one active instance of a `pool` plan with a banked reroll |

There is no endpoint that reads, claims or rerolls by anything other than the caller's own instance id (INV-25), and none that accepts a reward, target, state or progress value from the client.

### List response

```json
{
  "server_now": "2026-10-21T12:00:00Z",
  "rules": { "unclaimed_at_reset": "stay_claimable", "reroll_tier_policy": "same_tier" },
  "board": {
    "daily": { "window_key": "2026-10-21", "ends_at": "2026-10-21T17:00:00Z", "points": 20, "tasks_total": 3, "tasks_completed": 1, "done": false, "bank": { "balance": 1, "cap": 2 } }
  },
  "starter": { "total": 6, "claimed": 0, "done": false },
  "claimable_count": 1,
  "next_goal": "7d1f0c2e",
  "items": [
    { "instance_id": "7d1f0c2e", "objective_id": "daily.win-3", "kind": "objective", "scope": "daily", "state": "active",
      "tier": 2, "progress": 1, "target": 3, "remaining": 2, "reward": [{ "currency": "coins", "amount": 40 }],
      "points": 30, "title_key": "objective.daily.win-3.title", "description_key": "objective.daily.win-3.description",
      "ends_at": "2026-10-21T17:00:00Z", "horizon": null, "chain": null, "locked_by": null, "carried_in": 0,
      "counts_from_normal_play": false, "rerollable": true }
  ]
}
```

`board` has one entry per live `daily` or `weekly` window. `items` follow the ordering rule (tier ascending, then `sort_order`, then id) inside each scope and exclude every `hidden_until_earned` instance that is not `completed` (INV-20). Text is returned as i18n keys; `deepen_test`, `template_id`, weights and the seed are never returned.

### Event request and response

Request `{ events: [{ event_id, metric, amount, occurred_at, ref?, attempt_id? }] }`. Response `200 { server_now, results: [{ event_id, outcome, counted_amount, reason? }], changed: [item], completed: [instance_id], board, next_goal }` where `outcome` is `counted`, `capped`, `duplicate` or `rejected`.

### Errors

| Status | `error` | When |
|--------|---------|------|
| 401 | `unauthenticated` | No valid session |
| 404 | `not_found` | Instance missing, or it belongs to another account (indistinguishable) |
| 409 | `not_completed` | Claim before completion |
| 409 | `not_active` | Reroll of an instance that is not `active` |
| 409 | `not_rerollable` | Reroll of an instance of a `fixed` plan or a plan without a bank |
| 409 | `no_reroll_available` | Bank balance is 0 |
| 409 | `no_replacement_available` | No candidate for the replacement; the bank is untouched |
| 422 | `invalid_request` | Body shape wrong, unknown keys |
| 422 | `batch_too_large` | More than `EVENT_BATCH_MAX` events; nothing is recorded |
| 429 | `rate_limited` | More than `ACCOUNT_EVENTS_PER_DAY_MAX` recorded events today, or the per-client rate limit |
| 409 | `ledger_rejected` | The ledger refused a grant (`reason` carries its error: `balance_limit_exceeded`, `unknown_currency`, `unknown_reason`, `idempotency_conflict`); the instance stays `completed`; grants of earlier reward lines stay applied and replay on retry |
| 503 | `ledger_unavailable` | A claim could not reach the ledger; state unchanged, safe to retry |

Per-event rejection reasons (inside a `200` response): `unknown_metric`, `metric_not_client_reportable`, `invalid_amount`, `event_too_old`, `attempt_required`, `attempt_not_proven`, `validation_failed`. For server events the outcome `ignored` carries `self_feeding`, `paid_source` or `paid_with_premium` (see "Adapter filters").

---

## Internal interfaces

| Function | Caller | Contract |
|----------|--------|----------|
| `ingest_server_event(account_id, source, source_ref, metric, amount, reason?)` | Other blocks, the ledger adapter, the game server | Same pipeline as a client event with `event_id = <source>:<source_ref>`; the only way to feed a `server_derived` metric. A ledger-derived event whose `reason` is `objectives.reward` is ignored (INV-24) |
| `mergeAccounts(from_account_id, into_account_id, merge_id)` | `auth.guest-account` conflict import | See "Account merge"; one-way, idempotent by `merge_id` (a repeat returns the first result), a second merge of the same guest fails `already_merged` |
| `holdings(account_id)` | `auth.guest-account` | See "Holdings" |
| `deleteAccount(account_id)` | `auth.guest-account` purge, `compliance.account-deletion` | Deletes every per-account row in all tables; safe to repeat |
| `publish_definitions(set)` | Operator tooling | Validates the whole set (metrics, definitions, plans) and activates it atomically, or returns every error and changes nothing. Returns warnings alongside success |
| `attemptState(account_id, attempt_id)` | This block, for metrics with `requires_attempt` | Provided by `engagement.energy-lives`; returns the attempt's state or none. A metric with `requires_attempt` and no hook fails the publish (`attempt_hook_missing`) |
| `validate_event(account_id, event)` | This block, for `client_validated` metrics | Provided by the game; returns ok or rejected. Absent hook plus a `client_validated` metric fails the publish (`validator_missing`) |
| `feature_unlocked(account_id, feature)`, `player_level(account_id)` | This block | Provided by the game |
| `current_season()` | This block | Provided by the season window provider |
| `ingest_xp(account_id, event_id, source, units, occurred_at)` | This block, to `engagement.season-pass` | One call per completion of a kind in `SEASON_XP_KINDS`, `event_id = completion_id`, `source = "objective.completed"`, `units = 1`, delivered at least once after the completion commits |

---

## Adapter filters

Server events from other blocks pass the adapter table of `README.md` section 6 before they reach the ingestion pipeline. Three filters implement INV-23 and INV-24; a filtered event is answered `ignored` and recorded nowhere:

1. `paid_source`: an `item_granted` event whose `source_kind` is `purchase`.
2. `self_feeding`: a ledger or `item_granted` event whose `reason` is `objectives.reward`.
3. `paid_with_premium`: a soft-currency spend or an `item_upgraded` event whose cost lines include a currency in `PREMIUM_CURRENCY_CODES`.

`queue_item_collected` is counted whether or not the collection was sped up (the event's `sped_up` is not read), and no adapter row exists for `queue_speedup_quoted`, `queue_speedup_applied`, any purchase event, any subscription event, or any invitation to buy. Publishing a metric whose `source` is in `FORBIDDEN_METRIC_SOURCES` fails (`forbidden_metric_source`).

## Settle

`settle(account, now)` runs inside the request transaction before anything else. It is idempotent and reads no client value.

1. For each active plan whose scope the account can have, compute the current window key and bounds (README "Window rule"). For `session`, only when the request opened a session.
2. If no `assignment_windows` row exists for `(account, plan, window_key)`: first close the plan's earlier live window (step 4), then insert the row, credit the reroll bank (step 3), build the instances (step 2), and insert the ladder milestones. The unique key makes a concurrent first request fail the insert and read the stored rows instead (INV-11).
3. Credit the bank: `balance = min(cap, balance + earn * elapsed)` with `elapsed` the number of windows since `credited_through_key`, at least 1 for a new bank (snippet "credit-reroll-bank"). Set `credited_through_key`. Windows the player never opened produce nothing else: no instances, no events, no deduction (INV-15).
4. Close finished windows: every instance of the plan's earlier window with state `active` or `locked` and `ends_at <= now` (or superseded by a newer window) becomes `expired` with `expired_at = now`, and `objective.expired` and `objective_expired` fire. For `carry_over` members at or above `CARRY_OVER_MIN_PERCENT` with `carried_in = 0`, the new window's instance of the same objective starts at that progress with `carried_in` set. A `session` window closes when a newer session opens or `last_seen_at + SESSION_IDLE_TIMEOUT_SECONDS <= now`.
5. If `UNCLAIMED_AT_RESET = auto_grant`: every `completed` instance of a closed window is claimed with the same procedure as a player claim, `claim_source = auto`.
6. Build instances (step 2 detail): fixed plans assign every `active` member; pool plans run the draw (snippet "draw-objectives") then scaling (snippet "scale-target"); each instance snapshots `definition_version`, `target` and `reward`. Instances whose prerequisites are not met start `locked`, the rest `active` with `activated_at = now`; `lifetime_total` instances read the metric counter as their first progress and may complete at once, which unlocks dependents in the same transaction.

Starter and lifetime plans are assigned the first time the account calls any endpoint (INV-19); there is no signup hook to forget.

**The block's own events.** After settling, a request that opens a session or records an event sends two server events through the ingestion pipeline: `session_started` (once per session, `source = objectives.session`, `source_ref = session_id`) and `active_day` (once per local day, `source = objectives.activity`, `source_ref = day_key`). Their idempotency keys make a repeat harmless, and `active_day` has a `day_cap` of 1.

## Event ingestion

Inside one transaction, under a per-account mutex (an advisory lock, `BEGIN IMMEDIATE` on SQLite, or a locked per-account row elsewhere) so the day cap and the counters cannot race:

1. Reject the whole request if the batch exceeds `EVENT_BATCH_MAX` (`batch_too_large`) or the account's recorded events today are at `ACCOUNT_EVENTS_PER_DAY_MAX` (`rate_limited`). Settle.
2. For each event in order: look up the metric (`unknown_metric`); a `server_derived` metric from the HTTP path is `metric_not_client_reportable`; `amount` must be a positive integer (`invalid_amount`); `occurred_at` older than `EVENT_MAX_AGE_SECONDS` is `event_too_old` (an `occurred_at` in the future is accepted and stored as the receive time); a metric with `requires_attempt` needs an `attempt_id` (`attempt_required`) whose state from `attemptState` is `confirmed`, `won` or `failed` (`attempt_not_proven`; INV-30); then a `client_validated` metric calls the validator with `ref` (`validation_failed`). The attempt check comes first, so an unproven attempt never reaches the validator.
3. Insert the `objective_events` row, with the `attempt_id` when the metric has one (snippet "event-insert"); no row returned means `duplicate`, answered with the stored `counted_amount`.
4. Clamp: `counted = min(amount, max_amount_per_event)`; for a `sum` metric with a `day_cap`, `counted = min(counted, day_cap - already counted today)` where "today" is the account's local day (the sum query in "event-insert"). Store `counted_amount` and `outcome` (`capped` when `counted < amount`).
5. Update `metric_counters`: add `counted` (sum) or keep the maximum (max).
6. For every active instance of the account whose `metric` equals the event's, or whose definition lists the metric in `alt_sources`: compute the value (`counted`, times `multiplier` for an alternate source, or the counter for `lifetime_total`) and apply it (snippet "apply-to-instance").
7. For each instance that completed: run the completion cascade.
8. Return results, changed items, completed ids, board and next goal.

A `max` metric with `counted = 0` changes nothing; a `sum` event that counted 0 still records its row so a replay stays a duplicate.

## Completion cascade

When an instance reaches `completed` (one transaction with the event):

1. Set `completed_at`; emit `objective.completed` with `completion_id = {objective_id}:{window_key}` and the analytics event `objective_completed`.
2. Unlock dependents: every `locked` instance of the same window whose `prerequisite_ids` are all `completed` or `claimed` becomes `active`; a `lifetime_total` dependent starts from the counter and may complete immediately, repeating this step (bounded by the chain length).
3. Board: if the definition is a task (`kind = objective`) of a plan with `board_points_metric`, call the ingestion pipeline for that metric with `amount = points`, `source = objectives.board`, `source_ref = <instance_id>:points` (a zero-point task sends nothing). If every non-replaced task of the window is now `completed` or `claimed` and `board_cleared_metric` is set, send `1` with `source_ref = <window_id>:cleared`, once, and fire `objective_board_done`. Milestones carry no points, so the cascade ends here.
4. Hand-offs after commit: for a kind in `SEASON_XP_KINDS`, `ingest_xp` to `engagement.season-pass`; for a scope in `REWARD_READY_SCOPES`, `objective_reward_ready` with `state = armed`. Both go through an outbox written in the same transaction and delivered at least once; their keys (`completion_id`, `subject_key`) make a repeat harmless.

## Claim

`POST claim` and `claim-all` run the procedure of snippet "claim-instance" per instance:

- Lock the caller's instance (`not_found` if it is not theirs). `claimed` returns the stored result with `already_claimed = true` and calls nothing. Not `completed` is `not_completed`.
- For each reward line `i` call the ledger `grant(account_id, currency, amount, "objectives.reward", instance_id, key)` with `key = objectives:{account_id}:{objective_id}:{window_key}:{i}`. A crash between the grants and the state update repeats the same keys on retry; the ledger replays and the state update then completes (INV-8).
- Store the returned `entry_id` values, set `claimed`, `claimed_at`; emit `objective.claimed` and `objective_claimed`; if a hand-off was armed, send `objective_reward_ready` with `state = resolved`.
- A ledger outage aborts the transaction (`503 ledger_unavailable`); a ledger rejection aborts it with `409 ledger_rejected` and the ledger's error name. Either way the instance stays `completed`, and earlier reward lines already applied replay on the next attempt. A rejection during `auto_grant` is logged and retried at the next settle.
- `claim-all` takes instances ordered by `completed_at`, then id, up to `CLAIM_ALL_MAX`; each is its own transaction, so one failure does not undo the others; the response lists a result per instance and `remaining`.

## Reroll

1. Lock the instance, its window and the account's bank. `replaced` returns the stored replacement (no cost). State other than `active`: `not_active`. Plan not `pool` or no bank: `not_rerollable`. Balance 0: `no_reroll_available`.
2. Candidates: the plan's `active` members the account has unlocked, minus every objective already in this window (replaced ones included), minus members sharing an `exclusive_group` with a live instance, filtered to the replaced instance's `tier` when `REROLL_TIER_POLICY = same_tier`, within the occupies cap. None: `no_replacement_available`.
3. Draw one (snippet "draw-objectives" with `n = 1`), seeded with the number of replaced instances in the window plus one, scale it, insert it `active` at progress 0, mark the old one `replaced` with `replaced_by_instance_id`, decrement the balance. Fire `objective_rerolled`.

## Account merge

`mergeAccounts(from_account_id, into_account_id, merge_id)` in one transaction, locking both accounts in sorted id order. It settles both accounts first. Insert the `account_merges` row; a conflict on `merge_id` returns the stored result, a conflict on `from_account_id` with a different `merge_id` is `already_merged`.

1. Counters: `sum` metrics add, `max` metrics take the maximum.
2. Windows: for each `(plan, window_key)` held by the guest: if the receiving account holds it too, merge rows by `(objective_id)`; otherwise move the window and its instances to the receiving account.
3. Matching rows: the higher state wins (`claimed`, `completed`, `active`, `locked`, `expired`, `replaced`); two `active` rows add progress (`sum`) or take the higher value (`max`), clamped at the receiving row's target, and complete if they reach it (snippet "merge-instance"). Unmatched guest rows in a window the receiving account already holds are kept only if `completed` or `claimed`.
4. Lifetime instances are recomputed from the merged counters and the normal unlock rules run, so tiers earned by the combined total complete.
5. Reroll banks: the higher balance, capped at the plan cap.
6. No ledger call is made (INV-22); balances of the guest account join the signed-in account by the rules of `billing.virtual-currency` and `data.progress-sync`.

## Holdings

`holdings(account_id)` returns what the account holds so the player can see what each conflict choice keeps (`auth.guest-account`). It returns an empty list when the account has no counter above zero and no instance beyond `locked` or `active` at progress zero. Otherwise it returns entries `{ category, label_key, paid, effect }` with `paid = false` for every entry (nothing here is bought):

| `category` | `label_key` | `effect` when this account is the guest | Covers |
|---|---|---|---|
| `progress` | `objectives.holdings.progress` | `carried` | Metric counters, starter and lifetime instances, achievements, and instances of windows the receiving account does not hold |
| `progress` | `objectives.holdings.unclaimed` | `carried` | `completed` unclaimed instances (the receiving account keeps its own row when it holds the same objective and window) |
| `progress` | `objectives.holdings.todays_board` | `kept_target` | Active or locked instances of a live `session`, `daily`, `weekly` or `seasonal` window; when the receiving account already holds that window its own board wins and the guest's rows are dropped |

## Pure core (no I/O)

Keep these functions free of I/O and clocks: pass values in. They are the code the unit tests exercise.

<!-- PATTERN: apply-to-instance -->
<!-- PURPOSE: Advance one active instance from an event value or the lifetime counter; clamp at the target; never decrease -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `Inst` is the row type of objective_instances; `value` is counted * multiplier for sum metrics or the counted score for max metrics; `counter` is the metric counter after this event; set completed_at and run the cascade in the caller -->
```typescript
type Inst = { state: string; progress: number; target: number; counting: "since_activation" | "lifetime_total" };

export function applyToInstance(i: Inst, agg: "sum" | "max", value: number, counter: number): Inst {
  if (i.state !== "active") return i;
  const next =
    i.counting === "lifetime_total" ? counter
    : agg === "sum" ? i.progress + value
    : Math.max(i.progress, value);
  const progress = Math.min(i.target, Math.max(i.progress, next)); // never decreases, never above target
  return { ...i, progress, state: next >= i.target ? "completed" : "active" };
}
```

<!-- PATTERN: window-keys -->
<!-- PURPOSE: Derive the account's local day key and week key from a server instant and an IANA timezone -->
<!-- REFERENCE: language=typescript runtime=node20+ -->
<!-- ADAPT: Intl.DateTimeFormat exists in Node 20, Bun and Deno; the window ends_at (next local midnight as a UTC instant) needs the timezone database too: use Intl offsets, Temporal where available, or AT TIME ZONE in Postgres; SQLite has no timezone support, compute in the app -->
```typescript
export function dayKey(instantMs: number, timeZone: string): string {
  // the en-CA locale formats as YYYY-MM-DD
  return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" })
    .format(new Date(instantMs));
}

export function weekKey(day: string, weekStartIso = 1): string {
  const d = new Date(day + "T00:00:00Z");
  const iso = d.getUTCDay() === 0 ? 7 : d.getUTCDay(); // 1 = Monday .. 7 = Sunday
  d.setUTCDate(d.getUTCDate() - ((iso - weekStartIso + 7) % 7));
  return d.toISOString().slice(0, 10);
}
```

<!-- PATTERN: draw-objectives -->
<!-- PURPOSE: Seeded weighted draw with a normal-play slot, exclusive groups, repeat avoidance and an occupies cap -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `rng` is a seeded PRNG built from the stored seed (a hash of tenant, account, plan, window key and reroll index feeding a 32-bit xorshift or a SHA-256 stream); it must be platform-independent so stacks A, B and C draw identically; `repeat` marks candidates drawn in the previous window -->
```typescript
type Cand = { id: string; weight: number; group: string; normalPlay: boolean; occupies: boolean; repeat: boolean };

export function draw(cands: Cand[], n: number, maxOccupies: number, rng: () => number): string[] {
  const picked: Cand[] = [];
  const ok = (c: Cand) =>
    !picked.includes(c) && !picked.some((p) => p.group === c.group) &&
    !(c.occupies && picked.filter((p) => p.occupies).length >= maxOccupies);
  const pickFrom = (pool: Cand[]): boolean => {
    const live = pool.filter(ok);
    const total = live.reduce((s, c) => s + c.weight, 0);
    if (total === 0) return false;
    let r = rng() * total;
    picked.push(live.find((c) => (r -= c.weight) < 0) ?? live[live.length - 1]);
    return true;
  };
  const flagged = cands.filter((c) => c.normalPlay);
  if (n > 0 && flagged.length) pickFrom(flagged.filter((c) => !c.repeat)) || pickFrom(flagged); // normal-play slot
  for (const pass of [cands.filter((c) => !c.repeat), cands]) {                                  // pass 1, pass 2
    while (picked.length < n && pickFrom(pass)) { /* keep drawing */ }
  }
  return picked.map((c) => c.id);
}
```

<!-- PATTERN: credit-reroll-bank -->
<!-- PURPOSE: Earn rerolls per elapsed window up to a cap, so a returning player gets a full bank and no backlog -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `windowsBetween(a, b)` counts day keys (daily plans) or week keys (weekly plans) from a to b, for example by UTC date arithmetic on the YYYY-MM-DD keys; persist balance and credited_through_key together with the new window row -->
```typescript
export function creditBank(
  balance: number, creditedThrough: string | null, current: string,
  earn: number, cap: number, windowsBetween: (a: string, b: string) => number,
): number {
  const elapsed = creditedThrough === null ? 1 : Math.max(0, windowsBetween(creditedThrough, current));
  return Math.min(cap, balance + earn * elapsed);
}
```

<!-- PATTERN: scale-target -->
<!-- PURPOSE: Scale a nominal target and its reward by the same bounded factor, from gameplay inputs only -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `input` is the median of recent window totals (lower middle for an even count) or the player level, depending on SCALING_INPUT; `history` is the number of windows read, pass Infinity for the level input; `c` is the configuration of README section 7; never pass spending, entitlement or ad state into this function -->
```typescript
export const median = (xs: number[]): number =>
  [...xs].sort((a, b) => a - b)[Math.floor((xs.length - 1) / 2)];

export function scaleTarget(nominal: number, reward: number, reference: number,
                            input: number | null, history: number, c: Cfg) {
  const enough = input !== null && history >= c.SCALING_MIN_HISTORY_WINDOWS;
  const factor = enough ? Math.min(c.SCALE_MAX, Math.max(c.SCALE_MIN, input / reference)) : 1;
  const round = (x: number) => Math.max(1, Math.floor(x * factor + 0.5)); // half up
  return { factor, target: round(nominal), reward: round(reward) };
}
```

<!-- PATTERN: claim-instance -->
<!-- PURPOSE: Pay one completed instance through the ledger with deterministic keys, safe to retry and to run twice at once -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `db.transaction` and `lockOwned` (a SELECT ... FOR UPDATE on Postgres, BEGIN IMMEDIATE on SQLite, a locking read in other engines) map to the project's data layer; `ledger.grant` is the client of billing.virtual-currency and returns { applied, balance, entry_id }; the claim_source of claim-all and of auto_grant is recorded by the caller -->
```typescript
export async function claimInstance(ctx: Ctx, instanceId: string) {
  return db.transaction(async (tx) => {
    const inst = await tx.instances.lockOwned(ctx.tenantId, ctx.accountId, instanceId);
    if (!inst) throw new HttpError(404, "not_found");           // also for another account's id
    if (inst.state === "claimed") return { instance: inst, alreadyClaimed: true };
    if (inst.state !== "completed") throw new HttpError(409, "not_completed");
    const entryIds: string[] = [];
    for (const [i, line] of inst.reward.entries()) {
      const key = `objectives:${ctx.accountId}:${inst.objectiveId}:${inst.windowKey}:${i}`;
      const g = await ledger.grant(ctx.accountId, line.currency, line.amount, "objectives.reward", inst.id, key);
      entryIds.push(g.entry_id);                                 // a replay returns the original entry
    }
    await tx.instances.markClaimed(inst.id, entryIds, ctx.now);
    return { instance: { ...inst, state: "claimed" }, alreadyClaimed: false };
  });
}
```

<!-- PATTERN: merge-instance -->
<!-- PURPOSE: Merge two rows of the same objective and window by state rank, adding progress only when both are active -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `a` is the receiving account's row; `b` is the guest's row; set completed_at to the merge time when two active rows reach the target; copy claimed_at and ledger_entry_ids with the higher-ranked row -->
```typescript
const RANK = { claimed: 5, completed: 4, active: 3, locked: 2, expired: 1, replaced: 0 } as const;

export function mergeInstance(a: Inst, b: Inst, agg: "sum" | "max"): Inst {
  const hi = RANK[b.state] > RANK[a.state] ? b : a;
  if (a.state !== "active" || b.state !== "active") {
    return { ...a, state: hi.state, progress: hi.progress };   // the more advanced row decides
  }
  const progress = agg === "sum" ? Math.min(a.target, a.progress + b.progress) : Math.max(a.progress, b.progress);
  return { ...a, progress, state: progress >= a.target ? "completed" : "active" };
}
```

<!-- PATTERN: event-insert -->
<!-- PURPOSE: Record an event once per account and event id, and read the day-cap usage -->
<!-- REFERENCE: dialect=postgres orm=raw-sql -->
<!-- ADAPT: ON CONFLICT DO NOTHING RETURNING works on Postgres and SQLite 3.35+; MySQL uses INSERT IGNORE and then checks the affected row count; $1 placeholders are Postgres style (MySQL and SQLite use ?); the day bounds are the account's local day as UTC instants -->
```sql
-- zero rows returned means the event id was already recorded (a duplicate)
INSERT INTO objective_events (id, tenant_id, account_id, event_id, metric, attempt_id, counted_amount, outcome, occurred_at, received_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
ON CONFLICT (tenant_id, account_id, event_id) DO NOTHING
RETURNING id;

-- counted amount of a metric inside the account's local day (day cap check)
SELECT COALESCE(SUM(counted_amount), 0) AS used
FROM objective_events
WHERE tenant_id = $1 AND account_id = $2 AND metric = $3
  AND received_at >= $4 AND received_at < $5;
```

---

## Publish-time validation

`publish_definitions(set)` validates the whole set and either activates it or returns the errors. Every row below has a case in `fixtures/definitions.json` `invalid_definitions` and a scenario in `expiry-and-versioning.feature`.

| Error | Rule | Invariant |
|-------|------|-----------|
| `unknown_metric` | `metric` or an alternate source is not in `objective_metrics` | INV-3 |
| `forbidden_metric_source` | A metric's `source` is in `FORBIDDEN_METRIC_SOURCES` (purchases, subscriptions, premium spend, speed-ups, invitations to buy, referral or gift purchases, store reviews) | INV-23 |
| `validator_missing` | A `client_validated` metric exists and no validator hook is configured | INV-3 |
| `attempt_hook_missing` | A metric has `requires_attempt` and no `attemptState` hook is configured | INV-30 |
| `social_invite_requires_skippable_board` | An objective on a metric whose `source` is `social-invite` sits outside a `pool` plan with `reroll_bank_cap > 0`, in a `starter` plan, or is a prerequisite | INV-27 |
| `premium_reward_requires_trusted_metric` | A reward currency is in `PREMIUM_CURRENCY_CODES` and the metric or an alternate source is `client_reported` | INV-4 |
| `premium_reward_not_scalable` | A premium-reward definition has `scalable = true` | INV-4, INV-17 |
| `reward_flow_not_registered` | A reward currency or item has no enabled `faucet` row with reason `objectives.reward` in the ledger's `currency_flows` | INV-8 |
| `objective_id_too_long` | `objective_id` longer than 48 characters (the ledger key must fit `LEDGER_IDEMPOTENCY_KEY_MAX_LENGTH`) | INV-8 |
| `target_not_positive`, `reward_empty` | `target < 1`, or `reward` has no line or a non-positive amount | |
| `target_exceeds_metric_cap` | `daily` target above the metric's `day_cap`, or `weekly` target above seven times it | INV-6 |
| `tier_out_of_range` | `tier` outside 1 to 3 | |
| `counting_not_allowed_for_scope` | A window scope uses `lifetime_total` | |
| `reset_policy_scope_mismatch` | `starter` or `lifetime` with a policy other than `none`; a window scope with `none` | INV-15 |
| `carry_over_in_pool` | `carry_over` on a member of a `pool` plan | INV-15 |
| `achievement_scope` | `kind = achievement` outside `lifetime`, or with a reset | INV-20 |
| `hidden_requires_achievement` | `hidden_until_earned` on anything but an achievement | INV-20 |
| `achievement_limit` | More than `MAX_ACHIEVEMENT_DEFINITIONS` active achievements | |
| `prerequisite_outside_plan` | A prerequisite is not a member of the same plan | INV-18 |
| `prerequisite_cycle` | The prerequisite graph has a cycle | INV-18 |
| `chain_tier_descends` | `tier` decreases along a chain | INV-18 |
| `alt_source_not_allowed` | `alt_sources` on a `max` metric, on `lifetime_total` counting, or with a non-integer multiplier | INV-26 |
| `occupies_requires_skippable_board` | `deepen_test = occupies` outside a `pool` plan with `reroll_bank_cap > 0`, or in a `starter` plan | INV-27 |
| `occupies_as_prerequisite` | An occupying objective is listed in another objective's `prerequisite_ids` | INV-27 |
| `plan_without_normal_play_objective` | A `daily` or `weekly` plan has no member with `counts_from_normal_play` | INV-26 |
| `draw_count_exceeds_groups` | `draw_count` above the number of distinct exclusive groups | |
| `reroll_bank_invalid` | `reroll_bank_cap < reroll_earn_per_window`, or a bank on a non-`pool` or non-daily/weekly plan | INV-16 |
| `milestone_points_not_allowed` | A `milestone` or `achievement` definition with `points > 0` | INV-28 |
| `ladder_rung_kind` | A ladder entry is not a `milestone` definition, or its metric is neither the plan's points nor cleared metric | INV-28 |
| `ladder_not_below_task_points` | The top points rung's target is not below the smallest possible board total (the `draw_count` smallest `points` among distinct groups, or the sum of a fixed plan's members) | INV-28 |
| `metric_change_requires_new_id` | A new version of an `objective_id` changes `metric` | INV-21 |
| `migration_unfavorable` | A retroactive migration raises a target or lowers a reward | INV-21 |

**Warnings** (returned with a successful publish, never blocking): `pool_narrow` when a `pool` plan has fewer members than `POOL_MIN_WIDTH_FACTOR * draw_count` (kit guide 13 recommends a pool wider than a week of boards; LOW). The same call returns the repeat-rate hint: none computed at publish; the rate is read from the analytics events `objective_assigned`.

## Versioning rules

| Change | In-flight instances | New assignments | Rule |
|--------|---------------------|-----------------|------|
| New version of an objective (target, reward, text, tier, points) | Keep the version they were assigned under, with their stored `target` and `reward` | Use the new `active` version | Instances snapshot target and reward (INV-21) |
| Retire an objective | Finish under their version | Never assigned again | In-flight and completed instances keep working; completed ones stay claimable. An objective removed by an update therefore either pays out (finished) or disappears with its window (unfinished); a hidden achievement nobody earned simply stops being assigned |
| Change a metric | Not allowed in place | A new `objective_id` | `metric_change_requires_new_id` |
| Retroactive migration (`apply_to_in_flight`) | Updated in place | | Allowed only when favorable: lower target, higher reward. A lowered target that the progress already meets completes the instance on the next settle |
| New lifetime or achievement objective | Veterans see their true counter (`lifetime_total`) and may complete at once | | Use `since_activation` to start everyone at zero; the choice is per definition |
| Delete | Never | | History and claims reference rows (INV-21) |

## Concurrency and transactions

| Operation | Must be atomic | Mechanism |
|-----------|----------------|-----------|
| Window assignment | Window row, instances, ladder, bank credit | One transaction; unique `(tenant, account, plan, window_key)`; the loser reads |
| Event ingestion | Event rows, counters, instance updates, cascade | One transaction under the per-account mutex |
| Claim | Ledger grants and the state change | Row lock on the instance; deterministic ledger keys make the sequence retryable; no extra "claiming" state |
| Reroll | Old instance, new instance, bank | One transaction with the instance, window and bank locked |
| Merge | Everything above for two accounts | Lock both accounts in sorted id order; `account_merges` unique keys |

## Housekeeping

- Delete `objective_events` older than `EVENT_RETENTION_SECONDS`; the age check (`EVENT_MAX_AGE_SECONDS`) keeps a replay of a deleted id from counting.
- Delete terminal instances (`claimed`, `expired`, `replaced`) older than `HISTORY_RETENTION_SECONDS`, and windows with no instances left. `completed` instances are never deleted.
- Account deletion removes every per-account row (`compliance.account-deletion`).

## Analytics events (server-written)

Properties are in addition to the shared envelope (`event_name`, `account_id`, `session_id`, `server_ts`, `client_ts`, `app_version`, `platform`). Client-written events are in `frontend.md`. `objective_progress` and `objective_claimed` use the names and property names of the kit's instrumentation guide; the others follow its naming rules.

| Event | Fires when | Properties |
|-------|-----------|------------|
| `objective_assigned` | An instance is created | `objective_id`, `scope`, `plan_id`, `window_key`, `tier`, `target`, `scaled`, `template_id`, `deepen_test`, `counts_from_normal_play`, `repeated_objective`, `repeated_template` |
| `objective_progress` | An instance's progress changed in a request (one event per instance per request) | `objective_id`, `progress`, `target`, `scope` |
| `objective_completed` | An instance reaches `completed` | `objective_id`, `scope`, `kind`, `tier`, `window_key`, `seconds_since_activation`, `deepen_test` |
| `objective_claimed` | A claim succeeds | `objective_id`, `entry_id` (first reward line), `scope`, `claim_source` (`player`, `claim_all`, `auto`), `reward_lines` |
| `objective_expired` | An incomplete instance expires | `objective_id`, `scope`, `progress`, `target`, `progress_percent`, `deepen_test`, `carried` |
| `objective_rerolled` | A reroll succeeds | `plan_id`, `from_objective_id`, `to_objective_id`, `from_tier`, `to_tier`, `progress_lost`, `bank_balance_after`, `deepen_test` |
| `objective_board_done` | The last task of a board completes | `plan_id`, `window_key`, `points`, `tasks_total`, `rerolls_used_in_window` |
| `starter_objectives_completed` | Every `starter` instance is `completed` or `claimed` for the first time | `seconds_since_first_contact` |
| `objective_events_rejected` | A request had rejected events | `metric`, `reason` (including `attempt_required` and `attempt_not_proven`), `count` (one event per metric and reason per request) |
| `objectives_merged` | A merge is applied | `from_account_id`, `instances_moved`, `instances_dropped`, `counters_merged` |
| `objective_reward_ready` | Hand-off to `messaging.push-reengagement` on the REMOTE lane | `subject_key`, `state` (`armed` or `resolved`), `fire_at`, `expires_at`, `params` (`objective_id`, `scope`) |

`deepen_test` on `objective_completed`, `objective_expired` and `objective_rerolled` is what lets reports compare, per class, what players do next (return the next day, reuse the feature) rather than completion rate alone, as the deepen-or-occupy test in kit guide 13 asks.

---

## Reference Migration (Postgres)

Dialect translation of the data model in `README.md` section 2. Every statement needs the `ADAPT` mapping below.

#### `objective_metrics` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: text PRIMARY KEY DEFAULT gen_random_uuid()::text becomes CHAR(36) with UUID() in MySQL, TEXT with an app-generated uuid4 in SQLite; timestamptz becomes DATETIME(6) in MySQL, ISO 8601 TEXT in SQLite; bigint becomes BIGINT / INTEGER; CHECK ... IN (...) works on SQLite and MySQL 8.0.16+ -->
```sql
CREATE TABLE IF NOT EXISTS objective_metrics (
  id                   text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  tenant_id            text NOT NULL,
  metric               varchar(255) NOT NULL,
  aggregation          text NOT NULL CHECK (aggregation IN ('sum','max')),
  trust                text NOT NULL CHECK (trust IN ('server_derived','client_validated','client_reported')),
  requires_attempt     boolean NOT NULL DEFAULT false,
  source               varchar(255) NOT NULL,
  max_amount_per_event bigint NOT NULL CHECK (max_amount_per_event > 0),
  day_cap              bigint CHECK (day_cap > 0),
  created_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, metric)
);
```

#### `objective_definitions` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: jsonb (reward, alt_sources, prerequisite_ids) becomes JSON in MySQL and TEXT holding a JSON string in SQLite; the partial unique index (one active version per objective) works on Postgres and SQLite, in MySQL enforce it in the publish step; other mappings as for objective_metrics -->
```sql
CREATE TABLE IF NOT EXISTS objective_definitions (
  id text PRIMARY KEY DEFAULT gen_random_uuid()::text, tenant_id text NOT NULL,
  objective_id varchar(255) NOT NULL, version bigint NOT NULL CHECK (version >= 1),
  status text NOT NULL CHECK (status IN ('draft','active','retired')),
  kind text NOT NULL CHECK (kind IN ('objective','achievement','milestone')),
  scope text NOT NULL CHECK (scope IN ('starter','session','daily','weekly','seasonal','lifetime')),
  metric varchar(255) NOT NULL, alt_sources jsonb NOT NULL DEFAULT '[]',
  counting text NOT NULL CHECK (counting IN ('since_activation','lifetime_total')),
  target bigint NOT NULL CHECK (target > 0), reward jsonb NOT NULL,
  tier bigint NOT NULL CHECK (tier BETWEEN 1 AND 3), points bigint NOT NULL DEFAULT 0 CHECK (points >= 0),
  deepen_test text NOT NULL CHECK (deepen_test IN ('deepens','neutral','occupies')),
  counts_from_normal_play boolean NOT NULL DEFAULT false, template_id varchar(255),
  prerequisite_ids jsonb NOT NULL DEFAULT '[]', chain_id varchar(255), chain_position bigint,
  horizon text CHECK (horizon IN ('short','medium','long')),
  visibility text NOT NULL CHECK (visibility IN ('visible','preview','hidden_until_earned')),
  reset_policy text NOT NULL CHECK (reset_policy IN ('none','forfeit','carry_over')),
  requires_feature varchar(255), scalable boolean NOT NULL DEFAULT false, scaling_reference bigint,
  sort_order bigint NOT NULL, title_key varchar(255) NOT NULL, description_key varchar(255) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, objective_id, version)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_od_active ON objective_definitions (tenant_id, objective_id) WHERE status = 'active';
```

#### `assignment_plans` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: jsonb (members, ladder) becomes JSON in MySQL and TEXT in SQLite; other mappings as for objective_metrics -->
```sql
CREATE TABLE IF NOT EXISTS assignment_plans (
  id                     text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  tenant_id              text NOT NULL,
  plan_id                varchar(255) NOT NULL,
  scope                  text NOT NULL CHECK (scope IN ('starter','session','daily','weekly','seasonal','lifetime')),
  mode                   text NOT NULL CHECK (mode IN ('fixed','pool')),
  draw_count             bigint CHECK (draw_count >= 1),
  reroll_earn_per_window bigint NOT NULL DEFAULT 0 CHECK (reroll_earn_per_window >= 0),
  reroll_bank_cap        bigint NOT NULL DEFAULT 0 CHECK (reroll_bank_cap >= reroll_earn_per_window),
  scaling_enabled        boolean NOT NULL DEFAULT false,
  avoid_repeat           boolean NOT NULL DEFAULT false,
  members                jsonb NOT NULL,
  ladder                 jsonb NOT NULL DEFAULT '[]',
  board_points_metric    varchar(255),
  board_cleared_metric   varchar(255),
  status                 text NOT NULL CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, plan_id)
);
```

#### `assignment_windows` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: same type mapping as objective_metrics; the unique key is the guard that makes two concurrent first requests produce one window -->
```sql
CREATE TABLE IF NOT EXISTS assignment_windows (
  id            text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  tenant_id     text NOT NULL,
  account_id    text NOT NULL,
  plan_id       varchar(255) NOT NULL,
  window_key    varchar(255) NOT NULL,
  starts_at     timestamptz,
  ends_at       timestamptz,
  draw_seed     varchar(255),
  last_seen_at  timestamptz,
  superseded_at timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, account_id, plan_id, window_key)
);
CREATE INDEX IF NOT EXISTS idx_aw_recent ON assignment_windows (tenant_id, account_id, plan_id, created_at DESC);
```

#### `reroll_banks` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: same type mapping as objective_metrics; enforce balance <= cap in the application because the cap lives in assignment_plans -->
```sql
CREATE TABLE IF NOT EXISTS reroll_banks (
  id                   text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  tenant_id            text NOT NULL,
  account_id           text NOT NULL,
  plan_id              varchar(255) NOT NULL,
  balance              bigint NOT NULL CHECK (balance >= 0),
  credited_through_key varchar(255) NOT NULL,
  updated_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, account_id, plan_id)
);
```

#### `objective_instances` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: numeric(4,2) becomes DECIMAL(4,2) in MySQL, NUMERIC in SQLite; jsonb (reward, ledger_entry_ids) becomes JSON in MySQL and TEXT in SQLite; the partial indexes work on Postgres and SQLite, MySQL has none: use full indexes and keep the state predicate in the query -->
```sql
CREATE TABLE IF NOT EXISTS objective_instances (
  id text PRIMARY KEY DEFAULT gen_random_uuid()::text, tenant_id text NOT NULL, account_id text NOT NULL,
  window_id text NOT NULL REFERENCES assignment_windows(id) ON DELETE CASCADE,
  objective_id varchar(255) NOT NULL, definition_version bigint NOT NULL,
  metric varchar(255) NOT NULL,
  counting text NOT NULL CHECK (counting IN ('since_activation','lifetime_total')),
  state text NOT NULL CHECK (state IN ('locked','active','completed','claimed','expired','replaced')),
  progress bigint NOT NULL DEFAULT 0 CHECK (progress >= 0), target bigint NOT NULL CHECK (target > 0),
  reward jsonb NOT NULL, scale_factor numeric(4,2), carried_in bigint NOT NULL DEFAULT 0,
  activated_at timestamptz, completed_at timestamptz, claimed_at timestamptz, expired_at timestamptz,
  replaced_by_instance_id text, ledger_entry_ids jsonb,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (progress <= target),
  UNIQUE (window_id, objective_id)
);
CREATE INDEX IF NOT EXISTS idx_oi_active ON objective_instances (tenant_id, account_id) WHERE state = 'active';
CREATE INDEX IF NOT EXISTS idx_oi_completed ON objective_instances (tenant_id, account_id) WHERE state = 'completed';
```

#### `metric_counters` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: same type mapping as objective_metrics; update with INSERT ... ON CONFLICT DO UPDATE (Postgres, SQLite) or ON DUPLICATE KEY UPDATE (MySQL) -->
```sql
CREATE TABLE IF NOT EXISTS metric_counters (
  id         text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  tenant_id  text NOT NULL,
  account_id text NOT NULL,
  metric     varchar(255) NOT NULL,
  total      bigint NOT NULL DEFAULT 0 CHECK (total >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, account_id, metric)
);
```

#### `objective_events` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: same type mapping as objective_metrics; the unique key is the idempotency guard of INV-2 and must exist in every dialect -->
```sql
CREATE TABLE IF NOT EXISTS objective_events (
  id             text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  tenant_id      text NOT NULL,
  account_id     text NOT NULL,
  event_id       varchar(255) NOT NULL,
  metric         varchar(255) NOT NULL,
  attempt_id     varchar(255),
  counted_amount bigint NOT NULL CHECK (counted_amount >= 0),
  outcome        text NOT NULL CHECK (outcome IN ('counted','capped')),
  occurred_at    timestamptz NOT NULL,
  received_at    timestamptz NOT NULL,
  UNIQUE (tenant_id, account_id, event_id)
);
CREATE INDEX IF NOT EXISTS idx_oe_day ON objective_events (tenant_id, account_id, metric, received_at);
CREATE INDEX IF NOT EXISTS idx_oe_retention ON objective_events (received_at);
```

#### `account_merges` table

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: same type mapping as objective_metrics; both unique keys must exist in every dialect (idempotency by merge id, one merge per guest account) -->
```sql
CREATE TABLE IF NOT EXISTS account_merges (
  id              text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  tenant_id       text NOT NULL,
  merge_id        varchar(255) NOT NULL,
  from_account_id text NOT NULL,
  into_account_id   text NOT NULL,
  applied_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, merge_id),
  UNIQUE (tenant_id, from_account_id)
);
```
