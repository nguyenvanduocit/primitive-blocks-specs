# Backend Patterns — Shopify Webhook Management

> Snippets dưới đây là **L3 illustrative** (xem `docs/SPEC_GUIDELINES.md` mục 2). Mọi snippet ≤30 dòng với 4 marker — Claude Code adapt theo merchant stack qua `ADAPT` list.

## API Endpoints

### Public (Shopify-facing)

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `POST` | `/api/webhooks` | Receive all Shopify webhook deliveries | HMAC verified (no session auth) |

### Internal (called by other blocks or internal logic)

| Function | Purpose |
|----------|---------|
| `registerWebhooks(shopId)` | Register all configured topics for a shop after install |
| `syncWebhooks(shopId)` | Reconcile registered vs configured topics (add missing, remove stale) |
| `routeWebhook(topic, payload, shopId)` | Dispatch to the correct topic handler |

---

## Webhook Receiver

Receiver flow chia 3 trách nhiệm độc lập, compose theo thứ tự: **verify-and-ack → dedup-insert → dispatch**.

> **External contract (Shopify-dictated, KHÔNG được đổi)**:
> - HMAC algorithm: **HMAC-SHA256** over raw request body, encoded **base64**
> - Header carrying HMAC: `X-Shopify-Hmac-Sha256`
> - Response **must** be sent within **5 seconds** — Shopify retries otherwise
> - Idempotency key: `X-Shopify-Webhook-Id` header
> - Constant-time comparison required (chống timing attack)

### Pattern 1: HMAC verify + immediate 200 ack

<!-- PATTERN: shopify-webhook-verify-and-ack -->
<!-- PURPOSE: Read raw body, verify HMAC-SHA256 base64, send 200 within 5s; return raw body + Shopify headers for downstream -->
<!-- REFERENCE: runtime=node20+ framework=generic crypto=node-builtin algorithm=hmac-sha256 -->
<!-- ADAPT:
       - `readRawBody`: framework-specific — Express: `express.raw({ type: 'application/json' })` rồi `req.body` là Buffer; Hono: `await c.req.arrayBuffer()`; Fastify: `addContentTypeParser('application/json', { parseAs: 'buffer' })`; Deno/Oak: `await ctx.request.body({ type: 'bytes' }).value`
       - Header access lowercase: HTTP header name case-insensitive nhưng tên chính tả Shopify dictate — KHÔNG đổi spelling
       - Async dispatch: in-process `void promise`, queue (BullMQ/Inngest), edge waitUntil — chọn theo runtime
       - `verifyShopifyHmac`: dùng shared utility từ auth.shopify-oauth (HMAC-SHA256, base64, constant-time) -->

```typescript
async function handleWebhookReceive(req: RawRequest): Promise<Response> {
  // 1. Read raw body bytes FIRST — JSON middleware would corrupt HMAC input
  const rawBody = await readRawBody(req); // Buffer

  // 2. Verify HMAC-SHA256(rawBody, SHOPIFY_API_SECRET), compare base64 constant-time
  const hmacHeader = req.headers["x-shopify-hmac-sha256"] as string | undefined;
  if (!hmacHeader || !verifyShopifyHmac(config.SHOPIFY_API_SECRET, rawBody, hmacHeader)) {
    return error(401, "hmac_verification_failed");
  }

  // 3. Extract Shopify-dictated headers (exact names)
  const topic       = req.headers["x-shopify-topic"] as string;
  const shopDomain  = req.headers["x-shopify-shop-domain"] as string;
  const webhookId   = req.headers["x-shopify-webhook-id"] as string;

  // 4. Send 200 BEFORE processing — Shopify times out at 5s and will retry
  void processWebhookAsync(rawBody, topic, shopDomain, webhookId);
  return new Response(null, { status: 200 });
}
```

### Pattern 2: Idempotent delivery insert

<!-- PATTERN: shopify-webhook-dedup-insert -->
<!-- PURPOSE: INSERT webhook_deliveries with UNIQUE(webhook_id); skip on conflict to enforce exactly-once -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - `ON CONFLICT DO NOTHING ... RETURNING`: postgres + SQLite syntax; MySQL dùng `INSERT IGNORE` rồi check affected rows
       - `crypto.createHash("sha256")`: edge → Web Crypto `subtle.digest("SHA-256", body)` + hex encode; payload hash là forensic only, KHÔNG dùng cho idempotency
       - Idempotency key luôn là `webhook_id` (Shopify-dictated) — KHÔNG dùng payload hash thay thế
       - `getShopByDomain`: shared utility từ auth.shopify-oauth -->

