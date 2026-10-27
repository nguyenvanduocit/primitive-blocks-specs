# Frontend Patterns - Daily Streak

> The client is a web-tech mobile shell; text is framework-agnostic. The client renders server values and decides nothing about time, streak arithmetic, rewards or eligibility (INV-1, INV-18). Snippets are **L3 illustrative** (`docs/SPEC_GUIDELINES.md` section 6). Event names and properties are in `README.md` section 6; analytics events carry the shared envelope.

## Component Tree

```
StreakFeature/
├── StreakProvider            # holds `view`, `clock`, `stale`; refreshes on launch, resume, and ends_at
├── DailyRewardPopup          # opens once per day_key while today is claimable
│   ├── RewardSummary         # today's lines, cycle position, requirement text
│   ├── ClaimButton
│   └── NeedsPlayHint         # play_to_claim: progress and what counts
├── CelebrationLayer          # claim result, milestone result
├── RewardCalendarScreen
│   ├── CycleGrid             # one tile per cycle day
│   ├── MilestoneList
│   ├── ProtectionPanel       # freezes held, cap, optional purchase
│   └── TimezoneRow
├── StreakBadge               # HUD chip with the streak and protection
├── AtRiskBanner              # in-app reminder
├── LossSheet                 # freeze/repair prompt and the free exit
└── StatusViews               # alreadyClaimed, waiting, offline, error
```

## Client contract

| Concern | Rule |
|---------|------|
| Data | One call, `GET /api/streak`, on launch, on resume, when the claim or loss UI is about to open, and when a countdown reaches `ends_at`. Everything shown comes from that payload and from claim, repair and freeze responses |
| Time | The client keeps `offset = server_now - device_now` and shows countdowns toward the server's `ends_at`. It never compares the device date with a `day_key` and never decides that a day has ended; when a countdown reaches zero it refreshes the view |
| Claim | Disabled while the view is stale or offline. No optimistic claim and no queued claim: the server day decides |
| Idempotency | A repeated claim is safe. `already_claimed = true` renders the already-claimed view with the original claim, not an error |
| Money | The block displays reward amounts and prices exactly as the server sent them, in the currency they are paid in, next to the player's balance when a price appears |

<!-- PATTERN: server-time-countdown -->
<!-- PURPOSE: Show time left from the server's ends_at while ignoring the device clock setting -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: wire `onZero` to the provider's refresh; re-render once per minute, or per second only inside the last minute and only visually (never announce ticks to a screen reader); format with Intl.DateTimeFormat and Intl.RelativeTimeFormat in the app locale -->

```typescript
export function createServerClock(serverNow: string, deviceNow: number = Date.now()) {
  const offset = Date.parse(serverNow) - deviceNow;       // measured at response time
  return { now: () => Date.now() + offset };
}

export function timeLeft(endsAt: string, clock: { now(): number }) {
  const ms = Date.parse(endsAt) - clock.now();
  return { ms: Math.max(0, ms), reached: ms <= 0 };       // display only; the server decides
}

// Provider: when `reached` flips to true, call refresh() and replace the whole view.
// A changed device clock changes `Date.now()` and `offset` is stale until the next response,
// so refresh on resume and on visibility change as well.
```

<!-- PATTERN: claim-result-mapping -->
<!-- PURPOSE: Map the claim answers to the screen to show without recomputing anything -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `api.post` returns { ok, body, error, network }; `show` navigates to a view of this document; keep the retry on concurrent_update (the same request is idempotent) and cap it at two repeats -->

```typescript
async function onClaim(retries = 2) {
  if (view.stale || claiming) return;
  claiming = true;
  const r = await api.post("/api/streak/claim", {});
  claiming = false;
  if (r.ok) return show(r.body.already_claimed ? "alreadyClaimed" : "celebration", r.body);
  if (r.network) return show("offline");
  switch (r.error) {
    case "repair_decision_required": return show("lossSheet", r.body.offer);
    case "requirement_not_met": return show("needsPlay", r.body);
    case "not_available_yet": return show("waiting", r.body.available_at);
    case "concurrent_update": return retries > 0 ? onClaim(retries - 1) : show("error");
    default: return show("error");
  }
}
```

---

## Screens

Copy examples are English. Rules apply to every locale. Amounts, names of items and the cycle position are always shown as the server sent them.

Copy rules for the whole feature:

