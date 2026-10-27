# Backend Patterns — Season Pass

> Snippets below are **L3 illustrative** (see `docs/SPEC_GUIDELINES.md` section 6). Each is at most 30 lines with the four markers. `db`, `tx`, `ledger`, `purchases`, `config`, `err` and `Ctx` are placeholders for the project's own data layer, ledger client, purchase-record client, config module, error type and request context. The rules these handlers enforce are INV-1 to INV-26 in `README.md` section 8 and T1 to T12 in `security.md`; reference them in tests by id.

## API Endpoints

`account_id` and `tenant_id` always come from the player's session (or from the service credential for the internal call), never from a body (INV-21). Timestamps in every response are UTC instants in ISO 8601 with `Z`.

### Player (session)

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/api/season-pass/current` | State of the active season, or `{ server_now, season: null, next_season }` between seasons |
| `GET` | `/api/season-pass/seasons/{season_id}` | The caller's state and results for any season they have a progress row in (active, claim window or closed); 404 `season_not_found` otherwise |
| `GET` | `/api/season-pass/seasons/{season_id}/premium-offer` | Full premium contents and sale state, for the upsell sheet |
| `POST` | `/api/season-pass/claims` | Claim `{ season_id, items: [{ track, tier }] }` or `{ season_id, all: true }` |
| `POST` | `/api/season-pass/premium` | Confirm a premium purchase `{ season_id, store_transaction_id }`; reads the purchase record, idempotent |
| `GET` | `/api/season-pass/seasons/{season_id}/skip-quote?count=N` | Price, XP and resulting tier of skipping `N` tiers |
| `POST` | `/api/season-pass/skips` | Buy a skip `{ season_id, from_tier, count, price_shown }` |
| `POST` | `/api/season-pass/boosts` | Buy a boost `{ season_id, boost_code, price_shown }` |

**State response** (`current` and `seasons/{id}`), the only shape the screens read:

```
{ server_now,
  season: { season_id, name, starts_at, ends_at, claim_until, phase,        // active | claim_window | closed
            premium_product_code, unclaimed_policy },                        // auto_claim | forfeit
  tiers: [ { tier, xp_cost, cumulative_xp, free, premium } ],               // free and premium: { code, amount } or null
  repeat: { xp_per_tier, max_tiers, free, premium } | null,
  me: { total_xp, tier, xp_into_tier, xp_for_next_tier, premium_state,
        claimed: [ { track, tier, state } ], claimable: [ { track, tier } ],
        premium_locked_reward_count, active_boost, settled },
  skip: { enabled, price_per_tier, max_count } | null,
  boosts: [ { boost_code, multiplier_percent, duration_seconds, price, fits_in_season } ],
  next_season: { season_id, name, starts_at } | null }
```

A read after `ends_at` first completes the caller's `pending` rows and, under `auto_claim`, settles the caller (section "Settlement"), so the screen never shows a state the job has not caught up to. `tier`, `xp_into_tier`, `xp_for_next_tier` and `claimable` are computed on the response, never read from storage (INV-4).

**Claim response**: `200 { server_now, results: [{ track, tier, outcome, reason?, reward? }], state }`. `outcome` is `granted`, `already_claimed` or `rejected`; `reason` for a rejected cell is `tier_not_reached`, `premium_required`, `no_reward` or `ledger_unavailable` (the row stays `pending`). Request-level failures are HTTP errors (table below). `items` holds at most `MAX_TIERS + REPEAT_TIER_LIMIT` entries per track.

**Premium-offer response**: `{ server_now, season_id, ends_at, sale_open, premium_product_code, tiers: [{ tier, free, premium }], repeat: { free, premium } | null, earned_count, unclaimed_policy, refund_policy, value_figure? }`. `tiers` lists every tier with both tracks and nothing is omitted (INV-18). `value_figure` exists only when `PREMIUM_VALUE_FIGURE` is on and is computed from prices the shop actually charges (README section 3, "Disclosure before purchase"; INV-26). `sale_open` is false when `ends_at - server_now < PREMIUM_SALE_MIN_REMAINING_SECONDS`, when the season is not active, or when `premium_state = active`. The store's price string is not in this response: it comes from the store on the device.

### Internal (service credential, never reachable from a device)

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/internal/season-pass/xp` | Ingest `{ account_id, event_id, source, units, attempt_id?, occurred_at? }`; answers 200 with the outcome (`credited`, `capped`, `no_active_season`, `attempt_already_credited`) |
| in-process | `activate_premium`, `sync_premium_state` | Called by the purchase contract's `on_purchase_state_changed` and by the reconcile job |
| in-process | `holdings(account_id)`, `mergeAccounts(from_account_id, into_account_id, merge_id)`, `deleteAccount(account_id)` | The participant calls of `auth.guest-account` (section "Account lifecycle") |
| scheduler | `settle_season(season_id)`, `reconcile_pending()`, `recheck_premium()`, `prune_xp_events()` | Jobs (section "Jobs") |
| operator | `publish_season(definition)` | Validates and publishes (`README.md` section 3) |

