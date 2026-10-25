# Catalog of recurring retention and engagement mechanics in mobile games

Research date: 2026-10-22. Scope: global. Confidence labels: HIGH = read on the page by the researcher and the source is primary or a reputable analyst; MEDIUM = read on the page but vendor/blog/secondary or one source only; LOW = only seen in a search-result summary, community-derived, or single unverified source. All fetched pages were summarised by the fetch tool, so exact numbers should be re-checked against the source before publication. Several sources (pocketgamer.biz, the Game Developer "Deconstructing Clash Royale" article, rpgsite in one pass) returned HTTP 403 on some attempts and were not read in full.

## 1. Daily login rewards and streaks, daily/weekly quests, daily deals, free chests and timers

### Takeaway
Daily login rewards are the single most common retention device found in the only quantitative prevalence study located (38 of the top 40 Korean mobile games, 2025). Modern top casual games have shifted from passive login bonuses toward "play to claim" daily events (Royal Match "Lava Quest") and toward streak mechanics with loss-aversion framing (Duolingo is the best-documented streak case, although it is not a game).

### Cited Findings

**Daily login (what / how / behavior / metric)**
- What and how: a calendar or counter that grants a reward for opening the game each day, usually escalating with consecutive days; some designs reset on a missed day, others (for example 30-day calendars) do not reset, and some let players "recover" a missed day by watching a rewarded ad. — [Search summary of Beamable and others, 2025](https://beamable.com/blog/inspiring-examples-of-daily-login-rewards-for-your-mobile-game); [arXiv 2504.10714 abstract page](https://arxiv.org/abs/2504.10714). Confidence: LOW (search summary of vendor blogs; no page read in full).
- Prevalence: Daily Login appeared in 38 of the 40 most popular mobile games in South Korea (95%); the authors classify it as a retention strategy based on future loss aversion. Paper submitted April 14, 2025; method is direct gameplay observation and video analysis of the top 40 Korean games. — [arXiv 2504.10714 HTML](https://arxiv.org/html/2504.10714) (counts from Table 1; percentages computed by the fetch tool). Confidence: MEDIUM (preprint, single country, single snapshot).
- Behavior targeted: build a daily-open habit; metric targeted: D1/D7/D30 retention and DAU/MAU. The "up to 30% increase in daily engagement" figure circulating in blogs has no named underlying study. — [Search summary of thefestivals.uk and others](https://thefestivals.uk/?p=42821). Confidence: LOW, treat as unverified.
- Risk: pure login rewards reward opening the app, not playing; Naavik says top puzzle games replaced simple daily login bonuses with an in-game "daily jackpot" that requires winning core gameplay. — [Naavik, Nov 16, 2025](https://naavik.co/digest/live-ops-trends-powering-mobile-puzzle/). Confidence: HIGH.

**Streaks (Duolingo as the best-documented case; not a game but widely copied by games)**
- A streak counts consecutive days with at least one completed lesson. Duolingo separated the daily goal from the streak in an A/B test: +3.3% relative Day-14 retention, +1% daily active learners, +10.5% in the share of daily learners on a streak within 20 days (Nov 19, 2020). — [Duolingo blog, Nov 19, 2020](https://blog.duolingo.com/improving-the-streak). Confidence: HIGH (company primary source, though 2020).
- Duolingo reported learners with a 7-day streak were 2.4 times more likely to return the next day than those without one; the same post reports just over half of daily learners had a 7+ day streak a year after the change, up from about a third. — [Duolingo blog, Nov 19, 2020](https://blog.duolingo.com/improving-the-streak). Confidence: HIGH for the claim as reported; the 2.4x figure is correlational, not causal.
- Duolingo's retention team found users who reached a 10-day streak were less likely to drop off, a correlation affected by selection bias, and the first big win was a streak-saver notification (warning before the streak is lost); later additions were calendar views, streak freezes, streak rewards. Q2 2026 results cited as 58.7M DAU and an 84% current-user retention rate. — [Search summary citing Duolingo blog and Pulse 2.0, Aug 2026](https://pulse2.com/duolingo-daily-active-users-reach-58-7-million-as-retention-hits-record-84-and-social-accounts-top-1-billion-organic-impressions/). Confidence: LOW (search summary only; earnings figures not checked against a filing). Note: the fetched 2020 Duolingo post itself did not mention freeze, streak saver or calendar.

**Daily/weekly quests and recurring events**
- Sensor Tower (March 2026) groups "recurring events" as daily missions, check-ins, standard promotions, win-streak mechanics and milestone progression; these "sustain daily engagement and prepare players for mid-term and large-scale events." It gives no login statistics. — [Sensor Tower live ops report, March 2026](https://sensortower.com/blog/top-grossing-mobile-games-live-ops-strategies-2025-report). Confidence: HIGH (analyst, read on page).
- Royal Match daily-pressure events: "Lava Quest" is a win-streak event requiring seven levels in a row or the player loses progress; "Jungle Treasure" is a rolling offer. — [Sensor Tower, May 2026](https://sensortower.com/blog/what-royal-matchs-calendar-teaches-about-live-ops-in-2026). Confidence: HIGH.
- Naavik: the "daily jackpot" (Royal Match Lava Quest) rewards consistent daily logins with a large prize, is typically solvable in the first session of the day, is usually unlocked within a player's first week, and its main design challenge is pacing the prize pool so the economy stays stable. — [Naavik, Nov 16, 2025](https://naavik.co/digest/live-ops-trends-powering-mobile-puzzle/). Confidence: HIGH.

**Daily deals, rolling offers**
- Sensor Tower defines "rolling offers" as linked bundles claimed in sequence, often starting with a free entry to lower the barrier to a first purchase. — [Sensor Tower, March 2026](https://sensortower.com/blog/top-grossing-mobile-games-live-ops-strategies-2025-report). Confidence: HIGH. (Pricing/offer design is out of scope; only the mechanic is noted.)

**Free chests and timers (Clash Royale)**
- Winning a battle awards a chest; chests take 3, 8 or 12 hours to unlock (per a secondary analysis), one opens at a time, four storage slots. — [Search summary, Game Developer "Deconstructing Clash Royale" and others](https://www.gamedeveloper.com/business/deconstructing-clash-royale). Confidence: LOW (page returned 403; figures from search summary).
- Supercell confirms the "chest slot system has existed since the game's release" and, on 15 Jan 2025, tested for King Tower Levels 1 to 9 a variant removing Golden/Magical/Giant chests and adding Wooden (instant) and Crown (24-hour) chests with total reward value held constant. — [Supercell news post, 15 Jan 2025](https://supercell.com/en/games/clashroyale/blog/news/chest-experiment-king-tower-levels-1-9). Confidence: HIGH.

### Inferences
- Daily login is table-stakes infrastructure; the differentiator in 2025-26 is tying the daily reward to actually playing (daily jackpot) rather than just opening the app.
- Streak and daily reward mechanics all target the same metric ladder: D1, D7, D30 retention and DAU/MAU stickiness, with the loss-aversion lever (missing a day forfeits accrued progress).
- Timer-gated free chests double as a pacing device and an "appointment" (come back when it's ready) and as a monetization hook (speed-up with gems).

### Gaps
- No independent, quantified retention lift for login rewards in games (only unsourced blog claims). A GDC Vault or Naavik study with cohort data was not located.
- Only Duolingo has a primary-source streak experiment, and it is an education app, not a game; no game company publishes equivalent A/B results found here.
- The arXiv paper's text and its Table 1 disagree on some counts (see section 7); the 2504.10714 abstract page reports no prevalence figures, they come only from the HTML version.

## 2. Energy / stamina / lives / wait timers and appointment mechanics

### Takeaway
Energy and wait timers are the oldest free-to-play pacing tool: a hard gate (Candy Crush lives) or a soft gate (Clash Royale chest slots, Clash of Clans build timers) that limits session volume, creates a reason to return, and sells "skip the wait." Evidence on revenue share is anecdotal, and designers openly criticise energy as a weak purchase and a poor fit with game settings.

### Cited Findings
- Four stated purposes of energy systems: habituation, content pacing, monetization, strategic choices; they also narrow the gap between highly engaged and less engaged users by capping the fastest players. One source estimates that in casual games energy might typically be about a third of bookings, and argues energy is a weak purchase because players could simply wait. — [Search summary of PocketGamer.biz/mobilefreetoplay.com, undated](https://www.pocketgamer.biz/is-there-any-place-in-the-f2p-designers-toolbox-for-energy-based-systems). Confidence: LOW (page returned 403, the mobilefreetoplay page fetched did not contain the content; "a third of bookings" is an unsourced estimate).
- "Hard" systems such as Candy Crush Saga lives versus "soft" systems such as Clash Royale, which allow unlimited play but restrict rewards; Clash of Clans uses timers on building upgrades and troop training instead of a stamina bar; most limiters can be bypassed with money, which is a fairness problem in PvP games. — [Search summary of mobilefreetoplay.com and a University of Turku thesis](https://mobilefreetoplay.com/eliminating-energy/). Confidence: LOW to MEDIUM (blog/thesis seen via summary).
- Candy Crush Saga lives: per a fan wiki, one life is regenerated every 30 minutes up to a cap of five; a failed level costs a life. — [Candy Crush Wiki, Lives](https://candycrush.fandom.com/wiki/Lives). Confidence: MEDIUM (community wiki; page not read in full, figures from search summary).
- Royal Match's "Team Gift Offer" (last three days of Train Journey and Culinary Collection) gives coins, boosters and unlimited lives to all team members, which shows lives are used as a reward currency as well as a gate. — [Sensor Tower, May 2026](https://sensortower.com/blog/what-royal-matchs-calendar-teaches-about-live-ops-in-2026). Confidence: HIGH.
- Time-gated progression appeared in 9 of the top 40 Korean games per the paper's Table 1 (22.5%), 10 (25%) per the paper's text. — [arXiv 2504.10714 HTML](https://arxiv.org/html/2504.10714). Confidence: MEDIUM (internal inconsistency; Korean RPG/strategy-heavy sample, so genre skew likely).
- Criticism: energy systems rarely fit a game's setting, and one designer suggests limiting reward rate and leaving play unlimited. — [Search summary of mobilefreetoplay.com](https://mobilefreetoplay.com/eliminating-energy/). Confidence: LOW.

**Appointment mechanics (what they are)**
- A search-result summary lists GameAnalytics' "appointment mechanics: how to keep your players in game," but the fetched page (last updated Sep 03, 2026) did not discuss appointment mechanics (it covered core loops), so no appointment-mechanics definition from that source can be cited. — [GameAnalytics page](https://www.gameanalytics.com/blog/appointment-mechanics-how-to-keep-your-players-in-game). Confidence: LOW.
- Working definition from the examples above: any mechanic that makes the game ready at a time chosen by the designer (timer completion, daily reset, event start) so that the player schedules a return. Chests, build timers, lives refill, daily jackpot and weekend events all fit. This definition is an inference, not a cited definition.

### Inferences
- Wait timers target session frequency (return visits), not session length; the metrics are sessions per day, D1/D7 retention, and soft-currency/premium-currency sink conversion.
- The trend in the 2025-26 puzzle sources is to soften hard gates: Royal Match hands out unlimited lives as an event reward, and Clash Royale tested instant and 24-hour chests (inference from the two cited items, MEDIUM).

### Gaps
- No verified revenue share for energy/lives; the "a third of bookings" figure is unsourced.
- No primary or GDC-style source on appointment mechanics was read. Candy Crush's current (2026) lives rules were not checked on a first-party page.
- No data on how many top games dropped hard energy gates and what happened to retention.

## 3. Progression: levels, XP, unlocks, skill trees, collections, achievements, mastery, prestige/reset loops

### Takeaway
The best-sourced items here are prestige (idle games) and the 2025 shift to endless collections/albums in casual puzzle. Generic levels/XP/unlocks/skill-tree/achievement claims returned only low-quality content-farm pages, so those are mostly gaps.

### Cited Findings

**Prestige / reset loops (idle games)**
- Prestige lets a player voluntarily reset progress in exchange for a permanent multiplier or prestige currency that speeds later runs; popularised and possibly invented by Cookie Clicker. Two stated design purposes: (1) a "ladder climbing" feeling of power from resetting with a big boost, and (2) controlling growth by bringing numbers back to a manageable scale so designers can set stable targets. — [Anthony Pecorella, "The Math of Idle Games, Part III," Game Developer, Feb 1, 2017](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii). Confidence: HIGH (read on the page; 2017, but design principle still standard).
- Prestige formulas differ by game: AdVenture Capitalist is based on lifetime earnings (square root), Realm Grinder on max earnings, Cookie Clicker on lifetime earnings (cube root), Egg, Inc. on earnings since last reset; lifetime-based systems give diminishing returns for resetting at the same point. — same source. Confidence: HIGH.

**Collections and endless albums**
- Naavik (Nov 16, 2025): two-month seasonal collections became infinitely repeatable ("endless album" systems echoing Monopoly Go!), removing the finite content ceiling that caused boom-and-bust engagement cycles; Royal Match offset the extra perpetual reward source with a roughly 30% cut in coin rewards from level completions; endless albums "have now become commonplace" in most top-grossing casual puzzle games. — [Naavik](https://naavik.co/digest/live-ops-trends-powering-mobile-puzzle/). Confidence: HIGH.
- Sensor Tower (March 2026): collection systems (cards or albums) unlock high-value rewards on set completion and can drive card-pack purchases and paid event participation. — [Sensor Tower](https://sensortower.com/blog/top-grossing-mobile-games-live-ops-strategies-2025-report). Confidence: HIGH.
- Royal Match runs "Culinary Collection" (two months) and "Merge Smith" (a secondary progression system) as long-term/mid-term systems on top of level progression. — [Sensor Tower, May 2026](https://sensortower.com/blog/what-royal-matchs-calendar-teaches-about-live-ops-in-2026). Confidence: HIGH.
- Collection Gacha appeared in 12 of the top 40 Korean games (30%). — [arXiv 2504.10714 HTML](https://arxiv.org/html/2504.10714). Confidence: MEDIUM.
- Monopoly Go: albums and cooperation events described as main retention tools; Sensor Tower data via PocketGamer.biz reports the "Backing Partners" event lifted revenue 34%, ARPDAU 26%, daily session time over 60% during the event. — [Search summary of PocketGamer.biz "Decoding the live ops strategy of Monopoly Go"](https://www.pocketgamer.biz/feature/82961/decoding-the-live-ops-strategy-of-monopoly-go/). Confidence: LOW (page not read; figures from summary). A claimed $200M/month "sticker pressure" figure comes from a single low-authority site and is not used here.

**Design principle behind casual-puzzle convergence**
- Naavik says convergence is driven by engagement-level appeal (works for casual and committed players), spending-potential appeal (depth for top spenders, fairness for non-spenders), and motivations served: achievement/completion drives retention, social/competition drives monetization. Cross-title D90-to-D1 relative retention is converging around 25% and minutes per day around 38 (iOS, US). — [Naavik, Nov 16, 2025](https://naavik.co/digest/live-ops-trends-powering-mobile-puzzle/). Confidence: HIGH (analyst data, iOS-US only).

### Inferences
- Collections and albums turn a one-off event into permanent completion pressure; the metric targeted is long-term retention and spending depth; the key economic risk named by Naavik is added reward inflow (hence Royal Match's coin cut).
- Prestige is a genre-specific mechanic (idle/incremental), not table stakes.

### Gaps
- No reliable source found for generic player-level/XP curves, unlock cadence, skill trees, achievements or mastery in mobile; search returned content-farm pages, which were excluded. GDC Vault talks and Deconstructor of Fun meta-progression posts should be searched directly.
- Subway Surfers, Genshin Impact (resin/abyss) and Candy Crush progression systems were not covered with primary sources.

## 4. Battle pass / season pass / events / LiveOps calendar / limited-time offers

### Takeaway
Live ops is organised in layers by cadence: daily recurring events, weekly/mid-term feature events (including passes), and multi-week/seasonal events with collections. Battle passes are now mainstream in grossing games across genres, with wide variance in revenue contribution.

### Cited Findings

**Cadence layers**
- Sensor Tower (March 2026) three layers: recurring events (daily missions, check-ins, win streaks, milestone systems), feature events (battle passes, mini-games, treasure hunts, gacha, bingo; the "rhythm layer"), large-scale events (seasonal events, PvP/PvE competitions, alliance championships, collection systems). Whiteout Survival launched nine interconnected Halloween events in late October 2025 and hit a three-month daily-revenue peak. — [Sensor Tower](https://sensortower.com/blog/top-grossing-mobile-games-live-ops-strategies-2025-report). Confidence: HIGH.
- Royal Match (May 2026): daily pressure (Lava Quest, Jungle Treasure), weekly rhythm (Weekly Contest, Archery Arena, Team Battle, Champion Clash, Friends Train Journey, Mission Pursuit), long-term (Culinary Collection two months, Easter Pass seasonal track); six standard tournament formats; revenue spikes on weekends and the article attributes this to event-driven conversion rather than higher DAU, downloads or time spent. In a 12-game benchmark set: 2.5 standard tournament formats per game, 9.4 sprint-time events per month per game, over 5,500 tournament instances tracked. — [Sensor Tower, May 2026](https://sensortower.com/blog/what-royal-matchs-calendar-teaches-about-live-ops-in-2026). Confidence: HIGH.
- Events in top F2P games grew 35% between May 2023 and January 2025 (GameRefinery data cited by Global Games Forum). — [Search summary of Global Games Forum](https://www.globalgamesforum.com/news/the-trends-shaping-the-world-of-liveops). Confidence: LOW (fetched page was an index without the stat).
- A PocketGamer.biz piece argues mobile gaming has shifted from a "core-first" to an "event-first" model, with a Rovio product lead saying live ops shift player focus from core difficulty to event-driven progression. — [PocketGamer.biz (search summary; page 403)](https://www.pocketgamer.biz/why-mobile-gaming-has-shifted-from-a-core-first-to-an-event-first-model/). Confidence: LOW.
- Calendar guidance (predictable or overloaded calendars cause fatigue; rhythm of return matters more than volume; 8-15 events per month for mid-core RPG/strategy) comes from vendor blogs. — [ThinkingData](https://thinkingdata.io/?p=3867). Confidence: LOW. The claim "weekly LiveOps gives 2.1x higher 30-day retention" (attributed to Adjust 2025 via Rocketship HQ) and "84% of IAP revenue flows through games with active LiveOps" (Playio) could not be traced to originals; do not use. — [Rocketship HQ](https://www.rocketshiphq.com/?p=5717). Confidence: LOW.

**Battle pass / season pass / event pass**
- Definition: a time-limited pass with free and premium tiers of tiered rewards, usually a month long, cheap, with some premium rewards visible to non-buyers to tempt purchase. Examples: Clash of Clans Gold Pass (~$4.99 for one month, with cheaper upgrades and faster healing for holders), Call of Duty: Mobile (free, ~$10 premium, ~$26 premium-plus), Legends of Runeterra event passes (~$10, roughly a month). Cautions: keep exclusives exclusive, avoid more than 3-4 tiers. — [GameAnalytics, last updated Feb 26, 2025](https://www.gameanalytics.com/blog/designing-battle-passes-in-mobile-games-the-whats-whys-and-hows). Confidence: MEDIUM (blog, prices as of article).
- Mechanism claims: frequent small rewards, commitment bias, FOMO from time-limited cosmetics, and the IKEA effect; event passes are shorter "mini-passes"; examples Brawl Stars and Helldivers 2. — [Games Alchemy (Antti Kananen), Feb 12, 2025](https://gamesalchemy.substack.com/p/29-the-evolution-of-battle-pass-event). Confidence: MEDIUM (practitioner Substack, no data).
- Prevalence: Battle Pass in 31 of 40 top Korean games (77.5%). — [arXiv 2504.10714 HTML](https://arxiv.org/html/2504.10714). Confidence: MEDIUM. GameRefinery data seen via search summary (older reports) put battle passes in roughly 60% of the top 20% grossing games, US top-100 adoption roughly doubling from 20% to 40% in a year, and Google Play data (2020) putting 1-40% of top-game revenue through passes. — [Search summaries via PocketGamer.biz and TheGamer](https://www.pocketgamer.biz/gamerefinery-battle-pass-implementation-in-top-grossing-mobile-games/). Confidence: LOW (pages 403; dates unclear, 2020-2024).
- Design variants: Call of Duty: Mobile auto-renewing passes; Stumble Guys let players choose which reward track to unlock first. — same PocketGamer.biz summary. Confidence: LOW.
- Median pass price $9.99 (entry $5.99, premium $29.99) as of May 2026 comes from a vendor's own catalog and is not used as fact. — [MWM glossary](https://mwm.ai/glossary/battle-pass). Confidence: LOW. Claims that pass holders show 40-80% higher D30/D60 retention come from a glossary with no method; discount. Confidence: LOW.
- Common failure mode per one blog (Aug 2026): difficulty curve and completability, with a standard that a season should be completable a week before end at target daily playtime. — [Playio](https://blog.playio.co/battle-pass-monetization). Confidence: LOW (single vendor blog).

**Limited-time and FOMO**
- Time-limited seasonal cosmetics create FOMO per Games Alchemy (see above). Royal Match's Team Gift Offer is a limited-time bundle appearing in the final three days of events. — [Sensor Tower, May 2026](https://sensortower.com/blog/what-royal-matchs-calendar-teaches-about-live-ops-in-2026). Confidence: HIGH.

### Inferences
- Pattern for the reader: daily (check-in, jackpot) feeds weekly (tournament, team event) feeds seasonal (pass, collection), each layer telling the player why to come back at a different time scale.
- Weekend-timed events suggest events are deliberately scheduled for conversion peaks, not only for retention (Sensor Tower's claim, MEDIUM).

### Gaps
- No verified, current (2025-26) battle-pass retention or revenue-share data; GameRefinery figures are old and secondary. Naavik battle-pass articles were not found by search.
- Season length/cadence benchmarks per genre are vendor-only.
- Limited-time offer (LTO) mechanics were not researched beyond the above (offer design is out of scope).

## 5. Gacha, loot boxes, random rewards, pity systems, collection completion

### Takeaway
Random-reward monetization is near-universal in the Korean top 40 (loot boxes in 37 of 40) and pity systems (a guaranteed pull after N failures, plus "featured guarantee" after a lost 50/50) are the standard answer to the fairness backlash and to regulation requiring odds disclosure.

### Cited Findings
- Prevalence in top-40 Korean games (2025): Loot Box 37 (92.5%), Collection Gacha 12 (30%), Complete Gacha 3 (7.5%); the authors flag poorly regulated transparency and probability disclosure as ethical concerns. — [arXiv 2504.10714 HTML](https://arxiv.org/html/2504.10714) and [abstract](https://arxiv.org/abs/2504.10714). Confidence: MEDIUM.
- Genshin Impact (launch-era rates, Oct 7, 2020): 5-star 0.6%, 4-star 5.1%, 3-star 94.3% on the character banner; 4-star pity at 9+ pulls; a lost 5-star roll guarantees the next 5-star is the featured prize; the article describes 50% 5-star chance after 89 pulls. — [RPG Site, Oct 7, 2020](https://www.rpgsite.net/feature/10312-genshin-impact-wish-system-gacha-rates-banners-and-the-pity-mechanic-explained). Confidence: MEDIUM (2020, game rules may have changed; contradicted below).
- Community-derived terms: hard pity (guarantee) at 90 pulls on the Genshin character banner (80 weapon), 90 in Honkai: Star Rail; "soft pity" is an unofficial, community-identified rise in odds beginning around pull 70-79 in Genshin (often cited 75); carries over between limited banners. Soft pity thresholds are player-derived estimates and sources differ. — [Search summary of Sportskeeda/Twinfinite/AFK Gaming](https://www.sportskeeda.com/esports/genshin-impact-pity-soft-pity-systems-explained). Confidence: LOW (community estimates, not official).
- Regulation: Apple added a rule to App Store Review Guideline 3.1.1 in December 2017 requiring apps offering randomized virtual items for purchase to disclose odds before purchase; coverage notes this mirrored disclosure rules recently enacted in China. — [TouchArcade, Dec 21, 2017](https://toucharcade.com/2017/12/21/apple-quietly-updated-the-app-store-review-guidelines-to-require-disclosure-of-loot-box-iap-odds/); [Fenwick](https://www.fenwick.com/insights/publications/apple-now-requires-disclosure-of-loot-box-odds). Confidence: MEDIUM (search summary; current guideline text not checked).
- Belgium treats paid loot boxes as banned/illegal gambling (since 2018 per glossary and SCMP); the Netherlands also cited; Korea probability disclosure since 2024 and China's guaranteed-within-N-draws rule are claimed in a glossary with no primary source. — [SCMP Abacus, 2019-20](https://amp.scmp.com/abacus/tech/article/3029544/china-wants-limit-number-loot-boxes-players-can-buy); [MWM glossary](https://mwm.ai/glossary/pity-system). Confidence: LOW.
- Monopoly Go albums, Royal Match Culinary Collection and Train Journey "guaranteed new card pack" apply the same randomized-collection loop to non-gacha games. — [Sensor Tower, May 2026](https://sensortower.com/blog/what-royal-matchs-calendar-teaches-about-live-ops-in-2026). Confidence: HIGH.

### Inferences
- A pity counter converts an unbounded random spend into a bounded one, which is why it is both a player-trust feature and a regulatory shield (inference, MEDIUM; the regulatory link is partly cited, the causal motive is not).
- Collection completion is the same psychological hook as gacha without the money-for-chance transaction, which is why casual puzzle games import it.

### Gaps
- Official current Genshin/HSR/Wuthering Waves rates and pity numbers were not read from the developers' pages.
- No independent data on gacha revenue share or spend distribution (whales) was gathered.
- Regulatory dates (China 2016 vs 2017; Korea 2024) are unresolved; loot box regulation by country was not systematically verified.

## 6. Push notifications, re-engagement, win-back and comeback bonuses

### Takeaway
Push is the main outbound re-engagement channel, but opt-in rates are low on iOS and fell on Android after Android 13 made permission opt-in. Win-back practice is segment-by-dormancy and escalating incentives, supported mainly by vendor content; no hard benchmarks for reactivation rate were found.

### Cited Findings
- Pushwoosh (article dated July 25, 2025): categories of game pushes are early churn prevention, habit-building (daily bonus and streak messages), conversion of loyal players, dormant re-engagement, gifts, limited-time offers, reminders; recommends asking permission after a meaningful action with a pre-permission explanation; example re-engagement flow: 3-day inactivity trigger, 24-hour offer expiry, reminder after 12 hours unopened, feedback request after another 3 days; do not interrupt active players, use in-app messages instead. Vendor-reported results: justDice early churn -26% and streak-message CTR up to 7.4%, Bladestorm DAU +16% in eight months with 97% opt-in, Beach Bum 3x DAU/MAU. — [Pushwoosh](https://www.pushwoosh.com/blog/game-app-push-notifications/). Confidence: MEDIUM (vendor with commercial interest; case results not independently verified).
- Opt-in benchmarks (vendor): Android game apps 83.2% vs iOS game apps 29.98%, and no correlation between opt-in and D1 retention in the sampled apps (an Android app had 77.9% D1 with 86.5% opt-in, another 22.4% D1 with 92.2% opt-in). — [Search summary of PocketGamer.biz reporting Pushwoosh](https://www.pocketgamer.biz/chart-of-the-week-why-getting-players-to-opt-in-to-game-push-notifications-matters/). Confidence: LOW (page 403; undated; vendor).
- Older benchmark (2013, Urban Airship): games had the lowest opt-in rate of any vertical (35%), opt-in users had 55% vs 29% first-month retention. — same search summary. Confidence: LOW and dated (2013); do not present as current.
- Android 13 made notifications opt-in (POST_NOTIFICATIONS runtime permission); Pushwoosh (16M+ devices, 2024) reports gaming apps lost nearly a third of opted-in users; Netcore reports about 60% average Android 13 opt-in vs 80-90% before. — [Pushwoosh 2024 research](https://pushwoosh.com/blog/android-13-opt-in-rates-research); [Android docs](https://source.android.com/docs/core/display/notification-perm). Confidence: LOW to MEDIUM (vendor figures via search summary; platform behavior itself is from Android docs).
- Win-back practice: segment inactive players by dormancy (example 7-30 days short-term, 30-90 days mid-term with re-onboarding via easy mission wins) and by value/likelihood of return; escalate from gentle reminder to bonus to exclusive comeback deal; tie incentives to what players value in the game; use live-ops events and updates as the reason to return. — [XtremePush](https://www.xtremepush.com/blog/gamification-dormant-player-reactivation); [Pushwoosh player re-engagement](https://www.pushwoosh.com/products/player-reengagement/); [Lloyd Melnick](https://lloydmelnick.com/tag/win-back/); [AppAgent](https://appagent.com/blog/winning-back-lapsed-players-reactivation-creative/). Confidence: LOW (vendor/blog summaries, no benchmark data).
- Streak-revival as a comeback tool: Duolingo management credited a one-time "Streak Revival" campaign for part of Q2 2026 DAU growth (see section 1). Confidence: LOW.

### Inferences
- The main push targets are D1-D7 retention (habit pushes), resurrection of 7-90 day lapsed users (win-back), and event/offer conversion. Because Day-1 is the largest drop-off, the first 3-5 minutes and first-day pushes are emphasised (Pushwoosh, vendor).
- Because opt-in is low on iOS, in-game appointment hooks (timers, daily events) and in-app messaging carry much of the return burden; push is an amplifier, not the foundation (MEDIUM inference).

### Gaps
- No independent, current opt-in benchmark for mobile games; every number is from a push vendor.
- No quantified comeback-bonus reactivation rates (for example "comeback chest after 14 days"); only qualitative practice found. No specific game examples of comeback bonuses with citable pages.
- Notification fatigue or uninstall effects in games: no data found.

## 7. Table stakes versus genre-specific

### Takeaway
Table stakes (nearly universal in grossing games): daily login/check-in, timer or limiter pacing, an events layer, a pass or equivalent, randomized rewards, and push/re-engagement. Genre-specific: prestige (idle), lives (match-3/casual puzzle), chest slots (Clash Royale-style), gacha banners with pity (character collectors), endless albums and tournaments (casual puzzle), alliance championships (4X strategy).

### Cited Findings
- Korean top-40 prevalence (2025, single market, mostly gacha RPG/strategy): Daily Login 38 (95%), Loot Box 37 (92.5%), Battle Pass 31 (77.5%), Progress Boosters 27 (67.5%), Social Dynamics 26 (65%), Conflict-Driven Design 25 (62.5%), First Purchase Benefits 17 (42.5%), Collection Gacha 12 (30%), Time-Gated Progression 9 (22.5%), Ease of Play 9 (22.5%), Complete Gacha 3 (7.5%). The paper's text reports Ease of Play and Time-Gated Progression as 10 games (25%), conflicting with Table 1. — [arXiv 2504.10714 HTML](https://arxiv.org/html/2504.10714). Confidence: MEDIUM.
- Casual puzzle convergence (Royal Match, Candy Crush, Gossip Harbor, Merge Mansion, Toon Blast): daily jackpot, leaderboard plus achievement-track events, endless album collections. — [Naavik, Nov 16, 2025](https://naavik.co/digest/live-ops-trends-powering-mobile-puzzle/). Confidence: HIGH.
- Strategy titles dominate 2025 revenue (nearly $15B), with Last War: Survival and Whiteout Survival projected at $2.4B and $2.2B; 135 games generated over $100M IAP in 2025 (total $50.8B). — [Sensor Tower, March 2026](https://sensortower.com/blog/top-grossing-mobile-games-live-ops-strategies-2025-report). Confidence: HIGH.
- Prestige is described for idle/incremental games. — [Game Developer 2017](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii). Confidence: HIGH.

### Inferences
- The "same patterns everywhere" the reader sees are explained by convergent evolution on three time scales (daily return, weekly competition, seasonal collection) plus a randomized-reward layer; Naavik says convergence even in retention (D90-to-D1 about 25%) and playtime (about 38 min/day).
- The Korean sample overstates gacha and loot boxes relative to the global market, which includes hypercasual and puzzle games that use no gacha. Table stakes for casual puzzle and for gacha RPG differ; the report writer should present them as two archetypes, not one list.

### Gaps
- No global, cross-genre prevalence study for daily login, events or push (the Korean study excludes events, push and stamina as categories).
- GameRefinery or Sensor Tower global feature-adoption tables, GDC Vault talks and Deconstructor of Fun posts were not obtained; Naavik and Deconstructor of Fun battle-pass and retention essays were not located by search.
- Contradictions to carry forward: (a) arXiv paper text vs Table 1 counts; (b) Genshin pity: 2020 article (50% after 89 pulls) vs community "hard pity at 90"; (c) China loot-box disclosure date 2016 vs 2017; (d) Pushwoosh Android game opt-in 83.2% vs Netcore about 60% on Android 13 (different periods and samples); (e) battle-pass prevalence 77.5% (Korean top 40) vs roughly 60% of top 20% grossing (GameRefinery, older, unclear region).
