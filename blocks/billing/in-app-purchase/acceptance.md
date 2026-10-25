# Acceptance — In-App Purchase: One-Time Unlock

Verification checklist Claude Code runs AFTER implementation, BEFORE reporting done. Every item must pass. Items marked **(extension)** apply only if the OPTIONAL EXTENSION was built; items marked **(manual, store console)** cannot be checked from code and go into the report as "needs manual setup".

## Build & Types

- [ ] The project's type check passes with zero errors
- [ ] The store SDK is imported only from the real port file, never from components or the gate
- [ ] No `any` types except with an explicit justification comment

## Free slice and gate

- [ ] `FREE_SCOPE_COUNT` and `FREE_RULE` exist as named configuration, with the values the owner chose
- [ ] `fixtures/free-slice-catalog.json` expectations pass for both `every` and `any` (the unit test for the free-slice rule reads the fixture)
- [ ] An item with no scopes, or with an unknown scope, is locked
- [ ] `FREE_SCOPE_COUNT = 0` frees nothing; a count at or above the scope count frees everything
- [ ] Difficulty (or any other attribute) is never read by the gate
- [ ] Exactly one gate function exists and every content entry calls it (list the entries found in the codebase in the report)
- [ ] The gate runs before sessions are cut to length; a size-2 request from the fixture yields `q1`, `q2`
- [ ] Nothing playable opens the paywall and the entry reports failure; an empty request does not open it
- [ ] Resuming a stored session does not call the gate
- [ ] The paywall is not opened by any start-up code path (verified by a test that boots the app and checks it is closed)

## Store port and inert behavior

- [ ] `PurchasesPort` has `active`, `start`, `identify`, `offer`, `buy`, `restore`; every call returns a reply value and does not throw
- [ ] The inert port is returned for: browser, dev, test, and a native build with no key for its platform
- [ ] A native iOS build uses only the iOS key and a native Android build only the Android key (the four-row table in `inert-mode.feature` passes)
- [ ] With an inert port: everything is unlocked, no store call is made, no paywall is rendered
- [ ] The SDK module is imported lazily; the browser build never evaluates it
- [ ] The plugin object is carried inside a plain object when returned from a promise

## Purchase, restore, errors

- [ ] The paywall shows the price from the store's price string; no price constant exists in the app code
- [ ] `buy()` purchases the package `offer()` showed; without one it answers `noOffer`
- [ ] A successful buy or restore closes the paywall and shows one confirmation
- [ ] Every row of `fixtures/store-errors.json` maps to the listed problem; `cancelled` shows nothing
- [ ] A failed call leaves the paywall open and re-enables Buy and Restore
- [ ] A second tap while a call runs is ignored
- [ ] Restore is visible in all four offer states (`loading`, `ready`, `none`, `failed`)
- [ ] `offerState = none` shows no Buy button; `failed` shows Try again and reloads the offer
- [ ] Restore with no purchase shows the "no purchase found" text
- [ ] Store calls (start, identify, offer, buy, restore) run one at a time
- [ ] A failed store start is retried by the next store action
- [ ] A store-pushed update unlocks and closes the paywall; a later update with no entitlement locks again

## Identity

- [ ] The store is configured with the account uid when signed in, null (anonymous) when signed out
- [ ] Sign-in calls log in as the uid; sign-out calls log out; neither reconfigures the SDK
- [ ] The app user id sent to the store is never an email address or display name

## Security

- [ ] No store secret (service-account JSON, IAP key file, key id, issuer id, promo codes) exists in tracked files; `git check-ignore` reports the secrets and env paths as ignored
- [ ] The Test Store key (`test_` prefix) is absent from the final native bundle
- [ ] Public SDK keys are read from build-time environment, not written in source
- [ ] A release candidate with the keys shows the paywall on a locked item (run on a simulator or device)
- [ ] The store listing / app-access text does not contradict the declaration about reviewer credentials
- [ ] **(extension)** The webhook rejects calls without the shared secret using a constant-time comparison, and never logs the secret or body
- [ ] **(extension)** An event older than `last_event_at` does not change `entitlement_mirror`

## Data

- [ ] If the catalog lives in SQL: the `gated_scopes` migration runs on a clean database and is idempotent; `scope_key` and `sort_order` are UNIQUE
- [ ] **(extension)** The `entitlement_mirror` migration runs on a clean database; (`account_id`, `entitlement_key`) is UNIQUE

## Store console (manual, store console)

- [ ] RevenueCat: product (non-consumable), entitlement `pro` with the product, offering `default` with one `$rc_lifetime` package, verified through RevenueCat's public API with each platform's public key
- [ ] The product identifier is identical on both stores
- [ ] Google Play: product active with a base price and regions; service-account credentials show valid in RevenueCat; promo codes created and entered in the app-access form
- [ ] App Store Connect: IAP created, IAP key uploaded to RevenueCat and valid, Paid Apps Agreement active, IAP added to the first version submission with a paywall screenshot
- [ ] The RevenueCat app and public key existed before the first store upload

## Tests

- [ ] Unit tests pass for: free-slice rule, `keepPlayable`, `hasPro`, `purchaseProblem`, store-key selection
- [ ] Component or integration tests with a fake port pass for every scenario in the five `.feature` files
- [ ] At least one test exercises the gate with an inert port and one with a locked, active port

## Configuration

- [ ] The app starts and works with no store keys set (inert)
- [ ] `STORE_KEY_IOS`, `STORE_KEY_ANDROID`, `ENTITLEMENT_ID`, `PRODUCT_ID`, `FREE_SCOPE_COUNT`, `FREE_RULE` are documented in the project's setup notes
- [ ] The report lists every manual step left (store console items above) and every `Assumption:` made
