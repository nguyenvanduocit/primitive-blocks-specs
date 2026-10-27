# Security — Items

## Trust Boundaries

| Caller | May do | May never do |
|---|---|---|
| Player (session) | Read own inventory, stacks, held list and notices; upgrade, equip, unequip, discard, convert, consume and claim own items with a `request_id` | Name another account or tenant; send a level, an attribute, an amount, a cost the server did not quote, a time, or a state; read another player's item ids |
| Calling game block (service credential, in-process) | `items.grant` with a stable `source_ref`; `items.owned`; `items.active_effects` | Reach a device endpoint; write a level or an instance row; name a reason the definition does not allow |
| Random source (a calling block, in-process) | `items.grant` with `source = {kind: random, source_code, odds_version}` for items whose definition lists it | Grant an item that does not list its `source_code`; grant without an `odds_version` |
| Purchase contract (`billing.virtual-currency`, in-process) | Announce a purchase state change; `purchase_record` read | Grant items itself; change an instance |
| `auth.guest-account` (in-process participant calls) | `holdings`, `mergeAccounts`, `deleteAccount` | Move an instance by any other path |
| Operator tooling | Publish and retire definitions; read the operation journal | Edit a published definition row; edit an instance level by hand |
| Recovery, expiry and held-conversion jobs | Continue a journaled plan; run an expiry outcome | Invent a ledger line the plan or the definition does not hold |

Rules that follow: `account_id` and `tenant_id` come from the session or the service credential, never from a body (INV-3); every level, cost and clock reading comes from the server (INV-3, INV-15); every ledger call carries a key derived from the operation id (INV-10).

## Threat Model

### T1: Client-reported level, cost or attribute

**Attack**: a modified client posts `level: 10`, a lower `cost`, an `amount` or its own `attributes` to the upgrade, equip or consume endpoint.

**Impact**: HIGH. Free power and free materials in an economy that sells both.

**Mitigation**:
- The upgrade body carries `expected_version` and `expected_cost`, which are compared to server state and never applied. A different cost is `cost_changed` and spends nothing (INV-12).
- The level changes only in the compare-and-swap of the upgrade operation (INV-3, INV-13). `attributes` are written only at grant by a server caller.
- Any extra body field, and any field the server owns (`level`, `amount`, `account_id`), is rejected with `invalid_request`.

**Validation rule**: `upgrade-saga.feature` sends a body with `level` and an `expected_cost` that differs from the quote; nothing is spent and the level is unchanged.

### T2: Duplicated grants

**Attack / failure**: a caller retries, a message queue redelivers, two devices claim the same reward at once, or a replayed internal request grants an item twice.

**Impact**: HIGH. Duplicated items, or a duplicate that pays value twice.

**Mitigation**:
- UNIQUE (`tenant_id`, `account_id`, `source_ref`, `item_code`, `ordinal`) on `item_grants` decides a race; a replay returns the stored result (INV-4).
- The grant row, copy count, capacity check and instance insert commit in one transaction (INV-6); ledger lines follow with keys `items:{operation_id}:{step}` (INV-10), so recovery repeats a call without repeating its effect.
- A replay with different arguments is `idempotency_conflict` and alerts: it signals a caller bug or an attack with a captured request.

**Validation rule**: `grant-and-duplicates.feature` runs two concurrent grants with one `source_ref` and a crash-and-retry; exactly one instance and at most one ledger entry per step exist after each.

### T3: Replayed or concurrent upgrade

**Attack / failure**: a captured upgrade request is replayed after success; two taps race; two devices upgrade the same instance with different `request_id` values; a retry follows a timeout.

**Impact**: HIGH. A second charge for one level, or a level raised twice for one payment.

**Mitigation**:
- The operation key `request:{account_id}:{request_id}` returns the stored result for a replay; the same id with another body is `idempotency_conflict`.
- `lock_key` `instance:{id}` is unique while an operation is non-terminal, so a second request on the instance answers `operation_in_progress` before spending (INV-11).
- The level update is a compare-and-swap on `version` and `level` (INV-13). A replay after the retention window finds a stale `expected_version` and fails `version_conflict`.

