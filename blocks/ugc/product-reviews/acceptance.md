# Acceptance Checklist — Product Reviews

Claude Code runs this checklist after implementation, before reporting done.

## Database

- [ ] Migration runs successfully (`reviews` + `review_aggregates` tables created)
- [ ] `CHECK (rating BETWEEN 1 AND 5)` constraint is active on `reviews.rating`
- [ ] `CHECK (status IN ('pending', 'approved', 'rejected'))` constraint is active on `reviews.status`
- [ ] `UNIQUE (shop_id, product_id, customer_id)` index exists on `reviews`
- [ ] `UNIQUE (shop_id, product_id)` index exists on `review_aggregates`
- [ ] All queries include `WHERE shop_id = $shop_id` (tenant isolation)

## Review Submission

- [ ] Submitting a review with rating 1-5 and valid body returns 201
- [ ] Submitting with rating 0 or 6 returns 422 `invalid_rating`
- [ ] Submitting with body shorter than MIN_BODY_LENGTH returns 422 `body_too_short`
- [ ] Submitting duplicate review (same customer + product) returns 409 `already_reviewed`
- [ ] Verified buyer check queries orders table and sets `verified_buyer` correctly
- [ ] When REQUIRE_VERIFIED_BUYER is true, non-buyers get 403 `verified_buyer_required`
- [ ] When AUTO_APPROVE_THRESHOLD is set, qualifying reviews get status `approved` and aggregate is updated
- [ ] `review.submitted` event is emitted on successful submission
- [ ] `customer_id` and `shop_id` are extracted from session, not request body

## Moderation

- [ ] GET /api/admin/reviews?status=pending returns only pending reviews for the current shop
- [ ] PATCH /api/admin/reviews/:id with `approved` sets status, moderated_at, moderated_by
- [ ] PATCH /api/admin/reviews/:id with `rejected` sets status, moderated_at, moderated_by
- [ ] Approving a review recalculates `review_aggregates` for that product
- [ ] Rejecting a previously approved review recalculates aggregate (count decreases)
- [ ] Rejecting a pending review does not change aggregate (was not counted)
- [ ] Moderating a review from another shop returns 404
- [ ] Bulk moderation endpoint processes multiple reviews and recalculates aggregate once per product
- [ ] `review.approved` / `review.rejected` events are emitted

## Display

- [ ] GET /api/reviews/aggregate/:product_id returns correct avg_rating, total_count, and per-star counts
- [ ] Aggregate reflects only approved reviews (pending/rejected excluded)
- [ ] GET /api/reviews returns only approved reviews (pending/rejected excluded)
- [ ] Pagination works correctly (page 1 returns REVIEWS_PER_PAGE items, page 2 returns remainder)
- [ ] Sort by newest returns reviews ordered by created_at DESC
- [ ] Sort by highest returns reviews ordered by rating DESC
- [ ] Sort by lowest returns reviews ordered by rating ASC
- [ ] Empty product (no reviews) returns aggregate with avg_rating 0 and total_count 0
- [ ] `customer_email` is NOT returned in public review list responses

## Security

- [ ] Review body and title are sanitized (HTML stripped) before storage
- [ ] No XSS possible when rendering review content on PDP
- [ ] `verified_buyer` field cannot be set by client — server-computed only
- [ ] Unique constraint prevents duplicate reviews at DB level (not just app level)
- [ ] All admin endpoints require admin authentication
- [ ] All queries are tenant-scoped (shop_id)

## Type Safety & Build

- [ ] `tsc --noEmit` passes (or equivalent type check for the project)
- [ ] No `any` types used without justification comment
- [ ] Zod (or equivalent) validation at API boundary for request bodies
