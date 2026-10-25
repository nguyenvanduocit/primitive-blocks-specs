# Backend, Login and Privacy

Where the app and its data live, how users sign in, how the data is protected before any screen reads it, how accounts are deleted, and how the privacy page is written.

## Decision rule

Decide in this order. Each answer fixes the next one.

1. **One sentence per surface, on day 0.** "Web is ____; iOS and Android are ____; the paywall lives in ____ only." On the source project the role of the web build flipped three times in one afternoon (app, then landing page, then app again) because this sentence did not exist (observed once, on one project).
2. **Backend tier.** Pick the lowest tier that satisfies every requirement.
   - **A. None:** data stays on the device.
   - **B. Backend-as-a-service (Firebase by default):** all of these hold: data is per-user documents plus simple queries (top N, counts); cheating is bounded by validation that security rules can express (ranges, monotonic growth, key whitelists); no secret must live server-side, and there are no webhooks, scheduled jobs or cross-user fan-out; the payments backend is a third party (RevenueCat), not yours.
   - **C. Custom server:** only when at least one of these is true: authoritative scoring computed from data you hold server-side; a call to an API that needs a secret; webhooks from a payment provider other than RevenueCat; cron, queue or moderation work; relations that rules cannot express (rules cannot iterate list items); regulatory data residency.
   - If the request names a favourite tool or library as the reason for a server, ask which requirement it serves before building. On the source project a custom server was built from habit, then replaced the same morning, because it could not be more trustworthy than the rules and it required an OAuth client that someone had to create by hand. About two hours of work was discarded (observed once, on one project).
3. **Login.** Offer the fewest providers that the stores accept. Google; on iOS an equivalent login option next to it (Apple Guideline 4.8; Sign in with Apple is the ready-made one); email and password only if a requirement names it. Login stays optional unless the product cannot work without it.
4. **Rules before UI.** Write the data model and the access rules, and test them against the emulator, before any screen reads or writes that data.
5. **Privacy page from the real data flows.** The page is a description of what the app does, written after the data model exists, never copied from another product.

On a stack other than Firebase, the same rules apply: replace "security rules" with whatever enforces access at the data layer, and "Firebase user" with your identity provider's user.

## Default path

### Hosting

