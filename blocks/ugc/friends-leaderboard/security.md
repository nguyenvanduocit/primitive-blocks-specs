# Security — Friends & Leaderboard

> **Translation note.** The system this block was extracted from enforces access with Firestore security rules (`firebase/firestore.rules`). NoSQL is a non-goal of this repo, so each rule is restated below as an **authorization invariant** (I-1..I-10) that a SQL backend enforces in its handlers and queries. The "Source" column names the rule lines or tests that justify each invariant; confidence is HIGH where the rule text was read, MEDIUM where the invariant is the translation.

## Authorization Invariants

| ID | Invariant | Source in the shipped system |
|----|-----------|------------------------------|
| I-1 | **Identity comes from the session.** A caller can create, update, reset or delete only the profile whose `account_id` is the authenticated account. No request body field selects whose profile is written. | `isOwner(uid)` on create/update/delete (`firestore.rules:11-13, 108-126`) |
| I-2 | **Responses use an explicit field whitelist.** Another learner's profile is serialized as exactly: `id`, `display_name`, `friend_code`, `level`, effective `xp` (period), effective `streak_days`, effective `accuracy` (nullable), `rank`. Never: `account_id`, `tenant_id`, `answered`, `public_board` of others, timestamps. | The stored document admits only 12 keys (`hasOnly`, `:35-38`), so nothing else can sit next to the stats. The shipped reads return the whole document; the explicit projection is stricter (README D2/D3) |
| I-3 | **Board membership is decided by the server.** A board query always carries `public_board = true` AND period XP `> 0`. The caller cannot supply or remove that predicate. There is no endpoint that lists, counts or scans profiles without it. | `list` allowed only when `resource.data.publicBoard == true` or owner (`:104-106`); tests: unfiltered list and `publicBoard == false` list denied (`rules.test.ts:531-539, 557-563`) |
| I-4 | **The friend code, not the id, is the capability.** A profile with `public_board = false` can be reached only (a) by a code lookup made by a signed-in caller, or (b) through a friend link the viewer already owns. No endpoint takes an arbitrary profile id from the caller and returns that profile. | `get` needs sign-in and the uid is discoverable only through `friendCodes/{code}` (`:98-102`, `:164`); the SQL translation is stricter because it removes the by-id read entirely |
| I-5 | **Individual answers are never part of this block.** No table here stores them, no projection includes them, no endpoint returns them. The study snapshot lives in `data.progress-sync` and is readable by its owner only. | `private/study`: `read, delete: if isOwner(uid)` (`:129-141`); `CONTRACT.md:133-135` "never answers" |
| I-6 | **Immutable fields.** `friend_code`, `created_at`, `account_id`, `tenant_id` never change after insert. | `friendCode == resource.data.friendCode`, `createdAt == resource.data.createdAt` on update (`:119-120`); tests `rules.test.ts:277-284` |
| I-7 | **Totals are monotonic.** `xp`, `level`, `answered` never decrease, except through the reset action (I-9). A lower reported value is folded with `max`, not rejected. | `validGrowth` (`:72-77`); tests `rules.test.ts:296-306` (the shipped rules reject; the SQL fold is equivalent for honest clients) |
| I-8 | **The week is decided by server time, and nothing carries over.** `week_start_day` is always `week_start(server now)`. In a new week the base is `0`. Weekly credit per report is `min(xp gain, BURST_XP + floor(hours since previous write * XP_PER_HOUR))`; the first report of an account (stored `xp = 0` and `answered = 0`) credits `0`. | `currentWeekStart()` from `request.time` (`:15-23, 122`); `validWeekCredit` (`:79-90`); tests `rules.test.ts:341-410`. The first-report baseline is a **client** rule in the shipped system (`progress.ts:39-42`); the rules would allow up to the cap, so here the server enforces it (README D4) |
| I-9 | **Reset only to the zero state.** "Erase my data" sets `xp = 0`, `answered = 0`, `week_xp = 0`, `level = 1` (and clears streak and accuracy); nothing in between is accepted. `friend_code`, `created_at` and `public_board` survive. | `validReset` (`:92-95`); tests `rules.test.ts:412-454` |
| I-10 | **Friend links are bounded and owner-scoped.** At most `MAX_FRIENDS` per owner, no self-link, no duplicates, written only by the owner, enforced atomically with the insert. | `uids.size() <= 50` (`:152`); the cap holds under concurrency because the shipped list is edited in one transaction (`firebasePort.ts:303-314`) |

### Read matrix (the translated rules)

| Resource | Anonymous | Signed in, not the owner | Owner |
|----------|-----------|--------------------------|-------|
| Board rows (listed learners) | Read | Read | Read |
| Own rank (count of listed learners above) | Denied (needs a session; the shipped rules allow anonymous counts, but the app calls `countAbove` only when signed in, `useCommunity.ts` `refresh`) | Own rank only | Own rank only |
| Own profile, hidden or not | - | - | Read, write (bounded) |
| Non-listed profile by code | Denied | Read (projection) | Read |
| Non-listed profile by id | Denied (no such endpoint) | Only inside the viewer's own friends list | Read |
| Another learner's friend list | Denied | Denied | Own list only |
| Individual answers | Denied | Denied | Not in this block |

