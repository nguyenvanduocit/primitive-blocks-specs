# Backend Patterns — Shopify Metafields

## API Endpoints

### Metafield Operations

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `POST` | `/api/metafields/sync-definitions` | Register/sync definitions with Shopify | Session token |
| `GET` | `/api/metafield-definitions` | List registered definitions for current shop | Session token |
| `GET` | `/api/metafields/:ownerType/:ownerId` | Read all metafields for a resource | Session token |
| `POST` | `/api/metafields/:ownerType/:ownerId` | Write a single metafield value | Session token |
| `POST` | `/api/metafields/batch` | Write up to 25 metafields in one call | Session token |
| `DELETE` | `/api/metafields/:ownerType/:ownerId/:namespace/:key` | Delete a metafield value | Session token |

All endpoints require the `auth.shopify-session-token` middleware to be applied. The middleware attaches `{ shopId, shopDomain, accessToken }` to the request context.

---

## External Contract Reference (Shopify-dictated)

| Item | Concrete value | Why |
|------|----------------|-----|
| GraphQL mutation for definition creation | `metafieldDefinitionCreate(definition: MetafieldDefinitionInput!)` | Shopify-defined name; do not rename |
| GraphQL mutation for value upsert (batch) | `metafieldsSet(metafields: [MetafieldsSetInput!]!)` — max 25 entries | Shopify-defined batch ceiling |
| GraphQL mutation for value deletion | `metafieldDelete(input: MetafieldDeleteInput!)` | Shopify-defined |
| `ownerType` enum values | `PRODUCT`, `PRODUCTVARIANT`, `ORDER`, `CUSTOMER`, `COLLECTION`, `SHOP`, `COMPANY`, `LOCATION`, `MARKET`, `DRAFTORDER`, `BLOG`, `ARTICLE`, `PAGE`, `MEDIAIMAGE` | Shopify `MetafieldOwnerType` enum |
| `type` string values | See README §7 "Supported Metafield Types" — full enum value list | Shopify metafield type registry |
| Owner ID format | `gid://shopify/{OwnerType}/{numericId}` (e.g. `gid://shopify/Product/123`) | Shopify Global ID convention |
| `userErrors[].code` for already-existing definition | `TAKEN` | Treat as success on re-sync |
| Namespace convention | App-owned prefix (e.g. `myapp`); `$app:` reserved for app-reserved namespace; `global` is Shopify-reserved | Shopify namespace rules |

---

## Definition Sync — Compose 3 sub-patterns

The handler composes: **(1) build mutation** → **(2) call Shopify** → **(3) upsert local record**. Each pattern testable in isolation.

### Pattern 1: Build `metafieldDefinitionCreate` input

<!-- PATTERN: metafield-build-definition-input -->
<!-- PURPOSE: Build the `MetafieldDefinitionInput` payload Shopify expects for one definition -->
<!-- REFERENCE: language=typescript external-contract=shopify-graphql-admin -->
<!-- ADAPT:
       - Field names (`namespace`, `key`, `name`, `description`, `type`, `ownerType`, `pin`): Shopify-dictated, KHÔNG đổi
       - `definition` shape: `{ key, name, type, ownerType, description }` is merchant-side config schema — adapt to your config layer (env JSON, YAML, code constants)
       - `pin` boolean: pins definition card in Shopify Admin UI (merchant visibility), unrelated to storefront access -->

```typescript
interface AppDefinitionConfig {
  key: string; name: string; type: string;
  ownerType: string; description?: string;
}

function buildDefinitionInput(def: AppDefinitionConfig, namespace: string, pin: boolean) {
  return {
    namespace, key: def.key, name: def.name,
    description: def.description ?? null,
    type: def.type, ownerType: def.ownerType, pin,
  };
}
```

### Pattern 2: Call `metafieldDefinitionCreate` mutation

<!-- PATTERN: metafield-definition-create-call -->
<!-- PURPOSE: Send metafieldDefinitionCreate; treat TAKEN userError as success (idempotent re-sync) -->
<!-- REFERENCE: external-contract=shopify-graphql-admin runtime=node20+ -->
<!-- ADAPT:
       - `shopifyGraphQL(...)`: replace with merchant GraphQL client (graphql-request, Apollo, urql, raw fetch)
       - Mutation string body and field selection on `createdDefinition`: Shopify-dictated, KHÔNG đổi
       - `userErrors[].code === "TAKEN"`: external contract — already-exists signal; treat as success
       - Throwing vs returning Result<T,E>: project convention -->

