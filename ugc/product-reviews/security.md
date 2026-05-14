# Security — Product Reviews

## Threat Model

### 1. Spam / Bot Reviews

**Impact**: High — fake reviews erode trust, pollute aggregate ratings, overwhelm moderation queue.

**Mitigations**:
- Require authentication — only logged-in customers can submit reviews
- Rate limiting — max 5 review submissions per customer per hour
- `REQUIRE_VERIFIED_BUYER` config — when enabled, only customers with a completed order for the product can review
- Duplicate prevention — DB-level UNIQUE constraint on `(shop_id, product_id, customer_id)` prevents multiple reviews
- Honeypot field — include a hidden form field; if filled, reject silently (bots fill all fields)
- Moderation queue — all reviews start as `pending` unless auto-approved, giving merchant final control

### 2. XSS in Review Content

**Impact**: Critical — review body/title rendered on PDP could execute malicious scripts affecting all shoppers.

**Mitigations**:
- Server-side sanitization on input — strip HTML tags from `title` and `body` before storing. Use a whitelist approach (allow only plain text)
- Output encoding — when rendering reviews, use framework's built-in XSS protection (React's JSX auto-escapes, Vue's `{{ }}` auto-escapes)
- Content Security Policy (CSP) header — defense-in-depth against any sanitization bypass
- Never use `dangerouslySetInnerHTML` / `v-html` for review content
- Store sanitized content — sanitize before write, not just at read time

### 3. Fake Verified Buyer Status

**Impact**: Medium — undermines the trust signal of the verified buyer badge.

**Mitigations**:
- Server-side verification only — verified buyer status is computed on the backend by querying the orders table, never accepted from the client
- The `verified_buyer` field is set by the server during review creation — the client cannot pass this value
- Order lookup uses `shop_id` + `customer_id` + `product_id` in line items — tenant-isolated, no cross-shop leakage

### 4. Rating Manipulation

**Impact**: Medium — artificially inflating/deflating product ratings to harm competitors or self-promote.

**Mitigations**:
- One review per customer per product (DB constraint) — prevents vote stuffing from a single account
- `REQUIRE_VERIFIED_BUYER` — when enabled, limits reviews to actual purchasers
- Aggregate recalculation is server-side only — clients cannot directly modify `review_aggregates`
- Moderation queue gives merchant ability to reject suspicious patterns
- Audit trail: `created_at`, `moderated_at`, `moderated_by` on every review for investigation

### 5. Tenant Data Leakage

**Impact**: Critical — reviews from one shop visible to another shop's customers.

**Mitigations**:
- `shop_id` in every query — all SELECT, INSERT, UPDATE queries include `WHERE shop_id = $shop_id`
- Row Level Security (RLS) at DB layer as defense-in-depth
- API endpoints extract `shop_id` from authenticated session, never from client input
- Aggregate endpoint scoped to `shop_id` — no cross-tenant aggregate queries

## Input Validation Rules

| Field | Validation | Error Code |
|-------|-----------|------------|
| `product_id` | Required, non-empty string, must exist in products | `invalid_product` |
| `rating` | Required, integer, 1-5 inclusive | `invalid_rating` |
| `title` | Optional, max 200 chars, stripped of HTML | `title_too_long` |
| `body` | Required, MIN_BODY_LENGTH to MAX_BODY_LENGTH chars, stripped of HTML | `body_too_short`, `body_too_long` |
| `customer_id` | Extracted from auth session, never from request body | — |
| `shop_id` | Extracted from auth session, never from request body | — |

## Secrets Management

No block-specific secrets required. Authentication relies on the app's existing auth layer. No API keys or external service credentials needed for core review functionality.
