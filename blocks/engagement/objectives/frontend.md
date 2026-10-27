# Frontend Patterns — Objectives, Missions and Achievements

> Snippets below are **L3 illustrative** (see `docs/SPEC_GUIDELINES.md` section 6). They are TypeScript for clarity and show state logic without a UI framework; map them through each `ADAPT` list. The client is a web app in a native shell. Every rule about progress, completion, windows and rewards lives on the server (`backend.md`); the client renders what the server returned and never decides that an objective completed, that a window ended, or what a reward is (INV-1). Copy keys are i18n keys; the English text shown is the default wording the rules below constrain.

## Component Tree

```
Shell
├── NextGoalChip              # Home screen: one chip from `next_goal`; hidden when the player turned it off
├── ObjectiveToast            # "New goal" and "Goal done" toasts, coalesced per response
├── CompletionCelebration     # One short, dismissible celebration per completed instance
├── RerollSheet               # Confirmation sheet for one reroll
└── ObjectivesScreen
    ├── ScopeTabs             # Starter (until done) | Today | This week | Season | Achievements
    ├── BoardHeader           # Countdown, points ladder, reroll bank, unclaimed-reward rule, "Done for today"
    │   ├── LadderBar         # Rungs at their thresholds with their rewards
    │   └── ClaimAllButton    # Shown when claimable_count > 1
    ├── StarterChecklist      # Ordered steps, then the three goals
    ├── ObjectiveRow[]        # Title, true count, bar, reward, claim, reroll, chain step
    ├── AchievementShelf      # Tiers by chain; earned secret achievements
    ├── ExpiredSection        # Collapsed: rows that ended unfinished, with their final count
    └── EmptyState | OfflineBanner | ErrorBanner
```

Suggested test hooks: `objectives-tab-<scope>`, `objective-row-<objective_id>`, `objective-progress-<objective_id>`, `objective-claim-<objective_id>`, `objectives-claim-all`, `objective-reroll-<objective_id>`, `reroll-sheet-confirm`, `board-done`, `board-countdown`, `next-goal-chip`, `starter-checklist`, `objectives-offline`.

## Progress display rules (apply to every screen)

These rules apply the goal-gradient effect without inventing progress. The effect is real in loyalty-card studies and untested on game goals, so the rules limit how it may be used (README Origin).

1. **True count, always.** Every row shows `progress of target` and the remaining amount (`remaining` from the server) and the exact reward lines. Never a bare bar, never a percentage alone.
2. **The bar is the count.** Fill equals `progress / target`. Zero is empty: no minimum sliver, no easing that overshoots, no pre-filled bar. An animation may take time but ends at the true value.
3. **A head start has a reason and a number.** A `lifetime_total` objective or a carry-in starts above zero because of real work; the row says why ("Counts the 3 levels you already cleared", "5 carried over from last week") and the number is the true count. Nothing is endowed that the player did not earn (INV-10).
4. **Pending is not done.** Progress from events still in the device queue may show as "+2 syncing" next to the server count, visually distinct. Completion, the celebration and the claim button appear only when the server says `completed`. If the server counts less than the device expected (a cap), the row corrects downward and says nothing alarming: "Counted: 1 of 3".
5. **The next reward is visible.** A row shows its reward; a ladder shows the next rung's threshold and reward ("40 points: 25 coins; you have 30"); the chain shows the next step's title (a `preview` instance).
6. **Nearness only when true.** Words such as "nearly there" appear only when `remaining / target` is at or below `NEAR_COMPLETE_COPY_PERCENT`.
7. **Time is the server's.** Countdowns come from `ends_at` and the offset between `server_now` and the device clock at the last answer (snippet "remaining-time"). They are plain text in one style at every remaining time: no blinking, shaking, red escalation or "last chance" wording. At zero the row says "Ending" and refetches; the client does not mark anything expired. Offline, the row shows the absolute local end time ("Ends 7:00 PM") and no ticking value.
8. **Order is easy first.** Rows follow the server order (tier ascending). The client does not reorder by urgency or reward size.
9. **Say what resets.** A board footer states, from `rules.unclaimed_at_reset`, whether finished goals wait to be claimed ("Finished goals stay here until you claim them") or are claimed for the player when the board ends ("Finished goals are claimed for you when the board ends"), and what happens to unfinished progress ("Unfinished progress does not carry over" or "Progress above 80% carries over" with the configured share).

