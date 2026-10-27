# Acceptance - Guest Account

Verification checklist Claude Code runs AFTER implementation, BEFORE reporting done. Tests are generated from the six `.feature` files and the four fixtures; there is no shipped `tests/` folder, so create the test files in the project's own test framework. Items tagged **(manual)** cannot be checked from code and go into the report as "needs manual setup". Items tagged **(platform)** need a device or a store console.

## Build and types

- [ ] The project's type check passes with zero errors
- [ ] No `any` types except with an explicit justification comment
- [ ] `powBits`, `powValid`, `exchangeOutcome`, `guestWeight`, `previewDigest`, `defaultChoice`, `canonicalCode` and `promptDue` are pure: no imports of storage, network, clock or UI framework
- [ ] No framework syntax appears in the spec-level behaviour of the implementation notes the project writes

## Database

- [ ] The migration of `README.md` section 2 runs on a clean database and is idempotent
- [ ] `accounts.kind = linked` requires `linked_at` and `status = active`; `kind = guest` requires `linked_at IS NULL` (CHECK or equivalent)
- [ ] `guest_credentials`: UNIQUE `(tenant_id, secret_hash)`; at most one active credential per `(account_id, purpose)`; UNIQUE `(tenant_id, creation_request_id)` where set
- [ ] `guest_sessions.token_hash` is UNIQUE; no plaintext token or secret exists in any column
- [ ] `ON DELETE CASCADE` from `accounts` reaches credentials, sessions and link attempts (on SQLite, foreign keys are enabled on every connection)
- [ ] `abuse_counters` increments with one atomic statement; two concurrent requests cannot both pass the last slot
- [ ] Every table has `tenant_id` and every lookup in the code filters by it
- [ ] Expired `guest_challenges`, `abuse_counters`, `guest_sessions` and `guest_tombstones` are deleted by the sweep

## Issuance

- [ ] First launch in `general` mode creates an account with no screen, prompt or permission request (`guest-issuance.feature`)
- [ ] `account_id` is a server-generated UUID version 4, never accepted from a request, unchanged in every later response
- [ ] The secret and tokens are returned once and stored only as SHA-256 hashes
- [ ] A retry with the same `creation_request_id` inside `GUEST_CREATE_REPLAY_WINDOW_MINUTES` returns the same account and a new secret; after the window or after the first exchange it answers `409 request_consumed` (`creation_replay` in `fixtures/lifecycle-cases.json`)
- [ ] The client reads secure storage again before creating, and never creates while a valid credential is present
- [ ] A `4xx` exchange outcome never creates an account by itself
- [ ] `platform` other than `ios` and `android` answers `400`
- [ ] No advertising identifier is read, sent or stored (search the code for the platform advertising-ID APIs and find none)

## Credentials and sessions

- [ ] Every row of `fixtures/accounts.json` `exchange_cases` returns the listed status, code and reason
- [ ] The unknown-secret case carries no reason field
- [ ] Failed exchanges count in `credential_fail_network_hour`; the 21st in an hour answers `429`
- [ ] A guest session resolves to `{ account_id, tenant_id, kind, linked_at }`; a linked session resolves to the same shape
- [ ] `last_active_at` is written at most once per `GUEST_ACTIVITY_TOUCH_MINUTES`

## Abuse controls

- [ ] `powValid` matches every case of `fixtures/abuse-vectors.json` `pow.cases`, including the two format rejections
- [ ] `powBits` matches every case of `pow_bits`
- [ ] Every case of `limits` answers as listed; the global cap raises difficulty and shedding starts at twice the cap
- [ ] IPv4 uses the full address and IPv6 the /64 prefix (`network_bucket`)
- [ ] A challenge is single use, expires after `GUEST_POW_CHALLENGE_TTL_SECONDS` and is refused for another network bucket
- [ ] Limits, challenge and proof are checked before attestation; the attestation verifier is not called for a request that failed an earlier check
- [ ] Every row of `attestation_modes` answers as listed; `required` is documented in the project's setup notes as unsafe during a platform-service outage
- [ ] **(platform)** iOS attestation verification follows the steps of Apple's "Validating apps that connect to your server" (chain to the App Attest root, nonce, key identifier, RP ID hash, counter 0, aaguid for the environment); development and production keys are kept apart
- [ ] **(platform)** Android tokens are decoded with `decodeIntegrityToken` on Google's servers; `requestHash`, package name, timestamp, `PLAY_RECOGNIZED` and `MEETS_DEVICE_INTEGRITY` are checked (`android_verdict_cases`)
- [ ] The creation log line has only the allowed fields of `log_line_examples`; none of `forbidden_fields` appears in any log, counter, event or crash report (search a log sample and the event payloads)
- [ ] Counter keys are keyed hashes that change after `ABUSE_KEY_ROTATION_HOURS`
- [ ] **(manual)** The base proof-of-work difficulty was timed on the slowest supported phone in the project's web-tech shell and the value written in the setup notes
- [ ] **(manual)** The web server's access-log retention is set and listed in the privacy text

