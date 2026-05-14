# Frontend Patterns — Product Reviews

## Component Tree

```
ProductReviews/                    # Top-level wrapper, placed on PDP
├── ReviewAggregate/               # Stars + count + distribution bars
│   ├── StarDisplay                # Read-only star visualization (filled/half/empty)
│   └── RatingDistribution         # Horizontal bars showing count per star
├── ReviewList/                    # Paginated list of approved reviews
│   ├── ReviewCard                 # Single review: name, rating, date, body, badge
│   │   ├── StarDisplay            # Reused — shows review's rating
│   │   └── VerifiedBuyerBadge     # Conditional badge
│   ├── ReviewSortSelect           # Dropdown: newest, highest, lowest
│   └── Pagination                 # Page navigation
├── ReviewForm/                    # Submit form (shown to authenticated shoppers)
│   ├── StarRatingInput            # Interactive clickable stars
│   ├── TextInput (title)          # Optional headline
│   ├── TextArea (body)            # Review content with char count
│   └── SubmitButton               # With loading state
└── EmptyState/                    # "No reviews yet — be the first!"
```

## Star Rating Input Component

<!-- PATTERN: interactive-star-input -->
<!-- PURPOSE: Capture 1-5 star rating with hover preview and click to set -->
<!-- ADAPT: Styling, star icon (SVG/emoji/icon library), size -->

```typescript
interface StarRatingInputProps {
  value: number;              // Current selected rating (0 = none)
  onChange: (rating: number) => void;
  disabled?: boolean;
}

// Behavior:
// - 5 star icons in a row
// - Hover over star N → stars 1..N highlight (preview)
// - Click star N → onChange(N), stars 1..N fill solid
// - Click same star again → no deselect (rating required)
// - Keyboard: arrow left/right to change, Enter to confirm
// - Accessible: role="radiogroup", each star role="radio", aria-label="N stars"
```

## Review Form with Validation

<!-- PATTERN: review-submit-form -->
<!-- PURPOSE: Collect rating + optional title + body with client-side validation -->
<!-- ADAPT: Form library, validation approach, styling -->

```typescript
interface ReviewFormState {
  rating: number;       // 0 = not set yet
  title: string;        // Optional
  body: string;
  status: 'idle' | 'submitting' | 'success' | 'error';
  errorMessage: string | null;
}

// Validation rules (mirror backend):
// - rating: required, 1-5
// - title: optional, max 200 chars
// - body: required, MIN_BODY_LENGTH..MAX_BODY_LENGTH chars
// Show character count below textarea: "42 / 5000"
// Disable submit until rating > 0 and body meets min length
// On submit: set status='submitting', disable form, POST /api/reviews
// On 201: set status='success', show thank you message, optionally add to list (if auto-approved)
// On 409: show "You already reviewed this product"
// On 403: show "Only verified buyers can review this product"
// On 422: show specific validation error from server
```

## Review List with Pagination

<!-- PATTERN: paginated-review-list -->
<!-- PURPOSE: Display approved reviews with sort and page controls -->
<!-- ADAPT: Pagination style (numbered pages vs load more), sort UI -->

```typescript
interface ReviewListProps {
  productId: string;
}

// Fetch: GET /api/reviews?product_id={id}&page={page}&sort={sort}
// Sort options: newest (default), highest, lowest
// Store sort in URL query param for shareable links
// Show loading skeleton while fetching
// On empty result: render EmptyState component
// Each ReviewCard shows: customer_name, StarDisplay, relative date, title (if present), body, VerifiedBuyerBadge (if verified)
```

## Aggregate Display

<!-- PATTERN: rating-aggregate -->
<!-- PURPOSE: Show avg rating, total count, and star distribution bars on PDP -->
<!-- ADAPT: Layout (horizontal/vertical), bar styling, compact vs expanded -->

```typescript
interface AggregateDisplayProps {
  avgRating: number;      // e.g. 4.2
  totalCount: number;     // e.g. 47
  countPerStar: {         // Distribution
    1: number;
    2: number;
    3: number;
    4: number;
    5: number;
  };
}

// Layout:
// Left side: large avg number (e.g. "4.2") + StarDisplay + "47 reviews"
// Right side: 5 horizontal bars (star 5 at top, star 1 at bottom)
//   Each bar: "5 ★ ████████░░ 24" — label, proportional bar, count
//   Bar width = (count / max_count) * 100% for visual proportion
// When totalCount is 0: show EmptyState instead
```

## Verified Buyer Badge

<!-- PATTERN: verified-badge -->
<!-- PURPOSE: Trust signal showing reviewer purchased the product -->
<!-- ADAPT: Icon, text, color -->

```typescript
// Simple conditional render:
// if (review.verified_buyer) → show badge with checkmark icon + "Verified Buyer"
// Accessible: include in aria-label of the review card
// Style: small, subtle, green checkmark — not dominant over review content
```

## Empty State

<!-- PATTERN: no-reviews-empty-state -->
<!-- PURPOSE: Encourage first review when product has zero reviews -->
<!-- ADAPT: Copy, illustration, CTA style -->

```typescript
// When aggregate.totalCount === 0:
// - Heading: "No reviews yet"
// - Subtext: "Be the first to share your experience with this product"
// - CTA button: "Write a Review" → scrolls to or reveals ReviewForm
// When user is not authenticated:
// - CTA: "Sign in to write a review"
```

## UI/UX States

| State | Visual | Behavior |
|-------|--------|----------|
| Loading aggregate | Skeleton pulse (star shape + bar shapes) | Fetch on PDP mount |
| Loading reviews | Skeleton cards (3 placeholders) | Fetch after aggregate |
| Form idle | Interactive stars + empty fields | Submit disabled until valid |
| Form submitting | Button shows spinner, form fields disabled | Prevent double submit |
| Form success | Green banner: "Thanks! Your review is pending moderation" | Auto-dismiss after 5s |
| Form error | Red inline error below relevant field | Preserve user input |
| Empty state | Illustration + CTA | Show form prominently |
| Pagination loading | Dim current list, show spinner | Keep scroll position |

## Anti-patterns

**DON'T** render review body using `innerHTML` / `v-html` / `dangerouslySetInnerHTML`. Always use text rendering (framework default). Review content is user-generated and must be treated as untrusted.

**DON'T** let the client send `verified_buyer: true` in the submit request. This field is server-computed. Ignore any client-provided value.

**DON'T** show pending/rejected reviews to shoppers. The storefront API only returns `status='approved'` reviews. Don't add client-side filtering as the sole guard.

**DON'T** block PDP render waiting for reviews. Load reviews asynchronously — the product info should render immediately, reviews load in below.

**DON'T** use star images without alt text. Each star state (filled, half, empty) needs accessible labeling for screen readers.