- Pick the canonical custom domain on day 0. Store listings, share cards, the privacy URL, authorised sign-in domains and data-safety forms all bake the host in, and each one needs a separate edit if it changes later.
- Static web build: a small container serving static files with scale-to-zero, or a static pages host. Both are cheap; the first request after idle is slow on scale-to-zero.
- If the host manages its own certificate, set DNS records to DNS-only; a proxying CDN in front blocks certificate validation and renewal.
- Native apps never update from a web deploy. Treat each as its own release channel.
- Confirm which account owns each hosting, DNS and backend project before the first deploy (run each CLI's "who am I" command). Projects created under the wrong organisation are hard to move later; see guide 02 for account ownership.
- Keep a short route table in the web repo: `/` the app or landing page, `/privacy` the policy, a support page, a health check.

### Backend tier B: Firebase set-up

- Create the project. Choose the database location explicitly; it cannot be changed afterwards. Pick the region nearest the users. If a create command picked a location silently, delete the empty database and recreate it.
- Stay on the free plan and set a budget alert.
- Register every app: web, iOS (the bundle id of the team that owns it), Android (debug, upload and Play App Signing SHA-1 and SHA-256 fingerprints). Authorised domains must include every host that serves the web app, or sign-in fails with an unauthorised-domain error.
- CLI limits to expect:
  - Deploy configuration can enable providers but cannot disable them; read the live state after every auth deploy.
  - Providers the config schema does not know (Apple) and switches that must go off (email and password) go through the identity admin API; the first deploy may turn email and password on, and every later deploy re-enables it if the key is still in the config.
  - Authorised domains are editable only through the config file plus a deploy.
  - The cloud CLI needs interactive login; use the Firebase CLI, which was already logged in, instead.
  - Emulators need a Java runtime on the path (Java 21 on the source project).

### Login

- Providers: Google everywhere; on iOS an equivalent login option (Sign in with Apple) when Google is offered, per Guideline 4.8; no email and password unless required. Decide with the owner and record it, because a parallel agent will otherwise restore the form.
- Optional by design: everything works signed out; nudge to sign in after some engagement, and stay quiet for a while after "Not now".
- Web: call the popup sign-in directly from the click handler, or the browser blocks the popup.
- Native: a web view cannot run the Google popup. Use the Capacitor Firebase authentication plugin to show the system sheet with native Firebase sign-in skipped. It returns an ID token; the Firebase web SDK then signs in with a credential from that token, so the web SDK holds the only session and the database client uses it. Apple needs the raw nonce and gives the user's name only on the first sign-in.
- Capacitor trap: a plugin proxy must never be the resolved value of a promise, or the runtime calls a native `then` on it and hangs. Resolve a plain object that holds it (`{ p: plugin }`). Unit tests passed; the bug appeared only in a real emulator, so keep a regression test.
- Platform ids differ. The Firebase Apple provider id must be the iOS bundle id, which may differ from the Android application id when a bundle id belongs to another team.
- "Blocked on X" notes expire. A note saying Google sign-in is unusable until an OAuth client exists was repeated by three sessions after the architecture change that made it false; with Firebase Auth, enabling the provider supplies the client. Re-test a blocker when the architecture under it changes.
- Blocks:
  - `auth.google-login`: login phase; use when the app has no login yet. On the default Firebase stack the Firebase user is the identity.
  - `auth.sign-in-with-apple`: login phase; use on an iOS app whose primary account is set up with a social login (Apple Guideline 4.8). It lists `auth.google-login` as a prerequisite, so add it after the first provider works.

### Rules before UI

- Write the data model and the access rules first. Shape whitelists, bounds on sizes and numbers, monotonic counters for totals that never decrease, server timestamps for time-derived fields (a week boundary derived from the request time, never from the client), owner-only private documents, and capability ids for sharing (a friend code is the only way to discover another user's id).
- Honest limit: if progress is reported by the client, rules can cap how fast it grows but cannot recompute it. Write that limit into the privacy and design notes instead of pretending the board is cheat-proof.
- A public leaderboard is a decision, not a default: decide who can read it (signed-in only, or everyone), which fields appear, and whether new profiles are public. Real names visible to signed-out visitors can draw questions from store review about user-generated content (report and block tools).
- Test with the emulator: a build flag that points the client at emulators, a rules test suite, and a browser script that drives the emulator's identity widget. Keep the app's default account dependency inert so no unit test can reach the network.
- Verify live, not only on the emulator: anonymous reads and writes denied, public queries behave as decided, sign-in works on every host, sign-in works on a real device from the store-signed build.
- Blocks:
  - `data.progress-sync`: data phase; use when progress must follow the account across devices.
  - `ugc.friends-leaderboard`: social phase; use when the app has friends or leaderboards. Its rules and privacy choices are the ones above.

### Account deletion

- Required in-app by the stores whenever the app has accounts. Reachable from settings, and described in the privacy page.
- Order: re-authenticate the user, delete every document that belongs to the user in one batch (profile, private documents, the friend-code registry entry), delete the auth user, and revoke the Apple token when the user signed in with Apple.
- Test it on a throwaway account on a real device, and record a short video for store review.
- Block: `compliance.account-deletion`: compliance phase, before store submission; use when the app has accounts.

### Privacy page

- Lives in the app's own repository and is served at its own route, with the languages the app ships.
- Written from verified app behaviour: list every collected field and where it goes (what the login provider stores, purchase records held by the payments provider, services the app calls), the retention and deletion path (in-app deletion plus a contact address), children, and security. Remove any claim you cannot verify.
- Never reuse another product's policy. On the source project the company policy said no personal data was collected, which would have contradicted the store data-safety form once accounts and purchases existed.
- Align it with the store forms: the data-safety answers on Android and the privacy answers on iOS describe the same flows. Align it with the app's real community behaviour too; on the source project the page described a narrower leaderboard than the rules allowed.
- Decide the support URL, marketing URL and a neutral contact address on day 0. Use the canonical domain in every store field; entries that point at a temporary host break when it goes away.

## Checklist

- [ ] One sentence per surface (web, iOS, Android, where the paywall lives) is written.
- [ ] Backend tier is chosen with the A/B/C rule; a custom server names the requirement that forces it.
- [ ] Canonical domain is chosen and used in privacy, support and marketing URLs, share links and authorised sign-in domains.
- [ ] Each hosting, DNS and backend project is owned by the account that owns the store accounts; checked with each CLI before the first deploy.
- [ ] Database location was chosen explicitly and a budget alert exists.
- [ ] Web, iOS and Android apps are registered; Android has debug, upload and Play App Signing fingerprints.
- [ ] Providers are enabled as decided and the live provider state was read after the last deploy; email and password is off unless required.
- [ ] Native sign-in uses the system sheet plus credential sign-in; plugin proxies are resolved inside a plain object; a regression test exists.
- [ ] Access rules and their emulator tests exist before the UI reads the data.
- [ ] Live checks passed: anonymous access denied, public queries as decided, sign-in on every host and on a real signed build.
- [ ] `auth.google-login` (and `auth.sign-in-with-apple` on iOS) applied if the app has no login yet.
- [ ] `data.progress-sync` applied if progress must follow the account; `ugc.friends-leaderboard` applied if there are friends or leaderboards.
- [ ] `compliance.account-deletion` applied; deletion ran on a throwaway account on a real device.
- [ ] Privacy page is in the app repo, lists every collected field, matches the store forms and the real community behaviour, and is not copied from another product.
- [ ] Support URL, marketing URL and contact address are decided.
- [ ] Any "blocked on X" note was re-tested after the last architecture change.
