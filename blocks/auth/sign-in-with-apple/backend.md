# Backend Patterns — Sign in with Apple

Provenance: The origin app that this block derives from delegated every item below to Firebase Authentication. The server-side contract here is **extrapolated from Apple's public documentation, not run**. Items marked "confirm" in the table below must be checked against current Apple documentation before shipping.

## API Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `POST` | `/api/auth/apple/native` | none | iOS shell: exchange a native identity token for a session |
| `GET` | `/auth/apple/start` | none | Web: create state + nonce, redirect to Apple |
| `POST` | `/auth/apple/callback` | none (state cookie) | Web: Apple's `form_post` return; creates a session, redirects |
| `POST` | `/api/auth/apple/link` | session | Attach Apple to the signed-in user |

Sessions, `/api/me` and `/api/auth/logout` come from `auth.google-login` unchanged.

### `POST /api/auth/apple/native`

Request (JSON):

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `identity_token` | string | yes | Apple identity token (JWT) from the system sheet |
| `raw_nonce` | string | yes | The unhashed nonce whose SHA-256 hex digest was sent to Apple |
| `authorization_code` | string | no | Accepted and ignored at sign-in; kept in the contract so clients send one shape |
| `display_name` | string | no | Name from the first authorization; sanitized (see Validation) |

Responses: `200 { user }` + `Set-Cookie: session=...` (same cookie rules as `auth.google-login`); `400 missing_identity_token | missing_nonce`; `401 apple_auth_failed`; `409 account_exists_with_different_provider`; `502 upstream_error` (signing keys unreachable).

### `GET /auth/apple/start`

Generates `state` (32 bytes, hex) and a raw nonce (32 bytes, hex), stores both in a pre-auth cookie, redirects (302) to Apple's authorize URL with the parameters below.

### `POST /auth/apple/callback`

Body is `application/x-www-form-urlencoded`: `code`, `id_token`, `state`, optional `user` (JSON string, first authorization only), or `error` when the user cancelled. Success: `302` to `LOGIN_REDIRECT_PATH` + session cookie. Any failure: `302` to `/login?error=<code>`; the page maps the code to a message. No token or secret ever appears in a URL.

### `POST /api/auth/apple/link`

Requires a valid session. Body as `native`. Verifies the token; sets `users.apple_id` on the current user. `409 apple_id_in_use` when another user already holds that `sub`; `409 already_linked` when the current user already has an `apple_id`. Emits `user.identity_linked`.

---

## External Protocol Contract (Apple-dictated, do not change)

The merchant does not choose these values. Provenance column: **repo** = visible in the origin app's code or docs; **Apple docs** = author's knowledge of Apple documentation, MEDIUM confidence, confirm before shipping.

