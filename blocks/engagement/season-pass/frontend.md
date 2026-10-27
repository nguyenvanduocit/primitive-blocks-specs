# Frontend Patterns — Season Pass

> Screens for a web-tech mobile shell (a web app in a native wrapper). The text is framework-agnostic: map the state names to your framework's reactive primitive. Snippets are L3 illustrative TypeScript with the four markers per `docs/SPEC_GUIDELINES.md` section 6; the behavior (WHAT) is in the prose. The server decides every fact on these screens: tier, claimability, premium state, prices, windows and the season's end (INV-1). The client shows them.

## Component tree

```
App shell
 ├── SeasonPassScreen            driven by one server answer (README: state response)
 │     ├── SeasonHeader          season name, countdown, tier badge, XP into tier
 │     ├── EndingSoonBanner      only inside ENDING_SOON_WINDOW_SECONDS
 │     ├── NextRewardCard        the next reward the player does not hold
 │     ├── TrackGrid             free row, premium row, one TierCell per tier, repeat cell
 │     ├── ClaimAllBar           "Claim all (N)"
 │     └── EntryRow              Premium, Skip tiers, XP boost entries (each only when available)
 ├── PremiumSheet                full contents, price, rules, purchase
 ├── SkipSheet / BoostSheet      share PriceConfirm: quote, balance after, confirm
 ├── ClaimResultSheet            what a claim or claim-all delivered
 └── SeasonResultsScreen         final tier, delivered, claimed, next season
```

| Unit | Responsibility | Interface |
|---|---|---|
| `pass` state holder | owns the last server answer, `clockOffset`, `loadState`, in-flight claims; serializes writes per cell | `load()`, `claim(items)`, `claimAll()`, `confirmPremium(txnId)`, `quoteSkip(n)`, `buySkip(...)`, `buyBoost(...)` |
| Screens and sheets | render state; hold no business rule | read `pass`; call the holder |
| Store bridge | the store SDK purchase of the premium product and the price string | owned by `billing.virtual-currency`'s client; this block asks it for the price string and the purchase result |

Sheets are mounted once at the shell and shown by state.

## 1. Pass track screen

**Purpose**: show where the player stands in the season and what is next, in one glance, with the free and premium rows side by side.

**Content**: season name; a countdown to the end (section 5); current tier and the XP bar into the next tier (`xp_into_tier` of `xp_for_next_tier`; at the final tier the bar is full and says so); the tier grid; the next-reward card; the claim-all bar; the entries for premium, skips and boosts.

**Tier grid rules**:

- Both rows show every tier. Premium rewards are visible to every player, with a text label "Premium" on the row, so the player sees what premium holds before any prompt.
- A tier with no reward on a track shows an empty cell with the accessible name "no free reward at tier 2".
- Repeat tiers after the last defined tier show as one repeat cell: the reward, "every 300 XP", and the count reached.
- The grid opens scrolled to the player's tier. Claimable cells carry a badge; the screen shows the total claimable count.

**States**:

| State | UI |
|---|---|
| `loading` (first load) | skeleton of header and grid; no countdown yet |
| `ready` | everything above |
| `no_season` | "No season is running." plus the next season's name and absolute start time when the server returns `next_season`; no grid, no entries |
| `offline` | the last answer, read-only, with "Last updated <time>"; the countdown is replaced by the absolute end time; claim, skip, boost and purchase controls are disabled with the reason "Connect to claim" (section 8) |
| `error` | "Could not load your season pass." with Try again; the last answer, if any, stays visible dimmed |
| `claim_window` | the season has ended and `claim_until` has not passed: the header says "Season ended", claimable cells stay claimable (section 6) |
| `closed` | redirect to the results screen (section 6) |

**Copy rules**: say what a tier needs in XP ("250 XP to tier 8"), never in vague pressure ("almost there!") or loss framing ("don't miss out"). The countdown is a plain remaining time. No element blinks or pulses for attention beyond the one claimable badge.

