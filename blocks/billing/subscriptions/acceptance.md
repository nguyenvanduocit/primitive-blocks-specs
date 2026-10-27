# Acceptance: Subscriptions

Checklist Claude Code runs AFTER implementation, BEFORE reporting done. Items marked **(manual, store console)** cannot be checked from code and go into the report as "needs manual setup". Items marked **(optional)** apply only when the optional feature is built. Fixtures are read by name from `fixtures/`.

## Build & Types

- [ ] The project's type check passes with zero errors
- [ ] No store SDK or store HTTP client is imported outside the store adapter (client) and the snapshot sources (server)
- [ ] The pure core (`normalizeApple`, `normalizeGoogle`, `acceptSnapshot`, `entitlement` composition, `sliceStarts`, `stipendKey`, `bindDecision`, `banners`) has no I/O imports

## State mapping and entitlement

- [ ] Every row of `fixtures/state-matrix.json` `rows` normalizes to its `expected` state, `active`, `will_renew`, `expires_at`, `phase` and `ownership` (or `ignored`)
- [ ] Every `read_time_rules` row gives the expected `active`, state and refresh behavior at the fixed clock
- [ ] Every `composition` case returns its expected objects, including level dominance, priority `retry > paused > pending > revoked > expired`, and the `none` shape
- [ ] `entitlement(account_id, product_code)` returns exactly `{active, state, expires_at, will_renew}`; unknown account or product returns the `none` shape and does not throw
- [ ] `trial`, `active`, `canceled` and `grace` are entitled only while `now < expires_at`; `retry`, `paused`, `pending`, `expired`, `revoked` never are
- [ ] A read with an entitled chain past `expires_at` refreshes once, bounded by `READ_REFRESH_TIMEOUT_MS`; with the store unreachable access lasts at most `ENTITLEMENT_LAG_ALLOWANCE_SECONDS` and only for entitled states
- [ ] No response, log or event contains `chain_ref`, a purchase token or an original transaction id

## Intake and idempotency

- [ ] The handler is registered with `register_notification_handler` for (`apple`, `subscription`) and (`google`, `subscription`) and has no HTTP route of its own
- [ ] Each sequence in `fixtures/store-events.json` ends in its `expected_final` state with the listed outcomes (duplicate, out of order, concurrent refresh, revoked sticky, unlinked, billing failure, plan changes, price increase)
- [ ] The event row is inserted before processing; a duplicate with a terminal outcome returns success with no change; a `pending` or `failed` row is retried
- [ ] A handler failure returns a failure to the receiver; the redelivery completes the work
- [ ] The 17 Apple notification types routed to the handler and all listed Google types are handled as the tables in `backend.md` section 3 say (`ONE_TIME_CHARGE`, `REFUND`, `REFUND_REVERSED`, `REFUND_DECLINED`, `CONSUMPTION_REQUEST` and `TEST` never reach it); an unlisted type refreshes (Google) or is ignored (Apple without a subscription transaction)
- [ ] `bundleId`, `packageName` and `environment` are checked again by the handler; a mismatch is ignored and alerted
- [ ] Google snapshots come from `purchases.subscriptionsv2.get` on every message; the message itself is never used for state
- [ ] A chain write is a compare-and-swap on `revision`; `snapshot_at` never decreases (verified by a concurrency test with two interleaved writers)
- [ ] `expired` and `revoked` leave only through a new transaction or an Apple refund reversal

## Claim, restore, linking

- [ ] `POST /api/subscriptions/intents` returns the account token and store ids, no price, and `409 already_entitled` when the group is entitled on either platform (unless it is a same-platform change)
- [ ] A claim verifies the proof with the store (`verify_apple_transaction` for Apple), maps the product to a plan, applies the snapshot, writes one purchase record per term through `record_verified_purchase`, and acknowledges Google after the commit
- [ ] Claiming the same proof twice leaves one term, one purchase record and one slice set
- [ ] `bindDecision` outcomes: bind, already bound, conflict; a conflict returns `409 linked_to_other_account` with no detail of the other account
- [ ] A transfer needs `confirm_transfer`, respects `TRANSFER_COOLDOWN_DAYS` (`429 transfer_cooldown`), moves the entitlement, and notifies the previous account
- [ ] A message for a bound chain never rebinds it from its token; an unbound chain binds from a known token, else stays unlinked
- [ ] `account_merged` re-points chains without starting the cooldown; `account_deleted` detaches chains and deletes the token row
- [ ] `account_id` is taken from the session; a body field of that name is ignored
- [ ] Claims and restores are rate limited by `CLAIM_RATE_LIMIT_PER_HOUR`

