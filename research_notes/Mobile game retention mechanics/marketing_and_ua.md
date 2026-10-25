# Mobile game marketing, user acquisition (UA) and growth

Research date: 2026-10-22. Confidence labels: HIGH = primary or named-methodology source with a date; MEDIUM = reputable secondary source, or a vendor report with a stated methodology; LOW = vendor blog, unsourced figure, or the search tool's summary that I could not verify against the page. Many "benchmarks" on the web come from vendors selling UA, ASO or analytics tools, so each is labelled with its type.

Glossary for a non-developer reader (definitions are standard industry usage; no source needed): CPM = cost per 1,000 ad impressions. CTR = share of viewers who click. CPI = cost per install. IPM = installs per 1,000 impressions. D1/D7/D30 = share of installers who return on day 1/7/30. ARPDAU = average revenue per daily active user. LTV = lifetime revenue per installed player. ROAS = revenue divided by ad spend (D7 ROAS = revenue in the first 7 days divided by spend). Payback = days until cumulative revenue from a cohort equals what it cost to acquire it.

---

## 1. Funnel and unit economics: CPI, CPM, CTR, retention, LTV, ROAS, payback by genre and region

### Takeaway
The funnel is: ad impression (CPM) -> click (CTR) -> install (store conversion) -> D1/D7/D30 retention -> revenue (LTV). A game is only scalable when LTV exceeds CPI by a margin, and CPI rose in 2025 in every major Western region. The most credible regional CPI data (Adjust, Jan 2024-Jan 2026) shows North America about 3x Europe and about 12x LatAm; ROAS "targets" differ widely between sources, so the only dependable rule is "payback inside your cash window, tested against your own cohorts".

