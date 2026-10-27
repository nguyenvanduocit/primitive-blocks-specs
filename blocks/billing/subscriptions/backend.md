# Backend Patterns: Subscriptions

> "Backend" here is everything that is not UI: the pure core (snapshot normalization, guard, composition, stipend slices), the notification handler, claim and restore, jobs, and the endpoints. Snippets are L3 illustrative TypeScript or SQL with the four markers of `docs/SPEC_GUIDELINES.md` section 6; the behavior (WHAT) is in the prose around them.
>
> **External contracts kept concrete**: App Store Server Notifications V2 type and subtype names, Apple status, offer, expiration-intent and ownership values, Apple API paths; Google RTDN envelope fields and type numbers, `SubscriptionPurchaseV2` state names, Google API paths. Merchant projects do not choose these. Source keys (`[SA1]`, `[SG3]`) are in the README Sources table.
>
> Shared services from `billing.virtual-currency`: `register_notification_handler`, `record_verified_purchase`, `verify_apple_transaction`, `on_purchase_state_changed`, `grant`, `spend`, the Google service-account client.

## 1. Endpoints

All client endpoints need a session; `account_id` comes from the session, never from the body. Errors use the codes of section 9.

| Method | Path | Body | Success | Purpose |
|---|---|---|---|---|
| GET | `/api/subscriptions/catalog` | | `{plans: [{plan_code, product_code, platform, store_product_id, store_base_plan_id, period}]}` | Active plans for the caller's platform. No price: the price is read from the store on the device |
| POST | `/api/subscriptions/intents` | `{plan_code}` | `{store_account_token, platform, store_product_id, store_base_plan_id, trial_eligible_hint, change}` | Returns the token to attach to the store purchase. `409 already_entitled` when the account has an entitled chain in the plan's group and the plan is not a change within the same platform (INV-18) |
| POST | `/api/subscriptions/claims` | `{platform, proof, confirm_transfer?}` | `{linked, entitlement, detail}` | Verify a proof with the store, bind the chain, return the entitlement. `proof` is `{signed_transaction}` (Apple, the JWS from the device) or `{purchase_token}` (Google) |
| POST | `/api/subscriptions/restores` | `{platform, proofs: [proof]}` (at most 20) | `{results: [{ref, outcome}], entitlements}` | Run a claim per proof without transfer; `outcome` is `linked`, `already_linked`, `linked_to_other_account`, `not_found`, `error`. `ref` is the position in `proofs`, never the proof |
| GET | `/api/subscriptions/status` | | `{server_now, entitlements, detail}` | The read model of section 1.1 |
| POST | `/api/subscriptions/refresh` | | same as status | Refresh the caller's chains from the store, within `REFRESH_MIN_INTERVAL_SECONDS` per chain |
| GET | `/api/subscriptions/offers` | | `{winback}` or `{}` | Optional (section 7). Returns a win-back offer reference when `WINBACK_ENABLED` and the account qualifies |

No store-facing endpoint exists in this block: the receivers of `billing.virtual-currency` own the URLs the stores call (README section 3).

### 1.1 Read model

```json
{
  "server_now": "2026-10-27T12:00:00Z",
  "entitlements": [{"product_code": "vip", "active": true, "state": "canceled", "expires_at": "2026-11-27T12:00:00Z", "will_renew": false}],
  "detail": {"vip": {"plan_code": "vip-monthly-apple", "platform": "apple", "phase": "regular", "ownership": "purchased",
    "pending_plan_code": null, "price_change_state": "none", "auto_resume_at": null, "next_stipend_at": "2026-11-27T12:00:00Z",
    "trial_ending": null}}
}
```

`entitlements` carries exactly the four contract fields per product the account holds or held; `detail` is for the UI only. `next_stipend_at` is the earliest `due_at` of a pending slice, or null. `trial_ending` is null except while a renewing free trial is inside its reminder window; then it is `{ends_at, renews_at, period, price_milliunits, currency_code, platform}` (section 10.4). No field carries `chain_ref`.

### 1.2 Contract call

`entitlement(account_id, product_code)` returns `{active, state, expires_at, will_renew}` and nothing else. It never throws for an unknown account or product: it returns the `none` shape. Other blocks call it in process; it performs the read-through refresh of section 8.

## 2. Snapshot normalization and apply (pure core)

A **snapshot** is built from a verified Apple payload or a Google fetch and has these fields; the functions below have no I/O and run without mocks.

| Field | Meaning |
|---|---|
| `state`, `phase`, `willRenew`, `expiresAt`, `ownership` | As the chain columns |
| `observedAt` | Apple `signedDate`; Google the instant the fetch started |
| `autoResumeAt`, `pendingPlanRef`, `priceChange`, `endReason` | As the chain columns |
| `term` | `{storeTransactionId, startsAt, endsAt, offerKind, offerId, priceMilliunits, currencyCode}` of the newest term |
| `chainRef`, `planRef` | Chain identity; `{storeProductId, basePlanId}` |
| `accountHint` | `appAccountToken` or `obfuscatedExternalAccountId` when present |
| `linkedChainRef` | Google `linkedPurchaseToken` |
| `environment` | `production` or `sandbox` (Google `testPurchase` present means sandbox) |
| `acknowledged` | Google `acknowledgementState` is acknowledged; true on Apple |
| `renewalPrice` | `{milliunits, currency}` of the next renewal, null when the store does not report it |

`end_reason` values: `canceled_by_player`, `billing`, `price_increase_not_accepted`, `product_not_for_sale`, `refund`, `revoked`, `replaced`, `developer`, `other`. Apple derives it from `expirationIntent` 1 to 5 [SA9] (1 canceled by the player, 2 billing, 3 price increase not accepted, 4 product not for sale, 5 other), `refund` for a refunded own purchase and `revoked` for a family revocation. Google derives it from the `canceledStateContext` reason: user initiated, system initiated (`billing`), developer initiated (`developer`), replacement (`replaced`) [SG4]; absent context gives `other`.

