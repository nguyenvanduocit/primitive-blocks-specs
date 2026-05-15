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

## Definition Sync Handler

<!-- PATTERN: metafield-definition-sync -->
<!-- PURPOSE: Register app's metafield definitions with Shopify on install or config change -->
<!-- ADAPT: GraphQL client, DB client -->

```typescript
// POST /api/metafields/sync-definitions
// Called after install and when METAFIELD_DEFINITIONS config changes

async function handleSyncDefinitions(req: Request): Promise<Response> {
  const { shopId, shopDomain, accessToken } = req.shopContext;
  const definitions = config.METAFIELD_DEFINITIONS;

  if (!definitions || definitions.length === 0) {
    return json(200, { synced: 0, definitions: [] });
  }

  const results = [];

  for (const def of definitions) {
    const mutation = `
      mutation metafieldDefinitionCreate($definition: MetafieldDefinitionInput!) {
        metafieldDefinitionCreate(definition: $definition) {
          createdDefinition {
            id
            namespace
            key
            name
            type { name }
            ownerType
          }
          userErrors {
            field
            message
            code
          }
        }
      }
    `;

    const variables = {
      definition: {
        namespace: config.METAFIELD_NAMESPACE,
        key: def.key,
        name: def.name,
        description: def.description ?? null,
        type: def.type,
        ownerType: def.ownerType,
        pin: config.METAFIELD_PIN_TO_ADMIN,
      },
    };

    const response = await shopifyGraphQL(shopDomain, accessToken, mutation, variables);
    const { createdDefinition, userErrors } = response.metafieldDefinitionCreate;

    if (userErrors && userErrors.length > 0) {
      // TAKEN_BY_MERCHANT_RESOURCE — definition already exists, that's OK
      const alreadyExists = userErrors.some(e => e.code === "TAKEN");
      if (!alreadyExists) {
        // Log non-ignorable errors but continue syncing others
        console.warn(`metafield definition sync error for ${def.key}:`, userErrors);
        continue;
      }
    }

    const shopifyGid = createdDefinition?.id ?? null;

    // Upsert local registry record
    await db.query(`
      INSERT INTO metafield_definitions
        (shop_id, namespace, key, owner_type, type, name, description, shopify_gid, synced_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now())
      ON CONFLICT (shop_id, namespace, key, owner_type) DO UPDATE SET
        type = EXCLUDED.type,
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        shopify_gid = COALESCE(EXCLUDED.shopify_gid, metafield_definitions.shopify_gid),
        synced_at = now()
    `, [shopId, config.METAFIELD_NAMESPACE, def.key, def.ownerType, def.type, def.name, def.description ?? null, shopifyGid]);

    results.push({ key: def.key, ownerType: def.ownerType, shopifyGid });
  }

  emit("metafield.synced", { shopId, count: results.length, definitions: results });

  return json(200, { synced: results.length, definitions: results });
}
```

---

## List Definitions Handler

<!-- PATTERN: metafield-list-definitions -->
<!-- PURPOSE: Return all registered definitions for the current shop -->
<!-- ADAPT: DB client -->

```typescript
// GET /api/metafield-definitions

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

## Read Metafields Handler

<!-- PATTERN: metafield-read -->
<!-- PURPOSE: Fetch metafield values from Shopify for a given resource -->
<!-- ADAPT: GraphQL client -->

```typescript
// GET /api/metafields/:ownerType/:ownerId?namespace=myapp

async function handleReadMetafields(req: Request): Promise<Response> {
  const { ownerType, ownerId } = req.params;
  const { namespace } = req.query;
  const { shopDomain, accessToken } = req.shopContext;

  // ownerId must be a full Shopify GID: gid://shopify/Product/123
  const gid = decodeURIComponent(ownerId);

  const ownerQuery = buildOwnerQuery(ownerType, gid, namespace);
  const response = await shopifyGraphQL(shopDomain, accessToken, ownerQuery.query, ownerQuery.variables);

  const metafields = extractMetafields(ownerType, response);

  return json(200, { metafields });
}