**Validation rule**: `upgrade-saga.feature` replays a completed upgrade, races two requests, and crashes between spend and apply; the level rises once and the materials are spent once.

### T4: Forced failure to keep the materials and the level

**Attack**: induce a failure between the spend and the apply (a dropped connection, a request that hits a size limit, a crafted conflict) so a refund lands while the level was already raised.

**Impact**: HIGH. A free upgrade.

**Mitigation**:
- Spend first, apply second (INV-9). The level cannot rise before the spend is recorded; refund keys are separate from spend keys and are issued only on the `reverting` path, which is reached only when the level was not applied (`nextStep` in `backend.md`).
- The compare-and-swap sets `last_operation_id`; recovery treats an instance whose `last_operation_id` equals the operation as applied and never refunds it.

**Validation rule**: `upgrade-saga.feature` injects a failure after the spend and after the apply and checks that refunds never accompany a raised level.

### T5: Cost or value tampering through a stale quote

**Attack**: the player holds a quote from before a definition publish and confirms it after the cost rose or a conversion value fell.

**Impact**: MEDIUM. A mismatch between the price shown and the price charged; a consumer-protection problem when the charged price is higher.

**Mitigation**: the server compares `expected_cost` and `expected_value` to the current definition at request time; any difference is `cost_changed` or `value_changed` with the new figures, and nothing is spent (INV-12).

**Validation rule**: `upgrade-saga.feature` publishes a new version between quote and confirm.

### T6: Probing other players' items

**Attack**: enumerate instance ids or operation ids to learn what other accounts own, or to act on them.

**Impact**: MEDIUM. A privacy leak and a path to acting on another account.

**Mitigation**:
- Every read and write filters by `account_id` from the session in the same query. An id of another account answers `item_not_found`, identical to a missing id, with the same timing class.
- Instance and operation ids are `unique_id` values with at least 128 bits of entropy (`docs/SPEC_GUIDELINES.md` section 5); no id is sequential.
- This block has no public read of another player's inventory. A feature that shows a profile or a team (out of scope) owns its own visibility rules.

**Validation rule**: `inventory-limits-and-reads.feature` requests another account's instance id and a missing id and compares the answers.

### T7: Clock manipulation

**Attack**: change the device clock to extend a booster, to stop an expiry, or to make an offer window appear open.

**Impact**: MEDIUM. Free booster time or avoided expiry.

**Mitigation**: the server clock is the only authority (INV-15). `starts_at`, `ends_at`, `expires_at`, `warned_at` and every window use the server's `now`; the client only displays a countdown from `server_now` and an absolute instant and never sends a time.

**Validation rule**: `expiry-and-boosters.feature` runs with a fixed server clock and a request whose device time is a day ahead; the result is unchanged.

### T8: Bypassing a cap through another path

**Attack / failure**: grant a count item through the ledger directly, or through a pack, to exceed the stack cap or to skip the held list.

**Impact**: LOW to MEDIUM. Stockpiles above the design cap; economy skew.

**Mitigation**: the stack cap is a rule of free sources that go through `items.grant`; a pack the player paid for is delivered in full by the ledger (a paid purchase is delivered, INV-12 of `billing.virtual-currency`), and that is intended (INV-14). Free sources are expected to call `items.grant`; the flow audit job reports `currency_flows` faucet rows of an item code whose reason does not appear in the definition's `faucet_reasons`. This block cannot stop another block from calling the ledger directly; the audit is the control.

**Validation rule**: `acceptance.md` lists the flow audit as a release check.

### T9: Hostile or mistaken definitions

**Attack / failure**: an operator publishes a definition that breaks a rule (a duplicate rule with zero value, a random source without a disclosure key, an item sold for money that expires, a required item with no free route), or edits a published row.

**Impact**: HIGH for players (value destroyed, hidden odds), HIGH for the operator (a store-policy or consumer-protection problem).

