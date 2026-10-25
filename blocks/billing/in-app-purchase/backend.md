# Backend Patterns — In-App Purchase: One-Time Unlock

> "Backend" here means everything that is not UI: the pure entitlement core, the store port, the store-side configuration, and the OPTIONAL server extension. The core block runs **without any server**: the source project reads the entitlement from the RevenueCat SDK on the device and keeps no purchase data on its server.
>
> Code snippets are L3 illustrative TypeScript with the four markers (`PATTERN`, `PURPOSE`, `REFERENCE`, `ADAPT`) per `docs/SPEC_GUIDELINES.md` section 6. The behavior (WHAT) is in the prose around each snippet.
>
> **External contracts kept concrete** in this file: the RevenueCat SDK call names and result fields the app reads (`configure`, `logIn`, `logOut`, `getCustomerInfo`, `getOfferings`, `purchasePackage`, `restorePurchases`, `addCustomerInfoUpdateListener`, `customerInfo.entitlements.active`, `offerings.current.availablePackages`, `package.product.priceString`), the package identifier `$rc_lifetime`, the numeric error codes below, and the public-key prefixes `goog_` / `appl_` / `test_`. Merchant projects do not choose these.

## Endpoints

The core block adds **no HTTP endpoints**. The store SDK talks to RevenueCat directly from the device. The OPTIONAL EXTENSION adds one inbound webhook endpoint (below).

---

## 1. Free-slice rule (pure)

Input: the ordered scope catalog, an item list where each item names its scopes, `FREE_SCOPE_COUNT`, and `FREE_RULE`.

Rules:

1. The free scopes are the first `FREE_SCOPE_COUNT` scopes in catalog order.
2. Rule `every` (default): an item is free when it has at least one scope **and** every scope resolves to a free scope.
3. An item with no scopes, or with a scope the catalog does not contain, is **not** free.
4. `FREE_SCOPE_COUNT = 0` frees nothing; a count at or above the number of scopes frees everything.
5. No other attribute (difficulty, length, type) is read.
6. The result is a set of item ids, computed once from static content.

<!-- PATTERN: free-slice-rule -->
<!-- PURPOSE: compute the set of free item ids from the ordered catalog, with no framework and no store dependency -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: `scopeKeys` -> however your items name scopes (a column, a join table, a mapping file; the source maps free-text skill phrases to scope ids first); read `catalog` from the `gated_scopes` table ordered by `sort_order` or from a bundled file; to ship the `any` rule replace `every` with `some` and keep the non-empty check -->
```typescript
interface Item { id: string; scopeKeys: string[] }

export function freeItemIds(
  catalog: { scopeKey: string }[],   // already in catalog order
  items: Item[],
  freeScopeCount: number,
): Set<string> {
  const free = new Set(catalog.slice(0, freeScopeCount).map((s) => s.scopeKey));
  return new Set(
    items
      .filter((i) => i.scopeKeys.length > 0 && i.scopeKeys.every((k) => free.has(k)))
      .map((i) => i.id),
  );
}
```

The unknown-scope case falls out of the set lookup: a key missing from the catalog is never in `free`.

## 2. Gate (pure)

<!-- PATTERN: keep-playable -->
<!-- PURPOSE: filter candidate ids to those the learner may play, preserving the caller's order -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic -->
<!-- ADAPT: none for the filter itself; the stateful wrapper that opens the paywall is in frontend.md "gate-choke-point" -->
```typescript
export const keepPlayable = (
  ids: readonly string[],
  free: ReadonlySet<string>,
  unlocked: boolean,
): string[] => (unlocked ? [...ids] : ids.filter((id) => free.has(id)));

export const hasPro = (active: Record<string, unknown>): boolean =>
  Object.hasOwn(active, "pro"); // customerInfo.entitlements.active
```

Rules:

- `unlocked` is `not storeActive or pro`. Owned and inert builds both pass every id through.
- The gate runs **before** a session is cut to its length. Locked ids are dropped and the places go to the next playable ids in the engine's own order, so a 10-item session stays 10 long while the free pool allows. Running the gate after truncation yields short or empty sessions.
- Items that can be re-entered from stored state (a saved, half-finished session) are not re-gated; they were gated when they started.

## 3. Store port (the one seam to the SDK)

The app talks to the store through one interface. The real implementation wraps the RevenueCat SDK; tests pass a fake; builds without a store pass the inert one. Every call answers a reply value, never throws: `{ ok: true, value }` or `{ ok: false, code }`. Each success value is "is `pro` active after this call".

