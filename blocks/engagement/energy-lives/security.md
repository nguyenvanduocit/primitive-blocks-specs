# Security — Energy and Lives

> The counter limits play and carries money-adjacent paths (refills charge a ledger, ads and gifts grant value). The threats are: tampering with time, spending the same point twice, free play through the refund path, forged rewards, a refill that charges without delivering, and design that pressures players to pay. Each threat lists its impact, its mitigations and the validation rule a test can check. Confidence labels follow the repo convention; sources are in the README.

## Authorization Invariants

| ID | Invariant |
|----|-----------|
| A-1 | `account_id` and `tenant_id` come from the verified session for every player route (INV-17). The one other source of an account id is a verified ad callback, and it can only receive a grant. |
| A-2 | An attempt, refill or gift is addressed by an id that is unique per account. Another account's id answers 404, not 403, so ids cannot be probed. |
| A-3 | Players never choose prices, units, costs, ceilings or durations. Those come from config versions and offers on the server; `expected_cost` is a guard that can only stop a charge, never raise or set one. |
| A-4 | `publishMeterConfig`, `grantEnergy`, `grantBoost`, `mergeAccounts` and `attemptState` are in-process or admin-only; no player route reaches them. |
| A-5 | Every write is attributable: attempts and entries carry server timestamps; entries carry `reason`, `source_ref` and the idempotency key. |

## Threat Model

### T-1. Clock manipulation

**Attack**: the player moves the device clock forward to make timers elapse, back to extend a boost, or replays requests with a forged timestamp. A community answer reports that one big casual game's life timer follows the device clock (LOW: search summary of a community thread, not opened), which is the weakness this block removes.

**Impact**: MEDIUM. Free points and free boost time; the same trick on a server-trusting design gives unlimited play.

**Mitigations**:
- Every timer input is the server clock, read once per atomic unit (INV-12). No request field carries a time that the block reads.
- The client countdown uses a monotonic source and the server's absolute instants; no client code increments a value (`frontend.md`).
- A backwards server clock cannot reduce a value or extend a timer: the unit uses `max(now, anchor_at, updated_at)`.
- Several app instances read the instant from one source or hold a stated skew, so write order is not ambiguous.

**Validation rule**: a test sends every endpoint with a forged `X-Client-Time` header and a `client_ts` months ahead and gets the same results; a test with the server clock stepped back by an hour changes no value.

### T-2. Double spend, replay and races

**Attack**: two devices or a scripted client send many starts at once for the last point; a captured start request is replayed; a client reuses an attempt id with another meter.

**Impact**: HIGH for fairness and revenue; the meter is the product.

**Mitigations**:
- Read, settle, advance, check and write are one atomic unit per meter row (INV-4): row lock or compare-and-swap on `revision` with bounded retries.
- `available >= cost` is checked inside the unit, and `value` has a CHECK `>= 0`.
- `attempt_id` is unique per account; replays return the stored attempt; a different meter under the id is `attempt_conflict` (INV-5).
- In `on_fail`, reservations make concurrent starts on one point fail at start rather than at finish.

**Validation rule**: a concurrency test with two simultaneous starts on value 1 yields exactly one 201 and one 409, on Postgres, SQLite and the third stack; the value is never negative after any interleaving.

### T-3. Free play through the refund path

**Attack**: start (charged), play the session without calling confirm, call cancel with `start_failed`, receive the point back. Repeated, this is unlimited play at the price of one point.

**Impact**: MEDIUM. It defeats the pacing but not the economy when the rewards are protected.

**Mitigations**:
- Reward-paying blocks accept an attempt only in `confirmed`, `won` or `failed` through `attemptState` (INV-13). Play that was never confirmed earns nothing and reports no score.
- Cancel is allowed only while `open`, which ends at `CONFIRM_TIMEOUT_SECONDS` (default 120) or at the first confirm.
- At most `START_REFUND_LIMIT_PER_DAY` refunds apply per account and `day_key`; further ones end `expired` with `refund_denied`.
- Where the level or session payload comes from the server, release it only after confirm. Then play without confirm has nothing to play.

**Residual risk (stated, not hidden)**: when the level data ships inside the app and the session needs no server payload, a player can play offline of the protocol up to the refund limit per day for no reward. The rewards stay protected; the pacing does not. This is an extrapolation (MEDIUM): no source measures this abuse.

**Validation rule**: a test starts, never confirms, cancels, and checks that `attemptState` reports `cancelled` and that the 11th refund of the day is `expired` with `refund_denied = daily_limit`.

### T-4. Forged, replayed or amplified ad rewards

**Attack**: the client claims a reward it never earned; a captured server callback is sent again; a callback is edited to raise `reward_amount`; `user_id` names someone else; the daily cap is bypassed by spreading across accounts.

