# Backend Patterns — Product Reviews

> Snippets dưới đây là **L3 illustrative** (xem `docs/SPEC_GUIDELINES.md` mục 2). Mọi snippet ≤30 dòng với 4 marker — Claude Code adapt theo merchant stack qua `ADAPT` list.

## API Endpoints

### Storefront (public, authenticated shopper)

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `POST` | `/api/reviews` | Submit a review | Shopper session |
| `GET` | `/api/reviews` | Paginated approved reviews | Public |
| `GET` | `/api/reviews/aggregate/:product_id` | Aggregate for a product | Public |

### Admin (merchant staff)

| Method | Path | Purpose | Auth |
|--------|------|---------|------|
| `GET` | `/api/admin/reviews` | Moderation queue (filterable) | Admin |
| `PATCH` | `/api/admin/reviews/:id` | Approve or reject a review | Admin |
| `PATCH` | `/api/admin/reviews/bulk` | Bulk approve/reject | Admin |

---

## Submit Flow — split into 3 patterns

Compose order: **validate → decide-verified-and-approve → insert-with-dedup**. Each pattern testable independently.

### Pattern 1: Input validation + sanitization

<!-- PATTERN: review-input-validate -->
<!-- PURPOSE: Validate rating range, body length; HTML-strip user input to prevent XSS at write time -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `stripHtml`: any whitelist-based HTML stripper (`sanitize-html` with empty allowedTags, `DOMPurify` in JSDOM, `striptags`); the discipline is "treat input as plain text, store sanitized" — NOT escape-at-render-only
       - Validation library: zod, valibot, yup, or hand-rolled — error shape must distinguish field-level errors for the form
       - Char count semantic: `.length` is UTF-16 code units in JS; for true grapheme count use `Intl.Segmenter` — usually overkill for review length checks
       - Title length cap 200: domain rule; expose as config if needed -->

```typescript
type ReviewInput = { product_id: string; rating: number; title?: string; body: string };
type ValidReview = { product_id: string; rating: number; title: string | null; body: string };

function validateReviewInput(input: ReviewInput): ValidReview {
  if (!Number.isInteger(input.rating) || input.rating < 1 || input.rating > 5) {
    throw new HttpError(422, "invalid_rating");
  }
  const body = stripHtml(input.body);
  if (body.length < config.MIN_BODY_LENGTH) throw new HttpError(422, "body_too_short");
  if (body.length > config.MAX_BODY_LENGTH) throw new HttpError(422, "body_too_long");
  const title = input.title ? stripHtml(input.title).slice(0, 200) : null;
  return { product_id: input.product_id, rating: input.rating, title, body };
}
```

### Pattern 2: Verified-buyer + auto-approve decision

<!-- PATTERN: review-verified-and-approve-decision -->
<!-- PURPOSE: Look up verified-buyer status, apply REQUIRE_VERIFIED_BUYER gate, decide approval status -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `checkVerifiedBuyer`: see verified-buyer-lookup pattern below — depends on how orders data is modeled in the merchant project
       - `REQUIRE_VERIFIED_BUYER` is a domain gate; if absent, treat as `false`
       - `AUTO_APPROVE_THRESHOLD = 0` disables auto-approve entirely (all reviews go to moderation) -->

```typescript
async function decideReviewStatus(
  shopId: string, customerId: string, productId: string, rating: number
): Promise<{ status: "approved" | "pending"; verifiedBuyer: boolean }> {
  const verifiedBuyer = await checkVerifiedBuyer(shopId, customerId, productId);
  if (config.REQUIRE_VERIFIED_BUYER && !verifiedBuyer) {
    throw new HttpError(403, "verified_buyer_required");
  }
  const autoApprove = config.AUTO_APPROVE_THRESHOLD > 0
                   && rating >= config.AUTO_APPROVE_THRESHOLD;
  return { status: autoApprove ? "approved" : "pending", verifiedBuyer };
}
```

### Pattern 3: Insert with UNIQUE-driven dedup

<!-- PATTERN: review-insert-with-dedup -->
<!-- PURPOSE: Insert review; rely on UNIQUE(shop_id, product_id, customer_id) to detect duplicates; recalculate aggregate if approved -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - `db.insert("reviews", {...})`: ORM-specific — Drizzle `db.insert(reviews).values(...)`; Prisma `prisma.review.create(...)`; raw SQL `INSERT INTO reviews (...) VALUES (...) RETURNING *`
       - `isUniqueViolation(err)`: error code matching — Postgres `23505`, MySQL `ER_DUP_ENTRY (1062)`, SQLite `SQLITE_CONSTRAINT_UNIQUE`
       - `recalculateAggregate(shopId, productId)`: see Aggregate Recalculation pattern below — should run in same transaction as the insert for atomicity -->

