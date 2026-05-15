---
id: "operations.shopify-bulk"
name: "Shopify Bulk Operations"
version: "1.0.0"
category: "operations"
tags: [shopify, bulk, graphql, async, large-datasets, jsonl]
prerequisites: ["auth.shopify-session-token"]
complexity: high
estimated_effort: "~75 min"
files:
  - README.md
  - backend.md
  - security.md
  - bulk-query.feature
  - bulk-mutation.feature
  - status-tracking.feature
  - result-processing.feature
  - fixtures/bulk-operations.json
  - fixtures/sample-jsonl.json
  - acceptance.md
---

# Shopify Bulk Operations

## 1. Overview

### Problem Statement

Shopify's standard GraphQL API is rate-limited and paginated — fetching 100,000 products requires hundreds of requests over many minutes. Bulk operations solve this by running a query or mutation asynchronously on Shopify's infrastructure, then making the full result available as a JSONL download. Without bulk operations, any app that needs to process large datasets (catalog exports, price updates, inventory syncs) is forced into slow, expensive polling loops that exhaust rate limits.

### User Stories

- **Developer**: I want to export all products and their variants so I can sync them to an external system without hitting rate limits
- **Developer**: I want to update prices for thousands of product variants in a single operation rather than looping individual mutations
- **Developer**: I want to know when a bulk operation completes so I can process the results immediately (via webhook)
- **Developer**: I want to parse JSONL results efficiently, including nested objects that use the `__parentId` convention
- **Merchant / App**: I want bulk imports and exports to complete reliably without timing out or losing data mid-process

### When to use this block

- App needs to read or write more than a few hundred records at once
- User mentions: "bulk export", "bulk import", "bulk update", "large dataset", "JSONL", "bulkOperationRunQuery", "bulkOperationRunMutation"
- App needs to sync full Shopify catalog to an external system
- App needs to update prices, inventory, or metafields for thousands of products

### When NOT to use

- Fetching fewer than ~200 records — use paginated GraphQL queries instead
- Real-time operations that need an immediate response — bulk ops are async (minutes to hours)
- Operations that need per-record error handling — bulk mutation errors are aggregated, not per-line

---

## 2. Data Model

```mermaid
erDiagram
    shops {
        uuid id PK "from auth.shopify-oauth"
        text shop_domain UK
    }

    bulk_operations {
        uuid id PK "gen_random_uuid()"
        uuid shop_id FK "shops.id"
        text shopify_operation_id UK "Shopify GID"
        text type "query | mutation"
        text status "created→running→completed|failed|cancelled"
        text query_text "GraphQL query or mutation string"
        text result_url "JSONL download URL (time-limited ~24h)"
        text error_code "null unless failed"
        text error_message "null unless failed"
        bigint object_count "objects in result"
        bigint file_size "result file bytes"
        timestamptz started_at
        timestamptz completed_at
        timestamptz created_at
        timestamptz updated_at
    }

    shops ||--o{ bulk_operations : "runs"
```

### Table: `bulk_operations`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `uuid` | PK, default `gen_random_uuid()` | |
| `shop_id` | `uuid` | NOT NULL, FK `shops.id` ON DELETE CASCADE | |
| `shopify_operation_id` | `text` | UNIQUE, nullable | Shopify GID — null until Shopify accepts the operation |
| `type` | `text` | NOT NULL | `'query'` or `'mutation'` |
| `status` | `text` | NOT NULL, default `'created'` | State machine: `created → running → completed \| failed \| cancelled` |
| `query_text` | `text` | NOT NULL | The full GraphQL query or mutation string |
| `result_url` | `text` | nullable | JSONL download URL — set on completion, time-limited (~24h) |
| `error_code` | `text` | nullable | Shopify error code if status is `failed` |
| `error_message` | `text` | nullable | Human-readable error if status is `failed` |
| `object_count` | `bigint` | nullable | Number of objects in the JSONL result |
| `file_size` | `bigint` | nullable | Result file size in bytes |
| `started_at` | `timestamptz` | nullable | When Shopify moved to `RUNNING` status |
| `completed_at` | `timestamptz` | nullable | When Shopify moved to terminal status |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | |
| `updated_at` | `timestamptz` | NOT NULL, default `now()` | |