**Impact**: MEDIUM. Free points; ad revenue is paid per verified view, so forged grants cost the game revenue it has not earned.

**Mitigations**:
- The grant starts only at the ad network's server-to-server callback. For AdMob (HIGH, [AdMob SSV](https://developers.google.com/admob/android/ssv)) the signature is ECDSA with SHA-256 over every query parameter before `&signature=`, exactly as received; keys are fetched from the network's key file and cached at most 24 hours because they rotate. Re-serializing or re-ordering the query before verifying breaks the check and is a bug.
- `transaction_id` is the replay key: `energy-lives:{account_id}:ad:{transaction_id}`. The network's page does not say how to guard replay (HIGH that it is silent), so this block does.
- Units come from `AD_GRANT_UNITS`; `reward_amount` is never used.
- `user_id` is set by the client; an unknown account is refused. A forged `user_id` can only gift points to another account, and each point still needs a signed callback.
- `AD_GRANTS_PER_DAY` per account and `day_key` bounds a farm per account. It does not bound many accounts; that is the same exposure as any per-account reward (LOW: no data).

**Validation rule**: the cases `ad-forged-signature` and `ad-unknown-user` in `fixtures/meter-config.json` grant nothing; a repeated valid callback grants once; the sixth grant of a day is `daily_limit`.

### T-5. Gift farming and unsolicited gifts (optional extension)

**Attack**: many accounts befriend each other to pass points around, or a harasser floods a recipient's inbox.

**Impact**: LOW to MEDIUM.

**Mitigations**: a friend link older than `GIFT_MIN_FRIEND_AGE_SECONDS`; `GIFTS_SENT_PER_DAY` per sender; one gift per pair per `day_key`; `GIFT_INBOX_MAX` per recipient; recipient opt-out; expiry; one uniform `gift_not_available` for opt-out, non-friend and too-new link so the answer discloses nothing; no request route (a request puts an obligation on a friend, guide 06). Gifts claim through the idempotent `grantEnergy` and respect the ceiling.

**Validation rule**: the friend-link cases in `fixtures/meter-config.json` (an old link accepted, a new link refused with the same body as an opt-out).

### T-6. A refill that charges without delivering, or delivers without charging

**Attack or failure**: a crash between the ledger spend and the meter credit; a client retry after a timeout; a tampered `expected_cost`; a double tap.

**Impact**: HIGH. Money moves.

**Mitigations**:
- The pending entry is durable before the spend; the spend precedes the credit; the credit and the status change are one transaction (INV-7).
- Both the ledger and the entry table are idempotent on `energy-lives:{account_id}:refill:{refill_id}`; a retry or re-drive charges once.
- A pending entry is re-driven on reads and never abandoned. An undeliverable one is refunded by a ledger grant `energy-lives.refill-refund`.
- The price is computed on the server; the client's `expected_cost` can only abort with `price_changed`.
- Nothing is charged at or above the cap.

**Validation rule**: `refill-crash-after-spend` in `fixtures/api-cases.json` ends with value 5 and one ledger spend; a refill at the cap charges nothing.

### T-7. Cross-account and cross-tenant access

**Attack**: reading or acting on another account's meter or attempt by guessing ids or by putting another `account_id` in a body.

**Impact**: HIGH.

**Mitigations**: A-1 and A-2; every query filters by `tenant_id` and `account_id` from the session; unique keys include the tenant; responses never include another account's data; `attemptState` is in-process only and takes the account id from the caller block, which got it from the session.

**Validation rule**: a request for account B's attempt id as account A is 404; a body carrying `account_id` is ignored.

### T-8. Config tampering and back-dating

**Attack or failure**: an admin or a compromised tool edits a version in place or publishes a version dated in the past, changing values players already saw (a cap cut that removes points, an interval change that erases progress).

**Impact**: MEDIUM to HIGH (player trust).

**Mitigations**: append-only versions with no UPDATE or DELETE path; `effective_at` at or after the server's now at publication; admin authentication and an audit trail; a lint line `cap / regen_amount * regen_interval_seconds` shown to the approver; a second reviewer for any version that lengthens the longest wait or lowers the cap (guide 12, rule 14 asks for owners and reviewers on the live calendar).

**Validation rule**: publishing with `effective_at` one second in the past fails; a lowered cap leaves held points intact (`cap-lowered-keeps-units`).

### T-9. Offline queue abuse

**Attack**: a modified client queues many sessions, claims impossible start times, or resends a batch.

**Impact**: MEDIUM.

**Mitigations**: `OFFLINE_ATTEMPTS` is off by default; the queue is bounded by `OFFLINE_MAX_ATTEMPTS` (a larger batch is `invalid_request`); the server runs each attempt at its own now and ignores any client time; an unaffordable attempt is `rejected` and final; rewards need a confirmed attempt (INV-13); batches are idempotent per attempt id.

