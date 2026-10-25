# Backend Patterns - Progress Sync

The server side of this block is deliberately small: it stores **one opaque snapshot per account** and enforces ownership, size, and a compare-and-swap on `revision`. It does not know the sections, does not merge, and does not validate domain data. The merge runs on the client (see `frontend.md`), which is why the server needs no domain code and why a fix to a merge rule ships with the app, not with the API.

Everything on this page is a translation of a document-store design (one document per user, atomic read-merge-write inside a database transaction) to a SQL table. The translation has not been run on stacks A, B, or C.

## API Endpoints

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `GET` | `/api/progress/snapshot` | Read the account's snapshot and revision | Verified session |
| `PUT` | `/api/progress/snapshot` | Write the snapshot if the revision still matches | Verified session |
| `DELETE` | `/api/progress/snapshot` | Erase the account's snapshot (idempotent) | Verified session |

All endpoints require the auth block's middleware: it attaches `{ accountId }` from the verified session to the request context. `accountId` is the only identity the handlers use.

### `GET /api/progress/snapshot`

| Status | Body | When |
|--------|------|------|
| 200 | `{ "snapshot": "<json text>", "revision": 5, "updated_at": "<ISO 8601 UTC>" }` | A row exists for the account |
| 404 | `{ "error": "no_snapshot" }` | No row. The client treats this as "nothing in the cloud yet", not as a failure. |
| 401 | `{ "error": "unauthenticated" }` | No or invalid session |

`snapshot` is a **string** containing JSON, as the client sent it (a `json` column may have reformatted it; clients re-serialize deterministically and never compare bytes with what they read back).

### `PUT /api/progress/snapshot`

Request body:

```json
{ "snapshot": "<json text>", "format_version": 1, "base_revision": 5 }
```

`base_revision` is the revision the client merged against; `0` means "I found no row". Success returns the new revision.

| Status | Body | When |
|--------|------|------|
| 200 | `{ "revision": 6, "updated_at": "<ISO 8601 UTC>" }` | Written |
| 400 | `{ "error": "invalid_request" }` | Body is not an object with the three fields, or `base_revision` is not a non-negative integer, or `snapshot` is not a string |
| 401 | `{ "error": "unauthenticated" }` | No or invalid session |
| 409 | `{ "error": "revision_conflict", "revision": 6 }` | The stored revision differs from `base_revision` (or a row exists and `base_revision` is 0). Nothing was written. |
| 413 | `{ "error": "snapshot_too_large" }` | `snapshot` longer than `SNAPSHOT_MAX_CHARS_SERVER` characters. Checked before parsing. |
| 422 | `{ "error": "invalid_snapshot" }` | `snapshot` does not parse as a JSON object |
| 422 | `{ "error": "unsupported_format_version" }` | `format_version` is not `1` |

### `DELETE /api/progress/snapshot`

`204` whether or not a row existed. After a `204` the next `GET` is `404 no_snapshot`.

## Business Logic

### Write algorithm (L1)

1. Resolve `accountId` from the verified session. Ignore any account id in the body or query.
2. Reject bodies larger than `SNAPSHOT_MAX_CHARS_SERVER` plus a small envelope allowance **at the transport layer before buffering them** (see `security.md`).
3. Validate the envelope: object, `snapshot` string, `format_version` integer, `base_revision` non-negative integer. Else 400.
4. `format_version` must equal 1. Else 422.
5. `content_length` = character length of `snapshot` as received. If it exceeds `SNAPSHOT_MAX_CHARS_SERVER`: 413.
6. Parse `snapshot`; it must be a JSON object (not array, string, number, null). Else 422.
7. Write with a **single atomic statement** that succeeds only if the revision matches:
   - `base_revision = 0`: insert a row; if a row for `account_id` already exists, nothing is inserted.
   - `base_revision > 0`: update the row where `account_id` matches **and** `revision = base_revision`, setting `revision = revision + 1` and `updated_at` = server now.
8. If the statement affected no row: 409 with the current revision (read it in a second query; it is informational only).
9. Else 200 with the new revision and `updated_at`.

The compare-and-swap replaces the document store's transaction. The conflict is expected under concurrency and is resolved by the **client**: it re-reads, re-merges, and writes again (frontend.md, pattern `sync-retry-loop`).

### Why revision and not `updated_at`

Two writes can land within the same clock tick, and a client clock is not trusted. `revision` is a counter the server increments inside the same statement as the write, so it is monotonic and unforgeable. `updated_at` is informational (shown to the user as "last synced").

### Pattern 1: shape and size gate

<!-- PATTERN: snapshot-write-gate -->
<!-- PURPOSE: Reject oversized or non-object snapshots before touching the database -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: replace the returned `{ status, error }` shape with the project's error type or Result; MAX comes from config SNAPSHOT_MAX_CHARS_SERVER; keep the check order (size first, parse second) because parsing a huge string is the cost being avoided -->
```typescript
type Gate = { ok: true; length: number } | { ok: false; status: 400 | 413 | 422; error: string };

export function gateSnapshotWrite(body: unknown, MAX: number): Gate {
  if (typeof body !== "object" || body === null) return { ok: false, status: 400, error: "invalid_request" };
  const { snapshot, format_version, base_revision } = body as Record<string, unknown>;
  if (typeof snapshot !== "string" || !Number.isInteger(base_revision) || (base_revision as number) < 0)
    return { ok: false, status: 400, error: "invalid_request" };
  if (format_version !== 1) return { ok: false, status: 422, error: "unsupported_format_version" };
  if (snapshot.length > MAX) return { ok: false, status: 413, error: "snapshot_too_large" };
  try {
    const parsed = JSON.parse(snapshot);
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
  } catch {
    return { ok: false, status: 422, error: "invalid_snapshot" };
  }
  return { ok: true, length: snapshot.length };
}
```

