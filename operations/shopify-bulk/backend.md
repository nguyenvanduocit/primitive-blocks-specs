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

## External Contract Quick Reference

See README §2 "External Contract Reference" for full table. The most error-prone items repeated:

- Webhook topic name: **`BULK_OPERATIONS_FINISH`** (exact case)
- Webhook payload key: **`admin_graphql_api_id`** (bulk operation GID)
- JSONL nested-resource key: **`__parentId`** (two leading underscores)
- Result URL TTL: **~24h** — after that the URL returns 4xx/5xx; the app must process before then
- Per-shop concurrency: **1 active query + 1 active mutation** simultaneously

---

## Submit Bulk Query — Compose check → submit → record

### Pattern: Active-operation guard (one-per-type-per-shop)

<!-- PATTERN: bulk-active-operation-guard -->
<!-- PURPOSE: Reject submission if shop already has an active operation of the same type -->
<!-- REFERENCE: dialect=postgres orm=raw-sql external-contract=shopify-bulk-concurrency -->
<!-- ADAPT:
       - SQL placeholder `$1`/`$2`: postgres-style; MySQL/SQLite use `?`
       - ORM equivalent: Drizzle `db.select().from(bulkOperations).where(and(eq, eq, inArray(status, ["created","running"])))`
       - `status IN ('created','running')`: app-side state set — see README §5 status mapping
       - One-per-type rule mirrors Shopify's external constraint; if you skip this check Shopify will silently cancel the old op -->

```typescript
async function hasActiveBulkOp(shopId: string, type: "query" | "mutation"): Promise<string | null> {
  const row = await db.query(
    `SELECT id FROM bulk_operations
     WHERE shop_id = $1 AND type = $2 AND status IN ('created', 'running')
     LIMIT 1`,
    [shopId, type]
  );
  return row?.id ?? null;
}
```

### Pattern: Call `bulkOperationRunQuery` mutation

<!-- PATTERN: bulk-query-submit-call -->
<!-- PURPOSE: Submit a bulk query to Shopify and return the assigned operation GID -->
<!-- REFERENCE: external-contract=shopify-graphql-admin runtime=node20+ -->
<!-- ADAPT:
       - Mutation string and field selection: Shopify-dictated, KHÔNG đổi
       - `getShopifyGraphQLClient(shopId)`: shared GraphQL client from `auth.shopify-oauth` — adapt to your DI/factory
       - `userErrors` non-empty → caller returns 422 with Shopify's verbatim error array -->

```typescript
const BULK_OPERATION_RUN_QUERY = `
  mutation bulkOperationRunQuery($query: String!) {
    bulkOperationRunQuery(query: $query) {
      bulkOperation { id status }
      userErrors { field message }
    }
  }`;

async function callBulkOperationRunQuery(shopId: string, query: string) {
  const gql = getShopifyGraphQLClient(shopId);
  const r = await gql.mutation(BULK_OPERATION_RUN_QUERY, { query });
  return r.bulkOperationRunQuery as {
    bulkOperation: { id: string; status: string } | null;
    userErrors: { field: string[]; message: string }[];
  };
}
```

### Pattern: Insert bulk_operations record

<!-- PATTERN: bulk-operation-insert -->
<!-- PURPOSE: Persist a newly-submitted bulk operation for tracking + later result retrieval -->
<!-- REFERENCE: dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - `INSERT ... RETURNING *`: postgres-only. MySQL: `INSERT` then `SELECT WHERE id = LAST_INSERT_ID()`. SQLite ≥3.35: supports `RETURNING`.
       - ORM equivalent: Drizzle `.returning()`; Prisma `.create({ data })`
       - `type` and `status` are app-side enum strings — keep lowercase per CHECK constraint -->

```typescript
async function insertBulkOpRecord(
  shopId: string, shopifyId: string, type: "query" | "mutation", queryText: string
) {
  return db.query(`
    INSERT INTO bulk_operations
      (shop_id, shopify_operation_id, type, status, query_text)
    VALUES ($1, $2, $3, 'created', $4)
    RETURNING *
  `, [shopId, shopifyId, type, queryText]);
}
```

