# Frontend Patterns — Product Reviews

> Snippets dưới đây là **L3 illustrative** (xem `docs/SPEC_GUIDELINES.md` mục 2). Pseudocode/interfaces dùng TypeScript syntax cho rõ ràng — Claude Code map qua framework cụ thể (React/Vue/Svelte/Solid) qua `ADAPT` list.

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
<!-- PURPOSE: Capture 1-5 star rating with hover preview and click to set; full keyboard + a11y support -->
<!-- REFERENCE: language=typescript framework=generic -->
<!-- ADAPT:
       - Framework binding: React `useState` + `onMouseEnter/onClick`; Vue `ref` + `@mouseenter/@click`; Svelte/Solid equivalents
       - Star icon: SVG inline (preferred — color tints + a11y), emoji (lazy), icon library (Lucide/Tabler) — pick per project
       - Accessibility: role=radiogroup parent, role=radio each star, aria-checked, aria-label="N stars" — KHÔNG omit
       - Keyboard: ArrowLeft/Right + Home/End standard radiogroup behavior; Enter/Space activate -->

```typescript
interface StarRatingInputProps {
  value: number;              // Current selected rating (0 = none)
  onChange: (rating: number) => void;
  disabled?: boolean;
}
// Behavior contract:
// - 5 stars in a row; hover over star N → stars 1..N highlight (preview)
// - Click star N → onChange(N), stars 1..N fill solid; clicking same star does not deselect
// - Keyboard: ArrowLeft/Right cycle, Home/End jump to 1/5, Enter/Space commit
// - A11y: role="radiogroup", each star role="radio" + aria-label="N stars" + aria-checked
```

## Review Form with Validation

<!-- PATTERN: review-submit-form -->
<!-- PURPOSE: Collect rating + optional title + body with client-side validation mirroring backend rules -->
<!-- REFERENCE: language=typescript framework=generic -->
<!-- ADAPT:
       - Form library: React Hook Form, Formik, VeeValidate, Felte, or hand-rolled — pick per project; validation rules must mirror backend (rating 1-5, body MIN..MAX)
       - Char count UX: live "42 / 5000" under textarea; warn at 90%, hard-stop at 100%
       - Submit lifecycle: idle → submitting → success/error; disable form during submit to prevent double-post
       - Server error mapping: 409 → "already_reviewed", 403 → "verified_buyer_required", 422 → show field-level error from response, 429 → "rate_limited" (anti-spam) -->

```typescript
interface ReviewFormState {
  rating: number;       // 0 = not set yet
  title: string;        // optional
  body: string;
  status: 'idle' | 'submitting' | 'success' | 'error';
  errorMessage: string | null;
}
// Validation (mirror backend):
//   - rating: required, 1-5
//   - title:  optional, max 200 chars
//   - body:   required, MIN_BODY_LENGTH..MAX_BODY_LENGTH chars
// Submit gated: rating > 0 && body.length >= MIN_BODY_LENGTH
// Show char count "42 / MAX_BODY_LENGTH" below textarea
```

## Review List with Pagination

<!-- PATTERN: paginated-review-list -->
<!-- PURPOSE: Display approved reviews with sort + page controls; render plain text (no innerHTML) -->
<!-- REFERENCE: language=typescript framework=generic -->
<!-- ADAPT:
       - Pagination style: numbered pages (shown) vs "Load more" — match project UX
       - Sort UI: `<select>` semantic (preferred for a11y) vs custom dropdown; persist `sort` in URL query param for shareable links
       - Loading state: skeleton placeholders (preferred — no layout shift) vs spinner; SSR-friendly
       - Empty state: render EmptyState component when total === 0 -->

```typescript
interface ReviewListProps { productId: string }
// Behavior:
//   - Fetch: GET /api/reviews?product_id={id}&page={page}&sort={sort}
//   - Sort options: newest (default), highest, lowest — store in URL query param
//   - Loading: skeleton cards (3 placeholders); empty: render EmptyState
//   - Each ReviewCard shows: customer_name, StarDisplay(rating), relative date,
//     title (if present), body (plain text), VerifiedBuyerBadge (if verified_buyer)
//   - Body rendered as plain text — never innerHTML/v-html/dangerouslySetInnerHTML
```

