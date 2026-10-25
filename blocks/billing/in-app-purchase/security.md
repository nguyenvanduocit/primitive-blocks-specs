# Security — In-App Purchase: One-Time Unlock

## Threat Model

### T1: Client-side gate bypass (accepted risk, bounded)

**Attack**: The gate runs on the device and the gated content is bundled in the app (and, if the web build is published, served free). A rooted device, a modified build, or a read of the bundle yields the paid content without paying.

**Impact**: MEDIUM — lost revenue. No account takeover and no data loss.

**Mitigation**:
- Decide up front that this block protects the *experience*, not a secret. Use it for content whose copy-out you accept.
- Keep one choke point (invariant 1) so the honest path cannot be bypassed by accident.
- For content that must not leave the server, deliver it from a server that checks entitlement (OPTIONAL EXTENSION in `backend.md`, not production-verified) and do not bundle it.

**Validation rule**: no content entry reaches the engine without passing `playable(ids)`.

### T2: Shipping with purchases silently off

**Attack / failure**: A native build without the store key is inert by design: everything unlocks. A store upload made before the key existed gave the app away for free until a keyed release replaced it (this happened to the source project's first Play release).

**Impact**: HIGH — the paywall is off for every user of that release.

**Mitigation**:
- Create the RevenueCat app and copy the public key **before the first store upload**.
- Release check: build the native release, then confirm the key for each platform is present in the build input and a purchase-enabled run shows the paywall on locked content (`release-readiness.feature`).
- Keep inert-by-default; the alternative (fail closed, locking everything when the key is missing) would lock paying users out instead.

**Validation rule**: a release candidate on a device or simulator shows the paywall when a locked item is tapped.

### T3: Secret or test key in a shipped build

**Attack**: A credential ends up in the uploaded bundle or the repo: the RevenueCat Test Store key (`test_` prefix), the Play service-account JSON, the App Store IAP `.p8` file, its key id, or its issuer id.

**Impact**: HIGH for the service account and `.p8` (access to store billing data and API); MEDIUM for the Test Store key (sells nothing real, but a build carrying it cannot sell).

**Mitigation**:
- Public SDK keys (`goog_`, `appl_`) are designed to ship in the app; they live in a git-ignored env file read at native build time.
- Service-account JSON, `.p8`, key id, and issuer id live only in a git-ignored secrets folder with mode 600 and are uploaded to RevenueCat; they are never read by app code.
- The Test Store key is used for a single screenshot build; afterwards rebuild with the real key and search the final bundle for the `test_` prefix and for any secret file name.
- The Play service account is invited to one app only, with three permissions: view app information, view financial data, manage orders and subscriptions.

**Validation rule**: a search of the shipped bundle for the Test Store key value finds nothing; `git check-ignore` confirms the env and secrets paths.

### T4: Wrong store user (entitlement on the wrong account)

**Attack / failure**: The store user id is the account uid. If the id is shared, guessable, or switched incorrectly, one person's entitlement attaches to another identity, or a signed-out device keeps the previous owner's unlock.

**Impact**: MEDIUM.

**Mitigation**:
- Use the opaque account uid, never an email or a name (extrapolated privacy rule).
- Sign-in calls log in as the uid; sign-out calls log out, which creates a fresh anonymous store user; the unlock of the previous user does not remain visible (`restore-and-identity.feature`).
- Serialize all store calls (`frontend.md`, "serialize-store-calls") so a log-in cannot race a purchase.

**Not verified**: how RevenueCat merges a purchase made as an anonymous user when that user later logs in. The source project's records do not show it; read RevenueCat's current documentation on identity before relying on it.

### T5: Forged or replayed entitlement events (OPTIONAL EXTENSION only)

**Attack**: An attacker posts fake webhook calls to grant themselves `pro` in the mirror, or a late delivery reverts a refund.

**Impact**: HIGH if the server delivers paid content from the mirror.

**Mitigation**:
- Authenticate every call with a shared secret and compare in constant time; reject with 401 and never log the secret or the body.
- Apply an event only when it is newer than `last_event_at`.
- Keep the secret in the server's secret store, not in code.

Status: not production-verified; the source project did not build the extension.

### T6: Reviewer access material leaks

**Attack**: Promo codes for the product, handed to store reviewers, are committed or published and redeemed by the public.

**Impact**: LOW to MEDIUM — free unlocks until the codes expire.

**Mitigation**: store codes in the git-ignored secrets folder; put them only in the store's own review form; use few, one-time codes with an expiry.

## Validation rules

| Input | Rule |
|---|---|
| Item ids passed to the gate | strings only; ids the engine produced; an unknown id is simply not in the free set and so is locked |
| Store error code | treated as an opaque string; unlisted codes map to `store`; never shown raw to the learner |
| Price | taken from the store string; never parsed or computed |
| Entitlement key | `pro`, matched by exact key presence in `entitlements.active` |

## Auth/authz

- The client trusts only the store SDK's answer for `pro`. There is no app-owned token to forge.
- The extension, if built, authorizes webhook calls by shared secret and authorizes reads by the caller's own account.

## Secrets management

| Secret | Where | Never |
|---|---|---|
| RevenueCat public SDK keys (`goog_`, `appl_`) | git-ignored env file, injected at native build | in a spec or in a tracked file |
| RevenueCat Test Store key (`test_`) | local env for one screenshot build | in an uploaded build |
| Play service-account JSON | git-ignored secrets folder, mode 600, uploaded to RevenueCat | in the repo, the app, or CI logs |
| App Store IAP `.p8`, key id, issuer id | git-ignored secrets folder, mode 600, uploaded to RevenueCat | in the repo, the app, or CI logs |
| Promo codes | git-ignored secrets folder; pasted into the store form | in the repo or a spec |
| Webhook shared secret (extension) | server secret store | in code or logs |

Back up the signing keystore and these files to a password manager on day one; the source project never confirmed a backup of any of them.
