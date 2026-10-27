# Backend Patterns - Guest Account

> Snippets are **L3 illustrative** (see `docs/SPEC_GUIDELINES.md` section 6): at most 30 lines, four markers, adapt through each `ADAPT` list, do not copy. Paths are examples; the behaviour is the contract. The data model and flows are in `README.md` sections 2 and 3.
>
> Provenance: every endpoint, order of checks and algorithm below is a **design choice** of this block unless a platform page is cited; nothing here has been run on stacks A, B or C.

## API Endpoints

| Method | Path (example) | Auth | Purpose |
|---|---|---|---|
| `POST` | `/api/guest/challenge` | none | Issue a proof-of-work challenge |
| `POST` | `/api/guest` | none, challenge proof | Create a guest account (README 3.1) |
| `POST` | `/api/guest/session` | device secret in the body | Exchange the secret for a session (README 3.2) |
| `POST` | `/api/guest/recover` | recovery code in the body | Recover on a new device (README 3.6) |
| `POST` | `/api/account/recovery-code` | guest session + device secret | Create or replace the recovery code; the code is returned once |
| `POST` | `/api/account/link/start` | guest session + device secret | Start a link attempt, return the nonce |
| `POST` | `/api/account/link` | guest session + provider proof | Attach the credential to the same account |
| `POST` | `/api/account/link/resolve` | guest session | Resolve a conflict (keep existing or keep guest) |
| `GET` | `/api/account` | any session | Return `{ account_id, kind, linked_at, server_now }` |

All times in responses are server instants; `server_now` accompanies every payload a client may show a countdown for (time contract).

### Create: request and response

```json
{
  "creation_request_id": "<random, at least 128 bits, base64url>",
  "challenge_id": "<from the challenge response>",
  "pow_counter": "429",
  "attestation": { "platform": "ios | android", "token": "<attestation object or integrity token>", "key_id": "<iOS only>" },
  "platform": "ios | android",
  "app_version": "1.4.0",
  "age_screen": "of_age | under_age"
}
```

`platform` is `ios` or `android`: a web view has no secure credential storage, so any other value answers `400 invalid_request`. `attestation` is optional unless `GUEST_ATTESTATION_MODE` is `required`; a client that cannot attest sends `{ "platform": "...", "unavailable": true }`. `age_screen` is required in `mixed` mode only. `201` body: `{ account_id, kind: "guest", linked_at: null, credential: { secret }, session: { token, expires_at }, server_now }`.

### Responses (all endpoints)

| Condition | Status | `error` code | Notes |
|---|---|---|---|
| Created, or replayed within the window | `201` | none | A replay returns the same `account_id` and a new secret |
| Malformed body, unknown platform | `400` | `invalid_request` | |
| Credential or recovery code unknown | `401` | `credential_invalid` | No reason is given |
| Attestation required and absent | `403` | `attestation_required` | |
| Attestation present and invalid | `403` | `attestation_failed` | |
| Credential retired by a link | `403` | `account_linked` | Body: `provider` hint is not given |
| Credential retired by recovery or rotation | `410` | `credential_retired` | Body: `reason` |
| Account abandoned | `410` | `account_abandoned` | |
| Tombstone found | `410` | `guest_purged` | Body: `reason` (`inactive`, `abandoned`, `deleted`) |
| Challenge expired or used | `410` | `challenge_expired` | |
| Proof of work does not meet `bits` | `422` | `pow_invalid` | |
| Request id already consumed | `409` | `request_consumed` | |
| Link conflict | `409` | `link_conflict` | Body in the next section |
| Confirmation digest differs from the recomputed one | `409` | `preview_changed` | Body: the new `items` and `preview_digest` |
| Account is not an active guest | `409` | `not_a_guest` | |
| Import step failed; resume with the same request | `503` | `import_incomplete` | |
| Rate limit, device limit, load shedding | `429` | `rate_limited`, `device_limit` | Body: `retry_after_seconds` |

Error bodies carry the code (and the stated body field) only. Never echo secrets, tokens, network addresses, hashes or other accounts' ids.

### `409 link_conflict` body

```json
{
  "error": "link_conflict",
  "reason": "credential_owned",
  "guest_weight": "played",
  "default_choice": "keep_existing",
  "items": [
    { "category": "progress", "label_key": "streak", "paid": false, "effect": "carried" },
    { "category": "currency", "label_key": "coins", "paid": false, "effect": "left_behind" }
  ],
  "preview_digest": "<sha-256 hex of the canonical items list>",
  "expires_at": "2026-10-27T12:10:00Z"
}
```

`default_choice` is `keep_existing`, `keep_guest` or `none`. For `email_owned_by_other_provider` the body carries `reason` and no items.

### Resolve: request

