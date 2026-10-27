# Backend: Event Calendar

> Snippets are L3 illustrative TypeScript with the four markers per `docs/SPEC_GUIDELINES.md` section 6. The behavior (WHAT) is in the prose and tables; the snippets show the pure rules that must come out identical on every stack. Data model, state rule, defaults and invariants (INV-n) are in `README.md`.

## Components and ports

| Unit | Responsibility | Interface |
|---|---|---|
| Calendar reader | Builds discovery and detail answers from one `server_now` | `listForAccount(account, client)`, `detail(account, client, event_id)` |
| Participation writer | Join, progress, claim, each in one transaction | `join`, `recordProgress`, `claim` |
| Settlement worker | Creates end-of-event claim rows, idempotently, in batches | `settleDue(now)` |
| Grant worker | Turns `earned` claim rows into ledger grants with retry and backoff | `payDue(now)` |
| Authoring and operator service | Drafts, checks, publish, extend, hold, release, end-now, unpublish, series expansion, calendar health | admin routes below |
| Preview service | Read-only discovery at an operator-chosen instant | `GET /admin/preview/events` |
| Lifecycle participant | Registers with `auth.guest-account` for guest linking, import and purge | `holdings`, `mergeAccounts`, `deleteAccount` |

| Port | Who provides it | Contract |
|---|---|---|
| `Clock` | Host | `now()` returns a UTC instant; the only time source in this block |
| `LedgerPort` | `billing.virtual-currency` | `grant(account_id, currency, amount, reason, source_ref, idempotency_key)` returning `{applied, balance, entry_id}`; a replay with the same key returns the original result |
| `AccountFacts` | Host | `facts(account_id)` returning `{created_at, previous_session_ended_at, timezone, country, platform, app_version}`; `timezone` is an IANA name; `previous_session_ended_at` is the end of the session before the current one, null on a first session |
| `RankSource` | Optional board component | `finalRanks(event_id, account_ids)` returning rank or null per account, frozen at the event's effective end |
| `TypeRegistry` | Config (`EVENT_TYPES`) | Per type: allowed `config_schema_versions`, a schema for `config`, `shared_outcome` |
| `OperatorAuth` | Host | Authenticates operators and answers role checks: `calendar_author`, `calendar_publisher`, `calendar_operator`, `calendar_preview` |
| `EventOutbox` | Host | Accepts domain events and the `event_ending_soon` hand-off with at-least-once delivery |

## Pure rules

These four functions are pure: no I/O, no clock reads (the caller passes instants in milliseconds). They run in tests without mocks, and `fixtures/time-cases.json` is their test vector.

<!-- PATTERN: event-state-derivation -->
<!-- PURPOSE: derive an event's timeline and state from definition fields and one server instant -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: millisecond numbers -> your timestamp type; config maps -> your config loader; keep the half-open comparisons and the quarter-length clamp identical -->
```typescript
type Layer = "daily" | "weekly" | "seasonal";
type Win = { start: number; authoredEnd: number; closesAt: number | null; layer: Layer };
type Cfg = { soon: Record<Layer, number>; grace: Record<Layer, number> }; // seconds

function timeline(w: Win, c: Cfg) {
  const effectiveEnd = Math.min(w.authoredEnd, w.closesAt ?? Infinity);
  const quarter = Math.floor((w.authoredEnd - w.start) / 4000) * 1000;
  const window = Math.min(c.soon[w.layer] * 1000, quarter);
  return {
    start: w.start,
    endingSoonAt: Math.max(w.start, effectiveEnd - window),
    effectiveEnd,
    archiveAt: effectiveEnd + c.grace[w.layer] * 1000,
  };
}

function stateAt(t: ReturnType<typeof timeline>, now: number) {
  if (now < t.start) return "scheduled";
  if (now < t.endingSoonAt) return "live";
  if (now < t.effectiveEnd) return "ending-soon";
  return now < t.archiveAt ? "ended" : "archived";
}
```

<!-- PATTERN: local-window-resolution -->
<!-- PURPOSE: turn a wall-clock time in an IANA zone into a UTC instant with the RFC 5545 gap and overlap rules -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: offsetAt -> your time zone library's offset lookup in minutes for a zone at a UTC instant; replace the two-day look-back with your library's gap handling and confirm it matches "offset before the gap" -->
```typescript
type OffsetAt = (zone: string, utcMs: number) => number; // minutes east of UTC

function resolveLocal(zone: string, local: string, offsetAt: OffsetAt): number {
  const naive = Date.parse(local + "Z");
  const hits: number[] = [];
  for (let off = -14 * 60; off <= 14 * 60; off += 15) {
    const utc = naive - off * 60_000;
    if (offsetAt(zone, utc) === off) hits.push(utc);
  }
  if (hits.length > 0) return Math.min(...hits);          // overlap: first occurrence
  const before = offsetAt(zone, naive - 2 * 86_400_000);  // gap: offset before the gap
  return naive - before * 60_000;
}
```

