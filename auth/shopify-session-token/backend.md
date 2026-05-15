# Backend Patterns — Shopify Session Token Verification

## Middleware (no API endpoints)

This block exposes no HTTP endpoints. It is a middleware function applied to all authenticated routes.

| Function | Purpose |
|----------|---------|
| `authenticateShopifyRequest` | Express/Hono/Fastify middleware — verify JWT, attach shop context |
| `decodeJwt(token)` | Split and base64url-decode JWT parts |
| `verifySessionToken(token)` | Full verification pipeline — signature + claims |

---

## Authentication Middleware

<!-- PATTERN: shopify-session-token-middleware -->
<!-- PURPOSE: Verify App Bridge JWT on every authenticated API request, attach shop context -->
<!-- ADAPT: Framework middleware signature (Express/Hono/Fastify/Next.js API routes) -->

```typescript
// Apply to all authenticated routes:
// app.use("/api/*", authenticateShopifyRequest);
// or per-route: router.get("/products", authenticateShopifyRequest, handler);

async function authenticateShopifyRequest(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  // 1. Extract Bearer token from Authorization header
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: "missing_token" });
    return;
  }
  const token = authHeader.slice(7); // Remove "Bearer " prefix

  // 2. Verify token and extract claims
  const result = await verifySessionToken(token);
  if (!result.ok) {
    res.status(401).json({ error: result.error });
    return;
  }

  // 3. Look up shop in database
  const shop = await db.query(
    `SELECT id, shop_domain FROM shops WHERE shop_domain = $1 AND uninstalled_at IS NULL`,
    [result.shopDomain]
  );
  if (!shop) {
    res.status(401).json({ error: "shop_not_found" });
    return;
  }

  // 4. Attach shop context to request — available to all downstream handlers
  req.shopContext = {
    shopId: shop.id,
    shopDomain: shop.shop_domain,
    shopifyUserId: result.sub,
  };

  next();
}
```

## JWT Verification

<!-- PATTERN: shopify-jwt-verify -->
<!-- PURPOSE: Decode and cryptographically verify a Shopify App Bridge session token -->
<!-- ADAPT: Crypto library (Node crypto shown; use Web Crypto API for edge runtimes) -->

```typescript
interface VerifyResult {
  ok: true;
  shopDomain: string;
  sub: string;
  aud: string;
  jti: string;
  sid: string;
} | {
  ok: false;
  error: "invalid_token" | "expired_token" | "invalid_audience";
}

async function verifySessionToken(token: string): Promise<VerifyResult> {
  // 1. Split JWT into 3 parts
  const parts = token.split(".");
  if (parts.length !== 3) {
    return { ok: false, error: "invalid_token" };
  }
  const [headerB64, payloadB64, signatureB64] = parts;

  // 2. Verify HMAC-SHA256 signature
  // Sign the "header.payload" string — NOT the decoded bytes
  const signingInput = `${headerB64}.${payloadB64}`;
  const expectedSig = crypto
    .createHmac("sha256", config.SHOPIFY_API_SECRET)
    .update(signingInput)
    .digest("base64url");

  // Constant-time comparison to prevent timing attacks
  const receivedSig = signatureB64;
  if (expectedSig.length !== receivedSig.length) {
    return { ok: false, error: "invalid_token" };
  }
  const sigMatch = crypto.timingSafeEqual(
    Buffer.from(expectedSig),
    Buffer.from(receivedSig)
  );
  if (!sigMatch) {
    return { ok: false, error: "invalid_token" };
  }

  // 3. Decode payload (after signature is verified)
  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(Buffer.from(payloadB64, "base64url").toString("utf8"));
  } catch {
    return { ok: false, error: "invalid_token" };
  }

  // 4. Validate exp (expiry) — tokens live ~1 minute
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp !== "number" || payload.exp < now) {
    return { ok: false, error: "expired_token" };
  }

  // 5. Validate nbf (not-before)
  if (typeof payload.nbf === "number" && payload.nbf > now) {
    return { ok: false, error: "invalid_token" };
  }

  // 6. Validate aud (audience) — must equal app's API key
  if (payload.aud !== config.SHOPIFY_API_KEY) {
    return { ok: false, error: "invalid_audience" };
  }

  // 7. Validate iss (issuer) and dest (destination)
  // iss = "https://{shop}.myshopify.com/admin"
  // dest = "https://{shop}.myshopify.com"
  // Both must reference the same shop, and dest must strip /admin suffix
  if (
    typeof payload.iss !== "string" ||
    typeof payload.dest !== "string" ||
    !payload.iss.startsWith("https://") ||
    !payload.iss.endsWith("/admin") ||
    !payload.dest.startsWith("https://")
  ) {
    return { ok: false, error: "invalid_token" };
  }

  const issShop = payload.iss.replace("https://", "").replace("/admin", "");
  const destShop = payload.dest.replace("https://", "");
  if (issShop !== destShop) {
    return { ok: false, error: "invalid_token" };
  }

  // 8. Extract shop domain and return
  const shopDomain = destShop; // e.g. "example.myshopify.com"
  return {
    ok: true,
    shopDomain,
    sub: String(payload.sub),
    aud: String(payload.aud),
    jti: String(payload.jti ?? ""),
    sid: String(payload.sid ?? ""),
  };
}
```

## JWT Decode Helper (standalone, no verification)

<!-- PATTERN: jwt-decode-helper -->
<!-- PURPOSE: Inspect JWT claims without verifying — for debugging/logging only. Never use for auth. -->
<!-- ADAPT: No changes needed -->

```typescript
// FOR DEBUGGING ONLY — does not verify signature
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

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `missing_token` | 401 | `Authorization` header absent or not `Bearer ...` |
| `invalid_token` | 401 | Malformed JWT, invalid signature, claim format error, iss/dest mismatch, nbf in future |
| `expired_token` | 401 | `exp` claim is in the past — App Bridge will auto-refresh and retry |
| `invalid_audience` | 401 | `aud` claim does not equal `SHOPIFY_API_KEY` |
| `shop_not_found` | 401 | Shop domain from `dest` claim not in `shops` table, or shop is uninstalled |

## Anti-patterns

**DON'T** use a JWT library (`jsonwebtoken`, `jose`) that defaults to RS256 or asymmetric key verification. Shopify session tokens use HMAC-SHA256 (symmetric) — the secret is `SHOPIFY_API_SECRET`. A library misconfigured for asymmetric keys will silently accept forged tokens or always reject valid ones.

**DON'T** decode the payload before verifying the signature. Decoding is cheap, but any business logic that runs on unverified claims is a security hole. Verify first, decode after.

**DON'T** extract the shop from the `sub` claim. The `sub` claim is the Shopify **user** ID (a merchant staff member), not the shop. The shop domain comes from the `dest` claim.

**DON'T** cache session tokens. They are ~1 minute lived and App Bridge refreshes them automatically. Caching adds complexity without benefit and risks serving stale auth context if a shop is uninstalled mid-session.

**DON'T** apply this middleware to webhook endpoints. Webhooks use HMAC body signing (`verifyShopifyHmac` from `auth.shopify-oauth`), not session tokens.
