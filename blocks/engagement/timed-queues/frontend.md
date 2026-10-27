# Frontend Patterns: Timed Queues

> Client text is framework-agnostic: the client is a web-tech mobile shell (a web app in a native wrapper). Snippets are L3 illustrative TypeScript with the four markers per `docs/SPEC_GUIDELINES.md` section 6; map state holders to your reactive primitive. Wording shown in quotes is placeholder English; the rules about what the player must be told are the contract. Every string is a localization key; the server sends keys, never display text.
>
> The client never decides that an item is ready, never sends a time, and never computes a price. It shows what the server returned and asks the server when a countdown reaches zero.

## Component tree

```
App shell
 ├── Home entry (queue button)          number badge = ready items, nothing else
 ├── QueuePanel                         one tab per queue (kind icon, name)
 │     ├── IdleNudgeCard                at most one, inline, dismissible
 │     ├── SlotCard (per lane)          idle, reserved, queued, running, ready, locked, revoked
 │     ├── CollectAllBar                when two or more items are ready
 │     └── SuggestionRow                "start again" and up to two more jobs
 ├── StartSheet                         cost, duration, output, cancel terms
 ├── SpeedUpSheet                       free finish, time items, price per step, ApproxMoney beside each price
 ├── CancelSheet                        what comes back, what does not
 ├── UnlockSheet                        locked-slot options with full disclosure
 ├── CompletionToast                    one per refresh batch, never blocking
 └── (host) Local-notification scheduler   consumes queue_item_ready events (messaging.push-reengagement)
```

| Unit | Responsibility | Interface |
|---|---|---|
| `queues` store | Holds the last `GET /api/queues` body, the `ServerClock`, quotes, busy flags; applies every response | `refresh()`, `start()`, `collect()`, `collectAll()`, `cancel()`, `quote()`, `speedUp()`, `unlockSlot()`, `claimPurchase()`, `reportNudge()` |
| `SlotCard` | Renders one lane; no business logic | reads lane state and the clock; calls store actions |
| Sheets | Render a flow from store state; one mounted copy at the shell | open with an item or lane id |
| Hand-off emitter | After every response, emits `queue_item_ready` on the client event bus for each `armed` and `resolved` entry the response carries | event bus |

## 1. The countdown

The countdown is built from the response's `server_now` and the item's absolute `ends_at`. It uses a monotonic timer between responses, so a change of the device's wall clock cannot move it (README section 3, Clock manipulation).

<!-- PATTERN: server-clock-countdown -->
<!-- PURPOSE: show a countdown from server_now and ends_at, immune to device clock changes, and ask the server when it reaches zero -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `performance.now` -> your monotonic timer (it can pause while the app is suspended, so also call refresh() on resume); `refresh` -> the store's GET /api/queues; add jitter and backoff to refresh when the server still reports the item as running -->
```typescript
interface ServerClock { serverMs: number; monoMs: number }  // captured when a response arrives

const capture = (serverNowIso: string): ServerClock =>
  ({ serverMs: Date.parse(serverNowIso), monoMs: performance.now() });

const serverNow = (c: ServerClock): number => c.serverMs + (performance.now() - c.monoMs);

const secondsLeft = (endsAtIso: string, c: ServerClock): number =>
  Math.max(0, Math.ceil((Date.parse(endsAtIso) - serverNow(c)) / 1000));

function onTick(item: { endsAt: string; state: string }, c: ServerClock, refresh: () => void) {
  // zero on screen means "ask", never "ready": the ready state comes from the server
  if (secondsLeft(item.endsAt, c) === 0 && item.state !== "ready") refresh();
}
```

Rules:

- **Resume and focus refresh.** On app resume and on regaining connectivity, call `refresh()` before showing any countdown as current.
- **Drift report.** When a response moves a displayed countdown by more than `COUNTDOWN_DRIFT_REPORT_SECONDS`, fire `queue_countdown_corrected` with the drift.
- **Offline.** The last clock keeps running for display only and the card is labelled stale (section 9).
- **Format.** Remaining time as the two largest units ("2 h 05 min", "14 min 20 s"), localized. The absolute ready time ("ready at 14:00") shows in the device's local time zone beside it, converted from `ends_at`.
- **No countdown elsewhere.** A countdown appears only on a running or queued item card and in the speed-up sheet header. No countdown is attached to an offer, an unlock or a nudge (INV-20; guide `06-design-ethics-and-compliance.md`).

## 2. Queue panel and slot cards

**Purpose.** One place to see everything the player has running, what is ready, and what can start next. It is the only screen that needs the whole queue state.