<!-- PATTERN: min-version-compare -->
<!-- PURPOSE: decide whether a client build can render an event -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: none beyond the language; the numeric per-component comparison and the malformed-is-0.0.0 rule must stay identical on server and client -->
```typescript
function parseVersion(v: string | null): [number, number, number] | null {
  if (v === null) return null;
  if (!/^\d+(\.\d+){0,2}$/.test(v)) return [0, 0, 0];
  const p = v.split(".").map(Number);
  return [p[0], p[1] ?? 0, p[2] ?? 0];
}

function meetsMinVersion(client: string, min: string | null): boolean {
  const need = parseVersion(min);
  if (need === null) return true;
  const have = parseVersion(client)!;
  for (let i = 0; i < 3; i++) if (have[i] !== need[i]) return have[i] > need[i];
  return true;
}
```

<!-- PATTERN: compensation-clamp -->
<!-- PURPOSE: pay compensation without lifting any player above the reward table's maximum -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: Grant -> the ledger grant line type; earned must count claims in both statuses (earned and granted) of the same event and account -->
```typescript
type Grant = { currency: string; amount: number };

function clampCompensation(
  requested: Grant[],
  tableMax: Record<string, number>,
  earned: Record<string, number>,
): Grant[] {
  return requested
    .map((g) => ({
      currency: g.currency,
      amount: Math.min(g.amount, Math.max(0, (tableMax[g.currency] ?? 0) - (earned[g.currency] ?? 0))),
    }))
    .filter((g) => g.amount > 0);
}
```

## Player API

All routes need an authenticated account (guest or signed in). Responses are JSON; errors are `{ "error": "<code>" }`. Every response from these routes carries `server_now`. The client sends its build and platform on every request: `X-App-Version` (for example `2.5.0`), `X-Platform` (`ios|android|web`), and `Accept-Language`.

### `GET /api/events`

Returns what a player may see at one `server_now`.

```json
{
  "server_now": "2026-10-27T12:00:00.000Z",
  "next_boundary_at": "2026-10-27T16:00:00.000Z",
  "locale": "en",
  "events": [{
    "event_id": "evt-weekly-sprint-w44", "type": "sprint", "config_schema_version": 1,
    "cadence_layer": "weekly", "state": "live",
    "starts_at": "2026-10-26T00:00:00.000Z", "ending_soon_at": "2026-11-01T00:00:00.000Z",
    "ends_at": "2026-11-02T00:00:00.000Z", "archive_at": "2026-11-05T00:00:00.000Z",
    "closed_early": false, "original_ends_at": null, "priority": 50, "join_mode": "opt_in",
    "recurrence": { "repeats": true, "next_starts_at": "2026-11-02T00:00:00.000Z" }, "season_ref": null,
    "joined": true, "progress": 120, "progress_cap": 600,
    "rewards": [
      { "reward_key": "m1", "trigger_kind": "milestone", "threshold": 100, "claim_mode": "auto",
        "grants": [{ "currency": "coins", "amount": 50 }], "status": "granted" },
      { "reward_key": "m2", "trigger_kind": "milestone", "threshold": 300, "claim_mode": "manual",
        "grants": [{ "currency": "coins", "amount": 100 }, { "currency": "booster-hint", "amount": 1 }], "status": "locked" }
    ],
    "content": { "title": "Weekly Sprint", "summary": "...", "rules": ["..."], "assets": {}, "cta": { "route": "level-select" } },
    "config": {}
  }],
  "upcoming": [{ "event_id": "evt-weekend-rush", "type": "sprint", "config_schema_version": 1, "cadence_layer": "weekly",
    "starts_at": "2026-10-30T18:00:00.000Z", "ends_at": "2026-11-01T18:00:00.000Z", "priority": 55, "recurrence": null,
    "content": { "title": "Weekend Rush", "teaser": "..." } }],
  "recent": [],
  "unavailable": [{ "event_id": "evt-harvest-season", "reason": "update_required", "title": "Harvest Season",
    "starts_at": "2026-10-12T00:00:00.000Z", "ends_at": "2026-11-09T00:00:00.000Z", "min_app_version": "2.4.0" }]
}
```

Rules:

- `events`: state `live` or `ending-soon`, in the player's audience, renderable by the client's version. `recent`: state `ended` where the account has joined (same shape; carries `rewards` with `status`). `upcoming`: state `scheduled` with a start within `UPCOMING_HORIZON_SECONDS`, at most `UPCOMING_MAX`, one per series and none for a series that already has an instance in `events`. `unavailable`: stubs, at most `UNAVAILABLE_STUBS_MAX` for `update_required` (an event the player is eligible for except the version) plus one `held` stub per joined, held event.
- All four lists are sorted by the priority rule below.
- `ends_at` is the account's effective end (the window end or `closes_at`, whichever is earlier); `closed_early` is true when `closes_at` shortened it. `original_ends_at` is the authored end before the first extension and is null while the event was never extended (INV-25). A client counts down to `ends_at` and rebuilds the countdown from it on every response.
- `recurrence` is `{repeats: true, next_starts_at}` for an event with a `series_key` and null otherwise; `next_starts_at` is the start, resolved for the account, of the published instance of the series with the earliest start after this one, or null when none is published yet. The client always shows the label (INV-26).
- `season_ref` is returned as stored (or null) and means nothing to the server: the client may use it to label the event or link to the pass screen (INV-24).
- Reward `status` is `locked`, `earned` or `granted`.
- `next_boundary_at` is the earliest instant after `server_now` at which any returned event changes state (an upcoming start, an `ending_soon_at`, an end, an `archive_at`); null when none. A client refetches then (plus jitter) and at most every `DISCOVERY_REFRESH_SECONDS`.
- Teasers carry no reward amounts and no rules. Full terms are in the detail answer (an eligible `scheduled` event is readable there), so a player can read them before the start.
- Unknown request headers and query parameters are ignored; there is no time parameter (INV-14).

### `GET /api/events/{event_id}`

The same `events` item for one event, in any state except `archived`. Errors: `404 event_not_found` for every case a player must not tell apart (INV-15), `403 update_required` with `min_app_version` when only the version blocks the player, `409 event_held` for a participant.

### `POST /api/events/{event_id}/join`

Joins an `opt_in` event. Allowed in states `live` and `ending-soon`. Idempotent: a second call returns the same participation with 200. Errors: `404 event_not_found`, `409 event_not_live` (scheduled), `409 event_ended`, `409 event_held`, `422 invalid_request` (the event is `auto`: it needs no join).

### `POST /api/events/{event_id}/progress`

Body `{ "amount": integer, "source_ref": text_short }`, with an optional `occurred_at` honored only for trusted server callers (INV-3). Returns `{ progress, applied_amount, capped, duplicate, new_claims[] }`. Errors: `422 invalid_progress` (amount below 1 or above `progress_max_per_call`, malformed `source_ref`), `409 not_joined` (opt-in event), `409 event_not_live`, `409 event_ended`, `409 event_held`, `404 event_not_found`, `429 rate_limited`.

### `POST /api/events/{event_id}/claim`

Body `{ "reward_keys": [text_short] }`, optional; omitted means every `earned` manual reward of the event. Returns one result per reward: `{ reward_key, status, grant_path, grants }`. Rules: allowed in any state except while held; a reward already `granted` answers 200 with its stored result; a reward that is not `earned` answers `409 reward_not_earned`; a ledger failure answers `503 grant_pending` and leaves the claim `earned` (the grant worker will complete it).

### Error codes

| Status | Code | Meaning |
|---|---|---|
| 401 | `unauthenticated` | No account session |
| 403 | `update_required` | Only `min_app_version` blocks this player |
| 404 | `event_not_found` | Unknown, draft, outside the audience, or not on the allow-list |
| 409 | `event_not_live` | The event has not started |
| 409 | `event_ended` | The event ended at or before the server instant |
| 409 | `event_held` | The kill switch is on |
| 409 | `not_joined` | Opt-in event without a join |
| 409 | `reward_not_earned` | Claim of a reward that is not earned |
| 422 | `invalid_progress` / `invalid_request` | Malformed or out-of-bound input |
| 429 | `rate_limited` | Progress or claim rate limit |
| 503 | `grant_pending` | Ledger unavailable; retry |
| 503 | `latch_unavailable` | The first-listing latch could not be written; retry |

## Discovery algorithm

1. Read `server_now` once. Load the account's facts. Load published definitions for the tenant whose outer bounds overlap `[server_now - max claim grace - 14 hours, server_now + UPCOMING_HORIZON_SECONDS + 14 hours]`, and the account's participation rows for them.
2. For each definition, resolve the account's window: `absolute` uses the definition; `local` uses the latched `window_*` of the participation row if one exists, otherwise `resolveLocal` on both wall-clock bounds in the account's timezone.
3. Derive the state with `timeline` and `stateAt` using `closes_at`.
4. Discard `archived` events and `ended` events without a joined participation row.
5. Audience: an account with a participation row skips the audience test (INV-7). Otherwise apply `allow_list_only`, `platforms`, country and `segment` (`inAudience`). A failed test removes the event silently.
6. Version: if the account passes the audience test but `meetsMinVersion` is false, the event becomes an `unavailable` stub with reason `update_required` (when `UPDATE_STUBS_ENABLED`); otherwise it is dropped.
7. Held: a held event is dropped, except for a joined account, which gets an `unavailable` stub with reason `held`.
8. Latch: for each remaining event in state `live` or `ending-soon` whose audience segment is not `all` or whose window is `local`, insert a participation row if none exists (`first_seen_at`, resolved window, `eligibility_snapshot`). A failed write answers `503 latch_unavailable` rather than a list that could change on the next call.
9. Sort, split into the four lists, compute `next_boundary_at`, return.

