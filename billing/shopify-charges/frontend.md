# Frontend Patterns — Shopify App Billing & Subscriptions

> Snippets below are L3 illustrative — TypeScript interfaces + behavior commentary. Every snippet carries 4 markers (`PATTERN`, `PURPOSE`, `REFERENCE`, `ADAPT`) per `docs/SPEC_GUIDELINES.md` mục 6. The behavioral spec lives in the prose around each snippet; UI framework choice (React, Vue, Svelte, Solid) is left to the merchant — the interfaces below describe data shape and behavior only.

## Component Tree

```
BillingRoot/                       # Top-level billing UI, renders based on subscription state
├── BillingStatusBanner/           # Persistent banner: trial countdown, frozen notice, upgrade CTA
│   ├── TrialCountdown             # "X days left in trial" with progress bar
│   ├── FrozenNotice               # "Account frozen — payment failed" with reactivation link
│   └── UpgradeCTA                 # "Upgrade to Pro" button (shown on free/basic plan)
├── PlanSelection/                 # Full-page plan chooser (shown when no active subscription)
│   ├── PlanCard                   # Individual plan: name, price, features, trial badge, CTA
│   │   ├── PlanPrice              # Price display: "$29/month" or "$290/year (save 17%)"
│   │   ├── FeatureList            # Checklist of plan features
│   │   ├── TrialBadge             # "14-day free trial" badge (conditional)
│   │   └── SelectPlanButton       # "Get Started" / "Subscribe" CTA with loading state
│   └── PlanComparison             # Optional: feature comparison table across plans
├── SubscriptionDetails/           # Current plan info for settings/billing page
│   ├── CurrentPlanCard            # Plan name, status, renewal date
│   ├── UsageSummary               # This period's usage charges (if any)
│   └── ManageActions              # Upgrade, downgrade, cancel buttons
└── UpgradeModal/                  # Confirmation dialog for plan changes
    ├── PlanChangeSummary          # "Switching from Basic → Pro"
    ├── PriceChange                # Price delta and effective date
    └── ConfirmUpgradeButton       # Initiates POST /api/billing/subscribe
```

## Plan Card Component

Displays one plan with price, features, and a subscribe CTA. External contract: `interval` is the Shopify-dictated string (`EVERY_30_DAYS` | `ANNUAL`) and must be rendered as `"month"`/`"year"` in the UI, but the type field itself stays untranslated for round-tripping back to the backend.

<!-- PATTERN: plan-card -->
<!-- PURPOSE: Display a single plan with price, features, and subscribe CTA with loading state -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT:
       - Component framework: define `PlanCard` as React function component, Vue SFC, Svelte component, or Solid component — props shape stays the same
       - Currency formatting: `Intl.NumberFormat(locale, { style: 'currency', currency: plan.priceCurrency })` works in all 3 runtimes
       - Loading spinner: framework-specific (React state, Vue ref, Svelte writable) — same isSubmitting boolean
       - `onSelect`: callback prop signature is identical across frameworks; emit/dispatch in Vue/Svelte if preferred -->

```typescript
interface PlanCardProps {
  plan: {
    id: string;
    name: string;
    slug: string;
    priceAmount: number;
    priceCurrency: string;
    interval: "EVERY_30_DAYS" | "ANNUAL";   // Shopify-dictated values
    trialDays: number;
    features: string[];                      // Feature flag strings from `features` json column
    sortOrder: number;
  };
  isCurrentPlan: boolean;
  isRecommended?: boolean;
  onSelect: (planSlug: string) => void;
  isSubmitting: boolean;
}

// Behavior:
// - Display price as "$29/month" (EVERY_30_DAYS) or "$290/year" (ANNUAL)
// - Show trial badge if trialDays > 0: "14-day free trial"
// - Highlight recommended plan with border/badge (typically the middle tier)
// - isCurrentPlan → show "Current Plan" label, disable SelectPlanButton
// - onSelect fires POST /api/billing/subscribe, then redirect to confirmationUrl
// - isSubmitting → show spinner on SelectPlanButton, disable all plan cards
// - Keyboard accessible: Enter/Space on card or button triggers selection
```

## Plan Selection State Machine

External contract: in Shopify embedded apps the app runs inside an iframe. Redirecting to Shopify's confirmation URL **MUST** be done via `window.top.location.href` — `window.location.href` redirects the iframe only and the merchant gets a blank inner frame.

