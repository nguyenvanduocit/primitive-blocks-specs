# Acceptance — Transactional Email

Checklist Claude Code runs AFTER implementation, BEFORE reporting done.

## Database

- [ ] Migration creates `email_templates` table with `shop_id` column (nullable) and `UNIQUE (shop_id, slug)` constraint
- [ ] Migration creates `email_log` table with `shop_id NOT NULL` and `idempotency_key UNIQUE NOT NULL`
- [ ] Migration creates `email_suppressions` table with `UNIQUE (shop_id, email)` constraint
- [ ] All tables have `id`, `created_at` columns; `email_templates` and `email_log` have `updated_at`
- [ ] Indexes created on: `email_templates(shop_id, slug)`, `email_log(status)`, `email_suppressions(shop_id, email)`

## Template Engine

- [ ] Handlebars (or equivalent) renders `{{variable}}` with HTML auto-escaping ON
- [ ] Variable value `<script>alert('xss')</script>` renders as escaped `&lt;script&gt;...`
- [ ] Template with `{{` in user variable input does not execute as template syntax
- [ ] Template preview endpoint returns rendered subject + body given sample variables

## Email Sending

- [ ] Event handler correctly maps event type to template slug
- [ ] Template lookup prefers `(shop_id, slug)` over `(NULL, slug)` platform default
- [ ] Idempotency: same `(event_id, template_slug, to)` processed only once — second call is a no-op
- [ ] Suppressed recipients are skipped; email_log entry records the skip with reason
- [ ] Inactive templates cause send to be silently skipped
- [ ] Provider adapter interface works with at least one provider (Resend or SendGrid)
- [ ] Provider API receives correct `from`, `to`, `subject`, `html` fields
- [ ] `email_log` row created with `status='queued'` BEFORE provider call
- [ ] `email_log` updated to `status='sent'` with `provider_message_id` after success

## Retry & Error Handling

- [ ] Transient errors (5xx, timeout) trigger retry with exponential backoff
- [ ] Permanent errors (4xx) do NOT trigger retry — marked `status='failed'` immediately
- [ ] After max retries exhausted, `email_log.status` is `failed` with error message
- [ ] No unhandled exceptions escape the send handler (all errors caught and logged)

## Rate Limiting

- [ ] Per-shop hourly limit enforced (`EMAIL_RATE_LIMIT_PER_SHOP`)
- [ ] Per-recipient hourly limit enforced (`EMAIL_RATE_LIMIT_PER_RECIPIENT`)
- [ ] Exceeding rate limit returns/logs appropriate error, email is not sent

## Security

- [ ] `to_address` and `subject` validated for CRLF characters (`\r`, `\n`, `\0`) — rejected if present
- [ ] `EMAIL_PROVIDER_API_KEY` read from environment variable, never in code/config/database
- [ ] Provider webhook endpoint verifies signature before processing
- [ ] Invalid webhook signatures return 401
- [ ] Hard bounce webhook adds recipient to `email_suppressions`
- [ ] Complaint webhook adds recipient to `email_suppressions`

## Template CRUD (Admin)

- [ ] GET `/api/email-templates` returns only templates for the current shop
- [ ] POST creates template scoped to current shop; slug validated against `^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$`
- [ ] PUT updates only own shop's template; returns 404 for other shop's template
- [ ] DELETE removes template; returns 204
- [ ] Duplicate endpoint creates new template with different slug, same content
- [ ] Duplicate slug within same shop returns 409

## Type Safety & Build

- [ ] `tsc --noEmit` (or equivalent type check) passes
- [ ] No `any` types without justification comment
- [ ] All provider adapter methods return typed results
- [ ] Email validation function has proper type narrowing

## Configuration

- [ ] All config keys from Configuration Surface (README.md section 7) are documented and read from env/config
- [ ] Missing required env vars (`EMAIL_PROVIDER_API_KEY`, `FROM_EMAIL`) cause startup error with clear message
- [ ] Default values applied for optional config (`EMAIL_MAX_RETRIES=3`, `EMAIL_RATE_LIMIT_PER_SHOP=100`)
