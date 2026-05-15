# Backend Patterns — Shopify App Installation & OAuth

## API Endpoints

### OAuth Flow

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `GET` | `/api/auth/shopify` | Initiate install, redirect to Shopify | None (shop param required) |
| `GET` | `/api/auth/shopify/callback` | Handle OAuth callback, exchange code | None (HMAC verified) |

### Internal (called by other blocks)

| Function | Purpose |
|----------|---------|
| `getShopByDomain(domain)` | Look up shop record by myshopify.com domain |
| `getShopToken(shopId)` | Get decrypted access token for API calls |
| `verifyShopifyHmac(secret, data, hmac)` | HMAC-SHA256 verification (shared utility) |

---

## Install Redirect Handler

<!-- PATTERN: shopify-oauth-redirect -->
<!-- PURPOSE: Validate shop domain, generate nonce, redirect to Shopify permission screen -->
<!-- ADAPT: Crypto for nonce generation, redirect mechanism -->

```typescript
// GET /api/auth/shopify?shop=example.myshopify.com

async function handleInstallRedirect(req: Request): Promise<Response> {
  const shop = req.query.shop;

  // 1. Validate shop domain format
  if (!shop || !isValidShopDomain(shop)) {
    return error(400, "invalid_shop_domain");
  }

  // 2. Generate cryptographically random nonce
  const nonce = crypto.randomBytes(16).toString("hex"); // 32 chars

  // 3. Store nonce with TTL
  await db.insert("oauth_nonces", {
    nonce,
    shop_domain: shop,
    expires_at: new Date(Date.now() + config.OAUTH_NONCE_TTL_SECONDS * 1000),
  });

  // 4. Build Shopify authorize URL
  const authUrl = new URL(`https://${shop}/admin/oauth/authorize`);
  authUrl.searchParams.set("client_id", config.SHOPIFY_API_KEY);
  authUrl.searchParams.set("scope", config.SHOPIFY_SCOPES);
  authUrl.searchParams.set("redirect_uri", `${config.APP_URL}/api/auth/shopify/callback`);
  authUrl.searchParams.set("state", nonce);

  return redirect(302, authUrl.toString());
}

function isValidShopDomain(shop: string): boolean {
  // Only allow *.myshopify.com domains — prevents open redirect
  return /^[a-zA-Z0-9][a-zA-Z0-9\-]*\.myshopify\.com$/.test(shop);
}
```

## OAuth Callback Handler

<!-- PATTERN: shopify-oauth-callback -->
<!-- PURPOSE: Verify HMAC + nonce, exchange code for offline token, upsert shop -->
<!-- ADAPT: HTTP client for token exchange, encryption for token storage -->

```typescript
// GET /api/auth/shopify/callback?code=...&hmac=...&shop=...&state=...&timestamp=...

