# Frontend Patterns — Sign in with Apple

Provenance: the native-sheet patterns (provider list per platform, single session, cancel handling, name capture, plugin-proxy trap) come from the origin app and ran in production there. The web redirect and the call to this block's own backend endpoints are extrapolated; the origin app does not offer Apple on the web and its backend was Firebase.

## Component Tree

| Component | Responsibility | Props / inputs |
|-----------|---------------|----------------|
| `SignInProviders` | Decide which provider buttons to show for the current platform and config; render Google (from `auth.google-login`) and Apple | none (reads platform + `APPLE_SIGN_IN_PLATFORMS`) |
| `AppleSignInButton` | Start the platform's flow; show `idle / opening / verifying` states; map results to messages | `onSignedIn(user)`, `onAccountExists()` |
| `LinkAppleAction` | In account settings: run the native or web flow against `/api/auth/apple/link` | `currentUser` |

Platform detection (`web`, `ios`, `android`) lives in one function; no component reads the platform directly.

## Platform Rules

| Platform | Apple flow | Provider list |
|----------|-----------|---------------|
| iOS app (native shell) | System Sign in with Apple sheet, token posted to `POST /api/auth/apple/native` | Google + Apple |
| Web | Full-page navigation to `GET /auth/apple/start` (no popup, no client-side Apple script) | Google + Apple if `web` in `APPLE_SIGN_IN_PLATFORMS` |
| Android app | Not offered unless `android` is listed in config | Google |

The origin app shipped iOS = Google + Apple, Android = Google, web = Google only (`nativeAuth.ts:17`, `CONTRACT.md:109`). Web and Android Apple are config choices of this block, not shipped behavior.

<!-- PATTERN: providers-by-platform -->
<!-- PURPOSE: Single source of truth for which sign-in buttons a platform shows -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT:
       - `platform`: Capacitor `Capacitor.getPlatform()` returns `web | ios | android`; other shells (Tauri, React Native) map their own platform API to the same three values
       - `applePlatforms`: read from the exposed config (`APPLE_SIGN_IN_PLATFORMS`), served by the backend or build-time env
       - Keep the function pure so tests pass the platform in -->

```typescript
export type Platform = "web" | "ios" | "android";
export type Provider = "google" | "apple";

/** Google everywhere; Apple only where the config lists the platform. */
export const providersFor = (platform: Platform, applePlatforms: readonly Platform[]): readonly Provider[] =>
  applePlatforms.includes(platform) ? ["google", "apple"] : ["google"];
```

---

## Native iOS Flow

1. Generate a random raw nonce (32 random bytes, hex) and its SHA-256 hex digest.
2. Open the system sheet with scopes `name` and `email` and the **digest** as the nonce. Apple receives only the digest.
3. The sheet returns an identity token, an authorization code, and (first authorization only) the user's name.
4. Post `{ identity_token, raw_nonce, authorization_code, display_name }` to `/api/auth/apple/native`. The raw nonce travels only to your own backend, over TLS.
5. The native layer must **not** create a second session of its own. The shipped app asked the plugin for tokens only (`skipNativeAuth: true`, `nativeAuth.ts:66`) and let the app sign in itself, so one session exists and every request uses it. With this block the one session is the backend's cookie session.

Some plugins generate the nonce and return the raw value (the origin app read it from the plugin result, `nativeAuth.ts:39`); others take a nonce from the caller. Either is fine as long as the invariant holds: **Apple gets the hash, the backend gets the raw value**.

<!-- PATTERN: apple-nonce-pair -->
<!-- PURPOSE: Produce the raw nonce kept by the client and the SHA-256 hex digest that is sent to Apple -->
<!-- REFERENCE: language=typescript crypto=web-crypto -->
<!-- ADAPT:
       - Skip this pattern when the native plugin generates the nonce and returns the raw value
       - `crypto.getRandomValues` / `crypto.subtle`: available in WebViews and browsers over secure contexts; React Native needs a crypto polyfill
       - Hex encoding must match the backend's `nonceMatches` (lowercase hex) -->

```typescript
const toHex = (b: Uint8Array) => [...b].map((x) => x.toString(16).padStart(2, "0")).join("");

export async function newNoncePair(): Promise<{ raw: string; hash: string }> {
  const raw = toHex(crypto.getRandomValues(new Uint8Array(32)));
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw));
  return { raw, hash: toHex(new Uint8Array(digest)) };
}
```

### The plugin proxy trap

Capacitor plugin objects are proxies that answer **every** property, `then` included. A promise that resolves with the plugin object directly makes the runtime call a native `then`, which does not exist, and the sign-in fails on the device while unit tests still pass. Always return the plugin wrapped in a plain object. The origin app hit this on Android and added a regression test that fails on the unwrapped form (playbook B-web-server-login section 3.3; `nativeAuth.ts:56-59`; `test/native-auth.test.ts`).

<!-- PATTERN: native-apple-sheet -->
<!-- PURPOSE: Open the system Sign in with Apple sheet, return plain token data, keep the plugin proxy out of promise results -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT:
       - Module name and method: the shipped app used `@capacitor-firebase/authentication` with `signInWithApple({ skipNativeAuth: true })` and read `credential.idToken`, `credential.nonce`, `credential.authorizationCode`, `user.displayName`; another plugin has other method and field names, map them to `NativeApple`
       - Dynamic `import()`: keeps the web bundle from evaluating native code; keep it lazy
       - Wrapping the plugin as `{ plugin }`: required for any Capacitor plugin, harmless elsewhere -->

