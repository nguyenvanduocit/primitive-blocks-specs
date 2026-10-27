# Frontend Patterns: Virtual Currency

> The client is a web-tech app in a native shell and keeps framework-agnostic logic. Snippets are L3 illustrative TypeScript with the four markers per `docs/SPEC_GUIDELINES.md` section 6; map state to your framework's reactive primitive. The behavior (WHAT) is in the prose.
>
> The client never decides a balance, an amount, a limit or whether a purchase happened. It shows what the server says, talks to the store through one port, and submits proofs. Server rules are in `backend.md`; the data contract is in `README.md`.
>
> Screens come first (purpose, states, copy rules, accessibility, events); the client logic follows.

## Component tree

```
App shell
 ├── WalletHud                  balances of the currencies the screen cares about; opens PackPrices
 ├── ShopScreen
 │    ├── RefundNotice          unseen refund notices (banner)
 │    ├── GuestNudge            signed-out players only
 │    ├── SpendLimitBanner      only when a limit exists
 │    ├── StarterOfferCard      only while eligible
 │    ├── PackCard (n)          contents, bonus, store price, Buy
 │    └── PendingPurchasesRow   purchases waiting for payment approval
 ├── ParentalGate               host component, called through purchase_policy
 ├── ConfirmPurchaseSheet       contents, store price, remaining limit, Buy / Not now
 ├── PurchaseStatusSheet        verifying, pending, failed, rejected, blocked
 ├── PurchaseReceipt            what was credited and what was charged
 ├── InsufficientBalanceSheet   mounted once at the shell; opened by any spend caller
 ├── ApproxMoney                "about <amount>" beside a gem price
 ├── SpendingScreen             limit, spent, pending change; purchase history
 └── (no UI) PurchaseRecovery   runs at launch and on resume
```

| Unit | Responsibility | Interface |
|---|---|---|
| `wallet` state holder | Balances, refund notices, `server_offset` | `refresh()`, readable state |
| `shop` state holder | Catalog, store product details, eligibility, purchase flow state | `open(source)`, `select(code)`, `confirm()`, `retry()` |
| `StorePort` | The one seam to StoreKit and Play Billing | below |
| `PurchaseRecovery` | Finds unfinished store transactions and submits them | `run(source)` |
| Screens | Render state; no business logic | read state, call the holders |

The shop and the sheets are mounted once at the shell and shown by state. The shop never opens by itself: only a player action (tapping the HUD, a pack link, a "need more" sheet) opens it.

---

## Screens

### 1. Wallet HUD

**Purpose.** Show the balance of each currency the current screen uses, and give a path to pack prices wherever a purchasable currency is shown.

| State | Behavior |
|---|---|
| Loading (first fetch) | Placeholder of the same width; no zero shown |
| Loaded | Number with thousands separators for the locale |
| Stale (offline, last value kept) | Last value plus a small "offline" mark; spends and purchases are decided by the server, so the player can still try |
| Changed | Counts up from old to new in at most one second; with reduced motion the number replaces itself |
| Error (never loaded) | "Balance unavailable" with a retry |

Copy rules. The balance is a number and the currency name. A purchasable currency's HUD is tappable and opens the shop's "Pack prices" view (INV-24). No "running low" pressure text.

Accessibility. One accessible name per chip: "Gems: 1,240". A polite live region announces a change once ("Gems: 1,290, plus 50"); no announcement while counting. Tap target at the platform minimum. The count-up respects the reduced-motion setting.

Events. None (the ledger events are server-written).

### 2. Shop

**Purpose.** Sell packs. One list, ordered by `sort_order`, with the store's price on each.

| State | Behavior |
|---|---|
| Loading | Skeleton cards, no prices |
| Ready | Cards with prices from the store |
| Store prices unavailable | Cards without Buy; text "Prices could not be loaded" and Try again. No price is guessed or cached from an earlier session |
| Empty (no pack for this platform) | "Nothing to buy right now" and no error tone |
| Server error / offline | Message and Try again; the HUD still shows the last balances |
| Purchases disabled (`purchase_policy`) | Cards visible but Buy disabled, with the reason: `age` ("Purchases are off for this profile"), `region` ("Purchases are not available here"), `review` ("Purchases are paused for this account. Contact support") |
| Limit reached | Buy disabled on cards that do not fit; the banner states the limit, what was spent and the earliest time the pack would fit (`next_room_at`; no time is shown when it is null, and the text says the pack is above the limit) |
| Guest | GuestNudge above the list |