function buildOwnerQuery(ownerType: string, gid: string, namespace?: string) {
  // Build type-appropriate query — resource type determines the root query field
  const nsFilter = namespace ? `, namespace: "${namespace}"` : "";

  switch (ownerType.toUpperCase()) {
    case "PRODUCT":
      return {
        query: `query ($id: ID!) {
          product(id: $id) {
            metafields(first: 50${nsFilter}) {
              edges { node { namespace key value type updatedAt } }
            }
          }
        }`,
        variables: { id: gid },
      };
    case "ORDER":
      return {
        query: `query ($id: ID!) {
          order(id: $id) {
            metafields(first: 50${nsFilter}) {
              edges { node { namespace key value type updatedAt } }
            }
          }
        }`,
        variables: { id: gid },
      };
    case "CUSTOMER":
      return {
        query: `query ($id: ID!) {
          customer(id: $id) {
            metafields(first: 50${nsFilter}) {
              edges { node { namespace key value type updatedAt } }
            }
          }
        }`,
        variables: { id: gid },
      };
    default:
      throw new AppError(400, "unsupported_owner_type");
  }
}
```

---

## Write Metafield Handler

<!-- PATTERN: metafield-write -->
<!-- PURPOSE: Set a single metafield value with type validation -->
<!-- ADAPT: GraphQL client, DB client -->

```typescript
// POST /api/metafields/:ownerType/:ownerId
// Body: { namespace: string, key: string, value: string }

async function handleWriteMetafield(req: Request): Promise<Response> {
  const { ownerType, ownerId } = req.params;
  const { namespace, key, value } = req.body;
  const { shopId, shopDomain, accessToken } = req.shopContext;

  const gid = decodeURIComponent(ownerId);

  // 1. Look up type from local definition registry
  const definition = await db.query(`
    SELECT type FROM metafield_definitions
    WHERE shop_id = $1 AND namespace = $2 AND key = $3 AND owner_type = $4
  `, [shopId, namespace, key, ownerType.toUpperCase()]);

  if (!definition) {
    return error(404, "definition_not_found");
  }

  // 2. Validate value against the registered type
  const validation = validateMetafieldValue(value, definition.type);
  if (!validation.valid) {
    return error(400, "type_mismatch", { expected: definition.type, reason: validation.reason });
  }

  // 3. Write to Shopify
  const mutation = `
    mutation metafieldsSet($metafields: [MetafieldsSetInput!]!) {
      metafieldsSet(metafields: $metafields) {
        metafields {
          namespace
          key
          value
          type
          updatedAt
        }
        userErrors {
          field
          message
          code
        }
      }
    }
  `;

  const variables = {
    metafields: [{
      ownerId: gid,
      namespace,
      key,
      type: definition.type,
      value: String(value),
    }],
  };

  const response = await shopifyGraphQL(shopDomain, accessToken, mutation, variables);
  const { metafields, userErrors } = response.metafieldsSet;

  if (userErrors && userErrors.length > 0) {
    return error(422, "shopify_validation_error", { errors: userErrors });
  }

  emit("metafield.set", { shopId, ownerId: gid, ownerType, namespace, key });

  return json(200, { metafield: metafields[0] });
}
```

---

## Batch Write Handler

<!-- PATTERN: metafield-batch-write -->
<!-- PURPOSE: Write up to 25 metafields in a single metafieldsSet call -->
<!-- ADAPT: GraphQL client, DB client -->

```typescript
// POST /api/metafields/batch
// Body: { metafields: Array<{ ownerId, ownerType, namespace, key, value }> }