```typescript
export type NativeApple = {
  identityToken: string;
  rawNonce: string;
  authorizationCode?: string;
  displayName?: string; // first authorization only
};

const load = () => import("<native-apple-plugin>").then((m) => ({ plugin: m.AppleSignIn }));

export async function nativeAppleSignIn(): Promise<NativeApple> {
  const { plugin } = await load(); // never `await load()` returning the bare plugin
  let r;
  try {
    r = await plugin.signIn({ skipNativeAuth: true });
  } catch (e) {
    throw appleError(e);
  }
  const c = r.credential;
  if (!c?.idToken || !c.nonce) throw appleError({ code: "invalid_credential" });
  return {
    identityToken: c.idToken, rawNonce: c.nonce,
    authorizationCode: c.authorizationCode || undefined, displayName: r.user?.displayName || undefined,
  };
}
```

### Cancellation is not an error

Closing the sheet must leave the screen as it was, with no message. The native layer reports it differently per platform (the origin app matched the text "cancel" and Apple's authorization error code 1001, `nativeAuth.ts:46-54`).

<!-- PATTERN: apple-cancel-detect -->
<!-- PURPOSE: Map a closed sheet to a silent "cancelled" outcome and everything else to a generic failure -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: error text and code shape depend on the plugin and iOS version; extend the regex with what the plugin actually throws, and keep the unknown case as a visible failure -->

```typescript
export function appleErrorKind(e: unknown): "cancelled" | "failed" {
  const { message } = (e ?? {}) as { message?: unknown };
  const text = typeof message === "string" ? message : "";
  return /cancel/i.test(text) || /error 1001\b/.test(text) ? "cancelled" : "failed";
}
```

### Keep the first-authorization name until the server confirms

Apple will not send the name again. If the request to the backend fails after the sheet succeeded (network, 5xx), the retry must carry the same name, so hold it in memory until a `200`. The origin app stored the name on the Firebase user right after sign-in and treated a failed store as losing only the name (`firebasePort.ts:136-139`).

<!-- PATTERN: keep-first-name -->
<!-- PURPOSE: Do not lose the one-time name when the backend call fails and the user retries -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `postApple` is the app's HTTP client call to POST /api/auth/apple/native; store `pendingName` in the app's state container instead of a module variable if you use one; do not persist it to disk -->

```typescript
let pendingName: string | undefined;

export async function signInWithApple() {
  const t = await nativeAppleSignIn();
  pendingName = t.displayName ?? pendingName;
  const res = await postApple({
    identity_token: t.identityToken, raw_nonce: t.rawNonce,
    authorization_code: t.authorizationCode, display_name: pendingName,
  });
  if (res.ok) pendingName = undefined;
  return res;
}
```

Residual risk: if the app is killed between the sheet and a successful response, the name is lost. Offer a way to set the display name in account settings.

---

## Web Flow

The button is a plain link (or form submission) to `GET /auth/apple/start`. The backend creates state and nonce, so the browser holds no secret and no Apple script is needed. After approval Apple posts to the backend, which redirects back signed in or to `/login?error=<code>`. The login page reads `error` and maps it to a message.

---

## UI/UX Patterns

| State | Behavior |
|-------|----------|
| Idle | Apple button next to the Google button, equal size and prominence; use Apple's official button artwork or native control and label ("Sign in with Apple") rather than a custom-drawn mark |
| Opening / verifying | Button disabled with a spinner; the other provider button also disabled so two sign-ins cannot race |
| Cancelled | Back to idle, **no toast, no error** |
| `401 apple_auth_failed` / network / 5xx | Generic message "Sign-in failed, try again"; keep `pendingName` |
| `409 account_exists_with_different_provider` | Message: "An account with this email already exists. Sign in with Google, then link Apple in Settings." Offer the Google button |
| `409 apple_id_in_use` (link) | "This Apple ID is already used by another account." |
| User without name | Show a neutral label wherever `name` is `null`; never show the relay address as a name |
| Relay email | Show the address as stored; do not label it an error; mark it private in account settings if the UI lists emails |
| Empty / signed-out | Standard login screen from `auth.google-login` |

Accessibility: both buttons have accessible names, are keyboard reachable, and keep 44x44 pt tap targets. State is never conveyed by color alone.

## Native Shell and the Session Cookie

The native request to `/api/auth/apple/native` returns the same `Set-Cookie: session` as web sign-in, and the shell then calls `/api/me` with it. Whether a WebView's origin lets the `sameSite=lax` cookie ride along to the API depends on the shell configuration (same-site API origin, or an HTTP plugin that shares the cookie jar). This was **not** exercised in the origin app (it used Firebase tokens, not cookies). Decide the shell's API origin first; if cross-site is unavoidable, record that decision as its own block rather than putting the session token in a response body.

## Anti-patterns

- **DON'T** open a web popup or redirect inside a WebView for the iOS app; use the system sheet.
- **DON'T** let the native plugin create its own session in addition to the backend session (two sources of truth). Ask it for tokens only.
- **DON'T** resolve a promise with the Capacitor plugin object.
- **DON'T** show an error when the user closes the sheet.
- **DON'T** import the native plugin at module top level; web builds must never evaluate it.
- **DON'T** assume `name` or `email` exist after sign-in.
- **DON'T** send the nonce digest to your backend or the raw nonce to Apple.
- **DON'T** show the Apple button on a platform outside `APPLE_SIGN_IN_PLATFORMS`.