```typescript
const METAFIELD_DEFINITION_CREATE = `
  mutation metafieldDefinitionCreate($definition: MetafieldDefinitionInput!) {
    metafieldDefinitionCreate(definition: $definition) {
      createdDefinition { id namespace key name type { name } ownerType }
      userErrors { field message code }
    }
  }`;

async function callDefinitionCreate(shopDomain: string, token: string, input: object) {
  const resp = await shopifyGraphQL(shopDomain, token, METAFIELD_DEFINITION_CREATE, { definition: input });
  const { createdDefinition, userErrors } = resp.metafieldDefinitionCreate;
  const taken = userErrors?.some((e: { code: string }) => e.code === "TAKEN");
  return { shopifyGid: createdDefinition?.id ?? null, takenAlready: !!taken, otherErrors: taken ? [] : userErrors ?? [] };
}
```

### Pattern 3: Upsert local registry record

<!-- PATTERN: metafield-definition-upsert -->
<!-- PURPOSE: Upsert the local `metafield_definitions` row so app has the registry mirror -->
<!-- REFERENCE: dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - `INSERT ... ON CONFLICT (...) DO UPDATE`: postgres/sqlite syntax. MySQL: `INSERT ... ON DUPLICATE KEY UPDATE`.
       - ORM equivalent: Drizzle `db.insert(metafieldDefinitions).values(...).onConflictDoUpdate(...)`; Prisma `upsert`
       - `COALESCE(EXCLUDED.shopify_gid, metafield_definitions.shopify_gid)`: preserves previous GID on TAKEN re-sync
       - SQL placeholder `$1...`: postgres-style; MySQL/SQLite use `?` -->

```typescript
async function upsertDefinitionRow(
  shopId: string, namespace: string, def: AppDefinitionConfig, shopifyGid: string | null
) {
  await db.query(`
    INSERT INTO metafield_definitions
      (shop_id, namespace, key, owner_type, type, name, description, shopify_gid, synced_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now())
    ON CONFLICT (shop_id, namespace, key, owner_type) DO UPDATE SET
      type = EXCLUDED.type, name = EXCLUDED.name, description = EXCLUDED.description,
      shopify_gid = COALESCE(EXCLUDED.shopify_gid, metafield_definitions.shopify_gid),
      synced_at = now()
  `, [shopId, namespace, def.key, def.ownerType, def.type, def.name, def.description ?? null, shopifyGid]);
}
```

### Composition (the actual handler)

<!-- PATTERN: metafield-definition-sync-handler -->
<!-- PURPOSE: Wire patterns 1→2→3 across all configured definitions; emit event -->
<!-- REFERENCE: framework=generic runtime=node20+ -->
<!-- ADAPT:
       - `req.shopContext`: from `auth.shopify-session-token` middleware (Express `req`, Hono `c.var`, Fastify `req`)
       - `config.METAFIELD_DEFINITIONS` / `config.METAFIELD_NAMESPACE` / `config.METAFIELD_PIN_TO_ADMIN`: merchant config layer
       - Error policy for non-TAKEN userErrors: continue + log (default) vs abort (project choice) -->

```typescript
async function handleSyncDefinitions(req: Request): Promise<Response> {
  const { shopId, shopDomain, accessToken } = req.shopContext;
  const defs = config.METAFIELD_DEFINITIONS ?? [];
  if (defs.length === 0) return json(200, { synced: 0, definitions: [] });
  const out: Array<{ key: string; ownerType: string; shopifyGid: string | null }> = [];
  for (const def of defs) {
    const input = buildDefinitionInput(def, config.METAFIELD_NAMESPACE, config.METAFIELD_PIN_TO_ADMIN);
    const { shopifyGid, otherErrors } = await callDefinitionCreate(shopDomain, accessToken, input);
    if (otherErrors.length > 0) { console.warn("metafield def sync", def.key, otherErrors); continue; }
    await upsertDefinitionRow(shopId, config.METAFIELD_NAMESPACE, def, shopifyGid);
    out.push({ key: def.key, ownerType: def.ownerType, shopifyGid });
  }
  emit("metafield.synced", { shopId, count: out.length, definitions: out });
  return json(200, { synced: out.length, definitions: out });
}
```