async function handleBatchWriteMetafields(req: Request): Promise<Response> {
  const { metafields } = req.body;
  const { shopId, shopDomain, accessToken } = req.shopContext;

  // Shopify limit: 25 metafields per metafieldsSet call
  if (!metafields || metafields.length === 0) {
    return error(400, "metafields_required");
  }
  if (metafields.length > 25) {
    return error(400, "batch_size_exceeded", { max: 25, received: metafields.length });
  }

  // Validate each value against its registered type
  const validatedMetafields = [];

  for (const mf of metafields) {
    const definition = await db.query(`
      SELECT type FROM metafield_definitions
      WHERE shop_id = $1 AND namespace = $2 AND key = $3 AND owner_type = $4
    `, [shopId, mf.namespace, mf.key, mf.ownerType.toUpperCase()]);

    if (!definition) {
      return error(404, "definition_not_found", { namespace: mf.namespace, key: mf.key });
    }

    const validation = validateMetafieldValue(mf.value, definition.type);
    if (!validation.valid) {
      return error(400, "type_mismatch", {
        namespace: mf.namespace,
        key: mf.key,
        expected: definition.type,
        reason: validation.reason,
      });
    }

    validatedMetafields.push({
      ownerId: mf.ownerId,
      namespace: mf.namespace,
      key: mf.key,
      type: definition.type,
      value: String(mf.value),
    });
  }

  const mutation = `
    mutation metafieldsSet($metafields: [MetafieldsSetInput!]!) {
      metafieldsSet(metafields: $metafields) {
        metafields { namespace key value type updatedAt }
        userErrors { field message code }
      }
    }
  `;

  const response = await shopifyGraphQL(shopDomain, accessToken, mutation, { metafields: validatedMetafields });
  const { metafields: written, userErrors } = response.metafieldsSet;

  if (userErrors && userErrors.length > 0) {
    return error(422, "shopify_validation_error", { errors: userErrors });
  }

  return json(200, { metafields: written });
}
```

---

## Delete Metafield Handler

<!-- PATTERN: metafield-delete -->
<!-- PURPOSE: Delete a single metafield value from a Shopify resource -->
<!-- ADAPT: GraphQL client -->

```typescript
// DELETE /api/metafields/:ownerType/:ownerId/:namespace/:key

async function handleDeleteMetafield(req: Request): Promise<Response> {
  const { ownerType, ownerId, namespace, key } = req.params;
  const { shopId, shopDomain, accessToken } = req.shopContext;

  const gid = decodeURIComponent(ownerId);

  // First, fetch the metafield's GID from Shopify (needed for deletion)
  const fetchQuery = `
    query ($id: ID!, $namespace: String!, $key: String!) {
      ${ownerType.toLowerCase()}(id: $id) {
        metafield(namespace: $namespace, key: $key) { id }
      }
    }
  `;

  const fetchResponse = await shopifyGraphQL(shopDomain, accessToken, fetchQuery, {
    id: gid,
    namespace: decodeURIComponent(namespace),
    key: decodeURIComponent(key),
  });

  const resourceData = fetchResponse[ownerType.toLowerCase()];
  if (!resourceData?.metafield) {
    return error(404, "metafield_not_found");
  }

  const metafieldGid = resourceData.metafield.id;

  const deleteMutation = `
    mutation metafieldDelete($input: MetafieldDeleteInput!) {
      metafieldDelete(input: $input) {
        deletedId
        userErrors { field message }
      }
    }
  `;

  const deleteResponse = await shopifyGraphQL(shopDomain, accessToken, deleteMutation, {
    input: { id: metafieldGid },
  });

  if (deleteResponse.metafieldDelete.userErrors?.length > 0) {
    return error(422, "shopify_validation_error", { errors: deleteResponse.metafieldDelete.userErrors });
  }

  emit("metafield.deleted", { shopId, ownerId: gid, ownerType, namespace, key });

  return json(204, null);
}
```

---

## Type Validation Utility

<!-- PATTERN: metafield-type-validation -->
<!-- PURPOSE: Validate a value matches its expected Shopify metafield type before sending to API -->
<!-- ADAPT: Extend with additional types as needed -->

```typescript
interface ValidationResult {
  valid: boolean;
  reason?: string;
}