<!-- PATTERN: progress-view -->
<!-- PURPOSE: Turn a server item into the exact numbers and keys a row may render; no invented fill or wording -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `Item` is one element of the list response; keys feed the i18n layer ("{progress} of {target}", "{remaining} to go", "{carried_in} carried over"); bind `fraction` to the bar's value and to its accessible value; NEAR_COMPLETE_COPY_PERCENT comes from the shared configuration, not a literal -->
```typescript
type Item = { progress: number; target: number; remaining: number; carried_in: number };

export function progressView(i: Item, nearPercent: number) {
  return {
    fraction: i.target > 0 ? i.progress / i.target : 0,      // zero is empty, never a minimum sliver
    countKey: "objective.count",
    remainingKey: "objective.remaining",
    nearly: i.remaining > 0 && i.remaining / i.target <= nearPercent / 100,
    carriedKey: i.carried_in > 0 ? "objective.carried" : null,
  };
}
```

<!-- PATTERN: remaining-time -->
<!-- PURPOSE: Show a countdown from the server's absolute ends_at without trusting the device clock or deciding that time elapsed -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: store serverNowIso and the device time at the moment the response arrived; recompute on a coarse tick (once a minute is enough for a goal list); when the result is "ending" refetch the list; offline show the absolute end time with Intl.DateTimeFormat -->
```typescript
export function remainingMs(
  endsAtIso: string, serverNowIso: string, deviceNowAtFetch: number, deviceNow: number,
): number | "ending" {
  const offset = Date.parse(serverNowIso) - deviceNowAtFetch;     // server clock minus device clock at the last answer
  const left = Date.parse(endsAtIso) - (deviceNow + offset);
  return left > 0 ? left : "ending";                              // the client never decides that the window ended
}
```

## Screens

### 1. Objectives screen (list by scope)

**Purpose.** One place to see every goal at every range, claim finished ones, and replace one.

**Data.** `GET /api/objectives` on open (reuse a list younger than `LIST_STALE_SECONDS`), after every event flush that changed something, after a claim or reroll, and on foreground.

**Layout rules.**
- Tabs: `Starter` (until every starter instance is claimed), `Today` (`daily`), `This week` (`weekly`), `Season` (`seasonal`), `Achievements` (`lifetime`). The `session` goals appear as a short block at the top of the screen that is open while a session is live. A tab with no items is not shown.
- Each tab is ordered by the server. A claimable row sorts to no special place; claiming is a button on the row, not a reordering.
- `ObjectiveRow`: title (from `title_key`), count line, bar, reward chips, tier-neutral styling (tier is not shown as a rarity color), a chip "Counts any mode" when `counts_from_normal_play`, the chain step ("Step 2 of 3") when `chain` is set, and the actions: **Claim** (state `completed`), **Replace** (state `active`, `rerollable`).
- `locked` rows (`preview` visibility) are greyed with "Complete {prerequisite title} first"; they show the reward and target.
- `BoardHeader` (daily and weekly tabs): countdown (rule 7), the ladder (screen 3), the reroll bank ("Replacements: 1 of 2"), and the reset footer (rule 9).

**States.**

| State | UI |
|---|---|
| Loading, no cache | Skeleton rows; tabs disabled; no counts shown |
| Loading, cached list | Cached rows with a "Last updated {time}" line; refresh in the background |
| Ready | Rows as above |
| `completed` row | Row marked "Done", a **Claim** button with the reward on it, no countdown (a finished goal has no deadline) |
| `claimed` row | "Claimed" with the grants; stays visible until the next refresh of its window |
| Claim in flight | The tapped button shows progress and is disabled; other rows stay usable; a second tap is ignored |
| Claim `already_claimed` | Treated as success; the row shows "Claimed" |
| Claim `503 ledger_unavailable` | Inline "Couldn't reach the reward service. Try again." The row stays `completed`; nothing is lost |
| Claim `409 ledger_rejected` with reason `balance_limit_exceeded` | Inline "Your {currency} is full. Spend some, then claim again." The row stays `completed` |
| Claim `409 ledger_rejected` with another reason | Inline "This reward can't be paid right now. Try again later." The row stays `completed`; the failure is reported to the operator |
| Claim `not_completed` or `not_found` | Refetch the list; no error toast (the list was stale) |
| Empty (no goals yet) | See screen 9 |
| Offline | See screen 11 |

