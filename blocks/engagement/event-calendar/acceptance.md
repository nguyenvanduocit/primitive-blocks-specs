# Acceptance: Event Calendar

Claude Code runs this checklist after implementation and before reporting done. Tests are generated from the six `.feature` files and the four `fixtures/*.json`; invariant ids (INV-n) refer to `README.md` section 8 and threat ids (T-n) to `security.md`. Fixture clock: `2026-10-27T12:00:00Z`; every test injects the clock through the `Clock` port and never reads the system time. Items marked **(manual)** cannot be checked from code and go into the report as "needs manual setup".

## Build and types

- [ ] The project's type check passes with zero errors
- [ ] The ledger is called only through `LedgerPort.grant`; a search of the code finds no `spend`, no balance write and no import of the ledger's storage (INV-8)
- [ ] The four pure rules (timeline and state, local window resolution, version comparison, compensation clamp) have no I/O and no clock read; they take instants as arguments
- [ ] No route handler reads a time parameter, a time header or a preview token on a player route (INV-14)

## Database

- [ ] The migration runs on a clean database and again without error (`event_definitions`, `event_rewards`, `event_participation`, `event_progress_entries`, `event_reward_claims`, `event_operations`, `event_account_merges`)
- [ ] `UNIQUE (tenant_id, merge_id)` and `UNIQUE (tenant_id, from_account_id)` exist on `event_account_merges`; inserting a duplicate of each fails
- [ ] `UNIQUE (event_id, reward_key)`, `UNIQUE (event_id, account_id)`, `UNIQUE (event_id, account_id, source_ref)`, `UNIQUE (event_id, account_id, reward_id)` and the series unique index exist; inserting a duplicate of each fails
- [ ] `CHECK (ends_at > starts_at)` and the local-window consistency check are active (insert a violating row directly and see it fail)
- [ ] Foreign keys cascade: deleting an event removes its rewards, participation, entries, claims and operations; deleting an account removes its participation, entries and claims
- [ ] On SQLite or any text-timestamp dialect, every stored instant uses one fixed-width UTC format (`YYYY-MM-DDTHH:MM:SS.sssZ`) and local wall-clock fields use `YYYY-MM-DDTHH:MM:SS`, so text comparison orders correctly
- [ ] Every query carries `tenant_id` (INV-17); a query without it is a test failure
- [ ] Discovery, settlement and the grant worker use the indexes in `README.md` section 2 (check the query plans)

## State and time

- [ ] Every row of `state_cases` in `fixtures/time-cases.json` passes, including the extension, emergency end with notice and emergency end now cases
- [ ] The ending-soon window is `min(layer window, floor(authored length / 4))`; the short QA event gives 1800 seconds
- [ ] Windows are half-open: live at `start`, ended at `effective_end`, archived at `archive_at` (INV-3)
- [ ] No scheduled job changes an event's state; a test advances the clock across every boundary with no worker running and the derived state is correct (INV-2)
- [ ] Every row of `window_cases` passes: the five zones, the nonexistent local time and the repeated local time, and the 23-hour and 25-hour days
- [ ] The stored outer bounds of a local window equal local start minus 14 hours and local end plus 12 hours
- [ ] A local window is latched at first listing and a later timezone change does not move it (INV-19)
- [ ] `meetsMinVersion` passes every row of `version_cases`
- [ ] An event id never returns from `ended` or `archived` to `live`; `extend` on an ended event is refused; the `end never restarts` outline in `event-lifecycle.feature` passes (INV-25)
- [ ] After an extension the item carries `original_ends_at` (the authored end before the first extension, unchanged by later extensions) and a never-extended event has null
- [ ] `write_boundary_cases` pass: join and progress succeed at `start` and fail with `event_not_live` before it; fail with `event_ended` at `effective_end`; a trusted late report is accepted only inside `PROGRESS_GRACE_SECONDS`; a client report never gets the grace

## Discovery and targeting