## Stipends

- [ ] Every case in `fixtures/stipend-schedule.json` produces its `total_slices`, `expected_slices`, `expected_due_now`, statuses and idempotency keys at the case clock
- [ ] The ledger key is `subscriptions.stipend:{platform}:{store_transaction_id}:{slice_index}`, at most 200 characters, with no account id
- [ ] Slice rows are unique per (`tenant_id`, `platform`, `store_transaction_id`, `slice_index`)
- [ ] The runner grants through `grant` with reason `subscriptions.stipend`; a replay returns the original result; `idempotency_conflict` is recorded as `skipped` with `already_granted`; `unknown_reason` leaves the slice pending and alerts
- [ ] No stipend for `trial` terms, `family_shared` ownership, sandbox chains, revoked terms or held accounts under the defaults
- [ ] No stipend slice exists for a renewal that failed; slices come only from verified terms
- [ ] Stipends are delivered with no client request (INV-15)
- [ ] **(optional)** With `STIPEND_REVERSAL = spend_clamped`, a revoked term debits `min(amount, balance)` with reason `subscriptions.stipend-reversal` and the reversal key, and a zero balance skips it
- [ ] `currency_flows` has a faucet row for `subscriptions.stipend` and, when reversal is on, a sink row for `subscriptions.stipend-reversal`, per stipend currency

## Refunds and revocation

- [ ] Apple refunds (through the purchase record hook) and `REVOKE`, Google type 12 and voided purchases of product type subscription revoke the entitlement on the next read and skip the term's pending slices
- [ ] `on_purchase_state_changed` for a refunded subscription term wakes the chain and converges on the same state; both channels together are idempotent
- [ ] An Apple refund reversal (record back to `verified`, through the hook) restores the entitlement with its original expiry
- [ ] The revocation sweeps (Apple refund history, Google voided purchases with `type=1` and a start time within 30 days) are scheduled

## Disclosure and screens

- [ ] The paywall shows plan name, duration, what is included, the billed amount as the most prominent price, renewal terms, how to cancel, Restore, and the Terms and Privacy links, all visible without expanding (`paywall-disclosure.feature`)
- [ ] Trial and introductory wording appear only for an offer the store reports as eligible, with the trial length and the price after it
- [ ] No price, trial length or offer text is a constant in the client; the price string is the store's
- [ ] The paywall never opens at launch, never opens for an entitled player, and Close is always visible
- [ ] The charged-but-unconfirmed state keeps the store transaction unfinished and retries the claim on foreground
- [ ] One primary banner plus the price-change banner at most; no banner for an auto-renewing active subscription
- [ ] Manage opens the store of the chain: `showManageSubscriptions` or `https://apps.apple.com/account/subscriptions` on Apple, `https://play.google.com/store/account/subscriptions?sku=<product>&package=<package>` on Google; the client refreshes after returning
- [ ] The Terms of Use and Privacy Policy links work inside the app
- [ ] Every analytics event of README section 6 fires from the listed side with the listed properties and carries no PII

## Trial-ending reminder

- [ ] Every case in `fixtures/state-matrix.json` `trial_reminders` yields exactly its `expected_events` at the case clock (arm, resolve, resolve then arm, none)
- [ ] The hand-off event has `subject_key = trial:{term_id}:{reminder_seq}`, `state` `armed` or `resolved`, `fire_at` (`ends_at` minus `min(TRIAL_REMINDER_LEAD_SECONDS, half the trial length)`, never before emission), `expires_at` equal to the trial end, and `params` with `plan_code`, `product_code`, `platform`, `period`, `renews_at` and, when known, `price_milliunits` and `currency_code`
- [ ] Only free trials of purchased, production terms arm; paid introductory prices, family-shared terms and sandbox chains do not
- [ ] `reminder_seq` and `reminder_ends_at` are written in the same transaction as the chain write; events leave after commit; a re-emit by the reconcile job does not create a second reminder (the consumer dedupes on `subject_key`)
- [ ] The minimum-notice check applies only when arming; an armed reminder is not resolved because time passed
- [ ] `detail.trial_ending` is non-null only inside the reminder window of a renewing eligible trial and never reads push state
- [ ] The banner, the Settings line and the push template carry the end date and time, the price after the trial (store string preferred), the period and a Manage path, and contain no offer, discount, upsell, loss framing, urgency wording or permission prompt
- [ ] With push denied the banner still shows; after a cancel during the trial the `canceled` banner replaces it
- [ ] `subscription_trial_reminder_emitted` and `subscription_trial_reminder_resolved` fire from the server with the listed properties
- [ ] **(manual, adopter)** `messaging.push-reengagement` has a non-promotional category, an `EVENT_ROUTES` entry (remote lane), a template for `subscription_trial_ending` and the route `subscription`; the config keys `TRIAL_REMINDER_LEAD_SECONDS` and `TRIAL_REMINDER_MIN_NOTICE_SECONDS` exist with their defaults