---

## Pure core (no I/O)

Keep these functions free of I/O and clocks: pass instants in. They are what the unit tests exercise, and they run unchanged on a server, in a client, and in a test (INV-4).

### Tier derivation

`cum(i)` is the cumulative XP to reach tier `i`; the tier is a function of total XP and the table alone.

<!-- PATTERN: tier-derivation -->
<!-- PURPOSE: compute the current tier from total XP and the tier table; no stored tier exists -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: the Season shape -> your loaded definition; for tier tables with more than a few hundred tiers precompute `cum` once per season and cache it with the definition (it never changes after publish); keep the arithmetic in integers -->
```typescript
type Season = { tiers: { xpCost: number }[]; repeatXp: number; repeatMax: number };

function cumulative(s: Season): number[] {
  const cum = [0];
  for (const t of s.tiers) cum.push(cum[cum.length - 1] + t.xpCost);
  return cum;
}

function tierFor(totalXp: number, s: Season): number {
  const cum = cumulative(s);
  const n = s.tiers.length;
  if (totalXp < cum[n]) {
    let t = 0;
    while (cum[t + 1] <= totalXp) t++;
    return t;
  }
  if (s.repeatXp === 0 || s.repeatMax === 0) return n;
  return n + Math.min(Math.floor((totalXp - cum[n]) / s.repeatXp), s.repeatMax);
}
```

The 15 vectors in `fixtures/season-2026-10.json` (`tier_derivation_cases`) are the unit test. `xp_into_tier` and `xp_for_next_tier` follow `README.md` section 2.

### Caps and boost

`remaining` values are computed by the caller from `xp_events` sums inside the locked transaction; this function only combines them.

<!-- PATTERN: xp-caps -->
<!-- PURPOSE: reduce requested base XP by the smallest remaining allowance and name the cap that bound it -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: a configured cap of 0 means "no cap": map it to null before calling; keep the order of the array, it decides which cap is named on a tie -->
```typescript
type Remaining = { sourceDaily: number | null; sourceSeason: number | null; totalDaily: number | null };

function applyCaps(requested: number, r: Remaining) {
  const caps: [string, number | null][] = [
    ["source_daily", r.sourceDaily],
    ["source_season", r.sourceSeason],
    ["total_daily", r.totalDaily],
  ];
  let allowed = requested;
  let cappedBy: string | null = null;
  for (const [name, remaining] of caps) {
    if (remaining === null) continue;
    const room = Math.max(0, remaining);
    if (room < allowed) { allowed = room; cappedBy = name; }
  }
  return { allowed, cappedBy };
}

const credited = (allowed: number, boostPercent: number) => Math.floor((allowed * boostPercent) / 100);
```

### Catch-up XP

<!-- PATTERN: catch-up-xp -->
<!-- PURPOSE: deterministic late-join grant from season elapsed time, in integers -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: use BigInt (or a decimal type) when cumLast x percent x elapsed can exceed 2^53, about 9e15; elapsed is whole seconds from starts_at to the server instant -->
```typescript
function catchUpXp(cumLast: number, percent: number, elapsedSeconds: number, durationSeconds: number): number {
  return Math.floor((cumLast * percent * elapsedSeconds) / (100 * durationSeconds));
}
```

