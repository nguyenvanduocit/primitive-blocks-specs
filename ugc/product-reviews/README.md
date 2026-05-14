---
id: "ugc.product-reviews"
name: "Product Reviews"
version: "1.0.0"
category: "ugc"
tags: [reviews, ugc, social-proof, moderation, ratings]
prerequisites: []
complexity: medium
estimated_effort: "~60 min"
files:
  - README.md
  - frontend.md
  - backend.md
  - security.md
  - submit-review.feature
  - moderate-review.feature
  - display-reviews.feature
  - fixtures/sample-reviews.json
  - fixtures/aggregate.json
  - acceptance.md
---

# Product Reviews

## 1. Overview

### Problem Statement

Social proof drives conversion. Shoppers trust other shoppers more than marketing copy — a product with 50 reviews at 4.3 stars converts measurably better than one with zero reviews. Merchants need a way for shoppers to submit reviews, a moderation workflow to filter spam/abuse, and a storefront display that shows aggregate ratings + individual reviews on product pages.

### User Stories

- **Shopper**: I purchased a product, I want to leave a star rating and written review so other shoppers can benefit from my experience
- **Shopper**: I'm browsing a product page, I want to see the average rating, star distribution, and read individual reviews so I can make an informed purchase decision
- **Merchant**: I want to moderate reviews before they appear publicly so I can filter spam, abuse, or off-topic content
- **Merchant**: I want verified buyer badges on reviews so shoppers trust the authenticity
- **Merchant**: I want high-rating reviews to auto-approve so I spend less time on moderation

### When to use this block

- User mentions: "reviews", "ratings", "social proof", "product feedback", "star rating", "UGC"
- App needs product page enrichment with customer opinions
- Merchant wants moderation control over user-generated content

### When NOT to use

- Merchant wants Q&A on products (not ratings/reviews) → block: `ugc.product-qa`
- Merchant wants site-wide testimonials (not product-specific) → block: `ugc.testimonials`
- Merchant wants photo/video reviews only → extend this block with media upload

---

## 2. Data Model

```mermaid
erDiagram
    reviews {
        text id PK "gen_random_uuid()"
        text shop_id FK "tenant isolation"
        text product_id "Shopify product ID"
        text customer_id "Shopify customer ID"
        text customer_name "Display name"
        text customer_email "Contact email"
        int rating "1-5 stars"
        text title "Review headline"
        text body "Review content"
        text status "pending | approved | rejected"
        boolean verified_buyer "Checked via order history"
        timestamptz moderated_at "When moderated"
        text moderated_by "Admin who moderated"
        timestamptz created_at
        timestamptz updated_at
    }

    review_aggregates {
        text id PK "gen_random_uuid()"
        text shop_id FK "tenant isolation"
        text product_id UK "One row per product per shop"
        numeric avg_rating "Rounded to 1 decimal"
        int total_count "Approved reviews only"
        int count_star_1
        int count_star_2
        int count_star_3
        int count_star_4
        int count_star_5
        timestamptz last_updated_at
    }

    reviews }o--|| review_aggregates : "aggregated into"
```

### Table: `reviews`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `text` | PK, default `gen_random_uuid()` | |
| `shop_id` | `text` | NOT NULL, indexed | Tenant isolation |
| `product_id` | `text` | NOT NULL | Shopify product GID |
| `customer_id` | `text` | NOT NULL | Shopify customer GID |
| `customer_name` | `text` | NOT NULL | Display name on review |
| `customer_email` | `text` | NOT NULL | Not displayed publicly |
| `rating` | `integer` | NOT NULL, CHECK 1-5 | Star rating |
| `title` | `text` | nullable | Optional headline |
| `body` | `text` | NOT NULL | Review content |
| `status` | `text` | NOT NULL, default `'pending'` | `pending`, `approved`, `rejected` |
| `verified_buyer` | `boolean` | NOT NULL, default `false` | Checked at submit time |
| `moderated_at` | `timestamptz` | nullable | Set on approve/reject |
| `moderated_by` | `text` | nullable | Admin user ID |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | |
| `updated_at` | `timestamptz` | NOT NULL, default `now()` | |

### Table: `review_aggregates`

Denormalized table (not materialized view) — updated transactionally on each approve/reject. This avoids refresh-overhead and staleness windows that hurt PDP latency. Trade-off: slight write overhead on moderation actions, but moderation is low-frequency compared to PDP reads.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | `text` | PK, default `gen_random_uuid()` | |
| `shop_id` | `text` | NOT NULL | Tenant isolation |
| `product_id` | `text` | NOT NULL | One row per product per shop |
| `avg_rating` | `numeric(2,1)` | NOT NULL, default `0` | Average of approved reviews |
| `total_count` | `integer` | NOT NULL, default `0` | Count of approved reviews |
| `count_star_1` | `integer` | NOT NULL, default `0` | |
| `count_star_2` | `integer` | NOT NULL, default `0` | |
| `count_star_3` | `integer` | NOT NULL, default `0` | |
| `count_star_4` | `integer` | NOT NULL, default `0` | |
| `count_star_5` | `integer` | NOT NULL, default `0` | |
| `last_updated_at` | `timestamptz` | NOT NULL, default `now()` | |