### Cited Findings
**Global/regional CPI, CPM, IPM (Adjust, top 5,000 apps, data Jan 2024-Jan 2026, published Apr 15 2026) - MEDIUM-HIGH (large dataset, but read through a secondary summary, not the PDF itself)**
- Global average CPI $0.56 (+30% YoY). Europe $0.53 (up 47% from $0.36); LATAM $0.14 (+40%); North America $1.68 (up 31% from $1.28). — [GameDev Reports summary of Adjust Gaming App Insights 2026](https://gamedevreports.substack.com/p/adjust-gaming-app-insights-report)
- CPI by genre: Slots $4.47, Idle RPG $3.19, Strategy $1.03; CPI fell for Casino and Family. — same source
- Average CPM $4.34 (+20% from $3.63); North America $15.98; Casino and Slots near or above $12. Average CPC $0.04. — same source
- Global IPM 8.62 (8.59 in 2024); Racing 16.2; Casino 5.13. — same source
- Median paid-to-organic install ratio rose from 2.07 to 3.33 (+61%), i.e. about 3 paid installs per organic one. By country: Brazil 5.32, Turkey 4.28, India 3.81, US 3.53. — same source
- Adjust did not report ROAS in this report, and did not mention AI creative (per the page extract). — same source

**Spend and mix (AppsFlyer State of Gaming for Marketers 2026, published Jan 14 2026; 9.6K gaming apps, 24.8B installs, 14.1B paid) - HIGH**
- Global gaming app UA spend $25B in 2025 (+3.8% YoY); nearly half in the US, where budgets fell 5%; fastest growth Turkey (+29%), India (+19%). Paid install share +10%, ad impressions +20%. — [AppsFlyer press release](https://www.appsflyer.com/company/newsroom/pr/gaming-marketing/)
- China-headquartered publishers held 35% of global gaming UA spend outside China (their share +22% YoY). — same source
- Android paid share 59% vs 44% on iOS; casual games held over 50% of spend. — [ContentGrip summary of the AppsFlyer/Newzoo report, Jan 29 2026](https://www.contentgrip.com/gaming-marketing-trends-report/) (MEDIUM: secondary)

**iOS vs Android and genre ROAS (Liftoff 2025 Casual Gaming Apps Report, article dated Jul 28 2025; data 2024) - MEDIUM-HIGH (vendor with large dataset)**
- Average D30 ROAS for casual games: iOS 47% vs Android 15%. iOS D30 ROAS by genre: Sports 80%, Kids 68%, Strategy 60%; Android: Sports 21%, Strategy 27%, Kids 8%. Simulation, Action and Racing have roughly 10x higher CPI on iOS than Android. — [Liftoff](https://liftoff.ai/?p=35032)
- About half of casual game installs come from hyper-casual and puzzle game ads; more than half of installs from non-gaming publishers come from utility/productivity and entertainment apps. — same source

**Retention baselines**
- D1 retention across all genres 27% in 2025; family games 23%; Japan about 25% (highest country); top games 40-50%+. Day-zero sessions 1.65. — [GameDev Reports summary of Adjust 2026](https://gamedevreports.substack.com/p/adjust-gaming-app-insights-report) (MEDIUM-HIGH)
- Practitioner "launch-ready" bands are higher than the all-game average: D1 35-50%+, D7 15-25%+, D30 5-15%+ — [MWM glossary](https://mwm.ai/glossary/soft-launch) (LOW-MEDIUM, vendor/publisher glossary). Another vendor gives a "good" profile of 35/15/5 (D1/D7/D30) as of July 2026 — [Playio](https://blog.playio.co/d1-d7-d30-retention-benchmarks-2026) (LOW, via search summary).
- A pooled-dataset caveat: GameAnalytics' 2025 benchmark pools 11,600 games and yields much lower D7 medians than datasets of commercially scaled, UA-funded titles — [AppAgent, via search summary](https://appagent.com/?p=61637) (LOW-MEDIUM).

**Soft-launch CPI ranges, Android casual/puzzle (Game Growth Advisor, Dec 16 2025; author's operating estimates, not a dataset) - LOW-MEDIUM**
- US $1.50-3.50; UK/CA/AU $1.00-2.50; Western Europe (FR, DE) $0.60-1.50; LatAm (Brazil, Mexico) $0.15-0.60; Southeast Asia $0.20-0.60; India $0.08-0.30 ("volume only, weakest LTV transfer"). For iOS apply a 3-4x multiplier. — [Game Growth Advisor](https://gamegrowthadvisor.com/blog/2025-12-16-mobile-soft-launch-complete-guide/)

**ROAS and payback targets (sources disagree) - LOW-MEDIUM**
- Breakeven ROAS = 1 / margin (a 70% margin gives about 1.43x). Teams track D1/D3/D7/D14/D30/D60/D180 ROAS and use D7 to predict later days. — [Unity "What is ROAS"](https://unity.com/resources/what-is-roas) (via search summary)
- Playio (2026): IAP-centric games D7 ROAS 15-40%; F2P about 15-25% at D7 and 40-60% at D30; ad-monetized casual median D7 near 7-8%. Linkrunner: hyper-casual ad-based often target 0.8-1.0x D7, mid-core IAP 0.3-0.5x D7. MWM: F2P D7 15-25% with full payback around D90-D180; hyper-casual often needs D1-D7 payback. — [Playio](https://blog.playio.co/d7-roas-benchmarks-mobile-games), [MWM payback](https://mwm.ai/glossary/payback-period) (all via search summary)
- Practical example: CPI $1.50 vs projected value by day 200 of $2.25 is used as an illustrative LTV check; predictive LTV is built from 7-14 days of early behaviour. — [CAS.AI, Apr 2026 (publisher marketing, illustrative)](https://cas.ai/blog/the-mobile-game-publishing-reality-why-most-indies-fail-and-what-actually-works/) (LOW)
- Soft-launch rule: CPI should be 30-50% of LTV to "go", 50-70% to "extend", at or above LTV to "kill" (equivalent to LTV:CPI of about 1.4x-3.3x). — [Game Growth Advisor](https://gamegrowthadvisor.com/blog/2025-12-16-mobile-soft-launch-complete-guide/) (LOW-MEDIUM, author's convention)

### Inferences
- A beginner can read the Adjust numbers as: a typical Western install costs $0.50-1.70 and a typical D1 is about 27%. Only a minority of installers are still around at D7, so the average player must produce far more than the CPI from a small paying fraction. This is the economic reason every game uses the same pattern (see Section 2 and the CRM section).
- The paid:organic ratio of about 3:1 (and above 5:1 in Brazil) means most installs are bought, not found; organic work (Section 3) is a multiplier on paid, not a replacement.
- Because CPI is up while the all-genre average D1 is flat, margins for small or generic games are shrinking; this explains the shift to hybrid IAP+ads monetisation (30% of games per ContentGrip/AppsFlyer, MEDIUM) and to D2C web shops (Section 7).

### Gaps
- No clean published CPI table by genre x region from a primary source; Adjust's genre-by-region tables were not accessible (only headline figures from a secondary summary). The soft-launch CPI ranges above are one practitioner's estimates.
- No reliable published ROAS targets by genre/region; sources disagree (see above). No Adjust or AppsFlyer ROAS figure was found for 2025.
- Contradiction: all-genre D1 of 27% (Adjust) versus "good" D1 of 35%+ (vendor blogs) is partly a definition issue (average of all games vs. commercially scaled games); the sources do not reconcile it.
- Playio's Oct 10 2025 CPI-trends article gave direction only (no figures) for the regional/genre split. — [Playio](https://blog.playio.co/2025-mobile-game-cpi-trends)

---

## 2. Paid UA channels and creative testing

### Takeaway
Paid UA is dominated by self-optimising ad platforms (Meta, Google, TikTok, AppLovin, Unity, Mintegral, Moloco), where the creative itself does most of the "targeting", so teams produce thousands of ad variants and keep the top few. Fake-gameplay and "fail" ads exist because they win on cheap installs; evidence on whether they hurt downstream quality is mostly weak vendor data, though the platforms and regulators have started to push back.

### Cited Findings
**Channel landscape**
- Eric Seufert's argument (as summarised by RocketShip HQ, not the original): after ATT, deterministic audience targeting became a relic; advertisers should hand targeting to the platform algorithm and invest in creative. Meta's 2025 changes default app-promotion campaigns to the Advantage+ automation setup (1 campaign, 1 ad set, multiple ads). RocketShip cites roughly 50 conversion events per ad set per week to leave the learning phase (agency figure, not from Meta). — [RocketShip HQ](https://www.rocketshiphq.com/?p=5541), [Meta developer docs](https://developers.facebook.com/docs/app-ads/advantage-app-campaigns), [Bïrch](https://bir.ch/blog/meta-mobile-ad-tools) (MEDIUM; search-summary only, original Mobile Dev Memo post was not retrieved)
- AppLovin: one Chinese analysis (Sep 2025) credits it with about 28% of in-game advertising (AdMob 27%, Unity 12%); Barchart estimates gaming clients' spend on AppLovin at a roughly $10B annual run rate, crediting Axon 2. MAX, Unity LevelPlay and AdMob controlled over 90% of the mediation market in 2025 (mediation = ad monetisation, not UA). — [36kr](https://www.36kr.com/p/3480808267798659), [Barchart](https://www.barchart.com/story/news/32724079/axon-2-drives-applovin-s-advertising-surge-and-gaming-ecosystem) (LOW-MEDIUM)
- Non-gaming publishers are a large install source: over half of non-gaming-publisher installs for casual games come from utility/productivity and entertainment apps, about 25% from social/photo/video. — [Liftoff 2025](https://liftoff.ai/?p=35032) (MEDIUM-HIGH)
- iOS advertisers use about 15% more media sources than Android; casino titles 6-6.5 sources at large scale and 8-10+ at the top; hyper-casual is the most consolidated genre. — [ContentGrip](https://www.contentgrip.com/gaming-marketing-trends-report/) (MEDIUM)
- Adjust: average ad partners per app fell from 6 to 5.3. — [GameDev Reports / Adjust](https://gamedevreports.substack.com/p/adjust-gaming-app-insights-report) (MEDIUM-HIGH)

**Creative volume and concentration**
- Top gaming advertisers (over $4M/quarter) produce 2,400-2,600 creative variations per quarter (+25-30% YoY); mid-tier ($0.5-1M) stagnate unless above 1,000 creatives; advertisers under $500K grew output 20-40%. — [AppsFlyer](https://www.appsflyer.com/company/newsroom/pr/gaming-marketing/), [ContentGrip](https://www.contentgrip.com/gaming-marketing-trends-report/) (HIGH / MEDIUM)
- In gaming the top 2% of creatives accounted for 53% of ad spend (AppsFlyer 2025 report, cited by AppSamurai). — [AppSamurai, Aug 25 2026](https://appsamurai.com/blog/how-to-market-test-a-mobile-game/) (MEDIUM; second-hand)
- Publisher-scale capacity (unsourced claim from a publisher selling services): 30-40+ motion designers, 50-100 video variants per game per month, 2-3 "winners" per batch with CTR above 20%, publishers' CPI 10-20% lower and indie CPI 10-20% higher. — [CAS.AI](https://cas.ai/blog/the-mobile-game-publishing-reality-why-most-indies-fail-and-what-actually-works/) (LOW)

**Creative formats**
- Playable ads: Liftoff's 2025 Mobile Ad Creative Index (as cited by Innowise/Segwise) reports 16x higher impression-to-install rates for non-top spenders and 8x for the biggest advertisers. AppAgent/Apptica data cited by Segwise says AppLovin carried 59% of playable traffic share and 84% of new playable experiments; Unity Ads 2%. — [Segwise AI stats](https://segwise.ai/blog/ai-game-marketing-ua-statistics-2026.md), [Innowise](https://innowise.com/blog/playable-ads/) (LOW-MEDIUM; vendors citing vendors). Claims that playable-acquired users retain "2-5x" better are unsourced (LOW).
- "Fail" concept: Unity's hyper-casual guide advises 4 creative versions at the marketability stage, with at least one showing a fail in the first 3-4 seconds; it says 70-80% of Supersonic's most successful creatives showed a fail situation; the first 3-5 seconds matter most. — [Unity, Growing hyper casual games](https://unity.com/resources/growing-hyper-casual-games) (MEDIUM; publisher claim, undated)
- Liftoff recommends testing "Fail", "Noob to Pro" and "Fake" playable concepts and letting each channel's algorithm judge. Hyper-casual captions such as "only 1% can solve this" are common. — [Liftoff](https://liftoff.io/?p=23967) (LOW-MEDIUM, via search summary)
- Test meaningfully different "game promises", not cosmetic edits; evaluate attention (CTR, IPM), intent (click-to-install), product response (tutorial completion, D1) and economics (early ROAS) together; AppSamurai explicitly advises against a single CPI threshold as a universal kill criterion. — [AppSamurai](https://appsamurai.com/blog/how-to-market-test-a-mobile-game/) (MEDIUM)

**Why ads often do not look like the game (and the cost)**
- Incentive: fake ads can cut CPI 40-60% (from $2.50-3.00 to $0.80-1.20 per install). Same article claims D1 retention of 14% for fake-ad cohorts vs 32% for true-gameplay playables, D7 1.5% vs 11%, LTV $0.05 vs $0.25, 26% immediate uninstall. Most figures are unsourced or traced to one blog (ExpertBeacon). — [Segwise, Feb 24 2025](https://segwise.ai/blog/fake-ads-and-mobile-gaming-how-studios-balance-clickbait-gameplay-integrity-and-profitability-cm7j2hc9s00bvip0l0r4k59lw) (LOW; vendor blog, unverified numbers)
- Enforcement/pushback: Google Play ad guidelines (Aug 2022) ban ads that do not accurately reflect the app; the UK ASA took action against Playrix ads (date not given); Supercell's marketing director called misleading ads "a race to the bottom". — same Segwise article (LOW-MEDIUM; second-hand)
- Academic note: Gardenscapes and similar titles advertise gameplay unlike the actual puzzle game yet passed 100M downloads. — [NSF-hosted paper](https://par.nsf.gov/servlets/purl/10552301), [Apptica](https://apptica.com/blog/misleading-ad-in-mobile-games-playrix-metchington-mansion-mafia-city/) (MEDIUM, via search summary)

**Incentivized traffic**
- Vendors (Unity) say offerwalls often raise retention; a LinkedIn post attributes "2-7x higher retention" to Unity data (unverifiable). Risks: reward-driven players churn after rewards run out; fraud; Apple's App Store rules prohibit incentivized installs inside iOS apps, so this is mainly an Android tactic. A 2011 W3i dataset showed 30-day retention of 6.2% vs 2.2% across traffic sources of similar volume. — [Unity ad-monetization guide](https://unity.com/resources/the-definitive-guide-to-ad-monetization), [More Rewarding Substack](https://morerewarding.substack.com/p/incentivized-advertising-for-f2p), [TechCrunch 2011](https://techcrunch.com/2011/09/07/incentivized-installs-not-all-bad-says-new-study-but-consider-the-source/amp/) (LOW; vendor claims and old data)

### Inferences
- "Same patterns across games" has an economic reason: ad platforms reward the creative that gets the highest IPM, and a few concepts (fail, "noob to pro", puzzle choices, pull-pin, fake "other game" mini-games) repeatedly win, so every studio converges on them. This is an inference from the creative-concentration and testing guidance, not directly stated by a source.
- The gap between ad and game is a deliberate trade: the marketing side optimises installs per dollar; retention is fixed by the product team. If the ad over-promises, D1 falls and some of the CPI saving is lost. The evidence for the size of that loss is weak (LOW).
- Because 2% of creatives take 53% of spend, volume matters mostly as a search for outliers. A small team cannot match 2,400 variants/quarter but can test a handful of distinct concepts.

### Gaps
- No primary data (Moloco, Mintegral, Unity Ads, TikTok) on channel share of game UA spend or channel-specific CPI; only AppLovin figures were found (LOW-MEDIUM). Mintegral and Moloco returned no usable data.
- No independent study quantifying retention damage from fake-gameplay ads; only vendor blogs.
- UGC-style game ads: no quantified source found.
- Original Mobile Dev Memo posts were not retrieved (search returned only podcast listings); Seufert's view is second-hand.

---

## 3. Organic: ASO, store featuring, cross-promotion, community, TikTok, pre-registration

### Takeaway
Organic is small relative to paid (a well-optimised indie game gets about 200-500 organic installs a day, per one unsourced claim) but it raises the conversion of every paid install and is the only channel that scales with a low budget. The best-evidenced levers are store-page conversion tests, editorial featuring nominations, pre-registration with a reward, and creator-led social content. Evidence is mostly vendor case studies.

### Cited Findings
**ASO (store listing optimisation)**
- 57% of games A/B test screenshots two or more times on Google Play vs 34% of apps; apps whose rating improved from 3.6 to 4.2 saw nearly 60% higher conversion (AppTweak 2025 benchmarks, using 2024 data on top US apps). — [AppTweak](https://www.apptweak.com/aso-blog/aso-trends-benchmarks-report-2025) (MEDIUM, via search summary)
- Icon test: Ciliz (Spin the Bottle) lifted store conversion from 20.46% to 24.42% (+19.4% relative) by redesigning the icon. Rovio (Angry Birds 2) found screenshots with characters beat plain ones, and a later test favoured portrait over landscape. Date of both is unclear. — [SplitMetrics Ciliz case](https://splitmetrics.com/cases/ciliz-improves-conversion-with-splitmetrics-agency/), [SplitMetrics Angry Birds 2](https://splitmetrics.com/blog/angry-birds-2/) (LOW-MEDIUM; vendor marketing cases)
- Google Play store-listing experiments can test up to two variants against the current listing, and can target "unique user open clicks" (installers who open the app). — [AppTweak/SplitMetrics summaries via search](https://www.apptweak.com/aso-blog/aso-trends-benchmarks-report-2025) (LOW-MEDIUM)

**Store featuring**
- Apple: Featuring Nominations in App Store Connect; at least two weeks' lead time, up to three months for broader consideration. Google Play: nomination form at least three weeks before the target date, four for new apps, with the build already in Play Console. — [Apple Developer](https://developer.apple.com/contact/app-store/promote/), [Google Play support](https://support.google.com/googleplay/contact/featuring_review?hl=en) (HIGH for the process)
- Third-party view: Apple editors lean to design, innovation and cultural/seasonal ties; Google leans to technical performance and metrics. — [AppTweak](https://www.apptweak.com/en/aso-blog/how-to-get-your-app-featured-on-the-app-store) (LOW-MEDIUM)

**Pre-registration (Google Play)**
- Nexon (FAITH): baseline about half of pre-registrations became installs; a pre-registration reward raised the rate by 20%; cohort showed almost 50% higher day-60 retention. Panzerdog: nearly 60% of pre-registrants installed. Play Console counts conversions as installs within 14 days of availability; one reward per campaign, cannot be edited after creation. — [Google Play Console case study](https://play.google.com/console/about/nexon-casestudy/), [Android Developers Panzerdog](https://developer.android.com/stories/games/panzerdog) (MEDIUM; Google-hosted success stories, Nexon case from 2019)

**Social, creators, community**
- TikTok's own guidance for games: three stages starting with organic; internal claim that the top 100 gaming hashtags exceed 40B views a month. — [TikTok for Business](https://ads.tiktok.com/business/de/blog/gaming-marketers-ultimate-guide-tiktok-content) (LOW-MEDIUM; platform claim, undated)
- Squad Busters (Supercell, launched May 29 2024): about 3.2B TikTok views in six weeks and 60M+ downloads at launch (creator-distribution vendor page). Deconstructor of Fun (via secondary summaries, Nov 2025): estimated total cost about $150M (development $30-45M, user acquisition about $65M for roughly 25M bought installs of 60M, about $15M celebrity talent and $5M production); revenue about $70-80M; game shut down Oct 30 2025. — [Game World Observer, Jun 2024](https://gameworldobserver.com/2024/06/19/squad-busters-revenue-28-million-paid-ads-supercell), [WN Hub summary of DoF](https://wnhub.io/ru/news/games/item-49267) (MEDIUM for the estimates; they are analyst estimates, not company figures; the original DoF post was not retrieved)
- Cross-promotion: Liftoff's data shows hyper-casual/puzzle ads supply about half of casual installs (see Section 1), which shows that games advertising other games is itself a large channel. — [Liftoff](https://liftoff.ai/?p=35032) (MEDIUM-HIGH). Dedicated cross-promo benchmarks were not found.

### Inferences
- The Squad Busters case shows that even a very large creator and celebrity push (about $35M combined) did not substitute for retention and monetisation; organic buzz is an install multiplier, not a retention fix.
- For a small team, ASO tests (free) and pre-registration are the cheapest levers with published uplift numbers; TikTok creator work has high variance and no public benchmarks.

### Gaps
- No Discord/community-building benchmarks found. No independent organic-install benchmark. No dated 2025 game-specific ASO case study with verified numbers. Apple Product Page Optimization data not found. No cross-promotion benchmarks.
- The "200-500 organic installs per day" claim is unsourced (CAS.AI marketing content).

---

## 4. Pre-launch process: concept tests, soft launch, scale-or-kill gates

### Takeaway
Studios test the ad before the game: they make a video of the idea, buy a few hundred to a few thousand dollars of traffic, and measure CPI and IPM; only concepts that earn cheap installs get built. A playable build then goes to a soft launch in 1-2 cheaper markets, where D1/D7/D30 and LTV vs CPI are used as go/no-go gates.

### Cited Findings
**Concept (marketability) test**
- Steps: video ads showing the new hero/mode/feature -> run as creatives -> measure CPI and IPM; illustrative cost $500 for creative vs $20,000 for engineering. — [CAS.AI](https://cas.ai/blog/the-mobile-game-publishing-reality-why-most-indies-fail-and-what-actually-works/) (LOW; publisher marketing)
- One studio's first CPI test spends as little as $300. — [PocketGamer.biz](https://pocketgamer.biz/news/62598/user-acquisition-experts-talk-about-how-much-it-costs-to-make-a-million-on-the-app-store/) (LOW-MEDIUM, via search summary)
- Unity hyper-casual: CPI is the most important prototype KPI; targets CPI under $0.30 and D1 38%+ on Android; Draw the Line had CPI $0.38 but D1 51% and reached the US iOS top 5. Run first tests on Facebook. Date undated (likely 2020-21 era). — [Unity](https://unity.com/resources/growing-hyper-casual-games) (MEDIUM; old)
- Voodoo's 2021 prototype competition thresholds: $0.20 CPI and 30% D1 on Android, $0.30 CPI and 30% D1 on iOS; 2020 partner KPIs: CPI $0.10 (Android) / $0.20 (iOS), D1 38%/45%, D7 8%/13%. Homa Games: CPI under $0.4, D1 over 35%, D3 over 15%. — [PocketGamer.biz](https://www.pocketgamer.biz/voodoo-offering-1-million-for-new-hypercasual-hits), [Homa](https://support.homagames.com/knowledge/prototyping-for-hyper-casual), [WN Hub](https://wnhub.io/news/other/item-17705) (MEDIUM for the numbers but they are 2020-21 hyper-casual-era and not valid for midcore or 2026 CPIs)
- CrazyLabs weighs D1 retention and 24-hour playtime alongside CPI: a weak CPI with strong engagement may not justify cancelling a game. — [AppSamurai, Aug 25 2026](https://appsamurai.com/blog/how-to-market-test-a-mobile-game/) (MEDIUM)

**Soft launch**
- Market choice: run two markets in parallel (one resembling the paying audience, one cheap for volume); keep the US, Japan, South Korea, China out of the first phase. Lean run 4 weeks / one market; full 12 weeks / two markets. Budget lean $11,000-23,000 total, full $62,000-110,000; algorithm floor $300-500 per day per ad set; about 1,000 purchased installs per cell (896 installs needed for a D1 near 30% within +/-3 points at 95% confidence). — [Game Growth Advisor, Dec 16 2025](https://gamegrowthadvisor.com/blog/2025-12-16-mobile-soft-launch-complete-guide/) (LOW-MEDIUM; one practitioner's framework, but the sample-size arithmetic is checkable)
- Gates (same source): D1 stop buying below 25% on Android (peer band 28-32%, median about 22%, from AppsFlyer Q3 2022); D7 stop scaling below 8% (market median 3.4-3.9%, top quartile 7-8%); D30 stop scaling below 3%; scale test: triple daily spend and require CPI to rise under 30% (kill above 50%). The 30%/50% bands are the author's convention, not published data. — same source (LOW-MEDIUM)
- Alternative gate set: D1 under 30% stop and fix onboarding; D7 under 12% or D30 under 4% stop scaling; CPI rises above 40% when spend triples signals a saturated channel. — [Game Growth Advisor (as relayed by search summary)](https://gamegrowthadvisor.com/blog/2025-12-16-mobile-soft-launch-complete-guide/) (LOW; thresholds differ from the page I read, so the search summary may be wrong. Treat the two sets as unreconciled.)
- Launch-ready F2P targets: D1 35-50%+, D7 15-25%+, D30 5-15%+, 99%+ crash-free. — [MWM](https://mwm.ai/glossary/soft-launch) (LOW-MEDIUM)
- D7/D1 ratio as a diagnostic: high D1 with a low ratio suggests a first-day experience problem. — [GameDev.net](https://gamedev.net/blogs/entry/2298160-the-d7d1-retention-ratio-for-mobile-games-a-complete-guide) (LOW, directional)

**Indie odds**
- Per CAS.AI (publisher, unnamed Q4 2025 aggregate): of 100 indie mobile games, 1 reaches $10K/month; 1 in 300 reaches $30K; 1 in 1,000 or fewer reaches $100K+. 80-90% of indie teams have under $3,000/month for marketing; developers often spend $10,000-20,000 on testing then quit; a publisher A/B test costs $300-500 over 2-4 days vs more than $2,000 over weeks for an indie. — [CAS.AI, Apr 8 2026](https://cas.ai/blog/the-mobile-game-publishing-reality-why-most-indies-fail-and-what-actually-works/) (LOW; unsourced, self-interested)
- A UA expert in PocketGamer.biz recommended $5,000-10,000 for a soft launch. — [PocketGamer.biz](https://pocketgamer.biz/news/62598/user-acquisition-experts-talk-about-how-much-it-costs-to-make-a-million-on-the-app-store/) (LOW-MEDIUM; date unknown)

### Inferences
- The scale-or-kill thresholds in circulation come from only a few practitioners. They agree on the logic (D1 first, then D7, then LTV vs CPI, then a spend-tripling test) but not on the numbers. A reader should adopt the logic and set own numbers from genre peers.
- Hyper-casual-era CPI targets ($0.10-0.40) are not transferable to midcore or to 2026 Western markets, where average CPI is $0.53-1.68 (Section 1).

### Gaps
- No primary-source playtime thresholds, and Game Growth Advisor gives none. No published ROAS gates. No data on how many concepts pass CPI tests.
- The $1 CPI threshold I was asked about (Voodoo) does not appear in any source found.

---

## 5. Privacy era: ATT / SKAdNetwork, Google Privacy Sandbox, MMPs

### Takeaway
Apple's ATT (2021) left only a minority of iOS users trackable, so iOS attribution relies on aggregated, delayed Apple postbacks (SKAdNetwork, now AdAttributionKit). Google shut down most of Privacy Sandbox in Oct 2025, so Android still relies on the Google Advertising ID. Measurement partners (AppsFlyer, Adjust, Singular, Branch) stitch these signals together.

### Cited Findings
- ATT opt-in in games: global 38% (Q1 2025) to 39% (Q1 2026); Sports 54%, Action 50%, Arcade down from 50% to 46%; India 44% to 51%; Indonesia 60%. — [GameDev Reports / Adjust 2026](https://gamedevreports.substack.com/p/adjust-gaming-app-insights-report) (MEDIUM-HIGH). Contradicted by a figure of "as low as 14% globally" attributed to Aarki, undated — [Moburst, Mar 20 2026](https://www.moburst.com/blog/mobile-attribution-in-2026-what-marketers-actually-need-to-know/) (LOW; the Adjust gaming-specific, dated figure is preferable; the two are likely different populations).
- Apple introduced AdAttributionKit (AAK) at WWDC 2024 as SKAN's successor; iOS 18.4 added configurable attribution windows, overlapping re-engagement conversions, country codes in postbacks when anonymity thresholds are met, and alternative-marketplace support. SKAN 5.0 was never released. SKAN and AAK interoperate. — [Moburst, Mar 20 2026](https://www.moburst.com/blog/mobile-attribution-in-2026-what-marketers-actually-need-to-know/) (MEDIUM; marketing agency blog, not Apple docs)
- SKAN/AAK data threshold: campaigns under roughly 20 daily installs often get null conversion values; guidance is 100-150 installs/campaign/day (Aarki, via Moburst). — same source (LOW-MEDIUM)
- Google announced on Oct 17 2025 it would retire most Privacy Sandbox technologies (Attribution Reporting, Topics, Protected Audience, Protected App Signals, SDK Runtime, On-Device Personalization, others) citing "low levels of adoption", no dates given in the announcement coverage. GAID has not been deprecated as of March 2026; third-party cookies remain in Chrome. — [PPC Land, Oct 18 2025](https://ppc.land/chrome-kills-most-privacy-sandbox-technologies-after-adoption-fails/), [Moburst](https://www.moburst.com/blog/mobile-attribution-in-2026-what-marketers-actually-need-to-know/) (MEDIUM-HIGH)
- MMP role: combine SKAN/AAK postbacks, probabilistic signals, Play Referrer and deterministic Android data into one source of truth; Apple's Privacy Manifest requirements (enforced since May 2024) prohibit fingerprinting; Safari 26 blocks common fingerprinting surfaces. — [Moburst](https://www.moburst.com/blog/mobile-attribution-in-2026-what-marketers-actually-need-to-know/) (MEDIUM)
- MMP cost for a soft launch: $0 (lean) to $600-2,100 (full programme). — [Game Growth Advisor](https://gamegrowthadvisor.com/blog/2025-12-16-mobile-soft-launch-complete-guide/) (LOW-MEDIUM)
- Spend shift: Singular reported (Q2 2025) total ad spend up 40.3% YoY, while mobile game spend was down. — [Appier summary of Singular Q2 2025](https://www.appier.com/en/blog/global-ad-spend-surged-40.3-but-tariffs-shift-the-landscape-key-insights-from-the-q2-2025-mobile-trends-report) (LOW-MEDIUM, via search summary)

### Inferences
- With only about 40% iOS opt-in, an iOS cohort's ROAS is partly modelled, which is why D7 predictions and "creative as targeting" matter. This is an inference.
- Android's continued GAID availability helps explain why Android CPIs are about 3-4x cheaper but also why iOS D30 ROAS (47%) is about 3x Android (15%) (Section 1).

### Gaps
- Conflicting dates for Chrome/Android phase-outs (one search summary gave Chrome 144/150 in 2026, others give no dates); I did not retrieve Google's own status page, so no phase-out dates are asserted.
- No primary Apple documentation was retrieved on AAK. No Mobile Dev Memo ATT analysis was retrieved.
- Differences between AppsFlyer, Adjust, Singular and Branch features were not researched.

---

## 6. CRM / LiveOps marketing: push, email, retargeting, win-back, deep links

### Takeaway
Once a player is acquired, re-engagement through push, email and retargeting ads is far cheaper than buying a new install, but evidence that it works comes mostly from tool vendors. Opt-in rates for push in games are low and do not reliably predict retention.

### Cited Findings
- Games had the lowest push opt-in of any category (35% average) in an older Urban Airship Good Push Index; across apps, 55% of opted-in users were retained in month one vs 29% of opt-outs. Date unclear (probably several years old). — [PocketGamer.biz](https://www.pocketgamer.biz/chart-of-the-week-why-getting-players-to-opt-in-to-game-push-notifications-matters/) (LOW-MEDIUM)
- Pushwoosh's 2025 benchmark (600+ apps) found no clear link between opt-in rate and D1 retention in games (one app: 86.5% opt-in and 77.9% D1; another: 92.2% opt-in and 22.4% D1). — [Pushwoosh](https://www.pushwoosh.com/blog/game-apps-metrics/) (LOW-MEDIUM; vendor)
- Timing guidance: start win-back pushes after 3-7 days of inactivity for casual games and 7-14 days for deeper ones; segment by churn depth and spend history. — [Countly](https://countly.com/blog/how-to-use-push-notifications-to-bring-lapsed-players-back-to-your-game), [Playio](https://blog.playio.co/re-engagement-strategies-lapsed-mobile-gamers) (LOW; vendor blogs)
- Vendor claim: "65% of users return within 30 days with push enabled vs 20% when disabled" is attributed to Localytics, second-hand. — [Countly](https://countly.com/blog/how-to-use-push-notifications-to-bring-lapsed-players-back-to-your-game) (LOW)
- RevX ran a retargeting campaign for DomiNations (Big Huge Games) segmenting lapsed players by prior purchase behaviour; lift figures not seen. — [RevX case study, 2024](https://revx.io/storage/2024/10/RevX_BigHugeGames_Casestudy_2024.pdf) (LOW)
- Google's guidance: deep-link pushes to the specific in-app destination and send only tailored messages. — [Think with Google](https://marketfinder.thinkwithgoogle.com/intl/en_us/guide/engage-users-app) (MEDIUM)

**D2C web shops (links go from push/email/in-game banners to a web store)**
- Following Epic v. Apple (US ruling Apr 30 2025), US developers may link out to web stores without Apple commission; Apple has appealed, and implementation is described as contested. EU DMA permits external links with Apple fees (about 2% initial acquisition fee for six months, 5-13% store services, 5% core technology commission); Japan opened paths under MSCA in January 2026; UK standard rates with reform expected mid-2026. — [Game Growth Advisor, May 5 2026](https://gamegrowthadvisor.com/blog/2026-05-05-mobile-game-d2c-web-shop-strategy-2026/), [Appcharge](https://appcharge.com/blog/the-ruling-weve-been-waiting-for) (MEDIUM for the legal status; verify per region before launch)
- Economics: store fee 30% (15% Small Business under $1M) vs web shop provider fees of 5-7%; a $99.99 pack nets about $93 on web vs $70 via the app store. — [Game Growth Advisor](https://gamegrowthadvisor.com/blog/2026-05-05-mobile-game-d2c-web-shop-strategy-2026/) (LOW-MEDIUM; vendor/advisor estimate)
- Adoption: more than 60 of the top 100 grossing games run a web shop (2026, "industry reporting"); D2C payments +46% in 2025; top performers route 20-30% of revenue via web in 12 months; casual and hyper-casual typically stay under 5-8%; conversion drops up to 45% when a player leaves the app (inconsistent: the FAQ says 30-50%). — same source (LOW-MEDIUM). FoxData title claims D2C game revenue of $17B (headline only). — [FoxData](https://foxdata.com/en/blogs/mobile-game-d2c-revenues-hit-17-billion-why-publishers-are-pushing-beyond-app-stores/) (LOW)
- Routing: in-game banners, push, paid re-engagement (email, Meta retargeting); "Buy on Web" links where allowed; push deep links back into the game; author advises avoiding aggressive pop-ups because Apple polices steering. No channel-level conversion figures given. — [Game Growth Advisor](https://gamegrowthadvisor.com/blog/2026-05-05-mobile-game-d2c-web-shop-strategy-2026/) (LOW-MEDIUM)

### Inferences
- The "push -> deep link -> offer" pattern the reader notices is both a retention tactic and, since 2025, a margin tactic (web shops return about 20-25 points more per dollar).
- Casual and hyper-casual titles have little to gain from web shops (under 5-8% of revenue), while live-ops RPG/4X/casino titles gain the most. This follows from the adoption figures above.

### Gaps
- No controlled-experiment data on win-back uplift by channel (push vs email vs retargeting). No dated 2025-26 benchmark for game push CTR or email. No CRM benchmark for Vietnam/SEA.
- Pricing and offer design is out of scope (covered by another researcher).

---

## 7. AI's effect on creative production and UA (2025-2026)

### Takeaway
AI has made ad variants cheaper to produce and lifted volume, but because everyone has the same tools, the market is "flooded" and the cost of standing out rises. AI is used mostly to manage scale, not set strategy.

### Cited Findings
- AppsFlyer ties 25-30% growth in creative output to AI; "The result is not a shortage of creativity, but a surplus of it." Of 5,000+ AI-assistant queries analysed, 46% were about reporting and performance breakdowns; AI is mostly used to manage scale, not to set strategy. Paid installs +10%, impressions +20%. — [AppsFlyer, Jan 14 2026](https://www.appsflyer.com/company/newsroom/pr/gaming-marketing/) (HIGH)
- 90% of game developers use generative AI in workflows (Google Cloud / Harris Poll, 615 developers, Aug 2025). — [Segwise compilation](https://segwise.ai/blog/ai-game-marketing-ua-statistics-2026.md) (MEDIUM; second-hand)
- Meta reported (per Segwise, unlinked) that its AI video-generation tools hit a $10B revenue run-rate in Q4 2025 and that a new AI attribution model drove a 24% rise in incremental conversions vs its standard model (Jan 2026). — [Segwise compilation](https://segwise.ai/blog/ai-game-marketing-ua-statistics-2026.md) (LOW; not checked against Meta)
- Generative AI plus AI-enhanced playables compress creative cycles to under a week; short-form video accounts for most impressions in H1 2025. — [Game Industry Library summary](https://gameindustrylibrary.com/topics/in-game-advertising?page=2) (LOW)
- Liftoff: Metaplay creative aligned with audiences drove a 93% rise in IPM (vendor case, undated). — Segwise compilation (LOW)

### Inferences
- AI lowers the production cost of testing, which helps small teams, but also raises the volume bar (top spenders at 2,400+ variants/quarter), so differentiation shifts to concept originality and to the real product. This is my reading of the AppsFlyer "surplus of creativity" statement.

### Gaps
- No credible published numbers on cost per AI-generated creative, win-rate of AI vs human creatives, or CPI change attributable to AI. AppLovin Axon and Meta Advantage+ creative-generation specifics were not found with primary sources. Unity/Moloco AI claims were not retrieved.

---

## 8. What an indie team can realistically do vs large studios; Vietnam / Southeast Asia

### Takeaway
Large studios win through creative throughput, testing speed and predictive LTV, which an indie cannot match. An indie's feasible path is cheap pre-build demand tests, careful soft launch, ASO, community/short-video content, or partnering with a publisher. Vietnam is a large download market with low monetisation and a big developer base that sells to the world.

### Cited Findings
**Indie vs publisher**
- Publisher advantages (unsourced, from a publisher's marketing): 50-100 video ad variants per game per month, 5-10x faster A/B tests, indie CPI 10-20% higher and ARPDAU 5-20% lower; traditional publisher deals split revenue from 70/30 to 90/10 in the publisher's favour; self-publishing needs capital, a UA team and 12-18 months of iteration. — [CAS.AI, Apr 8 2026](https://cas.ai/blog/the-mobile-game-publishing-reality-why-most-indies-fail-and-what-actually-works/) (LOW)
- A/B sample size needs: 3,000-6,000 users per variant (CAS.AI); consistent with the Game Growth Advisor figure of about 1,000 installs per cohort for a D1 read (Section 4). (LOW-MEDIUM)
- Advertisers under $500K increased creative production 20-40% YoY (AppsFlyer), suggesting smaller teams are copying the high-volume approach. — [ContentGrip](https://www.contentgrip.com/gaming-marketing-trends-report/) (MEDIUM)
- Squad Busters' estimated $150M total cost shows the other end of the spectrum (Section 3). (MEDIUM)

**Vietnam**
- Revenue and players: Vietnam mobile games revenue about $825M in 2025 (+9.16% YoY), about 54M gamers; only 7-10% of users spend and 2-3% are high spenders; local payment methods are gaining ground (Gamota report). — [PocketGamer.biz](https://www.pocketgamer.biz/vietnams-mobile-games-market-reached-825m-in-revenue-in-2025) (MEDIUM; via search summary, page returned HTTP 403)
- Another figure set (Vietnam News, May 5 2025): projected overall Vietnamese gaming revenue $1.66B end-2025 and $2.42B by 2029; mobile game growth in Vietnam/SEA 7.4% a year (2022-25). The $825M and $1.66B figures differ because they measure different scopes (mobile vs all games), which the sources do not say explicitly. — [Vietnam News](https://vietnamnews.vn/economy/1716994/viet-nam-targets-us-2-4-billion-in-gaming-industry-revenue-by-2029.html) (MEDIUM)
- Downloads (Sensor Tower Q1 2025): SEA 1.93B installs, IAP spend $625M (excludes D2C payments, which are common in SEA); Indonesia 870M, Philippines 366M, Vietnam 329M installs. Vietnam top download genres: platformers/runners, simulators, arcade; top revenue genres: 4X strategy (+51.5%), MMORPG, squad RPG; Last War: Survival and local RPG Big Bang Thoi Khong lead revenue; Roblox leads downloads. — [GameDev Reports / Sensor Tower, Jun 13 2025](https://gamedevreports.substack.com/p/sensor-tower-southeast-asia-mobile?open=false) (MEDIUM-HIGH)
- Vietnamese developers build quickly around popular trends to gather organic traffic; 3 of top 15 publishers (2024) were Vietnamese; Vietnamese studios reached 4.9B downloads (ranking #2 globally per a GameGeek/Sensor Tower-supported report) - this measures games made in Vietnam, not played there. — same Sensor Tower summary; [search summary of GameGeek report](https://80.lv/articles/vietnam-s-game-winning-era) (MEDIUM / LOW)
- Marketing channel: TikTok Marketing Science Global Gaming LiveOps Survey 2024: 59% of users discovered new games via creative content on TikTok; self-reported campaign claims include CPI drops of 35-72% and ROAS 58x industry average (a Funtap case). Treat as vendor claims. — [Vietnam News, May 5 2025](https://vietnamnews.vn/economy/1716994/viet-nam-targets-us-2-4-billion-in-gaming-industry-revenue-by-2029.html), [TikTok Funtap case](https://ads.tiktok.com/business/en/inspiration/staple-games-tiktok) (LOW; link is a TikTok case index, not necessarily the Funtap case)
- Vietnamese app developers spent $397M on UA from Q3 2023 to Q2 2025, with the US taking 53% of that spend (AppsFlyer, via a Vietnamese news site). AppsFlyer forecasts Vietnam install volume down 2% in 2025, the first decline since 2018. TikTok, Shopee and Zalo are the most engaging apps. — [Thi truong tai chinh tien te](https://thitruongtaichinhtiente.vn/appsflyer-nen-kinh-te-ung-dung-viet-nam-buoc-vao-giai-doan-truong-thanh-khi-chat-luong-len-ngoi-thay-cho-so-luong-72056.html) (MEDIUM; I did not open the page, relying on search snippet summary, so LOW-MEDIUM)
- Regional CPI lens: SEA CPI $0.20-0.60 and India $0.08-0.30 for Android casual (practitioner estimates, Section 1); LATAM Adjust average $0.14. India has the 3.81 paid:organic ratio. (LOW-MEDIUM / MEDIUM-HIGH)
- Mobile Legends: Bang Bang kept top-5 revenue/downloads in SEA since 2017 through localisation, SEA-inspired characters, tournaments, influencers, and local offices; Western companies face cultural barriers and rely on personal connections. — [GameDev Reports / Sensor Tower](https://gamedevreports.substack.com/p/sensor-tower-southeast-asia-mobile?open=false) (MEDIUM)

### Inferences
- For a Vietnamese indie, an affordable test plan is: concept video test in a low-CPI SEA/LatAm market, soft launch in SEA plus one English-speaking market, rather than the US, then decide on a publisher partnership if D1/D7 pass. This combines Section 4 and the regional CPI data; it is not stated by any single source.
- Vietnam's low payer share (7-10%) and the common use of local payment channels imply that web/local payment shops and D2C are likely more important for Vietnamese players than the global average, but no source tests this directly.

### Gaps
- No Vietnam-specific CPI/ROAS benchmarks by genre; no 2025 Vietnam gaming figures from the Adjust spotlight PDF (the binary PDF could not be parsed by the fetch tool); no data on Zalo or Facebook as game ad channels in Vietnam; no Vietnam ATT opt-in, retention, or ARPU figures.
- Gamota's and the Vietnam News figures are not reconcilable from the sources alone (different scopes).
- Reddit threads from r/gamedev / r/UserAcquisition were not retrieved, so no first-hand indie numbers beyond vendor blogs.
- Sensor Tower's own "State of Mobile 2026" and Deconstructor of Fun's original posts were not accessed (403 / not retrieved).

---

## Cross-cutting contradictions and caveats for the report writer
- "Benchmarks" disagree by source type: Adjust's D1 27% (all games) vs vendor "good" D1 35%+ vs GameAnalytics pooled lower D7; ROAS targets differ by 2-3x between Playio, Linkrunner and MWM. Prefer ranges and name the source type.
- Fake-ad retention statistics originate from a single vendor blog and are likely not independent.
- Most 2025-26 "statistics blogs" (Segwise, Playio, Game Growth Advisor, CAS.AI) sell tools or services; flagged LOW unless they cite a named dataset.
- The original Mobile Dev Memo, Deconstructor of Fun, Sensor Tower and Liftoff full reports were not retrieved; findings from them are second-hand and labelled.
