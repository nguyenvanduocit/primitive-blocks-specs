# Security: Subscriptions

Source keys (`[SA5]`, `[SG18]`) are in the README Sources table. The shared store receivers belong to `billing.virtual-currency`; their verification contract is restated in T1 so this block can be reviewed alone, and the owner block is the source of truth.

## Threat Model

### T1: Forged store notification

**Attack**: An attacker posts a fake "subscribed" or "renewed" message to the notification URL to grant themselves VIP.

**Impact**: HIGH. Free entitlement and stipends.

**Mitigation**:
- Apple: the receiver verifies the V2 `signedPayload`, a JWS per RFC 7515 [SA6], with Apple's published roots (the App Store Server Library provides `verifyAndDecodeNotification` and the transaction and renewal-info verifiers in Swift, Java, Python and Node [SA14]); checks `bundleId` against `APPLE_BUNDLE_ID`, `environment` against `ACCEPTED_ENVIRONMENTS`, and `appAppleId` in production. Algorithm and certificate-chain details are the library's; this block never parses a notification without them.
- Google: the receiver authenticates the Pub/Sub push by the signed JWT in the `Authorization` header: signature checked against Google's public certificates, `email` equal to the configured push service account with `email_verified` true, `aud` equal to the configured audience, `iss` `https://accounts.google.com`; tokens can be up to an hour old [SG18].
- Google messages carry only a purchase token and a type. Even an authentic-looking forged message cannot grant anything: the handler fetches the state from the Play Developer API with its own credentials (`backend.md` section 3). A forged message costs one rate-limited fetch.
- The handler refuses to run on a message the receiver did not verify; it has no HTTP route of its own.

**Validation rule**: a test posts an Apple payload with a broken signature and a Google push with a wrong audience; both change nothing and answer non-2xx at the receiver.

### T2: Replayed or duplicated message

**Attack / failure**: Apple retries five times at 1, 12, 24, 48 and 72 hours in production [SA5]; Pub/Sub delivers at least once and may redeliver [SG18]; an attacker replays a captured genuine message.

**Impact**: MEDIUM. Double processing, wrong state, double stipends.

**Mitigation**: event rows unique per (`platform`, `event_id`) with a terminal-outcome check; terms unique per `store_transaction_id`; stipend slices unique and ledger-keyed (INV-4). A replayed genuine message carries an old `signedDate` and loses to the guard (T3).

**Validation rule**: `fixtures/store-events.json` sequence `apple_duplicate_delivery` changes state once.

### T3: Out-of-order or stale data overwrites newer state

**Attack / failure**: A late `AUTO_RENEW_DISABLED` flips a renewed subscription back to canceled; a late fetch result removes a just-granted entitlement; a stale `RENEWED` revives an expired chain. Pub/Sub does not order messages by default [SG18]; Apple's notification history shows state at send time [SA12].

**Impact**: HIGH. Wrongly removed or wrongly kept access.

**Mitigation**: state from snapshots (INV-2); `snapshot_at` monotonic with a compare-and-swap on `revision` (INV-3); terminal states leave only through a new transaction or an Apple refund reversal (INV-7); Google revocation is sticky because the store reports a revoked subscription as expired [SG3].

**Validation rule**: sequences `apple_out_of_order_renewal_flag`, `google_concurrent_refresh_older_result_loses` and `google_revoked_cannot_be_undone_by_expired_fetch`.

### T4: Purchase proof theft: claiming someone else's subscription

**Attack**: An attacker obtains a victim's purchase token (Google) or signed transaction (Apple) and calls claim or restore to attach the subscription to their own account, or to move it away from the victim.

**Impact**: MEDIUM. The attacker gets perks the victim paid for; the victim loses access.

