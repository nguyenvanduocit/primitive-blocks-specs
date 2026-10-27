# Frontend Patterns — Items

> Screens for a web-tech mobile shell (a web app in a native wrapper). The text is framework-agnostic: map the state names to your framework's reactive primitive. Snippets are L3 illustrative TypeScript with the four markers per `docs/SPEC_GUIDELINES.md` section 6; the behavior (WHAT) is in the prose. The server decides every fact on these screens: levels, costs, capacity, expiry and what a duplicate becomes (INV-3). The client shows them. Names of endpoints and fields are those of `backend.md`.

## Component tree

```
App shell
 ├── InventoryScreen              one page of instances plus stacks, from the server
 │     ├── CapacityBar            "Bag 187 of 200" per bag, text value
 │     ├── ActiveBoostStrip       active boosters with countdowns
 │     ├── ExpiryBanner           only when a copy is inside the warning window
 │     ├── HeldBanner             only when the held list is not empty
 │     ├── FilterBar              bag, kind, view toggle (grid, list), order
 │     ├── ItemGrid / ItemList    the same rows in two layouts
 │     └── StackList              count items with their balances
 ├── ItemDetailScreen             one instance or one stack
 │     ├── DisclosureList         how to get it, duplicate rule, expiry, free route
 │     └── ActionBar              Upgrade, Equip or Unequip, Convert, Discard
 ├── UpgradeSheet                 cost lines, balances, shortfall, confirm
 ├── EquipSheet                   slot, target, replace confirmation
 ├── InventoryFullSheet           held list and the three exits
 ├── ConvertSheet                 value, what is lost, confirm
 ├── DuplicateResultSheet         what a duplicate became
 ├── NoticesSheet                 "While you were away"
 └── ConsumeSheet                 booster use with its duration
```

| Unit | Responsibility | Interface |
|---|---|---|
| `items` state holder | Owns the last server answers, `inventory_version`, `serverOffset`, `loadState`, the `pendingRequests` map; serializes one mutation per instance | `loadInventory(filters)`, `loadMore()`, `loadStacks()`, `loadHeld()`, `quoteUpgrade(id)`, `upgrade(id)`, `equip(id, target?)`, `unequip(id)`, `discard(id)`, `convert(id)`, `claim(grantId)`, `consume(code, qty)` |
| Screens and sheets | Render state; hold no business rule | Read `items`; call the holder |
| Real-money helper | Computes the approximate money value of an amount of a purchasable currency from the store's price of the reference pack | Owned by the client of `billing.virtual-currency` (its `README.md`, "Real-money value"); this block asks it and never computes money itself |

Sheets are mounted once at the shell and shown by state.

### One request id per action

A mutation that times out may or may not have reached the server. The holder generates a `request_id` when the player confirms an action and keeps it in `pendingRequests` until a terminal answer arrives, so every retry of that confirmation reuses it.

<!-- PATTERN: request-id-per-action -->
<!-- PURPOSE: reuse one request id across retries of the same confirmed action and release it only on a terminal answer -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `newId` is any unique-id generator available in the shell (a UUID v4 from the Web Crypto API is typical); `send` is the shell's HTTP client; a terminal answer is any 2xx or a 4xx other than 409 `operation_in_progress` -->
```typescript
type Send<T> = (requestId: string) => Promise<{ status: number; body: T }>;

class PendingRequests {
  private ids = new Map<string, string>();
  constructor(private newId: () => string) {}

  async run<T>(action: string, send: Send<T>): Promise<{ status: number; body: T }> {
    const requestId = this.ids.get(action) ?? this.newId();
    this.ids.set(action, requestId);
    const reply = await send(requestId); // a thrown network error keeps the id for the retry
    const retryable = reply.status >= 500 || reply.status === 409 && (reply.body as any)?.error === "operation_in_progress";
    if (!retryable) this.ids.delete(action);
    return reply;
  }
}
// action key example: `upgrade:${instanceId}:${expectedVersion}`
```

## 1. Inventory screen

