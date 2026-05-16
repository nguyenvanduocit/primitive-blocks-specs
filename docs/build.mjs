#!/usr/bin/env node
// Static site generator for the Primitive Block Library.
// Run from repo root:  node docs/build.mjs
// Outputs:
//   docs/index.html
//   docs/assets/style.css
//   docs/blocks/<block-id>.html  (one file per block)
//
// To add a block: append an entry to BLOCKS below and re-run.

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DOCS = __dirname;

const REPO_HTTPS = "https://github.com/nguyenvanduocit/primitive-blocks-specs";
const REPO_BLOB = `${REPO_HTTPS}/blob/main`;
const REPO_TREE = `${REPO_HTTPS}/tree/main`;

// ============================================================================
// DATA
// ============================================================================
const BLOCKS = [
  {
    id: "auth.google-login",
    name: "Login with Google",
    category: "auth",
    folder: "auth/google-login",
    version: "1.0.0",
    complexity: "medium",
    effort: "~45 min",
    tags: ["authentication", "oauth", "google", "social-login"],
    prerequisites: [],
    summary: "Google Sign-In for end users. Handles the OAuth handshake, persists sessions, and ships login, session-persistence, protected-route, and logout primitives without password management.",
    use: [
      "User says &ldquo;login&rdquo;, &ldquo;sign in&rdquo;, &ldquo;Google login&rdquo;.",
      "App needs protected routes for authenticated users only.",
      "Merchant wants visibility into who is using the app."
    ],
    avoid: [
      "Fully public app with no authentication needed.",
      "Username/password login &mdash; use a different block.",
      "Embedded Shopify app &mdash; use <code>auth.shopify-session-token</code>."
    ],
    tables: [
      { name: "users", desc: "Identity record: email, Google sub, role, restricted domain, last login." },
      { name: "sessions", desc: "Crypto-random tokens with expiry, user-agent, and IP for revocation." }
    ],
    files: ["README.md", "security.md", "login.feature", "session.feature", "fixtures/google-user.json", "fixtures/google-tokens.json", "acceptance.md"]
  },
  {
    id: "auth.shopify-oauth",
    name: "Shopify App Installation & OAuth",
    category: "auth",
    folder: "auth/shopify-oauth",
    version: "1.0.0",
    complexity: "medium",
    effort: "~45 min",
    tags: ["shopify", "oauth", "installation", "access-token", "embedded-app"],
    prerequisites: [],
    summary: "The OAuth handshake every Shopify app must implement. Merchant approves install, app exchanges authorization code for an offline access token, and the token is persisted for Admin API access.",
    use: [
      "App needs to be installed on a Shopify store.",
      "Mentions &ldquo;shopify app&rdquo;, &ldquo;install app&rdquo;, &ldquo;oauth&rdquo;, &ldquo;access token&rdquo;.",
      "App needs to call the Shopify Admin API on behalf of a merchant."
    ],
    avoid: [
      "Building a Shopify theme &mdash; no OAuth needed.",
      "Building a sales channel &mdash; different auth flow.",
      "Need per-request auth for an embedded app &mdash; use <code>auth.shopify-session-token</code>."
    ],
    tables: [
      { name: "shops", desc: "Merchant record with encrypted access token, granted scopes, install/uninstall timestamps." },
      { name: "oauth_nonces", desc: "Single-use CSRF tokens for the OAuth callback (5 min TTL)." }
    ],
    files: ["README.md", "backend.md", "security.md", "install-flow.feature", "uninstall.feature", "security.feature", "fixtures/oauth-callback.json", "fixtures/shop-records.json", "acceptance.md"]
  },
  {
    id: "auth.shopify-session-token",
    name: "Shopify Session Token Verification",
    category: "auth",
    folder: "auth/shopify-session-token",
    version: "1.0.0",
    complexity: "low",
    effort: "~30 min",
    tags: ["shopify", "session-token", "jwt", "app-bridge", "embedded"],
    prerequisites: ["auth.shopify-oauth"],
    summary: "Middleware that verifies the short-lived JWT issued by Shopify App Bridge for every request from the embedded app. Validates signature, claims, and attaches shop context to the request.",
    use: [
      "Building an embedded Shopify app inside the Admin iframe.",
      "Any API endpoint called by the embedded frontend.",
      "Mentions &ldquo;session token&rdquo;, &ldquo;app bridge&rdquo;, &ldquo;jwt verification&rdquo;."
    ],
    avoid: [
      "Non-embedded storefronts &mdash; use <code>integration.shopify-app-proxy</code>.",
      "Webhook handlers &mdash; HMAC body signing, different flow.",
      "Server-to-server calls when you already hold an offline access token."
    ],
    tables: [
      { name: "shops", desc: "Read-only consumer. Owned by auth.shopify-oauth.", shared: true }
    ],
    files: ["README.md", "backend.md", "security.md", "session-token-verification.feature", "middleware-integration.feature", "fixtures/session-tokens.json", "acceptance.md"]
  },
  {
    id: "billing.shopify-charges",
    name: "Shopify App Billing & Subscriptions",
    category: "billing",
    folder: "billing/shopify-charges",
    version: "1.0.0",
    complexity: "high",
    effort: "~90 min",
    tags: ["shopify", "billing", "subscriptions", "charges", "monetization", "recurring"],
    prerequisites: ["auth.shopify-session-token"],
    summary: "Recurring subscriptions, one-time charges, and usage-based billing through the Shopify Billing API &mdash; the only allowed channel to monetize a Shopify App Store listing. Handles the approve-activate lifecycle and feature gating.",
    use: [
      "App needs to charge merchants for access.",
      "Mentions &ldquo;billing&rdquo;, &ldquo;subscription&rdquo;, &ldquo;monetize&rdquo;, &ldquo;trial&rdquo;, &ldquo;usage-based&rdquo;.",
      "App needs feature gating by subscription tier."
    ],
    avoid: [
      "Building a free app with no monetization.",
      "Charging shoppers &mdash; that&rsquo;s the Shopify Payments API.",
      "Non-Shopify payment processor &mdash; App Store requires Shopify Billing."
    ],
    tables: [
      { name: "billing_plans", desc: "Plan catalog: price, currency, interval, trial days, feature flags, sort order, active flag." },
      { name: "shop_subscriptions", desc: "Per-shop subscription lifecycle with status state machine and Shopify charge GID." },
      { name: "usage_records", desc: "Idempotent usage-based charges, keyed by idempotency_key against Shopify usage GID." }
    ],
    files: ["README.md", "backend.md", "frontend.md", "security.md", "plan-selection.feature", "subscription-lifecycle.feature", "usage-billing.feature", "plan-gating.feature", "fixtures/billing-plans.json", "fixtures/shopify-billing-responses.json", "acceptance.md"]
  },
  {
    id: "compliance.shopify-gdpr",
    name: "Shopify GDPR Mandatory Webhooks",
    category: "compliance",
    folder: "compliance/shopify-gdpr",
    version: "1.0.0",
    complexity: "low",
    effort: "~30 min",
    tags: ["shopify", "gdpr", "privacy", "data-erasure", "mandatory"],
    prerequisites: ["webhooks.shopify-webhooks"],
    summary: "The three GDPR webhook endpoints every Shopify App Store submission must implement: customers/data_request, customers/redact, and shop/redact. Missing or wrong implementation = rejected review.",
    use: [
      "Any app submitted to the Shopify App Store (mandatory).",
      "Mentions &ldquo;GDPR&rdquo;, &ldquo;privacy webhooks&rdquo;, &ldquo;data erasure&rdquo;.",
      "App stores any customer PII."
    ],
    avoid: [
      "Building a Shopify theme &mdash; not subject to these webhooks.",
      "Internal tooling never published to the App Store.",
      "Apps that provably store zero customer data (rare in practice)."
    ],
    tables: [
      { name: "gdpr_requests", desc: "Audit trail with request_type enum, idempotency by shopify_request_id, status state machine. Survives shop deletion via ON DELETE SET NULL." }
    ],
    files: ["README.md", "backend.md", "security.md", "data-request.feature", "customer-redact.feature", "shop-redact.feature", "fixtures/gdpr-payloads.json", "acceptance.md"]
  },
  {
    id: "data.shopify-metafields",
    name: "Shopify Metafields",
    category: "data",
    folder: "data/shopify-metafields",
    version: "1.0.0",
    complexity: "medium",
    effort: "~60 min",
    tags: ["shopify", "metafields", "custom-data", "graphql", "embedded-app"],
    prerequisites: ["auth.shopify-session-token"],
    summary: "Attach app-defined custom data to Shopify resources (products, orders, customers, shop). Definitions live locally for validation; values live in Shopify via GraphQL &mdash; the source of truth never diverges.",
    use: [
      "App needs to extend a Shopify resource with custom attributes.",
      "Mentions &ldquo;metafields&rdquo;, &ldquo;custom data&rdquo;, &ldquo;extend Shopify model&rdquo;.",
      "Data logically belongs to a Shopify resource, not your own domain."
    ],
    avoid: [
      "App-internal data with no Shopify resource relationship.",
      "Large blobs or binary data &mdash; use file uploads.",
      "Data requiring complex querying &mdash; metafield filtering is limited."
    ],
    tables: [
      { name: "metafield_definitions", desc: "Local registry of definitions registered in Shopify (namespace, key, owner_type, type). Values themselves stay in Shopify." }
    ],
    files: ["README.md", "backend.md", "security.md", "definition-sync.feature", "read-write.feature", "type-validation.feature", "fixtures/metafield-definitions.json", "fixtures/metafield-values.json", "acceptance.md"]
  },
  {
    id: "integration.shopify-app-proxy",
    name: "Shopify App Proxy",
    category: "integration",
    folder: "integration/shopify-app-proxy",
    version: "1.0.0",
    complexity: "medium",
    effort: "~45 min",
    tags: ["shopify", "app-proxy", "storefront", "liquid"],
    prerequisites: ["auth.shopify-oauth"],
    summary: "Serve app-generated content (HTML, JSON, or Liquid) under the merchant&rsquo;s own storefront domain. Shopify forwards proxied requests &mdash; the app verifies the signature and responds with the appropriate content type.",
    use: [
      "App surfaces content on the storefront, not just the admin.",
      "Mentions &ldquo;storefront widget&rdquo;, &ldquo;liquid template&rdquo;, &ldquo;/apps/ URL&rdquo;.",
      "Content needs to live under the merchant&rsquo;s domain."
    ],
    avoid: [
      "Content only needed in the admin.",
      "Building a headless storefront &mdash; use Storefront API directly.",
      "Need customer auth on the endpoint &mdash; proxy is always public."
    ],
    tables: [
      { name: "shops", desc: "Read-only lookup by shop_domain query param. Owned by auth.shopify-oauth.", shared: true }
    ],
    files: ["README.md", "backend.md", "security.md", "signature-verification.feature", "response-types.feature", "storefront-integration.feature", "fixtures/proxy-requests.json", "acceptance.md"]
  },
  {
    id: "messaging.transactional-email",
    name: "Send Transactional Email",
    category: "messaging",
    folder: "messaging/transactional-email",
    version: "1.0.0",
    complexity: "medium",
    effort: "~60 min",
    tags: ["email", "transactional", "notifications", "templates", "resend", "sendgrid"],
    prerequisites: [],
    summary: "Event-triggered email delivery with Handlebars templates, idempotent send keys, provider retries, suppression list for bounces and complaints, and a full delivery log. Provider-agnostic adapter.",
    use: [
      "App needs event-driven email (order placed, signup, shipping).",
      "Mentions &ldquo;email&rdquo;, &ldquo;notification&rdquo;, &ldquo;order confirmation&rdquo;.",
      "Merchant wants to manage templates via admin UI."
    ],
    avoid: [
      "Marketing or bulk email campaigns &mdash; use a marketing block.",
      "SMS or push notifications.",
      "In-app notifications only with no email."
    ],
    tables: [
      { name: "email_templates", desc: "Handlebars subject/body templates, per-shop overrides or platform defaults, active flag." },
      { name: "email_log", desc: "Every send attempt: idempotency_key, status, provider_message_id, error, metadata." },
      { name: "email_suppressions", desc: "Bounces, complaints, manual suppression. Recipients are blocked from further sends." }
    ],
    files: ["README.md", "backend.md", "security.md", "send-email.feature", "template-management.feature", "fixtures/welcome-template.json", "fixtures/order-confirmation-template.json", "fixtures/provider-response.json", "acceptance.md"]
  },
  {
    id: "operations.shopify-bulk",
    name: "Shopify Bulk Operations",
    category: "operations",
    folder: "operations/shopify-bulk",
    version: "1.0.0",
    complexity: "high",
    effort: "~75 min",
    tags: ["shopify", "bulk", "graphql", "async", "large-datasets", "jsonl"],
    prerequisites: ["auth.shopify-session-token"],
    summary: "Async bulk query and mutation pipeline. Submit a GraphQL operation to Shopify, listen for the completion webhook, download the JSONL result, and process records with the parent-child convention &mdash; without exhausting rate limits.",
    use: [
      "Read or write more than ~200 records at once.",
      "Mentions &ldquo;bulk export/import&rdquo;, &ldquo;JSONL&rdquo;, &ldquo;bulkOperationRunQuery&rdquo;.",
      "Need to sync the full Shopify catalog to an external system."
    ],
    avoid: [
      "Fewer than ~200 records &mdash; use paginated queries.",
      "Real-time operations &mdash; bulk ops are async (minutes to hours).",
      "Per-record error handling &mdash; bulk mutation errors aggregate."
    ],
    tables: [
      { name: "bulk_operations", desc: "Lifecycle of every submitted operation: type, status, query_text, result_url, error_code, object_count, file_size." }
    ],
    files: ["README.md", "backend.md", "security.md", "bulk-query.feature", "bulk-mutation.feature", "status-tracking.feature", "result-processing.feature", "fixtures/bulk-operations.json", "fixtures/sample-jsonl.json", "acceptance.md"]
  },
  {
    id: "ugc.product-reviews",
    name: "Product Reviews",
    category: "ugc",
    folder: "ugc/product-reviews",
    version: "1.0.0",
    complexity: "medium",
    effort: "~60 min",
    tags: ["reviews", "ugc", "social-proof", "moderation", "ratings"],
    prerequisites: [],
    summary: "Shopper-submitted product reviews with rating, optional title and body, verified-buyer attribution, moderation workflow, auto-approve threshold, and a denormalized aggregate for fast PDP rendering.",
    use: [
      "Mentions &ldquo;reviews&rdquo;, &ldquo;ratings&rdquo;, &ldquo;social proof&rdquo;.",
      "Product pages need customer feedback enrichment.",
      "Merchant wants moderation control over UGC."
    ],
    avoid: [
      "Q&amp;A on products &mdash; use a different UGC block.",
      "Site-wide testimonials &mdash; not product-scoped.",
      "Photo or video-only review &mdash; extend this block with media."
    ],
    tables: [
      { name: "reviews", desc: "Per-customer-per-product review with status state machine, server-computed verified_buyer, moderation metadata." },
      { name: "review_aggregates", desc: "Denormalized rollup updated transactionally on moderation actions. Cheap reads, eventual staleness avoided." }
    ],
    files: ["README.md", "frontend.md", "backend.md", "security.md", "submit-review.feature", "moderate-review.feature", "display-reviews.feature", "fixtures/sample-reviews.json", "fixtures/aggregate.json", "acceptance.md"]
  },
  {
    id: "webhooks.shopify-webhooks",
    name: "Shopify Webhook Management",
    category: "webhooks",
    folder: "webhooks/shopify-webhooks",
    version: "1.0.0",
    complexity: "medium",
    effort: "~60 min",
    tags: ["shopify", "webhooks", "hmac", "events", "real-time", "idempotency"],
    prerequisites: ["auth.shopify-oauth"],
    summary: "Subscribe to Shopify events, verify each delivery with HMAC-SHA256, and process each payload exactly once using the X-Shopify-Webhook-Id idempotency key. The event backbone other blocks (GDPR) depend on.",
    use: [
      "App needs to react to Shopify events in real time.",
      "Mentions &ldquo;webhook&rdquo;, &ldquo;orders create&rdquo;, &ldquo;APP_UNINSTALLED&rdquo;.",
      "Downstream blocks like <code>compliance.shopify-gdpr</code> require this."
    ],
    avoid: [
      "One-time data sync &mdash; use <code>operations.shopify-bulk</code>.",
      "Storefront data without real-time need &mdash; poll the Admin API.",
      "Building a Shopify theme."
    ],
    tables: [
      { name: "webhook_subscriptions", desc: "Per-shop topic subscription with callback URL and Shopify GraphQL GID." },
      { name: "webhook_deliveries", desc: "Idempotent delivery log keyed by X-Shopify-Webhook-Id with status state machine and forensic payload hash." }
    ],
    files: ["README.md", "backend.md", "security.md", "webhook-registration.feature", "webhook-receiving.feature", "webhook-idempotency.feature", "fixtures/webhook-payloads.json", "fixtures/webhook-headers.json", "acceptance.md"]
  }
];