---

## List Definitions Handler

<!-- PATTERN: metafield-list-definitions -->
<!-- PURPOSE: Return all registered definitions for the current shop (tenant-scoped) -->
<!-- REFERENCE: dialect=postgres orm=raw-sql framework=generic -->
<!-- ADAPT:
       - `db.query(...)`: ORM-specific — Drizzle `db.select().from(metafieldDefinitions).where(eq(...))`; Prisma `findMany({ where: { shopId } })`
       - SQL placeholder `$1`: postgres-style; MySQL/SQLite use `?`
       - `ORDER BY owner_type, namespace, key`: stable enumeration for admin UI rendering -->

```typescript
async function handleListDefinitions(req: Request): Promise<Response> {
  const { shopId } = req.shopContext;
  const definitions = await db.query(`
    SELECT namespace, key, owner_type, type, name, description, shopify_gid, synced_at
    FROM metafield_definitions
    WHERE shop_id = $1
    ORDER BY owner_type, namespace, key
  `, [shopId]);
  return json(200, { definitions });
}
```

---

## Read Metafields — 2 sub-patterns

The read endpoint composes: **(1) build owner-type GraphQL query** → **(2) execute + extract**.

### Pattern: Build owner-scoped metafield query

<!-- PATTERN: metafield-build-owner-query -->
<!-- PURPOSE: Build a GraphQL query that fetches metafields for the given Shopify owner type -->
<!-- REFERENCE: external-contract=shopify-graphql-admin language=typescript -->
<!-- ADAPT:
       - Root field name per ownerType (`product`, `order`, `customer`, `productVariant`, `collection`, `company`, ...): Shopify-dictated, KHÔNG đổi
       - Extend `cases` list if app supports more owner types from §7 list
       - `first: 50`: page size — increase to 250 (Shopify hard cap) if app expects many fields
       - Namespace inline interpolation: safe here because `namespace` is validated against `METAFIELD_NAMESPACE` config — never accept arbitrary client input -->

```typescript
const OWNER_ROOT_FIELD: Record<string, string> = {
  PRODUCT: "product", PRODUCTVARIANT: "productVariant",
  ORDER: "order", CUSTOMER: "customer", COLLECTION: "collection",
  SHOP: "shop", COMPANY: "company", LOCATION: "location",
};

function buildOwnerMetafieldQuery(ownerType: string, gid: string, namespace?: string) {
  const root = OWNER_ROOT_FIELD[ownerType.toUpperCase()];
  if (!root) throw new AppError(400, "unsupported_owner_type");
  const nsFilter = namespace ? `, namespace: "${namespace}"` : "";
  const query = `query ($id: ID!) {
    ${root}(id: $id) {
      metafields(first: 50${nsFilter}) {
        edges { node { namespace key value type updatedAt } }
      }
    }
  }`;
  return { query, variables: { id: gid }, rootField: root };
}
```

### Pattern: Execute + extract metafields

<!-- PATTERN: metafield-read-handler -->
<!-- PURPOSE: GET metafields for a Shopify resource, scoped to authenticated shop -->
<!-- REFERENCE: framework=generic external-contract=shopify-graphql-admin -->
<!-- ADAPT:
       - `req.params` / `req.query`: framework-specific
       - `decodeURIComponent(ownerId)`: ownerId in URL must be percent-encoded Shopify GID (`gid%3A%2F%2Fshopify%2FProduct%2F123`)
       - `shopifyGraphQL(...)`: merchant GraphQL client
       - Edge-case: GraphQL response root returns `null` when GID not found — return `404` or empty `metafields` array depending on UX choice -->

