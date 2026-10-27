# Security — In-App Account Deletion

Provenance tags: **[origin]** = behavior shipped in the origin app (Firebase, client-orchestrated). **[extrapolated]** = SQL-family translation, not run on any stack.

## Threat Model

### 1. Unauthorized deletion of someone else's account

**Impact**: Critical. A stolen session, a forged cross-site request or a shared device lets an attacker erase an account and its data irreversibly.

**Mitigations**:
- **Fresh re-authentication on every deletion**, never "the session is valid, so go ahead". **[origin]** `firebasePort.ts:166` re-authenticates before anything is touched; the provider also enforces a recent sign-in for the identity delete.
- The proof's `sub` must equal the current user's provider subject; otherwise `403 wrong_account`. **[origin]** `auth/user-mismatch` shown as "different account" (`CONTRACT.md:125`).
- Single-use, expiring nonce bound to the session and carried inside the proof; proof `iat` within `ACCOUNT_DELETION_REAUTH_MAX_AGE_SECONDS`. **[extrapolated]**
- The deletion endpoint is a state-changing request authenticated by a cookie: apply the CSRF protection `auth.google-login` uses for its cookie session (SameSite cookie plus anti-CSRF token or header check). **[extrapolated]**
- Rate-limit the challenge and deletion endpoints per session and per IP; return `429 rate_limited`. **[extrapolated]** (the origin maps the provider's `too-many-requests`, `CONTRACT.md:125`).

### 2. Incomplete erasure

**Impact**: High. Data that survives deletion, especially public presence such as a leaderboard row or a friend code that still resolves to a person, contradicts what the dialog and the privacy page promised.

**Mitigations**:
- The erasure registry (`backend.md` Pattern 3) lists every user-owned table; the completeness query plus a test fails the build on an unregistered table.
- Public read paths are enumerated and checked after deletion: leaderboard list, profile-by-id, friend-code lookup, friend lists of other users. Acceptance requires each to return "not found" or omit the user. **[origin]** the profile document and the friend-code entry are deleted in the same batch (`firebasePort.ts:173-177`), and reads of other users' friend lists drop accounts that no longer exist (`account.ts:112`).
- Derived or cached copies (search index, CDN-cached leaderboard, export files, analytics rows keyed by user id) are listed in the registry as erasers or documented as retained. **[extrapolated]**: the origin has no such copies, so it never had to decide.
- Backups, logs and provider-side copies are **not established** by the origin evidence. State a retention period in the privacy page; *decision for the merchant*.

### 3. Half-deleted account

**Impact**: Medium. Content erased, identity alive: the user is signed in to an empty account that the app may silently repopulate, or deletion fails without explanation.

**Mitigations**:
- Identity is destroyed last; every step is safe to re-run (`backend.md` ordering invariants). **[origin]** `firebasePort.ts:159-162,180`. The origin documents re-run recovery but has no test for it; the claim "a re-run finishes it" rests on the code's shape (deleting absent documents is a no-op, a missing profile is handled) and is not verified by a test. Add one in your stack (`partial-failure.feature`).
- `account_deletions` marks the open deletion; while it exists, profile auto-creation is skipped and the client shows "Finish deleting". **[extrapolated]**
- Failed steps are named in `failed_step` and counted in a PII-free metric.

### 4. Deleting the wrong data

**Impact**: High. A delete without an ownership condition can remove another user's friend code, friendship rows or content.

**Mitigations**:
- Every eraser filters by the authenticated user's id; the user id never comes from the request body.
- The friend-code entry is deleted only when it belongs to the user. **[origin]** `firebasePort.ts:175` (`owner.data().uid === uid`).
- Tests run with two users and assert the second user's rows are intact after the first is deleted.

### 5. Leaking secrets or identifiers through the deletion path

**Impact**: Medium. ID tokens, authorization codes and the Apple signing key are sensitive; a log line or a "deleted users" table can re-identify a person who asked to be forgotten.

**Mitigations**:
- Never log or persist ID tokens, authorization codes, nonces, emails or subjects in this path.
- No table keyed by the deleted user's id or email after completion; `account_deletions` cascades away with the user.
- Events and metrics carry provider and outcome only.
- The Apple signing key (direct variant) lives in the secret store, never in client code or the repository.

### 6. Guest account deleted with a session alone or a copied credential

**Impact**: Critical. A guest has no provider to re-authenticate with: the device credential is the account. A stolen session token must not be able to erase it, and anyone who holds the credential can.

**Mitigations** (all **[extrapolated]**; the origin has no guests):
- The proof is the device credential shown again together with a single-use challenge issued to this session (`backend.md` Pattern 1b). The session alone never deletes a guest. This is the same rule `auth.guest-account` applies to link start and recovery codes.
- The credential is looked up by its SHA-256 hash and only among the active `device` credentials of the session's account. An unknown, retired or other account's secret answers the same `401 reauth_required`; the answer never says which case it was.
- The challenge is single use and expires after `ACCOUNT_DELETION_CHALLENGE_TTL_SECONDS`; a replayed challenge answers `401 reauth_required` and changes nothing.
- The challenge and deletion endpoints are rate limited per session and per IP as for the provider proofs (`429 rate_limited`).
- The secret is read from secure storage for this one request; it is never logged, never stored by this block and never echoed.

**Accepted property**: whoever holds the unlocked device holds the guest account, and the platform's screen lock is the only stronger factor. The dialog says the game lives on this device and that deletion cannot be undone. The recovery-code route for a guest without a credential, and its limits, belong to `auth.guest-account` (section 3.9).

## Validation Rules

| Field | Validation | Error |
|---|---|---|
| session | valid, unexpired | `401 no_session` |
| `provider` | one of the user's linked providers (`google`, `apple`), or `guest` for an active guest account | `400 invalid_provider` |
| `id_token` | present; signature, `iss`, `aud`, `exp` valid per `auth.google-login` | `401 reauth_required` |
| `id_token.sub` | equals the user's subject for `provider` | `403 wrong_account` |
| `nonce` | issued to this session, unused, unexpired; equals the token's `nonce` claim (`guest`: the body's `nonce`, there is no token) | `401 reauth_required` |
| `id_token.iat` | within `ACCOUNT_DELETION_REAUTH_MAX_AGE_SECONDS` | `401 reauth_required` |
| `device_secret` | `guest` only; its SHA-256 equals the `secret_hash` of an active `device` credential of the session's account | `401 reauth_required` |
| `authorization_code` | optional; Apple only; forwarded to revocation, never stored | none |
| body size | small fixed limit (tokens only) | `413` |