Anonymous read of the board is a **product decision**, not an accident: the user asked that social content be visible without signing in (origin project notes). Remove the anonymous row from the matrix if your product decides otherwise.

---

## Threat Model

### T-1. Score forgery (client-reported progress)

**Impact**: Medium for a social app, unacceptable for prizes. The server cannot recompute XP from answers it never sees.

**Mitigations (what the shipped bounds do):**
- Range checks: `xp` and `week_xp` ≤ `MAX_XP`, `level` 1..`MAX_LEVEL`, `streak_days` ≤ `MAX_STREAK_DAYS`, `answered` ≤ `MAX_ANSWERED`, `accuracy` 0..100 (`:58-67`)
- Monotonic totals (I-7), so a leaderboard position cannot be lowered or "rolled back"
- Weekly credit capped per report (I-8): a single report cannot add more than `BURST_XP` plus time-based allowance to the week
- Week and `updated_at` come from the server clock, never from the client

**What the bounds do not stop** (stated plainly; do not hide this from the product owner):
1. **All-time XP is forgeable in one request.** The credit cap limits `week_xp` only. A report with `xp = MAX_XP` is accepted and raises the all-time total; the capped week credit does not block it (shipped rule test: `xp` 50,000 with `weekXp` 4,500 succeeds, `rules.test.ts:351-353`). The original project documents this: "A forged all-time total is possible; a forged week is bounded by that cap" (`server/README.md` "Rules worth knowing"). HIGH
2. **The weekly cap is per report, and the shipped rules do not limit report frequency.** Each accepted report gets the `BURST_XP` allowance even when the previous write was seconds ago (`rules.test.ts:355-360`: 500 allowed on a one-minute-old document). Repeated small reports can therefore accumulate far more than `XP_PER_HOUR` suggests. This is an inference from the rule text and that test, not an observed exploit. MEDIUM. Mitigation in this block (extrapolated): set `REPORT_MIN_INTERVAL_SECONDS` above zero, or replace the per-report burst by a token bucket (capacity `BURST_XP`, refill `XP_PER_HOUR`) so the allowance cannot be re-spent
3. **Streak, accuracy, level and answered are only range-bounded.** A report may set `streak_days = 3650` or `accuracy = 100` at once; `level` is not tied to `xp`. They are display fields and are not ranked on, except that streak breaks ties. HIGH (`:58-67` has no relation between fields; test `rules.test.ts:234-239` edits `streakDays` freely)
4. **Many accounts per person.** Nothing ties a profile to a verified human beyond the sign-in provider. LOW (general property of open sign-in, not tested)

**Consequence for the spec:** `README.md` "When NOT to use" excludes any ranking with real stakes. Add server-side recomputation from signed answer events if you need integrity; that is a different block.

### T-2. Friend-code guessing and enumeration

**Impact**: Medium. A code resolves to a profile projection (name, level, XP) for any signed-in caller, whether or not the owner is on the board.

