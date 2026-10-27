# Security - Push Notifications and Re-engagement

Scope: the Push API, the token table, the dispatcher's provider credentials, the hand-off ingest, the comeback reward and the device-side handlers. Authentication belongs to the auth blocks; this block consumes the verified `account_id`. The ledger's own rules belong to `billing.virtual-currency`.

Each item is tagged **[documented]** when a platform page or store rule states it (row ids P1 to P26 in `README.md` section 3), **[design]** when this block chooses it, or **[extrapolated]** when it is reasoned from the documents and has not been run (see "Origin and verification status").

## Threat Model

### 1. Provider credential theft

**Attack**: the APNs signing key (`.p8`), its key id and team id, or the FCM service account leaks from a repository, a log or a build.

**Impact**: High. The holder can push any text to every installed device of the app, including phishing copy that arrives under the game's name.

**Mitigations**:
- Credentials live in the project's secret store and are read by the dispatcher only; no client bundle, repository, fixture or log contains them. **[design]**
- APNs keys can be limited to one environment or to specific topics; use separate keys for sandbox and production and a topic-specific key where the team has several apps (P14: "team-scoped keys... restrict usage to either Sandbox or Production"; topic-specific keys give granular control). **[documented]**
- A suspected leak: revoke the key in the developer account, request a new one, close all connections to APNs and open new ones (P14). **[documented]**
- The FCM service account carries only the messaging permission (`cloudmessaging.messages.create`, P19) and nothing else. **[documented]** for the permission name; **[design]** for the least-privilege rule.
- The provider JWT is generated in memory, refreshed between every 20 and 60 minutes, never logged (P14). **[documented]**

**Validation rule**: a search of the repository, the build output and the logs for the key material finds nothing; the service account's role list shows messaging only.

### 2. Device token exposure

**Attack**: tokens are copied from a database dump, a log line, an analytics event or a URL.

**Impact**: Medium. A token is a persistent device identifier; without the provider credential it cannot be used to send, but it identifies a device and links it to an account. Exposure is a privacy incident.

**Mitigations**:
- `token` is never returned by any endpoint, never logged, never placed in analytics events or URLs. **[design]**
- The column inherits the database's at-rest encryption and its access control; adopters that must encrypt the column keep a keyed hash column for the `(provider, token)` uniqueness lookup. **[design]**
- Rows are deleted with the account (INV-22) and pruned after `TOKEN_PRUNE_DAYS`. **[design]**
- A token is bound to one account at a time (INV-4). **[design]**

**Validation rule**: `rg` over handlers, loggers and analytics code finds no path that serializes `token`; the account-deletion test leaves no row.

### 3. Forged hand-off events and internal operations

**Attack**: a client or another service posts a crafted event or calls `set_age_status`, `merge_accounts`, `erase_account` to change who is notified or to wipe data.

**Impact**: High for the internal operations (an `adult` status for a minor re-enables notifications), Medium for events (spam bounded by caps).

**Mitigations**:
- Hand-off events arrive only over the internal event bus; the bus authenticates its publishers. The five internal operations are not routes of the public API. **[design]**
- Events are idempotent by `(account, category, subject_key)`; a flood of one key changes one row (INV-21). Pending rows per profile are bounded by `MAX_PENDING_PER_PROFILE`; the newest are dropped and counted. **[design]**
- Frequency caps bound what a buggy or hostile emitter can make reach a player (INV-10). **[design]**
- `set_age_status` is called only by the adopter's age-gate service; the client never supplies an age. **[design]**

**Validation rule**: no public route reaches an internal operation; an event with an unknown name or a forged lane changes nothing.

### 4. Deep-link and payload abuse

**Attack**: a forged notification or another app on the device hands the game an intent or payload whose `route` or `rp` points at an unexpected screen, an external URL or a crafted parameter.

**Impact**: Medium. A phishing screen or an unintended action inside the game.

**Mitigations**:
- The payload carries a route id and string parameters, never a URL; `resolveRoute` accepts only ids in `ROUTE_ALLOWLIST`, only the parameter names that route lists, and only values matching `^[A-Za-z0-9._:-]{1,64}$`; anything else opens `home` (INV-18). **[design]**
- Notification data from the platform is treated as untrusted input on the device, including tap intents that arrive from other apps. **[design]**
- A route that performs a state change (claiming a reward) is not a route: routes open screens; the claim needs the player's action in the app. **[design]**
- No notification grants a reward (INV-15). **[design]**

**Validation rule**: the fixtures for unknown route, bad parameter and malformed `rp` all land on `home` without throwing.

### 5. Sensitive content on the lock screen

**Attack**: a notification shows a balance, a purchase, a friend's name or a minor's data to anyone who sees the screen.

**Impact**: Medium. App Review 4.5.4 says push "should not be used to send sensitive personal or confidential information" (P5). **[documented]**

