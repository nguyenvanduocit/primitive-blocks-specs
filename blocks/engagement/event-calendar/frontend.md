# Frontend: Event Calendar

> The client is a web-tech app in a native shell; the text below is framework-agnostic. Snippets are L3 illustrative TypeScript with the four markers per `docs/SPEC_GUIDELINES.md` section 6. Behavior (WHAT) is in the prose. API shapes, error codes and the state rule are in `backend.md` and `README.md`; the client mirrors only the parts it needs.

## Component tree

```
App shell
 ├── HomeSurface
 │     ├── EventBanner            one slot: first live event with a banner asset
 │     └── EventBadge             count of claimable rewards; "new" dot
 ├── EventHub                     live and ending-soon, upcoming, recent, unavailable
 │     ├── EventCard              one per renderable event
 │     ├── UpcomingTeaserRow
 │     ├── UnavailableRow         update required, or paused
 │     └── SnapshotNotice         stale, offline, error
 ├── EventDetail                  timer, rules, reward list, progress, Join or CTA
 │     └── EventRenderer          per type@schema_version, from the renderer registry
 ├── ResultsSheet                 final progress, rewards, Claim, sweep note
 └── PreviewBanner                QA builds only
```

| Unit | Responsibility | Interface |
|---|---|---|
| `eventStore` | Owns the snapshot, status, clock sample, refetch timer, per-account epoch | `refresh(force)`, readable `events`, `upcoming`, `recent`, `unavailable`, `status`, `serverNow()` |
| `eventClock` | Server-time estimate from the last response and the monotonic clock | `serverNow()`, `remainingMs(endsAt)` |
| Renderer registry | Maps `type@schema_version` to a component | `has(key)`, `render(event)` |
| Route registry | Closed set of screens a call-to-action may open | `has(route)`, `open(route)` |
| Presentational components | Render state; hold no business rules | read the store, call `join`, `claim`, `refresh` |

The store is created once at the shell. Components never call the API directly and never compute whether an event has started or ended.

## Client rules in code

### Server-time estimate

The device wall clock is read once per response and never used for remaining time. The server read `server_now` somewhere between the request leaving and the answer arriving; using the midpoint of the round trip bounds the error by half the round-trip time.

<!-- PATTERN: server-time-estimate -->
<!-- PURPOSE: show countdowns from server time using only the monotonic clock after a response -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: monotonic -> performance.now() in a webview or your shell's monotonic source; persist nothing across a restart (the monotonic origin is lost) and show an absolute end time labelled approximate until the next response -->
```typescript
type Sample = { serverNow: number; monoSent: number; monoReceived: number };

const serverNowEstimate = (s: Sample, monoNow: number): number =>
  s.serverNow + (monoNow - (s.monoSent + s.monoReceived) / 2);

const remainingMs = (s: Sample, endsAt: number, monoNow: number): number =>
  Math.max(0, endsAt - serverNowEstimate(s, monoNow));

// remainingMs reaching 0 means "ask the server", never "the event ended".
// Always pass ends_at from the latest response; never start from a duration, so a refetch cannot restart a countdown.
```

### Refetch at the next boundary

<!-- PATTERN: boundary-refetch -->
<!-- PURPOSE: refetch when the server says something changes, spread across clients by jitter, and never later than the refresh interval -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: setTimeout -> your timer; rand -> Math.random or a seeded source in tests; also refetch on app foreground when the snapshot is older than the interval or a boundary has passed while in the background -->
```typescript
function nextRefetchDelayMs(
  nextBoundaryAt: string | null,
  estNow: number,
  refreshSeconds: number,   // DISCOVERY_REFRESH_SECONDS
  jitterMaxSeconds: number, // BOUNDARY_JITTER_MAX_SECONDS
  rand: () => number,
): number {
  const cap = refreshSeconds * 1000;
  if (nextBoundaryAt === null) return cap;
  const untilBoundary = Math.max(0, Date.parse(nextBoundaryAt) - estNow);
  const jitter = Math.floor(rand() * jitterMaxSeconds * 1000);
  return Math.min(cap, untilBoundary + jitter);
}
```

### Hide what cannot be rendered

<!-- PATTERN: renderable-filter -->
<!-- PURPOSE: drop events the build has no renderer for, or whose enum values it does not know, before any screen sees them -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: renderers -> the keys of your renderer registry (type@schema_version); report each drop with the live_event_render_skipped analytics event -->
```typescript
const TRIGGERS = new Set(["milestone", "completion", "participation", "rank", "compensation"]);
const STATES = new Set(["scheduled", "live", "ending-soon", "ended", "archived"]);

function renderable(e: EventItem, renderers: ReadonlySet<string>): boolean {
  if (!renderers.has(`${e.type}@${e.config_schema_version}`)) return false;
  if (!STATES.has(e.state)) return false;
  return e.rewards.every(
    (r) => TRIGGERS.has(r.trigger_kind) && (r.claim_mode === "auto" || r.claim_mode === "manual"),
  );
}
```