- [ ] `GET /api/events` at the fixture clock returns exactly `expected_discovery` from `fixtures/events.json` for each account in `fixtures/accounts.json`: same lists, same order, same resolved windows
- [ ] `server_now` is read once per request and has millisecond precision; `next_boundary_at` for `acc-ann` is `2026-10-27T16:00:00.000Z`
- [ ] The order is priority descending, then end ascending, then start ascending, then id
- [ ] Every event with a `series_key` is returned with `recurrence = {repeats: true, next_starts_at}` (resolved for the account; null next date when no later instance is published) and every other event with `recurrence` null; the values in `expected_recurrence` of `fixtures/events.json` match (INV-26)
- [ ] `season_ref` is returned as stored and nothing else uses it: no call to `engagement.season-pass`, no validation against it, no effect on windows or states when the event is held, released or ended (INV-24)
- [ ] `upcoming` carries no rewards or rules, respects `UPCOMING_HORIZON_SECONDS` and `UPCOMING_MAX`, and omits a series that has a live instance
- [ ] `recent` lists `ended` events the account joined and nothing else; archived events are never listed
- [ ] Unknown, draft, allow-list and out-of-audience events all answer `404 event_not_found` with identical bodies (INV-15)
- [ ] An account below `min_app_version` gets an `update_required` stub (when enabled) and `403 update_required` on the detail route; stubs carry no rewards, rules or config
- [ ] The response uses one locale resolved from `Accept-Language` with fallback to `default_locale`
- [ ] A lapsed player who returns keeps the comeback event; a new player who aged out keeps the welcome event; an account never listed does not get it (INV-7)
- [ ] A failed latch write answers `503 latch_unavailable`
- [ ] No player response contains `allow_list`, `issuance_budget`, `eligibility_snapshot`, `audience`, `tenant_id` or an operator id (A-6)

## Participation and rewards

- [ ] Every case in `progress_cases` of `fixtures/rewards-and-participation.json` ends in its expected state, response and ledger calls
- [ ] Join is idempotent; an `opt_in` event refuses progress before a join; an `auto` event joins at the first accepted progress
- [ ] One `source_ref` counts once; `amount` above `progress_max_per_call` is `422 invalid_progress`; progress never exceeds `progress_cap`; `progress` equals the sum of `applied_amount`
- [ ] A progress write that crosses a milestone inserts its claim row in the same transaction as the progress change
- [ ] The idempotency key is exactly `event-calendar:{account_id}:{event_id}:{reward_key}:{currency}`, the reason is `event-calendar.reward` and the source reference is `event:{event_id}:reward:{reward_key}`
- [ ] A manual claim, an auto grant, a sweep and a retry of the same reward send the same key; the ledger shows one effect per grant line (INV-9)
- [ ] Two simultaneous claims answer 200 with the same entry ids; a replay answers 200 with no new ledger effect
- [ ] A ledger failure leaves the claim `earned` and answers `503 grant_pending`; a ledger answer with `applied` false or no `entry_id` does not mark the claim `granted`
- [ ] Every `claim_cases` row passes, including the ledger outage that recovers with the same key
- [ ] No code path deletes, voids or reduces a claim row (INV-10)
- [ ] The `ending_soon_handoff` examples are emitted with the stated fields: `armed` when a player joins, re-armed when an instant changes, `resolved` on hold, on all milestones reached, or when nothing is left to notify

## Settlement and workers

- [ ] The `settlement_cases` pass: end-of-event claims are created once, a participant with progress 0 gets none and is marked settled, and a second run adds no row and makes no ledger call (INV-20)
- [ ] Settlement does not start before `effective_end + PROGRESS_GRACE_SECONDS` and processes each row in its own transaction in batches of `SETTLEMENT_BATCH_SIZE`
- [ ] A manual claim stays `earned` until `archive_at` and is granted by the sweep at that instant, not before
- [ ] After a simulated crash between the ledger call and the status update, the next run grants nothing twice and marks the claim `granted`
- [ ] Failed grants back off from `GRANT_RETRY_BASE_SECONDS` to `GRANT_RETRY_MAX_SECONDS`; after `GRANT_MAX_ATTEMPTS` the claim stays `earned`, the worker stops selecting it and an alert fires; the claim retry route resets it
- [ ] A merged guest account follows the `merge_cases` row: progress recomputed, a reward granted on either side stays granted, no new ledger call

## Operator actions and authoring