function validateMetafieldValue(value: unknown, type: string): ValidationResult {
  const str = String(value);

  switch (type) {
    case "number_integer":
      return Number.isInteger(Number(str)) && !isNaN(Number(str))
        ? { valid: true }
        : { valid: false, reason: `Expected integer, got "${str}"` };

    case "number_decimal":
      return !isNaN(parseFloat(str)) && isFinite(Number(str))
        ? { valid: true }
        : { valid: false, reason: `Expected decimal number, got "${str}"` };

    case "boolean":
      return str === "true" || str === "false"
        ? { valid: true }
        : { valid: false, reason: `Expected "true" or "false", got "${str}"` };

    case "date":
      return /^\d{4}-\d{2}-\d{2}$/.test(str) && !isNaN(Date.parse(str))
        ? { valid: true }
        : { valid: false, reason: `Expected ISO date (YYYY-MM-DD), got "${str}"` };

    case "date_time":
      return !isNaN(Date.parse(str))
        ? { valid: true }
        : { valid: false, reason: `Expected ISO datetime, got "${str}"` };

    case "json":
      try {
        JSON.parse(str);
        return { valid: true };
      } catch {
        return { valid: false, reason: `Invalid JSON: ${str}` };
      }

    case "url":
      try {
        new URL(str);
        return { valid: true };
      } catch {
        return { valid: false, reason: `Invalid URL: "${str}"` };
      }

    case "color":
      return /^#[0-9a-fA-F]{6}$/.test(str)
        ? { valid: true }
        : { valid: false, reason: `Expected hex color (#rrggbb), got "${str}"` };

    case "single_line_text_field":
    case "multi_line_text_field":
    case "rich_text_field":
      return typeof value === "string"
        ? { valid: true }
        : { valid: false, reason: "Expected string" };

    default:
      if (type.startsWith("list.")) {
        // List types: value must be a JSON array
        try {
          const parsed = JSON.parse(str);
          return Array.isArray(parsed)
            ? { valid: true }
            : { valid: false, reason: `List type "${type}" requires a JSON array` };
        } catch {
          return { valid: false, reason: `List type "${type}" requires a JSON array` };
        }
      }
      // Reference types and unknown types: pass through (Shopify validates GIDs)
      return { valid: true };
  }
}
```

---

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `definition_not_found` | 404 | Namespace+key+ownerType not in local registry for this shop |
| `type_mismatch` | 400 | Value does not match the registered metafield type |
| `unsupported_owner_type` | 400 | ownerType not in supported list (PRODUCT, ORDER, CUSTOMER, SHOP) |
| `metafield_not_found` | 404 | Metafield does not exist on the resource in Shopify |
| `batch_size_exceeded` | 400 | More than 25 metafields in a single batch write request |
| `metafields_required` | 400 | Empty metafields array in batch write |
| `shopify_validation_error` | 422 | Shopify returned userErrors on a mutation |

## Anti-patterns

**DON'T** store metafield values in your app's database. Values live in Shopify — storing them locally creates sync drift and stale data bugs. Always read values via GraphQL.

**DON'T** skip type validation before calling `metafieldsSet`. A type mismatch returns a 422 userError from Shopify — validate locally first for better error messages.

**DON'T** use a generic namespace like `global` or `app`. Use a specific prefix tied to your app (e.g., `myapp`, `acme`) to avoid collisions with other apps or Shopify's own namespaces.

**DON'T** make individual API calls for each metafield in a batch. `metafieldsSet` accepts up to 25 in a single call — use it to reduce API costs and rate limit consumption.

**DON'T** expose storefront-accessible metafields without explicit intent. Metafields are private by default. To expose via Storefront API, the definition must have `access.storefront` set — this is an intentional opt-in.
