# Security — Season Pass

## Trust Boundaries

| Caller | May do | May never do |
|---|---|---|
| Player (session) | read own state; claim own cells; confirm own premium purchase; quote and buy own skips and boosts | name another account or tenant; send an XP amount, a tier, a price the server did not quote, or a premium flag |
| Trusted game server or `engagement.objectives` (service credential) | ingest XP events for any account of the tenant | read player state; claim; publish seasons |
| Purchase contract (`billing.virtual-currency`, in-process) | announce a purchase state change | grant rewards; change tiers |
| `auth.guest-account` (in-process) | call `holdings`, `mergeAccounts`, `deleteAccount` | be reachable from a player route |
| `engagement.energy-lives` (in-process, read) | answer `attemptState` | write season state |
| Operator tooling | publish a season | edit a published season |
| Settlement and reconcile jobs | run the claim execution for due cells | grant any cell the claim rules do not allow |

Rules that follow: `account_id` and `tenant_id` come from the session or the service credential, never from a body (INV-21); XP amounts come from configuration (INV-5); the season is named by the request for claims and chosen by the server clock for everything else (INV-1, INV-8).

## Threat Model

### T1: Forged XP (client-reported progress)

**Attack**: a modified client posts "I completed 500 levels" or an XP amount, to climb the pass and claim premium-track value (after buying) or free-track value.

**Impact**: HIGH — free currency and items in an economy that sells them; unfair standing.

