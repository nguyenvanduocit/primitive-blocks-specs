# Frontend Patterns - Guest Account

> The client is a web-tech mobile shell (a web app in a native wrapper); the text is framework-agnostic. Snippets are L3 illustrative TypeScript with the four markers (`docs/SPEC_GUIDELINES.md` section 6). Behaviour (WHAT) is in the prose, layout is the implementer's. Copy lines below are **rules plus sample English**: the sample shows the content that must be conveyed, not a pixel design. Provider names come from the sign-in flow (`Google`, `Apple`).
>
> The data model, flows and rules are in `README.md`; endpoints and codes are in `backend.md`.

## Component tree

```
App shell
 |- StartupGate              runs the start sequence; renders nothing in the normal case
 |    |- AgeScreen           only in `mixed` audience mode, before any identifier is requested
 |    |- WelcomeBackScreen   one variant per exchange outcome
 |    |- WelcomeScreen       after an explicit sign-out: Sign in | Play as guest
 |- PendingIdentityChip      small status shown by server-dependent features while identity is pending
 |- SaveProgressPrompt       non-blocking banner or bottom sheet, timing rules below
 |- LinkFlow                 provider buttons, provider sheet, verifying, result
 |    |- ConflictSheet       choices, then ConfirmLossStep
 |- RecoveryCodeScreen       display (once) and entry
 |- SettingsAccountSection   kind, player id, link, recovery code, switch or sign out, delete
 |    |- SwitchAccountSheet
```

| Unit | Responsibility | Interface |
|---|---|---|
| `identity` state holder | owns `identity`, runs the start sequence, the exchange, the queue | `start()`, `retryCreate()`, `link(provider, intent)`, `resolve(choice, ...)`, `createRecoveryCode()`, `recover(code)`, `switchAccount()`, readable state |
| Screens | render state; no business logic | read `identity`, `linkFlow`, `problem`; call the holder |

The prompt and every sheet are mounted once at the shell and driven by state; a feature screen never mounts its own copy.

## 1. Start sequence and silent creation (no screen)

In `general` mode first launch shows **no screen and no prompt**: the player sees the game's own first screen while the account is created in the background (`README.md` section 3.1).

**States**: `none` (before start), `pending` (no account yet: offline, throttled, attestation unavailable, under-age local play), `guest`, `linked`, `needs_sign_in`.

**Rules**:

- Never block the first frame, the tutorial or the first win on account creation. Server-dependent features show their own state (section 8).
- Read secure storage; if a credential exists, exchange it. If none exists and the device is online, read secure storage once more (a platform restore may have delivered it) and only then create.
- After an explicit sign-out (`guest.signed_out`) show the welcome screen (section 10); never create a guest silently.
- A `4xx` exchange outcome (`403`, `410`, `401`) shows the welcome-back screen (section 7) and deletes the stored secret. A new guest is created only when the player taps the button on that screen, so the loss is never hidden by a quiet re-creation.
- A `429` or a network failure sets `pending` and retries with `OFFLINE_CREATE_BACKOFF_SECONDS`, on foreground and on connectivity change. No error is shown for the first failures; the chip of section 8 appears only where a feature needs the server.
- A found credential beats a new account: the client never creates while a valid secret is present.

<!-- PATTERN: start-sequence -->
<!-- PURPOSE: decide what the first frames do, so the player never waits and a loss is never hidden -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: readSecret/exchange/create/readSecretAgain -> your secure-storage plugin and HTTP client; setIdentity and showWelcomeBack -> your state holder and screen controller; keep the order (exchange, re-read, create) and the rule that a 4xx outcome never creates -->
```typescript
async function start(): Promise<void> {
  const secret = await readSecret();
  if (secret) return handleExchange(await exchange(secret));
  if (store.signedOut) return showWelcome();
  if (audience === "mixed" && !store.ageScreenDone) await runAgeScreen();
  if (!(await isOnline())) return setIdentity("pending", "offline");
  const late = await readSecretAgain(); // a platform restore may have arrived
  if (late) return handleExchange(await exchange(late));
  await createGuest();
}

function handleExchange(r: ExchangeResult): void {
  if (r.ok) return setIdentity("guest");
  if (r.status === 429 || r.network) return setIdentity("pending", "throttled");
  deleteSecret();
  showWelcomeBack(r.code, r.reason); // never creates by itself
}
```

