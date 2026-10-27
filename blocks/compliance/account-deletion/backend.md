# Backend Patterns — In-App Account Deletion

> Snippets below are **L3 illustrative** (see `docs/SPEC_GUIDELINES.md` section 6). Every snippet is 30 lines or fewer with 4 markers. Adapt through each `ADAPT` list; do not copy.
>
> Provenance tags used in this file: **[origin]** = behavior shipped in the origin app (Firebase, client-orchestrated). **[extrapolated]** = SQL-family translation, not run on any stack.

## API Endpoints

Paths are examples; the behavior is the contract.

| Method | Path (example) | Auth | Purpose |
|---|---|---|---|
| `POST` | `/api/account/deletion/challenge` | session | Issue a single-use nonce the re-authentication proof must carry **[extrapolated]** |
| `POST` | `/api/account/deletion` | session + proof | Run the deletion; `204` with empty body on success **[extrapolated endpoint, origin flow]** |

### Request: `POST /api/account/deletion`

```json
{
  "provider": "google | apple",
  "id_token": "<ID token from a sign-in the user just completed>",
  "nonce": "<the challenge value the sign-in carried>",
  "authorization_code": "<Apple only, one-time code from that sign-in; optional>"
}
```

For a guest account (`auth.guest-account`) the proof is the device credential and the challenge, not a provider token **[extrapolated]**:

```json
{
  "provider": "guest",
  "device_secret": "<the guest's device credential, read from secure storage>",
  "nonce": "<the value returned by POST /api/account/deletion/challenge>"
}
```

### Responses

