# Backend Patterns — Friends & Leaderboard

> Snippets below are **L3 illustrative** (see `docs/SPEC_GUIDELINES.md` section 6). Each is ≤30 lines with the four markers. `db`, `config`, `HttpError` and `Ctx` are placeholders for the merchant project's own data layer, config module, error type and request context. The authorization rules these handlers enforce are the invariants I-1..I-10 in `security.md`; reference them in tests by id.

## API Endpoints

### Public (no session)

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `GET` | `/api/board?period=week\|all` | Top `BOARD_SIZE` listed learners with ranks | None |

Response: `{ period, week_start_day, rows: [{ id, rank, display_name, level, xp, streak_days, accuracy, friend_code }] }`. `xp` is the effective XP **of the requested period**. Rows follow the projection in `security.md` I-2.

### Signed-in learner

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `PUT` | `/api/board/me` | Ensure the profile exists (idempotent); body `{ display_name_hint? }` is the sign-in name | Session |
| `GET` | `/api/board/me?period=week\|all` | Own profile, `listed`, `rank` (null when hidden or 0 XP), `count_above` | Session |
| `POST` | `/api/board/me/report` | Report progress `{ xp, level, streak_days, answered, accuracy }` | Session |
| `PATCH` | `/api/board/me` | Change `{ public_board }` | Session |
| `POST` | `/api/board/me/reset` | "Erase my data": zero the stats (invariant I-9) | Session |
| `GET` | `/api/friends` | Viewer plus friends ranked on `week`, with `gap` to the next row above | Session |
| `POST` | `/api/friends` | Add by code `{ code }`; 201 with the friend projection | Session |
| `DELETE` | `/api/friends/:profile_id` | Remove a link; 204 even if there was none | Session |

There is no endpoint that returns a profile by `id` (invariant I-4). Account deletion removes the profile through the foreign key cascade (`compliance.account-deletion`).

---

## Pure core (no I/O)

Keep these functions free of I/O and clocks: pass `nowMs` in. They are the code the unit tests exercise, and they mirror `app/src/lib/community.ts` and `app/src/lib/progress.ts` of the shipped system.

### Effective values

<!-- PATTERN: effective-values -->
<!-- PURPOSE: Compute week XP, streak and accuracy as the board shows them, from stored fields and the clock -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT:
       - `Profile` is the merchant's row type; keep field names or map them in the data layer
       - Replace `config` with the project's config access; `MIN_ANSWERED_FOR_ACCURACY` default 10
       - Keep arithmetic in UTC integers; do not use local-time date libraries for the week rule
       - Port the same four functions to the other stack's language if the server is not TypeScript; the test vectors in fixtures/profiles.json are language-neutral -->

```typescript
const DAY_MS = 86_400_000;

// Days since 1970-01-01 of the Monday that starts the week containing `ms` (1970-01-01 was a Thursday).
export function weekStart(ms: number): number {
  const day = Math.floor(ms / DAY_MS);
  return day - ((day + 3) % 7);
}

export const effectiveWeekXp = (p: Profile, now: number) =>
  p.weekStartDay === weekStart(now) ? p.weekXp : 0;

// Alive only if the account reported since the start of yesterday (UTC).
export const effectiveStreak = (p: Profile, now: number) =>
  p.updatedAtMs >= (Math.floor(now / DAY_MS) - 1) * DAY_MS ? p.streakDays : 0;

export const effectiveAccuracy = (p: Profile): number | null =>
  p.answered >= config.MIN_ANSWERED_FOR_ACCURACY ? p.accuracy : null;

export const periodXp = (p: Profile, period: "week" | "all", now: number) =>
  period === "week" ? effectiveWeekXp(p, now) : p.xp;
```

### Fold a progress report

<!-- PATTERN: fold-progress-report -->
<!-- PURPOSE: Apply a reported stat set to the stored profile: monotonic totals, baseline on first report, capped weekly credit -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT:
       - Types `Profile` / `Report` come from the project; `report` is already range-validated (see security.md Input Validation Rules)
       - `updatedAtMs` is the stored `updated_at` as epoch milliseconds, from the DB clock or the app clock but always the SAME clock that wrote it
       - Constants `BURST_XP`, `XP_PER_HOUR`, `MAX_XP` come from the configuration surface
       - No client clock-skew allowance is needed because the server computes the cap with its own clock -->

