# Frontend Patterns — Energy and Lives

> The client is a web-tech mobile shell (a web app in a native wrapper); text and snippets are framework-agnostic TypeScript. Snippets carry the four markers of `docs/SPEC_GUIDELINES.md` section 6. Rules (regeneration, ceilings, refunds) live on the server (`backend.md`); the client renders server values and never recomputes them (INV-12).
>
> Analytics events are written by the side that sees the fact (guide 12, rule 4): the server writes money, claim and accepted-progress events in the same transaction as the state change, the client writes what only it sees (sheets shown, taps, errors). Each screen below lists its events with the writer.

## Component Tree

```
App shell
 ├── EnergyHud                  header chip per meter; always visible where play starts
 │     ├── PointsDisplay        value / cap, overflow marker, infinity while a boost runs
 │     ├── NextPointTimer       "Next in 12:34" (hidden at or above the cap)
 │     └── FullTimer            "Full in 1:42:10" (in the expanded state)
 ├── StartControl               the Play or Start button of any level or mode
 │     └── CostLabel            "Costs 1 energy" | "Free while unlimited energy runs" | "You lose a life only if you fail"
 ├── EmptyEnergySheet           opened by a player action when available < cost
 │     ├── WaitRow              exact time to next point and to full
 │     ├── AdRow                rewarded video, "{n} left today"
 │     ├── GiftRow              optional extension
 │     └── RefillRow[]          paid offers, last
 ├── RefillConfirmSheet         exact price and balance after
 ├── BoostBanner                "Unlimited energy until 18:30"
 ├── ConnectionNotice           offline, stale, reconcile result
 └── GiftInbox (optional)
```

| Unit | Responsibility | Interface |
|---|---|---|
| `energyStore` | holds the last response per meter, the clock, the pending ids; serializes requests per meter | `view(meter)`, `refresh()`, `start(meter)`, `confirm()`, `finish(outcome)`, `cancel()`, `quote(meter)`, `refill(offer)` |
| `energyClock` | maps `server_now` and absolute instants to remaining time using a monotonic source | `sync(server_now)`, `remainingMs(instant)` |
| Views | render state; no business rules | read `view(meter)`; call store methods |

## Client store contract

- **One refresh path.** Every mutation (start, finish, refill) returns the meter fields; the store replaces its copy from the response. Other triggers for `refresh()`: app start, return to foreground, the countdown reaching zero, reconnecting, and opening the empty sheet. There is no polling interval.
- **Never increment locally.** When a countdown reaches zero the view shows "Checking..." and calls `refresh()`; the value changes only when the server says so (time contract).
- **Never trust the offset across a suspend.** A monotonic clock may pause while the app is suspended, so every return to foreground calls `refresh()` before showing a countdown as current.
- **Serialize per meter.** One request in flight per meter; a second tap waits or is ignored, so ids are never raced.
- **Persist ids.** The pending `attempt_id` and `refill_id` live in device storage until a terminal answer arrives; retries reuse them (INV-5, INV-7).
- **The mirror is display only.** The last response may be saved for the stale label; it is never exported, never part of a progress snapshot, never read to decide a start (INV-14).

<!-- PATTERN: energy-clock -->
<!-- PURPOSE: show countdowns to server instants without the device wall clock -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `mono` -> performance.now() in a browser or webview, or the shell's monotonic timer; call sync() with the server_now of every response; remainingMs(null) is for a meter with no timer (at or above the cap) -->
```typescript
export function makeEnergyClock(mono: () => number) {
  let offset = 0; // serverNowMs - mono(), refreshed by every response

  return {
    sync(serverNowIso: string) {
      offset = Date.parse(serverNowIso) - mono();
    },
    remainingMs(instantIso: string | null): number | null {
      if (instantIso === null) return null;
      return Math.max(0, Date.parse(instantIso) - (mono() + offset));
    },
  };
}
```

A device clock set forward six hours changes nothing: no function above reads it (`security.md` T-1).

