# Backend Patterns: Virtual Currency

> "Backend" is the whole server side: the wallet ledger, the catalog, store verification, notification receivers, refund handling, spending controls, reconciliation and erasure. Everything the client sees about money is decided here.
>
> Snippets are L3 illustrative code with the four markers (`PATTERN`, `PURPOSE`, `REFERENCE`, `ADAPT`) per `docs/SPEC_GUIDELINES.md` section 6; SQL snippets carry `REFERENCE` and `ADAPT`. The behavior (WHAT) is in the prose around each snippet.
>
> **External contracts kept concrete** in this file: Apple App Store Server API paths and hosts, `JWSTransactionDecodedPayload` and notification field names, `notificationType` values, the retry schedule; Google Play Developer API paths, `productsv2` fields and enum names, RTDN field names and the three-day acknowledge window; the Pub/Sub push acknowledgement codes. Each carries its source and label in `README.md` section 7 ("Store constants") or inline. Merchant projects do not choose them. Table and column names are this block's own contract and are concrete too.

## API Endpoints

Client endpoints require a verified session; the session supplies `account_id` and the handlers ignore any account id in a body, query or header. Errors are `{ "error": "<code>" }`.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/wallet` | Balances, unseen refund notices, `server_now` |
| `GET` | `/api/wallet/history` | The account's ledger entries, newest first, cursor paged |
| `GET` | `/api/shop/packs` | Catalog, eligibility, store account token, spend limit state, purchase policy |
| `POST` | `/api/purchases/intent` | Pre-purchase check: policy, review hold, spend limit |
| `POST` | `/api/purchases/verify` | Submit a store proof; verify, record, deliver |
| `GET` | `/api/purchases/recent` | The account's latest purchases with state and amount charged |
| `GET` | `/api/spend-limit` | Limit in force, spent, remaining, pending change |
| `PUT` | `/api/spend-limit` | Set, lower, raise, change currency of, or remove (`{ "limit_micros": null }`) the limit |
| `DELETE` | `/api/spend-limit/pending` | Cancel a pending change |
| `PUT` | `/api/wallet/consumption-consent` | Record the player's consent to send refund-request consumption data to Apple |
| `POST` | `/api/wallet/refund-notices/seen` | Mark refund notices as seen |
| `POST` | `/api/store/apple/notifications` | App Store Server Notifications V2 receiver (no session; authenticated by the signed payload) |
| `POST` | `/api/store/google/notifications` | Pub/Sub push receiver for real-time developer notifications (no session; authenticated by the push token) |

There is no endpoint that grants, spends or edits a balance for a client. `grant`, `spend`, `balance`, `record_verified_purchase`, `verify_apple_transaction`, `purchase_record`, `set_spend_limit` and `register_notification_handler` are in-process calls (`README.md` section 6).

### `GET /api/shop/packs?platform=apple|google`

```json
{
  "server_now": "2026-10-27T12:00:00Z",
  "store_account_token": "7d0c6c1e-4e5d-4c1e-9a43-0f2b7e6d9a10",
  "purchase_policy": { "purchases_enabled": true, "parental_gate_required": false, "countdown_offers_allowed": true, "reason": null },
  "spend_limit": null,
  "packs": [
    {
      "product_code": "gems_medium",
      "offer_kind": "standard",
      "store_product_id": "acme_gems_medium",
      "contents": [{ "currency": "gems", "amount": 500, "bonus_amount": 50, "first_purchase_bonus_amount": 500 }],
      "remaining_purchases": null,
      "ends_at": null
    }
  ],
  "reference_packs": [{ "currency": "gems", "product_code": "gems_small", "base_amount": 100 }]
}
```

`GET /api/shop/packs?platform=...&codes=a,b` additionally returns the named active products with `fulfilment = external` (direct purchases for an exact price, listed by a caller such as the insufficient-balance sheet) with `contents: []`; they use the same intent, confirmation and verification path. A product with `random_reward` carries `odds_url`.

Rules: `store_product_id` is the id for the requested platform; a pack without one for that platform is omitted. `first_purchase_bonus_amount` is `null` when the account is not eligible (the client shows no bonus). `ends_at` is a server instant for a starter window, `null` without one. Packs with `active = false`, a spent starter offer (`remaining_purchases = 0`) or an expired starter window are omitted. The response carries amounts and no price (INV-16). `purchase_policy.reason` is `age`, `region`, `review` or `null`; the host's `purchase_policy` supplies the first fields and this block adds `review`. With no host policy registered the answer is `purchases_enabled: false`, reason `age` (`PURCHASES_DEFAULT_WITHOUT_POLICY = off`, INV-28).

### `POST /api/purchases/intent`

Request: `{ "product_code": "gems_medium", "platform": "apple", "price": { "amount_micros": 4990000, "currency": "USD" } }`. The `price` is what the store's product details report on the device.

| Status | Body | When |
|---|---|---|
| 200 | `{ "allowed": true, "remaining_micros": 10010000 }` | Allowed. `remaining_micros` is the room left after this purchase, and `null` without a limit |
| 200 | `{ "allowed": false, "reason": "limit_reached", "remaining_micros": 3000000, "next_room_at": "<ISO 8601 UTC>" }` | The purchase would cross the limit. `next_room_at` is the earliest instant at which this purchase would fit, `null` when it never fits (the price alone is above the limit; section 12). `remaining_micros` is the room left before this purchase (`max(0, limit - spent)`). |
| 200 | `{ "allowed": false, "reason": "limit_currency_mismatch" }` | The price currency differs from the limit's currency |
| 200 | `{ "allowed": false, "reason": "policy" }` or `"review"` | `purchases_enabled` is false |
| 404 | `{ "error": "unknown_product" }` | Not an active catalog product |
| 400 | `{ "error": "invalid_request" }` | Malformed body |

The check does not reserve anything and issues no token; it is advice for the shop. The authority for what happens next is verification (INV-12).

### `POST /api/purchases/verify`

Request, Apple: `{ "platform": "apple", "signed_transaction": "<JWS>", "client_price": { "amount_micros": 4990000, "currency": "USD" } }`. Google: `{ "platform": "google", "product_id": "acme_gems_medium", "purchase_token": "<token>", "client_price": { ... } }`. `client_price` is optional.

| Status | Body | When |
|---|---|---|
| 200 | `{ "purchase_id": "...", "state": "verified", "beneficiary": "self", "granted": [{ "currency": "gems", "amount": 1050 }], "first_purchase_bonus_applied": true, "balances": [{ "currency": "gems", "balance": 1290 }], "finish_transaction": true }` | Recorded and delivered, or recognized as already delivered (same body) |
| 200 | `{ "purchase_id": "...", "state": "pending", "finish_transaction": false }` | The store says payment is incomplete. Nothing granted |
| 200 | `{ "purchase_id": "...", "state": "verified", "beneficiary": "other_account", "finish_transaction": true }` | The store echoed another account's token; that account received the grant. No balances are returned |
| 200 | `{ "purchase_id": "...", "state": "canceled" \| "refunded", "finish_transaction": true }` | Already canceled or refunded at the store |
| 409 | `{ "error": "purchase_rejected", "reason": "<reject_reason>", "finish_transaction": true }` | The store vouches for it and the server refuses delivery |
| 422 | `{ "error": "proof_invalid" }` | Signature, chain, bundle or package check failed. No row is written |
| 429 | `{ "error": "rate_limited" }` | More than `VERIFY_RATE_LIMIT_PER_MINUTE` calls for the account |
| 503 | `{ "error": "store_unavailable" }` | The store API failed or rate-limited the server. The client retries; nothing was recorded |
| 401 | `{ "error": "unauthenticated" }` | No session |

`finish_transaction` tells the client whether to finish an Apple transaction (INV-11). Google purchases are consumed by the server; the field is `false` for Google.

### `GET /api/purchases/recent`

Returns up to `PURCHASE_RECENT_LIMIT` purchases of the account, newest first: `{ purchase_id, product_code, state, purchased_at, store_order_id, granted: [{currency, amount}], first_purchase_bonus_applied, price_micros, price_currency, refunded_at }`. No transaction ids or tokens leave the server.

### `GET /api/wallet`

```json
{
  "server_now": "2026-10-27T12:00:00Z",
  "balances": [{ "currency": "coins", "balance": 1200 }, { "currency": "gems", "balance": 40 }],
  "refund_notices": [{ "purchase_id": "...", "product_code": "gems_medium", "refunded_at": "2026-10-26T08:00:00Z",
                       "clawed": [{ "currency": "gems", "amount": 200 }], "shortfall": [{ "currency": "gems", "amount": 350 }] }]
}
```

`refund_notices` are refunded purchases with `refunded_at` later than `wallet_accounts.refund_notice_seen_at`. `POST /api/wallet/refund-notices/seen` sets that column to the server clock.

---

## 1. The ledger (pure core, SQL shell)

Every balance change is one call to the writer: `grant`, `spend`, or the internal kinds `clawback`, `reinstatement` and the merge entries. The writer resolves the account (section 3), loads the existing entry for the key, and decides in a pure function; the shell then applies the decision in one transaction.

Decision rules (in this order):

1. `amount` is an integer from 1 to `LEDGER_MAX_AMOUNT`, else `invalid_amount`. Strings, floats, zero and negatives are rejected.
2. `reason` has the form `<block-slug>.<action>` and `idempotency_key` is non-empty and at most `LEDGER_IDEMPOTENCY_KEY_MAX_LENGTH` characters, else `invalid_request`.
3. A key already applied in the tenant: same `account_id`, `currency`, `amount`, `reason` and kind returns the original `{applied: true, balance: balance_after, entry_id}` and changes nothing; any difference returns `idempotency_conflict`.
4. `currency` must exist, else `unknown_currency`. With `LEDGER_REQUIRE_REGISTERED_FLOW`, an enabled `currency_flows` row for (currency, direction, reason) must exist, else `unknown_reason`. Direction is `faucet` for `grant` and `reinstatement`, `sink` for `spend` and `clawback`.
5. `spend` that would cross zero returns `insufficient_balance` with the current balance and writes nothing; the key stays free.
6. `grant` that would pass `LEDGER_MAX_BALANCE` returns `balance_limit_exceeded`.

<!-- PATTERN: ledger-plan -->
<!-- PURPOSE: decide one ledger call as a pure function so replay, conflict and limits are testable without a database -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: `Entry` -> the row your ORM returns for (tenant, idempotency_key); `Cfg` -> your configuration object; return a tagged union or throw typed errors per your error style; keep the checks in this order -->
```typescript
type Kind = "grant" | "spend" | "clawback" | "reinstatement";
interface Call { accountId: string; currency: string; amount: number; reason: string; kind: Kind }
interface Entry extends Call { id: string; balanceAfter: number }
type Plan =
  | { type: "reject"; error: string }
  | { type: "replay"; entryId: string; balance: number }
  | { type: "apply"; balanceAfter: number };