**Mitigations**:
- Copy carries the template text and flat non-personal variables only (INV-24); the lint rejects templates naming a balance, a token or another player. **[design]**
- Provider payloads carry `send_id`, `category`, `route` and `rp`; no account id, no email. **[design]**

**Validation rule**: the payload builders are tested against the key list above; a template with a personal variable fails the lint.

### 6. Comeback reward farming

**Attack**: a player stays away on purpose to collect the welcome-back gift again and again; or opens several accounts; or forges receipts to trigger grants.

**Impact**: Low to Medium: an economy leak bounded by the reward size.

**Mitigations**:
- The reward is a function of lapse length computed from server state (`last_session_at`, the profile timezone, the server clock), not of anything the client sends beyond the session call itself (INV-1, INV-15). **[design]**
- One grant per anchor, one per `LADDER.comeback_cooldown_days` (30), highest step only; the ledger idempotency key makes a replay a no-op (the ledger contract). **[design]**
- No grant depends on a push, a tap or a receipt, so forging receipts earns nothing. **[design]**
- Multiple accounts per person are outside this block; the ledger and the auth blocks own that control. **[design]**

**Accepted risk**: a client that sets its timezone can move a lapse by one local day, which can earn a step one day early. The timezone is the account's (the owner of the time contract rate-limits changes), and the gain is bounded by the cooldown. **[extrapolated]**

**Validation rule**: `reward_selection_cases` pass; two session calls with one `session_id` and two calls with different ids in one lapse create one grant.

### 7. Spam, fatigue and unwanted delivery

**Attack / failure**: the game messages too often, at night, or for categories the player turned off; or a timezone or daylight-time bug sends at 03:00 local.

**Impact**: Medium. Players turn notifications off at the system level (which no in-app control can undo) or uninstall; Apple may treat abuse as grounds to revoke push privileges (P5). **[documented]** for the policy; the uninstall effect has no data in the research notes (`retention_mechanics_catalog.md:176`).

**Mitigations**:
- Caps across all categories and both lanes; a capped message is dropped, not queued (INV-10). **[design]**
- Quiet hours in the profile's timezone evaluated at the instant with the IANA rules, tested across the daylight-time changes of `local_time_cases` (INV-11). **[design]**
- Category switches and the master switch are server-authoritative and cancel pending work immediately (INV-12). **[design]**
- The ladder ends: a final step, `max_lapse_days`, and `after_unopened_sends` (INV-14). **[design]**
- The holdout measures whether the program earns its place; a program with no incremental return is switched off by its owner. **[design]**

**Validation rule**: the decision cases for caps, quiet hours and switches pass; no send is created inside a quiet window.

### 8. Minors

**Attack / failure**: a player under the age threshold registers a device and receives re-engagement messages, or the age decision arrives late and notifications go out first.

**Impact**: High. Regulators act on children's data and on engagement mechanics aimed at children (`06-design-ethics-and-compliance.md:9`, `:45`, `:46`, `:51`). **[documented]** by the guide's sources: an FTC settlement over loot boxes sold to under-16s (HIGH in the guide), $275 million for children's privacy violations in the Fortnite case (HIGH), Vietnam's parent-managed accounts for under-16s (MEDIUM, conflicting).

**Mitigations**:
- Only `adult` profiles (or `unknown` under an explicit `UNKNOWN_AGE_POLICY = allow`) can register a token, hold a local plan, enter the ladder or receive a grant (INV-13). Default for `unknown` is `block`. **[design]**
- The age status is written only by the server-side age-gate input; a change to a non-eligible status deactivates tokens, cancels pending intents and tells the device to cancel its local plan on the next state read (INV-13). **[design]**
- No token row is created for a minor, which also keeps a persistent device identifier out of the table. **[design]**
- Whether a push token counts as a persistent identifier under children's privacy law, and the consent law for marketing messages, were not researched (guide 06 lists GDPR for children as not researched). Treat those questions as open and ask counsel before launch in the markets that apply. **[extrapolated]**

**Validation rule**: `D04-minor` suppresses with `age_ineligible`; the token upload for `unknown` returns 403 `age_not_eligible`.

### 9. Shared device and account switch

**Attack / failure**: after logout, the previous player's reminders (local notifications) or remote sends keep appearing for the next person.

**Impact**: Medium. A privacy leak between people, and wrong content.

**Mitigations**:
- Logout calls `DELETE /api/push/tokens/{installation_id}` and cancels the whole local plan before the session is dropped (INV-4, INV-7). **[design]**
- Registration deactivates any other profile's row for the same `installation_id` or `(provider, token)` (INV-4). **[design]**
- The local plan is rebuilt from the signed-in account's state at every session start. **[design]**

**Validation rule**: the account-switch scenario leaves one active row and an empty local plan until the second account's state rebuilds it.

### 10. Spoofed receipts and session calls

**Attack**: a client posts opened receipts for other accounts' `send_id`s, or replays session calls to manipulate attribution or counters.

**Impact**: Low. Attribution noise only; no reward depends on them.