<!-- PATTERN: hud-state -->
<!-- PURPOSE: map one server response plus connectivity and age to exactly one HUD state -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `ageSeconds` -> seconds since the last successful response (monotonic); thresholds -> STALE_NOTICE_SECONDS from config; extra states (for example a season skin) -> add them after these, never before `offline` -->
```typescript
type Meter = { value: number; cap: number; next_tick_at: string | null; boost_ends_at: string | null };
type Hud = "loading" | "error" | "offline" | "boost" | "overflow" | "full" | "regenerating" | "empty";

export function hudState(
  m: Meter | null, online: boolean, failed: boolean, ageSeconds: number, boostMs: number | null,
  staleAfter: number,
): Hud {
  if (m === null) return failed ? "error" : "loading";
  if (!online || ageSeconds > staleAfter) return "offline";  // value is shown with its age
  if (boostMs !== null && boostMs > 0) return "boost";
  if (m.value === 0) return "empty";
  if (m.value > m.cap) return "overflow";
  return m.value === m.cap ? "full" : "regenerating";
}
```

## 1. Energy HUD

**Purpose**: the always-visible answer to "can I play and when can I play more".

**States**

| State | What shows |
|---|---|
| loading | the last mirrored value dimmed with its age if one exists, else a placeholder of the same size (no layout jump) |
| regenerating | `value / cap`, "Next in {mm:ss}" and, expanded, "Full in {h:mm:ss}" |
| full | `cap / cap` and "Full"; no countdown |
| empty | `0 / cap`, the next-point countdown, and the Start control opens the empty sheet |
| overflow | `value` above the cap shown as the number with a "+{n} bonus" label; no countdown (it does not regenerate); a tap explains the bonus is kept |
| boost | an infinity mark and "Unlimited until {time}" with the remaining time on tap; the count stays visible beside it |
| offline or stale | the last values, a "Last updated {age}" label, no countdown claims; countdown text shows "Reconnect to update" once its target has passed |
| error | the last values with a retry control; never a blank chip |

**Copy rules**

- Show the next-point time and, on expand, the full time. Both come from `next_tick_at` and `full_at`; never round up to look longer or shorter.
- Format with the platform's locale APIs. Durations under one hour show minutes and seconds; longer ones show hours and minutes. Absolute times ("until 18:30") use the device's time zone for display only.
- No urgency language: no "hurry", no flashing at low points, no red-alert state for zero beyond the normal empty styling.
- Name the meter in the player's words ("Energy", "Lives"); the icon never replaces the word in the expanded view.

**Accessibility**

- The chip is one control with an accessible name that carries everything: "Energy 3 of 5, next in 12 minutes, full in 1 hour 42 minutes". A visual-only heart row has the same text alternative.
- The ticking countdown is not a live region: announcing each second would drown the screen reader. Announce only discrete changes (a point arrived, the meter became full, a boost started or ended) through one polite status element, which satisfies status messages without focus ([WCAG 2.2 SC 4.1.3](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html), AA, HIGH).
- Empty, full and boost are told by text and icon shape, not color alone ([WCAG 2.2 SC 1.4.1](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html), A, HIGH).
- The chip's touch target is at least 24 by 24 CSS pixels ([WCAG 2.2 SC 2.5.8](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html), AA, HIGH). Larger is better on a phone; 24 is the floor.
- A point arriving may animate; the animation is replaced by a static change under `prefers-reduced-motion: reduce` ([MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-motion), HIGH, Baseline widely available).