**Purpose**: show everything the player owns, what is equipped, what is active, what is about to expire and what is waiting, in an order that does not change under the player's thumb.

**Content**: the capacity bar per bag; the active-boost strip; the expiry banner and held banner when they apply; the filter bar; the item grid or list; the stack list. A row shows the item name, its level as text ("Level 4"), rarity as a label and shape, an "Equipped" mark, an expiry countdown when the copy has one, and a "Retired" label for a retired definition ("Not available to get").

**Ordering and paging**: the server returns `order` `newest` (default) or `rarity` pages (`backend.md`, "Inventory ordering and cursor"). The screen loads the first page, then the next page when the player scrolls to the end or taps "Show more"; it never reorders loaded rows when another row changes. Sorting by level or name is applied to the loaded rows on the device and is labeled "Sorted on this device". When `inventory_version` on a later page is higher than on page one, the screen refetches page one after the last page and merges new rows at the top.

**States**:

| State | UI |
|---|---|
| `loading` (first load) | Skeleton rows; no counts yet |
| `ready` | Everything above |
| `empty` | No items at all: "You have no items yet. Items you earn appear here." plus, when the game has item rewards, a link to the screen that lists them |
| `empty_filtered` | A filter hides everything: "No items match." with "Clear filters" |
| `partial` | Page one loaded, a later page failed: the loaded rows stay; the footer shows "Could not load more. Try again." |
| `offline` | The last snapshot, read-only, with "Last updated <time>"; every action control is disabled with the reason "Connect to continue"; countdowns are replaced by the absolute `expires_at` in local time |
| `error` | "Could not load your items." with Try again; the last answer, if any, stays visible and dimmed |
| `capacity_full` | The capacity bar reads "Bag 200 of 200" and the held banner states how many rewards are waiting; no row is hidden |

**Copy rules**: say what is true in plain words ("Bag 187 of 200", "3 rewards waiting for room"). A countdown is a plain remaining time with the absolute end time one tap away. No pulsing, shaking or red flashing on items or the banner; the expiry banner uses one static style. No sentence implies loss to push a purchase or an action ("Don't lose your items!" is not used).

**Accessibility**: the grid is a list of items; each item has an accessible name with name, level, rarity, state and expiry ("Iron Sword, level 4, rare, equipped, expires in 2 days"). Rarity and state are never conveyed by color alone: each has a text label or a shape with a name. The grid and list views hold the same rows in the same order, and the toggle announces its state. Touch targets meet the platform minimum. Focus returns to the row that opened a sheet when the sheet closes. Paging has a visible "Show more" control in addition to scroll loading.

**Analytics**: `inventory_viewed` on each open, `inventory_load_failed` on `error`.

## 2. Item detail

**Purpose**: everything the player needs to decide what to do with one item, with the disclosure fields of the definition in plain view.

**Content**: name, level (`Level 4 of 10`, or "Level 4" when `max_level` is 1), rarity, the game's own stat rendering (the block supplies `attributes` opaque; the game draws them), the action bar, and the **disclosure list**, always present for the fields the definition carries:

| Line | Shown when | Copy rule |
|---|---|---|
| How to get it | always | Lists the free route when `obtainable_free`; lists each random source with a "See odds" link that opens that source's odds screen by `odds_ref` |
| Duplicates | `max_copies` is set | One sentence from `duplicate_note_key`, followed by the exact value: "A duplicate becomes 30 Ember shards." For `cap`: "You can own one. This reward is not offered again." |
| Expiry | `expiry_mode` is not `none` | The sentence from `expiry_note_key` and what happens: "Expires on <date>. Then it converts to 50 coins." or "Expires on <date> and is removed." |
| Retired | the definition is `retired` | "This item is not available to get. Yours stays." |

**States**:

| State | UI |
|---|---|
| `loading` | Skeleton |
| `ready` | Content and the actions the item supports; an action the item cannot take is absent, not disabled, unless the reason helps ("Unequip first" on Discard of an equipped item) |
| `expired` | The copy is shown with an "Expired" label; only Discard and Convert (when it has a value) remain |
| `at_max_level` | Upgrade is replaced by the text "Max level" |
| `conflict` | A `version_conflict` answer: the screen reloads and shows "This item changed. We updated it." once |
| `not_found` | "This item is not in your inventory." and a back action |
| `offline` | Read-only from the cache; actions disabled with "Connect to continue" |

