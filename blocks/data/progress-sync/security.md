# Security - Progress Sync

Scope: the local store, the import file, the cloud snapshot, and the Snapshot API. Authentication itself belongs to the auth blocks (`auth.google-login`, `auth.sign-in-with-apple`); this block consumes the verified account id they produce.

Each item is tagged **[shipped]** when the source app implements and tests it, or **[extrapolated]** when this block adds it and it has not been run (see the README, "Origin and verification status").

## Threat Model

### 1. Hostile or corrupted input (import file, stored data, cloud copy)

**Impact**: High - an exception on load bricks the app; an oversized or deeply nested value breaks layout or exhausts memory; invented history inflates progress; a crafted cloud copy overwrites the user's data on every device.

**Mitigations**:
- Three inputs, three behaviors (INV-2, INV-3): stored data is repaired per section; an import is refused whole with an error path; a cloud copy that fails strict validation is never merged and never overwritten (`blocked`). **[shipped]**
- Size is checked before parsing: import text over `MAX_IMPORT_CHARS`, snapshot over the client or server cap. **[shipped]**
- Field limits (`MAX_KEY_CHARS`, `MAX_MEANING_CHARS`, `MAX_EXAMPLE_CHARS`, `MAX_TEXT`), list limits (`MAX_HISTORY`), duplicate rejection (marks, normalized collection keys, `sources`). **[shipped]**
- Plausibility checks on history: `seq` equals position, `ms` in `0..MAX_ELAPSED_MS`, `at` below `MAX_AT` and not earlier than the latest earlier `at` by more than `AT_SKEW_MS`, derived field `ok` equals the value recomputed from the current answer key. A shuffled or invented history is rejected. **[shipped]**
- Reserved object keys: any section that is a map keyed by user-supplied text (`notes`, `edits.marks`, `edits.collection`) is built as a null-prototype object or a `Map`, and keys `__proto__`, `constructor`, `prototype` are rejected by validation. **[extrapolated]** (the source app validates `marks` against known ids, but does not check the keys of `notes` or `edits`).
- Rendering: stored text (notes, collection fields) is rendered as text, never as HTML. **[extrapolated]** (a UI property outside this block; not verified for notes in the source app).

### 2. Lost or reverted writes (integrity)

**Impact**: High - silent loss of a user's history is the worst failure of this block.

**Mitigations**:
- Merge before write on every `update` (INV-4): storage is the truth, the pending change lands on top of it. **[shipped]** Found by an independent judge: a second tab's stale memory wiped answers and undid a Reset.
- A write that fails does not discard memory data and does not adopt older storage (INV-5). **[shipped]**
- Crossing `MAX_HISTORY` keeps the newest entries; it never resets the whole section (INV-7). **[shipped]** Found by an independent judge: history was wiped at the 20,001st answer.
- Import rolls back to the previous data when storage cannot hold the new data. **[shipped]**
- Cloud write is a compare-and-swap on `revision`; a lost race becomes a re-merge, not an overwrite. **[extrapolated]**
- Erase removes the cloud copy first and aborts if that fails. **[shipped]**

### 3. Cross-account exposure (shared device, cross-tenant access)

**Impact**: High - another person's progress, notes, or saved items appear in the wrong account, or one account reads another's snapshot.

**Mitigations**:
- Server: `account_id` comes only from the verified session; every query includes `WHERE account_id = <session account>`; no endpoint accepts an account id. **[shipped]** as an owner-only rule in the source app's database rules; **[extrapolated]** for the SQL form.
- Client: the owner marker `cloud.uid` records which account the device's data belongs to. Signing in as a different account **replaces** the data with that account's copy instead of merging, after the old data is saved aside (INV-12). **[shipped]**
- Guest data (no owner) merges into the first account that signs in. This is a product decision: the person using the device is assumed to be the person who made the guest data. **[shipped]**
- The auth profile (uid, display name) is stored under a separate key from the Local Store Record, so export, import, and backups never carry credentials or identity. **[shipped]**
- Signing out does not erase local progress (it belongs to the device). On a shared device the user needs the explicit Erase control; surface it near Sign out. **[extrapolated]**
- The previous-data backup holds another person's progress in plain text on the device. It is local only, never synced, and removed by Erase. **[extrapolated]** (the source app keeps it; whether Erase removes it was not verified).

### 4. Abuse of the Snapshot API (cost, availability)

**Impact**: Medium - an authenticated client can write the cap-sized snapshot repeatedly, or send huge bodies to exhaust memory.

**Mitigations**:
- Body size rejected at the transport layer before buffering (backend.md); character cap checked before parsing. **[shipped]** for the size cap in the source app's database rules; **[extrapolated]** for the transport limit.
- Per-account rate limit on `PUT`; the client already coalesces bursts to one write per `SAVE_DELAY_MS`. **[extrapolated]**
- `SNAPSHOT_MAX_CHARS_SERVER >= SNAPSHOT_MAX_CHARS_CLIENT`, so a well-behaved client is never rejected by the server because of the cap. **[shipped]** (900,000 vs 950,000 in the source app).
- `content_length` CHECK in the table, so an application bug cannot store an oversized row. **[extrapolated]**

### 5. Clock-dependent merge inputs (stamp poisoning)

**Impact**: Medium - merge decisions use stamps written by device clocks. A device with a clock far in the future wins every stamped field and keeps a deletion forever; a clock far in the past loses them.

