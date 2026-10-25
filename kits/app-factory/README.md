---
id: "app-factory"
name: "App Factory: idea to paid app on both stores"
version: "1.0.0"
tags: [mobile, ios, android, capacitor, firebase, revenuecat, store-submission]
complexity: high
estimated_effort: "days of work, plus lead times of up to weeks (account enrolment, a 14-day closed test on new personal Play accounts, store review)"
blocks:
  - id: "auth.google-login"
    phase: "login"
    when: "interview 6 chooses a login and the project has no login yet"
  - id: "auth.sign-in-with-apple"
    phase: "login"
    when: "interview 6 puts a social login on iOS"
  - id: "billing.in-app-purchase"
    phase: "payments"
    when: "interview 1 or 11 says the app charges"
  - id: "compliance.account-deletion"
    phase: "compliance"
    when: "interview 6 gives the app accounts"
  - id: "data.progress-sync"
    phase: "data"
    when: "interview 12 says progress follows the account"
  - id: "ugc.friends-leaderboard"
    phase: "social"
    when: "interview 13 says the app has friends, leaderboards or shared profiles"
guides:
  - 01-day-0-decisions.md
  - 02-lead-time-items.md
  - 03-stack-and-contract.md
  - 04-backend-login-privacy.md
  - 05-shell-payments-signing.md
  - 06-store-submission.md
  - 07-working-with-agents.md
tools:
  - file: tools/store-art-gen.py
    purpose: "Generate store listing background art"
    requires_env: [OPENROUTER_API_KEY]
    external_service: true
  - file: tools/store-art-compose.py
    purpose: "Compose phone screenshots and the feature graphic from art, screenshots and a config"
    requires_env: []
    external_service: false
---

# App Factory

## Overview

The path from an idea or a working web app to a paid iOS and Android app that has passed both store reviews. It was distilled from one mobile app built over about five days by one person directing many parallel Claude sessions, and it is written for the next app.

A kit sequences work; it does not hold implementation. The chapters under `guides/` carry the decisions, runbooks and checklists. The blocks listed above carry the implementation of each capability. The tools under `tools/` do the jobs an agent cannot do cheaply by reading: generating and composing store graphics.

Read the chapters in order. A web-only app can stop after chapter 04; chapters 05 and 06 apply when the app ships through the stores.

## Day-0 interview

Ask all fourteen in one sitting. Each is a pick-one question with a named default. A question the owner leaves unanswered takes its default and is recorded as an assumption. A default that is an action by the owner (for example supplying screenshots) is recorded as an open owner item, not as an assumption.

1. **Where does the app ship, and how does it earn?**
   Default: store apps only; one-time unlock; the web is a landing page (store links and privacy page), not a copy of the app.
   Options: web only · store apps · both; free · one-time unlock · subscription; web copy = landing page · limited demo · full free copy.
   Why it is expensive to reverse: a free full web copy undercuts the in-app unlock, and payment code is built around the model.

2. **Who may license the content, and is the permission in writing?**
   Default: written permission from the rights holder before any content work starts.
   Options: own content (the owner states so in writing) · licensed in writing · no permission yet (blocks content work).
   Why it is expensive to reverse: both stores can ask for proof, and the question tends to surface on submission day.

3. **Which stack and design system do you already use?**
   Default: the owner's stack; if none, a web framework with a component kit that the shell owner picks and records in the contract, and a Capacitor shell.
   Options: owner's stack · default stack · native only.
   Why it is expensive to reverse: switching after the UI exists means rewriting every screen.

4. **What is the product's positioning, and which 5 to 10 reference screenshots show the look?**
   Default: the owner supplies the screenshots before any UI task; one sentence of positioning in the contract.
   Options: references supplied · positioning only · none (expect heavy restyling).
   Why it is expensive to reverse: without references, the first designs get rejected and many tasks are restyled.

5. **Which backend tier?**
   Default: none when the answers to 6, 12 and 13 need no server-side data; otherwise managed auth and database with rules written before UI.
   Options: none (data stays on the device) · managed backend · custom server (needs server-side authority, a secret-holding call, other webhooks, cron or moderation).
   Why it is expensive to reverse: a custom server built and then replaced stays deployed and costs hours; adding a backend later changes the data layer.

