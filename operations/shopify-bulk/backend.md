# Backend Patterns — Shopify Bulk Operations

## API Endpoints

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `POST` | `/api/bulk/query` | Submit a bulk query operation | Session token |
| `POST` | `/api/bulk/mutation` | Upload JSONL + submit bulk mutation | Session token |
| `GET` | `/api/bulk/status/:operationId` | Check operation status | Session token |
| `POST` | `/api/bulk/cancel/:operationId` | Cancel a running operation | Session token |
| `GET` | `/api/bulk/results/:operationId` | Stream + process JSONL results | Session token |
| `POST` | `/api/webhooks` | Receive `BULK_OPERATIONS_FINISH` webhook | HMAC verified |

---

## Submit Bulk Query

<!-- PATTERN: bulk-query-submit -->
<!-- PURPOSE: Validate shop has no active query, call bulkOperationRunQuery, store record -->
<!-- ADAPT: GraphQL client, job queue for polling -->

```typescript
// POST /api/bulk/query
// Body: { query: string }

async function handleBulkQuerySubmit(req: Request): Promise<Response> {
  const { shopId, shopDomain } = req.shopContext; // from session token middleware
  const { query } = req.body;

  if (!query || typeof query !== "string") {
    return error(400, "missing_query");
  }

  // 1. Enforce one-per-shop constraint
  const active = await db.query(
    `SELECT id FROM bulk_operations
     WHERE shop_id = $1 AND type = 'query' AND status IN ('created', 'running')
     LIMIT 1`,
    [shopId]
  );
  if (active) {
    return error(409, "bulk_operation_in_progress", { type: "query", existingId: active.id });
  }

  // 2. Submit to Shopify
  const gql = getShopifyGraphQLClient(shopId);
  const result = await gql.mutation(`
    mutation bulkOperationRunQuery($query: String!) {
      bulkOperationRunQuery(query: $query) {
        bulkOperation {
          id
          status
        }
        userErrors {
          field
          message
        }
      }
    }
  `, { query });

  const { bulkOperation, userErrors } = result.bulkOperationRunQuery;

  if (userErrors.length > 0) {
    return error(422, "shopify_rejected_query", { errors: userErrors });
  }

  // 3. Store operation record
  const operation = await db.query(`
    INSERT INTO bulk_operations
      (shop_id, shopify_operation_id, type, status, query_text)
    VALUES ($1, $2, 'query', 'created', $3)
    RETURNING *
  `, [shopId, bulkOperation.id, query]);

  emit("bulk.started", {
    operationId: operation.id,
    shopId,
    type: "query",
    shopifyOperationId: bulkOperation.id,
  });

  // 4. Start polling if webhook not preferred
  if (!config.BULK_PREFER_WEBHOOK) {
    schedulePoll(operation.id, shopId, bulkOperation.id);
  }

  return json(202, {
    operationId: operation.id,
    shopifyOperationId: bulkOperation.id,
    status: "created",
  });
}
```

---

## Submit Bulk Mutation

<!-- PATTERN: bulk-mutation-submit -->
<!-- PURPOSE: Stage JSONL upload, then submit bulkOperationRunMutation -->
<!-- ADAPT: File upload client, multipart form handling -->