**Copy rules.** The reward is stated as an exact amount ("+40 coins") before the player starts and on the Claim button. No "mystery reward", no random bonus wording. Titles state the action and the number ("Win 3 matches"). The words "free" and "limited" are not used for goals; a goal that does not expire does not carry an expiry label.

**Accessibility.** Each bar is a `progressbar` with `aria-valuemin 0`, `aria-valuemax target`, `aria-valuenow progress` and an accessible name that includes the title and "3 of 10, 7 to go". Claim and Replace are real buttons with names that include the goal's title ("Claim reward: Win 3 matches"). State is not conveyed by color alone (text "Done", "Claimed", "Locked"). The countdown is not an `aria-live` region; it is read on focus. Touch targets meet the platform minimum (extrapolated: this repo does not cite one).

**Events.** `objectives_viewed` on open and on tab change; `objective_claim_failed` on a failed claim.

### 2. Claim and claim-all

**Purpose.** Pay finished goals, one or many.

**Rules.** `Claim all` appears when `claimable_count > 1` and acts on the visible tab (or all, from the home chip's overflow). It sends `claim-all`; the response lists a result per instance, so a partial failure shows per-row errors and the others show "Claimed". More than `CLAIM_ALL_MAX` completed instances leave a remainder: after the response, the button shows the remaining count ("12 more to claim") and stays enabled.

**States.** Idle, in flight (button disabled, rows keep their own state), done (rows "Claimed", a single summary toast "Claimed 4 rewards: +190 coins, 1 booster"), partial (summary plus the failed rows left as `completed`), offline (button disabled with the reason).

**Copy rules.** The summary lists the real grants. No claim animation that delays the balance update; the balance shown elsewhere updates from the ledger answer.

**Accessibility.** The summary toast is `role="status"`. The button name includes the count.

**Events.** `objective_claim_failed` per failed row; the server fires `objective_claimed` per success.

### 3. Points ladder and "Done for today"

**Purpose.** Show the second reward layer (board points) and the end state of a board.

**Rules.**
- The ladder shows each rung at its threshold with its reward and the player's true points ("30 of 60 points"). The sum of the day's task points is never shown as a goal to reach; the top rung is below it, so a player can stop early (INV-28). The screen does not imply that every task must be finished.
- The whole-board bonus appears as its own row ("Finish every goal on today's board: +60 coins").
- When `board.done` is true the board header shows **Done for today** with the next board's start (the window's `ends_at` in local time), the claim buttons of finished rows, and nothing else asking for play.
- A rerolled-away goal is not shown on the board and does not hold it open.

**States.** Ladder in progress, rung reached (the rung row is claimable like any goal), board done, board done with unclaimed rewards (the Claim all button stays), board ended.

**Copy rules.** "Done for today" is a statement, not an invitation: no "keep going", no "come back tomorrow for more!" pressure. The next board time is informational. Points are called "board points" and explained once in a tooltip: "Finished goals add points. Points unlock rewards on the board."

**Accessibility.** The ladder is a list of rungs with `aria-label` "25 coins at 40 points, reached" or "not reached"; the "Done for today" label is a heading.

**Events.** `objective_board_done` (server).

### 4. New-goal toast

**Purpose.** Tell the player when goals appear without interrupting play.

**Rules.** One toast per list response that created instances the player has not seen (`objective_assigned` for the account since the last list): "New goals: 3 for today". A newly unlocked chain step reads "Next step unlocked: {title}". A toast never names a deadline, never repeats within one session for the same window, and never appears during a level or round: the host game queues it until a calm moment.

**States.** Queued, shown, dismissed (swipe or timeout), suppressed (the player is on the Objectives screen).

**Accessibility.** `role="status"`, no focus steal, readable by a screen reader without blocking the game.

### 5. Completion celebration