`fixtures/season-2026-10.json` (`catch_up_cases`) gives the expected values.

### Claimable set

<!-- PATTERN: claimable-set -->
<!-- PURPOSE: list the cells a player may claim now, in a stable order: ascending tier, free before premium -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `rewardFor` returns the tier row's reward, or the repeat reward past the last defined tier; `claimed` holds `track:tier` strings of cells whose claim row exists in any state -->
```typescript
function claimable(season: Season, totalXp: number, premiumActive: boolean, claimed: Set<string>) {
  const reached = tierFor(totalXp, season);
  const out: { track: "free" | "premium"; tier: number; reward: Reward }[] = [];
  for (let tier = 1; tier <= reached; tier++) {
    for (const track of ["free", "premium"] as const) {
      if (track === "premium" && !premiumActive) continue;
      const reward = rewardFor(season, track, tier);
      if (reward && !claimed.has(`${track}:${tier}`)) out.push({ track, tier, reward });
    }
  }
  return out;
}
```

A `pending` claim row counts as claimed here, so it is not offered twice; the repair path completes it.

### Idempotency keys

One builder per key, used by every call site; the strings are fixed by the contract with `billing.virtual-currency`. A key is at most 200 characters.

| Effect | Key |
|---|---|
| Tier reward | `season-pass:{account_id}:{season_id}:{track}:{tier}` |
| Skip price | `season-pass:{account_id}:{season_id}:skip:{purchase_id}` |
| Boost price | `season-pass:{account_id}:{season_id}:boost:{purchase_id}` |
| Claw back | `{tier reward key}:clawback` |
| Restore after a reversed refund | `{tier reward key}:restore` |

The ledger returns `idempotency_conflict` when a key is replayed with different arguments. Every argument here derives from immutable facts (INV-3), so a replay carries the same arguments; a conflict is a bug to alert on, not to retry.

---

## Writing

### Ingest XP

One transaction. The progress row is created if missing and locked first, so every later read in the transaction is stable (INV-6).

<!-- PATTERN: ingest-xp-transaction -->
<!-- PURPOSE: idempotent XP credit with caps and boost applied atomically under a row lock -->
<!-- REFERENCE: language=typescript framework=agnostic orm=raw-sql -->
<!-- ADAPT: `lockProgress` -> INSERT ... ON CONFLICT DO NOTHING then SELECT ... FOR UPDATE on Postgres and MySQL; on SQLite a single write transaction already serializes writers; the catch-up step (section 3 of README, step 5) goes between the attempt check and the caps and is omitted here; `assertProven` runs before the transaction opens (see below) -->
```typescript
async function ingestXp(tx: Tx, ev: XpEvent, now: Date) {
  const season = await activeSeason(tx, ev.tenantId, now);          // at most one (INV-2)
  if (!season) return { outcome: "no_active_season", creditedXp: 0 };
  const progress = await lockProgress(tx, ev.accountId, season.id);
  const seen = await findEvent(tx, ev.accountId, ev.eventId);
  if (seen) return { ...seen.result, duplicate: true };              // INV-5
  if (ev.attemptId && (await attemptBooked(tx, ev))) {               // INV-23: one play, one credit
    return { outcome: "attempt_already_credited", creditedXp: 0 };
  }
  const src = config.xpSources[ev.source];
  const dayKey = localDate(now, await timezoneOf(tx, ev.accountId)); // UTC when unset
  const used = await sumAllowed(tx, progress, ev.source, dayKey);
  const { allowed, cappedBy } = applyCaps(src.xpPerUnit * ev.units, remainingOf(src, used));
  const boost = await activeBoostPercent(tx, progress, now);         // 100 when none
  const creditedXp = credited(allowed, boost);
  await insertXpEvent(tx, { ev, season, allowed, boost, creditedXp, cappedBy, dayKey, now });
  await addTotalXp(tx, progress, creditedXp);
  return result(allowed, boost, creditedXp, cappedBy, progress.totalXp + creditedXp);
}
```

Validation (unknown source, units, extra fields, attempt presence, `occurred_at` bounds) runs before this function and costs no transaction. The proof of play runs before the transaction opens, so no lock is held while another block is asked:

<!-- PATTERN: assert-proven-attempt -->
<!-- PURPOSE: accept play-session XP only for an attempt that engagement.energy-lives reports as confirmed, won or failed -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `attempts.attemptState` -> the in-process attemptState(account_id, attempt_id) of engagement.energy-lives, which returns { state } or null; `isBooked` -> a read of xp_events by (tenant, account, event_id) so a replay never asks again -->
```typescript
const PROOF = new Set(["confirmed", "won", "failed"]);

async function assertProven(ev: XpEvent): Promise<void> {
  if (!config.xpSources[ev.source].requiresAttempt) return;
  if (await isBooked(ev)) return;                       // replay: the first answer stands
  const a = await attempts.attemptState(ev.accountId, ev.attemptId);
  if (!a || !PROOF.has(a.state)) throw err("attempt_not_proven");
}
```

After commit, fire `season_pass_xp_credited` and, when the tier changed, `season_pass_tier_reached`.

### Claim one cell

Intent row, ledger grant, confirmation. Any caller that finds a `pending` row completes it with the same key.

<!-- PATTERN: claim-cell -->
<!-- PURPOSE: grant a tier reward once across retries, races and the settlement job -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `insertClaimIfAbsent` -> INSERT ... ON CONFLICT DO NOTHING followed by a SELECT of the row, or catch the unique violation and SELECT; `ledger.grant` -> the billing.virtual-currency client; `markGranted` must be a no-op when the row is already granted -->
```typescript
async function claimCell(cell: Cell, source: ClaimSource): Promise<"granted" | "already_claimed"> {
  const key = `season-pass:${cell.accountId}:${cell.seasonId}:${cell.track}:${cell.tier}`;
  const row = await db.insertClaimIfAbsent({
    ...cell, state: "pending", claimSource: source,
    rewardCode: cell.reward.code, rewardAmount: cell.reward.amount,
  });
  if (row.state === "granted") return "already_claimed";
  const res = await ledger.grant(
    cell.accountId, cell.reward.code, cell.reward.amount,
    "season-pass.tier-reward", `${cell.seasonId}:${cell.track}:${cell.tier}`, key,
  );
  await db.markGranted(row.id, res.entry_id);
  return "granted";
}
```

A ledger error that is not an `applied` result leaves the row `pending` and surfaces as `ledger_unavailable` for that cell. Before calling `claimCell` the handler has checked the claim rules in order (README section 3): window, `tier_not_reached`, `no_reward`, `premium_required`.

**Claim-all** builds the cell list with `claimable(...)`, then calls `claimCell` for each, collecting outcomes; one cell's failure does not stop the rest. If the request is cut off, repeating it finishes the remaining cells.

### Activate premium

<!-- PATTERN: activate-premium -->
<!-- PURPOSE: unlock premium from a verified purchase record, idempotently, for the right season -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `purchases.record` -> the purchase_record(store_transaction_id) call of billing.virtual-currency; `seasonContaining` -> the published season whose [starts_at, ends_at) contains the instant; the two error cases for a second, different transaction keep a double purchase from silently doing nothing -->
```typescript
async function activatePremium(tx: Tx, accountId: string, txnId: string, now: Date) {
  const rec = await purchases.record(txnId);
  if (!rec) throw err("purchase_not_found");
  if (rec.state !== "verified") throw err("purchase_not_valid");
  if (rec.account_id !== accountId) throw err("purchase_account_mismatch");
  const season = await seasonContaining(tx, rec.purchased_at);     // the store's instant, INV-11
  if (!season) throw err("purchase_outside_season");
  if (rec.product_code !== season.premiumProductCode) throw err("purchase_product_mismatch");
  const p = await lockProgress(tx, accountId, season.id);
  if (p.premiumState === "active" && p.premiumPurchaseRef === txnId) return { alreadyActive: true };
  if (p.premiumState === "active") throw err("premium_already_active"); // a second paid transaction
  await setPremium(tx, p.id, { state: "active", ref: txnId, purchasedAt: rec.purchased_at, now });
  return { alreadyActive: false, claimablePremiumCount: countPremium(season, p) };
}
```

