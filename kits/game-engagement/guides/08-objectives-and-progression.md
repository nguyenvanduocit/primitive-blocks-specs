# Objectives and Progression

A player who can say what they are trying to do, and can see they are closer than a minute ago, has a reason to keep playing. Objectives supply the what; progression supplies the how far. This guide lays the game's objectives out as a ladder of six ranges, says which objective types fit which rung and what each costs, covers level curves, soft walls and content runway, and sets the rules for showing the next goal honestly. The pacing of the loop lives in `07-hook-and-rhythm.md`; keeping players and winning back lapsed ones live in `09-keeping-players.md`. The block that implements objectives is `engagement.objectives`.

Evidence: goal-setting and goal-gradient research, Game Developer and Naavik design writing, Roblox Creator Docs, and practitioner blogs, named inline with HIGH, MEDIUM or LOW. The theory is published and strong; its transfer to mobile games is untested, and the guide labels the transfer apart from the theory (see Gaps).

## Decision rule

1. **Write the objective ladder before the feature list.** Roblox advises goals at short, mid and long range, shown in visible places ([Roblox Creator Docs](https://create.roblox.com/docs/production/game-design/onboarding), MEDIUM, platform-specific). Naavik defines a short-term goal as one finishable within a session or two and wants short goals chained into medium and long ones, with Royal Match's room-by-room castle renovation as the example ([Naavik, Sept 2023](https://naavik.co/f2p-mobile/the-players-journey-a-call-to-adventure/), HIGH that the article says so, MEDIUM as evidence: design opinion). Sensor Tower files daily missions, check-ins and milestone progression as the recurring layer that sustains daily engagement and prepares players for mid-term and large-scale events ([Sensor Tower, March 2026](https://sensortower.com/blog/top-grossing-mobile-games-live-ops-strategies-2025-report), HIGH). Splitting that into six rungs is this kit's synthesis (MEDIUM). Every rung answers one question: *what is the player trying to achieve here, and how do they know they are getting closer?* A rung that cannot be answered in one sentence is missing or vague. Ship the rungs in the order of interview 7: daily at launch, weekly after the soft launch, seasonal only when the team can ship to a calendar (guide 02).

   | Rung | Where the player is | Typical carrier |
   |---|---|---|
   | Moment | Mid-action, seconds to a minute | The loop's own feedback: a target on the board, a health bar, a combo meter |
   | Session | One sitting | The next level or stage, a session target, the end-of-session summary |
   | Daily | Today | Daily missions, a jackpot won by playing, a streak (`engagement.daily-streak`) |
   | Weekly | This week | A tournament, team event or weekly mission set (`engagement.event-calendar`) |
   | Seasonal | Weeks to a couple of months | A pass (`engagement.season-pass`), a collection or album |
   | Lifetime | The account as a whole | Account level, rank, collection completion, story progress |

2. **State each goal as a specific target with feedback.** Across the research Locke and Latham reviewed, specific difficult goals beat "do your best" (meta-analytic effect sizes d of 0.42 to 0.80), harder goals produced more effort until ability or commitment gave out (d of 0.52 to 0.82), and goals work with commitment and summary feedback ([Locke and Latham, American Psychologist, 2002](https://goal-lab.psych.umn.edu/orgpsych/2020/readings/5.%20Motivation/Locke%20%26%20Latham%20%282002%29.pdf), HIGH for what the review reports; MEDIUM to LOW on transfer, because the evidence is workplace and laboratory tasks with assigned goals, not leisure play). On complex tasks the gap narrows (d of 0.41 on the most complex tasks against 0.77 on the least complex), and a learning goal or a nearer proximal goal helped where a distant performance goal did not (same paper). Kit reading (MEDIUM, inference): "win three levels in a row" should pull harder than "play more", a mastery goal ("land the new combo") suits a complex game, and every objective needs a visible measure.

3. **Show distance, and treat the goal gradient as plausible, not proven, for games.** People speed up as a reward gets closer ([Kivetz, Urminsky and Zheng 2006, Columbia Business School](https://business.columbia.edu/faculty/research/goal-gradient-hypothesis-resurrected-purchase-acceleration-illusionary-goal), HIGH for the study, which used coffee-shop stamp cards), and a card with a head start was redeemed more often, 34% against 19% ([Nunes and Dreze 2006 via Wharton](https://knowledge.wharton.upenn.edu/podcast/knowledge-at-wharton-podcast/the-lowdown-on-customer-loyalty-programs-which-are-the-most-effective-and-why/), MEDIUM, secondary). The games evidence is thinner: a survey of 1,724 online-game players linked perceived goal proximity to continued play ([Teng et al. 2022](https://research.polyu.edu.hk/en/publications/drawing-goals-nearer-using-the-goal-gradient-perspective-to-incre/), MEDIUM, correlational), and a Wordle study reports that feedback showing the player closer raised motivation while thwarted attempts raised frustration ([Dixon et al. 2024](https://doaj.org/article/cdde8b4e865c4a929ed8887df870cf17), MEDIUM, abstract seen as a search snippet). No source tests a progress bar against retention in a mobile game. Split every far goal into reachable steps and show the amount remaining (guide 06 lists the tendency behind each progress display).

4. **Pick objective types by rung and by what they cost to author and keep fresh.** The cost columns are this kit's judgement (MEDIUM, inference); the notes below the table carry the sources.

   | Type | Rung | Cost to author | Cost to keep fresh |
   |---|---|---|---|
   | Starter objectives | Session, first play | A script of three goals at three ranges (guide 01 rule 4) | Retune from the tutorial funnel |
   | Missions and quests | Daily, weekly | Low per template; value comes from a pool the server draws from | A pool wide enough that today's set differs from yesterday's |
   | Achievements | Lifetime | One batch at launch, a few per update | Stale by design; grow the list with each content release |
   | Collection completion | Seasonal, lifetime | Art and tuning per set | Endless albums repeat the structure cheaply and cost a perpetual reward inflow |
   | Rank and leaderboard targets | Weekly, seasonal | Needs player density (guide 04, `ugc.friends-leaderboard`) | Season resets and prize tables |
   | Narrative goals | Lifetime | The highest cost per hour of content | New chapters on a calendar |

   - Missions: a daily quest system in AFK Arena awards points for core-loop tasks with a reward at each twenty-point milestone up to one hundred, which the author says helps players organise the day and signals when the daily goals are done ([Game Developer, 2020](https://www.gamedeveloper.com/design/flexible-time-session-design-in-afk-arena), MEDIUM, one analyst's reading). Unity advises layered quests from daily to multi-day ([Unity Learn](https://learn.unity.com/tutorial/how-to-build-in-retention-and-player-engagement-as-part-of-your-early-concept), MEDIUM).
   - Collections: endless albums removed the finite content ceiling behind boom-and-bust engagement, and Royal Match offset the added reward source with a cut of about 30% in level-completion coins ([Naavik, Nov 2025](https://naavik.co/digest/live-ops-trends-powering-mobile-puzzle/), HIGH). Set completion unlocks high-value rewards and can drive card-pack purchases ([Sensor Tower, March 2026](https://sensortower.com/blog/top-grossing-mobile-games-live-ops-strategies-2025-report), HIGH).
   - Achievements: a field experiment on a trading marketplace (not a game) found users more active after badges arrived, with 1,410 users before and 1,579 after in a before-and-after comparison ([Hamari 2017 via Tampere](https://webpages.tuni.fi/gamification/2018/09/20/badges-increase-user-activity-a-field-experiment-on-the-effects-of-gamification/), MEDIUM, secondary page). A 2026 comparison of Steam games with and without achievements reports higher engagement for the former ([Pugliese and Silva](https://periodicorease.pro.br/rease/en/article/view/25288), LOW: correlational, PC, read as a search summary).
   - Assigned goals: Naavik says goals the game assigns rarely hold motivation unless they match what the player already wants, and good games link assigned quests to goals the player sets (Naavik, Sept 2023, as above, HIGH that it says so, MEDIUM as evidence). A meta-analysis of 128 experiments found rewards contingent on engagement, completion or performance undermined free-choice intrinsic motivation (d of -0.40, -0.36 and -0.28) while positive feedback raised it (d of 0.33) ([Deci, Koestner and Ryan 1999](https://depts.washington.edu/techdocs/papers/deciExtrinsicRewardsAndIntrinsicMotivation99.pdf), HIGH for the abstract; contested, since the journal carried a comment titled "Uses and Abuses of Meta-Analysis"; LOW on transfer to games). Kit reading (LOW): pair a reward with news of competence ("stage cleared, new booster unlocked"), which also serves guide 02 rule 2.

5. **Set the level curve per phase.** Keep early thresholds low so the first levels arrive fast ([Roblox Creator Docs](https://create.roblox.com/docs/production/game-design/onboarding), MEDIUM); Luban warns that players are lost when early thresholds take too long ([Game Developer, 2018](https://www.gamedeveloper.com/design/quantitative-design---how-to-define-xp-thresholds-), MEDIUM, one practitioner). He names three shapes. A linear curve adds a fixed amount per level and runs too slow early or too fast late. An exponential curve multiplies the last threshold by a coefficient (his example is 1.4), is easy early and demanding late, and the coefficient is hard to get right: too low is flat, too high skyrockets. A linear-increment curve, where each step grows by a fixed amount more than the last, is his compromise, and he advises adjusting computed values by hand. Kit recommendation (MEDIUM to LOW, inference): size early levels in minutes of play, mid levels in sessions and late levels in weeks, and keep a table of threshold, expected time to reach and cumulative time next to the curve, because the time between thresholds matters as much as the thresholds.

6. **Name the power progression and every soft wall.** Bycer separates enemy power, scaling power (bigger numbers) and hard upgrades that change how the player plays ([Game Wisdom, 2017](https://game-wisdom.com/?p=19901), MEDIUM, practitioner vocabulary). In idle games costs grow exponentially while production grows linearly or polynomially (the AdVenture Capitalist example uses a growth rate of 1.07, an example and not a rule), and multipliers at thresholds and prestige resets restore the pacing ([Pecorella 2016](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-i), HIGH for the example; part III is cited in guide 02). A developer postmortem reports a first prestige after twenty-five to thirty-five minutes and would now aim for fifteen to twenty ([DEV Community](https://dev.to/tanishpaul1106/aura-data-and-prestige-designing-the-economy-of-doomscroll-2077-293f), LOW to MEDIUM, one developer). A soft wall (a spike, a timer, a resource shortfall) slows progress without stopping it. SayGames treats a fail-rate spike as information: a 50% fail rate means about two attempts per level and 80% about five, averages hide players who need ten or twenty attempts, and what looks like churn can be a pause of several sessions ([SayGames, 2026](https://blog.say.games/posts/how-to-work-with-difficulty-in-hybrid-puzzles-so-players-dont-leave--but-stay-and-pay), MEDIUM, producer's blog). Rovio researchers model less skilled and less persistent players as more sensitive to difficulty and quicker to churn ([Roohi et al., CHI PLAY 2020](https://arxiv.org/abs/2008.12937), MEDIUM, abstract only). One analyst reads AFK Arena's boss spikes every five levels as a brake that exposes players to paywalls ([Game Developer, 2020](https://www.gamedeveloper.com/design/flexible-time-session-design-in-afk-arena), LOW to MEDIUM). A Columbia Business School brief reports that easing difficulty for players at risk of quitting raised playtime, retention and spending in a large mobile puzzle game ([brief](https://business.columbia.edu/research-brief/digital-future/easier-games-more-revenue), LOW: the page returned 403 and was read through a secondary summary). Kit recommendation (MEDIUM, inference): every wall shows its exits (play on, wait, spend, ask) before the player reaches it, and timed gates belong to `engagement.energy-lives`.

7. **Give mastery a ladder and remove dead ends.** Mastery progression grows what the player can do while the character's numbers stay put: techniques, harder modes, rank tiers. It serves the competence need that predicted enjoyment and future play in four studies ([Ryan, Rigby and Przybylski 2006](https://www.rochester.edu/warner/lida/wp-content/uploads/2022/11/02bfe513dd59366750000000.pdf), HIGH, see guide 06), and Naavik's example of an intrinsic goal is a player aiming for a league such as Ultimate Champion (Naavik, Sept 2023, as above). Quantic Foundry's motivation model has a Mastery cluster and an Achievement cluster ([GDC Vault](https://gdcvault.com/play/1025742/A-Deep-Dive-into-the), HIGH that the model exists). A dead end is a point with no visible way forward. The 2015 list of reasons players leave names broken progression, grinding without intrinsic reward, scarce resources, empty sessions and punishing inactivity ([Game Developer](https://www.gamedeveloper.com/design/16-reasons-why-players-are-leaving-your-game), HIGH that these are the author's claims, MEDIUM as current guidance), and a finite ladder strands the player on its last rung (inference, MEDIUM; the endless album is the shipped fix, rule 4).

8. **Size the content runway to the calendar in interview 7.** Candy Crush Saga adds 30, 45 or 60 levels each Wednesday and has about 17,000 levels ([PocketGamer, Feb 2025](https://www.pocketgamer.com/articles/085479/how-many-levels-are-there-in-candy-crush-saga/), MEDIUM, third-party guide). A hybrid-casual producer suggests about 100 levels for a first public version and 200 to judge D14 and later metrics (SayGames, as in rule 6, MEDIUM to LOW, one producer). Roblox says many games ship a content update every two weeks to one month, spend fewer than three weeks of effort on it, and stretch each release with progression, limited-time events and passes ([Roblox Creator Docs](https://create.roblox.com/docs/production/game-design/content-updates), HIGH that this is the guidance, platform-specific). Kit recommendation (LOW, inference with no source): from the soft launch, measure the content units the fastest tenth of players finish per week, divide the unfinished units by that rate, and refuse a calendar whose next batch lands after the runway ends.

9. **Show the next goal honestly.** These rules apply the three tests of guide 06 rule 2 to progress displays (kit recommendation, MEDIUM). (a) Counts come from the server's progress record and the animation never runs ahead of it. (b) The remaining amount appears as a number next to the bar. (c) The next reward is visible with its kind; a random reward shows its odds (guide 06 rule 1). (d) One primary goal, the nearest meaningful one, is promoted and the rest sit under it. (e) A head start is real and explained, because a stated reason for an endowment strengthens the effect (Nunes and Dreze, rule 3). (f) Countdowns run from `server_now` and `ends_at`, and an expired objective says so and says what the player keeps. (g) Payment never decides whether a goal counts, and a paid skip is priced in real money. Red lines from guide 06: no pressure timers aimed at children, no bar that slows near the end or resets silently, no design argument that rests on loss aversion or the Zeigarnik effect (both contested there).

## Default path

1. Take interview 1 (archetype) and interview 7 (calendar), copy the matching ladder below, write the objective sentence and fill the worksheet; mark each rung the first release does not ship as "later", with the soft-launch gate that triggers it.
2. Script the end of the first session with a short, a medium and a long goal (guide 01 rule 4).
3. Build the level table (threshold, expected time, cumulative time) and set the early levels in minutes of play.
4. List every soft wall with its visible exits and measure fail rate or time at each wall (events in `12-live-ops-and-instrumentation.md`); compute the runway and give each rung a calendar owner.
5. Wire the rungs: `engagement.objectives` for missions, quests and achievements (rewards pass the ledger of `billing.virtual-currency` as `objectives.reward`), `engagement.daily-streak`, `engagement.event-calendar`, `engagement.season-pass`, `engagement.energy-lives` for timed gates, `ugc.friends-leaderboard`, and `data.progress-sync` when progress follows the player (interview 5). The screens are in guide 10 and the per-feature specs in guide 11.
6. Run every objective with a countdown, a pre-filled bar or a random reward through the three tests of guide 06 and record the answers.

## Per-archetype ladders

Rows with a source name it; the rest are this kit's illustrative ladders, a starting point and not observed practice (MEDIUM, synthesis).

| Casual puzzle or hybrid-casual | Example objective | Reward kind | Where it lives |
|---|---|---|---|
| Moment | Clear the level target (collect the tiles, free the item) | Score, stars, booster charge | In-level HUD with a target counter |
| Session | Reach the next node on the level map | Coins, a booster | Level map, next node marked |
| Daily | Win levels to claim the daily jackpot (Royal Match "Lava Quest", [Naavik, Nov 2025](https://naavik.co/digest/live-ops-trends-powering-mobile-puzzle/), HIGH) | Coins, boosters, a life | Home-screen event entry |
| Weekly | Climb a leaderboard event or add to a team goal (guide 04) | Chest, currency | Event tab with rank and time left |
| Seasonal | Complete an album (Royal Match's collection runs about two months, [Sensor Tower, May 2026](https://sensortower.com/blog/what-royal-matchs-calendar-teaches-about-live-ops-in-2026), HIGH) | Packs, cosmetics, large currency | Collection screen with set counters |
| Lifetime | Restore the castle rooms in order ([Naavik, Sept 2023](https://naavik.co/f2p-mobile/the-players-journey-a-call-to-adventure/), HIGH) | Decor, new areas | Meta screen showing the next room |

| Idle or incremental | Example objective | Reward kind | Where it lives |
|---|---|---|---|
| Moment | Buy the next upgrade within reach | Production multiplier | Upgrade list with cost and an affordable marker |
| Session | Unlock the next system; unveil systems gradually behind visible goals ([Global Games Forum](https://www.globalgamesforum.com/ctv/idle-game-design-lessons-from-developing-adventure-capitalist), LOW to MEDIUM) | A new income source | The locked row with its unlock cost |
| Daily | Collect offline earnings and clear the daily tasks | Currency, boosts | Offline-earnings popup, task list |
| Weekly | Reach a production threshold in a limited event | Event currency, boosts | Event tab |
| Seasonal | Reach a prestige tier before the season ends | Permanent multiplier | Prestige screen with the projected gain |
| Lifetime | Prestige count and total multiplier (first prestige early, rule 6) | Permanent bonuses | Progress screen |

| Character-collector RPG | Example objective | Reward kind | Where it lives |
|---|---|---|---|
| Moment | Win this battle with the chosen team | Hero XP, battle rewards | Battle result screen |
| Session | Push the next campaign stage | Hero XP, gear | Campaign map with the next stage |
| Daily | Earn daily quest points with a reward at each milestone (AFK Arena, [Game Developer, 2020](https://www.gamedeveloper.com/design/flexible-time-session-design-in-afk-arena), MEDIUM) | Summon currency, upgrade materials | Quest list with a milestone track |
| Weekly | Reach an arena rank or an event goal | Currency, limited shards | Event tab |
| Seasonal | Season pass or a banner season (odds disclosed, guide 06) | A limited hero, cosmetics | Pass screen, banner page with the pity counter |
| Lifetime | Complete the hero index, raise account level | Titles, index rewards | Collection index showing owned against total |

| 4X or survival strategy | Example objective | Reward kind | Where it lives |
|---|---|---|---|
| Moment | Queue a build, a research or a march | Progress toward the queue | City view with queue timers |
| Session | Fill the build queue and send a gather march before leaving | Resources | City view and queue panel |
| Daily | Give alliance help and clear the daily tasks | Speedups, resources | Task list, alliance tab |
| Weekly | Take part in an alliance or server event | Event currency, speedups | Event tab |
| Seasonal | Compete in an alliance championship ([Sensor Tower, March 2026](https://sensortower.com/blog/top-grossing-mobile-games-live-ops-strategies-2025-report), HIGH) | Exclusive items, rank | Championship screen |
| Lifetime | Raise the central building, whose level caps the others in one popular title ([HostedGG guide](https://hostedgg.com/blog/whiteout-survival-beginner-progression-guide), LOW: community guide, undated) | Troop tiers, slots, systems | City view with the requirements list |

## Worksheet

The objective sentence: *Players of [game] are trying to [outcome] by [core action], and they know they are getting closer because [visible measure].* Example: "Players are trying to restore the castle by clearing puzzle levels, and they know they are getting closer because each room shows repairs done out of repairs needed." Then fill one row per rung; a row that cannot be filled in one sentence marks a missing rung.

| Rung | Objective (one sentence, specific target) | Measure shown | Reward kind | Owner (block or feature) | Calendar owner |
|---|---|---|---|---|---|
| Moment | | | | | |
| Session | | | | | |
| Daily | | | | | |
| Weekly | | | | | |
| Seasonal | | | | | |
| Lifetime | | | | | |

## Gaps

- No source measures the retention or revenue effect of any objective type (mission, achievement, collection, narrative goal) in a mobile game. The nearest are a marketplace badge experiment, a correlational Steam comparison and one educational app's split of daily goal from streak (guide 02).
- No benchmark for XP thresholds, time to first level-up, level-up cadence, or how many daily missions work best; only the direction (fast early) is stated, by practitioners.
- Goal-gradient and endowed-progress evidence comes from loyalty cards, a Wordle lab study and an online-game survey; no field test of a progress display in a mobile game was found.
- No data on churn at the end of a finite ladder, no published runway size by genre (the figures above are single-studio cadences), and no developer data on 4X or gacha progression walls (the sources are a community guide and one analyst's reading).
- The reward-undermining result comes from non-game experiments, is disputed, and has not been tested on game objectives.
- Sources not read in full: the Columbia difficulty brief (read through a secondary summary), the Hamari primary page, and the Wordle paper beyond its abstract.

## Checklist

- [ ] The objective sentence is written, every rung has a one-sentence answer or a "later" mark with its gate, and each objective has a specific target and a visible measure.
- [ ] The first session ends with a short, a medium and a long goal.
- [ ] Early levels are sized in minutes of play, and a table of threshold, expected time and cumulative time exists.
- [ ] Every soft wall has visible exits and a measure; the content runway is computed from soft-launch data and every rung has a calendar owner.
- [ ] Each rung maps to a block or feature, and rewards pass the ledger.
- [ ] Progress displays use server counts, show the remaining amount and the next reward, and explain any head start.
- [ ] Objectives with a countdown, a pre-filled bar or a random reward passed the three tests of guide 06.
- [ ] No plan cites a retention lift for an objective type.
