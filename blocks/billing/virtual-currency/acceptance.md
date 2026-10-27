# Acceptance: Virtual Currency

Verification checklist Claude Code runs AFTER implementation, BEFORE reporting done. Every item must pass. Items marked **(manual, store console)** cannot be checked from code and go into the report as "needs manual setup". Items marked **[client]** apply to the web-tech client; the rest are server items. Tests are generated from the `.feature` files and the JSON fixtures; create the test files in the project's own test framework.

## Build & Types

- [ ] The project's type check passes with zero errors
- [ ] The store SDKs and plugins are imported only from the real `StorePort` file, never from components **[client]**
- [ ] No `any` types except with an explicit justification comment
- [ ] `planEntry`, `planPurchase`, `clawbackPlan`, `checkLimit` and `approxMoney` are pure: no database, clock, network or framework import

## Database

- [ ] The migrations run on a clean database and are idempotent
- [ ] `wallet_balances.balance` has a CHECK `>= 0`; `ledger_entries.amount` has a CHECK `> 0`; `ledger_entries.balance_after` has a CHECK `>= 0`
- [ ] `ledger_entries` has UNIQUE (`tenant_id`, `idempotency_key`)
- [ ] `store_purchases` has UNIQUE (`tenant_id`, `store_transaction_id`); `store_notifications` has UNIQUE (`tenant_id`, `platform`, `notification_id`)
- [ ] An UPDATE of a `ledger_entries` row fails; a DELETE fails unless the erasure flag is set (INV-1)
- [ ] The runtime database role has no UPDATE or DELETE on `ledger_entries` (where the dialect has roles)
- [ ] `store_products` rejects `fulfilment = ledger` with `product_kind <> consumable`
- [ ] Every table carries `tenant_id` and every read filters by it
- [ ] All timestamps are set by the server clock; no client-supplied time is stored except the store's own purchase and refund instants

## Ledger contract (`ledger.feature`, `fixtures/ledger-cases.json`)

- [ ] Every case in `fixtures/ledger-cases.json` returns the listed result or error
- [ ] `grant` and `spend` return `{applied, balance, entry_id}`; a replay returns the original entry's `balance_after`
- [ ] A rejected `spend` writes no entry and the same key can be used again
- [ ] The same key with a different amount, currency, reason, kind or account returns `idempotency_conflict` and leaks nothing
- [ ] Amounts: 0, negatives, floats, strings, null and values above `LEDGER_MAX_AMOUNT` return `invalid_amount`; 1 and `LEDGER_MAX_AMOUNT` are accepted
- [ ] A reason or key of the wrong shape returns `invalid_request`; a key over `LEDGER_IDEMPOTENCY_KEY_MAX_LENGTH` is rejected
- [ ] A grant past `LEDGER_MAX_BALANCE` returns `balance_limit_exceeded`
- [ ] Items use the same calls with an item code as `currency`
- [ ] `holders(currency, after_account_id, limit)` pages accounts with a balance above zero in ascending `account_id` order with an exclusive cursor, rejects a bad limit and an unknown currency, and is not an HTTP route
- [ ] The concurrency cases pass on the project's database: ten spends from 100 apply one; ten calls with one key apply one entry with one entry id
- [ ] After any test sequence `balance` equals the newest `balance_after` and credits minus debits
- [ ] No client route reaches `grant` or `spend` except through the verified purchase handler (list the routes found)
- [ ] `holdings`, `mergeAccounts` and `deleteAccount` are registered with `auth.guest-account` (its release gate) and `compliance.account-deletion`; `holdings` lists each currency or item code with a balance as `carried`, sorted, with `paid` from verified purchases
- [ ] `mergeAccounts` is idempotent by `merge_id` (a repeat returns the first result), moves balances once, can be re-run after a crash, fails `already_merged` for a second target, and later operations on the merged id resolve to the target
- [ ] Idempotency keys have no expiry: a replay of a key from the oldest entry of an account still returns its original result (INV-4)

## Registry and catalog