```typescript
// POST /api/bulk/mutation
// Body: { mutation: string, variables: object[] }

async function handleBulkMutationSubmit(req: Request): Promise<Response> {
  const { shopId } = req.shopContext;
  const { mutation, variables } = req.body;

  if (!mutation || !Array.isArray(variables) || variables.length === 0) {
    return error(400, "missing_mutation_or_variables");
  }

  // 1. Enforce one-per-shop constraint
  const active = await db.query(
    `SELECT id FROM bulk_operations
     WHERE shop_id = $1 AND type = 'mutation' AND status IN ('created', 'running')
     LIMIT 1`,
    [shopId]
  );
  if (active) {
    return error(409, "bulk_operation_in_progress", { type: "mutation", existingId: active.id });
  }

  // 2. Serialize variables to JSONL (one JSON object per line)
  const jsonlContent = variables.map(v => JSON.stringify(v)).join("\n");
  const jsonlBuffer = Buffer.from(jsonlContent, "utf-8");

  // 3. Get staged upload URL from Shopify
  const gql = getShopifyGraphQLClient(shopId);
  const stageResult = await gql.mutation(`
    mutation stagedUploadsCreate($input: [StagedUploadInput!]!) {
      stagedUploadsCreate(input: $input) {
        stagedTargets {
          url
          resourceUrl
          parameters {
            name
            value
          }
        }
        userErrors {
          field
          message
        }
      }
    }
  `, {
    input: [{
      resource: "BULK_MUTATION_VARIABLES",
      filename: "bulk-variables.jsonl",
      mimeType: "text/jsonl",
      fileSize: String(jsonlBuffer.byteLength),
      httpMethod: "POST",
    }],
  });

  const { stagedTargets, userErrors: stageErrors } = stageResult.stagedUploadsCreate;
  if (stageErrors.length > 0) {
    return error(422, "staged_upload_failed", { errors: stageErrors });
  }

  const target = stagedTargets[0];

  // 4. Upload JSONL to staged URL (multipart/form-data)
  const formData = new FormData();
  for (const param of target.parameters) {
    formData.append(param.name, param.value);
  }
  formData.append("file", new Blob([jsonlBuffer], { type: "text/jsonl" }), "bulk-variables.jsonl");

  const uploadResponse = await fetch(target.url, {
    method: "POST",
    body: formData,
  });

  if (!uploadResponse.ok) {
    return error(502, "staged_upload_upload_failed", { status: uploadResponse.status });
  }

  // 5. Extract the stagedUploadPath from the resourceUrl
  // resourceUrl: "https://storage.googleapis.com/shopify/bulk-mutations/abc123/bulk-variables.jsonl"
  // stagedUploadPath: "bulk-mutations/abc123/bulk-variables.jsonl"
  const stagedUploadPath = new URL(target.resourceUrl).pathname.replace(/^\/shopify\//, "");

  // 6. Submit the bulk mutation
  const mutResult = await gql.mutation(`
    mutation bulkOperationRunMutation($mutation: String!, $stagedUploadPath: String!) {
      bulkOperationRunMutation(mutation: $mutation, stagedUploadPath: $stagedUploadPath) {
        bulkOperation {
          id
          status
        }
        userErrors {
          field
          message
        }
      }
    }
  `, { mutation, stagedUploadPath });

  const { bulkOperation, userErrors } = mutResult.bulkOperationRunMutation;
  if (userErrors.length > 0) {
    return error(422, "shopify_rejected_mutation", { errors: userErrors });
  }

  // 7. Store operation record
  const operation = await db.query(`
    INSERT INTO bulk_operations
      (shop_id, shopify_operation_id, type, status, query_text)
    VALUES ($1, $2, 'mutation', 'created', $3)
    RETURNING *
  `, [shopId, bulkOperation.id, mutation]);

  emit("bulk.started", {
    operationId: operation.id,
    shopId,
    type: "mutation",
    shopifyOperationId: bulkOperation.id,
  });

  if (!config.BULK_PREFER_WEBHOOK) {
    schedulePoll(operation.id, shopId, bulkOperation.id);
  }

  return json(202, {
    operationId: operation.id,
    shopifyOperationId: bulkOperation.id,
    status: "created",
  });
}
```

---

## Get Operation Status

<!-- PATTERN: bulk-status-check -->
<!-- PURPOSE: Return current status of a bulk operation, scoped to requesting shop -->
<!-- ADAPT: DB client -->

```typescript
// GET /api/bulk/status/:operationId

async function handleBulkStatus(req: Request): Promise<Response> {
  const { shopId } = req.shopContext;
  const { operationId } = req.params;

  const operation = await db.query(
    `SELECT id, shopify_operation_id, type, status, object_count, file_size,
            error_code, error_message, started_at, completed_at, created_at
     FROM bulk_operations
     WHERE id = $1 AND shop_id = $2`,
    [operationId, shopId]
  );

  if (!operation) {
    return error(404, "operation_not_found");
  }

  return json(200, operation);
}
```

