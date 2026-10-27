# Acceptance Checklist — Objectives, Missions and Achievements

Claude Code runs this checklist after implementation, before reporting done. Tests are generated from the `.feature` files and `fixtures/*.json`; invariant ids (INV-1..INV-30) refer to `README.md` section 8, authorization ids (A-1..A-8) and threats (T-1..T-14) to `security.md`. Fixture clock: `2026-10-21T12:00:00Z`; fixture account timezone: `Asia/Ho_Chi_Minh`.

## Database

- [ ] Migration runs (`objective_metrics`, `objective_definitions`, `assignment_plans`, `assignment_windows`, `reroll_banks`, `objective_instances`, `metric_counters`, `objective_events`, `account_merges`)
- [ ] `UNIQUE (tenant_id, account_id, event_id)` exists on `objective_events` (INV-2)
- [ ] `UNIQUE (tenant_id, account_id, plan_id, window_key)` exists on `assignment_windows`, and `UNIQUE (window_id, objective_id)` on `objective_instances` (INV-11)
- [ ] `UNIQUE (tenant_id, merge_id)` and `UNIQUE (tenant_id, from_account_id)` exist on `account_merges` (INV-22)
- [ ] `CHECK (progress <= target)` is active on `objective_instances` (INV-10)
- [ ] At most one `active` version per `objective_id` (partial unique index, or the publish step enforces it)
- [ ] Every query includes `tenant_id` and, for player endpoints, the session's `account_id` (INV-25)
- [ ] Deleting an account removes every per-account row in all tables (`compliance.account-deletion`)

## Metrics and trust

- [ ] Every row of `fixtures/definitions.json` `metrics` loads with its trust class, `requires_attempt`, caps and source
- [ ] A `server_derived` metric reported through the client endpoint is `metric_not_client_reportable` (INV-3); `ingest_server_event` has no player-reachable route (A-3)
- [ ] A `client_validated` event reaches the counters only after the validator accepts it; no `ref` or a rejected `ref` is `validation_failed`
- [ ] Metrics with `requires_attempt` count only for an `attempt_id` that `attemptState` reports as `confirmed`, `won` or `failed`; `open`, `cancelled`, `expired`, `rejected`, unknown and missing attempts are rejected (`attempt_not_proven`, `attempt_required`) before the validator runs (INV-30); the `proof-of-play` case passes
- [ ] `FORBIDDEN_METRIC_SOURCES` blocks a metric sourced from a purchase, subscription, pack purchase, premium spend, speed-up, invitation or referral to buy, gift purchase or store review (INV-23)
- [ ] The adapter table maps `streak_extended`, `daily_reward_claimed`, ledger spend and grant entries, `queue_item_collected`, `item_granted`, `item_upgraded` and `item_equipped`; purchased item grants, premium-paid upgrades and grants with reason `objectives.reward` are ignored (`items-and-queue-adapters-filter-paid-and-self-fed-events`); no metric exists for speed-up use
- [ ] Any objective on a `social-invite` metric is skippable (pool plan with a reroll bank), capped, never a prerequisite, and its reward is also obtainable by another route without an invitation (INV-27)
- [ ] `PREMIUM_CURRENCY_CODES` equals the set of currencies that can be bought with money, checked against the ledger's currency catalog (T-2)

## Ingestion

- [ ] Every case in `fixtures/event-cases.json` returns its listed results, instances and counters
- [ ] A repeated event id, in one request or a later one, counts once (INV-2); `EVENT_RETENTION_SECONDS >= EVENT_MAX_AGE_SECONDS` is enforced at startup
- [ ] Amounts above `max_amount_per_event` or the remaining `day_cap` are clamped and reported as `counted_amount` (INV-5); malformed amounts are rejected per event, not per batch
- [ ] `max` metrics keep the highest value; progress never exceeds the target and never decreases (INV-10)
- [ ] An event is applied to every active instance whose metric or alternate source matches; alternate sources apply the multiplier after the metric's own caps
- [ ] Ingestion for one account is serialized (mutex or equivalent): two concurrent batches cannot exceed a day cap
- [ ] The event window is the server receive time; `occurred_at` never selects a window and a future timestamp is stored as the receive time (INV-1)
- [ ] A batch above `EVENT_BATCH_MAX` and an account above `ACCOUNT_EVENTS_PER_DAY_MAX` are refused before anything is stored
- [ ] Ledger-derived metrics ignore grants with reason `objectives.reward` (INV-24)
- [ ] The block records `session_started` once per session and `active_day` once per local day

## Completion and claim

