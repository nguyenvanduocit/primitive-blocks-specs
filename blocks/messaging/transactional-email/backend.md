# Backend — Transactional Email

## API Endpoints

### Template Management (Admin)

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/email-templates` | List templates for current shop | admin |
| `GET` | `/api/email-templates/:id` | Get single template | admin |
| `POST` | `/api/email-templates` | Create template | admin |
| `PUT` | `/api/email-templates/:id` | Update template | admin |
| `DELETE` | `/api/email-templates/:id` | Delete template | admin |
| `POST` | `/api/email-templates/:id/preview` | Render template with sample data | admin |
| `POST` | `/api/email-templates/:id/duplicate` | Clone template with new slug | admin |

### Email Log (Admin, read-only)

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `GET` | `/api/email-log` | List send log (paginated, filterable by status/template) | admin |
| `GET` | `/api/email-log/:id` | Get single log entry | admin |

### Provider Webhook (Public, signature-verified)

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| `POST` | `/api/webhooks/email` | Delivery status updates from provider | Webhook signature |

External contract notes for provider webhooks (provider-dictated, header names case-sensitive):

| Provider | Signature header | Algorithm |
|----------|-----------------|-----------|
| Resend | `svix-signature` (and `svix-id`, `svix-timestamp`) | HMAC-SHA256 (Svix-spec) — sign `${svix_id}.${svix_timestamp}.${body}` |
| SendGrid | `X-Twilio-Email-Event-Webhook-Signature` (+ `X-Twilio-Email-Event-Webhook-Timestamp`) | ECDSA-SHA256 over `${timestamp}${body}` |
| Amazon SES | SNS `X-Amz-Sns-Message-Type` + signed payload | SHA1WithRSA per SNS spec |

---

## Core Patterns

### Provider Adapter

Abstract over the chosen email provider so business logic depends on the interface, not a specific SDK.

<!-- PATTERN: email-provider-adapter -->
<!-- PURPOSE: Define a stable interface for send + webhook-verify across email providers — keep business logic provider-agnostic -->
<!-- REFERENCE: language=typescript runtime=node20+ -->
<!-- ADAPT:
       - Choose ONE provider per deployment (don't ship multiple adapters at once); provider names go in the factory below — common choices: Resend, SendGrid, Amazon SES, Postmark, Mailgun
       - SDK import: e.g. Resend `import { Resend } from "resend"`; SendGrid `import sgMail from "@sendgrid/mail"`; SES `import { SESClient, SendEmailCommand } from "@aws-sdk/client-ses"`; Postmark `import { ServerClient } from "postmark"`
       - Error mapping: each SDK throws differently — adapter MUST normalize to `{ status: number, message: string }` so `isPermanentError` (below) classifies consistently
       - `verifyWebhookSignature` body: per-provider HMAC scheme — see external contract table above; never share code between providers' signature verification logic (each is its own contract) -->

```typescript
interface EmailProviderAdapter {
  send(params: {
    from: string;
    to: string;
    subject: string;
    html: string;
    replyTo?: string;
    headers?: Record<string, string>;
  }): Promise<{ messageId: string }>;

  verifyWebhookSignature(params: {
    payload: string;
    headers: Record<string, string>;
    secret: string;
  }): boolean;
}

function createEmailProvider(provider: string): EmailProviderAdapter {
  // Resolve concrete adapter from EMAIL_PROVIDER env (see ADAPT above for choices)
  switch (provider) {
    default: throw new Error(`Unknown email provider: ${provider}`);
  }
}
```

### Template Engine (sandboxed)

<!-- PATTERN: email-template-render -->
<!-- PURPOSE: Render subject + body from a logic-less template with HTML auto-escape; pre-escape variable values to block template-injection via user input -->
<!-- REFERENCE: language=typescript -->
<!-- ADAPT:
       - Engine: Handlebars (`handlebars` npm) shown; equivalents — Mustache (`mustache`), Liquid (`liquidjs`), Pug, Jinja2 (Python). MUST be logic-less / sandboxable — no filesystem/env/runtime access from templates
       - Auto-escape: confirm engine's default — Handlebars `{{var}}` escapes HTML, `{{{var}}}` raw; if engine doesn't auto-escape (e.g., Mustache 5+), wrap output through a sanitizer (DOMPurify server-side, sanitize-html)
       - `hbs.create()`: produces an isolated instance with no inherited helpers — DO NOT register helpers that read fs/env/process -->

```typescript
import Handlebars from "handlebars";