**Accessibility**: the grid is a list of tiers, each tier a group with the free and premium cells; every cell has an accessible name with tier, track, reward and state ("Tier 7, premium, 15 gems, ready to claim"). State is never conveyed by color alone: the premium label, the lock glyph and the claimed check are text or shapes with names. Touch targets meet the platform minimum. The XP bar has a text value (`50 of 200 XP`).

**Analytics**: `season_pass_viewed` on each open (`entry_point`: `home`, `banner`, `push`, `claim_toast`), `season_pass_error_shown` on `error`.

## 2. Tier cell, claim, claim all

**Purpose**: deliver an earned reward exactly once and make the result obvious.

**Cell views** (derived from the server answer; pure):

<!-- PATTERN: cell-view -->
<!-- PURPOSE: derive what one tier cell shows from the server answer and the in-flight set, with no business rule beyond what the server returned -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `me.claimed` -> a map from `track:tier` to `granted` or `pending` built from the state response; `me.tier` and `me.premiumState` come from the response, never from local arithmetic on XP -->
```typescript
type CellView = "locked" | "claimable" | "claiming" | "claimed"
  | "premium_locked" | "premium_removed" | "no_reward";

function cellView(c: { track: string; tier: number; reward: unknown }, me: Me, inFlight: Set<string>): CellView {
  if (!c.reward) return "no_reward";
  const key = `${c.track}:${c.tier}`;
  const state = me.claimed.get(key);
  if (state === "granted") return "claimed";
  if (state === "pending" || inFlight.has(key)) return "claiming";
  if (c.tier > me.tier) return "locked";
  if (c.track === "premium" && me.premiumState === "none") return "premium_locked";
  if (c.track === "premium" && me.premiumState === "revoked") return "premium_removed";
  return "claimable";
}
```

| View | UI |
|---|---|
| `locked` | reward preview, "<n> XP to go" for the next locked tier only; not tappable |
| `claimable` | "Claim"; tap claims this cell |
| `claiming` | spinner on this cell; the cell ignores a second tap (the holder serializes per cell) |
| `claimed` | check mark and "Claimed"; stays visible |
| `premium_locked` | reward preview with the "Premium" label; tap opens the premium sheet (section 3). A premium cell the player has already reached says "Reached, unlocks with premium" |
| `premium_removed` | "Premium removed"; not claimable; claimed cells stay `claimed` |
| `no_reward` | empty cell |

**Single claim**: tap, the holder sends `POST claims` with the cell, shows `claiming`, and on `granted` plays the reward feedback and updates the cell from the response's `state`. On `already_claimed` (another device or a race) the cell becomes `claimed` quietly with no error and no second reward animation. On `tier_not_reached` or `premium_required` the screen reloads the state, because the server knows something the client did not.

**Claim all**: the bar shows "Claim all (N)" where N is the server's `claimable` count; it is hidden at 0. The result opens the claim-result sheet listing every reward delivered, grouped by code ("3 x coin 650, 1 x hint pack"), with each cell's outcome. A partial result says how many were delivered and how many remain ("Delivered 5 of 7. 2 could not be delivered yet." with Try again); the undelivered cells stay `claiming` or `claimable` as the server says.

**Retry rule** (identical request is safe because claims are idempotent, INV-7):

<!-- PATTERN: claim-with-one-retry -->
<!-- PURPOSE: survive a dropped connection on a claim without a duplicate reward or a client-made id -->
<!-- REFERENCE: language=typescript framework=agnostic http=fetch-builtin -->
<!-- ADAPT: `post` and `isNetworkError` -> your HTTP wrapper; keep the body identical on retry; after the second failure show Try again and let the player repeat the same action -->
```typescript
async function claim(seasonId: string, items: { track: string; tier: number }[]) {
  const body = { season_id: seasonId, items };
  try {
    return await post("/api/season-pass/claims", body);
  } catch (e) {
    if (!isNetworkError(e)) throw e;
    return post("/api/season-pass/claims", body);   // same body, same ledger keys server-side
  }
}
```

**Copy rules**: after a claim say exactly what arrived ("+150 coins"). Never auto-open a purchase prompt from a claim. A rejected cell uses a one-line reason, not a code.