- [ ] Every `reason` written by a test appears in `currency_flows` with the right direction
- [ ] A reason without an enabled row returns `unknown_reason`; disabling a flow stops new entries but a replay of an applied key still returns its original result
- [ ] `fixtures/catalog.json` loads; the startup checks in `expected.startup_check_errors` each fail startup with the listed error
- [ ] Each calling block's reasons are registered by its own migration; the table in `README.md` section 6 ("Flows registered by the calling blocks") matches the sibling READMEs (list any reason found in a sibling that is missing from the registry)
- [ ] The catalog startup check fails when packs grant more than `MAX_PURCHASABLE_CURRENCIES` hard currencies, and no ledger operation converts one currency into another
- [ ] A `random_reward` product without `odds_url`, or on a `fulfilment = ledger` row, is rejected by the schema; the card and the confirmation sheet show the odds link **[client]**
- [ ] The catalog contains amounts and no price, price string or currency symbol (INV-16); a search of the schema and responses finds none
- [ ] `GET /api/shop/packs` omits packs with no product id for the platform, inactive packs, spent starter offers and expired starter windows

## Apple verification (`pack-purchase.feature`)

- [ ] The JWS chain is verified to a pinned Apple root certificate; `bundleId` and `environment` are checked; `appAppleId` is checked for production
- [ ] A payload altered after signing, a JWS signed outside the pinned roots, and a transaction with another `bundleId` each return `proof_invalid` and write nothing
- [ ] The accepted signature algorithm is pinned after inspecting a sandbox transaction (record the algorithm in the report)
- [ ] The transaction is confirmed with Get Transaction Info on the production or sandbox host matching its `environment`; a refunded transaction is recorded as `refunded` and not delivered
- [ ] The API request JWT uses ES256, `aud` = `appstoreconnect-v1`, `iss`, `iat`, `exp` at most 60 minutes after `iat`, and `bid`
- [ ] `429` and `5xx` from Apple answer `store_unavailable` and write nothing
- [ ] `type` is checked against the catalog `product_kind`; `quantity` above `MAX_PURCHASE_QUANTITY` is rejected
- [ ] `price` times 1000 is stored as `price_micros` with `price_source = apple_payload`

## Google verification (`pack-purchase.feature`)

- [ ] The state is read with `purchases.productsv2.getproductpurchasev2` for `GOOGLE_PACKAGE_NAME`; a token for another package or a made-up token returns `proof_invalid`
- [ ] Exactly one line item with the submitted product id is required; two line items are rejected and refunded with `orders.refund` and `revoke` true, never consumed or acknowledged
- [ ] `PURCHASE_STATE_UNSPECIFIED` is treated as retryable, not as paid
- [ ] `store_transaction_id` is the purchase token; a promo-code purchase without `orderId` is recorded
- [ ] After the record commits the server calls `products.consume` for a consumable and `products.acknowledge` for a non-consumable; never before; never for a rejected purchase
- [ ] A test purchase is recorded as `sandbox` and follows `GOOGLE_ACCEPT_TEST_PURCHASES`

## Recording and delivery

- [ ] Recording and ledger grants commit in one transaction; a forced failure after the record leaves neither (INV-9)
- [ ] Ten concurrent submissions of one proof credit once and return one purchase id
- [ ] The first-purchase bonus cases in `fixtures/money-cases.json` (`contents_and_bonus`) pass for both `FIRST_PURCHASE_BONUS_SCOPE` values
- [ ] `starter_visibility` cases pass; a paid repeat of the starter bundle is delivered in full
- [ ] A `fulfilment = external` product writes a record, no ledger entry, and fires `on_purchase_state_changed`; `purchase_record` returns the documented fields
- [ ] With `STORE_ACCOUNT_TOKEN_SOURCE = account_id` the token sent to the stores equals the account id; with `wallet_token` it is a random UUID; neither is an email or a provider id
- [ ] With no `purchase_policy` registered, `GET /api/shop/packs` answers `purchases_enabled` false with reason `age`, and a purchase the store confirms is still delivered
- [ ] A token owned by another account credits that account and answers the submitter `other_account` without balances; an unknown token is rejected `account_unknown`; a tokenless purchase follows `ACCOUNT_TOKEN_MISSING_POLICY`; a tokenless purchase seen first by notification is `unclaimed` and is delivered when a session submits it
- [ ] The verify endpoint is rate limited per account and a recorded transaction causes no store call

## Pending and interrupted (`pending-and-interrupted.feature`)

- [ ] A Google `PENDING` purchase is recorded `pending`, grants nothing, and is neither consumed nor acknowledged
- [ ] A pending purchase completes through the real-time notification and through a client resubmission; a canceled one becomes `canceled`
- [ ] A purchase recovered at launch is delivered once; the Apple transaction is finished only after `finish_transaction` true
- [ ] The client retries with the configured backoff and keeps the transaction unfinished while the server is unreachable
- [ ] A failed consume is retried every `CONSUME_RETRY_INTERVAL_SECONDS` and alerts after `CONSUME_ALERT_AFTER_SECONDS`
- [ ] A crash injected between commit and consume leaves a verified, unfinalized purchase that the retry job finalizes
- [ ] A Google purchase already consumed by a client is delivered once and flagged

