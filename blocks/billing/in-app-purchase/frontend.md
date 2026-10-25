# Frontend Patterns — In-App Purchase: One-Time Unlock

> Code snippets are L3 illustrative TypeScript with the four markers per `docs/SPEC_GUIDELINES.md` section 6. They show state logic without a UI framework; map `Ref`-style state to your framework's reactive primitive. The behavior (WHAT) is in the prose.
>
> The pure rules (`freeItemIds`, `keepPlayable`, `purchaseProblem`) and the `PurchasesPort` interface are in `backend.md`. This file covers state, the gate wrapper, store-call sequencing, and the paywall.

## Component tree

```
App shell
 ├── (content screens) --- call gate.playable(ids) at every entry
 ├── PaywallSheet            mounted once at the shell, driven by purchases state
 │     ├── headline + what unlocking adds + free count
 │     ├── Buy button        label "Unlock for <store price>"
 │     ├── Restore purchases always visible
 │     └── Close             dismisses, buys nothing
 └── (optional) Settings "Unlock" row --- opens the same sheet
```

| Unit | Responsibility | Interface |
|---|---|---|
| `purchases` state holder | owns `pro`, `unlocked`, paywall state, serialization of store calls | `playable(ids)`, `openPaywall()`, `closePaywall()`, `buy()`, `restore()`, `retryOffer()`, readable state |
| `PaywallSheet` | renders state; no business logic | reads `offer`, `offerState`, `busy`, `problem`, `nothingToRestore`; calls `buy`, `restore`, `retryOffer`, `closePaywall` |
| Gate callers | every entry that selects content | pass candidate ids, use the returned list |

The sheet is mounted **once**, at the shell, and shown by state; screens never mount their own copy.

## 1. The gate (single choke point)

`playable(ids)` filters candidates through `keepPlayable` and, if the caller asked for something and nothing survived, opens the paywall as a side effect. It returns the kept list in every case.

<!-- PATTERN: gate-choke-point -->
<!-- PURPOSE: one function every content entry calls; opens the paywall only when the learner actually hit locked content -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `unlocked`/`openPaywall` -> your reactive state and sheet controller; the caller list (start, open one item, review misses, more-like-this, setup form) -> the content entries of your app, each must call this function before it builds a session -->
```typescript
function playable(ids: readonly string[]): string[] {
  const kept = keepPlayable(ids, freeIds, unlocked());
  if (ids.length > 0 && kept.length === 0) openPaywall();
  return kept;
}

// Callers (shape only):
function startSession(candidates: string[], size: number): boolean {
  const pool = playable(candidates);   // gate BEFORE cutting to size
  if (pool.length === 0) return false; // paywall is already open
  begin(pool.slice(0, size));
  return true;
}
```

Rules:

- **Gate before truncation.** A request for 10 items from a pool with 4 free items yields a session of 4, not an empty one, and not 10.
- **Empty request does not open the paywall.** `ids.length > 0` is part of the condition.
- **The paywall opens only from a gate call or an explicit buy entry**, never from start-up code.
- **Resume is not gated.** Resuming a stored session calls no gate.
- **Difficulty and other attributes never reach the gate**; it sees ids only.

## 2. Serialize store calls

Configure, log in/out, offer, buy, and restore share one SDK user. Run them one at a time.

<!-- PATTERN: serialize-store-calls -->
<!-- PURPOSE: prevent interleaved SDK calls (for example a log-in racing a purchase) from corrupting the store user -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: none for the queue; keep one queue instance per store port -->
```typescript
let queue: Promise<unknown> = Promise.resolve();

const exclusive = <T>(fn: () => Promise<T>): Promise<T> => {
  const run = queue.then(fn);
  queue = run.catch(() => undefined); // a failure must not block the next call
  return run;
};
```

## 3. Buy and restore

One function runs both. It blocks a second tap, makes sure the store is configured, maps failures, and updates `pro` from the answer.

