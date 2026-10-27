# Backend Patterns - Push Notifications and Re-engagement

The server decides, sends and measures. It is split on the **pure vs I/O boundary**:

| Part | Responsibility | I/O? |
|------|----------------|------|
| `pushCore` | `decide`, `ladderDue`, `quietUntil`, `selectComebackStep`, `renderTemplate`, `classifyApns`, `classifyFcm`, cap counting over a list of rows | None. No clock besides the `now` argument, no storage, no network. Runs in tests with no mocks. |
| API handlers | Token, state, preferences, session and receipt endpoints; read the verified session, call `pushCore`, write rows | HTTP, SQL |
| Ingest | Hand-off events, age status, merge, erase | event bus, SQL |
| Dispatcher | A periodic tick: claim due work, call `decide`, fan out to devices, call the providers, apply responses | SQL, HTTPS to APNs and FCM, the ledger |

Framework, ORM, queue and scheduler are the adopter's choice. External contracts (APNs, FCM, the ledger) are concrete; facts are cited by row id (P1 to P26) from `README.md` section 3.

## API Endpoints

All endpoints require the auth block's middleware: it attaches `{ tenantId, accountId }` from the verified session. `accountId` is the only identity the handlers use; no endpoint accepts an account id in its body or query.

| Method | Path | Purpose |
|--------|------|---------|
| `PUT` | `/api/push/tokens` | Register, rotate or refresh a device token; report permission |
| `DELETE` | `/api/push/tokens/{installation_id}` | Deactivate this install's token (logout) |
| `GET` | `/api/push/state` | Everything the client needs to render settings and run the local lane |
| `PATCH` | `/api/push/preferences` | Master switch, quiet hours, category switches |
| `POST` | `/api/push/session` | Session start: return detection, ladder reset, comeback reward, local-fire reports |
| `POST` | `/api/push/receipts` | Opened and delivered receipts, up to 20 per call |

### `PUT /api/push/tokens`

```json
{ "installation_id": "inst-ann-1", "platform": "ios", "provider": "apns", "target_kind": "apns_token",
  "apns_environment": "production", "token": "<provider value>", "permission_state": "authorized",
  "os_blocked_categories": [], "app_version": "1.4.0" }
```

| Status | Body | When |
|--------|------|------|
| 200 | `{ "token_status": "active" }` or `{ "token_status": "inactive", "reason": "permission_denied" }` | Stored or deactivated |
| 400 | `{ "error": "invalid_request" }` | Missing field, `token` longer than `MAX_TOKEN_CHARS`, `permission_state` other than the four values |
| 401 | `{ "error": "unauthenticated" }` | No or invalid session |
| 403 | `{ "error": "age_not_eligible" }` | Decision rule 1 would suppress every notification for this profile (`INV-13`); nothing is stored |
| 422 | `{ "error": "unsupported_combination" }` | `provider = apns` without `target_kind = apns_token` and an `apns_environment`; `provider = fcm` with `apns_token`; `platform` and `provider` pair not allowed |

Rules:

1. Create the profile on first contact (defaults of section 7, `holdout` from the stable hash).
2. `permission_state = denied`: the call carries no `token`. Deactivate the install's row with reason `permission_denied`; answer 200.
3. `authorized` or `provisional`: `token` is required. Upsert by `(profile_id, installation_id)`; set `last_registered_at` to the server clock, `status = active`, clear `inactive_reason`.
4. Before the upsert, deactivate (reason `superseded`) every other active row with the same `(provider, token)` or the same `installation_id` under a different profile (INV-4).
5. Never log `token`; never return it.

### `DELETE /api/push/tokens/{installation_id}`

`204` whether or not a row existed. Deactivates the row (reason `logout`) and marks its `queued` deliveries `failed` with `provider_status = token_removed`. The client calls it before it drops its session; if it cannot (offline), rule 4 above removes the stale row when the next account registers on the same install.

### `GET /api/push/state`

```json
{ "server_now": "2026-10-21T12:00:00Z", "eligible": true, "ineligible_reason": null,
  "global_enabled": true, "timezone": "Asia/Ho_Chi_Minh",
  "quiet_hours": { "enabled": true, "start": "22:00", "end": "08:00" },
  "categories": [ { "category": "events", "enabled": false, "promotional": true, "service_notice": false, "channel_id": "events.v1" },
                  { "category": "subscription", "enabled": true, "promotional": false, "service_notice": true, "channel_id": "subscription.v1" } ],
  "caps": { "per_local_day": 2, "per_7_local_days": 8, "used_today": 1, "used_7_days": 3 },
  "local": { "allowed": true, "max_pending": 20 },
  "lanes": { "energy_full": "local", "event_ending_soon": "remote" },
  "consent_text_version": "v1" }
```

`eligible = false` with `ineligible_reason = age_not_eligible` tells the device to cancel its whole local plan, hide the priming sheet and show no notification setting. `local.allowed` is false for the same reason and when the global switch is off. `used_*` count rows with `status = dispatched` by `sent_day_key` (section "Caps"). `lanes` is the `EVENT_ROUTES` lane column so the client scheduler never guesses (INV-6).

### `PATCH /api/push/preferences`