```typescript
async function handleReadMetafields(req: Request): Promise<Response> {
  const { ownerType, ownerId } = req.params;
  const { namespace } = req.query;
  const { shopDomain, accessToken } = req.shopContext;
  const gid = decodeURIComponent(ownerId);
  const built = buildOwnerMetafieldQuery(ownerType, gid, namespace);
  const resp = await shopifyGraphQL(shopDomain, accessToken, built.query, built.variables);
  const edges = resp?.[built.rootField]?.metafields?.edges ?? [];
  const metafields = edges.map((e: { node: unknown }) => e.node);
  return json(200, { metafields });
}
```

---

## Write Metafield — 3 sub-patterns

Composes: **(1) load type from registry** → **(2) validate value** → **(3) call `metafieldsSet`**.

### Pattern: Load registered type for (shop, namespace, key, ownerType)

<!-- PATTERN: metafield-load-registered-type -->
<!-- PURPOSE: Fetch the registered Shopify type so write can validate locally before remote call -->
<!-- REFERENCE: dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - SQL placeholder `$1`: postgres-style; MySQL/SQLite use `?`
       - ORM equivalent: Drizzle `db.select({ type }).from(metafieldDefinitions).where(and(...))`
       - Tenant isolation rule: `shop_id` MUST come from session context, NEVER from client body — see security.md -->

```typescript
async function loadRegisteredType(
  shopId: string, namespace: string, key: string, ownerType: string
): Promise<string | null> {
  const row = await db.query(`
    SELECT type FROM metafield_definitions
    WHERE shop_id = $1 AND namespace = $2 AND key = $3 AND owner_type = $4
  `, [shopId, namespace, key, ownerType.toUpperCase()]);
  return row?.type ?? null;
}
```

### Pattern: Call `metafieldsSet` mutation

<!-- PATTERN: metafield-set-call -->
<!-- PURPOSE: Send 1..25 metafield entries to Shopify in a single mutation -->
<!-- REFERENCE: external-contract=shopify-graphql-admin runtime=node20+ -->
<!-- ADAPT:
       - Mutation string and field names: Shopify-dictated (`metafieldsSet`, `metafields`, `userErrors`, `MetafieldsSetInput!`) — KHÔNG đổi
       - Entry shape `{ ownerId, namespace, key, type, value }`: Shopify-dictated
       - `userErrors` non-empty → 422 with Shopify-supplied error array (do not paraphrase) -->

```typescript
const METAFIELDS_SET = `
  mutation metafieldsSet($metafields: [MetafieldsSetInput!]!) {
    metafieldsSet(metafields: $metafields) {
      metafields { namespace key value type updatedAt ownerType }
      userErrors { field message code }
    }
  }`;

interface SetEntry { ownerId: string; namespace: string; key: string; type: string; value: string; }

async function callMetafieldsSet(shopDomain: string, token: string, entries: SetEntry[]) {
  const resp = await shopifyGraphQL(shopDomain, token, METAFIELDS_SET, { metafields: entries });
  return resp.metafieldsSet as { metafields: unknown[]; userErrors: { field: string[]; message: string; code: string }[] };
}
```

### Composition: Single-write handler

<!-- PATTERN: metafield-write-handler -->
<!-- PURPOSE: Validate + write a single metafield value, scoped to authenticated shop -->
<!-- REFERENCE: framework=generic -->
<!-- ADAPT:
       - `req.body` extraction: framework-specific
       - `validateMetafieldValue(value, type)`: see Type Validation pattern below
       - `emit(...)`: in-process EventEmitter, queue, pubsub — project choice -->

```typescript
async function handleWriteMetafield(req: Request): Promise<Response> {
  const { ownerType, ownerId } = req.params;
  const { namespace, key, value } = req.body;
  const { shopId, shopDomain, accessToken } = req.shopContext;
  const type = await loadRegisteredType(shopId, namespace, key, ownerType);
  if (!type) return error(404, "definition_not_found");
  const v = validateMetafieldValue(value, type);
  if (!v.valid) return error(400, "type_mismatch", { expected: type, reason: v.reason });
  const { metafields, userErrors } = await callMetafieldsSet(shopDomain, accessToken, [
    { ownerId: decodeURIComponent(ownerId), namespace, key, type, value: String(value) },
  ]);
  if (userErrors.length > 0) return error(422, "shopify_validation_error", { errors: userErrors });
  emit("metafield.set", { shopId, ownerId: decodeURIComponent(ownerId), ownerType, namespace, key });
  return json(200, { metafield: metafields[0] });
}
```

