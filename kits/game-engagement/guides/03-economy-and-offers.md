# Economy and Offers

How a game earns, how its currencies are balanced, and how offers, ads and web shops fit. The repeating offers in top games (starter pack, limited-time bundle, pass, piggy bank, "watch a video") are answers to one fact: spending is concentrated in a small share of players.

Evidence: Sensor Tower, AppMagic, Moloco, Bain, Unity and design essays, named inline with HIGH, MEDIUM or LOW. Platform-fee rules were checked as of 2026-08-11 and are still in court.

## Decision rule

1. **Pick the earning model from the genre.** Hyper-casual is almost all ads, casual leans toward in-app purchase, and hybrid-casual is described as roughly half ads and half purchases ([Sensor Tower, State of Mobile Gaming 2025](https://investgame.net/wp-content/uploads/2025/11/sensor_tower__state_of_mobile_gaming_2025__en.pdf), MEDIUM). Strategy, RPG and casino lean on purchases (Juego Studios, directional only, LOW). Global mobile game purchase revenue was about $81.75B in 2025, up 1.3%, gross of store fees and excluding Android China and web-shop sales ([Sensor Tower via GameDev Reports](https://gamedevreports.substack.com/p/sensor-tower-the-state-of-the-mobile), HIGH for the headline). Hybrid-casual was the fastest-growing segment in that report (secondary summary, MEDIUM); AppMagic's genre totals use a different scope and show strategy and puzzle growing.
2. **Design for concentration.** The top 2% of players generate 35 to 45% of purchase revenue and the top 10% generate 70 to 85% ([Moloco via GameDev Reports](https://gamedevreports.substack.com/p/moloco-mobile-market-status-and-growth), HIGH). Offers are tuned to find and keep the likely big spenders; ads and free rewards serve everyone else. No free, current benchmark exists for the share of players who pay or for revenue per daily active user, so measure both in the soft launch.
3. **Run two currencies with named faucets and sinks.** A soft currency (coins) is earned by playing and spent on routine progress. A hard currency (gems) is mostly bought with money and used to skip waits or buy exclusives ([Adrian Crook, 2016](https://adriancrook.com/?p=4918), MEDIUM). When faucets (rewards in) exceed sinks (spending out), the currency inflates ([MWM glossary](https://mwm.ai/glossary/game-economy) and design blogs, LOW). Soft-currency generosity sets how often a player feels pressure to pay, so economy tuning is also a retention lever (inference, MEDIUM; no quantified evidence).
4. **Shape offers as a ladder.** The recurring logic is a cheap, time-boxed, high-value first purchase, then bundles, passes and personalized offers above it. Evidence that each step raises conversion is vendor-published, and no source gives data for price anchoring, "best value" tags or daily deals; test them in the soft launch. One sourced fact: the average first purchase in top US RPGs is $17.90 on the App Store and $8.30 on Google Play ([AppMagic via GameDev Reports](https://gamedevreports.substack.com/p/appmagic-mobile-games-monetization), HIGH). That suggests payers differ by platform (inference, MEDIUM).
5. **Place rewarded video at pain points and cap interstitials.** Rewarded video (opt-in) is offered when a player runs out of lives, fails a level or lacks currency; interstitials (forced) are capped conservatively ([Unity/ironSource](https://unity.com/blog/3-ways-to-optimize-the-ad-experience-for-your-users), MEDIUM). In one vendor test, adding interstitials to a rewarded-only game raised revenue 17% and ARPDAU 18% and cut day-7 retention 2.3% ([ironSource case](https://is.com/?p=52105), MEDIUM, vendor case). The claim that rewarded-ad viewers retain and pay more is correlational, and the vendor concedes that people who choose to watch are probably more engaged (LOW as causal evidence).
6. **Decide on a web shop per market and genre.** Bain reports 74% of top-grossing mobile games ran their own web store in 2026, with an estimated margin gain of 15 to 30 points per direct purchase ([Bain Gaming Report 2026](https://www.bain.com/insights/game-distribution-half-your-players-already-buy-direct-gaming-report-2026/), HIGH for adoption, MEDIUM for margin). AppMagic measures a different base (US top-100 titles using direct-sale tools) and shows 72% falling to 62%, so the two figures do not show a trend. In the US, link-outs to web purchases have been allowed since an April 2025 ruling and an appeals court in December 2025 allowed Apple a "reasonable" commission (9to5Mac and Neonpay coverage, MEDIUM). That commission had not been set as of 2026-08-11, and the Supreme Court agreed in June 2026 to review the contempt finding ([Courthouse News](https://www.courthousenews.com/apples-fight-over-commissions-for-linked-out-app-store-purchases-continues-in-district-court/), HIGH). Google's fee structure is reported inconsistently (LOW). Casual titles take under 5 to 8% of revenue through the web ([Game Growth Advisor](https://gamegrowthadvisor.com/blog/2026-05-05-mobile-game-d2c-web-shop-strategy-2026/), LOW to MEDIUM); that live-ops RPG, 4X and casino titles gain most is this kit's inference.
7. **Expect payback to follow the model.** Ad-led games recoup acquisition cost over days to about a month; strategy and purchase-heavy games take far longer, which is why they build deep long-run systems like alliances, events and passes (inference, MEDIUM; the window figures are glossary-grade, [MWM](https://mwm.ai/glossary/payback-period), LOW).

## Default path

1. Choose the model from interview 2 and write the share of revenue expected from ads and from purchases.
2. List every currency with its faucets (where it enters) and sinks (where it leaves), and a rule for what happens when faucets win.
3. Draft the offer ladder: one first purchase, then bundles, then a pass. Mark each as a hypothesis to test in the soft launch.
4. Place rewarded video at the two or three moments where a player is blocked; start with no interstitial and add one only if the test shows revenue outweighs the retention cost.
5. Use `billing.in-app-purchase` for a one-time unlock. It covers one permanent unlock only; consumable currency packs, credit packs and subscriptions are outside it, and no block exists yet for a battle pass.
6. Revisit the web shop after launch (interview 10).

## Gaps

- No free current benchmark for payer conversion, ARPDAU, or the whale, dolphin and minnow thresholds; ranges in circulation are unattributed vendor figures.
- No citable data for price anchoring, "best value" tags, daily deals, bundle lifts or personalized-offer lift.
- Subscriptions (VIP, monthly card, ad-free pass) and premium games returned nothing usable.
- Hybrid-casual ARPDAU ranges conflict between sources, and Apple fee rules outside the US were not covered.

## Checklist

- [ ] The earning model matches the genre and is written into the contract.
- [ ] Every currency has named faucets and sinks.
- [ ] Offers are written as testable hypotheses with a metric each.
- [ ] Rewarded video is opt-in and sits at a blocked moment; interstitials are capped or absent.
- [ ] Payer conversion and revenue per daily user are measured from the soft launch.
- [ ] Web-shop exposure to the platform rules is decided per market.
