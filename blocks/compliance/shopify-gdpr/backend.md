# Backend Patterns — Shopify GDPR Mandatory Webhooks

> Snippets dưới đây là **L3 illustrative** (xem `docs/SPEC_GUIDELINES.md` mục 2). Mọi snippet ≤30 dòng với 4 marker — Claude Code adapt theo merchant stack qua `ADAPT` list.

## API Endpoints

### GDPR Webhook Receivers

| Method | Path (example) | Shopify Topic (`X-Shopify-Topic`) | Auth |
|--------|------|---------|------|
| `POST` | `/api/gdpr/customers-data-request` | `customers/data_request` | HMAC-SHA256 verified |
| `POST` | `/api/gdpr/customers-redact` | `customers/redact` | HMAC-SHA256 verified |
| `POST` | `/api/gdpr/shop-redact` | `shop/redact` | HMAC-SHA256 verified |

All 3 endpoints share the same shape: **verify HMAC** → **respond 200 within 5 seconds** → **process async**.

> **External contract** (Shopify-dictated):
> - HMAC: **HMAC-SHA256** over raw body, **base64-encoded**, header `X-Shopify-Hmac-Sha256`
> - 200 response **required within 5 seconds**
> - Erasure must complete within **30 days** of the redact request (Shopify SLA)
> - `shop/redact` is sent **48 hours after uninstall** — not immediately

---

## GDPR Receiver — split into 3 patterns

Compose order: **verify-and-ack → audit-insert → status-transition + processor**. Each pattern testable in isolation.

### Pattern 1: HMAC verify + immediate 200 ack

<!-- PATTERN: gdpr-hmac-verify-and-ack -->
<!-- PURPOSE: Read raw body, verify HMAC-SHA256 base64, send 200 within 5s; hand off raw body for async processing -->
<!-- REFERENCE: runtime=node20+ framework=generic crypto=node-builtin algorithm=hmac-sha256 -->
<!-- ADAPT:
       - Raw body access: framework-specific (Express raw middleware, Hono arrayBuffer, Fastify content-type-parser, Deno bytes) — see webhooks.shopify-webhooks/backend.md Pattern 1 ADAPT list
       - `verifyShopifyHmac`: shared utility from auth.shopify-oauth (HMAC-SHA256, base64, constant-time)
       - Async dispatch: `void promise` simple; production prefer queue (BullMQ/Inngest) to survive process restart
       - Header name `X-Shopify-Hmac-Sha256`: exact spelling dictated by Shopify -->

```typescript
type GdprType = "customers_data_request" | "customers_redact" | "shop_redact";

async function handleGdprWebhook(
  req: Request,
  requestType: GdprType,
  processor: (payload: GdprPayload, shopId: string) => Promise<void>
): Promise<Response> {
  const rawBody = await req.text();
  const hmacHeader = req.headers.get("X-Shopify-Hmac-Sha256") ?? "";
  if (!verifyShopifyHmac(config.SHOPIFY_API_SECRET, rawBody, hmacHeader)) {
    return error(401, "hmac_verification_failed");
  }
  const payload = JSON.parse(rawBody) as GdprPayload;
  // Fire-and-forget: respond first, process async (avoid Shopify 5s timeout)
  processGdprRequest(payload, requestType, processor).catch((err) => {
    logger.error({ err: err.message, requestType, shop: payload.shop_domain }, "gdpr processing failed");
  });
  return new Response(null, { status: 200 });
}
```

### Pattern 2: Audit insert with idempotency