// ============================================================================
// CSS — shared between landing and per-block pages
// ============================================================================
const CSS = `:root {
  --bg: #0a0a0b;
  --bg-elev: #131316;
  --bg-elev-2: #1a1a1f;
  --border: #25252b;
  --border-strong: #34343d;
  --text: #ededf0;
  --text-muted: #9a9aa8;
  --text-dim: #6a6a78;
  --accent: #fb923c;
  --accent-soft: rgba(251, 146, 60, 0.12);
  --accent-strong: #f97316;
  --green: #22c55e;
  --yellow: #eab308;
  --red: #ef4444;
  --blue: #60a5fa;
  --purple: #a78bfa;
  --pink: #f472b6;
  --teal: #2dd4bf;
  --mono: "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, monospace;
  --sans: "Inter", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --radius: 10px;
  --radius-lg: 16px;
  --max-w: 1180px;
}
* { box-sizing: border-box; }
html, body {
  margin: 0; padding: 0;
  background: var(--bg);
  color: var(--text);
  font-family: var(--sans);
  font-size: 15px;
  line-height: 1.6;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
  scroll-behavior: smooth;
}
body::before {
  content: "";
  position: fixed; inset: 0;
  background:
    radial-gradient(ellipse 80% 50% at 50% -20%, rgba(251, 146, 60, 0.10), transparent 70%),
    radial-gradient(ellipse 60% 40% at 100% 100%, rgba(167, 139, 250, 0.06), transparent 70%);
  pointer-events: none;
  z-index: 0;
}
main, header, footer { position: relative; z-index: 1; }
a { color: var(--accent); text-decoration: none; }
a:hover { color: var(--accent-strong); text-decoration: underline; text-underline-offset: 3px; }
code, pre { font-family: var(--mono); font-size: 0.875em; }
code { background: var(--bg-elev-2); padding: 1px 6px; border-radius: 4px; border: 1px solid var(--border); }
pre code { background: transparent; padding: 0; border: 0; }
h1, h2, h3, h4 { font-family: var(--sans); font-weight: 700; letter-spacing: -0.02em; line-height: 1.2; margin: 0 0 0.5em 0; }
h1 { font-size: clamp(2.5rem, 5vw, 4rem); font-weight: 800; letter-spacing: -0.035em; }
h2 { font-size: clamp(1.6rem, 3vw, 2.25rem); }
h3 { font-size: 1.25rem; }
h4 { font-size: 1rem; }

/* HEADER */
header.site {
  position: sticky; top: 0;
  background: rgba(10, 10, 11, 0.85);
  backdrop-filter: saturate(180%) blur(14px);
  -webkit-backdrop-filter: saturate(180%) blur(14px);
  border-bottom: 1px solid var(--border);
  z-index: 50;
}
.nav { max-width: var(--max-w); margin: 0 auto; padding: 14px 24px; display: flex; align-items: center; justify-content: space-between; gap: 24px; }
.brand { font-weight: 700; font-size: 0.95rem; color: var(--text); letter-spacing: -0.01em; text-decoration: none; display: flex; align-items: center; gap: 10px; }
.brand:hover { color: var(--text); text-decoration: none; }
.brand-mark { width: 22px; height: 22px; border-radius: 6px; background: linear-gradient(135deg, var(--accent), #c084fc); display: grid; place-items: center; color: #0a0a0b; font-family: var(--mono); font-weight: 700; font-size: 12px; }
.nav-links { display: flex; gap: 22px; list-style: none; margin: 0; padding: 0; font-size: 0.875rem; }
.nav-links a { color: var(--text-muted); text-decoration: none; transition: color 0.15s ease; }
.nav-links a:hover { color: var(--text); text-decoration: none; }
.nav-links a.github { color: var(--text); background: var(--bg-elev); border: 1px solid var(--border); padding: 6px 12px; border-radius: 6px; }
.nav-links a.github:hover { background: var(--bg-elev-2); border-color: var(--border-strong); }
@media (max-width: 640px) { .nav-links li:not(:last-child) { display: none; } }

main { padding: 0 24px; }
section { max-width: var(--max-w); margin: 0 auto; padding: 96px 0; }
section + section { border-top: 1px solid var(--border); }

/* HERO */
.hero { padding: 120px 0 80px; text-align: center; }
.hero .eyebrow { display: inline-block; font-family: var(--mono); font-size: 0.75rem; color: var(--accent); background: var(--accent-soft); border: 1px solid rgba(251, 146, 60, 0.25); padding: 5px 12px; border-radius: 999px; margin-bottom: 28px; letter-spacing: 0.05em; text-transform: uppercase; }
.hero h1 { background: linear-gradient(180deg, var(--text), #b0b0bd 100%); -webkit-background-clip: text; background-clip: text; color: transparent; margin-bottom: 24px; }
.hero .tagline { font-size: clamp(1.05rem, 1.6vw, 1.25rem); color: var(--text-muted); max-width: 720px; margin: 0 auto 40px; line-height: 1.55; }
.hero .ctas { display: flex; gap: 12px; justify-content: center; flex-wrap: wrap; margin-bottom: 64px; }
.btn { font-family: var(--sans); font-weight: 500; font-size: 0.9rem; padding: 10px 18px; border-radius: 8px; border: 1px solid var(--border-strong); background: var(--bg-elev); color: var(--text); cursor: pointer; text-decoration: none; transition: all 0.15s ease; display: inline-flex; align-items: center; gap: 8px; }
.btn:hover { background: var(--bg-elev-2); border-color: var(--accent); text-decoration: none; color: var(--text); }
.btn.primary { background: var(--accent); border-color: var(--accent); color: #1a0d00; font-weight: 600; }
.btn.primary:hover { background: var(--accent-strong); border-color: var(--accent-strong); color: #1a0d00; }
.hero-stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; max-width: 760px; margin: 0 auto; }
.hero-stats .stat { border: 1px solid var(--border); border-radius: var(--radius); padding: 18px 14px; background: var(--bg-elev); }
.hero-stats .stat .num { font-family: var(--mono); font-size: 1.6rem; font-weight: 700; color: var(--accent); letter-spacing: -0.02em; }
.hero-stats .stat .label { font-size: 0.8rem; color: var(--text-muted); margin-top: 4px; }
@media (max-width: 640px) { .hero-stats { grid-template-columns: repeat(2, 1fr); } }

/* SECTION HEADERS */
.section-header { margin-bottom: 48px; max-width: 760px; }
.section-header .eyebrow { font-family: var(--mono); font-size: 0.78rem; color: var(--accent); letter-spacing: 0.08em; text-transform: uppercase; margin-bottom: 12px; }
.section-header p { color: var(--text-muted); font-size: 1.05rem; margin: 8px 0 0; }

/* COMPARE CARDS */
.compare { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 32px 0 48px; }
@media (max-width: 720px) { .compare { grid-template-columns: 1fr; } }
.compare .card { border: 1px solid var(--border); border-radius: var(--radius-lg); padding: 28px; background: var(--bg-elev); }
.compare .card.old { opacity: 0.78; }
.compare .card.new { border-color: var(--border-strong); }
.compare .card h3 { margin-bottom: 18px; font-size: 1.1rem; }
.compare .card h3 .tag { display: inline-block; font-family: var(--mono); font-size: 0.7rem; font-weight: 500; padding: 2px 8px; border-radius: 4px; margin-left: 8px; vertical-align: middle; }
.compare .card.old h3 .tag { background: rgba(239, 68, 68, 0.1); color: #fca5a5; border: 1px solid rgba(239, 68, 68, 0.25); }
.compare .card.new h3 .tag { background: var(--accent-soft); color: var(--accent); border: 1px solid rgba(251, 146, 60, 0.3); }
.compare ul { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 10px; }
.compare li { padding-left: 24px; position: relative; font-size: 0.92rem; color: var(--text-muted); }
.compare .card.new li { color: var(--text); }
.compare li::before { content: ""; position: absolute; left: 4px; top: 0.65em; width: 8px; height: 8px; border-radius: 2px; background: var(--border-strong); }
.compare .card.new li::before { background: var(--accent); }

/* LAYERS */
.layers { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-top: 32px; }
@media (max-width: 800px) { .layers { grid-template-columns: 1fr; } }
.layer { border: 1px solid var(--border); border-radius: var(--radius); padding: 22px; background: var(--bg-elev); position: relative; overflow: hidden; }
.layer::before { content: ""; position: absolute; top: 0; left: 0; right: 0; height: 2px; background: linear-gradient(90deg, transparent, var(--c, var(--accent)), transparent); }
.layer:nth-child(1) { --c: var(--green); }
.layer:nth-child(2) { --c: var(--blue); }
.layer:nth-child(3) { --c: var(--purple); }
.layer .layer-num { font-family: var(--mono); font-weight: 600; color: var(--c); font-size: 0.78rem; letter-spacing: 0.05em; margin-bottom: 8px; }
.layer h4 { margin-bottom: 12px; }
.layer p { color: var(--text-muted); font-size: 0.88rem; margin: 0 0 12px; }
.layer .verdict { display: inline-block; font-family: var(--mono); font-size: 0.72rem; padding: 3px 9px; background: rgba(255,255,255,0.04); border: 1px solid var(--border); border-radius: 4px; color: var(--c); }

/* FILTER BAR */
.filter-bar { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 32px; padding: 6px; background: var(--bg-elev); border: 1px solid var(--border); border-radius: 12px; width: fit-content; max-width: 100%; overflow-x: auto; }
.filter-pill { font-family: var(--sans); font-size: 0.85rem; font-weight: 500; padding: 7px 14px; border-radius: 8px; border: 0; background: transparent; color: var(--text-muted); cursor: pointer; white-space: nowrap; transition: all 0.15s ease; }
.filter-pill:hover { color: var(--text); background: rgba(255,255,255,0.04); }
.filter-pill.active { background: var(--bg-elev-2); color: var(--text); box-shadow: inset 0 0 0 1px var(--border-strong); }
.filter-pill .count { font-family: var(--mono); font-size: 0.72rem; color: var(--text-dim); margin-left: 6px; }
.filter-pill.active .count { color: var(--accent); }

/* BLOCK GRID — landing */
.block-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(360px, 100%), 1fr)); gap: 16px; }
.block-card {
  display: block;
  text-decoration: none;
  color: var(--text);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  background: var(--bg-elev);
  padding: 24px;
  transition: all 0.2s ease;
  position: relative;
  overflow: hidden;
}
.block-card::after {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: var(--radius-lg);
  border: 1px solid transparent;
  pointer-events: none;
  transition: border-color 0.2s ease;
}
.block-card:hover {
  text-decoration: none;
  color: var(--text);
  transform: translateY(-2px);
  border-color: var(--border-strong);
}
.block-card:hover::after { border-color: var(--accent); }
.block-card .row-1 { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 8px; }
.block-id { font-family: var(--mono); font-size: 0.74rem; color: var(--text-dim); letter-spacing: 0.02em; }
.cat-badge { font-family: var(--mono); font-size: 0.7rem; font-weight: 600; padding: 3px 9px; border-radius: 4px; background: var(--bg-elev-2); border: 1px solid var(--border); color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.05em; }
.cat-badge.auth { color: var(--blue); border-color: rgba(96, 165, 250, 0.25); background: rgba(96, 165, 250, 0.08); }
.cat-badge.billing { color: var(--green); border-color: rgba(34, 197, 94, 0.25); background: rgba(34, 197, 94, 0.08); }
.cat-badge.compliance { color: var(--red); border-color: rgba(239, 68, 68, 0.25); background: rgba(239, 68, 68, 0.08); }
.cat-badge.data { color: var(--purple); border-color: rgba(167, 139, 250, 0.25); background: rgba(167, 139, 250, 0.08); }
.cat-badge.integration { color: var(--teal); border-color: rgba(45, 212, 191, 0.25); background: rgba(45, 212, 191, 0.08); }
.cat-badge.messaging { color: var(--pink); border-color: rgba(244, 114, 182, 0.25); background: rgba(244, 114, 182, 0.08); }
.cat-badge.operations { color: var(--yellow); border-color: rgba(234, 179, 8, 0.25); background: rgba(234, 179, 8, 0.08); }
.cat-badge.ugc { color: var(--accent); border-color: rgba(251, 146, 60, 0.25); background: rgba(251, 146, 60, 0.08); }
.cat-badge.webhooks { color: #c084fc; border-color: rgba(192, 132, 252, 0.25); background: rgba(192, 132, 252, 0.08); }
.block-name { font-size: 1.18rem; font-weight: 700; letter-spacing: -0.015em; margin: 4px 0 12px; color: var(--text); }
.block-card .lead { color: var(--text-muted); font-size: 0.92rem; margin: 0 0 16px; line-height: 1.55; display: -webkit-box; -webkit-line-clamp: 3; line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
.block-tags { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 16px; }
.tag { font-family: var(--mono); font-size: 0.7rem; color: var(--text-muted); background: var(--bg-elev-2); border: 1px solid var(--border); padding: 2px 8px; border-radius: 4px; }
.block-meta { display: flex; gap: 16px; flex-wrap: wrap; font-size: 0.82rem; color: var(--text-muted); align-items: center; padding-top: 16px; border-top: 1px solid var(--border); }
.meta-item { display: flex; align-items: center; gap: 6px; }
.meta-item .label { color: var(--text-dim); font-family: var(--mono); font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.05em; }
.complexity { font-family: var(--mono); font-weight: 600; font-size: 0.78rem; padding: 2px 8px; border-radius: 4px; }
.complexity.low { color: var(--green); background: rgba(34, 197, 94, 0.1); }
.complexity.medium { color: var(--yellow); background: rgba(234, 179, 8, 0.1); }
.complexity.high { color: var(--red); background: rgba(239, 68, 68, 0.1); }
.block-card .arrow { position: absolute; top: 24px; right: 24px; opacity: 0; transform: translateX(-4px); transition: all 0.2s ease; color: var(--accent); font-family: var(--mono); }
.block-card:hover .arrow { opacity: 1; transform: translateX(0); }
.empty-state { text-align: center; padding: 64px 24px; color: var(--text-muted); border: 1px dashed var(--border); border-radius: var(--radius); }

/* CONSUMER FLOW */
.flow-steps { display: grid; grid-template-columns: repeat(5, 1fr); gap: 12px; margin-top: 32px; }
@media (max-width: 900px) { .flow-steps { grid-template-columns: repeat(2, 1fr); } }
@media (max-width: 480px) { .flow-steps { grid-template-columns: 1fr; } }
.flow-step { border: 1px solid var(--border); border-radius: var(--radius); padding: 18px; background: var(--bg-elev); position: relative; }
.flow-step .step-num { font-family: var(--mono); font-size: 0.72rem; font-weight: 600; color: var(--accent); letter-spacing: 0.06em; margin-bottom: 8px; }
.flow-step h4 { font-size: 0.95rem; margin-bottom: 6px; }
.flow-step p { font-size: 0.82rem; color: var(--text-muted); margin: 0; line-height: 1.5; }

/* FOOTER */
footer.site { border-top: 1px solid var(--border); padding: 48px 24px; text-align: center; color: var(--text-muted); font-size: 0.85rem; }
footer.site .footer-inner { max-width: var(--max-w); margin: 0 auto; }
footer.site p { margin: 4px 0; }
footer.site a { color: var(--text-muted); }
footer.site a:hover { color: var(--accent); }

/* ============ PER-BLOCK PAGE ============ */
.page-grid {
  max-width: var(--max-w);
  margin: 0 auto;
  padding: 48px 0 96px;
  display: grid;
  grid-template-columns: 240px 1fr;
  gap: 64px;
  align-items: start;
}
@media (max-width: 900px) { .page-grid { grid-template-columns: 1fr; gap: 24px; padding: 32px 0 64px; } }

.toc {
  position: sticky;
  top: 88px;
  font-size: 0.875rem;
}
.toc .back {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--text-muted);
  font-family: var(--mono);
  font-size: 0.78rem;
  margin-bottom: 32px;
  text-decoration: none;
  transition: color 0.15s ease;
}
.toc .back:hover { color: var(--accent); text-decoration: none; }
.toc .back::before { content: "←"; font-size: 1.1em; }
.toc-section {
  font-family: var(--mono);
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--text-dim);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  margin-bottom: 12px;
}
.toc-nav { display: flex; flex-direction: column; gap: 2px; margin-bottom: 32px; }
.toc-nav a {
  display: block;
  padding: 7px 10px;
  border-radius: 6px;
  color: var(--text-muted);
  text-decoration: none;
  font-size: 0.875rem;
  border-left: 2px solid transparent;
  margin-left: -2px;
  transition: all 0.15s ease;
}
.toc-nav a:hover { color: var(--text); background: var(--bg-elev); text-decoration: none; }
.toc-nav a.active { color: var(--accent); border-left-color: var(--accent); background: var(--accent-soft); }
.toc-meta { padding: 16px; border: 1px solid var(--border); border-radius: var(--radius); background: var(--bg-elev); display: flex; flex-direction: column; gap: 10px; }
.toc-meta .meta-row { display: flex; justify-content: space-between; align-items: center; font-size: 0.82rem; }
.toc-meta .meta-row .label { color: var(--text-dim); font-family: var(--mono); font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.05em; }
@media (max-width: 900px) { .toc { position: static; } .toc-nav { display: none; } }

.page-content { min-width: 0; }
.breadcrumb { font-family: var(--mono); font-size: 0.78rem; color: var(--text-dim); margin-bottom: 18px; letter-spacing: 0.02em; }
.breadcrumb a { color: var(--text-muted); }
.breadcrumb .sep { margin: 0 8px; color: var(--text-dim); }
.block-id-large { font-family: var(--mono); font-size: 0.85rem; color: var(--accent); background: var(--accent-soft); padding: 4px 10px; border-radius: 6px; border: 1px solid rgba(251, 146, 60, 0.25); display: inline-block; margin-bottom: 16px; }
.page-content h1 { font-size: clamp(2rem, 4vw, 3rem); margin-bottom: 20px; background: linear-gradient(180deg, var(--text), #b0b0bd 100%); -webkit-background-clip: text; background-clip: text; color: transparent; }
.page-content .lead { font-size: 1.15rem; color: var(--text-muted); line-height: 1.6; margin: 0 0 32px; max-width: 70ch; }
.page-content > .block-tags { margin-bottom: 48px; }
.page-content section { padding: 48px 0; margin: 0; max-width: none; border-top: 1px solid var(--border); }
.page-content section:first-of-type { border-top: 0; padding-top: 0; }
.page-content section h2 { font-size: 1.5rem; margin-bottom: 20px; scroll-margin-top: 96px; }
.page-content section p { color: var(--text); margin: 0 0 14px; max-width: 70ch; }
.page-content section p:last-child { margin-bottom: 0; }

.prereq-list { display: flex; flex-wrap: wrap; gap: 8px; }
.prereq-list .prereq { font-family: var(--mono); font-size: 0.82rem; color: var(--accent); background: var(--accent-soft); border: 1px solid rgba(251, 146, 60, 0.25); padding: 5px 12px; border-radius: 6px; text-decoration: none; transition: all 0.15s ease; }
.prereq-list .prereq:hover { background: rgba(251, 146, 60, 0.18); text-decoration: none; }
.prereq-list .prereq.none { background: var(--bg-elev); color: var(--text-muted); border-color: var(--border); cursor: default; }

.tables-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 12px; }
.table-card { border: 1px solid var(--border); border-radius: 10px; padding: 18px; background: var(--bg-elev); }
.table-card .table-name { font-family: var(--mono); font-size: 0.95rem; font-weight: 600; color: var(--text); margin-bottom: 8px; }
.table-card .table-desc { font-size: 0.88rem; color: var(--text-muted); line-height: 1.55; }
.table-card.shared { border-style: dashed; opacity: 0.85; }
.table-card.shared .table-name::after { content: " (shared)"; font-size: 0.72rem; color: var(--text-dim); font-weight: 400; }

.two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
@media (max-width: 700px) { .two-col { grid-template-columns: 1fr; } }
.use-card { border: 1px solid var(--border); border-radius: var(--radius); padding: 20px; background: var(--bg-elev); }
.use-card h5 { font-family: var(--mono); font-size: 0.72rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; margin: 0 0 12px; }
.use-card.yes h5 { color: var(--green); }
.use-card.no h5 { color: var(--red); }
.use-card ul { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 8px; font-size: 0.92rem; color: var(--text); }
.use-card li { padding-left: 18px; position: relative; }
.use-card li::before { content: ""; position: absolute; left: 0; top: 0.6em; width: 6px; height: 6px; border-radius: 50%; }
.use-card.yes li::before { background: var(--green); }
.use-card.no li::before { background: var(--red); }

.files-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 8px; }
.file-link { display: flex; align-items: center; gap: 10px; padding: 10px 14px; border: 1px solid var(--border); border-radius: 8px; background: var(--bg-elev); font-family: var(--mono); font-size: 0.82rem; color: var(--text-muted); text-decoration: none; transition: all 0.15s ease; }
.file-link:hover { border-color: var(--accent); color: var(--accent); background: var(--accent-soft); text-decoration: none; }
.file-link .ftype { font-size: 0.68rem; color: var(--text-dim); margin-left: auto; padding: 2px 6px; border-radius: 3px; border: 1px solid var(--border); background: var(--bg-elev-2); }
.file-link:hover .ftype { color: var(--accent); border-color: rgba(251, 146, 60, 0.4); }

.prev-next { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-top: 48px; padding-top: 48px; border-top: 1px solid var(--border); }
@media (max-width: 600px) { .prev-next { grid-template-columns: 1fr; } }
.prev-next a { display: flex; flex-direction: column; padding: 18px 20px; border: 1px solid var(--border); border-radius: var(--radius); background: var(--bg-elev); text-decoration: none; transition: all 0.15s ease; color: var(--text); }
.prev-next a:hover { border-color: var(--accent); text-decoration: none; color: var(--text); transform: translateY(-1px); }
.prev-next .label { font-family: var(--mono); font-size: 0.72rem; color: var(--text-dim); text-transform: uppercase; letter-spacing: 0.06em; margin-bottom: 6px; }
.prev-next .title { font-weight: 600; font-size: 0.95rem; }
.prev-next .next { text-align: right; }
.prev-next .placeholder { border-style: dashed; opacity: 0.4; pointer-events: none; }

.hidden { display: none !important; }
`;