### Migration (reference)

```sql
CREATE TABLE IF NOT EXISTS bulk_operations (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id              uuid NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  shopify_operation_id text UNIQUE,
  type                 text NOT NULL CHECK (type IN ('query', 'mutation')),
  status               text NOT NULL DEFAULT 'created'
                            CHECK (status IN ('created', 'running', 'completed', 'failed', 'cancelled')),
  query_text           text NOT NULL,
  result_url           text,
  error_code           text,
  error_message        text,
  object_count         bigint,
  file_size            bigint,
  started_at           timestamptz,
  completed_at         timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_bulk_shop ON bulk_operations(shop_id);
CREATE INDEX idx_bulk_status ON bulk_operations(shop_id, status);
CREATE INDEX idx_bulk_shopify_id ON bulk_operations(shopify_operation_id) WHERE shopify_operation_id IS NOT NULL;
```

---

## 3. Data Flow

### Bulk Query Flow

```mermaid
flowchart TD
    A[POST /api/bulk/query] --> B[Validate session token + shop context]
    B --> C[Check: any running query for this shop?]
    C -->|Yes| D[409 Conflict — one bulk query per shop]
    C -->|No| E[bulkOperationRunQuery mutation to Shopify]
    E -->|Error| F[502 Shopify rejected query]
    E -->|Success| G[Store bulk_operations record: status=created]
    G --> H{BULK_PREFER_WEBHOOK?}
    H -->|Yes, wait for webhook| I[Return operationId to caller]
    H -->|No, start polling| J[Poll currentBulkOperation every BULK_POLL_INTERVAL_MS]
    I --> K[BULK_OPERATIONS_FINISH webhook arrives]
    J --> K
    K --> L[Query currentBulkOperation for result_url + objectCount]
    L --> M[Update bulk_operations: status=completed, result_url, object_count]
    M --> N[Emit bulk.completed event]
    N --> O[Caller can GET /api/bulk/results/:id]
    O --> P[Stream JSONL from result_url]
    P --> Q[Parse line by line, reconstruct __parentId nesting]
    Q --> R[Process in batches of BULK_RESULT_PROCESSING_BATCH_SIZE]
    R --> S[Emit bulk.results_processed event]

    E2[Shopify bulk op fails] --> T[Update bulk_operations: status=failed, error_code, error_message]
    T --> U[Emit bulk.failed event]
```

### Bulk Mutation Flow

```mermaid
flowchart TD
    A[POST /api/bulk/mutation] --> B[Validate session token + shop context]
    B --> C[Check: any running mutation for this shop?]
    C -->|Yes| D[409 Conflict — one bulk mutation per shop]
    C -->|No| E[stagedUploadsCreate mutation to Shopify]
    E --> F[Receive staged upload URL + parameters]
    F --> G[Upload JSONL file to staged URL via multipart POST]
    G --> H[Extract stagedUploadPath from upload response]
    H --> I[bulkOperationRunMutation mutation to Shopify]
    I -->|Error| J[502 Shopify rejected mutation]
    I -->|Success| K[Store bulk_operations record: status=created]
    K --> L[Wait for webhook or poll — same as query flow]
    L --> M[Update bulk_operations on completion]
```

---

## 4. Sequence Diagrams

### Bulk Query — Webhook Completion (happy path)