Unknown JSON fields are ignored. An unknown `type`, `config_schema_version`, state, trigger or claim mode hides the event; the player is not shown a card that would misstate the rules (INV-13). A renderer that throws is caught at the card boundary: that event is dropped and reported, the rest of the hub stays.

### Content is plain text

Titles, summaries, rules and alt text are inserted as text, never as markup. Asset URLs are used only as image sources. A call-to-action opens a screen only when `routes.has(cta.route)`; otherwise the button is not shown and the event stays visible (INV-18).

## Screens

Time display: absolute instants from the server are formatted in the device locale and time zone. The countdown is the primary display. A countdown shows days and hours while more than a day remains, hours and minutes below that, and minutes and seconds in the last hour; it ticks once per second only in the last minute.

### 1. Event hub

**Purpose.** One list of everything the player can do, ordered as the server sent it (priority, then end time).

**Sections.** Live and ending-soon cards (ending-soon marked by a text label, not only color); Upcoming (teasers); Recent (results of events the player joined); a single Unavailable row group.

**States.**

| State | Behavior |
|---|---|
| Loading, snapshot present | Show the snapshot with the `Last updated` notice; replace on 200 |
| Loading, no snapshot | Skeleton cards; no timers |
| Success | Sections as above |
| Empty | "No events are running right now." If `upcoming` has items they still show; no promise of coming rewards |
| Offline | Snapshot with "You are offline. Times may be out of date." Join and Claim disabled; Retry |
| Error | Snapshot with "Could not refresh events." and Retry; without a snapshot, a message and Retry |
| Stale (older than `STALE_AFTER_SECONDS`) | The same notice as Offline or Error; Join and Claim wait for a fresh response |
| Partial | An event that failed to render is skipped; the rest shows |

**Copy rules.** State facts, not commands: "Ends Sunday 2 November, 00:00" and "1 day left", never "Hurry" or "Don't miss out". Every card shows the title, the layer in words ("Daily", "Weekly", "Season"), the timer and the player's progress. A card whose `recurrence` is set also shows "This event repeats." and, when `next_starts_at` is set, "Next: Monday 2 November, 00:00."; with no next date: "The next date is not set yet." (INV-26). A card whose `original_ends_at` is set shows "Extended from Sunday 1 November, 00:00." beside the new end (INV-25). Rewards you earn are described as kept: "Rewards you earn are yours to keep." The order is the server's; the client does not promote an event because it pays more.

**Accessibility.** Cards are a list of links; each has one accessible name made of title, layer, state and time left. The timer has `role="timer"` and no live announcements; a visually hidden line states the absolute end. The Retry control and every card meet WCAG 2.2 SC 2.5.8 (target at least 24 by 24 CSS pixels; 44 recommended on touch). Section headings are real headings.

**Analytics.** `live_event_hub_viewed`, `live_event_banner_viewed`, `live_event_banner_tapped`, `live_event_render_skipped`, `live_event_stale_shown`, `live_event_discovery_failed`.

### 2. Home banner and badge

**Purpose.** A single entry to the hub from the home screen.

**Banner.** One slot, filled by the first item of `events` that has a banner asset and a renderable type. No banner asset or a failed image load: a text-only banner with the title and timer. No events: no banner (the slot collapses; no placeholder).

**Badge.** A number that counts events with at least one `earned` manual reward waiting (something the player can do now). A separate "new" dot marks a live event the player has not opened since it went live (`seenEventIds`); it clears when the hub or the event detail is opened. An event that is only ending soon adds nothing to the badge.

| State | Behavior |
|---|---|
| Loading | Banner and badge hidden until the first response or snapshot |
| Offline or stale | Banner from the snapshot, no badge number (claims are disabled) |
| Error | Same as offline |
| Reduced motion | No pulsing or shimmer on the badge (`prefers-reduced-motion: reduce`, MDN baseline widely available) |

**Copy rules.** The banner shows title and timer only. The badge has no text beyond the number. No "limited" or "last chance" wording.

**Accessibility.** The banner is one link with the same accessible name pattern as a card; the badge number is part of the entry's name ("Events, 2 rewards waiting").

**Analytics.** `live_event_banner_viewed`, `live_event_banner_tapped`.

