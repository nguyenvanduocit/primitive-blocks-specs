# Acceptance Checklist — In-App Account Deletion

Claude Code runs this checklist after implementation, before reporting done. Items marked **(manual)** need a person or a physical device; list them in the final report as not run if you cannot do them.

## Database

- [ ] Migration runs successfully on a clean database (`account_deletions` created)
- [ ] Migration is idempotent (running twice does not error)
- [ ] `account_deletions.user_id` is UNIQUE and a foreign key to `accounts.id` (the project's account or user id) with ON DELETE CASCADE, so a guest account can hold an open deletion
- [ ] On SQLite: foreign key enforcement is enabled per connection, so the cascade really runs
- [ ] Every table with a column naming a user (`user_id`, owner or friend column) is either covered by an eraser in the registry or has a cascading foreign key (the completeness query from `backend.md` Pattern 3 returns nothing unaccounted for)
- [ ] The registry completeness check is a test that fails when a new user-owned table is added without an eraser

## Endpoints

- [ ] `POST /api/account/deletion/challenge` returns a single-use nonce with a TTL of `ACCOUNT_DELETION_CHALLENGE_TTL_SECONDS`
- [ ] `POST /api/account/deletion` returns `204` with an empty body on success
- [ ] No session returns `401 no_session`
- [ ] Invalid, expired, replayed or too-old proof returns `401 reauth_required`
- [ ] Proof whose `sub` differs from the current user returns `403 wrong_account` and nothing is deleted
- [ ] Unknown or unlinked `provider` returns `400 invalid_provider`; `guest` on an account that is not an active guest returns the same
- [ ] **(when `auth.guest-account` is installed)** `provider: guest` with the device credential and a fresh challenge returns `204` (the `guest_valid` proof); a wrong secret, a retired credential, another account's secret, a missing secret and a replayed challenge each return `401 reauth_required` and delete nothing
- [ ] A concurrent second request returns `409 deletion_in_progress`
- [ ] Failure of a step returns `500 deletion_incomplete`, the session stays valid
- [ ] Error bodies contain only the code (no tokens, subjects, emails, table names)
- [ ] Challenge and deletion endpoints are rate limited (`429 rate_limited`)

## Ordering and Re-runnability

- [ ] Nothing is deleted before the proof is verified (test: wrong account, stale proof, replayed nonce each leave all rows)
- [ ] Order observed in a test: erase content, then revoke, then delete identity
- [ ] Content erase is one transaction: an injected failure leaves all rows in place
- [ ] Identity delete is the last mutation
- [ ] **(when `auth.guest-account` is installed)** The identity step deletes the `users` row (when one exists) and then the `accounts` row in one transaction; for a guest only the `accounts` row exists; the `accounts` cascade removes credentials, sessions, link attempts and every `account_id` table
- [ ] Revocation failure is recorded and does not fail the deletion
- [ ] Injected failure after the content erase: the user is still signed in, the row is `failed`, and a second request with a new proof returns `204`
- [ ] Erasers are idempotent: running them on already-erased data raises no error
- [ ] A stale open deletion (older than `ACCOUNT_DELETION_STALE_AFTER_SECONDS`) can be retaken
- [ ] While an `account_deletions` row exists, login or profile load does not create a new profile or friend code, and `GET /api/me` reports `deletionPending`

## Erasure Completeness

- [ ] Profile and leaderboard row deleted
- [ ] Progress snapshot deleted
- [ ] The user's friend list deleted
- [ ] The user's friend code deleted, and only when owned by the user (test with `friend_code_owned_by_someone_else`)
- [ ] Rows in other users' friend lists that point at the deleted user are removed (or readers omit them): after deletion the other user's list does not show them
- [ ] Sessions and provider link deleted, `users` row deleted
- [ ] **(when `auth.guest-account` is installed)** The `accounts` row is deleted after the `users` row; later exchanges of the old device credential find only a tombstone with reason `deleted` and no account id
- [ ] Derived or cached copies (search index, cached leaderboard, exports, analytics keyed by user id) are either erased or listed as retained in the privacy page
- [ ] A bystander user's rows are unchanged (compare `other_user` before and after)

## Public Presence

- [ ] Leaderboard list no longer contains the user
- [ ] Profile-by-id returns not found
- [ ] Friend-code lookup returns not found
- [ ] Cached leaderboard or profile responses expire or are invalidated, so the user does not reappear

## Security

- [ ] Re-authentication happens on every deletion; a valid session alone is not enough
- [ ] Proof verification reuses the ID-token verification of `auth.google-login` (signature, `iss`, `aud`, `exp`) and additionally checks `sub`, `nonce` and `iat`
- [ ] Nonce is single use (second use fails)
- [ ] CSRF protection applies to the deletion endpoint
- [ ] Tokens, authorization codes and nonces never appear in logs or events (grep test output)
- [ ] No table keeps the deleted user's id or email after completion
- [ ] `account.deleted` and `account.deletion_failed` events carry no user identifiers
- [ ] No hardcoded secrets; the Apple private key (if used) comes from the secret store
- [ ] The guest device secret never appears in logs, events or the database of this block (grep test output; the server compares hashes only)

## Provider Revocation

- [ ] For an Apple account, a revocation request is made with the authorization code from the fresh sign-in (Identity Toolkit shape in `fixtures/reauth-proofs.json`, or the direct Apple variant)
- [ ] For a provider with nothing to revoke, `revocation` is `not_applicable`
- [ ] The revocation call is skipped in test and emulator builds
- [ ] **(manual)** One real Apple revocation was exercised against the real provider at least once. Until then, mark revocation "not verified live" in the report

## Frontend and Reachability

- [ ] Delete account is reachable from Settings by a signed-in user from the account card on the Settings screen, with no link out of the app and no contact with support
- [ ] The control is absent when the account is signed out, still being checked, or unreachable
- [ ] The confirm dialog lists what is deleted, that it cannot be undone, that the user must confirm identity, and what stays (consistent with `ACCOUNT_DELETION_WIPE_LOCAL_DATA`)
- [ ] Re-authentication opens as the first asynchronous step of the confirm click (web popup not blocked); the challenge is fetched before the click
- [ ] Closing the provider sheet shows no error and deletes nothing
- [ ] A different account shows the "different account" message
- [ ] Success: signed-out state, success message, cached identity removed, ownership marker cleared, on-device content kept or wiped as configured
- [ ] Account calls (sign in, sign out, delete) run one at a time; sign-out issued during deletion waits
- [ ] The control meets the touch-target and focus rules of your design system; destructive state is not conveyed by colour alone
- [ ] Hooks `account-delete`, `account-delete-confirm`, `account-delete-cancel`, `account-delete-error` exist (or the project's equivalents are documented)

## Documents Agree

- [ ] The privacy policy names the in-app path (Settings, account, Delete account), what is deleted, what stays on the device, what the purchase processor keeps, and the backup and log retention
- [ ] The store listing forms that ask about account deletion or data deletion say the same things as the privacy policy
- [ ] The secondary email route, if offered, is described as an addition to the in-app route

## Verification Artifact (manual)

The reviewer-facing evidence. The origin app needed it after an "Information Needed" App Review round that asked for a screen recording from a physical device showing registration or login and account deletion.

- [ ] **(manual)** Recording made on a **physical device**, not a simulator, on a current OS release
- [ ] **(manual)** The recording starts from launching the app from the Home Screen or launcher
- [ ] **(manual)** It shows sign-in (or registration), then Settings, then Delete account, the confirm dialog, the provider re-authentication, and the signed-out result
- [ ] **(manual)** A throwaway account is used. A real account's data is deleted for real
- [ ] **(manual)** The recording contains no personal information: other apps, the owner's email in a provider sheet, other people's names on a live leaderboard. Check by sampling frames before sending; the origin's early takes exposed a personal chat, an email address in a provider sheet and other people's names
- [ ] **(manual)** If a biometric prompt falls back to a passcode, the wait is acceptable but the passcode is never visible
- [ ] **(manual)** Original recordings are removed from the device gallery and download folders after trimming and compressing
- [ ] **(manual)** The written reply or review notes state the in-app path in one sentence and attach the clip
- [ ] **(manual)** The final report lists the reviewer's verdict as "not yet known" until it arrives. This checklist cannot establish acceptance

## Configuration

- [ ] All keys in `README.md` section 7 exist with the documented defaults
- [ ] `ACCOUNT_DELETION_WIPE_LOCAL_DATA` default matches the dialog text
- [ ] Missing Apple revocation settings (direct variant) disable revocation with a recorded `failed`, they do not fail startup or the deletion

## Type Safety & Build

- [ ] `tsc --noEmit` passes (or the stack's type check)
- [ ] All unit tests and integration tests pass
- [ ] Every scenario in the three `.feature` files has a test
- [ ] Zero hardcoded secrets
