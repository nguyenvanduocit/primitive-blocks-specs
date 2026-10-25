# Day-0 Decisions

Fourteen decisions are expensive to reverse once code, store listings and agents are running. Ask the owner all fourteen at minute 0, each as a pick-one question with a named default. Anything the owner does not answer takes the default and is recorded as an assumption.

Evidence: source playbook sections 2 and 8. Every duration and count in this guide was observed once, on one project; read them as the scale of the cost, not as targets.

## Decision rule

Ask only what is expensive to reverse. For each decision, choose by the rule below. The rule says how to decide; the default is the answer to use when the owner has no preference.

| # | Decision | Rule for choosing | Default |
|---|---|---|---|
| 1 | Distribution and money | Decide the web's role before any charging code. A free, full web copy undercuts an in-app unlock. Choose the price model by how long the user needs the product: a short, bounded use favours a one-time unlock, an ongoing service favours a subscription. | Store apps only; one-time non-consumable unlock; the web is a landing page (store links and privacy page), not a copy of the app |
| 2 | Content rights | Anyone who supplies content (questions, text, images, data) must be able to license it in writing for commercial store distribution. Get this before the first extraction or generation agent runs. | Written permission from the rights holder on file before content work starts; store text says content is "used with the rights holder's permission", never "ours" or "original" |
| 3 | Stack and design system | Ask "which stack and component kit do you already use?" at minute 0. Reuse the owner's choice. Keep domain logic free of UI imports so a framework switch costs a day, not a rewrite. | The owner's stack; if none, a web framework with a component kit the shell owner picks and records in the contract, and a Capacitor shell for the stores |
| 4 | Positioning and visual references | The product category (game-like app versus reading tool versus utility) decides the look. Collect references instead of describing taste. | 5 to 10 reference screenshots from the owner before any UI task; one-sentence positioning written into the contract |
| 5 | Backend tier | Pick the lowest tier that satisfies every requirement gathered in decisions 6, 12 and 13. Add a custom server only for server-side authority, a call that holds a secret, webhooks from services other than the purchase provider, scheduled jobs, or moderation. | None when no account, sync or social feature needs server-side data; otherwise managed auth and database (Firebase Auth and Firestore), rules written before UI |
| 6 | Login | Offer the fewest providers that cover your users, or none when the app needs no accounts. Apple Guideline 4.8 requires an equivalent login option next to any third-party or social login that sets up the primary account; Sign in with Apple is the ready-made one. Avoid passwords you would have to store and reset. | No login when no account is needed; otherwise Google everywhere plus Sign in with Apple on iOS; no email and password |
| 7 | Domain and hosting | Pick one canonical domain on day 0. Store listings, share cards, the privacy URL and auth domains all embed it. A free host subdomain is fine during development and must not appear in a listing or the privacy URL. | One domain, one host, chosen before the first store listing is drafted |
| 8 | Accounts and bundle id | Find out which developer team owns the bundle id and whether the owner is the Account Holder. Use one reverse-domain id on a domain the owner controls and reserve it on both stores. A team that already owns the id forces a different id, so check first. | Owner is Account Holder on a team that does not yet own the id; one identical id reserved on Apple and Google |
| 9 | Languages | If the app ships in more than one language, translate all bundled content and UI strings ahead of time rather than at runtime. Plan a native-speaker review for the owner's language. | One language; where more ship, pre-translated in every shipped language, runtime translation out of scope |
| 10 | Acceptance criteria | State the measurement conditions with the number: device class, throttled or unthrottled run, size budget. Lighthouse measures the web layer; cold start is measured on a device or simulator. | Cold start to the first usable screen within 3 seconds on a named mid-range Android phone and a recent iPhone; web-layer size budget 2 MB gzip; performance measured on the built artifact under throttling. Starting points the owner may change |
| 11 | Price and free slice | Decide the product, the price and what stays free before store setup. Gate by coverage (how much of the app is free), never by difficulty; the free slice must let a user complete the whole core loop. | One one-time unlock at a price the owner names; the free tier covers a visible slice of the core loop |
| 12 | Cross-device progress | Sync needs an account, a backend and a merge rule for every stored record. Ask whether a user would be upset to lose progress on a new phone. | No; data stays on the device |
| 13 | Social features | Friends, leaderboards and shared profiles add public data, moderation questions and store user-generated-content rules. | No |
| 14 | Support contact | The address is published in the privacy policy, the listings and the review contacts. Use a role-based address, never a personal one. | A role-based address on the app's own domain |

