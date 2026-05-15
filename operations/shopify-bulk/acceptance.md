# Acceptance Checklist — Shopify Bulk Operations

Claude Code runs this checklist after implementation, before reporting done.

## Database

- [ ] Migration runs successfully (`bulk_operations` table created)
- [ ] `UNIQUE` constraint on `bulk_operations.shopify_operation_id` is active
- [ ] `CHECK` constraint on `type` enforces `'query'` or `'mutation'` values
- [ ] `CHECK` constraint on `status` enforces valid state values
- [ ] Index `idx_bulk_shop` on `shop_id` exists
- [ ] Index `idx_bulk_status` on `(shop_id, status)` exists
- [ ] Index `idx_bulk_shopify_id` on `shopify_operation_id` (WHERE NOT NULL) exists
- [ ] All queries include `shop_id` in WHERE clause (tenant isolation)
- [ ] `ON DELETE CASCADE` on `shop_id` FK correctly removes operations when shop is deleted

## Bulk Query

- [ ] POST /api/bulk/query requires valid session token
- [ ] POST /api/bulk/query returns 202 with `operationId` and `shopifyOperationId`
- [ ] POST /api/bulk/query returns 409 when a query with status `created` or `running` exists for shop
- [ ] POST /api/bulk/query returns 400 when `query` body field is missing
- [ ] POST /api/bulk/query calls `bulkOperationRunQuery` mutation with correct query string
- [ ] POST /api/bulk/query returns 422 when Shopify returns `userErrors`
- [ ] `bulk.started` event is emitted on successful query submission
- [ ] Polling starts automatically when `BULK_PREFER_WEBHOOK=false`
- [ ] Polling stops at `BULK_MAX_POLL_ATTEMPTS` and marks operation as `failed` with `poll_timeout`

## Bulk Mutation

- [ ] POST /api/bulk/mutation requires valid session token
- [ ] POST /api/bulk/mutation returns 202 with `operationId` and `shopifyOperationId`
- [ ] POST /api/bulk/mutation returns 409 when a mutation with status `created` or `running` exists
- [ ] POST /api/bulk/mutation returns 400 when `mutation` or `variables` is missing
- [ ] POST /api/bulk/mutation returns 400 when `variables` is an empty array
- [ ] `stagedUploadsCreate` is called with `resource: BULK_MUTATION_VARIABLES` and correct metadata
- [ ] Variables array is serialized to JSONL — one JSON object per line, no embedded newlines
- [ ] JSONL is uploaded to staged URL via multipart POST with all `parameters` included
- [ ] `bulkOperationRunMutation` is called with the mutation string and correct `stagedUploadPath`
- [ ] `stagedUploadPath` is correctly extracted from `resourceUrl` (strips `/shopify/` prefix)
- [ ] Returns 422 when `stagedUploadsCreate` returns `userErrors`
- [ ] Returns 502 when staged upload PUT fails
- [ ] Returns 422 when `bulkOperationRunMutation` returns `userErrors`
- [ ] `bulk.started` event emitted on successful mutation submission

## Status Tracking

- [ ] GET /api/bulk/status/:id requires valid session token
- [ ] GET /api/bulk/status/:id returns correct status, type, object_count, file_size
- [ ] GET /api/bulk/status/:id returns 404 for non-existent or cross-shop operation
- [ ] GET /api/bulk/status/:id does NOT expose `result_url` in response
- [ ] POST /api/bulk/cancel/:id calls `bulkOperationCancel` mutation
- [ ] POST /api/bulk/cancel/:id returns 409 for completed, failed, or cancelled operations
- [ ] POST /api/bulk/cancel/:id returns 404 for non-existent or cross-shop operation
- [ ] `BULK_OPERATIONS_FINISH` webhook verifies HMAC before processing
- [ ] Webhook handler responds 200 immediately before querying Shopify for final status
- [ ] Webhook updates `status`, `result_url`, `object_count`, `file_size`, `completed_at` correctly
- [ ] Webhook maps Shopify status: `COMPLETED→completed`, `FAILED→failed`, `CANCELLED→cancelled`
- [ ] `bulk.completed` event emitted when operation completes
- [ ] `bulk.failed` event emitted when operation fails with `errorCode`
- [ ] Webhook for unknown `shopify_operation_id` is silently ignored (no error)
- [ ] Duplicate webhook for same operation is handled idempotently

## Result Processing

- [ ] GET /api/bulk/results/:id requires valid session token
- [ ] GET /api/bulk/results/:id returns 409 when operation is not `completed`
- [ ] GET /api/bulk/results/:id returns 410 when `result_url` is null (expired)
- [ ] GET /api/bulk/results/:id returns 404 for non-existent or cross-shop operation
- [ ] JSONL is fetched from `result_url` server-side (never exposed to client)
- [ ] JSONL is streamed line by line — not fully buffered in memory
- [ ] Blank lines in JSONL are skipped without error
- [ ] Flat objects (no `__parentId`) are processed as root objects
- [ ] Objects with `__parentId` are grouped as children of matching parent
- [ ] Processing occurs in batches of `BULK_RESULT_PROCESSING_BATCH_SIZE` lines
- [ ] Final partial batch (smaller than batch size) is processed correctly
- [ ] Empty JSONL (zero lines) returns 200 with `processedCount: 0`
- [ ] `bulk.results_processed` event emitted with `processedCount` and `batchCount`
- [ ] Returns 502 when `result_url` download fails
- [ ] JSONL content is not logged — only aggregate counts are logged

## Security

- [ ] `result_url` is never returned to the client in any response
- [ ] All endpoints require a valid session token (no unauthenticated access)
- [ ] All DB queries scope to `shop_id` from verified session token
- [ ] `BULK_OPERATIONS_FINISH` webhook verified with constant-time HMAC comparison
- [ ] Variables JSONL is serialized server-side — client never touches staged upload URL
- [ ] JSONL content is not logged

## Configuration

- [ ] `BULK_PREFER_WEBHOOK` defaults to `true`
- [ ] `BULK_POLL_INTERVAL_MS` defaults to `2000`
- [ ] `BULK_MAX_POLL_ATTEMPTS` defaults to `500`
- [ ] `BULK_RESULT_PROCESSING_BATCH_SIZE` defaults to `1000`
- [ ] Required config keys fail fast on missing value at startup

## Type Safety & Build

- [ ] `tsc --noEmit` passes (or equivalent type check)
- [ ] No `any` types without justification
- [ ] Zod (or equivalent) validation at API boundary for request bodies
- [ ] `BulkResultObject` and `ParsedBulkObject` types are defined and used
