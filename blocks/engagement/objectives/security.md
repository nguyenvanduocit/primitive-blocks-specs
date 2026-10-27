# Security — Objectives, Missions and Achievements

> The block is a second source of currency: every claim is a ledger grant. Its threat model is therefore economic first (forged progress, double payout, farming) and privacy second. The authorization rules are written as invariants (A-1..A-8) a SQL backend enforces in its handlers and queries; tests reference them by id.

## Authorization Invariants

| ID | Invariant |
|----|-----------|
| A-1 | **Identity comes from the session.** Every player endpoint resolves `account_id` and `tenant_id` from the verified session. No body, query, path or header value selects whose rows are read or written (INV-25). |
| A-2 | **The client sends facts, never outcomes.** The only client-supplied values that change state are event `metric`, `amount`, `occurred_at`, `ref`, `attempt_id` and `event_id`, an instance id for claim or reroll, and a `session_id`. No request carries progress, state, target, reward, scope, tier, points or a ledger key; a body naming one is `422 invalid_request`. |
| A-3 | **Server-derived metrics are unreachable from the client.** `ingest_server_event` is an internal function with no HTTP route a player's session can reach; the same metric sent through the client endpoint is `metric_not_client_reportable` (INV-3). |
| A-4 | **Responses use an explicit projection.** An item serializes exactly the fields listed in `backend.md` "List response". Never: `account_id`, `tenant_id`, `draw_seed`, plan `members` or weights, `template_id`, `deepen_test`, `definition_version`, `ledger_entry_ids` of other claims, and nothing at all of a `hidden_until_earned` instance that is not `completed` (INV-20). |
| A-5 | **Content is operator-only.** `publish_definitions` is not a player endpoint. It runs under an operator credential, validates the whole set, activates atomically, and records who published what and when. |
| A-6 | **The ledger reason is fixed.** Claims call the ledger with the constant reason `objectives.reward`, the instance id as `source_ref` and a key built from stable facts (`objectives:{account_id}:{objective_id}:{window_key}:{line_index}`), under a service credential. No client value enters the reason, the key or the amount. |
| A-7 | **Merge is a service call of the guest-account block.** `mergeAccounts` is invoked by `auth.guest-account` after the player proved control of the credential that owns the target account (its link conflict flow decides that); the block exposes no endpoint that takes two account ids from a client. |
| A-8 | **Isolation.** Every query includes `tenant_id` and the session's `account_id`; an instance id of another account answers `404 not_found`, the same as a missing one. |

### Read and write matrix

| Resource | Anonymous | Signed in (owner) | Operator | Other service |
|----------|-----------|-------------------|----------|---------------|
| Own list, claim, claim-all, reroll, events, sessions | Denied (401) | Allowed | Not through this surface | Denied |
| `ingest_server_event` | Denied | Denied | Allowed through the internal call | Allowed with a service credential (blocks, ledger adapter, game server) |
| `publish_definitions` | Denied | Denied | Allowed | Denied |
| `mergeAccounts`, `holdings`, `deleteAccount` | Denied | Denied | Denied | `auth.guest-account` and `compliance.account-deletion` only |
| Another account's rows | Denied | Denied | Denied (no read path in this block) | Denied |

## Input Validation Rules

| Field | Rule | On failure |
|-------|------|------------|
| `events` | Array, `1..EVENT_BATCH_MAX`, objects with known keys only | `422 invalid_request` or `batch_too_large`; nothing recorded |
| `event_id` | `text_short` (at most 255 characters), unique per account | `invalid_request` |
| `metric` | Must exist in the registry | per-event `unknown_metric` |
| `amount` | Integer, at least 1, at most the platform's safe integer; no strings, fractions or null | per-event `invalid_amount` |
| `occurred_at` | ISO 8601 UTC timestamp; older than `EVENT_MAX_AGE_SECONDS` is rejected; the future is clamped to the receive time | per-event `event_too_old` or clamp |
| `ref` | `text_short`, opaque to this block, passed to the validator hook only | `validation_failed` when the hook rejects |
| `attempt_id` | `external_id` of at most 255 characters in the shape `engagement.energy-lives` accepts; required for metrics with `requires_attempt` | per-event `attempt_required` or `attempt_not_proven` |
| `session_id` | `text_short`, at most 64 characters, characters `[A-Za-z0-9_-]` | `invalid_request` |
| `instance_id` | `unique_id` shape | `404 not_found` |
| `scope` (list, claim-all) | One of the six scope values | `422 invalid_request` |
| Bodies | At most 64 KB, rejected before full buffering; unknown keys rejected | `422` |

Error bodies are `{ error: string }` with the stable identifiers of `backend.md`; they carry no stack traces and no internal ids.

## Threat Model

### T-1. Forged client events (client_reported and client_validated metrics)

