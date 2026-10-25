Feature: Moderate Review
  As a merchant
  I want to approve or reject submitted reviews
  So that only quality, relevant reviews appear on my product pages

  Background:
    Given the app is configured for shop "shop-001"
    And I am authenticated as admin "admin-001"
    And the following reviews exist:
      | id         | product_id  | rating | status  | customer_name  | created_at          |
      | review-001 | product-abc | 5      | pending | Alice Nguyen   | 2025-01-15T10:00:00Z |
      | review-002 | product-abc | 2      | pending | Bob Tran       | 2025-01-15T11:00:00Z |
      | review-003 | product-abc | 4      | approved| Charlie Le     | 2025-01-14T09:00:00Z |
      | review-004 | product-def | 1      | pending | Diana Pham     | 2025-01-15T12:00:00Z |

  @happy
  Scenario: Approve review updates aggregate
    Given review_aggregates for product "product-abc" shows avg_rating 4.0 and total_count 1
    When I send PATCH /api/admin/reviews/review-001 with { "status": "approved" }
    Then the response status is 200
    And review "review-001" status is "approved"
    And review "review-001" moderated_at is set to now
    And review "review-001" moderated_by is "admin-001"
    And review_aggregates for product "product-abc" shows avg_rating 4.5 and total_count 2
    And count_star_5 incremented by 1
    And a "review.approved" event is emitted with reviewId "review-001"

  @happy
  Scenario: Reject review updates aggregate (no change if was pending)
    Given review_aggregates for product "product-abc" shows avg_rating 4.0 and total_count 1
    When I send PATCH /api/admin/reviews/review-002 with { "status": "rejected" }
    Then the response status is 200
    And review "review-002" status is "rejected"
    And review "review-002" moderated_at is set to now
    And review_aggregates for product "product-abc" remains avg_rating 4.0 and total_count 1
    And a "review.rejected" event is emitted with reviewId "review-002"

  @happy
  Scenario: Reject a previously approved review recalculates aggregate
    When I send PATCH /api/admin/reviews/review-003 with { "status": "rejected" }
    Then the response status is 200
    And review "review-003" status is "rejected"
    And review_aggregates for product "product-abc" total_count decreases by 1
    And avg_rating is recalculated excluding review-003

  @happy
  Scenario: Auto-approve high rating review
    Given AUTO_APPROVE_THRESHOLD is configured as 4
    And a new review is submitted with rating 5 for product "product-ghi"
    Then the review status is "approved" immediately
    And review_aggregates for product "product-ghi" is created or updated
    And no moderation action is needed

  @happy
  Scenario: Filter moderation queue by status
    When I send GET /api/admin/reviews?status=pending
    Then the response contains 3 reviews (review-001, review-002, review-004)
    And reviews are ordered by created_at ascending (oldest first)
    When I send GET /api/admin/reviews?status=approved
    Then the response contains 1 review (review-003)

  @happy
  Scenario: Bulk moderate multiple reviews
    When I send PATCH /api/admin/reviews/bulk with:
      | review_ids                    | status   |
      | ["review-001", "review-002"] | approved |
    Then the response status is 200
    And review "review-001" status is "approved"
    And review "review-002" status is "approved"
    And review_aggregates for product "product-abc" is recalculated once (not per review)
    And 2 "review.approved" events are emitted

  @edge
  Scenario: Moderate review from another shop is forbidden
    Given review "review-999" belongs to shop "shop-other"
    When I send PATCH /api/admin/reviews/review-999 with { "status": "approved" }
    Then the response status is 404
    And review "review-999" status is unchanged

  @edge
  Scenario: Moderate nonexistent review returns 404
    When I send PATCH /api/admin/reviews/review-nonexistent with { "status": "approved" }
    Then the response status is 404