**Events**: none written by the HUD itself. After every response the client emits `energy_full` on its event bus (`armed` with `fire_at` = the server's `full_at` and the section 6 fields of the README, or `resolved` when `full_at` is null), so the device can schedule a local notification. The client does not compute `fire_at`.

## 2. Start control and the attempt flow

**Purpose**: begin a session so that the player pays at most once and never pays for a session that did not open.

**Flow**

1. The player taps Start. The store generates an `attempt_id` (UUID or ULID), saves it, and sends `POST /api/energy/attempts`.
2. The view shows the loading screen immediately. It does not show the first interactive frame before a 200 or 201.
3. On 409 `insufficient_energy` the loading screen closes and the empty sheet opens with the returned `next_tick_at` and `full_at`.
4. On success the client loads the level. When the level is on screen and playable it calls `confirm`. If loading fails or the player backs out before play begins, it calls `cancel` with `start_failed`, then tells the player the point came back.
5. At the end it calls `finish` with `win`, `fail` or `abandon`.

<!-- PATTERN: attempt-flow -->
<!-- PURPOSE: start, confirm, cancel and finish with ids that survive a crash and retries -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `api` -> your HTTP client returning { status, body }; `store` -> device key-value storage; `loadLevel` -> your session loader (resolves when the first playable frame is ready); on app start call resume() before showing the home screen -->
```typescript
export async function play(meter: string, api: Api, store: KV, loadLevel: () => Promise<void>) {
  const id = crypto.randomUUID();
  store.set("pendingAttempt", id);
  const r = await api.post("/api/energy/attempts", { attempt_id: id, meter_code: meter });
  if (r.status === 409) { store.remove("pendingAttempt"); return { ok: false, reason: r.body.error, meter: r.body }; }
  if (r.status >= 500) return { ok: false, reason: "unavailable" };      // retry with the SAME id
  try {
    await loadLevel();
    await api.post(`/api/energy/attempts/${id}/confirm`);
    return { ok: true, id };
  } catch {
    await api.post(`/api/energy/attempts/${id}/cancel`, { reason: "start_failed" });
    store.remove("pendingAttempt");
    return { ok: false, reason: "start_failed_refunded" };
  }
}

export async function resume(api: Api, store: KV) {          // after a crash or kill
  const id = store.get("pendingAttempt");
  if (!id) return;
  const a = await api.get(`/api/energy/attempts/${id}`);
  if (a.body.state === "open") await api.post(`/api/energy/attempts/${id}/cancel`, { reason: "start_failed" });
  if (a.body.state !== "confirmed") store.remove("pendingAttempt");  // confirmed: the session UI resumes it
}
```

**States of the Start control**

| State | Behavior |
|---|---|
| enough points | enabled; the CostLabel states the cost (`on_start`: "Costs {n}"; `on_fail`: "You lose a life only if you fail") |
| boost active | enabled; "Free while unlimited energy runs" |
| not enough | looks like Start and opens the empty sheet on tap, never disabled without explanation |
| request in flight | busy; a second tap is ignored |
| start failed | the player is told "Couldn't start. Your {meter} was returned." only when the refund applied (`refunded > 0` or the unspent reservation released); when the refund hit its daily limit the message says it was not returned and why |
| offline | `OFFLINE_ATTEMPTS` false: "Connect to play" and a retry; true: the queued path (section 7) |

**Copy rules**: the cost is stated before the tap, not after. In `on_fail` games a quit or pause-quit that would count as a fail warns before it happens ("Leaving now costs a life", guide 10, Pause row). A fail screen states any continue cost before the tap (guide 10, Result row).

**Accessibility**: the CostLabel is part of the button's accessible name. The loading screen announces "Starting" once.

**Events** (server): `energy_spent` at the charge (`on_start` at start, `on_fail` at a failed finish), `energy_attempt_cancelled` on a refund, release or timeout.

## 3. Empty-energy sheet

**Purpose**: when the player cannot start, say exactly why, when it ends, and every way to continue, free ones first.

**Opens** only on a player action (a Start tap, or the HUD tap when empty). It never opens at app start, on a timer, or on a return to foreground.

**Layout order** (fixed): title and the plain fact; the wait row; the ad row when an ad is available and the daily limit is not reached; the gift row when gifts exist; the paid rows; a Close control of the same visual weight as the paid action.

**States**

| State | What shows |
|---|---|
| loading | the sheet opens at once from the last response and refreshes; rows that need the server (offers, ad count) show a skeleton |
| default | wait row with "Next {meter} in {mm:ss}. Full in {h:mm:ss}."; other rows as available |
| ad unavailable | the ad row is hidden, or shows "No video right now" if hiding would confuse; never a spinner that never ends |
| ad daily limit | "No more videos today" and the paid and wait rows remain |
| boost active | the sheet does not open: starts are free |
| refilled while open | the sheet closes itself and shows the new value |
| offline | the wait row from the last response labeled with its age; the ad and paid rows are hidden with "Connect to see more options" |
| error | "Couldn't load options" with Retry; the wait row stays |
| minor account without permission | the paid rows are absent; the wait and ad rows stay |

**Copy rules**

- The wait row always shows the exact times. Waiting is never hidden or shamed ("Just wait" is fine; "Don't want to wait?" is not).
- The ad row states what the ad gives ("Watch a short video for +{n}") and the remaining count ("{k} left today"). It does not imply the video is needed to play.
- A paid row states what it gives and its price in the currency, as `{units} for {cost} {currency}`; it never says "Best value" unless another row is genuinely cheaper per point and the text is true.
- No countdown on the offers, no "last chance", no limited-time styling, no preselected paid option, no repeated reopen after Close. No row is worded as the player's failure.
- The text names the effect on game progress only if true ("Your streak is safe" is allowed only if it is).

**Accessibility**: focus moves to the sheet title on open and returns to the Start control on close; the Close control is reachable first in the swipe order as well as visually; rows are buttons with full labels; all timings are text.

**Events**: client `energy_empty_shown` with `options_shown[]`, `seconds_to_next`, `seconds_to_full`, `ad_remaining_today`; client `energy_sheet_action` with `action` (`wait`, `ad`, `gift`, `refill`, `boost`, `dismiss`).

## 4. Refill confirmation

**Purpose**: show what the player gets and what it costs before any money moves.

**Flow**: tapping a paid row calls `GET /api/energy/offers` if the quote is older than a few seconds, then opens the sheet with the quote. Confirm sends `POST /api/energy/refills` with a new `refill_id` and `expected_cost` equal to the displayed cost.

**States**

| State | What shows |
|---|---|
| quote | "Refill {units} {meter} for {cost} {currency}", "You have {balance}; after this you will have {balance_after}", Confirm and Cancel with equal weight |
| price changed | the new quote replaces the old and Confirm needs a new tap; the sheet says the price changed |
| already full | "You're already full" and a Close; nothing was charged |
| no room | for a `units` offer: "Not enough room for {units}" |
| insufficient balance | "You need {shortfall} more {currency}" and a link to the currency shop (`billing.virtual-currency`); nothing opens by itself |
| in progress | Confirm is busy; the sheet cannot be closed by a swipe |
| pending (503 or timeout) | "Finishing your refill..." and the same `refill_id` is retried; the sheet states that the player is charged once |
| success | the new value and balance, then the sheet closes |
| offline | Confirm is disabled with "Connect to refill" |

**Copy rules**

- The price is the amount charged, in the currency the ledger spends. Where `billing.virtual-currency` provides a real-money reference for the currency, show it next to the cost; the EU network's principles ask for clear and transparent pricing and no practices that hide the cost of in-game content ([European Commission](https://commission.europa.eu/news-and-media/news/european-commission-hosts-stakeholders-talks-application-cpc-networks-key-principles-games-virtual-2025-06-03_en), HIGH; non-binding). Whether the reference must be in real money is a reading of the principle, not its text (MEDIUM; guide 06 rule 1 states it as the kit's floor).
- The balance after is shown so the player sees what remains. No "limited time" wording and no countdown on the sheet.
- The same offer shows the same price to every account in the same state. The sheet shows no "price for you" and no price that moves with how much the player has spent; an adopter-added rate for a group (a subscriber rate, say) is shown with the reason beside the price (INV-18).
- A boost offer states the length and what unlimited means: "Unlimited {meter} for 1 hour. Time already running is added."

