# Design Ethics and Compliance

Each recurring hook leans on a human tendency. This guide names the tendency behind each, says how solid the evidence is, and sets the compliance floor that regulators and the app stores now enforce.

Evidence: academic papers, regulators and law-firm briefings, named inline with HIGH, MEDIUM or LOW. The feature-to-tendency mapping is this kit's synthesis, built on loyalty-card and slot-machine studies; no peer-reviewed source maps game features to psychology one to one. The legal picture is dated 2026-10-22.

## Decision rule

1. **Meet the compliance floor in every game.** Disclose odds for any random reward that can be bought (Apple has required it since December 2017 and Google Play since May 2019; the current policy text was not rechecked, [Fenwick](https://www.fenwick.com/insights/publications/apple-now-requires-disclosure-of-loot-box-odds), [PocketGamer.biz](https://www.pocketgamer.biz/google-play-developers-must-now-disclose-loot-box-odds), MEDIUM). Show prices in real money, not only in game currency. Handle minors deliberately (interview 4). The floor follows from the enforcement below, which attaches to deception and to children and not to engagement mechanics.
2. **Apply three tests to any hook.** (a) Would the player, shown exactly how it works and what it costs, still choose it? (b) Does it work through anxiety, shortage or obligation, or through competence, relatedness and enjoyment? (c) Is the audience likely to include children? The tests are a synthesis of the dark-pattern literature, Self-Determination Theory and the FTC and EU reasoning, not a published standard (MEDIUM). Mechanics regulators have challenged sit at the exploitative end: paid random rewards sold to minors, currency bundles that obscure price, time-limited pressure aimed at children. Progress bars, social play and mastery loops are largely uncontested in the sources found.
3. **Do not over-claim the psychology.** Use the table for design vocabulary and read the last column as a limit.
4. **Re-check the legal snapshot before launch.** It moves faster than any other part of this kit.

## Feature to tendency

| Feature | Tendency it leans on | How solid |
|---|---|---|
| Daily login reward | Habit loop of prompt, ability and motivation (Fogg behavior model, HIGH); goal gradient across a calendar; loss avoidance when a missed day resets the streak | Links MEDIUM. China's December 2023 draft proposed banning daily login rewards, which shows regulators treat them as a hook (draft withdrawn, MEDIUM) |
| Streak | Loss avoidance; endowed progress once the streak is above zero | Loss aversion is contested; effect in games untested |
| Timers, energy, lives | Scarcity and impatience; a 2022 heuristic evaluation (Dahlan and Susanty) labels them "Playing by Appointment" and "Pay to Skip" dark patterns ([deceptive.design](https://www.deceptive.design/articles/finding-dark-patterns-in-casual-mobile-games-using-heuristic-evaluation)) | MEDIUM |
| Gacha, loot box | Variable-ratio reward, near-miss, opaque virtual currency | Near-miss evidence comes from slot machines; no source tests whether pity raises or lowers spending |
| Battle pass | Goal gradient and endowed progress (tiers visible and pre-filled), time-limited scarcity | MEDIUM; loyalty-card data, not game data |
| Collection, album | Completion motivation ([Quantic Foundry](https://gdcvault.com/play/1025742/A-Deep-Dive-into-the)) and ownership | Mapping is an inference |
| Clan, guild | Relatedness, one of three needs in Self-Determination Theory ([Ryan, Rigby, Przybylski 2006](https://www.rochester.edu/warner/lida/wp-content/uploads/2022/11/02bfe513dd59366750000000.pdf), HIGH), plus social obligation | Obligation claim MEDIUM |
| Starter pack | Barrier removal, anchoring, scarcity | EU consumer authorities list time-limited offers as a pressure tactic (MEDIUM) |
| Rewarded ad | Voluntary exchange; the most autonomy-preserving hook in the best case | No direct psychology source |
| Limited-time event | Urgency, fear of missing out, social proof via leaderboards | MEDIUM |
| Tutorial progress bar | Endowed progress, goal gradient | Transfer from loyalty cards to games is plausible but untested |

Solid findings behind the table:

- **Endowed progress**: a car-wash loyalty-card experiment found 34% redemption for a card with two stamps already added versus 19% for a blank card needing the same purchases ([Wharton Knowledge](https://knowledge.wharton.upenn.edu/podcast/knowledge-at-wharton-podcast/the-lowdown-on-customer-loyalty-programs-which-are-the-most-effective-and-why/), MEDIUM, secondary summary).
- **Goal gradient**: effort speeds up as the reward gets closer, shown with coffee-shop stamp cards ([Columbia Business School](https://business.columbia.edu/faculty/research/goal-gradient-hypothesis-resurrected-purchase-acceleration-illusionary-goal), HIGH for the study's existence).
- **Near-miss**: in a 2009 brain-imaging study a near-miss felt worse than a plain miss yet increased the urge to keep playing, but only when players felt in control ([Clark et al., Neuron](https://pmc.ncbi.nlm.nih.gov/articles/PMC2929454), HIGH for the main finding, small sample).

Contested, so do not build a design argument on them:

- **Zeigarnik effect**: the memory advantage for unfinished tasks failed to replicate in 2025; the tendency to resume an interrupted task held up, so the safe claim is "unfinished tasks pull you back" ([Ghibellini and Meier 2025](https://ideas.repec.org/a/pal/palcom/v12y2025i1d10.1057_s41599-025-05000-w.html), MEDIUM).
- **Loss aversion**: a large study found people of all experience levels loss averse ([Mrkva et al. 2020](https://imo.unisg.ch/wp-content/uploads/2020/12/01_jcpy.1156.pdf), MEDIUM), while a 2022 study that removed confounds found none for small amounts ([Judgment and Decision Making](https://dlab.sauder.ubc.ca/sjdm/journal/22/220414/jdm220414.html), MEDIUM).
- **Frameworks**: Fogg's model and Self-Determination Theory have academic backing. The Hook model and Octalysis are practitioner playbooks without controlled game trials (MEDIUM). Bartle's player types came from a 1989 to 1990 discussion among UK MUD players, and Bartle calls them "stereotypical" ([Bartle](https://mud.co.uk/richard/hcds.htm), HIGH).

## Harm and enforcement

- Loot box spending correlates with problem-gambling symptoms at r of about 0.26 (0.37 after a trim-and-fill correction; a later review notes the 0.26 figure included unpublished studies), a small to moderate link; the direction of cause is unresolved ([Garea et al.](https://figshare.utas.edu.au/articles/journal_contribution/Meta-analysis_of_the_relationship_between_problem_gambling_excessive_gaming_and_loot_box_spending/22996898/1/files/40746986.pdf), MEDIUM, abstract-level). A study of 726 collectible-card-game players found booster-pack spending had no significant link to problem gambling in physical stores and a trivial one online ([Zendle et al. 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC8023484), HIGH with sample caveats); a 2025 longitudinal study reported baseline loot box spending predicted starting conventional gambling six months later ([BMC Psychology 2025](https://biomedcentral-bmcpsychology.publicaciones.saludcastillayleon.es/articles/10.1186/s40359-025-02766-1), MEDIUM).
- **FTC and Department of Justice, January 2025**: Cognosphere (Genshin Impact) settled for a $20 million penalty, with terms barring loot box sales to under-16s without parental consent and requiring truthful odds and cost disclosure and a direct US-dollar purchase option; the court entry date is unconfirmed ([FTC](https://ftc.gov/business-guidance/blog/2025/01/level-tips-businesses-ftcs-settlement-genshin-impact-developer-hoyoverse), HIGH for the terms).
- **Epic Games (Fortnite), December 2022**: $245 million in refunds for dark patterns such as confusing buttons that led to unwanted charges, plus $275 million for children's privacy violations ([FTC](https://www.ftc.gov/node/80648), HIGH).
- **South Korea (about January 2024, exact date unconfirmed)**: Nexon Korea was fined 11.6 billion won for lowering gacha drop rates without telling players ([Siliconera](https://www.siliconera.com/nexon-fined-over-8-million-for-manipulating-item-drop-rates-in-games/), MEDIUM).
- **EU**: on 30 September 2026 the consumer-protection network announced eleven coordinated actions against ten named game companies, asking them to bring their in-game virtual currency practices into line with EU consumer law, with particular attention to variable-reward systems (loot boxes) aimed at or open to children, dark patterns and direct exhortation to children; the actions are not findings of breach ([joint statement](https://commission.europa.eu/document/download/75ff33d4-77a6-4f14-916a-766a8c6c281c_en?filename=CPC+Network+Joint+Statement+of+the+Consumer+Protection+Cooperation+Network+on+online+games.pdf), HIGH, read as a PDF). A Digital Fairness Act proposal is reported for November 2026 and is expected to cover dark patterns, addictive design, loot boxes and virtual currencies, but the text is unpublished and earlier timing slipped ([Lewis Silkin](https://www.lewissilkin.com/insights/2026/10/15/eu-consumer-protection-network-launches-action-involving-nine-video-games-compani-102o5do), LOW).
- **Brazil**: Law 15.211/2025 prohibits loot boxes in games accessible to minors and has been in force since 17 March 2026; enforcement practice was not found ([Machado Meyer](https://www.machadomeyer.com.br/en/recent-publications/publications/digital-law/law-15-211-25-protection-for-children-and-adolescents-in-the-digital-environment), MEDIUM).
- **China**: the December 2023 draft rules were withdrawn in January 2024 and no final rules were found ([RTTNews](https://www.rttnews.com/3418482/china-withdraws-online-gaming-restrictions-draft.aspx), MEDIUM). **UK**: self-regulation, with no update found after 2023 (MEDIUM).
- **Vietnam**: Decree 147/2024 requires verified player accounts and parent or guardian management of under-16 accounts; reports conflict on the time limits for minors, and no Vietnamese rules on loot boxes or gacha were found ([AP via Bangkok Post](https://bangkokpost.com/world/2926912/sweeping-vietnam-internet-law-comes-into-force), MEDIUM, conflicting).

## Gaps

- Sunk cost, anchoring, reciprocity, commitment and social proof are standard principles but were not sourced here.
- No practitioner ethics material was retrieved (Fair Play Alliance, GDC talks).
- Not researched: GDPR for children, the WHO gaming-disorder classification, gacha-specific harm to minors. Not found: Korea's statutory basis for odds disclosure, Japan's current rules, the current Apple and Google guideline text.

## Checklist

- [ ] Every random reward that can be bought has disclosed odds in the store listing and in the game.
- [ ] Prices appear in real money wherever currency is sold.
- [ ] Interview 4 is answered and the age handling matches it.
- [ ] Each hook passed the three tests in the decision rule, with the answers written down.
- [ ] The design does not rely on Zeigarnik or loss aversion as proof of effect.
- [ ] The legal snapshot was rechecked within the month before launch.