### Composition: Submit-query handler

<!-- PATTERN: bulk-query-submit-handler -->
<!-- PURPOSE: Wire guard → Shopify submit → insert → emit; respond 202 with the operationId -->
<!-- REFERENCE: framework=generic runtime=node20+ -->
<!-- ADAPT:
       - `req.shopContext`: from `auth.shopify-session-token` middleware
       - `req.body.query`: validate as non-empty string at API boundary (Zod, Valibot, manual)
       - `schedulePoll(...)`: background poller — only invoked when `BULK_PREFER_WEBHOOK` is false -->

```typescript
async function handleBulkQuerySubmit(req: Request): Promise<Response> {
  const { shopId } = req.shopContext;
  const { query } = req.body as { query?: string };
  if (!query || typeof query !== "string") return error(400, "missing_query");
  const existing = await hasActiveBulkOp(shopId, "query");
  if (existing) return error(409, "bulk_operation_in_progress", { type: "query", existingId: existing });
  const { bulkOperation, userErrors } = await callBulkOperationRunQuery(shopId, query);
  if (userErrors.length > 0 || !bulkOperation) return error(422, "shopify_rejected_query", { errors: userErrors });
  const op = await insertBulkOpRecord(shopId, bulkOperation.id, "query", query);
  emit("bulk.started", { operationId: op.id, shopId, type: "query", shopifyOperationId: bulkOperation.id });
  if (!config.BULK_PREFER_WEBHOOK) schedulePoll(op.id, shopId, bulkOperation.id);
  return json(202, { operationId: op.id, shopifyOperationId: bulkOperation.id, status: "created" });
}
```

---

## Submit Bulk Mutation — Compose serialize → stage → upload → submit

### Pattern: Serialize variables to JSONL

<!-- PATTERN: bulk-mutation-jsonl-serialize -->
<!-- PURPOSE: Serialize an array of variable objects to JSONL (one JSON object per line) for staged upload -->
<!-- REFERENCE: external-contract=shopify-bulk-jsonl language=typescript -->
<!-- ADAPT:
       - JSONL contract: line-delimited JSON, one object per line, LF-terminated. Shopify rejects CRLF or trailing commas.
       - `Buffer.from(..., "utf-8")`: replace with `TextEncoder().encode(...)` on edge runtimes
       - For very large variable arrays, stream into a temp file rather than building a Buffer in memory -->

```typescript
function serializeJsonl(variables: object[]): Buffer {
  if (!Array.isArray(variables) || variables.length === 0) {
    throw new AppError(400, "missing_mutation_or_variables");
  }
  const content = variables.map((v) => JSON.stringify(v)).join("\n");
  return Buffer.from(content, "utf-8");
}
```

### Pattern: Call `stagedUploadsCreate`

<!-- PATTERN: bulk-staged-uploads-create -->
<!-- PURPOSE: Request a Shopify-managed staged upload URL for the JSONL variables file -->
<!-- REFERENCE: external-contract=shopify-graphql-admin -->
<!-- ADAPT:
       - Mutation string + input shape: Shopify-dictated, KHÔNG đổi
       - `resource: "BULK_MUTATION_VARIABLES"`, `mimeType: "text/jsonl"`, `httpMethod: "POST"`: external contract enum values for this use case
       - `fileSize` must be the exact byte count of the JSONL buffer
       - Caller handles `userErrors` non-empty → 422 -->

```typescript
const STAGED_UPLOADS_CREATE = `
  mutation stagedUploadsCreate($input: [StagedUploadInput!]!) {
    stagedUploadsCreate(input: $input) {
      stagedTargets { url resourceUrl parameters { name value } }
      userErrors { field message }
    }
  }`;

async function callStagedUploadsCreate(shopId: string, fileSize: number) {
  const gql = getShopifyGraphQLClient(shopId);
  const r = await gql.mutation(STAGED_UPLOADS_CREATE, {
    input: [{ resource: "BULK_MUTATION_VARIABLES", filename: "bulk-variables.jsonl",
              mimeType: "text/jsonl", fileSize: String(fileSize), httpMethod: "POST" }],
  });
  return r.stagedUploadsCreate as {
    stagedTargets: { url: string; resourceUrl: string; parameters: { name: string; value: string }[] }[];
    userErrors: { field: string[]; message: string }[];
  };
}
```