- [ ] Completion changes state only; the ledger is not called (INV-7)
- [ ] A claim calls `grant` once per reward line with reason `objectives.reward`, `source_ref` = instance id, key `objectives:{account_id}:{objective_id}:{window_key}:{line_index}` (INV-8)
- [ ] A repeated or concurrent claim yields one applied grant and an `already_claimed` answer; a claim that crashed after the grant completes on retry with no second grant
- [ ] A ledger outage returns `503 ledger_unavailable`, and a ledger rejection returns `409 ledger_rejected` with the ledger's error name; both leave the instance `completed`
- [ ] `currency_flows` has a `faucet` row with reason `objectives.reward` for every reward currency and item (publish checks it), and `objective_id` is at most 48 characters so the key fits `LEDGER_IDEMPOTENCY_KEY_MAX_LENGTH`
- [ ] `engagement.season-pass` lists `objective.completed` in its `XP_SOURCES`
- [ ] The reward paid is the snapshot on the instance, whatever later versions say (INV-9)
- [ ] `claim-all` is capped at `CLAIM_ALL_MAX`, each instance is its own transaction, and the response lists a result per instance and `remaining`
- [ ] A completed instance stays claimable after its window closed; with `UNCLAIMED_AT_RESET = auto_grant` the server claims it at the next settle with the same keys; no setting expires a finished reward (INV-9)
- [ ] The completion emits `objective.completed` with `completion_id = {objective_id}:{window_key}` (INV-29) and sends `ingest_xp` to `engagement.season-pass` with that id as `event_id`, source `objective.completed`, units 1, for kinds in `SEASON_XP_KINDS`; a retry repeats the same id
- [ ] A claim resolves the `objective_reward_ready` hand-off with the same `subject_key`

## Assignment, draw and windows

- [ ] Every vector in `fixtures/assignment-cases.json` `window_vectors` is reproduced, including the 25-hour day and the week across a DST change (INV-13)
- [ ] The first read of a window assigns it; two devices and two simultaneous requests produce one set (INV-11); the draw uses stable seed facts only
- [ ] Every `draw_cases` property holds, with the PRNG left to the implementation; the normal-play slot, `exclusive_group`, `avoid_repeat` and the occupies cap are all exercised (INV-26, INV-27)
- [ ] A day the player never opens produces no window, no instances, no expiry (INV-15)
- [ ] A new window of a plan closes the earlier live window; completed instances stay claimable (INV-12)
- [ ] `session` plans are assigned at most `SESSIONS_WITH_OBJECTIVES_PER_DAY` times per local day
- [ ] The list is ordered tier ascending, then `sort_order`, then id; a chain never descends in tier (INV-18)

## Rerolls

- [ ] The bank earns `reroll_earn_per_window` per elapsed window up to `reroll_bank_cap`; every `bank_cases` case passes (INV-16)
- [ ] A reroll spends one banked reroll on an `active` instance of a `pool` plan; the replacement is never an objective already in the window and follows `REROLL_TIER_POLICY`
- [ ] A failed reroll (`no_reroll_available`, `no_replacement_available`, `not_active`, `not_rerollable`) spends nothing; a repeated reroll returns the same replacement
- [ ] No endpoint, config or response sells, extends or revives a reroll or an expired goal (INV-16, INV-23)

## Board, points and the done state

- [ ] The `board-ladder-and-completion-bonus` case passes step by step: points are added when a task completes, rungs advance, the bonus completes when the last task completes (INV-28)
- [ ] Publish rejects a ladder whose top rung is not below the smallest possible board total, and a milestone with points
- [ ] A replaced instance never holds a board open; `board.done` and the `objective_board_done` event follow the rule
- [ ] Neither the API nor the screens present the sum of task points as a target to reach

## Reset, scaling and versioning

- [ ] Default reset is `forfeit`; every `carry_over` case passes (one hop, 80 percent threshold, never for a completed instance, never for a pool member) (INV-15)
- [ ] Every `scaling_cases` case passes; scaling is off by default; inputs exclude spending, entitlement and ads; the scaled target and reward are frozen on the instance (INV-17)
- [ ] An in-flight instance keeps its version, target and reward; a retired objective is not assigned again; the migration rules accept only favorable changes (INV-21)
- [ ] Every row of `invalid_definitions` fails publish with its error and leaves the active set untouched; the unchanged set publishes with the `pool_narrow` warning
- [ ] `publish_definitions` is not reachable from a player session (A-5)

## Starter objectives and achievements

- [ ] The `starter` plan is assigned at the first call of any endpoint, never expires, unlocks each step on completion, and reveals the short, medium and long goals after the last step (INV-19)
- [ ] A lifetime-counted step starts at the true count, never at a pre-filled value (INV-10)
- [ ] Achievements never reset or expire (INV-20); a hidden achievement appears in no response, field or count until completed; the raw response body is searched in a test
- [ ] A new `lifetime_total` achievement back-fills from the counter; a `since_activation` one starts at zero

## Merge

- [ ] The `merge` case in `fixtures/merge-and-version-cases.json` produces the listed counters, rows and bank; unmatched active guest rows in a held window are dropped
- [ ] The merge calls no ledger function (INV-22); replaying `merge_id` changes nothing; a second merge of the same guest is `already_merged`
- [ ] `mergeAccounts`, `holdings` and `deleteAccount` are registered as the participant hooks of `auth.guest-account` and are not reachable from a player session (A-7); a same-account link calls none of them
- [ ] `holdings` returns the entries of `fixtures/merge-and-version-cases.json` `holdings` and an empty list for a pristine guest; `deleteAccount` removes every per-account row and is safe to repeat