```json
{
  "link_attempt_id": "<id>",
  "choice": "keep_existing | keep_guest",
  "import": true,
  "confirmed_preview_digest": "<digest the player was shown>",
  "acknowledged_paid": ["currency:gems"]
}
```

`confirmed_preview_digest` is required for `keep_existing` when the weight is `played` or `paid`. `acknowledged_paid` lists each paid holding whose effect is not `carried`; the server refuses `keep_existing` for a `paid` guest unless every such holding is listed. Success for `keep_existing`: `200 { account_id: <existing account>, kind: "linked", linked_at }` plus a login-block session; for `keep_guest`: `200 { account_id: <guest>, kind: "guest" }`.

---

## Ordering invariants (normative)

**Creation** (README 3.1, in this order): idempotent replay lookup; global and per-network counters; challenge valid, unused, same network bucket; proof of work; attestation; per-device limits; the creating transaction (insert account, credential, session; mark challenge used). A step that fails ends the request with no row written other than counters. The counter increment for a request that passes the earlier checks is committed even when a later check fails (a failing requester is counted).

**Credential exchange**: hash the secret, look up `(tenant_id, secret_hash)`; on a hit apply the outcome table of README 3.2; on a miss look up the tombstone; count a failure against `credential_fail_network_hour`. Touch `last_active_at` only when `GUEST_ACTIVITY_TOUCH_MINUTES` have passed since the stored value.

**Link commit** (README 3.7, one transaction): (1) the attempt is `started`, unexpired, belongs to this session's account; (2) the provider proof was verified by the login block and its nonce hash equals `nonce_hash`; (3) insert the `users` row with `id = account_id` (its UNIQUE provider-id and email constraints decide a race); (4) `UPDATE accounts SET kind = 'linked', linked_at = now, status = 'active' WHERE id = ? AND kind = 'guest'`, and fail the transaction when zero rows change; (5) retire both credentials with reason `linked`; (6) set `revoked_at` on the account's guest sessions; (7) set the attempt `linked`. The login-block session is created after the commit; if that step fails the account is linked and the client signs in with the provider (README 3.7, lost response).

**Conflict resolution**: the attempt must be `conflict` and unexpired. `keep_guest` closes the attempt (`kept_guest`) and changes nothing else. `keep_existing` first checks `LINK_IMPORTS_PER_TARGET_PER_DAY` against `link_attempts` rows with the same `target_account_id` (answer `429 rate_limited` past it), recomputes holdings and the digest, then: set the attempt `importing`; for `import = true` call each participant's `mergeAccounts(guest, target, merge_id)` with `merge_id = "link:" + link_attempt_id`; after all return, in one transaction set the guest `status = abandoned`, `abandoned_at = now`, `merged_into_account_id` (when imported), retire the guest credentials (`abandoned`), revoke the guest sessions, set the attempt `kept_existing`; then create the login-block session for the target. A failure before the last transaction leaves the attempt `importing`; the same request resumes.

**Recovery**: look up SHA-256 of the canonical code and map a retired row through the outcome function of Pattern 2 (`linked` answers `403 account_linked`, `used` or `rotated` answers `410 credential_retired`); require an `active` `recovery` credential whose account is a guest and not abandoned; in one transaction retire that credential (`used`) and the account's active device credential (`recovered`), insert a new device credential, revoke the sessions, insert a session, touch `last_active_at`.

---

## Pattern 1: Proof-of-work difficulty and verification

`powBits` is pure and takes counters as arguments; the verifier reads no clock and no database.

<!-- PATTERN: pow-difficulty-and-verify -->
<!-- PURPOSE: price bulk guest creation with a client-side hash search that the server verifies with one hash -->
<!-- REFERENCE: runtime=node20+ language=typescript crypto=node-builtin algorithm=sha256 -->
<!-- ADAPT: node:crypto createHash -> Web Crypto subtle.digest on Deno and Bun (or their node:crypto shims); keep the input string, the SHA-256 and the leading-zero-bit rule identical on every stack; the cap values come from configuration -->
```typescript
import { createHash } from "node:crypto";

export function powBits(c: { netHits: number; netHourCap: number; globalHits: number;
                             globalCap: number; base: number; step: number; max: number }): number {
  let bits = c.base;
  if (c.netHits >= c.netHourCap / 2) bits += c.step;
  if (c.globalHits >= c.globalCap) bits += c.step;
  return Math.min(bits, c.max);
}

function leadingZeroBits(d: Buffer): number {
  let n = 0;
  for (const byte of d) {
    if (byte === 0) { n += 8; continue; }
    return n + Math.clz32(byte) - 24;
  }
  return n;
}

export function powValid(seed: string, requestId: string, counter: string, bits: number): boolean {
  if (!/^(0|[1-9][0-9]*)$/.test(counter)) return false;
  const digest = createHash("sha256").update(`${seed}:${requestId}:${counter}`, "utf8").digest();
  return leadingZeroBits(digest) >= bits;
}
```