**Mitigation**:
- XP ingestion is a service-credential endpoint no device can reach (INV-5). The player API has no XP-write path.
- The request carries a source and a unit count; the amount is `xp_per_unit x units` from `XP_SOURCES`. An amount field is rejected (`invalid_event`).
- Per-source daily and season caps and the optional total daily cap bound what a compromised caller or a farmed repeatable action can credit (INV-6).
- Proof of play: a source with `requires_attempt` credits only an attempt that `attemptState` reports as `confirmed`, `won` or `failed`, and one attempt credits one source once (INV-23). An `open` attempt proves nothing, so a start that is refunded earns no XP.
- Callers must derive events from server-validated game results (the objective service's own validation); this block cannot detect a lying caller beyond the proof of play and the caps.

**Validation rule**: `xp-ingestion-and-tiers.feature` rejects an amount field, an unknown source and every attempt state outside `confirmed`, `won` and `failed`, and shows the caps binding; no endpoint under the player session writes `xp_events`.

### T2: Replayed or duplicated events

**Attack**: a retry storm, a message-queue redelivery, or an attacker with a captured request replays an event to credit it again.

**Impact**: MEDIUM — XP inflation up to the caps.

**Mitigation**:
- UNIQUE (`tenant_id`, `account_id`, `event_id`): one event credits at most once, ever, and a replay returns the first answer (INV-5).
- `occurred_at` older than `INGEST_MAX_EVENT_AGE_SECONDS` is rejected, and rows are kept at least that long, so pruning a row cannot reopen a replay (`XP_EVENT_RETENTION_DAYS` is never below the max age).
- Skips book `skip:{purchase_id}` and catch-up books `catch-up:{season_id}` in the same table, so they share the guarantee.

**Validation rule**: a replay of `evt-0001` leaves `total_xp` unchanged and writes no row (`xp-event-cases.json`, `replay-of-evt-0001`).

### T3: Double claim (races, retries, two devices)

**Attack / failure**: two taps, two devices, a retry after a dropped response, a claim racing the settlement job, or a crash between the ledger grant and the confirmation produce two ledger grants for one cell.

**Impact**: HIGH — duplicated currency and items; the economy inflates.

**Mitigation**:
- The claim row's UNIQUE (`tenant_id`, `account_id`, `season_definition_id`, `track`, `tier`) decides a race; the ledger key `season-pass:{account_id}:{season_id}:{track}:{tier}` makes the grant itself idempotent (INV-7).
- Intent first: a `pending` row exists before the grant, so a crash leaves a completable row, not an orphan grant (INV-20).
- The ledger replays an applied key with identical arguments and returns `idempotency_conflict` for different arguments; the arguments here derive from an immutable definition (INV-3), so a conflict signals a bug and alerts.

**Validation rule**: `claims.feature` runs concurrent claims of one cell and a crash-and-retry; exactly one ledger entry exists after each.

### T4: Premium without paying, or paying once for many

**Attack**: set a premium flag from the client; submit another player's `store_transaction_id`; replay one transaction for two accounts or two seasons; submit a transaction for a different product (a cheap currency pack).

**Impact**: HIGH — paid content for free.

**Mitigation**:
- `premium_state` is server state and every premium claim checks it at claim time (INV-9).
- Activation reads the purchase record only. It requires state `verified`, the record's `account_id` equal to the caller (a null account, after erasure, matches nobody), the record's product equal to the season's `premium_product_code`, and the season to be the one containing the store's `purchased_at` (INV-12).
- UNIQUE (`tenant_id`, `premium_purchase_ref`): one transaction can unlock one account-season.
- A second paid transaction for an account that is already premium answers `premium_already_active` and alerts; it never silently grants or silently swallows.
- This block verifies no receipt. Receipt verification is the purchase contract's single path.

**Validation rule**: `premium-unlock-and-refund.feature` covers account mismatch, wrong product, outside any season, pending state, null account, and a replay.

### T5: Refund abuse and a missed refund signal

**Attack**: buy premium, claim every premium reward, refund through the store. Or a refund occurs and the signal never arrives, so premium stays on.

**Impact**: MEDIUM — value kept after a refund; bounded to one season's premium rewards per refund.

**Mitigation**:
- The record is the truth: `premium_state` follows the record's state (`verified` means `active`). The in-process callback is a latency hint delivered at most once, so a recheck job re-reads every active row every `PREMIUM_RECHECK_SECONDS`; that interval bounds the exposure of a missed signal.
- `REFUND_POLICY` chooses between keeping claimed rewards (default) and clawing back what the balance still holds. The ledger never goes below zero, so a clawback is partial by construction. Google's guidance lists clawback, warnings and temporary purchase blocks as options for voided purchases, not a duty ([Google Play Billing security](https://developer.android.com/google/play/billing/security), HIGH); repeated abuse handling (a strike count, a purchase block) is the operator's decision and is not specified here.
- Apple documents `REFUND` and `REFUND_REVERSED`, and Google documents `VoidedPurchaseNotification`; the purchase contract maps them to the record's state (`README.md` section 6).

**Validation rule**: `premium-unlock-and-refund.feature` refunds and reverses a purchase under both policies and checks that the ledger never goes negative.

### T6: Clock manipulation and boundary abuse

**Attack**: set the device clock back to keep a "season" alive; claim after the season; claim at the rollover instant expecting the new season's table; run two seasons that overlap so one XP event feeds both; edit a published season mid-way.

**Impact**: MEDIUM.

**Mitigation**:
- The server clock decides every window, cap day and boundary. Season intervals are absolute UTC instants, half-open (INV-1). A device clock changes only a display.
- Claims name their season and are evaluated against its window and tier table; `claim_until = ends_at + CLAIM_GRACE_SECONDS` closes the window (INV-8).
- Publish rejects overlapping intervals; the read path treats two active seasons as a configuration error and credits nothing (INV-2). A published season is immutable (INV-3).
- Daily caps use the account's `day_key`; changing timezone is rate-limited by `engagement.daily-streak`, and the per-source season cap bounds a timezone-hopping player.

**Validation rule**: `season-end-and-rollover.feature` and `clock-and-season-definition.feature` cover the boundary instants to the second.

### T7: Price tampering on skips and boosts

**Attack**: send a lower `price_shown`, a negative or huge `count`, a boost code from another catalog, or buy a boost that outlasts the season.

**Impact**: MEDIUM — progress or multipliers for less than the listed price.

**Mitigation**:
- The server computes the price and the XP; `price_shown` only has to match it (INV-13). A mismatch is `price_changed` with the fresh quote, never a silent re-price.
- `count` is bounded by `MAX_SKIP_TIERS_PER_REQUEST` and the last defined tier; the boost code must be in `XP_BOOST_CATALOG`; a boost that does not fit is rejected (INV-14).
- The amount spent is the intent row's `price_amount`, written before the spend and never taken from a later request.

**Validation rule**: `skips-and-boosts.feature` covers a lowered `price_shown`, an over-large count, an unknown boost, and a boost that does not fit.

### T8: Ingest endpoint abuse

**Attack**: a leaked service credential is used to credit XP to chosen accounts; a runaway caller floods the endpoint; a farmed in-game action fills the pass.

**Impact**: HIGH if the credential leaks; MEDIUM for flooding.

**Mitigation**:
- The service credential is held in a secrets store, never in a client bundle or a log, rotated on suspicion, and checked in constant time.
- `INGEST_RATE_LIMIT_PER_ACCOUNT_PER_MINUTE` backs the caller off (`rate_limited`).
- The caps in T1 limit damage per account; a credential leak is a full-compromise event for the caps' purposes and is handled by rotation and by auditing `xp_events` for unusual `event_id` patterns.

**Validation rule**: a request without the credential is `unauthorized` and writes nothing.

### T9: Crossing accounts or tenants

**Attack**: change `account_id`, `season_id` or a cell in a request to read or claim another account's data.

**Impact**: HIGH — another player's rewards.

**Mitigation**:
- Every query filters by the session's tenant and account; there is no endpoint that takes an account id (INV-21).
- `GET seasons/{season_id}` returns the caller's own state or 404; it never reveals whether another account has progress.
- No leaderboard of pass progress is part of this block (`ugc.friends-leaderboard` owns social views).

**Validation rule**: `claims.feature` shows a body carrying another `account_id` is rejected (`invalid_request`).

### T10: Value moved, effect lost

**Attack / failure**: the process dies after a ledger spend for a skip and before the XP is booked; or the ledger is down mid claim-all.

**Impact**: HIGH for trust — a player paid and received nothing.

**Mitigation**: intent rows before effects and idempotent completion by any caller (INV-20); the reconcile job completes `pending` rows every `PENDING_RECONCILE_SECONDS`; rows stuck past twice that interval raise an alert; the read path repairs the caller's own pending rows before answering.

**Validation rule**: `claims.feature` (crash between grant and confirm) and `skips-and-boosts.feature` (crash between spend and XP) end with one ledger entry and the effect applied.

### T11: A wrong or hostile season definition

**Attack / failure**: an operator publishes a tier table with a gap, an unknown reward code, or a premium track with nothing in it; a season is edited after players saw it.

**Impact**: MEDIUM — failed claims in production, or a sale of nothing.

**Mitigation**: the publish validations (`README.md` section 3) run before `published_at` is set; a published season is immutable (INV-3); reward codes are checked against the ledger catalog at publish.

**Validation rule**: `clock-and-season-definition.feature` covers each publish error.

### T12: Funnelling farmed guests into one account

**Attack**: create many guest accounts, earn each one's capped XP, then merge them into one main account to exceed the per-account caps.

**Impact**: MEDIUM — XP above what one account can earn.

**Mitigation**: the per-source season caps bound each guest's contribution (INV-6), and `auth.guest-account` limits how many guests can be imported into one existing account per day (its `LINK_IMPORTS_PER_TARGET_PER_DAY` rule); the merge itself is one-way, idempotent by `merge_id` and runs only from that block's confirmed link flow (INV-25), never from a player route. The sum a funnel can add is bounded by imports per day times the season caps.

**Validation rule**: `claims.feature` merges a guest twice (same `merge_id`, then another) and checks one result and `already_merged`.

## Disclosure and consumer-protection requirements

These are design obligations, not code paths, and each has a place in `frontend.md`.

- **Before the store sheet opens**, the player sees both tracks in full, the store price, the season end, the unclaimed-rewards rule and the refund rule (INV-18). No "worth", "value" or "save" figure is shown unless it is computed from prices the shop actually charges (INV-26).
- **The fate of unclaimed rewards is disclosed** before purchase under either policy, and under forfeit wherever the loss applies (INV-15). Apple's guideline text says credits or in-game currencies purchased through in-app purchase may not expire ([Apple, 3.1.1](https://developer.apple.com/app-store/review/guidelines/), HIGH for the text); whether an unclaimed pass reward falls under it is not settled by the text (LOW), which is one reason the default is `auto_claim`.
- **Randomized rewards are out of scope.** A randomized reward that can be bought requires odds disclosure before purchase (same page, HIGH); this block holds fixed rewards only.
- **No accidental spends.** The FTC's December 2022 action against Epic Games recovered $245 million in refunds for charges players did not intend, citing a confusing button configuration ([FTC](https://www.ftc.gov/news-events/news/press-releases/2022/12/fortnite-video-game-maker-epic-games-pay-more-half-billion-dollars-over-ftc-allegations), HIGH). Every currency spend has a separate confirm control carrying the price.
- **Time pressure.** EU consumer authorities list time-limited offers as a pressure tactic and the EU coordinated action of 2026-10-15 targets dark patterns and variable rewards (carried from kit guide 06, MEDIUM, not reopened here). The pass shows real remaining time once as a fact, never restarts a countdown, and offers no purchase prompt in the ending-soon banner.
- **Children.** Where the game's age handling (kit interview 4) treats an account as a child's, the premium sheet opens only from the player's own tap and no banner offers it. The legal picture changes quickly; recheck it before launch.

## Input Validation Rules

| Input | Rule |
|---|---|
| `season_id` | `text_short` slug, at most 64 characters, must name a published season; unknown is `season_not_found` |
| `track` | `free` or `premium` |
| `tier` | integer from 1 to N plus `repeat_tier_max`; the cell must hold a reward |
| `items` | at most `MAX_TIERS + REPEAT_TIER_LIMIT` entries per track; duplicates are collapsed |
| `count` | integer 1 to `MAX_SKIP_TIERS_PER_REQUEST`, not past tier N |
| `price_shown` | integer; compared to the server price, never used to charge |
| `boost_code` | a key of `XP_BOOST_CATALOG` |
| `store_transaction_id` | `external_id`, non-empty, at most 255 characters; looked up only through the purchase contract |
| ingest `event_id` | non-empty `external_id`, at most 255 characters |
| ingest `source` | a key of `XP_SOURCES` |
| ingest `units` | integer 1 to the source's `max_units_per_event` |
| ingest `attempt_id` | non-empty `external_id`, at most 255 characters; present exactly when the source has `requires_attempt` |
| Any extra field | rejected with `invalid_request` (player API) or `invalid_event` (ingest) |

## Secrets Management

- `INGEST_SERVICE_CREDENTIAL` lives only in server configuration and the callers' secret stores. It is not in any client bundle, repository or log.
- No store secret exists in this block: the purchase contract holds receipt-verification credentials.

## Logging and Privacy

Log error codes, tenant id, account id (an opaque id, never an email or display name), season id and `event_id`. Do not log service credentials, store receipts, or request bodies of purchase confirmation beyond the `store_transaction_id`. When an account is erased (`compliance.account-deletion`) or a guest account is purged (`auth.guest-account`), `deleteAccount(account_id)` removes its `season_progress`, `xp_events`, `tier_claims`, `season_purchases` and `account_merges` rows and is safe to repeat; ledger entries follow `billing.virtual-currency`'s rule.