## Aggregate Display

<!-- PATTERN: rating-aggregate -->
<!-- PURPOSE: Show avg rating, total count, and star distribution bars on PDP -->
<!-- REFERENCE: language=typescript framework=generic -->
<!-- ADAPT:
       - Layout: horizontal split (preferred for wide PDP) vs vertical stack (mobile)
       - Bar width formula: `(count / max_count) * 100%` — uses max single-star count as denominator for visual proportion; use `total_count` if you prefer percentage-of-total
       - Star rendering: same StarDisplay component as ReviewCard for visual consistency
       - When `totalCount === 0`: render EmptyState instead of zero-state aggregate -->

```typescript
interface AggregateDisplayProps {
  avgRating: number;            // e.g. 4.2 (1 decimal — see README aggregate rule)
  totalCount: number;
  countPerStar: { 1: number; 2: number; 3: number; 4: number; 5: number };
}
// Layout contract:
//   Left:  large avg number ("4.2") + StarDisplay + "{totalCount} reviews"
//   Right: 5 horizontal bars (5★ top, 1★ bottom), each "N ★ ████████░░ count"
// Bar width = (count_star_N / max(count_star_1..5)) * 100%
```

## Verified Buyer Badge

<!-- PATTERN: verified-badge -->
<!-- PURPOSE: Trust signal for shoppers — reviewer purchased the product (server-computed) -->
<!-- REFERENCE: language=typescript framework=generic -->
<!-- ADAPT:
       - Icon: checkmark (preferred — universal) or shield; use SVG for color tinting + a11y
       - Text: "Verified Buyer" (English) — localize per project
       - Color: subtle green/teal — must not dominate review content visually
       - A11y: include badge text in review card's aria-label so screen readers announce it -->

```typescript
// Conditional render based on server-computed `review.verified_buyer`:
//   if (review.verified_buyer) → render badge (checkmark icon + "Verified Buyer")
// MUST come from the server response; client cannot fabricate this status
```

## Empty State

<!-- PATTERN: no-reviews-empty-state -->
<!-- PURPOSE: Encourage first review when product has zero approved reviews -->
<!-- REFERENCE: language=typescript framework=generic -->
<!-- ADAPT:
       - Copy: "No reviews yet" + "Be the first to share your experience" — localize per project
       - CTA target: scroll to form (preferred — keeps context) vs open modal vs separate page
       - Auth-aware: when shopper not signed in, show "Sign in to write a review" CTA pointing to login -->

```typescript
// When aggregate.totalCount === 0:
//   Heading: "No reviews yet"
//   Subtext: "Be the first to share your experience with this product"
//   CTA:     authenticated → "Write a Review" → scroll to ReviewForm
//            unauthenticated → "Sign in to write a review" → login redirect
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
| Rate-limited | "You've reached the review limit — please try later" | From 429 response |
| Empty state | Illustration + CTA | Show form prominently |
| Pagination loading | Dim current list, show spinner | Keep scroll position |

## Anti-patterns

**DON'T** render review body using `innerHTML` / `v-html` / `dangerouslySetInnerHTML`. Always use text rendering (framework default). Review content is user-generated and must be treated as untrusted — even though backend HTML-strips on insert (defense in depth).

**DON'T** let the client send `verified_buyer: true` in the submit request. This field is server-computed. Ignore any client-provided value at the API boundary.

**DON'T** show pending/rejected reviews to shoppers. The storefront API only returns `status='approved'` reviews. Don't add client-side filtering as the sole guard.

**DON'T** block PDP render waiting for reviews. Load reviews asynchronously — the product info should render immediately, reviews load in below.

**DON'T** use star images without alt text. Each star state (filled, half, empty) needs accessible labeling for screen readers; rating inputs use `role="radiogroup"` with per-star `aria-label`.