| Item | Value | Provenance |
|------|-------|-----------|
| Identity token format | JWT signed **RS256**; pin the algorithm at the verifier, reject `none` and every non-RS256 `alg` | Apple docs |
| Signing keys | JWKS at `https://appleid.apple.com/auth/keys`; choose the key by the JWT header `kid` | Apple docs |
| `iss` | exactly `https://appleid.apple.com` | Apple docs |
| `aud` | the Apple client id of the requesting app: **iOS bundle id** for native tokens, **Services ID** for web tokens | Apple docs; bundle id as Firebase Apple provider client id is in `firebase/README.md:28` of the origin app |
| `exp` | must be in the future (allow at most 5 s clock skew) | Apple docs |
| `sub` | stable opaque user id, scoped to the developer team; the identity key | Apple docs |
| `nonce` | the value the client sent to Apple. The client sends the **SHA-256 hex digest** of a random raw nonce to Apple; the server receives the **raw** nonce and recomputes the digest | repo for "hash sent to Apple, raw value used for verification" (the origin app `nativeAuth.ts:23`, `firebasePort.ts:128-129`); SHA-256 hex encoding from Apple docs / Firebase guidance, confirm |
| `email` | optional; may be a relay address `...@privaterelay.appleid.com` | Apple docs |
| `is_private_email` | claim present when the email is a relay address; may arrive as boolean **or** the string `"true"` | Apple docs, confirm |
| `email_verified` | may arrive as boolean **or** the string `"true"`; accept both, require true when `email` is present | Apple docs, confirm |
| Name | **not in the identity token**. Native: given by the system sheet; web: in the `user` form field. Only on the **first** authorization of the app by that user | repo (the origin app `nativeAuth.ts:27`, `CONTRACT.md:115`) |
| Web authorize URL | `https://appleid.apple.com/auth/authorize` with `client_id`=Services ID, `redirect_uri`, `response_type=code id_token`, `response_mode=form_post`, `scope=name email`, `state`, `nonce` (the hash). `form_post` is required when `name` or `email` scope is requested | Apple docs |
| Token endpoint | `POST https://appleid.apple.com/auth/token` (form: `client_id`, `client_secret`, `code`, `grant_type=authorization_code`) | Apple docs |
| Revoke endpoint | `POST https://appleid.apple.com/auth/revoke` (form: `client_id`, `client_secret`, `token`, `token_type_hint=refresh_token`) | Apple docs; revoke-on-delete requirement is in the origin app `CONTRACT.md:117` and `firebasePort.ts:70-82` |
| Client secret | a JWT signed **ES256** with the `.p8` key: header `kid`=`APPLE_KEY_ID`; claims `iss`=`APPLE_TEAM_ID`, `sub`=client id, `aud`=`https://appleid.apple.com`, `iat`, `exp` (Apple allows up to about 6 months; this block mints a 10-minute secret per call) | Apple docs |
| Authorization code | single use and short lived (minutes); obtained fresh from a re-authentication right before revoke | repo for "fresh authorization code" (the origin app `firebasePort.ts:144-158`, `:179`); lifetime from Apple docs |

---

## Identity Token Verification

`verifyAppleIdentityToken` is one pipeline: **signature (RS256, JWKS) → issuer → audience → expiry → nonce → claim normalization**. A failure at any step yields the same outward error `apple_auth_failed` (401); the reason goes to server logs without the token.

Signing keys: fetch from the JWKS endpoint, cache, pick by `kid`. On an unknown `kid` refetch once, with a floor on refetch frequency so a forged `kid` cannot make the server hammer Apple. Network failure fetching keys is `502 upstream_error`, not 401.

<!-- PATTERN: apple-identity-token-verify -->
<!-- PURPOSE: Verify an Apple identity token's signature, issuer, audience, expiry and nonce before trusting any claim -->
<!-- REFERENCE: runtime=node20+ language=typescript algorithm=rs256 api=apple-sign-in -->
<!-- ADAPT:
       - `jose` (`createRemoteJWKSet`, `jwtVerify`): any JWT library that pins the algorithm and accepts a JWKS works; Deno 2 uses `jose` via npm: specifier, Bun runs it as is
       - `audiences`: pass `[APPLE_BUNDLE_ID]` for native, `[APPLE_SERVICES_ID]` for web, or both when one endpoint serves both
       - `clockTolerance: 5` (seconds): keep at or below 5 to match auth.google-login
       - `nonceMatches` / `normalizeClaims`: defined in the next two patterns
       - Return shape: swap for your error style (throw, Result type) -->

```typescript
import { createRemoteJWKSet, jwtVerify } from "jose";

const appleKeys = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

export async function verifyAppleIdentityToken(
  token: string, rawNonce: string, audiences: string[],
): Promise<AppleClaims | null> {
  try {
    const { payload } = await jwtVerify(token, appleKeys, {
      algorithms: ["RS256"],
      issuer: "https://appleid.apple.com",
      audience: audiences,
      clockTolerance: 5,
    });
    if (!nonceMatches(payload.nonce, rawNonce)) return null;
    return normalizeClaims(payload);
  } catch {
    return null; // log the reason server-side, never the token
  }
}
```

