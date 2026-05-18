#!/usr/bin/env node
// Static site generator for the Primitive Block Library.
// Run from repo root:  node docs/build.mjs
// Outputs:
//   docs/index.html
//   docs/assets/style.css
//   docs/blocks/<block-id>.html  (one file per block)
//
// To add a block: append an entry to BLOCKS below and re-run.

import { writeFileSync, mkdirSync, readFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DOCS = __dirname;
const REPO_ROOT = resolve(DOCS, "..");

const REPO_HTTPS = "https://github.com/nguyenvanduocit/primitive-blocks-specs";
const REPO_BLOB = `${REPO_HTTPS}/blob/main`;
const REPO_TREE = `${REPO_HTTPS}/tree/main`;

// ============================================================================
// SOURCE-MARKDOWN ENRICHMENT
// Parse README / security / acceptance markdown to derive richer detail pages.
// All extractors are tolerant: missing file or missing section → returns empty.
// ============================================================================
function readSource(folder, filename) {
  const p = resolve(REPO_ROOT, folder, filename);
  if (!existsSync(p)) return null;
  try { return readFileSync(p, "utf8"); } catch { return null; }
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// Light inline-markdown: backticks → <code>, **bold** → <strong>.
function renderInline(s) {
  return escapeHtml(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
}

// Split a markdown body at a given heading regex (returns array of { heading, body }).
// Use this instead of lookaheads with $ (which misbehave with /m flag — $ matches
// end of every line, breaking lazy quantifiers).
function splitByHeading(md, headingRe) {
  if (!md) return [];
  const parts = [];
  const matches = [...md.matchAll(headingRe)];
  for (let i = 0; i < matches.length; i++) {
    const m = matches[i];
    const start = m.index + m[0].length;
    const end = (i + 1 < matches.length) ? matches[i + 1].index : md.length;
    let body = md.slice(start, end);
    // Stop at horizontal-rule divider on its own line (treated as section break).
    const hrIdx = body.search(/\n---+\s*\n/);
    if (hrIdx >= 0) body = body.slice(0, hrIdx);
    parts.push({ heading: m, body });
  }
  return parts;
}

// Extract the first paragraph after "### Problem Statement".
function extractProblemStatement(md) {
  if (!md) return null;
  const parts = splitByHeading(md, /^### Problem Statement[^\n]*\n/gm);
  if (!parts.length) return null;
  // First non-empty paragraph
  const para = parts[0].body.trim().split(/\n\n+/).find(p => p.trim());
  return para ? para.trim() : null;
}

// Parse a single Gherkin .feature file into:
//   { feature, description, background: [steps], scenarios: [{ tags, name, steps }] }
// Tolerant: ignores doc-strings, data tables, examples blocks.
function parseGherkin(content) {
  if (!content) return null;
  const lines = content.split(/\r?\n/);
  let feature = null;
  const description = [];
  const background = [];
  const scenarios = [];
  let current = null;          // current scenario being filled
  let pendingTags = [];        // tags pending attachment to next scenario
  let mode = "preamble";       // preamble | background | scenario
  let lastKeyword = null;      // for "And"/"But" inheritance

  const stepKwRe = /^(Given|When|Then|And|But)\s+(.+)$/;

  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;
    if (line.startsWith("#")) continue; // Gherkin comment

    if (line.startsWith("Feature:")) {
      feature = line.slice("Feature:".length).trim();
      mode = "feature-header";
      continue;
    }
    if (line.startsWith("Background:")) {
      mode = "background";
      lastKeyword = null;
      continue;
    }
    if (line.startsWith("@")) {
      pendingTags = line.split(/\s+/).filter(t => t.startsWith("@")).map(t => t.slice(1));
      continue;
    }
    if (line.startsWith("Scenario Outline:") || line.startsWith("Scenario:")) {
      mode = "scenario";
      const name = line.replace(/^Scenario(?:\s+Outline)?:\s*/, "").trim();
      current = { name, tags: pendingTags, steps: [] };
      scenarios.push(current);
      pendingTags = [];
      lastKeyword = null;
      continue;
    }
    if (line.startsWith("Examples:")) {
      mode = "examples";
      continue;
    }

    // Skip table rows and doc strings (informational, not step text).
    if (line.startsWith("|") || line.startsWith('"""') || line.startsWith('```')) continue;

    const stepMatch = line.match(stepKwRe);
    if (stepMatch) {
      let kw = stepMatch[1];
      const text = stepMatch[2].trim();
      if (kw === "And" || kw === "But") kw = lastKeyword || kw;
      else lastKeyword = kw;
      const step = { kw, text };
      if (mode === "background") background.push(step);
      else if (mode === "scenario" && current) current.steps.push(step);
      continue;
    }

    if (mode === "feature-header" && /^(As\s+an?|I\s+want|So\s+that|In\s+order)/i.test(line)) {
      description.push(line);
      continue;
    }
  }

  return { feature, description: description.join(" ") || null, background, scenarios };
}

// Read every .feature file in the block folder, parse, return [{ filename, parsed }].
function readBlockFeatures(b) {
  const out = [];
  for (const f of b.files) {
    if (!f.endsWith(".feature")) continue;
    const content = readSource(b.folder, f);
    const parsed = parseGherkin(content);
    if (parsed && parsed.feature) out.push({ filename: f, parsed });
  }
  return out;
}

// Extract threat headers: "### N. Name" + "**Impact**: Severity[ — desc]"
function extractThreats(md) {
  if (!md) return [];
  const threats = [];
  const parts = splitByHeading(md, /^### (\d+)\.\s+([^\n]+)\n/gm);
  for (const { heading, body } of parts) {
    const num = heading[1];
    const name = heading[2].trim();
    const impactMatch = body.match(/\*\*Impact\*\*\s*:\s*([^\n—]+?)(?:\s*—\s*([^\n]+))?\s*\n/);
    if (!impactMatch) { threats.push({ num, name, severity: null, severityRaw: null, desc: null }); continue; }
    const severityRaw = impactMatch[1].trim();
    const severity = severityRaw.toLowerCase().replace(/[^a-z]/g, "");
    const desc = impactMatch[2] ? impactMatch[2].trim() : null;
    threats.push({ num, name, severity, severityRaw, desc });
  }
  return threats;
}

// Acceptance checklist breakdown: { sections: [{ name, count }], total }
function extractAcceptance(md) {
  if (!md) return { sections: [], total: 0 };
  const sections = [];
  let total = 0;
  const parts = splitByHeading(md, /^## ([^\n]+)\n/gm);
  for (const { heading, body } of parts) {
    const name = heading[1].trim();
    const count = (body.match(/^\s*-\s*\[\s*[ x]\s*\]/gm) || []).length;
    if (count > 0) { sections.push({ name, count }); total += count; }
  }
  return { sections, total };
}

// Reverse lookup: blocks that list `block.id` in their prerequisites.
function getRequiredBy(block, allBlocks) {
  return allBlocks
    .filter(b => b.prerequisites.includes(block.id))
    .map(b => ({ id: b.id, name: b.name }));
}

// Group files into Documentation / Scenarios / Fixtures / Acceptance.
function groupFiles(files) {
  const g = { docs: [], scenarios: [], fixtures: [], acceptance: [] };
  for (const f of files) {
    if (f === "acceptance.md") g.acceptance.push(f);
    else if (f.startsWith("fixtures/")) g.fixtures.push(f);
    else if (f.endsWith(".feature")) g.scenarios.push(f);
    else g.docs.push(f);
  }
  return g;
}

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
const CSS = `/* ===========================================================
   PRIMITIVE BLOCK LIBRARY — Editorial Blueprint
   Paper-light, serif display, blueprint-cobalt accent.
   Reads like an engineering datasheet — not a SaaS dashboard.
   =========================================================== */

:root {
  /* Paper system — warm cream tones, like aged drafting paper */
  --paper:        #f4eee2;
  --paper-2:      #ece4d2;
  --paper-3:      #e3d8bf;
  --ink:          #161210;
  --ink-2:        #4a4339;
  --ink-3:        #7a7064;
  --ink-4:        #aa9f88;
  --rule:         #d6cab0;
  --rule-2:       #a3947a;

  /* Blueprint accent — engineering cobalt */
  --cobalt:       #1d4ed8;
  --cobalt-2:     #1e3a8a;
  --cobalt-soft:  rgba(29, 78, 216, 0.10);
  --cobalt-tint:  rgba(29, 78, 216, 0.04);

  /* Caution / verdict / warmth */
  --oxide:        #a72827;
  --oxide-soft:   rgba(167, 40, 39, 0.10);
  --verdict:      #0a6e44;
  --verdict-soft: rgba(10, 110, 68, 0.10);
  --sun:          #b25b00;
  --sun-soft:     rgba(178, 91, 0, 0.10);

  /* Category palette — distinct hues kept earthbound */
  --c-auth:       #1d4ed8;
  --c-billing:    #0a6e44;
  --c-compliance: #a72827;
  --c-data:       #6e3aa8;
  --c-integration:#0e7490;
  --c-messaging:  #b03060;
  --c-operations: #8a6a00;
  --c-ugc:        #b25b00;
  --c-webhooks:   #4338ca;

  /* Type */
  --display: "Fraunces", "Times New Roman", serif;
  --sans:    "IBM Plex Sans", "Helvetica Neue", system-ui, sans-serif;
  --mono:    "JetBrains Mono", ui-monospace, "SFMono-Regular", Menlo, monospace;

  --max-w: 1200px;
  --pad-x: 32px;
}
* { box-sizing: border-box; }

html, body {
  margin: 0; padding: 0;
  background: var(--paper);
  color: var(--ink);
  font-family: var(--sans);
  font-size: 15.5px;
  line-height: 1.55;
  font-weight: 400;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
  scroll-behavior: smooth;
}

/* Engineering paper grid — fixed, very subtle, like drafting paper */
body::before {
  content: "";
  position: fixed; inset: 0;
  background-image:
    linear-gradient(to right, rgba(46, 36, 22, 0.045) 1px, transparent 1px),
    linear-gradient(to bottom, rgba(46, 36, 22, 0.045) 1px, transparent 1px);
  background-size: 32px 32px;
  pointer-events: none;
  z-index: 0;
}
/* Soft atmospheric glow — top cobalt, bottom amber */
body::after {
  content: "";
  position: fixed; inset: 0;
  background:
    radial-gradient(ellipse 60% 30% at 50% 0%, rgba(29, 78, 216, 0.05), transparent 70%),
    radial-gradient(ellipse 40% 25% at 90% 100%, rgba(178, 91, 0, 0.05), transparent 70%);
  pointer-events: none;
  z-index: 0;
}

main, header, footer { position: relative; z-index: 1; }

a { color: var(--cobalt); text-decoration: none; }
a:hover {
  color: var(--cobalt-2);
  text-decoration: underline;
  text-decoration-thickness: 1px;
  text-underline-offset: 4px;
}

code, pre { font-family: var(--mono); font-size: 0.875em; }
code {
  background: var(--paper-2);
  padding: 1px 6px;
  border-radius: 2px;
  border: 1px solid var(--rule);
  color: var(--ink);
}
pre code { background: transparent; padding: 0; border: 0; }

h1, h2, h3, h4 {
  font-family: var(--display);
  font-weight: 500;
  letter-spacing: -0.02em;
  line-height: 1.1;
  margin: 0 0 0.4em 0;
  color: var(--ink);
  font-variation-settings: "opsz" 144, "SOFT" 80, "WONK" 0;
}
h1 {
  font-size: clamp(3rem, 6.8vw, 5.6rem);
  font-weight: 400;
  letter-spacing: -0.035em;
  line-height: 0.96;
}
h1 em, h2 em, h4 em {
  font-style: italic;
  font-variation-settings: "opsz" 144, "SOFT" 100, "WONK" 1;
  color: var(--cobalt);
}
h2 {
  font-size: clamp(2rem, 3.6vw, 2.85rem);
  font-weight: 400;
  letter-spacing: -0.025em;
}
h3 { font-size: 1.35rem; font-weight: 500; }
h4 {
  font-size: 1rem;
  font-weight: 600;
  font-family: var(--sans);
  letter-spacing: -0.005em;
}

/* ====================== HEADER ====================== */
header.site {
  position: sticky; top: 0;
  background: rgba(244, 238, 226, 0.88);
  backdrop-filter: saturate(140%) blur(14px);
  -webkit-backdrop-filter: saturate(140%) blur(14px);
  border-bottom: 1px solid var(--rule);
  z-index: 50;
}
.nav {
  max-width: var(--max-w);
  margin: 0 auto;
  padding: 14px var(--pad-x);
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
}
.brand {
  font-family: var(--mono);
  font-weight: 600;
  font-size: 0.78rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--ink);
  text-decoration: none;
  display: inline-flex;
  align-items: center;
  gap: 12px;
}
.brand:hover { color: var(--ink); text-decoration: none; }
.brand-mark {
  width: 26px; height: 26px;
  display: grid;
  place-items: center;
  font-family: var(--display);
  font-weight: 500;
  font-size: 18px;
  color: var(--cobalt);
  border: 1px solid var(--ink);
  background: var(--paper);
  font-variation-settings: "opsz" 144, "SOFT" 100, "WONK" 1;
  font-style: italic;
}
.brand:hover .brand-mark { background: var(--cobalt); color: var(--paper); border-color: var(--cobalt); }
.nav-links {
  display: flex;
  gap: 0;
  list-style: none;
  margin: 0;
  padding: 0;
  font-family: var(--mono);
  text-transform: uppercase;
  letter-spacing: 0.08em;
}
.nav-links a {
  color: var(--ink-2);
  text-decoration: none;
  transition: color 0.15s ease;
  padding: 8px 14px;
  font-size: 0.74rem;
}
.nav-links a:hover { color: var(--cobalt); text-decoration: none; }
.nav-links a.github {
  color: var(--paper);
  background: var(--ink);
  padding: 9px 14px;
  margin-left: 6px;
}
.nav-links a.github:hover { color: var(--paper); background: var(--cobalt); }
@media (max-width: 640px) { .nav-links li:not(:last-child) { display: none; } }

/* ====================== LAYOUT ====================== */
main { padding: 0 var(--pad-x); }
section {
  max-width: var(--max-w);
  margin: 0 auto;
  padding: 96px 0;
}

/* ====================== HERO ====================== */
.hero { padding: 64px 0 104px; }
.hero-meta {
  font-family: var(--mono);
  font-size: 0.7rem;
  color: var(--ink-3);
  letter-spacing: 0.1em;
  text-transform: uppercase;
  margin-bottom: 56px;
  display: flex;
  align-items: center;
  gap: 18px;
  flex-wrap: wrap;
}
.hero-meta::before {
  content: "";
  width: 32px;
  height: 1px;
  background: var(--ink);
}
.hero-meta .sep { color: var(--ink-4); }
.hero-grid {
  display: grid;
  grid-template-columns: minmax(0, 7fr) minmax(0, 5fr);
  gap: 64px;
  align-items: end;
}
@media (max-width: 920px) {
  .hero-grid { grid-template-columns: 1fr; gap: 48px; }
}
.hero-text { min-width: 0; }
.hero-tag {
  display: inline-block;
  font-family: var(--mono);
  font-size: 0.74rem;
  color: var(--cobalt);
  letter-spacing: 0.1em;
  text-transform: uppercase;
  margin-bottom: 28px;
  padding-left: 14px;
  border-left: 2px solid var(--cobalt);
  line-height: 1.4;
}
.hero h1 {
  margin: 0 0 32px;
  max-width: 760px;
}
.hero h1 em { white-space: nowrap; }
.hero .tagline {
  font-size: clamp(1.05rem, 1.3vw, 1.18rem);
  color: var(--ink-2);
  max-width: 600px;
  margin: 0 0 40px;
  line-height: 1.6;
}
.hero .ctas {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

/* Title-block — engineering datasheet */
.title-block {
  border: 1.5px solid var(--ink);
  background: var(--paper);
  font-family: var(--mono);
  box-shadow: 6px 6px 0 var(--ink);
}
.title-block .tb-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 11px 18px;
  font-size: 0.68rem;
  color: var(--paper);
  background: var(--ink);
  letter-spacing: 0.14em;
  text-transform: uppercase;
}
.title-block .tb-head .tb-doc { opacity: 0.55; }
.title-block .tb-row {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 16px;
  padding: 16px 18px;
  border-top: 1px solid var(--rule);
}
.title-block .tb-row:first-of-type { border-top: 0; }
.title-block .tb-label {
  font-size: 0.7rem;
  color: var(--ink-3);
  letter-spacing: 0.1em;
  text-transform: uppercase;
}
.title-block .tb-value {
  font-family: var(--display);
  font-weight: 400;
  font-size: 1.85rem;
  color: var(--ink);
  font-variation-settings: "opsz" 144, "SOFT" 50, "WONK" 0;
  letter-spacing: -0.02em;
  line-height: 1;
}
.title-block .tb-value .unit {
  font-family: var(--mono);
  font-weight: 500;
  font-size: 0.62rem;
  color: var(--ink-3);
  margin-left: 4px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
.title-block .tb-foot {
  padding: 11px 18px;
  border-top: 1px solid var(--rule);
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 0.64rem;
  color: var(--ink-3);
  letter-spacing: 0.14em;
  text-transform: uppercase;
  background: var(--paper-2);
}

/* ====================== BUTTONS ====================== */
.btn {
  font-family: var(--mono);
  font-weight: 500;
  font-size: 0.76rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  padding: 14px 18px 13px;
  border: 1px solid var(--ink);
  background: var(--paper);
  color: var(--ink);
  cursor: pointer;
  text-decoration: none;
  transition: all 0.18s ease;
  display: inline-flex;
  align-items: center;
  gap: 12px;
}
.btn::after {
  content: "→";
  transition: transform 0.18s ease;
  font-weight: 400;
}
.btn:hover { background: var(--ink); color: var(--paper); text-decoration: none; }
.btn:hover::after { transform: translateX(4px); }
.btn.primary {
  background: var(--ink);
  color: var(--paper);
  border-color: var(--ink);
}
.btn.primary:hover {
  background: var(--cobalt);
  border-color: var(--cobalt);
  color: var(--paper);
}

/* ====================== SECTION RULE / HEADERS ====================== */
.section-rule {
  display: flex;
  align-items: baseline;
  gap: 18px;
  padding-top: 22px;
  border-top: 1.5px solid var(--ink);
  margin-bottom: 44px;
  flex-wrap: wrap;
}
.section-rule .section-num {
  font-family: var(--mono);
  font-weight: 600;
  font-size: 0.82rem;
  color: var(--ink);
  letter-spacing: 0.06em;
}
.section-rule .section-label {
  font-family: var(--mono);
  font-weight: 600;
  font-size: 0.7rem;
  color: var(--ink-2);
  letter-spacing: 0.2em;
  text-transform: uppercase;
}
.section-rule .section-line {
  flex: 1;
  min-width: 32px;
  height: 1px;
  background: var(--rule);
  align-self: center;
  margin-top: 2px;
}
.section-rule .section-sheet {
  font-family: var(--mono);
  font-size: 0.66rem;
  color: var(--ink-4);
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.section-header { margin-bottom: 56px; max-width: 820px; }
.section-header h2 { margin: 0 0 18px; }
.section-header p {
  color: var(--ink-2);
  font-size: 1.1rem;
  margin: 0;
  max-width: 720px;
  line-height: 1.6;
}

/* ====================== EXAMPLE SECTION ====================== */
.example-spread {
  display: grid;
  grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr);
  gap: 56px;
  align-items: start;
  margin-top: 8px;
}
@media (max-width: 800px) {
  .example-spread { grid-template-columns: 1fr; gap: 32px; }
}
.example-text h2 { margin-bottom: 20px; }
.example-text p { color: var(--ink); font-size: 1.05rem; line-height: 1.6; max-width: 56ch; margin: 0; }
.example-text p code {
  font-size: 0.95em;
  background: var(--cobalt-soft);
  border-color: var(--cobalt);
  color: var(--cobalt);
}
.example-text a:hover code { background: var(--cobalt); color: var(--paper); }
.example-stats { box-shadow: 4px 4px 0 var(--ink); }

/* ====================== COMPARE CARDS ====================== */
.compare {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 28px;
  margin: 0 0 64px;
}
@media (max-width: 720px) { .compare { grid-template-columns: 1fr; } }
.compare .card {
  border: 1px solid var(--rule-2);
  padding: 32px;
  background: var(--paper);
  position: relative;
}
.compare .card.old {
  background: transparent;
  border-style: dashed;
  opacity: 0.82;
}
.compare .card.new {
  border-color: var(--ink);
  border-width: 1.5px;
  box-shadow: 4px 4px 0 var(--ink);
}
.compare .card h3 {
  margin-bottom: 22px;
  font-size: 1.45rem;
  font-weight: 400;
  font-variation-settings: "opsz" 144, "SOFT" 50, "WONK" 0;
}
.compare .card h3 .tag {
  display: inline-block;
  font-family: var(--mono);
  font-size: 0.62rem;
  font-weight: 600;
  padding: 3px 9px;
  margin-left: 10px;
  vertical-align: middle;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--ink-2);
  background: var(--paper);
}
.compare .card.old h3 .tag {
  background: transparent;
  color: var(--oxide);
  border: 1px solid var(--oxide);
}
.compare .card.new h3 .tag {
  background: var(--cobalt);
  color: var(--paper);
  border: 1px solid var(--cobalt);
}
.compare ul {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.compare li {
  padding-left: 24px;
  position: relative;
  font-size: 0.94rem;
  color: var(--ink-2);
  line-height: 1.55;
}
.compare .card.new li { color: var(--ink); }
.compare li::before {
  content: "—";
  position: absolute;
  left: 0;
  top: 0;
  font-family: var(--mono);
  color: var(--ink-3);
}
.compare .card.new li::before {
  content: "+";
  color: var(--cobalt);
  font-weight: 700;
}

/* ====================== LAYERS ====================== */
.layers {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 20px;
  margin-top: 40px;
}
@media (max-width: 800px) { .layers { grid-template-columns: 1fr; } }
.layer {
  border: 1px solid var(--rule-2);
  padding: 28px 26px 26px;
  background: var(--paper);
  position: relative;
  overflow: hidden;
}
.layer::before {
  content: "";
  position: absolute;
  top: 0; left: 0;
  width: 4px;
  height: 100%;
  background: var(--c, var(--cobalt));
}
.layer:nth-child(1) { --c: var(--verdict); }
.layer:nth-child(2) { --c: var(--cobalt); }
.layer:nth-child(3) { --c: var(--sun); }
.layer .layer-num {
  font-family: var(--mono);
  font-weight: 600;
  color: var(--c);
  font-size: 0.7rem;
  letter-spacing: 0.14em;
  margin-bottom: 14px;
  text-transform: uppercase;
}
.layer h4 {
  margin-bottom: 14px;
  font-family: var(--display);
  font-size: 1.5rem;
  font-weight: 400;
  font-variation-settings: "opsz" 144, "SOFT" 80, "WONK" 0;
  letter-spacing: -0.02em;
}
.layer p {
  color: var(--ink-2);
  font-size: 0.92rem;
  margin: 0 0 16px;
  line-height: 1.55;
}
.layer .verdict {
  display: inline-block;
  font-family: var(--mono);
  font-size: 0.66rem;
  padding: 4px 10px;
  background: var(--paper-2);
  border: 1px solid var(--c);
  color: var(--c);
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

/* ====================== FILTER BAR ====================== */
.filter-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 0;
  margin-bottom: 36px;
  border: 1px solid var(--ink);
  width: fit-content;
  max-width: 100%;
  overflow-x: auto;
  background: var(--paper);
}
.filter-pill {
  font-family: var(--mono);
  font-size: 0.72rem;
  font-weight: 500;
  padding: 11px 16px;
  border: 0;
  border-right: 1px solid var(--rule-2);
  background: transparent;
  color: var(--ink-2);
  cursor: pointer;
  white-space: nowrap;
  transition: all 0.15s ease;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
.filter-pill:last-child { border-right: 0; }
.filter-pill:hover { color: var(--ink); background: var(--paper-2); }
.filter-pill.active {
  background: var(--ink);
  color: var(--paper);
}
.filter-pill .count {
  font-size: 0.66rem;
  color: var(--ink-3);
  margin-left: 6px;
  font-weight: 400;
}
.filter-pill:hover .count { color: var(--ink-2); }
.filter-pill.active .count { color: var(--paper); opacity: 0.55; }

/* ====================== BLOCK GRID ====================== */
.block-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(380px, 100%), 1fr));
  gap: 20px;
}
.block-card {
  display: grid;
  grid-template-columns: 64px 1fr;
  text-decoration: none;
  color: var(--ink);
  border: 1px solid var(--rule-2);
  background: var(--paper);
  padding: 0;
  position: relative;
  overflow: hidden;
  transition: transform 0.2s ease, box-shadow 0.2s ease, border-color 0.2s ease;
}
.block-card:hover {
  text-decoration: none;
  color: var(--ink);
  border-color: var(--ink);
  transform: translate(-2px, -2px);
  box-shadow: 4px 4px 0 var(--ink);
}
.block-card .card-num {
  font-family: var(--mono);
  color: var(--ink-3);
  padding: 22px 0 16px 0;
  border-right: 1px solid var(--rule);
  background: var(--paper-2);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: flex-start;
  transition: background 0.2s ease, border-color 0.2s ease;
}
.block-card .num-main {
  font-family: var(--display);
  font-size: 1.45rem;
  font-weight: 500;
  color: var(--ink);
  font-variation-settings: "opsz" 144, "SOFT" 50, "WONK" 0;
  letter-spacing: -0.02em;
  line-height: 1;
}
.block-card .num-divider {
  width: 14px;
  height: 1px;
  background: var(--rule-2);
  margin: 6px 0;
}
.block-card .num-total {
  font-size: 0.62rem;
  color: var(--ink-3);
  letter-spacing: 0.1em;
}
.block-card:hover .card-num {
  background: var(--cobalt-tint);
  border-right-color: var(--cobalt);
}
.block-card:hover .num-main { color: var(--cobalt); }
.block-card:hover .num-divider { background: var(--cobalt); }
.block-card .card-body {
  padding: 22px 24px 20px;
  min-width: 0;
  display: flex;
  flex-direction: column;
}
.block-card .row-1 {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 10px;
}
.block-id {
  font-family: var(--mono);
  font-size: 0.72rem;
  color: var(--ink-3);
  letter-spacing: 0.02em;
}
.block-name {
  font-family: var(--display);
  font-size: 1.4rem;
  font-weight: 500;
  font-variation-settings: "opsz" 144, "SOFT" 80, "WONK" 0;
  letter-spacing: -0.02em;
  margin: 4px 0 12px;
  color: var(--ink);
  line-height: 1.15;
}
.block-card .lead {
  color: var(--ink-2);
  font-size: 0.92rem;
  margin: 0 0 16px;
  line-height: 1.55;
  display: -webkit-box;
  -webkit-line-clamp: 3;
  line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.block-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-bottom: 18px;
}
.tag {
  font-family: var(--mono);
  font-size: 0.66rem;
  color: var(--ink-2);
  background: var(--paper-2);
  border: 1px solid var(--rule);
  padding: 2px 7px;
  letter-spacing: 0.03em;
}
.block-meta {
  display: flex;
  gap: 18px;
  flex-wrap: wrap;
  font-size: 0.82rem;
  color: var(--ink-2);
  align-items: center;
  padding-top: 14px;
  border-top: 1px solid var(--rule);
  margin-top: auto;
}
.meta-item {
  display: flex;
  align-items: center;
  gap: 6px;
}
.meta-item .label {
  color: var(--ink-3);
  font-family: var(--mono);
  font-size: 0.64rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
}
.complexity {
  font-family: var(--mono);
  font-weight: 600;
  font-size: 0.7rem;
  padding: 2px 8px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
.complexity.low    { color: var(--verdict); border: 1px solid var(--verdict); background: var(--verdict-soft); }
.complexity.medium { color: var(--sun);     border: 1px solid var(--sun);     background: var(--sun-soft); }
.complexity.high   { color: var(--oxide);   border: 1px solid var(--oxide);   background: var(--oxide-soft); }
.block-card .arrow {
  position: absolute;
  top: 18px;
  right: 22px;
  opacity: 0;
  transform: translateX(-6px);
  transition: all 0.2s ease;
  color: var(--cobalt);
  font-family: var(--mono);
  font-size: 1.1rem;
}
.block-card:hover .arrow { opacity: 1; transform: translateX(0); }
.empty-state {
  text-align: center;
  padding: 64px 24px;
  color: var(--ink-2);
  border: 1px dashed var(--rule-2);
  background: var(--paper);
}

/* ====================== CATEGORY BADGES ====================== */
.cat-badge {
  font-family: var(--mono);
  font-size: 0.64rem;
  font-weight: 600;
  padding: 3px 9px;
  background: var(--paper);
  border: 1px solid var(--rule);
  color: var(--ink-2);
  text-transform: uppercase;
  letter-spacing: 0.1em;
  line-height: 1.4;
}
.cat-badge.auth        { color: var(--c-auth);        border-color: var(--c-auth);        background: rgba(29, 78, 216, 0.08); }
.cat-badge.billing     { color: var(--c-billing);     border-color: var(--c-billing);     background: rgba(10, 110, 68, 0.08); }
.cat-badge.compliance  { color: var(--c-compliance);  border-color: var(--c-compliance);  background: rgba(167, 40, 39, 0.08); }
.cat-badge.data        { color: var(--c-data);        border-color: var(--c-data);        background: rgba(110, 58, 168, 0.08); }
.cat-badge.integration { color: var(--c-integration); border-color: var(--c-integration); background: rgba(14, 116, 144, 0.08); }
.cat-badge.messaging   { color: var(--c-messaging);   border-color: var(--c-messaging);   background: rgba(176, 48, 96, 0.08); }
.cat-badge.operations  { color: var(--c-operations);  border-color: var(--c-operations);  background: rgba(138, 106, 0, 0.08); }
.cat-badge.ugc         { color: var(--c-ugc);         border-color: var(--c-ugc);         background: rgba(178, 91, 0, 0.08); }
.cat-badge.webhooks    { color: var(--c-webhooks);    border-color: var(--c-webhooks);    background: rgba(67, 56, 202, 0.08); }

/* ====================== FLOW STEPS ====================== */
.flow-steps {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 0;
  margin-top: 40px;
  border: 1px solid var(--rule-2);
  background: var(--paper);
}
@media (max-width: 900px) { .flow-steps { grid-template-columns: repeat(2, 1fr); } }
@media (max-width: 480px) { .flow-steps { grid-template-columns: 1fr; } }
.flow-step {
  padding: 28px 22px;
  border-right: 1px solid var(--rule);
  position: relative;
}
.flow-step:last-child { border-right: 0; }
@media (max-width: 900px) {
  .flow-step:nth-child(2n) { border-right: 0; }
  .flow-step { border-bottom: 1px solid var(--rule); }
  .flow-step:nth-last-child(-n+2):nth-child(odd):last-child { border-bottom: 0; }
}
.flow-step .step-num {
  font-family: var(--mono);
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--cobalt);
  letter-spacing: 0.14em;
  margin-bottom: 14px;
  text-transform: uppercase;
  display: flex;
  align-items: center;
  gap: 8px;
}
.flow-step .step-num::before {
  content: "";
  width: 16px;
  height: 1px;
  background: var(--cobalt);
}
.flow-step h4 {
  font-family: var(--display);
  font-size: 1.25rem;
  font-weight: 500;
  font-variation-settings: "opsz" 144, "SOFT" 80, "WONK" 0;
  margin-bottom: 8px;
  letter-spacing: -0.02em;
}
.flow-step p { font-size: 0.85rem; color: var(--ink-2); margin: 0; line-height: 1.55; }

/* ====================== FOOTER ====================== */
footer.site {
  border-top: 1.5px solid var(--ink);
  margin-top: 64px;
  padding: 56px var(--pad-x) 64px;
  color: var(--ink-2);
  font-size: 0.85rem;
  background: var(--paper-2);
}
footer.site .footer-inner {
  max-width: var(--max-w);
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
footer.site .footer-meta {
  font-family: var(--mono);
  font-size: 0.68rem;
  color: var(--ink-3);
  letter-spacing: 0.14em;
  text-transform: uppercase;
  margin-bottom: 8px;
  display: flex;
  align-items: center;
  gap: 16px;
}
footer.site .footer-meta::before {
  content: "";
  width: 24px;
  height: 1px;
  background: var(--ink);
}
footer.site p { margin: 0; }
footer.site a {
  color: var(--ink);
  text-decoration: underline;
  text-decoration-color: var(--rule-2);
  text-underline-offset: 4px;
}
footer.site a:hover { color: var(--cobalt); text-decoration-color: var(--cobalt); }

/* ====================== PER-BLOCK PAGE ====================== */
.page-grid {
  max-width: var(--max-w);
  margin: 0 auto;
  padding: 48px 0 96px;
  display: grid;
  grid-template-columns: 240px 1fr;
  gap: 64px;
  align-items: start;
}
@media (max-width: 900px) {
  .page-grid { grid-template-columns: 1fr; gap: 32px; padding: 32px 0 64px; }
}

.toc {
  position: sticky;
  top: 88px;
  font-size: 0.875rem;
}
.toc .back {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  color: var(--ink-2);
  font-family: var(--mono);
  font-size: 0.7rem;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  margin-bottom: 36px;
  text-decoration: none;
  transition: color 0.15s ease;
}
.toc .back:hover { color: var(--cobalt); text-decoration: none; }
.toc .back::before { content: "←"; font-size: 1em; }
.toc-section {
  font-family: var(--mono);
  font-size: 0.64rem;
  font-weight: 600;
  color: var(--ink-3);
  letter-spacing: 0.18em;
  text-transform: uppercase;
  margin-bottom: 14px;
  padding-bottom: 10px;
  border-bottom: 1px solid var(--rule);
}
.toc-nav {
  display: flex;
  flex-direction: column;
  gap: 0;
  margin-bottom: 36px;
}
.toc-nav a {
  display: block;
  padding: 10px 0 10px 14px;
  color: var(--ink-2);
  text-decoration: none;
  font-family: var(--mono);
  font-size: 0.76rem;
  letter-spacing: 0.02em;
  border-left: 2px solid var(--rule);
  transition: all 0.15s ease;
}
.toc-nav a:hover {
  color: var(--ink);
  border-left-color: var(--ink-2);
  text-decoration: none;
}
.toc-nav a.active {
  color: var(--cobalt);
  border-left-color: var(--cobalt);
  font-weight: 600;
}
.toc-meta {
  padding: 18px;
  border: 1px solid var(--ink);
  background: var(--paper);
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.toc-meta .meta-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  font-size: 0.82rem;
}
.toc-meta .meta-row .label {
  color: var(--ink-3);
  font-family: var(--mono);
  font-size: 0.64rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
}
@media (max-width: 900px) {
  .toc { position: static; }
  .toc-nav { display: none; }
}

.page-content { min-width: 0; }
.breadcrumb {
  font-family: var(--mono);
  font-size: 0.7rem;
  color: var(--ink-3);
  margin-bottom: 24px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
.breadcrumb a { color: var(--ink-2); text-decoration: none; }
.breadcrumb a:hover { color: var(--cobalt); text-decoration: underline; }
.breadcrumb .sep { margin: 0 10px; color: var(--ink-4); }
.block-id-large {
  font-family: var(--mono);
  font-size: 0.78rem;
  color: var(--cobalt);
  background: var(--cobalt-soft);
  padding: 6px 12px;
  border: 1px solid var(--cobalt);
  display: inline-block;
  margin-bottom: 24px;
  letter-spacing: 0.04em;
}
.page-content h1 {
  font-size: clamp(2.4rem, 5vw, 3.6rem);
  margin-bottom: 28px;
  max-width: 22ch;
  line-height: 1.02;
}
.page-content .lead {
  font-family: var(--display);
  font-size: clamp(1.18rem, 1.6vw, 1.4rem);
  font-weight: 400;
  font-variation-settings: "opsz" 144, "SOFT" 80, "WONK" 0;
  color: var(--ink-2);
  line-height: 1.45;
  letter-spacing: -0.015em;
  margin: 0 0 32px;
  max-width: 60ch;
}
.page-content > .block-tags { margin-bottom: 56px; }
.page-content section {
  padding: 40px 0;
  margin: 0;
  max-width: none;
}
.page-content section:first-of-type { padding-top: 8px; }
.page-content section h2 {
  font-size: 2rem;
  margin-bottom: 24px;
  scroll-margin-top: 96px;
  font-weight: 400;
  font-variation-settings: "opsz" 144, "SOFT" 50, "WONK" 0;
}
.page-content section p {
  color: var(--ink);
  margin: 0 0 14px;
  max-width: 68ch;
}
.page-content section p:last-child { margin-bottom: 0; }

.prereq-list { display: flex; flex-wrap: wrap; gap: 8px; }
.prereq-list .prereq {
  font-family: var(--mono);
  font-size: 0.78rem;
  color: var(--cobalt);
  background: var(--cobalt-soft);
  border: 1px solid var(--cobalt);
  padding: 6px 12px;
  text-decoration: none;
  transition: all 0.15s ease;
  letter-spacing: 0.02em;
}
.prereq-list .prereq:hover {
  background: var(--cobalt);
  color: var(--paper);
  text-decoration: none;
}
.prereq-list .prereq.none {
  background: var(--paper);
  color: var(--ink-3);
  border-color: var(--rule);
  border-style: dashed;
  cursor: default;
}

.tables-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 12px;
}
.table-card {
  border: 1px solid var(--rule-2);
  padding: 20px 22px;
  background: var(--paper);
}
.table-card .table-name {
  font-family: var(--mono);
  font-size: 0.9rem;
  font-weight: 600;
  color: var(--ink);
  margin-bottom: 8px;
  letter-spacing: -0.01em;
}
.table-card .table-desc {
  font-size: 0.88rem;
  color: var(--ink-2);
  line-height: 1.55;
}
.table-card.shared {
  border-style: dashed;
  background: transparent;
}
.table-card.shared .table-name::after {
  content: " (shared)";
  font-family: var(--sans);
  font-size: 0.7rem;
  color: var(--ink-3);
  font-weight: 400;
  letter-spacing: 0;
  text-transform: none;
}

.two-col {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
}
@media (max-width: 700px) { .two-col { grid-template-columns: 1fr; } }
.use-card {
  border: 1px solid var(--rule-2);
  padding: 24px 26px;
  background: var(--paper);
  position: relative;
}
.use-card.yes { border-color: var(--verdict); border-left-width: 4px; }
.use-card.no  { border-color: var(--oxide);   border-left-width: 4px; }
.use-card h5 {
  font-family: var(--mono);
  font-size: 0.7rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.14em;
  margin: 0 0 14px;
}
.use-card.yes h5 { color: var(--verdict); }
.use-card.no h5 { color: var(--oxide); }
.use-card ul {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 10px;
  font-size: 0.92rem;
  color: var(--ink);
}
.use-card li {
  padding-left: 22px;
  position: relative;
  line-height: 1.55;
}
.use-card li::before {
  content: "";
  position: absolute;
  left: 4px;
  top: 0.62em;
  width: 10px;
  height: 2px;
}
.use-card.yes li::before { background: var(--verdict); }
.use-card.no  li::before { background: var(--oxide); }

.files-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 8px;
}
.file-link {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 11px 14px;
  border: 1px solid var(--rule-2);
  background: var(--paper);
  font-family: var(--mono);
  font-size: 0.82rem;
  color: var(--ink-2);
  text-decoration: none;
  transition: all 0.15s ease;
}
.file-link:hover {
  border-color: var(--cobalt);
  color: var(--cobalt);
  background: var(--cobalt-soft);
  text-decoration: none;
}
.file-link .ftype {
  font-size: 0.62rem;
  color: var(--ink-3);
  margin-left: auto;
  padding: 2px 6px;
  border: 1px solid var(--rule-2);
  background: var(--paper-2);
  letter-spacing: 0.1em;
}
.file-link:hover .ftype { color: var(--cobalt); border-color: var(--cobalt); background: var(--paper); }

.prev-next {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
  margin-top: 64px;
  padding-top: 32px;
  border-top: 1.5px solid var(--ink);
}
@media (max-width: 600px) { .prev-next { grid-template-columns: 1fr; } }
.prev-next a {
  display: flex;
  flex-direction: column;
  padding: 22px 24px;
  border: 1px solid var(--rule-2);
  background: var(--paper);
  text-decoration: none;
  transition: all 0.15s ease;
  color: var(--ink);
}
.prev-next a:hover {
  border-color: var(--ink);
  text-decoration: none;
  color: var(--ink);
  background: var(--paper-2);
  transform: translateY(-2px);
}
.prev-next .label {
  font-family: var(--mono);
  font-size: 0.66rem;
  color: var(--ink-3);
  text-transform: uppercase;
  letter-spacing: 0.14em;
  margin-bottom: 10px;
}
.prev-next .title {
  font-family: var(--display);
  font-weight: 500;
  font-size: 1.15rem;
  font-variation-settings: "opsz" 144, "SOFT" 80, "WONK" 0;
  letter-spacing: -0.02em;
}
.prev-next .next { text-align: right; }
.prev-next .placeholder {
  border: 1px dashed var(--rule-2);
  background: transparent;
  opacity: 0.4;
  pointer-events: none;
}

/* ====================== AT-A-GLANCE METABAR ====================== */
.at-a-glance {
  display: grid;
  grid-template-columns: repeat(6, 1fr);
  gap: 0;
  margin: 0 0 56px;
  border: 1px solid var(--ink);
  background: var(--paper);
}
@media (max-width: 900px) { .at-a-glance { grid-template-columns: repeat(3, 1fr); } }
@media (max-width: 480px) { .at-a-glance { grid-template-columns: repeat(2, 1fr); } }
.glance-cell {
  padding: 14px 18px;
  border-right: 1px solid var(--rule);
  border-bottom: 1px solid transparent;
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
}
.glance-cell:last-child { border-right: 0; }
@media (max-width: 900px) {
  .glance-cell:nth-child(3n) { border-right: 0; }
  .glance-cell:nth-child(n+1):nth-child(-n+3) { border-bottom: 1px solid var(--rule); }
}
@media (max-width: 480px) {
  .glance-cell:nth-child(3n) { border-right: 1px solid var(--rule); }
  .glance-cell:nth-child(2n) { border-right: 0; }
  .glance-cell:nth-child(n+1):nth-child(-n+4) { border-bottom: 1px solid var(--rule); }
}
.glance-cell .glance-label {
  font-family: var(--mono);
  font-size: 0.62rem;
  color: var(--ink-3);
  letter-spacing: 0.16em;
  text-transform: uppercase;
}
.glance-cell .glance-value {
  font-family: var(--display);
  font-weight: 500;
  font-size: 1.45rem;
  color: var(--ink);
  font-variation-settings: "opsz" 144, "SOFT" 50, "WONK" 0;
  letter-spacing: -0.02em;
  line-height: 1;
}
.glance-cell .glance-value .unit {
  font-family: var(--mono);
  font-size: 0.58rem;
  color: var(--ink-3);
  margin-left: 4px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  vertical-align: middle;
}

/* ====================== PROBLEM CALLOUT ====================== */
.problem-callout {
  border-left: 3px solid var(--cobalt);
  padding: 4px 0 4px 22px;
  margin: 0 0 8px;
  font-family: var(--display);
  font-size: 1.15rem;
  font-weight: 400;
  font-variation-settings: "opsz" 144, "SOFT" 80, "WONK" 0;
  color: var(--ink);
  line-height: 1.5;
  letter-spacing: -0.015em;
  max-width: 68ch;
}

/* ====================== USER STORIES ====================== */
.user-stories {
  display: flex;
  flex-direction: column;
  gap: 0;
  border: 1px solid var(--rule-2);
  background: var(--paper);
  margin-top: 16px;
}
.user-story {
  display: grid;
  grid-template-columns: 150px 1fr;
  gap: 16px;
  padding: 18px 22px;
  border-bottom: 1px solid var(--rule);
  align-items: baseline;
}
.user-story:last-child { border-bottom: 0; }
.user-story .story-role {
  font-family: var(--mono);
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--cobalt);
  letter-spacing: 0.12em;
  text-transform: uppercase;
}
.user-story .story-text {
  color: var(--ink);
  line-height: 1.55;
  font-size: 0.95rem;
}
@media (max-width: 600px) {
  .user-story { grid-template-columns: 1fr; gap: 6px; }
}

/* ====================== RELATED BLOCKS ====================== */
.related-blocks {
  display: flex;
  flex-direction: column;
  gap: 18px;
  margin-top: 16px;
}
.related-row {
  display: flex;
  align-items: flex-start;
  gap: 18px;
  flex-wrap: wrap;
}
.related-row .related-label {
  font-family: var(--mono);
  font-size: 0.66rem;
  font-weight: 600;
  color: var(--ink-3);
  letter-spacing: 0.16em;
  text-transform: uppercase;
  padding-top: 9px;
  min-width: 130px;
}
.related-row .related-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

/* ====================== THREATS ====================== */
.threats-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin-top: 16px;
}
.threat-card {
  display: grid;
  grid-template-columns: 52px 1fr auto;
  gap: 20px;
  align-items: center;
  padding: 18px 22px;
  border: 1px solid var(--rule-2);
  background: var(--paper);
  border-left-width: 4px;
}
.threat-card.critical { border-left-color: var(--oxide); }
.threat-card.medium   { border-left-color: var(--sun); }
.threat-card.low      { border-left-color: var(--verdict); }
.threat-card .threat-num {
  font-family: var(--display);
  font-size: 1.65rem;
  font-weight: 500;
  color: var(--ink-3);
  font-variation-settings: "opsz" 144, "SOFT" 50, "WONK" 0;
  letter-spacing: -0.02em;
  line-height: 1;
  text-align: center;
}
.threat-card .threat-body { min-width: 0; }
.threat-card .threat-name {
  font-family: var(--display);
  font-weight: 500;
  font-size: 1.1rem;
  font-variation-settings: "opsz" 144, "SOFT" 80, "WONK" 0;
  letter-spacing: -0.015em;
  color: var(--ink);
  line-height: 1.2;
}
.threat-card .threat-desc {
  font-size: 0.88rem;
  color: var(--ink-2);
  margin-top: 6px;
  line-height: 1.5;
}
.threat-card .threat-impact {
  font-family: var(--mono);
  font-size: 0.66rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  padding: 5px 10px;
  border: 1px solid currentColor;
  white-space: nowrap;
  color: var(--ink-2);
  background: var(--paper-2);
}
.threat-impact.critical { color: var(--oxide); background: var(--oxide-soft); }
.threat-impact.medium   { color: var(--sun); background: var(--sun-soft); }
.threat-impact.low      { color: var(--verdict); background: var(--verdict-soft); }
@media (max-width: 600px) {
  .threat-card { grid-template-columns: 40px 1fr; }
  .threat-card .threat-impact { grid-column: 2; justify-self: start; margin-top: 8px; }
}

/* ====================== VERIFICATION ====================== */
.verify-summary {
  font-family: var(--sans);
  font-size: 0.98rem;
  color: var(--ink-2);
  margin: 0 0 18px;
  line-height: 1.55;
  max-width: 60ch;
}
.verify-summary .verify-count {
  font-family: var(--display);
  font-size: 1.2rem;
  color: var(--cobalt);
  font-weight: 600;
  font-variation-settings: "opsz" 144, "SOFT" 50, "WONK" 0;
  letter-spacing: -0.02em;
  padding: 0 4px 0 2px;
}
.verify-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: 0;
  border: 1px solid var(--rule-2);
  background: var(--paper);
}
.verify-cell {
  padding: 14px 18px;
  border-right: 1px solid var(--rule);
  border-bottom: 1px solid var(--rule);
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  gap: 12px;
}
.verify-cell .verify-name {
  font-size: 0.9rem;
  color: var(--ink);
  font-weight: 500;
}
.verify-cell .verify-checks {
  font-family: var(--mono);
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--cobalt);
  letter-spacing: 0.06em;
  white-space: nowrap;
  text-transform: uppercase;
}

/* ====================== SCENARIOS (Gherkin, compact) ====================== */
.feature-block { margin: 0 0 28px; }
.feature-block + .feature-block { margin-top: 24px; }
.feature-head {
  display: flex;
  align-items: baseline;
  gap: 14px;
  flex-wrap: wrap;
  margin: 0 0 10px;
  padding-bottom: 8px;
  border-bottom: 1px solid var(--rule);
}
.feature-head .feature-name {
  font-family: var(--display);
  font-size: 1.15rem;
  font-weight: 500;
  font-variation-settings: "opsz" 144, "SOFT" 80, "WONK" 0;
  letter-spacing: -0.015em;
  color: var(--ink);
  line-height: 1.2;
}
.feature-head .feature-link {
  font-family: var(--mono);
  font-size: 0.7rem;
  color: var(--ink-3);
  letter-spacing: 0.04em;
  margin-left: auto;
  text-decoration: none;
}
.feature-head .feature-link:hover { color: var(--cobalt); text-decoration: underline; }

.scenario-list {
  list-style: none;
  margin: 0;
  padding: 0;
}
.scenario-row {
  display: grid;
  grid-template-columns: 64px 1fr;
  gap: 14px;
  align-items: baseline;
  padding: 6px 0;
  font-size: 0.92rem;
}
.scenario-row .scenario-tag {
  font-family: var(--mono);
  font-size: 0.64rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  text-align: right;
  white-space: nowrap;
}
.scenario-tag.happy   { color: var(--verdict); }
.scenario-tag.error   { color: var(--oxide); }
.scenario-tag.edge    { color: var(--sun); }
.scenario-tag.neutral { color: var(--ink-3); }
.scenario-row .scenario-name {
  color: var(--ink);
  line-height: 1.45;
}

/* ====================== FILES — GROUPED ====================== */
.files-section { margin: 0 0 24px; }
.files-section .files-section-head {
  display: flex;
  align-items: baseline;
  gap: 14px;
  margin: 0 0 10px;
  padding: 8px 0 8px;
  border-bottom: 1px solid var(--rule);
}
.files-section .files-section-name {
  font-family: var(--mono);
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--ink);
  letter-spacing: 0.18em;
  text-transform: uppercase;
}
.files-section .files-section-count {
  font-family: var(--mono);
  font-size: 0.66rem;
  color: var(--ink-3);
  letter-spacing: 0.06em;
  margin-left: auto;
}

.hidden { display: none !important; }

/* ====================== ENTRANCE MOTION ====================== */
@keyframes fadeUp {
  from { opacity: 0; transform: translateY(14px); }
  to   { opacity: 1; transform: translateY(0); }
}
.hero-tag, .hero h1, .hero .tagline, .hero .ctas, .title-block {
  animation: fadeUp 0.7s cubic-bezier(0.2, 0.6, 0.2, 1) both;
}
.hero h1       { animation-delay: 0.08s; }
.hero .tagline { animation-delay: 0.16s; }
.hero .ctas    { animation-delay: 0.24s; }
.title-block   { animation-delay: 0.32s; }

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
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
<link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght,SOFT,WONK@0,9..144,400..600,30..100,0..1;1,9..144,400..600,30..100,0..1&family=IBM+Plex+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="${cssPath}">
</head>
<body>`;
}

function siteHeader(rootPath = "") {
  return `<header class="site">
  <nav class="nav">
    <a href="${rootPath || "./"}" class="brand">
      <span class="brand-mark">§</span>
      <span>Primitive Block Library</span>
    </a>
    <ul class="nav-links">
      <li><a href="${rootPath}#example">Example</a></li>
      <li><a href="${rootPath}#philosophy">Why</a></li>
      <li><a href="${rootPath}#consume">Workflow</a></li>
      <li><a href="${rootPath}#blocks">Blocks</a></li>
      <li><a class="github" href="${REPO_HTTPS}" target="_blank" rel="noopener">GitHub ↗</a></li>
    </ul>
  </nav>
</header>`;
}

function siteFooter() {
  return `<footer class="site">
  <div class="footer-inner">
    <p>
      <a href="${REPO_HTTPS}" target="_blank" rel="noopener">github.com/nguyenvanduocit/primitive-blocks-specs</a>
    </p>
    <p>
      Spec discipline: <a href="${REPO_BLOB}/docs/SPEC_GUIDELINES.md" target="_blank" rel="noopener">SPEC_GUIDELINES.md</a>
    </p>
  </div>
</footer>`;
}

// ============================================================================
// LANDING PAGE
// ============================================================================
function renderLanding() {
  const total = BLOCKS.length;
  const totalStr = String(total).padStart(2, "0");
  const cardsHtml = BLOCKS.map((b, i) => {
    const idx = String(i + 1).padStart(2, "0");
    return `
        <a class="block-card" data-cat="${b.category}" href="blocks/${b.id}.html">
          <span class="arrow" aria-hidden="true">→</span>
          <div class="card-num">
            <span class="num-main">${idx}</span>
            <span class="num-divider" aria-hidden="true"></span>
            <span class="num-total">${totalStr}</span>
          </div>
          <div class="card-body">
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
          </div>
        </a>`;
  }).join("");

  const filterPills = (() => {
    const counts = {};
    BLOCKS.forEach(b => counts[b.category] = (counts[b.category] || 0) + 1);
    const pills = [`<button class="filter-pill active" data-cat="all">All<span class="count">${BLOCKS.length}</span></button>`];
    Object.keys(counts).sort().forEach(cat => {
      pills.push(`<button class="filter-pill" data-cat="${cat}">${cat}<span class="count">${counts[cat]}</span></button>`);
    });
    return pills.join("");
  })();
  const categories = new Set(BLOCKS.map(b => b.category)).size;

  return `${headTags(
    "Primitive Block Library — AI-native feature blueprints",
    "Complete designs for features. Read by Claude Code, adapted to your stack, implemented into your codebase. Stack-agnostic specs across auth, billing, compliance, data, integration, messaging, operations, UGC, and webhooks.",
    { cssPath: "assets/style.css" }
  )}

${siteHeader("")}

<main>
  <section class="hero">
    <div class="hero-grid">
      <div class="hero-text">
        <span class="hero-tag">Feature blueprints for Shopify apps &amp; primitives</span>
        <h1>Skip the boilerplate.<br/><em>Ship</em> the feature.</h1>
        <p class="tagline">
          Each blueprint is the complete spec of one feature &mdash; data model, flows,
          security threats, acceptance checks. Claude Code reads the spec, adapts it to
          your stack, writes the code, runs the checks. You review the diff and ship.
        </p>
        <div class="ctas">
          <a class="btn primary" href="#blocks">Browse ${BLOCKS.length} blocks</a>
          <a class="btn" href="${REPO_HTTPS}" target="_blank" rel="noopener">View on GitHub</a>
        </div>
      </div>
      <aside class="title-block" aria-label="Library at a glance">
        <div class="tb-row">
          <span class="tb-label">Blocks</span>
          <span class="tb-value">${BLOCKS.length}</span>
        </div>
        <div class="tb-row">
          <span class="tb-label">Categories</span>
          <span class="tb-value">${categories}</span>
        </div>
        <div class="tb-row">
          <span class="tb-label">Tested stacks</span>
          <span class="tb-value">3</span>
        </div>
        <div class="tb-row">
          <span class="tb-label">Stack-agnostic</span>
          <span class="tb-value">100%</span>
        </div>
      </aside>
    </div>
  </section>

  <section id="example">
    <div class="section-rule">
      <span class="section-label">Example</span>
      <span class="section-line"></span>
    </div>
    <div class="example-spread">
      <div class="example-text">
        <h2>One block, one feature.</h2>
        <p>
          Take <a href="blocks/auth.shopify-oauth.html"><code>auth.shopify-oauth</code></a> &mdash;
          the install handshake every Shopify app must implement. Drop the spec on Claude Code.
          It picks your SQL dialect, your framework, your secrets vault. Writes the install
          handler, callback, nonce store, token encryption, uninstall hook. Runs the
          acceptance checks until green.
        </p>
        <p style="margin-top: 16px;">
          <strong>~45 minutes from spec to merged PR.</strong>
        </p>
      </div>
      <aside class="title-block example-stats" aria-label="auth.shopify-oauth at a glance">
        <div class="tb-row"><span class="tb-label">Files</span><span class="tb-value">9</span></div>
        <div class="tb-row"><span class="tb-label">Tables</span><span class="tb-value">2</span></div>
        <div class="tb-row"><span class="tb-label">Scenarios</span><span class="tb-value">19</span></div>
        <div class="tb-row"><span class="tb-label">Threats</span><span class="tb-value">5</span></div>
        <div class="tb-row"><span class="tb-label">Checks</span><span class="tb-value">36</span></div>
      </aside>
    </div>
  </section>

  <section id="philosophy">
    <div class="section-rule">
      <span class="section-label">Why a spec, not a library</span>
      <span class="section-line"></span>
    </div>
    <div class="section-header">
      <h2>Ship the <em>spec</em>, not the lib.</h2>
      <p>
        A code library locks in your framework, your ORM, your auth choice. The minute the
        stack diverges &mdash; fork, patch, maintain. Now agents can read your codebase,
        run your build, and write code that fits. So ship knowledge, not code.
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

  </section>

  <section id="consume">
    <div class="section-rule">
      <span class="section-label">Workflow</span>
      <span class="section-line"></span>
    </div>
    <div class="section-header">
      <h2>How a block <em>becomes</em> code.</h2>
      <p>
        Claude Code runs in your project with full filesystem access. It treats every block
        as a reference &mdash; reads it, understands your stack, adapts, implements, verifies.
      </p>
    </div>
    <div class="flow-steps">
      <div class="flow-step"><div class="step-num">STEP 01</div><h4>Discover</h4><p>Match your request against the library by tag, category, and overview.</p></div>
      <div class="flow-step"><div class="step-num">STEP 02</div><h4>Configure</h4><p>Ask the few business decisions that change behavior &mdash; currency, plan tiers, scopes. You answer in plain language.</p></div>
      <div class="flow-step"><div class="step-num">STEP 03</div><h4>Clone</h4><p>Copy the block into your project as a customized blueprint &mdash; the source library stays untouched.</p></div>
      <div class="flow-step"><div class="step-num">STEP 04</div><h4>Implement</h4><p>Translate the spec into code that follows your conventions and framework choices.</p></div>
      <div class="flow-step"><div class="step-num">STEP 05</div><h4>Verify</h4><p>Run the acceptance checklist: migrations, tests, type-check, lint, security mitigations.</p></div>
    </div>
  </section>

  <section id="blocks">
    <div class="section-rule">
      <span class="section-label">The library</span>
      <span class="section-line"></span>
    </div>
    <div class="section-header">
      <h2>${BLOCKS.length} blocks. <em>Ready to ship.</em></h2>
      <p>Click any block to open its spec page: problem, dependencies, data model, and direct links to every file.</p>
    </div>

    <div class="filter-bar" role="tablist" aria-label="Filter blocks by category">${filterPills}</div>

    <div class="block-grid" id="block-grid">${cardsHtml}
    </div>
    <div class="empty-state hidden" id="empty-state">No blocks match this category yet.</div>
  </section>

  <section id="layers">
    <div class="section-rule">
      <span class="section-label">For block authors</span>
      <span class="section-line"></span>
    </div>
    <div class="section-header">
      <h2>Three layers in every spec.</h2>
      <p>
        Writing a new block? Every spec follows a 3-layer abstraction discipline so it stays stack-agnostic &mdash;
        the agent can implement it on any SQL family, any framework, any runtime, without spec changes.
      </p>
    </div>
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
    <p style="margin-top: 24px;">
      Full authoring rules: <a href="${REPO_BLOB}/docs/SPEC_GUIDELINES.md" target="_blank" rel="noopener">SPEC_GUIDELINES.md &rarr;</a>
    </p>
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

function renderBlock(b, prev, next, allBlocks, index, total) {
  // ---- Source-file enrichments ----
  const readme = readSource(b.folder, "README.md");
  const securityMd = readSource(b.folder, "security.md");
  const acceptanceMd = readSource(b.folder, "acceptance.md");

  const problem = extractProblemStatement(readme);
  const features = readBlockFeatures(b);
  const threats = extractThreats(securityMd);
  const acceptance = extractAcceptance(acceptanceMd);
  const requiredBy = getRequiredBy(b, allBlocks);
  const fileGroups = groupFiles(b.files);

  // ---- Block-data renders ----
  const prereqChips = b.prerequisites.length
    ? b.prerequisites.map(p => `<a class="prereq" href="${p}.html">${p}</a>`).join("")
    : '<span class="prereq none">none</span>';

  const requiredByChips = requiredBy.length
    ? requiredBy.map(r => `<a class="prereq" href="${r.id}.html" title="${escapeHtml(r.name)}">${r.id}</a>`).join("")
    : '<span class="prereq none">none</span>';

  const tablesHtml = b.tables.length
    ? `<div class="tables-grid">${b.tables.map(t =>
        `<div class="table-card${t.shared ? ' shared' : ''}">
          <div class="table-name">${t.name}</div>
          <div class="table-desc">${t.desc}</div>
        </div>`
      ).join("")}</div>`
    : '<p style="color: var(--ink-2);">This block introduces no new tables.</p>';

  // ---- File groups ----
  const renderFileGroup = (label, files) => files.length
    ? `<div class="files-section">
        <div class="files-section-head">
          <span class="files-section-name">${label}</span>
          <span class="files-section-count">${files.length}</span>
        </div>
        <div class="files-grid">${files.map(f =>
          `<a class="file-link" href="${REPO_BLOB}/${b.folder}/${f}" target="_blank" rel="noopener">${f}<span class="ftype">${fileType(f)}</span></a>`
        ).join("")}</div>
      </div>`
    : "";
  const filesGroupedHtml =
    renderFileGroup("Documentation", fileGroups.docs) +
    renderFileGroup("Scenarios", fileGroups.scenarios) +
    renderFileGroup("Fixtures", fileGroups.fixtures) +
    renderFileGroup("Acceptance", fileGroups.acceptance);

  // ---- Threats section ----
  const sevClass = sev => {
    if (!sev) return "";
    if (sev === "critical" || sev === "high") return "critical";
    if (sev === "medium") return "medium";
    if (sev === "low") return "low";
    return "";
  };
  const threatsHtml = threats.length
    ? `<div class="threats-list">${threats.map(t => {
        const cls = sevClass(t.severity);
        return `<div class="threat-card ${cls}">
          <div class="threat-num">${t.num}</div>
          <div class="threat-body">
            <div class="threat-name">${renderInline(t.name)}</div>
            ${t.desc ? `<div class="threat-desc">${renderInline(t.desc)}</div>` : ""}
          </div>
          ${t.severityRaw ? `<span class="threat-impact ${cls}">${escapeHtml(t.severityRaw)}</span>` : ""}
        </div>`;
      }).join("")}</div>`
    : "";

  // ---- Verification section ----
  const verificationHtml = acceptance.sections.length
    ? `<p class="verify-summary">
         <span class="verify-count">${acceptance.total}</span> checks across
         <span class="verify-count">${acceptance.sections.length}</span> groups.
       </p>
       <div class="verify-grid">${acceptance.sections.map(s =>
         `<div class="verify-cell">
            <span class="verify-name">${escapeHtml(s.name)}</span>
            <span class="verify-checks">${s.count}</span>
          </div>`
       ).join("")}</div>
       <p style="margin-top:18px;"><a href="${REPO_BLOB}/${b.folder}/acceptance.md" target="_blank" rel="noopener">Full checklist on GitHub &rarr;</a></p>`
    : "";

  // ---- Scenarios (Gherkin .feature files) — name-only list, no step detail ----
  const tagClass = tag => {
    const t = tag.toLowerCase();
    if (t === "happy") return "happy";
    if (t === "error" || t === "security") return "error";
    if (t === "edge") return "edge";
    return "neutral";
  };
  const scenariosHtml = features.length
    ? features.map(({ filename, parsed }) => {
        const rows = parsed.scenarios.map(s => {
          const primary = (s.tags[0] || "scenario").toLowerCase();
          return `<li class="scenario-row">
            <span class="scenario-tag ${tagClass(primary)}">${escapeHtml(primary)}</span>
            <span class="scenario-name">${escapeHtml(s.name)}</span>
          </li>`;
        }).join("");
        return `<div class="feature-block">
          <div class="feature-head">
            <span class="feature-name">${escapeHtml(parsed.feature)}</span>
            <a class="feature-link" href="${REPO_BLOB}/${b.folder}/${filename}" target="_blank" rel="noopener">${filename} &nearr;</a>
          </div>
          <ul class="scenario-list">${rows}</ul>
        </div>`;
      }).join("")
    : "";

  // ---- At-a-glance metabar removed — too noisy now that most sections are gone. ----

  // ---- TOC items (conditional, skip duplicate "Overview" since lead == summary) ----
  const tocItems = [
    problem ? ["problem", "Problem"] : null,
    ["prerequisites", "Dependencies"],
    ["data-model", "Data model"],
    ["files", "Spec files"],
  ].filter(Boolean);
  const tocNavHtml = tocItems.map((item, i) =>
    `<a href="#${item[0]}"${i === 0 ? ' class="active"' : ""}>${item[1]}</a>`
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
      <nav class="toc-nav">${tocNavHtml}</nav>
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
      </div>
      <span class="block-id-large">${b.id}</span>
      <h1>${b.name}</h1>
      <p class="lead">${b.summary}</p>
      <div class="block-tags">${b.tags.map(t => `<span class="tag">${t}</span>`).join("")}</div>

      ${problem ? `
      <section id="problem">
        <div class="section-rule">
          <span class="section-label">Problem</span>
          <span class="section-line"></span>
        </div>
        <p class="problem-callout">${renderInline(problem)}</p>
      </section>` : ""}

      <section id="prerequisites">
        <div class="section-rule">
          <span class="section-label">Dependencies</span>
          <span class="section-line"></span>
        </div>
        <div class="related-blocks">
          <div class="related-row">
            <span class="related-label">Depends on</span>
            <div class="related-chips">${prereqChips}</div>
          </div>
          <div class="related-row">
            <span class="related-label">Required by</span>
            <div class="related-chips">${requiredByChips}</div>
          </div>
        </div>
      </section>

      <section id="data-model">
        <div class="section-rule">
          <span class="section-label">Data model</span>
          <span class="section-line"></span>
        </div>
        ${tablesHtml}
      </section>

      <section id="files">
        <div class="section-rule">
          <span class="section-label">Spec files</span>
          <span class="section-line"></span>
        </div>
        ${filesGroupedHtml}
        <p style="margin-top: 24px;"><a href="${REPO_TREE}/${b.folder}" target="_blank" rel="noopener">Browse <code>${b.folder}/</code> on GitHub &rarr;</a></p>
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
    written.push(emit(`blocks/${b.id}.html`, renderBlock(b, prev, next, BLOCKS, i, BLOCKS.length)));
  });
  console.log(`Built ${written.length} files:`);
  written.forEach(p => console.log("  " + p.replace(resolve(DOCS, ".."), ".")));
  console.log(`\n${BLOCKS.length} blocks, ${new Set(BLOCKS.map(b => b.category)).size} categories.`);
}

main();
