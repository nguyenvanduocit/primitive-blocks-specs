# Security - Guest Account

Scope: guest issuance, the device credential and sessions, abuse controls, recovery codes, linking and the conflict import, lifecycle and deletion, and the privacy of the identifiers. Provider token verification belongs to `auth.google-login` and `auth.sign-in-with-apple`; balances belong to the billing blocks.

Tags: **[documented]** a platform or standard page states it (cited in `README.md`); **[design]** a choice of this block; **[extrapolated]** not verified against the sibling blocks. Nothing here has been run on stacks A, B or C.

## Threat Model

### T1: Mass guest creation (bonus farming)

**Attack**: a script or an emulator farm creates thousands of guests to harvest daily rewards, event rewards and referral payouts, or to flood a leaderboard.

**Impact**: HIGH for an economy with real-money value; MEDIUM otherwise (inflated rewards, polluted analytics).

**Mitigation** [design]:

- Layered controls, cheapest first (`README.md` section 3.3): global breaker, per-network caps, proof of work, optional attestation, per-device caps. An attacker pays CPU before the server pays for an attestation check.
- Proof of work is bound to a random seed and to the request id, single use, and valid only for the requester's network bucket; precomputation is impossible and a solved puzzle serves one creation.
- Other blocks cap what a guest can farm (for example the freeze cap of `engagement.daily-streak`), and `kind` lets them apply stricter rules to guests.
- The conflict import runs once per guest (`already_merged`) and `LINK_IMPORTS_PER_TARGET_PER_DAY` limits how many guests can be merged into one account in a day, so farmed guests cannot be funnelled into a main account.

**Residual**: proof of work prices bulk creation, it does not stop a funded attacker; attestation raises the cost but does not prove one device per person ([documented]: the Play Integrity verdict is "input" to a policy; App Attest keys do not survive reinstall).

**Validation rule**: with the abuse vectors of `fixtures/abuse-vectors.json`, the limit of each scope answers `429` on the request after the cap; a replayed challenge answers `410`.

### T2: Theft of the device credential

**Attack**: the secret is read from the device (a rooted phone, an unencrypted backup, malware), from a log, or from a restored platform backup on a second device.

**Impact**: HIGH for that account: the secret is a bearer credential. It proves control of the guest account and nothing else.

**Mitigation**:

- Store the secret only in secure storage (Keychain, Keystore-backed storage or Block Store), never in web-view storage, logs, analytics or crash reports [design].
- Keep it out of Android Auto Backup targets: the platform advises that credentials "don't" belong in shared preferences or files and points to Block Store [documented].
- Treat platform backup as an opt-in trade (`GUEST_CREDENTIAL_PLATFORM_BACKUP`, default `off`): Block Store's cloud copy is end-to-end encrypted only with Android 9 or higher and a screen lock [documented].
- Sensitive actions re-present the device secret and do not rely on the session alone: link start, recovery-code creation and deletion. A stolen session token cannot link the account to the attacker's Google account or mint a recovery code [design].
- A link or a recovery retires the credential, so a stolen copy stops working at that moment [design]. A guest sees a returning stolen-device case as `credential_retired`.

**Residual**: a stolen secret works until the player links or recovers; there is no remote revoke for an unlinked guest. The copy of the prompt says the game lives on the phone for this reason.

**Validation rule**: after a link or a recovery, an exchange with the old secret answers `403 account_linked` or `410 credential_retired` and creates no session.

### T3: Database or backup leak

**Attack**: an attacker reads the tables.

**Impact**: MEDIUM: nothing in the tables lets them act as a player.

**Mitigation** [design, with OWASP as the documented basis for hashed verifiers]:

- Secrets, recovery codes and tokens are stored only as SHA-256 hashes of values with at least 112 bits (device secret and tokens 256 bits, recovery code 120 bits); the secret is not recoverable from the hash.
- Tombstones hold a hash of a random secret and no account id; `abuse_counters` hold keyed hashes under rotating keys; the device hash is a keyed hash.
- The `account_id` is not a secret and authenticates nothing; exposing it (support screens, logs) is acceptable and never enough to act.

**Validation rule**: a dump of every table contains no value that, presented to an endpoint, creates a session.

### T4: Recovery-code guessing

**Attack**: an attacker submits codes to the recovery endpoint to find a valid one.

**Impact**: HIGH if one succeeds (account takeover).