```json
{ "global_enabled": true,
  "quiet_hours": { "enabled": true, "start": "22:00", "end": "08:00" },
  "categories": { "events": { "enabled": true, "consent_text_version": "v1" }, "timers": { "enabled": false } } }
```

| Status | Body | When |
|--------|------|------|
| 200 | the same shape as `GET /api/push/state` | Applied |
| 403 | `{ "error": "age_not_eligible" }` | Profile is not eligible (a minor cannot switch anything on) |
| 422 | `{ "error": "consent_required" }` | A promotional category is switched on without a `consent_text_version` from `CONSENT_TEXT_VERSIONS` (P5) |
| 422 | `{ "error": "invalid_quiet_hours" }` | `start` or `end` is not `HH:MM` 24-hour, or they are equal |
| 422 | `{ "error": "unknown_category" }` | Category not in the catalog |

Side effects, in the same transaction: switching a category off cancels its `pending` intents (`category_off`); switching `comeback` on or off recomputes the ladder pointer; the master switch off cancels all pending intents (`global_off`). Quiet hours take effect on the next evaluation of each pending intent.

### `POST /api/push/session`

```json
{ "session_id": "s-7f3a", "timezone": "Asia/Ho_Chi_Minh", "locale": "en-GB", "app_version": "1.4.0",
  "local_fired": [ { "category": "timers", "local_key": "timers:energy:main:1792584000", "fire_at": "2026-10-20T11:00:00Z" } ] }
```

Response `200`: `{ "server_now", "day_key", "lapse_days", "comeback": null | { "status": "granted" | "pending", "step_id", "currency", "amount" } }`. `timezone` must be an IANA name; an unknown name is ignored and the stored value kept. `locale` is stored as sent when it is a well-formed BCP 47 tag.

### `POST /api/push/receipts`

```json
{ "receipts": [ { "kind": "opened", "send_id": "7c1e0d4a-...", "at": "2026-10-21T12:03:10Z" },
                { "kind": "opened", "local_key": "timers:energy:main:1792584000", "fire_at": "2026-10-21T11:00:00Z", "at": "2026-10-21T12:03:10Z" },
                { "kind": "delivered", "send_id": "7c1e0d4a-...", "at": "2026-10-21T12:00:04Z" } ] }
```

`204` always, including when a receipt is ignored, so the endpoint reveals nothing about other accounts' ids. A `send_id` that does not belong to the session's profile is ignored and counted (`push_receipt_rejected` in logs, not an analytics event). The server stamps `opened_at` and `delivered_at` with its own clock; the client's `at` is analytics-only (INV-1). Replays change nothing (INV-21).

## Internal operations

| Operation | Called by | Effect |
|-----------|-----------|--------|
| `ingest_handoff(event)` | event bus consumer | section "Hand-off ingest" |
| `set_age_status(account_id, status)` | the adopter's age gate | upsert the profile; on a change to a non-eligible status deactivate every token (`age_blocked`), cancel pending intents (`age_ineligible`), clear the ladder pointer; the device learns it from `GET /api/push/state` |
| `merge_accounts(from, to)` | guest-to-account merge | move the `from` tokens to the `to` profile (create it if absent; the conflict rules of `PUT /api/push/tokens` apply), cancel the `from` profile's pending intents, keep the `to` profile's switches, delete the `from` profile (INV-22) |
| `erase_account(account_id)` | account deletion | delete the profile row; everything else cascades |
| `tick()` | scheduler | section "Dispatcher" |

## Session start (the return path)

`POST /api/push/session` runs these steps in one transaction. Replaying the same `session_id` returns the stored result and changes nothing (INV-21): the profile keeps `last_session_id` and `previous_session_at` for this.

1. Load or create the profile. If `last_session_id = session_id`: skip to step 9 using `previous_session_at`.
2. `previous = last_session_at`. Set `previous_session_at = previous`, `last_session_at = server now`, `last_session_id = session_id`, `timezone`, `locale`.
3. `lapse_days = day_key(now, tz) - day_key(previous, tz)` in **local calendar days** (a UTC date difference is wrong near midnight; fixture `lapse_cases` L01). Null when `previous` is null.
4. Stamp returns: every intent of the profile with `returned_at` null, `status` in (`dispatched`, `held_out`), and `now` within the return window of its `dispatched_at` (held out: `due_at`) gets `returned_at = now` (INV-19). Window: the category's `return_window_hours`, default `RETURN_WINDOW_HOURS`.
5. Record `local_fired`: up to `LOCAL_REPORT_MAX` entries; for each, upsert an intent with `lane = local`, `source = local_report`, `status = dispatched`, `dispatched_at = fire_at`, `sent_day_key` from `fire_at` in the profile timezone, `dedupe_key = local:{account_id}:{local_key}:{fire_at epoch seconds}`. The category comes from the `local_key` prefix. Entries with an unknown category or a `fire_at` in the future are ignored.
6. Cancel pending intents whose event has `cancel_on_session` (`returned`).
7. Replace the ladder pointer as one unit (section "Ladder"); a profile that is not eligible, has `global_enabled = false`, has `comeback` off or has no active token gets a null pointer.
8. Comeback reward: if the profile is eligible and `lapse_days` is not null, `step = selectComebackStep(lapse_days, steps, cooldownClear)` where `cooldownClear` is `last_comeback_granted_at` null or at least `comeback_cooldown_days` local days ago. When a step is selected, insert `comeback_grants` (`status = pending`, key `push-reengagement:{account_id}:{anchor epoch seconds}:{step_id}`, unique on `(profile_id, anchor_at)`), commit, then call the ledger (below).
9. Answer with `lapse_days`, `day_key` and the grant (`granted` once the ledger returned `applied`, `pending` while it is retried).