```typescript
async function insertReviewWithDedup(
  shopId: string, customer: { id: string; name: string; email: string },
  v: ValidReview, decision: { status: "approved" | "pending"; verifiedBuyer: boolean }
): Promise<Review> {
  try {
    const review = await db.insert("reviews", {
      shop_id: shopId, product_id: v.product_id,
      customer_id: customer.id, customer_name: customer.name, customer_email: customer.email,
      rating: v.rating, title: v.title, body: v.body,
      status: decision.status, verified_buyer: decision.verifiedBuyer,
      moderated_at: decision.status === "approved" ? new Date() : null,
      moderated_by:  decision.status === "approved" ? "system" : null,
    });
    if (decision.status === "approved") await recalculateAggregate(shopId, v.product_id);
    return review;
  } catch (err) {
    if (isUniqueViolation(err)) throw new HttpError(409, "already_reviewed");
    throw err;
  }
}
```

### Composition (the route handler)

<!-- PATTERN: review-submit-compose -->
<!-- PURPOSE: Compose validate + decide + insert + emit into the actual POST /api/reviews route -->
<!-- REFERENCE: runtime=node20+ framework=generic -->
<!-- ADAPT:
       - `extractAuth(req)`: framework-specific session/JWT extraction; MUST return `shopId` + `customerId` from server-trusted source — NEVER from request body
       - `parseBody(req)` + `json/error` response helpers: framework-specific (Express `res.json`, Hono `c.json`, Fastify `reply.send`) -->

```typescript
async function handleSubmitReview(req: Request): Promise<Response> {
  const { shopId, customerId, customerName, customerEmail } = extractAuth(req);
  const valid = validateReviewInput(parseBody(req));
  const decision = await decideReviewStatus(shopId, customerId, valid.product_id, valid.rating);
  const review = await insertReviewWithDedup(
    shopId, { id: customerId, name: customerName, email: customerEmail }, valid, decision
  );
  emit("review.submitted", {
    reviewId: review.id, shopId, productId: valid.product_id,
    customerId, rating: valid.rating, status: decision.status,
  });
  return json(201, { review });
}
```

---

## Verified Buyer Check

<!-- PATTERN: verified-buyer-lookup -->
<!-- PURPOSE: Confirm customer purchased the product within this shop (paid order containing product) -->
<!-- REFERENCE: runtime=node20+ dialect=postgres orm=raw-sql -->
<!-- ADAPT:
       - Orders schema is project-specific — this query assumes `orders(shop_id, customer_id, financial_status)` + `order_line_items(order_id, product_id)`; if the merchant uses different table names or stores line items as JSON, rewrite accordingly
       - `financial_status = 'paid'`: align with Shopify's order financial_status enum if syncing from Shopify
       - `LIMIT 1`: existence check — short-circuit as soon as one match found
       - For NoSQL: replace with single-document lookup or aggregation pipeline -->

```typescript
async function checkVerifiedBuyer(
  shopId: string, customerId: string, productId: string
): Promise<boolean> {
  const result = await db.query(`
    SELECT 1 FROM orders o
    JOIN order_line_items li ON li.order_id = o.id
    WHERE o.shop_id = $1
      AND o.customer_id = $2
      AND li.product_id = $3
      AND o.financial_status = 'paid'
    LIMIT 1
  `, [shopId, customerId, productId]);
  return result.rows.length > 0;
}
```

---

## Moderate Handler

<!-- PATTERN: moderate-review-handler -->
<!-- PURPOSE: Transactionally update review status + recalculate aggregate; scope every query by shop_id -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - `db.transaction(async (tx) => {...})`: transaction shape — Drizzle/Prisma/Kysely each differ; key invariant is "status update + aggregate recalc are atomic"
       - `extractAdminAuth(req)`: must return server-trusted `shopId` + `adminId`
       - `AND shop_id = $shop_id` on every query — defense-in-depth against cross-tenant moderation via crafted review IDs
       - `status` enum values exact: `approved`, `rejected` — match DB CHECK constraint -->

