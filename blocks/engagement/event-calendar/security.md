# Security: Event Calendar

> The calendar decides what a player sees and what the ledger pays. Two kinds of failure matter: a player getting more than the table promised, and a player being treated worse than others for a reason that should not matter (what they spent). Confidence labels: HIGH where the rule follows from this block's own contract or a fetched source, MEDIUM where it is reasoned from the contracts, LOW where it is a guess to verify. Invariant ids INV-n are in `README.md` section 8.

## Authorization invariants

| ID | Invariant |
|---|---|
| A-1 | **Identity comes from the session.** Join, progress and claim act on the authenticated account. No request body field selects whose participation or claim is touched. |
| A-2 | **Operator routes use operator identity.** `/admin` routes accept only an operator credential with the required role; a player session, a guest session and a preview token never reach authoring, publish, extend, hold, release or end-now. |
| A-3 | **Roles are separate.** `calendar_author` drafts and checks, `calendar_publisher` publishes and unpublishes, `calendar_operator` extends, holds, releases and ends, `calendar_preview` issues preview tokens. A role does not imply another. With `PUBLISH_REQUIRES_SECOND_APPROVER` the publisher differs from the creator. |
| A-4 | **Caps and budgets are configuration, not operator input.** `REWARD_CAP_PER_PLAYER`, `RELEASED_APP_VERSIONS`, `ASSET_ORIGIN_ALLOWLIST` and `EVENT_TYPES` are changed through the deployment's own config path, never through an authoring route. |
| A-5 | **Tenant on every query.** Every read and write filters on `tenant_id` taken from the session or operator context (INV-17). |
| A-6 | **Reads are projections.** A player response contains the whitelisted fields in `backend.md` only. It never contains `allow_list`, `issuance_budget`, `eligibility_snapshot`, operator ids, other players' progress or audit rows. |
| A-7 | **The ledger is the only writer of balances.** This block calls `grant` and nothing else on the ledger (INV-8). |

### Access matrix

| Resource | Player | Operator (by role) | Preview token |
|---|---|---|---|
| Discovery and detail of eligible events | Read | Not applicable | Read, synthetic facts, any instant |
| Join, progress, claim | Own account only | Denied | Denied (`preview_read_only`) |
| Draft, check | Denied | author | Denied |
| Publish, unpublish | Denied | publisher | Denied |
| Extend, hold, release, end-now, claim retry | Denied | operator | Denied |
| Calendar view and health | Denied | author, operator | Denied |
| Audit rows | Denied | author, publisher, operator (read) | Denied |

## Threat model

### T-1. Device clock manipulation

**Impact**: A player moves the device clock to start, extend or end an event on screen, or to claim early.

**Mitigations**: Every window, grace period and boundary is computed on the server from its own clock; a write is judged by the server instant read inside its transaction (INV-1, INV-3). The client shows countdowns from `server_now` plus the monotonic clock and never from the wall clock (`frontend.md`). HIGH (follows from the contracts).

**What this does not stop**: A manipulated device clock cannot change an outcome, but an offline client can display a wrong absolute end time after a restart (the monotonic source is lost). The display is labelled approximate until the next response. Cosmetic only.

### T-2. Double grant

**Impact**: Economy inflation and unfair advantage. Causes: a retried claim, two devices claiming at once, a claim racing the sweep, a crash between the ledger call and the status update, a client replay.

**Mitigations**: Two barriers (INV-9). First, one claim row per (event, account, reward), enforced by a UNIQUE constraint, so a reward is recorded once. Second, every grant line carries an idempotency key built from stable facts, `event-calendar:{account_id}:{event_id}:{reward_key}:{currency}`, used by the claim path, the auto path, the sweep and every retry, so any replay returns the original ledger result. The status update is guarded by `status = earned`. A claim whose ledger call returned `applied` false or no `entry_id` is not marked granted. HIGH for the block's own barriers.

**What this does not stop**: If the ledger discards idempotency keys sooner than the claim grace plus the retry window, a crash after a successful ledger call and before the status update could be retried into a second grant. The block assumes the ledger keeps keys at least that long (an assumption recorded in `README.md` "Origin and verification status" and flagged for `billing.virtual-currency`). MEDIUM.

### T-3. Progress inflation

**Impact**: A client reports progress it did not earn and collects rewards.

**Mitigations**: Progress is idempotent per `source_ref` (INV-16); one call adds at most `progress_max_per_call`; total never exceeds `progress_cap`; client calls are rate limited (`PROGRESS_RATE_LIMIT_PER_MINUTE`); the reward table's maximum is capped per layer and currency at authoring, so the worst case per account per event is `table_max`. A trusted server caller (the game backend reporting a validated action) is the recommended source for any event worth farming.

**What the bounds do not stop** (stated plainly):
1. A modified client can reach the cap in few calls. With the fixture's weekly sprint, `progress_cap` 600 and `progress_max_per_call` 100, six accepted calls complete it. The bound limits per-call size and total, not honesty. HIGH (arithmetic on `fixtures/events.json`).
2. `source_ref` values are chosen by the caller; a client can invent new ones. Deduplication stops replays, not fabrication.
3. Many accounts per person each earn `table_max`. Nothing here ties an account to a human. LOW to MEDIUM (general property of open sign-in).