**Mitigation**:
- The proof is verified with the store, and the chain's echoed account token must not belong to another account unless the transfer path is taken (`bindDecision`, `backend.md` section 4.1).
- Transfers need an explicit confirmation, respect `TRANSFER_COOLDOWN_DAYS`, and notify the previous account, so the victim learns of the move and can react.
- Claims and restores are rate limited per account (`CLAIM_RATE_LIMIT_PER_HOUR`); proofs and chain references are never logged; errors do not reveal whether another account holds a chain.
- Transaction identifiers are not secrets: Apple's API accepts any transaction id of the customer [SA10] and they appear on receipts (inference, MEDIUM); that is why the Apple proof is the signed transaction verified through `verify_apple_transaction`, not an id.

**Residual risk**: a stolen bearer proof can still win one transfer per cooldown. Accepted; the notification and the cooldown bound it.

**Validation rule**: scenarios in `purchase-restore-linking.feature` tagged `@security`.

### T5: Client-asserted or tampered entitlement

**Attack**: A modified client claims VIP, or edits the cached entitlement, to unlock perks that other players or the server see.

**Impact**: HIGH for server-side perks; LOW for purely local cosmetics.

**Mitigation**: the server never accepts an entitlement from the client (INV-1); all perks that reach other players or the ledger call `entitlement`; the client cache is a display hint. A purely client-side perk can be bypassed by a rooted device, which is the accepted limit of any client-side gate (the same limit `billing.in-app-purchase` documents).

### T6: Sandbox and test purchases accepted in production

**Attack**: Someone makes free sandbox subscriptions (a public TestFlight build, a Google license tester) and presents them to the production server.

**Impact**: MEDIUM. Free VIP; free stipend currency.

**Mitigation**: `environment` is checked on every payload and fetch; sandbox chains are stored with `environment = sandbox`; no stipends for them unless `SANDBOX_STIPENDS`; `ACCEPTED_ENVIRONMENTS` can be set to `production` after approval, when no review is pending. Apple review purchases use the sandbox [SA23, LOW], which is why the default accepts it.

### T7: Stipend granted twice

**Attack / failure**: Two workers, a crash between the ledger call and the row update, or a rebind to another account re-grants a slice.

**Impact**: HIGH for the economy; the faucet is currency.

**Mitigation**: one row per slice (unique); ledger key `subscriptions.stipend:{platform}:{store_transaction_id}:{slice_index}` without an account id; a replay with equal arguments returns the original result, and a different account answers `idempotency_conflict`, which the runner records as `already_granted` (`backend.md` section 5.2).

**Validation rule**: `stipends.feature` replay and rebind scenarios.

### T8: Refund farming and chargebacks

**Attack**: Subscribe, collect the stipend, refund or charge back, repeat on new store accounts.

**Impact**: MEDIUM. Currency leaves the game for a refunded payment.

**Mitigation**: refunds revoke the term and skip its pending slices (`backend.md` section 6); optional `STIPEND_REVERSAL = spend_clamped` debits what the balance still holds; `STIPEND_HOLD_AFTER_REVOKES` holds an account after repeated revocations; free trials grant no stipend by default. Apple lets customers request refunds in the store and sends `REFUND` with a reason [SA1]; no source quantifies abuse rates.

**Residual risk**: the first slice is granted at term start, so a refund after spending it is not recoverable except by the clamped debit. Accepted; tune the stipend amount against the price.

### T9: Credential leakage

**Attack**: The App Store Server API private key, the Google service-account key, or the Pub/Sub audience leaks through the repo, logs or a bundle.

**Impact**: HIGH. An attacker can read subscriber data and call store APIs, including Google's revoke and Apple's renewal-date extension [SG6, SA13].

**Mitigation**: keys live in the server secret store, never in the client bundle or the repo; the Google service account has the minimum Play Console permissions the sibling blocks list (view app information, view financial data, manage orders and subscriptions); `chain_ref` is stored as a credential and is not selectable by any client endpoint; logs carry event ids and outcome codes only.

### T10: Account token leaks identity

**Attack / failure**: The token sent to the store reveals an email or account id; Google blocks purchases when PII is in the field [SG16].

