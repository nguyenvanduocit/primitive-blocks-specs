# Security - Daily Streak

> Threats are ordered by what a player can gain: free rewards first, then a free streak, then harm to other players or to the player. Each threat names its mitigation by invariant (`README.md` section 8) and says what the mitigation does not stop. Confidence labels: HIGH (follows from a stated rule or a source), MEDIUM (inferred), LOW (guess).

## Access rules

| Resource | Anonymous | Signed in (own account) | Another account |
|----------|-----------|-------------------------|-----------------|
| `GET /api/streak` | Denied | Read own | Not addressable |
| claim, freeze, repair, timezone, ack | Denied | Write own | Not addressable |
| `play` route | Not present when `PLAY_REPORT_SOURCE = server` | Write own, bounded | Not addressable |
| `recordPlay`, `holdings`, `mergeAccounts`, `deleteAccount`, sweeps | Not routable | Not routable | Internal callers only |

No route takes an `account_id` from a body, query or header (INV-22). Tenant comes from deployment configuration, never from the request.

---

## Threat model

### T-1. Device clock manipulation

**Impact**: High if it worked: free days, free streak length, skipped waits.

**Mitigations (INV-1, INV-18)**: the server computes `day_key` from its own clock and the stored zone. The client sends no date, time or day key; a body that carries `day_key`, `date`, `timestamp` or `claimed_at` is rejected with 422 `unexpected_field`. Countdowns are display only and read the server's `ends_at`. The streak lives only in `streak_states`; it is never part of the client's progress snapshot, so restoring or editing a local backup cannot rewrite it (`data.progress-sync` keeps entitlements and server-owned state out of the snapshot in the same way).

**Not stopped**: a player can still change the device clock and see wrong countdown text until the next refresh; nothing is owed or lost because of it. HIGH.

### T-2. Time-zone hopping

**Impact**: Low to Medium. A player who changes zone near a day boundary can make the calendar date advance sooner than a day of real time, claiming an extra day.

**Mitigations (INV-19)**: changes are rate-limited on the server (`TIMEZONE_CHANGES_PER_WINDOW` per `TIMEZONE_WINDOW_DAYS`, defaults 2 and 30). A change takes effect only when the current local day ends, so it cannot cut the day short or be used to claim twice inside one local day. A zone is accepted only if the server's tz database lists it. A zone moved behind the last credited day gives no claim until the date passes it (`not_available_yet`).