**Consequence for the spec:** `README.md` "When NOT to use" excludes rewards with real-world value and any ranking with stakes. Use server-authoritative progress when the economy impact is material.

### T-4. Probing for hidden events

**Impact**: A player learns about QA events, drafts, or other regions' events.

**Mitigations**: Unknown, draft, allow-list and out-of-audience events all answer `404 event_not_found` with the same body and similar timing (INV-15). Only `update_required` (the player can act on it) and `event_held` (for participants) differ. Allow-lists and budgets never appear in responses (A-6). HIGH.

**What this does not stop**: `update_required` confirms that an event requiring a newer version exists. That is intended and carries no reward data.

### T-5. Spoofed eligibility facts

**Impact**: A player gets an event meant for another platform, version or country.

**Mitigations**: Segment facts (`created_at`, `previous_session_ended_at`) come from the host's account record, not the client. Country is derived by the server (`COUNTRY_SOURCE`). The reward table is identical for everyone eligible (INV-6), so a spoofed fact yields access to the same terms, once per account.

**What this does not stop**: `platform` and `app_version` are client-declared and can be lied about, and a VPN changes an IP-derived country. A spoofing player can see an event aimed at another market, and a client that claims a newer version can be shown an event it cannot render (the client-side renderer filter then hides it, INV-13). Use the store's server-side verification if an event must be region-locked for legal reasons. MEDIUM.

### T-6. Preview and time-travel abuse

**Impact**: Time travel on player routes would let a player claim future events or read unpublished drafts.

**Mitigations**: There is no time parameter on any player route (INV-14); unknown query parameters are ignored. Time travel exists only on `GET /admin/preview/events`, behind a preview token that lives `PREVIEW_TOKEN_TTL_SECONDS`, is issued to a named operator with `calendar_preview`, and is refused by every write route. Preview uses synthetic facts and shows no participation, so it exposes no player data. Drafts appear only with `include_drafts=true` on that route. Preview responses are `no-store`. A release client has no code path that sends a preview token. HIGH.

**What this does not stop**: A leaked preview token lets its holder read drafts until it expires. It cannot write and shows no player data. MEDIUM.

### T-7. Spend-based targeting and price inflation

**Impact**: A calendar that selects audiences by what players have spent can raise prices or reduce value for likely spenders. That is the targeting pattern consumer regulators and the kit's ethics guide treat as an unfair practice.

**Mitigations**: The audience schema is closed (`README.md` "Audience rules"); a key for spending, purchase history, payer status, predicted value, price sensitivity or device value is rejected at authoring (`audience_key_not_allowed`) and never evaluated at runtime (INV-6). The block carries no price and no offer and never debits (INV-8). One event pays one table to everyone eligible. Test (a) of guide 06, decision rule 2, is the standard applied: a player shown exactly how the event works and what it costs would still choose it, which cannot hold for a price the player cannot see being different from another's. The FTC action against Epic Games (December 2022, $245 million refunds for dark patterns) and the EU consumer-protection network's October 2026 action on variable-reward systems and dark patterns are the enforcement context listed in guide 06 (HIGH and MEDIUM as labelled there). Under the EU Omnibus Directive a trader must disclose personalized pricing by automated decision-making (law-firm summary, MEDIUM, official text not opened); this block avoids the disclosure question by carrying no price.

**What this does not stop**: An operator can put hand-picked accounts, including big spenders, on an `allow_list`. Mitigations: an `allow_list_only` event may last at most `ALLOW_LIST_EVENT_MAX_SECONDS`, the list is at most `ALLOW_LIST_MAX` accounts and is recorded in the audit row, and the rest of the audience schema stays closed. A policy rule is still needed: allow-lists are for testers. Guide 03 describes offers tuned toward likely big spenders; those are not part of this block and the owner decides them under guide 06. MEDIUM.

### T-8. Operator error or compromise

**Impact**: A typo (an extra zero in a reward) or a stolen operator credential pays out too much.

**Mitigations**: The per-player cap and the declared budget are checked at authoring and publish (`reward_cap_exceeded`, `budget_exceeded`) and cannot be edited through the authoring routes (A-4); a published event is frozen (INV-4); a second approver can be required; every action is audited with operator and reason (INV-22); `hold` stops joins, progress, claims and grants within one write (INV-21). The block can only grant currencies and items the ledger catalog knows. HIGH for the checks.

**What this does not stop**: A compromised credential that holds author and publisher roles can still publish events up to the cap and budget on every window. Rewards earned before a hold stand (INV-10), so a hold limits future payout only; recovery of an over-payment is a ledger-side adjustment outside this block. MEDIUM.

### T-9. Content injection

**Impact**: Event copy or an asset URL contains a script or a link that runs in the web view of every player.