const credit = (k: Kind) => k === "grant" || k === "reinstatement";

export function planEntry(c: Call, existing: Entry | null, balance: number, flowOk: boolean, cfg: Cfg): Plan {
  if (!Number.isSafeInteger(c.amount) || c.amount < 1 || c.amount > cfg.maxAmount)
    return { type: "reject", error: "invalid_amount" };
  if (existing) {
    const same = existing.accountId === c.accountId && existing.currency === c.currency &&
      existing.amount === c.amount && existing.reason === c.reason && existing.kind === c.kind;
    return same ? { type: "replay", entryId: existing.id, balance: existing.balanceAfter }
                : { type: "reject", error: "idempotency_conflict" };
  }
  if (cfg.requireFlow && !flowOk) return { type: "reject", error: "unknown_reason" };
  const next = credit(c.kind) ? balance + c.amount : balance - c.amount;
  if (next < 0) return { type: "reject", error: "insufficient_balance" };
  if (next > cfg.maxBalance) return { type: "reject", error: "balance_limit_exceeded" };
  return { type: "apply", balanceAfter: next };
}
```

The shell applies an `apply` plan with a conditional update so concurrent calls cannot overdraw, then inserts the entry. The balance update and the entry insert are one transaction.

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: `$n` placeholders -> your driver's parameter style; SQLite 3.35+ supports `RETURNING` and `ON CONFLICT DO NOTHING`; MySQL has neither `RETURNING` nor `ON CONFLICT`: use `INSERT IGNORE` and re-select the balance in the same transaction; for a grant replace `balance >= $4` with `balance + $4 <= $max` and `- $4` with `+ $4` -->
```sql
-- one transaction per ledger call
INSERT INTO wallet_balances (tenant_id, account_id, currency_code, balance)
VALUES ($1, $2, $3, 0) ON CONFLICT (tenant_id, account_id, currency_code) DO NOTHING;

UPDATE wallet_balances SET balance = balance - $4, updated_at = now()
 WHERE tenant_id = $1 AND account_id = $2 AND currency_code = $3 AND balance >= $4
RETURNING balance;                      -- no row: insufficient_balance, roll back, write nothing

INSERT INTO ledger_entries (tenant_id, account_id, currency_code, entry_kind, amount,
                            balance_after, reason, source_ref, idempotency_key, purchase_id)
VALUES ($1, $2, $3, 'spend', $4, $5, $6, $7, $8, $9)
RETURNING id;                           -- unique violation on (tenant_id, idempotency_key):
                                        -- roll back, re-read the entry, answer as replay or conflict