- [ ] Every `authoring_cases` row returns its expected error or warning code; a valid draft returns `ok` with `reach_estimate` and `max_issuance`
- [ ] `season_ref_invalid` is reported for a non-seasonal layer, a malformed value or an overlong value, and not for an unknown season id; `repeat_without_series` is a warning when a new event repeats an earlier event's type and default-locale title without a series
- [ ] A `trigger_kind` outside `milestone`, `completion`, `participation`, `rank` and `compensation` (for example `purchase`) is rejected with `reward_trigger_invalid`; no code path pays a reward because of a purchase or spend (INV-6)
- [ ] The audience schema is closed; `lifetime_spend_min`, `payer_status`, `purchase_count`, `predicted_value`, `price_tier` and `device_value_tier` are rejected (INV-6)
- [ ] A currency with no `REWARD_CAP_PER_PLAYER` entry is rejected; `table_max` above the cap is rejected; `issuance_budget` below `reach_estimate * table_max` is rejected
- [ ] A published event cannot be edited (`409 event_frozen`); only `extend`, `hold`, `release`, `end_now` and `unpublish` (scheduled, no participation) change it (INV-4)
- [ ] `extend` only moves the end later, at most `MAX_EXTENSION_SECONDS` in total, only for `absolute` windows, never on an ended event, never into an exclusive-group overlap (INV-5)
- [ ] `hold` removes the event from discovery, shows a `held` stub to participants, makes join, progress and claim answer `409 event_held`, skips settlement and the grant worker, and keeps every row; `release` restores them (INV-21)
- [ ] The `emergency_end_cases` row passes: compensation per currency equals `min(requested, table_max - already earned)`; no player's total exceeds `table_max`; players with progress 0 receive none (INV-11)
- [ ] `end_now` cannot be undone, cannot be backdated and starts its ending-soon window from `closes_at`
- [ ] Every operator action appends an `event_operations` row with operator, kind, reason and changed fields; an action without a reason is refused (INV-22)
- [ ] The calendar view reports `layer_gap`, `density_over_cap` and `end_cluster` as warnings, and no runtime path hides an event because of density (INV-23)
- [ ] Series expansion is idempotent on `(series_key, occurrence_index)` and limited by `SERIES_MAX_INSTANCES`

## Account lifecycle