## Ladder

The ladder is configuration (`LADDER.steps`). The server does not materialize one row per step. It keeps a **pointer** on the profile (`ladder_anchor_at`, `ladder_next_step`, `ladder_next_due_at`) and the dispatcher creates an intent row only when it evaluates a step.

`ladderDue(anchor, step, tz, cfg)`:

1. `local_date = day_key(anchor, tz) + step.after_days`.
2. Convert `local_date` at `LADDER.send_at_local` to a UTC instant with the IANA rules of `tz`. A wall time that does not exist (spring-forward gap) becomes the first valid instant after the gap; an ambiguous one (fall-back) becomes the earlier instant.
3. Add the account's offset: `3 + (stable_hash(account_id) mod LADDER.spread_minutes)` minutes. The offset keeps the send outside the two-minute windows around :00, :15, :30 and :45 that FCM asks fan-outs to avoid (P23) and spreads a timezone's players over `spread_minutes`.
4. `expires_at = due_at + ttl_seconds` of the `comeback` category.

Session start sets the pointer to the first step with `anchor = now`. The dispatcher, when `ladder_next_due_at <= now` (index scan):

1. If `ladder_next_step` is not the highest step whose due time has passed (the dispatcher was down), skip to that step; earlier steps are not replayed as a burst.
2. Insert the intent (`source = ladder`, `dedupe_key = ladder:{account_id}:{anchor epoch seconds}:{step_id}`, `status = pending`); a unique-key conflict means another worker has it, so stop.
3. Run `decide` (below). Apply the outcome. For `send`, increment `ladder_unopened_sends`.
4. Advance the pointer to the next step, or null after the step with `final = true`, when `after_days` of the next step exceeds `stop.max_lapse_days`, or when the decision was `ladder_stopped`.

An opened receipt (any category) resets `ladder_unopened_sends` to 0, and so does the player switching `comeback` back on.

## Comeback reward

`selectComebackStep` is a pure function of `(lapse_days, steps, cooldownClear)`: the step with a reward and the largest `after_days` such that `after_days <= lapse_days <= claim_until_day`. Lower steps never stack (INV-15). `fixtures/profiles.json` `reward_selection_cases` is its table.

<!-- PATTERN: select-comeback-step -->
<!-- PURPOSE: pick the one comeback reward step a returning player is entitled to, from lapse length alone -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: Step comes from LADDER.steps in config; lapseDays is the local-calendar-day difference computed by the caller; cooldownClear is computed from last_comeback_granted_at and comeback_cooldown_days in the player's timezone -->
```typescript
type Step = { id: string; after_days: number; reward: { currency: string; amount: number; claim_until_day: number } | null };

export function selectComebackStep(lapseDays: number | null, steps: Step[], cooldownClear: boolean): Step | null {
  if (lapseDays === null || lapseDays < 1 || !cooldownClear) return null;
  const hits = steps.filter(
    (s) => s.reward !== null && s.after_days <= lapseDays && lapseDays <= s.reward.claim_until_day,
  );
  return hits.reduce<Step | null>((best, s) => (best === null || s.after_days > best.after_days ? s : best), null);
}
```

Granting: call the ledger operation `grant(account_id, currency, amount, reason, source_ref, idempotency_key)` with `reason = push-reengagement.comeback-reward`, `source_ref = comeback_grants.id` and the key stored on the row. Result `{applied, balance, entry_id}`: set `status = applied`, `ledger_entry_id`, `last_comeback_granted_at`. A failed or timed-out call leaves `pending`; the dispatcher retries pending grants each tick with the same key, and a replay returns the first result (ledger contract), so a retry never double-credits. The grant never depends on a push having been sent, delivered or held out, and never on a tap (INV-15; P6).

A step with a reward may be **sent** only when the grant would apply on return at that moment (decision rule 7): `cooldownClear` and `lapse_days_at_due <= claim_until_day`. Copy that names the reward is therefore always true (INV-16).

## Hand-off ingest

`ingest_handoff(event)` (events described in `README.md` section 6):

