Feature: Submit Review
  As a shopper
  I want to submit a review for a product I purchased
  So that other shoppers can benefit from my experience

  Background:
    Given the app is configured for shop "shop-001"
    And a product "product-abc" exists with title "Wireless Headphones"
    And a customer "customer-xyz" exists with name "Alice Nguyen" and email "alice@example.com"

  @happy
  Scenario: Submit review with valid data
    Given customer "customer-xyz" has a completed order containing product "product-abc"
    And no review exists for shop "shop-001", product "product-abc", customer "customer-xyz"
    When I submit POST /api/reviews with:
      | product_id  | product-abc           |
      | rating      | 4                     |
      | title       | Great sound quality   |
      | body        | These headphones exceeded my expectations. Clear audio and comfortable fit. |
    Then the response status is 201
    And a review is created with status "pending"
    And verified_buyer is true
    And a "review.submitted" event is emitted with rating 4 and status "pending"

  @happy
  Scenario: Submit review without title (title is optional)
    Given customer "customer-xyz" has a completed order containing product "product-abc"
    And no review exists for shop "shop-001", product "product-abc", customer "customer-xyz"
    When I submit POST /api/reviews with:
      | product_id  | product-abc                           |
      | rating      | 5                                     |
      | body        | Love this product, highly recommend!  |
    Then the response status is 201
    And the review title is null

  @happy
  Scenario: Auto-approve review when rating meets threshold
    Given AUTO_APPROVE_THRESHOLD is configured as 4
    And customer "customer-xyz" has a completed order containing product "product-abc"
    When I submit POST /api/reviews with:
      | product_id  | product-abc               |
      | rating      | 5                         |
      | body        | Absolutely perfect product |
    Then the response status is 201
    And the review status is "approved"
    And review_aggregates for product "product-abc" is updated with the new rating
    And a "review.submitted" event is emitted with status "approved"

  @error
  Scenario: Reject review when not a verified buyer and config requires it
    Given REQUIRE_VERIFIED_BUYER is true
    And customer "customer-xyz" has NO completed order containing product "product-abc"
    When I submit POST /api/reviews with:
      | product_id  | product-abc                    |
      | rating      | 3                              |
      | body        | Decent product for the price   |
    Then the response status is 403
    And the response body contains error "verified_buyer_required"
    And no review is created

  @error
  Scenario: Reject review when body is too short
    Given MIN_BODY_LENGTH is configured as 10
    And customer "customer-xyz" has a completed order containing product "product-abc"
    When I submit POST /api/reviews with:
      | product_id  | product-abc  |
      | rating      | 5            |
      | body        | Good         |
    Then the response status is 422
    And the response body contains error "body_too_short"
    And no review is created

  @error
  Scenario: Prevent duplicate review per product per customer
    Given a review already exists for shop "shop-001", product "product-abc", customer "customer-xyz"
    When I submit POST /api/reviews with:
      | product_id  | product-abc                 |
      | rating      | 2                           |
      | body        | Changed my mind about this  |
    Then the response status is 409
    And the response body contains error "already_reviewed"
    And no additional review is created

  @error
  Scenario: Reject rating out of range (too high)
    When I submit POST /api/reviews with:
      | product_id  | product-abc               |
      | rating      | 6                         |
      | body        | This product is amazing   |
    Then the response status is 422
    And the response body contains error "invalid_rating"

  @error
  Scenario: Reject rating out of range (too low)
    When I submit POST /api/reviews with:
      | product_id  | product-abc               |
      | rating      | 0                         |
      | body        | Terrible product          |
    Then the response status is 422
    And the response body contains error "invalid_rating"

  @edge
  Scenario: Non-verified buyer can still submit when REQUIRE_VERIFIED_BUYER is false
    Given REQUIRE_VERIFIED_BUYER is false
    And customer "customer-xyz" has NO completed order containing product "product-abc"
    When I submit POST /api/reviews with:
      | product_id  | product-abc                         |
      | rating      | 4                                   |
      | body        | Got this as a gift, works great!    |
    Then the response status is 201
    And verified_buyer is false
    And the review is created with status "pending"
