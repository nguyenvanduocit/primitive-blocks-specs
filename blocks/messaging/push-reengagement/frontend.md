# Frontend Patterns - Push Notifications and Re-engagement

The client is a web-tech app inside a native shell. It owns the permission flow, the token upload, the local lane, the settings screens and the tap handler. The text below is framework-agnostic; snippets are L3 illustrative TypeScript with the markers of `docs/SPEC_GUIDELINES.md` section 6. It is split on the **pure vs I/O boundary**:

| Part | Responsibility | I/O? |
|------|----------------|------|
| `pushCore` | `nextPrimingAction`, `planLocal` (the client subset of `decide`), `quietUntil`, `resolveRoute`, `localKey` | None. No clock besides arguments, no platform calls. Runs in tests with no mocks. |
| `PushPlatform` port | permission, token, channels, local scheduling, settings deep links, tap and foreground events | Native plugin calls |
| `pushStore` | `push_ui_state` (device storage), cached `GET /api/push/state`, the receipt queue, the handled-tap list | Device storage, Push API |
| UI | priming sheet, denied banner and hint, settings screen, welcome-back sheet | DOM |

## Platform port (L1)

Every platform call goes through one port so the policy code never touches a plugin. Each method returns a value and does not throw (an error is a result).

| Method | iOS | Android |
|--------|-----|---------|
| `permission()` | `getNotificationSettings`, status mapped `notDetermined` to `not_determined`, `authorized` and `ephemeral` to `authorized`, `provisional`, `denied` (P2) | `POST_NOTIFICATIONS` granted and `areNotificationsEnabled()`: `authorized`; refused: `denied`; never requested: `not_determined`. Android 12 and lower has no runtime permission: `areNotificationsEnabled()` decides (P7, P8) |
| `canPrompt()` | `permission() = not_determined` (P1) | the port counts its own refusals; after two refusals, or when a request returns with no dialog shown, it is `false` (P9) |
| `request({ provisional })` | `requestAuthorization` with alert, sound, badge; `provisional` adds the provisional option and needs no dialog (P1, P3) | requests `POST_NOTIFICATIONS` (P7) |
| `token()` | asks the system for the current token at every launch; never cached on the device (P17) | FCM registration identifier: an installation id or a registration token (P20) |
| `ensureChannels()` | none | creates one channel per category with the ids `<category>.v1` at every start; re-creating an existing channel is a no-op (P10) |
| `blockedCategories()` | empty | categories whose channel has importance none |
| `openSystemSettings(kind)` | `app` or `notifications`: the notification settings page (iOS 16+) or the app's settings page (P4) | `app`: the app's notification settings; `channel`: that channel's settings (P10) |
| `scheduleLocal`, `cancelLocal(key)`, `cancelAllLocal()`, `pendingLocal()` | requests by identifier; the same identifier replaces; at most 64 pending (P12) | inexact alarms, no exact-alarm permission requested (P11); rescheduled after boot (P11) |
| `onTap(fn)`, `launchTap()` | notification response, including the one that launched the app | intent extras |
| `onForeground(fn)` | `willPresent` | `onMessageReceived` |

## Priming policy

The policy is a pure function over the device record `push_ui_state` (`README.md` section 5) and the context the screen knows:

