# Backend Patterns — Product Reviews

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

## Submit Handler

<!-- PATTERN: submit-review-handler -->
<!-- PURPOSE: Validate input, check verified buyer, check duplicate, insert review, optionally auto-approve -->
<!-- ADAPT: Auth extraction, DB client, event emitter -->

```typescript
// POST /api/reviews
// Request: { product_id, rating, title?, body }
// customer_id + shop_id extracted from authenticated session — NEVER from request body

async function handleSubmitReview(req: Request): Promise<Response> {
  const { shopId, customerId, customerName, customerEmail } = extractAuth(req);
  const { product_id, rating, title, body } = parseBody(req);

  // 1. Validate input
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    return error(422, "invalid_rating");
  }
  const sanitizedBody = stripHtml(body);
  if (sanitizedBody.length < config.MIN_BODY_LENGTH) {
    return error(422, "body_too_short");
  }
  if (sanitizedBody.length > config.MAX_BODY_LENGTH) {
    return error(422, "body_too_long");
  }
  const sanitizedTitle = title ? stripHtml(title).slice(0, 200) : null;

  // 2. Check verified buyer
  const isVerifiedBuyer = await checkVerifiedBuyer(shopId, customerId, product_id);
  if (config.REQUIRE_VERIFIED_BUYER && !isVerifiedBuyer) {
    return error(403, "verified_buyer_required");
  }

  // 3. Determine status
  const autoApprove = config.AUTO_APPROVE_THRESHOLD > 0
    && rating >= config.AUTO_APPROVE_THRESHOLD;
  const status = autoApprove ? "approved" : "pending";

  // 4. Insert (unique constraint handles duplicate race)
  try {
    const review = await db.insert("reviews", {
      shop_id: shopId,
      product_id,
      customer_id: customerId,
      customer_name: customerName,
      customer_email: customerEmail,
      rating,
      title: sanitizedTitle,
      body: sanitizedBody,
      status,
      verified_buyer: isVerifiedBuyer,
      moderated_at: autoApprove ? new Date() : null,
      moderated_by: autoApprove ? "system" : null,
    });

    // 5. Update aggregate if auto-approved
    if (autoApprove) {
      await recalculateAggregate(shopId, product_id);
    }

    // 6. Emit event
    emit("review.submitted", {
      reviewId: review.id, shopId, productId: product_id,
      customerId, rating, status,
    });

    return json(201, { review });
  } catch (err) {
    if (isUniqueViolation(err)) {
      return error(409, "already_reviewed");
    }
    throw err;
  }
}
```

## Verified Buyer Check

<!-- PATTERN: verified-buyer-lookup -->
<!-- PURPOSE: Query orders table to confirm customer purchased this product -->
<!-- ADAPT: CDM table structure, line items access pattern -->

```typescript
async function checkVerifiedBuyer(
  shopId: string, customerId: string, productId: string
): Promise<boolean> {
  // Query CDM orders table for any fulfilled order
  // containing this product for this customer in this shop
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

## Moderate Handler

<!-- PATTERN: moderate-review-handler -->
<!-- PURPOSE: Update review status + recalculate aggregate atomically -->
<!-- ADAPT: Transaction support, admin auth extraction -->

```typescript
// PATCH /api/admin/reviews/:id
// Request: { status: "approved" | "rejected" }

async function handleModerateReview(req: Request): Promise<Response> {
  const { shopId, adminId } = extractAdminAuth(req);
  const reviewId = req.params.id;
  const { status } = parseBody(req);

  if (!["approved", "rejected"].includes(status)) {
    return error(422, "invalid_status");
  }

  return db.transaction(async (tx) => {
    // Fetch review scoped to shop
    const review = await tx.query(
      `SELECT * FROM reviews WHERE id = $1 AND shop_id = $2`,
      [reviewId, shopId]
    );
    if (!review) return error(404, "review_not_found");

    const previousStatus = review.status;

    // Update review
    await tx.query(`
      UPDATE reviews
      SET status = $1, moderated_at = now(), moderated_by = $2, updated_at = now()
      WHERE id = $3 AND shop_id = $4
    `, [status, adminId, reviewId, shopId]);

    // Recalculate aggregate if approval state changed
    if (previousStatus !== status) {
      await recalculateAggregate(tx, shopId, review.product_id);
    }

    const eventName = status === "approved" ? "review.approved" : "review.rejected";
    emit(eventName, {
      reviewId, shopId, productId: review.product_id, rating: review.rating,
    });

    return json(200, { review: { ...review, status, moderated_at: new Date(), moderated_by: adminId } });
  });
}
```

## Aggregate Recalculation

<!-- PATTERN: recalculate-aggregate -->
<!-- PURPOSE: Recompute aggregate from approved reviews, upsert into review_aggregates -->
<!-- ADAPT: DB dialect for UPSERT syntax -->

```typescript
async function recalculateAggregate(
  tx: Transaction, shopId: string, productId: string
): Promise<void> {
  // Single query: compute all aggregate fields from approved reviews
  const stats = await tx.query(`
    SELECT
      COALESCE(AVG(rating)::numeric(2,1), 0) as avg_rating,
      COUNT(*) as total_count,
      COUNT(*) FILTER (WHERE rating = 1) as count_star_1,
      COUNT(*) FILTER (WHERE rating = 2) as count_star_2,
      COUNT(*) FILTER (WHERE rating = 3) as count_star_3,
      COUNT(*) FILTER (WHERE rating = 4) as count_star_4,
      COUNT(*) FILTER (WHERE rating = 5) as count_star_5
    FROM reviews
    WHERE shop_id = $1 AND product_id = $2 AND status = 'approved'
  `, [shopId, productId]);

  // Upsert aggregate row
  await tx.query(`
    INSERT INTO review_aggregates (shop_id, product_id, avg_rating, total_count,
      count_star_1, count_star_2, count_star_3, count_star_4, count_star_5, last_updated_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now())
    ON CONFLICT (shop_id, product_id)
    DO UPDATE SET
      avg_rating = EXCLUDED.avg_rating,
      total_count = EXCLUDED.total_count,
      count_star_1 = EXCLUDED.count_star_1,
      count_star_2 = EXCLUDED.count_star_2,
      count_star_3 = EXCLUDED.count_star_3,
      count_star_4 = EXCLUDED.count_star_4,
      count_star_5 = EXCLUDED.count_star_5,
      last_updated_at = now()
  `, [shopId, productId, stats.avg_rating, stats.total_count,
      stats.count_star_1, stats.count_star_2, stats.count_star_3,
      stats.count_star_4, stats.count_star_5]);
}
```

## Paginated Review List

<!-- PATTERN: paginated-reviews-query -->
<!-- PURPOSE: Return approved reviews for a product with sort and pagination -->
<!-- ADAPT: Pagination style (offset vs cursor), response shape -->

```typescript
// GET /api/reviews?product_id=xxx&page=1&sort=newest
// Public endpoint — no auth required, but scoped to shop