- Say what the player gets and what it needs, in that order ("Claim 250 coins" and "Win one level to claim").
- Show the real end of the day in the player's local time ("Resets at 12:00 AM"). Show a countdown only toward the server's `ends_at` and never repeat it as a flashing or red element.
- State a loss as a fact with the way forward ("Your 9-day streak ended. Restore it or start a new one."). No blame, no pleading character, no "last chance", no countdown pressure beyond the true `ends_at`.
- Every option that costs something shows its price and the balance; the free option is always present and styled with equal weight.
- A price in a purchasable currency carries its indicative real-money equivalent beside it, labelled "about", through the shared `ApproxMoney` component of `billing.virtual-currency` (its INV-24; guide 15 check S1). The block does not compute a money figure itself.
- Reminders lead with the benefit: they name the reward that is waiting and the true end time. They never name a loss ("ends", "dies", "lose", "last chance") and never use a pleading or distressed character (guide 15 check S2).
- Never pre-select a paid option and never put a paid option where a free exit belongs.

### 1. Daily reward popup

Purpose: offer today's reward when the player opens the game and today is claimable or needs play.

| State | What the player sees | Behavior |
|-------|----------------------|----------|
| Claimable | Cycle day ("Day 3 of 7"), today's lines, `Claim` | Opens once per `day_key` after the first screen is ready, never over a tutorial step (guide `01-first-session.md`); dismissible; reopenable from the HUD |
| Needs play (`play_to_claim`) | Same, with "Win 1 level to claim" and a progress count when the target is above 1; `Play` | Claim stays disabled; progress comes from `play_count` and `play_target` |
| Loading | Skeleton of the lines | No layout shift when the lines arrive |
| Claiming | Button shows progress, disabled | Prevents a double tap; the server is idempotent anyway |
| Repair decision | Opens the loss sheet (screen 5) | The claim is held until the player decides |
| Waiting | "Your next reward is at {time}" | When the zone moved behind the last credited day; no loss |
| Offline, error | Screens 7 and 8 | |

Accessibility: modal dialog with a label that includes the day and the reward; focus moves to the dialog and returns to the invoking element on close; `Claim` is a native button; the lines are a list with the amount and the name in text.

Events: `daily_reward_popup_shown` (`day_key`, `cycle_day`, `streak`, `status`, `requirement`), then `daily_reward_claimed` from the server, `daily_reward_claim_failed` (`reason`) on failure.

### 2. Reward calendar screen

Purpose: show the cycle, the milestones, freezes and the time zone in one place; the passive entry point to repair after the proactive sheet was shown.

| State | What the player sees | Behavior |
|-------|----------------------|----------|
| Normal | A tile per cycle day with the lines; tiles are `claimed`, `today` or `upcoming`; a milestone list with reached marks; freezes held out of the cap | Tiles are text-labelled, not color-only |
| Protection panel | Freezes held out of the cap; how freezes are earned ("Day 7 of each cycle"); when a freeze is for sale, its price with the `ApproxMoney` figure and the balance | A purchase asks for confirmation with the price and never auto-selects; a freeze held never expires |
| Frozen day | A tile or marker "held by a freeze" for covered days when the history is shown | Uses `daily_claims` kinds `frozen`, `repaired`, `excused` |
| Repair open | A row "Restore your 9-day streak" with the methods and the end time | Opens the loss sheet; shown even after `LOSS_PROMPT_CAP` is reached, because it is passive |
| Loading, offline, error | Skeleton; last view marked "as of {time}"; error view with retry | Calendar content may be cached; claim and purchase controls are disabled |

Copy: "Day 7: 500 coins, 20 gems, 1 streak freeze". Milestones: "At a 30-day streak: 100 gems and a gold avatar frame". A capped freeze line reads "Streak freeze (storage full, 0 added)".

Accessibility: the grid is a list; each item reads "Day 3, claimed, 200 coins"; the current day has `aria-current`; color is never the only carrier of state ([WCAG 2.2, 1.4.1 Use of Color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html), Level A, HIGH).

Events: `streak_calendar_viewed` (C: `cycle_day`, `streak`).

### 3. Streak badge (HUD)

Purpose: show the current streak and whether it is protected, everywhere the HUD appears.

| State | What the player sees | Behavior |
|-------|----------------------|----------|
| No streak | Hidden, or "Start a streak" on the calendar only | Never shows a zero as a failure |
| Alive, claimed today | Count with a check mark | Tap opens the calendar |
| Alive, claim pending | Count; no animation, no color alarm | Tap opens the popup |
| Protected | Count with a freeze marker and the number held | Text shows "1 freeze" |
| Decayed or reset | The new count; the explanation lives in the notice | One-time notice (below) |

