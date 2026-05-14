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

**Mitigation**:
- Verify ID token using Google's public keys (JWKS at `https://www.googleapis.com/oauth2/v3/certs`)
- Validate all claims: `iss` (issuer), `aud` (audience matches GOOGLE_CLIENT_ID), `exp` (not expired)
- Use a well-maintained JWT library — never manually parse/verify

**Validation rule**: Use `google-auth-library` or equivalent — verify signature + claims in one call.

---

## Validation Rules Summary

| Field | Rule | Reject with |
|-------|------|-------------|
| OAuth `state` | Matches cookie, single-use, < 5 min old | Frontend: show error, redirect /login |
| `code` | Non-empty string | 400 `missing_code` |
| ID token `iss` | `https://accounts.google.com` or `accounts.google.com` | 401 `google_auth_failed` |
| ID token `aud` | Equals `GOOGLE_CLIENT_ID` | 401 `google_auth_failed` |
| ID token `exp` | Not expired (with 5s clock skew tolerance) | 401 `google_auth_failed` |
| ID token `email_verified` | `=== true` | 403 `email_not_verified` |
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

```
// NEVER: secret in source code
const CLIENT_SECRET = "GOCSPX-real-secret-here";

// NEVER: session token in URL
res.redirect(`/dashboard?token=${session.token}`);

// NEVER: log secrets
console.log("Token exchange response:", tokenResponse);

// NEVER: session token in response body
res.json({ user, sessionToken: session.token });
```