**Purpose.** Mark that a goal was earned, once.

**Rules.** Shown when a response lists an instance in `completed` that is not in `celebrated_ids`. A short, non-blocking banner with the goal's title and the reward ("Goal done: Win 3 matches. +40 coins ready"), a **Claim** button and a dismiss. It never claims for the player, never auto-opens a modal during play, and shows at most one per response (extra completions collapse into "3 goals done"). It respects the reduced-motion setting and the game's sound setting.

**States.** Shown, claimed from the banner (becomes the claim flow of screen 2), dismissed (the row stays claimable), suppressed (celebration already shown on this device, or the Objectives screen is open).

**Copy rules.** The reward is "ready", not "waiting" or "expiring". No countdown. A completed goal has no deadline, so no urgency wording is allowed.

**Accessibility.** `role="status"`; dismiss is reachable by keyboard and by the platform back gesture; animation can be turned off.

**Events.** None client-side beyond the claim; the server fires `objective_completed`.

### 6. Next-goal chip (home screen)

**Purpose.** One quiet pointer to the goal closest to done.

**Rules.** Renders the item named by `next_goal` ("Win 3 matches · 2 to go"), with its reward on tap. It is a chip, not a banner: no badge count, no pulsing, no countdown. Tapping opens the Objectives screen on that goal. It is hidden when `next_goal` is null, and the player can switch it off in settings (`show_chip`, stored on the device); a goal list is optional, and the setting is part of the screen.

**States.** Hidden (no goal, or turned off), shown, stale (cached list: shows the cached goal without a count that could be wrong; "Open to refresh"), offline (shows the cached goal).

**Accessibility.** A button with the name "Next goal: Win 3 matches, 2 to go".

**Events.** `objective_chip_tapped`; `objective_chip_setting_changed` when the setting changes.

### 7. Starter checklist (first session)

**Purpose.** Close the "now what?" gap: a guided first session, then three goals at three ranges (`01-first-session.md` rule 4).

**Rules.**
- A card on the home screen during the first session and a full screen behind it. The steps come from the `starter` instances in order: done steps checked with their reward, the current step highlighted with its true count and remaining amount, the next steps as `preview` rows with their reward.
- A head start is shown with its reason, as in rule 3 ("Counts the level you already cleared: 1 of 3").
- When the last step completes, the three goals (`horizon` short, medium, long) appear under the labels "In this session", "In the next few days" and "Long-term", each with its target, reward and true count.
- The card shows no countdown and no expiry: starter goals do not end. It disappears from the home screen when every starter instance is claimed, and the full screen then shows only the goals still open.
- Nothing on the checklist asks for a rating, an account, a notification permission or a purchase. Those asks follow their own triggers (`01-first-session.md` rule 3).

**States.** Loading, step active, step just completed (celebration of screen 5, then the next step highlights), goals revealed, all claimed (card removed), offline (cached checklist; claim disabled with the reason).

**Copy rules.** Step titles name one action ("Finish your first level"). Rewards are exact. The goal labels are ranges of time in words, never a countdown.

**Accessibility.** The checklist is an ordered list; each item announces "Step 2 of 3, current, 20 of 50 coins spent". Checkmarks have text alternatives.

**Events.** `starter_checklist_viewed` (steps_done, steps_total); the server fires `starter_objectives_completed`.

### 8. Reroll sheet

**Purpose.** Let the player replace one active goal, knowing what it costs.

**Rules.** Opened from **Replace** on an `active`, `rerollable` row. The sheet shows: the goal being replaced with its true count, "You will lose this goal's progress (3 of 10)" when progress is above zero, the bank ("You have 1 replacement. You earn 1 more each day, up to 2."), and under `REROLL_TIER_POLICY = any_tier` the sentence "The new goal can pay more or less." (under `same_tier` "The new goal has the same reward size."). The buttons are **Replace goal** and **Keep goal** (the default focus). There is no price, no ad, no "get more replacements" offer, no purchase path. After success the new goal appears with a "New" marker and the bank shows the new balance.

**States.**