**Mitigation**:

- 120 bits of entropy: the space is not searchable [design; NIST SP 800-63B-3 lists 112 bits as the line for a plain hash of a look-up secret, documented].
- `RECOVERY_ATTEMPTS_PER_NETWORK_PER_HOUR` (default 10) is far stricter than NIST's cap of 100 consecutive failures on one authenticator [documented, for the cap]; failures also count in `credential_fail_network_hour`.
- Format is checked on the client first, so honest typos do not spend attempts.
- A used, replaced or linked code answers a distinct code only to a requester who presented it exactly; an unknown code answers `401 credential_invalid` with no hint.

**Validation rule**: the eleventh attempt from one network bucket in an hour answers `429`; a canonicalised code with I, L, O or lower case matches (`fixtures/abuse-vectors.json`).

### T4b: A recovery code leaks (written on a note, posted in a screenshot)

**Attack**: someone who sees the code opens the account on another device.

**Impact**: HIGH for that account; the real owner is locked out of the device-credential path, because recovery retires the lost device's credential.

**Mitigation** [design]: the display screen says plainly that anyone with the code can open the game and that it is shown once; a new code replaces the old one; using a code retires it and prompts for a new one; the recovery event is visible to the player in the account section ("recovered on another phone") on the next start of the old device (`credential_retired`). A player who links the account to Google or Apple removes the code path entirely (INV-11).

### T5: Link hijack (login CSRF and session theft)

**Attack**: the attacker makes the victim complete a provider sign-in with the attacker's provider account, attaching the victim's progress to the attacker's identity; or uses a stolen guest session to link the attacker's Google account to the victim's guest.

**Impact**: HIGH: account takeover.

**Mitigation** [design]:

- The nonce is created per attempt, bound to the guest's account, single use, valid `LINK_NONCE_TTL_SECONDS`, and must equal the nonce claim of the provider token (the login blocks verify the token; `auth.sign-in-with-apple` verifies the nonce) [documented in those blocks].
- The flow starts only from a player action; the link request carries the guest session and the attempt id; link start requires the device secret (T2).
- The provider proof is verified by the login block's verifier; this block never parses provider tokens itself.

**Validation rule**: a proof whose nonce belongs to another attempt, or an attempt created from a session without the secret, is refused and changes nothing.

### T6: Conflict import abuse and loss

**Attack / failure**: (a) a player is tricked or hurried into discarding a valuable guest game; (b) a partially completed import leaves two accounts half-merged; (c) a participant that did not register is silently dropped; (d) the shown list differs from what runs.

**Impact**: HIGH for a `paid` guest (money), MEDIUM otherwise.

**Mitigation** [design]:

- No silent merge of balances or entitlements: only a participant that lists a holding as `carried` moves it, and only after confirmation (INV-9).
- The confirmation carries a digest of exactly the list shown; the server recomputes it and answers `409 preview_changed` on a difference.
- `paid` guests get no preselected choice and one acknowledgement per paid holding that is not carried.
- The import is resumable and idempotent per participant (`merge_id`); the guest is abandoned only after every participant finished; an abandoned guest is retained `GUEST_ABANDONED_RETENTION_DAYS` before purge.
- The acceptance checklist makes participant registration a release gate (c).

**Validation rule**: `fixtures/link-conflict-cases.json` cases produce the listed weights, defaults and digests; a changed holding after the preview answers `409`; a kill between participants resumes without double-applying.

### T7: Attestation bypass, replay and outage

**Attack / failure**: a replayed attestation or token; a modified client that skips attestation in `preferred` mode; the platform service being unavailable or over quota.

**Impact**: MEDIUM.

**Mitigation**: the attestation is bound to the challenge and request id through `clientDataHash` (App Attest) or `requestHash` (Play Integrity), so it is valid for one creation [documented: Apple's nonce construction, Google's `requestHash`]; Google clears the verdicts of a reused token [documented]; unattested creations in `preferred` mode face a stricter limit; `required` is documented as unsafe for outages and for the default quota of 10,000 requests per day [documented for the quota]; an empty device verdict is a failure.

### T8: Race conditions

**Attack / failure**: two link attempts for the same provider identity; two devices sharing one credential acting together; a recovery used twice at once; a sweep purging an account that is being reactivated.

**Impact**: MEDIUM.