**Mitigations**:
- Merge itself reads no clock (INV-8); stamps are data. **[shipped]**
- History `at` values are bounded (`MAX_AT`) and kept near-monotonic by validation. **[shipped]**
- Edit stamps (`edits.*`) must also be finite, non-negative, and below `MAX_AT`; cleaning ignores a stamp outside that range. **[extrapolated]** (the source app accepts any finite non-negative number).
- Accepted residual risk: a stamp inside the valid range but wrong (a clock one year ahead) still wins. The block documents it; it does not try to fix clocks.

### 6. Private data at rest and in logs

**Impact**: Medium - notes and saved items are free text and may contain personal data.

**Mitigations**:
- The snapshot is readable and writable only by its owner; it is never exposed in leaderboard or friends views (those use derived numbers from `ugc.friends-leaderboard`). **[shipped]**
- Never log snapshot text, import text, or note contents; log lengths, error codes, and status only. **[extrapolated]**
- Account deletion removes the snapshot row (`compliance.account-deletion`); the local copy stays on the device. **[shipped]** for deletion of the cloud copy in the source app; **[extrapolated]** for the SQL form.
- Entitlements are not part of the snapshot, so an edited import or a forged cloud copy cannot unlock paid features (`billing.in-app-purchase`). **[shipped]**

## Input Validation Rules

| Input | Validation | Error |
|-------|-----------|-------|
| Import text | length `<= MAX_IMPORT_CHARS`; parses as JSON; root is an object | `too large`, `not valid JSON`, `not an object` |
| `history.entries` | array, length `<= MAX_HISTORY` | `history.entries` |
| `history.entries[i].ref` | string, known to the app | `history.entries[i].ref` |
| `history.entries[i].value` | one of the allowed values | `history.entries[i].value` |
| `history.entries[i].ok` | boolean, equals the recomputed grade | `history.entries[i].ok` |
| `history.entries[i].seq` | integer, equals `i + 1` | `history.entries[i].seq` |
| `history.entries[i].ms` | finite number, `0 <= ms <= MAX_ELAPSED_MS` | `history.entries[i].ms` |
| `history.entries[i].at` | optional integer `0 <= at < MAX_AT`, not below the latest earlier `at` minus `AT_SKEW_MS` | `history.entries[i].at` |
| `history.seq` | integer, equals `entries.length` | `history.seq mismatch` |
| `marks` | strings, each a known `ref`, no duplicates | `marks`, `marks duplicate` |
| `collection[i].key` | non-empty after trim, `<= MAX_KEY_CHARS` | `collection[i].key` |
| `collection[i].meaning` / `.example` | string, `<= MAX_MEANING_CHARS` / `MAX_EXAMPLE_CHARS` | `collection[i].meaning`, `.example` |
| `collection[i].sources` | array of allowed values, no duplicates | `collection[i].sources` |
| `collection[i].savedAt` | optional finite number | `collection[i].savedAt` |
| `collection` keys | no two entries with equal `normalizeKey(key)` | `collection[i] duplicate` |
| `notes` | map of strings, each `<= MAX_TEXT` | `notes.<ref>` |
| `prefs.lang` | one of the supported languages | `prefs.lang` |
| `milestones` | `v` integer `>= 1`; if `v` is newer than known: accepted untouched; else `level` in range, `badges` known and unique | `milestones` |
| `PUT` envelope | object with `snapshot` string, `format_version` 1, `base_revision` integer `>= 0` | `invalid_request`, `unsupported_format_version` |
| `PUT` snapshot | length `<= SNAPSHOT_MAX_CHARS_SERVER`; parses to a JSON object | `snapshot_too_large`, `invalid_snapshot` |

The error strings are stable identifiers (the UI maps them to wording); do not localize them in the validator.

## Auth/Authz

- All three endpoints require a verified session; unauthenticated requests get 401 before any other check.
- A session may read, write, and delete only the row whose `account_id` equals its own account id. There is no admin path in this block.
- Local data needs no authorization: it belongs to whoever holds the device.

## Tenant Isolation

<!-- PATTERN: snapshot-tenant-isolation-rule -->
<!-- PURPOSE: Show where account_id must come from and where it must never come from -->
<!-- REFERENCE: dialect=postgres orm=raw-sql -->
<!-- ADAPT: placeholder `$1` is postgres-style, MySQL/SQLite use `?`; `ctx.accountId` is set by the auth block's middleware (Express `req`, Hono `c.var`, Fastify `req`); never read the account id from body, query, or params -->
```typescript
// CORRECT - the account id is the verified session's
const row = await db.query(
  `SELECT snapshot, revision, updated_at FROM progress_snapshots WHERE account_id = $1`,
  [ctx.accountId],
);

// WRONG - attacker-controlled account id
const row = await db.query(
  `SELECT snapshot, revision, updated_at FROM progress_snapshots WHERE account_id = $1`,
  [ctx.body.accountId],
);
```

## Secrets Management

This block holds no secrets of its own.

| Item | Rule |
|------|------|
| Session tokens, refresh tokens | Owned by the auth block; never written to the Local Store Record, never in a snapshot, never in an export file. |
| Auth profile (account id, display name) | Separate device key from `STORE_KEY`. |
| Database credentials | Environment variables of the service, as for any endpoint. |
| Anything in the snapshot | Treated as private user data, not as a secret store; no keys or tokens belong in it. |