### Migration (reference)

```sql
CREATE TABLE IF NOT EXISTS reviews (
  id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  shop_id text NOT NULL,
  product_id text NOT NULL,
  customer_id text NOT NULL,
  customer_name text NOT NULL,
  customer_email text NOT NULL,
  rating integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
  title text,
  body text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  verified_buyer boolean NOT NULL DEFAULT false,
  moderated_at timestamptz,
  moderated_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Tenant isolation + common queries
CREATE INDEX idx_reviews_shop_id ON reviews(shop_id);
CREATE INDEX idx_reviews_product_status ON reviews(shop_id, product_id, status);
CREATE INDEX idx_reviews_moderation_queue ON reviews(shop_id, status, created_at) WHERE status = 'pending';

-- Prevent duplicate reviews: one review per customer per product per shop
CREATE UNIQUE INDEX idx_reviews_unique_per_customer ON reviews(shop_id, product_id, customer_id);

CREATE TABLE IF NOT EXISTS review_aggregates (
  id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  shop_id text NOT NULL,
  product_id text NOT NULL,
  avg_rating numeric(2,1) NOT NULL DEFAULT 0,
  total_count integer NOT NULL DEFAULT 0,
  count_star_1 integer NOT NULL DEFAULT 0,
  count_star_2 integer NOT NULL DEFAULT 0,
  count_star_3 integer NOT NULL DEFAULT 0,
  count_star_4 integer NOT NULL DEFAULT 0,
  count_star_5 integer NOT NULL DEFAULT 0,
  last_updated_at timestamptz NOT NULL DEFAULT now()
);

-- One aggregate row per product per shop
CREATE UNIQUE INDEX idx_review_aggregates_product ON review_aggregates(shop_id, product_id);
```

---

## 3. Data Flow

```mermaid
flowchart TD
    A[Shopper submits review on PDP] --> B[Frontend validates form locally]
    B --> C[POST /api/reviews]
    C --> D[Backend validates input]
    D --> E{Verified buyer check}
    E -->|Config requires + not verified| F[Reject 403]
    E -->|Verified or not required| G{Duplicate check}
    G -->|Already reviewed| H[Reject 409]
    G -->|New review| I{Auto-approve?}
    I -->|Rating >= threshold| J[Insert with status=approved]
    I -->|Below threshold| K[Insert with status=pending]
    J --> L[Recalculate aggregate]
    K --> M[Emit review.submitted event]
    L --> M

    N[Merchant opens moderation queue] --> O[GET /api/admin/reviews?status=pending]
    O --> P[Merchant approves or rejects]
    P --> Q[PATCH /api/admin/reviews/:id]
    Q --> R[Update review status]
    R --> S[Recalculate aggregate]
    S --> T[Emit review.approved or review.rejected]

    U[Shopper visits PDP] --> V[GET /api/reviews/aggregate/:product_id]
    V --> W[Return aggregate from review_aggregates table]
    U --> X[GET /api/reviews?product_id=xxx&page=1]
    X --> Y[Return paginated approved reviews]
```

---

## 4. Sequence Diagrams

### Submit Review (with verified buyer check)

```mermaid
sequenceDiagram
    actor S as Shopper
    participant F as Frontend
    participant B as Backend
    participant DB as Database

    S->>F: Fill review form (rating, title, body)
    F->>F: Validate locally (rating 1-5, body length)
    F->>B: POST /api/reviews { product_id, rating, title, body }

    B->>B: Validate input (rating range, body length, sanitize)
    B->>DB: SELECT id FROM reviews WHERE shop_id=$1 AND product_id=$2 AND customer_id=$3
    alt Duplicate exists
        DB-->>B: row found
        B-->>F: 409 { error: "already_reviewed" }
    else No duplicate
        DB-->>B: null
        B->>DB: SELECT id FROM orders WHERE shop_id=$1 AND customer_id=$2 AND product_id in line_items
        alt Verified buyer
            DB-->>B: order found
            B->>B: verified_buyer = true
        else Not verified
            DB-->>B: null
            alt Config requires verified buyer
                B-->>F: 403 { error: "verified_buyer_required" }
            else Not required
                B->>B: verified_buyer = false
            end
        end
        B->>B: Check auto-approve (rating >= threshold)
        B->>DB: INSERT review (status = approved or pending)
        alt Auto-approved
            B->>DB: UPSERT review_aggregates (recalculate)
        end
        B-->>F: 201 { review }
        B->>B: Emit review.submitted event
    end
    F->>F: Show success message, optimistic UI update
```

### Moderate Review (approve/reject)