<!-- PATTERN: gdpr-audit-insert -->
<!-- PURPOSE: Look up shop, idempotent-check on shopify_request_id, insert audit row, return request ID -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - `payload.data_request?.id`: Shopify-dictated idempotency key (present on customers/* topics, may be absent on shop/redact)
       - Idempotency check: SELECT-then-INSERT shown for clarity; production prefer UNIQUE constraint + ON CONFLICT to avoid race
       - `orders_requested` (array param): postgres `bigint[]`; MySQL `JSON_ARRAY(...)`; SQLite `JSON_ARRAY(...)`; hoặc dùng join table — see README ADAPT
       - `getShopByDomain`: shared utility from auth.shopify-oauth -->

```typescript
async function auditInsert(
  payload: GdprPayload, requestType: GdprType
): Promise<{ requestId: string; shopId: string } | null> {
  const shop = await getShopByDomain(payload.shop_domain);
  if (!shop) {
    logger.warn({ requestType, shop: payload.shop_domain }, "gdpr: unknown shop");
    return null;
  }
  const shopifyRequestId = payload.data_request?.id ?? null;
  if (shopifyRequestId) {
    const existing = await db.query(
      `SELECT id, status FROM gdpr_requests WHERE shopify_request_id = $1`, [shopifyRequestId]
    );
    if (existing?.status === "completed") return null; // already processed
  }
  const row = await db.query(`
    INSERT INTO gdpr_requests (shop_id, request_type, shopify_request_id,
                               customer_id, customer_email, orders_requested, status)
    VALUES ($1, $2, $3, $4, $5, $6, 'received')
    RETURNING id
  `, [shop.id, requestType, shopifyRequestId,
      payload.customer?.id ?? null, payload.customer?.email ?? null,
      payload.orders_requested ?? null]);
  return { requestId: row.id, shopId: shop.id };
}
```

### Pattern 3: Status transition + processor wrap

<!-- PATTERN: gdpr-process-with-status -->
<!-- PURPOSE: Transition received → processing → completed/failed around processor execution -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - SQL placeholder `$1`: postgres; MySQL/SQLite dùng `?`
       - `now()` → MySQL `NOW()`, SQLite `CURRENT_TIMESTAMP`
       - Throwing after marking failed: preserves stack for upstream logging; remove `throw` if upstream already catches -->

```typescript
async function processGdprRequest(
  payload: GdprPayload, requestType: GdprType,
  processor: (payload: GdprPayload, shopId: string) => Promise<void>
): Promise<void> {
  const audit = await auditInsert(payload, requestType);
  if (!audit) return;
  const { requestId, shopId } = audit;
  try {
    await db.query(`UPDATE gdpr_requests SET status='processing' WHERE id=$1`, [requestId]);
    await processor(payload, shopId);
    await db.query(
      `UPDATE gdpr_requests SET status='completed', completed_at=now() WHERE id=$1`, [requestId]
    );
  } catch (err) {
    await db.query(`UPDATE gdpr_requests SET status='failed' WHERE id=$1`, [requestId]);
    throw err;
  }
}
```

---

## Customer Data Request Handler

<!-- PATTERN: gdpr-customer-data-request -->
<!-- PURPOSE: Collect all PII stored for a customer, notify compliance email, emit event -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - Per-table queries: enumerate EVERY table storing customer PII in your app's data model — this is a compliance gap-magnet; missing 1 table = compliance violation
       - `ANY($2)` for array of order IDs: postgres-specific; MySQL `JSON_CONTAINS` hoặc `IN (...)` với dynamic placeholders; SQLite `IN (SELECT value FROM json_each(?))`
       - `sendEmail`: any transactional email client (Resend, SendGrid, Postmark, SMTP)
       - 30-day SLA: data must be **available** for the merchant — Shopify spec does NOT require returning data in HTTP response -->

```typescript
export async function handleCustomersDataRequest(req: Request): Promise<Response> {
  return handleGdprWebhook(req, "customers_data_request", async (payload, shopId) => {
    const { id: customerId, email: customerEmail } = payload.customer!;
    const customerData: Record<string, unknown[]> = {};
    // Enumerate ALL PII tables — example: reviews, order_annotations, profiles, etc.
    const reviews = await db.query(
      `SELECT id, product_id, rating, body, created_at FROM reviews
       WHERE shop_id = $1 AND (shopify_customer_id = $2 OR author_email = $3)`,
      [shopId, customerId, customerEmail]
    );
    if (reviews.length > 0) customerData.reviews = reviews;
    // ... repeat for every table storing customer PII ...
    if (config.GDPR_NOTIFY_EMAIL) {
      await sendEmail({
        to: config.GDPR_NOTIFY_EMAIL,
        subject: `GDPR Data Request — Customer ${customerEmail}`,
        body: `Data found: ${JSON.stringify(customerData, null, 2)}`,
      });
    }
    emit("gdpr.data_requested", { shopId, shopDomain: payload.shop_domain,
      customerId, customerEmail, tablesQueried: Object.keys(customerData) });
  });
}
```

---

## Customer Redact Handler

<!-- PATTERN: gdpr-customer-redact -->
<!-- PURPOSE: Delete or anonymize all PII for a customer across every app table within 30-day SLA -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - Anonymize-vs-delete strategy: anonymize where records have aggregate value (reviews → keep rating, drop name/email); delete where record has no value without the customer (profile, annotations)
       - `ANY($2)` for order IDs: see Pattern 3 ADAPT in Data Request handler for non-postgres mapping
       - Enumerate EVERY PII table — missed table = compliance violation; maintain a "PII registry" doc as defense
       - 30-day SLA: erasure must complete within 30 days per Shopify rule; immediate erasure (default `GDPR_DATA_RETENTION_DAYS=0`) is safest -->

```typescript
export async function handleCustomersRedact(req: Request): Promise<Response> {
  return handleGdprWebhook(req, "customers_redact", async (payload, shopId) => {
    const { id: customerId, email: customerEmail } = payload.customer!;
    // Anonymize reviews (preserve rating + body for aggregate integrity)
    await db.query(`
      UPDATE reviews
      SET author_name = 'Deleted User', author_email = NULL, author_phone = NULL
      WHERE shop_id = $1 AND (shopify_customer_id = $2 OR author_email = $3)
    `, [shopId, customerId, customerEmail]);
    // Delete order annotations (no value without customer context)
    await db.query(
      `DELETE FROM order_annotations WHERE shop_id = $1 AND shopify_order_id = ANY($2)`,
      [shopId, payload.orders_to_redact ?? []]
    );
    // Delete customer profile (full PII record)
    await db.query(
      `DELETE FROM customer_profiles WHERE shop_id = $1 AND shopify_customer_id = $2`,
      [shopId, customerId]
    );
    emit("gdpr.customer_redacted", { shopId, shopDomain: payload.shop_domain, customerId, customerEmail });
  });
}
```

---

## Shop Redact Handler

<!-- PATTERN: gdpr-shop-redact -->
<!-- PURPOSE: Purge ALL data for a shop within 30-day SLA; preserve gdpr_requests audit row via ON DELETE SET NULL -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - `DELETE FROM shops`: CASCADE FK chain must reach EVERY table referencing shop_id; if any table lacks CASCADE FK, add explicit DELETE before this line
       - `gdpr_requests.shop_id` MUST be `ON DELETE SET NULL`, not CASCADE — else this delete wipes the audit trail of its own request (xem security.md mục 5)
       - Alternative: copy gdpr_requests row to append-only compliance store BEFORE shop delete; then CASCADE is OK
       - `shop/redact` is sent 48 hours after uninstall; the app may still receive other webhooks during that window — don't assume shop is gone before this fires -->

```typescript
export async function handleShopRedact(req: Request): Promise<Response> {
  return handleGdprWebhook(req, "shop_redact", async (payload, shopId) => {
    // Option A — Cascade via FK (preferred when all FK have ON DELETE CASCADE
    //   AND gdpr_requests.shop_id is ON DELETE SET NULL)
    await db.query(`DELETE FROM shops WHERE id = $1`, [shopId]);
    // CASCADE removes: reviews, orders, webhook_subscriptions, ...
    // gdpr_requests row survives (shop_id becomes NULL — audit preserved)

    // Option B — Explicit per-table delete (use if some tables lack CASCADE FK)
    // await db.query(`DELETE FROM reviews WHERE shop_id = $1`, [shopId]);
    // await db.query(`DELETE FROM webhook_subscriptions WHERE shop_id = $1`, [shopId]);
    // await db.query(`DELETE FROM shops WHERE id = $1`, [shopId]);

    emit("gdpr.shop_redacted", { shopId, shopDomain: payload.shop_domain });
  });
}
```

---

## Payload Type Definitions

<!-- PATTERN: gdpr-payload-types -->
<!-- PURPOSE: Type the Shopify-dictated GDPR webhook payload shapes -->
<!-- REFERENCE: language=typescript api=shopify-privacy-webhooks -->
<!-- ADAPT:
       - Field names + types: Shopify-dictated, KHÔNG đổi
       - `customer.id` typed `number` here for JSON parse fidelity (Shopify sends integer in payload); store as `external_id`/text in DB to avoid 64-bit overflow risk in JS
       - `phone`: present on customer payload; nullable per Shopify spec
       - `orders_requested` (data_request) vs `orders_to_redact` (redact): different field names per topic — do not conflate -->

```typescript
interface GdprPayload {
  shop_id:     number;
  shop_domain: string;
  customer?: {
    id:    number;
    email: string;
    phone: string | null;
  };
  orders_requested?: number[];  // customers/data_request
  orders_to_redact?: number[];  // customers/redact
  data_request?: { id: string };  // idempotency key (customers/* topics)
}
```

---

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `hmac_verification_failed` | 401 | HMAC signature missing or mismatch |
| Processing errors | — | Logged internally; never returned (200 already sent) |
| Unknown shop | — | Logged as warning; processing skipped gracefully |
| Duplicate request (same `shopify_request_id`) | — | Skipped silently if previous request `completed` |

## Anti-patterns

**DON'T** process before responding 200. Shopify sends GDPR webhooks with the same **5-second** timeout as other webhooks. Respond immediately, process async.

**DON'T** forget any table that stores customer data. Incomplete erasure is a compliance violation. Enumerate ALL tables with customer PII and verify each is handled in the redact handler. Maintain a "PII registry" document updated whenever the schema changes.

**DON'T** delete the `gdpr_requests` record when purging shop data. The audit trail must survive the shop purge — use **`ON DELETE SET NULL`** for `gdpr_requests.shop_id` FK, or log the completed GDPR request to an append-only compliance store before executing the purge.

**DON'T** skip the HMAC check because "it comes from Shopify". Any public endpoint without HMAC verification can be called by anyone. Verify every time.

**DON'T** silently swallow errors in the async processor. Log all failures — failed GDPR erasure creates compliance liability.

**DON'T** miss the 30-day SLA. Default `GDPR_DATA_RETENTION_DAYS=0` (immediate erasure) is the safest path; any delay must complete strictly within 30 days.