The loop is bounded by the number of published events near `server_now`, which is small by design (INV-23 and `MAX_CONCURRENT_LIVE` keep it so); participation is read once per request by `(tenant_id, account_id)`.

### Overlap and priority

Layers overlap on purpose: a daily event, a weekly event and a seasonal event are live together. Sorting and conflicts follow fixed rules:

1. Display order everywhere: `priority` descending, then effective end ascending, then start ascending, then `id` ascending. The order is deterministic, so two clients never disagree.
2. The home banner shows the first item of `events` whose `content.assets` has a `banner`; there is one slot. The hub shows all items.
3. Events in one `exclusive_group` must not overlap. Authoring rejects the overlap (`exclusive_group_overlap`), `extend` rejects an extension that would create one (`extension_conflict`), so at runtime two events of a group are never live together and no tie-break is needed.
4. Progress is per event. One game action may be reported to several live events by the host; this block never moves progress between events and never deduplicates across them.
5. Rewards are independent grants per event. A non-stackable item granted by two overlapping events is resolved by the ledger and the item catalog, not here.

## Write path rules

**Join.** In one transaction: read the server instant; load the definition and the account's participation row (locking it); require state `live` or `ending-soon`, not held, and eligibility (audience test unless a row exists); set `joined_at` if null; create the row if missing. Repeating the call changes nothing.

**Progress.**

1. Read the server instant inside the transaction. For a trusted server caller that passes `occurred_at`, accept when `occurred_at < effective_end` and `now < effective_end + PROGRESS_GRACE_SECONDS`; for every other caller, `now` is the judged instant and there is no grace.
2. Require not held, state `live` or `ending-soon` at the judged instant, and `amount` within `[1, progress_max_per_call]`.
3. Load or create the participation row. An `auto` event joins the player here (eligibility test applies when no row existed); an `opt_in` event requires `joined_at` (`not_joined`).
4. Insert the entry. The UNIQUE `(event_id, account_id, source_ref)` turns a replay into `duplicate: true` with no change.
5. `applied_amount = min(amount, progress_cap - progress)`; `progress` increases by it. The response carries `capped` when `applied_amount < amount`.
6. For every `milestone` reward with `threshold <= progress` and no claim row, insert one `earned` claim row. A single call may cross several thresholds.
7. Commit, then hand every new `earned` claim with `claim_mode = auto` to the grant worker.

**Claim.** For each requested reward: load the claim row; `granted` returns its stored result; `earned` runs `payClaim` (below) and sets `status = granted` with `grant_path = player_claim` guarded by `WHERE status = 'earned'`; absent returns `reward_not_earned`. Two simultaneous claims both call the ledger with the same keys and receive the same entry ids; one wins the status update and both answer 200.

<!-- PATTERN: idempotent-reward-grant -->
<!-- PURPOSE: pay every grant line of one claim with a key built from stable facts so any replay returns the original ledger result -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: ledger -> your LedgerPort adapter; db.markGranted -> one UPDATE guarded by status = earned that also stores ledger_refs and grant_path; RetryLater -> your retry signal -->
```typescript
const key = (acct: string, ev: string, reward: string, cur: string) =>
  `event-calendar:${acct}:${ev}:${reward}:${cur}`;

async function payClaim(c: Claim, r: Reward, ledger: LedgerPort, db: Db, path: GrantPath) {
  const refs: { currency: string; entry_id: string }[] = [];
  for (const g of r.grants) {
    const res = await ledger.grant(
      c.accountId, g.currency, g.amount, "event-calendar.reward",
      `event:${c.eventId}:reward:${r.key}`, key(c.accountId, c.eventId, r.key, g.currency),
    );
    if (!res.applied || !res.entry_id) throw new RetryLater("ledger_not_applied");
    refs.push({ currency: g.currency, entry_id: res.entry_id });
  }
  await db.markGranted(c.id, refs, path); // UPDATE ... WHERE status = 'earned'
}
```

A result with `applied` false or no `entry_id` is not a grant; the claim stays `earned` and is retried.

## Settlement and grant workers

**Settlement.** On each tick (`SETTLEMENT_INTERVAL_SECONDS`), select participation rows with `joined_at` set and `settled_at` null whose event is not held and whose row end plus `PROGRESS_GRACE_SECONDS` has passed. The row end is the latched `window_ends_at` for `local` events and `min(ends_at, closes_at)` otherwise. Process in batches of `SETTLEMENT_BATCH_SIZE`; each row in its own transaction:

1. Compute the rewards the row's progress earns at settlement: `completion` when progress reached the highest milestone threshold, `participation` when progress is at least 1, `rank` when the rank source gave a rank inside a band (one `finalRanks` call per event, cached for the batch), `compensation` when the event carries a compensation reward and progress is at least 1.
2. For compensation, clamp every grant line with `clampCompensation(requested, table_max, earned)`, where `earned` sums the account's `earned` and `granted` claims of this event; a line clamped to zero creates no claim.
3. Insert the claim rows (insert-if-absent), store the facts in `detail` (progress, rank, clamp), set `settled_at`, commit.
4. Hand new `auto` claims to the grant worker.

