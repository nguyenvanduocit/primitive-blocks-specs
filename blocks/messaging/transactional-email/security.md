# Security — Transactional Email

## Threat Model

### 1. Email Header Injection (CRLF Injection)

**Impact**: HIGH — attacker injects additional headers (BCC, CC) to send spam through the merchant's sender domain, damaging reputation and triggering provider blacklisting.

**Attack vector**: User-controlled input flows into `to`, `subject`, or `reply_to` fields. Injecting `\r\n` characters adds arbitrary headers.

**Mitigation**:
- Reject any `to`, `subject`, `reply_to` value containing `\r`, `\n`, or `\0` characters
- Validate `to` field against strict email regex before send
- Provider SDKs (Resend, SendGrid) have built-in protections, but validate at application layer as defense-in-depth

### 2. Template Injection (Server-Side Template Injection)

**Impact**: MEDIUM — if template engine has access to filesystem/env, attacker-crafted variable values could extract secrets or execute code.

**Attack vector**: User-supplied variables (e.g., customer name containing `{{process.env.SECRET}}`) are rendered through template engine.

**Mitigation**:
- Use Handlebars/Mustache in **sandboxed mode** — no custom helpers that access filesystem, env, or runtime
- HTML auto-escaping ON by default (`{{var}}` escapes HTML). Raw output only via explicit `{{{var}}}` which template authors control, not end users
- Variable values are data, never template syntax — pre-escape `{{` and `}}` in user input before passing to render
- Template source (`subject_template`, `body_template`) is merchant-admin-authored, not end-user-authored

### 3. API Key Exposure

**Impact**: HIGH — leaked provider API key allows sending unlimited email from merchant's verified domain.

**Mitigation**:
- `EMAIL_PROVIDER_API_KEY` stored in env vars only, never in code, config files, or database
- Never log the API key (mask in error messages)
- Rotate key if compromised; provider dashboards support multiple active keys for zero-downtime rotation
- Restrict API key permissions at provider level (send-only, no domain management)

### 4. Spam Abuse via Rate Limit Bypass

**Impact**: HIGH — compromised or buggy event handler sends excessive emails, burning provider quota, damaging sender reputation, triggering provider account suspension.

**Attack vector**: Looping event (e.g., webhook retry storm), code bug creating infinite send loop, or malicious tenant abusing shared infrastructure.

**Mitigation**:
- **Per-shop rate limit**: max `EMAIL_RATE_LIMIT_PER_SHOP` sends per hour per tenant
- **Per-recipient rate limit**: max `EMAIL_RATE_LIMIT_PER_RECIPIENT` sends per recipient per hour (prevents mailbox bombing)
- **Idempotency key** on `email_log`: duplicate event with same `(event_id, template_slug, to)` is rejected at DB constraint level
- Circuit breaker: if a shop exceeds 3x rate limit in an hour, pause sending for that shop and alert

### 5. Provider Webhook Forgery

**Impact**: MEDIUM — attacker sends fake delivery/bounce webhooks to corrupt `email_log` status or add false suppressions (causing legitimate emails to be blocked).

**Attack vector**: POST to the webhook endpoint with fabricated payloads.

**Mitigation**:
- Verify provider webhook signature (HMAC) using `EMAIL_WEBHOOK_SECRET`
- Resend: verify `svix-signature` header. SendGrid: verify `X-Twilio-Email-Event-Webhook-Signature`
- Reject requests with missing or invalid signatures with 401
- Log rejected webhook attempts for monitoring

## Validation Rules

| Field | Rule | Rejection |
|-------|------|-----------|
| `to_address` | Valid email format, no `\r\n\0` chars | 400 — invalid recipient |
| `subject_template` | Max 998 chars (RFC 2822 line limit), no `\r\n` | 400 — invalid subject |
| `body_template` | Max 256KB | 400 — body too large |
| `template slug` | `^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$` | 400 — invalid slug |
| `variables` (user-supplied) | Escape `{{` and `}}` before render | Silent escape |

## Secrets Management

| Secret | Storage | Rotation |
|--------|---------|----------|
| `EMAIL_PROVIDER_API_KEY` | Environment variable | Rotate via provider dashboard; support multiple active keys |
| `EMAIL_WEBHOOK_SECRET` | Environment variable | Rotate via provider dashboard |

Never in code, never in database, never in logs.