**Mitigations**:
- A `send_id` that does not belong to the session's profile is ignored and the answer is the same `204` (no existence leak). **[design]**
- `opened_at`, `delivered_at` and `returned_at` use the server clock (INV-1). **[design]**
- Session and receipt calls are idempotent (INV-21) and rate-limited per account by the adopter's API gateway. **[design]**

**Validation rule**: a receipt for another account's `send_id` changes no row.

### 11. Mass token invalidation by a configuration error

**Attack / failure**: the wrong APNs environment, a changed bundle id or a wrong FCM sender makes every send answer `BadDeviceToken`, `DeviceTokenNotForTopic` or `SENDER_ID_MISMATCH`, and the block deactivates the whole table.

**Impact**: High. Every player silently loses notifications until they reopen the app and re-register.

**Mitigations**:
- Tokens carry their `apns_environment`; the host follows the row (`backend.md`, APNs request). **[design]**
- The breaker pauses a lane when config-class answers reach `BREAKER_CONFIG_ERROR_RATIO` of at least `BREAKER_MIN_SAMPLE` attempts and reverts deactivations made inside the window (INV-5). APNs itself disconnects a connection with too many errors, so the block must slow down before that (P15). **[documented]** for APNs's behavior; **[design]** for the thresholds.

**Validation rule**: `breaker_cases` B01 to B03 pass.

### 12. Consent record integrity

**Attack / failure**: a promotional category is switched on with no consent copy on screen, or the stored version names copy the app never displayed.

**Impact**: Medium. App Review 4.5.4 requires an explicit opt-in through consent language in the UI and a way to opt out (P5). **[documented]**

**Mitigations**:
- A promotional category switches on only with a `consent_text_version` the server knows (`CONSENT_TEXT_VERSIONS`); otherwise `422 consent_required`. **[design]**
- The version is stored with the switch (`push_category_prefs.consent_text_version`), so a later copy change can be traced to who saw what. **[design]**
- Every switch has an off path in Settings (P5). **[documented]**

**Validation rule**: the `D13-promotional-without-consent` case suppresses; the PATCH without a version is refused.

### 13. Logs, analytics and retention

**Attack / failure**: tokens, JWTs, access tokens or notification bodies end up in logs; intent rows about lapsed players accumulate forever.

**Impact**: Medium. Privacy and credential exposure.

**Mitigations**:
- Logs record ids, statuses and reasons; never `token`, JWTs, OAuth access tokens, request bodies. `provider_status` holds only the status code and the reason or error code. **[design]**
- Analytics events carry the properties listed in `README.md` section 6 and nothing else (no token, no body). **[design]**
- Intent and delivery rows older than `INTENT_RETENTION_DAYS` are purged after their counts are aggregated for the holdout analysis. **[design]**

**Validation rule**: a log capture of a full ladder run contains no token or JWT.

### 14. A service notice turned into an upsell, or relied on as the only disclosure

**Attack / failure**: the trial-ending notice is rewritten to sell (a discount, an upgrade, loss framing), is sent to a profile that is not verified as an adult, or is treated as the way the player learns the terms of a trial.

**Impact**: Medium to High. Guide 15 lists auto-renew and trial failures as a RED item (a silent conversion, a buried cancel) and notification guilt as AMBER (`15-manipulation-and-the-line.md`, catalog rows 14 and 16); selling inside a notice about a charge combines both.

**Mitigations**:
- The `subscription` templates pass `COPY_UPSELL_PATTERNS` besides the guilt, urgency and scarcity lint; the copy states the price after the trial, the renewal date and where to manage or cancel, and nothing else (INV-25, INV-17). **[design]**
- The notice is never a ladder step and never held out; `HOLDOUT_CATEGORIES` validation rejects a service category. **[design]**
- It defaults on only for an `adult` profile and a `minor` profile receives nothing (INV-13, INV-25); guide 15 keeps real-money spending off by default for any profile not verified as an adult (`:50`, `:111`), and extending that default to the notice is our reading. **[extrapolated]**
- The notice is exempt from the marketing caps by design, bounded by `CAP_SERVICE_PER_LOCAL_DAY`, and honours quiet hours and the master switch, so it can be dropped (`quiet_expired`, `global_off`); the terms at purchase and the in-app status belong to `billing.subscriptions` (its `paywall-disclosure.feature`), and this push is a convenience on top of them. **[design]**
- The price in the copy is formatted from the emitter's `price_milliunits` and `currency_code` in the player's locale, is never asked of the store here, and is stated as an approximate amount with the exact one on the store screen; with no price known the sentence is omitted. **[design]**

**Validation rule**: the `D17` to `D23` decision cases and the service-template lint cases pass; a template with offer wording is rejected at save time.

## Out of scope

Account takeover, session handling and the ledger's authorization belong to their blocks. Provider outages and Apple or Google policy changes are operational risks listed in `backend.md` (operations notes); the platform rows of `README.md` section 3 carry the date they were read.