## Notification receivers

- [ ] Apple: an unsigned body, a payload with another `bundleId` and a wrong environment answer 401 and change nothing; the payload is never logged
- [ ] Apple: duplicates by `notificationUUID` are processed once; `failed` rows are reprocessed; success answers 200, failure answers 5xx
- [ ] Apple types are dispatched as in `backend.md` section 9; subscription types go to the registered handler or are `ignored`
- [ ] Google: the push token signature, `email`, `email_verified` and `aud` are checked (`google_push_auth_cases`); `packageName` is checked; duplicates by `messageId` are processed once
- [ ] Google: every one-time and voided notification triggers a fresh `productsv2` or voided-list read; the body alone never sets a state
- [ ] Unknown notification kinds are acknowledged and logged
- [ ] A handler registered with `register_notification_handler` receives only its family and a failure makes the receiver answer non-2xx

## Refund and clawback (`refund-and-clawback.feature`, `fixtures/money-cases.json`)

- [ ] Every row of `clawback` passes: the take is `min(balance, granted)` per currency; no balance goes negative; no entry when nothing can be taken
- [ ] The shortfall equals granted minus clawed and appears in `purchase_refunded`
- [ ] Reinstatement returns the amounts taken, once, and never the shortfall; a second refund cycle uses a new key
- [ ] Out-of-order and duplicate notifications end in the state the store reports
- [ ] A forged refund or a validly signed refund for a purchase the store still shows as paid changes nothing
- [ ] The refund-review cases pass at the window boundary; a purchase the store confirms during review is still delivered
- [ ] The player-facing refund notice lists exact amounts once and `refund-notices/seen` clears it
- [ ] A refund after erasure is recorded and claws back nothing
- [ ] Consumption requests: nothing is sent without consent; with consent the body has `customerConsented` true, `deliveryStatus` `DELIVERED`, `sampleContentProvided` true and the capped `consumptionPercentage`; the call is made within 12 hours; `CONSUMPTION_REFUND_PREFERENCE` is honored

## Spending controls and real-money value (`spending-controls.feature`)

- [ ] Every pack card, the starter card and the confirmation Buy button show the store's display price string **[client]**
- [ ] The confirmation step precedes the store sheet when `PURCHASE_CONFIRMATION` is `always`; "Not now" has the same size and weight as Buy; dismissing sends nothing to the store **[client]**
- [ ] The intent check cases in `fixtures/money-cases.json` (`spend_limit.check`) pass, including the period boundary and unknown prices
- [ ] `next_room_at` is the earliest instant the candidate fits: the case where the oldest purchase alone frees too little room returns the instant the second purchase leaves, simultaneous leavers leave together, and a price above the limit returns null
- [ ] First limit and lowering apply at once; raising, removing and changing the currency apply after `SPEND_LIMIT_COOL_OFF_SECONDS` by the server clock; a new request restarts the cool-off; the player can cancel
- [ ] A purchase made outside the shop is delivered and counted
- [ ] A refund an operator initiates (`operator:unauthorized`) does not count toward the refund-review hold; the spending screen's "Unauthorized purchase?" help names the store's refund request and support **[client]**
- [ ] The insufficient-balance sheet marks covering packs, lists a `direct_offer` product when given, and every price in a purchasable currency on any screen shows `ApproxMoney` with its Indicative label **[client]**
- [ ] The parental gate runs before the intent call and before a limit change when the host requires it **[client]**
- [ ] The receipt and history show the amount charged or "See your store receipt" **[client]**
- [ ] `approxMoney` returns every value in `approx_money_cases` (`fixtures/catalog.json`) and nothing when the reference price is missing; it is used only for purchasable currencies, labeled "about" **[client]**
- [ ] A "pack prices" entry is reachable from every balance of a purchasable currency **[client]**
- [ ] No countdown shows when `countdown_offers_allowed` is false; countdowns run from `server_now` **[client]**
- [ ] The shop and the insufficient-balance sheet never open without a player action **[client]**

## Reconciliation and erasure (`reconciliation-and-erasure.feature`)

