# Native Shell, Payments and Signing

Turn a finished web app into a native app that charges money on both stores. This guide covers the shell, the unlock model, the order of the payments setup, signing, and the bundle-id ownership check. The entitlement layer itself (paywall, restore, inert mode, free slice gate) is the block `billing.in-app-purchase`; build it from the block and use this guide for everything around it.

## Decision rule

Four decisions, each made before the work that depends on it.

1. **Shell.** The app is already a web build and needs in-app purchase plus native social sign-in: wrap it in Capacitor. Revisit only if you also ship desktop apps, need Rust, or share a stack with another project that already uses the alternative. Both options render in the system WebView on mobile, so UI speed does not decide it; plugin coverage does (an official in-app-purchase plugin and a native sign-in plugin exist for Capacitor). Confidence MEDIUM: this is one project's outcome, not a benchmark.
2. **Unlock model.** Fixed content that people use for a bounded time (an exam, a course, a reference): sell one non-consumable "unlock all". Content or a service that keeps growing, or a cost that recurs per user: subscribe. An app the user keeps using that creates their own content (a tracker, a notes app): sell one non-consumable unlock and gate by a free cap on what they can create; subscribe only when there is a recurring cost per user. Do not sell a yearly-only subscription over fixed content, because nothing gives the user a reason to renew.
3. **What stays free.** Gate by coverage, never by difficulty. A free user must complete the app's whole core loop on a visible slice (a share of the content, or a cap on items they create), so they see exactly what the unlock sells. Decide what happens when a free user deletes an item and when a purchase is refunded. A paywall that appears on a hard item feels like a trap.
4. **Web role.** Decide what the web copy is (landing page only, limited demo, full free copy) before you set a price. A free full web copy undercuts the paid app; make it a deliberate marketing choice or do not ship it.

If you cannot state all four in one sentence each, stop and ask (see guide 07).

## Default path

### 1. Shell

- Point the shell at a bundle on disk. Do not set a remote server URL, or the store app depends on your web host.
- Build a separate multi-file bundle for native. A single inlined HTML file that is fine on the web painted blank for tens of seconds in the simulator; the multi-file bundle painted in about a second (observed once, on one project; single-file size was several megabytes). Use a relative base path and a separate output directory, and make sure the native build never overwrites the web deliverable.
- Add `viewport-fit=cover` to the page head, or the safe-area insets stay zero and the UI sits under the notch.
- Use Swift Package Manager on iOS if the plugins support it; some plugin setups need a symlink option in the shell config.
- Generate icons and splash screens from source images with the shell's asset tool, then delete the extra files it writes (web-app icons, manifest) if you do not ship a PWA.
- Remember what the shell changes about releases: web deploys never reach installed native apps. A UI change reaches mobile only through a new store build.
- Set the iOS export-compliance flag in the property list (`ITSAppUsesNonExemptEncryption=false`) when the app only uses exempt encryption, so every upload skips the prompt. Confirm with the owner that the statement is true.
- Build iPhone-only unless the app has a tablet layout. Leaving the iPad device family on makes the store demand tablet screenshots and cost one rebuild (observed once, on one project: about twenty minutes).

Traps that cost time and are cheap to avoid:

| Trap | Rule |
|---|---|
| Capacitor plugin objects are proxies that answer every property, including `then`. Returning one from an async function makes the Promise machinery call a native `then`, and the call hangs or rejects. Unit tests with plain mocks do not catch it; tapping the button on an emulator does. | Never return a plugin object from an async function. Wrap it (`{ plugin }`) and add a regression test that mocks a proxy with a rejecting `then`. |
| Gradle fails with `invalid source release` because a global Gradle property pins an older JDK than the shell needs. | Do not edit the global file other projects use. Override per command with `-Dorg.gradle.java.home=<JDK path>`. |
| `cap sync` run while Gradle is building left a missing transform-cache directory. | Never run sync and build at the same time. |
| A background wrapper reported success while the build had failed, because a subshell masked the exit code. | Write the real exit code into the log and read the log, not the notification. |
| `adb` without a serial hits the wrong device when a phone is attached. | Always pass the device serial. |
| The simulator install hangs until boot finishes. | Wait for boot before install. |

### 2. Entitlement design

Build it from `billing.in-app-purchase`. The design rules that held up:

- One choke point decides what is playable. Locked items are dropped from a session and replaced by the next playable ones; if none remain, open the paywall.
- The paywall never opens at launch. It opens when a locked item is tapped or after a win.
- Restore Purchases is always visible.
- The price shown comes from the store product, never from a constant.
- The purchase-service user id is your auth user id after sign-in, so one account unlocks every device.
- Purchases are inert unless the app runs natively and a public key is baked in for that platform. Consequence: a native build made without the key has everything unlocked. See the payments order below.
- Compute the free coverage under every candidate rule before you pick one. One word ("every skill" versus "any skill") moved the free share several-fold on the source project; the owner never chose, and that stayed an open product decision to the end.
- If a web copy ships, verify it still works with purchases inert (everything unlocked, the store never called).

### 3. Payments order

Create the key and the store product before the first store build. One project shipped release 1 without the key, so its paywall was off, and a corrected second release was needed (extra build, extra upload, extra console work).

