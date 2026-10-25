---
id: "game-engagement"
name: "Game Engagement: hooks, economy and launch for a mobile game"
version: "1.0.0"
tags: [mobile, game, retention, live-ops, monetization, user-acquisition, compliance]
complexity: medium
estimated_effort: "design decisions in one sitting; build effort depends on the features chosen"
blocks:
  - id: "billing.in-app-purchase"
    phase: "economy"
    when: "interview 2 puts a one-time unlock in the game"
  - id: "auth.google-login"
    phase: "identity"
    when: "interview 5 or 6 needs accounts and the project has no login yet"
  - id: "data.progress-sync"
    phase: "progress"
    when: "interview 5 says progress follows the player across devices"
  - id: "ugc.friends-leaderboard"
    phase: "social"
    when: "interview 6 chooses friends or a leaderboard"
  - id: "compliance.account-deletion"
    phase: "compliance"
    when: "players have accounts"
guides:
  - 01-first-session.md
  - 02-return-reasons.md
  - 03-economy-and-offers.md
  - 04-social-and-competition.md
  - 05-marketing-and-launch.md
  - 06-design-ethics-and-compliance.md
---

# Game Engagement

How a mobile game earns a second session, a second week and a paying minority, and how it finds players in the first place. The kit turns the recurring patterns of top mobile games (daily rewards, events, passes, timers, collections, clans, offers) into decisions: which ones the game needs, which belong to one genre, and what each costs.

## Evidence

Every figure in the guides comes from a public source named next to it, with a confidence label: HIGH (stated directly and consistent across sources), MEDIUM (one reasonable source, a vendor with a stated basis, or a secondary summary), LOW (vendor blog, old source, community estimate, or untraceable). None is a guarantee, and none was measured on the reader's game. Set your own targets from your own cohorts. Three gaps shape the kit:

- No source gives a causal size for a single hook (daily login, streak, energy, pass).
- No source gives a trustworthy retention gain for guild or friend features.
- No free source gives a current payer-conversion or revenue-per-daily-user benchmark.

Where a guide has to choose anyway, it says "kit recommendation" and gives the reasoning. Regulation is dated 2026-10-22 and moves quickly; recheck it before launch.

## Day-0 interview

Ask all ten in one sitting. Each is a pick-one question with a named default. A question the owner leaves unanswered takes its default and is recorded as an assumption.

1. **Which genre archetype is the game closest to?**
   Default: the nearest of the four archetypes below; do not mix archetypes at launch.
   Options: casual puzzle or hybrid-casual · idle or incremental · character-collector RPG · 4X or survival strategy.
   Why it is expensive to reverse: the archetype decides which return mechanics and which monetization model fit (guides 02 and 03).

2. **How does the game earn?**
   Default: follow the genre: ads for hyper-casual, ads plus a small set of purchases for hybrid-casual, purchases for strategy and RPG.
   Options: ads only · ads and purchases · purchases only · one-time unlock.
   Why it is expensive to reverse: the economy, the pacing of rewards and the ad placements are built around it.

3. **Does any paid reward come out at random?**
   Default: no paid random rewards.
   Options: none · random drops earned by play only · paid random rewards with disclosed odds and a pity counter.
   Why it is expensive to reverse: odds disclosure, minors rules and store policy attach to it, and regulators act on it (guide 06).

4. **Who may play?**
   Default: not directed at children; an age gate wherever a paid random reward or open chat exists.
   Options: general audience · includes children.
   Why it is expensive to reverse: child-directed status changes the ad, data and monetization rules in every market.

5. **Does progress follow the player across devices?**
   Default: no; progress stays on the device.
   Options: no · yes (needs accounts and a backend).
   Why it is expensive to reverse: it adds accounts, a backend and a merge rule to every stored record.

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

## Chapters

1. `guides/01-first-session.md`: the core loop, the first minutes and the first asks.
2. `guides/02-return-reasons.md`: daily, weekly and seasonal reasons to return, and which are must-have.
3. `guides/03-economy-and-offers.md`: earning models, currencies, offers, ads and web shops.
4. `guides/04-social-and-competition.md`: what social features do and cost.
5. `guides/05-marketing-and-launch.md`: the funnel, concept test, soft launch, creatives and privacy.
6. `guides/06-design-ethics-and-compliance.md`: the psychology behind the hooks and the compliance floor.

## What no block covers yet

The blocks above cover login, a one-time unlock, progress sync, a friends board and account deletion. No block covers consumable currency packs, subscriptions, a battle pass, daily rewards and streaks, an event calendar, energy and lives, or push re-engagement. The guides say what each should do; implementing them is a separate block each.

## Checklist

- [ ] The ten interview answers are written into the project contract.
- [ ] The first session is scripted and instrumented step by step (guide 01).
- [ ] At least one reason to return tomorrow exists; the live layers match the team's calendar (guide 02).
- [ ] The earning model matches the genre; currencies have named faucets and sinks (guide 03).
- [ ] Social scope matches the player base; moderation is planned before chat (guide 04).
- [ ] A concept test and soft-launch gates are written down before spend (guide 05).
- [ ] Odds, real-money prices and age handling meet the floor in guide 06.