| Condition | Status | `error` code | Origin message key |
|---|---|---|---|
| Success | `204` | none | success toast `account.deleted` |
| No valid session | `401` | `no_session` | `expired` |
| `provider` missing or not linked to the user (`guest`: the account is not an active guest) | `400` | `invalid_provider` | none |
| Proof invalid, expired, nonce unknown, replayed or too old (`guest`: device secret unknown, retired or not this account's) | `401` | `reauth_required` | `expired` |
| Proof subject differs from the current user | `403` | `wrong_account` | `wrongAccount` |
| Another deletion for this user is running | `409` | `deletion_in_progress` | none (origin serializes on the client) |
| A step failed; the user is still signed in | `500` | `deletion_incomplete` | `server` |
| Too many attempts | `429` | `rate_limited` | `rateLimited` |

Error bodies carry the code only. Never echo tokens, subjects, emails or table names.

---

## Ordering invariants (normative)

The sequence is fixed because each step depends on the one before it. The origin app's order is: confirm, re-authenticate, erase content, revoke provider tokens, delete identity.

1. **Nothing is destroyed before the proof is valid.** Backing out, a wrong account, a stale or replayed proof all leave every row untouched. **[origin]** `firebasePort.ts:159-166`: "nothing is deleted when the learner backs out".
2. **Content is erased while the identity still exists.** The origin needs the live sign-in to authorize its deletes (its data rules require it). **[origin]** `firebasePort.ts:160-162`. SQL stacks may merge steps 3 and 5 into one transaction (see below).
3. **Revocation needs a fresh credential and a live identity.** The authorization code is one-time and comes from the re-authentication in step 1. Revocation therefore happens before the identity is destroyed. **[origin]** `firebasePort.ts:178-179`.
4. **A revocation failure never keeps the account alive.** Record `revocation = failed`, continue. **[origin]** `firebasePort.ts:178` ("must not keep the account alive").
5. **The identity is destroyed last.** After it is gone the user cannot authenticate a retry, so everything that can fail goes before it. **[origin]** `firebasePort.ts:180`. With `auth.guest-account` the identity is the `users` row (when the account is linked) and then the `accounts` row, in that order and in one transaction; the `accounts` row is the last mutation and its cascades remove the account's credentials, sessions and every table that keys `account_id` to it. **[extrapolated]**
6. **Every step is safe to run again.** Erasing rows that are already gone is not an error. **[origin]** `firebasePort.ts:159-160` ("Run again after a failure, it finds what is left and finishes"); [extrapolated] for the SQL translation.

**Allowed variation [extrapolated]:** when content and identity live in one SQL database, the content erase and the identity delete may run in a single transaction, with revocation placed before the transaction. This removes the "content erased, identity alive" state at the cost of ordering revocation before the commit. If you choose this, keep `account_deletions` (it still records a failed revocation) and keep the same endpoint behavior.

---

## Pattern 1: Re-authentication proof

The proof is an ID token from a sign-in the user completed for this request. All of these must hold, in this order:

1. Verify the token exactly as `auth.google-login` verifies its ID token: signature against the provider's published keys, `iss`, `aud`, `exp`.
2. `sub` equals the signed-in user's provider subject (`users.google_id`, or the Apple link). Otherwise `403 wrong_account`. **[origin]** the same rule is Firebase's `auth/user-mismatch`, mapped to the "different account" message (`CONTRACT.md:125`).
3. The `nonce` claim matches an unused, unexpired challenge issued to this session. Mark it used in the same step. **[extrapolated]**
4. `iat` is no older than `ACCOUNT_DELETION_REAUTH_MAX_AGE_SECONDS`. **[extrapolated]**

Provider-dictated names (concrete): claims `iss`, `aud`, `exp`, `iat`, `sub`, `nonce`. Google `iss` is `https://accounts.google.com` (as in `auth.google-login` fixtures). Apple `iss` is `https://appleid.apple.com` **[extrapolated, from Apple's documentation, not from the origin repo; verify]**. Apple echoes the nonce value the client sent to it; if the client sent a SHA-256 hash of a raw nonce, compare against that hash.

<!-- PATTERN: reauth-proof-verify -->
<!-- PURPOSE: accept a deletion only when the owner just proved they are the owner, once -->
<!-- REFERENCE: runtime=node20+ framework=agnostic language=typescript -->
<!-- ADAPT: `verifyIdToken` is the function already written for auth.google-login (swap in the Apple key set for provider apple); `challenges.consume` is your short-lived single-use store (table, cache, or signed cookie plus used-list); `now()` from your clock abstraction; error classes map to the status table above -->
```typescript
type Proof = { provider: "google" | "apple"; idToken: string; nonce: string; code?: string };

async function verifyReauth(user: User, proof: Proof, maxAgeSec: number): Promise<void> {
  const claims = await verifyIdToken(proof.provider, proof.idToken); // signature, iss, aud, exp
  if (claims.sub !== user.providerSubject(proof.provider)) {
    throw new HttpError(403, "wrong_account");
  }
  const fresh = await challenges.consume(user.sessionId, proof.nonce); // single use
  if (!fresh || claims.nonce !== proof.nonce) {
    throw new HttpError(401, "reauth_required");
  }
  if (now() - claims.iat > maxAgeSec) {
    throw new HttpError(401, "reauth_required");
  }
}
```

### Pattern 1b: Guest proof

A guest has no provider identity, so the proof is possession of the device credential, shown again together with a single-use challenge **[extrapolated]**. All of these must hold, in this order:

1. `provider` is `guest` and the session's account is an active guest (`accounts.kind = guest`); otherwise `400 invalid_provider`.
2. `SHA-256(device_secret)` equals the `secret_hash` of an **active** `device` credential of **this account**. The lookup is by hash (`auth.guest-account` INV-3); an unknown, retired or other account's secret answers `401 reauth_required`, and no field of the answer says which. `wrong_account` does not apply: the session's account is the only subject.
3. The `nonce` matches an unused, unexpired challenge issued to this session; mark it used in the same step (same store as Pattern 1, lifetime `ACCOUNT_DELETION_CHALLENGE_TTL_SECONDS`). A token has no `iat`, so the challenge lifetime is the freshness bound; `ACCOUNT_DELETION_REAUTH_MAX_AGE_SECONDS` does not apply.

<!-- PATTERN: guest-proof-verify -->
<!-- PURPOSE: accept a guest's deletion only when the device credential and a fresh single-use challenge are shown together -->
<!-- REFERENCE: runtime=node20+ framework=agnostic language=typescript -->
<!-- ADAPT: `guestCredentials.findActiveDevice` is the lookup of `auth.guest-account` by (account id, secret hash) over `guest_credentials` with purpose `device` and status `active`; `sha256Hex` is your hash helper; `challenges.consume` is the same single-use store as `reauth-proof-verify`; never log or store `deviceSecret` -->
```typescript
type GuestProof = { provider: "guest"; deviceSecret: string; nonce: string };

async function verifyGuestReauth(account: Account, proof: GuestProof): Promise<void> {
  if (account.kind !== "guest") throw new HttpError(400, "invalid_provider");
  const credential = await guestCredentials.findActiveDevice(account.id, sha256Hex(proof.deviceSecret));
  if (!credential) throw new HttpError(401, "reauth_required"); // unknown, retired or another account's
  const fresh = await challenges.consume(account.sessionId, proof.nonce); // single use
  if (!fresh) throw new HttpError(401, "reauth_required");
}
```

---

## Pattern 2: Ordered, re-runnable deletion

Compose order: **claim → erase content → revoke → delete identity**. The claim makes concurrent and repeated requests safe.

<!-- PATTERN: claim-open-deletion -->
<!-- PURPOSE: allow one running deletion per user and let a failed or abandoned one be retaken -->
<!-- REFERENCE: dialect=postgres orm=raw-sql -->
<!-- ADAPT: `$n` placeholders -> MySQL/SQLite `?`; `ON CONFLICT ... DO UPDATE ... WHERE` -> MySQL `INSERT ... ON DUPLICATE KEY UPDATE` with an IF() on status (no WHERE clause), SQLite supports ON CONFLICT DO UPDATE WHERE; `make_interval(secs => $4)` -> MySQL `INTERVAL ? SECOND`, SQLite `datetime('now', '-' || ? || ' seconds')`; empty result means 409 deletion_in_progress -->
```typescript
const claim = `
  INSERT INTO account_deletions (id, user_id, provider)
  VALUES ($1, $2, $3)
  ON CONFLICT (user_id) DO UPDATE
    SET status = 'requested', provider = EXCLUDED.provider, updated_at = now()
    WHERE account_deletions.status = 'failed'
       OR account_deletions.updated_at < now() - make_interval(secs => $4)
  RETURNING id`;
// zero rows returned: another request holds the deletion -> 409 deletion_in_progress
```

<!-- PATTERN: ordered-erasure -->
<!-- PURPOSE: erase content, revoke, then destroy the identity; any failure leaves the user able to retry -->
<!-- REFERENCE: runtime=node20+ framework=agnostic language=typescript -->
<!-- ADAPT: `claimDeletion` runs the claim SQL above; `erasers.runAll` is Pattern 3; `revokeProviderTokens` must catch its own errors and return a status; `deleteIdentity` removes sessions, provider link and the users row (when one exists) and then the accounts row of `auth.guest-account` in one transaction (the cascade from accounts removes the account_deletions row and every account_id table); `revokeProviderTokens` returns `not_applicable` for provider `guest`; `Proof` becomes the union of the provider proofs and `GuestProof` (Pattern 1b); `stepOf` maps a thrown error to a step name without user content (`content_erase`, `identity_delete`, else `other`) -->
```typescript
async function deleteAccount(user: User, proof: Proof): Promise<void> {
  const rowId = await claimDeletion(user.id, proof.provider);
  try {
    await erasers.runAll(user.id);                          // one transaction, idempotent
    await setStatus(rowId, "content_erased");
    const revocation = await revokeProviderTokens(proof);   // never throws
    await setRevocation(rowId, revocation);
    await deleteIdentity(user.id);                          // last; cascade drops rowId
  } catch (err) {
    await setFailed(rowId, stepOf(err));                    // user stays signed in
    metrics.increment("account.deletion_failed");
    throw new HttpError(500, "deletion_incomplete");
  }
  metrics.increment("account.deleted", { provider: proof.provider });
}
```

After `deleteAccount` returns, invalidate the session cookie in the response (`Set-Cookie` with an expiry in the past, as in `auth.google-login` logout). Emit `account.deleted` with no user identifiers.

### Pattern 2b: Do not recreate a half-deleted account

If login or "load my profile" auto-creates a profile for a user who has none, a user whose deletion failed after the content erase gets a fresh empty profile and a new friend code on the next launch. **[origin, inferred from code]** The origin's profile load creates a missing profile (`firebasePort.ts:228-233`, called at `useAccount.ts:55-57`), and a signed-in user with an erased profile would hit that path; no test in the origin covers it, and the origin accepts it because the user can press Delete again. **[extrapolated fix]**: while an `account_deletions` row exists for the user, profile auto-creation is skipped and `GET /api/me` includes `deletionPending: true`, so the client shows "Finish deleting your account".

---

## Pattern 3: Erasure registry

Every place user data lives is erased by a named eraser. A forgotten table is the main way this block fails in production, so the registry is checked by a test.

<!-- PATTERN: erasure-registry -->
<!-- PURPOSE: list every user-owned table once so none is forgotten and the list is testable -->
<!-- REFERENCE: runtime=node20+ framework=agnostic language=typescript -->
<!-- ADAPT: one entry per table with user data in your schema (profile/leaderboard row, progress snapshot, friendships where the user is owner, friend code registry, ...); tables with a user_id or account_id FK ON DELETE CASCADE can be listed with `cascade: true` and no `run` (the account_id cascade fires when the accounts row goes, last); a block that exposes `deleteAccount(account_id)` (the participant hook named by `auth.guest-account`) is listed with a `run` that calls it; `Tx` is your transaction handle type -->
```typescript
type Eraser = { table: string; cascade?: boolean; run?: (tx: Tx, userId: string) => Promise<void> };

const erasers: Eraser[] = [
  { table: "profiles",        run: (tx, id) => tx.exec("DELETE FROM profiles WHERE user_id = $1", [id]) },
  { table: "study_snapshots", run: (tx, id) => tx.exec("DELETE FROM study_snapshots WHERE user_id = $1", [id]) },
  { table: "friendships",     run: (tx, id) => tx.exec(
      "DELETE FROM friendships WHERE user_id = $1 OR friend_id = $1", [id]) },
  { table: "friend_codes",    run: (tx, id) => tx.exec(
      "DELETE FROM friend_codes WHERE owner_user_id = $1", [id]) },   // ownership check is the WHERE
  { table: "sessions",        cascade: true },
];

async function runAll(userId: string): Promise<void> {
  await db.transaction(async (tx) => {
    for (const e of erasers) if (e.run) await e.run(tx, userId);
  });
}
```

The friend-code entry deletes only rows owned by this user. **[origin]** the origin deletes `friendCodes/{code}` only after checking the entry's `uid` equals the deleting user (`firebasePort.ts:170-175`), so a corrupted profile pointing at someone else's code cannot delete it.

<!-- PATTERN: registry-completeness-query -->
<!-- PURPOSE: find tables with a user_id column that the registry does not cover -->
<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: information_schema is Postgres/MySQL; SQLite -> iterate `pragma_table_info` for each table from sqlite_master; if your owner column is not named user_id, extend the column list (the blocks keyed by account id use `account_id`: add it); compare the result against erasers[].table in a test and fail on any extra table -->
```sql
SELECT c.table_name
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.column_name IN ('user_id', 'owner_user_id', 'friend_id')
  AND c.table_name <> 'account_deletions';
```

---

## Pattern 4: Provider token revocation

### Apple, through Firebase Identity Toolkit (proven in the origin app)

**[origin]** `firebasePort.ts:76-83`. Concrete external contract:

| Element | Value |
|---|---|
| Method and URL | `POST https://identitytoolkit.googleapis.com/v2/accounts:revokeToken?key=<project web API key>` |
| Header | `Content-Type: application/json` |
| Body field `providerId` | `apple.com` |
| Body field `tokenType` | `3` (the token is an authorization code) |
| Body field `token` | the authorization code from the fresh Apple sign-in |
| Body field `idToken` | the signed-in user's current Firebase ID token |
| Success | HTTP 2xx; anything else is a failure to record, not to raise |

The code is one-time and only available from the re-authentication of this request, which is why the re-authentication is not skippable for Apple accounts.

<!-- PATTERN: revoke-apple-identity-toolkit -->
<!-- PURPOSE: revoke the app's Apple tokens with the fresh authorization code, never failing the deletion -->
<!-- REFERENCE: runtime=node20+ framework=agnostic http=fetch-builtin api=identity-toolkit-v2 -->
<!-- ADAPT: apiKey from config (a public project identifier, not a secret); skip the call entirely in emulator/test builds as the origin does; return value feeds account_deletions.revocation -->
```typescript
async function revokeApple(apiKey: string, idToken: string, code: string): Promise<"done" | "failed"> {
  try {
    const res = await fetch(
      `https://identitytoolkit.googleapis.com/v2/accounts:revokeToken?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ providerId: "apple.com", tokenType: "3", token: code, idToken }),
      },
    );
    return res.ok ? "done" : "failed";
  } catch {
    return "failed";
  }
}
```

### Apple, direct (no Firebase) **[extrapolated, from Apple's documentation, not from the origin repo; verify before use]**

| Element | Value |
|---|---|
| Code exchange | `POST https://appleid.apple.com/auth/token`, `grant_type=authorization_code`, `code`, `client_id`, `client_secret` |
| Revoke | `POST https://appleid.apple.com/auth/revoke`, form fields `client_id`, `client_secret`, `token`, `token_type_hint` (`refresh_token` or `access_token`) |
| `client_secret` | a JWT signed **ES256** with the Apple key; claims `iss` (team id), `iat`, `exp`, `aud` = `https://appleid.apple.com`, `sub` (client id) |