Settlement may run late, twice or after a crash and yields the same rows (INV-20). It does not start before `effective_end + PROGRESS_GRACE_SECONDS`, so a late-accepted trusted write cannot land after its row was settled. Emit `event_settled` when an event has no unsettled joined rows left.

**Grant worker.** Selects claims with `status = earned`, `next_attempt_at` null or past, and either `claim_mode = auto` or, for `manual`, now past the claim row's archive instant (`row end + CLAIM_GRACE_SECONDS[layer]`); skips held events. It runs `payClaim` with `grant_path` `milestone_auto` (earned by progress), `settlement` (created by settlement) or `sweep` (a manual claim past the grace). On failure: `attempts + 1`, `last_error` = failure class, `next_attempt_at = now + min(GRANT_RETRY_BASE_SECONDS * 2^attempts, GRANT_RETRY_MAX_SECONDS)`. After `GRANT_MAX_ATTEMPTS` the claim stays `earned`, the worker stops selecting it and an operator alert fires; `grant_retry` resets `attempts`.

**Alerts and signals**: grant backlog age (oldest `earned` auto claim), settlement lag (now minus the oldest due unsettled row), claims at `GRANT_MAX_ATTEMPTS`, hold age against `HOLD_ALERT_SECONDS`, discovery error rate, `latch_unavailable` count.

## Account lifecycle participant

`auth.guest-account` calls these three operations on every block that holds per-account state (its README section 3.7 and hook table). They are in-process calls, not HTTP routes. The merge preview shows `holdings` to the player and a confirmation is tied to it, so `holdings` is deterministic: sorted by `category`, then `label_key`.

| Operation | Contract |
|---|---|
| `holdings(account_id)` | Returns a list of `{ category, label_key, paid, effect }`. One entry `{ progress, "event-calendar.participation", false, carried }` when the account has a participation row for an event that is not yet archived and has progress of at least 1; one entry per category the account's `earned` claims grant, `{ currency, "event-calendar.unpaid-reward", false, carried }` and `{ items, "event-calendar.unpaid-reward", false, carried }`, using the ledger catalog to tell a currency from an item code. Empty when the account holds neither. `paid` is always false: nothing in this block is bought |
| `mergeAccounts(from_account_id, into_account_id, merge_id)` | One-way. In one transaction: look up `merge_id` in `event_account_merges`; found means return the stored `result` and change nothing. Otherwise, if `from_account_id` already has a merge record under another `merge_id`, fail `already_merged`. Otherwise apply the merge rules of `README.md` section 3 to every event, insert the record with its `result` (`{events_moved, events_merged, claims_kept, claims_moved}`) and return it |
| `deleteAccount(account_id)` | Deletes the account's participation rows, progress entries, claims and merge records where the account is `from` or `into`. Safe to repeat: a second call finds nothing and succeeds. Resolves the account's armed `event_ending_soon` hand-offs. Never touches ledger entries; the ledger's own eraser handles them |

Rules:

- A merge never calls the ledger. A claim of the guest moves to the target when the target holds no claim for the same reward (`claims_moved`). When the target holds one too, the target's row wins and the guest's is dropped (`claims_kept`), except that the target's row adopts `granted`, with the guest's `grant_path` and `ledger_refs`, when only the guest's was granted. A reward granted on either side therefore stays granted and no reward is paid twice (INV-9, INV-27).
- Merge never changes a latched local window or a settlement flag of the target; a guest row moved to a target keeps its own.
- After the merge, the guest has no rows in this block; `deleteAccount(from_account_id)` later removes only the merge record.
- Foreign keys cascade on account deletion as a second barrier; `deleteAccount` does not depend on them.

## Operator actions

All routes are under `/admin`, need an operator identity (never a player session) with the stated role, require a `reason` (1 to 255 characters), and append an `event_operations` row (INV-22).

