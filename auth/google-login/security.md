# Security — Login with Google

## Threat Model

### T1: CSRF on OAuth Callback

**Attack**: Attacker crafts a URL `https://app.com/auth/callback?code=ATTACKER_CODE&state=xxx` and tricks victim into visiting it. Victim's browser sends the attacker's auth code to the backend, linking the victim's session to the attacker's Google account.

**Impact**: HIGH — account takeover (attacker controls which Google account gets linked)

**Mitigation**:
- Generate cryptographically random `state` parameter (32+ bytes, hex-encoded) before redirecting to Google
- Store `state` in a `sameSite=lax; httpOnly; secure` cookie with 5-minute TTL
- On callback, compare `state` query param with cookie value — reject if mismatch or missing
- Delete the state cookie after validation (single-use)

**Validation rule**: `callback_state === state_cookie` — strict equality, no substring match

### T2: XSS Session Hijack

**Attack**: XSS vulnerability in the app allows attacker to steal the session token and impersonate the user.

**Impact**: HIGH — full account impersonation for session lifetime

**Mitigation**:
- Session cookie: `httpOnly` (JavaScript cannot read it)
- Session cookie: `secure` (HTTPS only)
- Session cookie: `sameSite=lax` (not sent on cross-origin POST)
- Never include the session token in response bodies, URLs, or localStorage
- Never log session tokens

**Validation rule**: Session token MUST only appear in `Set-Cookie` header, nowhere else in the HTTP response.

### T3: Session Fixation

**Attack**: Attacker sets a known session token in the victim's browser before login. After victim logs in, attacker uses the same token.

**Impact**: HIGH — account takeover

**Mitigation**:
- Always generate a new session token server-side on login — never accept client-supplied tokens
- Session token = `crypto.randomBytes(32).toString('hex')` (64 hex chars)
- On login, invalidate any session token that was previously in the cookie (if applicable)

**Validation rule**: Session token is always server-generated, never from client input.

### T4: Unverified Google Email

**Attack**: Attacker creates a Google account with an unverified email address (possible in some edge cases), logs in, and gains access as if they own that email.

**Impact**: MEDIUM — impersonation if app trusts email for identity

**Mitigation**:
- Check `email_verified === true` in the ID token payload
- Reject login with 403 `email_not_verified` if false
- Never use email as sole identity — always pair with `sub` (Google user ID)

**Validation rule**: `id_token.email_verified === true` — boolean strict check, not truthy.

### T5: Open Redirect via Login Flow

**Attack**: Attacker crafts `https://app.com/login?redirect=https://evil.com`. After login, victim is redirected to attacker's site.

**Impact**: MEDIUM — phishing (victim trusts the redirect came from the real app)

**Mitigation**:
- Post-login redirect MUST be a relative path (starts with `/`)
- Validate against allowlist: only paths within the app
- Strip any `redirect` param containing `://`, `//`, or domains
- Default redirect: config `LOGIN_REDIRECT_PATH` (default `/dashboard`)

**Validation rule**: `redirect.startsWith('/') && !redirect.startsWith('//')` — reject everything else.

### T6: ID Token Tampering

**Attack**: Attacker submits a forged or modified ID token to bypass authentication.

**Impact**: HIGH — arbitrary account access

**Mitigation** (external contract dictated by Google OIDC — algorithm and JWKS endpoint are fixed):
- ID token signature algorithm: **RS256** (RSA-SHA256, asymmetric) — Google signs, app verifies with Google's public keys
- Fetch Google's public keys from JWKS endpoint: `https://www.googleapis.com/oauth2/v3/certs` (cache per `Cache-Control` `max-age` header, typically ≥1 hour; respect `kid` from JWT header to pick the right key)
- Discovery document (alternative source of JWKS URL): `https://accounts.google.com/.well-known/openid-configuration`
- Validate all OIDC claims:
  - `iss` ∈ `{"https://accounts.google.com", "accounts.google.com"}` (both forms valid per Google docs)
  - `aud` === `GOOGLE_CLIENT_ID` (exact match)
  - `exp` > now (with ≤5s clock skew tolerance)
  - `azp` === `GOOGLE_CLIENT_ID` when present (authorized party)
  - `email_verified` === `true` (boolean strict)
- Use a well-maintained OIDC/JWT library configured for RS256 + JWKS — never manually parse/verify the signature

**Validation rule**: signature algorithm pinned to RS256; verifier must reject `alg: none`, HS256, or any non-RS256 token. Never trust the `alg` header from the token blindly — pin algorithm at the verifier.

---

## Validation Rules Summary

| Field | Rule | Reject with |
|-------|------|-------------|
| OAuth `state` | Matches cookie, single-use, < 5 min old | Frontend: show error, redirect /login |
| `code` | Non-empty string | 400 `missing_code` |
| ID token `alg` (header) | Pinned to `RS256` at verifier — reject any other algorithm including `none` | 401 `google_auth_failed` |
| ID token signature | Verified against Google JWKS (`https://www.googleapis.com/oauth2/v3/certs`) using `kid` from header | 401 `google_auth_failed` |
| ID token `iss` | `https://accounts.google.com` or `accounts.google.com` | 401 `google_auth_failed` |
| ID token `aud` | Equals `GOOGLE_CLIENT_ID` | 401 `google_auth_failed` |
| ID token `azp` (if present) | Equals `GOOGLE_CLIENT_ID` | 401 `google_auth_failed` |
| ID token `exp` | Not expired (with 5s clock skew tolerance) | 401 `google_auth_failed` |
| ID token `email_verified` | `=== true` (boolean strict, not truthy) | 403 `email_not_verified` |
| `email` | Valid email format, lowercase, non-empty | 401 `google_auth_failed` |
| `domain` | In `ALLOWED_DOMAINS` if configured (non-empty array) | 403 `domain_not_allowed` |
| Post-login redirect | Relative path starting with `/`, no `//` prefix | Use default `LOGIN_REDIRECT_PATH` |

---

## Secrets Management

### Environment Variables (NEVER in code)

| Variable | Purpose | Rotation |
|----------|---------|----------|
| `GOOGLE_CLIENT_ID` | OAuth client identifier | Rotate via Google Cloud Console |
| `GOOGLE_CLIENT_SECRET` | OAuth client secret | Rotate via Google Cloud Console, invalidates old secret |
| `SESSION_SECRET` | (Optional) HMAC key for signing cookies if using signed cookies | Rotate with session invalidation |

### Rules

- `GOOGLE_CLIENT_SECRET` never appears in frontend code, client bundles, logs, or error messages
- Session tokens never appear in URLs, response bodies, or logs
- `.env` files with real secrets never committed — use `.env.example` with placeholder values
- Google OAuth credentials are per-environment (dev/staging/prod separate client IDs)

### Anti-patterns

The following patterns are NEVER acceptable regardless of stack — they violate baseline secret hygiene.

<!-- PATTERN: secret-hygiene-anti-patterns -->
<!-- PURPOSE: Illustrate what NEVER to write — secrets in source/URL/logs/response bodies -->
<!-- REFERENCE: language=typescript -->
<!-- ADAPT: applies to all stacks; equivalent forbidden patterns in other runtimes (e.g., `print()`, response writers, redirect helpers) — the rule is invariant, only the syntax of the violation changes -->

```typescript
// NEVER: secret in source code
const CLIENT_SECRET = "GOCSPX-real-secret-here";

// NEVER: session token in URL
res.redirect(`/dashboard?token=${session.token}`);

// NEVER: log secrets
console.log("Token exchange response:", tokenResponse);

// NEVER: session token in response body
res.json({ user, sessionToken: session.token });
```