// ============================================================================
// COMMON HTML CHROME
// ============================================================================
function headTags(title, description, opts = {}) {
  const cssPath = opts.cssPath || "assets/style.css";
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${title}</title>
<meta name="description" content="${description}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="${cssPath}">
</head>
<body>`;
}

function siteHeader(rootPath = "") {
  return `<header class="site">
  <nav class="nav">
    <a href="${rootPath || "./"}" class="brand">
      <span class="brand-mark">P</span>
      <span>Primitive Block Library</span>
    </a>
    <ul class="nav-links">
      <li><a href="${rootPath}#philosophy">Philosophy</a></li>
      <li><a href="${rootPath}#consume">Workflow</a></li>
      <li><a href="${rootPath}#blocks">Blocks</a></li>
      <li><a class="github" href="${REPO_HTTPS}" target="_blank" rel="noopener">GitHub</a></li>
    </ul>
  </nav>
</header>`;
}

function siteFooter() {
  return `<footer class="site">
  <div class="footer-inner">
    <p>
      Primitive Block Library &middot;
      <a href="${REPO_HTTPS}" target="_blank" rel="noopener">github.com/nguyenvanduocit/primitive-blocks-specs</a>
    </p>
    <p style="margin-top: 8px; color: var(--text-dim);">
      Read the <a href="${REPO_BLOB}/docs/SPEC_GUIDELINES.md" target="_blank" rel="noopener">Spec Guidelines</a>
      for the abstraction discipline that every block must pass.
    </p>
  </div>
</footer>`;
}

// ============================================================================
// LANDING PAGE
// ============================================================================
function renderLanding() {
  const cardsHtml = BLOCKS.map(b => `
        <a class="block-card" data-cat="${b.category}" href="blocks/${b.id}.html">
          <span class="arrow" aria-hidden="true">→</span>
          <div class="row-1">
            <span class="block-id">${b.id}</span>
            <span class="cat-badge ${b.category}">${b.category}</span>
          </div>
          <div class="block-name">${b.name}</div>
          <p class="lead">${b.summary}</p>
          <div class="block-tags">${b.tags.map(t => `<span class="tag">${t}</span>`).join("")}</div>
          <div class="block-meta">
            <div class="meta-item"><span class="label">Complexity</span><span class="complexity ${b.complexity}">${b.complexity}</span></div>
            <div class="meta-item"><span class="label">Effort</span><span>${b.effort}</span></div>
          </div>
        </a>`).join("");

  const filterPills = (() => {
    const counts = {};
    BLOCKS.forEach(b => counts[b.category] = (counts[b.category] || 0) + 1);
    const pills = [`<button class="filter-pill active" data-cat="all">All<span class="count">${BLOCKS.length}</span></button>`];
    Object.keys(counts).sort().forEach(cat => {
      pills.push(`<button class="filter-pill" data-cat="${cat}">${cat}<span class="count">${counts[cat]}</span></button>`);
    });
    return pills.join("");
  })();

  return `${headTags(
    "Primitive Block Library — AI-native feature blueprints",
    "Complete designs for features. Read by Claude Code, adapted to your stack, implemented into your codebase. Stack-agnostic specs across auth, billing, compliance, data, integration, messaging, operations, UGC, and webhooks.",
    { cssPath: "assets/style.css" }
  )}

${siteHeader("")}

<main>
  <section class="hero">
    <span class="eyebrow">Blueprints for agentic AI</span>
    <h1>Specs that build themselves.</h1>
    <p class="tagline">
      A library of complete feature designs &mdash; data models, sequence flows, security threats,
      and acceptance criteria. Claude Code reads them, understands your stack, and writes the
      implementation. Not pre-built code. Not config-driven scaffolds. Living specifications
      that any agent can compile into any codebase.
    </p>
    <div class="ctas">
      <a class="btn primary" href="#blocks">Browse the library</a>
      <a class="btn" href="${REPO_HTTPS}" target="_blank" rel="noopener">View on GitHub</a>
    </div>
    <div class="hero-stats">
      <div class="stat"><div class="num">${BLOCKS.length}</div><div class="label">Blocks</div></div>
      <div class="stat"><div class="num">9</div><div class="label">Categories</div></div>
      <div class="stat"><div class="num">3</div><div class="label">Tested stacks</div></div>
      <div class="stat"><div class="num">100%</div><div class="label">Stack-agnostic</div></div>
    </div>
  </section>

  <section id="philosophy">
    <div class="section-header">
      <div class="eyebrow">Philosophy</div>
      <h2>Don&rsquo;t solve agentic problems with classical tools.</h2>
      <p>
        Packaging features as fixed code &mdash; whether you call them &ldquo;primitives&rdquo;,
        &ldquo;components&rdquo;, or &ldquo;modules&rdquo; &mdash; carries every classical problem
        forward: customization is limited to predefined config, composition breaks unpredictably,
        versioning multiplies. When an agent can read filesystems, run commands, and iterate,
        let it solve the problem directly. A blueprint is knowledge, not code.
      </p>
    </div>

    <div class="compare">
      <div class="card old">
        <h3>Pre-built code <span class="tag">old paradigm</span></h3>
        <ul>
          <li>Rigid &mdash; only customizable through config JSON</li>
          <li>Fits one fixed runtime; merchant must match it</li>
          <li>Bugs live inside the pre-built package &mdash; hard to debug</li>
          <li>New feature requires writing new code from scratch</li>
          <li>Surface area shrinks as integrations multiply</li>
          <li>Fixed ceiling: capability equals what was written</li>
        </ul>
      </div>
      <div class="card new">
        <h3>Blueprint <span class="tag">new paradigm</span></h3>
        <ul>
          <li>Flexible &mdash; the agent adapts the entire implementation</li>
          <li>Fits any stack: SQL family, frameworks, runtimes</li>
          <li>Bugs are fixed in-place inside the merchant&rsquo;s codebase</li>
          <li>New feature is a new spec &mdash; markdown, not code</li>
          <li>Surface area grows with each iteration of the agent</li>
          <li>No ceiling: better models &times; better specs &times; better tests</li>
        </ul>
      </div>
    </div>

    <h3 style="margin-top: 48px;">Three layers in every spec</h3>
    <p style="color: var(--text-muted); max-width: 700px; margin: 6px 0 0;">
      The tension of the blueprint paradigm: too abstract and the agent has no guidance;
      too concrete and the spec becomes code in markdown. Every spec resolves it with three layers.
    </p>
    <div class="layers">
      <div class="layer">
        <div class="layer-num">L1 &mdash; SEMANTIC</div>
        <h4>What &amp; Why</h4>
        <p>Data model, sequence flows, state machines, business invariants, external protocol contracts, threats and mitigations.</p>
        <span class="verdict">Maximally concrete</span>
      </div>
      <div class="layer">
        <div class="layer-num">L2 &mdash; MECHANISM</div>
        <h4>How</h4>
        <p>Framework, ORM, SQL dialect, test runner, error-handling style, file convention. The agent picks all of this.</p>
        <span class="verdict">Abstract &mdash; agent decides</span>
      </div>
      <div class="layer">
        <div class="layer-num">L3 &mdash; ILLUSTRATIVE</div>
        <h4>Reference</h4>
        <p>Code snippets &le;30 lines, each tagged with <code>PATTERN</code> / <code>PURPOSE</code> / <code>REFERENCE</code> / <code>ADAPT</code> markers.</p>
        <span class="verdict">Concrete but marked</span>
      </div>
    </div>
  </section>

  <section id="consume">
    <div class="section-header">
      <div class="eyebrow">Workflow</div>
      <h2>How an agent consumes a block.</h2>
      <p>
        Claude Code &mdash; running in the merchant&rsquo;s workspace with full filesystem access &mdash;
        treats every block as a reference document. It reads, understands the stack, adapts, and verifies.
      </p>
    </div>
    <div class="flow-steps">
      <div class="flow-step"><div class="step-num">STEP 01</div><h4>Discover</h4><p>Match the merchant&rsquo;s request against the library by tag, category, and overview.</p></div>
      <div class="flow-step"><div class="step-num">STEP 02</div><h4>Interview</h4><p>Surface configuration decisions, lock business choices, present scenarios as plain language.</p></div>
      <div class="flow-step"><div class="step-num">STEP 03</div><h4>Clone &amp; customize</h4><p>Copy the block into the project as a customized blueprint &mdash; the source library stays untouched.</p></div>
      <div class="flow-step"><div class="step-num">STEP 04</div><h4>Implement</h4><p>Translate the spec into code that follows the merchant&rsquo;s conventions and frameworks.</p></div>
      <div class="flow-step"><div class="step-num">STEP 05</div><h4>Verify</h4><p>Run the acceptance checklist: migrations, tests, type-check, lint, security mitigations.</p></div>
    </div>
  </section>

  <section id="blocks">
    <div class="section-header">
      <div class="eyebrow">The library</div>
      <h2>${BLOCKS.length} blocks, ready to compile.</h2>
      <p>Click any block to open its full spec page with data model, prerequisites, use/avoid guidance, and direct links to every file in the spec folder.</p>
    </div>

    <div class="filter-bar" role="tablist" aria-label="Filter blocks by category">${filterPills}</div>

    <div class="block-grid" id="block-grid">${cardsHtml}
    </div>
    <div class="empty-state hidden" id="empty-state">No blocks match this category yet.</div>
  </section>
</main>

${siteFooter()}

<script>
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll(".filter-pill").forEach(btn => {
    btn.addEventListener("click", () => {
      const cat = btn.dataset.cat;
      document.querySelectorAll(".filter-pill").forEach(b => b.classList.toggle("active", b.dataset.cat === cat));
      let visible = 0;
      document.querySelectorAll(".block-card").forEach(c => {
        const show = cat === "all" || c.dataset.cat === cat;
        c.classList.toggle("hidden", !show);
        if (show) visible++;
      });
      document.getElementById("empty-state").classList.toggle("hidden", visible > 0);
    });
  });
});
</script>
</body>
</html>`;
}

// ============================================================================
// PER-BLOCK PAGE
// ============================================================================
function fileType(path) {
  if (path.endsWith(".md")) return "MD";
  if (path.endsWith(".feature")) return "GHERKIN";
  if (path.endsWith(".json")) return "JSON";
  if (path.endsWith(".ts") || path.endsWith(".js")) return "TS";
  return "FILE";
}

function renderBlock(b, prev, next) {
  const prereqHtml = b.prerequisites.length
    ? b.prerequisites.map(p => `<a class="prereq" href="${p}.html">${p}</a>`).join("")
    : '<span class="prereq none">none</span>';

  const tablesHtml = b.tables.length
    ? `<div class="tables-grid">${b.tables.map(t =>
        `<div class="table-card${t.shared ? ' shared' : ''}">
          <div class="table-name">${t.name}</div>
          <div class="table-desc">${t.desc}</div>
        </div>`
      ).join("")}</div>`
    : '<p style="color: var(--text-muted);">This block introduces no new tables.</p>';

  const filesHtml = b.files.map(f =>
    `<a class="file-link" href="${REPO_BLOB}/${b.folder}/${f}" target="_blank" rel="noopener">${f}<span class="ftype">${fileType(f)}</span></a>`
  ).join("");

  const prevNext = `
        <nav class="prev-next">
          ${prev ? `<a href="${prev.id}.html"><span class="label">← Previous block</span><span class="title">${prev.name}</span></a>` : `<div class="placeholder"></div>`}
          ${next ? `<a class="next" href="${next.id}.html"><span class="label">Next block →</span><span class="title">${next.name}</span></a>` : `<div class="placeholder"></div>`}
        </nav>`;

  return `${headTags(
    `${b.name} — Primitive Block Library`,
    b.summary.replace(/<[^>]+>/g, "").slice(0, 200),
    { cssPath: "../assets/style.css" }
  )}