**Impact**: Medium for soft-currency rewards, High if a premium reward could reach an untrusted metric (T-2).

**Mitigations**
- Trust classes (README "Trust classes"): everything tied to money, the ledger, streaks, active days, queue completions and board points is `server_derived`.
- Per-event clamp (`max_amount_per_event`) and per-day clamp (`day_cap`) bound what a forged stream can add (INV-5).
- Reachability check at publish (INV-6) keeps a cap from silently making an objective impossible, and means a cheater cannot complete more than the board allows.
- Daily payout is bounded by the plan structure, not by the client: with the sample content in `fixtures/definitions.json` the most a daily board can pay is the three largest rewards among distinct exclusive groups (70 + 60 + 50), the three ladder rungs (15 + 25 + 40) and the whole-board bonus (60), which is 320 coins before sessions and weekly goals. Operators compute the same figure for their content and alert when an account's `objectives.reward` grants per day exceed it.
- Play-based metrics need proof of play: the event must name an attempt that `engagement.energy-lives` reports as `confirmed`, `won` or `failed` (INV-30), so an `open` attempt, a refunded start or an invented id counts nothing, and a client cannot report play it never started.
- `client_validated` metrics pass the game's validator after the attempt check; its quality is the game's responsibility.

**What the bounds do not stop** (state this to the product owner)
1. A forged `client_reported` stream completes every objective bound to such a metric each day, up to the caps. The loss is bounded by the payout figure above, not prevented.
2. An attempt proves that a session existed, not what happened in it: one confirmed attempt can carry events up to the per-event and day caps, so a game that wants a per-attempt bound lowers `max_amount_per_event` or uses a `client_validated` metric. An honest event can also be rejected when its attempt was abandoned before the device reported it; that event is dropped.
3. Lifetime counters (`lifetime_total` objectives and achievements) accumulate up to the day caps for as many days as the account exists; a bot reaches long-horizon achievements faster than a person.
4. The validator hook is only as strong as the game's own checks; a validator that accepts any `ref` is the same as `client_reported` without the caps.
5. Several accounts per person (T-7).

**Consequence for the spec:** `README.md` "When NOT to use" excludes prizes and rankings with real stakes. For real stakes, make the metric `server_derived` from an authoritative game server.

### T-2. Premium reward through an untrusted metric

**Impact**: High. This is how a client mints premium currency.

**Mitigations**: the Value rule (INV-4): a definition paying a currency in `PREMIUM_CURRENCY_CODES` binds, through its metric and through every alternate source, only to `server_derived` or `client_validated` metrics and is never scalable. Publish rejects a violation (`premium_reward_requires_trusted_metric`, `premium_reward_not_scalable`; cases in `fixtures/definitions.json`). `PREMIUM_CURRENCY_CODES` must list every currency that can be bought with money; an incomplete list silently disables the rule, so the acceptance checklist verifies it against the ledger's currency catalog.

**Not stopped**: a compromised game server or validator that signs forged facts.

### T-3. Replayed and duplicated events

**Impact**: Medium. A retry, a double flush or a captured request must not count twice.

**Mitigations**: `(tenant, account, event_id)` unique (INV-2); `EVENT_RETENTION_SECONDS >= EVENT_MAX_AGE_SECONDS` checked at startup, and the age check rejects an old id whose row was deleted; server events use `<source>:<source_ref>`, built from the sender's stable facts.

### T-4. Double claim and claim races

**Impact**: High (double payout).

**Mitigations**: row lock on the instance; deterministic ledger keys per reward line; the ledger replays a repeated key and returns the original entry (INV-8); a crash between the grant and the state update repeats the same keys on retry; claim-all runs per-instance transactions. Concurrent claims from two devices yield one applied grant and one `already_claimed`.

### T-5. Instance id guessing (IDOR)

**Impact**: High if a claim or reroll could act on another account's row.

**Mitigations**: A-1 and A-8; ids are random (`unique_id`); a foreign id and a missing id are indistinguishable.

### T-6. Farming rerolls, sessions and daily windows

**Impact**: Medium.

**Mitigations**
- Rerolls come from a bank that earns per elapsed window and is capped (`reroll_bank_cap`), cost no currency and are not sold; a replacement can never be an objective already in the window, so rerolling cannot cycle until a favorable draw repeats; `same_tier` (default) keeps the reward size equal, so a reroll cannot trade a hard goal for an easy one of the same pay.
- A new instance counts only events after its activation, so a reroll cannot adopt progress already made (`since_activation`).
- `session` plans are assigned at most `SESSIONS_WITH_OBJECTIVES_PER_DAY` times per local day.
- One live window per plan and unique window keys: changing the timezone to reach a new `day_key` closes the earlier window (INV-12), and the number of changes is limited by `engagement.daily-streak`. The residual gain is one extra window per allowed timezone change.