`setPremium` also sets `settled_at` to null. Nothing is granted here (INV-10). `premium_already_active` for a different transaction means the store charged the player twice; the block answers the error, alerts operations, and leaves the refund to support.

### Sync premium with the record

`sync_premium_state(store_transaction_id)` runs from the callback and from the recheck job: read `purchase_record`, find the progress row by `premium_purchase_ref`, set `active` when the record is `verified` and `revoked` otherwise, and apply `REFUND_POLICY` on the transition to `revoked` (claw back) or from `revoked` back to `active` (restore), using the claim keys with the `:clawback` and `:restore` suffixes. The function is idempotent: calling it with no state change does nothing.

### Buy a tier skip

Skips and boosts share the shape: an existing intent is completed before any state-dependent check; a new intent is written `pending` before any money moves.

<!-- PATTERN: buy-tier-skip -->
<!-- PURPOSE: price-checked skip purchase that cannot double-charge or lose the XP after a crash -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `db.findPurchase` -> SELECT by (tenant, account, dedupe_key); `insertPurchase` relies on the UNIQUE (tenant_id, account_id, dedupe_key) and returns the existing row on a unique violation; the validation errors carry the fresh quote in the error body -->
```typescript
async function buySkip(ctx: Ctx, req: SkipRequest) {
  const dedupe = `skip:${req.seasonId}:${req.fromTier}`;
  const existing = await db.findPurchase(ctx.accountId, dedupe);
  if (existing) {                                      // retry: never re-priced
    if (existing.tierCount !== req.count) throw err("purchase_conflict");
    return completeSkip(ctx, existing);
  }
  const intent = await db.tx(async (tx) => {
    const st = await loadStateLocked(tx, ctx, req.seasonId);     // locks the progress row
    assertSeasonActive(st);                                      // season_not_active
    assertSkippable(st, req);                                    // tier_changed, skip_not_available, premium_required
    const quote = quoteSkip(st.season, st.totalXp, req.count, config.tierSkipPrice);
    if (quote.priceAmount !== req.priceShown) throw err("price_changed", quote);  // INV-13
    return insertPurchase(tx, ctx, { kind: "tier_skip", state: "pending", dedupeKey: dedupe, ...quote });
  });
  return completeSkip(ctx, intent);
}
```

<!-- PATTERN: complete-skip -->
<!-- PURPOSE: spend then record the XP in one step that any retry or the reconcile job can finish -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `ledger.spend` returns an error value for insufficient_balance in this sketch; map your client's error style; `applySkipXp` is one transaction: insert the xp_events row (event_id skip:{purchase_id}, source tier_skip), add xp_granted to total_xp, set the purchase applied, clear settled_at when the season has ended -->
```typescript
async function completeSkip(ctx: Ctx, p: Purchase) {
  if (p.state === "applied") return currentState(ctx, p.seasonId);
  const key = `season-pass:${ctx.accountId}:${p.seasonId}:skip:${p.id}`;
  const res = await ledger.spend(
    ctx.accountId, p.priceCurrency, p.priceAmount,
    "season-pass.tier-skip", `${p.seasonId}:skip:${p.tierFrom}`, key,
  );
  if (res.error === "insufficient_balance") {
    await db.failPurchase(p.id);                      // clears dedupe_key
    throw err("insufficient_balance");
  }
  await db.tx((tx) => applySkipXp(tx, p, res.entry_id));
  return currentState(ctx, p.seasonId);
}
```

A `pending` skip created before `ends_at` is completed even after the end (value moved, so the effect lands) and clears `settled_at`, so settlement runs again.

### Buy an XP boost

Same two-step shape. Differences: the dedupe key is `boost:{season_id}:{ordinal}` with `ordinal` = the account's non-failed boost rows in the season plus one; validation is `season_not_active`, `boost_exceeds_season` (the intent's `created_at` plus the duration passes `ends_at`), `boost_active` (an applied boost whose window contains the instant), `price_changed`; the window is `[created_at, created_at + duration)`; the spend uses reason `season-pass.xp-boost`. A `pending` boost found after its window has ended is left `pending` and counted in the stuck-pending metric: it is neither charged again nor dropped.

### Settlement

