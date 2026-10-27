# Security: Timed Queues

> Threats are ordered by what a player can gain: free time and free output first, then price tricks, then harm to other accounts or to the player. Each threat names its mitigation by invariant (`README.md` section 8) and says what the mitigation does not stop. Confidence labels: HIGH (follows from a stated rule or a source), MEDIUM (inferred), LOW (guess).

## Access rules

| Resource | Anonymous | Signed in or guest (own account) | Another account |
|---|---|---|---|
| `GET /api/queues` | Denied | Read own | Not addressable |
| start, collect, collect-all, cancel, quotes, speed-ups, unlock, claim-purchase, nudge | Denied | Write own | Not addressable (`item_not_found`) |
| `publish_definitions`, `rebase_shorter` | Not routable | Not routable | Operator only |
| `reduce_remaining`, `holdings`, `mergeAccounts`, `deleteAccount`, `on_purchase_state_changed`, recovery sweep | Not routable | Not routable | Internal callers only |

No route takes `account_id` or `tenant_id` from a body, query or header (INV-23). The tenant comes from deployment configuration. An item, quote or slot of another account answers `item_not_found` or `quote_invalid`, never 403, so ids cannot be probed.

---

## Threat model

### T-1. Device clock manipulation

**Impact**: High if it worked: skipped waits, instant output.

**Mitigations (INV-1, INV-2, INV-10)**: `starts_at`, `ends_at` and the effective state come from the server clock. The client sends no time, duration or price; a body that carries `now`, `starts_at`, `ends_at`, `server_now`, `duration_seconds`, `price` or `amount` is rejected `unexpected_field`. The countdown uses the response's `server_now` with a monotonic timer, and zero on screen triggers a request, never a local "ready". Queue state is server-owned and absent from the client snapshot, export and import (`data.progress-sync`), so a restored or edited local file cannot rewrite an item.

**Not stopped**: a player can still change the device clock and see wrong countdown text until the next response; nothing is owed or lost because of it. HIGH.

### T-2. Replay and double claim

**Impact**: High: duplicate output, duplicate refunds, duplicate speed-ups.

**Mitigations (INV-4, INV-5, INV-7)**: start is idempotent by `attempt_id` (unique per tenant and account); speed-up by `attempt_id`; collect and cancel by item state. Every ledger call carries a key built from `item_id` or `reduction_id` and the line number; the ledger returns the original entry for a repeat and rejects the same key with different arguments (`idempotency_conflict`). `collected` is set after every line is applied.

**Not stopped**: a bug in key construction (for example a key that includes a timestamp). The acceptance checklist tests keys against `fixtures/lifecycle-cases.json`. HIGH.

### T-3. Race across devices

**Impact**: Medium: two items in one slot, two spends for one start, two collects.

**Mitigations (INV-3, INV-6)**: every write to an account's items in a queue is a compare-and-swap on `queue_states.version`; one start is in flight per account and queue; lane depth and stacked time are checked inside the swap; the unique (account, queue, slot) on `slot_unlocks` and unique `attempt_id` guard the other races. The loser re-reads and receives the winner's result or a retry code.

**Not stopped**: a client that retries forever on `start_in_progress`; the rate limit answers `rate_limited`. HIGH.

### T-4. Price tampering and quote abuse

**Impact**: High: cheaper speed-ups.

**Mitigations (INV-11, INV-12)**: the price is computed on the server from remaining time and the published curve; the client sends only a `quote_id`. A quote is bound to the account, the item, the item's `schedule_version` and a validity window; it is consumed on use. The charge is `min(quote, current price)`, so an old quote can never charge less than the current price and a stale one is refused. A quote for another account or item answers `quote_invalid`.

**Not stopped**: a lower price inside the window after a config change that raised prices is honored for at most `QUOTE_TTL_SECONDS` (by design, the player-favorable side of the window). HIGH.

### T-5. Lower-price window abuse

**Impact**: Low to Medium: farming quotes at a moment with a short remainder, then using them on a different item.

**Mitigations**: a quote names its `item_id` and `item_schedule_version`; using it on another item answers `quote_invalid`; after any change to the item it answers `quote_stale`. The free finish applies to the actual remainder at spend time through `chargeFor`, not to the quote's remainder.

**Not stopped**: nothing relevant; the window cannot be moved to another item. HIGH.

### T-6. Negative, huge or fractional counts

**Impact**: Medium: negative `max_count` that grants items, `max_count` of billions.

**Mitigations**: `max_count` and `slot_index` must be positive integers within bounds (`max_count <= 1000`, a client default for sanity; the server consumes `min(max_count, needed)`); a non-integer or non-positive value answers `invalid_request`. The ledger itself rejects `invalid_amount`.

**Not stopped**: nothing relevant. HIGH.

### T-7. Refund arbitrage

**Impact**: Medium: start, cancel and profit from a config change.

**Mitigations (INV-9, INV-16)**: a cancel refunds from the item's snapshot (input lines and fraction), never from the current definition, so a later cost change helps or hurts no one; a refund never exceeds what was spent; `floor` per line; a ready item cannot be cancelled; a speed-up already paid is not refundable, so cancel-after-speed-up cannot launder currency.

**Not stopped**: a player can cancel a running item repeatedly at the stated loss (50% by default); that is the price of changing one's mind and is disclosed. HIGH.