### Pattern: Upload JSONL to staged URL

<!-- PATTERN: bulk-staged-upload-post -->
<!-- PURPOSE: POST the JSONL bytes to the Shopify-provided staged storage URL using multipart form -->
<!-- REFERENCE: external-contract=shopify-staged-upload runtime=node20+ http=fetch-builtin -->
<!-- ADAPT:
       - Form field order: Shopify expects `parameters` fields FIRST, then `file` last — keep order
       - `multipart/form-data` is dictated by Shopify staged upload contract
       - `FormData` / `Blob`: standard Web APIs; Node 18+ supports built-in, older Node use `form-data` package
       - Response 201/204 = success; 4xx/5xx → throw and caller returns 502 -->

```typescript
async function uploadJsonlToStaged(
  target: { url: string; parameters: { name: string; value: string }[] },
  jsonl: Buffer
): Promise<void> {
  const form = new FormData();
  for (const p of target.parameters) form.append(p.name, p.value);
  form.append("file", new Blob([jsonl], { type: "text/jsonl" }), "bulk-variables.jsonl");
  const resp = await fetch(target.url, { method: "POST", body: form });
  if (!resp.ok) throw new AppError(502, "staged_upload_upload_failed", { status: resp.status });
}
```

### Pattern: Derive `stagedUploadPath` from `resourceUrl`