## Lifecycle

- [ ] Every row of `fixtures/lifecycle-cases.json` `sweep_cases` ends as listed, with the listed events
- [ ] A dormant guest is reactivated by an exchange and `guest_reactivated` carries `dormant_days` (28 in the fixture)
- [ ] A purge calls every block's `deleteAccount`, deletes the `accounts` row, writes tombstones without an account id, and emits `guest_purged` without an account id
- [ ] A guest with a paid holding, or with a participant that did not answer, is not purged for idleness
- [ ] A launch during the purge transaction cancels it
- [ ] Linked accounts are never made dormant or purged by this block
- [ ] Tombstones expire by `GUEST_TOMBSTONE_RETENTION_DAYS` and an expired tombstone answers `401`
- [ ] The Settings text states the idle period after which unused guest games are removed

## Recovery

- [ ] The recovery code is 24 characters of the Crockford alphabet drawn uniformly (no modulo bias), 120 bits, shown once, stored as SHA-256 of the canonical string
- [ ] `canonicalCode` matches every case of `recovery.canonical_input_cases`
- [ ] Every case of `fixtures/accounts.json` `recovery_cases` answers as listed; a wrong-length code reads nothing from the database and spends no attempt
- [ ] Recovery retires the lost device's credential (`recovered`) and the code (`used`), issues a new credential and session in one transaction, and prompts for a new code
- [ ] The eleventh recovery attempt from one network bucket in an hour answers `429`
- [ ] **(platform)** With `GUEST_CREDENTIAL_PLATFORM_BACKUP` on, the secret is in Block Store (Android) or a synchronizable Keychain item (iOS), never in Auto Backup targets, and the setup notes record that Block Store's cloud copy is end-to-end encrypted only with a screen lock on Android 9 or higher
- [ ] The app starts correctly whether or not secure storage survives an uninstall (run both cases)

## Linking, same account

- [ ] A link keeps `account_id`, sets `kind` once, inserts the `users` row with `id = account_id`, retires both credentials, revokes the guest sessions and returns a login-block session (`link-same-account.feature`)
- [ ] No participant `mergeAccounts` is called by a same-account link; a count of re-keyed rows in other blocks is zero
- [ ] The nonce is single use, bound to the attempt, and must equal the provider token's nonce claim; a proof of another attempt is refused
- [ ] Link start, recovery-code creation and deletion require the device secret in addition to the session
- [ ] The kind change is a compare-and-set; two attempts for one provider identity produce one link and one conflict
- [ ] A lost response is recovered by `403 account_linked` and a provider sign-in on the same account
- [ ] The prompt follows `promptDue` (not before the first win, once per session, cooldown, maximum dismissals, never in `kids` mode or for an under-age account, never offline)
- [ ] On iOS, Apple is offered with equal prominence wherever Google is offered
- [ ] Purchases made as a guest carry `account_id` as the Apple app account token and as the Google obfuscated account id

## Link conflict

- [ ] `guestWeight`, `defaultChoice` and `previewDigest` match every case of `fixtures/link-conflict-cases.json` `weight_cases`, and the digest ignores list order
- [ ] A pristine guest gets no sheet and the listed notice; no participant is called
- [ ] A played guest gets `keep_existing` suggested with import on; a paid guest gets no preselection and one acknowledgement per paid holding that is not carried
- [ ] The confirm request carries the digest of the shown list; a changed list answers `409 preview_changed`; nothing runs before a valid confirmation
- [ ] Keep-existing with import calls each participant once with `merge_id = "link:" + link_attempt_id`; keep-existing without import calls none; keep-guest changes nothing
- [ ] An interrupted import resumes and applies each participant once; the guest is abandoned only after all finished
- [ ] A second merge of the same guest answers `already_merged`; the per-target daily limit answers `429`
- [ ] The conflict body carries no id, email, name or timestamp of the other account
- [ ] The email-conflict variant has no import and offers the other provider or staying a guest
- [ ] An abandoned guest is purged after `GUEST_ABANDONED_RETENTION_DAYS`
- [ ] **Release gate**: list every block of the project that keys rows by `account_id`; each has registered `holdings` and `mergeAccounts` or declared `no_holdings`; the report names the list
- [ ] No code path writes a `data.progress-sync` snapshot or sets its owner marker while `kind = guest` (search for the snapshot call sites and the marker writes); the first sync starts after the link and sets the marker to the unchanged `account_id` (INV-19)
- [ ] Every row of `fixtures/link-conflict-cases.json` `progress_sync_cases` holds: import on merges the device data into the existing account's snapshot with no replacement; import off saves the device data aside and resets it before the sign-in; a same-account link replaces nothing