```typescript
async function dedupInsertDelivery(
  rawBody: Buffer, topic: string, shopDomain: string, webhookId: string
): Promise<{ deliveryId: string; shopId: string } | null> {
  const shop = await getShopByDomain(shopDomain);
  if (!shop) {
    logger.warn({ shopDomain, topic }, "webhook for unknown shop");
    return null;
  }
  const payloadHash = crypto.createHash("sha256").update(rawBody).digest("hex");
  const result = await db.query(`
    INSERT INTO webhook_deliveries (shop_id, topic, webhook_id, payload_hash, status)
    VALUES ($1, $2, $3, $4, 'received')
    ON CONFLICT (webhook_id) DO NOTHING
    RETURNING id
  `, [shop.id, topic, webhookId, payloadHash]);
  if (result.rowCount === 0) {
    logger.info({ webhookId, topic }, "duplicate webhook — skipping");
    return null;
  }
  return { deliveryId: result.rows[0].id, shopId: shop.id };
}
```

### Pattern 3: Dispatch to handler

<!-- PATTERN: shopify-webhook-dispatch -->
<!-- PURPOSE: Emit received event, then route to async queue or inline executor based on config -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `dispatchToQueue`: queue framework tuỳ chọn — BullMQ `queue.add(...)`, Inngest `inngest.send(...)`, PgQueue insert, AWS SQS sendMessage
       - `emit`: event bus (in-process EventEmitter, Redis pubsub, etc.)
       - Sync mode (`WEBHOOK_PROCESS_ASYNC=false`) chỉ dùng cho test/dev — production nên async để không kéo dài request -->

```typescript
async function processWebhookAsync(
  rawBody: Buffer, topic: string, shopDomain: string, webhookId: string
): Promise<void> {
  const inserted = await dedupInsertDelivery(rawBody, topic, shopDomain, webhookId);
  if (!inserted) return; // unknown shop or duplicate
  const { deliveryId, shopId } = inserted;
  emit("webhook.received", { deliveryId, shopId, topic, webhookId });
  if (config.WEBHOOK_PROCESS_ASYNC) {
    await dispatchToQueue({ deliveryId, shopId, topic, rawBody, webhookId });
  } else {
    await executeTopicHandler(deliveryId, shopId, topic, rawBody, webhookId);
  }
}
```

---

## Topic Handler Execution

Handler execution chia 2 phase: **status-transition** (mark processing → terminal) và **handler-invoke** (pure business logic). Tách giúp test handler riêng mà không cần DB.

### Pattern 1: Status transition helper

<!-- PATTERN: webhook-delivery-status-transition -->
<!-- PURPOSE: Update webhook_deliveries.status — single source of truth for status writes -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - SQL placeholder `$1`: postgres; MySQL/SQLite dùng `?`
       - `now()`: postgres; MySQL `NOW()`; SQLite `CURRENT_TIMESTAMP`
       - Coalescing `status='failed', error=$2`: nếu ORM không hỗ trợ partial set, viết 2 statement riêng -->

```typescript
type DeliveryStatus = "processing" | "processed" | "failed";

async function setDeliveryStatus(
  deliveryId: string, status: DeliveryStatus, errorMessage?: string
): Promise<void> {
  if (status === "failed") {
    await db.query(
      `UPDATE webhook_deliveries SET status='failed', error=$2, processed_at=now() WHERE id=$1`,
      [deliveryId, errorMessage ?? "unknown_error"]
    );
  } else if (status === "processed") {
    await db.query(
      `UPDATE webhook_deliveries SET status='processed', processed_at=now() WHERE id=$1`,
      [deliveryId]
    );
  } else {
    await db.query(`UPDATE webhook_deliveries SET status='processing' WHERE id=$1`, [deliveryId]);
  }
}
```

### Pattern 2: Topic handler executor

<!-- PATTERN: webhook-topic-handler-execute -->
<!-- PURPOSE: Look up handler by topic, run with status lifecycle, emit terminal event -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `TOPIC_HANDLERS`: registry shape tuỳ project — map, dependency injection, decorator-based; key luôn là Shopify topic header value (slash form `orders/create`, NOT GraphQL enum `ORDERS_CREATE`)
       - `JSON.parse(rawBody.toString('utf8'))`: edge → `new TextDecoder().decode(rawBody)` + `JSON.parse`
       - Error reporting: logger, Sentry, OpenTelemetry — chọn theo project -->