const hbs = Handlebars.create(); // sandboxed — no fs/env/process helpers

function renderTemplate(
  template: { subject_template: string; body_template: string },
  variables: Record<string, unknown>
): { subject: string; body: string } {
  const safeVars = sanitizeVariables(variables);
  return {
    subject: hbs.compile(template.subject_template)(safeVars),
    body: hbs.compile(template.body_template)(safeVars),
  };
}
```

<!-- PATTERN: email-variable-sanitize -->
<!-- PURPOSE: Pre-escape `{{` and `}}` in user-supplied string values — prevents user input from being interpreted as template syntax (SSTI defense) -->
<!-- REFERENCE: language=typescript -->
<!-- ADAPT:
       - Escape strategy: HTML entity (`&#123;`) shown — works for Handlebars/Mustache; for engines with different delimiters (`{%`/`%}` Liquid, Jinja) escape THOSE delimiters
       - Non-string values: numbers/booleans/objects passed through — engine handles serialization; if you accept nested objects, recurse before rendering -->

```typescript
function sanitizeVariables(vars: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(vars)) {
    result[key] = typeof value === "string"
      ? value.replace(/\{\{/g, "&#123;&#123;").replace(/\}\}/g, "&#125;&#125;")
      : value;
  }
  return result;
}
```

### Send Email Handler (idempotent pipeline)

The handler composes 4 narrow patterns: **idempotency → suppression → resolve+render → enqueue+send**. Each is independently testable.

<!-- PATTERN: email-idempotency-check -->
<!-- PURPOSE: Reject duplicate sends for the same `(event_id, template_slug, to)` triple — exploits the UNIQUE constraint on `email_log.idempotency_key` -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `db.emailLog.findByIdempotencyKey`: ORM-specific — Drizzle `db.select().from(emailLog).where(eq(emailLog.idempotencyKey, k))`; Prisma `prisma.emailLog.findUnique({ where: { idempotencyKey: k } })`; raw SQL `SELECT 1 FROM email_log WHERE idempotency_key = $1` (postgres) / `?` (MySQL)
       - Idempotency key shape `${eventId}:${templateSlug}:${to}`: domain contract — do not change format; downstream `email_log` queries assume this -->

```typescript
async function isAlreadySent(idempotencyKey: string): Promise<boolean> {
  const existing = await db.emailLog.findByIdempotencyKey(idempotencyKey);
  return existing != null;
}
```

<!-- PATTERN: email-suppression-check -->
<!-- PURPOSE: Skip sends to suppressed recipients (hard-bounced, complained, manually blocked) — protects sender reputation -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `db.emailSuppressions.find`: ORM-specific (see provider-adapter ADAPT for ORM equivalents); query is `WHERE shop_id = $1 AND email = $2`
       - Returning `{ reason }` for logging: caller writes the suppression reason into `email_log.error` for audit — preserve the reason verbatim -->

```typescript
async function checkSuppression(
  shopId: string, to: string
): Promise<{ suppressed: false } | { suppressed: true; reason: string }> {
  const row = await db.emailSuppressions.find(shopId, to);
  return row ? { suppressed: true, reason: row.reason } : { suppressed: false };
}
```