## Authorization

- Only the signed-in user can delete their own account. There is no admin path in this block. A support-initiated deletion (user wrote in) is a separate, audited operator action and is outside this block.
- Deletion is not available to an unreachable or unconfirmed account: no server contact means no deletion. **[origin]** `account.test.ts:272-280`.

## Secrets Management

| Secret | Storage | Notes |
|---|---|---|
| `APPLE_PRIVATE_KEY` | secret store / environment variable | direct Apple revocation only; never commit; rotate per your key policy |
| Provider client secrets | environment variables | as in `auth.google-login` |
| Guest device secret | the guest's secure storage on the device | sent once in the deletion request body; never logged or stored by this block; the server holds only its hash (`auth.guest-account`) |
| Firebase web API key | build-time config | **[origin]** a public project identifier, not a secret; access is decided by authentication and rules (`CONTRACT.md:123`). Do not treat it as a credential and do not paste it into docs |

## Compliance Notes

- This block does not restate any store's policy text, review deadlines or exemptions, because the origin repository does not contain them. The origin labels its feature with a store guideline number in its own contract; read the current store policy yourself.
- Whether an app-store reviewer accepts an in-app deletion that keeps on-device data, or keeps purchase records, was **not tested** in the origin: Apple's review outcome for that app is unknown. Say plainly in the dialog and privacy page what stays.
- Whether Google Play treats a silently created guest as an account for its deletion policy is not settled by its page. `auth.guest-account` treats guests as in scope on both stores (its section 3.9, a design choice), and the `guest` proof exists so a guest can delete in the app.
- The store listing forms ask for a deletion URL (the origin's Play data-safety import has `PSL_ACCOUNT_DELETION_URL` and `PSL_DATA_DELETION_URL`, both pointing at the privacy page). Whether a URL is mandatory is marked "maybe required" in that form, not decided by the evidence. The privacy page must still describe the in-app path.
