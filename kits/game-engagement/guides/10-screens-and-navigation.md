# Screens and Navigation

A mobile game needs more screens than its core loop: a first-run path, a home, the meta and economy layers, live and social surfaces, and a set of system and legal screens that the app stores require. This guide lists every screen in phases, says which interview answer turns each one on and which block or guide specifies it, then fixes the navigation model, the popup budget, the states every screen must handle and the accessibility floor. How each feature behaves is in `11-feature-specs.md` and in the blocks' frontend files; this guide decides which screens exist and how the player moves between them. Staying-power mechanics are in `09-keeping-players.md`.

Evidence: Apple and Google policy and design pages read on 2026-10-27 (Apple's App Review Guidelines page shows "Last Updated: October 16, 2026"), WCAG 2.2 and the Game Accessibility Guidelines, named inline with HIGH, MEDIUM or LOW. A platform rule is HIGH where the current page states it. The navigation models, the home-screen anatomy and the popup budget are this kit's synthesis (LOW as evidence): no source found measures a layout, a popup cap or a navigation model against retention (see Gaps).

## Decision rule

1. **Derive the screen list from the interview.** Walk the ten answers in `README.md` and switch on only the inventory rows that an answer or a store rule turns on. Each screen costs a build, six states, copy, translations and a review pass; a screen that no answer needs stays off (kit recommendation, MEDIUM).
2. **Treat store rules as a floor that no interview answer lowers.** The platform table lists 18 rules, each adding a screen or a state. Apple states that an app which makes account deletion unnecessarily difficult "will not pass review" ([Apple](https://developer.apple.com/support/offering-account-deletion-in-your-app/), HIGH); Google names removal from Google Play as a possible enforcement for missing deletion ([Google Play](https://support.google.com/googleplay/android-developer/answer/13327111), HIGH).
3. **Keep the first run to the shortest path to the first win.** Apple asks for an instant launch, a fast, fun and optional onboarding, postponed setup, and ratings and purchases only after engagement ([HIG launching](https://developer.apple.com/design/human-interface-guidelines/launching), [HIG onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding), HIGH). An app without significant account features must work without a login ([guideline 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/), HIGH). `01-first-session.md` delays every ask until after the first win. Screens that law places ahead of data collection (consent, age) are the exception: one screen each.
4. **Choose one navigation model per archetype and cap the top level at five destinations.** Android documents the bottom bar for three to five equal destinations, and Apple advises few tabs and no More overflow (HIGH). Hub-and-spoke, map and single-screen layouts have no platform page; their fit is a kit synthesis (LOW).
5. **Route every prompt through one priority queue and show at most one non-blocking popup per app open.** Apple tells developers to avoid alerts at app start and to use alerts sparingly ([HIG alerts](https://developer.apple.com/design/human-interface-guidelines/alerts), HIGH). The cap of one and the priority order are kit recommendations (LOW).
6. **Give every screen the same six states and write their copy before building.** Loading, empty, error, offline, restricted and success are in the states table. Pricing, odds and consent copy follows the no-dark-pattern floor in `06-design-ethics-and-compliance.md` and the real-money rule under the states table.
7. **Meet the accessibility and localization floor on every screen, popups included.** The values come from Apple, Android, WCAG and the Game Accessibility Guidelines (HIGH).
8. **Recheck the platform pages in the month before submission.** Apple's guidelines page was last updated on 16 October 2026 and age-assurance rules are still moving (platform table, row 11).

## Screen inventory

"Req" means every game of that kind ships it; "Opt" means a design choice. Interview numbers refer to the ten questions in `README.md`; P-numbers refer to the platform table below. A block id names the block whose `frontend.md` specifies the screen; this table lists the screen and leaves its states, copy and events to that file.

### First run

| Screen | Purpose | Status | On when | Specified in |
|---|---|---|---|---|
| Launch screen | Bridges the OS start to the first screen: same layout as the first screen, no text, no advertising ([HIG launching](https://developer.apple.com/design/human-interface-guidelines/launching), HIGH) | Req | Always | This guide |
| Loading screen | Shows something at once while assets load; a custom game view is allowed ([HIG loading](https://developer.apple.com/design/human-interface-guidelines/loading), HIGH) | Req | Always | States table |
| Neutral age screen | Asks for age without signalling which answer passes, before any identifier is requested in a mixed audience; routes to the child or the general path | Req | Interview 4 includes children, or interview 3 sells random rewards, or open chat exists | P10, P11, `auth.guest-account`, `06-design-ethics-and-compliance.md` |
| Consent message | Collects consent for personalised ads and non-essential data where law requires it | Req | Interview 2 includes ads and interview 8 includes the EEA, UK or Switzerland | P9, `05-marketing-and-launch.md` |
| Tutorial | Playable, one mechanic per step, ends in a win | Req | Always | `01-first-session.md`, `07-hook-and-rhythm.md` |
| First-win celebration | Marks the win and hands over the starting gift | Req | Always | `01-first-session.md` |
| Starter checklist and first goals | A Home card and a full screen: ordered first-session steps, then a short, a medium and a long goal; it asks for no rating, account, permission or purchase | Req | Always | `01-first-session.md`, `engagement.objectives` |
| Notification priming sheet | One sheet before the system dialog, tied to a visible benefit; promotional switches start off | Opt | Push is used | P16, `messaging.push-reengagement` |
| Tracking explanation and system prompt | Optional pre-screen, then the system prompt, after the first win | Opt | iOS and an SDK links data across companies for advertising | P8 |
| Guest start | No screen: a guest account is created silently at first launch, and the first session stays playable if that fails | Req with guests | Interview 5 is yes | `auth.guest-account` |
| Save-your-progress prompt | A banner or bottom sheet at a natural pause after the first win: a guest game lives on this phone only | Opt | Interview 5 is yes | P2, `auth.guest-account`, `auth.google-login`, `auth.sign-in-with-apple`, `data.progress-sync` |

### Core

| Screen | Purpose | Status | On when | Specified in |
|---|---|---|---|---|
| Home | The one screen the player returns to; zones in the home table | Req | Always | This guide |
| Play screen | The loop with its goal, progress, pause and currency | Req | Always | `07-hook-and-rhythm.md` |
| Pause | Resume, settings, quit; quit warns when it costs a life or energy | Req | Always | `engagement.energy-lives` |
| Energy HUD and start cost | A meter chip with its next-point timer and an unlimited-energy boost banner; the Start control states its cost before the tap | Req with a gate | Lives or energy gate play | `engagement.energy-lives` |
| Pre-level or pre-battle | Goal, boosters, lives or team choice | Opt | Casual puzzle with boosters; collector RPG | `03-economy-and-offers.md` |
| Result, win | Reward summary, next goal, next action | Req | Always | `07-hook-and-rhythm.md`, `08-objectives-and-progression.md` |
| Result, fail | Retry, with any continue cost stated before the tap | Req | Where failing exists | `03-economy-and-offers.md`, `engagement.energy-lives` |
| Level select or map | Shows the path and the current level | Req | Interview 1 is casual puzzle | `07-hook-and-rhythm.md` |
| Base and world view | Builds, queues and the world map | Req | Interview 1 is 4X or survival | `08-objectives-and-progression.md` |
| Timer queue panel | One tab per queue, a card per slot (idle, running, queued, ready, locked), collect-all; entered from a Home entry that shows only a ready count | Req with timers | Interview 1 is 4X or idle, or builds and crafts run on timers | `engagement.timed-queues` |
| Start sheet | Cost, duration, output and cancel terms of one job before the tap; no premium currency here | Req with timers | Same | `engagement.timed-queues` |
| Cancel sheet and completion toast | What comes back on cancel; one non-blocking toast per refresh batch with Collect | Req with timers | Same | `engagement.timed-queues` |
| Idle-slot nudge | An inline card in the panel offering the next job; never a modal, badge or push | Opt | Same | `engagement.timed-queues` |
| Next-goal chip | One quiet pointer to the goal closest to done; switchable in Settings | Opt | Objectives are used | `engagement.objectives` |
| Help and tutorial replay | Easy to find after the first run | Opt | Recommended | [HIG onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) |

### Meta

| Screen | Purpose | Status | On when | Specified in |
|---|---|---|---|---|
| Progression | Level, XP, the next unlock | Opt | A player level exists | `08-objectives-and-progression.md` |
| Collection or album | Sets, completion progress | Opt | Casual album; collector roster | `07-hook-and-rhythm.md` |
| Hero or unit detail | Stats and the character view; upgrade and equip follow the item screens | Req | Interview 1 is collector RPG | `08-objectives-and-progression.md`, `engagement.items` |
| Inventory | Items, stacks, bag capacity, active boosters, expiry and held-reward banners | Opt | Items exist | `engagement.items` |
| Item detail | One item: how to get it, duplicate rule, expiry, free route, action bar | Opt | Items exist | `engagement.items` |
| Upgrade sheet | Cost lines, balances, shortfall and confirm; the shared real-money figure beside purchasable-currency lines | Opt | Items upgrade | `engagement.items`, `billing.virtual-currency` |
| Equip flow | Slot, target and a replace confirmation | Opt | Items equip | `engagement.items` |
| Inventory-full sheet | Held rewards with three exits (claim, make room, convert); opens on a player tap, never over a flow | Req with caps | Bags or stacks have caps | `engagement.items` |
| Duplicate, convert and discard sheets | What a duplicate became; the value returned and what is lost before a convert or discard | Opt | Items can duplicate or be sold | `engagement.items`, `14-rewards-resources-and-items.md` |
| Item notices and booster use | A "While you were away" list of expired and converted items; a booster sheet that states its duration | Opt | Items expire or boosters exist | `engagement.items` |
| Prestige | Explains and previews the reset gain | Req | Interview 1 is idle | `08-objectives-and-progression.md` |
| Offline-earnings summary | One popup, one-tap collect | Req | Interview 1 is idle | `08-objectives-and-progression.md` |
| Profile | Name, avatar, stats, board visibility | Opt, Req with friends | Interview 6 is friends or higher | `ugc.friends-leaderboard` |
| Achievements shelf | Lifetime chains with tiers and secrets; a tab of the Objectives screen | Opt | Lifetime rung used | `engagement.objectives` |

### Economy

| Screen | Purpose | Status | On when | Specified in |
|---|---|---|---|---|
| Wallet HUD | One balance per currency; tapping a purchasable one opens pack prices | Req | A currency exists | `billing.virtual-currency` |
| Shop | Packs, starter offer card, pending purchases, with banners for a guest note and a spend limit | Req | Interview 2 includes purchases | `03-economy-and-offers.md`, `billing.virtual-currency` |
| Currency top-up | Packs with contents as separate numbers and the store's price string | Req | Purchases | `billing.virtual-currency`, P6 |
| Purchase confirmation sheet | Contents, store price and the room left under a limit, with "Not now" as visible as Buy | Req | Purchases | `billing.virtual-currency`, `15-manipulation-and-the-line.md` |
| Purchase status and receipt | Verifying, pending, failed, rejected and blocked; a receipt of what was credited and charged | Req | Purchases | P3, `billing.virtual-currency`, `billing.in-app-purchase` |
| Spend-limit screen | Set a limit with a cool-off on raising it; spent and remaining; purchase history; help for an unauthorized purchase | Opt | Purchases | `billing.virtual-currency`, `15-manipulation-and-the-line.md` |
| Refund notice | A banner saying what the store refunded and what was removed | Req | Purchases | `billing.virtual-currency` |
| Insufficient-funds sheet | The shortfall, its indicative real-money value, and See packs beside Not now; opens only when an action fails | Req | Anything has a cost | `billing.virtual-currency` |
| Real-money figure component | Not a screen: "about" amount with an "Indicative" label beside any purchasable-currency price; rules under the states table | Req | A purchasable currency has prices | `billing.virtual-currency`, `14-rewards-resources-and-items.md` |
| Out-of-energy or out-of-lives sheet | Wait, gift, rewarded ad, then paid refills; opens on a player action | Req | Energy or lives exist | `engagement.energy-lives` |
| Refill confirmation | Exact price and balance after | Opt | Paid refills exist | `engagement.energy-lives` |
| Pass track screen | Free and premium rows, tiers, claim all, the next reward, the season countdown, an ending-soon banner | Opt | Interview 7 includes seasonal | `engagement.season-pass` |
| Premium upsell sheet | Every premium reward, the price, what is claimable at purchase | Opt | A pass sells premium | `engagement.season-pass`, P6 |
| Tier-skip and XP-boost sheets | Quote, price, balance after, confirm | Opt | A pass sells progress | `engagement.season-pass`, `billing.virtual-currency` |
| Season results | Final tier, what was delivered and claimed, what comes next | Opt | A pass exists | `engagement.season-pass` |
| Speed-up sheet | Waiting first; free finish, time items, price per step with its real-money value | Opt | Timers sell time | `engagement.timed-queues`, `billing.virtual-currency` |
| Slot unlock sheet | What a locked slot adds and every way to get it, free option first, Restore | Opt | Slots lock | `engagement.timed-queues`, P3 |
| Subscription paywall | Plans of equal weight, the full disclosure always visible, Restore, Terms, Privacy, Close | Opt | Interview 2 includes purchases and a subscription is sold | `billing.subscriptions`, P18 |
| Subscription status and manage entry | Status, dates, next stipend, Manage, Restore; a toast when a stipend arrives | Req with a subscription | Same | `billing.subscriptions`, P18 |
| Subscription state banners | Grace, retry, paused, canceled, price change, expired, revoked, pending, family | Req with a subscription | Same | `billing.subscriptions` |
| Trial-ending banner | Inside the reminder window before conversion: the end date and the price charged after it, with Manage and Dismiss; the Settings status line shows the same facts | Opt | A trial is offered | `billing.subscriptions`, `15-manipulation-and-the-line.md` |
| Win-back sheet | A welcome-back offer with the paywall's disclosure, opened from Settings or the expired banner | Opt | A subscription lapses | `billing.subscriptions` |
| One-time unlock paywall | Free count, price, restore | Opt | Interview 2 is one-time unlock | `billing.in-app-purchase` |
| Random-reward screen | Odds, pity counter, result reveal | Req | Interview 3 sells random rewards | P5, `06-design-ethics-and-compliance.md` |
| Offer popup | A starter pack or timed offer | Opt | Purchases | `03-economy-and-offers.md` |
| Rewarded-ad offer | Opt-in; states the reward before the ad | Opt | Interview 2 includes ads | `03-economy-and-offers.md`, P14 |

### Live

| Screen | Purpose | Status | On when | Specified in |
|---|---|---|---|---|
| Daily reward popup | Today's reward and claim with a short celebration, opened once per day | Opt | Interview 7 includes daily | `engagement.daily-streak` |
| Reward calendar | The cycle, milestones, freezes held, the daily-reset time zone | Opt | Same | `engagement.daily-streak` |
| Streak badge and at-risk banner | A HUD chip with the streak; an in-app reminder when the day is ending | Opt | Same | `engagement.daily-streak` |
| Streak loss sheet | A streak ended: free options always, a paid repair only when priced | Opt | Same | `engagement.daily-streak` |
| Event hub | Live, upcoming, recent and unavailable events, with update-required and paused rows | Opt | Interview 7 includes weekly or seasonal | `engagement.event-calendar` |
| Home event banner and badge | One banner slot; a count of claimable rewards and a new dot | Opt | Same | `engagement.event-calendar` |
| Event detail and results | Rules, exact rewards, timer, progress and one action; a results sheet with Claim all | Opt | Same | `engagement.event-calendar` |
| Objectives board | Tabs for starter, today, this week, season and achievements; the points ladder, claim all, expired rows | Req with objectives | Interview 7 includes a daily layer | `engagement.objectives` |
| Reroll sheet | Replace one goal, with its cost and the replacements left | Opt | Rerolls are on | `engagement.objectives` |
| New-goal toast and completion celebration | Non-blocking, queued to a calm moment | Opt | Objectives are used | `engagement.objectives` |
| Comeback reward sheet | Says what was added after a lapse; one OK button, no deadline | Opt | Comeback grants are on | `messaging.push-reengagement` |
| Inbox | Delivers compensation, gifts and unclaimed rewards | Opt | Live service (kit recommendation) | No block; Gaps |

### Social

| Screen | Purpose | Status | On when | Specified in |
|---|---|---|---|---|
| Friends and leaderboard | Friend code, ranked board, invite | Opt | Interview 6 is friends and leaderboard | `ugc.friends-leaderboard`, `04-social-and-competition.md` |
| Clan and chat | Roster, shared goals, messages | Opt | Interview 6 is clans with chat | `04-social-and-competition.md`; no block |
| Gift inbox | Friend gifts of energy; an accept-gifts setting; no ask-for-energy control | Opt | Friends and energy | `engagement.energy-lives`, `ugc.friends-leaderboard` |
| Report and block | On every chat line and public profile | Req | Chat, user content or public names | P13 |

### System and legal

| Screen | Purpose | Status | On when | Specified in |
|---|---|---|---|---|
| Settings | Music and effects volume separately, haptics toggle, language, notifications, privacy choices, account, restore, support, legal links, rate row, version, plus the block rows below | Req | Always | [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/basic/), [HIG settings](https://developer.apple.com/design/human-interface-guidelines/settings) |
| Notification settings | Permission status, master and category switches, quiet hours, a caps note, a denied banner with an inline hint | Req with push | Push is used | P16, `messaging.push-reengagement` |
| Privacy and data controls | Withdraw consent, privacy options entry, data choices | Req | Always | P7, P9 |
| Account section | Guest or provider, player ID, save progress, I already have an account, recovery code, switch account, sign out | Req with accounts | Interview 5 is yes | `auth.guest-account`, `auth.google-login`, `auth.sign-in-with-apple`, `data.progress-sync` |
| Link flow and conflict sheet | Provider buttons; when the credential belongs to another account, a sheet says what each choice keeps and removes before anything changes | Req with accounts | Same | `auth.guest-account` |
| Recovery code | Shown once with a stored-it confirmation; an entry screen on the new phone | Opt | Recovery codes are on | `auth.guest-account` |
| Welcome back, guest | Says whether the guest game was kept, removed or replaced; the safest button first | Req with guests | Same as the link flow | `auth.guest-account` |
| Pending-identity chip | A quiet chip on server features when the first launch was offline | Req with guests | Same | `auth.guest-account` |
| Sign-out welcome screen | Sign in, or play as a guest; a guest exists only on request | Req with accounts | Same | `auth.guest-account` |
| Delete account | In-app path to full deletion; the confirmation lists the balances that will be deleted | Req with accounts | Any account exists | P1, `compliance.account-deletion`, `billing.virtual-currency` |
| Restore purchases | Row in Settings and on every paywall; a result dialog for subscriptions | Req with purchases | Interview 2 includes purchases | P3, `billing.subscriptions`, `billing.in-app-purchase` |
| Support, terms and privacy links | Contact route; privacy policy link inside the app | Req | Always | P7 |
| Rating prompt and rate row | System prompt after a win; a Settings row that opens the store page | Opt | Recommended | P15 |
| Update required and maintenance | Blocks play until updated or until service returns | Opt | Live service | P17 |
| Offline state | Names what still works and what needs a connection | Req | Always | States table |
| Parental gate | Adult-level task before purchases and links out | Req | Interview 4 includes children | P10, `billing.virtual-currency` |

Settings rows that blocks contribute:

| Settings row | Block |
|---|---|
| Spending limit and purchase history | `billing.virtual-currency` |
| Subscription status, Manage, Restore, Terms, Privacy | `billing.subscriptions` |
| Notifications: status, switches, quiet hours | `messaging.push-reengagement` |
| Account section | `auth.guest-account` |
| Daily-reset time zone | `engagement.daily-streak` |
| Show the next goal on Home | `engagement.objectives` |
| Accept gifts | `engagement.energy-lives` |

## Platform requirements that add screens

| ID | Requirement | Adds | Sources and label |
|---|---|---|---|
| P1 | Apps with account creation must offer deletion in the app: the whole record, not only deactivation; confirmation steps are allowed; a link to the exact web page if finishing needs a website; tell the player when it takes time and what is kept; revoke Sign in with Apple tokens. Google asks for an in-app path plus a web resource, declared in the Data safety form | Delete-account screen in Settings | [Apple 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/), [Apple deletion page](https://developer.apple.com/support/offering-account-deletion-in-your-app/), [Google Play](https://support.google.com/googleplay/android-developer/answer/13327111): HIGH |
| P2 | Without significant account features, play without login; offering a third-party login for the primary account requires an equivalent login service that limits data to name and email, can hide the email and does not track for ads | Guest start, optional link, Sign in with Apple beside Google login (`auth.guest-account`) | [Apple 5.1.1(v) and 4.8](https://developer.apple.com/app-store/review/guidelines/): HIGH |
| P3 | Restorable purchases need a restore mechanism; a Restore Purchases button, never an automatic restore at launch; Apple's sync call only on a tap. Google: query purchases on connect and resume, grant entitlement only in the purchased state, acknowledge within three days | Restore row; pending-purchase state | [Apple 3.1.1](https://developer.apple.com/app-store/review/guidelines/), [StoreKit restore](https://developer.apple.com/documentation/storekit/restoring-purchased-products), [AppStore.sync](https://developer.apple.com/documentation/storekit/appstore/sync%28%29), [Play Billing](https://developer.android.com/google/play/billing/integrate): HIGH |
| P4 | Purchased credits and in-game currency may not expire | No expiry timer or warning on purchased balances; the text does not address earned or promotional currency | [Apple 3.1.1](https://developer.apple.com/app-store/review/guidelines/): HIGH; scope reading MEDIUM |
| P5 | Disclose the odds of every random item that can be bought before purchase; Google adds "in close and timely proximity" to the purchase | Odds panel on the screen that sells the reward | [Apple 3.1.1](https://developer.apple.com/app-store/review/guidelines/), [Google Payments](https://support.google.com/googleplay/android-developer/answer/9858738): HIGH |
| P6 | In-app prices match the Play billing interface; before asking for a subscription, say what the player gets for the price and meet Apple's Schedule 2 terms (not read) | Store price string on every pack and paywall; the real-money figure beside currency prices (copy rules under the states table) | [Google Payments](https://support.google.com/googleplay/android-developer/answer/9858738), [Apple 3.1.2(c)](https://developer.apple.com/app-store/review/guidelines/): HIGH |
| P7 | A privacy policy link inside the app and in store metadata; an easy way to contact the developer; store privacy answers (Apple labels, Google Data safety) include third-party SDK data and stay accurate | Privacy and Support rows in Settings; no screen for the labels | [Apple 5.1.1(i) and 1.5](https://developer.apple.com/app-store/review/guidelines/), [Apple privacy details](https://developer.apple.com/app-store/app-privacy-details/), [Google User Data](https://support.google.com/googleplay/android-developer/answer/10144311), [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469): HIGH |
| P8 | Tracking across other companies' apps or sites needs the App Tracking Transparency prompt; a denied or restricted status leaves the advertising identifier zeroed. A pre-screen has one button that opens the alert, and no incentive, imitation of the alert or annotation of it. Outside the EU the answer is changed only in Settings, so link there; in France, Germany, Italy, Poland and Romania the system shows a full-page sheet | Optional pre-screen; denied state | [Apple ATT](https://developer.apple.com/app-store/user-privacy-and-data-use/), [HIG privacy](https://developer.apple.com/design/human-interface-guidelines/privacy), [requestTrackingAuthorization](https://developer.apple.com/documentation/apptrackingtransparency): HIGH; the Settings-only reading MEDIUM |
| P9 | Personalised ads in the EEA and UK (from 16 January 2024) and Switzerland (from 31 July 2024) need a Google-certified consent platform; the UMP SDK is asked for an update at every launch and the app offers a privacy options entry where the message requires it. Apple asks for an easy way to withdraw consent | Consent message; Privacy choices row | [Google](https://support.google.com/admob/answer/13554116), [UMP](https://developers.google.com/admob/android/privacy), [Apple 5.1.1(ii)](https://developer.apple.com/app-store/review/guidelines/): HIGH |
| P10 | Apple Kids Category: no links out or purchases outside a parental gate, no third-party analytics or advertising. Google Families: certified ad SDKs, no interest-based ads, no interstitial at launch, rewarded ads closeable after five seconds, no blurring of coins and money, a neutral age screen for mixed audiences | Parental gate; neutral age screen | [Apple 1.3 and 5.1.4](https://developer.apple.com/app-store/review/guidelines/), [Apple kids](https://developer.apple.com/app-store/kids-apps/), [Google Families](https://support.google.com/googleplay/android-developer/answer/9893335): HIGH; mixed-audience scope MEDIUM |
| P11 | Apple's Declared Age Range API and Google Play's Age Signals API return age ranges or categories where laws require; Apple says "you must check the age" in those regions and that a child stays blocked from a significant update until a parent consents. GDPR Article 8 sets the digital-consent age at 16 unless a Member State lowers it, to no less than 13 | Waiting-for-parent restricted state; age-gated features off by default | [Apple](https://developer.apple.com/support/age-assurance/), [Google](https://support.google.com/googleplay/android-developer/answer/16569691), [GDPR Art. 8](https://gdpr-info.eu/art-8-gdpr/): HIGH for the text; the list of regions and dates LOW (Google names only Texas) |
| P12 | Age rating answers must be honest; Apple's table ties loot boxes, simulated gambling, chat and user content to rating bands | No screen; answers match the screens | [Apple 2.3.6](https://developer.apple.com/app-store/review/guidelines/), [age ratings](https://developer.apple.com/help/app-store-connect/reference/age-ratings): HIGH |
| P13 | Apps with user content or chat need filtering, a report mechanism, a block mechanism and published contact information | Report and block controls | [Apple 1.2](https://developer.apple.com/app-store/review/guidelines/): HIGH |
| P14 | Interstitials say they are ads, carry an easy close or skip control and a way to report inappropriate ads. Google bars full-screen interstitials before the splash or at the start of a level, and those not closeable after 15 seconds; opt-in rewarded ads are exempt | Ad frame; report-ad control | [Apple 2.5.18](https://developer.apple.com/app-store/review/guidelines/), [Google Ads](https://support.google.com/googleplay/android-developer/answer/9857753): HIGH |
| P15 | Apple disallows custom review prompts and caps the system prompt at three per app in a 365-day period; ask after engagement, not at first launch or from a button; a manual route is the store page link. Google enforces a quota and advises against a button that triggers the flow and against any question before the card | Rate row opens the store page | [Apple 5.6.1](https://developer.apple.com/app-store/review/guidelines/), [HIG ratings](https://developer.apple.com/design/human-interface-guidelines/ratings-and-reviews), [StoreKit](https://developer.apple.com/documentation/storekit/requesting-app-store-reviews), [Play](https://developer.android.com/guide/playcore/in-app-review): HIGH |
| P16 | Notifications need consent on iOS; Android 13 and later has a runtime permission the app triggers itself, with a suggestion to wait for a later launch or a user action | Explanation screen; denied state with a Settings link | [HIG notifications](https://developer.apple.com/design/human-interface-guidelines/notifications), [Android](https://developer.android.com/develop/ui/views/notifications/notification-permission): HIGH; applying the one-button pre-screen rule to notifications MEDIUM |
| P17 | Android's in-app update API offers a flexible flow and an immediate, full-screen flow for updates critical to core function | Update-required screen | [Android](https://developer.android.com/guide/playcore/in-app-updates): HIGH; no Apple page read |
| P18 | A subscription sign-up screen shows the name and duration, what the subscriber gets, the full renewal price clearly and prominently, a way for current subscribers to restore, and links to the Terms of Use and Privacy Policy; the billed amount is the most prominent price and any per-month figure is subordinate; a trial states its length and the price billed after it. Google asks for transparent cost, billing frequency and renewal terms without extra steps, for how and when a trial converts and how to cancel, and for an easy-to-use online way to cancel inside the app; it lists a missing or not clearly visible dismiss button and a missing manage-or-cancel link in account settings as violations | Disclosure on the paywall, a trial-ending notice, a manage entry in Settings | [Apple subscriptions](https://developer.apple.com/app-store/subscriptions/), [Google Subscriptions policy](https://support.google.com/googleplay/android-developer/answer/9900533): HIGH |

## Navigation models

| Model | Fits | Rules | Label |
|---|---|---|---|
| Bottom tab bar | Collector RPG, hybrid-casual with a meta layer: three to five equal destinations used each session | Navigation only, no actions; stays visible between sections except under a modal; no disabled or hidden tabs, an empty section explains itself; single-word labels; badges for critical information only; avoid the More overflow. Play is a full-screen mode that returns to the bar | [HIG tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [Android navigation bar](https://developer.android.com/develop/ui/compose/components/navigation-bar): HIGH |
| Hub and spoke | Casual puzzle at launch; any game with fewer than four menus | Home holds one primary action; every other screen opens from Home and returns to it by one back path | Kit synthesis, LOW |
| Map as home | Level-based casual puzzle | The current node is the primary action; side buttons open the spokes | Kit synthesis, LOW |
| Single-screen layout | Idle and incremental | Earn, buy and upgrade share one screen with panels inside it; prestige and settings are separate screens | Kit synthesis, LOW |

Hybrids work: a map or base view as Home with a bottom bar of three to five tabs. The one-handed reach argument has two parts. The platforms place the bar at the bottom of a phone (HIGH), and a 2013 observation of 780 people touching phones in public found 49% one-handed, 36% cradling the phone, 15% two-handed ([Hoober](https://www.uxmatters.com/mt/archives/2013/02/how-do-users-really-hold-mobile-devices.php), MEDIUM as an observation, LOW for current phones; the author notes grips change often). No source ties reach to game retention, so it supports putting frequent actions near the bottom edge and nothing stronger (LOW).

## Home screen by archetype

An attention mark is any badge, glow, pulse, timer ring or moving banner. Apple tells designers to reserve badges for critical information so they keep their meaning ([HIG tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), HIGH); the caps below are kit recommendations (LOW) to confirm in playtests. The zone content follows the archetype tables of `07-hook-and-rhythm.md` and `08-objectives-and-progression.md`.

| Zone | Casual puzzle or hybrid-casual | Idle or incremental | Character-collector RPG | 4X or survival |
|---|---|---|---|---|
| Top bar | Lives with timer, soft and premium currency, settings | Income per second, soft and premium currency, settings | Player level, stamina, two currencies, settings | Resource bar, power, mail, settings |
| Center | Level map or next-level preview; meta scene if hybrid | The generator and upgrade list | Hero showcase | Base view with a world-map toggle |
| Primary action | Play level N | Buy the next upgrade or collect | Continue campaign | The next-step pointer from the quest tracker |
| Ribbon | Daily reward, event, one offer | One boost offer | Events, daily reward, summon banner, pass | Events, alliance help, build queues |
| Bottom nav | None at launch, or three or four tabs | Panel tabs; prestige separate | Five tabs with the campaign in the middle | Base and world toggle, menu buttons |
| On return | Daily reward claim, lives refilled | Offline-earnings summary | Resets and refilled stamina | Finished builds, a what-happened summary |
| Attention marks besides the primary action | 2 | 2 | 3 | 4 |

Entries that blocks add to Home, and whether each counts as an attention mark (the block rules are specs; where Home carries the entry is a kit recommendation, LOW):

| Entry | Block | Zone | Attention mark |
|---|---|---|---|
| Wallet HUD, energy chip, streak badge | `billing.virtual-currency`, `engagement.energy-lives`, `engagement.daily-streak` | Top bar | No: a number or timer text; the streak badge is hidden when there is no streak |
| Next-goal chip | `engagement.objectives` | Beside the primary action | No: the block bars a badge count, a pulse and a countdown, and the player can switch it off |
| Starter checklist card | `engagement.objectives` | Center, first session only | No: no countdown; it leaves when every starter goal is claimed |
| Event banner and badge | `engagement.event-calendar` | Ribbon, one banner slot | Yes, one: the claimable-rewards count and the new dot together; an ending-soon event adds none |
| Queue entry | `engagement.timed-queues` | Ribbon or bottom bar | Yes, one: a plain number of ready items, with no pulse, glow, ring or timer |
| Subscription payment banner | `billing.subscriptions` | Shop and Settings; on Home only if the team accepts the mark | Yes, one, because it carries critical information |

Count the marks from this table when filling the zone sheet: the first three rows cost nothing and each remaining row costs one.

## Popup and interstitial budget

Four kinds of surface take attention in four ways (kit recommendation, LOW):

1. Blocking start screens: update required or maintenance, the age screen, the consent message, the guest welcome-back screen. They run before Home and are not popups.
2. One popup slot at app open, filled in this priority: a recovered-purchase receipt, a return summary (offline earnings, item notices), the daily reward or the streak loss sheet, the comeback reward, a personal offer. One non-blocking popup per open; the rest wait in the queue or become a badge.
3. Quiet surfaces that take no slot: toasts (new goal, queue complete, stipend arrived), the next-goal chip, banners (event, streak at risk, subscription state, refund), inline cards (idle-slot nudge, starter checklist). Each carries no pulse, glow or countdown, and each block states its own cap.
4. Sheets the player opens: insufficient balance, empty energy, speed-up, premium upsell, inventory full, reroll, paywall. They open from a player action, never queue and never open over another flow.

Prompts tied to a moment (rating, notification priming, tracking, rewarded-ad offer, save-your-progress) do not take a launch slot.

| Prompt | May appear | Cap | Before the first win |
|---|---|---|---|
| Update required, maintenance | On launch when the server says so | Until resolved | Allowed: it blocks, it does not ask |
| Consent, age screen | First launch or when the region requires it | Once; reopened from Settings | Only where law needs it before data collection (Gaps) |
| Guest welcome back | Start sequence, after a guest game was kept, removed or replaced | Once per outcome | Not applicable: a first launch has no history |
| Recovered-purchase receipt | App open, when a paid purchase was recovered | Once per purchase | Allowed: it reports money already spent |
| Return summary | App open after an absence: offline earnings, item notices | One summary per open; extras become inbox rows | Not applicable |
| Daily reward | App open, once per day key after the first screen is ready, never over a tutorial step (`engagement.daily-streak`) | One per day | Starts after the tutorial |
| Streak loss sheet | After a streak ended, in place of the daily popup | Capped per offer by the block | Not applicable |
| Comeback reward | App open after a lapse, when the server granted it | Once per grant | Not applicable |
| Event start | A Home banner and a new dot; no popup | The dot clears when the hub opens | No |
| Offer | After a result screen or in the shop, never the first open of a session; the starter offer card in the Shop is a card, not a popup | One per session | No; first offer after a first spend (`03-economy-and-offers.md`) |
| Rewarded-ad offer | A pain point: no lives, a failed level, a missing currency | Player-opted | No ads before the first win (`01-first-session.md`) |
| Interstitial | A natural break after a result, never at level start or before the splash | No primary source gives a number; set from soft launch | No; in purchase-led games only at session end ([Unity](https://unity.com/blog/3-ways-to-optimize-the-ad-experience-for-your-users), MEDIUM: 2021 guidance as recorded in the research notes, page not reopened) |
| Rating | After a win once engagement is shown, at the day-7 beat of `07-hook-and-rhythm.md` | The platform caps it (P15); wait a week or two between requests | No |
| Notification priming | At the first timer on a valuable resource, the second streak day or the third session (`messaging.push-reengagement`) | Never twice in a session; a re-ask after a set number of sessions, then only Settings | No |
| Denied-notification hint | Inline beside the feature it would serve, dismissible | Capped by count and by sessions between showings | No |
| Tracking prompt | After the first win, if an SDK needs it | Once; the answer changes in Settings (P8) | No |
| Save-your-progress | A banner or bottom sheet after a win at a natural pause, online guests only; a one-line note in the purchase confirmation never gates the purchase (`auth.guest-account`) | Once per session; a cooldown, then a dismissal cap, then only Settings offers it | No (P2) |
| Subscription payment banner | Where the host mounts it; returns each session while the problem lasts | Hideable for the current session only | Not applicable |

## Required states

| State | Rule | Copy rule |
|---|---|---|
| Loading | Structure appears at once; determinate progress when the time is known; hints during long loads ([HIG loading](https://developer.apple.com/design/human-interface-guidelines/loading)) | Say what is loading; no invented progress |
| Empty | Keep the tab and explain why the section is empty ([HIG tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)) | Name what fills it, with the server start time of the next event |
| Error | Say what failed, whether money or progress was touched, and give one retry; keep paid value safe (P3) | No blame; "not charged" only when the server confirmed it |
| Offline | Show cached data with a quiet label and raise no startup alert ([HIG alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)); local play continues where the design allows; action controls stay visible and disabled with their reason; timers show the last `server_now` as stale and never grant a reward from the device clock | "Connect to claim", not a red error |
| Restricted | Age, region, parental control, parent approval pending, denied permission, purchases off: say why and give the way out (a Settings link) | No guilt copy |
| Pending | Work the server accepted and has not finished (a purchase awaiting approval, an identity not yet created): say what is waiting and what the player can do meanwhile; never show it as received | "Waiting for payment approval. We will add your gems when the store confirms." Never "payment failed" when the outcome is unknown |
| Success | State what changed: amount received and the new balance | The cost and the result in one place |
| Expired and already claimed (live screens) | Show the absolute `ends_at` or the next availability | A countdown never restarts |

Real-money value. A pack, a purchase button, a paywall and a receipt carry the store's own price string. A price in a purchasable currency carries the shared `ApproxMoney` figure beside it: "about $1.19" with an "Indicative" label whose explanation says it is the standard pack rate without bonuses or discounts. The figure is `ceil_to_minor_unit(amount x P / B)`, where `P` is the store's price of the currency's reference pack and `B` that pack's base amount. It is hidden for a soft currency. It is hidden when `P` is not loaded, and a "Pack prices" link takes its place, so no figure is guessed or cached. It is display only and never reaches a grant, a spend or a settlement. Every screen that prices something in a purchasable currency uses the component (the insufficient-balance sheet, an item upgrade, a pass tier skip, an energy refill, a timer speed-up, a streak repair); none computes the figure itself. The rule is a design choice of `billing.virtual-currency` (README, "Real-money value", INV-16 and INV-24); its basis is the EU consumer-protection network's principle quoted in `14-rewards-resources-and-items.md` rule 4 (HIGH for the text, a non-binding document).

Other copy rules for every screen: the cost stated before the tap; the decline button as visible as the accept button; no pre-checked consent; no scarcity that is not real. Apple's conduct rule says apps should never "trick them into making unwanted purchases" ([guideline 5.6](https://developer.apple.com/app-store/review/guidelines/), HIGH), and Google's Families policy bars emotionally manipulative tactics to drive ad views or purchases (P10).

## Accessibility and localization floor

| Item | Floor | Source and label |
|---|---|---|
| Text size | Players can enlarge text to at least 200 percent without loss | [HIG accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [WCAG 1.4.4](https://www.w3.org/TR/WCAG22/): HIGH |
| Contrast | 4.5:1 for text, 3:1 for large text and UI components; test text over the busiest background | [WCAG 1.4.3 and 1.4.11](https://www.w3.org/TR/WCAG22/), [Android](https://developer.android.com/guide/topics/ui/accessibility/apps): HIGH |
| Colour | Rarity, state and team never rely on colour alone: add shape, icon or text | [WCAG 1.4.1](https://www.w3.org/TR/WCAG22/), [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/basic/): HIGH |
| Touch targets | At least 44 by 44 points on iOS ([HIG buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)), 48 by 48 dp on Android; one kit rule of 48 by 48 meets both. About 12 points of space around bezeled controls | HIGH; WCAG 2.5.8 sets a 24 by 24 CSS pixel minimum |
| Gestures | Every gesture has a visible control as an alternative | [HIG accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility): HIGH |
| Audio and haptics | Separate volume for music, effects and speech; a haptics toggle; no essential information by sound alone | [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/basic/): HIGH |
| Motion | Honour the system reduce-motion setting; avoid flicker | [HIG accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/basic/): HIGH |
| Screen reader | Every interactive element has a label | [HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Android](https://developer.android.com/guide/topics/ui/accessibility/principles): HIGH |
| Right to left | Mirror navigation and progress controls; never reverse the digits inside a number | [HIG right to left](https://developer.apple.com/design/human-interface-guidelines/right-to-left): HIGH |
| Long strings | No fixed-width labels; never truncate a price, an odds line or legal text; test short labels at three times the English length (IBM figures: 200 to 300% for strings up to ten characters) | [W3C](https://www.w3.org/International/articles/article-text-size): MEDIUM, dated |
| Layout | Menus adapt to aspect ratios and safe areas; settings persist; the game starts without nested menus | [HIG games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games), [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/basic/): HIGH |

## Default path

1. Answer the ten interview questions and mark every inventory row on, off or deferred, writing the deciding answer beside it.
2. Add the platform rows (P1 to P18) that apply and the screen or state each one adds.
3. Pick the navigation model for the archetype and fill the home zone sheet from the entries table; count the attention marks.
4. Sort every popup, toast, banner and sheet into the four surface kinds; write the queue as a table with priority, cap, cooldown and first-win rule for the one popup slot; one scheduler owns it.
5. Write the six states and their copy for every screen on the list, before building; wire the block frontends for the economy, live and social rows.
6. Fire one view event and one action event per screen with the envelope in `12-live-ops-and-instrumentation.md`.
7. Test at 200 percent text, in grayscale, with a screen reader, with reduced motion and with expanded strings.
8. Recheck the platform pages the month before submission.

## Gaps

- No source measures a home-screen layout, a maximum of attention marks, hub-and-spoke against a tab bar, or a popup cap or order. The numbers here are kit recommendations to test in a soft launch.
- No study ties one-handed reach to game retention; the only grip data is from 2013. Landscape games are not covered.
- No primary source gives an interstitial frequency cap (guide research notes); Apple's tab bar page states no maximum number of tabs.
- Whether the EEA consent message must precede analytics start-up in the first session is a legal question no source here settles; tracking-prompt timing trades against install attribution (`05-marketing-and-launch.md`).
- Age assurance moves fast: Google's page names only Texas; other states, other countries and the UK Children's Code were not researched.
- The blocks leave the Home placement of the event banner, queue entry and subscription banners to the host, and no block specifies an inbox; the entries table and the inbox row are kit recommendations (LOW).
- Web-shop link-out rules (interview 10), Apple's Schedule 2 subscription terms, forced-update screens on iOS, inbox and mail screens, language pickers and platform game services (Game Center, Play Games) were not researched.
- Material Design 3 pages were script-rendered and not read; Android Developers pages stand in. Apple's HIG pages were read through Apple's own documentation data.

## Checklist

- [ ] The ten interview answers are written down and every inventory row is marked on, off or deferred with its deciding answer.
- [ ] The always-on screens exist: launch, loading, tutorial, home, play, pause, results, settings, privacy link, support contact, offline state.
- [ ] Interview 1: the home zone sheet matches the archetype and the attention marks are counted; the map, prestige and offline summary, hero detail or base view exists as the archetype needs.
- [ ] Interview 2 with ads: rewarded-ad offer, ad frame with close and report controls, consent message for the EEA, UK and Switzerland, a tracking decision, no ad before the first win.
- [ ] Interview 2 with purchases: shop with the store's price string on every pack, the shared real-money figure beside every purchasable-currency price (hidden for soft currencies and when the reference price is not loaded), purchase confirmation, purchase status and receipt, insufficient-funds sheet, refund notice, restore in Settings, no expiry on purchased currency, and a spend-limit screen where the team ships limits.
- [ ] Interview 2 with a one-time unlock: the paywall exists. With a subscription: the paywall carries the full disclosure, Settings has the status and manage entry, the state banners and the trial-ending banner exist. With a pass: the track, the premium sheet and the season results exist.
- [ ] Interview 3 with paid random rewards: odds before the price, a pity counter, age screen, rating answers that match.
- [ ] Interview 4 with children: parental gate, neutral age screen, ads and analytics that follow the kids rules, no link out outside the gate.
- [ ] Interview 5 yes: guest start, the save-your-progress prompt, the link flow with its conflict sheet, a recovery code, the guest welcome-back screens, the pending-identity chip, an equivalent login service, in-app account deletion with a web link.
- [ ] Interview 6: friends and leaderboard, or clan and chat with report, block and published contact.
- [ ] Interview 7: daily reward popup, calendar and streak loss sheet; event hub with an empty state, the Home banner, detail and results; the objectives board and reroll sheet; pass track if seasonal; all matching the team's calendar.
- [ ] Timers, energy and items: the queue panel, start sheet, speed-up sheet and idle-slot nudge exist where timers run; the energy HUD, empty-energy sheet and refill confirmation exist where a gate runs; the inventory, item detail, upgrade, equip, inventory-full and duplicate sheets exist where items do.
- [ ] Push is used: the priming sheet, notification settings and denied-state hint exist, and the comeback reward sheet where comeback grants are on.
- [ ] Interview 8: consent where required, languages listed, right to left tested if Arabic or Hebrew ships, age rules per market.
- [ ] The popup queue table exists with the four surface kinds sorted; no popup stack at launch; every prompt has a cap and a first-win rule.
- [ ] Every screen has the six states with written copy; decline is as visible as accept.
- [ ] The accessibility floor passed the tests in the default path.
- [ ] Platform pages were rechecked within the month before submission.