| State | UI |
|---|---|
| Ready | Details above; Replace enabled |
| Bank empty | Replace disabled; "No replacements left. You earn another {when}." where {when} is the next window start from `ends_at` |
| In flight | Replace disabled, progress shown; a second tap is ignored |
| `no_replacement_available` | "No other goal fits right now. You keep your replacement." |
| `no_reroll_available` or `not_active` | Close the sheet, refetch the list |
| Success | Sheet closes, the old row shows "Replaced", the new row is highlighted |
| Offline | Replace disabled with "Replacing needs a connection" |

**Accessibility.** Focus moves into the sheet and returns to the row on close; Escape and the back gesture close it; the destructive effect (lost progress) is in text, not only in color.

**Events.** `objective_reroll_sheet_viewed`; the server fires `objective_rerolled`.

### 9. Empty state

**Purpose.** Say clearly when there is nothing to do.

| Situation | UI |
|---|---|
| Board done | "Done for today" (screen 3) |
| All starter goals claimed and no other scope has items | "No goals right now. New ones arrive {when}." where {when} is the next window start |
| Achievements tab, everything earned | "Every achievement earned." |
| Achievements tab, nothing earned yet | The visible achievements with true counts; no mention of hidden ones |
| No goals because the plan is empty or retired | "No goals right now." with no countdown |

**Copy rules.** The next-board time is stated plainly. No incentive copy, no "you're missing out". Hidden achievements are never hinted at ("3 secret achievements" would leak their existence and is not shown); the shelf may say "Some achievements stay secret until you earn them" once, in the tab's footer, regardless of whether any exist.

### 10. Expired state

**Purpose.** Show what ended unfinished without punishing the player.

**Rules.** A collapsed "Ended" section lists expired rows of the previous window with their final count ("Win 3 matches: 2 of 3"), and a plain line from the instance's policy: "Progress does not carry over" or, for a `carry_over` goal that carried, "{n} carried to this week". Completed rows of an ended window stay in the main list and remain claimable (they are not "expired"). There is no revive, extend or "buy back" action and no wording of loss ("you lost", "missed out"). A missed day shows nothing at all: windows the player never opened produce no rows.

**States.** Collapsed (default), expanded, none (no expired rows), cached.

**Accessibility.** The section is a disclosure button with the row count in its name.

### 11. Offline and error

**Purpose.** Keep the screens honest when the server cannot be reached.

| Situation | UI |
|---|---|
| Offline on open | Cached list, banner "You're offline. Showing goals from {time}.", Claim, Claim all and Replace disabled with the reason, countdowns replaced by absolute end times |
| Offline while playing | Events queue on the device (cap `EVENT_QUEUE_MAX`); the row may show "+N syncing"; nothing completes until the server answers |
| Back online | Send the energy block's attempt calls (confirm, finish) first, then flush the queue in batches of `EVENT_BATCH_MAX`, refetch, then show any celebrations once. Events of play metrics carry the `attempt_id` of the attempt that produced them |
| Queue full | The oldest `client_reported` events are dropped first; `objective_events_dropped` fires; nothing is shown to the player |
| Event rejected `attempt_not_proven` or `attempt_required` | The result is final: the event is dropped and not retried, and the player sees nothing; the cause is an attempt that was cancelled, abandoned or never confirmed |
| `429 rate_limited` | Keep the queue, retry after the next foreground |
| `422 invalid_request` on a batch | Drop that batch (it cannot succeed), keep the rest, report an `error` event |
| `401 unauthenticated` | Hand to the app's sign-in flow; keep the queue |
| List fetch failed, no cache | "Couldn't load goals." with Try again; the rest of the app is unaffected |
| List fetch failed, cache present | Keep the cache and its banner; no blocking error |

**Copy rules.** Errors say what happened and what is safe: "Your progress is saved on this device and will count when you're online." They never claim that progress is lost unless it is.

**Accessibility.** Banners use `role="status"` (offline) or `role="alert"` (a failed claim); retry buttons are focusable.

### 12. Achievements shelf

**Purpose.** Show lifetime marks, including tiers and secrets.

