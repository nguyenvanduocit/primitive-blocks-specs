# Backend Patterns — Shopify Webhook Management

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

## Webhook Receiver Handler

<!-- PATTERN: shopify-webhook-receiver -->
<!-- PURPOSE: Verify HMAC, respond 200 immediately, check idempotency, dispatch async -->
<!-- ADAPT: Raw body access mechanism, async dispatch method, DB client -->
<!-- CRITICAL: Must read raw body BEFORE any body-parsing middleware runs -->

```typescript
// POST /api/webhooks
// Headers: X-Shopify-Hmac-Sha256, X-Shopify-Topic, X-Shopify-Webhook-Id, X-Shopify-Shop-Domain, X-Shopify-Api-Version

async function handleWebhookReceive(req: RawRequest): Promise<Response> {
  // 1. Read raw body bytes FIRST — body-parsing middleware would corrupt HMAC input
  const rawBody = await readRawBody(req); // Buffer, not parsed JSON

  // 2. Verify HMAC — reuse shared utility from auth.shopify-oauth
  const hmacHeader = req.headers["x-shopify-hmac-sha256"];
  if (!hmacHeader || !verifyShopifyHmac(config.SHOPIFY_API_SECRET, rawBody, hmacHeader)) {
    return error(401, "hmac_verification_failed");
  }

  // 3. Extract headers
  const topic = req.headers["x-shopify-topic"] as string;         // e.g. "orders/create"
  const shopDomain = req.headers["x-shopify-shop-domain"] as string;
  const webhookId = req.headers["x-shopify-webhook-id"] as string;

  // 4. Respond 200 BEFORE processing — Shopify times out at 5s and will retry
  //    Fire-and-forget the rest; the HTTP response is already sent.
  const response = new Response(null, { status: 200 });
  void processWebhookAsync(rawBody, topic, shopDomain, webhookId);
  return response;
}

async function processWebhookAsync(
  rawBody: Buffer,
  topic: string,
  shopDomain: string,
  webhookId: string
): Promise<void> {
  // 1. Look up shop
  const shop = await getShopByDomain(shopDomain);
  if (!shop) {
    // Unknown shop — log and exit (possible race with uninstall)
    logger.warn({ shopDomain, topic }, "webhook received for unknown shop");
    return;
  }

  // 2. Compute payload hash for dedup fingerprint
  const payloadHash = crypto.createHash("sha256").update(rawBody).digest("hex");

  // 3. Idempotency check — INSERT with unique constraint on webhook_id
  //    ON CONFLICT DO NOTHING ensures exactly-once: if the row already exists,
  //    Shopify retried and we skip reprocessing.
  const result = await db.query(`
    INSERT INTO webhook_deliveries
      (shop_id, topic, webhook_id, payload_hash, status)
    VALUES ($1, $2, $3, $4, 'received')
    ON CONFLICT (webhook_id) DO NOTHING
    RETURNING id
  `, [shop.id, topic, webhookId, payloadHash]);

  if (result.rowCount === 0) {
    // Duplicate delivery — already processed (or in progress)
    logger.info({ webhookId, topic }, "duplicate webhook delivery — skipping");
    return;
  }

  const deliveryId = result.rows[0].id;
  emit("webhook.received", { deliveryId, shopId: shop.id, topic, webhookId });

  // 4. Dispatch to topic handler
  if (config.WEBHOOK_PROCESS_ASYNC) {
    await dispatchToQueue({ deliveryId, shopId: shop.id, topic, rawBody, webhookId });
  } else {
    await executeTopicHandler(deliveryId, shop.id, topic, rawBody, webhookId);
  }
}
```

## Topic Handler Execution

<!-- PATTERN: webhook-topic-handler -->
<!-- PURPOSE: Execute the correct handler per topic, update delivery status -->
<!-- ADAPT: Handler registry, error reporting -->

```typescript
// Map of Shopify topic strings → handler functions
// Topic format from headers uses slash notation: "orders/create", "app/uninstalled"
const TOPIC_HANDLERS: Record<string, (shopId: string, payload: unknown) => Promise<void>> = {
  "orders/create":        handleOrdersCreate,
  "orders/updated":       handleOrdersUpdated,
  "products/update":      handleProductsUpdate,
  "app/uninstalled":      handleAppUninstalled,
  "bulk_operations/finish": handleBulkOperationsFinish,
};

async function executeTopicHandler(
  deliveryId: string,
  shopId: string,
  topic: string,
  rawBody: Buffer,
  webhookId: string
): Promise<void> {
  const handler = TOPIC_HANDLERS[topic];

  // Update status to processing
  await db.query(
    `UPDATE webhook_deliveries SET status = 'processing' WHERE id = $1`,
    [deliveryId]
  );

  try {
    if (!handler) {
      // Unknown topic — accept silently (200 already sent), log for awareness
      logger.warn({ topic, webhookId }, "no handler registered for topic");
      await db.query(
        `UPDATE webhook_deliveries SET status = 'processed', processed_at = now() WHERE id = $1`,
        [deliveryId]
      );
      return;
    }

    const payload = JSON.parse(rawBody.toString("utf8"));
    await handler(shopId, payload);

    await db.query(
      `UPDATE webhook_deliveries SET status = 'processed', processed_at = now() WHERE id = $1`,
      [deliveryId]
    );
    emit("webhook.processed", { deliveryId, shopId, topic, webhookId });

  } catch (err) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    await db.query(
      `UPDATE webhook_deliveries SET status = 'failed', error = $2, processed_at = now() WHERE id = $1`,
      [deliveryId, errorMessage]
    );
    emit("webhook.failed", { deliveryId, shopId, topic, webhookId, error: errorMessage });
    logger.error({ deliveryId, topic, webhookId, err }, "webhook handler failed");
  }
}
```