| Route | Role | Allowed when | Effect |
|---|---|---|---|
| `POST /admin/events` | author | always | Create a draft |
| `PUT /admin/events/{id}` | author | `draft` | Replace the draft |
| `POST /admin/events/series` | author | always | Expand a series request into up to `SERIES_MAX_INSTANCES` drafts, idempotent on `(series_key, occurrence_index)` |
| `POST /admin/events/{id}/check` | author | `draft` | Run the authoring checks, return problems, `reach_estimate` and `max_issuance` |
| `POST /admin/events/{id}/publish` | publisher | `draft`, no check errors | Freeze; warnings need `acknowledge_warnings: true`; second approver when configured |
| `POST /admin/events/{id}/unpublish` | publisher | state `scheduled`, no participation rows | Back to `draft` |
| `POST /admin/events/{id}/extend` | operator | `live` or `ending-soon`, `absolute` window | `ends_at` moves later and `original_ends_at` is set at the first extension; total at most `MAX_EXTENSION_SECONDS`; rejected on overlap in an exclusive group |
| `POST /admin/events/{id}/hold` | operator | published, not ended | Kill switch on: set `held_at` |
| `POST /admin/events/{id}/release` | operator | held | Clear `held_at`; optional `extend_seconds` applies an extension in the same audited action |
| `POST /admin/events/{id}/end-now` | operator | `live` or `ending-soon` | Set `closes_at`; optional compensation |
| `POST /admin/claims/{claim_id}/retry` | operator | claim at `GRANT_MAX_ATTEMPTS` | Reset `attempts` |
| `GET /admin/calendar?from=&to=` | author | always | Events with their derived states plus the rhythm health list |
| `GET /admin/preview/events` | preview | preview token | Read-only discovery at an instant |

### Operator error codes

| Status | Code | Meaning |
|---|---|---|
| 401 | `unauthenticated` | No operator credential, or a player session, or an expired preview token |
| 403 | `forbidden` / `preview_read_only` | Missing role; a preview token on a write route |
| 409 | `event_frozen` | A published event cannot be edited |
| 409 | `event_ended` | `extend` or `hold` on an event whose effective end has passed |
| 409 | `extension_conflict` | The extension would overlap an event of the same exclusive group |
| 409 | `invalid_transition` | `unpublish` of an event that has started or has participation; `release` of an event that is not held |
| 422 | `extension_too_long` / `extension_must_be_later` | Total extension above `MAX_EXTENSION_SECONDS`, or a new end that is not later |
| 422 | `extend_local_window_unsupported` | `extend` on a `local` window |
| 422 | `compensation_currency_not_in_table` | Compensation line for a currency the table does not pay |
| 422 | `invalid_closes_at` | `closes_at` in the past or beyond `MAX_EXTENSION_SECONDS` ahead |
| 422 | `reason_required` | Missing or over-long reason |
| 422 | `check_failed` | Publish with error problems, or warnings without `acknowledge_warnings`; the body carries `problems` |

### Kill switch (`hold`)

Use `hold` when an event misbehaves and the cause is unknown: a client crash on a renderer, a reward table error, an exploit. It is instant (one write), needs no deploy and loses nothing.

- Discovery drops the event; a joined participant sees an `unavailable` stub with reason `held`, so the event does not just vanish.
- Join, progress and claim answer `409 event_held`. Settlement and the grant worker skip the event; claims already `earned` stay `earned`.
- The clock keeps running. If the hold lasted long enough to cost players time, `release` with `extend_seconds` (within `MAX_EXTENSION_SECONDS`) gives it back.
- A hold older than `HOLD_ALERT_SECONDS` alerts the operators. It is never released automatically, because an automatic release could pay out a faulty table.
- Held events on clients with a cached copy keep showing until the next refresh; the first write answers `event_held` and the client refreshes.

### Emergency end (`end-now`)

Use `end-now` when the event must stop and cannot resume. Body: `{ reason, closes_at?, compensation? }`. `closes_at` defaults to now and may be later (a notice period, at most `MAX_EXTENSION_SECONDS` ahead); it is never in the past. `compensation` is a list of grant lines.

| Situation | Rule |
|---|---|
| Rewards already `earned` or `granted` | Stand. Never revoked, reduced or voided (INV-10, INV-11) |
| Milestones | Judged on progress recorded before `closes_at` |
| `completion`, `participation`, `rank` | Settlement pays them as earned at `closes_at`; a player at 90 percent of the final threshold does not receive the completion reward, which is what compensation is for |
| `compensation` | Every participant with progress of at least 1 receives each requested line, clamped per currency to `table_max - already earned`; the currency of each line must already appear in the reward table (`compensation_currency_not_in_table`) |
| Players with progress 0 | Nothing |
| State | Normal derivation with `closes_at`: `ending-soon` from `max(start, closes_at - window)`, `ended` at `closes_at`; with `closes_at` now there is no `ending-soon` |
| Hand-off | `event_ending_soon` re-armed with the new instants, or `resolved` when `closes_at` is already reached |

The compensation reward is stored as a row in `event_rewards` with `trigger_kind = compensation` and `claim_mode = auto`, so it is auditable like any reward.

### Extend and unpublish

`extend` only moves the end later. It changes `ends_at` for every player, so it is valid for `absolute` windows only; a `local` window cannot be extended because each player's resolved window is latched (INV-19). `unpublish` is allowed only while the event is `scheduled` and has no participation rows (a series of local events creates rows at first listing, which begins at the first start).

## Authoring checks

`POST .../check` returns `{ ok, problems: [{ code, severity, path, message }], reach_estimate, max_issuance }`. Any `error` blocks publish; a `warning` needs `acknowledge_warnings`. The same checks run again at publish, against the published events at that instant.