```mermaid
sequenceDiagram
    actor C as API Caller
    participant A as App Backend
    participant DB as Database
    participant S as Shopify GraphQL
    participant W as Shopify Webhook

    C->>A: POST /api/bulk/query { query: "{ products { edges { node { id title } } } }" }
    A->>A: Verify session token, extract shopId
    A->>DB: SELECT COUNT(*) FROM bulk_operations WHERE shop_id=$1 AND type='query' AND status IN ('created','running')
    DB-->>A: 0 (no active query)
    A->>S: mutation bulkOperationRunQuery { query: "..." }
    S-->>A: { bulkOperation: { id: "gid://shopify/BulkOperation/123", status: CREATED } }
    A->>DB: INSERT bulk_operations (shopify_operation_id, type='query', status='created', query_text)
    A-->>C: 202 Accepted { operationId: "uuid-abc", shopifyOperationId: "gid://...123" }

    Note over S,W: Shopify runs the operation asynchronously

    W->>A: POST /api/webhooks (topic: BULK_OPERATIONS_FINISH) { admin_graphql_api_id: "gid://...123" }
    A->>A: Verify HMAC on webhook body
    A-->>W: 200 OK (immediate response)
    A->>S: query { node(id: "gid://...123") { ... on BulkOperation { status, url, objectCount, fileSize } } }
    S-->>A: { status: COMPLETED, url: "https://storage.googleapis.com/...", objectCount: 4521, fileSize: 892341 }
    A->>DB: UPDATE bulk_operations SET status='completed', result_url=url, object_count=4521, file_size=892341, completed_at=now()
    A->>A: Emit bulk.completed event

    C->>A: GET /api/bulk/results/uuid-abc
    A->>DB: SELECT * FROM bulk_operations WHERE id=$1 AND shop_id=$2
    DB-->>A: operation record with result_url
    A->>S: GET result_url (stream JSONL)
    S-->>A: stream of JSONL lines
    A->>A: Parse lines, batch 1000 at a time, reconstruct __parentId nesting
    A-->>C: processed result summary { processed: 4521, batches: 5 }
    A->>A: Emit bulk.results_processed event
```

### Bulk Query — Polling Completion

```mermaid
sequenceDiagram
    participant A as App Backend
    participant S as Shopify GraphQL
    participant DB as Database

    A->>S: mutation bulkOperationRunQuery { query: "..." }
    S-->>A: { bulkOperation: { id: "gid://...123", status: CREATED } }
    A->>DB: INSERT bulk_operations (status='created')

    loop Poll every BULK_POLL_INTERVAL_MS up to BULK_MAX_POLL_ATTEMPTS
        A->>S: query { currentBulkOperation { id, status, url, objectCount, errorCode } }
        S-->>A: { status: RUNNING, url: null }
        Note over A: status still RUNNING, continue polling
    end

    A->>S: query { currentBulkOperation { id, status, url, objectCount, errorCode } }
    S-->>A: { status: COMPLETED, url: "https://...", objectCount: 4521 }
    A->>DB: UPDATE bulk_operations SET status='completed', result_url, object_count, completed_at=now()
    A->>A: Emit bulk.completed event
```

### Bulk Mutation — Staged Upload + Submit

```mermaid
sequenceDiagram
    actor C as API Caller
    participant A as App Backend
    participant S as Shopify GraphQL
    participant GCS as Shopify Staged Storage
    participant DB as Database

    C->>A: POST /api/bulk/mutation { mutation: "...", variables: [...] }
    A->>A: Serialize variables array to JSONL (one JSON object per line)
    A->>S: mutation stagedUploadsCreate { input: [{ resource: BULK_MUTATION_VARIABLES, filename: "bulk.jsonl", mimeType: "text/jsonl", httpMethod: POST }] }
    S-->>A: { stagedTargets: [{ url: "https://storage.googleapis.com/...", parameters: [...], resourceUrl: "..." }] }
    A->>GCS: POST staged URL (multipart/form-data with parameters + JSONL file)
    GCS-->>A: 201 Created
    A->>S: mutation bulkOperationRunMutation { mutation: "mutation ($input: ProductInput!) { productUpdate(input: $input) { product { id } } }", stagedUploadPath: "bulk-mutations/..." }
    S-->>A: { bulkOperation: { id: "gid://...456", status: CREATED } }
    A->>DB: INSERT bulk_operations (type='mutation', status='created', shopify_operation_id)
    A-->>C: 202 Accepted { operationId: "uuid-def" }

    Note over S: Shopify runs mutations asynchronously against JSONL variables
    Note over A: Webhook or polling determines completion (same as query flow)
```