<!-- PATTERN: plan-selection-state -->
<!-- PURPOSE: Manage plan list fetch, subscribe POST, and iframe-breaking redirect to Shopify -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT:
       - State container: React `useReducer`, Vue `reactive`/Pinia, Svelte `writable`, Zustand, XState — same state shape, same transitions
       - HTTP client: `fetch`, `axios`, `ky`, `ofetch` — any with JSON support
       - Redirect: `window.top!.location.href = confirmationUrl` is universal; do NOT swap with framework router (this leaves the embedded iframe context)
       - Error UI: framework-specific toast/banner; copy and codes below stay the same -->

```typescript
interface PlanSelectionState {
  plans: Plan[];
  status: 'loading' | 'idle' | 'subscribing' | 'redirecting' | 'error';
  selectedPlanSlug: string | null;
  errorMessage: string | null;
}

// Lifecycle:
// 1. Mount → fetch GET /api/billing/plans → set status='idle', populate plans
// 2. Merchant clicks plan → set selectedPlanSlug, status='subscribing'
// 3. POST /api/billing/subscribe {planSlug} → receive {confirmationUrl}
// 4. status='redirecting' → window.top.location.href = confirmationUrl
//    NOTE: window.top required to break out of Shopify iframe — see external contract above
// 5. On error → status='error', show errorMessage, re-enable cards

// Error → UI copy mapping (HTTP code from backend.md):
// 404 plan_not_found       → "This plan is no longer available. Please refresh."
// 422 shopify_billing_error → "Billing error. Please try again or contact support."
// Network error             → "Something went wrong. Please check your connection and try again."
```

## Billing Status Banner

Renders a single banner at the top of the app based on subscription status and trial remaining. Priority order is strict — at most one banner visible at a time.

<!-- PATTERN: billing-status-banner -->
<!-- PURPOSE: Show persistent banner for trial/frozen/required state at top of embedded app -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT:
       - Render component: framework-specific (React `<Banner>`, Vue `<template>`, Polaris `<Banner>` if using Shopify Polaris design system) — Polaris recommended for embedded apps
       - `sessionStorage`: universal browser API — same across React/Vue/Svelte
       - Routing for upgrade CTA: framework router (React Router, Vue Router, etc.) — only target path matters: `/billing/plans` -->

```typescript
interface BillingStatusBannerProps {
  subscription: {
    status: 'active' | 'pending' | 'frozen' | 'none';
    planName: string;
    trialEndsAt: string | null;        // ISO datetime
    trialDaysRemaining: number | null; // pre-computed by backend status endpoint
    currentPeriodEnd: string | null;
  } | null;
}

// Render priority (only one banner shown at a time):
// 1. status='frozen' → error banner: "Your account is frozen due to a payment issue.
//    Update your payment method in Shopify to restore access."
//    → Link to Shopify billing settings
// 2. trialDaysRemaining !== null && trialDaysRemaining <= 7 →
//    warning banner: "Your trial ends in {N} day(s). Subscribe to keep access."
//    → "Choose a Plan" button → navigate to /billing/plans
// 3. trialDaysRemaining !== null && trialDaysRemaining > 7 →
//    info banner: "You have {N} days left in your trial."
//    → Dismissible (store dismissed=true in sessionStorage)
// 4. status='none' && BILLING_REQUIRED →
//    error banner: "A subscription is required. Choose a plan to continue."
//    → "See Plans" button → navigate to /billing/plans
// 5. All other cases → null (no banner)
```

## Upgrade / Downgrade Flow

Plan change is the SAME flow as initial subscribe: a new `appSubscriptionCreate` mutation; Shopify cancels the old subscription automatically when the merchant approves the new one.

<!-- PATTERN: plan-change-flow -->
<!-- PURPOSE: Guide merchant through upgrade/downgrade via the standard subscribe flow -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT:
       - Modal/dialog: framework-specific (Polaris `<Modal>`, headless UI, custom) — props shape unchanged
       - Effective-date prose: Shopify handles proration automatically; keep messaging neutral about exact $ amount
       - `onConfirm` → call same POST /api/billing/subscribe as plan-selection-state pattern -->