1. Look up `EVENT_ROUTES[event.event_name]`; an unknown name is dropped and counted.
2. No profile for `account_id`: drop (an account that never opened a session has no device).
3. `lane = local`: drop with reason `lane_mismatch` (the client scheduler handles it; INV-6).
4. `fire_at = event.fire_at ?? event.ends_at ?? event.server_ts`; `expires_at = event.expires_at ?? fire_at + ttl_seconds`. Keep only the `params` the route entry declares (`event_routes[].params`); an undeclared param is dropped and counted. `revision` is `event.revision` for `queue_item_ready` and `params.meter_revision` for `energy_full`; other events have none.
5. `dedupe_key = handoff:{account_id}:{category}:{subject_key}`.
6. `state = armed`: if no row exists and the profile holds fewer than `MAX_PENDING_PER_PROFILE` pending intents, insert `pending` with `due_at = fire_at`, `template_id`, `params`, and a validated route (a profile at the limit drops the event and counts it); if a `pending` row exists, compare revisions (the stored one is kept in the row's `params` under the reserved key `_revision`): a lower incoming revision is ignored and counted, an equal one is a replay and changes nothing, a higher one (or any event without a revision field) updates `due_at`, `expires_at`, `params` and `_revision` (`superseded`); if a terminal row exists, do nothing (the occurrence already ran).
7. `state = resolved`: a `pending` row becomes `cancelled` (`resolved`); anything else is left alone.

Hand-off events of a service category (`subscription_trial_ending`) are ingested like any other and differ only in the decision pipeline: no ladder, no holdout, the service cap, the age-based default. The renderer derives `renewal_date` and `price_text` from `params` with the platform's locale-aware formatters (next section) and never asks the store.

Route building: `route` comes from `EVENT_ROUTES`; each parameter the route accepts is copied from `params` and must match `route_param_pattern`; a parameter that fails the pattern is dropped, and a route missing a required parameter falls back to `home` (INV-18).

## Decision pipeline

`decide(candidate, profile, now, cfg)` implements the ordered list of `README.md` section 3. The list order is the array order below; reordering is a spec change (INV-8).

<!-- PATTERN: ordered-decision-rules -->
<!-- PURPOSE: make the rule order explicit and testable; the first rule that answers wins, holdout answers last -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: each rule is a pure function over a read-only ProfileView built by the handler (profile, prefs, active tokens, sent_day_keys); add or drop rules only through the spec; time conversions use the project's IANA-aware date library -->
```typescript
type Decision =
  | { action: "send" } | { action: "hold_out" }
  | { action: "defer"; dueAt: Date } | { action: "suppress"; reason: string };
type Rule = (c: Candidate, p: ProfileView, now: Date, cfg: Config) => Decision | null;

const RULES: Rule[] = [
  ageRule,       // age_ineligible
  expiryRule,    // expired
  globalRule,    // global_off
  categoryRule,  // category_off (includes missing consent for promotional categories and the age-based default of subscription)
  quietRule,     // defer(next window end) or quiet_expired
  deviceRule,    // no_device, os_blocked
  ladderRule,    // reward_unavailable, ladder_stopped (ladder candidates only)
  capRule,       // cap_day, cap_week (marketing); cap_service (service notices)
  holdoutRule,   // hold_out
];

export function decide(c: Candidate, p: ProfileView, now: Date, cfg: Config): Decision {
  for (const rule of RULES) {
    const d = rule(c, p, now, cfg);
    if (d !== null) return d;
  }
  return { action: "send" };
}
```

### Quiet hours

`quietUntil(now, window, tz)` returns null outside the window, else the instant the window ends. The window is `[start, end)` in the profile's timezone, evaluated at the instant with the IANA rules (INV-11). At exactly `end` the player is outside the window; at exactly `start` inside (`local_time_cases` T02, T03).

<!-- PATTERN: quiet-window-end -->
<!-- PURPOSE: decide whether a local wall-clock window contains an instant and, if so, when it ends -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: toLocal, addDays and fromLocal are the project's IANA-aware helpers (Temporal, Luxon, date-fns-tz, java.time); fromLocal must map a non-existent wall time to the first valid instant after the gap and an ambiguous one to the earlier instant -->
```typescript
const mins = (hhmm: string) => Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3));

export function quietUntil(now: Date, w: { start: string; end: string }, tz: string): Date | null {
  const { minutesOfDay, date } = toLocal(now, tz);
  const s = mins(w.start);
  const e = mins(w.end);
  const wraps = s > e;
  const inside = wraps ? minutesOfDay >= s || minutesOfDay < e : minutesOfDay >= s && minutesOfDay < e;
  if (!inside) return null;
  const endsToday = wraps ? minutesOfDay < e : true;
  return fromLocal(endsToday ? date : addDays(date, 1), w.end, tz);
}
```

A deferral sets `due_at` to the returned instant and leaves the intent `pending`; the intent is evaluated again then, with every rule. If that instant is at or after `expires_at`, the outcome is `suppress(quiet_expired)`.

### Category defaults

`defaultEnabled(category, age_status)` answers when no `push_category_prefs` row exists: service categories `true`, promotional categories `false`, and `subscription` `true` only when `age_status = adult` (INV-25). `GET /api/push/state` returns the resolved value in `enabled`. A row, once written, wins.

### Caps

- `sent_day_key` of a dispatched intent is `day_key(dispatched_at, tz)` at dispatch time and is stored, so a later timezone change does not move old sends.
- Today count: rows of the profile with `status = dispatched` and `sent_day_key = today`. Week count: `sent_day_key` within the seven local dates ending today. Both lanes and all categories count (INV-10).
- When several candidates of one profile are decided in the same tick, order them by category priority (1 first), then `due_at`; each `send` increments the count the next one sees.
- A capped candidate is suppressed and never re-queued: no catch-up burst the next morning.
- A category with `service_notice = true` (`subscription`) is excluded from the two counts above. Its own count is the rows of service categories with `status = dispatched` and `sent_day_key = today`, and it is limited to `CAP_SERVICE_PER_LOCAL_DAY`: `suppress(cap_service)`. A service notice never appears in the marketing counts, so it cannot consume the budget of a reminder (INV-25).

### Device selection

Eligible devices are active tokens with `permission_state` in (`authorized`, `provisional`), `last_registered_at` within `TOKEN_STALE_DAYS`, and the category absent from `os_blocked_categories`. Rule 6 suppresses with `no_device` when no active token passes the first two tests and with `os_blocked` when tokens pass them but every one blocks the category. A send goes to at most `MAX_DEVICES_PER_SEND` devices, most recently registered first, and counts once against the caps.

## Dispatcher

`tick()` every `DISPATCH_TICK_SECONDS`:

1. Claim up to `DISPATCH_BATCH_SIZE` rows by an atomic transition, so two workers never take the same row: pending intents with `due_at <= now`, ladder pointers with `ladder_next_due_at <= now`, queued deliveries with `next_attempt_at <= now`, pending comeback grants.
2. Skip a provider lane while its breaker is open (below).
3. For each intent: build the `ProfileView`, render the template (below), run `decide`.
   - `send`: set `status = dispatched`, `dispatched_at = now`, `sent_day_key`; insert one `queued` delivery per selected device with a new unique `id` (the `send_id`).
   - `defer(t)`: set `due_at = t`.
   - `suppress(r)`: `status = suppressed`, `suppress_reason = r`. `hold_out`: `status = held_out`.
4. For each queued delivery: build the provider request, send it, classify the response, apply it in one transaction (delivery status, token action, retry schedule).
5. Emit the server analytics events.

### APNs request

| Item | Value | Source |
|------|-------|--------|
| Host | `api.push.apple.com` for `apns_environment = production`, `api.sandbox.push.apple.com` for `sandbox`; HTTP/2, TLS 1.2+, port 443 (2197 allowed) | P13 |
| Request | `POST /3/device/<token>` | P13 |
| `authorization` | `bearer <JWT>`: ES256, `kid` the 10-character key id, `iss` the team id, `iat` now; reuse one JWT per connection pool and refresh every `APNS_JWT_REFRESH_MINUTES` (45; allowed range 20 to 60) | P14 |
| `apns-push-type` | `alert` | P13 |
| `apns-topic` | `APNS_TOPIC` (bundle id) | P13 |
| `apns-id` | the delivery id (canonical UUID); recorded as `provider_message_id` | P13 |
| `apns-priority` | `10` for category `delivery_priority = high`, `5` for `normal` | P13 |
| `apns-expiration` | UNIX seconds: the intent's `expires_at`; never `0`, so the provider may hold it briefly for an offline device | P13, P26 |
| `apns-collapse-id` | `{category}:{subject_key}` truncated to 64 bytes (ASCII) | P13 |
| Body | JSON of at most 4096 bytes; `aps` with `alert.title`, `alert.body`, `sound: "default"`, `thread-id` (the category), `mutable-content: 1` only when the app ships a notification service extension; custom keys `send_id`, `category`, `route`, `rp` (route parameters as a JSON string) | P13, P18 |

<!-- PATTERN: apns-request-builder -->
<!-- PURPOSE: build one APNs request from a message, a token row and a provider JWT -->
<!-- REFERENCE: language=typescript framework=agnostic api=apns -->
<!-- ADAPT: the HTTP/2 client and its connection reuse are the project's (undici, node:http2, Deno or Bun fetch with HTTP/2); cfg and Msg come from the template renderer and config; keep header names lower-case as HTTP/2 requires -->
```typescript
export function apnsRequest(t: { token: string; env: "production" | "sandbox" }, m: Msg, jwt: string) {
  const host = t.env === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  return {
    url: `https://${host}/3/device/${t.token}`,
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-push-type": "alert",
      "apns-topic": cfg.APNS_TOPIC,
      "apns-id": m.deliveryId,
      "apns-priority": m.priority === "high" ? "10" : "5",
      "apns-expiration": String(m.expiresAtS),
      "apns-collapse-id": m.collapseId.slice(0, 64),
    },
    body: JSON.stringify({
      aps: { alert: { title: m.title, body: m.body }, sound: "default", "thread-id": m.category },
      send_id: m.deliveryId, category: m.category, route: m.route, rp: JSON.stringify(m.routeParams),
    }),
  };
}
```

### FCM request

| Item | Value | Source |
|------|-------|--------|
| Request | `POST https://fcm.googleapis.com/v1/projects/{FCM_PROJECT_ID}/messages:send`, bearer OAuth access token with scope `https://www.googleapis.com/auth/firebase.messaging` | P19 |
| Target | `message.fid` when `target_kind = fcm_fid`; `message.token` when `fcm_registration_token`. `fid` is the preferred field; `token` remains accepted and, during the transition, also accepts an FID | P19, P20 |
| Content | `message.notification` with `title` and `body`; `message.data` as string-to-string: `send_id`, `category`, `route`, `rp`. No reserved key (`from`, `message_type`, `google.*`, `gcm.notification.*`) | P19 |
| Android | `android.priority` `high` or `normal` from `delivery_priority`; `android.ttl` as `"{remaining seconds}s"`, at most 2,419,200; `android.notification.channel_id` the category's channel id (the channel exists on the device before the first send, P10); `android.notification.tag` `{category}:{subject_key}` so a repeat replaces the one on screen (notification messages ignore `collapse_key`, P24) | P19, P24, P26 |
| iOS through FCM | `apns.headers`: `apns-priority`, `apns-expiration`, `apns-push-type: alert`, `apns-collapse-id`; `apns.payload.aps`: `thread-id`, and `mutable-content: 1` only with a service extension | P19 |
| Dry run | `validate_only: true` is allowed in the release check; never in production sends | P19 |

