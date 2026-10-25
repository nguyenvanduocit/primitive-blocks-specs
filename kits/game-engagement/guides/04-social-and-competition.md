# Social and Competition

Clans, friends, leaderboards and co-op events keep players longer in some genres and cost real money in all of them. This guide separates what is believed from what is measured and says how much social a small game should build.

Evidence: Naavik, a university thesis on two free-to-play games, practitioner writing, and research on matchmaking, named inline with HIGH, MEDIUM or LOW. No trustworthy retention multiplier exists for any social feature.

## Decision rule

1. **Do not plan on a published multiplier.** Blog figures such as "players with a friend retain three times better" or "guild joiners four times" trace to unsourced blogs, and a cited research paper argues raw gaps are inflated by self-selection, since engaged players join guilds (LOW). The strongest hard evidence is a 2019 thesis on two commercial free-to-play games: social-feature use in the first week was associated with higher day-30 retention in one game and not in the other ([University of Jyvaskyla](https://jyx.jyu.fi/handle/123456789/66822), MEDIUM on generalization: correlational, two games). A practitioner with 50 or more launches writes that players with at least one in-game connection churn more slowly in every title he has worked on, "though I have never seen a defensible published coefficient for it" ([Game Growth Advisor, 2026](https://gamegrowthadvisor.com/blog/2026-03-17-mobile-game-retention-strategies-2026/), MEDIUM).
2. **Start asynchronous.** Cohort leaderboards, asynchronous challenges and shared community milestones give social value without a large concurrent population (Game Growth Advisor, LOW to MEDIUM); ghost opponents are this kit's suggestion, not sourced. Most social features assume a player density that small titles lack (Game Growth Advisor, MEDIUM), and Naavik treats clans as costly late-game features ([Naavik](https://naavik.co/f2p-mobile/building-clan-features/), MEDIUM). No source gives a concurrent-player threshold.
3. **Match the social depth to the genre.** An RPG wants a guild hook early (churn risk sits in the first week), casino and tabletop games lean on competition from day one, and strategy games depend on alliance mechanics from about the second week (Game Growth Advisor, MEDIUM: the author calls it judgement from launches, not measurement). Casual puzzle games use lighter teams (a Royal Match comparison from [Esports.net](https://www.esports.net/news/mobile-games/royal-match-vs-royal-kingdom/), LOW).
4. **Understand obligation mechanics before copying them.** Clans work, per Naavik, through progression (clan level), return triggers (daily donation limits, clan events) and social obligation (event progress, item donations), and often lift cosmetic and VIP sales (HIGH that this is claimed, MEDIUM as evidence: expert opinion without data). Alliances in 4X games gate build help, buffs and event access, so leaving has a cost ([BlueStacks guide](https://www.bluestacks.com/blog/game-guides/white-out-survival/wos-alliance-guide-en.html), MEDIUM for the mechanic). The dark side is that a lapsing player now hurts the team (inference, unquantified).
5. **Treat hidden matchmaking tuning as unproven for mobile.** Choosing opponents by predicted churn instead of skill alone improved retained players by 0.3% to 1.1% in an Electronic Arts simulation ([arXiv 1702.06820](https://arxiv.org/pdf/1702.06820), MEDIUM). A study of 5.4 million Lichess games found that accounting for recent wins and losses raised engagement 4 to 6% over pure skill matching, and that a loss streak can push players to quit for the night ([Digital Trends](https://www.digitaltrends.com/gaming/gaming-study-says-skill-based-matchmaking-is-fair-but-it-also-quietly-drives-players-away/), MEDIUM on transfer to mobile). No source confirms that a specific mobile game ships it.
6. **Budget for the costs.** Clans raise server cost and complexity. A moderation-industry survey of 2,408 gamers found 19% spend less and 21% play less to avoid harassment ([Game Industry Library](https://gameindustrylibrary.com/documents/toxicity-and-the-bottom-line-2024), MEDIUM, industry-published, not mobile-specific). Naavik notes that bots can fake validation for an empty lobby but do not scale (MEDIUM); players reported boredom after a bot-balancing update in Warzone Mobile (anecdote, LOW).
7. **Do not count on virality.** The viral coefficient (invites per user times the share of invites that convert) is put at 0.3 to 0.5 as a realistic target by marketing blogs (one gives 0.3 to 0.7), enough to lower acquisition cost but rarely enough to grow alone ([Echai Ventures](https://echai.ventures/startingup/retention-referral/what-s-a-viral-coefficient-and-is-chasing-a-k-factor-above-1-realistic-for-my-kind-of-product), MEDIUM, generic app blogs; no game-specific K data exists).

## Default path

1. Take the answer to interview 6. The default is no social features at launch.
2. If the game needs a board or friends, use `ugc.friends-leaderboard`. It is a weekly and all-time leaderboard whose visibility the player can switch off, plus a private circle of friends added by a short code. New profiles are public by default and the default is configurable (`PUBLIC_BOARD_DEFAULT`), so choose it deliberately. The block assumes accounts, so `auth.google-login` or an equivalent existing login must be in place. Its progress numbers are reported by the device, which the block bounds but does not make cheat-proof.
3. If players have accounts, add `compliance.account-deletion`; deletion must remove the player's public board presence.
4. Add one asynchronous feature (shared goal or cohort board) before clans or chat.
5. Decide moderation, reporting and a block list before any free-text chat ships.

## Gaps

- No Royal Match team mechanics or Candy Crush social data; no sourced detail on trophy, season and tournament mechanics or win-rate tuning in shipped mobile games.
- No mobile-specific toxicity, cheating or moderation-cost data, and no cold-start threshold for concurrent players.
- No data on lives gifting or asynchronous play effects; Discord and Tencent retention figures are vendor-made and Discord's is from PC games.

## Checklist

- [ ] Social scope in the first release matches the player base the game can reach.
- [ ] No plan, forecast or pitch cites a guild or friend retention multiplier.
- [ ] Board visibility is player-controlled, the public-by-default choice is deliberate, and the board shows the minimum personal data.
- [ ] Account deletion removes public presence.
- [ ] Moderation and reporting exist before any free-text chat ships.
- [ ] A cold-start plan exists for a board or lobby with few players.