<!-- PATTERN: purchases-port -->
<!-- PURPOSE: isolate the store SDK behind one testable interface with an inert implementation -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic api=revenuecat-capacitor api-version=13.x -->
<!-- ADAPT: the `Reply` type -> your error style (Result type, tagged union); `Offer` -> add fields only when the paywall shows them; keep `active` so callers can skip store work -->
```typescript
type Reply<T> = { ok: true; value: T } | { ok: false; code: string };
interface Offer { priceString: string }

export interface PurchasesPort {
  readonly active: boolean; // false: web, dev, no key
  start(appUserId: string | null, onChange: (pro: boolean) => void): Promise<Reply<boolean>>;
  identify(appUserId: string | null): Promise<Reply<boolean>>; // log in, or log out for null
  offer(): Promise<Reply<Offer | null>>; // first package of the current offering
  buy(): Promise<Reply<boolean>>;        // buys exactly the package offer() showed
  restore(): Promise<Reply<boolean>>;
}

const off = Promise.resolve({ ok: false, code: "inactive" } as const);
export const inertPurchases: PurchasesPort = {
  active: false, start: () => off, identify: () => off,
  offer: () => off, buy: () => off, restore: () => off,
};
```

### Real port: key selection and SDK mapping

The port is active only when the build runs on a native platform **and** carries the public SDK key for that platform. Anything else returns the inert port.

<!-- PATTERN: store-key-selection -->
<!-- PURPOSE: make "no key or not native" mean inert instead of broken or free-by-accident -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic api=revenuecat-capacitor api-version=13.x -->
<!-- ADAPT: `platform` and `isNative` -> your shell's API (Capacitor `getPlatform` / `isNativePlatform` in the source); `keys` -> however your build injects public env values (Vite `import.meta.env.VITE_*` in the source) -->
```typescript
function storeKey(
  isNative: boolean,
  platform: string,
  keys: { ios?: string; android?: string },
): string {
  if (!isNative) return "";
  if (platform === "ios") return keys.ios ?? "";
  if (platform === "android") return keys.android ?? "";
  return "";
}

export function purchasesPort(): PurchasesPort {
  const key = storeKey(isNative(), platform(), keys);
  if (!key) return inertPurchases;
  return realPort(key); // wraps the SDK calls in the mapping below
}
```

SDK mapping the real port performs (RevenueCat Capacitor plugin names, concrete):

| Port call | SDK calls | Result read |
|---|---|---|
| `start(uid, onChange)` | `configure({ apiKey, appUserID: uid })`, `addCustomerInfoUpdateListener`, `getCustomerInfo()` | `entitlements.active` contains `pro` |
| `identify(uid)` | `getCustomerInfo()` when the id is unchanged, else `logIn({ appUserID: uid })`, or `logOut()` for null | same |
| `offer()` | `getOfferings()` | `current.availablePackages[0]`, `product.priceString`; null when there is no package |
| `buy()` | `purchasePackage({ aPackage })` with the package `offer()` returned | same |
| `restore()` | `restorePurchases()` | same |

Rules:

- The offering the app sells has **exactly one package** (`$rc_lifetime`). `offer()` takes the first package; a second package added in the dashboard changes what is sold.
- `buy()` purchases the package `offer()` showed, not a fresh lookup. Without a prior `offer()` it answers code `noOffer`.
- Load the SDK module on first use so the web build never evaluates it.
- Capacitor trap (observed): the plugin object is a proxy that answers every property, including `then`. Returning it directly from a promise makes the runtime call a native `then` and hang. Carry it inside a plain object: `{ p: plugin }`.

## 4. Error taxonomy

The numeric strings are RevenueCat `PURCHASES_ERROR_CODE` values as used in the source project's mapping; the port-level code `noOffer` is app-defined. A failed call returns the code as a string; anything unlisted (or a thrown value with no code) maps to `store`.

| Code | RevenueCat name | Problem | What the learner sees |
|---|---|---|---|
| `1` | PURCHASE_CANCELLED_ERROR | `cancelled` | Nothing. Not an error |
| `10` | NETWORK_ERROR | `network` | One-line "check your connection" message |
| `35` | OFFLINE_CONNECTION_ERROR | `network` | same |
| `32` | PRODUCT_REQUEST_TIMED_OUT_ERROR | `network` | same |
| `3` | PURCHASE_NOT_ALLOWED_ERROR | `notAllowed` | Purchases are disabled on this device (parental controls, payments off) |
| `20` | PAYMENT_PENDING_ERROR | `pending` | Waiting for approval (Ask to Buy, deferred payment); unlocks later through the update listener |
| `6` | PRODUCT_ALREADY_PURCHASED_ERROR | `owned` | Already purchased; suggest Restore |
| `5` | PRODUCT_NOT_AVAILABLE_FOR_PURCHASE_ERROR | `unavailable` | Product unavailable in the store |
| `noOffer` | (app-defined) | `unavailable` | same |
| anything else | | `store` | Generic store problem |