| Code | Severity | Rule |
|---|---|---|
| `ends_not_after_starts` | error | `ends_at > starts_at`; for `local`, `local_ends_at > local_starts_at` |
| `duration_out_of_range` | error | Authored length inside `DURATION_RANGE_SECONDS[layer]` (exempt: `allow_list_only`) |
| `window_fields_mismatch` | error | `local` needs both wall-clock fields; `absolute` needs neither |
| `local_window_shared_outcome` | error | A `local` window with a type whose registry entry has `shared_outcome` true |
| `exclusive_group_overlap` | error | Another published or drafted event of the group has an overlapping window (outer bounds for `local`) |
| `type_unknown` / `config_schema_unsupported` / `config_invalid` | error | Type, schema version and `config` against `EVENT_TYPES` |
| `audience_key_not_allowed` | error | Any audience key outside the closed schema, in particular spending, purchase, payer, value, price or device-value keys |
| `audience_value_invalid` | error | Unknown segment or platform, malformed country code, both country lists, `allow_list` over `ALLOW_LIST_MAX`, `allow_list_only` with an empty list |
| `allow_list_event_too_long` | error | An `allow_list_only` event longer than `ALLOW_LIST_EVENT_MAX_SECONDS` |
| `min_app_version_malformed` | error | Not one to three integers |
| `season_ref_invalid` | error | `season_ref` on an event whose layer is not `seasonal`, or longer than 64 characters, or outside letters, digits and `. _ : -`. The value is never looked up in `engagement.season-pass` (INV-24) |
| `min_app_version_unreleased` | error | Above `RELEASED_APP_VERSIONS` for any platform in the audience |
| `reward_key_duplicate` | error | `reward_key` unique per event |
| `reward_trigger_invalid` | error | A `trigger_kind` outside `milestone|completion|participation|rank|compensation` (no trigger depends on a purchase or on spend); milestone thresholds not strictly increasing or above `progress_cap`; `completion` without milestones; rank bands overlapping; trigger fields missing for the kind |
| `grant_invalid` | error | Amount not a positive integer; currency or item code unknown to the ledger catalog |
| `reward_cap_missing` | error | A currency in the table has no `REWARD_CAP_PER_PLAYER` entry for the layer |
| `reward_cap_exceeded` | error | `table_max` for a currency above its cap |
| `budget_exceeded` | error | `reach_estimate * table_max` above `issuance_budget` for a currency, or a currency with no budget entry |
| `rank_source_missing` | error | `rank` rewards while no `RankSource` is configured |
| `compensation_currency_not_in_table` | error | Emergency end only |
| `content_default_locale_missing` | error | No text for `default_locale`, or a limit in `CONTENT_LIMITS` exceeded |
| `asset_origin_not_allowed` | error | Asset URL not HTTPS or origin not in `ASSET_ORIGIN_ALLOWLIST` |
| `cta_route_unknown` | error | `cta.route` absent from the route registry the client declared at release |
| `lead_time_too_short` | error | Publish when `start - now < PUBLISH_MIN_LEAD_SECONDS` (exempt: `allow_list_only`) |
| `second_approver_required` | error | Publisher equals creator while `PUBLISH_REQUIRES_SECOND_APPROVER` is true |
| `series_instances_exceeded` | error | More than `SERIES_MAX_INSTANCES` |
| `density_over_cap` | warning | More than `MAX_CONCURRENT_LIVE` events live for one audience at one instant |
| `layer_gap` | warning | A layer in `REQUIRED_LAYERS` has an interval with no live event inside `RHYTHM_LOOKAHEAD_SECONDS` |
| `end_cluster` | warning | More than `END_CLUSTER_MAX` events end within one hour |
| `repeat_without_series` | warning | The event has no `series_key` but another published event of the tenant has the same `type` and the same title in `default_locale`; link the new event to a series so players are told it repeats (INV-26) |
| `ending_soon_window_clamped` | warning | The layer's ending-soon window exceeds a quarter of the event's length |
| `version_share_low` | warning | Share of reachable accounts below `min_app_version` above `VERSION_SHARE_WARN` |

