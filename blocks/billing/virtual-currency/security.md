# Security: Virtual Currency

A virtual currency is money-adjacent state. The attackers are players who want free currency, players who want their money back and keep the goods, other people's purchase proofs in transit, and anyone who can reach the two store receivers. Each threat below carries its attack, impact, mitigation and a rule a test can check.

## Threat Model

### T1: Forged purchase proof

**Attack**: A client sends a made-up Apple JWS or Google purchase token to `POST /api/purchases/verify`, or edits a real one (another product, a larger quantity, another bundle).

**Impact**: HIGH. Free hard currency, the game's main revenue line.

**Mitigation**:
- Apple: verify the JWS chain to a pinned Apple root certificate, then `bundleId` and `environment`, then confirm the transaction with Get Transaction Info and use the confirmed fields (`backend.md` section 4). Pin the accepted signature algorithm after inspecting a sandbox transaction.
- Google: ask the Developer API for the token's state under the app's package name (`backend.md` section 5). A token for another app or a made-up token fails there.
- The grant amount comes from the server catalog by store product id. The proof's `quantity` above `MAX_PURCHASE_QUANTITY` is rejected (INV-8).
- Failed verification writes no row and answers `proof_invalid`; the response never says which check failed.

**Validation rule**: a JWS with one altered payload byte, a JWS signed by a different key, a token for another package, and a made-up token each answer `proof_invalid` and leave ledger and purchases unchanged (`pack-purchase.feature`).

### T2: Replay of a valid proof

**Attack**: The same transaction is submitted twice (a retry, two tabs, a deliberate loop) to get the pack more than once.

**Impact**: HIGH.

**Mitigation**:
- UNIQUE (`tenant_id`, `store_transaction_id`) on `store_purchases`; the grants for a purchase use keys derived from the purchase id, so a replay finds the row and answers the original result (INV-4, INV-9).
- Record and grants commit in one transaction; two concurrent submissions serialize on the unique index and the account row lock.
- Notifications are deduplicated by Apple `notificationUUID` and Google `messageId`, and each notification still ends in the same idempotent recording step.

**Validation rule**: ten concurrent submissions of one proof credit the pack once and all return the same `purchase_id` (`pack-purchase.feature`).

### T3: Claiming someone else's purchase

**Attack**: A leaked or intercepted proof is submitted from the attacker's session to receive the grant.

**Impact**: MEDIUM. The victim loses a purchase they paid for; the attacker gains it.

**Mitigation**:
- The store echoes the random account token set at purchase time; the grant goes to the account that owns that token, whichever session submits (`backend.md` section 3). A submitter who is not the owner receives `beneficiary: other_account` and no balance data.
- Proofs are bearer material: never logged, never returned in a response, never stored beyond `store_transaction_id`.
- Without an echoed token (offer-code redemption, an older build) the submitting session is used (`ACCOUNT_TOKEN_MISSING_POLICY = bind_to_session`), so a leaked tokenless proof is claimable by its first submitter. Accepted risk, bounded by the proof's short useful life; `reject` closes it at the cost of undelivered tokenless purchases.

**Validation rule**: a proof echoing account A's token submitted by account B credits A and shows B only `other_account`.

### T4: Wrong app or wrong environment

**Attack**: A transaction from a different app, or a sandbox or test purchase, is presented to the production server to obtain currency without paying.

**Impact**: MEDIUM.

**Mitigation**:
- `bundleId` (Apple) and the package name in the API path (Google) must match the configuration.
- `environment` is checked. Sandbox and license-tester purchases are accepted only when `APPLE_ACCEPT_SANDBOX` or `GOOGLE_ACCEPT_TEST_PURCHASES` is true, are recorded as `sandbox`, and are excluded from revenue reports. They exist for App Review, TestFlight and testers (the sandbox claim for App Review is LOW evidence, `README.md`); a store-live deployment that does not need them sets both to false.
- Only the store can produce a sandbox transaction that verifies, so the exposure is the tester population.