**Mitigation**: the publish step validates every rule of `README.md` "Choosing the storage mode" and refuses a violating definition; a published row is immutable (a change is a new version) (INV-1, INV-7, INV-17, INV-18, INV-21, INV-22). The cross-checks that need the ledger's `store_product_contents` run at publish and again in the flow audit.

**Validation rule**: `definitions-merge-and-erasure.feature` publishes one definition per violated rule and expects a refusal each time.

### T10: Random-source misreporting

**Attack / failure**: a source grants a rare item as `fixed` to avoid recording the odds version, or grants an item whose definition does not list it, or reuses an old odds version.

**Impact**: HIGH. A hidden odds change is the pattern a regulator fined (a South Korean fine for lowering gacha rates without notice, kit guide 06, MEDIUM, one secondary report).

**Mitigation**: `source_not_allowed` rejects a `random` grant whose `source_code` is not in the definition's `random_sources`; `odds_version` is required and recorded on the grant row and the instance, so an audit can compare it to the odds the source published at that time. The block cannot tell a `fixed` label from a true fixed grant; labeling is the caller's duty and the audit compares item rarity distributions by `source_kind` and source (design, not run).

**Validation rule**: `grant-and-duplicates.feature` rejects a random grant for an unlisted source and one with no `odds_version`.

### T11: Merge abuse

**Attack**: farm many guests, give each valuable items, and funnel them into one account; or replay a merge to duplicate instances.

**Impact**: MEDIUM. Duplicated value, or an import farm.

**Mitigation**:
- `mergeAccounts` is idempotent per `merge_id`; a second `merge_id` for a merged guest fails `already_merged`; every instance moves (one row, one owner) or converts once (INV-20).
- The per-target import rate limit belongs to `auth.guest-account` (`LINK_IMPORTS_PER_TARGET_PER_DAY`); this block adds no second limit.
- Surplus copies of a unique item convert for their disclosed value, so a merge cannot stack unique items.

**Validation rule**: `definitions-merge-and-erasure.feature` replays a merge and merges a second guest holding the same unique unit.

### T12: Saga left half-done by a deletion or a bug

**Failure**: an account is deleted between the spend and the apply, or recovery loops on a poisoned operation.

**Impact**: MEDIUM. A charge with no result, or an alert storm.

**Mitigation**: `deleteAccount` removes the journal and `billing.virtual-currency` removes the ledger rows of the same account, so no charge outlives the account. Recovery backs off per operation (`attempts`, `next_attempt_at`) and alerts at `OPERATION_STUCK_ALERT_SECONDS`; it never edits history.

**Validation rule**: `definitions-merge-and-erasure.feature` deletes an account with a `debited` operation and checks that no row of the account remains.

### T13: Oversized or malformed inputs

**Attack**: a huge `attributes` bag from a caller, a long `source_ref`, a very large `limit`, a forged cursor, a deep `random_sources` list.

**Impact**: LOW. Resource use, parse errors.

**Mitigation**: the limits in "Input Validation Rules" apply at the boundary; a bad cursor is `invalid_cursor`; `limit` is clamped.

**Validation rule**: `inventory-limits-and-reads.feature` sends a forged cursor and an oversized limit.

## Disclosure and consumer-protection requirements

These are design obligations, not code paths, and each has a place in `frontend.md`.