<!-- PATTERN: email-resolve-and-render -->
<!-- PURPOSE: Look up template (shop-specific with platform-default fallback), confirm active, render subject + body -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - Template lookup `(shop_id=$1 OR shop_id IS NULL) ORDER BY shop_id NULLS LAST LIMIT 1`: postgres syntax for NULL ordering — MySQL: `ORDER BY shop_id IS NULL ASC` (or `ORDER BY shop_id DESC` since non-NULL > NULL by default); SQLite: same as postgres or use COALESCE
       - `renderTemplate`: from `email-template-render` pattern above
       - Returning `null` for inactive/missing — caller decides to log+skip; do NOT throw (templates being absent or inactive is a normal control-plane state, not an error) -->

```typescript
async function resolveAndRender(
  shopId: string, templateSlug: string, variables: Record<string, unknown>
): Promise<{ subject: string; body: string } | null> {
  const template = await db.emailTemplates.findByShopAndSlug(shopId, templateSlug);
  if (!template || !template.active) return null;
  return renderTemplate(template, variables);
}
```

<!-- PATTERN: email-log-suppressed-send -->
<!-- PURPOSE: Record the suppression event in email_log so audit trail captures why a send was skipped -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT: `db.emailLog.insert` is ORM-specific (see `email-idempotency-check` ADAPT for ORM equivalents); status `'failed'` with `error: 'suppressed: <reason>'` is the audit-trail contract — keep verbatim -->

```typescript
async function logSuppressedSend(
  shopId: string, idempotencyKey: string, to: string,
  templateSlug: string, reason: string
): Promise<void> {
  await db.emailLog.insert({
    shopId, idempotencyKey, toAddress: to,
    subject: "", templateSlug,
    status: "failed", error: `suppressed: ${reason}`,
  });
}
```

<!-- PATTERN: email-send-handler -->
<!-- PURPOSE: Top-level event handler — compose idempotency, suppression, render, enqueue, and dispatch in strict order -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - Event shape `{ eventId, shopId, templateSlug, to, variables }`: domain contract — adjust extraction if event bus delivers a different envelope
       - `rateLimiter.checkOrThrow`: see `email-rate-limiter` below
       - `from` formatting `"Name <email>"`: RFC 5322 mailbox spec — all providers accept this; some accept separate `fromName`/`fromAddress` fields — adapter normalizes -->

```typescript
async function handleSendEmail(event: {
  eventId: string; shopId: string; templateSlug: string;
  to: string; variables: Record<string, unknown>;
}): Promise<void> {
  const key = `${event.eventId}:${event.templateSlug}:${event.to}`;
  if (await isAlreadySent(key)) return;

  const sup = await checkSuppression(event.shopId, event.to);
  if (sup.suppressed) {
    return logSuppressedSend(event.shopId, key, event.to, event.templateSlug, sup.reason);
  }

  await rateLimiter.checkOrThrow(event.shopId, event.to);
  const rendered = await resolveAndRender(event.shopId, event.templateSlug, event.variables);
  if (!rendered) return; // template missing or inactive — silent skip
  validateEmailHeaders(event.to, rendered.subject);

  const log = await db.emailLog.insert({
    shopId: event.shopId, idempotencyKey: key, toAddress: event.to,
    subject: rendered.subject, templateSlug: event.templateSlug,
    status: "queued", metadata: event.variables,
  });
  await sendWithRetry(log.id, {
    from: `${config.FROM_NAME} <${config.FROM_EMAIL}>`,
    to: event.to, subject: rendered.subject, html: rendered.body,
    replyTo: config.REPLY_TO || undefined,
  });
}
```

### Retry with Exponential Backoff

<!-- PATTERN: email-send-with-retry -->
<!-- PURPOSE: Retry transient provider failures (5xx / timeout) with exponential backoff; fail fast on permanent errors (4xx) -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `provider.send`: from `email-provider-adapter` interface
       - `sleep(ms)`: `await new Promise(r => setTimeout(r, ms))` in Node; `Bun.sleep(ms)` in Bun; same `setTimeout` works in Deno/edge
       - Backoff curve `baseDelay * 2^(attempt-1)`: exponential — add `Math.random() * baseDelay` for jitter if many parallel workers retry simultaneously (avoid thundering herd) -->