```typescript
async function handleModerateReview(req: Request): Promise<Response> {
  const { shopId, adminId } = extractAdminAuth(req);
  const reviewId = req.params.id;
  const { status } = parseBody(req);
  if (!["approved", "rejected"].includes(status)) return error(422, "invalid_status");
  return db.transaction(async (tx) => {
    const review = await tx.query(
      `SELECT * FROM reviews WHERE id = $1 AND shop_id = $2`, [reviewId, shopId]
    );
    if (!review) return error(404, "review_not_found");
    const previousStatus = review.status;
    await tx.query(`
      UPDATE reviews SET status=$1, moderated_at=now(), moderated_by=$2, updated_at=now()
      WHERE id = $3 AND shop_id = $4
    `, [status, adminId, reviewId, shopId]);
    if (previousStatus !== status) await recalculateAggregate(tx, shopId, review.product_id);
    emit(status === "approved" ? "review.approved" : "review.rejected", {
      reviewId, shopId, productId: review.product_id, rating: review.rating,
    });
    return json(200, { review: { ...review, status, moderated_at: new Date(), moderated_by: adminId } });
  });
}
```

---

## Aggregate Recalculation

<!-- PATTERN: recalculate-aggregate -->
<!-- PURPOSE: Full recompute of aggregate from approved reviews; upsert into review_aggregates atomically -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - `COUNT(*) FILTER (WHERE rating = N)`: Postgres-specific; MySQL/SQLite use `SUM(CASE WHEN rating = N THEN 1 ELSE 0 END)`
       - `AVG(rating)::numeric(2,1)`: Postgres cast; MySQL `CAST(AVG(rating) AS DECIMAL(2,1))`; SQLite `ROUND(AVG(rating), 1)`
       - `ON CONFLICT (shop_id, product_id) DO UPDATE`: Postgres + SQLite; MySQL `INSERT ... ON DUPLICATE KEY UPDATE`
       - Full recompute (not increment): drift-proof + race-free vs increment/decrement on concurrent moderation
       - Aggregate rule: `avg_rating` rounded to 1 decimal; `total_count` and `count_star_N` count approved-only -->

```typescript
async function recalculateAggregate(
  tx: Transaction, shopId: string, productId: string
): Promise<void> {
  const stats = await tx.query(`
    SELECT
      COALESCE(AVG(rating)::numeric(2,1), 0) AS avg_rating,
      COUNT(*) AS total_count,
      COUNT(*) FILTER (WHERE rating = 1) AS count_star_1,
      COUNT(*) FILTER (WHERE rating = 2) AS count_star_2,
      COUNT(*) FILTER (WHERE rating = 3) AS count_star_3,
      COUNT(*) FILTER (WHERE rating = 4) AS count_star_4,
      COUNT(*) FILTER (WHERE rating = 5) AS count_star_5
    FROM reviews WHERE shop_id=$1 AND product_id=$2 AND status='approved'
  `, [shopId, productId]);
  await tx.query(`
    INSERT INTO review_aggregates (shop_id, product_id, avg_rating, total_count,
      count_star_1, count_star_2, count_star_3, count_star_4, count_star_5, last_updated_at)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9, now())
    ON CONFLICT (shop_id, product_id) DO UPDATE SET
      avg_rating=EXCLUDED.avg_rating, total_count=EXCLUDED.total_count,
      count_star_1=EXCLUDED.count_star_1, count_star_2=EXCLUDED.count_star_2,
      count_star_3=EXCLUDED.count_star_3, count_star_4=EXCLUDED.count_star_4,
      count_star_5=EXCLUDED.count_star_5, last_updated_at=now()
  `, [shopId, productId, stats.avg_rating, stats.total_count,
      stats.count_star_1, stats.count_star_2, stats.count_star_3,
      stats.count_star_4, stats.count_star_5]);
}
```

---

## Paginated Review List

<!-- PATTERN: paginated-reviews-query -->
<!-- PURPOSE: Return approved reviews for a product with sort and pagination; never expose customer_email -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - Offset pagination shown — for large products consider cursor pagination (created_at + id tiebreak) to avoid deep-offset cost
       - `ORDER BY ${orderBy}`: build allow-listed clause (NEVER interpolate raw user input — SQL injection risk); the map below is the allow-list
       - Public projection EXCLUDES `customer_email` — defense against email leak
       - `extractShopId(req)`: derive from request domain/header/subdomain; storefront calls may not have shopper auth -->

