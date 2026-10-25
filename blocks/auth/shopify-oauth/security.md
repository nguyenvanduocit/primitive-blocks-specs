# Security — Shopify App Installation & OAuth

## Threat Model

### 1. CSRF via Forged Callback

**Impact**: Critical — attacker could trick a merchant into installing a malicious app instance or linking their store to an attacker's account.

**Mitigations**:
- Nonce (state parameter) generated server-side with `crypto.randomBytes(16)`
- Nonce stored in database with 5-minute TTL
- Single-use: deleted immediately after verification
- HMAC verification on all callback query parameters provides additional layer
- Nonce is bound to the shop domain that initiated the flow

### 2. Shop Domain Spoofing

**Impact**: High — attacker could redirect the OAuth flow to a domain they control, intercepting the authorization code.

**Mitigations**:
- Strict regex validation: only `*.myshopify.com` domains accepted
- HMAC signature from Shopify covers the `shop` parameter — tampering detected
- The `redirect_uri` in the initial request is registered in the Shopify Partner Dashboard and cannot be changed

### 3. Access Token Exposure

**Impact**: Critical — stolen access token gives full API access to the merchant's store within granted scopes.

**Mitigations**:
- Encrypted at rest using AES-256-GCM (confidentiality + integrity)
- Encryption key stored in environment variable, never in code
- Never logged — log redaction for any request/response containing tokens
- Never returned in API responses to any client
- Never stored in cookies, localStorage, or URL parameters

### 4. Replay Attack on Callback

**Impact**: Medium — replaying a valid callback could re-trigger the install flow.

**Mitigations**:
- Nonce is deleted immediately after use — replay fails with "invalid_or_expired_state"
- Authorization code is single-use on Shopify's side — replay fails at token exchange
- Timestamp parameter can be checked for freshness (within acceptable window)

### 5. Scope Escalation

**Impact**: High — app could end up with more permissions than intended.

**Mitigations**:
- Requested scopes defined in `SHOPIFY_SCOPES` config, not dynamic
- Granted scopes from token exchange response are stored and can be compared
- If granted scopes differ from requested, the discrepancy is logged

## Input Validation Rules

| Field | Validation | Error Code |
|-------|-----------|------------|
| `shop` (query param) | Required, matches `^[a-zA-Z0-9][a-zA-Z0-9\-]*\.myshopify\.com$` | `invalid_shop_domain` |
| `hmac` (query param) | Required, valid HMAC-SHA256 hex string | `hmac_verification_failed` |
| `state` (query param) | Required, exists in oauth_nonces, not expired | `invalid_or_expired_state` |
| `code` (query param) | Required, non-empty string (opaque to us) | `token_exchange_failed` |
| `timestamp` (query param) | Required, numeric, within reasonable window | `invalid_timestamp` |

## Secrets Management

| Secret | Storage | Rotation |
|--------|---------|----------|
| `SHOPIFY_API_KEY` | Environment variable | Rotate via Shopify Partner Dashboard |
| `SHOPIFY_API_SECRET` | Environment variable | Rotate via Partner Dashboard (invalidates all HMAC + existing tokens) |
| `TOKEN_ENCRYPTION_KEY` | Environment variable | Rotate with re-encryption migration |
| Shop access tokens | Database (encrypted) | Refreshed on app reinstall |
