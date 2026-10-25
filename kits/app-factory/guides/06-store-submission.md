# Store Submission

Take a signed, payment-ready build through Google Play and the Apple App Store. This guide holds both runbooks, the rules for giving reviewers access to paid content, the Apple review package, the store CLIs, and the line between what an agent may drive and what only the human may do. Guide 05 must be done first: signing, bundle ids and the payments keys.

## Decision rule

1. **Order.** Submit to Google Play first, because its review is the longer one. Submit to Apple the same day only if the Apple lane is ready: membership active, agreements and bank and tax Active, bundle id owned, review package recorded. An Apple submission that is not ready costs a full review round.
2. **Dependencies.** Never fill a declaration before the decision it depends on. Paywall coverage decides the Play "App access" answer. Real data flows decide the privacy policy, and the privacy policy is the single source for Play Data safety and Apple App Privacy. Content rights decide the Apple Content Rights answer and any "protected third-party material" answer.
3. **Who acts.** An agent may drive any step that is reversible and inside the owner's instructions. Anything that is a legal statement in the owner's name, spends money, deletes data, or needs the human's credentials is the human's. The full split is in the automation boundary below.

## Default path

All durations in this guide were observed once, on one project; treat them as order-of-magnitude, not promises. Store consoles change, so confirm accepted sizes and field names in the console itself.

### 1. Day-one lead-time items

Start these before the app is finished, because they are waits, not work.

- Apple Developer membership active for the team that will own the app. A renewal took about a day (observed once, on one project; a new enrolment may take longer and was not observed).
- Apple agreements: Paid Apps Agreement, bank account, tax forms, plus the EU trader decision. Only the Account Holder can do these and they need the human's phone (two-factor codes). Apple said processing could take up to a day; it was Active in under an hour (observed once, on one project).
- Google Play developer account and payments profile. Personal developer accounts created after 13 November 2023 must run a closed test with at least 12 testers opted in continuously for at least 14 days before they can apply for production access (Google Play Console Help, "App testing requirements for new personal developer accounts", checked 2026-10-22). Organisation accounts are not covered. The source project used an older account and never met this; start the closed test on day 0, because it alone sets a floor of two weeks.
- A privacy policy page at a public HTTPS URL, written from what the code actually does. Never reuse another product's or a company-wide policy: one said "no personal data collected" and would have contradicted sign-in and cloud storage.
- A role-based support email, not the owner's personal address, used in the policy, the listings and the review contacts.
- Content rights in writing, before any console form that asks about them.
- One canonical host for the privacy URL, used on both stores.

### 2. Google Play runbook

1. Create the app record (name, package, app type, free or paid). Two certification boxes (developer policies, export laws) are legal statements: ask the human before ticking them.
2. Upload the signed `.aab` to the internal testing track first. This needs no store review and proves the upload path.
3. Create the in-app product at the chosen price. The dialog may default to another currency; set the base price deliberately and enable all regions you intend to sell in. Create the service account for RevenueCat and grant it only the permissions it needs, scoped to this one app (view app information, view financial data, manage orders). Credential validation can lag the grant by minutes to hours.
4. Store listing: name, short and full description, icon, feature graphic, phone screenshots. Do not mention a purchase in the text before the product exists.
5. Declarations, each derived from the code and the built manifest, not guessed:
   - Privacy policy URL.
   - Ads: none if the manifest has no ad SDK. Check the merged manifest for the advertising-ID permission; the billing permission should be present.
   - App access: restricted if a paywall locks content (see reviewer access below).
   - Content rating questionnaire, target audience (a locked section until App access is done), government, financial and health declarations.
   - Data safety: export the CSV template, fill one row per data type from the code, import it. The importer rejects "users can delete data" without a deletion URL; use the privacy page URL or a dedicated page.
   - AI-generated asset declaration in the listing's review step, for every image that used generation.