async function handleListReviews(req: Request): Promise<Response> {
  const shopId = extractShopId(req); // From domain/header, not auth
  const { product_id, page = 1, sort = "newest" } = req.query;

  const perPage = config.REVIEWS_PER_PAGE;
  const offset = (page - 1) * perPage;

  const orderBy = {
    newest: "created_at DESC",
    highest: "rating DESC, created_at DESC",
    lowest: "rating ASC, created_at DESC",
  }[sort] || "created_at DESC";

  const [reviews, countResult] = await Promise.all([
    db.query(`
      SELECT id, customer_name, rating, title, body, verified_buyer, created_at
      FROM reviews
      WHERE shop_id = $1 AND product_id = $2 AND status = 'approved'
      ORDER BY ${orderBy}
      LIMIT $3 OFFSET $4
    `, [shopId, product_id, perPage, offset]),

    db.query(`
      SELECT COUNT(*) as total
      FROM reviews
      WHERE shop_id = $1 AND product_id = $2 AND status = 'approved'
    `, [shopId, product_id]),
  ]);

  const total = parseInt(countResult.rows[0].total);

  return json(200, {
    reviews: reviews.rows,
    pagination: {
      page, per_page: perPage,
      total_count: total,
      total_pages: Math.ceil(total / perPage),
    },
  });
}
```

## Admin Queue Endpoint

<!-- PATTERN: admin-moderation-queue -->
<!-- PURPOSE: List reviews for moderation with status filter -->
<!-- ADAPT: Admin auth middleware, response shape -->

```typescript
// GET /api/admin/reviews?status=pending&page=1

async function handleAdminQueue(req: Request): Promise<Response> {
  const { shopId } = extractAdminAuth(req);
  const { status = "pending", page = 1 } = req.query;

  const perPage = 20;
  const offset = (page - 1) * perPage;

  const reviews = await db.query(`
    SELECT r.*, p.title as product_title
    FROM reviews r
    LEFT JOIN products p ON p.id = r.product_id AND p.shop_id = r.shop_id
    WHERE r.shop_id = $1 AND r.status = $2
    ORDER BY r.created_at ASC
    LIMIT $3 OFFSET $4
  `, [shopId, status, perPage, offset]);

  return json(200, { reviews: reviews.rows });
}
```

## Error Handling

| Error Code | HTTP Status | When |
|------------|-------------|------|
| `invalid_rating` | 422 | Rating not integer 1-5 |
| `body_too_short` | 422 | Body below MIN_BODY_LENGTH |
| `body_too_long` | 422 | Body above MAX_BODY_LENGTH |
| `invalid_product` | 422 | Product ID not found |
| `invalid_status` | 422 | Moderation status not approved/rejected |
| `verified_buyer_required` | 403 | Config requires verified buyer, customer hasn't purchased |
| `already_reviewed` | 409 | Duplicate review (unique constraint violation) |
| `review_not_found` | 404 | Review ID doesn't exist or belongs to different shop |
| `unauthorized` | 401 | Not authenticated |
| `forbidden` | 403 | Not admin (for moderation endpoints) |

## Anti-patterns

**DON'T** accept `shop_id` or `customer_id` from the request body. Always extract from the authenticated session. Client-provided tenant/user IDs enable cross-tenant attacks.

**DON'T** recalculate aggregates by iterating reviews in application code. Use a single SQL query with `COUNT(*) FILTER (WHERE rating = N)` for atomic, race-free calculation.

**DON'T** update aggregate counts with increment/decrement operations. Full recalculation via SQL is safer against race conditions and drift. The performance cost is negligible for typical review counts per product.

**DON'T** return `customer_email` in public-facing review list responses. The email is stored for merchant contact purposes only, never displayed on storefront.

**DON'T** allow moderation of reviews across shop boundaries. Always include `AND shop_id = $shop_id` in moderation queries, even if the review ID is a UUID (defense in depth).