### Conflict — Concurrent Bulk Operation Attempt

```mermaid
sequenceDiagram
    actor C as API Caller
    participant A as App Backend
    participant DB as Database

    Note over DB: shop already has status='running' bulk query

    C->>A: POST /api/bulk/query { query: "..." }
    A->>DB: SELECT COUNT(*) FROM bulk_operations WHERE shop_id=$1 AND type='query' AND status IN ('created','running')
    DB-->>A: 1
    A-->>C: 409 Conflict { error: "bulk_operation_in_progress", type: "query" }
```

---

## 5. State Management

This block is backend-only. No frontend state.

| State | Storage | Survives Reload | Notes |
|-------|---------|-----------------|-------|
| `bulk_operations` record | Database | Yes | Persistent record of all submitted operations |
| `result_url` | Database | Yes (~24h) | Time-limited URL from Shopify — must process before expiry |
| Polling loop | In-memory / job queue | No | Restarted if server restarts; webhook mode is more resilient |

### Status State Machine

```
created   → running    (Shopify starts processing)
running   → completed  (Shopify finishes, result_url available)
running   → failed     (Shopify error, error_code + error_message set)
running   → cancelled  (app called cancel or merchant cancelled in admin)
```

Terminal states: `completed`, `failed`, `cancelled`

### One-per-Shop Constraint

Shopify enforces at most 1 active bulk query and 1 active bulk mutation per shop simultaneously. The app mirrors this constraint by rejecting new submissions when a `created` or `running` operation of the same type exists for the shop.

---

## 6. Integration Points

### Inbound

| Caller | How | Purpose |
|--------|-----|---------|
| Embedded app / backend job | POST /api/bulk/query | Submit a bulk query |
| Embedded app / backend job | POST /api/bulk/mutation | Submit a bulk mutation |
| Embedded app / backend job | GET /api/bulk/status/:id | Poll operation status |
| Embedded app / backend job | GET /api/bulk/results/:id | Retrieve and process results |
| Shopify webhook system | POST /api/webhooks (BULK_OPERATIONS_FINISH) | Completion notification |

### Outbound

| Target | How | Purpose |
|--------|-----|---------|
| Shopify GraphQL Admin API | `bulkOperationRunQuery` mutation | Submit bulk query |
| Shopify GraphQL Admin API | `bulkOperationRunMutation` mutation | Submit bulk mutation |
| Shopify GraphQL Admin API | `stagedUploadsCreate` mutation | Get staged upload URL for mutation variables |
| Shopify GraphQL Admin API | `currentBulkOperation` query | Poll operation status |
| Shopify staged storage (GCS) | Multipart POST | Upload JSONL mutation variables |
| Shopify result URL (GCS) | GET (stream) | Download JSONL results |
| Database | SQL | Track operation records |

### Events

| Event | Payload | When |
|-------|---------|------|
| `bulk.started` | `{ operationId, shopId, type, shopifyOperationId }` | Shopify accepts the operation |
| `bulk.completed` | `{ operationId, shopId, type, objectCount, fileSize, resultUrl }` | Operation reaches `completed` status |
| `bulk.failed` | `{ operationId, shopId, type, errorCode, errorMessage }` | Operation reaches `failed` status |
| `bulk.results_processed` | `{ operationId, shopId, processedCount, batchCount }` | All JSONL lines processed |

---

## 7. Configuration Surface

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `BULK_PREFER_WEBHOOK` | `boolean` | `true` | Use `BULK_OPERATIONS_FINISH` webhook instead of polling for completion |
| `BULK_POLL_INTERVAL_MS` | `number` | `2000` | Milliseconds between polling attempts (when not using webhook) |
| `BULK_MAX_POLL_ATTEMPTS` | `number` | `500` | Max poll attempts before treating operation as timed-out (~16 min at 2s interval) |
| `BULK_RESULT_PROCESSING_BATCH_SIZE` | `number` | `1000` | JSONL lines to process per batch (controls memory footprint) |