Copy rules.
- Every card shows the store's localized price string beside the Buy control. Nothing computes or edits a pack price (INV-16).
- A product with `random_reward` shows its odds link (`odds_url`) beside the price and again on the confirmation sheet; a pack with fixed contents has none.
- Contents are separate numbers: base amount, bonus, first-purchase bonus ("500 + 50 bonus + 500 first purchase bonus"). The first-purchase bonus appears only when the server returned a non-null value. No "best value" or "most popular" label computed from price.
- No pack is preselected, highlighted by default, or opened automatically.
- Starter offer: the card says what it contains, that it is a one-time offer, and shows an end time only when `ends_at` is not null and `countdown_offers_allowed` is true. The countdown counts down from `server_now` (below). No "last chance" copy, no fake stock.
- "Pack prices" is this same screen; from a gem price elsewhere it opens scrolled to the top with no pack selected.

Accessibility. Each card is one region with a heading (the pack name), the contents as a list, the price as text, and a Buy button whose name includes the pack and price ("Buy 500 gems, $4.99"). Disabled Buy keeps its name and exposes the reason through the description. Focus order: banners, cards in order, history link.

Events. `shop_viewed` { `source` }; `offer_shown` { `offer_id`, `placement` } once per card per view (placement `shop`, `starter_banner`, `insufficient_balance`); `pack_selected` { `product_code`, `position` }.

### 3. Starter offer card

Same as a pack card plus: "One-time offer". When a window exists: "Available until <local time>" and a visible time left that refreshes every minute; screen readers get the end time once, not every tick. After purchase or when the server omits it, the card disappears at the next refresh. A repeat purchase of a hidden starter product (a second device) is delivered in full; the receipt says so.

### 4. Parental gate (host hook)

**Purpose.** Meet the platform's rule that purchasing opportunities for children sit behind a parental gate (Apple Review Guidelines 1.3 for the Kids Category: purchasing opportunities "unless reserved for a designated area behind a parental gate", [Apple](https://developer.apple.com/app-store/review/guidelines/), HIGH).

The host app owns the gate and the age decision. `purchase_policy` returns `parental_gate_required`; when true, the gate runs after the player taps a pack (and before a spend-limit change) and before any intent call. Gate passed: continue. Gate failed or dismissed: return to the shop; nothing is sent. The gate is required again for each purchase attempt. Events: `parental_gate_shown` { `context`: `purchase` or `spend_limit` }, `parental_gate_result` { `context`, `passed` }.

### 5. Confirm purchase sheet

**Purpose.** A deliberate step before the store sheet: the player sees what they get and what it costs.

Content: pack name, contents (base, bonus, first-purchase bonus, as separate numbers), the store's price string on the Buy button ("Buy for $4.99"), the account the gems go to for a guest ("This profile only, on this device"), and, when a limit exists, "Under your limit: $10.01 left of $20.00". A product with `random_reward` also shows its odds link (`odds_url`). Buttons: "Buy for <price>" and "Not now", the same size and weight, "Not now" first in focus order.

| State | Behavior |
|---|---|
| Shown | Buttons enabled |
| Intent pending | Buy shows a spinner; second taps ignored |
| Intent refused | Sheet replaced by the reason (limit reached with `next_room_at`, currency mismatch, policy) |
| Dismissed | Back to the shop, nothing sent |

When `PURCHASE_CONFIRMATION` is `off` the intent check still runs and the confirmation is skipped; the Buy button on the card then carries the price and contents.

Accessibility. Modal dialog, focus moves to the heading, returns to the tapped card on close, Escape or the platform back action equals "Not now".

Events. `purchase_confirm_shown` { `product_code` }, `purchase_confirmed` { `product_code` }, `purchase_confirm_dismissed` { `product_code` }.

### 6. Purchase status sheet

One sheet, one state at a time, after the player confirms.