**Structure.** A tab per queue (kind icon and name). Under it, one card per lane in slot order: active lanes first, then the next locked slot (full card), then later locked slots as a compact list. The queue's jobs appear in the start sheet, not in the panel body.

| Card state | Shows | Actions |
|---|---|---|
| `idle` | "Free" and the "Start" control; the last collected job as "Start again" when affordable | Start (opens the start sheet, or starts directly for "start again" after its own confirmation line showing cost and duration) |
| `reserved` (start in progress, spend not confirmed) | "Starting..." with a spinner, no countdown | None; resolves in a moment or shows the error |
| `running` | Job name, countdown, ready-at time, a progress bar with the number of time left beside it | Speed up, Cancel |
| `queued` (behind another item) | Job name, "Starts at 12:15", "Ready at 12:30" | Cancel (full refund stated) |
| `ready` | Job name, output lines, "Ready" | Collect |
| `locked` | What the slot adds, the cheapest unlock options (each with its price), progress toward a free option | Opens the unlock sheet |
| `revoked` | "Closed after a refund. Items already here will finish." | None for new items; existing items behave as above |

Copy rules:

- A lane with two or more items shows them as a short list on one card in chain order, with one ready-at time per item.
- The card never shows "hurry", "don't miss", "only", urgency colors or pulsing. Ready is shown with the check icon and text, not a flashing mark.
- The progress bar has a number beside it (guide `08-objectives-and-progression.md`, rule 9): the animation never runs ahead of the server's times.
- A queued item's time is "starts at" and "ready at"; it is exact because chaining is deterministic. After a speed-up or cancel ahead of it, the times move earlier, and the card updates with no emphasis.

Accessibility: each card is a labelled region ("Craft slot 1, running, bread, 12 minutes left"); the live countdown is not announced every second (update the accessible text at most once a minute, and on state change); state is never conveyed by color alone (icon and text beside it); controls meet the platform minimum touch target.

Events: `queue_panel_viewed` on open (properties of README section 6).

### Home entry

The entry point carries a plain number badge equal to the count of ready items, nothing when zero. No pulse, glow, ring or timer on it (guide `10-screens-and-navigation.md`, attention marks: badges are reserved for critical information and capped). The idle-slot nudge never adds a badge.

## 3. Start sheet

**Purpose.** Let the player decide to start one job knowing exactly what it costs, how long it takes, what it pays and what cancelling returns.

Contents, in this order:

1. Job name and kind icon.
2. **Time.** "Takes 15 min" and, for a queued start, "Starts about 12:15, ready about 12:30".
3. **Cost.** Each input line as "Flour 3 (you have 9)". A short line is marked with the missing amount ("Need 3 more"). No premium currency ever appears here (V3), so no `ApproxMoney` renders on this sheet; a line priced in a purchasable currency would carry it by the same rule as the other sheets.
4. **Output.** Each output line; an `effect` line reads as its host-defined name ("Farm level 2").
5. **Cancel terms.** "Cancel while it waits: everything comes back. Cancel while it runs: 50% comes back." The percentage is the job's `cancel_refund_fraction` from the same response the sheet renders; it is the value the item will snapshot.
6. **Actions.** "Start" and "Not now", equal visual weight.

| State | Behaviour |
|---|---|
| Ready to start | "Start" enabled |
| Short of input | "Start" disabled; the shortfall line names the currency, the amount missing, and a neutral "Where to get it" link supplied by the host (faucets, never a purchase prompt) |
| Job locked | The reason in words: "Finish Farm level 2 first" (prerequisite), "Reach tier 2" (flag), "Already in progress" (max active), "Already done" (not repeatable) |
| Lane full / time cap / ready cap | "This slot is full until something finishes." / "Too much already queued here." / "Collect your finished items to start more", with a collect action |
| Busy | The button shows progress; a second tap does nothing |
| `start_in_progress` | One automatic retry after a short delay, then "Another device is starting something here. Try again." |
| Offline | "Start" disabled with "Connect to start" |
| Success | Sheet closes; the card shows the item with its countdown; no celebration modal |

Copy rules: cost and time are stated before the tap; the decline control is as visible as the accept control; no preselected extras; no "recommended" speed-up in this sheet (speed-ups live on the item, after the start).

Accessibility: the sheet is a dialog with focus moved to its title; the cost and the cancel terms are read before the Start control in the focus order; the disabled Start control carries the reason in its accessible description.

Events: `queue_start_sheet_viewed` (`queue_id`, `job_id`, `can_afford`); errors fire `queue_error_shown`.

## 4. Speed-up sheet