**Mitigations**:
- 30^8 = 656,100,000,000 possible codes; a CSPRNG draws them (`firebasePort.ts:33-36` uses `crypto.getRandomValues`)
- Format validated before any database access (`parseFriendCode`, `community.ts:33-36`)
- Lookups require a session; rate-limit them per account (`FRIEND_LOOKUP_RATE_LIMIT`, extrapolated; the shipped rules have none, so only the platform's quotas slow guessing)
- Log aggregate counts of failed lookups, never the codes themselves

**Accepted properties**:
- The code of a **listed** learner is world-readable on the board by design (`CONTRACT.md:133`: friend code of listed learners). For them the code is not secret; only learners who hide from the board get protection from it
- The code cannot be rotated (I-6). Hiding from the board does not revoke access of people who already have the code or a link to the profile. Say this in the privacy copy (below)
- Observation, no security impact: `byte % 30` over 256 values makes the first 16 symbols marginally more likely (9/256 vs 8/256) in the shipped generator; use rejection sampling in a new implementation

### T-3. Over-exposure of personal data on a public board

**Impact**: High for trust and store review. Names of real people appear to anonymous visitors.

**Mitigations**:
- Explicit projection (I-2) rather than returning rows wholesale
- Accuracy hidden below `MIN_ANSWERED_FOR_ACCURACY` at the API, not only in the UI
- Opt-out flag honored by every board query (I-3) and surfaced as a toggle with a plain-language state
- Privacy copy requirement (below)

**Known gap in the shipped system**: the privacy page sentence about the leaderboard names "display name, level, streak and XP" and a "Social tab" (`web/privacy.html:48`), while the board also shows accuracy and the friend code and the tab is called Community (playbook B section 4.3(c)). Align the policy text with the projection in I-2 before shipping.

### T-4. Unfiltered scan of non-listed profiles

**Impact**: High if it happened: private learners would be enumerable.

**Mitigations**: I-3 and I-4. There is no query parameter that widens the predicate; no endpoint accepts a profile id for a profile that is neither listed nor in the caller's friend links. Cover with the `@security` scenarios in `public-board-privacy.feature`. The shipped rule tests prove the same on Firestore: unfiltered list, `publicBoard == false` list and unfiltered count are denied for signed-in and anonymous callers.

### T-5. Week rollover abuse

**Impact**: Low to Medium. A learner could try to keep last week's XP or write into an arbitrary week.

**Mitigations**: I-8. `week_start_day` is overwritten from server time on every write; a report in a new week starts from base `0`; the board query filters `week_start_day = current`, so stale rows drop out without any job. Shipped tests: carry-over denied, staying on last week's day denied (`rules.test.ts:372-410`).

### T-6. Abusive or impersonating display names

**Impact**: Medium to High for app-store review. A world-readable board is user-generated content.

**Evidence of the gap**: the shipped rules allow the owner to set `displayName` to any 1..30 character string (`:59`, test `rules.test.ts:234-239`), and the shipped app had no report/block mechanism; the assistant warned that Apple might raise user-generated-content requirements (playbook B section 4.3(a), outcome unknown). MEDIUM.

**Mitigations (extrapolated, not in the shipped system)**:
- This block has **no rename endpoint**: the name comes from the sign-in identity at profile creation. If you add rename, add a profanity filter and a report action
- Provide a way for a viewer to report a board row and for an operator to force `public_board = false`; hide reported rows from the viewer
- Truncate and collapse whitespace on creation; render names as plain text only (never `v-html`, `innerHTML`)

### T-7. Tenant leakage

**Impact**: Critical in multi-tenant deployments.

**Mitigations**: `tenant_id` in every `WHERE`, taken from server configuration or the session, never from the request; UNIQUE indexes are per tenant; a friend link requires both profiles in the same tenant.

### T-8. Scraping and load on an anonymous endpoint

**Impact**: Medium. `GET /api/board` needs no session, so anyone can hammer it. The original project recorded no App Check or quota alert (playbook B section 4.3(b), MEDIUM).

**Mitigations (extrapolated)**: per-IP rate limit, response cache for `BOARD_REFRESH_SECONDS`, bounded `limit` (never client-chosen above `BOARD_SIZE`), and no deep pagination.

---

## Privacy Copy Requirement

Because `PUBLIC_BOARD_DEFAULT = true`, a learner appears on a world-readable board **by default**. The product must therefore say, in plain language, **before or at the moment of first listing** (sign-in screen or first-run card) **and in the privacy policy**:

1. Which fields strangers see: display name, level, XP (week and all-time), streak, accuracy (after `MIN_ANSWERED_FOR_ACCURACY` answers), friend code
2. That the board can be read **without signing in**
3. That individual answers are never shared
4. That the learner can leave the board at any time with a toggle (name the toggle's label), and what the toggle does **not** do: people who already have the friend code can still look the profile up, and friends already added can still see it
5. That friends are one-way: adding someone asks nothing of them
6. That deleting the account removes the profile, the links and the code

If the product targets minors, or a jurisdiction that requires consent before publication, set `PUBLIC_BOARD_DEFAULT = false` and add an explicit opt-in step. Whether the default of `true` is acceptable is a legal question this block does not answer (not verified).

---

## Input Validation Rules

| Field | Validation | Error Code |
|-------|-----------|------------|
| `code` (friend lookup) | Strip whitespace and `-`, upper-case; must match `^[ABCDEFGHJKMNPQRSTVWXYZ23456789]{8}$` | `invalid_friend_code` (422) |
| `xp`, `answered` | Integer, `0..MAX_XP` / `0..MAX_ANSWERED` | `invalid_stats` (422) |
| `level` | Integer, `1..MAX_LEVEL` | `invalid_stats` (422) |
| `streak_days` | Integer, `0..MAX_STREAK_DAYS` | `invalid_stats` (422) |
| `accuracy` | Integer, `0..100` | `invalid_stats` (422) |
| `public_board` | Boolean | `invalid_request` (422) |
| `period` (board) | One of `week`, `all` | `invalid_period` (422) |
| `account_id`, `profile_id` for self, `tenant_id`, `week_start_day`, `updated_at`, `rank` | **Never accepted from the body**; derived server-side | - |

Unknown body fields are rejected, not ignored (mirrors the `hasOnly` key whitelist at `firestore.rules:35-38`).

## Secrets Management

No block-specific secrets. Authentication relies on the app's existing auth layer (`auth.google-login`). Do not commit service credentials or project identifiers for the datastore; do not place real account identifiers or emails in fixtures or logs.