---

## Batch Write — Compose validate-loop + single call

<!-- PATTERN: metafield-batch-validate -->
<!-- PURPOSE: Validate up to 25 entries against their registered types; reject whole batch on first failure -->
<!-- REFERENCE: dialect=postgres -->
<!-- ADAPT:
       - Look-up loop calls `loadRegisteredType` once per entry — for hot paths replace with single `WHERE (namespace,key,owner_type) IN (...)` query + map
       - `25` is external contract from Shopify (`metafieldsSet` ceiling) — KHÔNG đổi
       - Whole-batch reject vs partial-accept: this spec mandates whole-batch reject — atomic semantics simpler for caller -->

```typescript
interface BatchEntry { ownerId: string; ownerType: string; namespace: string; key: string; value: unknown; }

async function validateBatch(shopId: string, entries: BatchEntry[]): Promise<
  { ok: true; validated: SetEntry[] } | { ok: false; reason: string; field?: BatchEntry; expected?: string }
> {
  const out: SetEntry[] = [];
  for (const mf of entries) {
    const type = await loadRegisteredType(shopId, mf.namespace, mf.key, mf.ownerType);
    if (!type) return { ok: false, reason: "definition_not_found", field: mf };
    const v = validateMetafieldValue(mf.value, type);
    if (!v.valid) return { ok: false, reason: v.reason ?? "type_mismatch", field: mf, expected: type };
    out.push({ ownerId: mf.ownerId, namespace: mf.namespace, key: mf.key, type, value: String(mf.value) });
  }
  return { ok: true, validated: out };
}
```

### Composition: Batch handler

<!-- PATTERN: metafield-batch-write-handler -->
<!-- PURPOSE: Enforce 1..25 size, validate each, send single metafieldsSet call -->
<!-- REFERENCE: framework=generic -->
<!-- ADAPT:
       - `req.body.metafields`: input shape from API contract — adapt to your request validation layer (Zod schema, Valibot, manual)
       - 25 limit hard-coded — derived from Shopify external contract, KHÔNG đổi -->

```typescript
async function handleBatchWriteMetafields(req: Request): Promise<Response> {
  const { metafields } = req.body as { metafields?: BatchEntry[] };
  const { shopId, shopDomain, accessToken } = req.shopContext;
  if (!metafields || metafields.length === 0) return error(400, "metafields_required");
  if (metafields.length > 25) return error(400, "batch_size_exceeded", { max: 25, received: metafields.length });
  const r = await validateBatch(shopId, metafields);
  if (!r.ok) return error(400, r.reason === "definition_not_found" ? "definition_not_found" : "type_mismatch", r);
  const { metafields: written, userErrors } = await callMetafieldsSet(shopDomain, accessToken, r.validated);
  if (userErrors.length > 0) return error(422, "shopify_validation_error", { errors: userErrors });
  return json(200, { metafields: written });
}
```

---

## Delete Metafield — 2 sub-patterns

### Pattern: Resolve metafield GID via owner

<!-- PATTERN: metafield-resolve-gid -->
<!-- PURPOSE: Fetch the metafield's Shopify GID by (owner, namespace, key) before deletion -->
<!-- REFERENCE: external-contract=shopify-graphql-admin -->
<!-- ADAPT:
       - Root field per ownerType: reuse `OWNER_ROOT_FIELD` map from `metafield-build-owner-query`
       - GraphQL query body (`metafield(namespace, key) { id }`): Shopify-dictated
       - Return null when Shopify returns null — handler converts to 404 -->

```typescript
async function resolveMetafieldGid(
  shopDomain: string, token: string, ownerType: string, ownerGid: string, namespace: string, key: string
): Promise<string | null> {
  const root = OWNER_ROOT_FIELD[ownerType.toUpperCase()];
  if (!root) return null;
  const query = `query ($id: ID!, $namespace: String!, $key: String!) {
    ${root}(id: $id) { metafield(namespace: $namespace, key: $key) { id } }
  }`;
  const resp = await shopifyGraphQL(shopDomain, token, query, { id: ownerGid, namespace, key });
  return resp?.[root]?.metafield?.id ?? null;
}
```