**What the bounds do not stop**: each accepted change can advance the calendar by at most two extra dates (zone offsets span 26 hours, UTC-12:00 to UTC+14:00; [Wikipedia: List of UTC offsets](https://en.wikipedia.org/wiki/List_of_UTC_offsets), HIGH for the range; "at most two" is this block's derivation, MEDIUM). With the defaults that is at most four extra day credits in any 30-day window. The cost to the game is a few extra daily rewards; stronger measures (a minimum real-time gap between claims) would block honest players who claim at 23:59 and again at 00:01, so they are not specified.

### T-3. Double claim, replay, two devices

**Impact**: High (free currency).

**Mitigations (INV-3, INV-4, INV-5, INV-6)**: a UNIQUE `(tenant, account, day_key)` on `daily_claims`; the state update is a compare-and-swap on `version` in the same transaction as the claim row; a lost race re-reads and returns the winner's claim; ledger calls use `daily-streak:{account_id}:{day_key}:{line_no}`, so even a second grant attempt for the same claim returns the first result. A test with two concurrent claims must yield one claim row and one set of ledger entries (`claim.feature`).

### T-4. Reward tampering

**Impact**: High. A forged amount is free currency.

**Mitigations (INV-13)**: the client sends no amount, line, price or cycle day. Lines are resolved on the server from `CALENDAR` and stored on the claim row; retries read the row. The calendar is configuration, not client input, and is validated at startup (V1 to V5).

### T-5. Ledger failure, duplicate or lost reward

**Impact**: Medium. A lost reward breaks trust; a duplicate is free currency.

**Mitigations (INV-6, INV-7)**: record then grant; the claim commits before any ledger call; a failed or slow ledger leaves `pending` and the recovery sweep retries with the same keys until `granted`; a permanent rejection sets `failed` and alerts (`RECOVERY_ALERT_MINUTES`). Nothing writes a balance except the ledger.

**Not stopped**: a ledger that violates its idempotency contract (applies one key twice) defeats this block; the contract is owned by `billing.virtual-currency`. MEDIUM.

### T-6. Purchase replay and half-finished orders

**Impact**: Medium to High (double charge, or a charge without a result).

**Mitigations**: `protection_orders` is UNIQUE on `(tenant, account, kind, client_request_id)`, so a retried request is a replay; the `spend` key is built from the order id; a transient ledger error leaves the order `pending` and the sweep completes it with the same key; an order that is invalid after a successful spend is refunded with its own key and ends `refunded`. The ledger refuses a spend below zero (`insufficient_balance`), which ends the order `rejected` without changing the streak.

### T-7. Forged or replayed play

**Impact**: Low to Medium. A modified client could report qualifying play it did not do, or replay one attempt for several days, and claim for free.

**Mitigations (INV-24)**: with `PLAY_PROOF_SOURCE = attempt` (default) a play counts only when `engagement.energy-lives` `attemptState(account_id, attempt_id)` reports `confirmed`, `won` or `failed` for that account; an `open`, `cancelled`, `expired` or unknown attempt proves nothing, so a refunded start earns nothing. A play id counts once ever (UNIQUE `(tenant, account, play_key)`), so one attempt cannot satisfy two days. `action` is validated against `PLAY_ACTIONS`; rows stop at the largest target in use. The default `PLAY_REPORT_SOURCE = server` keeps the route off the client; with `client` the route still needs a proven attempt, which the client cannot forge without defeating the attempt block's own checks.

**Not stopped**: with `PLAY_PROOF_SOURCE = event` the host's play id is trusted as given, so a count is bounded and replay-safe but not verified. A player who truly starts and finishes the minimum attempt each day still earns the reward; that is the intended behavior. For prizes or ranked rewards use server-verified play. MEDIUM.

### T-8. Merge abuse

**Impact**: Medium. A forged merge could move or duplicate a streak.

**Mitigations (INV-21, INV-22)**: `mergeAccounts(from, into, merge_id)` is internal and runs after `auth.guest-account` has verified both accounts and the player confirmed the import; it takes the larger settled streak, never the sum; freezes sum and clip to `FREEZE_CAP`; a merge neither removes nor creates a grant. It is idempotent by `merge_id`: the retired guest row stays as a tombstone, a repeat returns `already_merged` and changes nothing, and a tombstoned guest cannot be merged into a second account. `holdings` is read-only and internal.

**What the bounds do not stop**: when the guest claimed today and the winning row did not, today stays claimable once, one extra reward per merge. HIGH (stated rule).

### T-9. Request flooding and sweeps

**Impact**: Low to Medium. Claim, play and time-zone routes are cheap to hit and the claim path writes.

**Mitigations**: a per-account request limit (`REQUEST_RATE_LIMIT_PER_MINUTE`); a body size limit; `MAX_CAS_RETRIES` bounds work per request; sweeps process bounded batches (100 pending rows, 500 at-risk candidates per run) ordered by age or deadline.

### T-10. Many accounts per person

**Impact**: Medium for the economy. Each account claims its own daily reward and earns its own freezes.

**Not stopped**: nothing in this block ties accounts to a person. Size daily rewards with this in mind (kit guide `03-economy-and-offers.md`), rely on the ledger's and the sign-in block's abuse controls, and never use this block to gate prizes with real value. LOW (general property of open sign-up).

### T-11. Time-zone identifier as personal data

**Impact**: Low to Medium. An IANA identifier is coarse location data.

**Mitigations (INV-23)**: collect it only to compute the day; store it in `streak_states` and `timezone_changes`; delete it with the account; keep it out of client analytics beyond `streak_timezone_changed`, and do not log it with request bodies. State it in the privacy notice.

### T-12. Server clock fault

**Impact**: High while it lasts. A server clock that jumps forward credits future dates and ends streaks; one that jumps back blocks claims.

**Mitigations**: keep servers on synchronized time. A local date differs from the UTC date by at most one day, because every offset lies between UTC-12:00 and UTC+14:00; so the server refuses a claim and alerts when `abs(day_index(day_key) - day_index(UTC date of server_now)) > 1`. A clock that jumped forward by less than a day is not detected by this check and is a monitoring matter. MEDIUM (the bound is arithmetic from the offset range; the check itself is a design choice).

### T-13. Dark-pattern and compliance exposure

**Impact**: Medium to High for store review and consumer-protection action (guide `06-design-ethics-and-compliance.md`).

**Mitigations (INV-14 to INV-18)**: earned protection, a free exit at the point of loss, capped loss prompts and reminders, true countdowns. Startup validation V1 to V3 refuses configurations that would make protection purchase-only. Games with children in the audience set both price pairs to `null`. The review checklist in `acceptance.md` asks the owner to run the three tests of guide 06, decision rule 2, against the shipped copy.

---

## Input validation

| Input | Rule |
|-------|------|
| Any body | Only the keys listed per route; unknown keys give 422 `unexpected_field`; maximum body size 4 KB |
| `timezone` | Exact IANA identifier known to the server's tz database; no offsets, abbreviations, trimming or case folding |
| `action` | One of `PLAY_ACTIONS` |
| `attempt_id`, `client_request_id` | Opaque text, 1 to 64 characters from a safe alphabet; never interpreted (an `attempt_id` is only passed to `attemptState`) |
| `method` | `currency` or `play` |
| `repair` | Only the value `decline` |

## Logging

Log the account id, route, status, error code and `day_key`; never request bodies, reward lines, balances or the time-zone identifier. Alerts carry counts and claim ids, not player data.