```

A unique violation means a concurrent twin won. The loser rolls back (its balance update disappears with it), re-reads the winner's entry and runs `planEntry` again, which yields `replay` or `idempotency_conflict`.

### The `holders` read

`holders(currency, after_account_id?, limit)` lists who holds a currency or item code, for sweeps such as the expiry of an item stack. It is in-process and read-only, never an HTTP route. It returns `{ holders: [{ account_id, balance }], next_after_account_id }` for accounts of the tenant whose `wallet_balances.balance` for the code is above zero, ordered by `account_id` ascending, strictly after `after_account_id` when given, at most `limit` rows. `limit` is an integer from 1 to `HOLDERS_MAX_LIMIT`, else `invalid_amount`; an unknown currency returns `unknown_currency`. `next_after_account_id` is the last returned id, or null on the last page. The order is stable, so a caller that pages while balances change visits every account that held the code for the whole sweep exactly once; an account whose balance changes during the sweep may or may not appear, and a caller re-reads the balance through `balance` before acting. The index (`tenant_id`, `currency_code`, `account_id`) serves the query.

### Guarantees tested in `ledger.feature`

- Ten concurrent spends of 70 from a balance of 100 with distinct keys apply exactly one.
- Ten concurrent calls with one key apply exactly one entry and all return the same `entry_id`.
- After any sequence of calls, `wallet_balances.balance` equals the newest `balance_after` and equals credits minus debits (`reconciliation-and-erasure.feature`).

## 2. Registry and catalog

- `currencies`, `currency_flows`, `store_products` and `store_product_contents` are configuration data. They are changed by migration or an operator tool, never by player-facing code.
- Each calling block ships its flow rows with its migration: currency, direction, reason, a one-sentence description a designer can read. `fixtures/catalog.json` lists this block's own reasons: `virtual-currency.pack-purchase` (faucet), `virtual-currency.pack-refund` (sink, the clawback), `virtual-currency.pack-refund-reversed` (faucet, the reinstatement), `virtual-currency.wallet-merge-out` (sink), `virtual-currency.wallet-merge-in` (faucet), `virtual-currency.support-grant` (faucet), `virtual-currency.support-debit` (sink).
- A catalog row with `fulfilment = ledger` must have at least one content row and `product_kind = consumable`; a catalog check at startup fails when a content row names a missing currency, when two products share a store product id, when `reference_product_code` names a pack that has no content row for that currency, when the packs together grant more than `MAX_PURCHASABLE_CURRENCIES` distinct `hard` currencies (INV-27), or when `random_reward` is set without an `odds_url` or on a `fulfilment = ledger` row. The contract has no operation that converts one currency into another and the catalog has no exchange table (INV-27).
- Packs grant `amount + bonus_amount (+ first_purchase_bonus_amount when eligible)` per content row. The client never sends or confirms an amount (INV-8).

## 3. Accounts and the store account token

- `wallet_accounts` is created on the first wallet call or intent for an account. `store_account_token` is the `account_id` when `STORE_ACCOUNT_TOKEN_SOURCE = account_id` (the default; `auth.guest-account` passes the account id to Apple as `appAccountToken` and to Google as the obfuscated account id, and defines it as a random UUID that is not personal data), else a random version 4 UUID from a cryptographically secure generator.
- **Resolve an account** for any operation: follow `merged_into_account_id` until a row without one (guard against cycles: at most 8 hops, else reject and alert). All ledger rows, purchases and limits attach to the resolved account.
- **Resolve the beneficiary of a purchase** from the verified proof:
  1. The store echoed a token (`appAccountToken` for Apple, the obfuscated account id for Google): look up the owner. Found: that account, `account_binding = token`. Not found (an erased account or a forged value): `rejected` with `account_unknown`.
  2. No token echoed: with `ACCOUNT_TOKEN_MISSING_POLICY = bind_to_session` the submitting session's account, `account_binding = session`; with no session (a notification arrived first) the purchase is recorded as `unclaimed`. With `reject`, `rejected` with `account_unknown`.
  3. The beneficiary differs from the submitting session's account: deliver to the beneficiary and answer the submitter `beneficiary: other_account`. A signed-out device resubmitting a previous user's unfinished purchase therefore cannot enrich the next user.
- The token is sent to the stores at purchase time by the client. It is never an email, a provider id or a value derived from personal data (INV-23). Past transactions keep their token after a guest merge because the lookup resolves through `merged_into_account_id`.

## 4. Apple verification

The server verifies; the client's JWS is a claim. For a purchase proof (`POST /api/purchases/verify`) and for notifications, in this order:

1. Peek at the unverified payload's `environment` (`Sandbox` or `Production`) only to choose the verifier and the API host; the verification itself re-checks it.
2. Verify the JWS: the `x5c` chain has three certificates and ends in a pinned Apple root certificate; the leaf signs the token; certificate validity dates are checked; with `APPLE_ONLINE_CERT_CHECKS` the library also checks certificate status online. Use Apple's App Store Server Library for your language, which implements this and checks `bundleId` and `environment` against its constructor (`SignedDataVerifier(appleRootCertificates, enableOnlineChecks, environment, bundleId, appAppleId)`; `appAppleId` is required for the production environment) ([library README](https://github.com/apple/app-store-server-library-node), MEDIUM: read through a page summarizer; [verification source](https://github.com/apple/app-store-server-library-node/blob/main/jws_verification.ts), MEDIUM). Accept only the algorithm Apple's JWS headers carry; pin it after inspecting a sandbox transaction (unconfirmed, see `README.md`, "Origin and verification status").
3. Reject `Sandbox` unless `APPLE_ACCEPT_SANDBOX`; sandbox purchases are recorded with `environment = sandbox`.
4. Confirm the current state with `GET /inApps/v1/transactions/{transactionId}` on the host for the environment (`https://api.storekit.apple.com/` or `https://api.storekit-sandbox.apple.com/`), authenticated by a JWT signed with the App Store Connect key: ES256, claims `iss`, `iat`, `exp` (at most 60 minutes after `iat`), `aud` = `appstoreconnect-v1`, `bid` ([Apple, Get Transaction Info](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info), [JWT for API requests](https://developer.apple.com/documentation/appstoreserverapi/generating-json-web-tokens-for-api-requests), HIGH). Verify the returned signed transaction the same way and use its fields, so a transaction refunded before submission is seen as refunded. `429` and `5xx` answer the caller `store_unavailable` and write nothing; `404 TransactionIdNotFoundError` answers `proof_invalid`.
5. Read the fields ([JWSTransactionDecodedPayload](https://developer.apple.com/documentation/appstoreserverapi/jwstransactiondecodedpayload), HIGH): `transactionId`, `productId`, `type` (`Consumable`, `Non-Consumable`, `Auto-Renewable Subscription`, `Non-Renewing Subscription`, [type](https://developer.apple.com/documentation/appstoreserverapi/type), HIGH), `quantity`, `purchaseDate` (milliseconds), `revocationDate`, `revocationReason` (0: refunded for other reasons such as an accidental purchase; 1: an actual or perceived issue in the app, [revocationReason](https://developer.apple.com/documentation/appstoreserverapi/revocationreason), HIGH), `appAccountToken`, `environment`, `price` (price times 1000) and `currency`.

<!-- PATTERN: apple-verify -->
<!-- PURPOSE: turn a client-supplied Apple JWS into verified facts, confirmed against the App Store Server API -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic api=apple-app-store-server -->
<!-- ADAPT: the library name and constructor -> Apple's App Store Server Library for your language (the Node.js package requires Node 22 or later per its README; Bun and Deno use it through npm specifiers); `peekEnvironment` -> base64url-decode the middle JWS segment and read `environment` without trusting it; `api(env).getTransactionInfo` -> the library's API client or one signed HTTP GET; call the endpoint with `fetch` if no library fits -->
```typescript
async function verifyApple(jws: string): Promise<Verified> {
  const env = peekEnvironment(jws);                  // "Sandbox" | "Production", unverified
  if (env === "Sandbox" && !cfg.acceptSandbox) throw reject("environment_not_accepted");
  const v = verifierFor(env);        // new SignedDataVerifier(roots, online, env, bundleId, appAppleId)
  const tx = await v.verifyAndDecodeTransaction(jws);        // chain, bundleId, environment
  const info = await api(env).getTransactionInfo(tx.transactionId!); // 429/5xx -> store_unavailable
  const cur = await v.verifyAndDecodeTransaction(info.signedTransactionInfo!);
  return {
    platform: "apple", storeTransactionId: cur.transactionId!, storeProductId: cur.productId!,
    type: cur.type!, quantity: cur.quantity ?? 1, environment: env === "Sandbox" ? "sandbox" : "production",
    purchasedAt: new Date(cur.purchaseDate!), revokedAt: cur.revocationDate ? new Date(cur.revocationDate) : null,
    revokeReason: cur.revocationReason ?? null, accountToken: cur.appAccountToken ?? null,
    price: cur.price != null && cur.currency ? { micros: cur.price * 1000, currency: cur.currency } : null,
    storeState: cur.revocationDate ? "REVOKED" : "PURCHASED",
  };
}
```

## 5. Google verification

1. The client sends `product_id` and `purchase_token`. The server calls `purchases.productsv2.getproductpurchasev2` for `GOOGLE_PACKAGE_NAME` and the token (`GET .../applications/{packageName}/purchases/productsv2/tokens/{token}`, scope `https://www.googleapis.com/auth/androidpublisher`) ([productsv2](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2/getproductpurchasev2), HIGH). A token from another app fails here: the package name is in the path.
2. Read ([ProductPurchaseV2](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2), HIGH): `productLineItem[]` (`productId`, `productOfferDetails.quantity`, `refundableQuantity`, `consumptionState`: `CONSUMPTION_STATE_YET_TO_BE_CONSUMED` or `CONSUMPTION_STATE_CONSUMED`), `purchaseStateContext.purchaseState` (`PENDING`, `PURCHASED`, `CANCELLED`, `PURCHASE_STATE_UNSPECIFIED`), `acknowledgementState` (`ACKNOWLEDGEMENT_STATE_PENDING`, `ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED`), `orderId`, `obfuscatedExternalAccountId`, `purchaseCompletionTime`, `testPurchaseContext` (present for test purchases), `regionCode`.
3. Require exactly one line item whose `productId` equals the submitted `product_id`, else `rejected` with `line_items_unsupported` or `unknown_product`. `PURCHASE_STATE_UNSPECIFIED` is treated as an error (`store_unavailable`, retry).
4. `store_transaction_id` is the purchase token ([Google, security](https://developer.android.com/google/play/billing/security): the token is globally unique and safe as a primary key; `orderId` is absent for promo-code purchases, HIGH). Test purchases are recorded as `sandbox` and rejected unless `GOOGLE_ACCEPT_TEST_PURCHASES`.
5. Price: the client's `client_price`, recorded with `price_source = client_report`. The `productsv2` fields read do not include a price.

<!-- PATTERN: google-verify -->
<!-- PURPOSE: read the authoritative state of a Google one-time purchase from the Developer API -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic api=google-play-developer api-version=v3 -->
<!-- ADAPT: `publisher.productsv2.get` -> googleapis `androidpublisher.purchases.productsv2.getproductpurchasev2` or one signed HTTP GET with a service-account access token; map the enum strings exactly as Google names them; on Deno use fetch with an access token from your OAuth library -->
```typescript
async function verifyGoogle(productId: string, token: string): Promise<Verified> {
  const p = await publisher.productsv2.get({ packageName: cfg.packageName, token });
  const items = p.productLineItem ?? [];
  if (items.length !== 1) throw reject("line_items_unsupported");
  if (items[0].productId !== productId) throw reject("unknown_product");
  const d = items[0].productOfferDetails!;
  return {
    platform: "google", storeTransactionId: token, storeOrderId: p.orderId ?? null,
    storeProductId: productId, quantity: Number(d.quantity ?? 1),
    environment: p.testPurchaseContext ? "sandbox" : "production",
    storeState: p.purchaseStateContext!.purchaseState!,       // PENDING | PURCHASED | CANCELLED
    consumed: d.consumptionState === "CONSUMPTION_STATE_CONSUMED",
    acknowledged: p.acknowledgementState === "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    accountToken: p.obfuscatedExternalAccountId ?? null,
    purchasedAt: new Date(p.purchaseCompletionTime ?? Date.now()),
  };
}
```

A purchase that is already `CONSUMED` with no local record (a client consumed it, a bug) is still delivered when `PURCHASED`: the customer paid. It is flagged `consumed_by_other` in logs and counted by reconciliation.

## 6. Recording and delivering a purchase

`record_verified_purchase` runs in one transaction. It is the only place a purchase row is written and the only place pack grants are issued.

1. Look up the catalog row by (platform, store product id). Missing: record `rejected` / `unknown_product` (the store vouches for the transaction, so a row exists) and stop.
2. Pure decision (below): `rejected`, `refunded`, `pending`, `canceled`, `verified`.
3. Lock the beneficiary's `wallet_accounts` row, so two purchases for one account serialize. Existing row for `store_transaction_id`: apply only the allowed transitions (`README.md` section 5, "Purchase state"); an unchanged verified purchase returns the stored result.
4. For `verified` with `fulfilment = ledger`: compute the lines, check first-purchase eligibility, issue one `grant` per line with reason `virtual-currency.pack-purchase`, key `virtual-currency:pack-purchase:{purchase_id}:{currency}`, `purchase_id` set, then set `verified_at`, `first_purchase_bonus_applied`, `price_*`. For `fulfilment = external` write the record only.
5. Commit, emit `purchase_verified`, fire `on_purchase_state_changed`, then finalize with the store (section 8).

**First-purchase bonus.** Eligible when the beneficiary has no other purchase in state `verified` or `refunded` for the scope: the same `product_code` (`FIRST_PURCHASE_BONUS_SCOPE = product`) or any `fulfilment = ledger` product (`account`). A refunded purchase keeps consuming the bonus (INV-18). Evaluation happens inside the locked transaction, in the order purchases reach verification; the receipt states what was credited.

**Starter offer.** `max_purchases_per_account` (1) controls visibility: the shop hides the offer once the account has a purchase of it in state `pending`, `verified` or `refunded`. A transaction that arrives for a hidden or inactive offer (a second device, a store product page) is verified and delivered in full and logged as `starter_repeat`; delivery is never reduced after the player paid (INV-12). `window_seconds` counts from `wallet_accounts.created_at` by the server clock; the shop returns `ends_at`.

<!-- PATTERN: purchase-plan -->
<!-- PURPOSE: decide the state of a verified store transaction before any write -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: `Verified` -> the facts returned by verifyApple or verifyGoogle; `Product` -> the catalog row; add checks for your own product kinds; the Apple type strings are Apple's, the Google state strings are Google's -->
```typescript
const APPLE_TYPE = { consumable: ["Consumable"], non_consumable: ["Non-Consumable"],
  subscription_term: ["Auto-Renewable Subscription", "Non-Renewing Subscription"] } as const;

type State = "pending" | "verified" | "canceled" | "refunded" | "rejected";

export function planPurchase(v: Verified, p: Product | null, cfg: Cfg): { state: State; reason?: string } {
  if (!p) return { state: "rejected", reason: "unknown_product" };
  if (v.environment === "sandbox" && !cfg.acceptSandbox(v.platform))
    return { state: "rejected", reason: "environment_not_accepted" };
  if (v.quantity > cfg.maxQuantity) return { state: "rejected", reason: "quantity_unsupported" };
  if (v.platform === "apple" && !APPLE_TYPE[p.kind].includes(v.type))
    return { state: "rejected", reason: "type_mismatch" };
  if (v.revokedAt) return { state: "refunded" };
  if (v.storeState === "PENDING") return { state: "pending" };
  if (v.storeState === "CANCELLED") return { state: "canceled" };
  return { state: "verified" };
}
```

**Interplay with spend limits:** none at delivery. Counting happens from the recorded `price_micros` (section 12).

## 7. Pending, unclaimed, interrupted

- **Google `PENDING`**: record `pending`, grant nothing, never acknowledge or consume (the three-day window starts only at `PURCHASED`). Completion arrives as `ONE_TIME_PRODUCT_PURCHASED` or through a client resubmission; both re-read the purchase. Cancellation or expiry arrives as `ONE_TIME_PRODUCT_CANCELED` or state `CANCELLED`: the row becomes `canceled`. Google does not state a maximum pending duration, so there is no server-side expiry; reconciliation alerts after `PENDING_ALERT_AFTER_SECONDS` (section 13).
- **Apple Ask to Buy**: StoreKit reports the purchase as pending on the device and delivers the transaction through `Transaction.updates` after approval ([Apple, pending](https://developer.apple.com/documentation/storekit/product/purchaseresult/pending), HIGH). The server sees nothing until then; no row exists.
- **Apple unclaimed**: an `ONE_TIME_CHARGE` notification for a transaction whose payload carries no `appAccountToken` (an offer-code redemption, for example) is recorded `unclaimed`. The next client submission binds it to that session's account and delivers it.
- **Interrupted**: the client recovers Apple unfinished transactions and Google unconsumed purchases at launch and on resume (`frontend.md`); resubmission is idempotent by `store_transaction_id`. A transaction the client finished too early is recovered by `ONE_TIME_CHARGE` (Apple) or `ONE_TIME_PRODUCT_PURCHASED` (Google) notifications and by reconciliation.
- **Delivery after a lost response**: a second submission finds the row and answers the original result.

## 8. Finishing with the store

- **Google, `consumable`**: after the record commits, call `purchases.products:consume` (`POST .../purchases/products/{productId}/tokens/{token}:consume`, empty body). It also acknowledges the purchase and lets the player buy the product again ([lifecycle](https://developer.android.com/google/play/billing/lifecycle/one-time), HIGH). **`non_consumable`**: call `purchases.products:acknowledge` after checking `acknowledgementState`. Success sets `store_finalized_at`. Failure leaves the row for the retry job; the deadline is three days from `PURCHASED`, after which Google refunds and revokes the purchase.
- **Never** consume or acknowledge a `rejected` purchase ([Google, integrate](https://developer.android.com/google/play/billing/integrate), HIGH). A Google purchase that fails the server's checks is refunded with `orders.refund` (`POST .../orders/{orderId}:refund?revoke=true`) as Google's lifecycle page documents, because waiting out the window delays the player's money ([lifecycle](https://developer.android.com/google/play/billing/lifecycle/one-time), HIGH). Apple: this block calls no endpoint that refunds; a rejected Apple purchase goes to the support queue (MEDIUM: no refund endpoint was found on the Apple pages read).
- **Apple**: the server cannot finish a transaction; it answers `finish_transaction: true` for terminal states and the client calls `finish()` ([Apple, finish](https://developer.apple.com/documentation/storekit/transaction/finish()), HIGH for the call; the page does not say what happens if it is never called).
- The order is fixed: commit the record and grants, then finalize. A crash between the two leaves a verified, unfinalized Google purchase that the retry job completes.

<!-- PATTERN: finalize-after-commit -->
<!-- PURPOSE: consume or acknowledge a Google purchase only after the grant is durable -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic api=google-play-developer -->
<!-- ADAPT: `db.tx` -> your transaction helper; `publisher.products.*` -> googleapis `purchases.products.consume` / `acknowledge` or signed HTTP POSTs; the retry job calls `finalizeGoogle` for rows with `store_finalized_at IS NULL` -->
```typescript
const rec = await db.tx((t) => recordVerifiedPurchase(t, v, session));
if (rec.state === "verified" && rec.platform === "google" && !rec.storeFinalizedAt) {
  await finalizeGoogle(rec);          // never throws into the caller; failures are retried
}

async function finalizeGoogle(rec: PurchaseRow): Promise<void> {
  try {
    const ref = { packageName: cfg.packageName, productId: rec.storeProductId, token: rec.storeTransactionId };
    if (rec.productKind === "consumable") await publisher.products.consume(ref);
    else if (!rec.acknowledged) await publisher.products.acknowledge(ref);
    await db.markFinalized(rec.id);   // sets store_finalized_at
  } catch (e) { log.warn("finalize_failed", { purchaseId: rec.id }); }  // no token or body in the log
}
```

## 9. Notification receivers

Both receivers authenticate the sender before parsing, dedupe in `store_notifications`, process, and answer so that a failure makes the store redeliver. Neither trusts the body: state comes from a fresh read (INV-17).

### Apple (`POST /api/store/apple/notifications`)

1. Body `{ "signedPayload": "<JWS>" }`. Verify the JWS as in section 4 (chain, `data.bundleId`, `data.environment`; production also checks `appAppleId`). Failure answers 401 and logs no payload.
2. Insert (`apple`, `notificationUUID`, type) in `store_notifications`. A row with outcome `processed` or `ignored` answers 200 at once. A `received` or `failed` row is reprocessed.
3. Dispatch on `notificationType` ([notificationType](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype), HIGH):

| `notificationType` | Action |
|---|---|
| `ONE_TIME_CHARGE` | Consumable, non-consumable or non-renewing purchase (also offer-code redemption). Run `record_verified_purchase` with the transaction in `data.signedTransactionInfo`, no session |
| `REFUND` | Section 10 |
| `REFUND_REVERSED` | Section 10 (reinstate) |
| `REFUND_DECLINED` | Record `processed`; no state change |
| `CONSUMPTION_REQUEST` | Section 11 |
| `REVOKE` | Family Sharing applies to non-consumables and subscriptions, so this does not occur for packs; handle it as a refund for a catalog `non_consumable` and route the rest to the registered handler |
| `TEST` | `processed` |
| Subscription types (`SUBSCRIBED`, `DID_RENEW`, `EXPIRED`, `DID_FAIL_TO_RENEW`, ...) | Route to the handler registered for (`apple`, `subscription`) (`billing.subscriptions`), else `ignored` |
| Anything else | `ignored` |

4. Answer 200 on `processed` or `ignored`, and 5xx when processing failed (`outcome = failed`). Apple retries five times at 1, 12, 24, 48 and 72 hours after the previous attempt in production; the sandbox sends once ([Apple, responding](https://developer.apple.com/documentation/appstoreservernotifications/responding-to-app-store-server-notifications), HIGH). The endpoint must support TLS 1.2 or later.
5. Missed notifications are recovered by Get Notification History (`POST /inApps/v1/notifications/history`, 180 days in production, 20 records per call) in reconciliation.

### Google (`POST /api/store/google/notifications`)

1. A Pub/Sub push body carries `message.data` (base64) and `message.messageId`. The push request's `Authorization: Bearer` token is a JWT signed by Google ([Pub/Sub push](https://docs.cloud.google.com/pubsub/docs/push), HIGH): verify the signature, then require `email` to equal `GOOGLE_PUSH_SERVICE_ACCOUNT`, `email_verified` to be true and `aud` to equal `GOOGLE_PUSH_AUDIENCE` ([authenticate push](https://docs.cloud.google.com/pubsub/docs/authenticate-push-subscriptions), HIGH). Failure answers 401.
2. Decode `message.data` to a `DeveloperNotification`: `version`, `packageName`, `eventTimeMillis` and exactly one of `oneTimeProductNotification`, `subscriptionNotification`, `voidedPurchaseNotification`, `pendingRefundReviewNotification`, `testNotification` ([RTDN reference](https://developer.android.com/google/play/billing/rtdn-reference), HIGH). Require `packageName` = `GOOGLE_PACKAGE_NAME`.
3. Dedupe by `messageId` in `store_notifications`.
4. Dispatch:

| Message | Action |
|---|---|
| `oneTimeProductNotification` (`notificationType` 1 `ONE_TIME_PRODUCT_PURCHASED`, 2 `ONE_TIME_PRODUCT_CANCELED`) | Re-read with `productsv2` by `purchaseToken` and run `record_verified_purchase` (a purchase never submitted by a client is `unclaimed` unless the echoed account id resolves). Google states these messages do not carry full status; always call the API ([RTDN reference](https://developer.android.com/google/play/billing/rtdn-reference), HIGH) |
| `voidedPurchaseNotification` with `productType` 2 | Section 10 (refund). `refundType` 1 is a full refund; 2 is a quantity-based partial refund, which cannot occur at `MAX_PURCHASE_QUANTITY` 1 and is logged |
| `subscriptionNotification` | Route to the handler registered for (`google`, `subscription`), else `ignored` |
| `testNotification` | `processed` |
| `pendingRefundReviewNotification` and unknown kinds | `ignored`, logged |

5. Acknowledge with 200 (Pub/Sub accepts 102, 200, 201, 202 and 204; any other status is a negative acknowledgement and Pub/Sub resends). Answer 5xx on processing failure so Pub/Sub redelivers.
6. One-time product messages exist only when the Play Console option "Get all notifications for subscriptions and one-time products" is chosen (`README.md` section 7). Voided-purchase messages arrive with the narrower option too.

## 10. Refund, revoke and clawback

### Detecting a refund

- **Apple**: `REFUND` (and the refund history endpoint in reconciliation). Re-read the transaction; `revocationDate` present means refunded. `REFUND_REVERSED` means Apple reversed a refund after a dispute; re-read, and `revocationDate` absent means the purchase stands again.
- **Google**: `voidedPurchaseNotification`, the Voided Purchases API (`GET .../purchases/voidedpurchases`, `startTime` not older than 30 days, `type` 0 for in-app items; fields `purchaseToken`, `orderId`, `voidedTimeMillis`, `voidedSource` 0 user / 1 developer / 2 Google, `voidedReason` 0 other, 1 remorse, 2 not_received, 3 defective, 4 accidental_purchase, 5 fraud, 6 friendly_fraud, 7 chargeback, 8 unacknowledged_purchase, [voidedpurchases](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.voidedpurchases), HIGH). A purchase that was never acknowledged is refunded by Google after three days and appears here as `unacknowledged_purchase`.
- A refund is a state change of the purchase record. `refund_reason` stores `apple:0`, `apple:1` or `google:<voidedReason name>`; `refunded_at` stores the store's instant.

### The clawback policy

When a `verified` purchase with `fulfilment = ledger` becomes `refunded`:

1. For each currency the purchase granted, the amount to reclaim is `min(current balance, amount the purchase granted)`. Lines come from the purchase's ledger entries (`purchase_id`).
2. A `clawback` entry (reason `virtual-currency.pack-refund`, key `virtual-currency:clawback:{purchase_id}:{currency}:{cycle}`) removes that amount. If the balance is zero no entry is written.
3. The unrecovered remainder (granted minus clawed) is the **shortfall**. It is recorded in the purchase's entries (it equals the grants minus the clawbacks), reported in `purchase_refunded`, shown to the player as a fact, and charged to no one: no negative balance, no debt, no deduction from later grants, no block on spending. A single refund causes no account action.
4. Items bought by the spent currency stay with the player. Other currencies are untouched.
5. Repeated refunds count toward `purchase_policy.reason = review` (refunds with `refund_reason` starting `operator:` do not count): with `REFUND_REVIEW_THRESHOLD` refunded purchases whose `refunded_at` is later than the server's now minus `REFUND_REVIEW_WINDOW_SECONDS`, the shop stops offering packs to that account. Delivery of purchases still arriving is unaffected (INV-12). Google suggests lighter action for a first offense than for repeat offenders ([Google, security](https://developer.android.com/google/play/billing/security), HIGH); the first refund shows only the player-facing notice.
6. `cycle` is 1 plus the number of earlier reinstatements of this purchase, so a second refund after a reversal uses a new key.

<!-- PATTERN: clawback-plan -->
<!-- PURPOSE: compute what a refund takes back from a partly spent pack, without ever going below zero -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: `granted` -> sums of the purchase's grant entries per currency; `balances` -> current balances of the beneficiary; the writer issues one `clawback` entry per line with `take > 0`; a policy that charges a debt would add a new table and is outside this block -->
```typescript
export function clawbackPlan(
  granted: Record<string, number>,      // currency -> units this purchase granted
  balances: Record<string, number>,     // currency -> current balance
): { currency: string; take: number; shortfall: number }[] {
  return Object.entries(granted).map(([currency, amount]) => {
    const take = Math.min(balances[currency] ?? 0, amount);
    return { currency, take, shortfall: amount - take };
  });
}
```

### Refund for spend a guardian did not authorize

The stores decide refunds. The block adds two things. The spending screen's "Unauthorized purchase?" help tells the player where to ask the store for a refund (Google: a request within 48 hours of purchase may succeed, after that the developer decides, [Google Play refund policy](https://support.google.com/googleplay/answer/15574908), HIGH) and how to contact support. For Google, an operator can refund a purchase with `orders.refund` (`revoke` true), which Google confirms with a voided-purchase message handled as any refund; the purchase's `refund_reason` is set to `operator:unauthorized` and it does not count toward the review hold, so a victim is not penalized. No Apple endpoint that refunds was found on the pages read (MEDIUM): for Apple the operator directs the guardian to Apple's refund request and the normal refund path applies.

### Reinstatement

Apple `REFUND_REVERSED` returns the purchase to `verified` and issues one `reinstatement` entry per currency for the amount the clawback took (reason `virtual-currency.pack-refund-reversed`, key `virtual-currency:reinstate:{purchase_id}:{currency}:{cycle}`). The shortfall is not granted: the player already spent those units. Google has no reversal message; a purchase refunded by Google stays refunded.

### Purchases without ledger fulfilment

For `fulfilment = external` the record changes state and `on_purchase_state_changed` fires. The owning block (`engagement.season-pass`, `billing.subscriptions`) reacts; this block touches no balance.

## 11. Consumption information (Apple refund requests)

On `CONSUMPTION_REQUEST` Apple asks for consumption data on a customer-initiated refund request for a consumable; the server answers `PUT /inApps/v2/transactions/consumption/{transactionId}` within 12 hours ([Apple, Send Consumption Information](https://developer.apple.com/documentation/appstoreserverapi/send-consumption-information), HIGH). The body (`ConsumptionRequest`) requires `customerConsented` (must be `true`; any other value is rejected with 400), `deliveryStatus` (`DELIVERED` when delivered; if not delivered `consumptionPercentage` must be 0) and `sampleContentProvided`; it accepts optional `consumptionPercentage` (milliunits, 0 to 100000) and `refundPreference` (`GRANT_FULL` or `DECLINE` for all product types) ([ConsumptionRequest](https://developer.apple.com/documentation/appstoreserverapi/consumptionrequest), HIGH).

- Send nothing unless `wallet_accounts.consumption_consent` is true; the player records consent through `PUT /api/wallet/consumption-consent`, with the consent text in the privacy settings. What Apple does when no data arrives is not stated on the pages read (`README.md`, unconfirmed list).
- `deliveryStatus` = `DELIVERED` for a `verified` purchase with grants.
- `sampleContentProvided` = `true`: the shop lists the contents before purchase (design).
- `consumptionPercentage` = `min(100000, floor(100000 * spent / granted))` where `granted` is the units the purchase granted in its primary currency and `spent` is the sum of `spend` entries in that currency since `verified_at` (design: a share of purchased units spent, an estimate, since units are fungible).
- `refundPreference`: omitted by default; `DECLINE` when `CONSUMPTION_REFUND_PREFERENCE = decline_if_consumed` and the percentage is 100000.
- Mark the notification `processed` after the call succeeds; a failed call returns 5xx so Apple retries.

## 12. Spending controls

`POST /api/purchases/intent` and `PUT /api/spend-limit` implement the controls in `README.md` section 6.

**Counted spend.** The sum of `price_micros` over the account's purchases with `price_currency` equal to the limit's currency, state `pending`, `unclaimed` or `verified`, and `purchased_at` later than the server's now minus `SPEND_LIMIT_PERIOD_SECONDS`. A refunded purchase drops out. A purchase with no recorded price (`price_source = none`) counts as zero, which the history shows as "see your store receipt".

**Intent decision.** Policy first (`purchases_enabled`, then the review hold), then the limit: no limit means allowed; a currency different from the limit's means `limit_currency_mismatch`; `spent + price > limit` means `limit_reached` with `remaining_micros = max(0, limit - spent)` and `next_room_at`. The check is advice for the shop; it reserves nothing.

**`next_room_at`** is the earliest instant at which this candidate purchase would fit. A counted purchase is counted while `purchased_at` is later than now minus `SPEND_LIMIT_PERIOD_SECONDS`, so it leaves the window exactly at `purchased_at + SPEND_LIMIT_PERIOD_SECONDS`. Walk the counted purchases oldest first, subtract each one's `price_micros` as it leaves (purchases that leave at the same instant leave together), and return the first leaving instant at which `spent + price <= limit`. The oldest purchase alone may free too little room, so the walk can pass several. If the candidate's price is above the limit itself it can never fit and `next_room_at` is `null`. A purchase with no recorded price counts as zero and changes nothing.

<!-- PATTERN: next-room-at -->
<!-- PURPOSE: find the earliest instant a candidate purchase fits under a rolling spend limit -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: `counted` -> the account's counted purchases in the limit's currency (state pending, unclaimed or verified, purchased_at later than now minus the period), as epoch milliseconds and micro-units; return an ISO string at the edge; keep it pure so the fixture cases run without a database -->
```typescript
interface Counted { at: number; micros: number }

export function nextRoomAt(limitMicros: number, priceMicros: number, counted: Counted[], periodMs: number): number | null {
  if (priceMicros > limitMicros) return null;                    // can never fit
  let spent = counted.reduce((sum, p) => sum + p.micros, 0);
  const byAge = [...counted].sort((a, b) => a.at - b.at);        // oldest first
  let i = 0;
  while (i < byAge.length) {
    const leaves = byAge[i].at + periodMs;
    while (i < byAge.length && byAge[i].at + periodMs === leaves) spent -= byAge[i++].micros;
    if (spent + priceMicros <= limitMicros) return leaves;       // first instant it fits
  }
  return null;                                                   // only when nothing is counted and it already fits
}
```

**Changing a limit** (`PUT /api/spend-limit`, passes the host's parental gate when required):

| Request | Effect |
|---|---|
| No limit exists, a limit is set | Applies at once |
| Same currency, smaller amount | Applies at once; clears any pending change |
| Larger amount, different currency, or `limit_micros: null` | Stored as pending with `pending_effective_at = server now + SPEND_LIMIT_COOL_OFF_SECONDS`; the limit in force is unchanged until then |
| `DELETE /api/spend-limit/pending` | Clears the pending change |

The limit in force at time `t` is the pending change when `pending_effective_at <= t`, else the stored one; a read at or after that instant writes the pending change into the stored columns (idempotent). A new request while one is pending replaces it and restarts the cool-off. The server clock decides (INV-22).

<!-- PATTERN: spend-limit-check -->
<!-- PURPOSE: decide whether a purchase fits under the account's spend limit, as a pure function -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: `spent` -> the sum from the purchases query above for the same currency and window; `Verdict` -> your error style; keep amounts in micro-units and never convert currencies -->
```typescript
interface Limit { micros: number; currency: string }
type Verdict =
  | { allowed: true; remaining: number | null }
  | { allowed: false; reason: "limit_reached" | "limit_currency_mismatch"; remaining: number };

export function checkLimit(limit: Limit | null, spent: number, price: Limit): Verdict {
  if (!limit) return { allowed: true, remaining: null };
  if (price.currency !== limit.currency)
    return { allowed: false, reason: "limit_currency_mismatch", remaining: Math.max(0, limit.micros - spent) };
  const remaining = Math.max(0, limit.micros - spent);
  return price.micros <= remaining
    ? { allowed: true, remaining: remaining - price.micros }
    : { allowed: false, reason: "limit_reached", remaining };
}
```

**Honest limits.** The price comes from the client's store product details for Google and from Apple's payload for Apple purchases when present. A modified client can under-report its price to the intent check, and purchases made outside the shop are counted only after the fact. The limit is a self-protection control for the player and the host's default for minors. It is not an anti-fraud control and not a substitute for the stores' parental approval flows.

## 13. Reconciliation job

Runs every `RECONCILE_INTERVAL_SECONDS` under a lease so one instance runs at a time. Every task is idempotent and read-mostly; none edits a ledger row (INV-19).

| Task | Check | Action |
|---|---|---|
| Ledger integrity | For each (account, currency): `balance` equals the newest `balance_after` and equals credits minus debits | Alert with the pair and both numbers. No automatic fix. The operator call `rebuild_balance(account, currency)` sets the balance to the ledger's credits minus debits (the ledger wins) and writes an audit record; a wrong amount inside the ledger is corrected by a support `grant` or `spend` with a `virtual-currency.support-*` reason |
| Registry audit | Every `reason` in `ledger_entries` has a `currency_flows` row of the right direction | Alert on any orphan reason (possible only when `LEDGER_REQUIRE_REGISTERED_FLOW` was off) |
| Flow report | Sum of faucets and sinks per currency per reason per day | Publish the net-flow report designers read (kit guide 12, rule 8; guide 14, rule 13) |
| Google finalize | Purchases `verified`, platform `google`, `store_finalized_at` null | Retry consume or acknowledge every `CONSUME_RETRY_INTERVAL_SECONDS`; alert after `CONSUME_ALERT_AFTER_SECONDS`; the hard deadline is three days |
| Pending and unclaimed | `pending` and `unclaimed` older than `PENDING_RECHECK_INTERVAL_SECONDS` | Re-read at the store; apply the allowed transition; alert on `pending` older than `PENDING_ALERT_AFTER_SECONDS` (default 604800, design) |
| Apple catch-up | Get Notification History over `NOTIFICATION_HISTORY_LOOKBACK_SECONDS` | Process every notification not in `store_notifications` |
| Google voided | `voidedpurchases.list` over `VOIDED_LOOKBACK_SECONDS` (at most 30 days) | Apply every void not yet applied. After one is found, poll more often until none is new, so clawbacks land before the player spends (Google's advice, [Google, security](https://developer.android.com/google/play/billing/security), HIGH) |
| Delivery audit | `verified` ledger purchases without grant entries | Re-run the idempotent grants (cannot happen inside one transaction; guards a manual repair) |
| Remainder report | For each pack purchase, the balance of its currency after the purchase and after the next spend | Publish the distribution per pack so a team can see remainders that no price spends (kit guide 14, rule 5) |
| Report | Counts: pending, unclaimed, unfinalized with oldest age, refunds in window, shortfall totals, ledger drift, notifications `failed` | One summary per run |

## 14. Guest merge and erasure

- **Participant contract of `auth.guest-account`** (`holdings`, `mergeAccounts`, `deleteAccount`; `README.md` section 3, "Guest wallet merge"):
  - `holdings(account_id)` lists, sorted by category then label key, one `{category, label_key, paid, effect}` per currency (category `currency`) or item code (category `items`) with a balance above zero; `paid` is true when a `verified` purchase of the account granted that code; `effect` is `carried`.
  - `mergeAccounts(from, into, merge_id)`: per currency with a positive balance, `spend` on `from` (reason `virtual-currency.wallet-merge-out`, key `wallet-merge-out:{merge_id}:{currency}`) and `grant` on `into` (reason `virtual-currency.wallet-merge-in`, key `wallet-merge-in:{merge_id}:{currency}`), then set `merged_into_account_id`. A repeat with the same `merge_id` returns the first result and completes missing legs; the same guest merged into another account fails `already_merged`; merging an account into itself is rejected.
- **`deleteAccount(account_id)`** (the eraser, registered with `compliance.account-deletion` and called by the guest purge): one transaction that sets the erasure flag for the append-only guard, deletes `ledger_entries`, `wallet_balances`, `spend_controls` and `wallet_accounts` for the account, and sets `store_purchases.account_id` to null (or deletes those rows when `ERASURE_PURCHASE_RECORDS = delete`). Re-runnable. A refund notification that later matches a de-linked purchase updates the record and claws back nothing.

## Error taxonomy

| Code | Where | Meaning |
|---|---|---|
| `invalid_amount`, `invalid_request` | ledger, endpoints | Malformed input |
| `unknown_currency`, `unknown_reason` | ledger | Not in the registry or disabled |
| `insufficient_balance` | `spend` | Would cross zero; nothing written |
| `balance_limit_exceeded` | `grant` | Would pass `LEDGER_MAX_BALANCE` |
| `idempotency_conflict` | ledger | Key reused with different arguments |
| `unknown_product` | intent | Not an active pack |
| `proof_invalid` | verify | Signature, chain, bundle, package or lookup failure; no row |
| `purchase_rejected` + reason | verify | `unknown_product`, `line_items_unsupported`, `type_mismatch`, `quantity_unsupported`, `environment_not_accepted`, `account_unknown` |
| `store_unavailable` | verify | Store API unreachable or rate-limited; retry |
| `rate_limited` | verify | Per-account limit (`VERIFY_RATE_LIMIT_PER_MINUTE`) |

## Anti-patterns

| DON'T | Why |
|---|---|
| Update `wallet_balances` from a feature | The ledger is the only history; a direct update cannot be audited or replayed |
| Build an idempotency key from a timestamp or a random value | A retry then double-applies; use stable facts |
| Grant on the client's word | A purchase proof is a claim; the store decides |
| Consume or acknowledge before the grant commits | A crash between the two loses the player's purchase |
| Grant on `PENDING` | Payment has not cleared |
| Use `orderId` as the Google purchase key | Promo-code purchases have none; use the purchase token |
| Trust the notification body | Re-read the state; notifications are hints (Google says they carry incomplete information) |
| Process notifications in arrival order | Delivery is at least once and unordered; derive state from the store |
| Compute or store a pack price | The store's string is the price (INV-16) |
| Clawback into a negative balance | Negative balances break every spend and every report |
| Delete ledger rows to "fix" drift | Rebuild the balance from the ledger, or add a correcting entry through the contract |
| Log a purchase token, JWS or signed payload | They are bearer material for the purchase |