## Frontend

- [ ] Every screen of `frontend.md` renders its states: loading, ready, completed, claimed, claim in flight, already claimed, ledger error, empty, done for today, expired, offline, error
- [ ] The bar equals `progress / target`; zero is empty; no pre-filled or minimum fill; the count and the remaining amount and the reward are always visible (progress display rules 1 to 3)
- [ ] Completion, the celebration and the claim button appear only after the server reports `completed`; pending events show as "syncing"
- [ ] Countdowns come from `ends_at` and the server offset; one plain style at every remaining time; at zero the row says "Ending" and refetches; offline shows the absolute end time
- [ ] The reset footer states the active `unclaimed_at_reset` rule and what happens to unfinished progress
- [ ] The reroll sheet states the lost progress, the bank, and the tier policy; it has no price and no purchase path
- [ ] The home chip can be switched off; "nearly there" wording appears only at or below `NEAR_COMPLETE_COPY_PERCENT`
- [ ] No copy anywhere asks for a rating or review, implies that a finished reward expires, or says "you lost" for a missed day
- [ ] Verified on the surface the player sees: open the Objectives screen on a phone-width viewport with the fixture set, finish a goal, claim it and compare the balance (a passing API test alone is not enough)
- [ ] Hidden achievements and secret counts are not hinted at anywhere in the UI

## Integration and events

- [ ] Every analytics event listed in `backend.md` and `frontend.md` fires with its properties; `objective_progress` and `objective_claimed` use the property names of the kit's instrumentation guide
- [ ] The `objective_reward_ready` hand-off carries `subject_key`, `state`, `fire_at`, `expires_at`, `params` as `messaging.push-reengagement` expects
- [ ] The adapter table maps `engagement.daily-streak` and `engagement.timed-queues` (`queue_item_collected`) events to metrics

## Security

- [ ] Threat model items T-1..T-14 each have the listed mitigation implemented or an explicit decision recorded in the report
- [ ] No hardcoded secrets; fixtures contain only synthetic ids and names
- [ ] No request body carries progress, state, target, reward or a ledger key (A-2); a body naming one is `422`
- [ ] Product owner has been told in writing what the bounds do not stop (`security.md` T-1: forged client-reported streams, lifetime counters, validator quality, many accounts) and has accepted that client-reported objectives have no real stakes
- [ ] The operator computed the worst-case daily payout for the shipped content and set an alert on `objectives.reward` grants per account per day above it

## Configuration

- [ ] Every key in `README.md` section 7 is exposed as configuration with the listed default
- [ ] `EVENT_RETENTION_SECONDS >= EVENT_MAX_AGE_SECONDS` and `reroll_bank_cap >= reroll_earn_per_window` are enforced

## Type Safety & Build

- [ ] The project's type check passes with zero errors
- [ ] Request bodies are validated at the API boundary with unknown keys rejected
- [ ] All `.feature` scenarios pass as automated tests on the merchant's stack

## Block-specific criteria

- [ ] Every INV-1 .. INV-30 maps to at least one passing test; list the mapping in the report
- [ ] The report lists which parts could not be run on the project's stack and why
- [ ] **Guide 13 coverage** (`kits/game-engagement/guides/13-missions-and-activities.md`): progress from any mode of normal play (`counts_from_normal_play`, alternate sources, the normal-play slot); a banked reroll with a tier policy; carry-over of incomplete progress and a missed day that costs nothing; milestone points with a ladder below the sum of the tasks; a done state and a whole-board bonus; the `deepen_test` tag and the occupies cap; a pool wider than the board (publish warning), `template_id` and the repeat flags on `objective_assigned`, player-level scaling; alternate progress sources; the unclaimed-reward rule shown on screen; no price and no purchase requirement; chains and lists ordered easy to hard
- [ ] **3-Stack mental test** (docs/SPEC_GUIDELINES.md section 7) - author's answers, not run on any stack: (1) data model: nine tables with logical types `unique_id`, `external_id`, `text_short`, `integer`, `boolean`, `enum`, `json`, `id_list`, `decimal`, `timestamp` map on Postgres, MySQL and SQLite (partial indexes are the one construct without a MySQL form, and the Reference Migration says what to do) - yes; (2) snippets: the TypeScript snippets are pure functions and use only language features present in Node 20, Bun and Deno (`Intl.DateTimeFormat`, `crypto.randomUUID`); the SQL differs only in placeholders and `ON CONFLICT` - ADAPT lists them - yes; (3) external contract: the ledger and season-pass calls are named contracts of sibling blocks, store policy text is quoted with its source, no cryptography is dictated - yes; (4) sequence flow: settle, ingest, claim and merge are transactions with unique keys and a per-account mutex, no framework feature - yes; (5) acceptance: every item is checkable with a plain SQL database, a fake ledger and fixtures, except the draw members, which are asserted by property because the PRNG is the implementer's - yes