```typescript
export function foldReport(prev: Profile, r: Report, nowMs: number): Profile {
  const week = weekStart(nowMs);
  const xp = Math.max(prev.xp, r.xp);                     // totals never go down (I-7)
  const baseline = prev.xp === 0 && prev.answered === 0;  // first report earns no weekly XP (I-8)
  const hours = Math.max(0, nowMs - prev.updatedAtMs) / 3_600_000;
  const cap = config.BURST_XP + Math.floor(hours * config.XP_PER_HOUR);
  const credit = baseline ? 0 : Math.min(xp - prev.xp, cap);
  const base = prev.weekStartDay === week ? prev.weekXp : 0; // nothing carries over a Monday
  return {
    ...prev,
    xp,
    level: Math.max(prev.level, r.level),
    answered: Math.max(prev.answered, r.answered),
    streakDays: r.streakDays,
    accuracy: r.accuracy,
    weekXp: Math.min(base + credit, config.MAX_XP),
    weekStartDay: week,
    updatedAtMs: nowMs,
  };
}
```

### Competition ranks

<!-- PATTERN: assign-competition-ranks -->
<!-- PURPOSE: Give equal-XP learners the same rank (1, 1, 3, 4) over rows already ordered by XP descending -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT:
       - Valid only when `rows` starts at the very top of the board and is ordered by XP descending; do not use on an arbitrary page offset
       - If you page deeper than the top, compute the first row's rank with the count-above query instead of assuming 1 -->

```typescript
export function assignRanks<T extends { xp: number }>(rows: T[]): (T & { rank: number })[] {
  const out: (T & { rank: number })[] = [];
  rows.forEach((row, i) => {
    const sameAsPrevious = i > 0 && out[i - 1].xp === row.xp;
    out.push({ ...row, rank: sameAsPrevious ? out[i - 1].rank : i + 1 });
  });
  return out;
}
```

---

## Reading the board

### Board query

The query applies invariant I-3 itself; the period decides which index it uses. Ordering carries every tie-breaker **before** `LIMIT`, so the learner cut off at the last position is deterministic.

<!-- PATTERN: board-query -->
<!-- PURPOSE: Fetch the top listed learners of one period in final display order -->
<!-- REFERENCE: dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - Placeholders `$n` → MySQL/SQLite `?`
       - `lower(display_name)` → use the dialect's Unicode-aware case-insensitive collation if available (Postgres ICU collation, MySQL `utf8mb4_unicode_ci`); SQLite `lower()` is ASCII-only, accept or collate in the app
       - The `all` variant drops the `week_start_day` filter and uses `xp` in place of `week_xp`
       - Streak is computed in the query so ordering matches what is displayed; `$3` is the start of yesterday (UTC) as a timestamp
       - Bind `$5` from `min(requested, BOARD_SIZE)`; never from an unchecked client value -->

```sql
-- period = week
SELECT id, display_name, friend_code, level,
       week_xp AS xp,
       CASE WHEN updated_at >= $3 THEN streak_days ELSE 0 END AS streak_days,
       CASE WHEN answered >= $4 THEN accuracy END AS accuracy
FROM board_profiles
WHERE tenant_id = $1
  AND public_board
  AND week_start_day = $2
  AND week_xp > 0
ORDER BY week_xp DESC,
         CASE WHEN updated_at >= $3 THEN streak_days ELSE 0 END DESC,
         lower(display_name) ASC,
         id ASC
LIMIT $5;
```

After the query: map rows through the projection (below), then `assignRanks`.

### Own rank below the top

<!-- PATTERN: own-rank-count -->
<!-- PURPOSE: Rank of the caller when they are not among the returned rows: 1 + listed learners with strictly more XP -->
<!-- REFERENCE: dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - Same placeholder/dialect changes as `board-query`
       - For `all`: replace `week_xp` by `xp` and drop the `week_start_day` filter
       - Skip the query and return `rank: null` when the caller's `public_board` is false or their effective period XP is 0 -->

```sql
SELECT count(*) AS count_above
FROM board_profiles
WHERE tenant_id = $1
  AND public_board
  AND week_start_day = $2
  AND week_xp > $3;      -- $3 = the caller's own effective week XP
-- rank = count_above + 1
```

### Projection (the only serializer for other learners)

<!-- PATTERN: public-profile-projection -->
<!-- PURPOSE: One place that decides which fields of another learner leave the server (invariant I-2) -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT:
       - Add a field here only after updating the privacy copy requirement in security.md
       - Reuse the same function for board rows, friend rows and the friend returned by POST /api/friends
       - Never spread the database row (`{ ...row }`) into a response -->

```typescript
export function toPublicProfile(p: Profile, period: "week" | "all", now: number) {
  return {
    id: p.id,
    display_name: p.displayName,
    friend_code: p.friendCode,
    level: p.level,
    xp: periodXp(p, period, now),
    streak_days: effectiveStreak(p, now),
    accuracy: effectiveAccuracy(p),
  };
}
```

