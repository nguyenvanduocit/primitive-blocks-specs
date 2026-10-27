# Frontend Patterns: Subscriptions

> The client is a web-tech app in a native shell. Text is framework-agnostic: "state holder", "sheet", "banner". Snippets are L3 illustrative TypeScript with the four markers of `docs/SPEC_GUIDELINES.md` section 6. The server answers every access question (`backend.md` section 1); the client shows it. The price, the trial length and the store's own offer text come from the store SDK on the device, never from constants.
>
> Disclosure rules cite Apple's App Review Guidelines 3.1.2 [SA15], the Auto-renewable Subscriptions page [SA16], Schedule 2 section 3.8 of the Developer Program License Agreement [SA17], and Google Play's Subscriptions and Payments policies [SG12, SG13], all read on 2026-10-27. Source keys are in the README Sources table.

## Component tree

```
App shell
 ├── EntitlementStore            state holder: entitlements, detail, server_now; refresh policy
 ├── StateBanner host            one primary banner plus an optional price-change banner
 ├── PaywallSheet                opened by a player action, never at launch
 │     ├── PlanPicker            plans with store price strings, equal visual weight
 │     ├── DisclosureBlock       always visible, no expand step
 │     ├── Subscribe button      "Subscribe" with the billed amount
 │     ├── Restore link          always visible
 │     ├── Terms of Use and Privacy Policy links
 │     └── Close                 always reachable
 ├── SubscriptionSettings        status, dates, next stipend, Manage, Restore
 ├── RestoreResultDialog         found, none, linked elsewhere, transfer confirm, error
 ├── PendingPurchaseNotice       waiting for payment or approval; confirming
 ├── WinbackSheet                optional
 └── StipendNotice               toast or inbox row when a stipend arrives
```

| Unit | Responsibility | Interface |
|---|---|---|
| `EntitlementStore` | Fetch `/api/subscriptions/status`, hold the result, refresh on app foreground, after claim or restore, after the store manage screen closes, and when `expires_at` passes | `refresh()`, `entitlement(product_code)`, `detail(product_code)` |
| Store adapter | The only code that talks to StoreKit or Play Billing (or an aggregator) | `loadOffers(plans)`, `purchase(intent)`, `proofs()`, `finish(result)`, `openManage(detail)` |
| `PaywallSheet` | Renders offers and disclosure; no business logic | reads offers, purchase state; calls `subscribe`, `restore`, `close` |

The store adapter is the seam to the vendor: a store SDK, a native plugin, or a purchase-aggregation service all fit as long as they return the fields the screens below use.

## 1. Paywall and offer sheet

**Purpose**: sell one subscription with every fact the player needs before the store sheet.

**Opens from**: the player tapping a locked perk, a "Get VIP" entry, or the Settings row. It never opens at launch, during onboarding, or on a timer. It does not open for an account whose entitlement for the product is active.

**States**

| State | Shown |
|---|---|
| `loading` | Plan names from the catalog, price placeholders, Subscribe disabled, Restore usable |
| `ready` | Offers with store price strings; trial wording only for an offer the store reports as eligible |
| `ready_no_trial` | Same without trial wording (the player already used the trial, or the store reports ineligible) |
| `unavailable` | "This subscription isn't available right now." No Subscribe; Restore and Close stay |
| `store_unreachable` | "Can't reach the store." Try again; Restore and Close stay |
| `already_subscribed` | Status line and Manage button; Subscribe is hidden (from `409 already_entitled`) |
| `subscribed_elsewhere` | "You already have this subscription through Google Play" (or the Apple App Store) with the Manage instruction for that store; no Subscribe (INV-18) |
| `purchases_blocked` | The host's purchase gate (parental gate or purchases disabled, from the host's `purchase_policy` of `billing.virtual-currency`) replaces Subscribe |
| `busy` | Subscribe disabled with progress; a second tap is ignored |

**Copy rules** (every line is built from store data or the catalog; none is a constant)

