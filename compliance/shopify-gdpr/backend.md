# Backend Patterns — Shopify GDPR Mandatory Webhooks

## API Endpoints

### GDPR Webhook Receivers

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `POST` | `/api/gdpr/customers-data-request` | Receive customer data access request | HMAC verified |
| `POST` | `/api/gdpr/customers-redact` | Receive customer PII erasure order | HMAC verified |
| `POST` | `/api/gdpr/shop-redact` | Receive full shop data purge order | HMAC verified |

All 3 endpoints share the same structure: verify HMAC → respond 200 → process async.

---

## Shared GDPR Request Handler Wrapper

<!-- PATTERN: gdpr-handler-wrapper -->
<!-- PURPOSE: Verify HMAC, respond 200 immediately, log request, dispatch to specific handler -->
<!-- ADAPT: Raw body extraction depends on framework -->

```typescript
// Shared wrapper used by all 3 GDPR endpoints
async function handleGdprWebhook(
  req: Request,
  requestType: "customers_data_request" | "customers_redact" | "shop_redact",
  processor: (payload: GdprPayload, shopId: string) => Promise<void>
): Promise<Response> {
  // 1. Read raw body for HMAC verification (must read before any parsing)
  const rawBody = await req.text();
  const hmacHeader = req.headers.get("X-Shopify-Hmac-Sha256") ?? "";

  // 2. Verify HMAC — reuse shared utility from auth.shopify-oauth
  if (!verifyShopifyHmac(config.SHOPIFY_API_SECRET, rawBody, hmacHeader)) {
    return error(401, "hmac_verification_failed");
  }

  // 3. Respond 200 immediately — Shopify retries if response takes > 5s
  // Processing happens after this point asynchronously
  const response = new Response(null, { status: 200 });

  // 4. Parse payload
  const payload = JSON.parse(rawBody) as GdprPayload;

  // 5. Process async (do not await — response already sent)
  processGdprRequest(payload, requestType, processor).catch((err) => {
    console.error(`GDPR ${requestType} processing failed`, { error: err.message, payload });
  });

  return response;
}

async function processGdprRequest(
  payload: GdprPayload,
  requestType: string,
  processor: (payload: GdprPayload, shopId: string) => Promise<void>
): Promise<void> {
  // 6. Lookup shop
  const shop = await getShopByDomain(payload.shop_domain);
  if (!shop) {
    console.warn(`GDPR ${requestType}: unknown shop ${payload.shop_domain}`);
    return; // Already responded 200 — log and exit gracefully
  }

  // 7. Log request (audit trail)
  const gdprRecord = await db.query(`
    INSERT INTO gdpr_requests (
      shop_id, request_type, shopify_request_id,
      customer_id, customer_email, orders_requested, status
    ) VALUES ($1, $2, $3, $4, $5, $6, 'received')
    RETURNING id
  `, [
    shop.id,
    requestType,
    payload.data_request?.id ?? null,
    payload.customer?.id ?? null,
    payload.customer?.email ?? null,
    payload.orders_requested ?? null,
  ]);

  const requestId = gdprRecord.id;

  try {
    await db.query(
      `UPDATE gdpr_requests SET status = 'processing' WHERE id = $1`,
      [requestId]
    );

    await processor(payload, shop.id);

    await db.query(
      `UPDATE gdpr_requests SET status = 'completed', completed_at = now() WHERE id = $1`,
      [requestId]
    );
  } catch (err) {
    await db.query(
      `UPDATE gdpr_requests SET status = 'failed' WHERE id = $1`,
      [requestId]
    );
    throw err;
  }
}
```

---

## Customer Data Request Handler

<!-- PATTERN: gdpr-customer-data-request -->
<!-- PURPOSE: Collect all PII stored for a customer and report it -->
<!-- ADAPT: Add queries for each app table that stores customer data -->

```typescript
// POST /api/gdpr/customers-data-request
export async function handleCustomersDataRequest(req: Request): Promise<Response> {
  return handleGdprWebhook(req, "customers_data_request", async (payload, shopId) => {
    const customerId = payload.customer.id;
    const customerEmail = payload.customer.email;

    // Query ALL app tables that store customer data
    // Adapt this list to match your app's actual data model
    const customerData: Record<string, unknown[]> = {};

    // Example: product reviews
    const reviews = await db.query(`
      SELECT id, product_id, rating, body, created_at
      FROM reviews
      WHERE shop_id = $1 AND (shopify_customer_id = $2 OR author_email = $3)
    `, [shopId, customerId, customerEmail]);
    if (reviews.length > 0) customerData.reviews = reviews;

    // Example: order-specific app data (not the Shopify orders themselves — Shopify owns those)
    const orderAnnotations = await db.query(`
      SELECT id, shopify_order_id, note, created_at
      FROM order_annotations
      WHERE shop_id = $1 AND shopify_order_id = ANY($2)
    `, [shopId, payload.orders_requested ?? []]);
    if (orderAnnotations.length > 0) customerData.order_annotations = orderAnnotations;

    // Notify via email if configured
    if (config.GDPR_NOTIFY_EMAIL) {
      await sendEmail({
        to: config.GDPR_NOTIFY_EMAIL,
        subject: `GDPR Data Request — Customer ${customerEmail}`,
        body: `Customer data request received for ${customerEmail}. Data found: ${JSON.stringify(customerData, null, 2)}`,
      });
    }

    emit("gdpr.data_requested", {
      shopId,
      shopDomain: payload.shop_domain,
      customerId,
      customerEmail,
      tablesQueried: Object.keys(customerData),
      recordCount: Object.values(customerData).flat().length,
    });
  });
}
```