Accessibility: one control with a text alternative, "9-day streak, claimed today, 1 freeze held". Count changes are announced politely once, not on every refresh.

The one-time notice after settlement (`unseen_notice`) is a toast or a line in the popup: `freeze_used` "A streak freeze kept your streak. 1 left."; `streak_lost` "Your 9-day streak ended."; `streak_decayed` "Your streak went from 10 to 6."; `excused` "We could not offer the daily reward during an outage, so your streak is safe." Acknowledge it with `POST /api/streak/ack { kind: "notice" }`.

### 4. Streak-at-risk reminder

Purpose: tell a player with a streak worth keeping that the day is ending. Delivery outside the app belongs to `messaging.push-reengagement`, reached only through the `streak_at_risk` event (`README.md` section 6); this screen is the in-app counterpart.

| State | What the player sees | Behavior |
|-------|----------------------|----------|
| Shown | Banner: "Today's reward is ready: 500 coins and 20 gems. Claim it before 12:00 AM." and `Open` | Shown only when the view says `streak.at_risk` and the player has not dismissed it for that `day_key` |
| Dismissed | Nothing | `dismissed_at_risk_day_key` is stored on the device; the banner does not return that day |
| Protected | Nothing, or a quiet line "A streak freeze protects you today" | No reminder while a freeze covers a missed day (`AT_RISK_WHEN_PROTECTED = false`) |

Copy: lead with the reward waiting today (the lines of the calendar day marked `today` in the view) and state the real end time and the action; the streak count may appear as a neutral fact ("Day 7 of 7"). No loss wording. Do not repeat the banner on every screen or add a second banner for the same `day_key`. The push copy follows the same rule with the variables of the `streak_at_risk` hand-off (`cycle_day`, `reward_code`, `reward_amount`).

Accessibility: a polite live region, not a modal, so it does not steal focus ([WCAG 2.2, 4.1.3 Status Messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html), Level AA, HIGH).

Events: `streak_at_risk` (S, hand-off, `armed` and `resolved`); `streak_at_risk_banner_shown`, `streak_at_risk_banner_dismissed` (C: `day_key`, `streak`).

### 5. Freeze and repair prompt (loss sheet)

Purpose: tell the player the streak ended or decayed and let them choose, with a free exit that is always available (INV-15).

| State | What the player sees | Behavior |
|-------|----------------------|----------|
| Offer open | Title "Your 9-day streak ended". Three options of equal weight: `Win 3 levels to restore it` (free), `Restore it for 80 coins, about {approx_money}` (only when a price is configured; shows the balance and the `ApproxMoney` figure), `Start a new streak` (free) | The sheet opens by itself at most `LOSS_PROMPT_CAP` times per offer (`loss_prompt.show`); the client acknowledges each showing with `POST /api/streak/ack { kind: "loss_prompt" }` |
| Play progress | "2 of 3 levels won today" | Restore becomes available when `play_count >= play_target`; the player keeps playing |
| Insufficient balance | The paid option shows "Not enough coins (have 40, need 80)" and the free options remain | The sheet offers no purchase of currency from here |
| Pending | "Restoring..." | A 202 pending purchase is shown as in progress and resolved by the next view; never charge twice (`client_request_id` is reused on retry) |
| Success | "Your 9-day streak is back" then the claim popup | The view is refreshed from the response |
| Window ended | The sheet does not open; the calendar row disappears | `repair_not_available` with `window_closed` |
| Freezes held but short | "You have 1 streak freeze, and 2 days were missed. A freeze covers whole gaps, so it was kept." | Explains why a held freeze was not used |

Copy rules: the price of the paid option is stated as currency plus the indicative real-money figure; the free options come first or share the first row; no countdown pressure beyond the true end time ("Available until 12:00 AM on Wed"); no "everyone restores"; no discount framing.

Accessibility: modal with focus trap and a first focus on the title; each option is a button whose label includes the cost or "free"; Escape or back chooses nothing and leaves the offer open until it expires; the prices and balance are text.

Events: `streak_repair_prompt_shown` (C: `streak_before`, `missed_days`, `free_method_offered`, `paid_method_offered`, `prompts_shown`), `streak_repair_accepted`, `streak_repair_declined`, `streak_freeze_purchased` (S).

### 6. Already-claimed view

Purpose: confirm today is done, on this device or any other.