**Accessibility**: the disclosure list is a labeled list read before the action bar. "See odds" is a link with the name "See odds for <source>". The level is text, not only a bar.

**Analytics**: `item_detail_viewed` on open; `odds_link_tapped` on the odds link.

## 3. Upgrade sheet

**Purpose**: let the player see exactly what the next level costs, what they hold, and what is missing, and pay that cost once.

**Content**: "Upgrade to level 5"; one row per cost line from the quote (`GET /api/items/instances/{id}`): the material's name, "You have 340", "Needs 200"; the total result; and a confirm button whose label names the cost ("Upgrade for 200 coins"). A line the player cannot afford shows the shortfall ("60 more needed") and a path to earn it (the screen that grants it) or, for a purchasable currency, a link to the shop with the missing amount (`billing.virtual-currency`).

**Real-money value rule** (kit guide 14, Decision rule 4; `billing.virtual-currency`, "Real-money value"): every cost line in a purchasable currency (ledger `kind` `hard`) shows an approximate real-money value next to the amount, labeled "about", for example "200 gems, about $2.00". The device computes it with the real-money helper at the undiscounted reference rate. Lines in a soft currency or a count item show no money value. When the reference price is unavailable, the value is hidden and a "Pack prices" link opens the shop. The server returns each line's `kind` so the sheet knows which lines qualify; no money figure is stored or sent by this block.

**Confirmation and results**:

- The confirm button sends `expected_version` and `expected_cost` from the quote the player saw. The button is disabled while the request runs; a second tap does nothing.
- `cost_changed`: the sheet shows "The cost changed." with the new lines and an unchanged confirm button that needs a new tap. Nothing was spent.
- `applying`: while the request or its recovery runs, the sheet says "Finishing your upgrade." and keeps the controls disabled. On `operation_in_progress` or a network failure the holder retries with the same `request_id`. Past the retry schedule the sheet says "We are still finishing this upgrade. Your materials are safe." and offers Close; the result appears on the next open from the `notices` feed.
- `success`: "Level 5." with the new level, the balances after, and a Done action. A count-up on the level and a short haptic are permitted; the sequence is skippable and the balances are already credited.
- `reverted`: "The upgrade did not finish. Your materials were returned." with the amounts.
- `insufficient_balance`: the shortfall lines replace the confirm button; no spend happened.
- `version_conflict`: the sheet closes and the detail screen reloads (section 2, `conflict`).

**States**: `quote_loading`, `ready`, `insufficient`, `applying`, `success`, `reverted`, `cost_changed`, `max_level`, `expired` ("This item expired."), `offline` ("Connect to upgrade."), `error` (one sentence and Try again; the confirm is not offered again until the quote reloads).

**Copy rules**: costs are written as amounts and names. No countdown pressure, no "last chance", no preselected larger option. The sheet never offers to buy the missing materials with a different currency than the one the cost names.

**Accessibility**: the sheet is a modal dialog with a heading; focus moves to the heading on open and returns to the Upgrade button on close. Each cost row reads as one sentence ("Coins, you have 340, needs 200"). The result is announced once with a polite live region.

**Analytics**: `upgrade_sheet_opened`, `upgrade_confirm_tapped`, `upgrade_cost_changed_shown`, `upgrade_shortfall_action_tapped`.

### Cost line view

<!-- PATTERN: cost-line-view -->
<!-- PURPOSE: derive what one upgrade cost row shows from the server quote, including the real-money rule, with no business rule -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `approxMoney` is the real-money helper of the `billing.virtual-currency` client and returns null when the reference price is unavailable; `kind` comes from the quote -->
```typescript
type QuoteLine = { currency: string; kind: "soft" | "hard" | "item"; amount: number; balance: number };
type LineView = { need: number; have: number; short: number; about: string | null };

function costLineView(l: QuoteLine, approxMoney: (currency: string, amount: number) => string | null): LineView {
  return {
    need: l.amount,
    have: l.balance,
    short: Math.max(0, l.amount - l.balance),
    about: l.kind === "hard" ? approxMoney(l.currency, l.amount) : null,
  };
}
```