### T-7. Many accounts per person

**Impact**: Medium. Starter and daily rewards are per account; a person with many guest accounts earns them many times.

**Mitigations in this block**: starter rewards are fixed and small by content design; merging a guest pays nothing (INV-22) and keeps the higher reroll bank, not the sum; unmatched active guest rows are dropped on merge.

**Not stopped**: nothing ties a guest account to a person. Device attestation and account-creation limits belong to the auth blocks. Tune starter rewards on the assumption that they can be repeated per account. LOW (general property of open sign-up, not tested).

### T-8. Leaking hidden achievements

**Impact**: Low (spoilers), but it breaks a product promise.

**Mitigations**: the server's projection omits a `hidden_until_earned` instance in every field and count until `completed` (INV-20, A-4); progress for it is still tracked server-side. Client-side hiding would leak through the API. Counters such as `claimable_count` and the starter totals exclude hidden instances.

### T-9. Bad or malicious content publish

**Impact**: High. A reward typo (an extra zero) or a premium reward on an untrusted metric mints currency to everyone assigned that objective.

**Mitigations**: A-5 and the publish-time validation table (`backend.md`); atomic activation; versioning (INV-21) so a bad version can be retired without touching claimed history. **Extrapolated, not specified here:** the operator tool should show a diff of reward totals per plan and require a second approver for any increase, and the ledger's own per-grant ceiling (if it has one) bounds the damage. Completed-unclaimed rewards keep the reward snapshot of the bad version; reverse them with an explicit operator action, not a silent edit.

### T-10. Client clock manipulation

**Impact**: Medium for any time-based goal.

**Mitigations**: windows, expiry, caps and the late-event age check use the server clock only (INV-1); `occurred_at` is clamped to the receive time and never selects a window; countdowns show `ends_at` from the server.

### T-11. Event flooding

**Impact**: Medium (database load, cap exhaustion).

**Mitigations**: `EVENT_BATCH_MAX`, body size limit, `ACCOUNT_EVENTS_PER_DAY_MAX`, a per-client rate limit, and `day_cap` (a capped event still stores one idempotency row, which is why the per-account recorded-event ceiling exists).

### T-12. Merge abuse

**Impact**: Medium. Merging many guests into one account to harvest rewards.

**Mitigations**: a guest account merges at most once (`UNIQUE from_account_id`); the merge never calls the ledger; matched rows keep the more advanced state rather than adding claims; reroll banks do not add. The ledger balances of the guest join by the ledger's and progress-sync's rules, which this block does not own.

### T-13. Self-feeding and cascade loops

**Impact**: Medium. A reward that counts toward its own objective, or a board that feeds itself.

**Mitigations**: ledger-derived metrics ignore `objectives.reward` grants (INV-24); board metrics are `server_derived` and emitted only by the cascade; milestones carry no points (INV-28) so the cascade ends in one step; the season XP call (`ingest_xp`) is one-way and idempotent by `completion_id` (INV-29).

### T-14. Store-policy and consumer-protection violations

**Impact**: High (store rejection, regulator action).

**Mitigations**: no metric can be a store rating, review, purchase, subscription state, premium spend, speed-up, or an invitation, referral or gift purchase (INV-23, `FORBIDDEN_METRIC_SOURCES`); the adapter drops purchased item grants and premium-paid upgrades; no definition has a price or requires a purchase or an invitation to buy; invitation and gift goals that involve no purchase are optional, skippable and capped, and their reward is also reachable without an invitation (INV-27); no reroll or revive is sold. Kit guide 15 (`15-manipulation-and-the-line.md`, checks O1 to O3) asks for the same. Platform text is quoted in `README.md` "Ethical floor" (Apple Guideline 3.2.2(x) and section 3 introduction; Google Play "User Ratings, Reviews, and Installs"). The EU principles on in-game currencies are non-binding; the legal snapshot of kit guide 06 moves quickly and is rechecked before launch. COPPA, GDPR-K and age handling were not researched for this block.

## Privacy and data handling

- Rows hold an account id, objective ids, counts and timestamps. No event payload carries a name, email, device id or free text; `ref` is an opaque run or record id supplied by the game.
- Do not log request bodies or `ref` values; log counts (events received, counted, rejected by reason) and request ids.
- Retention: events `EVENT_RETENTION_SECONDS`, terminal instances `HISTORY_RETENTION_SECONDS`; completed unclaimed instances until claimed.
- Account deletion removes every per-account row, including merge records (`compliance.account-deletion`).
- The objective list is behavioral data about the player's play; do not use it for advertising or for deciding prices.

## Secrets

This block holds no secrets of its own. The service credentials it uses to call the ledger and `engagement.season-pass` come from the deployment environment, are never sent to the client, never logged, and are scoped to the calls they need.