```typescript
async function executeTopicHandler(
  deliveryId: string, shopId: string, topic: string, rawBody: Buffer, webhookId: string
): Promise<void> {
  const handler = TOPIC_HANDLERS[topic];
  await setDeliveryStatus(deliveryId, "processing");
  try {
    if (!handler) {
      logger.warn({ topic, webhookId }, "no handler registered for topic");
      await setDeliveryStatus(deliveryId, "processed");
      return;
    }
    const payload = JSON.parse(rawBody.toString("utf8"));
    await handler(shopId, payload);
    await setDeliveryStatus(deliveryId, "processed");
    emit("webhook.processed", { deliveryId, shopId, topic, webhookId });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    await setDeliveryStatus(deliveryId, "failed", msg);
    emit("webhook.failed", { deliveryId, shopId, topic, webhookId, error: msg });
    logger.error({ deliveryId, topic, webhookId, err }, "webhook handler failed");
  }
}
```

### Topic handler registry (illustrative)

<!-- PATTERN: webhook-topic-registry -->
<!-- PURPOSE: Map Shopify topic header values to handler functions -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - Topic keys MUST match `X-Shopify-Topic` header values (slash form), NOT GraphQL enum form
       - Handler signature `(shopId, payload) => Promise<void>` is suggestion; project có thể inject thêm context (deliveryId, db, logger)
       - Unknown topics: silently accept + log (response 200 đã gửi) — KHÔNG throw -->

```typescript
const TOPIC_HANDLERS: Record<string, (shopId: string, payload: unknown) => Promise<void>> = {
  "orders/create":           handleOrdersCreate,
  "orders/updated":          handleOrdersUpdated,
  "products/update":         handleProductsUpdate,
  "app/uninstalled":         handleAppUninstalled,
  "bulk_operations/finish":  handleBulkOperationsFinish,
};
```

---

## Webhook Registration

Registration loop chia 3 phần: **GraphQL mutation call** → **subscription upsert** → **per-shop loop**. Mỗi topic register độc lập, failure 1 topic không kill cả batch.

### Pattern 1: Single-topic GraphQL mutation

<!-- PATTERN: shopify-webhook-graphql-create -->
<!-- PURPOSE: Call webhookSubscriptionCreate mutation for one topic; return GID or userErrors -->
<!-- REFERENCE: runtime=node20+ api=shopify-admin-graphql -->
<!-- ADAPT:
       - `shopifyGraphQL(shopDomain, token, { query, variables })`: GraphQL client from auth.shopify-oauth (or any HTTP+JSON wrapper hitting `https://{shop}/admin/api/{version}/graphql.json`)
       - `topic` value: GraphQL enum form UPPER_SNAKE_CASE (`ORDERS_CREATE`), NOT slash header form
       - `format: "JSON"`: default OK; có thể đổi `"XML"` nhưng KHÔNG khuyến nghị — payload parsing phức tạp hơn -->

```typescript
const WEBHOOK_CREATE_MUTATION = `
  mutation webhookSubscriptionCreate(
    $topic: WebhookSubscriptionTopic!,
    $webhookSubscription: WebhookSubscriptionInput!
  ) {
    webhookSubscriptionCreate(topic: $topic, webhookSubscription: $webhookSubscription) {
      webhookSubscription { id topic callbackUrl }
      userErrors { field message }
    }
  }`;

async function createSubscription(
  shopDomain: string, token: string, topic: string, callbackUrl: string
): Promise<{ graphqlId: string | null; userErrors: Array<{ field: string; message: string }> }> {
  const result = await shopifyGraphQL(shopDomain, token, {
    query: WEBHOOK_CREATE_MUTATION,
    variables: { topic, webhookSubscription: { callbackUrl, format: "JSON" } },
  });
  const data = result.data.webhookSubscriptionCreate;
  return { graphqlId: data.webhookSubscription?.id ?? null, userErrors: data.userErrors };
}
```

### Pattern 2: Subscription upsert

<!-- PATTERN: webhook-subscription-upsert -->
<!-- PURPOSE: Insert or update webhook_subscriptions row keyed by (shop_id, topic) -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - `ON CONFLICT (shop_id, topic) DO UPDATE`: postgres + SQLite; MySQL dùng `INSERT ... ON DUPLICATE KEY UPDATE` (yêu cầu UNIQUE index trên `(shop_id, topic)`)
       - `now()` → MySQL `NOW()`, SQLite `CURRENT_TIMESTAMP`
       - `active = true`: reactivate khi register lại topic đã deactivate -->

```typescript
async function upsertSubscription(
  shopId: string, topic: string, callbackUrl: string, graphqlId: string | null
): Promise<void> {
  await db.query(`
    INSERT INTO webhook_subscriptions (shop_id, topic, callback_url, graphql_id)
    VALUES ($1, $2, $3, $4)
    ON CONFLICT (shop_id, topic) DO UPDATE SET
      callback_url = $3,
      graphql_id   = $4,
      active       = true,
      updated_at   = now()
  `, [shopId, topic, callbackUrl, graphqlId]);
}
```