Same rules as above: best effort, record the outcome, never block. Google sign-ins have nothing to revoke in the origin flow, so record `revocation = not_applicable`.

---

## Error Handling

- A failure in any step: set `status = failed` and `failed_step`, return `500 deletion_incomplete`, keep the session so the user can press Delete again. **[origin]** a failed delete leaves the learner signed in and shows an error (`useAccount.ts:114-130`).
- The success path is the only place the session is invalidated.
- Log `requestId`, step name and error class. Never log tokens, authorization codes, nonces, emails or subjects.

## Anti-patterns

- **DON'T** delete the identity first and the data second. After the identity is gone nobody can authenticate a retry, and a failure strands the data.
- **DON'T** mark the user `deleted_at` and keep the rows. That hides the account; it does not erase it.
- **DON'T** treat revocation failure as a deletion failure. The user would be unable to delete an account whose provider setup is broken (the origin names this exact case: Apple not configured for revocation, `firebasePort.ts:178`).
- **DON'T** skip re-authentication because the session is valid. A stolen session could then erase the account; the origin re-authenticates every time.
- **DON'T** delete a friend-code registry row by code alone; check it belongs to the user.
- **DON'T** keep a "deleted users" table with the user id or email. Counters and PII-free logs only.
- **DON'T** add a table with a `user_id` column without adding it to the registry or giving it the cascade FK.