<!-- PATTERN: settle-account -->
<!-- PURPOSE: deliver what is due at season end through the normal claim path, from the job, from a read, or after a late premium activation -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `completePending` re-runs the grant for every pending claim row of the account with its original key; `markSettled` runs only after every claim call returned without throwing, so a failure leaves the account for the next pass -->
```typescript
async function settleAccount(season: SeasonRow, p: Progress, now: Date) {
  if (p.settledAt !== null || now < season.endsAt) return;
  await completePending(p);
  const lateUnlock = p.premiumActivatedAt !== null && p.premiumActivatedAt >= season.claimUntil;
  const due = claimable(season, p.totalXp, p.premiumState === "active", claimedSet(p)).filter(
    (c) => config.unclaimedAtEnd === "auto_claim" || (lateUnlock && c.track === "premium"),
  );
  for (const cell of due) await claimCell({ ...cell, accountId: p.accountId, seasonId: season.seasonId }, "season_end_auto");
  await db.markSettled(p.id, now);
}
```

`lateUnlock` implements INV-11: a premium activation recorded at or after `claim_until` is delivered even under `forfeit`.

### Account lifecycle

`holdings`, `mergeAccounts` and `deleteAccount` follow the participant contract of `auth.guest-account` and the rules in `README.md` section 3, "Account lifecycle". The merge is idempotent by `merge_id` and runs in one transaction after the guest's pending rows are completed.

