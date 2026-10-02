# Diplomacy design (revision 2)

**STATUS: APPROVED (2026-10-02).** All conflicts in section 17 and all open questions in section 18 were decided by the owner as recommended. Numbers remain placeholders for `data/diplomacy.json`.

History: revised 2026-10-02 to fit `docs/game-design.md` §7 (Reputation, decrees and suspicion) and §8 (Diplomacy, allies, vassals and puppets). No game code. Confirmed rules come from `constitution.md`; game-design items marked Proposed stay proposals here. Every number is a placeholder for `data/diplomacy.json`. Lore names follow `docs/world-bible-v2.md`.

**Approved 2026-10-02 (treaty question 1):** treaty protection is 20 turns counted from signing.
- A treaty cannot be cancelled during its first 20 turns.
- Attacking while a treaty stands is betrayal.
- After a treaty ends or is cancelled, an ordinary declaration of war applies.

Section 17 records how its conflicts with game-design.md were resolved; section 18 the adopted answers to its open questions.

## 1. Principles

- **TW:WH3 look and feel, CK depth through decisions** (constitution, Vision). The player sees TW:WH3's diplomacy screen: faction list with attitude, proposal builder, live acceptance, short reasons. Depth comes from events and choices: an embassy reveals a court, a captured spy confesses, a vassal asks for help. It does not come from modifier spreadsheets.
- **Numbers under the hood, words on the screen.** Attitude, reputation and suspicion are numbers in the simulation. The player sees TW-style labels, faces and a short list of reasons, never a CK opinion table.
- **The AI plays by the same rules and never betrays** (constitution, confirmed).

## 2. Diplomatic states and treaties

| State | Meaning | Attacking the other side |
|---|---|---|
| **War** | Armies may attack each other. | Allowed. |
| **Neutral** | No treaty: the starting state (game-design §3.4). | Needs a declaration of war (§7). |
| **Ceasefire** | A treaty pausing a war; reverts to Neutral when its 20-turn protection ends unless peace is signed. | **Betrayal**. |
| **Peace** | A treaty ending a war; stands until cancelled (possible after 20 turns). | **Betrayal**. |
| **Alliance** | Peace plus mutual defence, calls to arms and commandable help (§9). | **Betrayal**. |
| **Vassalage** | One faction serves another (§10). | **Betrayal** (either side). |

Agreements on top of a non-war state:
- **Trade:** can be cancelled at any time without betrayal (constitution).
- **Military access:** can be cancelled at any time.
- **Embassy:** can be closed at any time.

**Betrayal** (confirmed): attacking a treaty partner makes the attacker a Betrayer, with:
- irreversible war with every faction
- permanent loss of all allies and trade partners
- a permanent mark on both reputations

Only loading a save undoes it. The player can still do it, behind a dialog that spells out the consequences. The AI never does.

## 3. How factions see each other

Five layers stay separate:

| Layer | What it is | Changes |
|---|---|---|
| **Reputation** | What the world believes about a ruler and a House | through deeds and decrees |
| **Attitude** | How one faction feels about another, from shared history | through events between them |
| **Suspicion** | Unproven distrust of a neighbour | through suspicious events near you |
| **Prejudice and bloc** | Fixed feelings between peoples | never (prejudice) or by bloc |
| **Willingness** | Hard gates on what a faction will even discuss | by people, faith and state |

### 3.1 Reputation: ruler and House (game-design §7.1 to §7.4, confirmed)