| Line | Rule | Source |
|---|---|---|
| Plan name and duration | Shown for each plan, with what the subscription includes during the period | Apple sign-up screen [SA16]; guideline 3.1.2(c) "clearly describe what the user will get for the price" [SA15]; Schedule 2 section 3.8(b) title, length, price [SA17] |
| Billed amount | The full renewal price, localized, taken from the store; it is the most prominent price element. A per-month equivalent for a longer plan is smaller than the billed amount | Apple [SA16]; Google lists "annual subscriptions that prominently show only monthly pricing" as a violation [SG12] |
| Renewal | "Renews automatically every `<period>` at `<price>` until you cancel." | Google: be transparent about cost, billing frequency, renewal terms [SG12] |
| Trial | Length, the price billed after it, that it converts automatically, and how to cancel before conversion. Only for an eligible offer | Apple free trials [SA16]; Google free trials and introductory offers [SG12] |
| Introductory price | Its price, how long it lasts, and the price after it | Google [SG12] |
| Cancel | "Cancel any time in `<App Store or Google Play>` subscription settings." with a link that opens the store's manage page (section 4) | Google requires an easy-to-use online way to cancel [SG12] |
| Benefits | Truthful and recurring, for example "300 gems every month, delivered automatically"; values come from the catalog; no benefit line mentions a trial or promotional price because not every player qualifies | Google: benefits must be truthful and accurate [SG12]; design choice for the trial rule |
| Restore | "Restore purchases" visible in every state | Apple [SA15, SA16] |
| Terms and Privacy | Links to the Terms of Use and Privacy Policy inside the sheet | Apple [SA16, SA17] |
| Price match | The price on the paywall equals the price on the store sheet because both come from the store | Google Payments policy: in-app pricing must match the Play billing interface [SG13] |

**No dark patterns** (design rules following guide `06-design-ethics-and-compliance.md`): plans have equal visual weight and none is pre-selected by a countdown; no timer that the store does not back with a real offer end date; Close is as visible as Subscribe (Google flags a missing or hidden dismiss button [SG12]); the disclosure is not behind a collapsed section ("Users should not have to perform any additional action to review the information" [SG12]); subscription names describe the offer (Google flags a recurring-charge name such as "Free Trial" [SG12]).

**Accessibility**: the plan list is a radio group; each option's accessible name carries plan, period and billed price; the disclosure is plain text readable at the largest system text size without truncation; Subscribe and Restore meet the platform's touch target minimum (extrapolated from platform guidance); focus moves to the sheet title on open and returns to the trigger on close; errors use `role=alert`.

**Events**: `subscription_paywall_viewed` (`source`, `plan_codes`, `trial_shown`, `entitlement_state`), `subscription_plan_selected` (`plan_code`).

### Disclosure builder

<!-- PATTERN: disclosure-lines -->
<!-- PURPOSE: build the disclosure text only from store offer data so no price or trial length is hard-coded -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `StoreOffer` -> the fields your store adapter returns (price string, period, trial or introductory phase); `t` -> your i18n catalog, one key per line, all locales; `storeName` -> "App Store" or "Google Play" from the platform -->
```typescript
interface StoreOffer {
  planName: string; period: string;          // period label formatted for the locale
  renewalPrice: string;                      // store-localized string, never parsed
  trial?: { length: string; thenPrice: string };
  intro?: { price: string; length: string; thenPrice: string };
}

export function disclosureLines(o: StoreOffer, t: Strings, storeName: string): string[] {
  const lines = [t.planLine(o.planName, o.period), t.renews(o.period, o.renewalPrice)];
  if (o.trial) lines.push(t.trial(o.trial.length, o.trial.thenPrice), t.cancelBeforeTrialEnds(storeName));
  if (o.intro) lines.push(t.intro(o.intro.price, o.intro.length, o.intro.thenPrice));
  lines.push(t.cancelAnytime(storeName));
  return lines;
}
```

## 2. Purchase flow, pending, success, errors

<!-- PATTERN: subscribe-flow -->
<!-- PURPOSE: run intent, store purchase and server claim so a charged player is never left without a retry path -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `api`, `store` -> your HTTP client and store adapter; `retry` -> your backoff helper (a few attempts over about a minute); `setPurchase`/`setEntitlements` -> your reactive state; serialize store calls through one queue per adapter -->
```typescript
async function subscribe(planCode: string) {
  setPurchase("starting");
  const intent = await api.post("/api/subscriptions/intents", { plan_code: planCode }); // 409 stops here
  setPurchase("store_sheet");
  const result = await store.purchase(intent, intent.store_account_token);
  if (result.kind === "cancelled") return setPurchase("idle");   // the player chose; show nothing
  if (result.kind === "pending") return setPurchase("pending");  // waiting for payment or approval
  setPurchase("claiming");
  const claim = await retry(() => api.post("/api/subscriptions/claims", { platform, proof: result.proof }));
  if (!claim.ok) return setPurchase("confirming");               // charged, server not yet confirmed
  await store.finish(result);                                    // finish only after the server confirmed
  setEntitlements(claim.entitlements);
  setPurchase("done");
}
```