## Default path

Run the interview in one sitting, in the order above, using a pick-one question per decision with the default marked. Save the answers in the project contract, not in chat.

1. **Distribution and money.** Ask web only, store apps, or both, then free, one-time unlock or subscription. Observed once, on one project: the web's role flipped twice in 15 minutes because it was decided after charging began. For a one-time unlock, use the `billing.in-app-purchase` block.
2. **Content rights.** Ask who may license the content and ask for the permission in writing. Observed once, on one project: the brief said "personal use only", monetisation was added on day 3, and the licensing question surfaced on submission day. Both stores can ask for proof.
3. **Stack and design system.** Ask at minute 0. Observed once, on one project: the owner redirected to a different framework and component kit 50 minutes in. The DOM layer was rewritten; the framework-free logic and its 133 tests survived.
4. **Positioning and references.** Ask for the screenshots now. Observed once, on one project: without references the first results were judged "AI slop" and "old-school", and about 40 tasks were restyled.
5. **Backend tier.** Take the answers to decisions 6, 12 and 13 first: if none of them needs server-side data, choose no backend. Otherwise start with the managed backend. Observed once, on one project: a custom server took about 2.5 hours and 3,401 lines, was then replaced, and stayed deployed and unused.
6. **Login.** Use the `auth.google-login` block for Google and the `auth.sign-in-with-apple` block for iOS. Apple requires in-app account deletion whenever the app lets people create an account (Guideline 5.1.1(v)), so include the `compliance.account-deletion` block in the same decision.
7. **Domain and hosting.** Pick the domain before hosting. Observed once, on one project: hosting moved across three providers and a custom domain in 35 minutes.
8. **Accounts and bundle id.** Check both teams before creating the app record. Observed once, on one project: the company team already owned the preferred bundle id, so iOS shipped with a different id on the personal team while the cross-platform config still named the Android id.
9. **Languages.** Observed once, on one project: pre-translating the whole bank took 12 agents about 26 minutes; the runtime-translation alternative took two rework rounds and produced a 36,784-node DOM.
10. **Acceptance criteria.** Observed once, on one project: copying a "performance score 90" line without conditions cost about 4.5 hours on a 2.5 MB single file (100 unthrottled, 41 to 55 on simulated Slow 4G).
11. **Price and free slice.** Ask for the product, the price and the free slice together. The gate is the entitlement design: for a one-time unlock use the `billing.in-app-purchase` block, and say what a free user may create or open and what happens when they delete something or a purchase is refunded.
12. **Cross-device progress.** Ask whether progress must follow the account. If yes, decisions 5 and 6 cannot be "none"; use the `data.progress-sync` block.
13. **Social features.** Ask whether the app has friends, leaderboards or shared profiles. If yes, use the `ugc.friends-leaderboard` block and decide who can read the public data.
14. **Support contact.** Ask for a role-based address on the app's own domain; it goes into the policy, the listings and the review contacts.

Ask decision questions with defaults, not feelings questions. Over-asking and stopping early were both common complaints, so batch the fourteen questions once, then proceed on the answers. A default that is an action by the owner (supplying screenshots) is recorded as an open owner item, not as an assumption.

## Checklist

- [ ] All fourteen decisions asked in one sitting, each with a named default.
- [ ] Answers, and every default taken by silence, written into the project contract.
- [ ] Web role and price model fixed before any charging code.
- [ ] Written content permission on file, or content work blocked until it exists.
- [ ] Stack and design system confirmed as the owner's own, with domain logic free of UI imports.
- [ ] 5 to 10 reference screenshots collected, one-sentence positioning recorded.
- [ ] Backend tier chosen; a custom server proposed to the owner before it is built.
- [ ] Login providers chosen; an equivalent login option (Sign in with Apple by default) included wherever a social login sets up the primary account on iOS.
- [ ] One canonical domain chosen.
- [ ] Bundle id owner confirmed, owner confirmed as Account Holder, same id reserved on both stores.
- [ ] Shipped languages listed; native-speaker review planned.
- [ ] Acceptance criteria written with measurement conditions and a size budget.
- [ ] Price, free slice, sync, social features and the support contact decided and written down.
- [ ] Agents never silently pick a risky default (a custom server, passwords); they propose first.
