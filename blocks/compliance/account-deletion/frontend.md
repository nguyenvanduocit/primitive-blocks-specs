# Frontend Patterns — In-App Account Deletion

> Snippets below are **L3 illustrative** (see `docs/SPEC_GUIDELINES.md` section 6). 30 lines or fewer, 4 markers each. Component names and test hooks are examples; the behavior is the contract.
>
> Provenance tags: **[origin]** = shipped in the origin app (Vue 3 + Capacitor). **[extrapolated]** = added for the SQL-family translation, not run.

## Reachability (the review-critical part)

- The Delete account control lives in the account card on the Settings screen, a few taps from launch. It is not behind a support link, a web page, or a mailto. **[origin]** `AccountCard.vue:88-107`; the written reply to App Review states the path as "Settings > account card > Delete account".
- It is shown only for a signed-in user whose account was confirmed online (origin status `in`). While the account is `checking` or `offline` the control is absent, because deletion needs the server. **[origin]** `AccountCard.vue:88` (`v-if status === 'in'`) and the test "an account that cannot be reached cannot be deleted from here" (`account.test.ts:272-280`). **[extrapolated]** Consider a one-line note in the offline state ("Connect to delete your account") so a reviewer does not read the absence as a missing feature.
- A signed-out user has no account, so there is nothing to delete; the sign-in card is shown instead.
- The same path is described in the privacy policy page and in the store listing forms. Keep the three in agreement.

## Component Tree

```
SettingsView
  AccountCard                     (existing; signed-in branch)
    DeleteAccountButton           variant danger; disabled while any account call runs
    DeleteAccountDialog           modal confirm: title, body, Cancel, Delete
    DeletionErrorNote             role=alert; empty when the user simply backed out
```

| Component | Responsibility | Props / state |
|---|---|---|
| `DeleteAccountButton` | Opens the dialog | `disabled: boolean` (busy) |
| `DeleteAccountDialog` | States consequences, starts deletion from the confirm click | `onConfirm(): Promise<boolean>`; closes on success or cancel |
| `DeletionErrorNote` | Shows the failure message | `problem: string | null` |

Test hooks **[origin]**: `account-delete` (open), `account-delete-confirm`, `account-delete-cancel`, `account-delete-error`. Reuse these names; the recording script and UI tests refer to them.

## Dialog copy requirements

The confirm dialog is where the user learns what stays and what goes, so it is part of compliance, not decoration. It states:

1. **What is deleted** — profile and leaderboard place, friend code and friend list, progress saved in the account, the sign-in. Name every row of the erasure inventory in `README.md` section 2 that the user can see.
2. **That it cannot be undone.**
3. **That the user will be asked to confirm it is them** (so the provider sheet is not a surprise).
4. **What stays**: per `ACCOUNT_DELETION_WIPE_LOCAL_DATA`. Origin text, default `false`: "Your answers and progress on this device stay." **[origin]** `i18n/account.en.js:22`. If the merchant retains purchase records, say so here or in the privacy page.

Success message **[origin]**: "Your account was deleted. Your progress stays on this device." (`account.en.js:23`). Adjust the second sentence when local data is wiped.

## Pattern 1: The re-authentication must open from the click

Browsers block a popup that is opened after an `await`. The provider SDK must already be loaded, and the first `await` in the click handler must be the re-authentication itself.

<!-- PATTERN: reauth-from-click -->
<!-- PURPOSE: keep the provider popup attached to the user gesture so it is not blocked -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `provider.reauthenticate` is your sign-in wrapper (web popup, or the native system sheet in the app); `preloadProvider()` runs when the account card mounts, not at click time; `api.deleteAccount` calls POST /api/account/deletion; `challenge` comes from POST /api/account/deletion/challenge and must be fetched BEFORE the click (e.g. when the dialog opens) because awaiting it inside the handler loses the gesture -->
```typescript
async function onConfirmClick(): Promise<boolean> {
  // First await is the provider confirmation: nothing may be awaited before it.
  const proof = await provider.reauthenticate({ nonce: prefetchedChallenge.nonce })
    .catch((e) => (isCancelled(e) ? null : Promise.reject(e)));
  if (!proof) return false;                      // backed out: nothing deleted, no error shown

  const result = await api.deleteAccount(proof); // 204 or error code
  return result.ok;
}
```

**[origin]** `firebasePort.ts:143-144` ("The first await is the popup, so it opens from the click") and `firebasePort.ts:218` ("with the SDK loaded, the confirmation popup opens synchronously from the click"); verified by a test that expects the delete call synchronously after the click (`account.test.ts:247-248`). The prefetched challenge is **[extrapolated]**: the origin has no server-issued nonce.

In the native app the same step is the system sheet (Google, or Sign in with Apple on iOS), not a popup. For Apple, keep the returned authorization code and send it with the request; it is what makes revocation possible. **[origin]** `nativeAuth.ts:25`, `firebasePort.ts:154-156`.

