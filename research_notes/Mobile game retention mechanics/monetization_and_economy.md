# Mobile game monetization and in-game economy (as it relates to keeping and converting players)

Research date: 2026-10-22. Method: web search plus page fetch. Confidence labels: HIGH = primary or direct data source, figure and date confirmed on the fetched page; MEDIUM = credible but secondary, vendor-published, correlational, or only partly verified; LOW = unsourced origin, undated, or conflicts with other sources. Many search "summaries" were read through a fetch tool that summarizes pages; figures were taken from those fetch results. Where only a search snippet exists, it is flagged.

Overall data-quality warning for the report writer: there is no free, authoritative, current (2024-2026) public benchmark for payer conversion, ARPDAU, or whale concentration across mobile games. Most free numbers are either vendor blogs with unattributed ranges or older (2014-2019) studies. Paid reports (GameAnalytics, Adjust, AppsFlyer, Sensor Tower full reports) were not accessible.

---

## 1. Business models: F2P IAP, ads, hybrid-casual, subscriptions, premium (and which genre uses which)

### Takeaway
Mobile game money splits into three engines: in-app purchases (IAP) dominate midcore genres (strategy, RPG, casino), ads dominate hypercasual and parts of puzzle, and hybrid-casual mixes both at roughly even weight. Global IAP revenue was about $82B in 2025 and flat; hybrid-casual was the one segment growing.