**Validation rule**: with `APPLE_ACCEPT_SANDBOX = false` a verified sandbox transaction records `rejected` / `environment_not_accepted` and grants nothing.

### T5: Spoofed store notifications

**Attack**: Someone posts a forged `REFUND` to remove another player's currency, a forged `ONE_TIME_CHARGE` to mint currency, or floods the receivers.

**Impact**: HIGH.

**Mitigation**:
- Apple: the body is a signed payload; verify it as in T1 before any parsing of its contents, check `data.bundleId` and `data.environment`, and answer 401 without logging the payload.
- Google: the Pub/Sub push request carries a Google-signed JWT; verify the signature, require `email` equal to the configured push service account, `email_verified` true and `aud` equal to the configured audience ([Pub/Sub push authentication](https://docs.cloud.google.com/pubsub/docs/authenticate-push-subscriptions), HIGH). Require `packageName`.
- Notifications are hints. Every state change comes from a fresh read of the store (Apple Get Transaction Info; Google `productsv2` and the Voided Purchases API), so even a valid notification cannot set a state the store does not hold.
- Dedupe by notification id; unknown kinds are acknowledged and logged.

**Validation rule**: an unsigned Apple body and a Google push without a valid token answer 401 and change nothing; a validly signed `REFUND` for a transaction the store still shows as unrefunded changes nothing.

### T6: Double spend and overdraft races

**Attack**: Two requests spend the same balance at once (two devices, a scripted burst) to buy more than the player holds.

**Impact**: HIGH. Negative balances break every report.

**Mitigation**: the spend is a conditional decrement (`balance >= amount`) in the same transaction as the entry insert; a CHECK `balance >= 0` and a CHECK `balance_after >= 0` back it; the unique key makes twins resolve to one entry (`backend.md` section 1).

**Validation rule**: ten concurrent spends of 70 from 100 with distinct keys apply exactly one; the balance is 30 (`ledger.feature`).

### T7: Client-driven ledger writes and amount tampering

**Attack**: A modified client calls a grant endpoint, or sends an amount, a currency or a reason of its choice.

**Impact**: HIGH.

**Mitigation**: no endpoint grants or spends for a client (`backend.md`, API Endpoints). `grant` and `spend` are in-process calls made by other blocks' server code with reasons and keys they build from server-side facts. The client names a product code, never an amount. The registry rejects a reason that is not registered for the currency and direction (INV-7).

**Validation rule**: a search of the route table finds no path that reaches the ledger writer from a client request except the verify handler; a body field named `amount` is ignored.

### T8: Refund abuse

**Attack**: Buy a pack, spend it, then have the store refund the purchase (or dispute it) and keep the benefit.

**Impact**: MEDIUM per incident; HIGH if systematic.

**Mitigation**:
- Refunds are detected from Apple `REFUND` and Google voided-purchase notifications and from polling (`backend.md` section 13); Google advises more frequent polling after a void so clawback lands before the player spends ([Google, security](https://developer.android.com/google/play/billing/security), HIGH).
- Clawback removes `min(balance, granted)`; the unrecovered part is recorded and reported. No debt or negative balance (INV-15).
- `REFUND_REVIEW_THRESHOLD` refunded purchases in the window switch the shop to the `review` hold; delivery of purchases the store already confirmed continues (INV-12).
- A refunded purchase keeps consuming the first-purchase bonus and the starter offer (T10).
- A refund an operator initiates for spend a guardian did not authorize (`refund_reason` `operator:unauthorized`) does not count toward the review hold, so the victim is not penalized.
- Apple's consumption data (consented, section 11 of `backend.md`) lets Apple see how much was spent; the preference option can ask Apple to decline a refund of a fully consumed purchase.

**Validation rule**: after a refund of a half-spent pack, the balance is zero or higher, never negative, and `shortfall_total` equals granted minus clawed (`refund-and-clawback.feature`).

### T9: Finish ordering (lost purchases and free grants)

**Attack / failure**: The server consumes a Google purchase before the grant commits and crashes, or never acknowledges and Google refunds after three days while the player keeps the currency; the client finishes an Apple transaction early and the purchase is never delivered.

**Impact**: HIGH (lost money for the player, or free currency).

**Mitigation**: commit, then finalize (`backend.md` section 8). Unfinalized Google purchases are retried every `CONSUME_RETRY_INTERVAL_SECONDS` and alert after one day, well inside the three-day window. The client finishes an Apple transaction only when the server says `finish_transaction`. A Google purchase refunded by Google for lack of acknowledgement arrives as a void with reason `unacknowledged_purchase` and is clawed back like any refund.

**Validation rule**: a crash injected between the commit and the consume leaves a verified, unfinalized row that the retry job finalizes; no grant exists without a record.

### T10: Bonus and starter farming

**Attack**: Buy, refund and rebuy to collect the first-purchase bonus again; buy the starter offer repeatedly through a store product page.

**Impact**: LOW to MEDIUM (bounded by the bonus and by the attacker's own spend).

**Mitigation**: eligibility is computed on the server inside the locked transaction from purchases in state `verified` or `refunded`; a refunded purchase still consumes it. A repeat starter purchase is delivered in full (the player paid) and logged `starter_repeat`; the owner can disable store-level promotion of the starter product in the store consoles (a store setting that was not verified here).

**Validation rule**: purchase, refund, purchase of the same product: the second purchase carries no first-purchase bonus.

### T11: Spend-limit bypass and price misreporting

**Attack**: A player (or a child) buys outside the shop, edits the client to under-report the price to the intent check, or waits out a cool-off while a parent is not looking.

**Impact**: LOW for fraud; MEDIUM for player harm.

**Mitigation**: the limit is a self-protection and host-default control, not an anti-fraud control, and the spec says so (`backend.md` section 12). The server counts the Apple payload price when present; purchases made outside the shop are counted after the fact; raising, changing the currency of and removing a limit wait out `SPEND_LIMIT_COOL_OFF_SECONDS` of server time, can be cancelled, and pass the parental gate when the host requires it. For children the stores' own approval flows are the strong control.

**Validation rule**: a raise requested at time t is not in force before t plus the cool-off; a lowering is.

### T12: Purchases by minors

**Attack / risk**: A child buys currency without a parent's consent.

**Impact**: HIGH (legal and reputational).

**Mitigation**: real-money spending is off until the host enables it: with no `purchase_policy` registered `purchases_enabled` is false (`PURCHASES_DEFAULT_WITHOUT_POLICY = off`, INV-28; kit guide 15). The host's `purchase_policy` supplies `purchases_enabled` and `parental_gate_required`; the gate runs before every purchase attempt and before a limit change; `countdown_offers_allowed` can switch off pressure timers (`frontend.md`). Apple's Kids Category rules require purchasing opportunities behind a parental gate ([Apple 1.3](https://developer.apple.com/app-store/review/guidelines/), HIGH). The block does not decide ages; the age and consent design is the host's (kit guide 06, interview 4).

**Validation rule**: with `parental_gate_required = true`, no intent call is made before the gate passes.

### T13: Credential exposure

**Attack**: The App Store Connect API key or the Google service account leaks (repository, build, logs) and is used to read purchases, request refunds with `orders.refund`, or send consumption data.

**Impact**: HIGH.

**Mitigation**: both live in the server's secret store, never in the client bundle, the repository or logs. Scope the Google service account to this app and the Developer API. Rotate on any suspicion. The Pub/Sub audience and service-account email are configuration, not secrets, but a wrong value fails closed (401).

**Validation rule**: a search of the repository and the shipped client bundle finds no private key, service-account JSON or `.p8` content.

### T14: Identity and proof leakage

**Attack / risk**: The store account token, a JWS or a purchase token appears in logs, analytics or URLs; an email or provider id is sent to a store as the account token.

**Impact**: MEDIUM.

**Mitigation**: the token is the account id, a random UUID that `auth.guest-account` defines as not personal data, or a random UUID kept in `wallet_accounts` (`STORE_ACCOUNT_TOKEN_SOURCE`); it is never an email, a provider id or a value derived from them (INV-23); Google rejects personally identifiable information in the obfuscated id and blocks such purchases ([Google, BillingFlowParams](https://developer.android.com/reference/com/android/billingclient/api/BillingFlowParams.Builder), HIGH). Logs carry purchase ids, never proofs. Analytics events carry product codes and no transaction ids.

**Validation rule**: grep of a test run's logs for a marker placed in a signed transaction and a purchase token finds nothing.

### T15: Ledger tampering and drift

**Attack / failure**: An operator or a bug edits balances or entries; a partial manual repair leaves a purchase without grants.

**Impact**: HIGH.

**Mitigation**: append-only guard in the database, one writer, reconciliation of balance versus ledger and of purchases versus grants with alerts and no automatic edits (INV-1, INV-19). A balance that drifts from its ledger is rebuilt from the ledger by an audited operator call; a wrong amount in the ledger is corrected with a new entry with a `virtual-currency.support-*` reason that also appears in the registry and in reports.

**Validation rule**: an UPDATE or DELETE of a ledger row outside erasure fails; a deliberately skewed balance is reported by the next reconciliation run.

### T16: Verify endpoint abuse

**Attack**: A client hammers `POST /api/purchases/verify` so the server exhausts its App Store Server API rate limit (Apple answers 429 `RateLimitExceededError`) and legitimate purchases fail.

**Impact**: MEDIUM.

**Mitigation**: per-account limit `VERIFY_RATE_LIMIT_PER_MINUTE`; a repeated proof for an existing row answers from the database without calling the store; `store_unavailable` answers are retried by the client with backoff.

**Validation rule**: the 31st call in a minute for one account answers `rate_limited`; a replayed proof causes no store call.

## Validation rules

| Input | Rule |
|---|---|
| `amount` (internal calls) | Integer from 1 to `LEDGER_MAX_AMOUNT`; floats, strings, zero and negatives rejected (`invalid_amount`) |
| `reason` | `^[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*$`, registered and enabled for the direction |
| `idempotency_key` | Non-empty, at most `LEDGER_IDEMPOTENCY_KEY_MAX_LENGTH` characters; never logged with an account's full history |
| `currency` | Matches `[a-z][a-z0-9_]*`, exists in `currencies` |
| `product_code` | Exists, active, `fulfilment = ledger` for pack intents |
| `platform` | `apple` or `google` |
| `signed_transaction` | A compact JWS string, at most 16 KiB (design); verified before use |
| `purchase_token` and `product_id` | Strings, token at most 4096 characters (design; Google states no maximum on the pages read); the token is passed only to the Developer API |
| `client_price` | `amount_micros` integer from 1 to 1000000000000; `currency` three uppercase letters; otherwise ignored |
| `limit_micros` | Integer from 1 to 1000000000000 or `null` (remove) |
| Store notification body | Authenticated first; ids deduplicated; state re-read from the store |

## Auth/authz

- Client endpoints: a verified session; `account_id` is read only from the session. A body, query or header carrying another account id changes nothing.
- Receivers: no session; Apple authenticated by the signed payload, Google by the Pub/Sub push token.
- Internal calls (`grant`, `spend`, `balance`, `holders`, `holdings`, `mergeAccounts`, `deleteAccount`, `set_spend_limit`, `record_verified_purchase`): in-process from server modules only; not routable.
- Operator tools (catalog edits, support entries): a separate, audited administrative path.

## Secrets management

| Secret | Where | Never |
|---|---|---|
| App Store Connect API key (`APPLE_PRIVATE_KEY`, key id, issuer id) | Server secret store | In the repo, the client bundle or logs |
| Google service-account key | Server secret store | In the repo, the client bundle or logs |
| Apple root certificates | Server configuration (public data) | Fetched at request time from an untrusted source |
| Pub/Sub audience and push service account | Server configuration | Skipped or defaulted: a missing value fails closed |
| Database credentials | Server secret store; the runtime role cannot UPDATE or DELETE `ledger_entries` | Shared with the erasure routine's role |