## Guest accounts

A guest (`auth.guest-account`) has no provider sheet, so Pattern 1 does not apply to it. **[extrapolated]** The confirm dialog still states what is deleted, that it cannot be undone and what stays, and says that the game lives on this device in place of "you will be asked to confirm it is you". On confirm the client reads the device secret from secure storage, sends it with the prefetched challenge as the `guest` proof (`backend.md` Pattern 1b), and on `204` removes every device copy of the credential as `auth.guest-account` section 3.9 lists them, then follows Pattern 3. A guest whose credential is gone has no session and cannot reach Settings; it uses the recovery-code route of that block.

## Pattern 2: Deletion state and messages

<!-- PATTERN: deletion-state -->
<!-- PURPOSE: one place that serializes account calls and maps failures to messages -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `exclusive` is your queue that runs account calls (sign in, sign out, delete) one at a time; message keys go through your i18n; `forgetSession()` is Pattern 3 -->
```typescript
type Phase = "idle" | "working" | "failed";

async function deleteAccount(): Promise<boolean> {
  if (state.phase === "working" || state.status !== "in") return false;
  state.phase = "working";
  state.problem = null;
  try {
    return await exclusive(async () => {
      const ok = await onConfirmClick();
      if (!ok) { state.phase = "idle"; return false; }   // cancelled or failed
      forgetSession();                                    // success only
      return true;
    });
  } finally {
    if (state.phase === "working") state.phase = "idle";
  }
}
```

Error code to message **[origin]** mapping (`CONTRACT.md:125`, adapted to this block's HTTP codes):

| Server `error` | Message key | Shown |
|---|---|---|
| `wrong_account` | `account.err.wrongAccount` | yes: "confirm with the account you are signed in with" |
| `reauth_required`, `no_session` | `account.err.expired` | yes: sign in again |
| `rate_limited` | `account.err.rateLimited` | yes |
| network failure | `account.err.network` | yes |
| `deletion_incomplete`, anything else | `account.err.server` | yes, and Delete stays available |
| user closed the sheet | none | **no message** (not an error) |

**[origin]** `account.test.ts:260-270`: backing out leaves the user signed in, shows no message for a cancel and the "different account" message for another account, with `busy` released.

## Pattern 3: What the device does after success

<!-- PATTERN: forget-session-after-delete -->
<!-- PURPOSE: leave the device in a clean signed-out state without losing what the merchant chose to keep -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: storage keys are yours; `store.clearOwner()` removes the marker that ties on-device content to an account; `wipeLocal` reads ACCOUNT_DELETION_WIPE_LOCAL_DATA; purchase SDK hook is only needed if a purchase SDK holds the user id -->
```typescript
function forgetSession(): void {
  storage.remove(ACCOUNT_KEY);          // cached identity
  state.profile = null;
  state.status = "out";                 // sign-in button is back
  if (config.wipeLocalData) {
    storage.remove(CONTENT_KEY);        // merchant chose to erase device content too
  } else {
    store.clearOwner();                 // content stays, but belongs to nobody
  }
  toast(t(config.wipeLocalData ? "account.deleted.wiped" : "account.deleted"), "success");
}
```

**[origin]** the cached identity key is removed and the device content stays (`account.test.ts:251-254`), the owner marker is cleared (`AccountCard.vue:46`, `useCloud.ts:151-155`) so a later sign-in merges the device data instead of replacing it (`CONTRACT.md:121`). Origin sign-out also clears the system Google sheet's remembered account in the native app (`firebasePort.ts:212-214`); the origin's delete path does not call that native sign-out, so doing it after deletion is **[extrapolated]**.

Not verified in the origin: whether the purchase SDK is returned to an anonymous user after a deletion (its sign-out does, `CONTRACT.md:168`). Check this when integrating `billing.in-app-purchase`.

## UI/UX States

| State | What the user sees |
|---|---|
| idle | Delete account button (danger style, not colour alone: the label says Delete) |
| confirming | Dialog open |
| working | Button and dialog disabled, a progress indicator; sign-in and sign-out are queued behind it |
| failed | Error note, button enabled again |
| done | Signed-out screen and the success message |
| backed out | Back to idle, no message |

Accessibility: dialog traps focus, default focus on Cancel, the destructive action is a text button of at least 44px height, error note has `role="alert"`.

## Anti-patterns

- **DON'T** make `mailto:` or a web form the only path. The reviewer asks to see deletion in the app.
- **DON'T** fetch configuration, load the SDK or await a challenge between the click and the provider sheet. The popup is blocked; prefetch.
- **DON'T** show a "deleted" toast before the server answered `204`.
- **DON'T** treat closing the provider sheet as an error. It means "I changed my mind".
- **DON'T** offer Delete while the account is unreachable and then fail silently.
- **DON'T** describe a retention you do not apply. The dialog, the privacy page and the store forms must say the same thing about what stays.
