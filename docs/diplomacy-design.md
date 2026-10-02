# Diplomacy design (proposal, awaiting approval)

Status: proposal (2026-10-01). No game code yet. It follows constitution.md "Faction behavior and diplomacy", "Minor factions", "Battles and armies" and the confirmed treaty, betrayal and loss rules. Every number is a placeholder for `data/diplomacy.json`. Section 13 lists the open questions, each with a recommended answer.

V1 scope (docs/v1-scope.md) asks for basic diplomacy: war, peace, trade and alliance. This design covers those fully. It leaves hooks for marriage, subordination and confederation, which need the character system or are not V1.

## 1. Diplomatic states between two factions

| State | Meaning | Attacking the other side |
|---|---|---|
| **War** | Armies may attack each other's armies and settlements. | Allowed. |
| **Neutral** | No treaty: the starting state (constitution: neutral start). | Requires a declaration of war (section 9). Not a betrayal. |
| **Ceasefire** | A treaty pausing a war. Converts to Neutral when it ends unless peace is signed. | **Betrayal** (section 7). |
| **Peace** | A treaty ending a war. Stays until cancelled. | **Betrayal**. |
| **Alliance** | Peace plus mutual defence, shared military access and calls to arms. | **Betrayal**. |

Agreements that can be added to any non-war state:
- **Trade.** Can be cancelled at any time with no betrayal, as the constitution says.
- **Military access.** Can be cancelled at any time.

**Treaty protection** (confirmed): a ceasefire, peace or alliance is protected for **20 turns** from signing. My reading of the constitution's "protected post-treaty period":
- A treaty cannot be cancelled during its first 20 turns.
- While a treaty stands, including that protection, attacking the other faction is betrayal.
- After a treaty is cancelled (only possible once its protection has passed), the two factions are Neutral, and war needs an ordinary declaration.

Section 13 asks you to confirm this reading.

## 2. Relationships: attitude, tendencies, prejudice and willingness

The constitution separates two things: a faction's *tendencies*, which others account for, and *relationship bonuses*. This design keeps four layers apart:

1. **Attitude** (−100 … +100) is how a faction feels about another. It is the sum of **modifiers**, each with a value and a decay per turn. It starts at 0 for everyone (constitution: neutral starting relations).

   | Modifier (placeholder) | Value | Decay |
   |---|---|---|
   | You attacked us / declared war on us | −40 | 1 per turn, floor −20 while at war |
   | You attacked our ally | −15 | 1 per turn |
   | You attacked a faction we like (attitude > 40) | −5 | 0.5 per turn |
   | Alliance with us | +25 | none while it lasts |
   | Marriage (hook, character system) | +20 | none while both live |
   | Trade with us | +10 | none while it lasts |
   | Common enemy at war | +10 | none while it lasts |
   | Gift of gold (per 1,000) | +5, max +20 | 1 per turn |
   | Trespass (section 8), per army per turn | −2, max −20 | 1 per turn |
   | We are at war | −20 | none while it lasts |
   | Broke trade with us | −10 | 0.5 per turn |
   | Refused our call to arms | −15 | 0.5 per turn |
   | Abandoned us mid-war (left the alliance) | −30 | 0.5 per turn |
   | **Betrayer** (betrayal rule) | −100, permanent | none |

2. **Tendencies** (passive, income-focused, generous, kind, expansionist, cruel, treacherous; already in `data/factions.json` traits) are **reputation**: what everyone knows about how a faction *acts*. They are **not** attitude points. They change other factions' *expectations*, through three fixed channels:
   - **Threat** (already in the campaign AI as "wariness"). A cruel or treacherous neighbour's armies count as a threat even at Neutral, so others keep stronger garrisons and are more willing to ally against it. A kind or generous neighbour's armies count less.
   - **Trust.** Every agreement with a faction is valued × its reliability: treacherous 0.6, cruel 0.85, income-focused 1.0, kind and generous 1.1 (placeholders). A treacherous faction's trade or alliance offer is worth less, because others expect it to break trade, abandon allies or refuse calls (constitution).
   - **Fear of conquest.** Expansionist and cruel factions raise others' value of alliances and defensive deals *against* them.

   So two factions can both sit at attitude 0 toward a kind and a cruel neighbour and still act differently: they garrison against the cruel one, discount its promises, and look for allies against it. Attitude says "how much we like you". Tendency says "what we expect you to do". A relationship bonus would wrongly make a cruel neighbour simply "liked less". Reputation makes it *distrusted and feared*, which is different. A cruel neighbour that treats you well can still be liked (high attitude) but feared (threat stays).

