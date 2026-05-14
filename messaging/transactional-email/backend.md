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

---

## Core Patterns

### Provider Adapter

Abstract over Resend / SendGrid / SES so the rest of the codebase calls one interface.

```typescript
// PATTERN: provider-adapter
// PURPOSE: Swap email providers without touching business logic
// ADAPT: Add provider-specific SDK imports, adjust error mapping per provider

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

// Factory — reads EMAIL_PROVIDER env var
function createEmailProvider(provider: string): EmailProviderAdapter {
  switch (provider) {
    case "resend": return new ResendAdapter();
    case "sendgrid": return new SendGridAdapter();
    case "ses": return new SESAdapter();
    default: throw new Error(`Unknown email provider: ${provider}`);
  }
}
```

### Template Engine (Handlebars, sandboxed)

```typescript
// PATTERN: template-render
// PURPOSE: Render subject + body from Handlebars templates with auto-escaping
// ADAPT: Choose Handlebars vs Mustache vs other logic-less engine

import Handlebars from "handlebars";

// Sandboxed instance — no custom helpers that access fs/env/runtime
const hbs = Handlebars.create();

function renderTemplate(
  template: { subject_template: string; body_template: string },
  variables: Record<string, unknown>
): { subject: string; body: string } {
  // Sanitize variable values: escape {{ and }} to prevent template injection
  const safeVars = sanitizeVariables(variables);

  const subjectFn = hbs.compile(template.subject_template, { noEscape: false });
  const bodyFn = hbs.compile(template.body_template, { noEscape: false });

  return {
    subject: subjectFn(safeVars),
    body: bodyFn(safeVars),
  };
}

function sanitizeVariables(vars: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(vars)) {
    if (typeof value === "string") {
      result[key] = value.replace(/\{\{/g, "&#123;&#123;").replace(/\}\}/g, "&#125;&#125;");
    } else {
      result[key] = value;
    }
  }
  return result;
}
```

### Send Email Handler (event-driven, idempotent)

```typescript
// PATTERN: send-email-handler
// PURPOSE: Idempotent event handler — receives event, renders template, sends via provider
// ADAPT: Adjust event shape, template slug mapping, variable extraction per merchant

async function handleSendEmail(event: {
  eventId: string;
  shopId: string;
  templateSlug: string;
  to: string;
  variables: Record<string, unknown>;
}): Promise<void> {
  const { eventId, shopId, templateSlug, to } = event;
  const idempotencyKey = `${eventId}:${templateSlug}:${to}`;

  // 1. Idempotency check
  const existing = await db.emailLog.findByIdempotencyKey(idempotencyKey);
  if (existing) return; // already processed

  // 2. Suppression check
  const suppressed = await db.emailSuppressions.find(shopId, to);
  if (suppressed) {
    await db.emailLog.insert({ shopId, idempotencyKey, to, subject: "", templateSlug, status: "failed", error: `suppressed: ${suppressed.reason}` });
    return;
  }

  // 3. Rate limit check
  await rateLimiter.checkOrThrow(shopId, to);

  // 4. Template lookup (shop-specific, fallback to platform default)
  const template = await db.emailTemplates.findByShopAndSlug(shopId, templateSlug);
  if (!template || !template.active) return; // no template or inactive

  // 5. Render
  const rendered = renderTemplate(template, event.variables);

  // 6. Validate output
  validateEmailHeaders(to, rendered.subject);

  // 7. Insert log (queued)
  const logEntry = await db.emailLog.insert({
    shopId, idempotencyKey, toAddress: to,
    subject: rendered.subject, templateSlug, status: "queued",
    metadata: event.variables,
  });

  // 8. Send with retry
  await sendWithRetry(logEntry.id, {
    from: `${config.FROM_NAME} <${config.FROM_EMAIL}>`,
    to, subject: rendered.subject, html: rendered.body,
    replyTo: config.REPLY_TO || undefined,
  });
}
```

### Retry with Exponential Backoff

```typescript
// PATTERN: send-with-retry
// PURPOSE: Retry transient provider failures (5xx) with exponential backoff, fail on permanent errors (4xx)
// ADAPT: Adjust max retries and base delay via config

async function sendWithRetry(
  logId: string,
  params: { from: string; to: string; subject: string; html: string; replyTo?: string }
): Promise<void> {
  const maxRetries = config.EMAIL_MAX_RETRIES;
  const baseDelay = config.EMAIL_RETRY_BASE_DELAY_MS;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const result = await provider.send(params);
      await db.emailLog.update(logId, {
        status: "sent",
        providerMessageId: result.messageId,
        sentAt: new Date(),
      });
      return;
    } catch (err) {
      if (isPermanentError(err) || attempt === maxRetries) {
        await db.emailLog.update(logId, {
          status: "failed",
          error: err.message,
        });
        return;
      }
      // Transient error — wait and retry
      await sleep(baseDelay * Math.pow(2, attempt - 1));
    }
  }
}

function isPermanentError(err: unknown): boolean {
  // 4xx from provider = permanent (bad request, invalid address, etc.)
  // 5xx from provider = transient (server error, rate limit)
  if (err && typeof err === "object" && "status" in err) {
    return (err as { status: number }).status >= 400 && (err as { status: number }).status < 500;
  }
  return false;
}
```