<!-- PATTERN: merge-accounts -->
<!-- PURPOSE: move a guest's season state into the target once, idempotently, with no lost claim and no grant -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `lockProgressRows` -> SELECT ... FOR UPDATE on both accounts' season_progress rows in sorted order (SQLite: one write transaction); `mergeSeason` applies the per-season rules of README section 3 (re-key, keep the target's row on a collision, sum total_xp, premium active if either); `completePendingRows` throws pending_unresolved -->
```typescript
async function mergeAccounts(from: string, into: string, mergeId: string) {
  const done = await db.findMerge(mergeId);
  if (done) return done.result;                        // idempotent by merge_id
  if (await db.mergedFrom(from)) throw err("already_merged");
  await completePendingRows(from);                     // grants and spends finish first
  return db.tx(async (tx) => {
    await lockProgressRows(tx, [from, into].sort());   // fixed order, no deadlock
    const seasons = await seasonsOf(tx, from);
    for (const s of seasons) await mergeSeason(tx, s, from, into);
    await clearSettled(tx, into);                      // an ended season settles again
    return recordMerge(tx, { mergeId, from, into, seasons: seasons.length });
  });
}
```

`deleteAccount(account_id)` deletes the account's rows in the four per-account tables and the `account_merges` rows that name it, in one transaction; a repeat finds nothing and succeeds.

---

## Jobs

| Job | Trigger | Work |
|---|---|---|
| `settle_season(season_id)` | scheduler, from `ends_at` | page through `season_progress` where `settled_at IS NULL` in pages of `SETTLE_BATCH_SIZE`, call `settleAccount`; safe to run twice and to resume after a crash; fire `season_pass_settled` per run |
| `reconcile_pending()` | scheduler, every `PENDING_RECONCILE_SECONDS` | complete `pending` claims by calling `claimCell` for the same cell; complete `pending` purchases through `completeSkip` and the boost equivalent; count rows older than twice the interval as stuck |
| `recheck_premium()` | scheduler, every `PREMIUM_RECHECK_SECONDS` | for each `active` premium row of a season in its `active` or claim-window phase, call `sync_premium_state` (the callback is a latency hint, the record is the truth) |
| `prune_xp_events()` | daily | delete `xp_events` rows of ended seasons older than `XP_EVENT_RETENTION_DAYS` |

---

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `unauthorized` | 401 | no valid session, or a bad service credential on the internal call |
| `season_not_found` | 404 | unknown `season_id`, or the caller has no progress row for it |
| `invalid_request` | 422 | malformed body, unknown field, `count` below 1 or not an integer, `tier` out of range, or an account or premium field in the body |
| `unknown_source` | 422 | ingest `source` not in `XP_SOURCES` |
| `invalid_event` | 422 | ingest `units` out of range, an amount field, an extra field, a missing `attempt_id` for a source that requires one, an `attempt_id` on a source that does not, or `occurred_at` in the future |
| `event_too_old` | 422 | ingest `occurred_at` older than `INGEST_MAX_EVENT_AGE_SECONDS` |
| `attempt_not_proven` | 422 | ingest attempt not in `confirmed`, `won` or `failed` (open, cancelled, expired, rejected, unknown) |
| `already_merged` | 409 | `mergeAccounts` for a guest that was merged under another `merge_id` |
| `pending_unresolved` | 409 | `mergeAccounts` could not complete the guest's pending rows; nothing changed, retry |
| `claim_window_closed` | 409 | the server instant is at or after `claim_until` |
| `season_not_active` | 409 | skip or boost outside `[starts_at, ends_at)` |
| `tier_changed` | 409 | skip `from_tier` is not the current tier; body carries the fresh quote |
| `skip_not_available` | 409 | skips off, `count` past tier N or above `MAX_SKIP_TIERS_PER_REQUEST` |
| `premium_required` | 403 | skip under `TIER_SKIP_REQUIRES_PREMIUM` without premium |
| `price_changed` | 409 | `price_shown` differs from the server price; body carries the fresh quote |
| `insufficient_balance` | 409 | the ledger rejected the spend; nothing changed |
| `boost_active` | 409 | an applied boost is running |
| `boost_exceeds_season` | 409 | the boost would end after `ends_at` |
| `purchase_conflict` | 409 | an existing intent for the same skip has a different `count` |
| `purchase_not_found` | 404 | unknown `store_transaction_id` |
| `purchase_not_valid` | 409 | the record is not in state `verified` |
| `purchase_account_mismatch` | 403 | the record names another account, or none (erased) |
| `purchase_product_mismatch` | 422 | the record's product is not the season's premium product |
| `purchase_outside_season` | 409 | no season contains the record's `purchased_at` |
| `premium_already_active` | 409 | premium is active through a different transaction |
| `rate_limited` | 429 | claim, skip, boost or ingest above the limit |
| `season_config_error` | 500 | more than one active season, or an unpublished season served; credits nothing and alerts |

Ingest answers 200 for `no_active_season`, `capped` and `attempt_already_credited`, because those are business outcomes the caller must not retry. Log the error code, tenant, account id and season id; never log a store transaction id together with a receipt, and never log the service credential.

Publishing errors (`invalid_season_window`, `invalid_season_id`, `season_overlap`, `invalid_tier_table`, `unknown_reward_code`, `late_publish`, `empty_premium_track`) are operator-side and named in `README.md` section 3.

---

## Anti-patterns

**DON'T** store the tier. A stored tier drifts from `total_xp` the first time a table is edited or a merge runs; derive it (INV-4).

**DON'T** accept XP for a play-session source without an attempt that `attemptState` reports as `confirmed`, `won` or `failed`, and never credit the same attempt to the same source twice (INV-23).

**DON'T** accept an XP amount, `season_id` for crediting, `account_id`, `tenant_id`, `day_key`, `premium_state` or a price from a request body. Amounts come from `XP_SOURCES`, the season from the server clock, the rest from the session (INV-5, INV-21).

**DON'T** resolve "the current season" inside a claim. The request names the season; rollover must not move a claim (INV-8).

**DON'T** grant first and record after. Record the `pending` row, grant with the stable key, confirm (INV-20). A grant without a row cannot be repaired by the reconcile job.

**DON'T** call `grant` without the key, or build the key from a timestamp or a random value. Retries must collide on purpose (INV-7).

**DON'T** apply caps to the boosted amount. The cap binds base XP; otherwise a bought boost is swallowed on exactly the days a player plays most (INV-6).

**DON'T** let activation grant rewards. It changes state; rewards are claimed through the one claim path (INV-7, INV-10).

**DON'T** verify store receipts here, or read store state. Read `purchase_record`; the purchase contract owns verification (INV-12).

**DON'T** run the settlement as the only delivery path. The read path settles the caller too, so a late or failed job never shows a player a stale state (INV-16).

**DON'T** compute `fits_in_season` or any countdown on the client and trust it. The server computes `fits_in_season` and `sale_open`; the client displays them (INV-1).
