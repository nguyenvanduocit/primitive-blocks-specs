# Acceptance — Sign in with Apple

Verification checklist Claude Code runs AFTER implementation, BEFORE reporting done. Every item must pass. This block ships no `tests/` directory: derive unit and integration tests from the five `.feature` files and the fixtures.

Prerequisite: `auth.google-login` is implemented and its own acceptance still passes after this block's migration.

## Build & Types

- [ ] Type check passes with zero errors (`tsc --noEmit` or the stack's equivalent)
- [ ] No `any` types except with an explicit justification comment
- [ ] Request bodies for `native`, `callback` and `link` are validated at the boundary

## Database

- [ ] Migration runs on a clean database that already has the `auth.google-login` schema
- [ ] Migration is idempotent (running twice does not error)
- [ ] `users.apple_id` exists and is UNIQUE; many rows with `NULL` are allowed
- [ ] `users.email_is_private` exists, NOT NULL, default false
- [ ] `users.google_id`, `email`, `name`, `domain` accept `NULL`
- [ ] Inserting a user with neither `google_id` nor `apple_id` fails (CHECK constraint)
- [ ] `sessions` is unchanged and still cascades on user delete
- [ ] Existing Google users and their sessions survive the migration unchanged

## Native Flow

- [ ] `POST /api/auth/apple/native` with a valid token and matching raw nonce returns 200 and sets the session cookie
- [ ] New user: `apple_id` = token `sub`, `name` from `display_name`, `domain` null, role `user`
- [ ] Returning user: no new row, `last_login_at` updated, stored name unchanged
- [ ] `display_name` fills a null name once and never overwrites an existing one
- [ ] Token without `email` creates a user with null email, name and domain
- [ ] Concurrent first sign-ins for one `sub` create exactly one user

## Web Flow

- [ ] `GET /auth/apple/start` redirects to Apple's authorize URL with `response_type=code id_token`, `response_mode=form_post`, `scope=name email`, `state`, and `nonce` equal to the SHA-256 hex digest of the raw nonce
- [ ] The raw nonce never appears in the redirect URL
- [ ] The pre-auth cookie is `httpOnly`, `secure`, `SameSite=None`, 5 minute lifetime
- [ ] `POST /auth/apple/callback` accepts a form body, verifies `state` against the cookie, deletes the cookie in every outcome
- [ ] The `user` form field populates `name` on first authorization; invalid JSON in it never fails sign-in
- [ ] State mismatch, missing cookie and Apple `error` all redirect to `/login?error=...` with no session
- [ ] The session cookie keeps the `auth.google-login` attributes (`httpOnly; secure; sameSite=lax; path=/`)

## Token Verification

- [ ] Signature verified with Apple's published keys chosen by `kid`; algorithm pinned to RS256
- [ ] `alg: none` and HS256 tokens are rejected
- [ ] `iss` must equal `https://appleid.apple.com`
- [ ] `aud` must equal `APPLE_BUNDLE_ID` on the native endpoint and `APPLE_SERVICES_ID` on the web callback; a token for another app is rejected
- [ ] Expired token rejected (5 s skew at most)
- [ ] `nonce` claim must equal the lowercase hex SHA-256 of `raw_nonce`; mismatch and empty raw nonce are rejected
- [ ] `email_verified` accepts boolean `true` and string `"true"`; an email without verification is rejected
- [ ] Every verification failure returns 401 `apple_auth_failed` with no detail about which check failed
- [ ] Unreachable signing-key endpoint returns 502 `upstream_error`
- [ ] Unknown `kid` triggers at most one rate-limited key refetch

## Linking & Email

- [ ] Apple email equal to an existing user's email (different identity) returns 409 `account_exists_with_different_provider` and creates or links nothing
- [ ] `POST /api/auth/apple/link` requires a session, sets `apple_id` on the current user only, and emits `user.identity_linked`
- [ ] Link returns 409 `apple_id_in_use` / `already_linked` in the described cases
- [ ] A relay address is stored as given with `email_is_private` true and never used for matching
- [ ] No code path requires `email`, `name` or `domain` for an Apple user
- [ ] `ALLOWED_DOMAINS` is not applied to Apple sign-ins

## Revoke on Delete

- [ ] `verifyAppleReauthentication` succeeds only for a valid token whose `sub` equals the user's `apple_id`; otherwise 403 `wrong_account` and nothing is deleted
- [ ] `revokeAppleAuthorization` exchanges the code at the token endpoint, then revokes the refresh token, with `client_id` = bundle id (ios) or Services ID (web)
- [ ] The client secret is an ES256 JWT with `iss` team id, `kid` key id, `sub` client id, `aud` `https://appleid.apple.com`, short expiry
- [ ] A revoke failure returns `{ ok: false }`, is logged and emitted, and does not block the deletion
- [ ] `compliance.account-deletion` (or the app's deletion flow) calls both capabilities for users with an `apple_id`
- [ ] No Apple refresh token or authorization code is persisted

## Frontend

- [ ] Provider list comes from one function of platform and `APPLE_SIGN_IN_PLATFORMS`; Apple button shows only where listed
- [ ] iOS uses the system sheet, never a web popup; Apple receives only the nonce digest, the backend only the raw nonce
- [ ] The native layer creates no session of its own
- [ ] The native plugin is imported lazily and never resolved from a promise as a bare object (regression test exists)
- [ ] Closing the sheet shows no message and sends no request
- [ ] The first-authorization name is kept in memory across a failed attempt and sent on the retry
- [ ] 409 `account_exists_with_different_provider` shows the "sign in with Google, then link" message
- [ ] A user with null name or email renders without errors anywhere `currentUser` is displayed

## Security

- [ ] Session token never appears in a response body, URL, or log
- [ ] No Apple private key, client secret, identity token, raw nonce, authorization code or refresh token in source, logs, URLs or client bundle
- [ ] `.env.example` lists `APPLE_BUNDLE_ID`, `APPLE_SERVICES_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `APPLE_SIGN_IN_PLATFORMS` with placeholders only
- [ ] No code path writes `apple_id` from a sign-in request unless creating the row or holding a valid session for that user

## Events

- [ ] `user.created` fires only on insert, `user.logged_in` on every sign-in, both with `provider: "apple"`
- [ ] `user.identity_linked` fires on link; `user.apple_revoked` fires on every revoke attempt with `ok`

## Error Handling

- [ ] 400 `missing_identity_token`, 400 `missing_nonce`, 401 `apple_auth_failed`, 403 `wrong_account`, 409 (`account_exists_with_different_provider`, `apple_id_in_use`, `already_linked`), 502 `upstream_error`
- [ ] All error responses have the shape `{ error: string, message?: string }`

## Tests

- [ ] Unit tests pass for: token verification (each rejection reason in `identity-token-verification.feature`), nonce compare, claims normalization (boolean and string flags, absent email), user resolution (new, returning, collision, name set once), client-secret claims, provider list per platform, cancel detection
- [ ] Integration tests pass for every scenario in `native-sign-in.feature`, `identity-token-verification.feature`, `web-sign-in.feature`, `account-linking.feature` and `apple-revocation.feature`, with Apple stubbed using `fixtures/`
- [ ] Verification result of each external-contract item marked "confirm" in `backend.md` is recorded in the implementation report

## Manual (cannot be automated; list in the report)

- [ ] Apple developer account: App ID with Sign in with Apple capability; entitlement present in the iOS project
- [ ] Web only: Services ID, verified domain, return URL registered
- [ ] Revoke only: Sign in with Apple key created, `.p8` stored in the secret store
- [ ] A real-device sign-in on iOS and, if offered, a real browser sign-in on web (these were not run when the block was written)