<!-- PATTERN: apple-nonce-compare -->
<!-- PURPOSE: Bind the identity token to this sign-in attempt by comparing the SHA-256 hex digest of the raw nonce with the token's nonce claim in constant time -->
<!-- REFERENCE: runtime=node20+ language=typescript crypto=node-builtin -->
<!-- ADAPT:
       - `node:crypto` (`createHash`, `timingSafeEqual`): edge runtimes use Web Crypto `subtle.digest("SHA-256")` and an XOR-accumulator compare because Web Crypto has no `timingSafeEqual`
       - Digest encoding is hex, lowercase: keep it identical to what the client sends to Apple (see frontend.md); if your client library base64-encodes the digest, change both sides together, never one -->

```typescript
import { createHash, timingSafeEqual } from "node:crypto";

export function nonceMatches(claim: unknown, rawNonce: string): boolean {
  if (typeof claim !== "string" || rawNonce.length === 0) return false;
  const expected = Buffer.from(createHash("sha256").update(rawNonce).digest("hex"));
  const actual = Buffer.from(claim);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
```

<!-- PATTERN: apple-claims-normalize -->
<!-- PURPOSE: Turn the raw token payload into a typed shape, tolerating Apple's boolean-or-string flags and an absent email -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: `JWTPayload` type comes from the JWT library in use; add fields only if the app needs them; keep the "true" string handling -->

```typescript
type AppleClaims = {
  sub: string; email: string | null; emailIsPrivate: boolean;
};
const isTrue = (v: unknown) => v === true || v === "true";

export function normalizeClaims(p: { sub?: string; email?: unknown; email_verified?: unknown; is_private_email?: unknown }): AppleClaims | null {
  if (!p.sub) return null;
  const email = typeof p.email === "string" ? p.email.trim().toLowerCase() : null;
  if (email && !isTrue(p.email_verified)) return null; // an email that Apple does not vouch for is rejected
  return { sub: p.sub, email, emailIsPrivate: isTrue(p.is_private_email) };
}
```

---

## Resolving the User

Run inside one database transaction. Order matters: **find by `apple_id` first; only then consider email**.

