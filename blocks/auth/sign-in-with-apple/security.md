# Security — Sign in with Apple

Session rules are inherited from `auth.google-login` `security.md` (T2 XSS session hijack, T3 session fixation) and apply unchanged: the session token is server-generated (32 random bytes, 64 hex chars), set only in a `httpOnly; secure; sameSite=lax; path=/` cookie, and never appears in a body, URL, or log. This file covers what Apple adds.

Provenance: The origin app delegated token verification to Firebase Authentication, so the verification threats below are **extrapolated** from Apple's public documentation and have not been exercised on a server of this block's design. Algorithm, issuer, audience and endpoint values are Apple-dictated (see `backend.md`, "External Protocol Contract"; confirm against current Apple documentation).

## Threat Model

### T1: Forged or mis-targeted identity token

**Attack**: An attacker submits a token they minted, a token signed with a different algorithm (`none`, HS256), a token issued by Apple for a *different* app (valid signature, wrong audience), or an expired token.

**Impact**: HIGH — arbitrary account access, or access via a token that was never meant for this app.

**Mitigation**:
- Pin the signature algorithm to **RS256**; verify with Apple's published keys (`https://appleid.apple.com/auth/keys`), selecting the key by the JWT header `kid`. Reject `alg: none` and any non-RS256 token.
- Require `iss` === `https://appleid.apple.com`.
- Require `aud` to be one of the expected client ids: `APPLE_BUNDLE_ID` (native) or `APPLE_SERVICES_ID` (web). A token with a valid Apple signature but another app's `aud` is the main real-world forgery path; exact match only.
- Require `exp` in the future, with at most 5 s clock skew.
- Use a maintained JWT/OIDC library; never hand-parse or hand-verify the signature.
- One outward error (`apple_auth_failed`) for every verification failure, so responses do not reveal which check failed.

**Validation rule**: all of signature, `iss`, `aud`, `exp`, `nonce` pass, or the request creates nothing.

### T2: Token replay without nonce binding

**Attack**: An attacker obtains a valid identity token (from a log, a proxy, a malicious or compromised app on the same device) and presents it to the backend.

**Impact**: HIGH — session for the victim's account while the token is unexpired.

**Mitigation**:
- The client generates a random raw nonce per attempt and sends only its **SHA-256 hex digest** to Apple; Apple embeds that value in the token's `nonce` claim.
- The backend receives the **raw** nonce with the token, recomputes the digest, and compares it to the claim in constant time. A stolen token without its raw nonce is useless.
- Web flow: the backend generates the nonce itself and keeps the raw value in the pre-auth cookie, so the token is bound to the browser that started the flow.
- Never log the raw nonce or the token.

**Residual risk (MEDIUM)**: an attacker who captures **both** the token and the raw nonce (same TLS-terminating channel) can replay within the token's lifetime. Hardening not built in this block: a server-issued, single-use nonce (`GET` a challenge, store its digest with a short TTL, delete on use). Add it if the threat model includes hostile networks beyond TLS.

**Validation rule**: `claim_nonce === lowercase_hex(sha256(raw_nonce))`, constant-time compare; empty raw nonce is a failure.

### T3: Account takeover through email-based linking

**Attack**: An attacker signs in with an Apple ID whose email claim is `victim@example.com`. A backend that "merges by email" would hand over the victim's Google-created account.

**Impact**: HIGH — full takeover of an existing account.

**Mitigation**:
- Identity is `apple_id` (`sub`), never the email.
- If the Apple email equals an existing user's email and that user has no matching `apple_id`, respond `409 account_exists_with_different_provider` and create or link nothing.
- Linking happens only from an authenticated session (`POST /api/auth/apple/link`): the user proves control of the existing account first, then proves control of the Apple identity.
- Reject a token that carries `email` without `email_verified` true (boolean `true` or string `"true"`).

**Email handling rules** (relay addresses, `email_is_private = true`):
- Store the address as given; never replace it with a guess of the "real" email.
- Never use it for matching against other users.
- Mail sent to a relay address only reaches the user if the sending domain/address is registered in Apple's private email relay configuration (confirm in current Apple documentation); `messaging.transactional-email` must account for that.
- `email` may be absent: no flow may require it.

**Validation rule**: no code path writes `users.apple_id` from a sign-in request unless the row is being created, or the request carries a valid session for that exact user.

### T4: CSRF and cross-site `form_post` on the web callback

**Attack**: An attacker causes the victim's browser to post an attacker-controlled `code` / `id_token` to `/auth/apple/callback`, signing the victim into the attacker's account (login CSRF).

**Impact**: HIGH — the victim then stores data in an account the attacker controls.

**Mitigation**:
- `GET /auth/apple/start` creates `state` (32 random bytes, hex) and a raw nonce, stored in a pre-auth cookie: `httpOnly; secure; path=/auth/apple; max-age=300`.
- Apple returns by a cross-site `POST`, which a `SameSite=Lax` cookie would not accompany. The pre-auth cookie therefore uses `SameSite=None` (with `secure`). This is deliberately different from `auth.google-login`, whose redirect returns by `GET`.
- On callback: strict equality of the posted `state` and the cookie value; delete the cookie in every outcome (single use); verify the posted `id_token` with the cookie's raw nonce.
- The `user` form field (name, email) is **untrusted browser input**: used only as a display name after sanitizing, never for identity or email matching.