<!-- PATTERN: next-priming-action -->
<!-- PURPOSE: decide whether a trigger opens the priming sheet, the system dialog, a denied hint or nothing -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: ctx.canPrompt and ctx.permission come from the PushPlatform port; cfg is PRIME_* from /api/push/state or bundled defaults; add platform-specific refusals counting inside the port, not here -->
```typescript
type Action = "show_sheet" | "request_system" | "show_denied_hint" | "open_settings" | "none";

export function nextPrimingAction(s: UiState, c: Ctx, cfg: PrimeCfg): Action {
  if (!c.eligible || c.permission === "authorized" || c.permission === "provisional") return "none";
  if (c.trigger === "settings_toggle") return c.canPrompt ? "request_system" : "open_settings";
  if (cfg.requiresFirstWin && !c.firstWinDone) return "none";
  if (!cfg.triggers.includes(c.trigger)) return "none";
  if (s.systemPromptSession === c.sessionId) return "none";            // never twice in a session
  if (!c.canPrompt) {                                                   // denied for good
    const gap = c.sessionCount - s.lastHintSession >= cfg.deniedHintMinSessions;
    return s.deniedHintsShown < cfg.deniedHintMax && gap ? "show_denied_hint" : "none";
  }
  if (s.primingShown === 0) return "show_sheet";
  const gap = c.sessionCount - s.lastPrimingSession >= cfg.reaskMinSessions;
  return s.primingShown <= cfg.reaskMax && gap ? "show_sheet" : "none";
}
```

Rules behind it (INV-3):

