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
<!-- REFERENCE: runtime=node20+ framework=generic crypto=node-builtin -->
<!-- ADAPT:
       - `req.query` / `Response` / `redirect()`: thay bằng abstraction của framework (Express `req.query` + `res.redirect`; Hono `c.req.query()` + `c.redirect`; Fastify `req.query` + `reply.redirect`)
       - `crypto.randomBytes`: edge runtime → `crypto.getRandomValues(new Uint8Array(16))` + hex encode
       - `db.insert`: ORM-specific (Drizzle `db.insert(oauthNonces).values(...)`, Prisma `prisma.oauthNonces.create(...)`, raw SQL `INSERT INTO oauth_nonces`) -->

```typescript
// GET /api/auth/shopify?shop=example.myshopify.com

async function handleInstallRedirect(req: Request): Promise<Response> {
  const shop = req.query.shop;

  // 1. Validate shop domain (via shop-domain-validation pattern below)
  if (!shop || !isValidShopDomain(shop)) {
    return error(400, "invalid_shop_domain");
  }

  // 2. Generate cryptographically random nonce (16 bytes → 32 hex chars)
  const nonce = crypto.randomBytes(16).toString("hex");

  // 3. Store nonce with TTL
  await db.insert("oauth_nonces", {
    nonce,
    shop_domain: shop,
    expires_at: new Date(Date.now() + config.OAUTH_NONCE_TTL_SECONDS * 1000),
  });

  // 4. Build Shopify authorize URL (external contract: param names from Shopify docs)
  const authUrl = new URL(`https://${shop}/admin/oauth/authorize`);
  authUrl.searchParams.set("client_id", config.SHOPIFY_API_KEY);
  authUrl.searchParams.set("scope", config.SHOPIFY_SCOPES);
  authUrl.searchParams.set("redirect_uri", `${config.APP_URL}/api/auth/shopify/callback`);
  authUrl.searchParams.set("state", nonce);

  return redirect(302, authUrl.toString());
}
```

### Shop Domain Validation (Shared Utility)

External contract: Shopify shop URLs phải match `*.myshopify.com` exactly. Bất kỳ regex lỏng hơn (cho phép subdomain bậc 2, cho phép path, cho phép domain khác) đều tạo **open redirect vulnerability** — attacker craft shop param `evil.attacker.com.myshopify.com` hoặc tương tự.

<!-- PATTERN: shopify-shop-domain-validation -->
<!-- PURPOSE: Strict regex check that shop is exactly `<subdomain>.myshopify.com` — prevents open redirect -->
<!-- REFERENCE: language=typescript regex-flavor=ecmascript -->
<!-- ADAPT:
       - Regex flavor: ECMAScript regex syntax — chuyển sang PCRE/POSIX nếu dùng language khác
       - Subdomain charset `[a-zA-Z0-9][a-zA-Z0-9\-]*`: Shopify dictates alphanumeric + hyphen, không bắt đầu bằng hyphen
       - KHÔNG nới lỏng regex để "thuận tiện" — đây là security boundary -->

```typescript
function isValidShopDomain(shop: string): boolean {
  return /^[a-zA-Z0-9][a-zA-Z0-9\-]*\.myshopify\.com$/.test(shop);
}
```

## OAuth Callback Handler

Callback flow chia 3 pattern độc lập, compose theo thứ tự: **verify → exchange → upsert**. Mỗi pattern là 1 trách nhiệm rõ, dễ test riêng.

### Pattern 1: Verify callback (HMAC + shop + nonce)

<!-- PATTERN: shopify-oauth-callback-verify -->
<!-- PURPOSE: Verify callback authenticity — HMAC signature, shop domain format, single-use nonce -->
<!-- REFERENCE: runtime=node20+ framework=generic -->
<!-- ADAPT:
       - `req.query`: framework-specific (Express/Hono/Fastify đều có equivalent)
       - `db.query(SQL, params)`: ORM-specific (Drizzle `db.select().from(...)`, Prisma `findFirst`, raw SQL với placeholder tuỳ driver)
       - SQL placeholder `$1`: postgres-style; MySQL dùng `?`; SQLite hỗ trợ cả 2 -->

```typescript
// GET /api/auth/shopify/callback?code=...&hmac=...&shop=...&state=...&timestamp=...