**Accessibility**: the price and balance are in the dialog's description; Confirm announces its result through the status element; destructive-looking styling is not used for Cancel.

**Events**: client `energy_refill_confirm_shown`; client `energy_refill_failed` with `error`; server `energy_refilled` with `source = currency`.

## 5. Rewarded-ad refill

**Purpose**: let a player trade attention for a point, voluntarily, with the grant proven by the ad network's server.

**Flow**: the ad row starts the ad through the adopter's ad SDK (out of scope). The client sets the account id as the ad network's user id before showing the ad. When the ad closes the sheet shows "Adding your {meter}..." and polls `GET /api/energy` a few times (the adopter picks the interval and limit); the value rises when the server callback has been verified.

**States**: loading the ad, no ad filled, closed early (no reward: "The video ended early, so no {meter} was added"), reward pending (waiting for the server), reward delivered, daily limit reached, error. A reward that does not arrive within the polling limit shows "It can take a moment; we'll add it if the video was completed" and the sheet closes; the player can keep playing.

**Copy rules**: the row is optional and never the only exit. No dark button styling for skipping. No "watch to avoid losing your streak" wording.

**Accessibility**: the ad SDK's own controls are outside this block; the app's part (the row, the progress text) follows section 3.

**Events**: server `energy_refilled` with `source = ad`; client `energy_sheet_action` `ad`. Ad impressions are written by the ad integration.