```typescript
interface UpgradeModalProps {
  currentPlan: Plan;
  targetPlan: Plan;
  onConfirm: () => void;
  onCancel: () => void;
  isSubmitting: boolean;
}

// Display:
// - "Switch from {currentPlan.name} to {targetPlan.name}"
// - Price difference: "Your new monthly charge will be ${targetPlan.priceAmount}/month"
// - Proration note: "You'll be charged a prorated amount for the remainder of this billing period"
// - If upgrading (higher price): "Your new features are available immediately after approval"
// - If downgrading (lower price): "Your current features remain until the end of this billing period"
// - Confirm → POST /api/billing/subscribe {planSlug: targetPlan.slug}
//   NOTE: Creates a new subscription — Shopify cancels the old one automatically on approval
```

## Subscription Details

<!-- PATTERN: subscription-details -->
<!-- PURPOSE: Show current plan info in settings or billing management page -->
<!-- REFERENCE: language=typescript framework=agnostic -->
<!-- ADAPT:
       - Date formatting: `Intl.DateTimeFormat(locale, { dateStyle: 'medium' })` — universal; for relative ("3 days from now") use date-fns/luxon/dayjs
       - Status badge color mapping: project design system (Polaris `<Badge tone="success" />`, Tailwind classes, etc.) — colors stated below are semantic
       - Cancel confirmation: framework-specific `confirm()` or modal — copy stays the same -->

```typescript
interface SubscriptionDetailsProps {
  subscription: {
    planName: string;
    planSlug: string;
    status: string;
    priceAmount: number;
    priceCurrency: string;
    interval: string;
    activatedAt: string;
    trialEndsAt: string | null;
    currentPeriodEnd: string | null;
    features: string[];
  };
  onUpgrade: () => void;
  onCancel: () => void;
}

// Display:
// - Plan name + status badge (Active = green, Frozen = red, Cancelled = grey)
// - "Next billing date: {formatDate(currentPeriodEnd)}" or "Trial ends: {formatDate(trialEndsAt)}"
// - Feature list matching current plan
// - "Upgrade Plan" button → navigate to /billing/plans or open UpgradeModal
// - "Cancel Subscription" button → show confirmation dialog before proceeding
//   Cancel confirmation: "Are you sure? You'll lose access at the end of your billing period."
//
// Fetch data: GET /api/billing/status on mount; refresh after any plan action (subscribe, cancel, upgrade)
```

## UI/UX States

| State | Visual | Behavior |
|-------|--------|----------|
| Loading plans | Skeleton cards (3 placeholders matching card height) | Fetch on mount |
| Plans loaded | Plan cards with prices and features | User can select |
| Subscribing | Selected card shows spinner, all cards disabled | POST in progress |
| Redirecting | Full-page "Redirecting to Shopify..." overlay | `window.top` redirect imminent |
| Subscription error | Red inline error below plan cards, cards re-enabled | Retry available |
| Active subscription | No plan selection shown — status banner hidden | Normal app use |
| Trial active — many days | Dismissible info banner | `sessionStorage` tracks dismissed |
| Trial active — few days | Non-dismissible warning banner | Always visible ≤7 days |
| Frozen | Persistent error banner, all features disabled | No dismiss |
| Pending | Info notice: "Awaiting your approval on Shopify" | Auto-poll or reload prompt |

## Anti-patterns

**DON'T** redirect using `window.location.href` inside a Shopify embedded app — this redirects the iframe, not the top window. Use `window.top.location.href = confirmationUrl` to break out of the iframe and navigate to Shopify's charge approval page.

**DON'T** show plan prices fetched from the client or hardcoded in the frontend. Always display prices from `GET /api/billing/plans` — prices come from the database, not from client config.

**DON'T** assume approval after the redirect back from Shopify. The `callback` endpoint must verify with the Shopify API. Do not optimistically update subscription status in the UI before the backend confirms activation.

**DON'T** allow the cancel button to immediately cancel without confirmation. Cancellation is irreversible until the period ends — always show a confirmation dialog with clear consequence messaging.

**DON'T** poll `GET /api/billing/status` on a tight loop for pending subscriptions. Show a manual "Refresh" button or a one-time delayed check (e.g., after 5s) rather than aggressive polling that wastes API calls.

**DON'T** render the plan selection UI inside the normal app layout when `subscription_required` is returned. Show a dedicated full-screen plan selection page — the merchant cannot use the app until they subscribe.