**Accessibility**: the claim result sheet is a dialog with focus moved to its title; the delivered list is readable by a screen reader; an announcement of "Claimed 150 coins" uses a polite live region.

**Analytics**: `season_pass_claim_tapped` (`mode` `single` or `all`), `season_pass_error_shown`.

## 3. Premium upsell sheet

**Purpose**: let the player decide to buy premium with every fact in front of them (INV-18), and complete the purchase.

**Content, in this order**:

1. Title with the season name.
2. Both tracks in full, every tier: the free reward and the premium reward side by side, with the repeat rewards of both tracks, so the player sees what is free and what premium adds. A tier with no reward on a track shows an empty cell. Nothing is hidden behind "and more".
3. A line for what the purchase gives now: "You have reached tier 7. 7 premium rewards are ready to claim as soon as you buy." (the server's `earned_count`; INV-10). At tier 0, the line says rewards unlock as tiers are reached.
4. The price, as the store's localized price string from the store bridge, on the buy control: "Buy premium for <price>". No price constant exists in the app.
5. The end date and time, absolute and in the player's locale, and the remaining time.
6. A line that premium unlocks the premium rewards only and that tiers are still earned by playing.
7. The unclaimed-rewards rule for `UNCLAIMED_AT_END`:
   - `auto_claim`: "Rewards you have not claimed when the season ends are added to your account automatically."
   - `forfeit`: "Rewards you have not claimed when the season ends are lost, including premium rewards." (INV-15)
8. The refund rule for `REFUND_POLICY`:
   - `keep_claimed`: "If the store refunds this purchase, premium rewards you have not claimed are removed. Rewards you already claimed stay."
   - `claw_back_unspent`: "If the store refunds this purchase, premium rewards you have not claimed are removed, and claimed premium rewards are taken back as far as your balance allows."
9. A statement that it is a one-time purchase for this season and does not renew.
10. For a guest account: "This purchase belongs to this guest account. Sign in to keep it if you change device or reinstall." (the premium follows the account, README section 6).

**States**:

| State | UI |
|---|---|
| `loading_offer` | contents from the server answer shown at once; price placeholder; buy disabled until the store price string loads |
| `ready` | all of the above, buy enabled |
| `sale_closed` | the server's `sale_open = false`: contents stay, buy replaced by "Premium sales for this season have closed." with the end time |
| `already_premium` | "You have premium." and the claimable count; no buy control |
| `store_unavailable` | "The store is not available right now." with Try again; contents stay |
| `purchase_pending` | the store reports the purchase as pending (for example parental approval): "Your purchase is waiting for approval. Premium unlocks when it is approved." The sheet can be closed; the next load checks the record |
| `confirming` | the store purchase succeeded and the client is verifying and activating: "Unlocking premium..." with a timeout path |
| `activation_delayed` | verification or activation did not answer in time: "Your purchase went through. Premium is taking longer than usual to unlock." with Check again; the client keeps the `store_transaction_id` and repeats the confirm call, which is idempotent |
| `success` | closes, shows "Premium unlocked. N rewards ready to claim." and scrolls the grid to the first claimable premium cell |
| `cancelled` | silent; the sheet stays |
| `error` | one sentence for the mapped error (`purchase_not_valid`, `purchase_outside_season`, `premium_already_active`); `premium_already_active` says the purchase was already unlocked and that support will refund the duplicate |
| `offline` | contents shown from the last answer; buy disabled with "Connect to buy" |

**Copy rules**: no "worth", "value", "save" or crossed-out price appears on the sheet unless `PREMIUM_VALUE_FIGURE` is on; then the only figure is the server's `value_figure`, shown with its basis ("computed from the prices the shop charges for 70 gems and 500 coins; 3 rewards are not sold separately") and never as a discount on the premium price (INV-26). The sheet never says "limited time", "last chance", "hurry" or "only N left". The remaining time is shown once, as a fact. No pre-selected add-on, no countdown that restarts, no price shown in a different currency than the store charges. The control that spends money is labelled with its price. The sheet opens only from the player's own tap on a premium entry or a premium cell; it does not open by itself after a claim or at launch. If the game's age handling (kit interview 4) treats the account as a child's, no banner offers it.

**Accessibility**: the sheet is a dialog; focus starts on its title; the reward list is a list with one item per tier naming both rewards ("Tier 4: free, 1 hint pack; premium, 1 October frame"); the rules lines are body text, not tooltips; the buy control's name includes the price; Close is always reachable.

**Analytics**: `season_pass_premium_sheet_viewed`, `season_pass_premium_purchase_started`, `season_pass_error_shown`.

## 4. Tier skip and XP boost sheets

**Purpose**: sell progress for currency honestly: the player sees the price, the effect and the balance after, and confirms.

**Skip sheet**: a stepper for the number of tiers (1 to the server's `max_count`, not past the last defined tier), the quote from `skip-quote` (reload when the stepper changes): "Skip 2 tiers: tier 5 to tier 7, 450 XP", the price "80 gems", "Your balance: 100 gems. After: 20 gems." and the confirm control "Skip 2 tiers for 80 gems". The sheet states that XP inside the current tier is kept.

**Boost sheet**: one card per catalog entry: "Double XP for 24 hours", the price, the end time it would have ("until Oct 22, 12:00"), balance after, and "Buy for 60 gems". Cards the server marks `fits_in_season = false` are disabled with "Ends after the season". While a boost is active the sheet shows it and offers no purchase.

<!-- PATTERN: price-confirm -->
<!-- PURPOSE: send the price the player saw so the server can reject a changed price, and show the fresh quote when it does -->
<!-- REFERENCE: language=typescript framework=agnostic http=fetch-builtin -->
<!-- ADAPT: `post` -> your HTTP wrapper; `showQuote` -> re-render the sheet with the quote carried in the 409 body and require a new tap on the confirm control; never retry a `price_changed` automatically -->
```typescript
async function confirmSkip(q: Quote) {
  try {
    return await post("/api/season-pass/skips", {
      season_id: q.seasonId, from_tier: q.fromTier, count: q.count, price_shown: q.priceAmount,
    });
  } catch (e) {
    if (isError(e, "price_changed") || isError(e, "tier_changed")) return showQuote(e.body.quote);
    throw e;
  }
}
```

**States** (both sheets):

| State | UI |
|---|---|
| `loading_quote` | stepper and cards disabled; skeleton price |
| `ready` | as above; confirm enabled |
| `busy` | confirm disabled with a spinner; a second tap is ignored |
| `insufficient_balance` | "You need 40 more gems." with the shortfall; a link to the currency shop owned by `billing.virtual-currency`; no confirm |
| `price_changed` | the sheet shows the new price and the line "The price changed." and waits for a new tap |
| `tier_changed` | the quote reloads for the new tier with "You moved up a tier while this sheet was open." |
| `season_ended` | "This season has ended." and the sheet offers nothing |
| `not_available` | skips off, final tier reached, boost active, or premium required (`TIER_SKIP_REQUIRES_PREMIUM`): one sentence naming the reason |
| `success` | closes, updates tier and balance from the response, toast "Skipped to tier 7." |
| `offline` | disabled with "Connect to buy" |

**Copy rules**: the confirm control states the exact price and the exact effect. The confirm step is a separate tap from opening the sheet, so a tap on a screen that is loading or waking cannot spend (the FTC's Fortnite action cites buttons that led to accidental charges, [FTC, 2022-12-19](https://www.ftc.gov/news-events/news/press-releases/2022/12/fortnite-video-game-maker-epic-games-pay-more-half-billion-dollars-over-ftc-allegations), HIGH). No default quantity larger than 1. Prices are the currency amount and the currency name from the server; where the currency is bought with money, the currency shop shows real-money prices (`billing.virtual-currency`).

**Accessibility**: the stepper is operable by keyboard and by a screen reader with a spoken value; the confirm control's name carries price and effect; the balance line is plain text.

**Analytics**: `season_pass_skip_sheet_viewed`, `season_pass_boost_sheet_viewed`, `season_pass_error_shown` (with `error_code`).

## 5. Season countdown and ending-soon banner

**Purpose**: tell the player the real remaining time and what they would lose or keep, once, calmly.

**Countdown rules**: the client keeps `clockOffset = server_now - device_now` from each answer and shows `ends_at - (device_now + clockOffset)`.

<!-- PATTERN: server-offset-countdown -->
<!-- PURPOSE: show a countdown from the server's clock and absolute end instant; the client never decides the season ended -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: call `makeClock` on every successful state response; `tick` -> your timer (once per second, or once per minute above one day); on zero call `reload()` and keep the old state on screen until the answer arrives -->
```typescript
function makeClock(serverNowIso: string, deviceNowMs: number) {
  const offsetMs = Date.parse(serverNowIso) - deviceNowMs;
  return (endsAtIso: string, nowDeviceMs: number) =>
    Math.max(0, Date.parse(endsAtIso) - (nowDeviceMs + offsetMs));
}

function onTick(remainingMs: number) {
  if (remainingMs === 0) reload();   // the server answers what happens at the boundary
}
```

- Format: days and hours above one day, hours and minutes above one hour, minutes and seconds below. Always accompanied by the absolute end date on the pass screen.
- Offline, the ticking countdown is replaced by the absolute end time: a device that has been offline cannot know the server's clock.
- A device clock change moves nothing but the display; the server decides every action (INV-1).

**Ending-soon banner**: appears at the top of the pass screen and on the home entry when `ends_at - server_now < ENDING_SOON_WINDOW_SECONDS`, for players who have a progress row.

| Content | Rule |
|---|---|
| Remaining time | the countdown above |
| Unclaimed count | "You have 3 rewards ready to claim." when the server's `claimable` count is above 0; the button opens the pass screen |
| Policy line | `auto_claim`: "Rewards you have not claimed are added automatically when the season ends." `forfeit`: "Rewards you have not claimed are lost when the season ends." (INV-15) |
| XP to the next tier | only when the next tier is reachable in a stated number of XP, as a plain number |
| Purchase prompt | none in the banner. A free player sees the same banner; the premium entry stays where it always is |

States: `visible`, `dismissed` (stored per `season_id`, returns for the next season; dismissal never hides the countdown on the pass screen), `hidden` (outside the window, no progress row, or `no_season`).

**Accessibility**: the banner is a region with a heading; it is not an alert and does not interrupt a screen reader; its dismiss control has a name.

**Analytics**: `season_pass_ending_soon_shown` (once per session), `season_pass_ending_soon_dismissed`.

## 6. Season-ended results

**Purpose**: close the season: what the player reached, what was delivered, what was not, and what comes next.

**Content**: final tier; per track, the rewards delivered and how (claimed by the player, or "added automatically at the end of the season" for `season_end_auto`); under `forfeit`, the list of rewards not claimed in time, named plainly ("You did not claim 2 rewards before the season ended."); the premium summary ("Premium: yes", or "refunded" when revoked); the next season's name and absolute start time when known.

**States**:

| State | UI |
|---|---|
| `settling` | the server is delivering the player's end-of-season rewards: "Delivering your rewards..." with the list filling in; the screen reloads until `me.settled` is true or a failure shows |
| `delivered` | the complete summary |
| `partial` | some cells stayed `pending`: "Some rewards are still on their way." with Try again (the read repairs and settles again) |
| `claim_window` | before `claim_until` under `forfeit`: claimable cells stay claimable and the header says "Claim now. This closes at <time>." |
| `no_participation` | no progress row: the screen is not offered (404 `season_not_found`) |
| `offline` / `error` | last answer or Try again, as in section 8 |

**Copy rules**: no purchase prompt on this screen. A next-season teaser is a neutral line with the start time, not a call to action. Auto-claimed rewards are listed so the player sees what arrived.

**Accessibility**: a heading hierarchy (season, track, rewards); the delivered and not-delivered lists are lists; the screen is reachable from the home entry for as long as the season is in the results window the server returns.

**Analytics**: `season_pass_results_viewed` (`final_tier`, `auto_claimed_count`, `forfeited_count`).

## 7. Locked and unavailable states

| Situation | UI |
|---|---|
| Feature switched off by the operator or no published season | the entry is hidden; a deep link lands on "No season is running." |
| Season published but not started (`upcoming`) | on the `no_season` state only: name and absolute start time; no grid |
| Account in a state the account contract blocks (for example a deleted account) | the session handling of the shell applies; this block shows nothing |
| Server configuration error (`season_config_error`) | "The season pass is unavailable right now." with Try again; no partial grid |
| Skips or boosts off | the entries are not rendered |

## 8. Offline and error handling

- The last state response may be cached with its `as_of` instant. A cached pass renders read-only. Controls that change anything (claim, skip, boost, purchase confirm) are disabled offline, with the reason "Connect to claim" or "Connect to buy". The client never queues a claim for later; a queued claim would race the season's end.
- A network failure on a write shows the retry path of its screen (section 2 and 3); the repeat is the same request, which the server treats as idempotent.
- HTTP errors map to one-line messages from this table; unknown codes show "Something went wrong. Try again."

| Server error | Message |
|---|---|
| `claim_window_closed` | "This season's claim window has closed." |
| `season_not_active` | "This season has ended." |
| `price_changed`, `tier_changed` | handled in the sheet (section 4) |
| `insufficient_balance` | handled in the sheet |
| `purchase_not_valid` | "The store has not confirmed this purchase." |
| `premium_already_active` | "Premium was already unlocked. Support will refund the duplicate purchase." |
| `rate_limited` | "Too many requests. Try again in a moment." |
| `unauthorized` | the shell's sign-in handling |

## 9. Accessibility (all screens)

- Every interactive control meets the platform's minimum touch target and has an accessible name that includes the state.
- State never relies on color alone: claimable, claimed, locked and premium each have a text or shape cue.
- Respect the system's reduce-motion setting: reward feedback becomes a static check mark; the grid scrolls to the player's tier without animation.
- Time is announced in words ("ends in 2 days 4 hours"), not only as digits.
- Sheets trap focus, return it to the opener on close, and close with the platform's back gesture.
- Text scales with the system font setting; the grid reflows and nothing is clipped.

## 10. Analytics

Client events (envelope and the server-fired events are in `README.md` section 6). Each event fires once per user action, not per render.

| Event | Screen | When |
|---|---|---|
| `season_pass_viewed` | pass track | the screen opens |
| `season_pass_claim_tapped` | pass track | a claim or claim-all request is sent |
| `season_pass_premium_sheet_viewed` | premium sheet | the sheet opens |
| `season_pass_premium_purchase_started` | premium sheet | the store sheet is requested |
| `season_pass_skip_sheet_viewed` | skip sheet | the sheet opens |
| `season_pass_boost_sheet_viewed` | boost sheet | the sheet opens |
| `season_pass_ending_soon_shown` | banner | first display in a session |
| `season_pass_ending_soon_dismissed` | banner | the player dismisses it |
| `season_pass_results_viewed` | results | the screen opens |
| `season_pass_error_shown` | any | an error message is shown (`error_code`, `screen`) |

## Anti-patterns

| DON'T | Why |
|---|---|
| Compute the tier, claimability or premium state from XP on the device | The server's answer is the only truth; local arithmetic drifts after any table or purchase change (INV-4, INV-9) |
| Decide the season has ended from the countdown | The server decides; at zero the client reloads (INV-1) |
| Queue claims offline | A queued claim races the season end; claims need the network |
| Generate a client id for a claim | Claims are idempotent by cell; repeat the same request |
| Retry `price_changed` automatically | The player must see and confirm the new price (INV-13) |
| Open the premium sheet after a claim or at launch | Purchase prompts follow the player's own tap |
| Hide premium rewards from free players, or list only the premium track in the offer | Both tracks are listed in full before purchase (INV-18) |
| Show a "worth X" or crossed-out figure that is not a price the shop charges | INV-26 |
| Use urgency copy ("last chance", "hurry") | Real remaining time is shown once as a fact |
| Show a price constant for premium | The price string comes from the store |