6. Production release: upload the bundle with the real key built in, select countries (the release errors with no countries), write release notes, save, then "send for review". Managed publishing may be unavailable before the first publish, so the release goes live automatically on approval.
7. Console quirks worth knowing: deep links redirect to the app list or an open draft, so click through the sidebar; the asset library takes one file per chooser; "Save" only stages while contact details need "Save and publish"; downloads (service-account key, promo codes) may land in the automation browser's temp folder, so find the file and move it to the secrets folder with mode 600; a stray draft from an earlier session belongs to its owner, so ask before touching it.
8. After approval, read the Console warnings (code optimisation, edge-to-edge). They do not block the release.

Observed once, on one project: about seventy minutes from app creation to "send for review" with several agents working in parallel, then roughly sixty-four to seventy-four hours to publication, with no rejection.

Release choice with risk: the agent recommended internal testing with a real license-tester purchase before production; the owner chose production. The paywall was never purchase-tested before release. If you take that route, say so in the handoff and plan the first real purchase test immediately after publication.

### 3. Reviewer access to paid content

Both stores require a reviewer to reach what you sell.

- **Play.** When App access is restricted, reviewers must reach paid content, and they cannot pay. Create promotional codes for the product (Monetize, Promotions; the first use requires accepting the promo-code terms, which is the human's). The start date is the day after creation, so create them before submission, not on submission day. Put sign-in or code instructions in the "Sign in details" field (500-character limit). That dialog refused to save until the box "reviewers get full access including paid content" was ticked; it is only true once the codes exist. Do not tick it earlier.
- **Apple.** Submit the in-app purchase together with the first app version, and attach a screenshot of the paywall to the product. Reviewers purchase in the sandbox; the app must show Restore Purchases. Untick "Sign-in required" if no account is needed. If a sign-in is needed, supply a working demo account.
- Keep the listing document, the declaration and the code consistent. The source project's draft said "all content reachable without sign-in" while the paywall locked content; the fix cost a promo-code program and a re-declaration.

### 4. Apple App Store runbook

1. Confirm both teams, agreements and bundle-id ownership (guide 05). Build upload needs no API key: `xcodebuild archive`, then `-exportArchive` with `destination=upload` and `-allowProvisioningUpdates`.
2. Create the App Store Connect app record (SKU equal to the bundle id is a clean default).
3. Listing: name, subtitle, promotional text, description, keywords, support and marketing URLs, copyright, category, every locale you ship. Screenshots must show the real app in use (Guideline 2.3.3). Confirm the accepted size from the upload slot in the console. One slot accepted 1206x2622 and rejected 1290x2796. Crop other-platform status bars and gesture bars from screenshots that came from an Android emulator.
4. Age rating questionnaire (answer from the code; check no automated loop left an override set). Pricing and availability. Release mode: manual if you want to control the launch.
5. App Privacy: copy the Play Data safety answers; doing Play first saved the time.
6. Content Rights and the EU: Content Rights is a legal statement, the human's. If you do not want to publish a trader address, phone and email on EU product pages, remove the EU storefronts and revisit if you add them later.
7. In-app purchase product: availability saved, price, localisation, review screenshot, review notes, state "Ready to Submit". A first save of availability may not persist; re-check before "Add for Review". The pricing "Next" can open an Offer Codes dialog by accident: cancel it.
8. Attach the build, add the in-app purchase to the same submission as the app version, fill App Review Information (include the review package below), submit.
9. After approval: press "Release this version" if release is manual, then add the live store links to your web page and redeploy.

Observed once, on one project: about two hours forty-five minutes of work after the membership was active, then 21.5 hours to the first Apple response.

### 5. Apple review package (ship it on day one)

The first submission of a new developer account may come back as Guideline 2.1 "Information Needed". Apple said it was not a defect: accounts with little review history get asked for a physical-device recording and written answers. It cost a whole review round plus several hours of work (observed once, on one project). Put the package in the first submission instead.

Contents:

1. A screen recording on a physical device, latest OS, starting from launch, showing sign-in, the main features, the paywall with Restore Purchases (do not buy), Sign in with Apple, and account deletion with re-authentication. Use block `compliance.account-deletion` for the deletion flow; Apple requires in-app deletion for apps with account creation and may ask to see it. Use block `auth.sign-in-with-apple` for the equivalent login option that Guideline 4.8 requires next to a social login.
2. Written answers, also pasted into the review Notes: purpose and audience; how to reach the main features and any credentials; external services (data, auth, payment, AI); regional differences; documentation for any regulated field or protected third-party material; an overview of the in-app purchase and how to reach it. The source project's request had seven items in this shape.
3. Rights wording. Say exactly what is true: "used with the rights holder's permission, correspondence available on request". Never write "ours" or "original" for content you licensed. If the human asks you to, decline and ask what the permission actually says.

Recording hygiene: use a clean device or a clean demo account. One take captured the owner's private chat when the owner picked up the phone; another showed the owner's email in the Sign in with Apple sheet and other users' names on a live leaderboard. Delete such takes at the source (Photos, Downloads). The recording needs a human for Face ID and passcodes and for not touching the phone while it records. The device-automation server's own recorder produced no file; the path that worked was the OS Control Center screen-recording tile, then AirDrop to the computer, then compress (195 MB to 7 MB) and sample frames to confirm the content.

### 6. Store art

Real screenshots from the running app, composed into frames, over generated background scenery. Never redraw the UI, and never let a model render text (it misspells).

1. Capture phone screenshots from an emulator or simulator at the store's accepted size. Wait for tab animations to end or the shot blurs.
2. Generate background scenery with `tools/store-art-gen.py`. It needs the environment variable `OPENROUTER_API_KEY` (the owner sets it in their shell or a git-ignored env file; each run is a paid image generation, so tell the owner before a real run) and calls an external image service, so run it with `--dry-run` first to see the request, then without it. It writes `<out-dir>/<name>.png`. Prompt for scenery only, leave open space for a headline, and ask for no characters, text, logos or UI.
3. Compose with `tools/store-art-compose.py`, which takes `--config FILE` and builds phone screenshots and the feature graphic offline (no service, no key; it needs Pillow and fontTools installed). Run it with `--dry-run` first. Draw text with the app's own font rather than a model.
4. Declare generated imagery in Play's AI-asset step. The Apple form was not seen asking, but expect it.
5. Placeholder check: a Console header icon placeholder is normal before the first publish.

### 7. Store CLIs

Use a store CLI for status reads and for the writes it supports. Keep the console for what the store APIs do not expose: declarations, Data safety, promotion codes, Content Rights. Run `<cli> <command> --help` before the first use of a command and do not work from memory; flags differ between versions. Build, signing and upload commands are in guide 05.

**Google Play: `gpc`** (github.com/yasserstudio/gpc, installed from its Homebrew tap; version 1.0.0 was used). Covers release upload, promote and publish, metadata, in-app products, testers, rollout, vitals and reviews.

- Set the default app once with `gpc config set app <package>`; `--app <package>` overrides it per command.
- Authenticate with a service-account key: `gpc auth login --service-account <key file>`. Check the setup with `gpc doctor` and `gpc status`, and read release state with `gpc releases status --track <track>`.
- The service account's Play permissions decide what works. The account made for RevenueCat in the Play runbook (view app information, view financial data, manage orders) reads fine, and Google rejects `releases upload`, `promote` and `publish` from it. Releasing needs a second service account holding the release permission, granted by the owner.
- The Play API has no "Changes in review" state. The CLI reports release state per track only; the review state stays in the console.
- `gpc docs` reported a missing bundle on the Homebrew build. Read the online docs instead.

**App Store Connect: `asc`** (github.com/rorkai/App-Store-Connect-CLI, installed with Homebrew; version 5.16.0 was used). Covers TestFlight, builds, metadata, in-app purchases, submissions and review state. The repository holds the command list and workflow examples; `asc install-skills` installs the skill pack from a separate repository (github.com/rorkai/app-store-connect-cli-skills), so read the skill that matches the task before starting.

- Create an API key in App Store Connect (Account Holder), download the `.p8` once into the git-ignored secrets folder, and register it: `asc auth login --name <profile> --key-id <id> --issuer-id <id> --private-key <file>.p8 --network`. The login stores it in the system keychain under the profile name. The key used here had the App Manager role.
- The In-App Purchase key that RevenueCat asks for is a different key type and does not work with `asc`. Keep both.
- Status reads: `asc versions list --app <id>`, `asc review submissions list --app <id>`, `asc iap list --app <id>`.
- Use the long flag forms (`--app`, `--output`). Destructive commands need `--confirm`.

**Both.**

- Add `--json` to `gpc` when an agent parses the result. Run write commands with `--dry-run` first where the command offers it.
- Re-read the state after every write. A CLI that exits 0 has told you the request was accepted, not that the console shows it.
- Record the app ids, the profile names and the key file locations in the project's `AGENTS.md` (guide 07). They never go into a kit or a public repository.

### 8. Automation boundary

An agent may drive:

- Console clicking through a browser automation tool with named, resumable task spaces (names are stable; numeric ids are not; refs go stale after navigation, so use text or role locators). One task space per console.
- Builds (`xcodebuild`, Gradle), signing verification, RevenueCat and auth-provider setup, in-app product creation, pricing and availability, listing text and asset upload, CSV import and export, status reads, simulator and emulator screenshots, video trimming and compression.
- Reading console state back after every write. A "done" from any agent is a signal; re-read the console or re-run the command.

Only the human does:

- Apple and Google sign-in and two-factor codes (App Store Connect logs out repeatedly; plan for status checks that return "unknown", and prefer reading Apple's email on a decision).
- Face ID, passcodes, and any prompt on the human's phone.
- Legal and tax certifications in the owner's name: the Play create-app boxes, the promo-code terms, Content Rights, tax forms, Data safety text, privacy text.
- Bank and identity data. If the human grants access, they type every passcode, nothing is stored, and the preferred path is still the owner entering the fields.
- Spending money, buying accounts, deleting data (including the account-deletion test).
- Granting new authority. An instruction like "do it yourself" covers the named task, not the next one.

Hand-off protocol: when the human must act, hand the task space over, end the turn, say exactly what the human must do, and stop. After the human confirms, take the task space back. If the human takes control, stop and do not retry or route around.

Coordination: one agent per console and per declaration. Claim the step before starting (a message to peers, wait for the reply). Several sessions on one console nearly collided on Data safety and on creating the production release.

## Checklist

```
BEFORE ANY CONSOLE FORM
[ ] Privacy policy live at a public HTTPS URL, written from real data flows; one canonical host
[ ] Role-based support email in policy, listings and review contacts
[ ] Content rights settled in writing
[ ] Bundle ids confirmed on both stores (guide 05)
[ ] Build carries real RevenueCat keys; no test key in the bundle

GOOGLE PLAY
[ ] Signed .aab verified; versionCode higher than any upload
[ ] Internal testing release done; in-app product active; service account validated
[ ] Listing, graphics, phone screenshots, AI-asset declaration
[ ] Ads, App access, content rating, target audience, government/financial/health, Data safety (CSV, deletion URL)
[ ] Promo codes created a day ahead; Sign-in details written
[ ] Production release has countries selected; sent for review
[ ] First real purchase test planned if production went before internal testing

APPLE
[ ] Membership, Paid Apps Agreement, bank, tax Active; EU decision made or EU storefronts removed
[ ] App record, all locales, screenshots at the accepted size, App Privacy, age rating, Content Rights, pricing
[ ] Export-compliance flag set; device family correct; build processed
[ ] In-app purchase Ready to Submit, review screenshot, added to the same submission
[ ] Review package attached: recording, written answers in Notes, account-deletion flow shown
[ ] Recording made on a clean device; originals deleted
[ ] After approval: Release this version, store links added to the web page

AUTOMATION
[ ] One agent per console; step claimed before starting
[ ] Every agent "done" re-read from the console or by re-running the command
[ ] Human-only steps listed and scheduled for a time the human is available
```