- Each faction has a **ruler reputation** (moves relatively quickly, weighs more overall) and a **House reputation** (the dynasty's long memory, slow).
- Both are held on **reputation axes**, using game-design §7.3's list (Proposed): Trustworthy/Treacherous, Merciful/Cruel, Generous/Greedy, Peaceful/Expansionist, Pious/Impious, Liberator/Conqueror, Honorable/Dishonorable. Each axis runs −100 … +100. A label shows once an axis passes ±30, with a tooltip listing the deeds behind it.
- **Distance weighting** (confirmed): how another faction perceives you blends the two reputations by distance. Placeholder: perceived = w × ruler + (1 − w) × House, with w = 0.75 for neighbours, falling to 0.3 for distant factions (by travel turns between capitals).
- **First-impressions window** (confirmed): for about 10 turns after a new ruler takes power, deeds and decrees move both reputations about 3× faster (placeholder), in either direction.
- **Faction tendencies** (passive, income-focused, generous, kind, expansionist, cruel, treacherous; constitution) are kept in two places:
  1. **Seed** the House reputation at campaign start: a cruel House starts Cruel −40, a kind one Merciful +30, and so on.
  2. Drive the **AI's own behaviour**, as they already do in `core/ai.gd`.

  After the start, the world judges deeds, not labels. A treacherous House that keeps its word for decades drifts toward Trustworthy. An AI faction's tendencies keep pulling its own behaviour, so such drift is rare for it and possible for the player.
- **What reputation does** in diplomacy (the "reputation, not relationship points" rule from revision 1):
  - **Trust:** every agreement with you is valued × your perceived Trustworthy/Treacherous factor (0.6 … 1.1). Deals with a known Treacherous ruler are discounted.
  - **Threat:** a perceived Cruel and Expansionist reputation makes others garrison against you, value alliances against you, and treat your armies as threats at Neutral (the existing "wariness").
  - **Respect and fear:** Merciful, Generous and Liberator make minors and the oppressed more willing to become vassals or answer your Liberator's Call. Cruel makes the weak submit out of fear, and the strong ally against you.

### 3.2 Decrees as reputation levers (game-design §7.6, confirmed concept)

Decrees are the ruler's main deliberate way to shape reputation.

| Decree (examples from §7.6) | Axes moved (placeholders, per decree) |
|---|---|
| Lower taxes, grain doles | Generous +10 |
| Amnesty for rebels | Merciful +15 |
| Open trade | Generous +5, Trustworthy +5 |
| Honor old treaties | Trustworthy +15, Honorable +10 |
| Temple endowments | Pious +10 |
| Purge the court | Cruel −15 |
| Mobilize the realm | Expansionist −10 |
| Seize merchant gold | Greedy −15 |
| Punish a rebellious region | Cruel −10 |
| Forced conversion | Cruel −10, Pious ±10 by faith |

- Effects are ×3 during the first-impressions window.
- The number of active decrees is capped by Realm Standing (confirmed).
- **Diplomacy reads decrees:** an "Honor old treaties" decree raises the trust others place in your new treaties for as long as it is active.

### 3.3 Attitude: shared history (internal numbers, TW-style display)

- Attitude runs −100 … +100 per faction pair and starts at 0 (constitution: neutral start).
- It is the sum of remembered events between the two factions, each with a value and a decay:

  | Event | Value | Decay |
  |---|---|---|
  | You attacked us | −40 | |
  | You attacked our ally | −15 | |
  | Alliance | +25 | |
  | Marriage between our houses | +20 | |
  | Trade | +10 | |
  | Embassy | +5 | |
  | Common enemy | +10 | |
  | Gift (per 1,000 gold, max +20) | +5 | |
  | Released our captive | +10 | |
  | Trespass, per army per turn (max −20) | −2 | |
  | Broke trade | −10 | |
  | Refused our call | −15 | |
  | Abandoned us mid-war | −30 | |
  | Betrayer | −100 | permanent |

- **Display (TW parity):** the faction list shows an attitude face in five steps. The reasons panel shows the three to five biggest current causes as short phrases ("You attacked our ally, fading"). No full table, no numbers unless the player hovers.

### 3.4 Suspicion (game-design §7.7 and §7.8, Proposed)

- Each faction tracks **suspicion** of each neighbour (0 … 100). Every suspicious war, death, coup or rebellion near you nudges it up even without proof (placeholder +5 to +20 by event); it decays 2 per turn.
- **Suspected vs proven:**
  - *Suspected* acts add suspicion and a small attitude penalty (−5).
  - *Proven* acts (a captured low-level agent confesses, an intercepted letter) cost full reputation: Treacherous −20, and Dishonorable when an ally is the victim. They hit attitude with the victim (−30), and with all your allies if the victim was one of them. They may give the victim a war justification (§7).
- **Effects:** high suspicion makes your schemes against that faction harder and its counter-intelligence stronger, and lowers the trust it places in your new treaties (× 0.8 above 60). Pacing your plots is rewarded.

### 3.5 Prejudice, blocs and racial politics (game-design §3.4, §7.9, §8.7, confirmed)

- **Permanent prejudice** (never decays):
  - most orc tribes ↔ men −60; the **Redhand Warband** seeks friendship with men instead, and other orcs despise it (−20)
  - elves ↔ dark elves −60
  - lizardmen ↔ ratmen −60

  Dwarves are handled as **specific grudges** in the Book of Grudges rather than a blanket racial modifier. A grudge against a named House is −40 until avenged, and reminding the dwarves of a grudge is a scheme (game-design §6.3).
- **Blocs** (Order, Destruction, neutral):
  - **Same-bloc** deals get a bonus (+10 attitude-equivalent in valuation).
  - **Cross-bloc** deals cost more (−15). They also cost reputation with your own bloc ("Allied with orcs") and earn respect from the other bloc.
  - Neutral peoples (Tomb-King desert humans; lizardmen leaning Order) can be courted by both without the cross-bloc penalty.
- **Racial politics:** a human who schemes heavily against other humans gains quiet respect from Destruction peoples (+5 per proven scheme, max +20), and the reverse for Destruction schemers.
- **Cross-race marriage** (confirmed allowed): prejudiced factions and faiths disapprove (−10 with each); the other bloc may respect it (+5).

### 3.6 Willingness to negotiate

Hard gates per faction pair and proposal type, separate from attitude. The diplomacy screen shows the reason.
- The haters among the orc tribes never ally or trade with men, but accept a ceasefire or peace when war weariness is high.
- Elves never ally with dark elves.
- An anathematized faction cannot ally with faithful Throne Church realms (game-design §9.7, Proposed).

## 4. Information: embassies, dossiers and contact

- **Contact:** you can negotiate only with factions you have met: a shared border, or having seen one of their armies, agents or settlements (shroud, game-design §12.6).
- **Embassies** (game-design §8.2, confirmed):
  - Sending an embassy is a diplomatic action. A faction with no reason to refuse accepts. Reasons to refuse: at war, prejudice-gated, Betrayer, or suspicion above 80.
  - An embassy reveals that faction's **full court**: members, blurbs, who hates whom and why. It also gives vision of its capital region.
  - Factions **at war with you** close their embassies; seeing their court needs a **spy**.
  - Deeper information (true loyalties, secrets, hidden traits) always needs a spy embedded in that court (intrigue design).
- **Faction dossiers** (game-design §8.3, confirmed): for any faction you have visibility into, you can open:
  - its court, and each member's blurb
  - who hates whom and why
  - its perceived reputation labels, tendencies, treaties and wars

  Blurbs are written in the **Grey Scribes'** voice from what actually happened (`core/chronicle.gd`-style generators), so each faction reads like a chronicle. Information from a low-reliability source (a misinformed spy, game-design §6.8) is marked "by report".

## 5. The relationship web (constitution, confirmed)

- **Attacking** a faction applies "You attacked us" to the **victim** (−40) and "You attacked our ally" to its **allies and vassals** (−15).
  - It adds −5 with factions that like the victim (attitude > 40), and with the victim's suzerain or patron.
  - It nudges **suspicion** if the attack looks staged.
- **Alliances, marriages, trade and embassies** improve relations (§3.3).
- **Reputation spreads further:** an unjustified war or a proven scheme changes your reputation, which every faction sees, weighted by distance.

## 6. Bundled offers: items, eligibility and AI valuation

A proposal is a list of items **offered** and **demanded**. The AI values each in **gold equivalents**:

> score = Σ v(gets) − Σ v(gives) + attitude × `attitude_weight` + bloc term + state (war weariness, threat) − reluctance (tendencies)

Treaty-type items are valued × trust (§3.1, reduced by suspicion, §3.4). The AI accepts at score ≥ 0.

| Item | Eligibility | AI value *v* (placeholder) |
|---|---|---|
| Gold (lump sum) | ≤ treasury; not in debt | amount |
| Gold tribute (N turns) | net income ≥ amount | amount × N × 0.7 × trust |
| Resource tribute | the giver has the endowment | income share × N × 0.8 × trust |
| Land (a settlement) | not the last settlement, capital or a landmark seat; not besieged | income × 15 + strategic value |
| Troops (actual units) | units in an own settlement; travel as a detachment | recruitment cost × men ratio × rank, if upkeep is affordable |
| **Captive** (game-design §4.11, Proposed) | a captured family member or agent you hold | the captive's level, rank and family ties (an heir is worth most); +attitude when returned |
| **Secret** (game-design §6.8 and §8.1, Proposed addition) | a secret your spies hold about the receiver or a third party | about the receiver: blackmail value (it pays to keep it unleaked); about a third party: its intel or scheme value |
| **Marriage** (game-design §4.9, confirmed) | two eligible unmarried adults; needs the characters system | +20 attitude-equivalent; claims and Throne City influence for Church-aligned families |
| **Embassy** | contact, no reason to refuse | small; positive for everyone not hostile |
| Alliance | Neutral or Peace; willingness; not a Betrayer | (threat reduction by the ally's power) − (risk of its wars) × trust |
| **Vassalage** (§10) | see §10 | protection value vs lost independence |
| Ceasefire | at war | weariness relief + loss avoided |
| Peace | at war or in ceasefire | the same, larger |
| Trade | Neutral or better; trade-willing; a route (§12) | route income × 20 turns × trust |
| Military access | Neutral or better | small; negative if it fears you |
| Join war against X | no treaty with X (the AI never betrays) | X's defeat value × the giver's power share |
| Cancel an agreement with X (demand) | the giver has that agreement | X's value to the giver, as a cost |

- **War weariness** grows each turn at war and with losses, and decays at peace. It raises the value of ceasefire and peace, so wars end.
- **Reluctance:** proud and expansionist factions dislike giving land or tribute (cost × 1.5); generous factions give gold cheaply (× 0.7); kind factions value peace more.

## 7. War: declarations and justifications (game-design §8.8, Proposed)

- **The temporary rule retires.** War needs a declaration, from the diplomacy screen or the attack confirmation when you order an attack on a Neutral faction.
- **Justifications:** a grudge (Book of Grudges, past attacks), a claim (marriage or inheritance, a former holding), a **provocation** (proven schemes or raids against you, trespass beyond a limit), a **Holy War** call or an **Anathema** target (game-design §9, Proposed), or **defending an ally or vassal**. Schemes can manufacture justifications: a staged border raid, a forged insult.
- **Without a justification**, declaring war costs reputation (Peaceful/Expansionist −15, Honorable −10). The victim's allies treat it as unprovoked aggression (−20 instead of −15).
- The declaration dialog shows what will happen: the justification, or its absence and its reputation cost; who will be angered; which of the victim's allies are likely to join.

## 8. Allies, calls to arms and commandable allies

- **Calls to arms** (constitution, confirmed): an ally at war asks for help. Each ally chooses:
  - **Join** (becomes a belligerent)
  - **Support only** (gold, resources or troops, without becoming a belligerent; relations with the enemy take only −5)
  - **Refuse** (−15 with the caller)

  Treacherous factions refuse more often, and may abandon an alliance once its protection has passed (not betrayal).
- **Commandable allies** (game-design §8.4, confirmed): the player can give allies and vassals **specific orders**: attack this settlement, attack this army, defend this region, join this siege.
  - **Willingness** (0 … 1) comes from:
    - your economic and military dominance (the strongest economy in the region gets the most help)
    - their dependence on you
    - the rewards offered with the order
    - their personality
    - your perceived reputation
  - Weaker factions competing for your favour score higher.
  - **A genuine attempt** (confirmed): an accepted order commits **a real force**. The ally's AI assigns the army (or armies) that gives the best odds, at least `min_commit` of the needed power (placeholder 0.8 of the target's defence) or its strongest army. It marches until it attacks, besieges or the order is cancelled.
  - If it cannot commit a real force, it **declines openly** with the reason ("Our armies are needed at home"). It never sends a token army.
  - The order shows on the map as a TW-style objective marker with the ally's army path.
- Implementation hooks: orders become a new job type in `core/ai.gd` `_command` (above defend for vassals, below defend for allies), using the existing attack, besiege and march code with a pinned target.

## 9. Vassals (game-design §8.5, every route confirmed; obligations Proposed)

- **Routes to vassalage:**
  1. **War and surrender:** a losing faction may offer or accept vassalage in place of destruction or land.
  2. **Diplomacy:** a weak neighbour accepts protection for independence.
  3. **Debt:** a faction deep in debt sells its freedom for your gold.
  4. **Marriage:** your heir marries into a ruling house with a vassalage clause.
  5. **Protection from a bigger threat:** a faction facing a cruel, expansionist or Destruction power seeks a suzerain.
- **Obligations** (Proposed): tribute, troops on request, obeying war calls, following your diplomatic lead (no separate wars or alliances). **Loyalty and dependence** decide how reliably each is met.
- **Vassals commit real forces** to commanded orders (§8), with higher willingness than allies.
- **Independence:** a neglected, low-loyalty vassal can break away. It uses the small-rebellion rules (constitution): visible warning for several turns, at most one region at a time, and the Liberator's Call when its people dislike the rebel.
- **Culture variants** (game-design §10, Confirmed core, details Proposed): Roman **clients**, Medieval **feudal vassals**, Greek **league members**. They share this vassal model with culture-specific obligations and screens.

## 10. Puppets (game-design §6.6, confirmed)

- A **puppet** is a ruler you installed in another faction. Routes are the intrigue schemes: assassinate and back a weak heir, fund a coup, marry your candidate in, tip a succession, support a pretender.
- **Control scales with investment:**
  - A ward you raised and invested in obeys you like a vassal: commandable orders at the highest willingness, follows your diplomatic lead.
  - Someone you merely paid becomes a friendly ally, not a servant.
- **Skim:** a puppet skims its host faction's gold to you (confirmed; amount by investment, placeholder 5–15% of the host's income). Your own governors never skim.
- **Exposure:** a puppet relationship is secret. Discovery is a proven scheme (§3.4) against the host's other powers, and may cost you the puppet.