**Purpose.** Let the player skip some or all of the remaining time knowing the exact price per step and its real-money equivalent (through `ApproxMoney`), with the free option, the free path and the quote's honesty visible at once.

The sheet opens by requesting quotes. It lists, top to bottom:

1. **Header.** Job name and remaining time (the one countdown the sheet shows) and "Ready at 14:00 if you wait". Waiting is always the first, always visible option, with the same weight as the paid rows.
2. **Free finish** (only when `remaining <= free_finish_seconds`). "Finish now: free".
3. **Time boosts you own.** "Use 1 hour boost (you have 2)" with the result stated ("Ready in 1 h") and the count that will be used. The count is the server's `min(max_count, needed)` rule, shown as "uses 2" when finishing needs two.
4. **Price per step.** One row per quote: "Skip 1 hour: 11 gems" and "Finish now: 31 gems". Each row renders `ApproxMoney` beside the gems price (for example "about $0.35"), and shows what the item's ready time becomes.
5. **Balance line.** "You have 100 gems. After finishing now: 69."
6. **Close.** "Not now".

**Real-money value.** Beside every price in a purchasable currency the sheet renders the shared `ApproxMoney` component of `billing.virtual-currency` ([its `frontend.md` section 9](../../billing/virtual-currency/frontend.md); its README, "Real-money value"). The sheet passes the component the currency code and the amount and computes no money figure; the server sends none. The component hides itself for a soft currency and when the reference price is unavailable (store unreachable), and a "pack prices" link takes its place. The paid rows stay usable in that case: the price in gems is exact and the money equivalent is display only. Basis: the CPC network's principle that the real-money price of content bought with virtual currency be shown clearly, at what the consumer would pay in full ([Key Principles on In-game Virtual Currencies](https://esportslegal.news/wp-content/uploads/2025/03/Key-principles-on-in-game-virtual-currencies.pdf), HIGH for the text; kit guide `14-rewards-resources-and-items.md`, rule 4).

| State | Behaviour |
|---|---|
| Loading quotes | Rows show placeholders; no price is shown until quotes arrive; no countdown on the quotes |
| Ready | Rows as above |
| Quote refreshed, same or lower price | Silent update |
| Quote refreshed, higher price (a new curve) | The row shows the new price with "Price updated: 31 gems, was 28"; the confirm needs a new tap; fire `queue_speedup_price_changed_shown` |
| `quote_expired` / `quote_stale` | Fresh quotes replace the rows with the line "The time left changed. New price shown." and no charge |
| `insufficient_balance` | The row shows the shortfall ("Need 21 more gems"); the host supplies a neutral link to earn or buy exactly that amount; nothing else is pre-selected |
| Paid speed-ups off (`paid_speedup_disabled`) | Paid rows are absent; free finish, boosts and waiting remain |
| `item_not_running` | "This item is not running." and the sheet closes after refresh |
| Success | The card updates; one line "Spent 20 gems" (the **charged** amount, which can be lower than the quoted 21); the sheet closes |
| Offline | Paid rows disabled; "Connect to speed up" |

Copy rules:

- The price is in the buying currency and in money, both visible before the tap. The confirm control says what it spends: "Spend 31 gems".
- No "best value", "most popular" or preselected row. No countdown on prices. No "limited time" wording. The quote's validity window is invisible to the player except through the price-updated line.
- Rows are ordered by time skipped, ascending; free options first. The decline path ("Not now") is as visible as the price rows.
- Step prices are the telescoped differences of one curve (INV-13), so the sheet never makes several small steps dearer than finishing; the sheet may state this once: "Skipping in steps never costs more in total."
- For an account flagged as a minor with paid speed-ups off, the sheet shows only the free options.

Accessibility: each row is one button whose accessible name reads the whole offer ("Skip 1 hour, 11 gems, about 35 cents, ready at 13:00"); the confirm result is announced politely; do not move focus after a price refresh.

Events: `queue_speedup_sheet_viewed`, `queue_speedup_price_changed_shown`; server events `queue_speedup_quoted`, `queue_speedup_applied`.

## 5. Cancel sheet

**Purpose.** Let the player cancel with the consequences stated first.

Contents: "Cancel Bread?"; "You get back: Flour 1 (50%)" computed from the item's snapshot fraction (the server returns `refund_preview` with the item; a queued item shows 100%); "Time already passed is not returned."; when `sped_up`: "Speed-ups you already used are not returned."; two controls with equal weight, "Keep it going" and "Cancel item". A `ready` item shows no cancel control.