## 2. Age screen (`mixed` audience mode)

**Purpose**: ask age neutrally before any identifier is requested; the answer stays on the device until an account is created (`README.md` section 3.10).

**States**: idle; invalid (month or year missing); done.

**Copy rules**: ask for month and year of birth with no default selection and no hint of a threshold (FTC FAQ D.7: "does not default to an age 13 or over", free entry of month and year of birth, HIGH). Do not explain why a given answer changes anything. Do not offer an "I am over 18" button.

**Behaviour**: the result is written to device storage at once and cannot be changed in the app (a back-button or relaunch does not re-ask; FTC D.7 mentions preventing back-buttoning, HIGH). Below `AGE_THRESHOLD_YEARS` the outcome follows `AUDIENCE_UNDER_AGE_ACCOUNT`: `none` plays local-only with identity pending and hides server-dependent features; `guest_internal_ops` creates the account with `age_screen = under_age` and hides every link prompt.

**Accessibility**: pickers are labelled; the month and year fields work with a screen reader and a keyboard; no time limit.

**Events**: `age_screen_result`.

## 3. Save-your-progress prompt

**Purpose**: tell the player, once and without pressure, that a guest game lives on this device only, and offer to save it.

**Timing rules** (the prompt is due only when all hold):

1. The player has won the first level or its equivalent (`kits/game-engagement/guides/01-first-session.md`: no account ask before the first win).
2. The game is at a natural pause (a result screen, the home screen), never mid-play and never over another sheet.
3. It has not been shown in this session.
4. The last dismissal was at least `LINK_PROMPT_COOLDOWN_DAYS` ago, and fewer than `LINK_PROMPT_MAX_DISMISSALS` dismissals exist; after that only the Settings entry offers linking.
5. The device is online, identity is `guest`, audience mode is not `kids` and the account is not `under_age`.

A second, non-blocking trigger sits in the purchase flow: a one-line notice inside the purchase confirmation, "This purchase belongs to your guest account on this phone. Save your progress to keep it if you lose this phone." It never gates the purchase and never replaces a store sheet.

<!-- PATTERN: prompt-due -->
<!-- PURPOSE: one pure function decides whether the save-your-progress prompt may appear -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: Ctx fields -> your state holder; nowMs comes from the app clock but only compares two device-recorded times against a cooldown, which is display pacing, not a game timer; the config values come from configuration -->
```typescript
type Ctx = { won: boolean; atPause: boolean; shownThisSession: boolean; online: boolean;
             kind: "guest" | "linked"; audience: string; underAge: boolean;
             dismissals: number; lastDismissedMs: number | null; nowMs: number };

export function promptDue(c: Ctx, cooldownDays: number, maxDismissals: number): boolean {
  if (c.kind !== "guest" || !c.won || !c.atPause || c.shownThisSession || !c.online) return false;
  if (c.audience === "kids" || c.underAge) return false;
  if (c.dismissals >= maxDismissals) return false;
  if (c.lastDismissedMs !== null && c.nowMs - c.lastDismissedMs < cooldownDays * 86_400_000) return false;
  return true;
}
```

**Copy rules**:

- Say what is true: "Your game is saved on this phone only. If you lose or reset the phone, it is lost. Save it to your Google account (or Apple ID) to get it back on any phone."
- Say what is received: "We use your sign-in only to find your game again." (the login blocks decide the claims; Apple can hide the email address.)
- Two buttons of equal size and weight: the provider button and "Not now". "Not now" costs nothing and nothing is withheld for choosing it.
- No countdown, no fear copy ("You will lose everything!"), no reward for linking in the default configuration, no repeated pop-up within a session.
- On iOS, if Google is offered, Apple is offered with equal prominence ([Apple 4.8](https://developer.apple.com/app-store/review/guidelines/), HIGH).

**States**: hidden; shown; dismissed (writes `guest.prompt_state`); accepted (opens the link flow); offline (not shown; the Settings entry is disabled with the reason "Connect to the internet to save your game").

**Accessibility**: it is a region, not a modal trap; focus is not stolen from the game; the dismiss control is reachable by keyboard and screen reader with the label "Not now, keep playing as a guest"; text scales with the system setting.

**Events**: `link_prompt_shown`, `link_prompt_dismissed`, `account_link_started`.

## 4. Link flow

**Purpose**: attach Google or Apple to the guest account (`README.md` section 3.7).

**States**: `idle`, `starting` (link start), `provider` (the system or browser sheet is open), `verifying`, `done`, `conflict`, `failed`.

**Entry points**: the save-your-progress prompt; Settings ("Save progress" with `intent = link`, and "I already have an account" with `intent = restore`); the purchase notice; and, if the game has a title screen, a quiet text link "Already have an account? Sign in". The text link never opens a modal by itself and may appear before the first win because the player chose it; it is not an ask.

**Behaviour**:

- Link start sends the stored device secret together with the session; the client reads the secret from secure storage for that call only.
- Buttons are disabled during `starting`, `provider` and `verifying`; a second tap is ignored.
- Closing the provider sheet is a silent `idle` (no error). The login blocks' client flows are used unchanged; this block only supplies the nonce.
- On `done`: one confirmation ("Saved to {provider}. You can use this account on any phone."), the stored device secret is deleted, the settings row shows the linked state. Nothing about the game changes on screen.
- On `403 account_linked` at the next start (lost response): "Your game is saved. Sign in with {provider} to continue." with the provider buttons.
- Provider buttons follow the platform rules of the login blocks (`APPLE_SIGN_IN_PLATFORMS`).

**Errors** (`sign_in_failed.reason` in brackets):

| Condition | Copy rule | Action |
|---|---|---|
| Provider sheet closed [`cancelled`] | none | back to `idle` |
| No network [`network`] | "No connection. Your game is unchanged." | retry button |
| Provider error [`provider_error`] | "{provider} could not sign you in. Your game is unchanged." | retry button |
| Attempt expired [`nonce_expired`] | "That took too long. Try again." | restart |
| Too many starts [`rate_limited`] | "Too many tries. Try again in {minutes} minutes." | disabled until then |
| Account is not an active guest [`not_a_guest`] | "This account is already saved." | refresh account state |

Every message says the game is unchanged when that is true. No message shows a code, a token or an id.

**Accessibility**: status changes are announced politely once; the provider buttons carry visible text, not only the logo; focus returns to the entry control after the sheet closes.

**Events**: `account_link_started`, `sign_in_failed`; server `account_linked`, `link_conflict`.

## 5. Conflict-resolution sheet

**Purpose**: when the credential already belongs to another account, say in plain words what each choice keeps and what it removes, and change nothing until the player confirms.

**Content from the server**: `reason`, `guest_weight`, `default_choice`, `items` (each with `category`, `label_key`, `paid`, `effect`), `preview_digest`, `expires_at`.

**Variants**:

| `guest_weight` | Behaviour |
|---|---|
| `pristine` | No sheet. The sign-in completes into the existing account and a toast says: "Signed in. The new guest game on this phone was empty, so nothing was lost." |
| `played` | Sheet with both choices; "Use my saved game" carries the label "Suggested" when `default_choice` is `keep_existing`; the import toggle is on. |
| `paid` | Sheet with both choices and **no** preselection and no "Suggested" label. |
| reason `email_owned_by_other_provider` | Different sheet (below), no import, no choices about holdings. |

**Sheet copy rules** (sample):

- Title: "This {provider} account already has a saved game."
- Lead: "Your guest game on this phone and the saved game are separate. Choose which one to keep."
- Choice A, "Use my saved game": "Opens the game saved with {provider}. Your guest game stays on this phone only until it is removed." Then two lists built from `items`: **Brought over** (effect `carried`) and **Removed** (effect `left_behind`, and `kept_target` where the guest's value is dropped), each as plain labels ("daily streak", "coins"). A switch: "Bring over my guest progress" (on for `played`, off and unticked until chosen for `paid`).
- Choice B, "Keep my guest game": "Nothing changes. {provider} is not linked here. Your game stays only on this phone until you save it another way."
- A text button "Decide later" closes the sheet without a change; the attempt expires by itself.

**Confirm step** for choice A when the weight is `played` or `paid` (never skipped, never pre-confirmed):

- Heading: "Remove from your guest game?" and the list of `left_behind` and differing items.
- Button label names the loss: "Use saved game and remove {n} items"; never "OK" or "Continue".
- For each `paid` item whose effect is not `carried`, a separate checkbox, unticked: "I understand that {label}, bought with real money, stays on the guest account and will not be in the saved game." Beneath the list, for a `purchases` item that is a subscription: "Your subscription is billed by {store} and stays with the guest account. Manage or cancel it in {store} settings."
- "Go back" returns to the choices.
- The request carries `confirmed_preview_digest` and `acknowledged_paid`. A `409 preview_changed` replaces the list with the new one and shows: "Your guest progress changed. Please review again."

**Email variant**: title "This email already has an account with {other provider}." Body: "Sign in with {other provider} to continue." Buttons: "Sign in with {other provider}" and "Stay as guest". No holdings are shown.

**States**: loading preview; choosing; confirming; importing ("Moving your progress. Keep the app open." non-cancellable); import incomplete ("We could not finish. Nothing was lost. Try again."); preview changed; expired ("That took too long. Start again."); offline (confirm disabled with the reason); done.

**Rules**: no preselected destructive choice for `paid`; "Keep my guest game" removes nothing and is always one tap away; the order of the two choices is fixed, not randomised; the sheet never shows another account's id, email or name.

**Accessibility**: the choices are a radio group with the lists linked by `aria-describedby` (or the platform equivalent); focus moves to the sheet title on open and returns on close; the destructive button is identified by its text, not by colour alone; checkboxes have full sentence labels; targets are at least the platform minimum; the lists are read in order; reduce-motion removes the sheet animation.

**Events**: `link_conflict_sheet_shown`, `link_conflict_sheet_dismissed`; server `link_conflict`, `link_conflict_resolved`.

**Client data rule (`data.progress-sync`)**: a guest never syncs a snapshot, so the owner marker stays absent until the link completes and that block's first sync sets it (INV-19). Choice A with import: signing in lets that block merge the device data into the existing account's snapshot, and nothing is replaced. Choice A without import: the client first saves the device data aside with that block's previous-data backup and resets the local record, then signs in. Choice B and a same-account link leave the device data as it is (`README.md` section 3.7).

## 6. Recovery code: display and entry

### Display

**Purpose**: give the guest a way back after a lost device (`README.md` section 3.6).

**States**: creating; shown (code visible); confirmed; error; offline.

**Copy rules**: "This code opens your guest game on another phone. Anyone who has it can open the game, so keep it private. It is shown once." Show the 24 characters in six groups of four, large, selectable, in a font that separates `0` from `O` and `1` from `I`. Offer Copy and Share (the system share sheet). A checkbox "I stored this code" enables "Done". A new code replaces the old one: "Creating a new code makes the old one stop working."

**Behaviour**: the code is requested only from a guest session and only on the player's tap; it is never logged, never put in analytics or crash reports, and cleared from memory when the screen closes. Leaving without confirming keeps the code active on the server; the settings row then reads "Recovery code created, not confirmed" with a "Create a new code" action.

**Accessibility**: the code has a screen-reader mode that reads characters one by one on request, not automatically (to avoid speaking a secret in public); copy is announced ("Copied").

**Events**: `recovery_code_shown`, `recovery_code_confirmed`.

### Entry

**Purpose**: recover a guest account on a new device.

**States**: idle; typing; invalid format (before sending); submitting; wrong code; rate limited; network error; already used; account saved elsewhere; success.

**Behaviour**: the field accepts paste, ignores case, hyphens and spaces, and reads `I` and `L` as `1` and `O` as `0` (Crockford). Format is checked before sending (24 characters of the alphabet) so a typo does not cost an attempt.

**Copy rules**: wrong code: "That code does not match a guest game. Check it and try again." Rate limited: "Too many tries. Try again in {minutes} minutes." Already used: "This code was already used. If you recovered the game on another phone, use that phone." Saved elsewhere: "This guest game was saved with an account. Sign in with that account." Success: "Your guest game is back. Create a new recovery code now." and the display screen opens. The wording never says whether a code ever existed.

**Accessibility**: input has a visible label, supports paste and the platform's secure-field behaviours off (the field is not a password field, but is excluded from autofill suggestions and keyboard learning); errors are tied to the field and announced.

**Events**: `recovery_code_entered`; server `guest_recovered`.

## 7. Welcome-back screens

**Purpose**: tell a returning player the truth about the guest account (`README.md` section 3.2 and 3.5).

| Outcome (`welcome_back_shown.kind`) | Copy rule (sample) | Buttons |
|---|---|---|
| `reactivated` | "Welcome back. Your guest game was kept while you were away. Guest games that stay unused for {days} days are removed, so save yours to keep it." | Continue; Save progress |
| `purged`, reason `inactive` | "Your guest game was removed after a long time without use. We could not restore it." | Start a new game; Sign in |
| `purged`, reason `deleted` | "This guest game was deleted." | Start a new game; Sign in |
| `purged`, reason `abandoned`, and `account_abandoned` | "This guest game was replaced when you signed in to a saved game." | Start a new game; Sign in |
| `credential_retired`, reason other than recovered | "This phone's access to the guest game was replaced." | Start a new game; Sign in |
| `credential_retired` (recovered) | "This guest game was recovered on another phone with its recovery code. This phone is not connected to it now." | Start a new game; Sign in |
| `account_linked` | "Your game is saved. Sign in with the account you saved it to." | Provider buttons |
| `unknown_credential` | "We could not find your guest game. It may have been removed after a long break, or the data on this phone was cleared." | Start a new game; Sign in; Enter recovery code |

Rules: `{days}` is `GUEST_DORMANT_AFTER_DAYS` rounded for display, and the purge period is stated in the settings text, not invented per screen. The `unknown_credential` screen claims no reason. No screen blames the player. A new guest is created only on the "Start a new game" tap. "Continue" on `reactivated` is the primary action and takes one tap.

**Accessibility**: the heading receives focus; the first button is the safest action; text scales with the system setting.

**Events**: `welcome_back_shown`; server `guest_reactivated`.

## 8. Pending identity (offline first launch)

**Purpose**: keep the first session playable when the account cannot be created yet (`README.md` section 3.1).

**Behaviour**: the game runs. A feature that needs the server (a daily reward, a shop, a season track) shows its own offline state and a small chip: "Offline. Rewards are added when you connect." Rewards the server would pay are **not** shown as received; a local result screen says "will be added when you are online". Events are queued (`guest.pending_events`, cap `OFFLINE_EVENT_QUEUE_MAX`). When the account exists, the queue is submitted in order; each event is accepted or dropped by the receiving block, and the player sees a single summary only if something was dropped ("Some offline progress could not be added.").

**Rules**: the chip appears once per feature screen, not as a toast storm; nothing about identity is shown to the player at all in the normal case; the under-age local-only mode uses the same state with no retry.

**Accessibility**: the chip is text, not an icon alone; one polite announcement when the state changes.

**Events**: `guest_pending_identity`, `guest_identity_reconciled`.

## 9. Settings account section and switching

**Rows**:

| Row | Shown when | Behaviour |
|---|---|---|
| "Guest game on this phone" or "Saved with {provider}" | always | Kind and, for linked, the provider |
| Player ID | always | Full `account_id` with a copy action. It is not a secret and authenticates nothing; support quotes it (guide 11 item 20) |
| Save progress | guest, online | Starts the link flow (`intent = link`); disabled offline with the reason |
| I already have an account | guest, online | Starts the link flow with `intent = restore`; the conflict rules apply, and a pristine guest signs in without a sheet |
| Recovery code | guest, `RECOVERY_CODE_ENABLED` | Create, replace, or enter a code; status line from `guest.recovery_confirmed_at` |
| Switch account | guest | Opens the switch sheet |
| Sign out | linked | Confirmation, then the welcome screen |
| Delete account | always | `compliance.account-deletion`; a guest proves with the device credential |

**Switch sheet (guest)**. Copy: "This guest game lives on this phone. If you switch now, you cannot get back to it from here unless you saved it." Buttons: "Save progress first", "Create a recovery code first", and a plain text button "Switch anyway" that opens a confirmation: "Switch without saving? This guest game will not be reachable from this phone." The confirm button reads "Switch and leave this guest game". After it, the device secret is removed and the welcome screen opens.

**Sign out (linked)**. Copy: "Sign out of {provider}? Your game stays saved in your account." The device clears its session and account hint, then the welcome screen opens.

**Shared device**: signing in as someone else replaces the device's local data after saving it aside (`data.progress-sync`); the first screen after sign-in never shows the previous person's data.

**Accessibility**: rows are a list with labelled actions; destructive actions say what they do in text.

**Events**: `account_switch_started`, `account_switch_confirmed`.

## 10. Welcome screen after sign-out

**Purpose**: respect an explicit sign-out; create a guest only on request.

**Content**: "Sign in with Google", "Sign in with Apple" (on iOS), "Play as guest". A guest created here follows section 1 from the create step.

**States**: idle; signing in; creating; error (the messages of section 4).

**Accessibility**: the three actions are equal-weight buttons in a logical order; no auto-focus on a destructive control.

## 11. Error states summary

| Source | Outcome | Screen |
|---|---|---|
| Create | `429`, network, `410 challenge_expired`, `422` | none; identity `pending`; retry with backoff (challenge errors request a fresh challenge) |
| Create | `403 attestation_required` or `attestation_failed` | a calm message on first use: "This version of the game cannot start on this device. Update the app or try again later."; no account details |
| Exchange | `403 account_linked`, `410 *`, `401` | welcome-back screens (section 7) |
| Link | `409 link_conflict` | conflict sheet (section 5) or the pristine toast |
| Resolve | `409 preview_changed`, `503 import_incomplete`, expired | in the sheet (section 5) |
| Recovery | `401`, `403`, `410`, `429` | recovery entry messages (section 6) |
| Any | `401` on a later call while a session was held | one silent re-exchange; if it fails, the start sequence |

## 12. Pending, queue and privacy rules in the client

<!-- PATTERN: pending-event-queue -->
<!-- PURPOSE: record events before an account exists and submit them without trusting the device clock -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: persist/loadQueue -> your device storage; submit -> the HTTP call of the receiving block; the cap comes from OFFLINE_EVENT_QUEUE_MAX; local_event_id uses the platform's random UUID -->
```typescript
type Pending = { localEventId: string; type: string; payload: unknown; clientTs: number };

export function enqueue(q: Pending[], e: Omit<Pending, "localEventId">, cap: number)
    : { queue: Pending[]; dropped: number } {
  if (q.length >= cap) return { queue: q, dropped: 1 };
  return { queue: [...q, { ...e, localEventId: crypto.randomUUID() }], dropped: 0 };
}

export async function drain(q: Pending[], submit: (e: Pending) => Promise<"applied" | "rejected">) {
  let dropped = 0;
  for (const e of q) if ((await submit(e)) === "rejected") dropped += 1; // oldest first; clientTs orders only
  return { dropped };
}
```

- The device secret, recovery code, session token and any provider proof never appear in logs, analytics, crash reports, screenshots-for-support or exports.
- The client reads no advertising identifier at any point (INV-18).
- A web-view's storage is not secure storage: the secret lives in the native secure-storage plugin; if no such plugin exists in a build (web, dev), that build does not issue guest accounts and plays local-only.