---

## Cancel Operation

<!-- PATTERN: bulk-cancel -->
<!-- PURPOSE: Cancel a running bulk operation via bulkOperationCancel mutation -->
<!-- ADAPT: GraphQL client -->

```typescript
// POST /api/bulk/cancel/:operationId

async function handleBulkCancel(req: Request): Promise<Response> {
  const { shopId } = req.shopContext;
  const { operationId } = req.params;

  const operation = await db.query(
    `SELECT * FROM bulk_operations WHERE id = $1 AND shop_id = $2`,
    [operationId, shopId]
  );

  if (!operation) {
    return error(404, "operation_not_found");
  }

  if (!["created", "running"].includes(operation.status)) {
    return error(409, "operation_not_cancellable", { status: operation.status });
  }

  const gql = getShopifyGraphQLClient(shopId);
  const result = await gql.mutation(`
    mutation bulkOperationCancel($id: ID!) {
      bulkOperationCancel(id: $id) {
        bulkOperation {
          id
          status
        }
        userErrors {
          field
          message
        }
      }
    }
  `, { id: operation.shopify_operation_id });

  const { userErrors } = result.bulkOperationCancel;
  if (userErrors.length > 0) {
    return error(422, "cancel_failed", { errors: userErrors });
  }

  await db.query(
    `UPDATE bulk_operations
     SET status = 'cancelled', updated_at = now()
     WHERE id = $1`,
    [operationId]
  );

  return json(200, { status: "cancelled" });
}
```

---

## Download and Process Results

<!-- PATTERN: bulk-results-process -->
<!-- PURPOSE: Stream JSONL from result_url, parse line by line, reconstruct __parentId nesting -->
<!-- ADAPT: Streaming HTTP client, batch processor -->

```typescript
// GET /api/bulk/results/:operationId

async function handleBulkResults(req: Request): Promise<Response> {
  const { shopId } = req.shopContext;
  const { operationId } = req.params;

  const operation = await db.query(
    `SELECT * FROM bulk_operations WHERE id = $1 AND shop_id = $2`,
    [operationId, shopId]
  );

  if (!operation) {
    return error(404, "operation_not_found");
  }

  if (operation.status !== "completed") {
    return error(409, "operation_not_completed", { status: operation.status });
  }

  if (!operation.result_url) {
    return error(410, "result_url_expired");
  }

  let processedCount = 0;
  let batchCount = 0;
  let batch: ParsedBulkObject[] = [];

  // Stream and process JSONL line by line
  const response = await fetch(operation.result_url);
  if (!response.ok || !response.body) {
    return error(502, "result_download_failed");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? ""; // Keep incomplete last line in buffer

    for (const line of lines) {
      if (!line.trim()) continue;
      const obj = JSON.parse(line) as BulkResultObject;
      batch.push(obj);

      if (batch.length >= config.BULK_RESULT_PROCESSING_BATCH_SIZE) {
        await processBatch(batch, shopId, operationId);
        processedCount += batch.length;
        batchCount++;
        batch = [];
      }
    }
  }

  // Process remaining lines
  if (batch.length > 0) {
    await processBatch(batch, shopId, operationId);
    processedCount += batch.length;
    batchCount++;
  }

  emit("bulk.results_processed", { operationId, shopId, processedCount, batchCount });

  return json(200, { processedCount, batchCount });
}
```

---

## JSONL Parsing with `__parentId` Nesting

<!-- PATTERN: bulk-jsonl-parse -->
<!-- PURPOSE: Reconstruct parent-child relationships from flat JSONL using __parentId -->
<!-- ADAPT: Processing logic for specific resource types -->

