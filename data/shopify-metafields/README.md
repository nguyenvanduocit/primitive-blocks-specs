---
id: "data.shopify-metafields"
name: "Shopify Metafields"
version: "1.0.0"
category: "data"
tags: [shopify, metafields, custom-data, graphql, embedded-app]
prerequisites: ["auth.shopify-session-token"]
complexity: medium
estimated_effort: "~60 min"
files:
  - README.md
  - backend.md
  - security.md
  - definition-sync.feature
  - read-write.feature
  - type-validation.feature
  - fixtures/metafield-definitions.json
  - fixtures/metafield-values.json
  - acceptance.md
---

# Shopify Metafields

## 1. Overview

### Problem Statement

Shopify's built-in data model covers products, orders, and customers — but most apps need to store custom data against these resources. Metafields are Shopify's native extension mechanism: an app defines what fields exist (definitions), then reads and writes values for specific resources. Without this block, apps resort to storing Shopify resource data in their own database and keeping it in sync — a fragile pattern that diverges from Shopify's recommended approach.

### User Stories

- **Developer**: I want to store a custom "warranty period" value on products so merchants can display it on the storefront
- **Developer**: I want to read and write custom order attributes (e.g. delivery instructions) that persist in Shopify
- **Developer**: I want to define metafield types once at install time, then read and write values without repeating type information in every call
- **Merchant**: I want custom fields I set via the app to appear in Shopify Admin alongside the product

### When to use this block