**Rules.** Chains render as one card with tiers ("Levels 10 / 50 / 250"), the current tier with its true lifetime count (a veteran sees "60 of 250", not zero), and earned tiers checked. A `preview` tier shows the next one greyed. A `hidden_until_earned` achievement is absent until the server returns it as `completed`; once returned, it shows its full title, description and reward with a "Secret" marker and is claimable like any goal. The client never infers hidden ones from gaps in a list, and no counter of total achievements includes them. Achievements are never described as expiring, resetting or time-limited.

**States.** As rows; plus "earned" (claimed) and "earned, reward ready" (completed).

### 13. Settings entry

**Purpose.** Let the player turn the home chip off.

**Rules.** A single switch "Show next goal on the home screen" in the app's settings, default on, with a text state ("On" or "Off"); the choice is stored on the device (`show_chip`). It affects only the chip; the Objectives screen stays available. Fires `objective_chip_setting_changed`.

## Event queue

<!-- PATTERN: event-queue -->
<!-- PURPOSE: Queue client events with fixed ids so retries and replays count once, and survive offline play -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: pass the attempt id of the energy block's attempt for every play metric (`opts.attemptId`); persist the queue in the shell's device storage (Capacitor Preferences or an equivalent); crypto.randomUUID is available in current web views, otherwise use a uuid library; `dropOldestClientReported` removes the oldest events of client_reported metrics first and fires objective_events_dropped; call flush on foreground, on reconnect and after the flush delay -->
```typescript
type Q = { event_id: string; metric: string; amount: number; occurred_at: string; ref?: string; attempt_id?: string };
let queue: Q[] = loadQueue();

export function report(metric: string, amount: number, opts: { ref?: string; attemptId?: string } = {}) {
  queue.push({ event_id: crypto.randomUUID(), metric, amount, occurred_at: new Date().toISOString(), ref: opts.ref, attempt_id: opts.attemptId });
  if (queue.length > EVENT_QUEUE_MAX) queue = dropOldestClientReported(queue);
  saveQueue(queue);
  scheduleFlush(EVENT_FLUSH_DELAY_MS);
}

export async function flush() {
  const batch = queue.slice(0, EVENT_BATCH_MAX);          // the same ids on every retry
  if (batch.length === 0) return;
  const r = await api.post("/api/objectives/events", { events: batch });
  if (!r.ok && r.status !== 422) return;                   // keep the queue and retry later
  const sent = new Set(batch.map((e) => e.event_id));
  queue = queue.filter((e) => !sent.has(e.event_id));      // results, even rejected ones, are final
  saveQueue(queue);
  if (r.ok) applyResponse(r.body);                         // replace items, board, next_goal, show celebrations
}
```

## Analytics events (client-written)

Properties are in addition to the shared envelope. Server-written events are in `backend.md`.

| Event | Fires when | Properties |
|-------|-----------|------------|
| `objectives_viewed` | The Objectives screen opens or the tab changes | `scope`, `items_count`, `claimable_count`, `board_done` |
| `starter_checklist_viewed` | The starter card or screen is shown | `steps_done`, `steps_total` |
| `objective_chip_tapped` | The home chip is tapped | `objective_id` |
| `objective_chip_setting_changed` | The player switches the chip | `value` |
| `objective_reroll_sheet_viewed` | The reroll sheet opens | `objective_id`, `progress`, `bank_balance` |
| `objective_claim_failed` | A claim request fails | `objective_id`, `reason` |
| `objective_events_dropped` | The device queue overflowed | `count` |

## Anti-patterns

| DON'T | Why |
|---|---|
| Show a bar that starts above the real count, or a minimum sliver at zero | It fakes progress and breaks INV-10 |
| Add a countdown style that escalates (red, shake, "last chance") | Fake urgency (ethical floor 3) |
| Celebrate, enable Claim or mark done from a local count | Completion is the server's (INV-1) |
| Auto-claim from the celebration | Claiming is the player's action unless the server's configured rule says otherwise, and the screen states that rule |
| Offer a paid replace, revive or "extra goals" | Pay-to-skip (INV-16, INV-23) |
| Show a count of secret achievements | It leaks hidden ones (INV-20) |
| Reorder rows by urgency or reward size | The server order is easy first (README "Ordering rule") |
| Ask for a rating or review as a goal | Store policy (README ethical floor 2) |
| Write "you lost" for a missed day or an ended window | A missed day costs nothing (INV-15) |