### 2.1 Apple

The input is one entry of the Get All Subscription Statuses response or the notification `data` object: `status` (1 active, 2 expired, 3 billing retry, 4 billing grace period, 5 revoked [SA9]), the decoded transaction and the decoded renewal info.

<!-- PATTERN: normalize-apple -->
<!-- PURPOSE: map one verified Apple status entry to the normalized snapshot, with no I/O -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic api=app-store-server-api -->
<!-- ADAPT: `AppleView` -> the decoded types of your App Store Server Library binding (Swift, Java, Python and Node ship one); keep the numeric status codes and string values exactly; derive `offerDiscountType` comparison case-insensitively if your binding upper-cases enums -->
```typescript
type State = "pending" | "trial" | "active" | "canceled" | "grace" | "retry" | "paused" | "expired" | "revoked";

export function normalizeApple(v: AppleView): Snapshot | null {
  const ownership = v.tx.inAppOwnershipType.toLowerCase(); // PURCHASED | FAMILY_SHARED | ASSIGNED
  if (ownership === "assigned") return null;               // organization assignment: not granted here
  const free = v.tx.offerDiscountType === "FREE_TRIAL";
  const phase = free ? "trial" : v.tx.offerType === 1 ? "intro" : "regular"; // offerType 1 = introductory
  const renews = v.renewal.autoRenewStatus === 1;
  const byStatus: Record<number, State> = {
    1: renews ? (free ? "trial" : "active") : "canceled",
    2: "expired", 3: "retry", 4: "grace", 5: "revoked",
  };
  const state = byStatus[v.status];
  const expiresAt =
    state === "grace" ? v.renewal.gracePeriodExpiresDate
    : state === "revoked" ? v.tx.revocationDate
    : v.tx.expiresDate;
  const over = state === "expired" || state === "revoked";
  return {
    state, phase, ownership, expiresAt, observedAt: v.signedDate,
    willRenew: !over && renews,
    priceChange: v.renewal.priceIncreaseStatus === 0 ? "pending_consent"
      : v.renewal.priceIncreaseStatus === 1 ? "accepted" : "none",
  };
}
```

Rules:

- `phase = trial` for any free period regardless of offer type; `intro` for a paid introductory offer (`offerType` 1 with a pay-as-you-go or pay-up-front mode); promotional, offer-code and win-back pricing is `regular` for stipend purposes.
- `pendingPlanRef` is `renewal.autoRenewProductId` when it differs from the transaction `productId`; otherwise null (a downgrade or crossgrade scheduled for the renewal [SA1 `DID_CHANGE_RENEWAL_PREF`]).
- `priceChange` is `pending_consent` for `priceIncreaseStatus` 0 (the customer has not responded to an increase that needs consent) and `accepted` for 1 [SA9]. A chain with no increase has the field absent: `none`.
- A status entry for a transaction `environment` other than `ACCEPTED_ENVIRONMENTS` is dropped and alerted. `bundleId` must equal `APPLE_BUNDLE_ID`.
- Apple `price` and `currency` are stored on the term for display only; Apple says not to use them for revenue [SA8].
- `eligibleWinBackOfferIds` in the renewal info feeds section 7.
- `renewalPrice` is the renewal info `renewalPrice` (milliunits) with its `currency` [SA7]; it feeds the trial-ending reminder (section 10).

### 2.2 Google

The input is a `SubscriptionPurchaseV2` [SG4], the instant the fetch started, and the revocation instant if a `SUBSCRIPTION_REVOKED` (12) notification or a voided purchase of product type subscription was recorded for the chain. Google exposes no revoked value in `subscriptionState`: Google documents that a revoked subscription reads `SUBSCRIPTION_STATE_EXPIRED` [SG3].

<!-- PATTERN: normalize-google -->
<!-- PURPOSE: map one subscriptionsv2 response to the normalized snapshot, with no I/O -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic api=google-play-developer-api api-version=v3 -->
<!-- ADAPT: `GoogleSubscription` -> the generated type of your Google API client; the response uses RFC 3339 strings for times, convert with Date.parse; only lineItems[0] is read because auto-renewing plans without add-ons have one item -->
```typescript
const GOOGLE_STATE = {
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD: "grace",
  SUBSCRIPTION_STATE_ON_HOLD: "retry",
  SUBSCRIPTION_STATE_PAUSED: "paused",
  SUBSCRIPTION_STATE_EXPIRED: "expired",
} as const;

export function normalizeGoogle(p: GoogleSubscription, startedAt: number, revokedAt: number | null): Snapshot | null {
  const gs = p.subscriptionState;
  if (gs === "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED") return null;
  if (gs === "SUBSCRIPTION_STATE_PENDING") return { state: "pending", phase: "regular", willRenew: false, expiresAt: null, observedAt: startedAt };
  const item = p.lineItems[0];
  const expiresAt = Date.parse(item.expiryTime);
  const renews = item.autoRenewingPlan?.autoRenewEnabled === true;
  const offer = Object.keys(item.offerPhase ?? {})[0];
  const phase = offer === "freeTrial" ? "trial" : offer === "introductoryPrice" ? "intro" : "regular";
  let state: State;
  if (revokedAt !== null) state = "revoked";
  else if (gs === "SUBSCRIPTION_STATE_ACTIVE") state = phase === "trial" ? "trial" : "active";
  else if (gs === "SUBSCRIPTION_STATE_CANCELED") state = expiresAt > startedAt ? "canceled" : "expired";
  else state = GOOGLE_STATE[gs as keyof typeof GOOGLE_STATE] ?? "expired";
  const over = state === "expired" || state === "revoked";
  return { state, phase, ownership: "purchased", observedAt: startedAt, willRenew: !over && renews,
           expiresAt: state === "revoked" ? revokedAt : expiresAt };
}
```

Rules:

- During grace Google "dynamically extends the `expiryTime`" until the grace period ends, so `expiresAt` is the access end in `grace`; during account hold `expiryTime` is in the past [SG3].
- `SUBSCRIPTION_STATE_CANCELED` with an `expiryTime` already past means the entitlement ended: the state is `expired` [SG3: "If that date is in the past, then the user should lose entitlement immediately"].
- `renewalPrice` is `autoRenewingPlan.recurringPrice` converted to milliunits; Google says it excludes discounts and taxes [SG4].
- `autoResumeAt` is `pausedStateContext.autoResumeTime`. A pause schedule (type 11) leaves the state `active` until type 10 [SG3].
- `priceChange`: `autoRenewingPlan.priceChangeDetails.priceChangeState` `OUTSTANDING` is `pending_consent`, `CONFIRMED` is `accepted`, `APPLIED`, `CANCELED` and unspecified are `none` [SG4]. An opt-in increase the player ignores ends in an automatic cancellation on the renewal date [SG11].
- `pendingPlanRef` comes from `lineItems[].deferredItemReplacement` when present.
- `linkedChainRef` is `linkedPurchaseToken`; `accountHint` is `externalAccountIdentifiers.obfuscatedExternalAccountId`; `environment = sandbox` when `testPurchase` is present.
- A purchase token is valid for API calls until 60 days after expiration [SG3]; a refresh of an older chain returns an error that the reconcile job treats as "leave the stored state".
- The package name must equal `GOOGLE_PACKAGE_NAME`.

### 2.3 Guard and compare-and-swap

A snapshot is applied only when the guard accepts it, and the write is a compare-and-swap so two workers cannot interleave.

<!-- PATTERN: snapshot-guard -->
<!-- PURPOSE: decide whether a snapshot may change a chain, so stale and duplicate data is harmless -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: `reinstated` is true when an Apple snapshot clears the revocation after the purchase record left `refunded`; `newTransaction` is true when the snapshot's newest store_transaction_id is not yet a term of the chain; none of this depends on the runtime -->
```typescript
export function acceptSnapshot(
  chain: { state: State; snapshotAt: number; platform: "apple" | "google" },
  snap: Snapshot,
  newTransaction: boolean,
  reinstated: boolean,
): boolean {
  if (snap.observedAt < chain.snapshotAt) return false;           // older than what is stored
  if (chain.state === "revoked") {
    return newTransaction || (chain.platform === "apple" && reinstated); // Google revocation is sticky
  }
  if (chain.state === "expired") return newTransaction;           // only a new term revives it
  return true;
}
```

Ties (`observedAt` equal to `snapshotAt`) are accepted: re-applying an identical snapshot is a no-op (`applied_no_change`).

<!-- PATTERN: chain-compare-and-swap -->
<!-- PURPOSE: write a chain only if nobody else wrote it since it was read and the snapshot is not older -->
<!-- REFERENCE: dialect=postgres orm=raw-sql -->
<!-- ADAPT: `$n` placeholders -> your driver's style (`?` on SQLite and MySQL); `now()` -> `datetime('now')` on SQLite; the statement is identical on the three dialects otherwise; run it in the same transaction as the term upsert and the slice inserts -->
```sql
UPDATE subscription_chains
   SET state = $3, phase = $4, will_renew = $5, expires_at = $6, snapshot_at = $7,
       revision = revision + 1, updated_at = now()
 WHERE id = $1 AND revision = $2 AND snapshot_at <= $7;
-- 0 rows: re-read the chain, run acceptSnapshot again, stop when it now answers stale
```

### 2.4 Composition

<!-- PATTERN: entitlement-composition -->
<!-- PURPOSE: compute the contract result for one product from the account's chains at one instant -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: `iso` -> your timestamp serializer; chains are loaded by (tenant_id, account_id) with their product level joined from subscription_plans and subscription_products; the read-through refresh happens before this call, outside the pure function -->
```typescript
const ENTITLED = new Set(["trial", "active", "canceled", "grace"]);
const ORDER = ["retry", "paused", "pending", "revoked", "expired"];

export function entitlement(chains: ChainView[], product: { groupCode: string; level: number }, now: number) {
  const eligible = chains.filter((c) => c.groupCode === product.groupCode && c.level >= product.level);
  const live = eligible
    .filter((c) => ENTITLED.has(c.state) && c.expiresAt !== null && now < c.expiresAt)
    .sort((a, b) => b.expiresAt! - a.expiresAt!);
  const rank = (c: ChainView) => (ORDER.indexOf(c.state) + 1 || 99);
  const pick = live[0] ?? [...eligible].sort((a, b) => rank(a) - rank(b) || (b.expiresAt ?? 0) - (a.expiresAt ?? 0))[0];
  if (!pick) return { active: false, state: "none", expires_at: null, will_renew: false };
  return { active: live.length > 0, state: pick.state, expires_at: pick.expiresAt === null ? null : iso(pick.expiresAt), will_renew: pick.willRenew };
}
```

## 3. Event handler

The handler is registered twice with family `subscription`: `register_notification_handler("apple", "subscription", handler)` and `register_notification_handler("google", "subscription", handler)`. The receivers route every Apple notification type except `ONE_TIME_CHARGE`, `REFUND`, `REFUND_REVERSED`, `REFUND_DECLINED`, `CONSUMPTION_REQUEST` and `TEST`, and every Google `subscriptionNotification`; they handle the excluded types themselves. Input: `{platform, event_id, message}` where `message` is the verified, decoded Apple `responseBodyV2DecodedPayload` (with decoded `signedTransactionInfo` and `signedRenewalInfo`) or the decoded Google `DeveloperNotification`.

Steps, in order; any failure before step 8 returns a failure so the receiver answers non-2xx and the store redelivers:

1. Insert the event row (`outcome = pending`). On a unique violation: when the stored outcome is terminal (`applied`, `applied_no_change`, `stale`, `unlinked`, `ignored`) return `duplicate` and succeed without any other action; when it is `pending` or `failed`, increment `attempts` and continue (a retry).
2. Check `bundleId` or `packageName` and `environment`; on mismatch record `ignored`, alert, succeed.
3. Types the block ignores (tables below): record `ignored`, succeed.
4. Resolve the chain by `chain_ref`; when absent it is created in step 6.
5. Build the snapshot: Apple from the message; Google by calling `purchases.subscriptionsv2.get` with the token (one retry on a transient error, then fail the handler). Record the fetch start time as `observedAt`.
6. In one transaction: guard; chain insert or compare-and-swap update; upsert the newest term; for a new term, insert its slice rows (README section 3) and mark the term `purchase_id` pending; resolve the account of a new chain from `accountHint` through `subscription_account_tokens` (found: bound; not found: `account_id` null, outcome `unlinked`).
7. After commit: write the purchase record for a new term with `record_verified_purchase` (`product_kind = subscription_term`, `store_transaction_id` = the term id, `environment`, the bound account or none) and store the returned id in `purchase_id`; for Google, when the snapshot is entitled and unacknowledged, acknowledge (section 3.3); evaluate the trial-ending reminder for a trial term (section 10); fire `subscription_state_changed` and analytics events.
8. Update the event row (`outcome`, `chain_id`, `processed_at`) and succeed.

A failure in step 7 leaves the event `pending`; the reconcile job (section 8) completes it. Every step is idempotent: the term upsert is by `store_transaction_id`, the record writer is idempotent by `store_transaction_id`, acknowledgement is skipped once acknowledged.

### 3.1 Apple notification types [SA1, SA2]

All 23 `notificationType` values are listed; six are never routed here. Action `apply` builds the snapshot from the message and runs steps 4 to 8.

| `notificationType` (subtype) | Action |
|---|---|
| `SUBSCRIBED` (`INITIAL_BUY`, `RESUBSCRIBE`) | apply; new term; account from `appAccountToken` |
| `DID_RENEW` (none, `BILLING_RECOVERY`) | apply; new term |
| `DID_FAIL_TO_RENEW` (none, `GRACE_PERIOD`) | apply. With `GRACE_PERIOD` keep service; without it stop service [SA1] |
| `GRACE_PERIOD_EXPIRED` | apply |
| `EXPIRED` (`VOLUNTARY`, `BILLING_RETRY`, `PRICE_INCREASE`, `PRODUCT_NOT_FOR_SALE`, none) | apply; `end_reason` from the subtype |
| `DID_CHANGE_RENEWAL_STATUS` (`AUTO_RENEW_ENABLED`, `AUTO_RENEW_DISABLED`) | apply |
| `DID_CHANGE_RENEWAL_PREF` (`UPGRADE`, `DOWNGRADE`, none) | apply; upgrade takes effect immediately with a new term, downgrade at the next renewal, empty subtype cancels a pending downgrade [SA1] |
| `OFFER_REDEEMED` (`UPGRADE`, `DOWNGRADE`, none) | apply; record `offer_kind` |
| `PRICE_INCREASE` (`PENDING`, `ACCEPTED`) | apply; `priceChange` from `priceIncreaseStatus` |
| `REFUND`, `REFUND_REVERSED`, `REFUND_DECLINED` | not routed here: `billing.virtual-currency` records them on the purchase record and fires `on_purchase_state_changed`; this block reacts through that hook (section 6) |
| `REVOKE` | apply; Family Sharing ended or refund (section 6) |
| `RENEWAL_EXTENDED` | apply (new `expiresDate`) |
| `RENEWAL_EXTENSION` (`SUMMARY`, `FAILURE`) | ignored; operator tooling only |
| `CONSUMPTION_REQUEST`, `ONE_TIME_CHARGE`, `TEST` | not routed here (owned by `billing.virtual-currency`); an operator answers consumption requests outside this block |
| `EXTERNAL_PURCHASE_TOKEN`, `METADATA_UPDATE`, `MIGRATION`, `PRICE_CHANGE`, `RESCIND_CONSENT` | ignored (Advanced Commerce, external-purchase and consent types are out of scope) |

An unlisted future type is handled as `apply` when its `data` carries `signedTransactionInfo` for a subscription, else ignored. Apple expects 200 to 206 for success and 40x or 50x to trigger a retry; any other code counts as failed [SA5].

### 3.2 Google notification types [SG1]

`notificationType` of a `subscriptionNotification`. Every type triggers the same action: fetch and apply (step 5). The type is used only to mark a revocation, label the log and analytics, and pick `end_reason`.

| Type | Name | Extra |
|---|---|---|
| 1 | `SUBSCRIPTION_RECOVERED` | recovered from hold or resumed from pause |
| 2 | `SUBSCRIPTION_RENEWED` | new term |
| 3 | `SUBSCRIPTION_CANCELED` | also sent when a hold ends unrecovered |
| 4 | `SUBSCRIPTION_PURCHASED` | new term; new chain; acknowledge |
| 5 | `SUBSCRIPTION_ON_HOLD` | |
| 6 | `SUBSCRIPTION_IN_GRACE_PERIOD` | |
| 7 | `SUBSCRIPTION_RESTARTED` | player undid a cancellation before expiry; same token |
| 8 | `SUBSCRIPTION_PRICE_CHANGE_CONFIRMED` | marked obsolete by Google; refresh only |
| 9 | `SUBSCRIPTION_DEFERRED` | recurrence extended; refresh |
| 10 | `SUBSCRIPTION_PAUSED` | |
| 11 | `SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED` | state stays active until type 10 |
| 12 | `SUBSCRIPTION_REVOKED` | **set `revoked_at` from `eventTimeMillis` before applying** |
| 13 | `SUBSCRIPTION_EXPIRED` | |
| 17 | `SUBSCRIPTION_ITEMS_CHANGED` | add-on bundles are out of scope; refresh |
| 18 | `SUBSCRIPTION_CANCELLATION_SCHEDULED` | installment plans are out of scope; refresh |
| 19 | `SUBSCRIPTION_PRICE_CHANGE_UPDATED` | price migration outcome; refresh |
| 20 | `SUBSCRIPTION_PENDING_PURCHASE_CANCELED` | pending chain dropped |
| 22 | `SUBSCRIPTION_PRICE_STEP_UP_CONSENT_UPDATED` | consent period started or consent given (regions that require it); refresh |