3. **Permanent prejudice** is a fixed attitude modifier between peoples that never decays (data, by race and by faction pair). docs/world.md: the orc tribes and the northern human realms hate each other. The **Redhand Warband** is the orc faction open to friendship with men, and despised by other orcs for it.
   - Placeholder: −60 between hating pairs.
   - A minority of factions (the Redhand, possibly the Riverlands minor houses: world.md's friendship story) have **no** prejudice toward the other race. Instead they carry a −20 "betrayer of its kind" prejudice from their own race's haters.

4. **Willingness to negotiate** is a hard gate per faction pair and proposal type, separate from attitude.
   - The Ironjaw Horde will never sign an alliance or trade with a human realm, whatever the attitude, but it will accept a ceasefire when losing.
   - Prejudice lowers attitude; unwillingness removes options. The diplomacy screen shows the reason ("The Ironjaw Horde will not ally with men").

## 3. The relationship web

- **Attacking** a faction (declaring war, or attacking its army or settlement while Neutral) applies "You attacked us" to the **victim** strongly (−40). It applies "You attacked our ally" to the **victim's allies** (−15), and a small hit (−5) to factions with attitude > 40 toward the victim. This is the constitution's "strongly with the victim and less with its allies".
- **Alliances and marriages** improve relations (+25 and +20, above). Marriage is a hook: the item exists in the proposal builder, greyed out with "Requires the character system".
- **Threat spreading:** a declaration of war by an expansionist or cruel faction raises every neighbour's fear of it (section 2, channel 3). Its targets become more willing to ally with each other.

## 4. Bundled offers: items, eligibility and AI valuation

A proposal is a list of items **offered** and **demanded**; either side may be empty (gifts, demands). The AI values each item in **gold equivalents**, *v*. A proposal's score for the receiving AI is:

> score = Σ v(what it gets) − Σ v(what it gives) + attitude × `attitude_weight` + state bonus (war weariness, threat) − reluctance (personality)

It accepts when score ≥ 0.

| Item | Eligibility | AI value *v* (to the receiver, placeholder) |
|---|---|---|
| **Gold, lump sum** | ≤ giver's treasury; not while in debt | amount |
| **Gold, tribute per turn** (N turns) | giver's net income ≥ amount | amount × N × 0.7 (risk of non-payment), × trust |
| **Resource tribute** (a share of one resource's income for N turns) | the giver has that endowment | income share × N × 0.8, × trust |
| **Land** (a settlement) | owned, not besieged, not the giver's last settlement, not a landmark seat or capital (section 13, Q8) | (income × 15 turns) + strategic value (border, walls, endowments) + 2,000 if it borders the receiver |
| **Troops** (actual units: the constitution's army tribute) | units in an army inside one of the giver's settlements; arrive as a detachment (section 6) | recruitment cost × men ratio × rank bonus, if the receiver can pay their upkeep |
| **Marriage** | hook: requires the character system (greyed out) | — |
| **Alliance** | both at Peace or Neutral; no war between them; willingness | (threat reduced by the ally's power) − (risk of being dragged into the ally's wars), × trust |
| **Ceasefire** | at war | weariness relief + odds-based loss avoided, for the losing side; small for the winner |
| **Peace** | at war or in ceasefire | the same, larger; demands such as land or gold are usually attached by the winner |
| **Trade** | Neutral, Peace or Alliance; trade-willing; a connection (section 9) | expected trade income × 20 turns, × trust |
| **Military access** | Neutral, Peace or Alliance | small; negative if the receiver fears the giver (cruel or expansionist) |
| **Join war against X** | the giver is not at a protected treaty with X (no AI betrayal) | value of X's defeat to the receiver × the giver's power share |
| **Cancel trade or alliance with X** (demand) | the giver has that agreement | X's value to the giver, as a cost |

- **War weariness** grows each turn at war and with losses, and decays at peace. It feeds the ceasefire and peace values, so long losing wars end. **This is what replaces "wars never end".**
- **Reluctance:** proud and expansionist factions dislike giving land or tribute (× 1.5 cost); generous ones give gold more cheaply (× 0.7 cost); kind ones accept peace more readily (+ value).

## 5. Allies and wars

When a faction goes to war or is attacked, it may send a **call to arms** to each ally. Each ally chooses one of three answers:
1. **Join:** declare war and become a belligerent.
2. **Support only:** send gold, resource tribute or troops without becoming a belligerent. Its relations with the enemy take only a small hit (−5), as the constitution requires ("supporting an ally does not automatically mean joining its war").
3. **Refuse:** a "Refused our call" penalty with the ally.

How the AI chooses:
- **Join** when the war's odds are good and the enemy is a threat or disliked.
- **Support** when it values the ally but fears the enemy, or is far away.
- **Refuse** otherwise.
- **Treacherous** factions refuse more often (× 2 refusal weight) and may **abandon** an ally mid-war by cancelling the alliance once its protection has passed. This is allowed and not a betrayal: the betrayal rule covers attacking, not leaving.

## 6. Troop transfers (actual troops)

- Units given in a deal leave the giver's army in one of its own settlements.
- They travel as a **detachment** to the receiver's nearest settlement, arriving after (distance ÷ one turn's movement) turns. They then join the receiver's army there, or form a garrison army if none is present (within the army cap).
- Until they arrive, the giver still pays their upkeep.
- If the receiver loses that settlement first, the detachment returns home.

## 7. Betrayal (confirmed rule)

Attacking a faction while a ceasefire, peace or alliance stands, including its 20-turn protection, makes the attacker a **Betrayer**:
- irreversible war with **every** faction
- permanent loss of all allies and trade partners
- the permanent −100 modifier

Only loading an earlier save undoes it. Cancelling trade never triggers it.

- **The player** may still attack. A confirmation dialog states the consequences in full: "This breaks your peace with House Lannet. Every faction will declare war on you, forever."
- **The AI never does** (hardcoded, confirmed). Its attack and war planners skip any faction it holds a treaty with. Treacherous AI shows treachery only through cancelled trade, refused calls and abandoned alliances.

## 8. Military access and trespass

This replaces the current "armies move freely until diplomacy exists" rule (confirmed as temporary).

- **Own, allied, or with an access agreement:** free movement, no penalty.
- **At war:** enemy territory; no trespass (it is war).
- **Neutral, Peace or Ceasefire without access:** movement is allowed, but each army-turn there is **trespass**: −2 attitude per army per turn (max −20), and the owner's AI treats the army as a threat. No automatic war.
- An army that ends its turn adjacent to a neutral settlement triggers a warning to that faction (AI: higher threat; player: an event message).
- Replenishment counts allied and access territory as friendly (`core/armies.gd` region_owner check), and every other foreign region as enemy, as now.

## 9. Trade agreements

- **Connection required:** a land route through non-hostile territory between the two capitals' regions, or both factions holding a port settlement. This uses the existing road and movement grid and the port building.
- **Income:** each partner gains `trade_share` (placeholder 8%) of the other's settlement income, × (1 + 0.5 per endowment the partner has and you lack), × road/port bonus. It is capped at 25% of your own income. The ledger shows it as "Trade with House Lannet +312".
- This fits the constitution ("trade agreements, partners, roads, ships … affect how effectively resources generate gold"). Detailed pricing stays open.
- **Cancel** at any time: no betrayal, and a "Broke trade" penalty with the partner. Treacherous AI cancels when the partner is at war and losing, or when a better partner appears.

## 10. Minor factions (proposal; the constitution leaves the exceptions open)

The constitution wants minors attackable "without wider diplomatic repercussions", but not as free targets.

- Minors carry a `minor` flag in `data/factions.json`.
- **Attacking an unprotected minor** costs relations **only with the minor itself**, plus anyone with a **protection pact** with it. The web's ally and third-party penalties are skipped.
- Minors can sign only **Ceasefire, Peace, Trade, and protection** with majors. A *protection pact* is a major's guarantee: an alliance-lite treaty where only the major defends. Minors cannot join wars as belligerents.
- Treaties with minors are still **protected** (20 turns, betrayal rule), so a peace with a minor is honoured. A minor's value is that you need not *make* peace with it.
- **Consolidation** (constitution: absorbing same-race minors by conquest, confederation, marriage, subordination): conquest works now. Confederation and subordination are listed as V2 hooks.

## 11. The diplomacy screen (Total War: Warhammer III layout and flow)

Constitution UI direction: the campaign UI should heavily resemble TW:WH3. The diplomacy screen is a full-screen panel (round menu button "Diplomacy", top-left) with the TW:WH3 arrangement:

- **Left: faction list.** Every met faction with its emblem, name, diplomatic state icon (war, neutral, ceasefire, peace, alliance) and an **attitude face** (TW-style, five steps from hostile to friendly) with the attitude number on hover. Filters: All, At war, Allies, Neighbours. A treaty's remaining protection shows as a lock with turns left.
- **Centre-top: the two factions** side by side (your emblem, theirs), their tendencies as trait icons (reputation), and the current treaties and agreements between you.
- **Centre: proposal builder.** Two columns, "You offer" and "You demand", filled from an item palette grouped as in TW:WH3: Treaties (Peace, Ceasefire, Alliance, Military access, Trade), Payments (Gold, Tribute, Resource tribute), Land, Troops, War (Join war against…), and Marriage (greyed out, with a hook tooltip). Ineligible items are greyed out with their reason.
- **Bottom: live acceptance indicator.** A TW-style bar from "Will not accept" to "Very likely", with the 0 line marked. It updates as items are added (it re-scores the bundle each time). A "Balance" button lets the AI suggest what would make it acceptable, as TW's "What would it take?" does.
- **Right: their reasoning**, the "why" list as in TW:WH3:
  - each attitude modifier with its value and decay ("You attacked our ally −15, fading")
  - tendency effects ("You are known as cruel: they fear your armies")
  - the item values ("Wants: Greyhaven +2,400")
  - willingness gates ("Will not ally with men")
- **Buttons:** Propose, Clear, Declare war (with the betrayal warning when a treaty stands), Cancel agreement (shows protection turns left).
- **AI proposals to the player** arrive as an Event Messages entry with a pop-up (accept, counter in the screen, decline), at most one per turn per faction.

## 12. Retiring the temporary war rule

The temporary rule ("attacking another faction's army or settlement declares war after a confirmation; no peace until diplomacy") is replaced by:

- **Neutral target:** ordering an attack opens a **declaration of war** dialog. It lists the relationship consequences (victim −40, its allies −15, which allies may answer its call). Confirming sets War and applies the web effects; the attack proceeds.
- **Treaty target:** the **betrayal** dialog (section 7). The AI never reaches this.
- Wars end through **ceasefire or peace**, driven by war weariness and odds (section 4).
- The campaign AI's war decision (`core/ai.gd`: aggression, weakness, personality) moves into the diplomacy layer. War becomes one option among offers: a faction that can get land or tribute by demand does not need to fight. Its targets exclude treaty partners.
- The constitution's implementation note on the temporary rule is updated when this is built.

Code, after approval:
- `core/diplomacy.gd`: states, treaties, attitude modifiers, valuation, calls to arms
- `data/diplomacy.json`: every number above
- `ui/diplomacy_screen.gd`
- state additions: relations, treaties, weariness and trade, saved (save schema 4 with a migration)

## 13. Validation plan

**GUT tests:**
- Attitude modifiers apply and decay.
- The web: the victim −40, its allies −15, others only if they like the victim.
- Tendencies change threat and trust, not attitude.
- Prejudice is permanent; willingness gates hide options.
- Each item's eligibility.
- Valuation is monotonic: more gold is never less acceptable.
- The AI never attacks a treaty partner over 100 seeded turns, betrayal count = 0.
- Player betrayal triggers war with all factions and loses allies and trade.
- Treaty cancellation is blocked during protection.
- Trade income appears in the ledger and needs a connection.
- Trespass penalties accrue and military access removes them.
- Calls to arms resolve as join, support or refuse.
- Troop transfers arrive as actual units.
- Minor-faction attacks skip the web.
- Save/load keeps every diplomatic state.

**Soak tests** (extend `scripts/ai_soak.gd`; 8 seeds × 100 turns, all AI, plus a variant map with more factions when the V1 map exists). Proposed targets:

| Measure | Target |
|---|---|
| Wars end | ≥ 70% of wars end in ceasefire or peace within 25 turns |
| Peace holds | 0 AI betrayals; ≥ 80% of peace treaties still standing 20 turns after signing |
| Alliances form | at least one alliance per campaign on average; alliances against cruel or expansionist factions more often than against kind ones |
| Treacherous factions behave differently | cancel trade ≥ 2× as often, refuse calls ≥ 2× as often, abandon allies at least occasionally, and never betray a treaty |
| Kind and generous factions | accept peace sooner (shorter wars) than cruel ones |
| Trade | income share between 5% and 25% of faction income where trade exists |
| Determinism | identical results per seed, including across a save/load |
| Performance | diplomacy evaluation ≤ 10 ms per AI faction per turn in the debug build (bundle scoring is cheap; proposals capped per turn) |

## 14. Open questions (batched, each with a recommended answer)

1. **Treaty protection reading.** Is the 20 turns counted from signing (the treaty cannot be cancelled before then, and attacking while it stands is betrayal), or a period after a treaty ends? *Recommended: from signing, as in section 1. After a cancellation the factions are Neutral, and war is an ordinary declaration.*
2. **Ceasefire length.** *Recommended: a ceasefire lasts until its 20-turn protection ends, then reverts to Neutral unless peace is signed.*
3. **Attitude numbers and decay** (the section 2 table). *Recommended: adopt as placeholders in data and tune by soak test.*
4. **Which peoples hate each other permanently.** *Recommended:*
   - the Ironjaw Horde and Frostmaw Clans hate all human realms (−60)
   - House Varn and the Wardens of the Greywall hate all orcs (−60)
   - the Redhand Warband and the Riverlands minor houses have no race prejudice, and carry −20 from the other orcs
   - everyone else neutral, until races beyond humans and orcs are designed
5. **Willingness gates.** *Recommended: the orc haters never ally or trade with humans (and vice versa for the haters on the human side), but always accept a ceasefire or peace when weariness is high.*
6. **Tendency trust factors** (treacherous 0.6, cruel 0.85, kind and generous 1.1). *Recommended: adopt as placeholders.*
7. **Minor factions.** *Recommended: section 10. Attacks on unprotected minors hit relations only with the minor and its protectors; minors sign only ceasefire, peace, trade and protection; their treaties are still protected.*
8. **Land in deals.** *Recommended: any settlement except the giver's last, its capital and landmark seats (Goldspire Rock, Highbloom…), which change hands only by conquest.*
9. **Troop transfer travel.** *Recommended: detachments travel (section 6) rather than appearing instantly.*
10. **Player betrayal.** *Recommended: allow it, behind a dialog that spells out the permanent consequences.*
11. **AI proposals to the player.** *Recommended: yes, at most one per AI faction per turn, as Event Messages pop-ups; the player can turn them off per faction.*
12. **Third-party reaction to declarations of war.** *Recommended: only factions that like the victim (attitude > 40) react (−5), plus increased fear of expansionist or cruel attackers.*
13. **Contact.** Can you negotiate with factions you have not met? *Recommended: contact is needed (a shared border, or having seen one of their armies or settlements). On the prototype map all factions are in contact.*
14. **Vassals, confederation and marriage.** *Recommended: not V1. Marriage is a greyed-out item; confederation and subordination are listed for V2, once the character system exists.*
15. **Peace terms that last** (tribute for N turns). *Recommended: tribute stops if the payer goes into debt (no debt from tribute), and stopping it is not betrayal but costs −20 attitude.*