### Cited Findings
- Global mobile game IAP revenue reached $81.75B in 2025 (+1.3% YoY), downloads were 50.41B (-7.2%). Figures are gross (include store fees and taxes) and exclude Android China and direct-to-consumer (D2C) web-shop revenue. HIGH — [Sensor Tower via GameDev Reports, 2026-01-30](https://gamedevreports.substack.com/p/sensor-tower-the-state-of-the-mobile)
- 2025 IAP split: midcore $44.68B and casual $32.7B, both essentially flat; hybridcasual rose 20% YoY to $4.2B. MEDIUM (secondary search summary of the Sensor Tower report, not seen on the fetched page) — [Sensor Tower State of Mobile Gaming 2025 coverage via search result](https://gamedevreports.substack.com/p/sensor-tower-the-state-of-the-mobile)
- 2024 comparison: Sensor Tower reported about $82B global IAP in 2024 (+4%), US nearly $24B; Strategy was 21% of all IAP revenue with 16% growth. MEDIUM — [Sensor Tower press release, March 2025](https://sensortower.com/press/press-release-sensor-tower-mobile-gaming-rebounds-in-2024-as-player-engagement-and-spending-reach-new-highs)
- AppMagic (data through 2025-10-22, App Store plus Google Play worldwide, published 2025-12-04) puts total market IAP at $55.2B to $57.1B (+3.4%) in the comparison period. Genre totals: Strategy $13.5B (+25.6%), RPG $11.6B (-15.4%), Puzzle $8.8B (+14.7%), Casino $7.2B (-7.6%), Simulation $4.8B (+11.2%), Hybridcasual $733M (+88%, from $390M). HIGH — [AppMagic Mobile Games Monetization Report 2025 via GameDev Reports](https://gamedevreports.substack.com/p/appmagic-mobile-games-monetization)
- Hybrid-casual is described as roughly 50/50 ad and IAP revenue, in contrast to hypercasual (almost all ads) and casual (leans IAP). MEDIUM (search summary of Sensor Tower's State of Mobile Gaming 2025 PDF; the PDF itself was too large to fetch) — [Sensor Tower State of Mobile Gaming 2025 PDF](https://investgame.net/wp-content/uploads/2025/11/sensor_tower__state_of_mobile_gaming_2025__en.pdf)
- Per-title splits vary: ad-first titles like Wordscapes get about 80% of revenue from ads; IAP-first titles like Pixel Flow! and Color Block Jam are about 78-80% IAP. MEDIUM (search summary; the fetched Sensor Tower ad-report page itself only confirmed the "$12B+ ecosystem", 19 markets, and that puzzle titles take more than half of ad earnings at most large networks) — [Sensor Tower Gaming Deep Dive: Ad Monetization, June 2026](https://sensortower.com/blog/gaming-deep-dive-ad-monetization-report)
- Hybrid-casual momentum: the top 10 hybridcasual games earned $87M IAP in Q1 2025 (+67% YoY), puzzle 48% and arcade 45% of it. MEDIUM (search summary) — [AppMagic Q1 2025 via GameDev Reports](https://gamedevreports.substack.com/p/appmagic-top-10-hybridcasual-games)
- Hybrid-casual leaders overtook hypercasual leaders on Day-1 retention in 2025 and the gap widens by Day 7. HIGH — [Sensor Tower via GameDev Reports, 2026-01-30](https://gamedevreports.substack.com/p/sensor-tower-the-state-of-the-mobile)
- Rewarded ads were 17.7% of ad creatives in 2025 (up 53.9%); playables 13.3%; video 53.7%. Ad network share: AdMob 33%, AppLovin 27.3%, Mintegral 16%. HIGH — [Sensor Tower via GameDev Reports, 2026-01-30](https://gamedevreports.substack.com/p/sensor-tower-the-state-of-the-mobile)
- Genre-to-model mapping (directional only): hypercasual ads-primary; casual/puzzle hybrid; midcore/RPG IAP; strategy IAP with "time-compression" economics; social casino chip economy with VIP programs; shooters/MOBA cosmetic-only via battle passes and skins. LOW-MEDIUM (a blog describing ranges as drawn from AppsFlyer, GameAnalytics, Liftoff, Appodeal without attribution per row) — [Juego Studios, 2026-06-02](https://www.juegostudio.com/blog/arpdau-benchmarks-by-game-genre)
- Revenue is concentrated across games, not only players: "the top 1% of games captured most revenue; games outside the top 1% reached a 7.5% revenue share in 2025" (wording from a secondary summary; exact definition unclear). MEDIUM — [Sensor Tower via GameDev Reports, 2026-01-30](https://gamedevreports.substack.com/p/sensor-tower-the-state-of-the-mobile)
- Discoverability context: only about 2,500 of 190,000 mobile games released in 2025 passed 500,000 downloads. MEDIUM (search-result title only, article body not fetched) — [PocketGamer.biz](https://www.pocketgamer.biz/report-only-2500-of-190000-mobile-games-released-in-2025-surpassed-500000-downloads/)
- Users spent more in non-gaming apps than in games for the first time in Sensor Tower's tracking history (2025 data). HIGH — [Sensor Tower via GameDev Reports, 2026-01-30](https://gamedevreports.substack.com/p/sensor-tower-the-state-of-the-mobile)

### Inferences
- The "pattern" a non-developer sees (everything sells something) follows the genre's engine: ad-driven games interrupt with ads; IAP-driven games sell time-skips, gacha pulls and packs; hybrid games do both.
- The growth story in 2024-2026 is hybrid-casual and strategy/puzzle, while RPG and casino shrank in AppMagic's data, so "typical monetization" is moving toward hybrid structures.

### Gaps
- No reliable public revenue split (IAP vs ad vs subscription) per genre; only per-title examples and a 50/50 hybrid-casual rule of thumb.
- Subscriptions in games (VIP, monthly card, ad-free pass): I found no usable data on share of revenue or price points. A search returned nothing beyond a design portfolio entry. The report must treat "monthly card" economics as unresearched here.
- Premium (paid-upfront) mobile games: no data found in this slice.
- Sensor Tower's full 2025 PDF and full ad-monetization report were not readable (size limit / gated), so ad/IAP per-genre numbers rest on summaries.

---

## 2. Benchmarks: payer conversion, ARPDAU, ARPPU, whale concentration

### Takeaway
Typical free-to-play conversion is low single digits (most sources: under about 5% ever pay, a good casual game around 1-5%), and spending is extremely concentrated: Moloco puts the top 2% of users at 35-45% of IAP revenue and the top 10% at 70-85%. But the only strongly sourced "top 1% of payers" figure is old or academic, and numbers conflict by definition (share of players vs share of payers).

### Cited Findings
Concentration:
- Moloco (UA data on 4,000+ games, 195 countries, Sept 2023 to Sept 2024, excl. mainland China): top 2% of players generate 35-45% of all IAP revenue; top 10% generate 70-85%. HIGH — [Moloco via GameDev Reports, 2024-11-11](https://gamedevreports.substack.com/p/moloco-mobile-market-status-and-growth)
- Academic study of $4.7B in in-game spending across 69,144,363 players and 2,873 mobile games over 624 days: games with "hyper-Pareto" monetization (about 12% of games) account for about 42% of all revenue, and in those games about 38% of revenue comes from the top 1% of spenders. MEDIUM (reported via search summary; the ACM paper at doi 10.1145/3582927 returned HTTP 403 so I could not confirm directly) — [ACM, DOI 10.1145/3582927](https://dl.acm.org/doi/pdf/10.1145/3582927)
- Older anchors: Swrve 2014 found 0.13% of players produce 60% of mobile game revenue (62% from top 10% of payers). LOW (2014, definition mixes all players vs payers) — [wnhub summary of Swrve](https://wnhub.io/news/finance/item-8701)
- VentureBeat 2016 (cited): 0.19% of players bring half of game revenue; devtodev defines "grand whales" as top 1% of payers. LOW (2016, as cited by article) — [Game Developer, "What do we know about whales", 2016-04-18](https://www.gamedeveloper.com/business/what-do-we-know-about-whales)
- The "20% of payers bring 80% of revenue" rule is a restated Pareto principle, not a measured result in the source. LOW — [Game Developer, 2016-04-18](https://www.gamedeveloper.com/business/what-do-we-know-about-whales)

Payer conversion:
- Less than 5% of mobile gamers ever pay (AppsFlyer figure as cited by a blog); under 1% IAP conversion is called underperforming for casual games by a benchmark blog. LOW-MEDIUM — [maf.ad conversion rates blog (search result)](https://maf.ad/en/blog/mobile-game-conversion-rates/)
- GameAnalytics 2019: even top projects in most genres rarely convert more than 1%; top 15% of games convert 0.8-1.2%; RPG and Strategy convert many times better. LOW (2019) — [GameAnalytics 2019 benchmarks summary via WN Hub](https://wnhub.io/news/analytics/item-2261)
- A 2026 KPI guide gives first-purchase conversion of 1-5%+ and ARPPU of $10-100+ but cites no clear source. LOW — [AppFollow, Mobile Game KPIs 2026](https://appfollow.io/blog/mobile-game-kpis)
- Early timing: 77% of players who ever make an IAP do so in their first two weeks (undated vendor claim). LOW — [Fungies (search result)](https://fungies.io/how-to-effectively-monetize-your-player-base-in-mobile-games)

ARPPU (US top-10 grossing titles per genre, AppMagic, published 2025-12-04):
- Strategy: Day-90 payers spend about 2x casino payers; App Store ARPPU historically 4-5x Google Play, widening to up to 8x in 2025; average transaction about $7 on Google Play, often above $15 on App Store. HIGH — [AppMagic via GameDev Reports](https://gamedevreports.substack.com/p/appmagic-mobile-games-monetization)
- RPG: average first-purchase price $8.3 (Google Play) vs $17.9 (App Store); Google Play Day-90 ARPPU fell 42% YoY while App Store rose up to 27%. HIGH — same source.
- Hybridcasual: Day-90 ARPPU up to +71% (App Store) and +43% (Google Play); share of App Store payers spending over $100 by day 90 rose from 22% (2024) to 32% (2025). HIGH — same source.
- Casino: ARPPU fell up to 41% on Google Play and rose up to 40% on iOS. HIGH — same source.
- D90 IAP ARPPU roundup: casino $11.40, midcore $9.80, casual $7.26 (unattributed benchmark roundup, 2025-2026). LOW — [maf.ad (search result)](https://maf.ad/en/blog/mobile-game-conversion-rates/)
- Moloco D7 ARPPU by market: Hong Kong $37.5, Qatar $28, Iceland $27.4. HIGH — [Moloco via GameDev Reports, 2024-11-11](https://gamedevreports.substack.com/p/moloco-mobile-market-status-and-growth)

ARPDAU (all LOW-MEDIUM, from one blog that does not attribute rows to specific reports, published 2026-06-02): hyper-casual $0.01-0.05; casual/puzzle $0.03-0.10; midcore/RPG/card battler $0.08-0.20; strategy/4X $0.10-0.35; social casino $0.20-0.80+; sports/racing $0.04-0.12; MOBA/shooter $0.05-0.15. Notes iOS can outperform Android by up to 5x revenue per user in some categories. — [Juego Studios](https://www.juegostudio.com/blog/arpdau-benchmarks-by-game-genre)
- Another summary: ad-only casual about $0.01-0.05, hybrid-casual about $0.15-0.50, H1 2025 hypercasual $0.03-0.08; and that no trustworthy primary source exists for IAP-heavy midcore. LOW — [search result aggregate of ARPDAU blogs](https://blog.playio.co/arpdau-benchmarks-mobile-games)

### Contradictions
- Hybrid-casual ARPDAU: $0.03-0.10 (casual/puzzle hybrid, Juego Studios) vs $0.15-0.50 (hybrid-casual, another blog). Unreconciled; both unattributed. Cause is probably the different definitions of "hybrid".
- "Top 1% of payers" figures range from 38% (academic, hyper-Pareto games only) to 58% (blog citing Slice, undated) to 70% (vendor glossary). Different denominators (all players vs payers vs hyper-Pareto games only). Use Moloco's top-2% / top-10% figures as the best-sourced range.

### Inferences
- The best-supported statements for a lay reader: a small minority pay, a tiny minority of those pay most of the money, so offers are tuned to find and retain this minority (see section 3), and ads/free rewards serve the majority.
- Store matters as much as genre: App Store ARPPU runs several times Google Play's, which explains why monetization-heavy features are tested on iOS and Western/JP/KR markets first.

### Gaps
- No free current (2024-2026) cross-genre payer conversion table; GameAnalytics, Adjust and Sensor Tower paid reports not accessed.
- No source for the whale/dolphin/minnow tier definitions beyond devtodev's "grand whale = top 1% of payers"; dollar thresholds vary and were not found.
- The ACM study could not be opened to verify numbers.

---

## 3. Offer design patterns (starter pack, limited-time, bundles, anchoring, piggy bank, battle pass, daily deals, rewarded video)

### Takeaway
The recurring pattern: lower the barrier to the first purchase with a cheap, time-boxed, high-value "starter" offer, then ladder payers upward with bundles, passes and personalized offers. Hard evidence for specific conversion lifts is thin and mostly vendor-published.

### Cited Findings
Starter pack / first purchase:
- Recommended first-purchase price band $0.99-2.99 (one guide) or $1.01-5.00 (another); first-time buyer conversion is described as the most important metric because churn drops sharply after the first purchase. LOW-MEDIUM (vendor blog; Google's Android developer blog of 2016 is the original for the "first purchase" point) — [Fungies](https://fungies.io/how-to-effectively-monetize-your-player-base-in-mobile-games); [Android Developers Blog, 2016-08](https://android-developers.googleblog.com/2016/08/5-tips-to-help-you-improve-game-as-a-service-monetization.html)
- Limited-time sales are reported to convert first-time buyers at about 17% (iOS) and 16% (Android) — undated, vendor, no method. LOW — [Fungies (search result)](https://fungies.io/how-to-effectively-monetize-your-player-base-in-mobile-games)
- Let players try monetized mechanics free before asking to pay (free gacha pulls, new-player discounts). LOW-MEDIUM (design article summary) — [Game Refinery onboarding best practices part 3](https://gamerefinery.com/soft-landing-to-conversion-introducing-onboarding-best-practices-part-3)
- AppMagic: average first-purchase price is $8.3 on Google Play and $17.9 on App Store in RPGs (US top 10). HIGH — [AppMagic via GameDev Reports](https://gamedevreports.substack.com/p/appmagic-mobile-games-monetization)

Piggy bank:
- Mechanic: virtual savings that fill with play; the player pays to open it. Variants: upgradeable capacity, event banks, bonus-enhanced banks, rewarded-video top-ups. MEDIUM (sponsored vendor post, Heroic Labs, 2024-05-14; no figures) — [Heroic Labs](https://heroiclabs.com/blog/understanding-piggy-bank-mechanics-mobile-games/)
- Example: Hexa Sort's piggy bank appears at level 7, hides the price until a savings goal is reached, and at $4.99 was the 3rd most popular IAP in that game (Sensor Tower, iOS US). LOW-MEDIUM (secondhand through search summary; date not confirmed) — [Fungies piggy bank article (search result)](https://fungies.io/piggy-bank-monetization-mechanism-for-mobile-games/)

Battle pass:
- A glossary citing 754 apps puts median battle-pass price at $9.99, 25th percentile $5.99, top 10% $29.99; seasons 4-12 weeks; a typical band is $5-15. LOW-MEDIUM (methodology not seen) — [MWM glossary: battle pass](https://mwm.ai/glossary/battle-pass)
- A claim that battle passes carry 10-40% of top F2P revenue could not be traced to a primary dataset. LOW — [MWM glossary (search result)](https://mwm.ai/glossary/battle-pass)
- A "2026 battle pass statistics" page with precise figures (for example a 41% revenue share) attributes them to Sensor Tower/Newzoo but conflicts with the glossary; treat as unreliable. LOW — [voxbooster (search result)](https://voxbooster.com/blog/battle-pass-statistics-2026/)

Rewarded video as an offer (see also section 5):
- Users who engage with a rewarded ad were about 4.5x more likely to make a first purchase; spend rose a weighted average 326% after first rewarded engagement; sessions +34%. MEDIUM (ironSource/Tapjoy, 2022-08-24; 8 apps, correlational, no controls) — [Unity/ironSource blog](https://unity.com/blog/understanding-the-impact-of-rewarded-ads-on-iap-retention-and-engagement)

Personalization:
- Personalized/contextual offers based on player data are described as a major LiveOps lever by tool vendors (Metica, Balancy, Elevatix, Segwise); no independent lift figures found. LOW — [Segwise LiveOps article](https://segwise.ai/blog/how-to-boost-mobile-game-monetization-using-liveops-strategies-clvujuehh0048zvb27sywhnz2); [This Week in LiveOps #8](https://thisweekinliveops.substack.com/p/dont-underestimate-personalization)

### Inferences
- Price anchoring, "best value" tags and daily deals are visible in nearly all top games, but I found no citable evidence quantifying them. They should be presented to the reader as observed industry practice, not measured effects.
- Combining a high first-purchase price (RPG: $17.9 on iOS) with a cheap starter pack implies stores are segmenting payers by region/platform, but this is my inference.

### Gaps
- No source found for: price anchoring, "best value" tags, daily deals, bundle pricing lifts, daily-deal conversion, or dynamic offer lift with independent data.
- Deconstructor of Fun and Naavik pieces on offers were not found via search; coverage is vendor content.
- pocketgamer.biz "best practices starter bundles" returned HTTP 403, so its contents are unread.

---

## 4. In-game economy: soft vs hard currency, sinks and faucets, layering, pacing, inflation

### Takeaway
Standard design: a soft currency earned by play and spent on routine progression, plus a hard (premium) currency mainly bought with money and used to skip waits or buy exclusives. Balance faucets (inflows) against sinks (outflows); inflation appears when faucets outpace sinks. Only design-literature sources were found; no quantitative evidence.

### Cited Findings
- Soft currency (coins, XP) is earned in the core loop and runs day-to-day operations; hard currency (diamonds) speeds up wait timers, is given in some quantity at the start and then bought with real money, and is the main monetization lever. Currencies are chained so each gates the next stage (coins -> prizes -> XP -> store level -> new machines). MEDIUM (design essay, 2016, fictional example game) — [Adrian Crook, "A practical example of a free-to-play economy", 2016-08-05](https://adriancrook.com/?p=4918)
- The designer should avoid giving away so many premium currency units that paying players lose spending potential, while giving enough for players to experiment with it; premium inflow/outflow can be modeled across the player lifetime. MEDIUM — [Adrian Crook, 2016](https://adriancrook.com/?p=4918)
- Faucets put value in (rewards, drops); sinks remove it (crafting, fees, repairs). Faucets exceeding sinks causes inflation; too many sinks frustrate players. Hard sinks destroy currency (inflation control tools); soft sinks only change its form. Aspirational long-term goals are voluntary sinks. Event bonuses add faucets and should be offset with durable sinks. LOW-MEDIUM (blog and glossary aggregation, no primary data) — [MWM game economy glossary](https://mwm.ai/glossary/game-economy); [Medium: Designing Game Economies](https://medium.com/@msahinn21/designing-game-economies-inflation-resource-management-and-balance-fa1e6c894670); [metavert.io](https://metavert.io/game-economy-design)

### Inferences
- Time and scarcity are what hard currency sells: timers, energy, lives and caps create friction that payment removes. The pattern repeats across genres, which matches what a lay player sees.
- Because soft-currency generosity directly sets how often a player feels pressure to pay, economy tuning is also a retention lever; this link is common design logic but I found no quantified evidence for it.

### Gaps
- No Naavik, GDC or Deconstructor of Fun primary content retrieved on economy design; no measured values for pacing (time to first "pinch point"), sink/faucet ratios, or inflation indicators.
- Currency layering for gacha (pity, dual currency) not researched.

---

## 5. Ad design: placement, opt-in vs forced, frequency, ad ARPDAU

### Takeaway
Rewarded video (opt-in) is placed at "pain points" and is paced liberally; interstitials (forced) are capped conservatively and kept away from gameplay, especially in IAP-heavy games. Published evidence is vendor-sourced and often correlational.

### Cited Findings
- Rewarded placement: when players run out of lives, fail a level, or lack currency. Interstitials in ad-led games: at game open, after a loss, on return to home, or after a rewarded video. In IAP-heavy games show interstitials only at the end of sessions or when players ignore rewarded/IAP offers. Rewarded caps can be liberal; interstitial caps conservative and tested; hyper-casual and casual players tolerate more interstitials than midcore. No numeric caps given. MEDIUM (ironSource guidance, 2021-09-13) — [Unity/ironSource, "3 ways to optimize the ad experience"](https://unity.com/blog/3-ways-to-optimize-the-ad-experience-for-your-users)
- A/B test: ZiMAD added interstitials to a rewarded-only game: revenue +17%, ARPDAU +18%, D7 retention -2.3%. MEDIUM (vendor case study, search summary) — [ironSource case studies (search result)](https://is.com/?p=52105)
- Rewarded ad users: 30-day retention 53% to 68%, rising with each view, vs a 13% benchmark; at least 50% for those completing any one rewarded format in week one. Caveat from source and analysis: eight apps, no user counts, self-selection bias, commercial author. MEDIUM-LOW — [Unity/ironSource, 2022-08-24](https://unity.com/blog/understanding-the-impact-of-rewarded-ads-on-iap-retention-and-engagement)
- Rewarded latency is a common cause of bad rewarded UX. MEDIUM — [Unity/ironSource, 2022-08-24](https://unity.com/blog/understanding-the-impact-of-rewarded-ads-on-iap-retention-and-engagement)
- Ad format trend: rewarded ads 17.7% of game ad creatives in 2025 (+53.9%), playables 13.3%. HIGH — [Sensor Tower via GameDev Reports](https://gamedevreports.substack.com/p/sensor-tower-the-state-of-the-mobile)
- Puzzle titles account for more than half of ad earnings across most large ad networks. HIGH — [Sensor Tower, June 2026](https://sensortower.com/blog/gaming-deep-dive-ad-monetization-report)
- Ad ARPDAU ranges: hypercasual $0.01-0.05 / $0.03-0.08 (see section 2; LOW-MEDIUM).

### Contradictions
- Unity/ironSource claims rewarded ads increase retention and IAP, but the same source concedes the data are correlational; players who choose to watch are probably more engaged. Do not present as causal.

### Gaps
- No ad ARPDAU by format (rewarded vs interstitial vs banner) from a primary source; banner design not covered.
- No numeric interstitial frequency caps from a primary source.
- Forced-ad regulation, psychology (out of scope).

---

## 6. LTV modelling and its tie to retention (payback windows, ROAS targets)

### Takeaway
Marketing spend is judged by whether cumulative revenue per install repays the cost per install within a set window; windows are short for ad-driven games (days to 30) and long for IAP/strategy (90 to 180+). The Liftoff critique: early ROAS (D7) is an unstable predictor of long-term payback.

### Cited Findings
- Glossary windows: hyper-casual D1-D7; F2P games D90-D180; subscription apps D180-D365. Smaller studios should use shorter windows (D30) because of limited runway; strategy games should look at ROAS further out, hyper-casual closer to D1-D3. LOW-MEDIUM (glossary and Stash glossary) — [MWM payback glossary](https://mwm.ai/glossary/payback-period); [Stash ROAS glossary](https://www.stash.gg/glossary/return-on-ad-spend-roas)
- D7 ROAS targets are set from the historical ratio of long-window LTV to D7 LTV (example: D365/D7 ratio 20 means a 5% D7 ROAS target for 100% D365 payback), but D365 and D7 LTV are not proportional. MEDIUM (Liftoff, 2020 per search summary — dated) — [Liftoff](https://liftoff.io/?p=27508)
- Ad-driven games generally need to show returns within 30 days. LOW-MEDIUM — [Liftoff 2026 ROAS benchmarks article (search result)](https://liftoff.ai/?p=35616)
- Casual-game UA benchmarks (Singular data, Feb 2024 to Feb 2025; 2.4B installs, $11.9B spend; "casual" includes hypercasual): CPI $1.41 iOS and $0.14 Android; D30 ROAS 47% iOS and 15% Android; iOS D30 ROAS by genre sports 80%, kids 68%, strategy 60%; Android RPG 39%, tabletop 7%. Casino iOS CPI $21.03. HIGH — [Liftoff 2025 Casual Gaming Apps Report](https://liftoff.ai/?p=34267)
- Moloco: 71% of expected $29B 2025 gaming UA spend is in 10 countries, 39.8% in the USA. HIGH — [Moloco via GameDev Reports, 2024-11-11](https://gamedevreports.substack.com/p/moloco-mobile-market-status-and-growth)
- Link to retention: Sensor Tower notes hybrid-casual retention beats hypercasual at D1 and D7, supporting why hybrid games can monetize via IAP on top of ads. HIGH — [Sensor Tower via GameDev Reports](https://gamedevreports.substack.com/p/sensor-tower-the-state-of-the-mobile)

### Inferences
- Payback windows explain behavior the player sees: genres that pay back slowly (strategy) push long-run engagement systems (alliances, events, passes); ad-led genres need immediate high ad exposure in the first sessions.
- Retention is the multiplier on both ads (more impressions per user) and IAP (more days to reach a first purchase), so "hooking" and "monetizing" are the same system measured at different times.

### Gaps
- No Mobile Dev Memo primary article was retrievable; no authoritative published ROAS target by genre (for example "D180 ROAS 100%").
- No payback-day benchmark from Liftoff, AppsFlyer, or Adjust.
- Liftoff D7-ROAS critique is from 2020; current practice not verified.

---

## 7. Platform context: store fees, court rulings, D2C web shops

### Takeaway
2025-2026 court decisions and the Google/Epic settlement opened external payment routes. D2C web shops reached about $17B (about 15% of mobile IAP), and top games now almost all run one, but Apple's commission is not final and Google keeps a fee, so the margin gain is real but uncertain.

### Cited Findings
Apple (US):
- April 2025: court found Apple violated the anti-steering injunction by charging 27% on web purchases that originated from iOS apps and barred any commission on link-outs. HIGH — [9to5Mac, 2025-12-11](https://9to5mac.com/2025/12/11/apple-defeats-ban-on-charging-commission-on-linked-out-purchases-from-ios-apps/)
- Apple updated its App Store Guidelines on 2025-05-01; US apps can show buttons and links to web payments. MEDIUM (search summary) — [Median.co explainer](https://median.co/blog/epic-v-apple-payment-links-ruling-explained)
- 2025-12-11: Ninth Circuit (No. 25-2935) affirmed contempt but reversed the blanket no-commission ban. Apple may charge a "reasonable, non-prohibitive" commission tied to actual costs; may require links to be no more prominent than its own IAP buttons (equal prominence is allowed); cannot charge for security or review. Until a rate is approved, Apple can charge no commission. HIGH — [Neonpay, 2025-12-15](https://www.neonpay.com/blog/the-latest-epic-v.-apple-appeal-ruling-december-2025-what-changed-for-game-developers); [9to5Mac](https://9to5mac.com/2025/12/11/apple-defeats-ban-on-charging-commission-on-linked-out-purchases-from-ios-apps/)
- 2026: Supreme Court agreed 2026-06-30 to review the contempt finding (arguments in the term beginning October 2026); on 2026-08-11 Judge Gonzalez Rogers denied Apple's stay and said she will set the commission on the evidence on remand. No commission rate had been set as of that report. HIGH — [Courthouse News, 2026-08-11](https://www.courthousenews.com/apples-fight-over-commissions-for-linked-out-app-store-purchases-continues-in-district-court/)
- Unverified: a Spanish-language article claims Apple proposed a 15% commission in 2026; I could not corroborate it. LOW — [Ecosistema Startup](https://ecosistemastartup.com/apple-propone-comision-del-15-para-compras-fuera-del-app-store-en-2026/)
- Outside the US, Neonpay says nothing has changed as of December 2025. MEDIUM — [Neonpay](https://www.neonpay.com/blog/the-latest-epic-v.-apple-appeal-ruling-december-2025-what-changed-for-game-developers)

Google (Play):
- Per Bain (2026-08-18), Google's baseline fee has been cut from 30% to 20%, as low as 15% under conditions, under its settlement with Epic. MEDIUM — [Bain Gaming Report 2026](https://www.bain.com/insights/game-distribution-half-your-players-already-buy-direct-gaming-report-2026/)
- Other reporting describes a different structure: 10% service fee on the first $1M of annual earnings (US/UK/EEA), 10% for auto-renewing subscriptions, 20% service fee for other purchases on new installs and 25% on existing users, a separate 5% billing fee if Google billing is used, and an "app download event" fee of $2.85 per app / $3.65 per game install for external-content-link installs; rollout starting 2026-06-30 and expanding to Australia in September, Japan and Korea by end-2026, global in 2027. MEDIUM-LOW (several news sites; one fetched page confirmed only the 10%/20% external programs, $1M threshold, and the install fees) — [Notebookcheck](https://www.notebookcheck.net/Google-cuts-Play-Store-fees-as-Epic-settlement-reshapes-Android-app-payments.1243278.0.html); [Android Headlines, 2026-06](https://www.androidheadlines.com/2026/06/google-play-store-external-billing-fee-changes.html); [Shopifreaks](https://www.shopifreaks.com/google-starts-cutting-play-store-fees-to-a-flat-10-service-fee-on-the-first-1m-and-allows-external-payment-links-making-good-on-its-epic-games-settlement/)

D2C / web shops:
- GDC and Appcharge 2026 report (survey of 1,200+ developers, Jan-Feb 2026; released 2026-06-25): mobile D2C revenue about $17B, roughly 15% of the $113.3B global mobile IAP economy; 92% of publishers expect D2C growth in 2026; D2C leaders report a 35% median revenue lift vs a 15% industry median; transaction fees 2-5% via a payment processor vs 15-30% on app stores. MEDIUM (vendor co-authored; vendor sells D2C) — [Foxdata summary](https://foxdata.com/en/blogs/mobile-game-d2c-revenues-hit-17-billion-why-publishers-are-pushing-beyond-app-stores/)
- Bain (Media Consumption Survey, n=5,339, June 2026): 47% of gamers bought from a developer web store in the past year; top-grossing mobile games with their own web store: 12% (2019), 44% (2024), 74% (2026); MTG and Playtika D2C share roughly 25-40%; margin gain 15-30 percentage points per direct transaction (Bain estimate); web-store payback typically within a year at midsize publishers. HIGH for survey and adoption; MEDIUM for margin and payback estimates — [Bain Gaming Report 2026, 2026-08-18](https://www.bain.com/insights/game-distribution-half-your-players-already-buy-direct-gaming-report-2026/)
- Stash's calculator assumes all-in webshop costs around 10% (chargebacks, tax, FX, fee) vs a 30% store cut. MEDIUM (vendor) — [Stash fee calculator](https://www.stash.gg/fee-calculator)
- US top-100 grossing IAP titles grew D2C revenue 46% (AppMagic, data to 2025-10-22). HIGH — [AppMagic via GameDev Reports](https://gamedevreports.substack.com/p/appmagic-mobile-games-monetization)
- Unity reports top-100 titles grew D2C earnings by an estimated 38% in 2025 (search summary). LOW-MEDIUM — [Unity web shop business case](https://unity.com/blog/mobile-game-webshop-business-case)
- Neonpay: with the 27% fee plus over 3% processing, developers would have paid more than 30% total on link-outs, which is why the court found it prohibitive. MEDIUM — [Neonpay](https://www.neonpay.com/blog/the-latest-epic-v.-apple-appeal-ruling-december-2025-what-changed-for-game-developers)
- Sensor Tower's IAP figures exclude D2C, so store-reported IAP understates total spend. HIGH — [Sensor Tower via GameDev Reports](https://gamedevreports.substack.com/p/sensor-tower-the-state-of-the-mobile)

### Contradictions
- D2C adoption: Bain says 74% of top-grossing mobile games run a web store in 2026; AppMagic says the share of US top-100 IAP titles using D2C tools fell from 72% (end 2024) to 62% (H1 2025). The two measure different things (all global top-grossing vs US top-100; "tools" vs "own store"; different dates), so cannot be treated as a trend reversal; flag for the writer.
- Google fee: Bain says baseline cut to 20% (as low as 15%), while news reports describe 10% on first $1M with 20-25% above it plus a 5% billing fee. Unreconciled; both depend on settlement approval status, and sources disagree on whether court approval was complete.
- Apple fee: the "15% proposed" claim (one Spanish blog) is unverified. Nothing was found confirming a final rate.

### Inferences
- Margin gain depends on which fee wins: at 0% Apple commission and about 3-10% processing, a developer keeps 20+ points more than the 30% store cut; at a hypothetical 15% commission the gain halves. This is arithmetic from the sourced figures, not a sourced forecast.
- The sustained incentive is to push payers to the web with web-only bonus bundles. I found no primary example with figures; treat as inference.

### Gaps
- No up-to-date (Sept-Oct 2026) status of the Apple commission remand or the Supreme Court case beyond 2026-08-11.
- Apple fee changes outside the US (EU DMA, Japan) not researched.
- No data on which genres or which payer tiers are migrating to D2C first (Foxdata article gave no genre breakdown).
- Effects of D2C on retention/offer design (web-exclusive bundles) not sourced.

---

## Cross-cutting limits and coverage
- About 33 tool calls (search and fetch) were made; roughly 22 distinct pages were fetched. Pages returning errors: Sensor Tower State of Mobile Gaming 2025 PDF (size limit), ACM paper (HTTP 403), pocketgamer.biz starter bundles (HTTP 403).
- Mobile Dev Memo, Deconstructor of Fun, Naavik, and GDC talk pages did not surface in searches; no content from them is cited.
- Many search-summary-only items are labeled MEDIUM or LOW above; the report writer should prefer the HIGH-labeled AppMagic, Moloco, Sensor Tower (via GameDev Reports), Bain, Liftoff/Singular, and Courthouse News/9to5Mac items.