Other fields in the same envelope: `voidedPurchaseNotification` with `productType` 1 (subscription) marks the chain revoked like type 12 and carries `orderId` and `refundType`; `pendingRefundReviewNotification` (a chargeback you may answer) is logged for operators; `oneTimeProductNotification` is not routed here; `testNotification` is answered. A type not listed here (the page lists none for 14, 15, 16, 21) triggers a refresh. Pub/Sub acknowledges a push on 102, 200, 201, 202 or 204 and resends otherwise [SG18].

### 3.3 Google acknowledgement

A new Google subscription purchase must be acknowledged within three days or the user is refunded and the purchase revoked [SG3, SG9]. The server acknowledges after the chain and term are committed (step 7), with `POST .../purchases/subscriptions/{subscriptionId}/tokens/{token}:acknowledge` (`subscriptionId` is optional since May 21, 2025 [SG7]), optionally passing the account identifiers. Rules:

- Acknowledge only entitled, non-pending snapshots (never while `SUBSCRIPTION_STATE_PENDING`; the three-day window starts when the purchase leaves pending [SG9]).
- A resubscribe is a new purchase with a new token and needs its own acknowledgement; an upgrade, downgrade or resubscribe is blocked while the existing subscription is unacknowledged [SG3], so the claim of a plan change acknowledges the old chain first.
- The reconcile job retries unacknowledged chains and alerts after `GOOGLE_ACK_ALERT_AFTER_HOURS`.

## 4. Claim, restore, binding, transfer

### 4.1 Claim

Input: `{platform, proof, confirm_transfer?}`; session account `A`.

1. Rate limit `CLAIM_RATE_LIMIT_PER_HOUR` per account.
2. Verify the proof. Apple: `verify_apple_transaction(signed_transaction)` from `billing.virtual-currency` (chain, bundle id, environment); then call Get All Subscription Statuses with the verified transaction id [SA10] and take the entry of that `originalTransactionId`. Google: call `subscriptionsv2.get` with the token; `404` or an invalid token is `proof_invalid`.
3. Map the product to a plan by (`platform`, `store_product_id`, base plan); an unknown product is `product_unknown`.
4. Resolve the token owner `T`: the account whose `subscription_account_tokens.token` equals `appAccountToken` / `obfuscatedExternalAccountId`; null when absent or unknown.
5. Decide binding with `bindDecision(chain.account_id, T, A)`:

<!-- PATTERN: bind-decision -->
<!-- PURPOSE: decide whether the caller may attach a store chain to their account -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: none; pure function of three ids. The surrounding claim handler loads chain.account_id and the token owner from the database -->
```typescript
export function bindDecision(
  chainAccount: string | null,   // account the chain is bound to now, null when unlinked
  tokenOwner: string | null,     // account owning the token the store echoed, null when absent or unknown
  caller: string,
): "bind" | "already_bound" | "conflict" {
  if (chainAccount === caller) return "already_bound";
  if (chainAccount !== null) return "conflict";
  if (tokenOwner !== null && tokenOwner !== caller) return "conflict";
  return "bind";
}
```

6. `bind`: set `account_id = A`, `bound_at = now`; apply the snapshot (section 2); the intake steps 6 to 8 run for the newest term. `already_bound`: apply the snapshot, return. `conflict`: unless `confirm_transfer` is true, return `409 linked_to_other_account` with no information about the other account. With `confirm_transfer`, require `now - bound_at >= TRANSFER_COOLDOWN_DAYS` (else `429 transfer_cooldown`), then rebind: `account_id = A`, `bound_at = now`, fire `subscription_transfer_completed`, and tell the previous account (in-app notice, optional push through `messaging.push-reengagement`).
7. Return `{linked, entitlement, detail}`.

A message arriving for a chain already bound never rebinds it from its token: the token only places an unbound chain.

### 4.2 Restore

The client collects what the store holds for the current store account: Apple, the signed transactions of the current subscription entitlements; Google, the purchase tokens that `queryPurchasesAsync` returns, with suspended subscriptions included (it returns them only when `includeSuspendedSubscriptions` is set [SG9]). The server runs the claim for each proof without transfer and returns per-proof outcomes. A restore finding nothing returns `not_found`, which the client turns into the "none found" state. Apple requires a restore path [SA15, SA16]; Google's resubscribe and restore flows live in the Play subscription center [SG10].

### 4.3 One store account, many app accounts

The store account and the app account are different identities: one Apple ID or Google account can be signed in to several app accounts (a family phone, a guest that later signs in, a reinstall under a new guest). The rules:

- The token attached at purchase links the purchase to the account that started it; renewals keep it, so notifications bind an unbound chain to that account [SA7, SA8].
- A chain has one app account at a time (INV-8).
- A second account holding the same store account can prove possession and ask for a transfer; it is never silent, rate-limited by the cooldown, and the previous account is told.
- Possession proof is a bearer credential (Apple signed transaction, Google purchase token). Claims are rate limited and logged without the proof (`security.md` T4).
- Guest to signed-in merge: `account_merged(from, to)` re-points the chains of `from` to `to`, deletes the token row of `from`, and does not count as a transfer.
- Account deletion: `account_deleted(account_id)` sets `account_id` null on the chains and deletes the token row. Store billing continues until the player cancels in the store, so the deletion screen shows the manage-subscription link.

## 5. Stipends

### 5.1 Schedule