```typescript
async function sendWithRetry(
  logId: string,
  params: { from: string; to: string; subject: string; html: string; replyTo?: string }
): Promise<void> {
  const max = config.EMAIL_MAX_RETRIES, base = config.EMAIL_RETRY_BASE_DELAY_MS;
  for (let attempt = 1; attempt <= max; attempt++) {
    try {
      const { messageId } = await provider.send(params);
      await db.emailLog.update(logId, {
        status: "sent", providerMessageId: messageId, sentAt: new Date(),
      });
      return;
    } catch (err) {
      if (isPermanentError(err) || attempt === max) {
        await db.emailLog.update(logId, { status: "failed", error: errMessage(err) });
        return;
      }
      await sleep(base * Math.pow(2, attempt - 1));
    }
  }
}
```

<!-- PATTERN: email-error-classifier -->
<!-- PURPOSE: Distinguish permanent (4xx) from transient (5xx / network) provider errors — permanent = no retry -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - Status extraction: adapter normalizes to `{ status: number }`; if SDK exposes `err.response.status` or `err.statusCode`, unwrap in the adapter, not here
       - Network errors (no status — DNS failure, ECONNRESET): treat as transient by returning `false` → caller retries -->

```typescript
function isPermanentError(err: unknown): boolean {
  if (err && typeof err === "object" && "status" in err) {
    const s = (err as { status: number }).status;
    return s >= 400 && s < 500;
  }
  return false;
}

function errMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
```

### Webhook Handler (delivery status updates)

The webhook handler splits into: **verify → parse → update log → auto-suppress**.

<!-- PATTERN: email-webhook-verify -->
<!-- PURPOSE: Verify provider webhook signature using EMAIL_WEBHOOK_SECRET BEFORE parsing the body — rejects forged delivery/bounce reports -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `rawBody`: MUST be the raw request body bytes — DO NOT pre-parse JSON before signature check (many frameworks parse by default; disable JSON body parsing on this route or use a `raw` body parser)
       - Header names: provider-dictated, case-sensitive — see external contract table at top (Resend `svix-signature`; SendGrid `X-Twilio-Email-Event-Webhook-Signature`; SES via SNS) -->

```typescript
function verifyWebhook(rawBody: string, headers: Record<string, string>): void {
  const ok = provider.verifyWebhookSignature({
    payload: rawBody,
    headers,
    secret: config.EMAIL_WEBHOOK_SECRET,
  });
  if (!ok) throw new HttpError(401, "Invalid webhook signature");
}
```

<!-- PATTERN: email-webhook-apply -->
<!-- PURPOSE: After signature verified, parse event and update email_log status; auto-add to suppressions on hard bounce or complaint -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `parseWebhookEvent`: provider-specific — Resend returns `{ type, data: { email_id, ... } }`; SendGrid sends an array of events `[{ event, sg_message_id, ... }]` — adapter normalizes to `{ messageId, status, bounceType? }`
       - `db.emailSuppressions.upsert`: ORM-specific (postgres `INSERT ... ON CONFLICT (shop_id, email) DO UPDATE`; MySQL `INSERT ... ON DUPLICATE KEY UPDATE`; SQLite `INSERT ... ON CONFLICT(shop_id, email) DO UPDATE`)
       - Unknown messageId (no matching log row) — silently skip (logs from before this app was deployed, retry storms with stale IDs) -->

```typescript
async function applyWebhookEvent(event: {
  messageId: string; status: string; bounceType?: string;
}): Promise<void> {
  const log = await db.emailLog.findByProviderMessageId(event.messageId);
  if (!log) return;

  await db.emailLog.update(log.id, { status: event.status });

  const autoSuppressReason =
    event.status === "bounced" && event.bounceType === "hard" ? "hard_bounce" :
    event.status === "complained" ? "complaint" : null;

  if (autoSuppressReason) {
    await db.emailSuppressions.upsert({
      shopId: log.shopId, email: log.toAddress,
      reason: autoSuppressReason, sourceLogId: log.id,
    });
  }
}
```