Vectors for `powBits` and `powValid` are in `fixtures/abuse-vectors.json`.

## Pattern 2: Credential exchange outcome

One function maps a lookup to the outcome of README 3.2. The caller does the I/O.

<!-- PATTERN: credential-exchange-outcome -->
<!-- PURPOSE: map a hashed-secret lookup to exactly one outcome so every state has a distinct, truthful answer -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT: the Row and Tombstone shapes -> your ORM result types; the outcome codes map to the HTTP table in this file; return values stay plain data so the function runs in tests without a database -->
```typescript
type Outcome =
  | { kind: "ok"; reactivated: boolean }
  | { kind: "error"; status: 401 | 403 | 410; code: string; reason?: string };

export function exchangeOutcome(
  cred: { status: "active" | "retired"; retiredReason?: string } | null,
  account: { status: "active" | "dormant" | "abandoned" } | null,
  tombstone: { reason: string } | null,
): Outcome {
  if (!cred) {
    return tombstone
      ? { kind: "error", status: 410, code: "guest_purged", reason: tombstone.reason }
      : { kind: "error", status: 401, code: "credential_invalid" };
  }
  if (cred.status === "retired") {
    if (cred.retiredReason === "linked") return { kind: "error", status: 403, code: "account_linked" };
    if (cred.retiredReason === "abandoned") return { kind: "error", status: 410, code: "account_abandoned" };
    return { kind: "error", status: 410, code: "credential_retired", reason: cred.retiredReason };
  }
  if (!account || account.status === "abandoned") return { kind: "error", status: 410, code: "account_abandoned" };
  return { kind: "ok", reactivated: account.status === "dormant" };
}
```

## Pattern 3: Atomic counter and limit check

Rate limits are one atomic statement: increment and read in one round trip, so two concurrent requests cannot both pass the last slot.

<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT: Postgres and SQLite 3.24+ use INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING; MySQL uses INSERT ... ON DUPLICATE KEY UPDATE hits = hits + 1 followed by a SELECT in the same transaction; uuid and timestamptz map per README section 2; the window_start is computed in app code from the server clock aligned to the scope's window length -->
```sql
INSERT INTO abuse_counters (id, tenant_id, scope, bucket_hash, window_start, hits, expires_at)
VALUES ($1, $2, $3, $4, $5, 1, $6)
ON CONFLICT (tenant_id, scope, bucket_hash, window_start)
DO UPDATE SET hits = abuse_counters.hits + 1
RETURNING hits;
```

The caller compares `hits` with the scope's limit; `hits > limit` answers `429`. The bucket hash is `HMAC-SHA256(rotating_key, bucket)` (hex). The network bucket is the full IPv4 address or the IPv6 /64 prefix of the connecting peer, read from the trusted proxy header chain only when the deployment has such a chain.

## Pattern 4: Guest weight and confirmation digest

Both are pure functions over the holdings the participants return.

<!-- PATTERN: guest-weight-and-digest -->
<!-- PURPOSE: classify the guest for the conflict sheet and bind a confirmation to exactly the list the player saw -->
<!-- REFERENCE: runtime=node20+ language=typescript crypto=node-builtin algorithm=sha256 -->
<!-- ADAPT: node:crypto -> Web Crypto on Deno and Bun; the canonical form (code-point sort by category then label_key, arrays in fixed field order, JSON without spaces) must be identical on every stack because the client and the server both depend on the digest value -->
```typescript
import { createHash } from "node:crypto";

type Holding = { category: string; label_key: string; paid: boolean; effect: string };

export function guestWeight(items: Holding[]): "pristine" | "played" | "paid" {
  if (items.some((i) => i.paid)) return "paid";
  return items.length > 0 ? "played" : "pristine";
}

const key = (i: Holding) => i.category + "\u0000" + i.label_key; // code-point order, not locale order

export function previewDigest(items: Holding[]): string {
  const canonical = [...items]
    .sort((a, b) => (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0))
    .map((i) => [i.category, i.label_key, i.paid, i.effect]);
  return createHash("sha256").update(JSON.stringify(canonical), "utf8").digest("hex");
}

export function defaultChoice(weight: string, played: string, paid: string): string {
  return weight === "paid" ? paid : weight === "played" ? played : "keep_existing";
}
```

## Pattern 5: Recovery code canonical form

The client and the server both canonicalise before hashing; a code typed with the wrong case or with look-alike letters still matches.