- [ ] This block is registered as a participant of `auth.guest-account` for `holdings`, `mergeAccounts` and `deleteAccount` (that block's acceptance makes registration a release gate)
- [ ] `holdings(account_id)` returns `{category, label_key, paid, effect}` entries sorted by category then `label_key`, with `paid` false and `effect` `carried`, and matches every row of `holdings_cases`; it is empty for an account with no unarchived participation and no earned claim
- [ ] `mergeAccounts(from, into, merge_id)` follows the `merge_cases` rows: progress recomputed by `source_ref` union and cap, a reward granted on either side stays granted, an equal claim on the target wins, no ledger call (INV-27)
- [ ] A repeated `merge_id` returns the first stored result and changes nothing; a second merge of the same guest with another `merge_id` fails `already_merged`
- [ ] `deleteAccount(account_id)` leaves no participation, entry, claim or merge record for the account, resolves its armed hand-offs, leaves ledger entries alone and succeeds when repeated
- [ ] A dormant guest receives no new `armed` `event_ending_soon` and its pending ones are `resolved`

## Preview

- [ ] A preview token answers discovery at an instant with `server_now` equal to that instant, a `preview` object, no participation and `Cache-Control: no-store`
- [ ] Join, progress and claim refuse a preview token with `403 preview_read_only`; player routes ignore any time parameter
- [ ] A preview token expires after `PREVIEW_TOKEN_TTL_SECONDS`; `include_drafts` works only with a valid token
- [ ] A player session cannot call any `/admin` route (INV-14, A-2)

## Client

- [ ] Countdowns use `server_now` and the monotonic clock only; the `client_clock_cases` pass, including a device clock that is fast and one moved forward
- [ ] When a countdown reaches zero the card shows "Checking..." and changes state only on the next response; the refetch delay is between 0 and `BOUNDARY_JITTER_MAX_SECONDS`
- [ ] The client refetches at `next_boundary_at`, at most every `DISCOVERY_REFRESH_SECONDS`, and on foreground when a boundary passed in the background
- [ ] An event with an unknown `type`, `config_schema_version`, state, trigger or claim mode is hidden and reported with `live_event_render_skipped`; a renderer that throws drops only that event (INV-13)
- [ ] Event text renders as text; a script string in a title or rule is displayed, not run; a call-to-action with an unknown route shows no button (INV-18)
- [ ] After a restart the end time is shown as an absolute time labelled approximate until the next response
- [ ] A snapshot older than `STALE_AFTER_SECONDS` shows the notice and disables Join and Claim
- [ ] A card with `recurrence` shows "This event repeats." and the next date or "The next date is not set yet."; a card with `original_ends_at` shows the extension line; a refetch rebuilds a countdown from `ends_at` and never from the event's full length (INV-25, INV-26)
- [ ] The ending-soon state changes only a label and an announcement; amounts, thresholds and colors of the reward list do not change (INV-12)
- [ ] Every screen in `frontend.md` handles its listed states: hub, home banner and badge, detail, ending-soon, results and claim, teaser, unsupported version, paused, offline and error, preview
- [ ] The unsupported-version row and screen show no countdown and no reward data
- [ ] The timer exposes `role="timer"` without live announcements; the progress bar exposes `role="progressbar"` with values; targets are at least 24 by 24 CSS pixels (WCAG 2.2 SC 2.5.8); motion respects `prefers-reduced-motion`
- [ ] Every analytics event in `frontend.md` fires with the listed properties and none carries spend, price or balance data

## Security

- [ ] Join, progress and claim take the account from the session and ignore any account id in a body (A-1)
- [ ] The preview token and operator credentials never appear in logs; logs hold ids, codes and counts only
- [ ] Asset URLs outside `ASSET_ORIGIN_ALLOWLIST` and non-HTTPS URLs are rejected at authoring
- [ ] `config` has no field that the server or the client evaluates as code or an expression; renderers are compiled into the build (T-10)
- [ ] The project's content security policy disallows inline script in the web view (T-9)
- [ ] Deleting an account removes its participation, entries and claims and leaves ledger entries to the ledger
- [ ] No source or fixture contains a real account id, key, email address or product name

## Configuration

- [ ] The app starts with the defaults in `README.md` section 7 plus `REWARD_CAP_PER_PLAYER`, `RELEASED_APP_VERSIONS`, `ASSET_ORIGIN_ALLOWLIST` and `EVENT_TYPES` set by the owner; with those empty, authoring rejects rewards, versions and assets rather than failing silently
- [ ] Every key in section 7 is documented in the project's setup notes with its chosen value

## 3-stack mental test

The block was not run on any stack; this is the check an implementer repeats before reporting done.

| Question (`docs/SPEC_GUIDELINES.md` section 7) | A: Node 20, Express, Postgres, Drizzle | B: Bun, Hono, SQLite, raw SQL | C: Deno, Oak, Postgres, Prisma |
|---|---|---|---|
| 1. Data model maps from logical types | Native types, `jsonb`, `text[]` | `TEXT` JSON, JSON array for `allow_list`, fixed-width ISO text for instants (see Database) | Native types; Prisma maps `jsonb` and arrays |
| 2. Snippets have an equivalent | Pure TypeScript; offset lookup through `Intl` | Same; `Intl` is available | Same; `Intl` is available |
| 3. External contract is concrete | RFC 5545 gap and overlap rules, IANA zone names, ISO 3166 codes, `Accept-Language`, ledger key format | Same | Same |
| 4. Sequence flow does not depend on one framework | Row lock on the participation row | One write transaction serializes writers; the flow only needs "no two writes interleave on a participation row" | Row lock through the ORM or raw query |
| 5. Acceptance is verifiable | Injected `Clock`, fake `LedgerPort`, fixtures | Same | Same |

## Needs manual setup

- [ ] **(manual)** Operator authentication and the four roles are wired in the host's admin system
- [ ] **(manual)** The ledger catalog lists every currency and item code used in a reward table, and the ledger keeps idempotency keys at least as long as the longest claim grace plus the retry window
- [ ] **(manual)** `RELEASED_APP_VERSIONS` is updated by the release process after each store release
- [ ] **(manual)** The asset origin is provisioned and allow-listed; assets are immutable per URL
- [ ] **(manual)** If the game promotes events on the App Store, the store entry's dates and deep link match the calendar (Apple Guideline 2.3.13)
- [ ] **(manual)** The rank source, if any, can freeze final ranks at the effective end
- [ ] **(manual)** Alerts exist for grant backlog age, settlement lag, claims at `GRANT_MAX_ATTEMPTS`, hold age and discovery error rate

## Tests

- [ ] Unit tests pass for the four pure rules against `fixtures/time-cases.json`
- [ ] Integration tests with a fake ledger and an injected clock pass for every scenario in the six `.feature` files
- [ ] At least one test advances the clock across a start, an ending-soon instant, an end and an archive instant with no worker running
- [ ] At least one test runs two claims in parallel and one test kills the process between the ledger call and the status update
- [ ] The report lists every manual step left and every `Assumption:` made