## Webhook Registration

<!-- PATTERN: register-webhooks -->
<!-- PURPOSE: Register all configured topics via GraphQL after shop installs -->
<!-- ADAPT: GraphQL client, config structure -->

```typescript
// Called after shop.installed event fires from auth.shopify-oauth
async function registerWebhooks(shopId: string): Promise<void> {
  const shop = await db.query(`SELECT * FROM shops WHERE id = $1`, [shopId]);
  if (!shop) throw new Error("shop_not_found");

  const token = await getShopToken(shopId);
  const callbackUrl = `${config.APP_URL}${config.WEBHOOK_PATH}`;

  for (const topic of config.WEBHOOK_TOPICS) {
    try {
      const result = await shopifyGraphQL(shop.shop_domain, token, {
        query: `
          mutation webhookSubscriptionCreate($topic: WebhookSubscriptionTopic!, $webhookSubscription: WebhookSubscriptionInput!) {
            webhookSubscriptionCreate(topic: $topic, webhookSubscription: $webhookSubscription) {
              webhookSubscription {
                id
                topic
                callbackUrl
              }
              userErrors {
                field
                message
              }
            }
          }
        `,
        variables: {
          topic,
          webhookSubscription: { callbackUrl, format: "JSON" },
        },
      });

      const { webhookSubscription, userErrors } = result.data.webhookSubscriptionCreate;

      if (userErrors.length > 0) {
        logger.error({ topic, userErrors }, "webhookSubscriptionCreate user errors");
        continue;
      }

      // Upsert subscription record
      await db.query(`
        INSERT INTO webhook_subscriptions (shop_id, topic, callback_url, graphql_id)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (shop_id, topic) DO UPDATE SET
          callback_url = $3,
          graphql_id   = $4,
          active       = true,
          updated_at   = now()
      `, [shopId, topic, callbackUrl, webhookSubscription.id]);

      logger.info({ shopId, topic }, "webhook subscription registered");

    } catch (err) {
      // Log and continue — don't fail the entire registration on one topic
      logger.error({ shopId, topic, err }, "failed to register webhook topic");
    }
  }
}
```

## Webhook Sync (Reconciliation)

<!-- PATTERN: sync-webhooks -->
<!-- PURPOSE: Keep registered subscriptions in sync with configured WEBHOOK_TOPICS -->
<!-- ADAPT: Schedule trigger (cron, admin endpoint) -->

```typescript
// Compare registered vs configured topics; add missing, deactivate stale
async function syncWebhooks(shopId: string): Promise<void> {
  const shop = await db.query(`SELECT * FROM shops WHERE id = $1`, [shopId]);
  const registered = await db.query(
    `SELECT topic, graphql_id FROM webhook_subscriptions WHERE shop_id = $1 AND active = true`,
    [shopId]
  );

  const registeredTopics = new Set(registered.rows.map((r: { topic: string }) => r.topic));
  const configuredTopics = new Set(config.WEBHOOK_TOPICS);

  // Topics in config but not registered → register them
  const toAdd = config.WEBHOOK_TOPICS.filter(t => !registeredTopics.has(t));
  if (toAdd.length > 0) {
    const partialConfig = { ...config, WEBHOOK_TOPICS: toAdd };
    await registerWebhooks(shopId); // registerWebhooks already handles upsert
  }

  // Topics registered but not in config → deactivate
  const toRemove = registered.rows.filter((r: { topic: string }) => !configuredTopics.has(r.topic));
  for (const sub of toRemove) {
    await db.query(
      `UPDATE webhook_subscriptions SET active = false, updated_at = now() WHERE shop_id = $1 AND topic = $2`,
      [shopId, sub.topic]
    );
    logger.info({ shopId, topic: sub.topic }, "webhook subscription deactivated (removed from config)");
  }
}
```

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `hmac_verification_failed` | 401 | HMAC header missing or signature mismatch |
| (unknown topic) | 200 | Topic has no registered handler — accepted silently, logged |
| (unknown shop) | 200 | Shop domain not in database — accepted silently, logged |

**Important**: The webhook endpoint never returns 4xx/5xx for processing errors. Only HMAC failures return 401. All other errors are handled internally and the 200 has already been sent.

## Anti-patterns

**DON'T** process the webhook payload before returning 200. Shopify considers any response taking longer than 5 seconds a failure and will retry. Respond first, process asynchronously.

**DON'T** use a body-parsing middleware (e.g., `express.json()`) before the HMAC check. Parsed JSON loses the exact byte sequence that Shopify signed. Read the raw body buffer first, verify HMAC, then parse JSON.

**DON'T** use `==` or `===` to compare HMAC values. Use `crypto.timingSafeEqual` to prevent timing attacks that could allow HMAC forgery.

**DON'T** rely on the `payload_hash` alone for idempotency. Shopify can retry the same event with the same content but a different `X-Shopify-Webhook-Id`. The `webhook_id` header is the canonical idempotency key.

**DON'T** fail the entire webhook registration if one topic errors. Log and continue — partial registration is better than no registration.