## 11. Military access and trespass

This is aligned with game-design §12.1: full movement at home and in allied land, drastically reduced abroad.
- **Military access** (an agreement) and **alliance** give **home-territory movement** in the partner's land. Outposts extend home movement too (confirmed).
- **Without access**, foreign land is entered at reduced movement. At Neutral, Peace or Ceasefire it is also **trespass**: −2 attitude per army per turn (max −20), and the owner's AI treats the army as a threat. A trespass limit gives the owner a **provocation** justification.
- At war, enemy territory is war, not trespass.

## 12. Trade (game-design §12.7, confirmed)

- A trade agreement creates a **trade route**: drawn on the map as a land or sea line with caravans and ships (visual only). It carries an **abstract income** for both partners.
  - Placeholder income: 8% of the partner's settlement income, × (1 + 0.5 per endowment you lack and they have), × a road or port bonus, capped at 25% of your own income.
- A route needs a **connection**: a land path through non-hostile territory, or ports on both ends.
- **Raiding:** a raiding army or fleet next to a route draws its income away. It harms relations but is not an act of war, and lowers public order in the raided province.
- Cancelling trade is free of betrayal, but costs −10 with the partner. Treacherous AI cancels when its partner is losing a war, or when a better partner appears.

## 13. Minor factions (game-design §8.6, Proposed)

