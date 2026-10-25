# Acceptance — Login with Google

Verification checklist Claude Code runs AFTER implementation, BEFORE reporting done. Every item must pass.

## Build & Types

- [ ] `tsc --noEmit` passes with zero errors
- [ ] No `any` types except with explicit justification comment
- [ ] All Zod schemas (or equivalent) validate request/response boundaries

## Database

- [ ] Migration runs successfully on a clean database
- [ ] Migration is idempotent (running twice does not error)
- [ ] `users` table has UNIQUE constraints on `email` and `google_id`
- [ ] `sessions` table has UNIQUE constraint on `token`
- [ ] `sessions.user_id` has ON DELETE CASCADE
- [ ] Partial index on `sessions(token) WHERE expires_at > now()` exists

## Auth Flow

- [ ] `GET /login` or login page renders a "Sign in with Google" button
- [ ] Clicking the button redirects to `accounts.google.com` with correct `client_id`, `redirect_uri`, `scope`, `state`, `response_type=code`
- [ ] CSRF state cookie is set before redirect (httpOnly, secure, sameSite=lax, 5 min TTL)
- [ ] `/auth/callback` validates state param against state cookie
- [ ] `POST /api/auth/google/callback` exchanges code for tokens via Google API
- [ ] ID token is verified (signature, iss, aud, exp, email_verified)
- [ ] New users are created with correct field mapping (email lowercase, domain extracted, role=user)
- [ ] Returning users get `last_login_at` updated, no duplicate rows
- [ ] Session token is 64 hex characters generated via `crypto.randomBytes(32)`
- [ ] Session cookie is set: httpOnly, secure, sameSite=lax, path=/

## Session Management

- [ ] `GET /api/me` returns user data when session is valid
- [ ] `GET /api/me` returns 401 when session is expired, invalid, or missing
- [ ] `POST /api/auth/logout` deletes the session row and clears the cookie
- [ ] Logging out on one device does not affect sessions on other devices
- [ ] Frontend redirects to /login on 401 from /api/me

## Domain Restriction

- [ ] When `ALLOWED_DOMAINS` is empty or unset, all domains are allowed
- [ ] When `ALLOWED_DOMAINS` has entries, only matching email domains can log in
- [ ] Rejected domains receive 403 with error `domain_not_allowed`

## Security

- [ ] Session token never appears in response body, URL, or logs
- [ ] `GOOGLE_CLIENT_SECRET` never appears in frontend bundle or client-accessible code
- [ ] Unverified emails (email_verified=false) are rejected with 403
- [ ] ID tokens with wrong `aud` are rejected
- [ ] Post-login redirect only accepts relative paths (no open redirect)
- [ ] No hardcoded secrets in source code
- [ ] `.env.example` exists with placeholder values for all required env vars

## Events

- [ ] `user.created` event fires on first login (not on returning login)
- [ ] `user.logged_in` event fires on every successful login
- [ ] `user.logged_out` event fires on logout

## Error Handling

- [ ] Invalid/expired Google code returns 401 `google_auth_failed`
- [ ] Unverified email returns 403 `email_not_verified`
- [ ] Blocked domain returns 403 `domain_not_allowed`
- [ ] Google API network failure returns 502 `upstream_error` (not a raw stack trace)
- [ ] All error responses have consistent shape: `{ error: string, message?: string }`

## Tests

- [ ] Unit tests pass for: token verification, user upsert logic, session creation, domain check, redirect validation
- [ ] Integration tests pass for: full login flow (mocked Google), session validation, logout, expired session
- [ ] Concurrent login for same google_id creates one user (upsert, not insert-or-fail)

## Configuration

- [ ] App starts and shows login page with only `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `APP_URL` set
- [ ] `SESSION_DURATION_DAYS` defaults to 30 if unset
- [ ] `ALLOWED_DOMAINS` defaults to allow-all if unset
- [ ] `LOGIN_REDIRECT_PATH` defaults to `/dashboard` if unset
