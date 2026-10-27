# Hook and Rhythm

A game keeps a player through three hooks at three ranges (a promise in the first seconds, a pull into the next round, a goal worth staying for) and through a rhythm that paces them: tension and release inside a session, a reward cadence, a first-week script and a calendar of content drops. This guide describes each hook and each rhythm as top games ship it, says how strong the evidence is, and turns the archetype of interview 1 into a hook, a rhythm shape and a first-week script.

Evidence: Unity, Sensor Tower, Naavik, Game Developer essays, a King talk reported by Mobilegamer.biz, Nir Eyal's own page and one critic, plus survey and benchmark summaries (primary benchmark reports not opened), named inline with HIGH, MEDIUM or LOW. The patterns are documented; no source measures the effect of any hook or rhythm choice (see Gaps). The tendencies behind each hook and the compliance floor are in guide 06.

## Decision rule

1. **Write the hook as one sentence at three ranges.** The opening hook is the promise of the first seconds, the session hook pulls the player into the next round, and the long-term hook is the reason to still be here in a month. The split is this kit's synthesis (MEDIUM): the opening belongs to guide 01, the session pull to the core loop's goal layer in guide 01, and the long-term hook to the time scales of guide 02. Worksheet question 4 holds the sentence.
2. **Make the opening promise true.** Hyper-casual publishers advise showing the core action, with a fail inside the first 3-4 seconds in at least one ad variant, and report that 70 to 80% of Supersonic's most successful creatives did ([Unity, Nov 2024](https://unity.com/resources/growing-hyper-casual-games), MEDIUM: a publisher guide about ads). In a survey of 4,500 US players, 67% named gameplay as the main factor in downloading and staying, and showing real gameplay in ads was almost twice as important to Android players ([Mistplay survey via GameDev Reports](https://gamedevreports.substack.com/p/mistplay-and-appsflyer-player-loyalty), MEDIUM, self-reported). The first minutes then deliver what the ad showed (guide 01), and the concept test checks it before production (guide 05).
3. **End every round on a pull into the next one.** Four pulls recur: visible progress, a near-miss, an unfinished goal and anticipation of a reward (table below). Their psychology and limits are in guide 06 (loyalty-card and slot-machine findings; transfer to games is untested). Choose one per round. A near-miss that is paid for, or aimed at minors, sits at the exploitative end (guide 06).
4. **Choose one long-term hook that fits the archetype and name what carries it.** The options are collection, mastery or prestige, status, story and community (table below); each is carried by a block or a guide, and the table says which.
5. **Use the Hook Model as vocabulary and not as proof.** Eyal's page gives four phases (trigger, action, variable reward, investment), says predictable feedback loops do not create desire, and takes its examples from consumer internet products ([Nir Eyal](https://www.nirandfar.com/how-to-manufacture-desire/), HIGH that this is the model as he states it). A behavioral scientist argues that continuous rewards build a behavior while variable rewards maintain it, and that the model does not describe first-time onboarding ([Hreha, 2022, updated 2026](https://www.thebehavioralscientist.com/articles/hooked-how-to-build-habit-forming-products-is-wrong), MEDIUM that the critique is made, LOW as evidence). No controlled game trial of the model was found (guide 06, MEDIUM). Use the phases as a loop check: a trigger (timer, notification, goal), an easy action, a reward, and something the player has put in.
6. **Shape each session as tension and release.** Flow arises when the player has a real chance of completing the task, with clear goals, prompt feedback and a sense of control ([Bradshaw, Game Developer 2016](https://www.gamedeveloper.com/design/gameplay-flow-designing-for-player-immersion), MEDIUM, a summary of Csikszentmihalyi). The kit's beat sheet is: a visible goal, rising challenge, one peak, a release (reward and celebration), the next pull, a designed stopping point (kit synthesis, MEDIUM). Roblox advises ending onboarding on a designed moment of joy ([Roblox Creator Docs](https://create.roblox.com/docs/production/game-design/onboarding), MEDIUM, platform-specific).
7. **Ramp difficulty gradually and follow a hard round with an easy one.** King reported at GDC 2024 that level 65 was both its highest-converting level and its largest source of churn, that a harder version lifted conversion in the short term while easier versions kept players longer, that harder levels should be shorter, and that fixing its hundred least fun levels gave "a very significant uplift in engagement"; it measures fun as time to abandon and time to pass, separately from difficulty ([Mobilegamer.biz, 27 March 2024](https://mobilegamer.biz/how-king-defines-a-good-candy-crush-saga-level-and-why-it-constantly-prunes-the-bad-ones/), MEDIUM: a news report of a talk, one game). Hopson warns that sharp difficulty jumps in puzzles make players walk away and that cutting rewards is punishing ([Hopson, Game Developer 2001](https://www.gamedeveloper.com/design/behavioral-game-design), MEDIUM). The easy beat after a hard round is this kit's reading of King's result.
8. **Pay a fixed reward every cycle, add variable surprises on top, and keep one appointment.** Hopson's summary of schedules: a fixed ratio produces a pause after each reward, a fixed interval produces a pause and then frequent checking, a variable ratio produces the highest activity but "doesn't necessarily mean" the best design, a variable interval produces steady, slower activity, and offering several activities at once covers the pauses (HIGH that he states this; MEDIUM as guidance: behavioral theory from 2001, no game trial). Eyal leans on variable rewards and Hreha on continuous ones for a new habit (rule 5), so week one pays predictably on every step and variable rewards join once the player returns by habit (kit recommendation, LOW; test it in the soft launch). Variable rewards earned by play are the default; a bought random reward needs interview 3 and the guide 06 floor (odds disclosed, prices in real money, minors handled).
9. **Fit the session shape to the archetype and set its length from the soft launch.** For scale only: a summary of GameAnalytics' 2026 report gives about five minutes a session and five to six sessions a day for the top quarter of mobile games, and about eight minutes and nearly ten sessions for the top tenth ([GameDev Reports](https://gamedevreports.substack.com/p/gameanalytics-mobile-and-pc-game)); a summary of the previous report puts the median at five to six minutes, the top quarter at eight to nine, and midcore titles highest at six to seven sessions a day, without defining midcore ([GameDev Reports](https://gamedevreports.substack.com/p/gameanalytics-mobile-gaming-benchmarks)). The two do not reconcile and neither summary gives a genre split, so take only the order of magnitude (MEDIUM). Casual puzzle games on iOS in the US run about thirty-eight minutes a day, and the daily jackpot is "intentionally brief and typically solvable in a player's first session of the day" ([Naavik, Nov 2025](https://naavik.co/digest/live-ops-trends-powering-mobile-puzzle/), HIGH). One idle designer models a first session of fifteen to sixty minutes, then check-ins that thin from hourly to daily to weekly, with timers lengthened to match ([Guan, 2025](https://ericguan.substack.com/p/idle-game-design-principles), LOW: one model, no data).
10. **Script the first week and tie every ask to guide 01.** Roblox asks for short, medium and long goals, Unity Learn for a daily reward inside the first session and a preview of the next week's rewards, and Naavik says the daily jackpot of top puzzle games unlocks within a new player's first week ([Roblox](https://create.roblox.com/docs/production/game-design/onboarding), [Unity Learn](https://learn.unity.com/tutorial/how-to-build-in-retention-and-player-engagement-as-part-of-your-early-concept), MEDIUM; Naavik, HIGH). One practitioner puts the meta layer at D3 to D5, social hooks at D3 and a D7 reward worth more than D1 to D6 combined, and labels these tactics judgment, not measurement ([Game Growth Advisor, 2026](https://gamegrowthadvisor.com/blog/2026-03-17-mobile-game-retention-strategies-2026/), MEDIUM). The D7 anchor uses the same loss-avoidance lever as a streak, so it passes the guide 06 tests first.
11. **Drop content at three time scales, and ahead of the content wall.** Sensor Tower sorts top-grossing live ops into recurring, feature and large-scale events ([Sensor Tower, March 2026](https://sensortower.com/blog/top-grossing-mobile-games-live-ops-strategies-2025-report), HIGH); read them as the daily pull (jackpot, win streak), the weekly status contest and the seasonal collection or pass. Royal Match runs a weekly contest rhythm timed to weekends and a two-month collection, and its purchase revenue spikes on weekends, which Sensor Tower attributes to event-driven conversion and not to more players ([Sensor Tower, May 2026](https://sensortower.com/blog/what-royal-matchs-calendar-teaches-about-live-ops-in-2026), HIGH for the calendar, MEDIUM for the cause). Sensor Tower's benchmark set of twelve top casual games averages 2.5 standard tournament formats and 9.4 sprint-time events a month per game: scale for top-grossing games, not a launch target. Weekly leaderboard events run in almost all top casual puzzle titles (Naavik, HIGH). 34% of surveyed players name frequent content updates as a reason to return (Mistplay survey, MEDIUM), and a practitioner puts the puzzle content wall at D7 to D14 (Game Growth Advisor, MEDIUM, judgment). The cadence follows interview 7 and guide 02: daily at launch, weekly after the soft launch, seasonal only on a calendar the team keeps.

## Hook layers

| Layer | Hook | What top games show | Fits | Evidence |
|---|---|---|---|---|
| Opening | Promise in the first seconds | The ad shows the core action, often a fail, and the first level is that action | All four; most for casual puzzle and hybrid-casual | Unity guide, MEDIUM |
| Opening | Ad and game match | Real gameplay in the creatives | All, Android most | Mistplay survey, MEDIUM |
| Session | Visible progress | A bar, counter or "next reward" always on screen; Royal Match's Lava Quest requires seven levels in a row | All | Goal gradient HIGH, endowed progress MEDIUM, both from loyalty cards (guide 06); [Sensor Tower, May 2026](https://sensortower.com/blog/what-royal-matchs-calendar-teaches-about-live-ops-in-2026) HIGH for the event |
| Session | Near-miss | A round lost by one move, a streak broken at its last level | Casual puzzle | [Clark et al. 2009](https://pmc.ncbi.nlm.nih.gov/articles/PMC2929454) HIGH, slot-machine task, small sample |
| Session | Unfinished goal | Quest log, incomplete set, a queued timer | RPG, 4X, idle | Memory effect did not replicate, resumption of interrupted tasks held (guide 06, MEDIUM) |
| Session | Anticipation | A chest, pull, jackpot or stack of offline earnings waiting | All | Variable-ratio theory (Hopson, MEDIUM); no game experiment |
| Long-term | Collection | Endless album; character roster | Puzzle (album), RPG (roster) | Naavik HIGH; collection gacha in 12 of the top 40 Korean games ([arXiv 2504.10714](https://arxiv.org/html/2504.10714), MEDIUM, one country); completion among the top three motivations in a reported Quantic Foundry summary ([Player Driven](https://playerdriven.substack.com/p/quantic-foundrys-nick-yee-on-gamer), LOW) |
| Long-term | Mastery and prestige | Harder tiers; in idle, a reset for a permanent multiplier | RPG, 4X (mastery); idle (prestige) | Competence predicted enjoyment and future play ([Ryan, Rigby, Przybylski 2006](https://www.rochester.edu/warner/lida/wp-content/uploads/2022/11/02bfe513dd59366750000000.pdf), HIGH); prestige gives a ladder-climbing feeling and rescales numbers ([Pecorella 2017](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii), HIGH) |
| Long-term | Status | Weekly leaderboard events, power rank | Puzzle, 4X | Naavik HIGH that the events run; retention effect unmeasured (guide 04) |
| Long-term | Story | Chapters, character arcs | RPG | No source found |
| Long-term | Community | Teams, alliances | 4X, RPG | Guide 04: no trustworthy multiplier |

The Fits column is this kit's reading of the sources (MEDIUM). Goals and progression curves are in guide 08 (`08-objectives-and-progression.md`); investment and in-session staying power are in guide 09 (`09-keeping-players.md`).

## First week

| Point | The player does | The player receives | The player is asked |
|---|---|---|---|
| Day 0, first session | One mechanic per step; a first win inside the first couple of minutes | A reward per step, a starting gift that buys a meaningful upgrade, a designed moment of joy, three goals (short, medium, long) | Nothing that adds friction (guide 01) |
| Day 0, end | Sees what is waiting tomorrow | A preview of the coming week's rewards; the first daily reward ready | The notification explanation screen, at the first visible benefit |
| Day 1 | The daily loop once; meets the second mechanic | The first daily reward (a play-to-claim jackpot where the archetype has one) | An account link if interview 5 says yes |
| Days 2 to 3 | Reaches the start of the meta layer (upgrades, collection, map) | The first meta reward | One asynchronous social step (guide 04); a first offer only after a first spend (guide 03) |
| Days 4 to 6 | Joins the first weekly event | Daily rewards that step up toward the week's anchor | Nothing new |
| Day 7 | Finishes the first weekly event | The week's anchor reward | The rating prompt after a win (guide 01) |

The script is practitioner judgment plus this kit's synthesis (MEDIUM); no source measures it.

## Archetype table

| Interview 1 answer | Recommended hook | Rhythm shape | First-week script | Evidence |
|---|---|---|---|---|
| Casual puzzle or hybrid-casual | Opening: the first level is the ad's promise. Session: a win-streak or jackpot, lives bounding a run of levels (guide 02). Long-term: endless album, weekly leaderboard | Short rounds in a run; an easy round after a hard one; a jackpot solvable in the first session of the day; one weekly event; the content wall is the risk | Day 0 first win; day 1 first daily reward; days 3 to 5 meta layer (map, collection); day 7 first weekly leaderboard event | Naavik, Sensor Tower HIGH; King, Game Growth Advisor MEDIUM |
| Idle or incremental | Opening: the first automation arrives fast. Session: the next upgrade is within reach and earnings wait on return. Long-term: prestige | A long first session, then check-ins that thin out, with timers lengthening to match; the first reset arrives early (one postmortem: twenty-five to thirty-five minutes for most players, with fifteen to twenty as its author's aim, [DEV Community](https://dev.to/tanishpaul1106/aura-data-and-prestige-designing-the-economy-of-doomscroll-2077-293f)) | Day 0 the first automation and ideally the first reset; day 1 the first return to a waiting stack; days 2 to 3 one new system at a time; day 7 a second reset that is visibly faster (kit recommendation) | LOW: a designer's model and a postmortem; Pecorella HIGH only for why prestige exists |
| Character-collector RPG | Opening: the fantasy and the first character. Session: a stage push toward the next pull or upgrade, with a visible pity counter if pulls are sold. Long-term: roster, guild | Several sessions a day, each spending a daily resource and then stopping (kit recommendation); daily and weekly resets | Day 0 a first summon (one game's [guide](https://dotgg.gg/sword-of-convallaria/reroll-and-gacha-system-guide-for-sword-of-convallaria/) describes a beginner-only banner that guarantees a Legendary and closes after thirty days or at the first Legendary, LOW); a simple loop, since RPG players leave at D3 to D7 on complexity; the guild hook at D3 to D7 | LOW to MEDIUM: Game Growth Advisor judgment |
| 4X or survival strategy | Opening: the base the player builds, with fast first upgrades (kit recommendation). Session: queue a timer, leave, return when it ends. Long-term: alliance, power rank, seasonal event | Many short check-ins around build and training timers with no stamina bar (Clash of Clans, guide 02; midcore session counts, rule 9); players leave at D14 to D30 at the plateau (judgment) | Day 0 finish the tutorial, claim every reward and upgrade the main building at once; join an alliance in the first days ([fan guide to one game](https://wostools.net/beginners-guide), LOW; guide 04 puts alliance mechanics from about the second week); day 7 first alliance event | LOW; Game Growth Advisor MEDIUM for the leaving point |

## Worksheet

Copy these into the project contract and answer each in one or two lines.

Hook sentence
1. Which ad moment (guide 05 concept test) and which first-minute moment deliver the same promise?
2. Which pull ends each round: visible progress, near-miss, unfinished goal or anticipation?
3. Which one long-term hook (collection, mastery or prestige, status, story, community), and which block or guide carries it?
4. Fill in: "For a player who wants ___, the game promises ___ in the first minute, pulls them into the next round with ___ and keeps them for a month with ___."

One session's beat sheet
5. How many rounds make a session and how long is a round, as measured in the soft launch?
6. Where are the tension peak, the release, the designed stopping point and the reason to return (timer, waiting reward, event)?
7. Which rewards are fixed per cycle, which variable, which appointments, and is any variable reward bought (interview 3)?
8. Where does the easy beat follow a hard round, and how are difficulty and fun measured (guide 12)?

Day-1 to day-7 rhythm
9. For day 0, day 1, days 2 to 3, days 4 to 6 and day 7, what does the player do, receive and get asked, and does each ask follow guide 01?
10. Which day unlocks the meta layer, which day holds the first weekly event, and which reward anchors day 7?
11. How many days of content sit ahead of the fastest cohort, and who ships the next drop (interview 7)?
12. Which answer fails a guide 06 test, and what changes?

## Default path

1. Take the answer to interview 1 and start from its row in the archetype table; do not mix archetypes at launch.
2. Answer worksheet questions 1 to 4 and write the hook sentence into the project contract.
3. Draw one session as a beat sheet (questions 5 to 8) and check it against the four-layer loop of guide 01.
4. Write the reward cadence as fixed, variable and appointment. Objectives belong to guide 08, in-session staying power and lapsed-player recovery to guide 09.
5. Write the day 0 to day 7 script (questions 9 and 10) and tie each ask to its trigger in guide 01. `engagement.daily-streak` carries the daily reward and `engagement.objectives` the goals the script hands out.
6. Set the content calendar from interview 7 (question 11); `engagement.event-calendar` runs it, and `messaging.push-reengagement` joins once the notification soft ask works.
7. Run the three tests of guide 06 on every pull and anchor reward (question 12).
8. Fire one event per beat and per script step (guide 12) and compare the script with D1 and D7 from the soft launch (guide 05).

## Gaps

- No source gives a causal effect size for any hook, for the Hook Model or for a rhythm choice (reward schedule, easy beat, cadence); every pattern here is what top games ship or what a practitioner advises.
- No source sets a target session length or session count by archetype. The two GameAnalytics summaries disagree on top-quartile session length and carry no genre split, and the primary reports were not opened.
- Fixed versus variable schedules rest on 2001 behavioral theory and one critic; no game experiment compares them, and none covers week one.
- No published win-rate or difficulty-curve target survived sourcing; King's account is a news report of a talk about one game.
- First-week scripts for idle, character-collector RPG and 4X rest on one designer's model, one postmortem and fan guides (LOW). No teardown was found, and the first-week table is practitioner judgment plus this kit's synthesis.
- Nothing was found on story as a hook, on early timer lengths for 4X, or on how content cadence relates to retention; the Sensor Tower counts describe top-grossing casual games and are scale, not targets.

## Checklist

- [ ] The hook sentence exists and names an opening promise, a session pull and one long-term hook.
- [ ] The first minutes deliver what the ad shows (concept test, guide 05).
- [ ] One session is drawn as a beat sheet with a peak, a release, a stopping point and a reason to return.
- [ ] Each reward is marked fixed, variable or appointment, and no bought random reward lacks the guide 06 floor.
- [ ] Difficulty and fun are measured separately, and an easy beat follows the hardest round.
- [ ] The day 0 to day 7 script lists what the player does, receives and is asked, and every ask follows guide 01.
- [ ] The content calendar matches interview 7, with content ahead of the fastest cohort.
- [ ] Session length and session count are targets from the soft launch, not from a benchmark table.
- [ ] Every pull and anchor reward passed the three tests of guide 06.