- Minor factions start with **no allies** and carry a `minor` flag.
- Attacking an **unprotected** minor costs relations **only with the minor itself**. The web's ally and third-party penalties are skipped, and no war justification is needed (no reputation cost for an undeclared war on a minor).
- **Protection:** a major's explicit **protection pact** with a minor makes an attack on it count as an attack on the protector's ward. The protector gets −15 attitude and a justification, and the full web applies. So does a **Throne City edict** protecting a minor (game-design §9, Proposed).
- Minors sign ceasefire, peace, trade, embassy, protection and vassalage, but not alliances. Their treaties are still **protected**: the betrayal rule applies to every treaty.

## 14. The Throne City in diplomacy (game-design §9, Throne City confirmed, the rest Proposed)

- Caeloth is **untouchable**: it cannot be attacked or schemed against in V1 (confirmed). It has an embassy and dossier like any faction.
- Its edicts (Proposed) can protect minors, call Holy Wars (a justification for all faithful), and name **Anathema** targets (a justification against them; an alliance gate, §3.6).
- Throne City influence (confirmed) adds legitimacy, which feeds ruler reputation (Pious, Honorable).

## 15. The diplomacy screens (TW:WH3 parity)

- **Diplomacy** (round menu button, as in TW:WH3), full screen:
  - **Left:** faction list. Emblem, name, state icon, TW attitude face, treaty lock with protection turns left. Filters: All, At war, Allies, Vassals, Neighbours.
  - **Centre-top:** both factions with their **perceived reputation labels** (TW trait-style icons) and current treaties.
  - **Centre:** a **proposal builder** with "You offer" and "You demand" columns, filled from an item palette grouped as in TW:WH3: Treaties, Payments, Land, Troops, Characters (marriage, captives), Intelligence (secrets), War. Ineligible items are greyed out with their reason.
  - **Bottom:** a **live acceptance bar** (TW-style, "Will not accept" … "Very likely"), plus a "What would it take?" button.
  - **Right:** **their reasoning**, three to five short phrases: biggest attitude causes, reputation ("They think you are Treacherous"), suspicion ("They suspect you"), bloc and prejudice, willingness gates, and what they want.