---

## Writing

### Report progress

<!-- PATTERN: report-progress-handler -->
<!-- PURPOSE: Lock the caller's own row, fold the report, write it back with server time, in one transaction -->
<!-- REFERENCE: language=typescript framework=agnostic dialect=postgres -->
<!-- ADAPT:
       - `FOR UPDATE` → MySQL InnoDB supports it; SQLite has no row locks, run the transaction as `BEGIN IMMEDIATE`
       - `ctx.accountId` / `ctx.tenantId` come from the verified session, never from the body (I-1)
       - `parseReport`: any validator that throws 422 `invalid_stats` on a non-integer or out-of-range value and rejects unknown keys
       - Persist all folded columns in one UPDATE; `updated_at` gets the same `nowMs` the fold used -->

```typescript
async function reportProgress(ctx: Ctx, body: unknown): Promise<Profile> {
  const report = parseReport(body);
  return db.transaction(async (tx) => {
    const prev = await tx.one<Profile>(
      `SELECT * FROM board_profiles WHERE tenant_id = $1 AND account_id = $2 FOR UPDATE`,
      [ctx.tenantId, ctx.accountId],
    );
    if (!prev) throw new HttpError(404, "profile_missing");
    const now = Date.now();
    const next = foldReport(prev, report, now);
    await tx.exec(
      `UPDATE board_profiles
          SET xp=$1, level=$2, answered=$3, streak_days=$4, accuracy=$5,
              week_xp=$6, week_start_day=$7, updated_at=$8
        WHERE id=$9`,
      [next.xp, next.level, next.answered, next.streakDays, next.accuracy,
       next.weekXp, next.weekStartDay, new Date(now), prev.id],
    );
    return next;
  });
}
```

If `REPORT_MIN_INTERVAL_SECONDS > 0` and `now - prev.updatedAtMs` is smaller, respond `429 rate_limited` before folding (extrapolated hardening, see `security.md` T-1.2).

### Ensure profile (friend code claim)

<!-- PATTERN: ensure-profile-with-code -->
<!-- PURPOSE: Create the profile on first use with a unique friend code, retrying on collision -->
<!-- REFERENCE: language=typescript framework=agnostic dialect=postgres -->
<!-- ADAPT:
       - `isUniqueViolation(err, "idx_bp_code")`: Postgres code `23505` on that index; MySQL `ER_DUP_ENTRY (1062)`; SQLite `SQLITE_CONSTRAINT_UNIQUE`
       - The account UNIQUE index also fires if two first requests race: catch that one and return the row the winner created
       - `cleanName`: trim and collapse whitespace, truncate to MAX_DISPLAY_NAME, fall back to `Learner`
       - Set `public_board` from `config.PUBLIC_BOARD_DEFAULT` (default true) -->