- App needs to attach custom data to Shopify resources (products, orders, customers, shop)
- User mentions: "metafields", "custom data", "custom attributes", "extend Shopify data model"
- App reads/writes data that logically belongs to a Shopify resource (not the app's own domain objects)

### When NOT to use

- Storing app-internal data that has no relationship to a Shopify resource — use your own DB tables
- Storing large blobs or binary data — use file uploads or external storage
- Storing data that needs complex querying — metafields have limited filtering capability in Shopify's API

---

## 2. Data Model

```mermaid
erDiagram
    shops {
        uuid id PK
        text shop_domain UK
    }

    metafield_definitions {
        uuid id PK "gen_random_uuid()"
        uuid shop_id FK "references shops(id)"
        text namespace "e.g. myapp"
        text key "e.g. warranty_period"
        text owner_type "PRODUCT, ORDER, CUSTOMER, SHOP"
        text type "single_line_text_field, number_integer, json, etc."
        text name "Human-readable label"
        text description "Optional description"
        text shopify_gid "Shopify GID after sync"
        timestamptz synced_at "Last synced to Shopify"
        timestamptz created_at
    }

    shops ||--o{ metafield_definitions : "registers definitions for"
```

### Table: `metafield_definitions`

Local registry that mirrors what has been registered in Shopify. Used for validation and sync — the source of truth for values is always Shopify.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, default `gen_random_uuid()` | |
| `shop_id` | `uuid` | NOT NULL, FK → `shops(id)` ON DELETE CASCADE | Tenant isolation |
| `namespace` | `text` | NOT NULL | App namespace prefix, e.g. `myapp` |
| `key` | `text` | NOT NULL | Field key within namespace, e.g. `warranty_period` |
| `owner_type` | `text` | NOT NULL | `PRODUCT`, `ORDER`, `CUSTOMER`, `SHOP`, etc. |
| `type` | `text` | NOT NULL | Shopify metafield type, e.g. `single_line_text_field` |
| `name` | `text` | NOT NULL | Human-readable label shown in Shopify Admin |
| `description` | `text` | nullable | Optional description |
| `shopify_gid` | `text` | nullable | Shopify GID returned after `metafieldDefinitionCreate` |
| `synced_at` | `timestamptz` | nullable | Timestamp of last successful sync to Shopify |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | |

**Unique constraint**: `UNIQUE(shop_id, namespace, key, owner_type)` — one definition per shop per namespace+key+owner combination.

> **Important**: Metafield **values** live in Shopify, not in the app's database. This table only stores definitions (the schema). Every read/write of a value goes through the Shopify GraphQL API.

### Migration (reference)

```sql
CREATE TABLE IF NOT EXISTS metafield_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id uuid NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  namespace text NOT NULL,
  key text NOT NULL,
  owner_type text NOT NULL,
  type text NOT NULL,
  name text NOT NULL,
  description text,
  shopify_gid text,
  synced_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(shop_id, namespace, key, owner_type)
);

CREATE INDEX idx_metafield_defs_shop ON metafield_definitions(shop_id);
CREATE INDEX idx_metafield_defs_owner ON metafield_definitions(shop_id, owner_type);
```

---

## 3. Data Flow

```mermaid
flowchart TD
    A[App install completes] --> B[POST /api/metafields/sync-definitions]
    B --> C{For each definition in METAFIELD_DEFINITIONS config}
    C --> D[metafieldDefinitionCreate mutation]
    D -->|Success| E[Upsert metafield_definitions record with shopify_gid]
    D -->|Already exists| F[Update local record, keep shopify_gid]
    E --> G[Definitions ready]
    F --> G

    H[Frontend: read metafield] --> I[GET /api/metafields/:ownerType/:ownerId]
    I --> J[GraphQL: product metafield query]
    J --> K[Return value + type to client]

    L[Frontend: write metafield] --> M[POST /api/metafields/:ownerType/:ownerId]
    M --> N[Validate value against type from local definition]
    N -->|Invalid| O[400 type_mismatch]
    N -->|Valid| P[metafieldsSet mutation]
    P --> Q[Return updated metafield to client]

    R[DELETE /api/metafields/:ownerType/:ownerId/:namespace/:key] --> S[metafieldDelete mutation]
    S --> T[Return 204]
```

---

## 4. Sequence Diagrams

### Definition Sync (on install)

```mermaid
sequenceDiagram
    participant A as App Backend
    participant DB as Database
    participant S as Shopify GraphQL

    A->>A: App install event fires
    A->>A: Read METAFIELD_DEFINITIONS from config
    loop For each definition
        A->>S: metafieldDefinitionCreate mutation { namespace, key, name, type, ownerType, pin }
        S-->>A: { id: "gid://shopify/MetafieldDefinition/123" }
        A->>DB: INSERT metafield_definitions ON CONFLICT DO UPDATE SET shopify_gid, synced_at
    end
    A->>A: Emit metafield.synced event
```

### Read Metafield

```mermaid
sequenceDiagram
    actor C as Client
    participant A as App Backend
    participant S as Shopify GraphQL

    C->>A: GET /api/metafields/PRODUCT/gid://shopify/Product/123?namespace=myapp&key=warranty_period
    A->>A: Verify session token (auth.shopify-session-token middleware)
    A->>S: query { product(id) { metafield(namespace, key) { value, type, updatedAt } } }
    S-->>A: { metafield: { value: "2 years", type: "single_line_text_field" } }
    A-->>C: 200 { value: "2 years", type: "single_line_text_field" }
```

### Write Metafield (with type validation)

```mermaid
sequenceDiagram
    actor C as Client
    participant A as App Backend
    participant DB as Database
    participant S as Shopify GraphQL

    C->>A: POST /api/metafields/PRODUCT/gid://shopify/Product/123 { namespace, key, value }
    A->>A: Verify session token
    A->>DB: SELECT type FROM metafield_definitions WHERE shop_id=$1 AND namespace=$2 AND key=$3 AND owner_type='PRODUCT'
    DB-->>A: type = "number_integer"
    A->>A: Validate: is "value" a valid integer? YES
    A->>S: metafieldsSet mutation { metafields: [{ ownerId, namespace, key, type, value }] }
    S-->>A: { metafieldsSet: { metafields: [...] } }
    A-->>C: 200 { metafield: { value, type, updatedAt } }
```

### Batch Write (up to 25 metafields)

```mermaid
sequenceDiagram
    actor C as Client
    participant A as App Backend
    participant S as Shopify GraphQL

    C->>A: POST /api/metafields/batch { metafields: [...25 items] }
    A->>A: Validate each value against its type
    A->>S: metafieldsSet mutation { metafields: [all 25] }
    S-->>A: { metafieldsSet: { metafields: [...], userErrors: [] } }
    A-->>C: 200 { metafields: [...] }
```

---

## 5. State Management

This block is backend-only. The only local state is the definitions registry.

| State | Storage | Survives Reload | Notes |
|-------|---------|-----------------|-------|
| `metafield_definitions` | Database | Yes | Local mirror of definitions registered in Shopify |
| Metafield values | Shopify (via GraphQL) | Yes | Never stored locally — always fetched on demand |
| Sync status | `synced_at` column | Yes | Tracks last successful sync per definition |

### State transitions

```
Config has definitions → POST /api/metafields/sync-definitions → metafieldDefinitionCreate → record upserted with shopify_gid
Config changes → re-sync → upsert updates existing records
Shop uninstalls → CASCADE DELETE removes all metafield_definitions records
```

---

## 6. Integration Points

### Inbound

| Caller | How | Purpose |
|--------|-----|---------|
| App install handler | Internal call | Trigger definition sync after OAuth completes |
| Embedded app frontend | HTTP (authenticated) | Read/write metafield values via API endpoints |
| Admin UI or background job | HTTP (authenticated) | Batch write or sync definitions on config change |

### Outbound

| Target | How | Purpose |
|--------|-----|---------|
| Shopify GraphQL Admin API | GraphQL mutation | `metafieldDefinitionCreate` — register definitions |
| Shopify GraphQL Admin API | GraphQL mutation | `metafieldsSet` — write values (batch up to 25) |
| Shopify GraphQL Admin API | GraphQL query | Read metafields for a resource |
| Shopify GraphQL Admin API | GraphQL mutation | `metafieldDelete` — remove a value |
| Database | SQL | Store/query metafield definitions |

### Events

| Event | Payload | When |
|-------|---------|------|
| `metafield.synced` | `{ shopId, count, definitions[] }` | Definition sync completes successfully |
| `metafield.set` | `{ shopId, ownerId, ownerType, namespace, key }` | Metafield value written |
| `metafield.deleted` | `{ shopId, ownerId, ownerType, namespace, key }` | Metafield value deleted |

---

## 7. Configuration Surface

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `METAFIELD_NAMESPACE` | `string` | app handle | Namespace prefix for all metafields (e.g. `myapp`) |
| `METAFIELD_DEFINITIONS` | `object[]` | `[]` | Array of `{ key, name, type, ownerType, description }` to register |
| `METAFIELD_PIN_TO_ADMIN` | `boolean` | `true` | Pin definitions in Shopify Admin UI for merchant visibility |

### Supported Metafield Types

| Category | Types |
|----------|-------|
| Text | `single_line_text_field`, `multi_line_text_field`, `rich_text_field` |
| Numeric | `number_integer`, `number_decimal` |
| Boolean | `boolean` |
| Date/Time | `date`, `date_time` |
| Structured | `json`, `url`, `color` |
| Reference | `product_reference`, `variant_reference`, `collection_reference`, `file_reference` |
| Lists | `list.single_line_text_field`, `list.number_integer`, `list.product_reference`, etc. |