**Impact**: LOW to MEDIUM.

**Mitigation**: the token is a random UUID, unrelated to any account attribute (INV-17); one per account; at most 64 characters on Google [SG16].

### T11: Account deletion leaves billing active

**Failure**: A player deletes the game account and keeps paying the store.

**Impact**: MEDIUM. Money lost and a likely chargeback.

**Mitigation**: the deletion flow of `compliance.account-deletion` shows the manage-subscription link and states that the store subscription continues until canceled (`backend.md` section 4.3); the chain is detached, not deleted, so late store messages still resolve.

### T12: Deceptive subscription presentation

**Attack / failure**: Hidden renewal terms, a trial that converts without notice, a hidden close button, or a recurring charge named "Free Trial".

**Impact**: HIGH. Apple removes apps that "trick users into purchasing a subscription under false pretenses" [SA15]; Google disallows "deceptive or manipulative purchase experiences" and lists the violations above [SG12]; the FTC's December 2022 order against a game publisher cited dark patterns that led to unwanted charges (kit guide `06-design-ethics-and-compliance.md`, MEDIUM [SK1]).

**Mitigation**: the disclosure and no-dark-pattern rules of `frontend.md` section 1 (INV-14); `paywall-disclosure.feature`.

### T13: Handler load and endpoint abuse

**Attack**: A flood of genuine-looking claims, refreshes or redeliveries to exhaust store API quota.

**Impact**: MEDIUM. Store API quotas and latency.

**Mitigation**: per-chain refresh interval (`REFRESH_MIN_INTERVAL_SECONDS`), per-account claim limit, bounded read-through timeout, receivers answer only after durable storage; event rows hold no payload and follow the project's retention.

### T14: Entitlement kept past a real end

**Failure**: `ENTITLEMENT_LAG_ALLOWANCE_SECONDS` keeps access while the store is unreachable, so a cancellation or refund that happened during an outage grants up to the allowance of extra access.

**Impact**: LOW. Bounded by the allowance (default one hour).

**Mitigation**: the allowance applies only when the refresh fails, only past `expires_at`, and never to `retry`, `paused`, `expired` or `revoked`.

## Validation rules

| Input | Rule |
|---|---|
| `account_id` | From the session only; never read from a body |
| `plan_code` | Must match an active plan |
| `proof` | A JSON object with exactly one of `signed_transaction` or `purchase_token`; strings up to 16 KiB; verified with the store before any use |
| `proofs` | At most 20 entries per restore |
| `confirm_transfer` | Boolean; false when absent |
| Store messages | Handled only after the receiver verified them; `bundleId` or `packageName` and `environment` checked again by the handler |
| Dates and amounts | Read from the verified snapshot; never from the client |
| Stipend amount | Integer > 0 from the catalog; the ledger enforces its own bounds |
| Token | Random UUID text; compared exactly |

## Auth/authz

- Client endpoints: a session; every query filters by the session's `account_id` and `tenant_id`.
- The handler: reachable only through the receivers of `billing.virtual-currency`; no route, no secret of its own.
- Store APIs: Apple App Store Server API with a signed JWT (issuer id, key id, private key) [SA14]; Google Play Developer API with the service account scope `https://www.googleapis.com/auth/androidpublisher` [SG5].
- Operator tools that revoke or extend (`subscriptionsv2.revoke`, Apple renewal extension) run from an operator console with its own authorization, not from client endpoints.

## Secrets management

| Secret | Where | Never |
|---|---|---|
| App Store Server API private key, key id, issuer id | Server secret store | In the client bundle, the repo, logs |
| Google service-account key | Server secret store (shared with `billing.virtual-currency`) | In the client bundle, the repo, logs |
| Pub/Sub push audience and the expected service-account identity | Receiver configuration | In the client |
| `chain_ref` (Apple `originalTransactionId`, Google purchase token) | Database column, treated as a credential | In logs, responses, analytics |
| Store account tokens | Database; sent to the store by design | Derived from PII |