**Validation rule**: `callback_state === cookie_state`, no substring match, missing cookie rejects.

### T5: Apple authorization survives account deletion

**Attack / failure**: The account is deleted in the app but Apple still lists the app as authorized for that Apple ID, or the revoke step is skipped. Not an attacker scenario: a compliance and trust failure that can block App Store review.

**Impact**: MEDIUM — store rejection, user-visible stale authorization.

**Mitigation**:
- `compliance.account-deletion` calls, in order: `verifyAppleReauthentication` (token must belong to the same `apple_id`; otherwise `403 wrong_account` and nothing is deleted), then `revokeAppleAuthorization` with the authorization code from that fresh re-authentication.
- Revocation is best effort: failure is logged and emitted (`user.apple_revoked { ok: false }`) but does not keep the account alive (matches the origin app, `firebasePort.ts:179`).
- Do not store refresh tokens or authorization codes; the code is single use and short lived, so use it immediately.

---

## Validation Rules Summary

| Field | Rule | Reject with |
|-------|------|-------------|
| `identity_token` | Non-empty string | 400 `missing_identity_token` |
| `raw_nonce` | Non-empty string | 400 `missing_nonce` |
| Token `alg` (header) | Pinned to RS256 at the verifier | 401 `apple_auth_failed` |
| Token signature | Valid against Apple JWKS, key chosen by `kid` | 401 `apple_auth_failed` |
| Token `iss` | `https://appleid.apple.com` | 401 `apple_auth_failed` |
| Token `aud` | In the expected client-id set for the endpoint | 401 `apple_auth_failed` |
| Token `exp` | In the future (5 s skew) | 401 `apple_auth_failed` |
| Token `nonce` | Equals lowercase hex SHA-256 of `raw_nonce` | 401 `apple_auth_failed` |
| Token `sub` | Non-empty string | 401 `apple_auth_failed` |
| Token `email` | If present: verified (true or `"true"`); lowercased | 401 `apple_auth_failed` |
| Email collision | Existing user with that email and a different identity | 409 `account_exists_with_different_provider` |
| `display_name` / `user` field | Trim, strip control characters, max 200 chars; empty becomes absent | Ignore the field, do not fail sign-in |
| Web `state` | Equals pre-auth cookie, single use, under 5 min | Redirect `/login?error=apple_auth_failed` |
| Link: `sub` held elsewhere | `apple_id` UNIQUE | 409 `apple_id_in_use` |
| Post-login redirect | Relative path starting with `/`, no `//` (as in `auth.google-login` T5) | Use `LOGIN_REDIRECT_PATH` |

---

## Secrets Management

### Environment Variables (NEVER in code)

| Variable | Purpose | Rotation |
|----------|---------|----------|
| `APPLE_PRIVATE_KEY` | Content of the Sign in with Apple `.p8` key; signs the ES256 client secret | Create a new key in the Apple developer account, deploy it, then revoke the old key |
| `APPLE_KEY_ID` | Identifier of that key (`kid` of the client secret) | Changes with the key |
| `APPLE_TEAM_ID` | Developer team id (`iss` of the client secret) | Not secret in itself; keep in config |
| `APPLE_BUNDLE_ID` / `APPLE_SERVICES_ID` | Expected `aud` values | Fixed by the Apple app registration |

### Rules

- The `.p8` key is downloadable from Apple once; keep it in the secret store, never in the repository, the client bundle, logs or error messages.
- Client secrets are minted per call, short lived (10 minutes), and never persisted.
- Identity tokens, raw nonces, authorization codes and refresh tokens never appear in logs, URLs, or error bodies.
- `.env.example` lists the variable names with placeholders only.
- Use separate Apple registrations (bundle id / Services ID) per environment where the Apple account allows it.

### Anti-patterns

<!-- PATTERN: apple-secret-hygiene-anti-patterns -->
<!-- PURPOSE: Illustrate what NEVER to write — Apple key material and tokens in source, URL, logs, or response bodies -->
<!-- REFERENCE: language=typescript -->
<!-- ADAPT: applies to all stacks; the forbidden patterns map to `print()`, response writers and redirect helpers in other runtimes — the rule is invariant, only the syntax of the violation changes -->

```typescript
// NEVER: private key in source code
const APPLE_KEY = "-----BEGIN PRIVATE KEY-----...";

// NEVER: trust claims without verifying signature, issuer, audience, nonce
const claims = JSON.parse(atob(identityToken.split(".")[1]));
await signInAs(claims.email);

// NEVER: link by email
const user = await db.findUserByEmail(claims.email) ?? await db.createUser(claims);

// NEVER: log tokens or nonces
console.log("apple sign-in", { identityToken, rawNonce });

// NEVER: session token in a redirect URL
res.redirect(`/dashboard?token=${session.token}`);
```