| State | Shown |
|---|---|
| `starting`, `store_sheet` | Subscribe disabled; the store's own sheet is on screen |
| `claiming` | "Confirming your subscription" with progress |
| `confirming` | "We're confirming your purchase. Your access appears as soon as it's done. You don't need to pay again." The store transaction stays unfinished; the claim retries on app foreground and from Restore |
| `pending` | "Waiting for approval or payment. VIP starts when the payment completes, and you can keep playing." No perks yet; the sheet can close; the store's completion arrives through the store adapter and the next status refresh |
| `done` | Sheet closes or shows success: plan, "VIP is on", the renewal or end date from the server (`expires_at`, `will_renew`), what arrives next (the first stipend or its date), and a Manage link |
| `failed` | One-line reason from the problem table, Subscribe usable again |

| Problem | Cause | Message |
|---|---|---|
| `cancelled` | The player closed the store sheet | none |
| `network` | No connection or store timeout | "Check your connection and try again." |
| `not_allowed` | Purchases disabled on the device or by a parental setting | "Purchases are turned off on this device." |
| `unavailable` | The store has no such product or offer | "This subscription isn't available right now." |
| `already_entitled` | `409` from the server | Status line and Manage |
| `already_owned` | The store reports the subscription is already owned | "You're already subscribed. Tap Restore if VIP isn't showing." |
| `verification_failed` | Server could not confirm the proof | the `confirming` state, never an error toast |
| `store` | Anything else | "Something went wrong with the store. Try again." |

**Events**: `subscription_purchase_started` (`plan_code`, `offer_kind`), `subscription_purchase_pending` (`plan_code`), `subscription_purchase_cancelled` (`plan_code`), `subscription_purchase_failed` (`plan_code`, `problem`). `subscription_purchase_succeeded` is fired by the server when the claim or the first store message creates the term.

## 3. State banners

One primary banner at most, chosen by priority, plus the price-change banner when it applies.

<!-- PATTERN: banner-selector -->
<!-- PURPOSE: choose the banner for an entitlement and its detail with a pure function -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: none for the function; the host decides where each banner kind is rendered -->
```typescript
type Banner = "retry" | "grace" | "paused" | "pending" | "revoked" | "canceled" | "expired" | "family" | "price_change" | "trial_ending";

export function banners(e: Entitlement, d: Detail | undefined): Banner[] {
  const out: Banner[] = [];
  const primary: Record<string, Banner> = {
    retry: "retry", grace: "grace", paused: "paused", pending: "pending",
    revoked: "revoked", canceled: "canceled", expired: "expired",
  };
  if (primary[e.state]) out.push(primary[e.state]);
  else if (e.state === "trial" && d?.trial_ending) out.push("trial_ending");
  else if (e.active && d?.ownership === "family_shared") out.push("family");
  if (e.active && d?.price_change_state === "pending_consent") out.push("price_change");
  return out;
}
```