1. Create a RevenueCat project, then one app per platform inside it. Add the Play app by package name first; service-account credentials can follow.
2. Create the product as non-consumable, with the same identifier on both stores. The store status reads "Could not check" until the store product exists; that is expected.
3. Create the entitlement. Its identifier must equal the constant in code exactly.
4. Create the offering and make it current, with a lifetime package holding the product for each store.
5. Verify through the public API, not the dashboard badge. Call the offerings endpoint with the platform's public key and confirm the current offering id and that the lifetime package maps to the product. The dashboard showed no "Current" badge while the API was already correct.
6. Put the public SDK keys (platform prefixes `goog_` and `appl_`) in a git-ignored local env file that only the native build reads. Public keys are designed to ship; everything below is not.
7. Keep the Play service-account JSON and the Apple in-app-purchase key file (`.p8`, plus its key id and issuer id) in a git-ignored project-local secrets folder with file mode 600. Back them up in a password manager on day one. Nothing secret lives outside the project.
8. The Test Store key is for screenshots and sandbox only. When Apple needs a paywall screenshot before its sandbox product loads, build once with the Test Store key, take the screenshot, rebuild with the real key, and search the final bundle for the test key prefix (`rg`) before upload. Never ship a test key.
9. Add the store side after RevenueCat: Play in-app product and service account (guide 06), Apple in-app purchase product and key. Then rebuild with both keys and archive.

Observed once, on one project: Android side about eight minutes, iOS side about twenty-two minutes, Google's grant for the service account took under thirty-five minutes to validate (the agent had predicted hours). Treat these as lower bounds for a first run, not promises.

### 4. Signing

Android:

- Generate the upload keystore locally with `keytool` (RSA 2048, long validity) and a random password, mode 600. Keep it in the git-ignored project secrets folder and have the Gradle release config read it from there or from an environment variable. If the properties are missing, the release bundle builds unsigned; treat that as a failure, not a fallback.
- Prove the bundle is signed with `jarsigner -verify` on the `.aab`.
- Play App Signing holds the real app-signing key and re-signs. A lost upload key can be reset through support, slowly. Back up keystore and password on day one.
- Every upload needs a higher `versionCode` than any before it.
- If sign-in or any API ties to the signing certificate (Google sign-in does), register the debug, upload and Play App Signing SHA fingerprints with the auth provider. The source project registered only the debug one and never tested a Play-installed build; assume this is broken until you test it.

Apple:

- Archive with `xcodebuild archive` and `-allowProvisioningUpdates`, then export with an options file (`method=app-store-connect`, `destination=upload`, `signingStyle=automatic`, your team id, `uploadSymbols=true`). The signed-in Xcode account manages the cloud distribution certificate. No API key is needed for upload.
- Add the capabilities the app uses to the App ID: Sign in with Apple, In-App Purchase.
- Do not let automatic signing run on a device under a team you have not chosen. The first signed build registers the App ID under whichever team signs it, and that choice is permanent.

### 5. Bundle-id ownership check

Run this before the native projects, the auth-provider apps and the RevenueCat apps are created, because each of them embeds the id.

1. List every Apple team the human can sign with. For each: role (Account Holder, Admin, Developer), membership status and expiry, and agreement status. Only the Account Holder can accept agreements and enter bank and tax data, which decides which team can sell.
2. Register the intended id in the Apple developer portal. "Not available" means another team owns it. Stop and decide; do not rename quietly.
3. Check the Play package is free at create time. A package name is permanent.
4. Prefer one id on both stores. If the teams differ and the id is taken, the cost is a permanent split: a second auth-provider app, a new service file and URL scheme, a second RevenueCat app, and ids that differ across every config forever.
5. Record the team, the id and the account owning each console in the repo, so no later session has to rediscover them.

On the source project the check came after the app was built. The company team already owned the Android id, the personal membership had lapsed (renewal took about a day and a half, observed once, on one project), and iOS ended with a different id, an orphaned auth app and about a day and a half of idle waiting.

## Checklist

```
SHELL
[ ] Shell loads a bundle from disk, no remote server URL
[ ] Separate multi-file native bundle; native build cannot overwrite the web deliverable
[ ] viewport-fit=cover set; safe-area insets non-zero on a device
[ ] Plugin objects never returned from async functions; proxy regression test present
[ ] iOS device family iPhone-only unless a tablet layout exists
[ ] Export-compliance flag set and confirmed by the owner

MODEL
[ ] Unlock model, free slice rule, price and web role decided and written down
[ ] Free coverage computed under every candidate rule
[ ] Paywall not opened at launch; Restore always visible; price read from the store
[ ] Purchase-service user id equals the auth user id

PAYMENTS (before the first store build)
[ ] RevenueCat project, one app per platform, product (same id both stores), entitlement, current offering
[ ] Offering verified through the public API
[ ] Public keys in a git-ignored env file; secrets in the project secrets folder, mode 600
[ ] Secrets backed up in a password manager
[ ] Final bundle searched for the Test Store key prefix: no match

SIGNING
[ ] Android upload keystore generated, ignored by git, backed up
[ ] jarsigner -verify passes on the .aab; versionCode higher than any prior upload
[ ] Signing fingerprints registered with the auth provider; installed-from-store build tested
[ ] Apple team chosen before the first signed device build; capabilities on the App ID

OWNERSHIP
[ ] Every Apple team listed with role, membership expiry and agreement status
[ ] Bundle id registered on Apple and confirmed free on Play before native projects exist
[ ] Team, id and console account owners recorded in the repo
```