async function verifyCallback(req: Request): Promise<{ shop: string; code: string }> {
  const { code, hmac, shop, state, timestamp, ...rest } = req.query;

  // External contract: HMAC computed over all query params EXCEPT `hmac` and `signature`,
  // sorted alphabetically, joined with `&`, format `key=value`
  const params = { code, shop, state, timestamp, ...rest };
  const sortedParams = Object.keys(params).sort()
    .map(key => `${key}=${params[key]}`).join("&");

  if (!verifyShopifyHmac(config.SHOPIFY_API_SECRET, sortedParams, hmac)) {
    throw new HttpError(401, "hmac_verification_failed");
  }
  if (!isValidShopDomain(shop)) {
    throw new HttpError(400, "invalid_shop_domain");
  }

  // Nonce check + single-use deletion (atomic — race window negligible vs install rate)
  const nonceRecord = await db.query(
    `SELECT * FROM oauth_nonces WHERE nonce = $1 AND expires_at > now()`, [state]
  );
  if (!nonceRecord) throw new HttpError(401, "invalid_or_expired_state");
  await db.query(`DELETE FROM oauth_nonces WHERE nonce = $1`, [state]);

  return { shop, code };
}
```

### Pattern 2: Exchange code for offline access token

<!-- PATTERN: shopify-oauth-token-exchange -->
<!-- PURPOSE: POST authorization code to Shopify, receive offline access token + granted scopes -->
<!-- REFERENCE: runtime=node20+ http=fetch-builtin -->
<!-- ADAPT:
       - `fetch`: Node 18+ built-in, OK across runtimes; Node <18 → `undici` hoặc `node-fetch`
       - Response shape `{ access_token, scope }`: external contract from Shopify, KHÔNG đổi
       - Error handling style: throw HttpError vs return Result<T,E> tuỳ project convention -->

```typescript
async function exchangeCodeForToken(shop: string, code: string): Promise<{
  accessToken: string;
  scope: string;
}> {
  // External contract: POST to https://{shop}/admin/oauth/access_token
  // Body: { client_id, client_secret, code } — Shopify-dictated shape
  const resp = await fetch(`https://${shop}/admin/oauth/access_token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_id: config.SHOPIFY_API_KEY,
      client_secret: config.SHOPIFY_API_SECRET,
      code,
    }),
  });

  if (!resp.ok) throw new HttpError(502, "token_exchange_failed");
  const { access_token, scope } = await resp.json();
  return { accessToken: access_token, scope };
}
```

### Pattern 3: Upsert shop record + emit event + redirect

<!-- PATTERN: shopify-oauth-shop-upsert -->
<!-- PURPOSE: Encrypt token, upsert shop (handle reinstall via ON CONFLICT), emit installed event, redirect to embedded app -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - SQL `ON CONFLICT (col) DO UPDATE`: postgres-only; MySQL dùng `INSERT ... ON DUPLICATE KEY UPDATE`; SQLite dùng `INSERT ... ON CONFLICT(col) DO UPDATE` (giống PG syntax)
       - `emit(eventName, payload)`: event bus tuỳ project (in-process EventEmitter, Redis pubsub, queue worker, etc.)
       - `redirect(status, url)`: framework-specific -->

```typescript
async function upsertShopAndComplete(
  shop: string, accessToken: string, scope: string
): Promise<Response> {
  const encryptedToken = encrypt(accessToken);

  const shopRecord = await db.query(`
    INSERT INTO shops (shop_domain, access_token, scopes, installed_at, uninstalled_at)
    VALUES ($1, $2, $3, now(), null)
    ON CONFLICT (shop_domain) DO UPDATE SET
      access_token = $2, scopes = $3,
      installed_at = now(), uninstalled_at = null, updated_at = now()
    RETURNING *
  `, [shop, encryptedToken, scope]);

  emit("shop.installed", { shopId: shopRecord.id, shopDomain: shop, scopes: scope });

  // External contract: embedded app URL pattern dictated by Shopify
  return redirect(302, `https://${shop}/admin/apps/${config.SHOPIFY_API_KEY}`);
}
```

### Composition (the actual handler)

The 3 patterns above compose into the route handler:

```typescript
async function handleOAuthCallback(req: Request): Promise<Response> {
  const { shop, code } = await verifyCallback(req);
  const { accessToken, scope } = await exchangeCodeForToken(shop, code);
  return upsertShopAndComplete(shop, accessToken, scope);
}
```

## HMAC Verification (Shared Utility)

External contract: Shopify dictates **HMAC-SHA256** as the signing algorithm — KHÔNG được đổi sang thuật toán khác. Constant-time comparison là requirement bảo mật (chống timing attack).

<!-- PATTERN: shopify-hmac-verify -->
<!-- PURPOSE: Constant-time HMAC-SHA256 verification — used by OAuth, webhooks, GDPR, app proxy -->
<!-- REFERENCE: runtime=node20+ crypto=node-builtin algorithm=hmac-sha256 -->
<!-- ADAPT:
       - `crypto.createHmac`/`timingSafeEqual`: edge/Workers/Deno → Web Crypto API (`subtle.importKey` + `subtle.sign("HMAC", ...)`); manual constant-time compare bằng `XOR + accumulator` pattern
       - Output encoding `hex`: KHÔNG đổi (Shopify dùng hex cho callback HMAC, base64 cho webhook body HMAC — kiểm context trước khi truyền expectedHmac)
       - Algorithm `sha256`: KHÔNG đổi — external contract -->

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

  // Constant-time comparison — required to prevent timing attacks
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
<!-- REFERENCE: runtime=node20+ dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - `db.query(SQL, params)`: ORM-specific — Drizzle: `db.select().from(shops).where(eq(shops.shopDomain, domain))`; Prisma: `prisma.shop.findFirst({ where: { shopDomain: domain, uninstalledAt: null } })`; Kysely: `db.selectFrom('shops').where('shop_domain', '=', domain)`
       - `IS NULL` check: same across SQL dialects
       - `decrypt()`: dùng utility từ Token Encryption pattern bên dưới -->

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

External contract: Shopify access token là material nhạy cảm. **AES-256-GCM** được recommend vì cung cấp confidentiality + integrity (authenticated encryption) — merchant có thể chọn algorithm khác miễn là authenticated encryption (e.g., ChaCha20-Poly1305).

<!-- PATTERN: token-encryption -->
<!-- PURPOSE: Encrypt/decrypt Shopify access tokens at rest — confidentiality + integrity -->
<!-- REFERENCE: runtime=node20+ crypto=node-builtin algorithm=aes-256-gcm -->
<!-- ADAPT:
       - `crypto.createCipheriv`/`createDecipheriv`: edge/Workers → Web Crypto `subtle.encrypt({ name: "AES-GCM", iv })`
       - Algorithm choice: AES-256-GCM recommended; ChaCha20-Poly1305 acceptable nếu runtime hỗ trợ; KHÔNG dùng AES-CBC (không có integrity), KHÔNG dùng AES-ECB
       - Key management: env var `TOKEN_ENCRYPTION_KEY` (hex string, 32 bytes); production → KMS-managed (AWS KMS, GCP KMS, HashiCorp Vault)
       - Serialization format `iv:tag:ciphertext`: tuỳ project — JSON, binary concat, separate columns đều OK miễn là parseable
       - IV size 12 bytes: AES-GCM standard, KHÔNG đổi -->

```typescript
const ALGORITHM = "aes-256-gcm";

function encrypt(plaintext: string): string {
  const iv = crypto.randomBytes(12); // 12 bytes is AES-GCM standard
  const cipher = crypto.createCipheriv(ALGORITHM, getEncryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
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
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - `db.query` + `RETURNING id`: postgres-specific; MySQL dùng affected rows count, SQLite dùng `changes()`; hoặc đơn giản `DELETE` + đếm row count từ result
       - Job scheduler: cron job (`node-cron`), queue (BullMQ delayed), platform-native (Vercel cron, CF Workers cron), hoặc DB job runner (pg_cron); recommend chạy mỗi 10 min -->

```typescript
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