**Mitigations**: Event text is plain text, inserted as text, never as markup; asset URLs must be HTTPS on `ASSET_ORIGIN_ALLOWLIST` and are used only as image sources; a call-to-action opens only a route in the client's closed registry and never an arbitrary URL; text lengths are bounded by `CONTENT_LIMITS`; the page's content security policy should disallow inline script (INV-18). HIGH.

### T-10. Delivering code through the calendar

**Impact**: Treating events as a way to ship features makes the calendar a code-delivery channel. Apple Guideline 2.5.2 forbids downloading, installing or executing code that introduces or changes features or functionality of the app; Google Play's Device and Network Abuse policy forbids downloading executable code from outside Google Play and exempts code that runs in an interpreter or webview with indirect API access (both HIGH, read 2026-10-27).

**Mitigations**: Events are data validated against a schema; `config` has no script or expression fields; renderers are compiled into the build and keyed by `type@config_schema_version`; a new type or schema waits for a release and sets `min_app_version`. Whether a particular web-tech shell's own update mechanism is allowed under those policies is a question for the app owner and is not decided here. MEDIUM.

### T-11. Timezone changes to gain a daily window

**Impact**: A player changes the account timezone so a local daily event starts earlier than it otherwise would.

**Mitigations**: A local window is latched at first listing and never moves (INV-19); the timezone change rate limit belongs to `engagement.daily-streak`; each instance pays at most its table maximum.

**What this does not stop**: Changing the timezone before the next instance is first listed can bring that instance forward by up to the zone difference, at most once per allowed timezone change. Bounded by the rate limit and the per-instance cap. MEDIUM.

### T-12. Load spikes and stuck work

**Impact**: Every client refetching at the same boundary, or a ledger outage leaving claims unpaid.

**Mitigations**: Client jitter (`BOUNDARY_JITTER_MAX_SECONDS`) and `next_boundary_at`; rate limits on progress and claim; discovery cost bounded by the number of published events near `server_now`; settlement in batches and per-row transactions; retry with backoff and a cap, alerts on backlog age and on claims at `GRANT_MAX_ATTEMPTS`; holds never auto-release.

### T-13. Privacy

**Data kept**: per account and event: participation, progress entries with `source_ref`, claims with ledger references, and the eligibility snapshot (segment, platform, country code, app version). No spend or balance is stored here.

**Rules**: `deleteAccount(account_id)` erases the account's participation, entries, claims and merge records on request from `auth.guest-account` (purge) and `compliance.account-deletion`, and is safe to repeat; foreign-key cascades are a second barrier. The country is derived from the IP at request time and only the code may be kept in `eligibility_snapshot`; the IP is not stored with event data. Logs record ids, codes and counts, never request bodies, content text, preview tokens or operator credentials. Rows cascade-delete with the account (`compliance.account-deletion`) and are purged `HISTORY_RETENTION_SECONDS` after archive. Analytics events carry no spend or price (`frontend.md` "Analytics"). Event content must not contain personal data. MEDIUM.

### T-14. Misleading urgency

**Impact**: A countdown that restarts, an end that moves again and again, or an event presented as a one-off that returns makes players act on a deadline that is not real. Guide 15 (catalog row 5) grades it RED: the UK banned practice of an in-game item "only available for five days" that returns ten days later and the EU network's "misleading countdown timers" (both HIGH there). It asks of the calendar a server `ends_at` that never restarts and a recurring event that says it returns.

**Mitigations**: Every end is the server's `ends_at`; an event id never returns from `ended` to `live`; the client rebuilds a countdown from `ends_at` on each response (INV-25). An extension happens only before the end, within `MAX_EXTENSION_SECONDS` in total, with a recorded reason, and is disclosed to players through `original_ends_at`. Every event with a `series_key` is returned with a recurrence label that the client must show (INV-26), and authoring warns when a new event repeats an earlier one without a series (`repeat_without_series`). Ending-soon changes no reward (INV-12). Rewards depend on play and never on spend (INV-6). HIGH for the block's own rules.

**What this does not stop**: Free text in `content` can still say "last chance" on a recurring event; the calendar prints its own recurrence label beside it, the runbook forbids the claim, and no automatic text check exists. An operator can chain an `end_now` and a new event with the same title to simulate a restart; `repeat_without_series` warns and the recurrence label applies once a series exists. MEDIUM.

## Verification map

| Threat | Verified by |
|---|---|
| T-1 | `local-windows-and-clock.feature`, `fixtures/time-cases.json` client clock cases |
| T-2 | `participation-and-rewards.feature` (replay, parallel claim, sweep, ledger failure) |
| T-3 | `participation-and-rewards.feature` (bounds, duplicates) |
| T-4, T-5 | `discovery-and-targeting.feature` |
| T-6 | `emergency-and-preview.feature` |
| T-7, T-8 | `calendar-authoring.feature` |
| T-9, T-10 | `acceptance.md` content and delivery checks |
| T-14 | `event-lifecycle.feature` (no restart, disclosed extension), `discovery-and-targeting.feature` (recurrence label), `calendar-authoring.feature` (`repeat_without_series`) |
| T-13 | `participation-and-rewards.feature` (`deleteAccount` safe to repeat) |