6. **Which login providers?**
   Default: no login when the app needs no accounts; otherwise Google everywhere plus an equivalent login option on iOS (Sign in with Apple); no email and password.
   Options: no login · Google · Google + Apple · other providers.
   Why it is expensive to reverse: the store review and account deletion flow depend on the providers.

7. **Which single domain and host?**
   Default: one canonical domain and one host, chosen before the first store listing. A free host subdomain is allowed during development but never appears in a store listing or the privacy URL.
   Options: owner's domain · a free subdomain for development only.
   Why it is expensive to reverse: listings, share cards, the privacy URL and auth domains all embed it.

8. **Which developer team owns the bundle id, and is the owner the Account Holder?**
   Default: owner is Account Holder on a team that does not yet own the id; one reverse-domain id on a domain the owner controls, reserved on both stores.
   Options: personal team · company team · not yet enrolled.
   Why it is expensive to reverse: a team that already owns the id forces a different id, and enrolment takes days.

9. **Which languages ship?**
   Default: one language; where more ship, all bundled content and UI strings are translated ahead of time, never at runtime.
   Options: one language · several, pre-translated.
   Why it is expensive to reverse: runtime translation costs rework rounds and a heavier page.

10. **What are the acceptance criteria, with measurement conditions?**
    Default: cold start to the first usable screen within 3 seconds on a named mid-range Android phone and a recent iPhone; a web-layer size budget of 2 MB gzip; performance measured on the built artifact under throttling. These are starting points the owner may change.
    Options: owner supplies numbers · defaults.
    Why it is expensive to reverse: a criterion copied without conditions can be unreachable and cost hours.

11. **What is sold, at what price, and what stays free?**
    Default: one one-time unlock at a price the owner names; the free tier lets a user complete the app's whole core loop on a visible slice. Gate by coverage (how much), never by difficulty.
    Options: free · one-time unlock · subscription; free slice by count of items, by topics, or by time.
    Why it is expensive to reverse: the gate is the entitlement design, and the store product, price and review screenshots are built around it.

12. **Must progress follow the account across devices?**
    Default: no; data stays on the device.
    Options: no · yes (needs an account and a backend).
    Why it is expensive to reverse: it adds accounts, a backend and a merge rule to every stored record.

13. **Does the app have friends, leaderboards or shared profiles?**
    Default: no.
    Options: no · friends by code · public leaderboard.
    Why it is expensive to reverse: it adds public data, moderation questions and store user-generated-content rules.

14. **Which support contact address goes into the policy, listings and review contacts?**
    Default: a role-based address on the app's own domain, never the owner's personal address.
    Options: role-based address on the owner's domain · a mailbox the owner already uses for the product.
    Why it is expensive to reverse: it is published in the privacy policy and store listings.

## Chapters

1. `guides/01-day-0-decisions.md`: the fourteen decisions and their rules.
2. `guides/02-lead-time-items.md`: accounts, agreements and waits to start on day 0, and what only the owner can do.
3. `guides/03-stack-and-contract.md`: logic without UI, the contract document, quality gates.
4. `guides/04-backend-login-privacy.md`: hosting, backend tier, login, rules, account deletion, privacy page.
5. `guides/05-shell-payments-signing.md`: native shell, one-time unlock or subscription, signing.
6. `guides/06-store-submission.md`: both store runbooks, reviewer access, the Apple review package, the store CLIs.
7. `guides/07-working-with-agents.md`: directing agents and the anti-patterns.

## Checklist

- [ ] The fourteen interview answers are written into the project contract.
- [ ] Lead-time items (developer accounts, agreements, test device, promo codes) are started.
- [ ] A contract document and a committed test harness exist before parallel work begins.
- [ ] The payment product and key exist in the payment provider before the first store build.
- [ ] The privacy page, the data-safety answers and the in-app data flows match.
- [ ] Reviewers can reach paid content: sign-in details, the purchase path, a review screenshot.
- [ ] The Apple review package (recording, answers, account deletion flow) is ready on a clean device.
- [ ] Signing keys and service accounts are in git-ignored project files and the owner's password manager.
- [ ] Play is submitted first, because its review is the longer one; iOS follows the same day if ready.
- [ ] The store links are added to the web page and the web is redeployed after approval.