<!-- PATTERN: stipend-slices -->
<!-- PURPOSE: compute the slice start times of one paid term and the ledger key of each slice -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: times are epoch milliseconds here, use your timestamp type; days are 86400 seconds, no calendar math, so the result is identical on every stack -->
```typescript
const DAY = 86_400_000;

export function sliceStarts(startsAt: number, endsAt: number, sliceDays: number | null): number[] {
  if (!sliceDays) return [startsAt];
  const count = Math.max(1, Math.floor((endsAt - startsAt) / (sliceDays * DAY)));
  return Array.from({ length: count }, (_, i) => startsAt + i * sliceDays * DAY);
}

export const stipendKey = (platform: string, storeTransactionId: string, slice: number) =>
  `subscriptions.stipend:${platform}:${storeTransactionId}:${slice}`; // at most 200 characters
```

When a paid term is first seen the handler writes one `stipend_grants` row per slice with `amount` and `currency` copied from the product. Status at write time: `skipped` with `trial` when the term phase is `trial` and `STIPEND_DURING_TRIAL` is false; `skipped` with `family_shared` when ownership is `family_shared` and `STIPEND_FOR_FAMILY_SHARED` is false; otherwise `pending`. A product with no stipend writes no rows. A term whose catalog plan or stipend setting changes later keeps its stored rows.

### 5.2 Runner

Every `STIPEND_RUNNER_INTERVAL_SECONDS`, and when an entitlement read finds an unbound-to-ledger due slice for the caller, select `pending` rows with `due_at <= now` whose chain has an account. For each:

1. Skip with `revoked` when the term has `revoked_at`; with `sandbox` when the chain is sandbox and `SANDBOX_STIPENDS` is false; with `held` when the account is held (`STIPEND_HOLD_AFTER_REVOKES`).
2. Call `grant(account_id, currency, amount, "subscriptions.stipend", source_ref, key)` with `source_ref` the term's `purchase_id` and `key` from `stipendKey`.
3. On `{applied, balance, entry_id}` (including a replay): set `status = applied`, `ledger_entry_id`, `account_id`, `applied_at`; fire `subscription_stipend_granted`.
4. On `idempotency_conflict` (the key was applied for other arguments, for example another account after a rebind): set `skipped` with `already_granted`; grant nothing.
5. On `unknown_reason` or `unknown_currency`: leave `pending`, alert (the `currency_flows` row is missing).
6. On any other failure: leave `pending`; the next run retries.

`pending` rows of an unbound chain wait; when the chain is bound they are granted, including slices that fell due while unbound. The runner never grants a slice for a term that was never verified.

### 5.3 Optional reversal

With `STIPEND_REVERSAL = spend_clamped`, when a term is revoked the runner debits each of its `applied` slices that has no `reversal_entry_id`: read the account's balance through `billing.virtual-currency`, debit `min(amount, balance)` with `spend(account_id, currency, amount, "subscriptions.stipend-reversal", source_ref, key)` and key `subscriptions.stipend-reversal:{platform}:{store_transaction_id}:{slice_index}`, and store `reversal_entry_id`. `spend` is all-or-nothing and a rejected `insufficient_balance` does not consume the key, so the clamp is the caller's job; a zero balance skips the slice. With `none` nothing is debited.

## 6. Refunds and revocation

- **Signals**: Apple refunds and refund reversals reach this block only through the purchase record: `billing.virtual-currency` handles `REFUND` and `REFUND_REVERSED` for a subscription term, sets the record state and fires `on_purchase_state_changed(store_transaction_id)`. The refreshed snapshot carries the revocation date and reason (`revocationReason` 0 other or 1 an issue in the app [SA9]). Apple `REVOKE` (Family Sharing ended or the purchaser refunded) is routed to the handler. Google type 12 is routed to the handler; voided purchase notifications of product type subscription are recorded by `billing.virtual-currency` and arrive through the hook. `REFUND_DECLINED` changes nothing.
- **Effect**: the chain becomes `revoked` when the revoked term is its newest term; `revoked_at` is set on the term; pending slices of the term become `skipped` with `revoked`; entitlement is gone on the next read; `subscription_refund_processed` fires. A refund of an older term only marks that term.
- **Record hook**: the hook handler finds the term by `store_transaction_id`, reads `purchase_record(store_transaction_id)` and treats the call as a wake-up for the term's chain: refresh from the store (Apple Get All Subscription Statuses, Google `subscriptionsv2.get`), then if the record says `refunded` and the term is the chain's newest, apply `revoked`; if the record is `verified` again after a refund, apply the snapshot with `reinstated`. The record is the truth, so the hook is also read by the reconcile job. The handler and the hook converge on the same state and both are idempotent.
- **Reversal**: a record that returns from `refunded` re-applies the snapshot with `reinstated`; Apple keeps the renewal date unchanged when it reverses a refund [SA1], so the entitlement returns with its original expiry. Slices skipped for `revoked` stay skipped; the next terms schedule normally.
- **Support tools**: Google `subscriptionsv2.revoke` takes a refund type (full, prorated, item based) [SG6]; Apple's Extend a Subscription Renewal Date endpoint compensates outages and cannot be reversed [SA13]. Neither is called by this block; the resulting notifications arrive through the handler.
- **Abuse**: with `STIPEND_HOLD_AFTER_REVOKES = N > 0`, an account with N or more revoked terms has new slices skipped as `held`; a person reviews it.

## 7. Offers, family sharing, price increases, plan changes

### 7.1 Trial and introductory eligibility

The store decides. Apple: introductory offers are one per subscription group per customer [SA16], and `isEligibleForIntroOffer` is evaluated across the group [SA21]. Google: `queryProductDetailsAsync` returns only offers the user is eligible for [SG9]; eligibility types are new customer acquisition, upgrade, and developer determined, the last decided by the app [SG14]. The server never grants a trial; a trial exists only as a store transaction. `trial_eligible_hint` in the intent response is advisory: true when no chain of the account in the group has ever had a `trial` or `introductory` term; the client uses the store's own eligibility whenever it can read it, and shows trial wording only for an eligible offer (`frontend.md` section 1). A player who resubscribes to the same Google SKU is not eligible for a trial or introductory price again [SG10].

### 7.2 Promotional offers, offer codes, win-back (optional)