```typescript
async function ensureProfile(ctx: Ctx, nameHint: string): Promise<Profile> {
  const existing = await findByAccount(ctx.tenantId, ctx.accountId);
  if (existing) return existing;
  for (let attempt = 0; attempt < config.FRIEND_CODE_ATTEMPTS; attempt++) {
    try {
      return await db.one<Profile>(
        `INSERT INTO board_profiles
           (tenant_id, account_id, display_name, friend_code, public_board, week_start_day)
         VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
        [ctx.tenantId, ctx.accountId, cleanName(nameHint), drawFriendCode(),
         config.PUBLIC_BOARD_DEFAULT, weekStart(Date.now())],
      );
    } catch (err) {
      if (!isUniqueViolation(err, "idx_bp_code")) throw err; // a taken code: draw another
    }
  }
  throw new HttpError(503, "no_free_friend_code");
}
```

### Add friend

<!-- PATTERN: add-friend-by-code -->
<!-- PURPOSE: Resolve a code and insert a one-way link, enforcing no-self, no-duplicate and the cap atomically -->
<!-- REFERENCE: language=typescript framework=agnostic dialect=postgres -->
<!-- ADAPT:
       - `FOR UPDATE` on the owner row serializes concurrent adds from two devices so the count check holds; SQLite → `BEGIN IMMEDIATE`
       - Map the UNIQUE violation on `idx_fl_pair` to 409 `already_friends` even though the pre-check exists (race)
       - Rate-limit this endpoint per account before the transaction (`FRIEND_LOOKUP_RATE_LIMIT`) -->

```typescript
async function addFriend(ctx: Ctx, body: { code: string }): Promise<PublicProfile> {
  const code = normalizeFriendCode(body.code);
  if (!code) throw new HttpError(422, "invalid_friend_code");
  return db.transaction(async (tx) => {
    const me = await tx.one<Profile>(
      `SELECT * FROM board_profiles WHERE tenant_id=$1 AND account_id=$2 FOR UPDATE`,
      [ctx.tenantId, ctx.accountId]);
    const friend = await tx.one<Profile>(
      `SELECT * FROM board_profiles WHERE tenant_id=$1 AND friend_code=$2`, [ctx.tenantId, code]);
    if (!friend) throw new HttpError(404, "friend_not_found");
    if (friend.id === me.id) throw new HttpError(422, "cannot_add_self");
    const { n } = await tx.one<{ n: number }>(
      `SELECT count(*)::int AS n FROM friend_links WHERE owner_profile_id=$1`, [me.id]);
    if (n >= config.MAX_FRIENDS) throw new HttpError(409, "friends_full");
    try {
      await tx.exec(`INSERT INTO friend_links (tenant_id, owner_profile_id, friend_profile_id)
                     VALUES ($1,$2,$3)`, [ctx.tenantId, me.id, friend.id]);
    } catch (err) {
      if (isUniqueViolation(err, "idx_fl_pair")) throw new HttpError(409, "already_friends");
      throw err;
    }
    return toPublicProfile(friend, "week", Date.now());
  });
}
```

Order of checks matters for the error the learner sees: format, not found, self, full, already. (The shipped client checks `badCode`, `self`, `full`, `notFound`, `already` in that order, `useCommunity.ts` `add`; any order is acceptable as long as each condition yields its own code.)

### Friends list

`GET /api/friends` loads the caller's linked profiles (one `JOIN` on `friend_links`, scoped by `owner_profile_id` and `tenant_id`), adds the caller's own profile, maps through `toPublicProfile(.., "week", now)`, orders by the ranking rule (week XP, streak, name, id) and applies `assignRanks`. The `gap` is the XP the caller needs to pass the nearest row above with strictly more XP, `(above.xp - mine.xp + 1)`, or `null` when nobody is above. Links to hidden learners are returned (I-4, D2).

---

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `unauthorized` | 401 | No valid session on an endpoint that needs one |
| `invalid_friend_code` | 422 | Code fails normalization or shape |
| `cannot_add_self` | 422 | The code belongs to the caller |
| `invalid_stats` | 422 | Report has a non-integer, out-of-range value or unknown key |
| `invalid_period` | 422 | `period` is not `week` or `all` |
| `invalid_request` | 422 | Malformed body (for example `public_board` not boolean) |
| `profile_missing` | 404 | Report/patch before `PUT /api/board/me` |
| `friend_not_found` | 404 | No profile has this code |
| `already_friends` | 409 | Link exists |
| `friends_full` | 409 | Caller already has `MAX_FRIENDS` links |
| `rate_limited` | 429 | Friend lookups or reports above their limits |
| `no_free_friend_code` | 503 | All `FRIEND_CODE_ATTEMPTS` draws collided |

The shipped client maps failures to `badCode`, `self`, `notFound`, `already`, `full`, `network`, `server` (`useCommunity.ts` `CommunityProblem`); the client message table in `frontend.md` keeps those seven.

Logging: log the error code, the tenant and the profile id. Do not log friend codes of failed lookups.

---

## Anti-patterns

**DON'T** accept `account_id`, `profile_id` for self, `tenant_id`, `week_start_day`, `updated_at` or `rank` from the request body. Derive them from the session and the server clock (I-1, I-8).

**DON'T** let the client send `week_xp`. Weekly credit is computed by the server from the XP gain and elapsed time; a client-chosen `week_xp` is the exact hole the credit cap exists to close.

**DON'T** serialize a database row directly into a response. Use `toPublicProfile` (I-2); the next column someone adds would otherwise leak.

**DON'T** build the board query from client-supplied filters or accept `public_board` as a query parameter (I-3, T-4).

**DON'T** compute ranks with `i + 1` over sorted rows. Equal XP must share a rank, and ties at the cut-off need the tie-breakers inside the `ORDER BY` before `LIMIT`.

**DON'T** rank on accuracy or show it below `MIN_ANSWERED_FOR_ACCURACY`; apply the threshold in the API so no client can show it by mistake.

**DON'T** count friends in the application and then insert without a lock: two devices adding at once exceed the cap. Lock the owner row (or use `BEGIN IMMEDIATE`) inside the transaction.

**DON'T** use the account id as the public handle. Account ids are used by other blocks and must not be enumerable from the board.

**DON'T** run a weekly cron to reset `week_xp`. The week rule makes stale rows drop out of every query on their own; a reset job adds a failure mode with no benefit.