```typescript
// Shopify bulk JSONL: nested resources appear as flat objects with __parentId
// Example: product has variants — each variant line has __parentId = product.id
//
// Input JSONL:
// {"id":"gid://shopify/Product/1","title":"T-Shirt"}
// {"id":"gid://shopify/ProductVariant/10","price":"19.99","__parentId":"gid://shopify/Product/1"}
// {"id":"gid://shopify/ProductVariant/11","price":"24.99","__parentId":"gid://shopify/Product/1"}
// {"id":"gid://shopify/Product/2","title":"Hoodie"}
// {"id":"gid://shopify/ProductVariant/20","price":"49.99","__parentId":"gid://shopify/Product/2"}

interface BulkResultObject {
  id: string;
  __parentId?: string;
  [key: string]: unknown;
}

interface ParsedBulkObject {
  id: string;
  parentId?: string;
  data: Record<string, unknown>;
  children: ParsedBulkObject[];
}

function groupByParent(lines: BulkResultObject[]): ParsedBulkObject[] {
  const map = new Map<string, ParsedBulkObject>();
  const roots: ParsedBulkObject[] = [];

  for (const line of lines) {
    const node: ParsedBulkObject = {
      id: line.id,
      parentId: line.__parentId,
      data: line,
      children: [],
    };
    map.set(line.id, node);

    if (line.__parentId) {
      const parent = map.get(line.__parentId);
      if (parent) {
        parent.children.push(node);
      }
      // If parent not seen yet (out-of-order), treat as root — caller handles
    } else {
      roots.push(node);
    }
  }

  return roots;
}

async function processBatch(
  batch: BulkResultObject[],
  shopId: string,
  operationId: string
): Promise<void> {
  const grouped = groupByParent(batch);
  // Application-specific processing — e.g., upsert products with their variants
  for (const root of grouped) {
    await upsertProductWithVariants(root, shopId);
  }
}
```

---

## Webhook: BULK_OPERATIONS_FINISH

<!-- PATTERN: bulk-webhook-handler -->
<!-- PURPOSE: Handle completion webhook, fetch result URL, update record, emit event -->
<!-- ADAPT: Webhook routing from webhooks.shopify-webhooks block -->

```typescript
// Called by the webhook router when topic === "BULK_OPERATIONS_FINISH"

async function handleBulkOperationsFinish(
  payload: BulkOperationsFinishPayload,
  shopDomain: string
): Promise<void> {
  const { admin_graphql_api_id } = payload; // Shopify's bulk operation GID

  const shop = await getShopByDomain(shopDomain);
  if (!shop) return; // Shop uninstalled — ignore

  const operation = await db.query(
    `SELECT * FROM bulk_operations
     WHERE shopify_operation_id = $1 AND shop_id = $2`,
    [admin_graphql_api_id, shop.id]
  );

  if (!operation) return; // Unknown operation — ignore

  // Fetch final status and result URL from Shopify
  const gql = getShopifyGraphQLClient(shop.id);
  const result = await gql.query(`
    query getBulkOperation($id: ID!) {
      node(id: $id) {
        ... on BulkOperation {
          id
          status
          url
          errorCode
          objectCount
          fileSize
          createdAt
          completedAt
        }
      }
    }
  `, { id: admin_graphql_api_id });

  const bulkOp = result.node;

  const statusMap: Record<string, string> = {
    COMPLETED: "completed",
    FAILED: "failed",
    CANCELLED: "cancelled",
  };

  const newStatus = statusMap[bulkOp.status] ?? "failed";

  await db.query(`
    UPDATE bulk_operations SET
      status        = $1,
      result_url    = $2,
      error_code    = $3,
      object_count  = $4,
      file_size     = $5,
      started_at    = $6,
      completed_at  = $7,
      updated_at    = now()
    WHERE id = $8
  `, [
    newStatus,
    bulkOp.url ?? null,
    bulkOp.errorCode ?? null,
    bulkOp.objectCount ?? null,
    bulkOp.fileSize ?? null,
    bulkOp.createdAt ?? null,
    bulkOp.completedAt ?? null,
    operation.id,
  ]);

  if (newStatus === "completed") {
    emit("bulk.completed", {
      operationId: operation.id,
      shopId: shop.id,
      type: operation.type,
      objectCount: bulkOp.objectCount,
      fileSize: bulkOp.fileSize,
      resultUrl: bulkOp.url,
    });
  } else {
    emit("bulk.failed", {
      operationId: operation.id,
      shopId: shop.id,
      type: operation.type,
      errorCode: bulkOp.errorCode,
      errorMessage: null,
    });
  }
}
```

