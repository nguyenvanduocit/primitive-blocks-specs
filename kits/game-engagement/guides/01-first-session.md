# First Session

Most players decide within the first minutes whether the game is for them. This guide covers the core loop, the script of the first session, and the requests (account, ads, notifications, rating) that must wait until the player has had fun.

Evidence: sources are named inline with HIGH, MEDIUM or LOW. The advice is consistent across sources; the effect sizes are not measured anywhere (see Gaps).

## Decision rule

1. **Build the core loop first.** A core loop is the short action, reward, progress cycle the player repeats. The minimal stack that fits every source has four layers: an action with instant feedback, a reward on every cycle, a visible next goal outside the loop (level, upgrade, unlock), and a reason to return later (timer, event, daily reward). That stack is this kit's synthesis (MEDIUM). Hyper-casual games have only the first one or two layers; hybrid-casual adds the third, a simplified meta layer ([Voodoo interview](https://www.pocketgamer.biz/interview/77247/corentin-selz-voodoo-from-hypercasual-to-hybrid-casual/), MEDIUM, page not read: seen as a search snippet). One 2026 guide says the meta layer should be the main reason to relaunch the app by the third to fifth day ([Game Growth Advisor](https://gamegrowthadvisor.com/blog/2026-04-16-hybrid-casual-game-design-strategy-2026/), MEDIUM, seen as a search snippet).
2. **Show why the game is fun within the first couple of minutes.** Teach by doing and let the tutorial end in a success ([GameAnalytics](https://gameanalytics.com/blog/tips-for-a-great-first-time-user-experience-ftue-in-f2p-games), HIGH that this is the advice, MEDIUM on the timing, which is advice and not data). Introduce one mechanic at a time ([Supersonic](https://supersonic.com/learn/blog/optimizing-ftue/) and [Adrian Crook, 2015](https://adriancrook.com/?p=4922), MEDIUM); a game that introduced mechanics too fast lost most of its tutorial players (Supersonic, LOW as a benchmark: one case). Small rewards for finishing tutorial steps are common practice and rest on vendor search summaries (LOW to MEDIUM).
3. **Delay every request that adds friction.** No forced account, ad, paywall, rating prompt or notification permission before the player has felt the fun. For notifications show an explanation screen first and ask when the benefit is obvious (for a timer game, the first time a timer starts on a valuable resource; [Adrian Crook, 2015](https://adriancrook.com/?p=4922), MEDIUM on the logic, old source), because the iOS system dialog appears once per install ([Iterable](https://iterable.com/blog/when-to-request-permission-to-send-push-notifications/), MEDIUM). The iOS rating prompt is limited to three showings a year ([Apple Developer Forums](https://developer.apple.com/forums/thread/115193), MEDIUM, secondary).
4. **End onboarding with goals at three ranges.** Low early XP thresholds make the first level-ups fast, and the last tutorial step hands the player a short, a medium and a long goal ([Roblox Creator Docs](https://create.roblox.com/docs/production/game-design/onboarding), MEDIUM, platform-specific). Gift a currency that buys a meaningful upgrade: it rewards the player and teaches how spending works (GameAnalytics, as above).
5. **Measure the tutorial as a funnel.** Fire an event per tutorial step so the drop-off point is visible ([GameAnalytics](https://gameanalytics.com/blog/tips-for-a-great-first-time-user-experience-ftue-in-f2p-games), HIGH as advice).
6. **Set retention targets from your own soft launch, using public numbers as scale only.** Day-1, day-7 and day-30 retention are the shares of installers who return on those days. GameAnalytics data for 2025 (16,262 games) puts the all-genre median near 22% on day 1, just under 4% on day 7 and about 0.7% on day 30; the top 10% of games reach about 40%, 11 to 12% and about 4% ([summary of GameAnalytics](https://gamedevreports.substack.com/p/gameanalytics-mobile-and-pc-game), HIGH as reported; the primary report was not opened and the summary may be sponsored). Adjust reports 27% on day 1 for 2025 ([Adjust via GameDev Reports](https://gamedevreports.substack.com/p/adjust-gaming-app-insights-report), MEDIUM); the datasets measure different populations and do not reconcile. Published genre tables contradict each other by large factors (RPG day-30 retention appears as 3.5% and as 15 to 25%), so do not adopt one.

Why players leave in the first week clusters into four groups: fun arrives late, friction before play, difficulty or bugs, and an ad that does not match the game. The best list is a 2015 opinion piece ([Game Developer](https://www.gamedeveloper.com/design/16-reasons-why-players-are-leaving-your-game), MEDIUM as current guidance), and no source ranks the causes with data.

## Default path

1. Write the loop as the four layers above, in one paragraph in the project contract.
2. Script the first session: one mechanic per step, an early win, a reward per step, an end state with three goals.
3. Hide every ask (account, ad, rating, notification permission, offer) behind a trigger that fires after the first win.
4. Add one event per tutorial step and one at the first return.
5. Gift the starting currency so it buys one meaningful upgrade in the first session.
6. Run the soft launch (guide 05) and set the retention gates from its numbers.

## Gaps

- No tutorial length versus retention data, and no first-session drop-off benchmark by genre.
- No measured effect size for any early-game pattern (fast early level-ups, gifts, celebrations). Designers state the intent, not the result.
- No usable sources on first-session design for gacha, match-3, 4X or first-purchase offers.
- One snippet suggests an over-restrictive onboarding can lift day-1 retention while day-7 collapses because players are unprepared ([iGaming Business](https://igamingbusiness.com/?p=9760), LOW); judge onboarding on day-7, not day-1 alone.

## Checklist

- [ ] The four loop layers are written down and each is present in the build.
- [ ] The first win lands inside the first couple of minutes of play.
- [ ] No account, ad, paywall, rating or permission request appears before the first win.
- [ ] The notification permission has an explanation screen and a trigger tied to a visible benefit.
- [ ] The tutorial emits one event per step.
- [ ] Onboarding ends with a short, a medium and a long goal.
- [ ] Retention gates are taken from the soft launch, not copied from a genre table.
