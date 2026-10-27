# Acceptance - Push Notifications and Re-engagement

Verification checklist Claude Code runs AFTER implementation, BEFORE reporting done. Every item must pass. Items tagged **[client]** apply to the app, **[server]** to the Push API, dispatcher and tables. Items marked **(manual, device)** or **(manual, console)** cannot be checked from code and go into the report as "needs manual verification". Tests are generated from the six `.feature` files and the four JSON fixtures; there is no shipped `tests/` folder, so create the test files in the project's own test framework.

## Build & Types

- [ ] Type check passes with zero errors
- [ ] No `any` types except with a justification comment
- [ ] `pushCore` (client: `nextPrimingAction`, `planLocal`, `quietUntil`, `resolveRoute`; server: `decide`, `ladderDue`, `selectComebackStep`, `renderTemplate`, `classifyApns`, `classifyFcm`) imports no UI framework, storage, network or clock
- [ ] Platform plugins are imported only inside the `PushPlatform` port file

## Database [server]

- [ ] The six migrations run on a clean database and run twice without error
- [ ] UNIQUE constraints exist: `push_profiles (tenant_id, account_id)`, `push_category_prefs (profile_id, category)`, `device_tokens (provider, token)`, `device_tokens (profile_id, installation_id)`, `notification_intents (tenant_id, dedupe_key)`, `notification_deliveries (intent_id, device_token_id)`, `comeback_grants (profile_id, anchor_at)` and `comeback_grants (idempotency_key)`
- [ ] Deleting a `push_profiles` row removes every dependent row (INV-22)
- [ ] `updated_at` is set by the server on every write and cannot be supplied by the client
- [ ] The quiet-hours format and the `quiet_start <> quiet_end` rule are enforced (database check or application validation)

## Permission and priming [client]

- [ ] Every scenario of `permission-priming.feature` passes (INV-3)
- [ ] No code path other than the priming sheet's primary button and the settings toggle requests the system dialog; `rg` finds no other call to `request(` in the app
- [ ] The sheet is absent before the first win and at first launch; the fallback trigger is the third session
- [ ] After an iOS refusal the system dialog is never requested again; after the second Android refusal likewise
- [ ] The two promotional switches are unchecked by default and a switch-on sends `consent_text_version`
- [ ] The sheet and the welcome-back sheet promise no reward for enabling notifications (P6)
- [ ] The inline denied hint appears at most `DENIED_HINT_MAX` times and never opens system settings by itself
- [ ] Returning from system settings with a changed permission uploads the token or cancels the local plan
- [ ] Android channels `<category>.v1` exist after the first start; a changed default ships under a new id

## Tokens [server]

- [ ] Every scenario of `tokens-and-provider.feature` passes (INV-2, INV-4, INV-5)
- [ ] An upload for a profile that is not eligible answers 403 and stores nothing
- [ ] A `(provider, token)` pair is never active under two profiles
- [ ] No endpoint, log line or analytics event contains a token, JWT or access token (`rg` over handlers and loggers)
- [ ] The APNs host follows the row's `apns_environment`; the FCM field follows `target_kind` (`fid` or `token`)

## Provider contracts [server]

- [ ] Every case of `fixtures/provider-responses.json` (`apns`, `fcm`, `breaker_cases`) maps to the listed delivery status, token action and retry rule
- [ ] APNs requests carry `apns-push-type: alert`, `apns-topic`, `apns-id` (canonical UUID), `apns-priority` 10 or 5 by category, `apns-expiration` equal to the intent's `expires_at` in UNIX seconds, `apns-collapse-id` of at most 64 bytes, and a body of at most 4096 bytes (P13)
- [ ] The provider JWT is ES256 with `kid`, `iss`, `iat`, refreshed no more than once per 20 minutes and no less than once per 60 (P14)
- [ ] FCM requests use `message.fid` or `message.token`, string-only `data` with no reserved key, `android.ttl` at most 2,419,200 seconds, `android.notification.channel_id`, and the OAuth scope `https://www.googleapis.com/auth/firebase.messaging` (P19)
- [ ] An FCM 400 with an `FcmError` detail deactivates the token; a 400 with a `BadRequest` detail never does (P21)
- [ ] An APNs 410 deactivates the token only when `last_registered_at` is at or before the body `timestamp`
- [ ] Non-retryable APNs reasons are never retried; 5xx waits at least `APNS_5XX_RETRY_SECONDS`; FCM 429 waits `Retry-After` or 60 seconds
- [ ] A retry never sends after the intent's `expires_at`
- [ ] The breaker pauses a lane and reverts bulk deactivations (INV-5)

