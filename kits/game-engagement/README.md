---
id: "game-engagement"
name: "Game Engagement: hook, rhythm, features and launch for a mobile game"
version: "2.0.0"
tags: [mobile, game, retention, live-ops, monetization, user-acquisition, compliance, objectives, economy, screens]
complexity: high
estimated_effort: "design decisions in one sitting; build effort depends on the features chosen"
blocks:
  - id: "auth.guest-account"
    phase: "identity"
    when: "interview 5 puts progress, rewards or purchases on a server, so every player needs an account_id from the first launch"
  - id: "auth.google-login"
    phase: "identity"
    when: "interview 5 or 6 needs a sign-in and the project has no login yet"
  - id: "auth.sign-in-with-apple"
    phase: "identity"
    when: "the game offers a social login on iOS"
  - id: "data.progress-sync"
    phase: "progress"
    when: "interview 5 says progress follows the player across devices"
  - id: "billing.virtual-currency"
    phase: "economy"
    when: "interview 2 sells currency packs, or any feature gives or takes a currency or a stackable item"
  - id: "billing.in-app-purchase"
    phase: "economy"
    when: "interview 2 puts a one-time unlock in the game"
  - id: "billing.subscriptions"
    phase: "economy"
    when: "interview 2 adds a subscription or a VIP membership"
  - id: "engagement.items"
    phase: "economy"
    when: "interview 15 chooses items with levels, duplicates or expiry"
  - id: "engagement.objectives"
    phase: "objectives"
    when: "interview 13 chooses daily, weekly or lifetime objectives"
  - id: "engagement.daily-streak"
    phase: "live"
    when: "interview 7 includes a daily layer"
  - id: "engagement.event-calendar"
    phase: "live"
    when: "interview 7 includes a weekly or seasonal layer"
  - id: "engagement.season-pass"
    phase: "live"
    when: "interview 7 includes a seasonal layer and interview 2 includes purchases"
  - id: "engagement.energy-lives"
    phase: "live"
    when: "interview 14 chooses a regenerating meter"
  - id: "engagement.timed-queues"
    phase: "live"
    when: "interview 14 chooses timed queues"
  - id: "messaging.push-reengagement"
    phase: "messaging"
    when: "the game wants timer reminders or a comeback ladder for players who left"
  - id: "ugc.friends-leaderboard"
    phase: "social"
    when: "interview 6 chooses friends or a leaderboard"
  - id: "compliance.account-deletion"
    phase: "compliance"
    when: "players have accounts, guest or signed-in"
guides:
  - 01-first-session.md
  - 02-return-reasons.md
  - 03-economy-and-offers.md
  - 04-social-and-competition.md
  - 05-marketing-and-launch.md
  - 06-design-ethics-and-compliance.md
  - 07-hook-and-rhythm.md
  - 08-objectives-and-progression.md
  - 09-keeping-players.md
  - 10-screens-and-navigation.md
  - 11-feature-specs.md
  - 12-live-ops-and-instrumentation.md
  - 13-missions-and-activities.md
  - 14-rewards-resources-and-items.md
  - 15-manipulation-and-the-line.md
---

# Game Engagement

How a mobile game hooks a player, sets its rhythm, gives the player something to do and a reason to stay, and then earns from a paying minority and finds players in the first place. The kit turns the recurring patterns of top mobile games (daily rewards, events, passes, timers, collections, clans, offers) into decisions: which ones the game needs, which belong to one genre, what each costs, which screens and features carry it, and where persuasion becomes manipulation.

## Evidence

Every figure in the guides comes from a public source named next to it, with a confidence label: HIGH (stated directly and consistent across sources), MEDIUM (one reasonable source, a vendor with a stated basis, or a secondary summary), LOW (vendor blog, old source, community estimate, or untraceable). None is a guarantee, and none was measured on the reader's game. Set your own targets from your own cohorts. Three gaps shape the kit:

- No source gives a causal size for a single hook (daily login, streak, energy, pass).
- No source gives a trustworthy retention gain for guild or friend features.
- No free source gives a current payer-conversion or revenue-per-daily-user benchmark.

Where a guide has to choose anyway, it says "kit recommendation" and gives the reasoning. Regulation and store policy move quickly: each guide dates what it read (the latest read is 2026-10-27), so recheck both before launch.