## 6. Boost indicator

**Purpose**: tell the player that starts are free and when that ends.

**States**: active (infinity mark in the HUD and a banner row "Unlimited {meter} until {time}"); ending soon (no change in styling and no warning; the time is already shown); ended (a quiet toast "Unlimited {meter} ended" and the HUD returns to counts); stacked (the end time moves later, the banner says the new time).

**Copy rules**: state the end as an absolute time and a remaining duration from `boost_ends_at`; never imply that the boost refunds past attempts.

**Accessibility**: the start and end of a boost are announced once through the status element.

**Events**: server `energy_refilled` with `source = boost` at the grant or purchase.

## 7. Offline and error states

**Purpose**: keep the game usable and honest when the server cannot be reached.

| Situation | Behavior |
|---|---|
| Offline, `OFFLINE_ATTEMPTS` false | HUD shows the last values with "Last updated {age}"; Start shows "Connect to play"; non-energy screens work |
| Offline, `OFFLINE_ATTEMPTS` true | the client may start up to `OFFLINE_MAX_ATTEMPTS` sessions against the last `available` it saw; each gets its own `attempt_id`; they sit in a persisted queue; the HUD shows the points after the queue ("1 left, 2 will be checked when you're back online") |
| Reconnect with a queue | one `POST /api/energy/attempts/reconcile` with the queue in order; the result notice lists accepted and rejected sessions; the rewards of a rejected session are dropped and the notice says so |
| Request failed (5xx, timeout) | the last values stay; Retry; mutations retry with their stored ids |
| 429 | wait the `retry_after_seconds` and tell the player to try again in a moment |

**Copy rules**: never present a queued session's rewards as final before the reconcile result. A rejected offline session says "{meter} had already been used on another device; this session's rewards were not added".

**Accessibility**: offline and reconcile notices use the status element; they do not steal focus.

**Events**: server `energy_offline_reconciled` with `accepted` and `rejected`.

## 8. Gift inbox (optional)

**Purpose**: let a friend's gift reach the player without a request or an obligation.

**States**: empty ("No gifts right now"), list (sender name, units, expiry), claiming, claimed, no room ("You're at the maximum; this gift will wait until {expiry}"), expired, error, offline. A setting "Accept gifts" (default on) turns gifts off. Sending is a button on a friend's row; it states "Sent" or the daily limit; there is no "ask for energy" control anywhere.

**Copy rules**: nothing tells the player that a friend "needs" or "is waiting for" a reply gift.

**Accessibility**: list rows are buttons; claim results are announced.

**Events**: server `energy_gift_sent`, `energy_gift_claimed`; the claim also writes `energy_refilled` with `source = gift`.

## Pause and quit

When a session is on screen, `Pause` shows the cost of quitting: in `on_fail` games ("Leaving now costs a life" when `ABANDON_COUNTS_AS_FAIL`), in `on_start` games nothing (the point is spent). Quitting calls `finish` with `abandon`. A backgrounded session keeps its attempt; the server settles it after `ATTEMPT_TTL_SECONDS` by the rules in the README (3.2).

## Styling and anti-patterns

- No red badges or pulsing on the HUD to pull the player into the shop.
- No second copy of the sheets inside other screens; mount each once at the shell.
- No local arithmetic on `value`, `next_tick_at` or `full_at`.
- No paid prompt opened by code that is not a direct player tap.
- No hidden currency: a price is shown in the currency the ledger charges, with the balance after.
- Event names, properties and writers match the README (section 6) and `acceptance.md`.