`reach_estimate` is the number of accounts active within `REACH_ACTIVE_WINDOW_SECONDS` that pass the audience (counted by the host's `AccountFacts` source); `max_issuance[currency] = reach_estimate * table_max(currency)`. The budget is a planning ceiling and never a runtime limiter: players are always paid what the table promised (INV-10).

### Series

`POST /admin/events/series` takes a template, a `series_key` and a list of `(occurrence_index, local or absolute window)`. Each instance is a normal draft; a retry creates no duplicates. A daily-layer series uses one `local` window per local calendar day (`T00:00:00` to the next day's `T00:00:00`), so each player's day starts at their own midnight and rolls over at the `day_key` boundary of `engagement.daily-streak`. Progress and rewards never carry from one instance to the next.

## Preview and QA

- `POST /admin/preview/token` (role `calendar_preview`) issues a token that lives `PREVIEW_TOKEN_TTL_SECONDS`, scoped to the preview routes and read-only.
- `GET /admin/preview/events?at=<instant>` takes synthetic facts (`platform`, `app_version`, `country`, `timezone`, `segment`: `new_player|lapsed_player|none`) and optionally `include_drafts=true`. It answers in the discovery shape with `server_now` equal to `at`, a `preview` object echoing the inputs, no participation (every event unjoined) and `Cache-Control: no-store`.
- Every write route refuses a preview token (`403 preview_read_only`). Player routes never read a time parameter or a preview token.
- A tester who needs real join, progress, claim and settlement runs a short `allow_list_only` event in real time: its window is minutes long, it is exempt from duration and lead-time checks, and only listed accounts can see it.

## Caching and clock

- Player responses carry `Cache-Control: private, no-store`: they are personalized and carry `server_now`, so an HTTP cache would replay a stale clock. The client keeps its own copy with the receipt time (`frontend.md`).
- `server_now` has millisecond precision and is read once per request; every state in one response is consistent with it.
- No response depends on the device clock. The server never trusts a client-supplied timestamp except `occurred_at` from a trusted server caller (INV-3).
- Refetch load at boundaries is spread by the client's jitter and bounded by the progress and claim rate limits; `local` windows spread boundaries naturally across time zones.

## Rollover correctness around the end instant

1. At `effective_end` the state is `ended` (half-open window). A write whose transaction reads `now >= effective_end` fails with `event_ended`, even if the request left the device earlier.
2. A client-reported write has no grace. A trusted server caller may report `occurred_at < effective_end` until `effective_end + PROGRESS_GRACE_SECONDS`; the default is 0, so the simple rule holds unless the host opts in.
3. Settlement for a row starts at its end plus `PROGRESS_GRACE_SECONDS`; every accepted write committed before then is included.
4. A milestone reached by a write committed one millisecond before the end is `earned` and is paid whether the claim is auto, manual or swept.
5. A `local` event ends at different instants for different players; each row settles on its own latched end.
6. An extension that arrives after `effective_end` is rejected (`ended` to `live` is not a valid transition).
7. A countdown never restarts. The client rebuilds it from `ends_at` on every response, and an event id never returns from `ended` to `live`; the next occurrence of a recurring event is a different event with its own `ends_at` and a recurrence label.
8. Time zone and clock changes on the device change nothing: windows resolve from the account timezone on the server and latch (INV-19).

## Event-owner runbook

Per event, in order. Lead times are planning defaults, not benchmarks; the checks that block publish are in "Authoring checks".

| Step | What to prepare | Done when |
|---|---|---|
| 1. Decide | Layer, type, audience, `join_mode` (use `opt_in` when the event shows the player's name or rank), one success metric | Written in the event brief |
| 2. Client readiness | The renderer for `(type, config_schema_version)` exists in a store-released build; `min_app_version` is set to the first such build | `min_app_version_unreleased` is clear and `version_share_low` is understood |
| 3. Assets and copy | Banner and icon at an allow-listed origin with versioned URLs; alt text per locale; copy for every launch locale and `default_locale`; the text-only fallback checked; no claim in the copy that the event is a last chance or never returns, unless it is true (an event that repeats belongs to a series, and the calendar shows the recurrence label itself) | `asset_origin_not_allowed` and `content_default_locale_missing` are clear |
| 4. Rewards funded | Per-player maximum inside the layer cap; `issuance_budget` at or above `reach_estimate * table_max`; the faucet recorded in the economy sheet (guide 03: every currency has named faucets and sinks); every currency and item code exists in the ledger catalog | `reward_cap_*` and `budget_exceeded` are clear; the economy owner signed off |
| 5. Comms | In-app banner and detail copy reviewed; the `event_ending_soon` hand-off verified with the push block's template; if the event is promoted on the App Store, its dates and deep link match this event (Apple Guideline 2.3.13); a support reply for "the event ended early or was paused" | Each item has an owner |
| 6. QA | A real-time `allow_list_only` dry run of join, progress, claim, ending-soon, settlement and sweep; previews at start, ending-soon and end instants for the oldest supported build, a UTC+14 and a UTC-11 account, and a 23-hour or 25-hour local day if the layer is daily | The dry-run event is `ended` and every claim `granted` |
| 7. Publish | At least `PUBLISH_MIN_LEAD_SECONDS` before start; a second approver when configured | `published_at` set, `event_published` emitted |
| 8. Launch watch | Grant backlog age, discovery error rate, joins in the first hour, support inbox; the kill-switch owner is named and reachable; a hold has been rehearsed | The owner has the hold route open |
| 9. After | Settlement finished (`event_settled`), no claim at `GRANT_MAX_ATTEMPTS`, results review: joined divided by listed, completion rate, claim rate, support volume; notes added to the calendar | Review recorded before the next event of the series is published |