The blocks are specified from public platform documentation and published industry practice. No block has run on a real stack; each block's "Origin and verification status" section separates documented fact, design choice and extrapolation, and its acceptance checklist is a mental three-stack test.

## Day-0 interview

Ask all fifteen in one sitting. Each is a pick-one question with a named default. A question the owner leaves unanswered takes its default and is recorded as an assumption.

1. **Which genre archetype is the game closest to?**
   Default: the nearest of the four archetypes below; do not mix archetypes at launch.
   Options: casual puzzle or hybrid-casual · idle or incremental · character-collector RPG · 4X or survival strategy.
   Why it is expensive to reverse: the archetype decides which return mechanics and which monetization model fit (guides 02, 03 and 07).

2. **How does the game earn?**
   Default: follow the genre: ads for hyper-casual, ads plus a small set of purchases for hybrid-casual, purchases for strategy and RPG.
   Options: ads only · ads and purchases · purchases only · one-time unlock · subscription (alone or with purchases).
   Why it is expensive to reverse: the economy, the pacing of rewards and the ad placements are built around it.

3. **Does any paid reward come out at random?**
   Default: no paid random rewards.
   Options: none · random drops earned by play only · paid random rewards with disclosed odds and a pity counter.
   Why it is expensive to reverse: odds disclosure, minors rules and store policy attach to it, and regulators act on it (guides 06 and 15).

4. **Who may play?**
   Default: not directed at children; an age gate wherever a paid random reward or open chat exists.
   Options: general audience · includes children.
   Why it is expensive to reverse: child-directed status changes the ad, data and monetization rules in every market.

5. **Does progress follow the player across devices, and do rewards live on a server?**
   Default: no; progress stays on the device.
   Options: no · yes through a silent guest account that links to a sign-in later · yes with a sign-in before play.
   Why it is expensive to reverse: it adds accounts, a backend and a merge rule to every stored record, and every server-paid reward depends on it.

6. **How social is the game at launch?**
   Default: none at launch; add asynchronous features (shared goals, cohort boards) before clans or chat.
   Options: none · asynchronous · friends and leaderboard · clans with chat.
   Why it is expensive to reverse: social features add public data, moderation and the cold-start problem.

7. **Who ships live content, and how often?**
   Default: a daily layer at launch; a weekly layer after the soft launch; a seasonal layer only once a team can ship to a calendar.
   Options: daily only · daily and weekly · daily, weekly and seasonal.
   Why it is expensive to reverse: a calendar the team cannot keep trains players to expect events that stop.

8. **Which markets for the soft launch and the launch?**
   Default: one or two cheaper markets for the soft launch, the main markets after the gates pass.
   Options: owner names the markets · defaults.
   Why it is expensive to reverse: retention and spend differ by market, and a gate measured in the wrong market misleads.

9. **Does an ad concept get tested before the game is built?**
   Default: yes; a concept test runs before full production.
   Options: concept test first · build first · organic only.
   Why it is expensive to reverse: a game built for a concept that does not convert is the most expensive way to find out.

10. **Does the game sell on its own web shop?**
    Default: not at launch; revisit once there are paying players in a purchase-led genre.
    Options: no · later · at launch.
    Why it is expensive to reverse: it changes the payment stack, the support load and the platform-rule exposure.

11. **What is the game's long-term hook?**
    Default: the long-term hook that the guide 07 archetype table gives for the answer to question 1, written as one sentence at three ranges (the opening promise, the pull into the next round, the reason to be here in a month).
    Options: collection · mastery or prestige · status · story · community.
    Why it is expensive to reverse: the hook decides what the live layers carry, what the objectives reward and which blocks matter.

12. **What is the shape of one session and of the first week?**
    Default: the session shape and first-week script that guide 07 gives for the archetype.
    Options: short bursts, many a day · mid-length sessions · long sessions with waiting in between.
    Why it is expensive to reverse: it sets the energy and timer values, the event cadence and the push timing.

13. **How are objectives layered?**
    Default: starter goals plus a daily board at launch; weekly and lifetime objectives after the soft launch.
    Options: starter goals only · starter goals and a daily board · starter, daily, weekly and lifetime.
    Why it is expensive to reverse: it fixes the authoring load, the reward budget and the shape of the home screen (guides 08 and 13).