### Webhook Handler (delivery status updates)

```typescript
// PATTERN: webhook-handler
// PURPOSE: Process delivery/bounce/complaint notifications from email provider
// ADAPT: Map provider-specific event types to internal status values

async function handleEmailWebhook(req: {
  rawBody: string;
  headers: Record<string, string>;
}): Promise<void> {
  // 1. Verify signature
  const valid = provider.verifyWebhookSignature({
    payload: req.rawBody,
    headers: req.headers,
    secret: config.EMAIL_WEBHOOK_SECRET,
  });
  if (!valid) throw new HttpError(401, "Invalid webhook signature");

  // 2. Parse event
  const event = parseWebhookEvent(req.rawBody);

  // 3. Update log
  const logEntry = await db.emailLog.findByProviderMessageId(event.messageId);
  if (!logEntry) return; // unknown message, skip

  await db.emailLog.update(logEntry.id, { status: event.status });

  // 4. Auto-suppress on hard bounce or complaint
  if (event.status === "bounced" && event.bounceType === "hard") {
    await db.emailSuppressions.upsert({
      shopId: logEntry.shopId,
      email: logEntry.toAddress,
      reason: "hard_bounce",
      sourceLogId: logEntry.id,
    });
  }
  if (event.status === "complained") {
    await db.emailSuppressions.upsert({
      shopId: logEntry.shopId,
      email: logEntry.toAddress,
      reason: "complaint",
      sourceLogId: logEntry.id,
    });
  }
}
```

### Rate Limiter

```typescript
// PATTERN: rate-limiter
// PURPOSE: Prevent spam abuse — per-shop and per-recipient hourly limits
// ADAPT: Use Redis for distributed rate limiting, or in-memory for single-instance

interface RateLimiter {
  checkOrThrow(shopId: string, recipientEmail: string): Promise<void>;
}

// Sliding window counter in Redis (or DB)
// Two keys per check:
//   ratelimit:shop:{shopId}:hour:{hourBucket}
//   ratelimit:recipient:{shopId}:{email}:hour:{hourBucket}
// Increment on send, reject if over limit
```

### Input Validation

```typescript
// PATTERN: email-header-validation
// PURPOSE: Reject header injection attempts (CRLF) before any send
// ADAPT: Extend with additional checks per merchant requirements

function validateEmailHeaders(to: string, subject: string): void {
  const CRLF_PATTERN = /[\r\n\0]/;

  if (CRLF_PATTERN.test(to)) {
    throw new ValidationError("Invalid recipient: contains forbidden characters");
  }
  if (CRLF_PATTERN.test(subject)) {
    throw new ValidationError("Invalid subject: contains forbidden characters");
  }
  if (!isValidEmail(to)) {
    throw new ValidationError("Invalid recipient email format");
  }
}

function isValidEmail(email: string): boolean {
  // Strict check: local@domain, no whitespace, no consecutive dots
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 254;
}
```

---

## Anti-Patterns

### DON'T: Concatenate user input into HTML without escaping

```typescript
// BAD — XSS and template injection risk
const body = `<h1>Hello ${customerName}</h1>`;

// GOOD — use template engine with auto-escape
const body = hbs.compile("<h1>Hello {{customer_name}}</h1>")(variables);
```

### DON'T: Fire-and-forget without logging

```typescript
// BAD — no record of what was sent, no way to debug delivery issues
await provider.send({ to, subject, html });

// GOOD — log before send, update after
const log = await db.emailLog.insert({ status: "queued", ... });
await provider.send({ ... });
await db.emailLog.update(log.id, { status: "sent" });
```

### DON'T: Retry on permanent errors

```typescript
// BAD — retrying 422 "invalid address" wastes time and quota
for (let i = 0; i < 3; i++) {
  try { await provider.send(params); break; }
  catch (e) { await sleep(1000); } // retries everything
}

// GOOD — classify error type before retrying
if (isPermanentError(err)) { markFailed(); return; }
// Only retry transient errors (5xx, timeout)
```

### DON'T: Send to previously bounced addresses

```typescript
// BAD — damages sender reputation, provider may suspend account
await provider.send({ to: bouncedEmail, ... });

// GOOD — check suppression list before every send
const suppressed = await db.emailSuppressions.find(shopId, to);
if (suppressed) { logSkipped(); return; }
```

### DON'T: Store API keys in database or config files

```typescript
// BAD
const apiKey = await db.settings.get("email_api_key");
// BAD
const apiKey = config.json.emailApiKey;

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