<!-- PATTERN: purchase-problem-map -->
<!-- PURPOSE: turn store error codes into the small set of messages the learner can act on -->
<!-- REFERENCE: runtime=node20+ language=typescript framework=agnostic api=revenuecat-capacitor api-version=13.x -->
<!-- ADAPT: message keys -> your i18n catalog (one `err.<problem>` string per problem, all locales); the code list -> the current RevenueCat error-code table if your SDK version differs -->
```typescript
type Problem = "cancelled" | "network" | "notAllowed" | "pending" | "owned" | "unavailable" | "store";

export function purchaseProblem(code: string): Problem {
  switch (code) {
    case "1": return "cancelled";
    case "10": case "35": case "32": return "network";
    case "3": return "notAllowed";
    case "20": return "pending";
    case "6": return "owned";
    case "5": case "noOffer": return "unavailable";
    default: return "store";
  }
}
```

## 5. Reviewer access (operational contract)

Reviewers must reach the paid content. This is part of the block because a release without it risks a rejected or un-reviewable submission.

- **Google Play**: when the "App access" declaration says access is restricted, the "Sign in details" form (500-character limit in the source project) explains that content is free and the unlock is paid, and gives promo codes for `PRODUCT_ID`. Codes are one-time, start the day after creation, and are stored in a git-ignored secrets folder, never in this repo or in a spec.
- **App Store**: the IAP is submitted with the first app version and needs a paywall screenshot (see README section 7, step 5). The app must show Restore purchases.

Keep store listing text consistent with the declaration: the source project's listing file still claimed "no credentials needed" after the declaration changed to "Sign in details = Yes".

## 6. OPTIONAL EXTENSION, not production-verified: server entitlement mirror

> Not built in the source project. The source proposed "RevenueCat webhook to the database" and chose to read the SDK only. Build this only when a **server** must decide access (paid content delivered by an API, support tooling, cross-platform checks). The core block stays valid without it.

Behavior to specify when you build it:

1. One inbound HTTPS endpoint that RevenueCat calls on entitlement changes.
2. Authenticate every call with a shared secret set in the RevenueCat dashboard and checked with a constant-time comparison; reject with 401 otherwise and never log the secret or the body.
3. Upsert one `entitlement_mirror` row per (`account_id`, `entitlement_key`); set `is_active` from the event; apply an event only when its time is newer than `last_event_at`, so late deliveries cannot undo a newer state.
4. Treat events for anonymous store users (ids that are not account uids) as not applicable to any account and acknowledge them.
5. The server answers "does this account own `pro`" from the mirror. The client keeps reading the SDK; the mirror is never the only source for a client gate.

**Not captured here, take from RevenueCat's current webhook documentation before building**: event type names, the exact authorization header contract, retry behavior, and how an anonymous-to-identified transition (log in) is reported. The source project's evidence does not cover them.

## Error handling

| Situation | Behavior |
|---|---|
| Store call fails | Reply `{ ok: false, code }`; map with `purchase-problem-map`; never throw into the UI |
| Store not reachable at start | The next store action (offer, buy, restore) retries configuring; buy/restore report `network` if it still fails |
| Offering has no package | `offerState = none`; no Buy button; Restore remains |
| Owned but store reports not-owned later (refund) | The update listener flips `pro` to false; the next gate call locks again |

## Anti-patterns

| DON'T | Why |
|---|---|
| Hard-code the price in the paywall or the listing copy inside the app | Currency, tax, and storefront change the price; the store string is the only correct one |
| Gate in each screen separately | One missed entry gives the content away; use the one choke point |
| Ship a native build without the store key | Purchases silently turn off and the app is free (this happened to the source project's first release) |
| Ship the RevenueCat Test Store key (`test_` prefix) in an uploaded build | It sells nothing real; keep it for screenshots and sandbox only |
| Gate by difficulty | A learner who never reaches the hard tier never sees what is sold, and a paywall on a hard item feels like a trap (the source agent's recommendation, not a measured result) |
| Open the paywall at launch | The learner has seen no value yet |
| Use the email as the store user id | The id travels to a third party; use the opaque account uid (extrapolated privacy rule, not from the source) |
