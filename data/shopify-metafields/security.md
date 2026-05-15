# Security — Shopify Metafields

## Threat Model

### 1. Scope Mismatch

**Impact**: High — API calls will fail if the app's access token lacks the required scopes for the resource type being accessed. Worse, partial scope grants may allow reads but not writes, causing silent failures.

**Mitigations**:
- Validate required scopes on startup or before first API call: `read_products`/`write_products` for PRODUCT owner type, `read_orders`/`write_orders` for ORDER, etc.
- Surface scope errors clearly to the developer at configuration time, not at runtime for the merchant
- Store granted scopes in the `shops.scopes` column (set by `auth.shopify-oauth`) and check before API calls
- Required scope mapping per ownerType:

| ownerType | Read scope | Write scope |
|-----------|-----------|-------------|
| `PRODUCT` | `read_products` | `write_products` |
| `ORDER` | `read_orders` | `write_orders` |
| `CUSTOMER` | `read_customers` | `write_customers` |
| `SHOP` | `read_content` | `write_content` |

### 2. Namespace Collision

**Impact**: Medium — if two apps use the same namespace, they can overwrite each other's metafields. Apps using `global` namespace can conflict with Shopify's own reserved namespace.

**Mitigations**:
- Use app-specific namespace: configure `METAFIELD_NAMESPACE` to a unique prefix (e.g., `acme`, `myapp-slug`)
- Reject `global` as a namespace value — it is reserved by Shopify
- All API endpoints scope reads and writes to the configured namespace; never accept arbitrary namespace from the client without validating it is the app's own namespace
- Local `metafield_definitions` registry is keyed on `(shop_id, namespace, key, owner_type)` — only definitions belonging to this shop's configured namespace are stored

### 3. Type Mismatch

**Impact**: Low (API error) to Medium (data corruption) — sending a value that doesn't match the registered type causes a 422 from Shopify, or worse, silently stores an invalid value if types are loose.

**Mitigations**:
- Always validate value against the registered type from `metafield_definitions` before calling `metafieldsSet`
- `validateMetafieldValue()` covers all supported types with strict checks (integer, decimal, boolean, date, datetime, JSON, URL, color, lists)
- Return `400 type_mismatch` with a clear message before making any Shopify API call
- Never trust the `type` field from the client request — always fetch type from the local registry for the authenticated shop

### 4. Data Leakage via Storefront

**Impact**: High — metafields set as storefront-accessible expose data to the public Storefront API. If sensitive data (order notes, customer identifiers, internal flags) is stored in a storefront-accessible metafield, it becomes publicly readable.

**Mitigations**:
- Metafields are **private by default** — no Storefront API access unless `access.storefront` is explicitly set on the definition
- `METAFIELD_PIN_TO_ADMIN` controls admin UI pinning only — it does not change storefront visibility
- Never set `storefrontAccess` on definitions that may contain sensitive data (order details, customer PII, internal pricing)
- Document explicitly in `METAFIELD_DEFINITIONS` config which fields (if any) require storefront access and why

### 5. Rate Limiting

**Impact**: Medium — metafield API calls consume Shopify GraphQL cost points. High-volume writes (e.g., bulk product updates) can exhaust rate limits, causing 429 errors and degraded app performance.

**Mitigations**:
- Use `metafieldsSet` with up to 25 metafields per call instead of individual write calls — reduces API cost proportionally
- Enforce the 25-item limit in the batch endpoint (`batch_size_exceeded` error before any API call)
- The shared GraphQL Admin API client (from `auth.shopify-oauth`) handles 429 responses with `Retry-After` respect and exponential backoff
- For bulk metafield updates across many resources, prefer `operations.shopify-bulk` (bulk mutations) over repeated `metafieldsSet` calls

## Input Validation Rules

| Field | Validation | Error Code |
|-------|-----------|------------|
| `ownerType` (URL param) | Required, one of: `PRODUCT`, `ORDER`, `CUSTOMER`, `SHOP`, `VARIANT`, `COLLECTION` | `unsupported_owner_type` |
| `ownerId` (URL param) | Required, must be URL-encoded Shopify GID (`gid://shopify/...`) | `invalid_owner_id` |
| `namespace` (body/query) | Required, non-empty, matches app's configured namespace | `namespace_not_allowed` |
| `key` (body) | Required, non-empty string, alphanumeric + underscores | `invalid_key` |
| `value` (body) | Required, must pass type validation for registered type | `type_mismatch` |
| `metafields` (batch body) | Required array, length 1–25 | `batch_size_exceeded`, `metafields_required` |

## Tenant Isolation

Every database query includes `shop_id` in the WHERE clause. The `shop_id` is extracted from the verified session token (never from the request body or query params). A merchant cannot read or write another shop's definitions.

```typescript
// CORRECT — shop_id from verified session context
const definition = await db.query(
  `SELECT type FROM metafield_definitions WHERE shop_id = $1 AND namespace = $2 AND key = $3`,
  [req.shopContext.shopId, namespace, key]
);

// WRONG — never accept shop_id from client
const definition = await db.query(
  `SELECT type FROM metafield_definitions WHERE shop_id = $1`,
  [req.body.shopId]  // attacker-controlled
);
```

## Secrets Management

| Secret | Storage | Rotation |
|--------|---------|----------|
| `SHOPIFY_API_KEY` | Environment variable | Via `auth.shopify-oauth` |
| `SHOPIFY_API_SECRET` | Environment variable | Via `auth.shopify-oauth` |
| Shop access tokens | Database (encrypted, via `auth.shopify-oauth`) | On reinstall |
| `METAFIELD_NAMESPACE` | Environment variable | Changing requires re-sync of all definitions |