<!-- PATTERN: fcm-request-builder -->
<!-- PURPOSE: build one FCM HTTP v1 send request for an Android or iOS-through-FCM device -->
<!-- REFERENCE: language=typescript framework=agnostic api=fcm-http-v1 -->
<!-- ADAPT: access-token minting from the service account is the project's (google-auth-library or a signed JWT exchange); `android_v2` is an alternative to `android` that this snippet does not use; the fid/token choice follows device_tokens.target_kind -->
```typescript
export function fcmRequest(t: { kind: string; token: string }, m: Msg, accessToken: string) {
  const target = t.kind === "fcm_fid" ? { fid: t.token } : { token: t.token };
  return {
    url: `https://fcm.googleapis.com/v1/projects/${cfg.FCM_PROJECT_ID}/messages:send`,
    headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
    body: JSON.stringify({
      message: {
        ...target,
        notification: { title: m.title, body: m.body },
        data: { send_id: m.deliveryId, category: m.category, route: m.route, rp: JSON.stringify(m.routeParams) },
        android: { priority: m.priority, ttl: `${m.ttlS}s`, notification: { channel_id: m.channelId, tag: m.collapseId } },
        apns: {
          headers: { "apns-push-type": "alert", "apns-priority": m.priority === "high" ? "10" : "5",
                     "apns-expiration": String(m.expiresAtS), "apns-collapse-id": m.collapseId },
          payload: { aps: { "thread-id": m.category } },
        },
      },
    }),
  };
}
```

### Response handling

Tables are exhaustive for the codes the block reacts to; any other answer is treated as a defect of the request (`failed`, token kept, alert). `fixtures/provider-responses.json` holds one case per row.

**APNs** (P15):

| Answer | Delivery | Token | Retry |
|--------|----------|-------|-------|
| 200 | `sent`; store `apns-id` | `last_success_at`, failures 0 | none |
| 410 `Unregistered` / `ExpiredToken`, row `last_registered_at` at or before body `timestamp` (ms) | `failed` | deactivate `provider_unregistered` | no |
| 410, row registered after `timestamp` | `failed` | keep | no |
| 400 `BadDeviceToken` / `DeviceTokenNotForTopic` | `failed` | deactivate `bad_token`; counts toward the breaker | no |
| 403 `ExpiredProviderToken` | `queued` | keep; counts toward the breaker | refresh the JWT, retry once |
| 429 `TooManyProviderTokenUpdates` | `queued` | keep | keep the current JWT; no refresh for 20 minutes |
| 429 `TooManyRequests` | `queued` | keep | retry with a delay and back-off |
| 413 `PayloadTooLarge` | `failed` | keep | no; template defect, alert |
| 500, 503 `ServiceUnavailable` / `Shutdown` | `queued` | keep | not before `APNS_5XX_RETRY_SECONDS` (900); on `Shutdown` also open a new connection |
| other 4xx | `failed` | keep | no |

**FCM** (P21, P23):

| Answer | Delivery | Token | Retry |
|--------|----------|-------|-------|
| 200 with `name` | `sent`; store `name` | `last_success_at` | none |
| 404 `UNREGISTERED` | `failed` | deactivate `provider_unregistered` | no |
| 400 `INVALID_ARGUMENT`, `details` has an `FcmError` with `errorCode = INVALID_ARGUMENT` | `failed` | deactivate `bad_token` | no |
| 400 `INVALID_ARGUMENT`, `details` has a `google.rpc.BadRequest` with `fieldViolations` | `failed` | keep | no; payload defect, alert |
| 403 `SENDER_ID_MISMATCH` | `failed` | deactivate `sender_mismatch`; counts toward the breaker | no |
| 401 `THIRD_PARTY_AUTH_ERROR` | `queued` | keep; counts toward the breaker | pause the iOS-through-FCM lane, alert |
| 429 `QUOTA_EXCEEDED` | `queued` | keep | wait `Retry-After`, or `FCM_QUOTA_DEFAULT_WAIT_SECONDS` (60) without it |
| 503 `UNAVAILABLE` | `queued` | keep | honor `Retry-After`; exponential back-off with jitter, at least `FCM_RETRY_FLOOR_SECONDS` (10) |
| 500 `INTERNAL` | `queued` | keep | exponential back-off with jitter, at least 10 seconds |

Retries stop at `PROVIDER_MAX_ATTEMPTS` or at the intent's `expires_at`, whichever comes first; then the delivery is `failed` with `provider_status = expired` or `max_attempts`. A late retry never sends a notification whose `expires_at` has passed (INV-20).

<!-- PATTERN: apns-response-classifier -->
<!-- PURPOSE: turn an APNs answer into a delivery outcome and a token action by the documented rules -->
<!-- REFERENCE: language=typescript framework=agnostic api=apns -->
<!-- ADAPT: map the returned Act onto the project's transaction (update delivery, device_tokens, retry schedule); the 60 second delay for TooManyRequests is a default, back-off growth is the project's -->
```typescript
type Act = { delivery: "sent" | "failed" | "queued"; token: "keep" | "deactivate"; reason?: string; retryAfterS?: number; breaker?: boolean };