### Pattern 2: compare-and-swap write

<!-- PATTERN: snapshot-cas-write -->
<!-- PURPOSE: Write a snapshot only if the caller merged against the current revision, in one atomic statement -->
<!-- REFERENCE: dialect=postgres orm=raw-sql -->
<!-- ADAPT: placeholders $1.. are postgres-style, MySQL/SQLite use ?; `RETURNING` exists in postgres and SQLite 3.35+, on MySQL run the statement then read affected rows and SELECT revision; `ON CONFLICT DO NOTHING` becomes `INSERT IGNORE` on MySQL; `now()` becomes `CURRENT_TIMESTAMP` or an app-supplied UTC instant on SQLite; ORM equivalent: Drizzle `.insert().onConflictDoNothing().returning()` and `.update().where(and(eq(..), eq(..))).returning()`, Prisma `updateMany` with both conditions and a count check -->
```typescript
// accountId comes from the verified session context, never from the request.
async function writeSnapshot(db: Db, accountId: string, text: string, len: number, base: number) {
  const rows = base === 0
    ? await db.query(
        `INSERT INTO progress_snapshots (account_id, snapshot, content_length)
         VALUES ($1, $2, $3) ON CONFLICT (account_id) DO NOTHING
         RETURNING revision, updated_at`, [accountId, text, len])
    : await db.query(
        `UPDATE progress_snapshots
            SET snapshot = $2, content_length = $3, revision = revision + 1, updated_at = now()
          WHERE account_id = $1 AND revision = $4
          RETURNING revision, updated_at`, [accountId, text, len, base]);
  return rows.length === 1 ? { ok: true as const, ...rows[0] } : { ok: false as const };
}
```

### Pattern 3: handler composition

<!-- PATTERN: snapshot-put-handler -->
<!-- PURPOSE: Wire gate, write, and conflict response into the PUT endpoint -->
<!-- REFERENCE: framework=agnostic runtime=node20+ -->
<!-- ADAPT: `ctx.accountId` comes from the auth block's middleware (Express `req`, Hono `c.var`, Fastify `req`); `json(status, body)` is the project's response helper; `readRevision` is a SELECT of revision by account_id; rate limiting and body-size limiting are middleware, not shown -->
```typescript
export async function putSnapshot(ctx: { accountId: string; body: unknown }, db: Db, MAX: number) {
  const gate = gateSnapshotWrite(ctx.body, MAX);
  if (!gate.ok) return json(gate.status, { error: gate.error });
  const { snapshot, base_revision } = ctx.body as { snapshot: string; base_revision: number };
  const w = await writeSnapshot(db, ctx.accountId, snapshot, gate.length, base_revision);
  if (!w.ok) return json(409, { error: "revision_conflict", revision: await readRevision(db, ctx.accountId) });
  return json(200, { revision: w.revision, updated_at: w.updated_at });
}
```

## Middleware

- **Auth**: required on all three endpoints; an unauthenticated request never reaches a handler (401).
- **Body size**: reject by `Content-Length` and by streamed byte count above `SNAPSHOT_MAX_CHARS_SERVER` plus 4 KiB envelope allowance, before parsing. Characters can be more than one byte each, so the byte limit is a coarse guard and the character check in the gate is the contract.
- **Rate limiting**: limit `PUT` per account (the client sends at most one write per `SAVE_DELAY_MS` plus conflict retries). The value is the adopter's choice.

## Error Handling

| Error | Response | Logged | Notes |
|-------|----------|--------|-------|
| Gate failures | 400 / 413 / 422 with `error` code | code and `content_length` only | Never log the snapshot text: it is the user's private data. |
| Revision conflict | 409 | no (expected under concurrency) | Counted as a metric if desired. |
| Database failure | 500 `{ "error": "server_error" }` | error class, account id hash | Client keeps local data and retries after `RETRY_DELAY_MS`. |

Error body shape is always `{ error: string, ... }`; no stack traces.

## Anti-patterns

- **DON'T** merge on the server by interpreting sections. The server would need every domain rule, and a rule change would need an API deploy.
- **DON'T** implement the write as `SELECT revision` then `UPDATE`. Two requests can both pass the check; the revision test must be inside the `WHERE` of the write statement.
- **DON'T** use `updated_at` or a client timestamp as the conflict token (clock skew, same-tick writes).
- **DON'T** take `account_id` from the body, query string, or a header the client controls.
- **DON'T** answer a `GET` with a row from a different account because of a missing `WHERE` - every query filters by `account_id`.
- **DON'T** return `404` for `DELETE` of a missing row; erase must be safely repeatable (a half-finished erase is re-run).
- **DON'T** compare read-back snapshot bytes with what was written (a `json` column may reorder keys and drop whitespace).