1. Look up `users.apple_id = sub`. Found: update `last_login_at`; set `name` only if it is currently `NULL` and a sanitized name was sent. Never overwrite a stored name.
2. Not found and `email` is present: look up `users.email = email`. Found: respond `409 account_exists_with_different_provider`; create and link nothing. (This is the same outcome as the origin app's `auth/account-exists-with-different-credential` message, `account.ts:138`.)
3. Otherwise insert a user: `apple_id`, `email` (may be `NULL`), `email_is_private`, `name` (may be `NULL`), `domain = NULL`, `role = user`.
4. Concurrent first sign-ins for the same `sub` must yield one user row (upsert on `apple_id`), and two sessions.

<!-- PATTERN: apple-user-resolve -->
<!-- PURPOSE: Upsert the Apple user atomically, refuse silent email-based linking, and store the first-authorization name once -->
<!-- REFERENCE: dialect=postgres language=typescript orm=raw-sql -->
<!-- ADAPT:
       - `tx.one(sql, params)`: your driver's single-row query; Drizzle/Prisma users express the same three statements with their builders inside a transaction
       - `ON CONFLICT (apple_id) DO UPDATE`: MySQL uses `ON DUPLICATE KEY UPDATE`; SQLite supports ON CONFLICT as written
       - `$1` placeholders: MySQL uses `?`
       - `newId()`: your unique_id generator (uuid4 string for SQLite, `gen_random_uuid()` default for Postgres)
       - `COALESCE(name, $2)`: keep; it is the "set name once" rule -->

```typescript
export async function resolveAppleUser(tx: Tx, c: AppleClaims, displayName: string | null) {
  const known = await tx.one(`SELECT id FROM users WHERE apple_id = $1`, [c.sub]);
  if (known) {
    return tx.one(
      `UPDATE users SET last_login_at = now(), updated_at = now(), name = COALESCE(name, $2)
       WHERE id = $1 RETURNING *`, [known.id, displayName]);
  }
  if (c.email) {
    const clash = await tx.one(`SELECT id FROM users WHERE email = $1`, [c.email]);
    if (clash) throw new AuthError(409, "account_exists_with_different_provider");
  }
  return tx.one(
    `INSERT INTO users (id, apple_id, email, email_is_private, name, domain, role, last_login_at)
     VALUES ($1, $2, $3, $4, $5, NULL, 'user', now())
     ON CONFLICT (apple_id) DO UPDATE SET last_login_at = now()
     RETURNING *`, [newId(), c.sub, c.email, c.emailIsPrivate, displayName]);
}
```

After resolving: create the session exactly as `auth.google-login` does (new server-generated token, 64 hex chars, `expires_at` from `SESSION_DURATION_DAYS`), emit `user.created` only for an inserted row and `user.logged_in` always.

---

## Web Callback Handling

1. Read the form body. If `error` is present (for example the user cancelled) → redirect `/login?error=apple_cancelled`, no session.
2. Compare `state` to the pre-auth cookie value, strict equality. Missing cookie or mismatch → redirect `/login?error=apple_auth_failed`. Delete the pre-auth cookie in every outcome (single use).
3. Take the raw nonce from the pre-auth cookie and run `verifyAppleIdentityToken(id_token, rawNonce, [APPLE_SERVICES_ID])`.
4. If `user` is present, parse it as JSON defensively (invalid JSON means no name), compose `display_name` from first and last name, sanitize.
5. `resolveAppleUser`, create session, `302` to `LOGIN_REDIRECT_PATH` with `Set-Cookie: session=...`.

The pre-auth cookie is `httpOnly; secure; path=/auth/apple; max-age=300` and **`SameSite=None`**. This differs from the `lax` state cookie in `auth.google-login` on purpose: Apple returns by a cross-site `POST`, and a `lax` cookie is not sent on a cross-site `POST`. The **session** cookie keeps the `auth.google-login` attributes (`httpOnly; secure; sameSite=lax; path=/`).

---

## Revoke on Delete

Apple expects an app that creates accounts with Sign in with Apple to revoke the user's authorization when the account is deleted (the origin app `CONTRACT.md:117`, citing App Store 5.1.1(v), and `firebasePort.ts:70-82`). `compliance.account-deletion` owns the deletion; this block exposes two capabilities for it to call, in this order:

1. `verifyAppleReauthentication({ userId, identityToken, rawNonce })`: verifies the token like sign-in and requires `sub === users.apple_id` of `userId`. A valid token for another Apple account → `403 wrong_account` (the origin app maps this to `wrongAccount`, `account.ts` and `CONTRACT.md:117`). Nothing is deleted when this fails.
2. `revokeAppleAuthorization({ authorizationCode, platform })` → `{ ok: boolean }`. Exchanges the fresh code at the token endpoint, then revokes the returned refresh token. `platform` picks the client id: native → `APPLE_BUNDLE_ID`, web → `APPLE_SERVICES_ID`.

Revocation is **best effort**: a failure is logged, emitted as `user.apple_revoked { ok: false }`, and must **not** keep the account alive (the origin app swallows the failure, `firebasePort.ts:179`). The authorization code is single use and short lived, so the client re-authenticates with Apple immediately before the deletion request; the server never stores Apple refresh tokens.

<!-- PATTERN: apple-client-secret -->
<!-- PURPOSE: Mint the short-lived ES256 client secret that Apple's token and revoke endpoints require -->
<!-- REFERENCE: runtime=node20+ language=typescript algorithm=ecdsa-sha256 api=apple-sign-in -->
<!-- ADAPT:
       - `jose` (`SignJWT`, `importPKCS8`): any library that signs ES256 (ECDSA P-256 + SHA-256) from a PKCS8 PEM
       - `cfg.privateKey`: the `.p8` content from a secret store; some env systems flatten newlines, restore them before import
       - `"10m"`: any lifetime up to Apple's maximum; short avoids storing or caching the secret
       - `clientId`: bundle id (native) or Services ID (web) -->

```typescript
import { SignJWT, importPKCS8 } from "jose";

export async function appleClientSecret(
  cfg: { teamId: string; keyId: string; privateKey: string }, clientId: string,
): Promise<string> {
  const key = await importPKCS8(cfg.privateKey, "ES256");
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: cfg.keyId })
    .setIssuer(cfg.teamId)
    .setSubject(clientId)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt()
    .setExpirationTime("10m")
    .sign(key);
}
```

<!-- PATTERN: apple-revoke-authorization -->
<!-- PURPOSE: Exchange a fresh authorization code for a refresh token and revoke it, so the app disappears from the user's Apple sign-in list -->
<!-- REFERENCE: runtime=node20+ language=typescript http=fetch-builtin api=apple-sign-in -->
<!-- ADAPT:
       - `fetch` and `URLSearchParams`: Node 20, Bun, Deno 2 have both built in; use your HTTP client if it adds timeouts
       - Add a request timeout (5 to 10 s); a hung call must not block account deletion
       - Never log `client_secret`, `code` or `refresh_token` -->

```typescript
const form = (o: Record<string, string>) => ({
  method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams(o),
});

export async function revokeAppleAuthorization(cfg: AppleCfg, clientId: string, code: string) {
  const client_secret = await appleClientSecret(cfg, clientId);
  const tok = await fetch("https://appleid.apple.com/auth/token",
    form({ client_id: clientId, client_secret, code, grant_type: "authorization_code" }));
  if (!tok.ok) return { ok: false };
  const { refresh_token } = await tok.json();
  const res = await fetch("https://appleid.apple.com/auth/revoke",
    form({ client_id: clientId, client_secret, token: refresh_token, token_type_hint: "refresh_token" }));
  return { ok: res.ok };
}
```

---

## Error Handling

All error bodies: `{ error: string, message?: string }`, as in `auth.google-login`.

| Condition | Status | `error` |
|-----------|--------|---------|
| Missing `identity_token` | 400 | `missing_identity_token` |
| Missing `raw_nonce` | 400 | `missing_nonce` |
| Any token verification failure (signature, alg, iss, aud, exp, nonce, unverified email) | 401 | `apple_auth_failed` |
| Email belongs to a user with another identity | 409 | `account_exists_with_different_provider` |
| Link: `sub` held by another user | 409 | `apple_id_in_use` |
| Link: current user already has Apple | 409 | `already_linked` |
| Re-authentication with a different Apple account | 403 | `wrong_account` |
| Apple signing keys unreachable | 502 | `upstream_error` |

Logging: log the failure reason class (for example `aud_mismatch`), the `sub` hash prefix at most, never the token, the raw nonce, the authorization code or the client secret.

---

## Anti-patterns

- **DON'T** treat `email` as identity. Key everything on `sub` (`apple_id`); the email can be absent, relayed, or changed.
- **DON'T** link an Apple sign-in to an existing user because the emails match. Linking requires a signed-in session (`/api/auth/apple/link`).
- **DON'T** require `name`, `email` or `domain` to be non-null for an Apple user. Do not invent a fake email to satisfy a NOT NULL column.
- **DON'T** overwrite a stored `name` with an empty or missing value on later sign-ins; Apple will not send it again.
- **DON'T** decode the identity token and trust its claims without signature verification, and never trust the `alg` header: pin RS256.
- **DON'T** send the raw nonce to Apple or the hash to your server; the hash goes to Apple, the raw value goes to your backend.
- **DON'T** resolve a Capacitor plugin object from a promise on the client (see `frontend.md`).
- **DON'T** store the Apple `.p8` key, client secrets, refresh tokens or authorization codes in the database, logs, or the client bundle.