export function classifyApns(status: number, reason: string | undefined, tsMs: number | undefined, lastRegisteredMs: number): Act {
  if (status === 200) return { delivery: "sent", token: "keep" };
  if (status === 410) {
    const dead = tsMs === undefined || lastRegisteredMs <= tsMs;
    return { delivery: "failed", token: dead ? "deactivate" : "keep", reason: "provider_unregistered" };
  }
  if (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic") {
    return { delivery: "failed", token: "deactivate", reason: "bad_token", breaker: true };
  }
  if (reason === "ExpiredProviderToken") return { delivery: "queued", token: "keep", retryAfterS: 1, breaker: true };
  if (reason === "TooManyProviderTokenUpdates" || reason === "TooManyRequests") {
    return { delivery: "queued", token: "keep", retryAfterS: 60 };
  }
  if (status >= 500) return { delivery: "queued", token: "keep", retryAfterS: 900 };
  return { delivery: "failed", token: "keep" }; // PayloadTooLarge and header errors are defects
}
```

<!-- PATTERN: fcm-response-classifier -->
<!-- PURPOSE: turn an FCM HTTP v1 answer into a delivery outcome and a token action, telling an invalid token from a bad payload -->
<!-- REFERENCE: language=typescript framework=agnostic api=fcm-http-v1 -->
<!-- ADAPT: detail is the first element of error.details[] reduced to { type: "FcmError" | "BadRequest", errorCode }; retryAfter is the Retry-After header in seconds (parse an HTTP date if your provider path returns one); exponential growth after the floor is the project's -->
```typescript
export function classifyFcm(status: number, detail: { type?: string; errorCode?: string }, retryAfter?: number): Act {
  if (status === 200) return { delivery: "sent", token: "keep" };
  if (status === 404 && detail.errorCode === "UNREGISTERED") {
    return { delivery: "failed", token: "deactivate", reason: "provider_unregistered" };
  }
  if (status === 400) {
    return detail.type === "FcmError" && detail.errorCode === "INVALID_ARGUMENT"
      ? { delivery: "failed", token: "deactivate", reason: "bad_token" }
      : { delivery: "failed", token: "keep" }; // BadRequest: a defect in our payload
  }
  if (status === 403 && detail.errorCode === "SENDER_ID_MISMATCH") {
    return { delivery: "failed", token: "deactivate", reason: "sender_mismatch", breaker: true };
  }
  if (status === 401) return { delivery: "queued", token: "keep", retryAfterS: 60, breaker: true };
  if (status === 429) return { delivery: "queued", token: "keep", retryAfterS: retryAfter ?? 60 };
  return { delivery: "queued", token: "keep", retryAfterS: Math.max(retryAfter ?? 0, 10) };
}
```

### Throttling, batching and the breaker

- **APNs**: keep a small pool of long-lived HTTP/2 connections and reuse them for hours to days; send a PING after an hour idle; spread load across connections; do not open and close a connection per push. Do not assume a number of concurrent streams, read the server's `SETTINGS`, and slow down when 4xx answers rise because APNs disconnects a connection with too many errors (P13, P15). One JWT per pool, refreshed on the schedule above.
- **FCM**: use HTTP/2 multiplexed requests or the Admin SDK `sendEach` (at most 500 messages per call). The project quota is 600,000 messages per minute by default; client errors count against it. Ramp from zero to the target rate over at least 60 seconds and never put a whole timezone on one instant; the ladder offset (3 to 12 minutes) and the 30-second tick do that for ladder sends, and the dispatcher's ramp does it for bursts of hand-offs (P23).
- **Batching** is internal: claim up to `DISPATCH_BATCH_SIZE` rows per tick; group deliveries by provider and, for APNs, by connection.
- **Breaker**: per provider, over a sliding window, if at least `BREAKER_MIN_SAMPLE` (50) attempts were made and the share of config-class answers (the rows marked "counts toward the breaker" above) is at least `BREAKER_CONFIG_ERROR_RATIO` (0.2), pause that lane for `BREAKER_PAUSE_MINUTES` (15), emit `push_lane_paused`, and **reactivate every token deactivated for `bad_token` or `sender_mismatch` inside the window**. A mistyped topic or a credential from the wrong environment would otherwise wipe the token table (INV-5). `fixtures/provider-responses.json` `breaker_cases` is its table.

## Template rendering and locale

- Resolve the locale per template: exact tag, then the language subtag, then `DEFAULT_LOCALE` (`fixtures/template-catalog.json` `locale_resolution_cases`).
- **Variables** (`README.md` section 6, "Template variables"): `{name}` is required, `[[ ... ]]` is an optional segment omitted whole when any variable inside it is absent. A param the template does not name is ignored. A required variable that is absent gives `template_error` and the intent is suppressed.
- **Derived variables**, each absent when its inputs are absent:
  - `ends_in`: the intent's `expires_at` minus the send instant, formatted by the platform's locale-aware formatter; exists only for a template with `time_binding`.
  - `reward_name`: the display name of `reward_code` from the adopter's item catalog, in the profile locale.
  - `renewal_date`: `renews_at` as a long date in the profile's locale and timezone.
  - `price_text`: `price_milliunits / 1000` formatted as `currency_code` in the profile locale, then a period phrase by `period`: `P1W` per week, `P1M` per month, `P2M`, `P3M`, `P6M` every N months, `P1Y` per year; any other period gives the amount with no phrase. Absent when `price_milliunits` or `currency_code` is absent. The amount is the store's informational figure and the copy says the exact amount is on the store screen.
- After rendering, check `TITLE_MAX_CHARS` and `BODY_MAX_CHARS`; over length gives `template_error`.
- Save-time lint (`INV-17`): reject a template whose text matches `COPY_GUILT_PATTERNS`, `COPY_FAKE_URGENCY_PATTERNS` or `COPY_FALSE_SCARCITY_PATTERNS` (and, for a service category, `COPY_UPSELL_PATTERNS`: offers, discounts, upgrades, "limited" or "special" wording), names a variable that is neither a declared param of its event nor a derived variable, has a reward variable without `requires_reward`, or carries a literal deadline word without a `time_binding`. `copy_lint_cases` is the executable list.
- Copy never carries a balance, a token, a name of another player, or a link (INV-24).

<!-- PATTERN: render-optional-segments -->
<!-- PURPOSE: fill required variables and drop optional segments whose variables are absent, so the copy reads correctly with or without them -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: vars holds declared params plus derived variables already formatted for the locale; a null return means template_error; the regexes use the s flag (ES2018) so port them if the runtime lacks it; no nesting of [[ ]] -->
```typescript
const SEGMENT = /\[\[(.*?)\]\]/gs;
const VAR = /\{([a-z_]+)\}/g;
type Vars = Record<string, string | number | undefined>;