### Pattern: `metafieldDelete` mutation + handler composition

<!-- PATTERN: metafield-delete-handler -->
<!-- PURPOSE: Resolve GID, send metafieldDelete, return 204; emit deleted event -->
<!-- REFERENCE: external-contract=shopify-graphql-admin framework=generic -->
<!-- ADAPT:
       - Mutation string and `MetafieldDeleteInput!` shape: Shopify-dictated
       - `decodeURIComponent` for path params: required when GIDs and namespace/key are URL-encoded -->

```typescript
const METAFIELD_DELETE = `
  mutation metafieldDelete($input: MetafieldDeleteInput!) {
    metafieldDelete(input: $input) { deletedId userErrors { field message } }
  }`;

async function handleDeleteMetafield(req: Request): Promise<Response> {
  const { ownerType, ownerId, namespace, key } = req.params;
  const { shopId, shopDomain, accessToken } = req.shopContext;
  const ns = decodeURIComponent(namespace), k = decodeURIComponent(key);
  const gid = decodeURIComponent(ownerId);
  const mfGid = await resolveMetafieldGid(shopDomain, accessToken, ownerType, gid, ns, k);
  if (!mfGid) return error(404, "metafield_not_found");
  const resp = await shopifyGraphQL(shopDomain, accessToken, METAFIELD_DELETE, { input: { id: mfGid } });
  if (resp.metafieldDelete.userErrors?.length > 0) {
    return error(422, "shopify_validation_error", { errors: resp.metafieldDelete.userErrors });
  }
  emit("metafield.deleted", { shopId, ownerId: gid, ownerType, namespace: ns, key: k });
  return json(204, null);
}
```

---

## Type Validation Utility — Compose per-category validators

The validator dispatches on the **Shopify-dictated type string** (see README §7). Each category has its own pattern for testability.

### Pattern: Scalar type validators (numeric / date / boolean)

<!-- PATTERN: metafield-scalar-validators -->
<!-- PURPOSE: Validate values against Shopify scalar metafield types before remote call -->
<!-- REFERENCE: external-contract=shopify-metafield-types language=typescript -->
<!-- ADAPT:
       - Type strings (`number_integer`, `number_decimal`, `boolean`, `date`, `date_time`, `money`, `rating`, `dimension`, `volume`, `weight`, `id`): Shopify-dictated, KHÔNG đổi
       - `boolean` accepts only literal "true"/"false" — Shopify rejects "1"/"yes"
       - `date` regex `^YYYY-MM-DD$` — strict per Shopify
       - For `money`/`rating`/`dimension`/`volume`/`weight`: Shopify expects JSON object — handle in JSON-validator branch -->

```typescript
type Ok = { valid: true };
type Bad = { valid: false; reason: string };
type ValidationResult = Ok | Bad;

function validateScalar(value: unknown, type: string): ValidationResult | null {
  const str = String(value);
  switch (type) {
    case "number_integer":
      return Number.isInteger(Number(str)) && !isNaN(Number(str)) ? { valid: true } : { valid: false, reason: `expected integer, got "${str}"` };
    case "number_decimal":
      return !isNaN(parseFloat(str)) && isFinite(Number(str)) ? { valid: true } : { valid: false, reason: `expected decimal, got "${str}"` };
    case "boolean":
      return str === "true" || str === "false" ? { valid: true } : { valid: false, reason: `expected "true"|"false", got "${str}"` };
    case "date":
      return /^\d{4}-\d{2}-\d{2}$/.test(str) && !isNaN(Date.parse(str)) ? { valid: true } : { valid: false, reason: `expected YYYY-MM-DD, got "${str}"` };
    case "date_time":
      return !isNaN(Date.parse(str)) ? { valid: true } : { valid: false, reason: `expected ISO datetime, got "${str}"` };
    case "id":
      return /^\d+$/.test(str) ? { valid: true } : { valid: false, reason: `expected numeric id, got "${str}"` };
  }
  return null; // not handled here
}
```

### Pattern: Structured validators (json / url / color / text / list)