14. **What keeps a player occupied between sessions?**
    Default: one mechanism, not two: the one the archetype leans on, a regenerating meter or timed queues.
    Options: nothing, play drives everything · a regenerating meter (energy or lives) · timed queues with slots · both.
    Why it is expensive to reverse: it sets the pacing, the pressure to buy and the notification volume (guides 02, 13 and 15).

15. **What can a player own?**
    Default: counts only: currencies and stackable items.
    Options: counts only · items with levels, duplicates or expiry · a collection with duplicate conversion.
    Why it is expensive to reverse: items with their own state need an inventory, an upgrade rule and odds disclosure when random (guides 14 and 15).

## Chapters

1. `guides/01-first-session.md`: the core loop, the first minutes and the first asks.
2. `guides/02-return-reasons.md`: daily, weekly and seasonal reasons to return, and which are must-have.
3. `guides/03-economy-and-offers.md`: earning models, currencies, offers, ads and web shops.
4. `guides/04-social-and-competition.md`: what social features do and cost.
5. `guides/05-marketing-and-launch.md`: the funnel, concept test, soft launch, creatives and privacy.
6. `guides/06-design-ethics-and-compliance.md`: the psychology behind the hooks and the compliance floor.
7. `guides/07-hook-and-rhythm.md`: the hook at three ranges and the rhythm of a session and the first week.
8. `guides/08-objectives-and-progression.md`: the objective ladder from the first minute to lifetime goals, and progression curves.
9. `guides/09-keeping-players.md`: what keeps a player in, the churn signals and the comeback of a player who left.
10. `guides/10-screens-and-navigation.md`: the screen inventory, navigation, the popup budget and the store rules that dictate screens.
11. `guides/11-feature-specs.md`: one behaviour spec per feature, the selection matrix by archetype and the build order.
12. `guides/12-live-ops-and-instrumentation.md`: the event envelope, metrics, remote config, experiments, live-ops process and the engineering floor.
13. `guides/13-missions-and-activities.md`: the content of missions and activities, their number and time budget, and where busy-ness stops being engagement.
14. `guides/14-rewards-resources-and-items.md`: the taxonomy of currencies, resources and items, small rewards and faucet and sink balance.
15. `guides/15-manipulation-and-the-line.md`: the catalog of manipulation techniques, their evidence and legal status, and the pre-ship audit.

## Blocks

The frontmatter lists the blocks and the interview answer that calls for each. The blocks added with guides 07 to 15 assume a backend: they key data by `account_id` (issued by `auth.guest-account` or a login block), use the server clock for every timer and window, and pay every reward through the ledger of `billing.virtual-currency`. A game that keeps everything on the device (interview 5 answered no), sells nothing and ships no live content uses the guides and none of these blocks.

No block covers the following; guide 11 lists each as "no block yet" and says what it should do: tutorial and first win, core loop and level progression, starter offers (they use the purchase contract of `billing.virtual-currency`), rewarded ads, collections and albums, clans and chat, gacha and loot boxes, settings, rating prompt, support, referral and invite, force update and maintenance. Remote config, experiments and the analytics pipeline are described in guide 12 and have no block either.

## Checklist

- [ ] The fifteen interview answers are written into the project contract.
- [ ] The first session is scripted and instrumented step by step (guide 01).
- [ ] At least one reason to return tomorrow exists; the live layers match the team's calendar (guide 02).
- [ ] The earning model matches the genre; currencies have named faucets and sinks (guides 03 and 14).
- [ ] Social scope matches the player base; moderation is planned before chat (guide 04).
- [ ] A concept test and soft-launch gates are written down before spend (guide 05).
- [ ] Odds, real-money prices and age handling meet the floor in guide 06.
- [ ] The hook is one sentence at three ranges, and one session and the first week have a written beat sheet (guide 07).
- [ ] The objective ladder is filled from the starter goals to the lifetime goals (guide 08), and the mission board passes the deepen-or-occupy review (guide 13).
- [ ] Churn signals are observable and a returning player has a welcome-back flow (guide 09).
- [ ] Every screen the interview answers call for exists, with its loading, empty, error and offline states (guide 10).
- [ ] The feature list is chosen from the selection matrix and built in the order given (guide 11).
- [ ] The event envelope, the core metrics and the economy dashboards exist before the soft launch (guide 12).
- [ ] The currency and item list names each source, sink, cap and expiry (guide 14).
- [ ] Every feature has passed the pre-ship manipulation audit, and every amber item has two signers recorded (guide 15).