Apple distinguishes introductory (`offerType` 1), promotional (2), offer code (3) and win-back (4) [SA9]. Offer codes are redeemed in the store and arrive as `OFFER_REDEEMED` or `SUBSCRIBED` with `offerType` 3 [SA1]. Promotional offers need a server-created signature: the App Store Server Library provides the signing function [SA14]; the signed fields and their order are in Apple's promotional-offer documentation and are not restated here. Win-back offers are shown by Apple to eligible customers; `eligibleWinBackOfferIds` in the renewal info lists them [SA7]. On Google a win-back is a developer-determined offer, and a player can resubscribe in the Play subscription center for up to one year after expiration [SG10].

With `WINBACK_ENABLED`, `GET /api/subscriptions/offers` returns an offer reference when the account's newest chain in the group is `expired` (not `revoked`), lapsed at least `WINBACK_MIN_LAPSE_DAYS`, and the store lists an eligible offer. The server returns the reference and, for Apple promotional offers, the signature; the client presents the offer with the same disclosure as any other (INV-14). `subscription_winback_shown` and `subscription_winback_redeemed` record it. Without the flag the endpoint returns `{}`.

### 7.3 Family Sharing

Apple lets a subscriber share an auto-renewable subscription with up to five family members when Family Sharing is enabled for the subscription in App Store Connect, which cannot be undone [SA16]. A family member's transactions carry `inAppOwnershipType = FAMILY_SHARED`; the purchaser's are `PURCHASED`; `ASSIGNED` is organization access [SA9]. The block grants entitlement for `FAMILY_SHARED` (ownership `family_shared`), grants no stipend by default (`STIPEND_FOR_FAMILY_SHARED`), ignores `ASSIGNED`, and revokes on `REVOKE` (sharing disabled, member left, or refund). A family member binds the chain through claim or restore.

### 7.4 Price increases

- Apple: when a price increase passes the per-storefront thresholds the customer must consent, otherwise the subscription expires at the end of the billing cycle [SA16, SA22]; notifications `PRICE_INCREASE` (`PENDING` while the customer has not responded, `ACCEPTED` after consent or when no consent is needed) and `EXPIRED` (`PRICE_INCREASE`) [SA1]. The app may delay the in-app consent sheet to avoid a critical moment [SA16].
- Google: increases are opt-in by default; the player must accept before the first charge at the higher price, with an advance period of 37 days and notifications starting 30 days before; if the player does nothing, the subscription is canceled and expires on that renewal date [SG11]. `SUBSCRIPTION_PRICE_CHANGE_UPDATED` (19) reports the outcome; `SUBSCRIPTION_PRICE_STEP_UP_CONSENT_UPDATED` (22) covers regions that require consent for a price step-up [SG1].
- The block records `price_change_state` and surfaces it as a banner. It does not change the entitlement; the store's refusal path reaches it as a normal expiry.

### 7.5 Plan changes

Upgrade: immediate, a new term, entitlement level rises at once (Apple credits a prorated refund of the unused period [SA16]). Downgrade: effective at the next renewal; the current plan stays entitled and `pending_plan_code` records the scheduled plan. Crossgrade: a switch to an equal level; same duration starts immediately, a different duration at the next renewal [SA16]. Apple `UPGRADE` also covers a crossgrade of the same duration and `DOWNGRADE` a crossgrade of a different duration [SA2].

Google: an upgrade, downgrade or resubscribe before expiry invalidates the old purchase and creates a new one with a new token whose `linkedPurchaseToken` names the old [SG3]. The handler creates the new chain with `linked_chain_id` set, refreshes the old chain, and gives it `end_reason = replaced` when it expires. Composition (section 2.4) keeps access continuous whichever chain reports first. The replacement mode is an app choice [SG10]: the default for an upgrade is `WITH_TIME_PRORATION`, the default Google documents; a downgrade uses `DEFERRED`, which applies the change at renewal. The intent response `change` field carries `{kind: upgrade|downgrade|crossgrade, replacement_mode}` for Google.

## 8. Reconcile and catch-up jobs

- **Read-through**: when `entitlement` finds an entitled chain with `now >= expires_at`, it refreshes that chain once, bounded by `READ_REFRESH_TIMEOUT_MS` and `REFRESH_MIN_INTERVAL_SECONDS`, then recomputes. If the store is unreachable, access continues while `now < expires_at + ENTITLEMENT_LAG_ALLOWANCE_SECONDS`.
- **Reconcile** every `RECONCILE_TROUBLE_INTERVAL_SECONDS`: refresh chains in `grace`, `retry`, `paused`, `pending`; entitled chains past `expires_at`; any chain with `snapshot_at` older than `RECONCILE_MAX_AGE_SECONDS`; events stuck `pending`; unacknowledged Google chains; re-emit the current `armed` trial-ending event of every trial term in progress (duplicates are harmless: the push block dedupes on `subject_key`). Refreshes are serialized per chain and use the same guard.
- **Apple catch-up**: after an outage, call Get Notification History for the window `now - CATCHUP_LOOKBACK_DAYS` to now (page of up to 20, repeat with the pagination token and the same request body [SA12]); run each record's signed payload through the verification and handler path. Records show the state at send time [SA12], so the guard applies as for live messages.
- **Revocation sweep**: Apple refund history for chains with recent activity; Google `voidedpurchases.list` with `type=1` and a start time within 30 days [SG8]; matches mark revocations as in section 6.

## 9. Errors

| Code | HTTP | Meaning |
|---|---|---|
| `unauthenticated` | 401 | No session |
| `plan_not_found` | 404 | Unknown or inactive `plan_code` |
| `already_entitled` | 409 | Intent for a plan in a group where the account is entitled and the request is not a same-platform change |
| `linked_to_other_account` | 409 | The chain belongs to another app account; retry with `confirm_transfer` |
| `proof_invalid` | 422 | The store did not confirm the proof |
| `product_unknown` | 422 | The store product matches no plan |
| `environment_not_accepted` | 422 | Sandbox proof while only production is accepted |
| `bundle_mismatch` | 422 | Proof for another app |
| `transfer_cooldown` | 429 | Rebinding too soon; includes `retry_after_seconds` |
| `rate_limited` | 429 | Claim or refresh rate limit |
| `store_unavailable` | 503 | The store API could not be reached; the client retries later |