<!-- PATTERN: email-webhook-handler -->
<!-- PURPOSE: Compose verify → parse → apply for the webhook route -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - `parseWebhookEvent(rawBody)`: same as `email-webhook-apply` ADAPT — provider-specific normalization
       - Reply status: provider expects `2xx` to acknowledge; non-2xx triggers retries from provider side (most providers retry up to ~24h with backoff) -->

```typescript
async function handleEmailWebhook(req: {
  rawBody: string; headers: Record<string, string>;
}): Promise<void> {
  verifyWebhook(req.rawBody, req.headers);
  const event = parseWebhookEvent(req.rawBody);
  await applyWebhookEvent(event);
}
```

### Rate Limiter

<!-- PATTERN: email-rate-limiter -->
<!-- PURPOSE: Per-shop and per-recipient hourly send limits — defends against spam abuse and runaway loops -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT:
       - Storage: Redis (multi-instance, distributed) — `INCR` + `EXPIRE` on hour-bucketed keys; in-memory `Map` for single-instance dev; DB row with hour bucket for low-volume
       - Keys: `ratelimit:shop:{shopId}:{hourBucket}` and `ratelimit:recipient:{shopId}:{email}:{hourBucket}` (hourBucket = `Math.floor(now / 3600)`)
       - Limits: read from `EMAIL_RATE_LIMIT_PER_SHOP` and `EMAIL_RATE_LIMIT_PER_RECIPIENT` env vars (see README §7)
       - Failure mode: throw `HttpError(429, "rate_limit_exceeded")` — caller decides whether to drop the event or requeue with delay -->

```typescript
interface RateLimiter {
  checkOrThrow(shopId: string, recipientEmail: string): Promise<void>;
  // Implementation: increment both counters atomically; if either > limit, throw 429.
}
```

### Input Validation

External contract: SMTP/RFC 5322 forbids `\r`, `\n`, `\0` in `To`/`Subject`/`Reply-To` header values (CRLF injection vector). Subject line ≤998 chars per RFC 5322 §2.1.1. Email address ≤254 chars per RFC 5321 §4.5.3.1.

<!-- PATTERN: email-header-validation -->
<!-- PURPOSE: Reject CRLF injection and malformed email addresses BEFORE provider send — defense-in-depth even if SDK protects -->
<!-- REFERENCE: language=typescript -->
<!-- ADAPT:
       - Regex flavor: ECMAScript shown; PCRE/POSIX/RE2 (Go) equivalent — same charset semantics
       - Email regex: intentionally loose (`^[^\s@]+@[^\s@]+\.[^\s@]+$`) — strict RFC 5322 regex is ~6KB and rejects valid addresses in practice; rely on provider's stricter validation for final acceptance
       - 254-char limit: RFC 5321 path length — not the local-part limit (64 chars per RFC 5321 §4.5.3.1.1) — provider enforces local-part rules -->

```typescript
function validateEmailHeaders(to: string, subject: string): void {
  const CRLF = /[\r\n\0]/;
  if (CRLF.test(to)) {
    throw new ValidationError("Invalid recipient: contains forbidden characters");
  }
  if (CRLF.test(subject)) {
    throw new ValidationError("Invalid subject: contains forbidden characters");
  }
  if (!isValidEmail(to)) {
    throw new ValidationError("Invalid recipient email format");
  }
}

function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 254;
}
```

---

## Anti-Patterns

### DON'T: Concatenate user input into HTML without escaping

<!-- PATTERN: email-html-escape-anti-pattern -->
<!-- PURPOSE: Show that string-concatenated HTML is unsafe; templated, auto-escaped HTML is the only acceptable form -->
<!-- REFERENCE: language=typescript -->
<!-- ADAPT: applies to all template engines with auto-escape on by default (Handlebars `{{var}}`, Liquid `{{var}}`, Jinja2 `{{ var }}`); if engine doesn't auto-escape (Mustache 5+) wrap output through a sanitizer -->