## Delivery lanes [client + server]

- [ ] Every scenario of `delivery-lanes.feature` passes (INV-6, INV-7)
- [ ] `EVENT_ROUTES` assigns exactly one lane per event; the server drops local-lane events with `lane_mismatch`
- [ ] A local notification has the key `{category}:{subject_key}`; re-arming replaces, `resolved` cancels
- [ ] The device holds at most `LOCAL_MAX_PENDING` local notifications and checks the permission before every schedule
- [ ] The delay is computed from `fire_at` and the server offset, not from the device clock alone (INV-1)
- [ ] Session start cancels and rebuilds the local plan; logout, switch changes, permission loss, an age change and a timezone change cancel it
- [ ] No exact-alarm permission is declared; local copy states no clock time (P11)
- [ ] A foreground notification shows no system banner (INV-9)

## Ladder and comeback reward [server]

- [ ] Every scenario of `lapsed-ladder.feature` passes (INV-14, INV-15, INV-16)
- [ ] Each `reward_selection_cases` row yields the listed step; lapse is counted in local calendar days (`lapse_cases`)
- [ ] The reward is granted through the ledger `grant` with `reason = push-reengagement.comeback-reward` and the key `push-reengagement:{account_id}:{anchor_epoch_seconds}:{step_id}`; a replay credits nothing
- [ ] The grant exists for a profile with notifications off, with no token, and in the holdout
- [ ] No code path grants on a tap, an opened receipt or a push send
- [ ] A step that names a reward is suppressed when the return grant would fail (`reward_unavailable`)
- [ ] The ladder ends at the final step, at `max_lapse_days`, at `after_unopened_sends`, and for ineligible profiles; overdue steps are not replayed as a burst
- [ ] Session start replaces the pointer as one unit; replaying a `session_id` changes nothing

## Restraint [server]

- [ ] Every scenario of `suppression-rules.feature` passes (INV-8 to INV-13)
- [ ] All 23 `decision_cases` return the listed action, reason and `due_at`
- [ ] All 9 `local_time_cases` pass, including the New York and Berlin daylight-time changes
- [ ] Caps count both lanes and all categories; a capped candidate is dropped; contention resolves by category priority, then `due_at`
- [ ] The holdout rule runs last: a held-out profile that is capped is `cap_day`, not `held_out`
- [ ] The `subscription` service notice (INV-25): skips the marketing caps and is not counted in them (`D17`), has its own cap of `CAP_SERVICE_PER_LOCAL_DAY` (`D22`), honours the master switch (`D18`) and quiet hours (`D19`), is never held out (`D20`, and `HOLDOUT_CATEGORIES` validation rejects it), defaults off for a profile that is not an adult (`D21`), never bypasses the age rule (`D23`), and never touches the ladder pointer or `ladder_unopened_sends`
- [ ] Promotional categories send only with a stored `consent_text_version`; the PATCH without one is refused
- [ ] `set_age_status` to a non-eligible value deactivates tokens, cancels pending intents and clears the ladder pointer; `unknown` follows `UNKNOWN_AGE_POLICY` (default `block`)

## Attribution [server]

- [ ] Every scenario of `attribution-and-routing.feature` passes (INV-19, INV-21)
- [ ] `delivered` is set only from a receipt or provider signal; `sent` is never promoted to `delivered`
- [ ] `opened_at`, `delivered_at`, `returned_at` use the server clock; a foreign `send_id` is ignored with a 204
- [ ] The return window is 24 hours, 72 for `comeback`; `returned_at` is stamped on held-out intents from `due_at`
- [ ] The holdout comparison reads `returned_at` on both groups over the same window length

## Copy and templates

