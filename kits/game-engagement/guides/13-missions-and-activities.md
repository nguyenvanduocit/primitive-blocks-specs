# Missions and Activities

A mission board and the timers behind it fill a player's day between the big events. This guide covers the content of that layer: the types of mission and what each costs, how shipped games size, refresh and reward a board, and where being busy stops being engaged and becomes chores. The ladder of objectives, XP curves and progression are in `08-objectives-and-progression.md`; session endings and lapsed players are in `09-keeping-players.md`; the carrier is the block `engagement.objectives`, and rewards pay through the ledger of `billing.virtual-currency` as `objectives.reward`. The ethical floor is guide 06, and every rule below passes its three tests.

Evidence: developer posts and support pages (Supercell, Riot, Duolingo, HoYoverse as reported), a Game Developer analysis, press and interview recaps, psychology and gamification papers, and community wikis (named LOW or MEDIUM), each inline with HIGH, MEDIUM or LOW. The boards are documented; no source measures the retention or revenue effect of any mission type, and the chore evidence is press, community and opinion (see Gaps).

## Decision rule

1. **Pick mission types by the need they serve, and budget authoring per type.** The table below is this kit's synthesis of the sources (MEDIUM). Launch with few types: a core-loop mission, one spend or upgrade mission and the one or two types the archetype board shows. Add a type when the soft launch shows the need it serves is unmet.
2. **Size the board to the day the player already has.** Shipped boards hold three missions (Legends of Runeterra, Pokémon GO and Duolingo, sources in rules 4 and 7), four (Genshin Impact, community guides, LOW) or eight (Honkai: Star Rail, rule 5); none says why, and no source gives a best count or a minutes-per-day budget (Gaps). The designer's analysis of AFK Arena says the game supports daily sessions of five minutes or an hour, and its quest points add up to more than the top threshold, so a player can leave tasks undone ([Game Developer, 2020](https://www.gamedeveloper.com/design/flexible-time-session-design-in-afk-arena), MEDIUM, one analyst's reading). Supercell rebalanced Clan Games tasks to finish in one to five attacks and within a day, to make them feel less "grindy" ([Supercell, Oct 2021](https://supercell.com/en/games/clashofclans/blog/news/clan-games-changes-2), HIGH). Kit recommendation (LOW, inference): in the soft launch, time a full clear of the board for the median daily-active player and compare it with that player's normal daily play (scale in guide 07 rule 9); a board that needs more play than the player gives is a chore by construction.
3. **Count progress from play the player already chooses.** At least one mission closes by playing normally, in any mode. Overwatch 2 rewrote win-based weekly challenges as games played with wins counting double, "to ensure every game played contributes" ([patch notes via MP1st, June 2023](https://mp1st.com/news/overwatch-2-update-3-53-dropped-for-season-5-this-june-13-here-are-the-patch-notes), MEDIUM, secondary). Genshin Impact 4.1 lets Encounter Points earned from quests, events, exploration and collecting stand in for daily commissions, because commissions grew "rather repetitive for longtime players" ([RPG Site, Sept 2023](https://rpgsite.net/news/14808-genshin-impact-version-41-will-make-it-simpler-for-players-to-do-their-dailies), HIGH for the announcement). Halo Infinite tied all battle-pass XP to daily and weekly challenges, players objected to weapon-specific weekly objectives that pulled teammates off winning, and 343 added "Play 1 Game" challenges that grant XP in any mode ([Dexerto, 16 Nov 2021](https://www.dexerto.com/gaming/halo-infinite-players-flame-horrendous-battle-pass-progression-1699768/); [Dexerto, 18 Nov 2021](https://www.dexerto.com/gaming/halo-infinite-devs-promise-better-battle-pass-progression-1700390/), HIGH for the events).
4. **Make the board forgiving: free skip or reroll, carry-over, no loss for a missed day.** Legends of Runeterra gives one quest a day, three active at most, one reroll earned a day with two banked, and a player away for a week returns to three waiting quests ([Riot support](https://support.riotgames.com/en-us/legends-of-runeterra/gameplay/let-s-talk-about-quests), HIGH). Pokémon GO lets a player delete any of up to three held tasks and counts one stamp a day toward a seven-stamp reward without resetting on a missed day ([Serebii](https://serebii.net/pokemongo/fieldresearch.shtml), LOW to MEDIUM, community wiki; the no-reset rule is from a Bulbapedia summary, page not opened). Overwatch 2 carries incomplete weekly progress into the next week (MP1st, above). Supercell prices reviving an expired Clan Games task at 5 to 20 gems (Supercell, above); the kit default is a free reroll and an honest expiry, and any paid revive must pass guide 06 rule 2.
5. **Pay a ladder, not a lump.** Boards pay small and often, then a bonus for the whole board. AFK Arena pays at every twenty points up to one hundred, then a final reward (Game Developer, above). Honkai: Star Rail pays at each hundred-point step of a five-hundred-point day, with tasks worth 100, 200 or 500 points and rewards that scale with Equilibrium level, the game's account tier ([Icy Veins](https://www.icy-veins.com/honkai-star-rail/daily-training), LOW to MEDIUM, a search summary of a wiki). Duolingo boosted rewards for learners who finish all three Daily Quests ([Duolingo, Dec 2025](https://blog.duolingo.com/product-highlights/), HIGH, no outcome given). Whiteout Survival's top chest is reachable without finishing every mission ([guide](https://heaven-guardian.com/whiteout-survival-daily-missions-guide/), LOW).
6. **Audit the faucet through the ledger before launch.** Sum `objectives.reward` grants per active account per day and set them against the sinks the same account meets. Kolibri Games, maker of Idle Miner Tycoon, calls an economy healthy when currency keeps moving, an ideal where players spend premium currency at the rate they receive it, and reports that most players save it instead ([Kolibri Games](https://www.kolibrigames.com/blog/economy-in-free-to-play-mobile-games-part-2/), HIGH as the developer's statement; no figures in the text). No source gives the share of daily income that missions should carry (Gaps); guide 03 holds the economy rules.
7. **Order the board easy to hard and make later missions move the player forward.** Duolingo says its Daily Quests are "optimized very carefully" for a quality-of-time metric: the first is the easiest and gets the learner going, later ones get harder and tend to reward finishing a unit or reading the next story. It built the metric because total sessions favored quick, easy sessions and raw time spent skewed toward a few very active learners, and a feature such as leaderboards mostly raised time among users already doing enough ([Duolingo, June 2024](https://blog.duolingo.com/time-spent-learning-well/), HIGH as the company's statement; an education app, transfer to games MEDIUM).
8. **Rotate from a pool wider than the board, and retire repeats.** Parameterized templates are cheap to author and read as repetitive: Bethesda's Nesmith said, of the Radiant Story system, that a hand-built storyline is more intriguing than automated objectives, and the team limited jobs to fitting NPCs and wrote voice-specific dialogue to hide repeats ([GamesBeat, 2012](https://gamesbeat.com/bethesdas-nesmith-reflects-on-the-difficult-birth-of-skyrims-radiant-story-system/), MEDIUM, a report of a talk). Supercell removed Clan Games' monthly list of boosted tasks so every task is worth doing (Supercell, above). Kit recommendation (LOW): draw from a pool wider than any week of boards, scale the ask to player level, and log the repeat rate per template.
9. **Run the deepen-or-occupy test on every mission (next section), cap daily obligation, and keep the clock honest.** A mission passes when it needs only play the player would do anyway, or teaches or opens something the player keeps. Cap the board with a visible "done" state; Duolingo, AFK Arena and Legends of Runeterra all end the day at a finite list. Every reset and expiry uses the server clock and the `ends_at` of the time contract. No mission requires real money or a premium-currency purchase (guide 06 rule 1; the EU consumer network's principles for in-game currencies include no forced currency purchases, [Forbrukertilsynet](https://www.forbrukertilsynet.no/eng-articles/national-consumer-authorities-and-commission-take-action-on-harmful-practices-in-the-gaming-industry), HIGH for the action, non-binding).

## Mission types

Authoring cost and aging are this kit's judgement (MEDIUM); the last column carries the evidence.

| Type | Asks | Need served | Authoring cost, aging | Evidence |
|---|---|---|---|---|
| Tutorial | Use a feature once | Competence | Low each; closes and never returns | Rewards for tutorial steps are common practice (guide 01 rule 2, LOW to MEDIUM) |
| Core loop | Win or play a few rounds | Routine, competence | Low, parameterized; repeats fast | Overwatch 2 games played; Halo "Play 1 Game"; Lava Quest asks seven levels in a row ([Sensor Tower, May 2026](https://sensortower.com/blog/what-royal-matchs-calendar-teaches-about-live-ops-in-2026), HIGH) |
| Collect or craft | Gather, produce | Routine | Low; becomes busywork where income is automatic | Whiteout Survival daily list: gathering, training, research (guide above, LOW) |
| Spend or upgrade | Use a currency, upgrade a hero | Keeps the sink in use | Low; must use earned currency only | AFK Arena asks equipment, hero level, a summon (Game Developer); Kolibri on circulation |
| Social | Pair, help, contribute | Relatedness | Medium: matching, absent partners | Duolingo pairs a friend weekly for a five-day quest ([Duolingo, Sept 2022](https://blog.duolingo.com/friends-quests/), HIGH; the company's 5.6 times figure is about following friends, not about Quests); Clan Games |
| Exploration | Find, visit, collect | Autonomy, curiosity | Medium to high; bound to content | Genshin Encounter Points credit exploration; Pokémon GO tasks come from stops (Serebii) |
| Challenge | A skill test or streak | Competence | Medium: tuned per skill band | Lava Quest loses progress on a failed streak (guide 06, loss avoidance); Halo weapon-specific weekly objectives drew objections |
| Narrative | Finish a story step | Meaning | Highest per hour; finite | Homescapes' to-do list is worked by earning a star per won level, over 7,000 levels by late 2021 ([Wikipedia](https://en.wikipedia.org/wiki/Homescapes), MEDIUM); Radiant (rule 8) |
| Timed task or queue | Start it, return later | Autonomy of choice, a reason to return | Medium: timers, speed-ups, a notice | AFK Arena bounty quests never exceed twelve hours (Game Developer); the most dedicated Idle Miner Tycoon players complete five expeditions in a day (Kolibri); Supercell's chest test (guide 02 rule 5) |
| Event task | A milestone ladder in a window | Novelty, urgency | Per event; ends by design | Monopoly Go event guides list 43 to 49 milestones over a few days ([AFK Gaming](https://afkgaming.com/gaming/general/monopoly-go-epic-myths-event-all-tasks-rewards-explained), LOW); `engagement.event-calendar` |
| Achievement | A lifetime mark | Mastery, completion | One batch, a few per update; stale by design | Badges raised activity in a marketplace (guide 08 rule 4, MEDIUM) |

## Busy is not engaged

- Rewards tied to engagement, completion or performance undermined free-choice interest in a meta-analysis of 128 experiments (numbers in guide 08 rule 4, HIGH). A reanalysis found rewards "not harmful" in general, with negative effects on high-interest tasks only when rewards were tangible, expected and loosely tied to performance, and a lift for low-interest tasks ([Cameron, Banko and Pierce 2001](https://pmc.ncbi.nlm.nih.gov/articles/PMC2731358/), HIGH for the abstract). A board that pays an expected prize for what players already enjoy sits in the contested zone; a board that pays for a dull task buys compliance (inference, MEDIUM). Neither camp tested games.
- Points, levels and leaderboards raised output in an image-tagging task but did not change competence or intrinsic motivation ([Mekler et al. 2017](https://datalearner.com/academic/journal-papers/0747-5632/volumes-and-issues/183/paper-detail/36713), MEDIUM, abstract only). A review of gamification studies found positive effects that depend greatly on context and users ([Hamari, Koivisto and Sarsa 2014](https://research.aalto.fi/fi/publications/does-gamification-work-a-literature-review-of-empirical-studies-o/), HIGH for the abstract). A meta-analysis of gamified learning found g of 0.49, 0.36 and 0.25 for cognitive, motivational and behavioral outcomes, the last two less stable in high-rigor studies ([Sailer and Homner 2020](https://opus.bibliothek.uni-augsburg.de/opus4/frontdoor/index/index/docId/109056), HIGH as reported; learning, not games).
- Time played does not measure fun. In a study of video-game players low need satisfaction went with more hours, more tension after play and lower enjoyment, while high satisfaction went with enjoyment and energy ([Przybylski et al. 2009](https://pure.ewha.ac.kr/en/publications/having-to-versus-wanting-to-play-background-and-consequences-of-h/), HIGH for the abstract). Less need satisfaction also went with more fear of missing out, which went with lower mood and life satisfaction, in samples about social media ([Przybylski et al. 2013](https://selfdeterminationtheory.org/wp-content/uploads/2014/04/2013_PrzybylskiMurayamaDeHaanGladwell_CIHB.pdf), HIGH for the finding, LOW for transfer to games).
- Designers see chores arrive. Blizzard's quest lead said Mists of Pandaria dailies were never meant to feel mandatory but did, because the rewards were tied to raiding gear, and patch 5.2 detached the new dailies from key gear ([GameSkinny, 2013 interview recap](https://www.gameskinny.com/news/wow-52-staff-interviews-part-2-dave-kosak-ion-hazzikostas-and-ghostcrawler/), MEDIUM, read as a search summary). A 2026 publisher essay says mobile games have become "a Second Job", names daily quest lists among the causes, and reads falling retention as players filtering out pressure ([Gamota, Feb 2026](https://gamota.com/en_GB/?p=2753%2F), LOW: opinion, a hypothetical evening, no figures). A 2022 heuristic evaluation (Dahlan and Susanty, 28 Nov 2022) names Playing by Appointment and Pay to Skip, among others, as dark patterns of casual mobile games ([deceptive.design](https://www.deceptive.design/articles/finding-dark-patterns-in-casual-mobile-games-using-heuristic-evaluation), MEDIUM). Regulators and platforms: guide 06, "Harm and enforcement".
- Turn the evidence into a test (kit synthesis, MEDIUM). **Deepens**: needs only normal play, or teaches or opens a feature the player keeps. **Neutral**: asks something the player may enjoy but would not choose. **Occupies**: needs an action the player would skip with no reward, or repeats one already done. Ship occupying missions only as optional, skippable and capped, and never as the sole route to a reward the player needs. Judge a board by what players do next (return the next day, use the feature again, a stop with no "claimed and left" spike), not by completion rate or time spent (events in `12-live-ops-and-instrumentation.md`).

## Default path

1. Take the archetype of interview 1, copy its board below, and fill the worksheet row by row; drop any mission that cannot name its need.
2. Write the board's size and clear time in words, test it in the soft launch against real play, and give the board a visible "done" state.
3. Add the forgiving mechanics: a free reroll or skip, carry-over of progress, an unclaimed-reward rule shown on screen (guide 11, feature 4), one reset time per account day.
4. Build a template pool wider than a week of boards; schedule retirements and a repeat-rate log.
5. Set the reward ladder and run the ledger audit with `billing.virtual-currency`; keep premium currency out of any mission's price.
6. Run every mission through the deepen-or-occupy test and the three tests of guide 06; record the answers.
7. Instrument the `objective_*` events of guide 11 and read completion, skip and next-day return per mission after the soft launch.

## Worksheet

One row per mission. A blank cell marks a design decision that is still open.

| Mission (one sentence, specific target) | Need served | Type | Time it asks (words) | Reward kind and ledger reason | Counts from normal play? | Skip or reroll | Expires at (`ends_at`) | Deepens, neutral or occupies |
|---|---|---|---|---|---|---|---|---|
| Win a few levels today | Routine | Core loop | A few minutes inside normal play | Coins, `objectives.reward` | Yes | Free reroll | End of the account day | Deepens |
| | | | | | | | | |

## Per-archetype boards

Each board is this kit's illustrative design (MEDIUM, synthesis) with a named game where a source exists; times are in words because no source sets them.

| Casual puzzle or hybrid-casual | Why it is on the board | Reward kind | Time it asks | Supported by |
|---|---|---|---|---|
| Win levels to open the daily jackpot (Royal Match "Lava Quest", guide 02) | Plays the core loop and ends the first session of the day on a win | Coins, boosters | A few minutes, inside normal levels | `engagement.event-calendar`, `engagement.objectives` |
| Use a booster you own | Nudges an unused feature | A booster | One level | `engagement.objectives`, item grants through the ledger |
| Finish the next castle-room task | Gives the meta a destination (guide 08) | Decor, story step | A few sessions | `engagement.objectives` chains |
| Send a life to a friend | Relatedness at near-zero cost | A life | A moment | `ugc.friends-leaderboard`, `engagement.energy-lives` |
| Weekend event milestone ladder | Novelty on a calendar | Event currency, chest | Spread over a weekend | `engagement.event-calendar` |

| Idle or incremental | Why it is on the board | Reward kind | Time it asks | Supported by |
|---|---|---|---|---|
| Collect offline earnings and reinvest | Teaches the return loop | Currency | A moment | `engagement.objectives` |
| Buy the next tier of one generator | Points at the next upgrade (spend) | Multiplier | A moment | `engagement.objectives` |
| Start an expedition and collect the last one | A reason to return in a few hours (Idle Miner Tycoon) | Boosts, currency | A moment to start; hours to finish | No block yet (Block implications) |
| Reach a production target before the event ends | Gives the economy a goal | Event currency | Across a few sessions | `engagement.event-calendar` |
| Prestige once | Opens the permanent layer (discovery) | Permanent multiplier | Once, when ready | `engagement.objectives` |

| Character-collector RPG | Why it is on the board | Reward kind | Time it asks | Supported by |
|---|---|---|---|---|
| Clear the daily stage a few times | Core loop, spends the daily resource | Hero XP, materials | A few minutes per session | `engagement.energy-lives`, `engagement.objectives` |
| Level a hero or gear piece | Sink use (AFK Arena asks it) | Quest points | A moment | `engagement.objectives` |
| Fight one arena opponent | Light challenge and social contact | Quest points | A few minutes | `ugc.friends-leaderboard` |
| Send a bounty party out | A return trigger under twelve hours (AFK Arena) | Materials | A moment to send | No block yet |
| Summon once with free currency | Teaches the pull and its odds (guide 06 rule 1) | A hero | A moment | `billing.virtual-currency` |

| 4X or survival strategy | Why it is on the board | Reward kind | Time it asks | Supported by |
|---|---|---|---|---|
| Queue a build or research | Gives the player something to do between sessions | Progress | A moment | No block yet |
| Send a gather march | Collects resources while away | Resources | A moment | `engagement.objectives` |
| Train troops | Uses the stockpile (spend) | Speed-ups, resources | A moment | `engagement.objectives` |
| Give alliance help | Relatedness, cheap for the helper | Speed-ups | A moment | `engagement.objectives`; clans have no block yet |
| Upgrade the central building (a chapter chain) | A narrative spine (guide 08) | New systems | Days of timers, a few sessions of play | `engagement.objectives` chains |

## Gaps

- No source gives the best number of missions on a board, the minutes a daily board should ask, or the share of daily income missions should carry; shipped counts range from three to eight and none gives a reason.
- No source measures a mission type's effect on retention, or a personalized board against a fixed one; no public experiment on missions that follow a player's taste against nudges toward unused features was found.
- Per-commission rewards in Genshin Impact conflict between guides (10 or 20 Primogems), so no mission-to-income figure is used.
- No data on a year of maintenance cost for a mission pool; the evidence is two statements (Radiant Story, Genshin 4.1).
- The undermining result and the gamification effects come from non-game settings (image tagging, a marketplace, learning, social media) and are disputed; no game-objective test exists. No rigorous study of churn caused by daily obligation was found.
- Not opened: Bulbapedia and Fandom pages (blocked), the Windows Central Halo article (truncated), the Kosak interview itself (read through summaries), and the full text of Deci et al., Hamari et al., Mekler et al. and Sailer and Homner (abstracts and summaries only).

## Checklist

- [ ] Each mission names the need it serves and has a type from the table.
- [ ] The board's size and full-clear time are written in words and tested against real play in the soft launch.
- [ ] At least one mission closes by normal play in any mode, and no mission demands an off-meta way to play without being optional.
- [ ] The board has a visible "done" state, and its reward ladder tops out below the sum of its tasks.
- [ ] A free reroll or skip exists, unfinished progress carries over, and a missed day takes no currency or banked progress.
- [ ] Every reset and expiry comes from the server clock and an `ends_at`, and the screen states what happens to an unclaimed reward.
- [ ] No mission requires real money, a premium-currency purchase or an ad.
- [ ] Every mission is marked deepens, neutral or occupies, and occupying missions are optional and capped.
- [ ] The template pool is wider than a week of boards, with a repeat-rate log and a retirement plan.
- [ ] The ledger audit of `objectives.reward` grants against sinks is done.
- [ ] Success is read from next-day return and feature reuse, not from completion rate or time spent.
- [ ] The board passed the three tests of guide 06, with answers written down.