| Banner | When | Copy rule | Action |
|---|---|---|---|
| `grace` | `state = grace` | "There's a problem with your payment. VIP stays on until `<expires_at>` while `<store>` tries again. Update your payment method." | Open the store's payment page (section 4) |
| `retry` | `state = retry` | "Your payment didn't go through, so VIP is off. Update your payment method to get it back." | Same |
| `paused` | `state = paused` | "Your subscription is paused until `<auto_resume_at>`. VIP is off until then." | Manage |
| `canceled` | `state = canceled` | "VIP ends on `<expires_at>`. You keep everything until then." | Manage (the store's resubscribe) |
| `price_change` | `price_change_state = pending_consent` | "The price of your subscription is changing. Confirm the new price in `<store>` to keep it." The new amount appears only as the store provides it. | Open the store's manage or consent page |
| `expired` | `state = expired` | "Your VIP ended on `<expires_at>`." plus a Subscribe entry; the win-back sheet when offered | Open the paywall |
| `revoked` | `state = revoked` | "Your subscription was refunded, so VIP access ended." No blame wording | Open the paywall; link to help |
| `pending` | `state = pending` | "Waiting for payment. VIP starts when it completes." | none |
| `trial_ending` | `state = trial`, auto-renew on, and `detail.trial_ending` present (the reminder window is open) | "Your free trial ends on `<date and time>`. After that, `<price>` per `<period>` is charged to your `<store>` account unless you cancel first." See "Trial-ending reminder" below for the price line and the rules | Manage subscription (opens the store's manage page, section 4); Dismiss |
| `family` | active with `ownership = family_shared` | "You have VIP through Family Sharing. It ends if sharing stops." | none |

Rules: the `grace` and `retry` banners return on every session while the condition holds and can be hidden for the current session only; the dates come from the server in the player's locale and time zone; no banner appears for `active` with `will_renew = true`; `trial` shows "Free trial ends on `<expires_at>`" in Settings, and as the `trial_ending` banner only inside the reminder window; the paywall's trial disclosure rules apply to any message about the trial.

### Trial-ending reminder

The server emits the hand-off event `subscription_trial_ending` for push (README section 6); this section is the in-app side and the copy rules for both. The in-app banner and the Settings line show the same facts whether push is on, off, denied, deferred or suppressed, because they read `detail.trial_ending` and never push state. The reminder is information: it tells the player what happens if they do nothing and how to avoid it.

| Fact | Rule |
|---|---|
| Date and time | The trial end in the player's locale and time zone, with the time, because the first charge follows it. Never "tomorrow" without the date |
| Price | The price after the trial. Prefer the store price string for the plan read on the device; otherwise format `price_milliunits` and `currency_code` in the player's locale and say "the plan price"; with neither, say "the plan price shown in `<store>`" and name no amount. The server value can differ from the charge by taxes, so the text sends the player to the store's subscription screen for the exact amount |
| Period | "per month", "per year", from `period` |
| Cancel path | "Manage subscription" opens the store's manage page for the chain's platform (section 4); the text names the store |
| Dismiss | Hides the banner for the current session; it returns next session while the window is open; it never blocks play and is never a modal or an interstitial |

Not allowed, in the banner, the Settings line and the push copy: an offer or discount, "keep your perks" or other upsell, loss framing ("you will lose"), urgency words ("last chance", "hurry", a countdown), a second action more prominent than Manage, and a push-permission prompt (push priming belongs to `messaging.push-reengagement`). Push copy is rendered by that block's template: title "Your free trial ends on `<date>`", body "Then `<price>` per `<period>` unless you cancel. Manage or cancel any time in your settings." The push opens the Settings subscription row. Kit guide `15-manipulation-and-the-line.md` row 16 and control B3 ask for a reminder before conversion; control N1 asks that push copy names a benefit without guilt or loss framing, and here the benefit is the information itself [SK2].

States: reminder window closed (no banner); open (banner); canceled during the trial (the `canceled` banner replaces it: "VIP ends on `<expires_at>`. You keep everything until then."); converted (no banner; the next paid term shows no banner while it renews).

**Accessibility**: `role=status`; the date, time and price are text, not an icon or color; the Manage button's accessible name carries the store ("Manage subscription in the App Store"); Dismiss has a name ("Dismiss trial reminder").

**Events**: `subscription_banner_viewed` (`banner`, `product_code`), `subscription_banner_action` (`banner`, `action`: `manage` or `dismiss` for `trial_ending`). The server events `subscription_trial_reminder_emitted` and `subscription_trial_reminder_resolved` record the push side; the push block records opens and deliveries.

## 4. Manage subscription and store deep links

**Purpose**: the player can see the state and reach the store's own cancel, change and payment screens. Google's policy requires access to an easy-to-use online method to cancel inside the app, and lists a missing manage or cancel link in account settings as a violation [SG12].

**Settings row contents**: plan name; one status line (Active, Free trial ends `<date>`, Ends on `<date>`, Payment problem, Paused, Ended); during a renewing trial the line also reads "then `<price>` per `<period>`" with the rules of "Trial-ending reminder"; next renewal or end date; next stipend date when `next_stipend_at` is set; Manage; Restore; Terms and Privacy links.

**Opening the store** (use the platform of the chain, `detail.platform`, not the device's):

| Store | Manage subscription | Update payment |
|---|---|---|
| Apple | In-app sheet `showManageSubscriptions(in:)` on iOS 15 and later [SA20]; not supported inside Mac apps built with Mac Catalyst or on iOS apps running on Apple silicon Macs [SA20]. Link fallback: `https://apps.apple.com/account/subscriptions` [SA19] | `https://apps.apple.com/account/billing` [SA19] |
| Google | `https://play.google.com/store/account/subscriptions?sku=<store_product_id>&package=<package name>` for the specific subscription; `https://play.google.com/store/account/subscriptions` for the list [SG10] | Same link; Play also shows its own in-app message for payment problems [SG10] |

A chain from the other platform cannot open on this device: show "Manage this on your iPhone: Settings, your name, Subscriptions" (Apple) or the Google Play link text (Google). In the web-tech shell, open store links with the system URL handler, not an in-app web view, so the store app takes over. After the player returns from a store screen, call `refresh()`: store messages reach the server asynchronously, and the next status read is the truth.

**Events**: `subscription_manage_opened` (`platform`, `via`: `native_sheet` or `deep_link`).

## 5. Restore

**Purpose**: bring a subscription back after a reinstall, a new phone, or a new game account. Apple requires a restore path for restorable purchases and a way for current subscribers to restore on the sign-up screen [SA15, SA16].

**Placement**: the paywall and Settings, always visible, in every paywall state.

**Flow**: the store adapter collects proofs (`backend.md` section 4.2) and posts them to `/api/subscriptions/restores`; the dialog shows one result.

| Result | Copy rule |
|---|---|
| `found` | "Restored. VIP is active until `<expires_at>`." (or the renewal date) |
| `none` | "We didn't find a subscription for this store account. If you subscribed with a different Apple ID or Google account, sign in to that account in the store and try again." |
| `linked_elsewhere` | "This subscription is linked to another game account. Move it to this account?" with Move and Cancel. No detail about the other account |
| transfer confirm | "Move VIP to this account? The other account loses VIP. You can't move it again for `<days>` days." (`<days>` comes from the server) |
| `cooldown` | "This subscription was moved recently. You can move it again on `<date>`." |
| `error` | "Couldn't reach the store or the server. Try again." |

States: `running` disables the button with progress; a second tap is ignored. **Events**: `subscription_restore_started`, `subscription_restore_completed` (`result`, server) and `subscription_transfer_completed` (server).

## 6. Win-back offer sheet (optional)

Shown only when `GET /api/subscriptions/offers` returns an offer (`WINBACK_ENABLED`). It carries the same disclosure as the paywall for the offer's own price, length and the price after it; it names the player's lapse neutrally ("Welcome back"); Close is as visible as the action; it opens from the Settings row or the expired banner, never as a launch interstitial. **Events**: `subscription_winback_shown` (`offer_kind`, `lapse_days`), `subscription_winback_redeemed` (server).

## 7. Stipend delivery

No claim button: subscribers receive the stipend without tapping anything (INV-15). When the wallet shows the grant, a toast or inbox row says "Your monthly 300 gems arrived" with the real amount and cadence from the catalog. Settings shows "Next delivery `<date>`" from `next_stipend_at`. If the subscription is canceled, the copy says deliveries continue until it ends. A skipped stipend (trial, family sharing, sandbox) shows no message; the paywall states up front whether the trial includes the stipend. **Events**: `subscription_stipend_granted` and `subscription_stipend_skipped` are server events; the client fires none.

## 8. Entitlement refresh policy

Refresh on: app foreground; after a claim, restore or manage-screen return; when the local clock passes `expires_at` (the server decides, the client only asks); on a push or in-app signal if one exists. Between refreshes the screens show the last result with `server_now` correction; the client never marks a subscription ended by itself. While a refresh is in flight after `expires_at`, keep showing the last state with no "ended" wording. An offline client shows the cached state with an "offline" hint and keeps perks that the server last confirmed.

## Styling and accessibility

- Banners use `role=status`; purchase failures use `role=alert`.
- State is never color-only: each banner has an icon with a text label.
- Dates and prices are localized by the platform formatter; the price string from the store is not reformatted.
- Provide stable test hooks on the paywall, each plan, Subscribe, Restore, each banner, Manage, and each restore result.

## Anti-patterns

| DON'T | Why |
|---|---|
| Decide "subscribed" from the store SDK on the device | INV-1; the server also sees refunds and expiries the SDK reports late |
| Open the paywall at launch or on a timer | The player has seen no value; Google flags deceptive purchase experiences [SG12] |
| Hide the disclosure behind a "details" link | Both stores require it where the player chooses [SA16, SG12] |
| Show "7 days free" from a constant | Eligibility is per player and per store |
| Call a trial the benefit of the plan | Not every player qualifies |
| Use the trial reminder to upsell, discount or pressure | INV-19; it is information, and a pressured conversion is the failure the guide names |
| Show the reminder only to players with push on | Push is best-effort; the player who most needs the reminder may have it off |
| Finish the store transaction before the server confirmed | A crash leaves a charged player with no entitlement and no retry |
| Treat a failed claim as a purchase failure | The player was charged; use `confirming` |
| Remove perks the moment auto-renew is turned off | `canceled` keeps access to `expires_at` |
| Ask for a check-in, a share or a tap before delivering perks | INV-15; Apple 3.1.2(a) [SA15] |