## Security

- [ ] The handler processes only messages the receivers verified (a test with a broken Apple signature and a wrong Google audience changes nothing)
- [ ] `ACCEPTED_ENVIRONMENTS = production` rejects sandbox chains; with sandbox accepted they are stored with `environment = sandbox` and receive no stipend unless `SANDBOX_STIPENDS`
- [ ] Store keys and the service account exist only in the server secret store; `git check-ignore` confirms the secret paths are ignored
- [ ] The account token is a random UUID, unrelated to any account attribute, at most 64 characters
- [ ] The deletion flow shows the manage-subscription link

## Data

- [ ] The migrations run on a clean database and are idempotent; every UNIQUE constraint of README section 2 exists, including the SKU expression index on `subscription_plans`
- [ ] `subscription_chains` has no way to be read by a client endpoint with `chain_ref`
- [ ] Every `subscription_plans` row has a matching `store_products` row in `billing.virtual-currency` with `product_kind = subscription_term`

## Store console (manual, store console)

- [ ] App Store Connect: subscription group, subscriptions with levels, durations of at least seven days, introductory offer if used, Billing Grace Period enabled per the project's choice, Family Sharing only if wanted (it cannot be undone), Notifications V2 URL for production and sandbox pointing at the receiver, App Store Server API key created
- [ ] Google Play Console: subscriptions with base plans and offers and eligibility, grace period and account hold set (together at least 30 days), pause and resubscribe as chosen, real-time developer notifications enabled with the topic and the publish right, test message received
- [ ] Reviewer access: sandbox accepted for the review window; license testers added on Google
- [ ] Terms of Use and Privacy Policy links in the app and in the App Store metadata

## 3-Stack mental test (docs/SPEC_GUIDELINES.md section 7)

Author's answers; not run on any stack.

1. **Data model**: seven tables use only `unique_id`, `external_id`, `text_short`, `integer`, `boolean`, `timestamp`, `enum`; the migration section maps them to Postgres and lists SQLite and MySQL equivalents; the only dialect-sensitive element is the expression index with `COALESCE`, listed in ADAPT. Yes.
2. **Snippets**: the pure functions are plain TypeScript with no runtime API; the compare-and-swap SQL differs only in placeholders and `now()`. Yes.
3. **External contract**: Apple types, subtypes, status codes, offer types, ownership values, API paths and retry behavior, and Google RTDN types, state names and API paths are concrete and cited; JWS and Pub/Sub JWT verification are delegated to the receivers of `billing.virtual-currency` and the Apple library, with the claims to check listed. Yes.
4. **Sequence flow**: no framework feature is assumed; the receiver-to-handler call is an in-process function; jobs are plain schedulers. Yes.
5. **Acceptance**: every item is checkable with a SQL database, a fake store adapter, fake store API clients driven by the fixtures, and a fake ledger. Yes.

## Tests

- [ ] Unit tests cover the pure core against the four fixtures
- [ ] Integration tests with fake store API clients and a fake ledger cover every scenario in the six `.feature` files
- [ ] At least one test interleaves two chain writers and one test redelivers a message after a handler failure

## Configuration

- [ ] Every key of README section 7 exists as named configuration with the stated default
- [ ] The app starts with `WINBACK_ENABLED = false` and `STIPEND_REVERSAL = none` and no optional feature code runs
- [ ] The report lists every manual step left and every `Assumption:` made