```mermaid
sequenceDiagram
    actor M as Merchant
    participant A as Admin UI
    participant B as Backend
    participant DB as Database

    M->>A: Open moderation queue
    A->>B: GET /api/admin/reviews?status=pending
    B->>DB: SELECT reviews WHERE shop_id=$1 AND status='pending' ORDER BY created_at
    DB-->>B: pending reviews
    B-->>A: 200 { reviews[], total }
    A->>A: Render queue with approve/reject buttons

    M->>A: Click approve on review-123
    A->>B: PATCH /api/admin/reviews/review-123 { status: "approved" }
    B->>DB: UPDATE reviews SET status='approved', moderated_at=now(), moderated_by=$admin WHERE id=$1 AND shop_id=$2
    B->>DB: Recalculate review_aggregates for product_id
    DB-->>B: done
    B-->>A: 200 { review }
    B->>B: Emit review.approved event
    A->>A: Remove from queue, show success
```

### Display Reviews on PDP

```mermaid
sequenceDiagram
    actor S as Shopper
    participant F as Frontend
    participant B as Backend
    participant DB as Database

    S->>F: Navigate to product page
    F->>B: GET /api/reviews/aggregate/product-123
    B->>DB: SELECT * FROM review_aggregates WHERE shop_id=$1 AND product_id=$2
    DB-->>B: aggregate row (or null)
    B-->>F: 200 { avg_rating, total_count, count_star_1..5 }

    F->>B: GET /api/reviews?product_id=product-123&page=1&sort=newest
    B->>DB: SELECT * FROM reviews WHERE shop_id=$1 AND product_id=$2 AND status='approved' ORDER BY created_at DESC LIMIT $per_page OFFSET $offset
    DB-->>B: review rows + total
    B-->>F: 200 { reviews[], pagination }

    F->>F: Render aggregate stars + distribution bars
    F->>F: Render paginated review list with verified badges
```

---

## 5. State Management

| State | Storage | Survives Reload | Notes |
|-------|---------|-----------------|-------|
| `aggregate` | In-memory (reactive) | No — fetched on PDP load | `{ avgRating, totalCount, countPerStar }` or `null` |
| `reviews` | In-memory (reactive) | No — fetched with pagination | `Review[]` |
| `pagination` | In-memory | No | `{ page, totalPages, totalCount }` |
| `sortOrder` | URL query param | Yes | `newest`, `highest`, `lowest` |
| `reviewForm` | In-memory | No | `{ rating, title, body }` |
| `formStatus` | In-memory | No | `idle`, `submitting`, `success`, `error` |
| `moderationQueue` | In-memory (admin) | No | `Review[]` with status filters |

### State transitions

```
PDP Load → fetch aggregate + fetch reviews page 1
  ├── Both succeed → render aggregate + review list
  ├── Aggregate empty → show "No reviews yet" + review form
  └── Error → show error state, retry button

Review Submit → formStatus=submitting → POST /api/reviews
  ├── 201 → formStatus=success → optimistic add to list (if auto-approved) → refetch aggregate
  ├── 409 → formStatus=error → "You already reviewed this product"
  ├── 403 → formStatus=error → "Only verified buyers can review"
  └── 422 → formStatus=error → show validation errors

Sort Change → update URL param → refetch reviews page 1

Page Change → fetch reviews page N → append or replace list
```

---

## 6. Integration Points

### Inbound

| Caller | How | Purpose |
|--------|-----|---------|
| Product page (PDP) | Component embed | Display aggregate + review list |
| Authenticated shopper | POST /api/reviews | Submit review |
| Admin panel | GET/PATCH /api/admin/reviews | Moderation queue |

### Outbound

| Target | How | Purpose |
|--------|-----|---------|
| Database | SQL | Reviews + aggregates CRUD |
| Orders data (CDM) | SQL query | Verified buyer check — lookup `orders` table for customer + product match |

### Events

| Event | Payload | When |
|-------|---------|------|
| `review.submitted` | `{ reviewId, shopId, productId, customerId, rating, status }` | Review created |
| `review.approved` | `{ reviewId, shopId, productId, rating }` | Merchant approves |
| `review.rejected` | `{ reviewId, shopId, productId }` | Merchant rejects |

### Verified Buyer Check Strategy

Synchronous lookup against CDM `orders` table at submit time. Query: does an order exist for this `shop_id` + `customer_id` that contains `product_id` in its line items? Result is stored as `verified_buyer` boolean on the review row — not re-checked later.

Trade-off: if a customer returns the product after reviewing, the badge persists. Acceptable because post-return badge removal adds complexity with minimal UX benefit, and the review content remains valid.

---

## 7. Configuration Surface

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `REQUIRE_VERIFIED_BUYER` | `boolean` | `false` | Reject reviews from non-buyers when true |
| `AUTO_APPROVE_THRESHOLD` | `number` | `0` (disabled) | Ratings >= this value auto-approve. Set 4 or 5 to auto-approve positive reviews. `0` = all reviews go to moderation queue |
| `MIN_BODY_LENGTH` | `number` | `10` | Minimum characters for review body |
| `MAX_BODY_LENGTH` | `number` | `5000` | Maximum characters for review body |
| `REVIEWS_PER_PAGE` | `number` | `10` | Pagination size for storefront display |
| `DEFAULT_SORT` | `string` | `"newest"` | Default sort order: `newest`, `highest`, `lowest` |