### 3. Event detail

**Purpose.** Everything a player needs to decide and to play: rules, the exact reward list, the timer, progress and the one action available.

**Layout.** Banner image (decorative alt from `content.assets.banner.alt`), title, layer and state, the recurrence line and the extension line described for the hub, timer, summary, rules list, reward list (each line with the threshold, every grant with its exact amount, and "Added automatically" or "You claim it"), progress bar, the action area, and a terms line.

**Action area by state.**

| State and player | Action |
|---|---|
| `live` or `ending-soon`, `opt_in`, not joined | Join button; the rules and the full reward list are on the same screen above it |
| `live` or `ending-soon`, joined, or `auto` | The call-to-action from `content.cta` (only if the route exists), and Claim when a manual reward is `earned` |
| `scheduled` (opened from a teaser or link) | No action; "Starts Friday 30 October, 18:00" |
| `ended` | The results sheet opens (screen 5) |
| Join request in flight | Button disabled with a progress indicator; one request at a time |
| `409 event_not_live` or `event_ended` | Refresh and show the new state |
| `409 event_held` | Paused notice (screen 8) |
| `404 event_not_found` | "This event is not available." with a button to the hub |
| `403 update_required` | Unsupported-version state (screen 7) |

**Copy rules.** The reward list shows exact grants. An `opt_in` event states what Join does and what it does not: "Join before you play: points earned before joining do not count." (the rule text comes from the event's `rules`; the client adds no marketing line). The terms line reads "Rewards you earn are yours to keep, even if you do not claim them or the event ends early." (true by INV-10 and INV-11). Compensation after an emergency end is described by the results sheet, not here.

When `season_ref` is present and the build has the season pass screen, the detail offers one link to that season's pass; the reference changes no rule, timer or reward here (INV-24). Without the pass screen the field is ignored.

**Accessibility.** The progress bar is `role="progressbar"` with `aria-valuenow`, `aria-valuemin` 0 and `aria-valuemax` the cap, and a text equivalent ("120 of 600"). Join and Claim buttons are real buttons with visible focus and disabled states that explain why in text. After Join succeeds, focus moves to the progress area and the change is announced once through a polite live region.

**Analytics.** `live_event_detail_viewed`, `live_event_join_tapped`, `live_event_claim_tapped`, `live_event_unsupported_shown`.

### 4. Ending-soon state

**Purpose.** Tell the player, once and plainly, that the event is in its last stretch.

**Behavior.** When the server marks an event `ending-soon`, the card and the detail show the label "Ending soon" and the exact end time. Nothing else changes: no new reward, no bigger numbers, no animation beyond the label (INV-12). A polite live region announces the state change once per event per session. The timer does not escalate in color or size as it approaches zero.

| State | Behavior |
|---|---|
| Entered while the app is open | Label appears at the boundary refetch; announce once |
| Entered while the app was closed | Label shown on the first response; no announcement |
| An extension returned the event to `live` | Label removed on the next response |
| Timer reaches zero | "Checking..." until the server answers, then the results sheet or the ended state |

**Copy rules.** "Ending soon. Ends Sunday 2 November, 00:00." No exclamation marks, no "last chance", no loss framing about progress (earned rewards are kept). For a game whose audience includes children (kit interview 4), keep this wording; urgency language aimed at children is among the practices named in the EU action described in guide 06.

**Accessibility.** The label is text, not only color or an icon. Reduced motion removes any transition on the label.

**Analytics.** `live_event_ending_soon_shown`.

### 5. Results and reward claim

**Purpose.** Close the loop: final progress, what was earned, what is waiting, and a single action to collect.

**Content.** Final progress ("580 of 600"), a list of rewards with status (Added, Ready to claim, Not reached), a Claim all button when any manual reward is `earned`, and a sweep note: "Rewards you do not claim are added to your account automatically on Thursday 5 November." (`archive_at` formatted for the player). For an event that closed early: "This event ended early." and, when compensation was paid, the compensation line as a reward with the label "Compensation".

| State | Behavior |
|---|---|
| Loading | Skeleton rows; no claim button |
| Success, nothing to claim | All rewards Added; a Close button |
| Claimable | Claim all enabled |
| Claiming | Button disabled with a progress indicator; one request per event |
| Partial success | Rewards that landed show Added; the rest show "Could not add yet. Try again."; Claim all stays enabled for what remains |
| `503 grant_pending` | Same as partial; the server keeps retrying and the sweep adds the rest |
| Already claimed (another device, a replay) | Rows show Added; no error |
| Expired | There is no expiry; after `archive_at` the event is not listed |
| Offline or stale | Claim disabled with the reason in text |
| `409 event_held` | Paused notice; Claim disabled |

**Copy rules.** The player is told exactly what was added, with amounts. "Not reached" lines show the threshold without reproach. No "you missed out" wording. A claim failure never says the reward is lost.

**Accessibility.** The sheet is a modal dialog with a heading, focus moved to it on open and returned to the opener on close. Each reward row announces its status in text. The result of Claim all is announced once through a polite live region ("2 rewards added").

**Analytics.** `live_event_results_viewed`, `live_event_claim_tapped`, `live_event_claim_failed`.

### 6. Upcoming teaser

**Purpose.** Let the player know what starts soon.

**Content.** Title, layer, "Starts Friday 30 October, 18:00" and a one-line teaser. No reward amounts and no countdown ticking (the answer carries none). Opening a teaser shows the detail screen in the `scheduled` state, whose terms are readable before the start. An optional "Remind me" control appears only when `messaging.push-reengagement` is integrated and the player has granted notification permission; otherwise it is absent.

| State | Behavior |
|---|---|
| Event starts while the screen is open | The boundary refetch replaces the teaser with a live card |
| Offline or stale | Teaser from the snapshot with the stale notice |
| None upcoming | The Upcoming section is not rendered |

**Copy rules.** Plain facts about the start time. No rewards teased as bait.

**Accessibility.** One link per teaser with the start time in its name.

**Analytics.** `live_event_teaser_viewed`.

### 7. Unsupported-version state

**Purpose.** Explain, without blocking the rest of the hub, that an event needs a newer build.

**Hub.** At most one row: "A new event needs version 2.4.0 or later. Update the app." It appears when `unavailable` has `update_required` stubs; the row names the event title once and shows no rewards (stubs carry none). The Update button opens the store listing for the app. Nothing else on the screen changes.

**Detail by deep link.** An answer of `403 update_required` shows a screen with the event title when known, "This event needs version 2.4.0 or later.", the Update button and a Back button. An event the client cannot render (no renderer) is hidden from the hub and, by deep link, shows the same screen.

| State | Behavior |
|---|---|
| Store listing unavailable offline | Update button disabled with "Connect to update." |
| Player updates and returns | The next discovery response contains the event as a normal card |
| `UPDATE_STUBS_ENABLED` is false | No hub row; only the deep-link screen exists |

**Copy rules.** One neutral line. No countdown on this row, no pressure ("Update now or lose rewards" is not allowed); an event already running is not described as being lost.

**Accessibility.** The Update button has a name that states the destination ("Update in the app store").

**Analytics.** `live_event_unsupported_shown`, `live_event_update_tapped`.

### 8. Paused event

**Purpose.** Tell a participant that an event is paused and that nothing is lost.

**Content.** In the hub, an Unavailable row with the title and "Paused. Your progress and rewards are kept." In the detail, the same notice with Back, and Join, progress and Claim hidden.

| State | Behavior |
|---|---|
| Hold released | The next response returns the event as a normal card |
| Event ended while held | Results appear after release; settlement resumes then |

**Copy rules.** No cause is guessed. No promise of a compensation or extension until the operator decides one.

**Analytics.** `live_event_unsupported_shown` with reason `held`.

### 9. Offline, stale and error

**Purpose.** Keep the calendar readable and honest when the network is not.

| Condition | Hub and detail | Writes |
|---|---|---|
| No connection | Snapshot with "You are offline. Times may be out of date."; countdowns use the monotonic estimate while the process lives, otherwise the absolute end time labelled approximate | Join, Claim and progress calls disabled in the UI |
| Server error or timeout | Snapshot with "Could not refresh events." and Retry | Same |
| `latch_unavailable` | Treated as a server error | Same |
| Snapshot older than `STALE_AFTER_SECONDS` | `Last updated` notice | Disabled until a fresh response |
| Account changed | Snapshot cleared, loading state | |
| Unparseable response | Snapshot kept, error notice, one `live_event_discovery_failed` | |

A device whose clock is wrong sees correct timers, because the estimate uses `server_now` and the monotonic clock. A device that moves its clock forward gains nothing: the server judges every write (INV-1).

**Accessibility.** Notices have `role="status"`; Retry is a real button.

**Analytics.** `live_event_discovery_failed`, `live_event_stale_shown`.

### 10. Preview mode (QA builds only)

A build with a preview token configured shows a persistent banner "Preview: showing <instant>. Read only." with the same state labelled in text. Join, Claim and progress controls are disabled with the reason "Preview is read only." Preview is not reachable from player settings or any deep link, and a release build without a token has no code path to it. See `security.md` T-6.

## Analytics

Names use the prefix `live_event_` so they cannot be confused with the analytics envelope's `event_name`. Every event carries the shared envelope (`event_name`, `account_id`, `session_id`, `server_ts`, `client_ts`, `app_version`, `platform`) from guide `12-live-ops-and-instrumentation.md`; server-emitted events omit `session_id` and `client_ts` and are emitted at the same moment as the domain event of the matching name in `README.md` section 6. Properties below are in addition. No event carries spend, price or balance data.

| Event | Emitted by | Properties |
|---|---|---|
| `live_event_hub_viewed` | client | `events_count`, `upcoming_count`, `recent_count`, `unavailable_count`, `snapshot_status` (`fresh|stale`), `source` (`home|deep_link|push|tab`) |
| `live_event_banner_viewed` | client | `event_id`, `cadence_layer`, `state`, `has_banner_asset` |
| `live_event_banner_tapped` | client | `event_id`, `cadence_layer`, `state` |
| `live_event_detail_viewed` | client | `event_id`, `event_type`, `cadence_layer`, `state`, `joined`, `source` |
| `live_event_join_tapped` | client | `event_id`, `cadence_layer`, `state` |
| `live_event_joined` | server | `event_id`, `cadence_layer`, `join_mode`, `state` |
| `live_event_progress_recorded` | server | `event_id`, `applied_amount`, `progress`, `capped`, `duplicate`, `caller` (`server|client`) |
| `live_event_reward_earned` | server | `event_id`, `reward_key`, `trigger_kind`, `claim_mode` |
| `live_event_claim_tapped` | client | `event_id`, `reward_count` |
| `live_event_reward_granted` | server | `event_id`, `reward_key`, `grant_path`, `attempts` |
| `live_event_claim_failed` | client | `event_id`, `error_code` |
| `live_event_ending_soon_shown` | client | `event_id`, `cadence_layer`, `remaining_seconds` |
| `live_event_results_viewed` | client | `event_id`, `progress`, `granted_count`, `pending_count`, `closed_early` |
| `live_event_teaser_viewed` | client | `event_id`, `cadence_layer`, `starts_in_seconds` |
| `live_event_unsupported_shown` | client | `event_id`, `reason` (`update_required|unknown_type|held`), `surface` (`hub|detail`), `min_app_version` |
| `live_event_update_tapped` | client | `event_id`, `min_app_version` |
| `live_event_discovery_failed` | client | `error_class` (`offline|server|timeout|parse`), `had_snapshot`, `snapshot_age_seconds` |
| `live_event_stale_shown` | client | `snapshot_age_seconds`, `surface` |
| `live_event_boundary_refetch` | client | `boundary_kind` (`start|ending_soon|end|archive`), `jitter_ms`, `drift_ms` (estimate minus returned `server_now`) |
| `live_event_render_skipped` | client | `event_id`, `event_type`, `config_schema_version`, `reason` (`no_renderer|unknown_enum|render_error|bad_asset`) |
| `live_event_settled` | server | `event_id`, `participants`, `claims_created`, `duration_ms` |

Server domain events (`event_published`, `event_extended`, `event_held`, `event_released`, `event_ended_early`, `event_settled`, `event_reward_granted`) and the `event_ending_soon` hand-off are defined in `README.md` section 6.

## Anti-patterns

| DON'T | Why |
|---|---|
| Decide that an event started or ended from the device clock | The server decides every window (INV-1); a changed device clock would show or hide events and unlock buttons |
| Hide the reward list until Join | The player must see exact terms before committing |
| Escalate the timer's color, size or wording near the end | Ending-soon is presentation only (INV-12); pressure copy is the pattern guide 06 flags |
| Show a badge for ending-soon events the player has nothing to do in | A badge must mean something to do now |
| Render event text as markup or open an unknown route | Content is data (INV-18); a stored script in event copy would run in the web view |
| Treat `server_now` from a cached HTTP response as current | It is stale by definition; keep the sample with its monotonic receipt time |
| Retry a claim with a new idempotency key | The server builds the key from stable facts; a client retry sends the same request |
| Rebuild a countdown from the event's full duration on a refetch, or reuse a timer for the next occurrence | The timer counts to the server's `ends_at` and never restarts (INV-25); the next occurrence is a different event with a recurrence label |
| Present a repeating event as a one-off, or write "last chance" on it | A recurring event says it repeats (INV-26); the calendar prints the label and the copy must not contradict it |
| Show "you lost your progress" when an event ends | Earned rewards are kept and swept; progress is not erased |
| Half-render an unknown event type | Hide it (INV-13) |