1. **No ask before the first win** (`PRIME_REQUIRES_FIRST_WIN`), and never at first launch (P1: ask in context, not at first launch; `01-first-session.md:11`).
2. **A trigger ties the ask to a visible benefit**: `first_timer_started` (the first time a timer starts on a valuable resource), `streak_day_2` (the first time the streak has something to protect), `session_3` (the fallback; Android suggests the third or fourth launch, P8). Each trigger fires once per occurrence; the sheet explains the reminders the game actually has.
3. **Explain first**: `show_sheet` opens the priming sheet; only its primary button calls `request_system`. `request_system` is also the direct answer when the player flips a switch in settings (the player's own act, no sheet).
4. **After "Not now"** the sheet may return after `REASK_MIN_SESSIONS` sessions, at most `REASK_MAX` more times; afterwards only the settings screen offers notifications.
5. **After a system refusal on iOS** `canPrompt` is false for good (P1). On Android the first refusal leaves one more attempt; the second is permanent (P9). Neither platform is asked again by code.
6. **Provisional** (`PROVISIONAL_FIRST`, default off): if on, the app calls `request({ provisional: true })` at first launch and registers a token without a dialog; notifications then arrive quietly in the notification list (P3). The upgrade to full delivery is the same priming flow; what the system does when an app already holding `provisional` asks for full authorization was not verified for this block (README, "Not covered").
7. **After the system dialog** the app reads `permission()` again, uploads the token on `authorized` or `provisional` (`PUT /api/push/tokens`), reports `denied` the same way, and fires `push_system_prompt_result`.
8. **Returning from system settings**: on every foreground the app compares `permission()` with `last_permission_state`; a change to `authorized` uploads the token and shows a one-line confirmation; a change to `denied` reports it and cancels the local plan (INV-2, INV-7).
9. **Token upload cadence**: at every start with `authorized` or `provisional`, upload when the token value differs from the last uploaded one or the last upload is older than `TOKEN_REUPLOAD_DAYS`. Failures retry on the next start and on the next foreground; nothing blocks the UI.

## Component tree

```
PushRoot/                          # mounts once; owns the platform port, store, listeners
├── PrimingSheet                   # modal, opened by nextPrimingAction = show_sheet
├── DeniedHint                     # inline, next to the feature that benefits; dismissible
├── WelcomeBackSheet               # modal, opened by a granted comeback answer
└── (Settings > Notifications)
    NotificationSettingsScreen/
    ├── PermissionStatusRow        # status text + one action
    ├── DeniedBanner               # only when the OS permission is off
    ├── MasterSwitch               # global_enabled
    ├── CategoryRow[]              # name, one line, switch; Android: channel-blocked note
    ├── QuietHoursCard             # switch, start and end pickers, time zone note
    └── CapsNote                   # "At most N a day and M a week, across all types"
```

## Screens

### Priming sheet

**Purpose**: explain what the notifications are for before the system asks, and let the player decline without cost.

| State | What the player sees |
|-------|----------------------|
| `default` | Title naming the benefit tied to the trigger; one line per category the game has and the player can switch on; two unchecked switches for the promotional categories; **Turn on notifications** and **Not now**; a line saying the choice can change in Settings |
| `requesting` | Buttons disabled while the system dialog is open |
| `granted` | Sheet closes; no further screen. If the player ticked a promotional switch, the preference is saved with the consent copy version |
| `denied` | Sheet closes; no message that scolds. The settings screen carries the explanation from then on |
| `offline` | Identical to `default`; the system dialog is local; the token upload retries later |
| `error` | Token upload failed: invisible to the player; retried in the background |
| `already-authorized`, `not-eligible`, `already-shown-this-session` | The sheet is not shown |

**Copy rules**:

- Name concrete benefits in the game's words ("Know when your energy is full", "A heads-up before your streak ends"). List only categories the game really sends; a subscription line appears only if the game offers a trial and is never pre-selected for a profile that is not an adult.
- The two promotional switches (events, welcome-back gifts) are **off by default**; their label is the consent language (P5): what is sent and that it can be switched off in Settings.
- No reward, bonus or progress is promised for enabling notifications, and none is withheld for refusing (P6; INV-15).
- No urgency, no count of "players who enabled", no guilt on **Not now** (no "Are you sure?"; no sad faces).
- The sheet never imitates the system dialog: its buttons do not read "Allow" and "Don't allow".
- **Not now** has the same size and reach as **Turn on notifications**.

**Accessibility**: a modal dialog with a title; focus moves to the title on open and returns to the trigger on close; focus stays inside; the back gesture and Escape mean **Not now**; every switch has a name and a state read aloud; the reading order is title, benefits, switches, buttons; text scales with the system size without clipping; no motion is required.

**Events**: `push_priming_shown {trigger, showing_index}`, `push_priming_accepted {trigger}`, `push_priming_declined {trigger, showing_index}`, then `push_system_prompt_result {result, can_prompt_again}`, `push_permission_changed`, `push_token_registered` or `push_token_register_failed`, `push_category_toggled` for each promotional switch ticked.

### Denied-state banner and inline hint

**Purpose**: tell a player who refused (or turned notifications off in the system settings) that reminders cannot reach them, and offer the way back **only when the player is looking for it**.

Two surfaces:

- **Banner** at the top of the notification settings screen whenever `permission()` is `denied`. It states the fact and carries one action, **Open settings**, which calls `openSystemSettings("notifications")` (`app` on older iOS, P4). The player reached the screen by choice; the action is theirs.
- **Inline hint** next to the feature that benefits (for example under a started timer): one line and a dismiss control, shown at most `DENIED_HINT_MAX` times in the install's life and never within `DENIED_HINT_MIN_SESSIONS` sessions of the last one. It links to the same settings screen, not directly to the system. Android's guidance is not to link to system settings in an effort to convince the player (P9); the hint therefore never auto-opens anything and never reappears after a dismiss in the same session.

| State | Behavior |
|-------|----------|
| `denied` | Banner visible; master switch and category switches are shown but a tap on one explains that notifications are off in system settings |
| `granted-after-return` | Banner disappears on foreground; one-line confirmation |
| `os-blocked-channel` (Android) | The category row says the channel is blocked in system settings and offers **Open channel settings** (P10) |
| `offline` | Unchanged; opening system settings needs no network |

**Copy rules**: state the situation and the consequence in neutral words ("Notifications are off for this app, so timers and reminders can't reach you."); no pressure, no repeated prompts, no reward for turning on (P6, P9).

**Accessibility**: the banner is a status region announced once on screen open; the action is a button with a name that says it opens system settings; the hint is dismissible by keyboard and by screen reader.

**Events**: `push_denied_hint_shown`, `push_denied_hint_action {action}`, `push_system_settings_opened {kind}`, `push_permission_changed {source: "system_settings"}`.

### Notification settings screen

**Purpose**: every control over notifications in one place: master switch, per-category switches, quiet hours.

| State | Behavior |
|-------|----------|
| `loading` | Render the cached `GET /api/push/state`; refresh in the background; skeleton rows only if no cache exists |
| `loaded` | All controls live |
| `empty` | Not applicable: the category list always has the catalog entries |
| `offline` | Switches stay usable; a change is applied locally, queued, and shown as "Will update when you're online"; the queue flushes on reconnect (server answers are idempotent) |
| `error` | A failed `PATCH` reverts the switch and shows "Couldn't save. Try again." beside it |
| `not-eligible` | The entry point in Settings is hidden; a deep link to this screen redirects to Settings home |
| `success` | The new switch position is the confirmation; no toast |

Controls:

- **Master switch** (`global_enabled`): when off, every category row is dimmed but keeps its position, so turning it back on restores the previous choices.
- **Permission status row**: one of "Allowed on this device", "Quiet delivery only" (`provisional`), "Not asked yet" with **Turn on** (opens the system dialog through `settings_toggle`), "Off in system settings" with **Open settings**.
- **Category rows**, in catalog order: name, one line ("Energy and timers: when a timer is done"), a switch. Promotional categories (events, welcome-back gifts) show their consent line under the name and record `consent_text_version` when switched on (P5). Defaults: service categories on, promotional off. The row "Subscription notices" ("A heads-up before a free trial ends") is shown only when the game offers a trial; it is a service category, shows no consent line, and its switch starts off for a profile that is not an adult (the value comes resolved in `GET /api/push/state`, INV-25). Its one-line description never mentions a plan, a price or an offer.
- **Quiet hours**: a switch and two time pickers in the 24-hour or 12-hour format of the device locale; a line "Uses your time zone: {name}". Start and end must differ; the window may cross midnight.
- **Caps note**: "At most {per_local_day} a day and {per_7_local_days} a week, across all types" from `GET /api/push/state`.
- A link row **Open system notification settings** at the bottom.

**Copy rules**: switching anything off is immediate and silent: no confirmation dialog, no "you'll miss out" text, no reward language. On and off controls have equal prominence. Labels describe what is sent, not what the player gains by keeping it on.

**Accessibility**: switches are native or role-switch controls with name and state; the quiet-hours pickers use the platform pickers; status is never conveyed by color alone (text plus icon); the screen reads in a single logical order; touch targets meet the platform minimum size; the "Will update when you're online" note is a live region.

**Events**: `push_settings_opened {from}`, `push_global_toggled {enabled}`, `push_category_toggled {category, enabled}`, `push_quiet_hours_changed {enabled, start, end}`, `push_system_settings_opened {kind}`.

### Welcome-back sheet

**Purpose**: tell a returning player what they received, once.

| State | Behavior |
|-------|----------|
| `granted` | Opens when `POST /api/push/session` answers `comeback.status = granted`: "Welcome back. {amount} {currency name} were added to your balance." One button **OK** |
| `pending` | Nothing shown. The client repeats the same `session_id` call after `COMEBACK_PENDING_RETRY_SECONDS`, up to `COMEBACK_PENDING_RETRY_MAX` times; the replay returns the current status (INV-21) |
| `none` | Nothing |
| `already-shown` | The client keeps the grant key (`step_id` + anchor) it showed and never shows it twice |
| `error` | Nothing; the grant is on the server regardless and appears in the balance |

**Copy rules**: state what was added; no deadline, no "claim now", no mention of notifications (the reward does not depend on them, P6; INV-15); no streak-loss framing.

**Accessibility**: the sheet announces its text as a polite live region; focus moves to **OK**; dismissal returns focus to the previous screen.

**Events**: `comeback_reward_shown {step_id, amount, currency}`.

### Tap handler (routing)

**Purpose**: open the right screen when the player taps a notification, from a closed app (cold start), a backgrounded app (warm start), or while the app is in the foreground.

| Situation | Behavior |
|-----------|----------|
| Cold start | The platform hands over the launching tap (`launchTap()`). Wait until the app is ready to navigate (session restored, config loaded), then route. The normal `POST /api/push/session` runs as for any launch |
| Warm start | `onTap` delivers the tap; route immediately |
| Foreground | `onForeground` delivers the message; **no system banner** (INV-9). Refresh the state it concerns (`GET /api/push/state`, the emitting block's data); route only if the player taps an in-app element the screens own |
| Duplicate delivery | A tap is handled once: key `send_id` (remote) or `local_key` plus `fire_at` (local), kept in `handled_taps` (the last `HANDLED_TAPS_MAX`) |
| Unknown or invalid route | `resolveRoute` returns `home` (INV-18) and `push_route_failed {reason: "unknown_route"}` fires |
| Target gone (event ended, objective claimed) | Route to the parent list and show a one-line notice: "That isn't available now." `push_route_failed {reason: "unavailable"}` |
| Signed out guest | Guest accounts exist; the tap routes the same way |

After routing, queue the `opened` receipt (`POST /api/push/receipts`); an offline queue holds it for retry. A tap grants nothing (INV-15).

<!-- PATTERN: resolve-route -->
<!-- PURPOSE: turn notification payload fields into a validated in-app route, never a URL -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: ROUTES is the route table of README section 7 (id to accepted parameter names); the route ids map to the project's router names; parse errors return home without throwing -->
```typescript
const PARAM = /^[A-Za-z0-9._:-]{1,64}$/;

export function resolveRoute(data: { route?: string; rp?: string }, ROUTES: Record<string, string[]>) {
  const id = data.route ?? "";
  if (!Object.prototype.hasOwnProperty.call(ROUTES, id)) return { route: "home", params: {}, ok: false };
  let raw: Record<string, unknown> = {};
  try { raw = JSON.parse(data.rp ?? "{}"); } catch { return { route: "home", params: {}, ok: false }; }
  const params: Record<string, string> = {};
  for (const name of ROUTES[id]) {
    const v = raw[name];
    if (typeof v === "string" && PARAM.test(v)) params[name] = v;
  }
  return { route: id, params, ok: true };
}
```

**Accessibility**: the destination screen sets focus to its heading as for any navigation; the "isn't available now" notice is announced politely.

**Events**: `push_opened {lane, category, route, cold_start, send_id | local_key}`, `push_route_failed {route, reason}`.

## Local lane

The local lane runs on the device from the emitting blocks' client-side events (`energy_full`, `queue_item_ready`, `streak_at_risk`). `planLocal` is pure:

1. **Time**: `fire_in = fire_at - (device_now + server_offset)`, where `server_offset = server_now - device_now` from the last server answer (time contract). A hand-off carrying `ends_at` and no `fire_at` uses `ends_at`. `fire_in <= 0` means the player is looking at the app: nothing is scheduled (INV-9).
2. **Decision subset**: apply decision rules 1 to 5 and 8 of `README.md` section 3 with the data of `GET /api/push/state`: eligibility, expiry, master and category switches, quiet hours (shift to the window end when it is before `expires_at`, otherwise drop), and the caps (planned local notifications of that local day plus the server's `used_today` and `used_7_days`). Rule 6 is answered by the OS: permission must be `authorized` or `provisional` and the category channel not blocked (P3, P10). Rules 7 and 9 do not apply to the local lane. Contention resolves by category priority, then `fire_in`.
3. **Pending limit**: keep the `LOCAL_MAX_PENDING` soonest.
4. **Keys**: `local_key = {category}:{subject_key}`, for example `timers:energy:main:1792584000` or `timers:queue-item:item-7f3a`. Scheduling an existing key replaces it (P12); the plan is applied as a diff against `pendingLocal()`: cancel absent keys, schedule new or changed ones.
5. **Order**: an armed event whose revision (`revision` for `queue_item_ready`, `params.meter_revision` for `energy_full`) is lower than the one held for its key is ignored, an equal one changes nothing, a higher one replaces the entry (`README.md` section 6).

<!-- PATTERN: plan-local -->
<!-- PURPOSE: turn armed hand-off events into the set of local notifications the device should hold -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: shiftQuiet wraps quietUntil with the profile window and time zone; capsLeft(day) is the cap minus (planned that local day + the server's used count); copy comes from the template catalog bundled with the app; sort keys follow the category priority column -->
```typescript
export function planLocal(events: Armed[], now: number, offsetMs: number, st: PushState, os: OsView): Planned[] {
  if (!st.eligible || !st.local.allowed || os.permission === "denied") return [];
  const plan: Planned[] = [];
  for (const e of events) {
    const cat = st.categories.find((c) => c.category === e.category);
    if (!cat?.enabled || os.blocked.includes(e.category)) continue;
    let at = e.fireAt;
    if (at - (now + offsetMs) <= 0) continue;                 // the player is in the app
    const quiet = shiftQuiet(at, st);
    if (quiet !== null) at = quiet;                           // window end, else the same instant
    if (at >= e.expiresAt) continue;                          // quiet_expired
    plan.push({ key: `${e.category}:${e.subjectKey}`, category: e.category, fireInMs: at - (now + offsetMs), event: e });
  }
  plan.sort((a, b) => priority(a.category) - priority(b.category) || a.fireInMs - b.fireInMs);
  return applyCaps(plan, st).slice(0, st.local.maxPending);
}
```

**Cancellation (INV-7)**, reported as `push_local_cancelled.reason` with one of `resolved`, `category_off`, `global_off`, `permission`, `logout`, `age_ineligible`, `timezone`, `session_rebuild`, `boot_rebuild`: `resolved` for the key; the same key re-armed (replace); session start (cancel everything and rebuild from the fresh state and the emitting blocks' current state); logout; master or category switch off; permission change to `denied`; `eligible = false`; timezone change; reboot on Android (rebuild at the next app start, and the boot receiver reschedules from the persisted plan, P11). A local notification already scheduled cannot be recalled by another device's change; the next session reconcile fixes it (README, Known limits).

**Android timing**: no exact-alarm permission is requested; inexact delivery may be late by up to an hour on Android 12 and higher (P11). Local copy therefore never states a clock time or a countdown.

**iOS**: check `permission()` before every schedule (P3); a `provisional` status delivers quietly (P3), which the settings status row says in words.

**Copy for the local lane** comes from the template catalog bundled with the app, in the app's current UI language, rendered with the same syntax as the server (required variables, optional segments, derived variables such as `reward_name` from the bundled item catalog); a catalog change ships with an app update. It follows the same lint (no guilt, no fake urgency, no false scarcity) and states a fact that stays true if the state changed meanwhile.

**Local-fire reports**: at every session start the client sends `local_fired`, the entries of its own plan whose `fire_at` has passed and that were not cancelled (at most `LOCAL_REPORT_MAX`), so the server counts them toward the caps and the return window (README section 3).

## Events

All events use the shared envelope. The client events are listed with their properties in `README.md` section 6; this file fires them as follows:

| Event | Fired by |
|-------|----------|
| `push_priming_shown`, `push_priming_accepted`, `push_priming_declined` | priming sheet |
| `push_system_prompt_result`, `push_permission_changed`, `push_token_registered`, `push_token_register_failed` | permission and token flow |
| `push_denied_hint_shown`, `push_denied_hint_action`, `push_system_settings_opened` | denied banner and hint, settings screen |
| `push_settings_opened`, `push_global_toggled`, `push_category_toggled`, `push_quiet_hours_changed` | settings screen |
| `push_local_scheduled`, `push_local_cancelled` | local lane |
| `push_opened`, `push_route_failed` | tap handler |
| `comeback_reward_shown` | welcome-back sheet |

No event carries a token, a notification body or a device identifier other than `installation_id` where the property list says so.