---

## Customer Redact Handler

<!-- PATTERN: gdpr-customer-redact -->
<!-- PURPOSE: Delete or anonymize all PII for a customer across all app tables -->
<!-- ADAPT: Add DELETE/UPDATE for each table that stores customer PII -->

```typescript
// POST /api/gdpr/customers-redact
export async function handleCustomersRedact(req: Request): Promise<Response> {
  return handleGdprWebhook(req, "customers_redact", async (payload, shopId) => {
    const customerId = payload.customer.id;
    const customerEmail = payload.customer.email;

    // Erase / anonymize ALL PII across every table that stores customer data
    // Strategy: anonymize where records must be retained for app integrity, delete otherwise

    // Example: anonymize reviews (preserve for statistical integrity, remove PII)
    await db.query(`
      UPDATE reviews
      SET
        author_name  = 'Deleted User',
        author_email = null,
        author_phone = null
      WHERE shop_id = $1
        AND (shopify_customer_id = $2 OR author_email = $3)
    `, [shopId, customerId, customerEmail]);

    // Example: delete order-specific app data outright
    await db.query(`
      DELETE FROM order_annotations
      WHERE shop_id = $1 AND shopify_order_id = ANY($2)
    `, [shopId, payload.orders_to_redact ?? []]);

    // Example: delete customer profile if app stores one
    await db.query(`
      DELETE FROM customer_profiles
      WHERE shop_id = $1 AND shopify_customer_id = $2
    `, [shopId, customerId]);

    emit("gdpr.customer_redacted", {
      shopId,
      shopDomain: payload.shop_domain,
      customerId,
      customerEmail,
    });
  });
}
```

---

## Shop Redact Handler

<!-- PATTERN: gdpr-shop-redact -->
<!-- PURPOSE: Purge ALL data for a shop — sent 48h after uninstall -->
<!-- ADAPT: Verify cascade deletes cover all tables; add explicit deletes for any that don't FK to shops -->

```typescript
// POST /api/gdpr/shop-redact
export async function handleShopRedact(req: Request): Promise<Response> {
  return handleGdprWebhook(req, "shop_redact", async (payload, shopId) => {
    // Log the GDPR request BEFORE deleting the shop
    // (the INSERT in processGdprRequest runs before this handler is called)

    // Option A — Cascade delete via FK (preferred if all tables have shop_id FK with ON DELETE CASCADE)
    await db.query(`DELETE FROM shops WHERE id = $1`, [shopId]);
    // CASCADE will automatically delete: reviews, orders, subscriptions, webhook_subscriptions, etc.

    // Option B — Explicit per-table delete (use if some tables lack CASCADE FK)
    // await db.query(`DELETE FROM reviews WHERE shop_id = $1`, [shopId]);
    // await db.query(`DELETE FROM webhook_subscriptions WHERE shop_id = $1`, [shopId]);
    // await db.query(`DELETE FROM shops WHERE id = $1`, [shopId]);

    emit("gdpr.shop_redacted", {
      shopId,
      shopDomain: payload.shop_domain,
    });
  });
}
```

---

## Type Definitions

```typescript
interface GdprPayload {
  shop_id:    number;
  shop_domain: string;
  customer?: {
    id:    number;
    email: string;
    phone: string | null;
  };
  orders_requested?: number[];  // customers/data_request
  orders_to_redact?: number[];  // customers/redact
  data_request?: {
    id: string;  // Shopify-assigned request ID for idempotency
  };
}
```

---

## Idempotency

Duplicate GDPR requests (Shopify retries on non-200) are handled by checking `shopify_request_id`:

```typescript
// Before inserting, check for existing record with same request ID
const existing = await db.query(`
  SELECT id, status FROM gdpr_requests
  WHERE shopify_request_id = $1
`, [payload.data_request?.id]);

if (existing && existing.status === 'completed') {
  return; // Already processed — idempotent
}
```

---

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `hmac_verification_failed` | 401 | HMAC signature doesn't match |
| Processing errors | — | Logged internally, never returned (already responded 200) |
| Unknown shop | — | Logged as warning, processing skipped gracefully |

## Anti-patterns

**DON'T** process before responding 200. Shopify sends GDPR webhooks with the same 5-second timeout as other webhooks. Respond immediately, process async.

**DON'T** forget any table that stores customer data. Incomplete erasure is a compliance violation. Enumerate ALL tables with customer PII and verify each is handled in the redact handler.

**DON'T** delete the `gdpr_requests` record when purging shop data. The audit trail must survive the shop purge. Either use `ON DELETE SET NULL` for `shop_id` FK or log to a separate compliance store before deleting.

**DON'T** skip the HMAC check because "it comes from Shopify". Any public endpoint without HMAC verification can be called by anyone. Verify every time.

**DON'T** silently swallow errors in the async processor. Log all failures — failed GDPR erasure creates compliance liability.