<!-- PATTERN: metafield-structured-validators -->
<!-- PURPOSE: Validate JSON / URL / color / text / list.* metafield values -->
<!-- REFERENCE: external-contract=shopify-metafield-types language=typescript -->
<!-- ADAPT:
       - `color` regex `^#[0-9a-fA-F]{6}$`: Shopify hex format (6-digit)
       - `list.<scalar>` / `list.<reference>` types: value must serialize to JSON array — see §7 for full prefix list
       - Reference types (`product_reference`, `variant_reference`, ...): pass through; Shopify validates GIDs server-side
       - For Shopify metaobject types (`money`, `rating`, `dimension`, `volume`, `weight`): they require JSON value — handled by `json` branch since clients send as serialized JSON -->

```typescript
function validateStructured(value: unknown, type: string): ValidationResult {
  const str = String(value);
  if (["single_line_text_field", "multi_line_text_field", "rich_text_field"].includes(type)) {
    return typeof value === "string" ? { valid: true } : { valid: false, reason: "expected string" };
  }
  if (type === "json" || type === "money" || type === "rating" || type === "dimension" || type === "volume" || type === "weight") {
    try { JSON.parse(str); return { valid: true }; } catch { return { valid: false, reason: `invalid JSON for ${type}` }; }
  }
  if (type === "url") {
    try { new URL(str); return { valid: true }; } catch { return { valid: false, reason: `invalid URL: "${str}"` }; }
  }
  if (type === "color") {
    return /^#[0-9a-fA-F]{6}$/.test(str) ? { valid: true } : { valid: false, reason: `expected #rrggbb, got "${str}"` };
  }
  if (type.startsWith("list.")) {
    try { return Array.isArray(JSON.parse(str)) ? { valid: true } : { valid: false, reason: `${type} requires JSON array` }; }
    catch { return { valid: false, reason: `${type} requires JSON array` }; }
  }
  return { valid: true }; // reference types & unknown types pass through (Shopify validates server-side)
}
```

### Composition: Top-level validator

<!-- PATTERN: metafield-type-validation -->
<!-- PURPOSE: Dispatch value-validation by Shopify type string -->
<!-- REFERENCE: external-contract=shopify-metafield-types -->
<!-- ADAPT:
       - Order of dispatch: scalar first (fast path), then structured
       - To extend with new Shopify types: prefer adding to one of the existing patterns above; only add new pattern if logic shape differs -->

```typescript
function validateMetafieldValue(value: unknown, type: string): ValidationResult {
  const scalar = validateScalar(value, type);
  if (scalar) return scalar;
  return validateStructured(value, type);
}
```

---

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `definition_not_found` | 404 | Namespace+key+ownerType not in local registry for this shop |
| `type_mismatch` | 400 | Value does not match the registered metafield type |
| `unsupported_owner_type` | 400 | ownerType not in supported list (see §7 / external contract table) |
| `metafield_not_found` | 404 | Metafield does not exist on the resource in Shopify |
| `batch_size_exceeded` | 400 | More than 25 metafields in a single batch write request |
| `metafields_required` | 400 | Empty metafields array in batch write |
| `shopify_validation_error` | 422 | Shopify returned userErrors on a mutation |

## Anti-patterns

**DON'T** store metafield values in your app's database. Values live in Shopify — storing them locally creates sync drift and stale data bugs. Always read values via GraphQL.

**DON'T** skip type validation before calling `metafieldsSet`. A type mismatch returns a 422 userError from Shopify — validate locally first for better error messages.

**DON'T** use a generic namespace like `global` or `app`. `global` is reserved by Shopify; pick an app-specific prefix (e.g., `myapp`, `acme`) to avoid collisions.

**DON'T** make individual API calls for each metafield in a batch. `metafieldsSet` accepts up to 25 in a single call — use it to reduce API costs and rate limit consumption.

**DON'T** expose storefront-accessible metafields without explicit intent. Metafields are private by default. To expose via Storefront API, the definition must have `access.storefront` set — this is an intentional opt-in.

**DON'T** accept `shop_id` or `namespace` from client request bodies. Use the verified session-token context for `shop_id`, and validate `namespace` against `METAFIELD_NAMESPACE` config.
