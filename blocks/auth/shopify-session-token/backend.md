# Backend Patterns — Shopify Session Token Verification

## Middleware (no API endpoints)

This block exposes no HTTP endpoints. It is a middleware function applied to all authenticated routes.

| Function | Purpose |
|----------|---------|
| `authenticateShopifyRequest` | Generic middleware — verify JWT, attach shop context |
| `verifySessionToken(token)` | Full verification pipeline — signature + claims |
| `decodeJwtPayload(token)` | Inspect claims WITHOUT verifying — debug only, never auth |

External protocol contract (Shopify-dictated, do not change):

- **Algorithm**: HMAC-SHA256 (header `alg: HS256`, `typ: JWT`) — pinned at verifier; reject any other `alg`
- **Signing key**: `SHOPIFY_API_SECRET` (the app's API secret — symmetric key)
- **Signing input**: the ASCII string `<base64url(header)>.<base64url(payload)>` — sign the encoded string, NOT decoded bytes
- **Signature encoding**: `base64url` (URL-safe base64, no padding)
- **Authorization header**: `Authorization: Bearer <token>` (case-insensitive header name per RFC 7230; `Bearer` scheme per RFC 6750)
- **Required claims**: `iss`, `dest`, `aud`, `exp`, `nbf`, `iat`, `sub`, `jti`, `sid` (see README section 2 for semantics)
- **Token TTL**: ~1 minute (App Bridge auto-refreshes); allow ≤5s clock skew for `exp` / `nbf` checks

---

## Authentication Middleware

<!-- PATTERN: shopify-session-token-middleware -->
<!-- PURPOSE: Verify App Bridge JWT on every authenticated API request, attach shop context -->
<!-- REFERENCE: runtime=node20+ framework=generic crypto=node-builtin -->
<!-- ADAPT:
       - Middleware signature: Express `(req, res, next)`; Hono `(c, next)` with `c.req.header('authorization')` + `c.json(...)`; Fastify `(req, reply)` with `reply.code(401).send(...)`; Next.js Route Handler returns `NextResponse.json(...)`
       - `req.headers.authorization`: case-insensitive in HTTP — most frameworks expose lowercase keys; verify framework's behavior (Hono lowercases; raw `req.headers` in Node is lowercase)
       - `db.query(SQL, params)`: ORM-specific — Drizzle `db.select().from(shops).where(and(eq(shops.shopDomain, d), isNull(shops.uninstalledAt)))`; Prisma `prisma.shop.findFirst({ where: { shopDomain: d, uninstalledAt: null } })`; raw SQL placeholder `$1` is postgres-style; MySQL uses `?`
       - `req.shopContext = ...`: attaches per-request — Express assigns to `req`; Hono uses `c.set('shopContext', ...)`; Fastify uses `req.shopContext` with decorator; Next.js passes via context wrapper -->

```typescript
async function authenticateShopifyRequest(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return res.status(401).json({ error: "missing_token" });
  }
  const token = authHeader.slice(7);

  const result = await verifySessionToken(token); // signature + claims, see below
  if (!result.ok) {
    return res.status(401).json({ error: result.error });
  }

  const shop = await db.query(
    `SELECT id, shop_domain FROM shops WHERE shop_domain = $1 AND uninstalled_at IS NULL`,
    [result.shopDomain]
  );
  if (!shop) {
    return res.status(401).json({ error: "shop_not_found" });
  }

  req.shopContext = {
    shopId: shop.id,
    shopDomain: shop.shop_domain,
    shopifyUserId: result.sub,
  };
  next();
}
```

---

## JWT Verification (Composed Pipeline)

`verifySessionToken` is composed from 4 narrow patterns, applied in order: **structure → signature → time claims → identity claims**. Each pattern is independently testable and ≤30 lines.

### Pattern 1: Decode structure + verify signature

External contract: signature algorithm is **HMAC-SHA256** over `<base64url(header)>.<base64url(payload)>`; comparison MUST be constant-time to prevent timing attacks on the secret.

<!-- PATTERN: shopify-jwt-signature-verify -->
<!-- PURPOSE: Split JWT into 3 parts, verify HMAC-SHA256 signature in constant time before any claim inspection -->
<!-- REFERENCE: runtime=node20+ crypto=node-builtin algorithm=hmac-sha256 -->
<!-- ADAPT:
       - `crypto.createHmac`/`timingSafeEqual`: edge/Workers/Deno → Web Crypto `subtle.importKey({name:"HMAC",hash:"SHA-256"}) + subtle.sign("HMAC", key, data)`; constant-time compare via XOR-accumulator loop because Web Crypto doesn't expose `timingSafeEqual`
       - `Buffer.from(s, "base64url")` (Node 16+): browser/edge → manual decode (URL-safe → standard base64, then `atob`)
       - Algorithm `sha256` and signing-input format `header.payload` (ASCII bytes): STRICT external contract — DO NOT change -->

```typescript
type SigOk = { ok: true; headerB64: string; payloadB64: string };
type SigFail = { ok: false; error: "invalid_token" };

function verifyJwtSignature(token: string, secret: string): SigOk | SigFail {
  const parts = token.split(".");
  if (parts.length !== 3) return { ok: false, error: "invalid_token" };
  const [headerB64, payloadB64, signatureB64] = parts;

  const expectedSig = crypto
    .createHmac("sha256", secret)
    .update(`${headerB64}.${payloadB64}`)
    .digest("base64url");

  if (expectedSig.length !== signatureB64.length) {
    return { ok: false, error: "invalid_token" };
  }
  const match = crypto.timingSafeEqual(
    Buffer.from(expectedSig),
    Buffer.from(signatureB64)
  );
  return match
    ? { ok: true, headerB64, payloadB64 }
    : { ok: false, error: "invalid_token" };
}
```

### Pattern 2: Decode payload (after signature verified)

<!-- PATTERN: shopify-jwt-payload-decode -->
<!-- PURPOSE: Base64url-decode and JSON-parse the JWT payload AFTER signature verification succeeded -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `Buffer.from(s, "base64url")`: Node 16+ supports `base64url` encoding directly; older runtimes → manual replace `-`→`+`, `_`→`/`, pad with `=`, then `base64` decode (or browser `atob` + URL-safe normalize)
       - `JSON.parse`: standard; wrap in try/catch — malformed JSON = `invalid_token` -->

```typescript
type PayloadOk = { ok: true; payload: Record<string, unknown> };
type PayloadFail = { ok: false; error: "invalid_token" };

function decodePayload(payloadB64: string): PayloadOk | PayloadFail {
  try {
    const json = Buffer.from(payloadB64, "base64url").toString("utf8");
    const payload = JSON.parse(json);
    if (typeof payload !== "object" || payload === null) {
      return { ok: false, error: "invalid_token" };
    }
    return { ok: true, payload: payload as Record<string, unknown> };
  } catch {
    return { ok: false, error: "invalid_token" };
  }
}
```

### Pattern 3: Validate time claims (`exp`, `nbf`)

External contract: `exp` and `nbf` are unix seconds (numeric). App Bridge tokens live ~1 minute; allow ≤5s clock skew.

<!-- PATTERN: shopify-jwt-time-claims -->
<!-- PURPOSE: Enforce token lifetime — reject expired or not-yet-valid tokens with a small clock-skew tolerance -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `Date.now() / 1000`: standard unix-seconds conversion; same across JS runtimes
       - Clock skew `5`: tune via config if NTP drift is observed; never set above 30s
       - Error code split: `exp` failure returns `expired_token` (App Bridge will auto-refresh and retry); `nbf` failure returns `invalid_token` (clock issue or forgery) -->

```typescript
type TimeOk = { ok: true };
type TimeFail = { ok: false; error: "expired_token" | "invalid_token" };

function validateTimeClaims(
  payload: Record<string, unknown>,
  clockSkewSeconds = 5
): TimeOk | TimeFail {
  const now = Math.floor(Date.now() / 1000);

  if (typeof payload.exp !== "number" || payload.exp + clockSkewSeconds < now) {
    return { ok: false, error: "expired_token" };
  }
  if (typeof payload.nbf === "number" && payload.nbf - clockSkewSeconds > now) {
    return { ok: false, error: "invalid_token" };
  }
  return { ok: true };
}
```

### Pattern 4: Validate identity claims (`aud`, `iss`, `dest`)

External contract: `iss` = `https://{shop}.myshopify.com/admin`, `dest` = `https://{shop}.myshopify.com`, `aud` = the app's `SHOPIFY_API_KEY`. `iss` and `dest` MUST reference the same shop — mismatch = forged or cross-shop attack.

<!-- PATTERN: shopify-jwt-identity-claims -->
<!-- PURPOSE: Enforce audience (this app) and issuer/destination (same shop) — prevents cross-app and cross-shop attacks -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - String manipulation (`startsWith`/`endsWith`/`replace`): standard; same across runtimes
       - URL parsing alternative: `new URL(iss).hostname` works in all modern runtimes — equally acceptable if you prefer explicit URL parsing over string ops
       - `aud` shape: Shopify always sends string `aud` (single value); generic JWT spec also allows `string[]` — for Shopify session tokens, string-only is the contract -->

```typescript
type IdOk = { ok: true; shopDomain: string };
type IdFail = { ok: false; error: "invalid_token" | "invalid_audience" };

function validateIdentityClaims(
  payload: Record<string, unknown>,
  expectedAud: string
): IdOk | IdFail {
  if (payload.aud !== expectedAud) {
    return { ok: false, error: "invalid_audience" };
  }
  const iss = payload.iss, dest = payload.dest;
  if (typeof iss !== "string" || typeof dest !== "string") {
    return { ok: false, error: "invalid_token" };
  }
  if (!iss.startsWith("https://") || !iss.endsWith("/admin") || !dest.startsWith("https://")) {
    return { ok: false, error: "invalid_token" };
  }
  const issShop = iss.slice("https://".length, -"/admin".length);
  const destShop = dest.slice("https://".length);
  if (issShop !== destShop) {
    return { ok: false, error: "invalid_token" };
  }
  return { ok: true, shopDomain: destShop };
}
```

### Composition

The 4 patterns above compose into the public `verifySessionToken`:

<!-- PATTERN: shopify-jwt-verify-compose -->
<!-- PURPOSE: Compose signature + payload + time + identity checks in strict order — fail fast at each step -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - Error-handling style: `Result<T,E>` discriminated-union shown; throw-based equivalent: throw HttpError(401, code) at each fail and catch in middleware
       - `sub`/`jti`/`sid` extraction: kept as strings; if downstream needs strict typing, validate with Zod/Valibot/io-ts schema before assignment -->

```typescript
type VerifyResult =
  | { ok: true; shopDomain: string; sub: string; aud: string; jti: string; sid: string }
  | { ok: false; error: "invalid_token" | "expired_token" | "invalid_audience" };

async function verifySessionToken(token: string): Promise<VerifyResult> {
  const sig = verifyJwtSignature(token, config.SHOPIFY_API_SECRET);
  if (!sig.ok) return sig;

  const dec = decodePayload(sig.payloadB64);
  if (!dec.ok) return dec;

  const time = validateTimeClaims(dec.payload);
  if (!time.ok) return time;

  const id = validateIdentityClaims(dec.payload, config.SHOPIFY_API_KEY);
  if (!id.ok) return id;

  const p = dec.payload;
  return {
    ok: true,
    shopDomain: id.shopDomain,
    sub: String(p.sub ?? ""),
    aud: String(p.aud),
    jti: String(p.jti ?? ""),
    sid: String(p.sid ?? ""),
  };
}
```

---

## JWT Decode Helper (debug only, no verification)

<!-- PATTERN: jwt-decode-helper-debug-only -->
<!-- PURPOSE: Inspect JWT claims without verifying — DEBUG/LOGGING ONLY. Never use the returned payload for authentication or authorization. -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `Buffer.from(s, "base64url")`: Node 16+; browser/edge → URL-safe base64 normalize + `atob`
       - Hard rule: this helper MUST NOT be exported from any module used in request-handling code paths — restrict to dev tooling / log-formatter modules to prevent accidental use as auth -->

```typescript
function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
  } catch {
    return null;
  }
}
```

---

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `missing_token` | 401 | `Authorization` header absent or not `Bearer ...` |
| `invalid_token` | 401 | Malformed JWT, invalid signature, claim format error, `iss`/`dest` mismatch, `nbf` in future, malformed payload JSON |
| `expired_token` | 401 | `exp` claim is in the past (beyond clock-skew tolerance) — App Bridge will auto-refresh and retry |
| `invalid_audience` | 401 | `aud` claim does not equal `SHOPIFY_API_KEY` |
| `shop_not_found` | 401 | Shop domain from `dest` claim not in `shops` table, or shop is uninstalled |

## Anti-patterns

**DON'T** use a JWT library defaulting to RS256 / asymmetric key verification. Shopify session tokens use HMAC-SHA256 (symmetric, header `alg: HS256`); the key is `SHOPIFY_API_SECRET`. A misconfigured library may silently accept forged tokens or reject valid ones. Always pin algorithm to `HS256` at the verifier level (e.g., `jose.jwtVerify(..., { algorithms: ["HS256"] })`).

**DON'T** decode the payload before verifying the signature. Decoding is cheap, but any business logic that runs on unverified claims is a security hole. Verify first, decode after.

**DON'T** extract the shop from the `sub` claim. `sub` is the Shopify **staff user** ID, not the shop. Shop domain comes from `dest`.

**DON'T** cache session tokens. They are ~1 minute lived; App Bridge refreshes automatically. Caching adds complexity and risks serving stale auth context if a shop is uninstalled mid-session.

**DON'T** apply this middleware to webhook endpoints. Webhooks use HMAC body signing (`verifyShopifyHmac` from `auth.shopify-oauth`), not session tokens.

**DON'T** trust the `alg` header from the token. Pin the algorithm at the verifier — never branch on `header.alg`. The classic `alg: none` attack and HS-vs-RS confusion attacks both depend on the verifier honoring the attacker-supplied `alg`.