**Validation rule**: `offline-queue-overdraft` in `fixtures/api-cases.json`.

### T-10. Read amplification and load

**Attack**: hammering `GET /api/energy`, which may write when something is due, or the reconcile route.

**Impact**: LOW to MEDIUM (cost, contention on one meter row).

**Mitigations**: a read that only advanced the meter writes nothing (INV-2); settlement writes happen once per due item; per-account rate limits (`RATE_LIMIT_PER_MINUTE`); bounded retries on revision conflicts; the pending re-drive is capped per read (`REDRIVE_MAX_PER_READ`); a request body size limit; the batch length limit.

**Validation rule**: 1,000 reads of an untouched meter produce zero updates; the 429 body carries `retry_after_seconds`.

### T-11. Pressure design and harm to minors

**Attack or failure**: the counter is tuned or presented so that waiting feels punitive and the paid refill feels necessary; paid prompts reach children.

**Impact**: HIGH legally and reputationally. Regulators attach to deception and to children, not to the mechanic itself (guide 06, rule 1). The EU network's Star Stable assessment lists time-limited purchase pressure on children among harmful practices (MEDIUM, law-firm summary); guide 12, rule 13 bars any experiment arm that raises price pressure, scarcity or spend prompts for minors or accounts of unknown age, and any arm targeted by vulnerability signals such as spend spikes or long late-night sessions.

**Mitigations**: the ethical floor INV-15 and INV-16; paid refill off for accounts flagged `is_minor` and the flag defaults to "unknown means minor" in adopter policy where the adopter cannot tell (a design recommendation, MEDIUM); no countdown or urgency on offers (`frontend.md`); the `source` of every refill is recorded so the team can see whether energy is the only reason players pay; test accounts and the QA clock are enforced on the server and excluded from metrics; wait length and refill price never vary with an account's spend history, segment or risk signals (INV-18): config versions have no account column, `publishMeterConfig` accepts no account selector, and the quote reads only the offer, the version and the meter's own state. Guide 15 lists this as E3 for energy (`kits/game-engagement/guides/15-manipulation-and-the-line.md`).

**Validation rule**: with `is_minor` true and `PAID_REFILL_FOR_MINORS` false, the offers list marks every paid offer `not_for_minors` and a direct refill returns `refill_not_available` with no ledger call; the empty sheet in that state shows no paid row. Two accounts in the same meter state, one with a long purchase history and one with none, receive identical offers, costs and `full_at`; a version published with an `account_id` or `segment` field is refused (`refill-paths.feature`, `config-change.feature`).

## Input Validation Rules

| Field | Rule | Failure |
|-------|------|---------|
| `attempt_id`, `refill_id`, `gift_id`, `merge_id` | match `ID_PATTERN` (`^[A-Za-z0-9_-]{2,64}$`) | 422 `invalid_request` |
| `meter_code`, `offer_code` | slug, 2 to 32 characters, must exist for the tenant | 404 `unknown_meter` / `unknown_offer` |
| `outcome` | one of `win`, `fail`, `abandon` | 422 |
| `reason` on cancel | exactly `start_failed` | 422 |
| `expected_cost` | integer >= 0 and below a sane ceiling (10,000,000) | 422 |
| `amount`, `seconds` (in-process) | positive integers; `amount` below the ceiling plus `OVERFILL_MAX` is applied, the rest reported | 422 |
| Reconcile batch | at most `OFFLINE_MAX_ATTEMPTS` items, no duplicate ids | 422 |
| Ad callback | query has `signature` last and `key_id` before it; `transaction_id` is hex; sizes bounded | refused, nothing granted |
| Config publication | `cap >= 1`, `overfill_max >= 0`, `regen_amount >= 1`, `regen_interval_seconds >= 1`, `attempt_cost >= 1`, `effective_at >= now` | 422 |
| Request body | JSON object, size below an adopter limit | 413 or 422 |

## Auth / Authz

Player routes need the session of `auth.google-login`, `auth.sign-in-with-apple` or the project's own auth (guest accounts included). Admin and in-process operations are never reachable from the player surface. The ad route authenticates by signature, not by session.

## Tenant Isolation

Every table has `tenant_id`; every unique key and lookup includes it; the tenant comes from the session or the verified callback's account record, never from the request. Idempotency keys are unique within (`tenant_id`, `account_id`).

## Logging and Privacy

Log ids, states, error codes and amounts. Do not log request bodies wholesale, bearer tokens, or the signature of an ad callback together with its full query. Energy events carry `account_id` (a pseudonym that still counts as personal data, guide 12 rule 3) and no free text. Account deletion erases every row of the five tables and the gift tables (`compliance.account-deletion`).

## Secrets Management

The block holds no secret of its own. The ad network's verification keys are public keys. Credentials of the ledger client and the admin API belong to the surrounding project, in its secret store, never in client bundles, fixtures or this block.