- [ ] The job takes a lease, is idempotent, and edits no ledger row
- [ ] A deliberate balance drift is reported and `rebuild_balance` restores the ledger value with an audit record
- [ ] The Apple catch-up and Google voided poll process what was missed and nothing twice; the voided read never uses a start time older than 30 days
- [ ] Pending, unclaimed and unfinalized purchases are re-read or retried; the report lists counts and the oldest age
- [ ] The wallet eraser deletes balances, accounts, spend controls and ledger rows, de-links purchases (or deletes them with `ERASURE_PURCHASE_RECORDS = delete`), and is re-runnable
- [ ] `deleteAccount` is registered with `compliance.account-deletion` and `auth.guest-account`, and its erasure inventory test passes
- [ ] The deletion confirmation lists the balances that will be lost **[client]**
- [ ] The balance follows the account to a new device with no store restore; the shop has no Restore action for packs **[client]**

## Security (`security.md`)

- [ ] Threat model items T1 to T16 each have the listed mitigation implemented or an explicit decision recorded in the report
- [ ] No client endpoint accepts an amount, currency or reason; `account_id` is read only from the session
- [ ] A search of the repository and the client bundle finds no App Store Connect key, service-account JSON or private key
- [ ] No log line contains a signed transaction, signed payload, purchase token or store account token (grep a test run for markers)
- [ ] The store account token is a random UUID with no relation to the account id or an email
- [ ] The Pub/Sub audience and service-account email are required configuration and a missing value fails closed

## Configuration

- [ ] Every key in `README.md` section 7 is exposed as configuration with the listed default
- [ ] The service starts only when the required keys are present and the catalog checks pass
- [ ] `LEDGER_MAX_BALANCE` does not exceed the JavaScript maximum safe integer while the client is web-tech

## Store console (manual, store console)

- [ ] Apple: each pack exists as a Consumable with the id in the catalog; the App Store Connect API key exists; the Server Notifications V2 production and sandbox URLs are set; the Paid Apps Agreement is active
- [ ] Google: each pack exists as an in-app product with the id in the catalog; the service account has Developer API access; the permissions needed for `products.consume`, `products.acknowledge` and `orders.refund` were confirmed (the pages read do not state them)
- [ ] Google: the Pub/Sub topic exists, the Google Play developer-notifications service account has Pub/Sub Publisher on it, the push subscription authenticates to the receiver, the topic is entered in Play Console, "Get all notifications for subscriptions and one-time products" is chosen, and the console's test message arrived
- [ ] A sandbox or license-tester purchase on each store completed end to end on a real device, and a refund of it was observed
- [ ] The Play Billing Library version meets Google's current requirement (version 8 or later since 2026-08-31, per the deprecation page read on 2026-10-27)
- [ ] If RevenueCat is also embedded, it does not finish or consume the consumable packs on either store

## Tests

- [ ] Unit tests pass for `planEntry`, `planPurchase`, `clawbackPlan`, `checkLimit`, the contents calculation and `approxMoney`, reading the fixtures
- [ ] Integration tests with a fake store verifier and fake store APIs pass for every scenario in the six `.feature` files
- [ ] At least one test runs the writer against the project's real database with concurrent connections

## Block-specific criteria

- [ ] Every INV-1 .. INV-30 in `README.md` section 8 maps to at least one passing test; list the mapping in the report
- [ ] Guide 15 controls are present: spend limit with cool-off, purchase confirmation, no expiry, one premium currency and no exchange, direct purchase for an exact price, odds link beside a random product, spending off until the host enables it, and the refund help (`README.md` section 6, "Guide 15 controls")
- [ ] The report lists which parts could not be run on the project's stack and why, every manual store step left, and every `Assumption:` made
- [ ] **3-Stack mental test** (docs/SPEC_GUIDELINES.md section 7), the author's answers, not run on any stack: (1) data model: ten tables with logical types `unique_id`, `external_id`, `text_short`, `text`, `integer`, `boolean`, `timestamp`, `enum` map on Postgres, MySQL and SQLite; the open point is Google purchase-token length against MySQL `VARCHAR(255)`, which the ADAPT note names - yes with that note; (2) snippets: the SQL writer differs only in placeholders, `RETURNING` and `ON CONFLICT`, and the ADAPT lists them; the TypeScript snippets are runtime-neutral apart from the Apple library's Node version, which the ADAPT states - yes; (3) external contract: Apple and Google paths, field names, enum values, retry schedules, acknowledge window and push acknowledgement codes are concrete and cited; the JWS signing algorithm is not confirmed and acceptance requires pinning it from a sandbox transaction - yes with that item; (4) sequence flow: no framework-specific feature; the conditional update, unique key and one transaction exist on all three databases - yes; (5) acceptance: every item is checkable with a SQL database, a fake store verifier and fake store APIs, except the items marked manual - yes
