Feature: Display Reviews
  As a shopper
  I want to see product ratings and reviews on the product page
  So that I can make an informed purchase decision

  Background:
    Given the app is configured for shop "shop-001"
    And REVIEWS_PER_PAGE is configured as 3
    And the following approved reviews exist for product "product-abc":
      | id         | rating | customer_name | verified_buyer | created_at           |
      | review-001 | 5      | Alice Nguyen  | true           | 2025-01-15T10:00:00Z |
      | review-002 | 4      | Bob Tran      | true           | 2025-01-14T09:00:00Z |
      | review-003 | 2      | Charlie Le    | false          | 2025-01-13T08:00:00Z |
      | review-004 | 5      | Diana Pham    | true           | 2025-01-12T07:00:00Z |
      | review-005 | 3      | Eve Vo        | false          | 2025-01-11T06:00:00Z |
    And review_aggregates for product "product-abc" shows:
      | avg_rating | total_count | count_star_1 | count_star_2 | count_star_3 | count_star_4 | count_star_5 |
      | 3.8        | 5           | 0            | 1            | 1            | 1            | 2            |

  @happy
  Scenario: Show aggregate rating on PDP
    When I send GET /api/reviews/aggregate/product-abc
    Then the response status is 200
    And the response contains avg_rating 3.8 and total_count 5
    And the response contains count_star_1 through count_star_5 breakdown

  @happy
  Scenario: Paginated review list sorted by newest
    When I send GET /api/reviews?product_id=product-abc&page=1&sort=newest
    Then the response status is 200
    And the response contains 3 reviews (review-001, review-002, review-003)
    And reviews are ordered by created_at descending
    And pagination shows page 1 of 2, total_count 5

  @happy
  Scenario: Second page of reviews
    When I send GET /api/reviews?product_id=product-abc&page=2&sort=newest
    Then the response status is 200
    And the response contains 2 reviews (review-004, review-005)
    And pagination shows page 2 of 2

  @happy
  Scenario: Sort reviews by highest rating
    When I send GET /api/reviews?product_id=product-abc&page=1&sort=highest
    Then the response status is 200
    And the first review has rating 5
    And reviews are ordered by rating descending, then created_at descending

  @happy
  Scenario: Sort reviews by lowest rating
    When I send GET /api/reviews?product_id=product-abc&page=1&sort=lowest
    Then the response status is 200
    And the first review has rating 2
    And reviews are ordered by rating ascending, then created_at descending

  @happy
  Scenario: Show verified buyer badge
    When I send GET /api/reviews?product_id=product-abc&page=1&sort=newest
    Then review "review-001" has verified_buyer true
    And review "review-003" has verified_buyer false

  @edge
  Scenario: Empty state when no reviews exist
    When I send GET /api/reviews/aggregate/product-new
    Then the response status is 200
    And the response contains avg_rating 0 and total_count 0
    When I send GET /api/reviews?product_id=product-new&page=1
    Then the response status is 200
    And the response contains 0 reviews
    And pagination shows page 1 of 0

  @edge
  Scenario: Pending and rejected reviews are not shown on PDP
    Given a pending review exists for product "product-abc" by customer "customer-pending"
    And a rejected review exists for product "product-abc" by customer "customer-rejected"
    When I send GET /api/reviews?product_id=product-abc&page=1&sort=newest
    Then the response does not contain reviews with status "pending" or "rejected"
    And total_count in pagination reflects only approved reviews
