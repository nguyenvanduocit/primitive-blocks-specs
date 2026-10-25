# Security — Shopify Session Token Verification

## Threat Model

### 1. Token Forgery

**Impact**: Critical — attacker forges a valid-looking JWT to impersonate a merchant and gain access to their shop data.

**Mitigations**:
- HMAC-SHA256 signature verification using `SHOPIFY_API_SECRET` before any claim inspection
- Constant-time comparison (`crypto.timingSafeEqual`) prevents timing-based secret extraction
- Without the secret, an attacker cannot produce a valid signature for any payload

### 2. Expired Token Replay

**Impact**: Medium — attacker captures a valid token and replays it after expiry to maintain access.

**Mitigations**:
- Strict `exp` claim check: `exp < Math.floor(Date.now() / 1000)` fails immediately
- Tokens are ~1 minute lived — the attack window is extremely narrow
- App Bridge auto-refreshes tokens before expiry during normal use — no legitimate need to hold a token long-term

### 3. Wrong Audience (Cross-App Attack)

**Impact**: High — a token issued for a different Shopify app is presented to this app's backend.

**Mitigations**:
- `aud` claim must exactly equal `SHOPIFY_API_KEY` (this app's API key)
- Each Shopify app has a unique API key — a token for "app-A" will fail `aud` check on "app-B"

### 4. Cross-Shop Attack

**Impact**: High — attacker presents a valid token for shop A to access shop B's data.

**Mitigations**:
- `iss` and `dest` claims must reference the same shop domain
- Shop domain extracted from `dest` is looked up in `shops` table — only installed, non-uninstalled shops pass
- All downstream queries are scoped by `shopId` (from the verified shop record), not from any client-supplied parameter

### 5. Token Replay via JTI

**Impact**: Low — attacker replays a still-valid (not expired) token to make duplicate requests.

**Mitigations**:
- Short expiry (~1 minute) makes the replay window trivially small
- `jti` claim is present and unique per token — can be used for replay detection if strict idempotency is required
- For most embedded apps, short expiry is sufficient. Implement jti blocklist only if the protected operations are non-idempotent and high-value (e.g., financial transactions).

## Input Validation Rules

| Claim | Validation | Error Code |
|-------|-----------|------------|
| `Authorization` header | Required, format `Bearer <token>` | `missing_token` |
| JWT structure | Exactly 3 dot-separated base64url parts | `invalid_token` |
| Signature | HMAC-SHA256 of `header.payload` using `SHOPIFY_API_SECRET`, constant-time compare | `invalid_token` |
| `exp` | Required, numeric, `exp > now()` | `expired_token` |
| `nbf` | If present, numeric, `nbf <= now()` | `invalid_token` |
| `aud` | Required, string, must equal `SHOPIFY_API_KEY` | `invalid_audience` |
| `iss` | Required, string, format `https://*.myshopify.com/admin` | `invalid_token` |
| `dest` | Required, string, format `https://*.myshopify.com`, shop matches `iss` | `invalid_token` |
| `sub` | Required, string (Shopify user ID) | `invalid_token` |
| Shop in DB | `dest` domain exists in `shops` table with `uninstalled_at IS NULL` | `shop_not_found` |

## Secrets Management

| Secret | Storage | Rotation Impact |
|--------|---------|-----------------|
| `SHOPIFY_API_KEY` | Environment variable | Rotation changes `aud` check — all existing valid tokens rejected until App Bridge re-issues |
| `SHOPIFY_API_SECRET` | Environment variable | Rotation invalidates all existing session tokens — App Bridge re-issues on next interaction. Also impacts OAuth callbacks and webhook HMAC. Coordinate rotation carefully. |

## Timing Attack Prevention

The signature comparison MUST be **constant-time**. A naive string comparison (`===`) short-circuits on first byte mismatch and leaks how many characters matched, allowing an attacker to reconstruct the expected HMAC byte-by-byte via many requests. A constant-time comparison always takes the same time regardless of where the mismatch occurs.

<!-- PATTERN: constant-time-compare-illustration -->
<!-- PURPOSE: Show the correct vs incorrect comparison style for signature bytes — invariant across stacks -->
<!-- REFERENCE: runtime=node20+ crypto=node-builtin -->
<!-- ADAPT:
       - `crypto.timingSafeEqual`: edge/Workers/Deno don't expose this — implement constant-time compare manually with an XOR accumulator over equal-length byte arrays (never bail on first mismatch); Python `hmac.compare_digest`; Go `crypto/subtle.ConstantTimeCompare`; Rust `subtle::ConstantTimeEq`
       - Length pre-check: comparing two strings of different length always leaks length difference — match length first AND treat the entire `mismatch` as `invalid_token` to keep error behavior uniform -->

```typescript
// CORRECT: constant-time
crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(received));

// WRONG: leaks timing information
expected === received;
```
