# Return Reasons

The patterns that repeat across mobile games are reasons to come back, stacked at three time scales: today, this week, this season. This guide names each pattern, says which are must-have, which are expected once a game competes for grossing rank, and which belong to one genre.

Evidence: Sensor Tower, Naavik, Duolingo, a 2025 preprint on the 40 top mobile games in South Korea, and game-design essays. Each is named inline with HIGH, MEDIUM or LOW.

## Decision rule

1. **Cover three time scales, in this order of build.** Sensor Tower organizes top-grossing live operations (the schedule of events and offers run after launch) into recurring events (missions, check-ins, win streaks), feature events (battle passes, mini-games, treasure hunts) and large-scale events (seasonal events, competitions, alliance championships, collection systems) ([Sensor Tower, March 2026](https://sensortower.com/blog/top-grossing-mobile-games-live-ops-strategies-2025-report), HIGH). The words "daily", "weekly" and "seasonal" are this kit's reading of those layers. Kit recommendation: launch with the daily layer, add the weekly layer after the soft launch, add the seasonal layer only when a team can ship to a calendar, because a calendar that stops trains players to expect events that never come.
2. **Reward play, not opening the app.** A pure login reward pays for opening the game, which is why top puzzle games added the daily jackpot: a large daily prize the player must win levels to claim (Royal Match "Lava Quest"). Top casual puzzle games have converged on a daily jackpot, leaderboard events and endless album collections ([Naavik, Nov 2025](https://naavik.co/digest/live-ops-trends-powering-mobile-puzzle/), HIGH).
3. **Tier the features.** The placement is this kit's synthesis of the sources (MEDIUM).

   | Tier | Features |
   |---|---|
   | Must-have for almost any game | At least one reason to return tomorrow (daily reward, timer or event) |
   | Expected once the game competes for grossing rank | Layered live-ops events, a battle pass or equivalent, streaks, collections and albums, rewarded video at pain points (vendor-sourced and correlational, see guide 03), notifications behind a soft ask, asynchronous social features (see guide 04) |
   | Genre-specific | Prestige (idle); lives, endless albums, tournaments and a daily jackpot (casual puzzle); chest slots (battlers); gacha banners with pity (character-collector RPG); alliances and alliance wars (4X and survival) |

4. **Read the prevalence data as two archetypes, not one list.** In the 40 top Korean mobile games (the paper's selection criterion was not confirmed), daily login appeared in 38, loot boxes in 37, battle passes in 31, social features in 26, first-purchase benefits in 17 and time-gated progression in 9 ([arXiv 2504.10714](https://arxiv.org/html/2504.10714), MEDIUM). One country, a sample skewed toward gacha RPG and strategy, and the paper's text and table disagree by one game on time-gated progression. Hyper-casual games and puzzle games that use no gacha or loot boxes are underrepresented.
5. **Use timers and energy deliberately, and expect them to soften (inference from two cases, MEDIUM; no data on how many top games dropped hard gates).** Timers (lives in Candy Crush, chest slots in Clash Royale, build timers in Clash of Clans) are the oldest pacing tool. Royal Match gives unlimited lives as an event reward ([Sensor Tower, May 2026](https://sensortower.com/blog/what-royal-matchs-calendar-teaches-about-live-ops-in-2026), HIGH), and Supercell tested instant and day-long chests with total reward value held constant, for King Tower levels 1 to 9 ([Supercell, Jan 2025](https://supercell.com/en/games/clashroyale/blog/news/chest-experiment-king-tower-levels-1-9), HIGH).
6. **Treat notifications as an amplifier.** They strengthen appointment hooks and do not replace them (kit recommendation). Android 13 made notification permission opt-in and vendors report lower opt-in as a result; every opt-in figure comes from a notification vendor (LOW).

## Pattern catalog

| What the player sees | Industry name | Example | Evidence |
|---|---|---|---|
| A calendar of gifts for opening the game | Daily login reward | 38 of 40 top Korean games | [arXiv](https://arxiv.org/html/2504.10714), MEDIUM |
| A daily prize won by playing | Daily jackpot | Royal Match "Lava Quest" | [Naavik](https://naavik.co/digest/live-ops-trends-powering-mobile-puzzle/), HIGH |
| A counter of consecutive days you can lose | Streak | Duolingo (an education app) | [Duolingo](https://blog.duolingo.com/improving-the-streak), HIGH |
| A chest or building that opens after hours | Time-gated progression | Clash Royale chests | [Supercell](https://supercell.com/en/games/clashroyale/blog/news/chest-experiment-king-tower-levels-1-9), HIGH |
| Hearts that refill slowly | Lives | Candy Crush Saga | [Candy Crush Wiki](https://candycrush.fandom.com/wiki/Lives), MEDIUM |
| A monthly track with free and paid rewards | Battle pass | Clash of Clans Gold Pass | [GameAnalytics](https://www.gameanalytics.com/blog/designing-battle-passes-in-mobile-games-the-whats-whys-and-hows), MEDIUM |
| A sticker or card book you complete | Collection, endless album | Monopoly Go; Royal Match Culinary Collection | [Naavik](https://naavik.co/digest/live-ops-trends-powering-mobile-puzzle/), HIGH; [Sensor Tower, May 2026](https://sensortower.com/blog/what-royal-matchs-calendar-teaches-about-live-ops-in-2026), HIGH |
| Random pulls with a guaranteed prize after N tries | Gacha with pity | Genshin Impact | [RPG Site, 2020](https://www.rpgsite.net/feature/10312-genshin-impact-wish-system-gacha-rates-banners-and-the-pity-mechanic-explained), MEDIUM |
| Reset everything for a permanent multiplier | Prestige | Cookie Clicker | [Game Developer, 2017](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii), HIGH |

Details worth knowing:

- Duolingo's A/B test that separated the daily goal from the streak raised relative day-14 retention by 3.3%, and users with a 7-day streak were 2.4 times more likely to return the next day, a correlation that does not prove the streak caused it ([Duolingo, 2020](https://blog.duolingo.com/improving-the-streak), HIGH as reported). It is the only primary-source streak experiment found, and it is not a game.
- Endless albums removed the content ceiling that caused boom-and-bust engagement, at the price of a perpetual reward source; Royal Match offset it with a cut of roughly 30% in coin rewards from level completions ([Naavik](https://naavik.co/digest/live-ops-trends-powering-mobile-puzzle/), HIGH).
- Prestige exists for two stated reasons: a ladder-climbing feeling of power, and a way to bring ever-growing numbers back to a manageable scale ([Game Developer, 2017](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii), HIGH).
- A pity counter bounds an otherwise unbounded random spend, so it is both a trust feature and a regulatory shield (inference, MEDIUM). Gacha numbers circulating for "soft pity" are community estimates (LOW).

## Gaps

- No game publisher quantifies the retention or revenue lift of daily login, energy, battle passes or events. The only measured streak experiment is Duolingo's, and it is not a game. The sizes above describe what top games ship, not measured effects.
- Comeback-bonus reactivation rates have no benchmark data.
- Levels, XP, skill trees, achievements and mastery returned only low-quality sources and are left out.
- Unsourced figures that circulate widely (energy as a third of bookings, a retention multiplier for weekly live ops, a retention lift for pass holders) are not used.

## Checklist

- [ ] At least one reason to return tomorrow is in the first release.
- [ ] The daily layer rewards play, not only opening the app.
- [ ] The weekly and seasonal layers match a calendar the team can keep.
- [ ] Every genre-specific feature chosen belongs to the game's archetype (interview 1).
- [ ] Timers and energy have a stated purpose and an owner for tuning.
- [ ] Notifications have an explanation screen and a trigger tied to a visible benefit.