<!-- PATTERN: bulk-staged-path-extract -->
<!-- PURPOSE: Extract the path portion that `bulkOperationRunMutation` expects from the staged resource URL -->
<!-- REFERENCE: external-contract=shopify-staged-upload language=typescript -->
<!-- ADAPT:
       - resourceUrl format: `https://storage.googleapis.com/shopify/<staged-path>` (Shopify's GCS bucket)
       - Strip leading `/shopify/` prefix to get the path Shopify's bulk-mutation API expects
       - If Shopify changes hosting (e.g. moves to S3), the strip prefix may change — verify against current docs -->

```typescript
function extractStagedUploadPath(resourceUrl: string): string {
  return new URL(resourceUrl).pathname.replace(/^\/shopify\//, "");
}
```

### Pattern: Call `bulkOperationRunMutation`

<!-- PATTERN: bulk-mutation-submit-call -->
<!-- PURPOSE: Submit a bulk mutation referencing the staged JSONL upload -->
<!-- REFERENCE: external-contract=shopify-graphql-admin -->
<!-- ADAPT:
       - Mutation string and arguments (`mutation`, `stagedUploadPath`): Shopify-dictated, KHÔNG đổi
       - Caller handles `userErrors` non-empty → 422 -->

```typescript
const BULK_OPERATION_RUN_MUTATION = `
  mutation bulkOperationRunMutation($mutation: String!, $stagedUploadPath: String!) {
    bulkOperationRunMutation(mutation: $mutation, stagedUploadPath: $stagedUploadPath) {
      bulkOperation { id status }
      userErrors { field message }
    }
  }`;

async function callBulkOperationRunMutation(shopId: string, mutation: string, stagedUploadPath: string) {
  const gql = getShopifyGraphQLClient(shopId);
  const r = await gql.mutation(BULK_OPERATION_RUN_MUTATION, { mutation, stagedUploadPath });
  return r.bulkOperationRunMutation as {
    bulkOperation: { id: string; status: string } | null;
    userErrors: { field: string[]; message: string }[];
  };
}
```

### Composition: Submit-mutation handler

<!-- PATTERN: bulk-mutation-submit-handler -->
<!-- PURPOSE: Wire guard → serialize → stage → upload → submit → insert; respond 202 -->
<!-- REFERENCE: framework=generic runtime=node20+ -->
<!-- ADAPT:
       - `req.body.mutation` / `req.body.variables`: validate at API boundary
       - Stage error → 422 `staged_upload_failed`; upload error → 502 `staged_upload_upload_failed` -->

```typescript
async function handleBulkMutationSubmit(req: Request): Promise<Response> {
  const { shopId } = req.shopContext;
  const { mutation, variables } = req.body as { mutation?: string; variables?: object[] };
  if (!mutation || !Array.isArray(variables) || variables.length === 0) return error(400, "missing_mutation_or_variables");
  const existing = await hasActiveBulkOp(shopId, "mutation");
  if (existing) return error(409, "bulk_operation_in_progress", { type: "mutation", existingId: existing });
  const jsonl = serializeJsonl(variables);
  const stage = await callStagedUploadsCreate(shopId, jsonl.byteLength);
  if (stage.userErrors.length > 0) return error(422, "staged_upload_failed", { errors: stage.userErrors });
  const target = stage.stagedTargets[0];
  await uploadJsonlToStaged(target, jsonl);
  const stagedUploadPath = extractStagedUploadPath(target.resourceUrl);
  const { bulkOperation, userErrors } = await callBulkOperationRunMutation(shopId, mutation, stagedUploadPath);
  if (userErrors.length > 0 || !bulkOperation) return error(422, "shopify_rejected_mutation", { errors: userErrors });
  const op = await insertBulkOpRecord(shopId, bulkOperation.id, "mutation", mutation);
  emit("bulk.started", { operationId: op.id, shopId, type: "mutation", shopifyOperationId: bulkOperation.id });
  if (!config.BULK_PREFER_WEBHOOK) schedulePoll(op.id, shopId, bulkOperation.id);
  return json(202, { operationId: op.id, shopifyOperationId: bulkOperation.id, status: "created" });
}
```

---

## Status & Cancel — Simple handlers

### Pattern: Get operation status

<!-- PATTERN: bulk-status-handler -->
<!-- PURPOSE: Return current operation status, scoped to requesting shop -->
<!-- REFERENCE: dialect=postgres orm=raw-sql framework=generic -->
<!-- ADAPT:
       - SQL placeholder `$1`/`$2`: postgres-style
       - WHERE clause MUST include both `id` and `shop_id` — tenant isolation
       - Never return `result_url` — that's the internal-only signed Shopify URL -->

```typescript
async function handleBulkStatus(req: Request): Promise<Response> {
  const { shopId } = req.shopContext;
  const { operationId } = req.params;
  const op = await db.query(
    `SELECT id, shopify_operation_id, type, status, object_count, file_size,
            error_code, error_message, started_at, completed_at, created_at
     FROM bulk_operations WHERE id = $1 AND shop_id = $2`,
    [operationId, shopId]
  );
  if (!op) return error(404, "operation_not_found");
  return json(200, op);
}
```

### Pattern: Cancel operation

<!-- PATTERN: bulk-cancel-handler -->
<!-- PURPOSE: Send bulkOperationCancel to Shopify and mark local record cancelled -->
<!-- REFERENCE: external-contract=shopify-graphql-admin dialect=postgres -->
<!-- ADAPT:
       - Mutation `bulkOperationCancel`: Shopify-dictated, KHÔNG đổi
       - Only `created` or `running` ops are cancellable — guard via status check
       - Update local status to `cancelled` AFTER Shopify accepts the cancel — Shopify may move through CANCELING then CANCELED; webhook reconciles -->

```typescript
const BULK_OPERATION_CANCEL = `
  mutation bulkOperationCancel($id: ID!) {
    bulkOperationCancel(id: $id) { bulkOperation { id status } userErrors { field message } }
  }`;

async function handleBulkCancel(req: Request): Promise<Response> {
  const { shopId } = req.shopContext;
  const { operationId } = req.params;
  const op = await db.query(`SELECT * FROM bulk_operations WHERE id = $1 AND shop_id = $2`, [operationId, shopId]);
  if (!op) return error(404, "operation_not_found");
  if (!["created", "running"].includes(op.status)) return error(409, "operation_not_cancellable", { status: op.status });
  const gql = getShopifyGraphQLClient(shopId);
  const r = await gql.mutation(BULK_OPERATION_CANCEL, { id: op.shopify_operation_id });
  if (r.bulkOperationCancel.userErrors.length > 0) return error(422, "cancel_failed", { errors: r.bulkOperationCancel.userErrors });
  await db.query(`UPDATE bulk_operations SET status='cancelled', updated_at=now() WHERE id = $1`, [operationId]);
  return json(200, { status: "cancelled" });
}
```

---

## Results Processing — Compose stream → parse → batch → process

### Pattern: Stream JSONL line by line

<!-- PATTERN: bulk-jsonl-stream-lines -->
<!-- PURPOSE: Async-iterate JSONL lines from a Shopify result URL without loading the whole file -->
<!-- REFERENCE: external-contract=shopify-bulk-jsonl runtime=node20+ -->
<!-- ADAPT:
       - `fetch(...).body.getReader()`: Web Streams API; on older Node use `node-fetch` + Node streams
       - `TextDecoder("utf-8")`: handle multi-byte boundaries with `{ stream: true }`
       - Buffer holds incomplete trailing line until next chunk — empty buffer at end indicates clean termination
       - JSONL contract: lines separated by LF; blank lines ignored -->

```typescript
async function* streamJsonlLines(url: string): AsyncGenerator<string> {
  const resp = await fetch(url);
  if (!resp.ok || !resp.body) throw new AppError(502, "result_download_failed");
  const reader = resp.body.getReader();
  const decoder = new TextDecoder("utf-8");
  let buffer = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";
    for (const line of lines) if (line.trim()) yield line;
  }
  if (buffer.trim()) yield buffer;
}
```

### Pattern: Parse + batch lines

<!-- PATTERN: bulk-jsonl-parse-batch -->
<!-- PURPOSE: Parse JSONL line stream into typed objects and accumulate into fixed-size batches -->
<!-- REFERENCE: external-contract=shopify-bulk-jsonl language=typescript -->
<!-- ADAPT:
       - `BulkResultObject` shape: minimal; extend with project-specific resource type interfaces if needed
       - Batch size from `BULK_RESULT_PROCESSING_BATCH_SIZE` config — tune for memory vs throughput trade-off
       - `__parentId` key: Shopify external contract for nested resources; preserve as-is on parsed line
       - Yields final partial batch — caller should not assume every yielded batch is full -->

```typescript
interface BulkResultObject { id: string; __parentId?: string; [k: string]: unknown; }

async function* batchJsonl(
  lines: AsyncIterable<string>, batchSize: number
): AsyncGenerator<BulkResultObject[]> {
  let batch: BulkResultObject[] = [];
  for await (const line of lines) {
    batch.push(JSON.parse(line) as BulkResultObject);
    if (batch.length >= batchSize) { yield batch; batch = []; }
  }
  if (batch.length > 0) yield batch;
}
```

### Pattern: Group children by `__parentId`

<!-- PATTERN: bulk-jsonl-parent-grouping -->
<!-- PURPOSE: Reconstruct parent-child tree from flat JSONL using __parentId convention -->
<!-- REFERENCE: external-contract=shopify-bulk-jsonl language=typescript -->
<!-- ADAPT:
       - `__parentId` is Shopify-dictated convention; child line has it set to parent's `id`
       - Caveat: JSONL ordering is NOT guaranteed parent-first within a single batch; for cross-batch parent/child references, accumulate across batches before grouping
       - For very large datasets, prefer 2-pass: first pass index parents by id, second pass attach children -->

```typescript
interface ParsedBulkNode { id: string; parentId?: string; data: Record<string, unknown>; children: ParsedBulkNode[]; }

function groupByParent(lines: BulkResultObject[]): ParsedBulkNode[] {
  const map = new Map<string, ParsedBulkNode>();
  const roots: ParsedBulkNode[] = [];
  for (const line of lines) {
    const node: ParsedBulkNode = { id: line.id, parentId: line.__parentId, data: line, children: [] };
    map.set(line.id, node);
    if (line.__parentId) {
      const parent = map.get(line.__parentId);
      if (parent) parent.children.push(node); else roots.push(node); // orphan → root for caller to reconcile
    } else roots.push(node);
  }
  return roots;
}
```

### Pattern: Process-batch callback

<!-- PATTERN: bulk-results-process-batch -->
<!-- PURPOSE: Apply application-specific processing to one batch of grouped objects -->
<!-- REFERENCE: language=typescript -->
<!-- ADAPT:
       - Replace `upsertProductWithVariants` with the merchant's resource handler — products, customers, orders, metafields, etc.
       - All writes inside `processBatch` must be idempotent (upsert, not insert-only) so retries do not duplicate
       - Apply same access controls / data filters as direct API calls — bulk results are NOT a permission bypass -->

```typescript
async function processBatch(
  batch: BulkResultObject[], shopId: string, _operationId: string
): Promise<void> {
  const grouped = groupByParent(batch);
  for (const root of grouped) {
    await upsertProductWithVariants(root, shopId); // application-specific
  }
}
```

### Composition: Results handler

<!-- PATTERN: bulk-results-handler -->
<!-- PURPOSE: Load record → validate completed/url → stream+parse+batch → process → emit -->
<!-- REFERENCE: framework=generic runtime=node20+ -->
<!-- ADAPT:
       - Tenant isolation: WHERE clause includes `shop_id` from session context
       - `result_url` never returned to client — it's a signed Shopify URL with broad access
       - On expired URL (null `result_url` after 24h) return 410 Gone -->

```typescript
async function handleBulkResults(req: Request): Promise<Response> {
  const { shopId } = req.shopContext;
  const { operationId } = req.params;
  const op = await db.query(`SELECT * FROM bulk_operations WHERE id = $1 AND shop_id = $2`, [operationId, shopId]);
  if (!op) return error(404, "operation_not_found");
  if (op.status !== "completed") return error(409, "operation_not_completed", { status: op.status });
  if (!op.result_url) return error(410, "result_url_expired");
  let processedCount = 0, batchCount = 0;
  for await (const batch of batchJsonl(streamJsonlLines(op.result_url), config.BULK_RESULT_PROCESSING_BATCH_SIZE)) {
    await processBatch(batch, shopId, operationId);
    processedCount += batch.length; batchCount++;
  }
  emit("bulk.results_processed", { operationId, shopId, processedCount, batchCount });
  return json(200, { processedCount, batchCount });
}
```

---

## Webhook: `BULK_OPERATIONS_FINISH` — Compose lookup → fetch → persist → emit

### Pattern: Fetch BulkOperation by ID

<!-- PATTERN: bulk-fetch-by-id -->
<!-- PURPOSE: Fetch terminal-state details (status, url, errorCode, counts) for a known BulkOperation GID -->
<!-- REFERENCE: external-contract=shopify-graphql-admin -->
<!-- ADAPT:
       - Use `node(id:)` + inline fragment on `BulkOperation` — Shopify-dictated way to fetch any node by GID
       - Field selection: pick only what you persist (url, errorCode, counts, timestamps)
       - For polling (when current op), prefer `currentBulkOperation` instead — see `bulk-polling` pattern below -->

```typescript
const BULK_FETCH_BY_ID = `
  query getBulkOperation($id: ID!) {
    node(id: $id) {
      ... on BulkOperation {
        id status url errorCode objectCount fileSize createdAt completedAt
      }
    }
  }`;

async function fetchBulkOpById(shopId: string, gid: string) {
  const gql = getShopifyGraphQLClient(shopId);
  const r = await gql.query(BULK_FETCH_BY_ID, { id: gid });
  return r.node as {
    id: string; status: string; url: string | null; errorCode: string | null;
    objectCount: number | null; fileSize: number | null;
    createdAt: string | null; completedAt: string | null;
  } | null;
}
```

### Pattern: Map Shopify BulkOperation status to app status

<!-- PATTERN: bulk-status-map -->
<!-- PURPOSE: Translate Shopify's BulkOperationStatus enum to app-side status -->
<!-- REFERENCE: external-contract=shopify-bulk-operation-status -->
<!-- ADAPT:
       - Shopify enum values (`COMPLETED`, `FAILED`, `CANCELED`, `CANCELING`, `EXPIRED`, `RUNNING`, `CREATED`): external contract, KHÔNG đổi
       - App-side enum values (`completed`, `failed`, `cancelled`, `running`, `created`): see README §2 status column
       - `EXPIRED` (result URL TTL elapsed) maps to `failed` with code `expired` — Shopify-defined value; preserve verbatim if you store separately
       - Unknown status → conservative `failed` -->

```typescript
function mapShopifyBulkStatus(s: string): "completed" | "failed" | "cancelled" | "running" | "created" {
  switch (s) {
    case "COMPLETED": return "completed";
    case "FAILED":
    case "EXPIRED": return "failed";
    case "CANCELED":
    case "CANCELING": return "cancelled";
    case "RUNNING": return "running";
    case "CREATED": return "created";
    default: return "failed";
  }
}
```

### Pattern: Persist terminal state + emit completion event

<!-- PATTERN: bulk-persist-terminal -->
<!-- PURPOSE: Update bulk_operations row with terminal fields and emit completed/failed event -->
<!-- REFERENCE: dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - SQL placeholder `$1...`: postgres-style
       - ORM equivalent: Drizzle `db.update(bulkOperations).set({...}).where(eq(id, ...))`
       - Emit `bulk.completed` only on `completed`; `bulk.failed` on anything else terminal -->

```typescript
async function persistBulkTerminal(opId: string, shopId: string, type: string, st: {
  status: string; url: string | null; errorCode: string | null;
  objectCount: number | null; fileSize: number | null;
  createdAt: string | null; completedAt: string | null;
}): Promise<void> {
  await db.query(`
    UPDATE bulk_operations SET
      status=$1, result_url=$2, error_code=$3, object_count=$4, file_size=$5,
      started_at=$6, completed_at=$7, updated_at=now()
    WHERE id = $8`,
    [st.status, st.url, st.errorCode, st.objectCount, st.fileSize, st.createdAt, st.completedAt, opId]
  );
  if (st.status === "completed") {
    emit("bulk.completed", { operationId: opId, shopId, type, objectCount: st.objectCount, fileSize: st.fileSize, resultUrl: st.url });
  } else {
    emit("bulk.failed", { operationId: opId, shopId, type, errorCode: st.errorCode, errorMessage: null });
  }
}
```

### Composition: Webhook handler

<!-- PATTERN: bulk-webhook-handler -->
<!-- PURPOSE: Reconcile completion webhook with local record; respond 200 immediately, process out-of-band -->
<!-- REFERENCE: external-contract=shopify-webhook framework=generic -->
<!-- ADAPT:
       - Webhook topic name `BULK_OPERATIONS_FINISH`: external contract, KHÔNG đổi
       - Payload key `admin_graphql_api_id`: external contract — the bulk operation GID
       - Caller is the webhook router from `webhooks.shopify-webhooks` — HMAC already verified upstream
       - Unknown shop or operation → silent ignore (do not 5xx — Shopify will retry) -->

```typescript
interface BulkOperationsFinishPayload { admin_graphql_api_id: string; }

async function handleBulkOperationsFinish(payload: BulkOperationsFinishPayload, shopDomain: string): Promise<void> {
  const shop = await getShopByDomain(shopDomain);
  if (!shop) return;
  const op = await db.query(
    `SELECT id, type FROM bulk_operations WHERE shopify_operation_id = $1 AND shop_id = $2`,
    [payload.admin_graphql_api_id, shop.id]
  );
  if (!op) return;
  const bulkOp = await fetchBulkOpById(shop.id, payload.admin_graphql_api_id);
  if (!bulkOp) return;
  await persistBulkTerminal(op.id, shop.id, op.type, {
    status: mapShopifyBulkStatus(bulkOp.status), url: bulkOp.url, errorCode: bulkOp.errorCode,
    objectCount: bulkOp.objectCount, fileSize: bulkOp.fileSize,
    createdAt: bulkOp.createdAt, completedAt: bulkOp.completedAt,
  });
}
```

---

## Polling Fallback — When webhook not preferred

### Pattern: `currentBulkOperation` query

<!-- PATTERN: bulk-poll-current -->
<!-- PURPOSE: Fetch the shop's current bulk op state (used in polling mode) -->
<!-- REFERENCE: external-contract=shopify-graphql-admin -->
<!-- ADAPT:
       - `currentBulkOperation` returns the single active op for the shop OR the most recent terminal op
       - If returned id doesn't match the one we're polling for, the op has been superseded — see polling loop -->

```typescript
const BULK_CURRENT_OPERATION = `
  query { currentBulkOperation { id status url errorCode objectCount fileSize } }`;

async function fetchCurrentBulkOperation(shopId: string) {
  const gql = getShopifyGraphQLClient(shopId);
  const r = await gql.query(BULK_CURRENT_OPERATION);
  return r.currentBulkOperation as {
    id: string; status: string; url: string | null; errorCode: string | null;
    objectCount: number | null; fileSize: number | null;
  } | null;
}
```

### Pattern: Polling loop with bounded attempts

<!-- PATTERN: bulk-polling -->
<!-- PURPOSE: Poll currentBulkOperation until terminal state or max attempts -->
<!-- REFERENCE: framework=generic runtime=node20+ external-contract=shopify-graphql-admin -->
<!-- ADAPT:
       - `setTimeout(poll, ...)` is in-process polling — replace with persistent job queue (BullMQ, Inngest, pg_cron) for production resilience
       - `BULK_POLL_INTERVAL_MS` and `BULK_MAX_POLL_ATTEMPTS` from config — tune to operation expected duration
       - On `id` mismatch: another operation superseded this one — mark this one failed with code `operation_superseded`
       - Webhook mode is more resilient — prefer that for production -->

```typescript
async function schedulePoll(operationId: string, shopId: string, shopifyId: string): Promise<void> {
  let attempts = 0;
  const poll = async (): Promise<void> => {
    if (attempts++ >= config.BULK_MAX_POLL_ATTEMPTS) {
      await db.query(`UPDATE bulk_operations SET status='failed', error_code='poll_timeout', updated_at=now() WHERE id=$1`, [operationId]);
      emit("bulk.failed", { operationId, shopId, type: "unknown", errorCode: "poll_timeout", errorMessage: "max poll attempts" });
      return;
    }
    const bulkOp = await fetchCurrentBulkOperation(shopId);
    if (!bulkOp || bulkOp.id !== shopifyId) {
      await db.query(`UPDATE bulk_operations SET status='failed', error_code='operation_superseded', updated_at=now() WHERE id=$1`, [operationId]);
      return;
    }
    if (["COMPLETED", "FAILED", "CANCELED", "EXPIRED"].includes(bulkOp.status)) {
      await handleBulkOperationsFinish({ admin_graphql_api_id: shopifyId }, await getShopDomain(shopId));
      return;
    }
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
| `staged_upload_upload_failed` | 502 | HTTP POST to staged URL failed |
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

**DON'T** assume JSONL objects are ordered with parents before children. The `groupByParent` pattern handles in-batch out-of-order via the orphan-as-root fallback; for cross-batch references, accumulate or two-pass.

**DON'T** confuse the `__parentId` convention (two leading underscores) with `parentId`/`parent_id`. Only `__parentId` is the Shopify external contract.

**DON'T** rename the webhook topic from `BULK_OPERATIONS_FINISH` — it's the exact case-sensitive identifier Shopify sends.