| Flow state | What the player sees | Actions |
|---|---|---|
| `store_sheet` | Nothing of ours (the store's sheet is on top) | |
| `verifying` | "Adding to your balance..." with a spinner. The player may leave; the work continues | Close |
| `granted` | Receipt (screen 7) | Done |
| `pending` | "Waiting for payment approval. We will add your gems when the store confirms. You can keep playing." | Close |
| `cancelled` | Nothing. The sheet closes without a message (the player chose to cancel) | |
| `failed`, network | "We could not confirm this purchase. If you were charged, it will be added automatically." | Try again, Close |
| `failed`, store | "The store could not complete the purchase." with the store's problem class (not allowed on this device, item unavailable) | Close |
| `rejected` | "This purchase could not be added to your account. Contact support with the reference below." On Google the store refunds it automatically; the text says "The store will refund it" only for Google | Contact support, Close |
| `blocked` | The intent reason (screen 5) | Close |

Copy rules. Never say "payment failed" when the outcome is unknown; say it could not be confirmed and that a charged purchase is added automatically (recovery guarantees it). Never show raw store error codes. `cancelled` shows nothing, as in `billing.in-app-purchase`.

Accessibility. The status text is an alert region (`role=alert` for failed and rejected, polite for verifying and granted). The spinner has a text label.

Events. `purchase_started` { `product_code`, `platform` } when the store sheet opens; `purchase_cancelled` { `product_code`, `platform` }; `purchase_pending` { `product_code`, `platform` }; `purchase_failed` { `product_code`, `platform`, `reason` } with `reason` in `network`, `not_allowed`, `unavailable`, `store`, `rejected`, `verify`; `purchase_recovered` { `platform`, `source` (`launch`, `resume`, `update`), `outcome` (`granted`, `pending`, `rejected`, `noop`) }.

### 7. Purchase receipt

**Purpose.** Confirm what was credited and what was charged.

Content: pack name; credited lines ("1,050 gems: 500 + 50 bonus + 500 first purchase bonus"); when the first-purchase bonus was not applied because it was already used, the line says so ("First purchase bonus already used"); new balance; "Charged: <price_micros formatted in price_currency>" or, when unknown, "See your store receipt for the amount charged"; a reference (the store order id when present, else the first eight characters of the purchase id) for support. Beneficiary `other_account`: "This purchase belongs to another profile on this device and was added there." with no balances shown.

States: shown, closed. There is no "share" or "buy more" button.

Accessibility. Heading "Purchase complete"; the credited lines as a list; the sheet is announced once.

### 8. Insufficient-balance sheet

**Purpose.** When a feature needs more of a currency than the player has, say how much is missing and offer the shop. Mounted once at the shell; any caller opens it with `{ currency, needed, balance, reason }`.

Content: "You need 120 more gems" (needed minus balance), the player's balance, an indicative real-money equivalent of the missing amount when the reference price is available ("about $1.19", through `ApproxMoney`), and two buttons: "See packs" and "Not now" with equal weight. "See packs" opens the shop with packs whose total contents of that currency (base + bonus) cover the shortfall marked "Covers what you need" (computed from amounts, not prices). When the caller passes `direct_offer: { product_code }` (a `fulfilment = external` product for the item itself, sold for its exact price), the sheet also lists it as "Buy directly for <store price>", beside the packs and with the same weight; it goes through the same confirmation. Nothing is preselected.

| State | Behavior |
|---|---|
| Shown | As above |
| Reference price unavailable | The money line is hidden; "Pack prices" link instead |
| Currency not purchasable (a soft currency) | No "See packs"; the sheet explains where the currency is earned (text supplied by the caller) |
| Policy blocks purchases | "See packs" opens the shop in its disabled state with the reason |

Copy rules. No countdown, no "limited" wording, no emotional language. The sheet never opens on its own at launch or between actions; it opens only when a player action fails for lack of balance.

Events. `insufficient_balance_shown` { `currency`, `needed`, `balance`, `reason` } (`reason` is the ledger reason the caller tried to spend); `insufficient_balance_routed` { `currency` } when "See packs" is tapped; `offer_shown` with placement `insufficient_balance` for each marked pack.

### 9. ApproxMoney (indicative real-money equivalent)

**Purpose.** Guide 10 (Real-money value) requires this indicative figure beside any price in a purchasable currency. Wherever any screen of any block shows a price in a purchasable currency (the insufficient-balance sheet, a pass tier skip, an energy refill, a timer speed-up), it renders `ApproxMoney` beside the currency price. The component is shared; no screen computes the figure itself.

Rule. The figure is an indicative equivalent derived from the pack catalog at the undiscounted rate:

```
indicative = ceil_to_minor_unit( amount x P / B )
P = the store's numeric price of the pack named by the currency's reference_product_code
B = that pack's base amount in store_product_contents (no bonus, no first-purchase bonus, no discount)
```

Example: `P` = 0.99 USD for `gems_small`, `B` = 100 gems, an item costing 120 gems: 120 x 0.99 / 100 = 1.188, rounded up to 1.19. The text reads "about $1.19" with an "Indicative" label; tapping or focusing the label explains: "Indicative value at the standard pack rate, without bonuses or discounts. The store shows the exact price when you buy gems." It never replaces a store price, is never shown for a soft currency, and is display only: it never reaches a grant, a spend or a settlement (INV-16, INV-24). When `P` is not loaded, no figure is shown and a "Pack prices" link takes its place.

Accessibility. The text reads "about 1 dollar 19 cents" through the platform currency formatter; the words "about" and "indicative" are part of the text, not only styling.

Events. `price_info_opened` { `surface` } when the "Pack prices" link or the Indicative explanation is opened.

### 10. Spending screen (limit and history)

**Purpose.** Let the player set a limit, see what counts toward it, and read what each purchase charged.

Limit section.

| State | Behavior |
|---|---|
| No limit | "No limit set" and a field to set one, in the store currency |
| Limit set | Limit, spent in the period, remaining, and when room returns |
| Pending change | "Your change to $50.00 takes effect on <local time>. Until then your limit is $20.00." with "Cancel change" |
| Parental gate required | Gate before any change |
| Currency mismatch | "Your limit is in EUR and the store now charges in USD. Set a new limit to buy again." |

Copy rules. Lowering applies at once and says so. Raising or removing says "This takes effect after <cool-off> so a quick decision cannot undo your limit." (the cool-off from the server's `effective_at`). No wording that nudges the player to keep or raise the limit.

Help section. "Unauthorized purchase?" explains in plain text how to ask the store for a refund (Google: a request within 48 hours of purchase may succeed, after that the developer decides; Apple: the store's own refund request) and gives the support contact. It makes no promise of a refund. A refund the store grants appears in the history and in the refund notice (screen 11).

History section. Purchases newest first: pack, date, state, credited lines, "Charged <amount>" or "See your store receipt". Refunded purchases show "Refunded by the store" with what was removed. States: loading, empty ("No purchases yet"), error with retry.

Accessibility. The limit field has a label and a currency; errors are tied to the field; the pending change is text, not only a color.

Events. `spend_limit_screen_viewed`; `spend_limit_submitted` { `change`: `set`, `lowered`, `raise`, `remove`, `cancel_pending` } (the server writes `spend_limit_changed` with the outcome).

### 11. Refund notice

**Purpose.** Tell the player, once, that the store refunded a purchase and what that changed.

Shown as a banner at the top of the shop and on the spending screen for each unseen notice: "The store refunded <pack> on <date>. We removed 200 gems from your balance." When a shortfall exists: "350 gems from that purchase were already spent, so nothing more was removed." No debt wording, no blame. A "Dismiss" button marks it seen (`POST /api/wallet/refund-notices/seen`). A reinstated purchase shows "The refund was reversed. 200 gems were returned."

Events. `refund_notice_shown` { `product_code` }.

### 12. Guest nudge

Signed-out players see, above the packs and in the confirmation sheet: "You are not signed in. Purchases stay on this device's profile. Sign in to keep them if you change phones." with a Sign in button. It never blocks a purchase.

### 13. Account deletion copy

The deletion confirmation for `compliance.account-deletion` lists the balances that will be deleted ("1,240 gems and 2,000 coins will be deleted and are not refunded by the game. Refunds of store purchases are handled by the store") and that purchase records may be kept as the law requires (the merchant's text).

---

## Client logic

### The store port (the one seam)

The client talks to StoreKit and Play Billing only through this interface. A fake implements it in tests; no component imports the store plugin. Every call answers a reply value and never throws. The plugin behind the port maps its own errors to the problem classes below.

<!-- PATTERN: store-port -->
<!-- PURPOSE: isolate StoreKit and Play Billing behind one testable interface that returns proofs the server verifies -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `Reply` -> your error style; the plugin calls behind `purchase` (StoreKit product purchase with the app account token option, Play launchBillingFlow with the obfuscated account id) and `unfinished` (Apple unfinished transactions, Play queryPurchasesAsync) -> your native plugin's names; `price` carries the numeric store price so the device can read it without parsing the display string -->
```typescript
type Problem = "cancelled" | "pending" | "network" | "notAllowed" | "unavailable" | "alreadyOwned" | "store";
type Reply<T> = { ok: true; value: T } | { ok: false; problem: Problem };
type Proof =
  | { platform: "apple"; signedTransaction: string }
  | { platform: "google"; productId: string; purchaseToken: string };
interface StoreProduct { storeProductId: string; displayPrice: string; priceMicros: number; currency: string }

interface StorePort {
  readonly active: boolean;                                   // false on web and in tests without a store
  products(ids: string[]): Promise<Reply<StoreProduct[]>>;
  purchase(storeProductId: string, accountToken: string): Promise<Reply<Proof>>; // "pending" is a problem class
  unfinished(): Promise<Reply<Proof[]>>;                      // recovery source
  finish(proof: Proof): Promise<Reply<void>>;                 // Apple finish(); no-op on Google (the server consumes)
  onUpdate(cb: (p: Proof) => void): () => void;              // Apple Transaction.updates, Play purchase updates
}
```

Problem classes and what the player sees: `cancelled` nothing; `pending` the pending state (screen 6); `network` "could not confirm"; `notAllowed` "Purchases are turned off on this device"; `unavailable` "This item is not available"; `alreadyOwned` (Google reports an unconsumed purchase of the same product) recover by submitting the owned purchase, no message; `store` a generic store problem. The Apple pending result and the Google `PENDING` state both map to `pending` ([Apple, pending](https://developer.apple.com/documentation/storekit/product/purchaseresult/pending), HIGH).

### Delivering a proof

Every proof from a purchase, an update or a recovery goes through one function. It submits to the server, retries transient failures, and finishes the Apple transaction only when the server says so (INV-11). Store calls run one at a time (same serialization pattern as `blocks/billing/in-app-purchase/frontend.md`, `serialize-store-calls`).

<!-- PATTERN: deliver-proof -->
<!-- PURPOSE: submit a store proof, retry transient failures, and finish the store transaction only on the server's word -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `api.verify` -> your HTTP client; `sleep` -> your timer; the backoff list is VERIFY_RETRY_BACKOFF_SECONDS; after the list is exhausted keep retrying once a minute while the app is open and again at the next launch -->
```typescript
const BACKOFF_S = [2, 5, 15, 60];

async function deliver(proof: Proof, price?: { amountMicros: number; currency: string }): Promise<VerifyResult | null> {
  for (let attempt = 0; ; attempt++) {
    const r = await api.verify({ proof, clientPrice: price });
    if (r.ok) {
      if (r.body.finish_transaction) await store.finish(proof);   // never before the server answers
      wallet.apply(r.body);                                       // balances, receipt, pending row
      return r.body;
    }
    if (r.status === 409) { await store.finish(proof); return null; } // rejected: terminal
    if (r.status === 422) return null;                              // invalid proof: do not finish
    await sleep(BACKOFF_S[Math.min(attempt, BACKOFF_S.length - 1)] * 1000);  // 429, 503, network
  }
}
```

A proof is never discarded while the server is unreachable: the store keeps the transaction unfinished (Apple) or the purchase unconsumed (Google) until delivery succeeds, which is what makes recovery possible.

### Recovery at launch and on resume

<!-- PATTERN: recover-unfinished -->
<!-- PURPOSE: deliver purchases that were paid but not confirmed because the app was closed, killed or offline -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: call `run` at app start, on foreground, and from `store.onUpdate`; Google's guidance is to query purchases again when the app resumes ([Google, integrate](https://developer.android.com/google/play/billing/integrate)); no UI is shown unless a purchase is granted -->
```typescript
async function recover(source: "launch" | "resume" | "update"): Promise<void> {
  const r = await store.unfinished();
  if (!r.ok) return;                                   // try again at the next trigger
  for (const proof of r.value) {
    const out = await deliver(proof);                  // idempotent by store_transaction_id on the server
    analytics.track("purchase_recovered", { platform: proof.platform, source, outcome: out?.state ?? "noop" });
    if (out?.state === "verified" && out.beneficiary === "self") notifyReceipt(out);
  }
}

store.onUpdate((proof) => void deliver(proof));        // approvals and purchases made outside the app
```

### Countdown from the server clock

The client never decides that a timer has elapsed. It records the server's `server_now` against a monotonic clock once per response and displays from that; the server still decides on submit.

<!-- PATTERN: server-offset-countdown -->
<!-- PURPOSE: show a starter-offer countdown from server_now and ends_at without trusting the device clock -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `performance.now` -> any monotonic clock your shell exposes; call `syncClock` on every shop response; render at minute granularity for accessibility -->
```typescript
let serverAtSync = 0;                               // the server's now, in epoch milliseconds, at the last response
let monoAtSync = 0;                                 // monotonic clock reading at that moment

function syncClock(serverNowIso: string): void {
  serverAtSync = Date.parse(serverNowIso);
  monoAtSync = performance.now();
}

function secondsLeft(endsAtIso: string): number {
  const serverNow = serverAtSync + (performance.now() - monoAtSync);   // immune to device clock changes
  return Math.max(0, Math.floor((Date.parse(endsAtIso) - serverNow) / 1000));
}
```

### Approximate real-money value

<!-- PATTERN: approx-real-money -->
<!-- PURPOSE: estimate what an amount of a purchasable currency costs at the undiscounted reference rate, rounded up to the minor unit -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `Intl.NumberFormat` is available in web shells; the fraction-digit lookup keeps JPY (0 digits) and similar currencies correct; integer BigInt arithmetic avoids float rounding errors (a float ceiling can round 1.1 times 100 up to 111); format with the player's locale; show nothing when `ref` is null -->
```typescript
interface Ref { priceMicros: number; baseAmount: number; currency: string }  // the reference pack from the store

export function approxMoney(amount: number, ref: Ref | null, locale: string): string | null {
  if (!ref || ref.baseAmount < 1 || amount < 1) return null;
  const fmt = new Intl.NumberFormat(locale, { style: "currency", currency: ref.currency });
  const digits = fmt.resolvedOptions().maximumFractionDigits;
  const unit = 10n ** BigInt(6 - digits);                       // micro-units per minor unit
  const base = BigInt(ref.baseAmount);
  const micros = (BigInt(amount) * BigInt(ref.priceMicros) + base - 1n) / base;   // integer ceiling
  const minor = (micros + unit - 1n) / unit;                    // ceiling to the minor unit
  return fmt.format(Number(minor) / 10 ** digits);              // shown inside the "about" string
}
```

`ApproxMoney` renders the result inside the localized "about {amount}" string with its Indicative label. The function is the only place a money figure is computed (INV-24).

### Purchase flow

```
idle -> gate (when required) -> intent -> confirming -> store_sheet -> verifying -> granted
                                   |            |            |             |-> pending
                                   |            |            |             |-> failed (retry loops in deliver)
                                   |            |            |-> cancelled -> idle
                                   |            |-> idle ("Not now")
                                   |-> blocked
```

One purchase at a time: while the flow is not `idle`, a second tap on any Buy is ignored. The flow persists nothing; recovery, not flow state, protects a purchase across a crash.

## Anti-patterns

| DON'T | Why |
|---|---|
| Compute, round or cache a pack price | The store's string is the price; a cached price can be wrong after a storefront change |
| Open the shop or a "need more" sheet at launch or between levels | The shop opens only on a player's action |
| Preselect, highlight by default or auto-scroll to a pack | The choice must be the player's |
| Show a "best value" tag derived from price | A computed price signal; the guide's rule is real-money clarity, not nudging |
| Show only a gem price for a purchasable currency | The player must be able to learn the real-money value (INV-24) |
| Finish an Apple transaction before the server answers | A crash then loses a paid purchase |
| Consume or acknowledge a Google purchase from the client | The server finishes after the grant commits |
| Show "payment failed" when the outcome is unknown | Say it could not be confirmed and that a charged purchase is added automatically |
| Start a countdown from the device clock | The server clock is the only authority |
| Hide Not now or make it smaller than Buy | Equal weight is a copy rule |
| Show a countdown to a child profile | `countdown_offers_allowed` is false; show the offer without a timer |