## Sign-out, switching and deletion

- [ ] Sign-out of a linked account revokes only that device's session; the next launch shows the welcome screen and creates no guest without a tap
- [ ] A guest has no "Sign out"; "Switch account" warns, offers link and recovery code first, and removes the device secret only after confirmation
- [ ] A different account on a device replaces the device data after saving it aside (`data.progress-sync`)
- [ ] Guest deletion works from inside the app with the device secret and the deletion challenge; it deletes the `accounts` row after every eraser, writes tombstones with reason `deleted`, and clears every device copy of the credential
- [ ] Linked deletion deletes the `users` row then the `accounts` row, after the erasers
- [ ] **(manual)** The web deletion page accepts a recovery code for a guest; the setup notes record that Google's policy page does not name guest accounts
- [ ] **(manual)** `compliance.account-deletion` accepts a `guest` proof type in the project; if it does not, the gap is in the report

## Privacy and audience

- [ ] `AUDIENCE_MODE` is set deliberately for the project and written in the setup notes
- [ ] In `mixed` mode the age screen runs before any request, has no default selection and cannot be changed in the app; under-age behaviour follows `AUDIENCE_UNDER_AGE_ACCOUNT`
- [ ] In `kids` mode and for under-age accounts no link prompt, no attestation and no advertising identifier exists
- [ ] The privacy page names the guest identifier, the abuse counters, the idle periods, in-app deletion, and that deleting the app does not delete the account
- [ ] **(manual)** Counsel confirmed the legal basis, any notice at collection (`GUEST_FIRST_RUN_NOTICE`), and the audience mode

## Screens (frontend.md)

- [ ] Every screen of `frontend.md` handles its listed states, including offline and expired
- [ ] The conflict sheet shows lists built from the holdings, a confirm button that names the loss, per-item acknowledgements for paid holdings, and "Keep my guest game" removes nothing
- [ ] Every welcome-back variant of `frontend.md` section 7 renders and none claims a reason the server cannot know
- [ ] Recovery-code display shows once, is not logged or captured, and the entry screen normalises input
- [ ] Offline first launch plays, queues events with a `local_event_id`, shows nothing as granted, and submits oldest first on connection
- [ ] Accessibility: focus order, labelled controls, text not colour for destructive actions, polite single announcements, reduce motion, scalable text, minimum target size

## Events

- [ ] Every event of `README.md` section 6 is emitted with the listed properties and the shared envelope; `guest_purged` and `guest_create_throttled` carry no `account_id`; `link_conflict` carries no id of the other account
- [ ] No event carries a secret, token, recovery code, request id, network address or device identifier

## Security

- [ ] Each threat of `security.md` T1 to T12 has its mitigation implemented and its validation rule run
- [ ] The only way to supply `account_id` to a server call is a verified credential or session
- [ ] Server secrets (bucket hashing key, device hashing key, service-account credentials) live in the secret store and are not in the repo

## Configuration

- [ ] Every key of `README.md` section 7 exists with its default and is documented in the project's setup notes
- [ ] The setup notes list the values the owner changed from the defaults and the reason

## Tests

- [ ] Unit tests pass for the pure functions listed under Build and types, reading the fixtures
- [ ] Integration tests with test doubles for the login verifiers and the participants pass for every scenario in the six `.feature` files
- [ ] At least one test kills the process between participants of an import and between the two transactions of a purge

## 3-Stack mental test

Run for stacks A (Node 20, Express, Postgres, Drizzle), B (Bun, Hono, SQLite) and C (Deno 2, Oak, Postgres, Prisma). Written answers belong in the project's report.

1. **Data model**: the logical types map to all three dialects; the partial UNIQUE indexes need SQLite 3.8 or higher and Postgres, and MySQL needs the generated-column form noted in the migration. Yes.
2. **Snippets**: SHA-256 and a CSPRNG exist on all three runtimes; `ADAPT` names the import changes. Yes.
3. **External contracts**: App Attest verification steps, Play Integrity fields and the Crockford alphabet are concrete. Yes.
4. **Sequence flows**: no flow depends on a framework feature; session transport is a bearer header. Yes.
5. **Acceptance**: every item above is checkable on all three stacks with test doubles. Yes.

## Gaps the adopter fills (not settled by any source)

- The return-time distribution of lapsed players, to confirm `GUEST_DORMANT_AFTER_DAYS` and `GUEST_PURGE_AFTER_DAYS`. Read it from the game's own cohorts.
- The cost of the proof of work on the slowest supported phone, to set `GUEST_POW_BASE_BITS`.
- Per-network limits for carriers that put many players behind one address; read the creation log before the first marketing push.
- Whether Google Play treats a silently created guest as an account for the deletion policy; this block treats it as in scope.
- The legal position on persistent identifiers for the game's audience.