**Mitigation** [design]: the `users` uniqueness decides the link race and the loser becomes a conflict; the kind change is a compare-and-set (`WHERE kind = 'guest'`); credential retirement and the new credential are one transaction, guarded by the partial UNIQUE on active credentials; the sweep re-reads `last_active_at` inside the purge transaction and skips the account when it changed.

### T9: Privacy leak through logs, analytics and the account id

**Attack / failure**: the secret, recovery code, request id, network address or device identifier ends up in a log, an analytics event, a crash report or a support screenshot; or an event names another account in a conflict.

**Impact**: MEDIUM to HIGH (a secret in a log is a credential leak).

**Mitigation**: the logging table of `README.md` section 3.3; no secret field in any event of section 6; `link_conflict` carries no id of the other account; `guest_purged` and `guest_create_throttled` carry no account id; error bodies carry codes only; the client rules in `frontend.md` section 12; the web server's access log retention is set by the adopter (it holds addresses).

### T10: Identifier persistence and children

**Attack / failure**: a credential that survives uninstall keeps identifying a person who deleted the app; a child's persistent identifier is created without the required steps.

**Impact**: MEDIUM (privacy and legal).

**Mitigation**: deletion clears every device copy (secure storage, Block Store, synchronizable Keychain item); the privacy text says deletion happens in Settings; `AUDIENCE_MODE` applies the age screen before any identifier; `kids` and under-age accounts get no link prompt and no attestation; no advertising identifier is ever read (INV-18). Sources and limits: `README.md` section 3.10; this is not legal advice.

### T11: Tenant crossing

**Attack / failure**: a credential, session or challenge from one tenant resolves in another.

**Impact**: HIGH in a multi-tenant deployment.

**Mitigation** [design]: every table carries `tenant_id` and every lookup includes it; unique indexes are per tenant; the tenant comes from the verified request context, never from the body.

### T12: Purge destroys paid value

**Failure**: the sweep deletes a dormant guest who bought something.

**Impact**: HIGH (money, support load, store disputes).

**Mitigation** [design]: `GUEST_PURGE_EXEMPT_PAID` (default true) skips any guest whose participants report a paid holding; a participant that fails to answer `holdings` is treated as holding paid value; purge is skipped, not retried blindly, and logged as a counter.

## Validation rules

| Input | Rule |
|---|---|
| `creation_request_id` | base64url, at least 128 bits, at most 128 characters |
| `challenge_id` | an id issued to this network bucket, unused, unexpired |
| `pow_counter` | canonical decimal string, at most 20 digits |
| `platform` | `ios` or `android`; anything else answers `400 invalid_request` (a web view has no secure credential storage) |
| `app_version` | text up to 32 characters; logged as a value, never parsed for decisions |
| Device secret, recovery code | exact length and alphabet before hashing; wrong shape answers `401 credential_invalid` without a database write |
| `link_attempt_id`, `choice`, `confirmed_preview_digest` | ids are `unique_id`; `choice` is in the enum; the digest is 64 hex characters |
| `acknowledged_paid` | list of `category:label_key`; each entry must exist in the recomputed holdings |
| Tenant | from verified context only |

## Auth/authz

| Action | Requires |
|---|---|
| Create guest, challenge | none (rate limited and proof-gated) |
| Exchange, recover | the secret or code in the body; no session |
| Read account, link resolve | a valid session of the account |
| Link start, recovery-code create, deletion | session **and** the device secret re-presented |
| Link | session and the provider proof bound to the attempt |
| Sweep, erasers | internal only; no public route |

A request never supplies `account_id`; it is always derived from the credential or the session.

## Secrets management

| Secret | Where | Never |
|---|---|---|
| Key that hashes network buckets (rotates every `ABUSE_KEY_ROTATION_HOURS`) | server secret store | in the database, in logs |
| Key that hashes device signals (`creation_device_hash`) | server secret store | in the database, shared with the abuse key |
| Play Integrity service-account credentials (token decoding) | server secret store | in the app, in the repo |
| Apple team and bundle identifiers for the attestation RP ID check | configuration | hard-coded per environment without a development/production split |
| Device secrets, recovery codes, session tokens | shown once, held on the device or by the player | stored in plaintext anywhere on the server |

## Logging rules

Log outcomes and counts, never identities: the table in `README.md` section 3.3. A failed exchange logs the outcome enum and the network bucket **hash** only through the counters, not a line per attempt.