<!-- PATTERN: recovery-code-canonical -->
<!-- PURPOSE: accept a hand-typed recovery code and reject malformed input before it costs an attempt -->
<!-- REFERENCE: language=typescript framework=agnostic crypto=node-builtin algorithm=sha256 -->
<!-- ADAPT: node:crypto -> Web Crypto on Deno and Bun; the CSPRNG that creates the code (crypto.randomBytes or crypto.getRandomValues) is the stack's own; length 24 comes from RECOVERY_CODE_CHARS -->
```typescript
import { createHash } from "node:crypto";

const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"; // Crockford Base32, no I L O U

export function canonicalCode(input: string, chars = 24): string | null {
  const s = input.toUpperCase().replace(/[-\s]/g, "").replace(/[IL]/g, "1").replace(/O/g, "0");
  if (s.length !== chars) return null;
  for (const ch of s) if (!ALPHABET.includes(ch)) return null;
  return s;
}

export const codeHash = (canonical: string): string =>
  createHash("sha256").update(canonical, "utf8").digest("hex");

// Generation: draw RECOVERY_CODE_CHARS values uniformly from 0..31 (reject-sample bytes >= 224),
// map through ALPHABET, group in fours with hyphens for display only.
```

---

## Participants and erasers

The host registers participants at start-up in a fixed order. An unregistered block counts as holding nothing, so the release gate in `acceptance.md` lists every block that keys by `account_id` and requires either registration or an explicit `no_holdings` declaration.

| Hook | Called by | Rules |
|---|---|---|
| `holdings(account_id)` | conflict preview, sweep (paid hold) | Read only; fast; returns an empty list when nothing is held |
| `mergeAccounts(from, into, merge_id)` | conflict import only | Idempotent by `merge_id`; `already_merged` on a second target; the block's own transaction |
| `deleteAccount(account_id)` | purge, guest deletion | Safe to repeat; erasing nothing is not an error |

`engagement.daily-streak` already names the merge and erasure hooks (`mergeAccounts(from_account_id, into_account_id)`, `deleteAccount(account_id)`) and `engagement.objectives` takes a `merge_id`; this block fixes the call site and the `holdings` listing. A same-account link calls none of them.

## Lifecycle sweep

Runs every `GUEST_SWEEP_EVERY_HOURS`, in batches of `GUEST_SWEEP_BATCH_SIZE`, each batch idempotent:

1. `UPDATE accounts SET status = 'dormant', dormant_at = now WHERE kind = 'guest' AND status = 'active' AND last_active_at <= now - GUEST_DORMANT_AFTER_DAYS`; for each row emit `guest_dormant { inactive_days, paid_hold }` where `paid_hold` is any `holdings` item with `paid = true`.
2. Select dormant guests with `last_active_at <= now - GUEST_PURGE_AFTER_DAYS`. Skip those with `paid_hold` while `GUEST_PURGE_EXEMPT_PAID`. For the rest: run every `deleteAccount`, write a tombstone per device credential hash (reason `inactive`), delete the `accounts` row, emit `guest_purged` without an account id.
3. Select abandoned guests with `abandoned_at <= now - GUEST_ABANDONED_RETENTION_DAYS`; purge as in step 2 with reason `abandoned`.
4. Delete expired rows: `guest_tombstones`, `guest_challenges`, `abuse_counters`, expired `guest_sessions`, terminal `link_attempts` older than `LINK_ATTEMPT_RETENTION_DAYS`; mark unresolved attempts past `expires_at` as `expired`.

A purge that fails in the middle leaves the account in place; the next sweep repeats it.

## Login-block integration

- The verifier is the login block's own function; this block passes `provider` and the proof and receives `{ provider, subject, email, email_verified, email_is_private, name }` or an error that maps to `sign_in_failed`.
- The `users` insert uses the columns of the login block's model (`google_id` or `apple_id`, `email`, `name`, `domain`, `email_is_private`) and `id = account_id`. Apple's name arrives only on the first authorization and outside the identity token (`auth.sign-in-with-apple` README section 1); the client passes it along exactly as that block specifies.
- The login-block session is created through that block's session function; its cookie or token transport is that block's open question for a native shell.
- A project that uses managed auth maps `account_id` to the managed user id and keeps sections 3.5 to 3.9 of the README unchanged.

## Attestation verification

The checks are the external contracts of `README.md` section 3.4 (Apple's attestation steps, Google's token decoding and verdict fields). Implementation notes: store the iOS public key and counter only if the adopter also asserts on later calls (the block needs only the attestation at creation); the iOS `key_id` is hashed with a long-lived server key before it becomes `creation_device_hash`; on Android, decode the token with a service account whose credentials live in the server's secret store; treat an empty `deviceRecognitionVerdict`, an `UNEVALUATED` `appRecognitionVerdict` and a missing `MEETS_DEVICE_INTEGRITY` label as a failed attestation. `unavailable` is only what the client itself reports (no platform support, no Play services, a transient platform error).