- **Faction dossier:** opened from the faction list or the map. Court portraits and blurbs (Scribes' voice), who hates whom, reputation labels with their deeds, treaties and wars. Locked sections show what reveals them ("Send an embassy", "Embed a spy").
- **Orders to allies and vassals:** right-click on the map target with an ally's or vassal's army selected in the diplomacy orders mode, or from the dossier. Objective markers on the map, TW-style.
- **AI proposals to the player** come as Event Messages pop-ups (accept, counter, decline), at most one per AI faction per turn.

## 16. Validation plan

**GUT tests:**
- Reputation:
  - distance weighting blends ruler and House as specified
  - the first-impressions window speeds both up
  - decrees move axes
  - tendencies seed the House reputation only at start
- Attitude events and decay.
- Suspicion rises on suspicious events and decays; proven acts cost reputation and attitude with allies.
- Embassies reveal courts; at war they need spies.
- Every item's eligibility, including captives and secrets.
- Valuation is monotonic; trust and suspicion reduce treaty values.
- War justifications: an unjustified war costs reputation.
- Commandable orders:
  - an accepted order commits at least `min_commit` of the needed power, or is declined with a reason
  - no token armies over 50 seeded orders
- Vassalage by each route.
- Puppet skim and control by investment.
- Military access and trespass.
- Trade routes and raiding income.
- Minor factions skip the web unless protected.
- The AI never betrays, over 100 seeded turns.
- Save/load keeps every diplomatic state.

**Soak tests** (extend `scripts/ai_soak.gd`; 8 seeds × 100 turns, all AI; plus a Stage A map run):

| Measure | Target |
|---|---|
| Wars end | ≥ 70% of wars end in ceasefire or peace within 25 turns |
| AI betrayals | 0 |
| Peace holds | ≥ 80% of peace treaties still stand 20 turns after signing |
| Alliances | at least one alliance and one vassal per campaign on average |
| Treacherous factions | cancel trade and refuse calls ≥ 2× as often as others, and never betray |
| Kind and generous factions | shorter wars than cruel ones |
| Justified wars | a larger share than unjustified wars for factions with a Peaceful or Honorable reputation |
| Commanded orders | ≥ 90% of accepted orders produce a real attack or siege within 5 turns |
| Performance | ≤ 10 ms per AI faction per turn for diplomacy in the debug build, with staggered re-evaluation (game-design §17) |

## 17. Conflicts with game-design.md (resolved 2026-10-02)

| # | Topic | Decision |
|---|---|---|
| 1 | Modifier spreadsheets (game-design §1.3) | Attitude is numeric internally; the screen shows TW-style faces and three to five short reasons. Approved. |
| 2 | Tendencies vs earned reputation | Tendencies seed the House reputation and drive AI behaviour; perception then follows deeds, so labels can drift. Intended. |
| 3 | Military access | Follows game-design §12.1: movement is reduced abroad, and access agreements restore home movement. game-design §8.1 is corrected. |
| 4 | Marriage | A real tradable item. Approved. |
| 5 | Minor factions | No relationship penalty beyond the minor itself unless a major protects it. game-design §8.6 is updated. |
| 6 | War weariness | Approved as the mechanism that ends wars. |
| 7 | Unjustified wars | A reputation cost plus a heavier penalty from the victim's allies. Approved. |
| 8 | Dwarf grudges | Named entries in the Book of Grudges. Approved. |
| 9 | Embassies | Require prior contact. Approved. |
| 10 | Secrets and captives | Tradable items. Approved. |
| 11 | Orders to allies and vassals | Allies defend themselves first; vassals put the player's orders first. Approved. |

## 18. Former open questions (adopted 2026-10-02 as recommended)

| # | Question | Adopted answer |
|---|---|---|
| 1 | Ceasefire length | Lasts until its 20-turn protection ends, then reverts to Neutral unless peace is signed. |
| 2 | Reputation scale | Axes −100 … +100, labels at ±30, distance weights 0.75 near → 0.3 far, first impressions × 3 (tuned by soak). |
| 3 | Attitude events and decay | The section 3.3 values, as placeholders. |
| 4 | Prejudice pairs | Orc haters ↔ men −60, the Redhand friendly to men (−20 from other orcs), elves ↔ dark elves −60, lizardmen ↔ ratmen −60, dwarf grudges as named entries. |
| 5 | Land in deals | Never the last settlement, the capital or a landmark seat. |
| 6 | Troop transfers | Travel as captain-led detachments rather than appearing instantly. |
| 7 | Player betrayal | Allowed, behind a dialog that spells out the consequences. |
| 8 | AI proposals to the player | Yes, at most one per AI faction per turn; the player can mute them per faction. |
| 9 | Tribute and debt | Tribute pauses while the payer is in debt; not betrayal, but −20 attitude. |
| 10 | Puppet skim | 5% for a paid ruler, up to 15% for a raised ward. |
| 11 | Vassal obligations | Tribute 10% of income, troops on request, follows your wars, no independent alliances; loyalty below 30 makes each obligation a chance. |
| 12 | Throne City edicts protecting minors | Decided with the religion design; until then only major factions' protection pacts protect minors. |