export function render(text: string, vars: Vars): string | null {
  const fill = (s: string, onAbsent: () => void) =>
    s.replace(VAR, (_m, name: string) => {
      const v = vars[name];
      if (v === undefined || v === "") { onAbsent(); return ""; }
      return String(v);
    });
  const noSegments = text.replace(SEGMENT, (_m, inner: string) => {
    let absent = false;
    const filled = fill(inner, () => { absent = true; });
    return absent ? "" : filled;
  });
  let missing = false;
  const out = fill(noSegments, () => { missing = true; });
  return missing ? null : out;
}
```

## Receipts and attribution

| Stage | Source | Stored |
|-------|--------|--------|
| `dispatched` | decision to send | `notification_intents.dispatched_at` |
| `sent` | provider accepted (APNs 200, FCM 200 with `name`); P25 calls this "Sends" and it includes a hand-off to APNs | `notification_deliveries.sent_at` |
| `delivered` | a client receipt (a notification service extension on iOS, a message handler on Android) or a provider report; absent when neither exists | `delivered_at`; never inferred from `sent` (P16, P25) |
| `opened` | `POST /api/push/receipts` with `kind = opened` | `opened_at` on the delivery and, first one wins, on the intent; resets `ladder_unopened_sends` |
| `returned` | the first session start inside the return window | `notification_intents.returned_at` |

- A tap grants nothing and changes no balance (INV-15), so a forged opened receipt can only reset the unopened counter and add a count to one's own funnel.
- **Holdout comparison**: for a ladder step `s` and a period, `incremental_return(s) = returned_share(dispatched intents of s) - returned_share(held_out intents of s)`, each over the same window length (treated from `dispatched_at`, held out from `due_at`). Both groups passed every earlier decision rule, which is why holdout is last (INV-8). Both groups receive the same comeback reward on return, so the difference isolates the notification. The block specifies the measure, not a significance test or a sample size; no source here supplies one.
- A delivery with no receipt after `RETURN_WINDOW_HOURS` is not an error: `delivered` is optional (P25: "Received" exists only on Android).

## Erasure and merge

Deleting the `push_profiles` row removes tokens, preferences, intents, deliveries and comeback grants by cascade (INV-22). The ledger entries of past grants stay with `billing.virtual-currency` under its own erasure rule. Analytics events already in the analytics store carry `account_id` and follow the adopter's analytics retention; this block emits no event after erasure.

## Operations notes

- A daily sweep marks tokens older than `TOKEN_STALE_DAYS` inactive (`stale`), deletes tokens older than `TOKEN_PRUNE_DAYS`, and purges intents and deliveries older than `INTENT_RETENTION_DAYS` after aggregating their counts.
- Alert on: breaker trips, `PayloadTooLarge`, FCM `BadRequest` (template defects), a rising share of `BadDeviceToken` (environment mix-up), JWT refresh failures, pending comeback grants older than one tick.
- Credentials: the APNs signing key (`.p8`), key id, team id, and the FCM service account live in the project's secret store, never in this block's tables or logs (`security.md`).
- A sandbox build registers tokens with `apns_environment = sandbox`; the host choice follows the row, never a global flag.