```typescript
// BAD — XSS and template injection risk
const body = `<h1>Hello ${customerName}</h1>`;

// GOOD — use template engine with auto-escape
const body = hbs.compile("<h1>Hello {{customer_name}}</h1>")(variables);
```

### DON'T: Fire-and-forget without logging

<!-- PATTERN: email-fire-and-forget-anti-pattern -->
<!-- PURPOSE: Show that sends without a log row leave no audit trail and break idempotency -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT: `db.emailLog.insert`/`update` are ORM-specific (see `email-send-handler` ADAPT) — but the discipline (log BEFORE send, update AFTER) is invariant -->

```typescript
// BAD — no record of what was sent
await provider.send({ to, subject, html });

// GOOD — log queued, send, log sent
const log = await db.emailLog.insert({ status: "queued" /* ...rest */ });
await provider.send({ /* ... */ });
await db.emailLog.update(log.id, { status: "sent" });
```

### DON'T: Retry on permanent errors

<!-- PATTERN: email-retry-classification-anti-pattern -->
<!-- PURPOSE: Show why blind retry loops waste quota and damage sender reputation — must classify error before retry -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT: `isPermanentError` is the `email-error-classifier` pattern above; status-code thresholds (4xx permanent / 5xx transient) are HTTP-standard, do not change -->

```typescript
// BAD — retrying 422 "invalid address" wastes quota
for (let i = 0; i < 3; i++) {
  try { await provider.send(params); break; }
  catch (e) { await sleep(1000); }
}

// GOOD — classify error before retry (see email-send-with-retry + email-error-classifier)
if (isPermanentError(err)) { markFailed(); return; }
```

### DON'T: Send to previously bounced addresses

<!-- PATTERN: email-suppression-anti-pattern -->
<!-- PURPOSE: Show why bypassing suppression-list damages sender reputation and can get the account suspended -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT: `db.emailSuppressions.find` is ORM-specific — see `email-suppression-check` for ORM equivalents; the rule (check before every send) is invariant -->

```typescript
// BAD — damages sender reputation
await provider.send({ to: bouncedEmail });

// GOOD — check suppression list before every send (see email-suppression-check)
const sup = await checkSuppression(shopId, to);
if (sup.suppressed) { logSkipped(); return; }
```

### DON'T: Store API keys in database or config files

<!-- PATTERN: email-secret-storage-anti-pattern -->
<!-- PURPOSE: Show that DB-stored or file-stored API keys leak through backups, logs, and shared dev environments — env vars only -->
<!-- REFERENCE: runtime=node20+ -->
<!-- ADAPT: `process.env.X` is the Node way; Deno `Deno.env.get("X")`; Bun `Bun.env.X`; production should source secrets from a secret manager (AWS Secrets Manager, GCP Secret Manager, HashiCorp Vault, Doppler) that injects into the process environment at start -->

```typescript
// BAD — secrets in DB or config file
const apiKey1 = await db.settings.get("email_api_key");
const apiKey2 = config.json.emailApiKey;

// GOOD — environment variables only
const apiKey = process.env.EMAIL_PROVIDER_API_KEY;
```

---

## Error Handling

| Error | HTTP Status | Response | Action |
|-------|------------|----------|--------|
| Invalid email format | 400 | `{ error: "invalid_recipient" }` | Reject before send |
| Template not found | 404 | `{ error: "template_not_found" }` | Skip send, log warning |
| Template inactive | — | Silent skip | Log that send was skipped |
| Rate limit exceeded | 429 | `{ error: "rate_limit_exceeded" }` | Reject, include retry-after |
| Provider transient error | — | Retry internally | Up to `EMAIL_MAX_RETRIES` |
| Provider permanent error | — | Mark failed | Log error, do not retry |
| Webhook signature invalid | 401 | `{ error: "invalid_signature" }` | Reject, log attempt |
| Recipient suppressed | — | Silent skip | Log suppression reason |