${siteHeader("../")}

<main>
  <div class="page-grid">

    <aside class="toc">
      <a class="back" href="../">Back to library</a>
      <div class="toc-section">On this page</div>
      <nav class="toc-nav">
        <a href="#overview" class="active">Overview</a>
        <a href="#prerequisites">Prerequisites</a>
        <a href="#data-model">Data model</a>
        <a href="#usage">Use / Avoid</a>
        <a href="#files">Spec files</a>
      </nav>
      <div class="toc-meta">
        <div class="meta-row"><span class="label">Category</span><span class="cat-badge ${b.category}">${b.category}</span></div>
        <div class="meta-row"><span class="label">Complexity</span><span class="complexity ${b.complexity}">${b.complexity}</span></div>
        <div class="meta-row"><span class="label">Effort</span><span>${b.effort}</span></div>
        <div class="meta-row"><span class="label">Version</span><code>v${b.version}</code></div>
      </div>
    </aside>

    <article class="page-content">
      <div class="breadcrumb">
        <a href="../">Library</a>
        <span class="sep">/</span>
        <span>${b.category}</span>
        <span class="sep">/</span>
        <span>${b.name}</span>
      </div>
      <span class="block-id-large">${b.id}</span>
      <h1>${b.name}</h1>
      <p class="lead">${b.summary}</p>
      <div class="block-tags">${b.tags.map(t => `<span class="tag">${t}</span>`).join("")}</div>

      <section id="overview">
        <h2>Overview</h2>
        <p>${b.summary}</p>
      </section>

      <section id="prerequisites">
        <h2>Prerequisites</h2>
        ${b.prerequisites.length
          ? `<p>This block depends on the following blocks being implemented first:</p><div class="prereq-list">${prereqHtml}</div>`
          : `<p>This block has no prerequisites &mdash; it can be implemented standalone.</p>`}
      </section>

      <section id="data-model">
        <h2>Data Model</h2>
        <p>Logical tables introduced by this block. Types resolve to dialect-specific SQL per the <a href="${REPO_BLOB}/docs/SPEC_GUIDELINES.md" target="_blank" rel="noopener">canonical logical-type mapping</a>.</p>
        ${tablesHtml}
      </section>

      <section id="usage">
        <h2>Use it / Avoid it</h2>
        <div class="two-col">
          <div class="use-card yes">
            <h5>Use when</h5>
            <ul>${b.use.map(u => `<li>${u}</li>`).join("")}</ul>
          </div>
          <div class="use-card no">
            <h5>Avoid when</h5>
            <ul>${b.avoid.map(u => `<li>${u}</li>`).join("")}</ul>
          </div>
        </div>
      </section>

      <section id="files">
        <h2>Spec files</h2>
        <p>Every file in the <code>${b.folder}/</code> folder. Click any link to open the file on GitHub.</p>
        <div class="files-grid">${filesHtml}</div>
        <p style="margin-top: 20px;"><a href="${REPO_TREE}/${b.folder}" target="_blank" rel="noopener">Open the folder on GitHub &rarr;</a></p>
      </section>