### T-8. Stacking and growth exploits

**Impact**: Medium: an unbounded lane, an unbounded ready list, a very long chain.

**Mitigations (INV-3)**: `lane_depth`, `MAX_LANE_SECONDS`, `READY_UNCOLLECTED_MAX`, `INPUT_LINES_MAX`, `COLLECT_ALL_MAX`, `STARTS_PER_MINUTE_MAX` and `SLOTS_HARD_MAX` bound every list a request can grow. Prerequisites and `max_active_per_account` stop duplicate one-time upgrades. A start always passes the cap checks inside the swap, not only on the earlier read.

**Not stopped**: a bot that starts the cap number of items per minute with real resources; that is play, not an exploit. MEDIUM.

### T-9. Definition tampering

**Impact**: High: a client that picks its own duration, cost or output.

**Mitigations (INV-9, INV-24)**: the client sends ids only; the server reads definitions, snapshots them into the item, and pays the snapshot. Definition sets enter only through `publish_definitions`, an operator operation that validates V1 to V9; it has no route a client can reach.

**Not stopped**: a compromised operator account; protect `publish_definitions` and `rebase_shorter` with the operator access controls of the host. HIGH.

### T-10. Ledger down or slow

**Impact**: Medium: lost spend, lost grant, stuck items.

**Mitigations (INV-5, INV-7, INV-8)**: reserve before spend, record before grant, deterministic keys, a recovery sweep that repeats the same calls, undo with `timed-queues.cancel-refund` when a later line fails, and an alert after `RECOVERY_ALERT_MINUTES`. A refused grant for `balance_limit_exceeded` leaves the item `ready`; nothing is destroyed.

**Not stopped**: a ledger outage longer than the alert window leaves players waiting; the alert exists so an operator acts. HIGH.

### T-11. Slot purchase fraud

**Impact**: High: free permanent slots.

**Mitigations (INV-21)**: this block never verifies a receipt; it accepts a slot only from a `purchase_record` with `state = verified`, the session's `account_id`, `product_kind = non_consumable` and a product named by a locked slot. `store_transaction_id` is unique per tenant on `slot_unlocks`. A refund sets the slot `revoked` and stops new starts in it; a reversed refund restores it.

**Not stopped**: a refund after the player already collected output from items run in that slot; the store and `billing.virtual-currency` own refund policy and the block only stops new starts. MEDIUM.

### T-12. Enumeration and information leaks

**Impact**: Low.

**Mitigations (INV-23)**: ids are random `unique_id` values; another account's rows answer `item_not_found`; error bodies carry codes and numbers, never other accounts' data; events carry `account_id` only in the shared envelope the analytics pipeline already protects.

**Not stopped**: timing differences between "not found" and "not yours"; use one code path for both. MEDIUM.

### T-13. Hand-off content and stale local notifications

**Impact**: Low.

**Mitigations (INV-22)**: the event carries only ids and kinds (`queue_code`, `queue_kind`, `job_id`, `slot_index`); the push template is generic ("a timer has finished") and shows no amounts. A local notification can fire for an item changed on another device; the push block cancels local notifications on session start and reconciles with the server list.

**Not stopped**: a stale notification after a collect on another device; it opens the panel, which shows the true state. HIGH.

### T-14. Paid speed-ups for children

**Impact**: High (regulatory and harm): premium currency spent by minors on skipping waits.

**Mitigations (INV-17, config `PAID_SPEEDUP_FOR_MINORS`)**: paid speed-ups are refused for accounts the adopter flags `is_minor` unless the adopter opts in; the free finish, time items and waiting remain. CPC principle 7 and guide 06 test (c) are the basis (non-binding, HIGH for the text; the default is a kit recommendation, MEDIUM).

**Not stopped**: a minor who is not flagged. Age handling belongs to the adopter (guide interview 4). MEDIUM.

### T-15. Account merge and deletion

**Impact**: Medium: duplicated items or slots through a merge, leftover data after deletion.

**Mitigations (INV-25)**: `mergeAccounts` is idempotent by `merge_id`, refuses while rows are pending, keeps the busier lane and refunds the other in full, and never creates output; `deleteAccount` removes the rows in all six account tables and is safe to repeat; armed hand-offs are resolved.

**Not stopped**: a colliding purchased slot that finds no free index is listed for the operator (extrapolation, README Origin). MEDIUM.

---

## Data handling

| Data | Sensitivity | Rule |
|---|---|---|
| `queue_items`, `queue_states`, `slot_unlocks` | Gameplay state | Server-owned; erased with the account |
| `speed_up_quotes`, `time_reductions` | Spend records | Retained per `QUOTE_RETENTION_DAYS` and the adopter's financial-record policy; erased with the account unless the adopter must keep spend records (state the choice in the privacy page) |
| `store_transaction_id` on `slot_unlocks` | Payment reference | No card or personal data; the purchase record itself stays with `billing.virtual-currency` |
| Events | Analytics | No real-money amounts, no personal data beyond the shared envelope |

## Logging

Log request ids, `attempt_id`, error codes and ledger entry ids. Do not log session tokens or full request bodies. An alert on any `unexpected_field` from a production client version is a useful tamper signal (LOW: a heuristic).