Handler outcomes are not HTTP codes: they are the event row outcomes of the README data model. A claim never reveals whether another account holds a chain beyond `linked_to_other_account`.

## 10. Trial-ending reminder

### 10.1 Eligibility

A term arms a reminder only when all hold: phase `trial`, ownership `purchased`, environment `production`, the chain state is `trial` with auto-renew on, and the term is the chain's newest. A paid introductory price is already paid, a family member pays nothing, and sandbox trials are test data, so none of them arm.

### 10.2 Pure plan

<!-- PATTERN: trial-reminder-plan -->
<!-- PURPOSE: decide from current facts whether to resolve the armed reminder and whether to arm a new one -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: times are epoch milliseconds, use your timestamp type; `Facts` is built from the chain and its newest term; `armedEndsAt` is subscription_terms.reminder_ends_at; no runtime API is used -->
```typescript
export function reminderPlan(f: Facts, armedEndsAt: number | null, now: number, c: Cfg) {
  const eligible = f.phase === "trial" && f.ownership === "purchased" && f.environment === "production"
    && f.state === "trial" && f.willRenew && f.isNewestTerm;
  if (armedEndsAt !== null && eligible && armedEndsAt === f.endsAt) return { resolve: false, arm: null };
  const resolve = armedEndsAt !== null;                        // facts changed or the term stopped being eligible
  const roomLeft = f.endsAt - now >= c.minNoticeSeconds * 1000;
  if (!eligible || !roomLeft) return { resolve, arm: null };
  const lead = Math.min(c.leadSeconds * 1000, (f.endsAt - f.startsAt) / 2);
  return { resolve, arm: { fireAt: Math.max(f.endsAt - lead, now), expiresAt: f.endsAt } };
}
```

The minimum-notice check applies only when arming, so an armed reminder is not resolved merely because time passed.

### 10.3 Emission

- Evaluate after every chain commit that touches a trial term (handler step 7, claim, restore) and in the reconcile job.
- When `resolve` is true, emit `resolved` with `subject_key = trial:{term_id}:{reminder_seq}`, then add one to `reminder_seq` and clear `reminder_ends_at`. When `arm` is set, emit `armed` with the current `reminder_seq`, `fire_at`, `expires_at` and the params of README section 6, and set `reminder_ends_at` to the term end. The counter and the column are written in the same transaction as the chain write; events are emitted after commit, at least once.
- `params` carries `renews_at` (the trial `ends_at`) and, when the chain has a renewal price, `price_milliunits` and `currency_code`; with no price known the params omit both and the copy points to the store.
- Analytics: `subscription_trial_reminder_emitted` on `armed`; `subscription_trial_reminder_resolved` on `resolved` with `reason`: `canceled` (auto-renew off), `converted` (a newer term exists or the chain is `active`), `ended` (expired, revoked, retry, grace, paused), `changed` (the term end moved and a new occurrence follows).
- Push delivery after `armed` belongs to `messaging.push-reengagement`: its switches, quiet hours, caps and `expires_at` handling apply, and a notification the provider already accepted cannot be recalled. That is why `expires_at` is the trial end and why the in-app surfaces below exist.

### 10.4 In-app facts

`detail.trial_ending` is non-null while the chain state is `trial`, auto-renew is on, the term is eligible as in 10.1, and `ends_at - min(TRIAL_REMINDER_LEAD_SECONDS, half the trial length) <= server_now < ends_at`. It does not depend on `TRIAL_REMINDER_MIN_NOTICE_SECONDS` and does not read push state, so the banner shows the same facts when push is off, denied, deferred or suppressed. Fields: `ends_at`, `renews_at` (equal), `period`, `price_milliunits` and `currency_code` when known, `platform`.

### 10.5 What it never does

No offer, discount, urgency or loss wording, no upsell, no second reminder per occurrence, no permission prompt. It does not replace the pre-purchase trial disclosure of `frontend.md` section 1 (INV-14).

## Error handling

| Situation | Behavior |
|---|---|
| Message for an unknown chain with no token | Create the chain unlinked, outcome `unlinked`, succeed |
| Google fetch fails | Fail the handler; the store redelivers; the reconcile job also retries |
| Chain write loses the compare-and-swap | Re-read, run the guard, retry up to three times, then fail the handler |
| Record writer unavailable | Leave the event `pending`; reconcile completes it |
| Snapshot for a product not in the catalog | Record `ignored`, alert, succeed; no chain is created without a plan |
| Stipend ledger error other than conflict or unknown reason | Leave the slice `pending`, retry next run |

## Anti-patterns

| DON'T | Why |
|---|---|
| Replay notification types as transitions | Duplicates and reordering corrupt state; use snapshots |
| Trust the Google notification type or payload for state | It carries a token and a type only; fetch |
| Remove access when `SUBSCRIPTION_CANCELED` or `AUTO_RENEW_DISABLED` arrives | The player paid until `expires_at` |
| Keep access in `retry` or `paused` | Hold and pause are not entitled |
| Cache the client's claim as the entitlement | INV-1 |
| Key the stipend by account | A rebind would mint a second grant |
| Grant a trial or compute an introductory-offer eligibility yourself | The store enforces eligibility; the server only hints |
| Hard-code a price or a trial length in a paywall string | The store's offer is the source |
| Verify receipts a second way | `billing.virtual-currency` owns verification (INV-11) |
| Return or log `chain_ref` | It is a credential |
| Put an offer, a discount or urgency wording in the trial reminder | INV-19; it is information, and guide `15-manipulation-and-the-line.md` row 16 treats a silent or pressured trial conversion as a failure |
| Show the trial banner only when push is off | The facts must not depend on delivery; push is best-effort |