${prevNext}
    </article>
  </div>
</main>

${siteFooter()}

<script>
// Highlight active TOC link on scroll
document.addEventListener("DOMContentLoaded", () => {
  const links = document.querySelectorAll(".toc-nav a");
  const sections = [...links].map(a => document.querySelector(a.getAttribute("href"))).filter(Boolean);
  const obs = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (e.isIntersecting) {
        const id = e.target.id;
        links.forEach(l => l.classList.toggle("active", l.getAttribute("href") === "#" + id));
      }
    });
  }, { rootMargin: "-30% 0px -60% 0px" });
  sections.forEach(s => obs.observe(s));
});
</script>
</body>
</html>`;
}

// ============================================================================
// MAIN
// ============================================================================
function emit(path, content) {
  const abs = resolve(DOCS, path);
  mkdirSync(dirname(abs), { recursive: true });
  writeFileSync(abs, content, "utf8");
  return abs;
}

function main() {
  const written = [];
  written.push(emit("assets/style.css", CSS));
  written.push(emit("index.html", renderLanding()));
  BLOCKS.forEach((b, i) => {
    const prev = i > 0 ? BLOCKS[i - 1] : null;
    const next = i < BLOCKS.length - 1 ? BLOCKS[i + 1] : null;
    written.push(emit(`blocks/${b.id}.html`, renderBlock(b, prev, next)));
  });
  console.log(`Built ${written.length} files:`);
  written.forEach(p => console.log("  " + p.replace(resolve(DOCS, ".."), ".")));
  console.log(`\n${BLOCKS.length} blocks, ${new Set(BLOCKS.map(b => b.category)).size} categories.`);
}

main();