| State | What the player sees | Behavior |
|-------|----------------------|----------|
| Claimed | "Today's reward is claimed." The lines received, tomorrow's lines, the time the next day starts | From `already_claimed = true` or `today.status = claimed`; no error styling |
| Delivery pending | "Your reward is on its way" with the lines | `grant_status = pending`; the view polls the view endpoint until `granted` |
| Delivery failed | "We could not add this reward. Contact support with this reference: {claim id}" | `grant_status = failed` |

Accessibility: the confirmation is a status message in a live region; the claim control is absent, not disabled-and-empty.

### 7. Offline

| State | What the player sees | Behavior |
|-------|----------------------|----------|
| No connection | The last view, marked "as of {time}"; claim, repair and purchase disabled with "Connect to claim" | No local claim; countdowns use the last `offset`; the view refreshes on reconnect and on resume |

The game itself keeps working; only claiming waits. Accessibility: the offline status is a live-region message; disabled controls state why.

### 8. Error

| State | What the player sees | Behavior |
|-------|----------------------|----------|
| Request failed (5xx, `concurrent_update` after retries) | "Something went wrong. Your streak is safe. Try again." and `Try again` | The same request is repeated; the server is idempotent |
| Validation (`unexpected_field`, `invalid_timezone`) | Specific line for the time-zone row; otherwise generic | Log `streak` errors without the request body |

### 9. Celebration

Purpose: confirm a claim and mark milestones.

| State | What the player sees | Behavior |
|-------|----------------------|----------|
| Claim | The lines received, the new streak, the cycle day, `Done` | Plays once per claim, skippable; the numbers come from the response |
| Milestone | The milestone lines beside the day's lines ("30-day streak: 100 gems and a gold avatar frame") | Shown only for ids in `milestone_ids` |
| Freeze earned | "You earned a streak freeze (1 of 2)" | From a `freeze` line with `amount > 0`; with `capped = true` "Streak freeze storage is full" |
| Reduced motion | A static card | Respect the platform setting ([MDN: prefers-reduced-motion](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-motion), HIGH) |

Accessibility: the result is announced once in a live region; no flashing content; the animation never blocks the `Done` control.

Events: `daily_reward_claimed` (S) and `streak_extended` (S); `streak_freeze_earned` (S).

### 10. Time-zone row

Purpose: let the player change the zone that decides their day, and explain what a change does.

| State | What the player sees | Behavior |
|-------|----------------------|----------|
| Same | "Your day resets at 12:00 AM in Europe/Berlin" | Zone shown in plain words with its identifier |
| Device differs | "Your device is in Asia/Tokyo. Switch your daily reset?" `Switch` / `Keep` | A suggestion, never an automatic change; a change is the player's choice |
| Pending | "Switches at {time}, when today ends. Today stays yours." | From `pending_timezone` and `timezone_effective_at` |
| Rate limited | "You can change this again on {date}." | From `next_change_at` |

Events: `streak_timezone_changed` and `streak_timezone_change_rejected` (S).

---

## Client messages

| Case | When | Message (EN) |
|------|------|--------------|
| `requirement_not_met` | Claim before the play target | "Win {n} level(s) to claim today's reward." |
| `not_available_yet` | Zone behind the last credited day | "Your next reward is at {time}. Your streak is safe." |
| `insufficient_balance` | Paid option short | "Not enough {currency} (have {x}, need {y})." |
| `freeze_cap_reached` | Purchase at the cap | "You already hold the most streak freezes ({n})." |
| `timezone_rate_limited` | Third change in the window | "You can change this again on {date}." |
| `network` | Request did not leave the device | "No connection. Connect to claim." |
| other | Anything else | "Something went wrong. Your streak is safe. Try again." |

## Anti-patterns

**DON'T** compare the device date with a `day_key`, or decide locally that a day ended. A changed device clock must change nothing the player is owed or loses.

**DON'T** claim optimistically or queue a claim offline. The server's day is the only day.

**DON'T** hide the free exit, put it behind a purchase, or make the paid option larger, brighter or pre-selected.

**DON'T** open the loss sheet more than `loss_prompt.show` allows, repeat the at-risk banner, or add a reminder when a freeze protects the day.

**DON'T** write a reminder that names a loss, or ship a push variable that does; name the reward waiting.

**DON'T** show a currency price for a freeze or a repair without its `ApproxMoney` equivalent, or remove, expire or hide a freeze, item or currency because a streak ended.

**DON'T** render a streak of 0 as a failure, or show a red countdown for a day that has hours left.

**DON'T** log reward lines, balances or the time-zone identifier in client analytics beyond the properties listed in `README.md` section 6.