- **Odds are visible where the item is obtained.** Apple requires apps that offer loot boxes or other mechanisms that provide randomized virtual items for purchase to disclose the odds of receiving each type of item before purchase ([Apple, App Review Guidelines 3.1.1](https://developer.apple.com/app-store/review/guidelines/), HIGH for the text, read 2026-10-27). Google Play requires the odds in advance of and in close and timely proximity to the purchase ([Google Play Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738), section 7, HIGH, read 2026-10-27). This block carries the `random_sources` and `odds_ref` fields and shows the link on the item detail; the odds themselves and the screen that shows them belong to the random source. Whether Apple's odds sentence covers boxes bought with premium currency has no official answer in the sources the kit found (guide 14, Gaps); treat it as covered.
- **Duplicates are disclosed before the pull.** The duplicate sentence and value appear on the same surface as the odds link (kit guide 14, Decision rule 10; `frontend.md` sections 2 and 6). A duplicate has a positive value unless the rule is `cap`, which random sources cannot use.
- **Real-money value of what is priced in a purchasable currency.** The upgrade sheet shows an approximate real-money value next to a cost line in a purchasable currency, computed at the undiscounted rate by the client of `billing.virtual-currency` (kit guide 14, Decision rule 4; the principle is read through that guide, MEDIUM, and the source document was not opened here).
- **No required item sold only for money.** `progress_gating` implies `obtainable_free` at publish (INV-22). The attestation is the designer's; the block cannot verify that a free route exists.
- **An item sold for money does not expire in the inventory.** Apple's text says credits and in-game currencies purchased through in-app purchase may not expire; it does not name items (HIGH for the text, read 2026-10-27), and the block applies the stricter reading to anything sold for money (INV-17, MEDIUM).
- **Nothing is deleted silently.** A full bag holds the grant; a stack at its cap holds the rest; an expiring `convert` item pays its value; a `remove` item is removed only after the warning was shown or the maximum deferral passed (INV-5, INV-14, INV-16).
- **No time pressure from the block.** Countdowns show real remaining time as a fact. No copy in `frontend.md` uses loss framing or a purchase prompt in an expiry notice. The EU coordinated action of 2026-10-15 targets dark patterns and variable rewards (carried from kit guide 06, MEDIUM, not reopened here).
- **Children.** Where the game's age handling treats an account as a child's, random sources and any purchase path are the game's to gate. This block sells nothing and grants only what a caller asks it to.

## Input Validation Rules

| Input | Rule |
|---|---|
| `request_id` | `unique_id` form, generated by the client once per action; missing or malformed is `invalid_request` |
| `instance id`, `grant_id` | `unique_id` form; not the caller's is `item_not_found` |
| `expected_version` | integer at least 1 |
| `expected_cost`, `expected_value` | list of `{currency, amount}` with positive integer amounts, at most `UPGRADE_MAX_COST_LINES` entries; compared, never applied |
| `target_id` | `unique_id` of an `owned` instance of kind `unit` of the same account |
| `quantity` (consume, discard stack) | integer at least 1; booster consume is 1 |
| `code` | `[a-z][a-z0-9_]*`, at most `ITEM_CODE_MAX_LENGTH` |
| `order` | `newest` or `rarity` |
| `bag`, `kind` | a bag name in use; a kind from the enum |
| `limit` | integer 1 to `PAGE_SIZE_MAX`; larger is clamped |
| `cursor` | opaque token issued by the server for the same order and filters |
| grant `quantity` | instance mode exactly 1; count mode 1 to `GRANT_MAX_QUANTITY` |
| grant `source_ref` | non-empty, at most `SOURCE_REF_MAX_LENGTH` characters |
| grant `initial_attributes` | JSON object, at most `INSTANCE_ATTRIBUTES_MAX_BYTES` serialized |
| grant `source.odds_version` | non-empty `text_short` when `source.kind` is `random` |
| Any extra field | rejected with `invalid_request` |

## Secrets Management

- The internal service credential for `items.grant` lives only in server configuration and the callers' secret stores. It is not in any client bundle, repository or log.
- No store secret exists in this block: receipt verification stays in `billing.virtual-currency`.

## Logging and Privacy

Log error codes, tenant id, account id (an opaque id, never an email or display name), item code, operation id and state transitions. Do not log service credentials, `attributes` contents, or request bodies beyond ids and versions. Item ownership is personal data of the player: the events in `README.md` section 6 carry item codes and counts, never a name or an email. When an account is erased (`compliance.account-deletion`, or a guest purge through `auth.guest-account`), `deleteAccount` removes every row of this block for the account; ledger entries follow `billing.virtual-currency`'s rule.