<!-- PATTERN: act-buy-restore -->
<!-- PURPOSE: run buy or restore with a busy guard, lazy store start, quiet cancel, and a mapped error -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: state setters -> your reactive primitives; `ensureStarted` -> configure-once logic that retries after a failure (stay false until the port's start succeeds) -->
```typescript
async function act(kind: "buy" | "restore", call: () => Promise<Reply<boolean>>) {
  if (busy) return false;
  busy = kind; problem = null; nothingToRestore = false;
  try {
    if (!(await ensureStarted())) { problem = "network"; return false; }
    const r = await exclusive(call);
    if (!r.ok) {
      const p = purchaseProblem(r.code);
      problem = p === "cancelled" ? null : p; // cancel is silent
      return false;
    }
    pro = r.value;
    if (kind === "restore" && !r.value) nothingToRestore = true;
    return r.value;
  } finally {
    busy = null; // always release, also on throw
  }
}
```

After `pro` becomes true, from a purchase, a restore, or a store-pushed update, the paywall closes and the learner gets one confirmation toast. A cancelled purchase shows nothing.

## 4. Store user follows the account

At start-up the store is configured with the account uid when signed in, anonymous otherwise. When the account changes, switch the store user; do not reconfigure.

<!-- PATTERN: store-user-follows-account -->
<!-- PURPOSE: keep one entitlement per account across devices, and a fresh anonymous user after sign-out -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `onAccountChange` -> your auth state subscription; call `identify` only after the first successful `start` (start already reads the current uid) -->
```typescript
onAccountChange((uid: string | null) => {
  void exclusive(async () => {
    if (!started) return; // start() reads the uid itself
    const r = await port.identify(uid);
    if (r.ok) pro = r.value;
  });
});
```

## UI/UX patterns

| State | UI |
|---|---|
| Store inactive | No paywall rendered anywhere; no Unlock entry |
| `offerState = loading` | Price placeholder; Buy disabled; Restore usable |
| `offerState = ready` | Buy "Unlock for <store price>" |
| `offerState = none` | No Buy button; text that the product is unavailable; Restore stays |
| `offerState = failed` | Message "could not reach the store" with Try again (reloads the offer) |
| `busy` | Buy and Restore disabled, progress indicator on the tapped one |
| `problem` set | One-line alert (`role=alert`) in the sheet; sheet stays open |
| `nothingToRestore` | Inline text "no purchase found" |
| Success | Sheet closes, one confirmation toast, the locked item the learner tapped now opens |
| Cancelled | Silent |

Paywall copy: title, what unlocking adds, the free count and the total ("N of M are free"; counts are always greater than 1), Buy, Restore, Close. Localize every string, including each `err.<problem>`.

## Styling and accessibility

- The paywall is a full-height sheet; Close is always reachable.
- Interactive controls meet the platform's minimum touch target (extrapolated: the source project documents a 44px minimum for its onboarding flow, not for the paywall).
- Alert text uses an alert role so screen readers announce a failed purchase.
- Provide stable test hooks on: the sheet, Buy, Restore, price loading, product unavailable, offer failed, Try again, error alert, restore-none, Close.

## Anti-patterns

| DON'T | Why |
|---|---|
| Read the plugin object from a promise directly | Capacitor's proxy answers `then`; carry it in `{ p: plugin }` (see `backend.md`) |
| Call the SDK from components | All store access goes through the port so tests can fake it |
| Disable Restore when the learner "has no purchase" | Restore must be visible always; the store decides whether anything restores |
| Treat `cancelled` as an error toast | The learner chose to cancel; show nothing |
| Close the sheet because a buy call returned | Close only when `pro` is true; a failed call leaves it open |
| Let two taps start two purchases | The busy guard is part of the contract |
| Call the gate during start-up | Gate calls happen on learner actions, so the paywall cannot appear at launch |

## Known limitation (read from code, not tested)

`pro` starts false. A gate call that happens before the first entitlement read finishes sees the learner as not owning the unlock, and may open the paywall for an owner. In the source project the read starts at launch and a learner action takes longer than the read; if your entries can fire at start-up (deep links, restored sessions), hold gate calls until the first read settles or fails. An owner who starts the app offline is a case the source project did not test.