---

## Polling Loop (when webhook not available)

<!-- PATTERN: bulk-polling -->
<!-- PURPOSE: Poll currentBulkOperation until terminal state, with backoff guard -->
<!-- ADAPT: Job queue / background worker -->

```typescript
async function schedulePoll(operationId: string, shopId: string, shopifyId: string): Promise<void> {
  let attempts = 0;

  const poll = async (): Promise<void> => {
    if (attempts >= config.BULK_MAX_POLL_ATTEMPTS) {
      await db.query(
        `UPDATE bulk_operations SET status = 'failed', error_code = 'poll_timeout', updated_at = now() WHERE id = $1`,
        [operationId]
      );
      emit("bulk.failed", { operationId, shopId, type: "unknown", errorCode: "poll_timeout", errorMessage: "Max poll attempts reached" });
      return;
    }

    attempts++;

    const gql = getShopifyGraphQLClient(shopId);
    const result = await gql.query(`
      query {
        currentBulkOperation {
          id
          status
          url
          errorCode
          objectCount
          fileSize
        }
      }
    `);

    const bulkOp = result.currentBulkOperation;

    if (!bulkOp || bulkOp.id !== shopifyId) {
      // Operation no longer current — may have been superseded
      await db.query(
        `UPDATE bulk_operations SET status = 'failed', error_code = 'operation_superseded', updated_at = now() WHERE id = $1`,
        [operationId]
      );
      return;
    }

    if (["COMPLETED", "FAILED", "CANCELLED"].includes(bulkOp.status)) {
      await handleBulkOperationsFinish({ admin_graphql_api_id: shopifyId }, await getShopDomain(shopId));
      return;
    }

    // Still running — schedule next poll
    setTimeout(poll, config.BULK_POLL_INTERVAL_MS);
  };

  setTimeout(poll, config.BULK_POLL_INTERVAL_MS);
}
```

---

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `missing_query` | 400 | Query body field is missing or not a string |
| `missing_mutation_or_variables` | 400 | Mutation or variables array missing |
| `bulk_operation_in_progress` | 409 | Shop already has an active operation of same type |
| `shopify_rejected_query` | 422 | Shopify returned `userErrors` on `bulkOperationRunQuery` |
| `shopify_rejected_mutation` | 422 | Shopify returned `userErrors` on `bulkOperationRunMutation` |
| `staged_upload_failed` | 422 | Shopify returned `userErrors` on `stagedUploadsCreate` |
| `staged_upload_upload_failed` | 502 | HTTP PUT to staged URL failed |
| `operation_not_found` | 404 | Operation ID not found or belongs to different shop |
| `operation_not_cancellable` | 409 | Operation is already in a terminal state |
| `operation_not_completed` | 409 | Results requested but operation not yet completed |
| `result_url_expired` | 410 | Result URL was null (expired ~24h after completion) |
| `result_download_failed` | 502 | HTTP GET to result URL failed |
| `cancel_failed` | 422 | Shopify returned `userErrors` on `bulkOperationCancel` |

## Anti-patterns

**DON'T** expose `result_url` directly to the client. The URL is signed by Shopify and grants unauthenticated access to potentially sensitive merchant data — always proxy through your backend.

**DON'T** load the entire JSONL file into memory. Results can be hundreds of megabytes. Stream line by line and process in batches controlled by `BULK_RESULT_PROCESSING_BATCH_SIZE`.

**DON'T** skip the one-per-shop constraint check. If you submit a second bulk query while one is running, Shopify will cancel the first one automatically, losing its results.

**DON'T** rely solely on polling in production. If the server restarts mid-poll, the operation completes silently. Prefer `BULK_PREFER_WEBHOOK=true` and use polling only as a fallback.

**DON'T** block on JSONL processing before acknowledging the webhook. Respond 200 to `BULK_OPERATIONS_FINISH` immediately, then process results asynchronously.

**DON'T** assume JSONL objects are ordered with parents before children. The `groupByParent` pattern handles out-of-order lines by buffering the full batch, but for very large files use a streaming approach that handles forward references.