## 4. Equip flow

**Purpose**: put an item in its slot, on the player or on a unit, and make a replacement obvious.

**Flow**: Equip on the detail screen opens the sheet. For `equip_target` `unit` the sheet first asks which unit (a list of owned units, each with its current item in the slot); for `account` it goes straight to the slot. If the slot holds an item, the sheet shows "Replace <current> with <new>?" with both names and levels; the replaced item stays owned and returns to the bag list. Confirm sends `target_id` and `request_id`.

**States**: `choosing_target`, `confirm_replace`, `applying`, `success` ("Equipped"), `refused` (the game's `reason_key` text, for example "This hero cannot use heavy armor"), `conflict` (the item or target changed: reload and show once), `expired` ("This item expired."), `offline` ("Connect to equip.").

**Copy rules**: the refusal reason is the game's own sentence; the block supplies a key, not text. An item worn by another target says where: "Worn by Ember. Moving it unequips it there."

**Accessibility**: the unit list is a radio group with names and current items; the replace dialog names both items and levels; focus returns to the Equip button.

**Analytics**: `equip_sheet_opened`, `equip_replace_confirmed`; the server fires `item_equipped`.

## 5. Inventory-full sheet and the claim path

**Purpose**: tell the player that a reward is saved, show every exit, and never let a reward disappear.

**When it appears**: when a screen that grants rewards receives `held` in a grant result, when a claim answers `no_room`, and from the held banner. The granting screen shows "Reward saved. Your bag is full." and opens the sheet on tap; it never opens it by itself over another flow.

**Content**: the held list (`GET /api/items/held`): item, quantity, why it is held ("Bag full", "At the stack limit"), the date it converts by itself when `held_until` is set ("Converts to 50 coins on <date> if you do nothing"), and the room left. Three exits per row:

| Exit | Shown when | Result |
|---|---|---|
| Claim | Room exists | Applies as much as fits (`claim`) |
| Make room | The bag is full | Opens the inventory with a "Choose an item to discard or convert" mode; nothing is preselected and nothing is ordered by value |
| Convert held reward | `can_convert` | Opens the convert sheet (section 7) for the held quantity |

A held reward without a conversion value shows no time limit and says "Waits here until you claim it."

**States**: `loading`, `ready`, `empty` ("Nothing is waiting."), `claiming`, `claimed`, `no_room` ("No room yet. Make room or convert."), `offline` ("Connect to claim."), `error`.

**Accessibility**: the list is a list of held rewards; each row has the three exits as buttons with the item name in their labels. The date is written out, not only a countdown.

**Analytics**: `inventory_full_sheet_shown`, `held_claim_tapped`, `make_room_started`; the server fires `item_held_resolved`.

## 6. Duplicate disclosure and result

**Before**: wherever an item can be obtained (a reward preview, a source's reward list, the detail screen), the duplicate sentence and value appear beside the item (section 2, Duplicates). For an item with a random source the sentence is required by the definition (`duplicate_note_key`) and sits on the same screen as the odds link, before the player commits.

**After**: when a grant result reports `converted_quantity` above 0, the receiving screen shows the duplicate result sheet: the item's name, "You already own it.", what it became ("30 Ember shards added"), and, for `trade_in`, where the shards are used ("Used to upgrade Ember"). The balance is already credited. The sheet has one action, Done, and is skippable.

**States**: `ready`, `offline` (no sheet; the result is in the notices feed on the next open).

**Analytics**: `duplicate_result_shown`; the server fires `item_duplicate_converted`.

## 7. Convert and discard confirmation

**Purpose**: make the player's own conversion or discard an informed, deliberate action.

**Convert sheet** (an instance or a held reward): the item's name and level, the lines it returns ("Returns 120 coins"), and a sentence on what is not returned ("The materials spent on upgrades are not returned."). Confirm sends `expected_value`. `value_changed` shows the new value and needs a new tap.

**Discard sheet**: the item's name and level, "This cannot be undone.", Confirm and Cancel with equal weight. Discard of an equipped item is not offered; the detail screen says "Unequip first."

**States**: `ready`, `applying`, `success`, `value_changed`, `equipped` (blocked), `conflict`, `offline`, `error`.

**Copy rules**: Cancel is as large as Confirm; no countdown; the value is shown even when it is small. The sheet for a rare item (`rarity_rank` at or above the game's setting) adds the item's name to the Confirm label ("Discard Iron Sword").

**Accessibility**: a modal dialog; focus starts on Cancel, the safe action.

**Analytics**: `convert_confirm_shown`, `convert_confirmed`, `discard_confirm_shown`.

## 8. Expiry countdown and notices

**Countdown**: every timed copy and every active booster shows time remaining computed from `server_now` and the absolute `expires_at` or `ends_at`, corrected for drift (`serverOffset` = `server_now` minus device time at the response). The client never decides that a timer ended: at zero it reloads the item and shows what the server says.

<!-- PATTERN: server-clock-countdown -->
<!-- PURPOSE: compute remaining time from an absolute server instant and a measured offset between the server and device clocks -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `serverNow` is the `server_now` of the response and `deviceAtResponse` is `Date.now()` taken when it arrived; recompute the offset on every response; format with the shell's locale tools -->
```typescript
function makeClock(serverNowIso: string, deviceAtResponse: number) {
  const offset = Date.parse(serverNowIso) - deviceAtResponse;
  return {
    remainingMs(endsAtIso: string, deviceNow = Date.now()): number {
      return Math.max(0, Date.parse(endsAtIso) - (deviceNow + offset));
    },
  };
}
```

**Display**: more than a day left: "Expires in 3 days"; under a day: hours and minutes; under a minute: "Expires soon". The absolute end time in local time is one tap away. Screen readers read the sentence once when focus enters the row and at thresholds (one day, one hour), not every second. With reduced motion enabled, no animated countdown.

**Warning copy**, by outcome: `convert`: "Expires in 2 days. Then it converts to 50 coins." `remove`: "Expires in 2 days and is removed." Boosters: "Active for 12 minutes."

**Notices sheet** ("While you were away"): opens once after a load that returns unseen notices, as a list: "3 Frost Keys expired and became 150 coins.", "Your upgrade of Iron Sword did not finish. Your materials were returned.", "A waiting reward converted to 50 coins." Dismiss acknowledges them (`POST /api/items/notices/ack`). The sheet never blocks a game session already in progress; it waits for the next inventory open.

**States**: `ready`, `empty` (no sheet), `offline` (no sheet).

**Analytics**: `expiry_notice_shown` (banner or sheet), `notices_acknowledged`.

## 9. Booster use

**Purpose**: use a booster knowing exactly how long it lasts and what the policy does when one is active.

**Content**: "Use Double XP for 30 minutes." If one is active under `extend`: "Adds 30 minutes after the current one ends at <time>." Under `refuse`: "Already active until <time>." (Use is disabled.) Confirm sends `request_id` and quantity 1. The result shows `ends_at` and starts the countdown from `server_now`.

**States**: `ready`, `applying`, `success`, `refused`, `limit` ("You have the most booster time that can be queued."), `insufficient` ("You have none."), `offline`, `error`.

**Analytics**: server events `item_consumed` and `item_activated`; the client fires `inventory_viewed` only.

## 10. Offline and error handling

| Situation | Behavior |
|---|---|
| Offline on open | The last snapshot is shown read-only with "Last updated <time>"; no mutation control works; no mutation is queued for later |
| Offline during a mutation | The holder keeps the `request_id`; the sheet says "No connection. Your materials were not changed unless this says otherwise." and retries when the connection returns, with the same id |
| 5xx after a mutation | Retry with the same `request_id`; the answer is the stored result or `operation_in_progress` |
| `version_conflict` | Reload the item and show "This item changed. We updated it." once |
| `item_expired` | Reload and show the Expired state |
| `invalid_cursor` | Reload page one |
| Clock drift | The countdown uses the offset from the latest response; a device clock change does not change a result |

## 11. Accessibility (all screens)

- Every actionable element has an accessible name that includes the item name.
- Level, rarity, equipped, expired and retired are text or named shapes, never color alone.
- Touch targets meet the platform minimum; swipe gestures have a button alternative.
- Sheets are modal dialogs with a heading, a focus trap, Escape or back to close, and focus return.
- Results (upgrade success, equip, convert, claim) are announced once through a polite live region.
- Animations (count-ups, equip flourishes) respect reduced motion and are skippable; the state they show is already in effect.
- Text scales with the platform's text-size setting without clipping cost rows or the confirm button.

## 12. Analytics

Shared envelope from the kit guide `12-live-ops-and-instrumentation.md`. Client events:

| Event | Properties | When |
|---|---|---|
| `inventory_viewed` | `view` (`grid`, `list`), `order`, `bag`, `held_count`, `entry_point` (`home`, `reward_toast`, `push`, `deep_link`) | The inventory opens |
| `inventory_load_failed` | `reason` (`offline`, `error`), `has_snapshot` | The first load fails |
| `item_detail_viewed` | `item_code`, `level`, `state` (`owned`, `expired`, `retired`), `source` (`inventory`, `reward`, `held`) | The detail screen opens |
| `odds_link_tapped` | `item_code`, `source_code` | The player taps "See odds" |
| `upgrade_sheet_opened` | `item_code`, `from_level`, `affordable` | The sheet opens |
| `upgrade_confirm_tapped` | `item_code`, `from_level`, `cost_lines` | The player confirms |
| `upgrade_cost_changed_shown` | `item_code`, `from_level` | A `cost_changed` answer is shown |
| `upgrade_shortfall_action_tapped` | `item_code`, `currency`, `action` (`earn`, `shop`) | The player follows a shortfall path |
| `equip_sheet_opened` | `item_code`, `slot`, `target_kind` | The equip sheet opens |
| `equip_replace_confirmed` | `item_code`, `replaced_item_code` | The player confirms a replacement |
| `inventory_full_sheet_shown` | `held_count`, `trigger` (`grant`, `claim_attempt`, `held_banner`) | The sheet opens |
| `held_claim_tapped` | `item_code`, `held_quantity` | The player taps Claim |
| `make_room_started` | `action` (`discard`, `convert`) | The player starts choosing an item to remove |
| `convert_confirm_shown` | `item_code`, `level`, `context` (`player`, `held`) | The convert sheet opens |
| `convert_confirmed` | `item_code`, `context` | The player confirms |
| `discard_confirm_shown` | `item_code`, `level` | The discard sheet opens |
| `duplicate_result_shown` | `item_code`, `rule` (`convert`, `trade_in`) | The duplicate result sheet opens |
| `expiry_notice_shown` | `count`, `soonest_ends_in_seconds`, `surface` (`banner`, `notices_sheet`) | An expiry banner or notice shows |
| `notices_acknowledged` | `count` | The player dismisses the notices sheet |

Server events are listed in `README.md` section 6. No event carries a price or a money amount.

## Anti-patterns

| Anti-pattern | Why it fails |
|---|---|
| Sending `level`, a cost or an amount from the client | The server owns them (INV-3); a mismatch is `cost_changed` |
| Generating a new `request_id` on each retry | A timeout then double-spends or double-grants from the player's view |
| Reordering loaded rows when one changes | The player taps the wrong item |
| Opening the inventory-full sheet over a running game session | A rule of the kit: at most one non-blocking popup per app open (guide 10, Decision rule 5) |
| Showing a countdown from the device clock | The server decides expiry; a changed clock cannot end or extend a timer |
| Preselecting the most valuable item for "make room" | The player discards by accident; nothing is preselected |
| Hiding the duplicate sentence until after a pull | The rule must be visible before the player commits (kit guide 14, Decision rule 10) |
