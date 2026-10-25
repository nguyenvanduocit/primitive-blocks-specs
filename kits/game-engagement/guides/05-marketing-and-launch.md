# Marketing and Launch

Marketing buys installs; it pays off only if the game then retains and monetizes them. This guide covers the unit economics, the test sequence before and after launch, why game ads look alike, and what privacy rules changed.

Evidence: Adjust, AppsFlyer, Liftoff, Unity and practitioner guides, named inline with HIGH, MEDIUM or LOW. Most benchmarks come from vendors that sell advertising, attribution or analytics tools; treat them as scale, not targets.

## Decision rule

1. **Know the funnel terms and the one inequality.** The funnel runs: ad impression (priced per 1,000 views, CPM) to click (CTR) to install (priced as CPI, cost per install) to day-1, day-7 and day-30 retention to revenue (LTV, lifetime revenue per installed player). ROAS is revenue divided by ad spend, and payback is the time until a cohort's revenue equals what it cost to acquire. A game scales only if LTV beats CPI by enough margin.
2. **Scale of cost, for orientation.** Adjust's data for the top 5,000 apps (January 2024 to January 2026) shows a global average CPI of $0.56, with North America at $1.68, Europe at $0.53 and Latin America at $0.14; about three installs are paid for each organic install ([Adjust via GameDev Reports](https://gamedevreports.substack.com/p/adjust-gaming-app-insights-report), MEDIUM, secondary summary). Gaming user-acquisition spend was about $25B in 2025 ([AppsFlyer](https://www.appsflyer.com/company/newsroom/pr/gaming-marketing/), HIGH). Average day-30 ROAS for casual games (hyper-casual included) is 47% on iOS versus 15% on Android, for February 2024 to February 2025 ([Liftoff 2025 Casual Gaming Apps Report](https://liftoff.ai/?p=34267), MEDIUM, vendor with a large dataset).
3. **Test the concept before building.** Run an ad video as paid ads and measure CPI and installs per 1,000 impressions (IPM). Then run a soft launch (a trial release in one or two cheaper markets) where day-1, day-7 and day-30 retention and LTV versus CPI act as go or no-go gates, then a scale test that checks CPI does not jump when spend rises. Practitioners agree on this order but not on thresholds: the gate numbers that circulate do not agree, and two versions attributed to one advisor page differ, one of them seen only through a search summary ([Game Growth Advisor](https://gamegrowthadvisor.com/blog/2025-12-16-mobile-soft-launch-complete-guide/), LOW). The hyper-casual CPI targets of 2020 and 2021 do not transfer to 2026 midcore markets ([Unity](https://unity.com/resources/growing-hyper-casual-games), MEDIUM, old). Write the gates down before spending, from your own unit economics.
4. **Know why game ads look alike, and keep them honest.** Ad platforms (Meta, Google, TikTok, AppLovin, Unity, Mintegral, Moloco) optimize targeting themselves, so the creative does most of the work. Top gaming advertisers produced 2,400 to 2,600 creative variations per quarter, up 25 to 30% ([AppsFlyer](https://www.appsflyer.com/company/newsroom/pr/gaming-marketing/), HIGH), and one secondary report says the top 2% of creatives took 53% of spend ([AppSamurai](https://appsamurai.com/blog/how-to-market-test-a-mobile-game/), MEDIUM). Unity advises showing a "fail" in the first seconds of a hyper-casual ad ([Unity](https://unity.com/resources/growing-hyper-casual-games), MEDIUM, publisher claim, undated). An ad that does not reflect the game is a risk: Google Play bans ads that do not accurately reflect the app, and the UK advertising regulator has acted against game ads ([Segwise](https://segwise.ai/blog/fake-ads-and-mobile-gaming-how-studios-balance-clickbait-gameplay-integrity-and-profitability-cm7j2hc9s00bvip0l0r4k59lw), LOW). Kit recommendation: show only what the game contains, because a mismatched ad also counts among the churn causes in guide 01.
5. **Use the cheap levers, and treat their evidence as thin.** A store-page icon test lifted one game's conversion from 20.46% to 24.42% ([SplitMetrics case](https://splitmetrics.com/cases/ciliz-improves-conversion-with-splitmetrics-agency/), LOW, vendor marketing). Google Play pre-registration with a reward raised the share of pre-registrants who installed by 20% in one 2019 Nexon case ([Google Play Console case study](https://play.google.com/console/about/nexon-casestudy/), MEDIUM). Apple and Google both run featuring nominations with weeks of lead time ([Apple Developer](https://developer.apple.com/contact/app-store/promote/), HIGH for the process).
6. **Do not mistake buzz for retention.** Supercell's Squad Busters drew about 3.2B TikTok views in six weeks (a creator-distribution vendor's claim, LOW; [Game World Observer](https://gameworldobserver.com/2024/06/19/squad-busters-revenue-28-million-paid-ads-supercell), June 2024). Per Deconstructor of Fun estimates, about $150M in total cost, and the game shut down on 30 October 2025 ([WN Hub summary](https://wnhub.io/ru/news/games/item-49267), MEDIUM, analyst estimates, original not retrieved).
7. **Plan measurement for the privacy era.** About 38 to 39% of gaming users accepted Apple's App Tracking Transparency prompt in Q1 2025 and Q1 2026 ([Adjust via GameDev Reports](https://gamedevreports.substack.com/p/adjust-gaming-app-insights-report), MEDIUM). The rest are measured through aggregated, delayed Apple postbacks (SKAdNetwork, now AdAttributionKit), so iOS cohort revenue is partly modeled. Google announced in October 2025 that it would retire most Privacy Sandbox technologies, ([PPC Land](https://ppc.land/chrome-kills-most-privacy-sandbox-technologies-after-adoption-fails/), MEDIUM). The Android advertising ID had not been deprecated as of March 2026 ([Moburst](https://www.moburst.com/blog/mobile-attribution-in-2026-what-marketers-actually-need-to-know/), MEDIUM). Use a mobile measurement partner (AppsFlyer, Adjust, Singular).
8. **Treat re-engagement as a separate program.** Push, email and retargeting ads target lapsed players with escalating comeback offers by dormancy segment. The evidence is almost entirely from tool vendors and there are no controlled win-back uplift numbers (LOW).

## Vietnam and Southeast Asia

- Vietnam's mobile game revenue was about $825M in 2025 with roughly 54M gamers, of whom only 7 to 10% spend ([PocketGamer.biz](https://www.pocketgamer.biz/vietnams-mobile-games-market-reached-825m-in-revenue-in-2025), MEDIUM, read through a search summary).
- Sensor Tower's Q1 2025 data puts Vietnam at 329M installs, with 4X strategy and MMORPG leading revenue ([Sensor Tower via GameDev Reports](https://gamedevreports.substack.com/p/sensor-tower-southeast-asia-mobile?open=false), MEDIUM).
- One author's estimate puts Android casual CPI at $0.20 to $0.60 in Southeast Asia and $0.08 to $0.30 in India ([Game Growth Advisor](https://gamegrowthadvisor.com/blog/2025-12-16-mobile-soft-launch-complete-guide/), LOW).
- Kit recommendation, unsourced: run concept tests and the soft launch in a low-CPI Southeast Asian market plus one English-speaking market rather than the US, and expect local-payment channels to matter more than the global average because few players pay.
- Vietnam-specific CPI, retention and ARPU benchmarks, and the role of Zalo or Facebook as game ad channels, were not found.

## Default path

1. Make several distinct ad concepts for the game idea (kit recommendation, no sourced count) and run a paid concept test for CPI and IPM (interview 9).
2. Build only if the concept clears a CPI gate written beforehand.
3. Soft-launch in the markets from interview 8 with an attribution partner installed; compare day-1, day-7 and day-30 retention and LTV versus CPI against the written gates.
4. Scale in steps and watch CPI at each step.
5. Prepare store assets, a pre-registration page and a featuring nomination in parallel with the soft launch.
6. Set up notification, email and retargeting segments for lapsed players once the first cohorts exist.

## Gaps

- No primary CPI table by genre and region; the genre-by-region figures that circulate are one practitioner's estimates.
- No Moloco or Mintegral data, no UGC-ad data, and no AI-creative win-rate data. The original Mobile Dev Memo, Deconstructor of Fun and Sensor Tower State of Mobile reports were not retrieved, so anything from them is second-hand.
- Two soft-launch gate sets attributed to one author do not match, though one was seen only through a search summary and may be wrong; ATT opt-in appears as 38 to 39% (Adjust) and "as low as 14%" (undated, one vendor); the retention and cost numbers circulating about "fake gameplay" ads trace to one vendor blog and are not used.

## Checklist

- [ ] CPI, ROAS and payback gates are written down before the first paid test.
- [ ] A concept test ran before full production.
- [ ] The soft launch has an attribution partner, named markets and written retention gates.
- [ ] Ad creatives show only content that exists in the game.
- [ ] Measurement plan covers the Apple opt-in rate and modeled iOS revenue.
- [ ] A re-engagement program exists for lapsed players, with segments by dormancy.