### Pattern 3: Per-shop registration loop

<!-- PATTERN: shopify-register-webhooks -->
<!-- PURPOSE: Register all configured topics for one shop; tolerate per-topic failures -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `getShopToken(shopId)`: shared utility từ auth.shopify-oauth (decrypts access token)
       - Loop strategy: serial (shown) ưu tiên simplicity; parallel với `Promise.allSettled` nếu cần throughput cao và Shopify rate limit cho phép (mỗi shop có throttle riêng)
       - Continue-on-error: log + tiếp tục — KHÔNG throw để register topic khác -->

```typescript
async function registerWebhooks(shopId: string): Promise<void> {
  const shop = await db.query(`SELECT * FROM shops WHERE id = $1`, [shopId]);
  if (!shop) throw new Error("shop_not_found");
  const token = await getShopToken(shopId);
  const callbackUrl = `${config.APP_URL}${config.WEBHOOK_PATH}`;
  for (const topic of config.WEBHOOK_TOPICS) {
    try {
      const { graphqlId, userErrors } = await createSubscription(shop.shop_domain, token, topic, callbackUrl);
      if (userErrors.length > 0) {
        logger.error({ topic, userErrors }, "webhookSubscriptionCreate user errors");
        continue;
      }
      await upsertSubscription(shopId, topic, callbackUrl, graphqlId);
      logger.info({ shopId, topic }, "webhook subscription registered");
    } catch (err) {
      logger.error({ shopId, topic, err }, "failed to register webhook topic");
    }
  }
}
```

---

## Webhook Sync (Reconciliation)

<!-- PATTERN: sync-webhooks -->
<!-- PURPOSE: Reconcile registered subscriptions vs configured WEBHOOK_TOPICS — add missing, deactivate stale -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - Schedule trigger: cron (`node-cron`), platform cron (Vercel/CF Workers), admin endpoint
       - `Set` difference: Standard ECMAScript Set ops; nếu runtime cũ thiếu Set, dùng object map
       - "Deactivate" vs "delete": deactivate giữ audit row; delete xoá hẳn (cần thêm GraphQL `webhookSubscriptionDelete` nếu muốn remove ở Shopify side) -->

```typescript
async function syncWebhooks(shopId: string): Promise<void> {
  const registered = await db.query(
    `SELECT topic FROM webhook_subscriptions WHERE shop_id = $1 AND active = true`,
    [shopId]
  );
  const registeredTopics = new Set(registered.rows.map((r: { topic: string }) => r.topic));
  const configuredTopics = new Set(config.WEBHOOK_TOPICS);
  const missing = config.WEBHOOK_TOPICS.filter(t => !registeredTopics.has(t));
  if (missing.length > 0) await registerWebhooks(shopId); // upsert is idempotent
  for (const r of registered.rows) {
    if (configuredTopics.has(r.topic)) continue;
    await db.query(
      `UPDATE webhook_subscriptions SET active=false, updated_at=now() WHERE shop_id=$1 AND topic=$2`,
      [shopId, r.topic]
    );
    logger.info({ shopId, topic: r.topic }, "webhook subscription deactivated");
  }
}
```

---

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `hmac_verification_failed` | 401 | HMAC header missing or signature mismatch |
| (unknown topic) | 200 | Topic has no registered handler — accepted silently, logged |
| (unknown shop) | 200 | Shop domain not in database — accepted silently, logged |

**Important**: The webhook endpoint never returns 4xx/5xx for processing errors. Only HMAC failures return 401. All other errors are handled internally and the 200 has already been sent.

## Anti-patterns

**DON'T** process the webhook payload before returning 200. Shopify considers any response taking longer than **5 seconds** a failure and will retry up to 19 times over 48 hours. Respond first, process asynchronously.

**DON'T** use a JSON body-parsing middleware before the HMAC check. Parsed JSON loses the exact byte sequence Shopify signed. Read the raw body buffer first, verify HMAC, then parse JSON.

**DON'T** use `==` or `===` to compare HMAC values. Use a **constant-time comparison** (Node `crypto.timingSafeEqual`, Web Crypto manual XOR-accumulator) to prevent timing-based forgery.

**DON'T** rely on the `payload_hash` alone for idempotency. Shopify can retry the same event with the same content but a different `X-Shopify-Webhook-Id`. The `X-Shopify-Webhook-Id` header is the canonical idempotency key.

**DON'T** fail the entire webhook registration if one topic errors. Log and continue — partial registration is better than no registration.

**DON'T** mix the two topic forms. Header `X-Shopify-Topic` uses slash form (`orders/create`); GraphQL enum uses upper-snake (`ORDERS_CREATE`). Convert at the boundary, never store both.
