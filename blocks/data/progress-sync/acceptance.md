# Acceptance - Progress Sync

Verification checklist Claude Code runs AFTER implementation, BEFORE reporting done. Every item must pass. Tests are generated from the `.feature` files and the JSON fixtures; there is no shipped `tests/` folder, so create the test files in the project's own test framework.

Items tagged **[client]** apply to the local store and sync client, **[server]** to the Snapshot API and table. A project that has no server (local-only use) skips the **[server]** items and the `cloud-sync.feature` / `account-switch.feature` scenarios that need an account; say so in the report.

## Build & Types

- [ ] Type check passes with zero errors (`tsc --noEmit` or the project's equivalent)
- [ ] No `any` types except with an explicit justification comment
- [ ] `progressCore` (validate, recover, merge, serialize, parse) has no imports from the UI framework, storage, network, or clock

## Database [server]

- [ ] Migration runs successfully on a clean database
- [ ] Migration is idempotent (running twice does not error)
- [ ] `progress_snapshots.account_id` has a UNIQUE constraint
- [ ] A CHECK (or equivalent) rejects `content_length` above `SNAPSHOT_MAX_CHARS_SERVER`
- [ ] `created_at` and `updated_at` exist; `updated_at` is set by the server on every write and cannot be supplied by the client
- [ ] The snapshot column accepts a JSON object and rejects non-JSON text on the project's dialect

## Local Store [client]

- [ ] `load()` never throws: every case in `fixtures/load-repair-cases.json` passes (INV-2, INV-3, INV-7)
- [ ] Unknown top-level keys survive load, export, and import (INV-1)
- [ ] A section whose version is newer than the client knows is kept untouched (INV-1)
- [ ] Storage unavailable at start: app runs from memory with `persistent = false` (INV-5)
- [ ] A failed write keeps the in-memory data and does not adopt older storage (INV-5)
- [ ] Crossing `MAX_HISTORY` keeps the newest entries and renumbers `seq`; no other section is reset (INV-7)
- [ ] All scenarios in `local-store.feature` pass

## Import / Export [client]

- [ ] Every case in `fixtures/invalid-imports.json` returns exactly the listed `ok` / `error`, leaves `store.data` and stored text unchanged, and does not throw (INV-3)
- [ ] The two `ok: true` boundary cases (`note-at-limit`, `entry-time-back-within-a-day`) pass
- [ ] Import text over `MAX_IMPORT_CHARS` is refused before parsing
- [ ] A write failure during import restores the previous data and `persistent` flag and returns `quota`
- [ ] Export then import round-trips the whole record
- [ ] The import UI maps every error path to wording; an unknown path shows the generic wording, never an empty message
- [ ] All scenarios in `import-export.feature` pass

## Multi-tab [client]

- [ ] Every write goes through `update(fn)`: `rg` finds no direct storage write to `STORE_KEY` outside the store module (INV-4)
- [ ] Two stores on one storage keep all answers whether or not storage events arrive
- [ ] Reset in one store is not undone by the other store's next write, heard or not
- [ ] Refresh runs on the storage event for the key (and for a cleared storage), page show, and visibility to visible; not on hidden or on other keys
- [ ] An invalid external value is ignored without throwing
- [ ] All scenarios in `multi-tab.feature` pass

## Merge [client]

- [ ] `merge(A, B)` equals `fixtures/snapshot-merged-a-local.json`, structurally (INV-8)
- [ ] `merge(B, A)` equals `fixtures/snapshot-merged-b-local.json`, structurally
- [ ] `merge(M, B) == M` where `M = merge(A, B)`, compared as serialized text (idempotence)
- [ ] `merge(A, null)` returns only the synced sections
- [ ] Merge reads no clock: the function takes no time argument and the module imports no clock (INV-8)
- [ ] Removal stamps: removed bookmark stays removed, later re-add stands, equal-time tie keeps the bookmark; deleted word stays deleted, later re-save stands, `savedAt` equal to the tombstone is dropped (INV-9)
- [ ] Stamped sections: later stamp wins, unstamped loses, tie keeps local (INV-10)
- [ ] Malformed `edits` entries are ignored and do not break the merge
- [ ] Serialization is deterministic: synced sections in fixed order, `edits` map keys sorted (INV-11)
- [ ] All scenarios in `snapshot-merge.feature` pass

## Cloud Sync [client + server]

- [ ] Signed out: zero requests (INV-12, INV-14)
- [ ] First sign-in sends `base_revision: 0`; the response sets the owner marker (INV-12)
- [ ] A burst of changes produces one write `SAVE_DELAY_MS` after the last change; a sync that changes nothing locally causes no further write (INV-11)
- [ ] A change made during an in-flight sync causes exactly one follow-up sync
- [ ] Network or server failure sets `error`, keeps local data, retries after `RETRY_DELAY_MS` (INV-14)
- [ ] Unreadable cloud copy: `blocked`, no PUT, cloud text unchanged (INV-13)
- [ ] Merged text over `SNAPSHOT_MAX_CHARS_CLIENT`: `blocked`, no PUT (INV-6, INV-13)
- [ ] 409 triggers re-read, re-merge, re-write, at most `MAX_CONFLICT_RETRIES` attempts (INV-16)
- [ ] `cache`, `session`, the owner marker, and unknown keys never appear in a sent snapshot (INV-15)
- [ ] All scenarios in `cloud-sync.feature` pass

## Accounts and Erase [client + server]

- [ ] Different owner: data replaced, not merged; the old data is in the `PREVIOUS_KEY` slot; preferences stay (INV-12)
- [ ] Same owner and guest data merge
- [ ] If the backup cannot be written, the replacement does not happen
- [ ] An import clears the owner marker
- [ ] Erase while signed in deletes the cloud copy first; on failure nothing is erased locally
- [ ] All scenarios in `account-switch.feature` pass

## Snapshot API [server]

- [ ] Every case in `fixtures/api-cases.json` returns the listed status and body
- [ ] The write is a single atomic statement with the revision test in its WHERE (or an equivalent transaction); a concurrency test with two simultaneous writers on the same `base_revision` yields exactly one 200 and one 409
- [ ] `account_id` is read only from the verified session; a request carrying another account id in body, query, or header does not change which row is touched
- [ ] Snapshot text is never written to logs (grep logs of a test run for a marker string placed in a note)
- [ ] Body larger than the cap is rejected before it is fully buffered
- [ ] Error bodies are `{ error: string, ... }` with no stack traces

## Security

- [ ] Threat model items 1-6 in `security.md` each have the listed mitigation implemented or an explicit decision recorded in the report
- [ ] Edit stamps outside `0 <= at < MAX_AT` are ignored by the cleaner
- [ ] Map sections keyed by user text reject `__proto__`, `constructor`, `prototype` keys or use null-prototype objects / `Map`
- [ ] No hardcoded secrets; no tokens or identity in the Local Store Record, the snapshot, or an export
- [ ] Entitlements are not part of the synced sections

## Configuration

- [ ] Every key in README section 7 is exposed as configuration (or a documented constant) with the listed default
- [ ] `SNAPSHOT_MAX_CHARS_SERVER >= SNAPSHOT_MAX_CHARS_CLIENT` is enforced at startup
- [ ] `STORE_KEY` embeds a major version suffix

## Block-specific criteria

- [ ] Every INV-1 .. INV-16 in README section 8 maps to at least one passing test; list the mapping in the report
- [ ] The report lists which parts could not be run on the project's stack and why
- [ ] **3-Stack mental test** (docs/SPEC_GUIDELINES.md section 7) - author's answers, not run on any stack: (1) data model: one table, logical types `unique_id`, `external_id`, `integer`, `json`, `timestamp` all map on Postgres, MySQL, SQLite - yes; (2) snippets: the SQL snippet differs only in placeholders, `RETURNING`, `ON CONFLICT` - ADAPT lists them - yes; (3) external contract: no external protocol is dictated, status codes and error codes are concrete - yes; (4) sequence flow: no framework-specific feature, conflict handling is a status code and a loop - yes; (5) acceptance: every item is checkable with a plain SQL database and a fake storage - yes