States: busy; success ("Cancelled. Flour 1 returned") then the card is idle; `invalid_transition` (the item just finished): "It finished. Collect it instead." with a collect action.

Events: `queue_item_cancelled` (server).

## 6. Completion toast, collect and collect-all

**Completion toast.** When a refresh shows items that became ready while the app was open, show one toast per refresh batch: "Bread is ready" with a "Collect" action, or "3 things are ready" with "Collect all". It never blocks, never auto-collects, never repeats for the same item, and stays until dismissed or acted on when a screen reader is active (otherwise at least `6` seconds, a client default). Fire `queue_completion_toast_shown` once. Haptics and sound follow the player's settings.

**Collect.** The control on a ready card. States: busy; success (the card shows "+2 Bread" briefly, then becomes idle with the "start again" suggestion); `collect_blocked_cap` ("Your Bread storage is full. Make room and try again." with the host's link to its use or sale screen; the item stays ready); 503 ("We couldn't finish adding your rewards. Nothing is lost; try again in a moment."); `already_collected` (treated as success).

**Collect all.** Shown when `ready_count >= 2` (also as the toast action). One tap collects every ready item up to `COLLECT_ALL_MAX`; the summary lists totals per currency and item ("+4 Bread, +400 Coins"), then any item that did not collect with its reason. A `more` flag shows "Collect more" until none remain. Fire `queue_collect_all_tapped` with `ready_count`.

After a collect the response's `suggestions` fill the suggestion row ("Start Bread again", up to two more jobs). When nothing is affordable the row names what is missing and where it comes from, never a blank state (INV-19, the design rule of README section 3).

Accessibility: totals and failures are announced in one polite message, not per item.

## 7. Idle-slot nudge card

**Purpose.** Offer to start something when a slot is idle and the player can afford it, without nagging.

Shown only when `idle_nudge.eligible` is true: an inline card at the top of the queue panel: "Slot 2 is free. Start Bread again?" with "Start" (opens the start sheet for `idle_nudge.job_id`, or starts after a one-line confirmation of cost and duration) and "Not now".

Rules:

- The client reports `shown` when the card first renders in the viewport, `dismissed` on "Not now" or a swipe, `acted` on "Start"; the server owns the counters (`IDLE_NUDGE_*`), so a second device sees the same cap (README section 3).
- Inline in the panel only: never a modal, a toast, a badge, a sound or a push. It does not appear on the home screen or at app open outside the panel.
- No countdown, no streak or loss language, no "your slot is wasting time".
- After repeated dismissals the server stops offering for a week; the card simply does not appear.

Events: `queue_idle_nudge_shown`, `queue_idle_nudge_dismissed`, `queue_idle_nudge_acted` (`queue_id`, `slot_index`, `job_id`).

## 8. Unlock sheet (locked-slot upsell)

**Purpose.** Show what a locked slot adds and every way to get it, with the facts the player needs to decide.

Contents:

1. **What it adds.** "A third crafting slot: craft two things at once." One sentence, no superlatives.
2. **Every option in the definition**, each with its cost or condition:
   - *Free option* (progression flag): "Reach tier 2" with the player's current progress where the host reports it. Free options are listed first and are never hidden or reduced when a paid option exists.
   - *Currency option*: "150 gems" with `ApproxMoney` beside the price (section 4 states its hiding rules) and the player's balance.
   - *Store product*: the store's localized price string (never a constant in the app), for example the string the store returns for `slot_craft_plus`.
3. **Disclosure line.** "Permanent. Works on all your devices. If the store refunds this purchase, this slot closes for new items; items already in it still finish."
4. **Restore.** A visible "Restore purchases" control when a store product is listed (Apple 3.1.1: "a restore mechanism for any restorable in-app purchases", [Apple](https://developer.apple.com/app-store/review/guidelines/), HIGH, read 2026-10-27).
5. **Actions.** One button per option and "Not now", equal weight; no option is pre-selected; no timer, no "limited offer", no discount that is not real.

| State | Behaviour |
|---|---|
| Loading store price | The store option shows a placeholder and is disabled; other options work |
| Purchases disabled or a parental gate required (`purchase_policy`) | The store and currency-for-money paths follow the policy of `billing.virtual-currency`; free options remain |
| Buying | The store sheet is the store's; on return call `claim-purchase` with the transaction id; show "Slot unlocked" when the server answers |
| `purchase_not_verified` (pending) | "Your purchase is pending. The slot opens when the store confirms it." No retry loop longer than a few polls; the slot opens through `on_purchase_state_changed` |
| `slot_out_of_order` | The sheet shows the next unlockable slot instead |
| `insufficient_balance` | Shortfall shown as in the speed-up sheet |
| Already unlocked on another device | "Already unlocked." and the panel refreshes |
| Offline | Options that need the server are disabled; "Connect to unlock" |

Accessibility: the options are a list of buttons with full accessible names (cost, condition, permanence); the disclosure line is not hidden behind a disclosure control.

Events: `queue_slot_upsell_viewed` (`queue_id`, `slot_index`, `option_kinds`); server `queue_slot_unlocked`.

## 9. Offline and error states

| Condition | Panel behaviour |
|---|---|
| First load | Skeleton cards with no countdowns |
| Offline, cached state | A quiet label "Showing saved state"; countdowns run from the last clock and are dimmed with "may be out of date"; Start, Collect, Speed up, Cancel and Unlock are disabled with "Connect to ..."; no red error and no startup alert (guide `10-screens-and-navigation.md`, offline rows) |
| Server error on load | "Could not load your queues." with Try again; cached cards stay visible if present |
| Action fails with 503 | The action's own message (sections 3 to 8); the control becomes usable again; the request is retryable with the same `attempt_id` |
| Another device changed the state | A short note "Updated on another device" and a refresh |
| `rate_limited` | "Too many requests. Try again in a moment." |
| Maintenance (host) | Actions disabled and a banner with the host's end time |

All money and reward actions are online-only: the client queues no start, collect, cancel or speed-up intent for later (guide `12-live-ops-and-instrumentation.md`, rule 19). A tap while offline shows the "Connect to ..." text.

## 10. Hand-off from the client

After every response that carries `handoff[]` or `armed[]`, the client emits `queue_item_ready` on its event bus for each entry (`subject_key`, `state`, `ends_at`, `fire_at`, `expires_at`, `revision`, `params`). The host's local-notification scheduler of `messaging.push-reengagement` upserts by `subject_key` and keeps the highest `revision`; a `resolved` entry cancels. On app start and resume the client calls `refresh()` first, then replays `armed[]` so the local schedule matches the server's. At most `LOCAL_MAX_PENDING` local notifications exist (README validation V6).

## 11. Analytics events (client)

| Event | Properties | When |
|---|---|---|
| `queue_panel_viewed` | `queue_id`, `idle_slots`, `running`, `ready` | The panel is shown |
| `queue_start_sheet_viewed` | `queue_id`, `job_id`, `can_afford` | The start sheet opens |
| `queue_speedup_sheet_viewed` | `item_id`, `remaining_seconds`, `free_available`, `finish_price_shown` | Quotes are shown |
| `queue_speedup_price_changed_shown` | `item_id`, `old_amount`, `new_amount` | A refreshed quote differs from the last one seen |
| `queue_completion_toast_shown` | `item_id`, `queue_kind` | The toast appears |
| `queue_collect_all_tapped` | `ready_count` | Collect all is used |
| `queue_idle_nudge_shown`, `queue_idle_nudge_dismissed`, `queue_idle_nudge_acted` | `queue_id`, `slot_index`, `job_id` | The nudge outcomes |
| `queue_slot_upsell_viewed` | `queue_id`, `slot_index`, `option_kinds` | The unlock sheet opens |
| `queue_countdown_corrected` | `item_id`, `drift_seconds` | Drift above the threshold |
| `queue_error_shown` | `queue_id`, `error` | An error state renders |

The shared envelope of guide `12-live-ops-and-instrumentation.md` applies. Server events are in README section 6.

## Anti-patterns

| DON'T | Why |
|---|---|
| Mark an item ready because the local countdown hit zero | Only the server's effective state decides (INV-1); a wrong device clock would show collectable items that are not |
| Show a countdown on a price, an offer, an unlock or a nudge | Manufactured urgency; guide 06 and CPC principle 7 |
| Pre-select a paid row or order rows by price descending | Anchors the player on the most expensive option |
| Compute a money figure in this block, or leave `ApproxMoney` off a price in a purchasable currency | One shared component computes the only money figure (virtual-currency INV-24); CPC principle 1 and guide 14 rule 4 |
| Disable the free finish or hide "just wait" | The non-paying path must stay visible (INV-17) |
| Show the quoted price after the server charged less | The sheet reports the charged amount |
| Queue a spend, collect or cancel for later while offline | Money and rewards are online-only; an optimistic grant the server may refuse is a trust bug |
| Auto-collect when an item finishes | The player chooses when to claim; auto-collect also hides a refused grant |
| Turn a dismissed nudge into a badge or a push | INV-20 |
| Put a price constant in the app for a slot product | The store's price string is the price (virtual-currency INV-16) |