async function handleOAuthCallback(req: Request): Promise<Response> {
  const { code, hmac, shop, state, timestamp, ...rest } = req.query;

  // 1. Verify HMAC over all query params (except hmac and signature)
  const params = { code, shop, state, timestamp, ...rest };
  const sortedParams = Object.keys(params).sort()
    .map(key => `${key}=${params[key]}`).join("&");

  if (!verifyShopifyHmac(config.SHOPIFY_API_SECRET, sortedParams, hmac)) {
    return error(401, "hmac_verification_failed");
  }

  // 2. Validate shop domain format
  if (!isValidShopDomain(shop)) {
    return error(400, "invalid_shop_domain");
  }

  // 3. Verify nonce (state parameter)
  const nonceRecord = await db.query(
    `SELECT * FROM oauth_nonces WHERE nonce = $1 AND expires_at > now()`,
    [state]
  );
  if (!nonceRecord) {
    return error(401, "invalid_or_expired_state");
  }

  // Delete nonce immediately (single-use)
  await db.query(`DELETE FROM oauth_nonces WHERE nonce = $1`, [state]);

  // 4. Exchange code for offline access token
  const tokenResponse = await fetch(`https://${shop}/admin/oauth/access_token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_id: config.SHOPIFY_API_KEY,
      client_secret: config.SHOPIFY_API_SECRET,
      code,
    }),
  });

  if (!tokenResponse.ok) {
    return error(502, "token_exchange_failed");
  }

  const { access_token, scope } = await tokenResponse.json();

  // 5. Encrypt token and upsert shop record
  const encryptedToken = encrypt(access_token);
  const shop_record = await db.query(`
    INSERT INTO shops (shop_domain, access_token, scopes, installed_at, uninstalled_at)
    VALUES ($1, $2, $3, now(), null)
    ON CONFLICT (shop_domain) DO UPDATE SET
      access_token = $2,
      scopes = $3,
      installed_at = now(),
      uninstalled_at = null,
      updated_at = now()
    RETURNING *
  `, [shop, encryptedToken, scope]);

  // 6. Emit event
  emit("shop.installed", {
    shopId: shop_record.id,
    shopDomain: shop,
    scopes: scope,
  });

  // 7. Redirect to embedded app in Shopify admin
  return redirect(302, `https://${shop}/admin/apps/${config.SHOPIFY_API_KEY}`);
}
```

## HMAC Verification (Shared Utility)

<!-- PATTERN: shopify-hmac-verify -->
<!-- PURPOSE: Constant-time HMAC-SHA256 verification — used by OAuth, webhooks, GDPR, app proxy -->
<!-- ADAPT: Crypto library -->

```typescript
function verifyShopifyHmac(
  secret: string,
  data: string | Buffer,
  expectedHmac: string
): boolean {
  const computed = crypto
    .createHmac("sha256", secret)
    .update(data)
    .digest("hex");

  // Constant-time comparison to prevent timing attacks
  if (computed.length !== expectedHmac.length) return false;
  return crypto.timingSafeEqual(
    Buffer.from(computed, "hex"),
    Buffer.from(expectedHmac, "hex")
  );
}
```

## Shop Lookup (Shared Utility)

<!-- PATTERN: shop-lookup -->
<!-- PURPOSE: Retrieve shop record by domain — used by all blocks needing shop context -->
<!-- ADAPT: DB client -->

```typescript
async function getShopByDomain(domain: string): Promise<Shop | null> {
  return db.query(
    `SELECT * FROM shops WHERE shop_domain = $1 AND uninstalled_at IS NULL`,
    [domain]
  );
}

async function getShopToken(shopId: string): Promise<string> {
  const shop = await db.query(`SELECT access_token FROM shops WHERE id = $1`, [shopId]);
  if (!shop) throw new Error("shop_not_found");
  return decrypt(shop.access_token);
}
```

## Token Encryption

<!-- PATTERN: token-encryption -->
<!-- PURPOSE: Encrypt/decrypt Shopify access tokens at rest -->
<!-- ADAPT: Encryption key management, algorithm choice -->

```typescript
// AES-256-GCM recommended — provides confidentiality + integrity
const ALGORITHM = "aes-256-gcm";

function encrypt(plaintext: string): string {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ALGORITHM, getEncryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  // Format: iv:tag:ciphertext (all hex)
  return `${iv.toString("hex")}:${tag.toString("hex")}:${encrypted.toString("hex")}`;
}

function decrypt(encoded: string): string {
  const [ivHex, tagHex, ciphertextHex] = encoded.split(":");
  const decipher = crypto.createDecipheriv(
    ALGORITHM, getEncryptionKey(), Buffer.from(ivHex, "hex")
  );
  decipher.setAuthTag(Buffer.from(tagHex, "hex"));
  return decipher.update(Buffer.from(ciphertextHex, "hex")) + decipher.final("utf8");
}
```

## Nonce Cleanup

<!-- PATTERN: nonce-cleanup -->
<!-- PURPOSE: Periodic cleanup of expired nonces to prevent table bloat -->
<!-- ADAPT: Job scheduler -->

```typescript
// Run periodically (e.g., every 10 minutes)
async function cleanupExpiredNonces(): Promise<number> {
  const result = await db.query(
    `DELETE FROM oauth_nonces WHERE expires_at < now() RETURNING id`
  );
  return result.rowCount;
}
```

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `invalid_shop_domain` | 400 | Shop param missing or not `*.myshopify.com` |
| `hmac_verification_failed` | 401 | HMAC signature doesn't match |
| `invalid_or_expired_state` | 401 | Nonce not found or expired |
| `token_exchange_failed` | 502 | Shopify rejected the authorization code |
| `shop_not_found` | 404 | Shop domain not in database |

## Anti-patterns

**DON'T** accept the access token from the client or store it unencrypted. The offline access token is equivalent to a password — encrypt at rest, never log, never return in API responses.

**DON'T** skip HMAC verification on the callback. Without it, an attacker can forge callbacks with arbitrary authorization codes.

**DON'T** reuse nonces or skip the nonce check. The nonce (state parameter) prevents CSRF attacks on the OAuth callback endpoint.

**DON'T** validate the shop domain with a loose regex that allows subdomains or non-myshopify.com domains. This prevents open redirect attacks.

**DON'T** use the online access token mode for background tasks. Offline tokens persist and work for webhooks, background jobs, and scheduled tasks. Online tokens expire when the merchant's session ends.