- [ ] Every template in `fixtures/template-catalog.json` passes the lint; every `copy_lint_cases` row gives the listed violations
- [ ] `render_cases` give the listed outcomes; a missing variable suppresses the intent with `template_error`
- [ ] Hand-off events: `config-defaults.json` `event_routes` and the "Hand-off events consumed" table of `README.md` section 6 name, for each of the six events, the emitter's exact `subject_key` shape, `params` and extra fields (`handoff_param_cases` H1 to H6 render to the listed title and body, lane, key and route); every template names only declared params or derived variables, an undeclared param is ignored, and an absent optional param leaves copy that reads correctly (`render_cases` R2, R4, R5, R8, R9)
- [ ] Re-armed events are ordered by `revision` (`queue_item_ready`) or `params.meter_revision` (`energy_full`): lower ignored, equal unchanged, higher replaces (`revision_cases` V1 to V5)
- [ ] Locale resolution follows exact tag, language subtag, default (`locale_resolution_cases`)
- [ ] A template of a service category passes the upsell lint (`COPY_UPSELL_PATTERNS`); the trial notice states the renewal date, formats the price from `price_milliunits` and `currency_code` in the profile locale, says the exact amount is on the store screen, and omits the price sentence when the price is unknown (`render_cases` R6 to R9)
- [ ] No template names a balance, a token, another player or a link (INV-24)

## Deep links and the tap handler [client]

- [ ] `resolveRoute` returns `home` for an unknown id, a parameter not listed for the route, a value failing the pattern and malformed `rp`, and never throws (INV-18)
- [ ] Cold start waits until the app can navigate; warm start routes at once; a duplicate tap is handled once
- [ ] A tap on an ended event or a claimed objective lands on the parent list with the notice and fires `push_route_failed`

## Screens [client]

- [ ] Each screen handles the states listed for it in `frontend.md` (priming sheet, denied banner and hint, settings screen, welcome-back sheet)
- [ ] Every switch and picker has an accessible name and state; focus moves and returns as specified; status never relies on color alone
- [ ] Every event in `README.md` section 6 fires with the listed properties and the shared envelope

## Security

- [ ] The items of `security.md` threats 1 to 14 each have a passing test or a manual note
- [ ] `rg` over the repository and the build output finds no APNs key material, key id, team id or service-account file
- [ ] The five internal operations are not reachable from any public route

## Configuration

- [ ] Every key of `README.md` section 7 exists as named configuration with the default of `fixtures/config-defaults.json`
- [ ] `TOKEN_STALE_DAYS` is at least `LADDER.stop.max_lapse_days`
- [ ] The app starts and works with no provider credentials set (the dispatcher idles; local notifications still run)

## 3-stack mental test

A mental test only; no stack has run this block.

| Question (`docs/SPEC_GUIDELINES.md` section 7) | Stack A (Node 20, Express, Postgres, Drizzle) | Stack B (Bun, Hono, SQLite) | Stack C (Deno, Oak, Postgres, Prisma) |
|---|---|---|---|
| Data model maps to the dialect | `json` to `jsonb`; partial indexes allowed | `json` to `TEXT`; `timestamp` to ISO text; partial indexes allowed; CHECK with regex needs app validation | same as A |
| Snippets have an equivalent | Fetch with HTTP/2 through `undici` or `node:http2` | Bun's fetch; HTTP/2 to APNs needs a client that speaks it (verify) | `Deno.createHttpClient` with HTTP/2 or an npm client |
| External contracts are concrete enough | Hosts, headers, status and reason strings, FCM fields and error details are named | same | same |
| Sequence flows do not depend on one framework | The dispatcher is a periodic job; any scheduler fits | same; claim rows by an atomic status update because SQLite has no `SKIP LOCKED` | same as A |
| Acceptance is verifiable on every stack | Features plus fixtures run with `vitest` | `bun test` | `deno test` |

## Manual (device and console)

- [ ] **(manual, device)** On an iOS device: the sheet, the system dialog, a denial, the denied banner, the return from system settings, one local notification, one remote notification with a deep link from a closed app
- [ ] **(manual, device)** On an Android 13+ device: the same list plus the channel settings link and a blocked channel
- [ ] **(manual, device)** On an Android 12 or lower device: no dialog, notifications work
- [ ] **(manual, console)** APNs: key created, topic enabled for the app id, production and sandbox tested; FCM: service account with the messaging permission only, iOS credentials uploaded if iOS goes through FCM
- [ ] **(manual, console)** Store listing and review notes describe the notification categories and the opt-out (P5)
- [ ] The report lists every manual step left and every `Assumption:` made