```typescript
async function handleListReviews(req: Request): Promise<Response> {
  const shopId = extractShopId(req);
  const { product_id, page = 1, sort = "newest" } = req.query;
  const perPage = config.REVIEWS_PER_PAGE;
  const offset = (page - 1) * perPage;
  const orderBy = ({
    newest: "created_at DESC",
    highest: "rating DESC, created_at DESC",
    lowest: "rating ASC, created_at DESC",
  } as const)[sort as string] ?? "created_at DESC";
  const [reviews, countResult] = await Promise.all([
    db.query(`
      SELECT id, customer_name, rating, title, body, verified_buyer, created_at
      FROM reviews
      WHERE shop_id=$1 AND product_id=$2 AND status='approved'
      ORDER BY ${orderBy} LIMIT $3 OFFSET $4
    `, [shopId, product_id, perPage, offset]),
    db.query(`SELECT COUNT(*) AS total FROM reviews
              WHERE shop_id=$1 AND product_id=$2 AND status='approved'`, [shopId, product_id]),
  ]);
  const total = parseInt(countResult.rows[0].total);
  return json(200, { reviews: reviews.rows, pagination: {
    page, per_page: perPage, total_count: total, total_pages: Math.ceil(total / perPage),
  }});
}
```

---

## Admin Queue Endpoint

<!-- PATTERN: admin-moderation-queue -->
<!-- PURPOSE: List reviews for moderation, filtered by status, scoped to admin's shop -->
<!-- REFERENCE: runtime=node20+ dialect=postgres -->
<!-- ADAPT:
       - `LEFT JOIN products`: optional enrichment — if app does not store product metadata, drop the join (the storefront PDP knows the title)
       - `extractAdminAuth(req)`: must verify admin role + return `shopId`; failure → 403
       - Admin endpoints may return `customer_email` (merchant-facing) — but be cautious of audit-log access -->

```typescript
async function handleAdminQueue(req: Request): Promise<Response> {
  const { shopId } = extractAdminAuth(req);
  const { status = "pending", page = 1 } = req.query;
  const perPage = 20;
  const offset = (page - 1) * perPage;
  const reviews = await db.query(`
    SELECT r.*, p.title AS product_title
    FROM reviews r
    LEFT JOIN products p ON p.id = r.product_id AND p.shop_id = r.shop_id
    WHERE r.shop_id = $1 AND r.status = $2
    ORDER BY r.created_at ASC
    LIMIT $3 OFFSET $4
  `, [shopId, status, perPage, offset]);
  return json(200, { reviews: reviews.rows });
}
```

---

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `invalid_rating` | 422 | Rating not integer 1-5 |
| `body_too_short` | 422 | Body below `MIN_BODY_LENGTH` |
| `body_too_long` | 422 | Body above `MAX_BODY_LENGTH` |
| `invalid_product` | 422 | Product ID not found |
| `invalid_status` | 422 | Moderation status not `approved`/`rejected` |
| `verified_buyer_required` | 403 | Config requires verified buyer, customer hasn't purchased |
| `already_reviewed` | 409 | Duplicate review (UNIQUE constraint violation) |
| `review_not_found` | 404 | Review ID doesn't exist or belongs to different shop |
| `unauthorized` | 401 | Not authenticated |
| `forbidden` | 403 | Not admin (for moderation endpoints) |
| `rate_limited` | 429 | Submitted >`REVIEW_SUBMIT_RATE_LIMIT` reviews/hour (anti-spam — see security.md) |

## Anti-patterns

**DON'T** accept `shop_id` or `customer_id` from the request body. Always extract from the authenticated session. Client-provided tenant/user IDs enable cross-tenant attacks.

**DON'T** recalculate aggregates by iterating reviews in application code. Use a single SQL query with `COUNT(*) FILTER (WHERE rating = N)` (or `SUM(CASE ... )` equivalent) for atomic, race-free calculation.

**DON'T** update aggregate counts with increment/decrement operations. Full recalculation from approved reviews is safer against race conditions and drift. The performance cost is negligible for typical review counts per product.

**DON'T** return `customer_email` in public-facing review list responses. The email is stored for merchant contact purposes only, never displayed on storefront.

**DON'T** allow moderation of reviews across shop boundaries. Always include `AND shop_id = $shop_id` in moderation queries, even if the review ID is a UUID (defense in depth).

**DON'T** trust client-side HTML sanitization. Strip HTML on the server before insert — output encoding alone protects against XSS but allows malicious markup to survive in storage and leak via raw exports.
