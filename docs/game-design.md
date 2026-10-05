# Project Freedom: Game Design Document

**Status:** Approved direction. Items marked Proposed still need owner approval before implementation.
**Companion:** `world-bible-v2.md` (lore, geography, factions, landmarks).
**Precedence:** `constitution.md` remains the source of truth for confirmed mechanics. This document records owner decisions from the design brainstorm (marked **Confirmed**) and design proposals that still need approval (marked **Proposed**). Numbers are placeholders unless stated.
**Already built (prototype):** economy with population taxes, construction, recruitment, movement, lane-based battles with deployment and replay, campaign AI, save/load, TW-style UI shell.


## 0. Rule changes (owner, 2026-10-05; `docs/war-and-realm.md` §0.2)

`docs/war-and-realm.md` and `docs/v1-content.md` are approved direction (2026-10-05). Their items marked **Proposed** still need the owner's approval before implementation. These rules replace earlier text in this document; the old text is kept below, marked *Superseded*.

| Earlier rule | New rule (Confirmed) |
|---|---|
| Deployment screen with lanes and orders; Quick Resolve default | **Battles are stance only** (Aggressive / Balanced / Defensive), then auto-resolve. The deployment screen and 2D replay leave V1's UI (code may stay dormant). The simulation treats each army as a block, so many stacks can fight on each side. |
| Gold is the only spendable currency; resources only raise income | **Gold, food, wood and stone** are real stockpiles. Gold rules and can buy the others at regional markets. |
| Confederation absorbs a faction | **Confederation = fealty.** The house swears to you and stays its own faction as a loyal vassal. |
| Embassies require prior contact | **Envoys can reach anyone**, travelling automatically; contact happens on arrival. |
| War ends trade | **Trade continues during war** with tariffs and disruption, unless raided, blockaded or cancelled. |
| Betrayal: permanent war with every faction | **Betraying an ally during an invasion turns you to Chaos** (a post-V1 playstyle). In V1 the current betrayal rule stays, flagged as the future Chaos trigger. |
| Free movement through foreign land until diplomacy | Fast in friendly land, slow in enemy land, and **large armies block passage** (zone of control scales with army size). |
| Campaign arc as fixed turn numbers | **Condition-driven Ages** that repeat and escalate (`war-and-realm.md` §8). |

---

## Contents
1. Vision and pillars
2. The player's experience
3. Campaign structure and starting situation
4. Characters, court, and dynasty
5. Careers, agents, and the spymaster
6. Intrigue and schemes
7. Reputation, decrees, and suspicion
8. Diplomacy, allies, vassals, and puppets
9. Religion and the Throne City
10. Races, cultures, and the three playable human cultures
11. Economy, realm, and order
12. The campaign map: movement, captains, outposts, trade, navies, magic
13. Research
14. Events, quests, items, and the chronicle
15. The freshness engine (1,000-turn campaigns)
16. Difficulty and campaign settings
17. AI requirements
18. UI screens (TW:WH3 parity)
19. V1 scope (revised)
20. Constitution changes required
21. Implementation roadmap
22. Open questions
23. Glossary

---

## 1. Vision and pillars

### 1.1 The one-line vision **(Confirmed)**
**"Crusader Kings depth, Total War look and feel."** The politics, dynasties, and intrigue of Crusader Kings, presented entirely through Total War: Warhammer III's map, UI, controls, and accessibility.

### 1.2 Pillars
1. **You are the mastermind.** The most satisfying victories are engineered, not fought: wars you started between others, kingdoms that collapsed from within, alliances broken by a forged letter, regions that invited you in. Armies still matter; they are one tool among many.
2. **Depth through decisions, not spreadsheets.** The owner finds Crusader Kings too intense. Depth arrives as meaningful events and choices (a jealous general, a marriage offer, a captured assassin who might talk). Routine administration runs automatically. The game surfaces what needs attention.
3. **Total War parity in everything the player touches.** Map interactions, camera, UI layout, panels, cards, tooltips, controls, notifications. Only the rules underneath differ. When unsure, research how TW:WH3 does it.
4. **Order at home, chaos abroad.** The player keeps control of their own realm: no civil wars, no surprise succession crises. The world around them is chaotic and exploitable.
5. **Your family is your toolkit.** Generals, assassins, spies, envoys, merchants, wizards, priests, warlords: all come from your court and family. Losing one is personal.
6. **A living, dark world.** Game of Thrones betrayal, Warhammer brutality. Leans dark.
7. **Sandbox forever.** No victory conditions. The joy is building an empire over hundreds or thousands of years and watching decisions play out. Freshness over time is a design requirement (Section 15).

### 1.3 What we are not
- Not a tactical battle game. Battles are simulated and stance-only (Aggressive / Balanced / Defensive, then auto-resolve; confirmed 2026-10-05, §0). *Superseded: deployment, orders and Quick Resolve as the default (2026-10-04).* Free deployment and a spatial simulation are no longer on the roadmap.
- Not a Crusader Kings clone. No opinion-modifier spreadsheets, no realm-splitting factions against the player, no succession-law micromanagement.
- Not a Total War clone. Politics, intrigue, dynasty, and religion are deeper than anything in Total War.

---

## 2. The player's experience

### 2.1 The perfect turn **(Confirmed)**
A turn should include several of:
- Moving armies and coordinating campaigns with allies and vassals.
- A few court decisions (career paths, marriages, rewards, appointments).
- Issuing agent missions through the spymaster: bribes, rumors, forged letters, marriage proposals, assassinations.
- Reviewing results of earlier missions and committing to the consequences.

**Rhythm:** every turn has a few small decisions. Every few turns, bigger consequences land: an assassin arrives at their target, an election is called, a puppet ruler is installed, a rebellion breaks out next door. The player must commit or adapt.

### 2.2 Turn length **(Confirmed)**
- Early game: about 1 minute per turn.
- Late game: 5 to 10 minutes per turn.
- Automation, notifications, and the End Turn blocking list (TW-style) keep late turns from becoming chores.

### 2.3 The first five minutes **(Confirmed direction; details Proposed)**
Research summary: Total War: Warhammer (2016) gave each race its own cinematic intro, an optional tutorial battle, and guided first turns via an "Enable introduction" checkbox. Warhammer III's prologue was praised for drip-feeding mechanics in bite-size explanations. Its sandbox start was criticized for a loading screen, a one-line greeting, and text dumps.

Our start sequence:
1. **Faction select:** three playable houses (one per human culture), each with founder portrait, house tradition, culture mechanics summary, difficulty indicator, and starting position on a map preview. Checkbox: **Enable guidance**.
2. **Illustrated intro:** 6 to 10 painted scenes narrated in text by the Grey Scribes, telling the house's history, the God-Emperor and the Seven, the end of the Long Stillness, and the immediate situation. Skippable.
3. **Court introduction:** meet the founder, family, and key courtiers. Each has a portrait, epithet, traits, loyalty, and one line of personality. The player picks the first career path for one child.
4. **Guided first turns (if enabled):** bite-size prompts across the first 10 to 15 turns covering movement, construction, recruitment, the spymaster, diplomacy, the Liberator's Call, and the Throne Church. Each prompt explains one thing and asks for one action.

### 2.4 Campaign arc **(Proposed)**
*Superseded (2026-10-05, §0): the campaign moves through condition-driven Ages (`docs/war-and-realm.md` §8). The phase table below is kept for history.*

| Phase | Turns (approx.) | Player focus | Event density |
|---|---|---|---|
| Opening | 1 to 10 | Absorb neighboring minor factions (war, marriage, diplomacy, Liberator's Call). Set children's careers. | High (front-loaded) |
| Rise | 10 to 60 | Regional power. First major rivals. First schemes. First puppet. Holy City influence. | Medium-high |
| Dominance | 60 to 200 | Commanding allies and vassals, manipulating wars, elections, Holy Wars, legendary characters reaching level 20. | Medium |
| Legacy | 200+ | Freshness engine events (Section 15), cross-continent politics, new powers rising, monsters awakening. | Medium, prominent |

---

## 3. Campaign structure and starting situation

### 3.1 No victory conditions **(Confirmed)**
Sandbox. The campaign continues indefinitely. Optional personal ambitions (Section 14.3) give direction without "winning."

### 3.2 Small, humble starts on a crowded map **(Confirmed)**
- Every faction (player and AI) starts small: one or two settlements.
- The map starts **crowded**: many minor factions, consolidating quickly into a few dozen powers, as in TW:WH3.
- **Every major faction is surrounded by a few small minor factions** it can absorb within about 10 turns through war, diplomacy, marriage, or the Liberator's Call.

### 3.3 The Liberator's Call **(Confirmed concept; details Proposed)**
Many factions start next to a minor faction ruled by a **hated lord**. Early in the campaign (turns 2 to 6), that region's people send an envoy asking for help.

Player options:
1. **Liberate:** invade with the people's support. Lower garrison resistance, quick capture, region starts with high public order and loyalty, reputation gains "Liberator."
2. **Scheme him out:** assassinate him, back a better heir, or fund a coup. Bloodless; the new ruler may become a puppet or vassal.
3. **Ignore:** the call expires. The region can still be taken later the hard way.

Purpose: teaches the core idea in the first turns (politics can win what armies struggle to) and gives each start a distinct opening. The same mechanic reappears later whenever a hated lord rules near you, including a rebellious governor of your own (Section 11.8).

### 3.4 Starting relations **(Confirmed)**
- No starting wars, no starting alliances (the Long Stillness has just expired).
- Neutral relations, but **permanent prejudices** exist (most orc tribes hate men; elves hate dark elves; lizardmen hate ratmen; dwarves remember grudges).
- Faction **tendencies** (passive, income-focused, generous, kind, expansionist, cruel, treacherous) shape how others perceive them.

### 3.5 Playable factions in V1 **(Confirmed)**
One per human culture. See world bible Section 7.1.
| Culture | Faction | Founder | Core loop |
|---|---|---|---|
| Medieval (Throne Church) | House Varn of Frosthold | Edric Varn, the Winter Shield | Feudal vassals, the Church, the Greywall |
| Roman (Radiant Seven) | House Varrenus | Lucan Varrenus, the Silver Tongue | Unite the great families through the Senate |
| Greek (Radiant Seven) | The Aurekids of Goldspire | Kallias Aurekos, the Gold-Handed | Unite the free cities through leagues, trade, oracles |

All other factions are AI in V1. Long-term goal: every faction playable. **Elves are the first race to become playable after V1.**

---

## 4. Characters, court, and dynasty

### 4.1 The court **(Confirmed)**
The court is everyone who serves your house: family members (by blood and marriage), wards, and courtiers who joined you. It is the pool for every role: rulers, heirs, governors, generals, agents, priests.

**Ways the court grows (Confirmed, all of these):**
- Births.
- Marriage (spouses join your court).
- Wards from vassals and allies.
- Captured nobles who convert after long imprisonment.
- Lesser nobles, adventurers, and exiles who ask to join when your faction is powerful or famous.
- Absorbed ruling families (when you take a faction, you choose whether its family enters your court, keeps lands, or is removed; see 4.10).

### 4.2 Ages and growing up **(Confirmed direction; numbers Proposed)**
One turn is one year. Childhood is compressed so no time is dead:
| Age | Turns per year of age | What happens |
|---|---|---|
| 0 to 12 | about 2 to 3 years per turn | No decisions. Portrait grows. Occasional flavor event. |
| 12 to 16 | 1 year per turn | **Formative years.** Career path chosen. Education events. Mentors. Traits form. |
| 16+ | Adult | Usable in any role. Stops aging in their prime. |

Result: a child becomes useful about **10 turns after birth**.

**Aging and death (Confirmed, from constitution):** characters mature and stop aging in their prime. No sickness or old-age deaths. Non-immortal characters die only in battle or through assassination (and execution, imprisonment outcomes, or disasters from events).

### 4.3 Careers **(Confirmed list)**
The player chooses each child's path during the formative years. Pre-assigned characters exist at campaign start.

| Career | TW equivalent | Map role | Battle role |
|---|---|---|---|
| **General** | Lord | Leads armies (required to attack) | Commands; morale aura |
| **Warlord** | Champion hero | Agent actions (duels, wound characters), joins armies | Single-entity monster-like fighter; lord-killer; ascends into a monster at high level |
| **Assassin** | Assassin-type hero | Wound and kill characters, sabotage, burn outposts | Light fighter |
| **Spy** | Spy hero | Intel, rumors, forged letters, embed in courts, steal secrets | None or minimal |
| **Politician** | Dignitary hero | Envoy, bribes, marriage negotiations, governing regions, embassies | None |
| **Merchant** | (ours) | Trade deals, secret funding, smuggling gold or arms, buying influence | None |
| **Wizard** | Wizard hero | Campaign spells (seal a pass, plague a region), counter-magic | Spellcaster (battle modifiers) |
| **Priest** | (ours; MTW2 priest) | Religious influence, conversion, Throne Church/temple standing; pious priests become Exarchs/high priests | Morale/faith support |

Governors are not a separate career: any adult (most often politicians) can be appointed governor of a region.

### 4.4 Progression: skill trees plus life traits **(Confirmed)**
- **Skill points (TW):** each level grants one skill point in the character's career tree. Each career has its own tree (example branches: General = Command / Logistics / Conquest; Spy = Shadows / Whispers / Networks).
- **Traits and epithets (CK):** earned from life and events, not chosen. A lord who wins many battles and conquers territory becomes "**the Great**"; a just ruler becomes "**the Wise**"; one who razes cities becomes "**the Butcher**"; one who kills family "**the Kinslayer**."
- Traits affect stats, AI opinions, loyalty, and event outcomes.

### 4.4a Skill point notifications **(Confirmed 2026-10-02; build with the character system)**
When any lord or hero has unspent skill points, a TW-style alert appears on their card and in the notification list (the End Turn warnings). Clicking it opens that character's skill tree.

### 4.5 Levels, immortality, and ascension **(Confirmed)**
- **No level cap.**
- **Level 20 is a great feat:** in practice most campaigns produce only a handful of level-20 characters. Leveling is slow (TW reference: a lord winning roughly 20 battles).
- At level 20 a character becomes **immortal**. An immortal defeated in battle returns after X turns; an assassinated immortal returns after Y turns (Y much longer).
- Immortal **warlords** can **ascend** into a monster-like single-entity unit (details open).
- **Legendary founders are immortal from the start** (Edric, Lucan, Kallias, and AI legendary lords).

### 4.6 Loyalty **(Confirmed)**
- **One clear, visible stat** per character.
- Rises with rewards (titles, regions, army commands, marriages, gifts, favor).
- Falls with neglect, favoritism toward other branches, harsh treatment, and humiliating events.
- **Favoritism matters:** pouring attention into one branch of the family makes the other branches resent it. Spreading favor keeps the court content.
- High-loyalty characters are rewarded and trusted; low-loyalty characters can be spent as cannon fodder (but if the court notices a pattern, the ruler gains a Cruel reputation).

### 4.7 Ambition at scale (softened) **(Confirmed)**
As the realm grows (Realm Standing, Section 11.6), courtiers want more: titles, regions to govern, army commands, marriages. This appears as **requests and opportunities**, never as a realm-splitting crisis.

**Guarantees:**
- **No civil wars and no succession wars for the player. Ever.**
- **Nothing hits the player without warning.** Every loyalty problem is visible and fixable before it causes harm.
- AI factions **can** suffer civil wars and succession crises, which become opportunities for the player.

### 4.8 Rulers, heirs, and succession **(Confirmed)**
- The player **always chooses the heir**.
- Succession is **low-drama**. When a ruler dies or is retired, the chosen heir takes over without crisis.
- The player can **replace the ruler at any time**. Replaced rulers become heroes or courtiers. A ruler can rule one turn or a thousand.
- Generational drama comes from the wider court (careers, marriages, governors, rivalries), not from inheritance fights.
- The player controls the faction regardless of who rules; faction destruction is the loss condition (Section 11.10).

### 4.9 Marriage **(Confirmed)**
- Marriage is a diplomatic and court tool: alliances, influence (including with the Throne City), absorbing families, claims.
- **Cross-race marriage is allowed.** Children take the **father's race** (orc father + human mother = orc children; human father + ratmen mother = human children).
- Cross-race marriages have political consequences: prejudiced factions and faiths disapprove; the other bloc may respect it.
- **Women's roles** are a **campaign setting** (Section 16): equal access to all roles in every culture, or culture-specific restrictions (a source of politics).

### 4.10 Absorbed families **(Confirmed from constitution)**
When a faction is absorbed (conquest, confederation, marriage, subordination), the player decides what happens to its ruling family:
- **Enter the court** (new characters for careers; loyalty starts low but can grow).
- **Keep their lands** as vassals or governors (may later seek independence; see 11.8).
- **Be removed** (exile, imprisonment, execution; reputation consequences).

### 4.11 Captured family members **(Proposed)**
Because agents are family, capture is personal:
- The enemy can **ransom**, **imprison**, **execute**, or **turn** a captured relative.
- The player can pay ransom, negotiate in diplomacy (a captive is a tradable item), mount a rescue (agent mission), or abandon them (loyalty and reputation effects).

### 4.12 Renaming **(Confirmed)**
Like TW:WH3, the player can rename any settlement and any character.

### 4.13 Early lords: boom or bust **(Confirmed 2026-10-02; build with the character system)**
- During the formative years (12 to 16) the player can make a child a lord (General) early.
- It is a gamble with extreme outcomes. At one end, a legendary prodigy: great traits and fast leveling. At the other, a broken failure: bad traits, low loyalty, and a risk of early death.
- Inspired by Aegon Targaryen versus Daemon Blackfyre.
- Outcome probabilities are proposed later.

---

## 5. Careers, agents, and the spymaster

### 5.1 Agents are your court **(Confirmed)**
Agents are not generic recruits. They are family and court members on a career path, represented on the map as TW-style heroes.

### 5.2 On the map **(Confirmed)**
- Agents appear on the map as hero figures (TW-style), with movement allowances.
- They can **travel with an army** to gain experience before attempting dangerous tasks.
- They can be **directly controlled** like TW heroes: if an enemy general stands next to your assassin, you can just select the assassin and act, no spymaster screen required.
- **Agents can target agents** (assassin vs. assassin, spy vs. spy).
- Lone agents cannot be attacked by armies, only by agents (TW rule).

### 5.3 The spymaster screen **(Confirmed)**
The central screen for missions. The player picks an agent, a mission type, and a target. **Travel is automated**: the agent walks to the target on their own, turn by turn. The player can redirect or take direct control at any time.

### 5.4 Travel time **(Confirmed)**
Missions take as long as the journey: one or two turns nearby, several turns across a continent. Agents physically traverse the map and can be intercepted on the way (by enemy agents, or caught crossing hostile territory with strong counter-intel).

### 5.5 Level gates **(Confirmed)**
Mission difficulty scales with the target's importance and protection. A level 1 assassin cannot target a ruler. Example gates (Proposed):
| Target | Minimum assassin level |
|---|---|
| Captain, minor courtier | 1 |
| Agent, governor | 5 |
| General, minor ruler | 10 |
| Major faction heir | 15 |
| Major faction ruler | 18 |
| Immortal | 20 (wounds only, they return) |

### 5.6 Mission lifecycle **(Confirmed concept)**
1. **Order:** pick agent, mission, target. See an estimated success chance (except where noted).
2. **Travel:** automated, multiple turns if far.
3. **Arrival decision point:** a pop-up when the agent arrives. Situations can change: the target moved, is heavily guarded, or is absent. Options appear (example from the owner: target not there; kill someone else who is, wait, or redirect).
4. **Outcome:** success, failure, or capture.
5. **Reveal:** who knows what you did (Section 7.5: suspected vs. proven).

### 5.7 Capture outcomes by level **(Confirmed)**
- **Low-level agents** caught on a mission may **break and confess**, exposing you (proven).
- **High-level agents** (e.g. level 20) **die before revealing** their mission.
- Captured agents can **die, be imprisoned, or switch sides**.

### 5.8 Mission catalog **(Proposed, from brainstorm)**
| Career | Missions |
|---|---|
| Assassin | Wound, assassinate, sabotage buildings, burn outposts, poison a feast, kill an envoy and frame another faction |
| Spy | Embed in court (reveals hidden info), steal secrets, start rumors, forge letters, sow distrust (multi-turn), stage a border incident, intercept enemy agents' messages, incite unrest |
| Politician | Open embassy, bribe official, negotiate marriage, support a claimant, fund a coup, buy Exarch votes, govern a region |
| Merchant | Secretly fund a faction, sell arms to both sides, smuggle gold to rebels, buy influence in the Throne City, corner a trade route |
| Wizard | Seal a pass, plague a region, scry a court, counter-magic, protect a ruler from assassins |
| Priest | Raise religious influence, convert a region, preach unrest against a heretic ruler, denounce a rival to the Church |
| Warlord | Challenge and duel a lord, terrorize a region, hunt legendary monsters |

### 5.9 Agent caps **(Confirmed)**
Capped by **Realm Standing** (Section 11.6): more territory and wealth allows more agents per career and more lord armies. Your court is the practical limit too: a cap of four spies means nothing without four trained spies.

---

## 6. Intrigue and schemes

### 6.1 Philosophy **(Confirmed)**
Give the player as many creative options as possible. Schemes are the main way the player plays mastermind.

### 6.2 V1 priority schemes **(Confirmed top 3)**
1. **Start wars between other factions without moving your own armies.**
2. **Secretly fund both sides of a war.**
3. **Install weak rulers and create uprisings.**

### 6.3 Starting wars between others **(Confirmed: all methods)**
- **Forged insults:** a forged letter from one ruler to another.
- **Staged border raids:** your agents raid one faction's land disguised as another.
- **Assassinate an envoy and frame someone.**
- **Bribe a hawkish general** at a rival's court to push for war.
- **Revive old grudges:** remind dwarves of a grudge, remind the Church of heresy.
Each method has a success chance, a detection risk, and a delay before war erupts.

### 6.4 Funding both sides **(Confirmed)**
- Merchants and politicians send **secret** gold, arms, or mercenaries to one or both belligerents.
- Each secret shipment has an **exposure risk**. If a side discovers you are arming their enemy: **reputation damage**, and they may start **attacking or scheming against you**.
- Open support (allies supporting a war without joining it) is part of diplomacy (Section 8.5).

### 6.5 Weak rulers and uprisings **(Confirmed: all methods)**
Ways to install a weak or puppet ruler:
- Assassinate the current ruler and back a weak heir.
- Fund a coup.
- Marry your candidate into the ruling family.
- Win or tip a succession dispute.
- Support a pretender with gold, agents, or troops.

**Uprisings:** a weak or hated ruler builds unrest. Rebels rise. Then:
- **If you supported the rebels**, they **invite you in** (peaceful takeover, loyal region).
- **If you did nothing**, you can sweep in and take the region from a new rebel faction that has **no allies**, with little diplomatic cost.

### 6.6 Puppets **(Confirmed)**
Control scales with investment:
- **A ward you raised and invested heavily in** obeys you completely.
- **Someone you merely paid** (e.g. a favor to an ally) becomes a friendly ally, not a servant.

**Puppet skim:** a puppet you install in another faction **skims that faction's gold to you** (your own governors never skim from you).

### 6.7 Forged letters and broken alliances **(Confirmed: both)**
- **Quick forgery:** one turn, risky, one-shot effect (e.g. an ally refuses one war call).
- **Sow distrust:** a multi-turn spy campaign, harder to detect, permanently erodes trust between two allies.

### 6.8 Secrets and misinformation **(Confirmed)**
- **Secrets are a resource:** discovered by spies (an illegitimate heir, a disloyal general, hidden debts, a secret Chaos pact). Use them for **blackmail** or **leak** them.
- **You can be misinformed:** enemy spies can feed you false reports. Intel has a reliability rating based on the source.

### 6.9 Being schemed against **(Confirmed direction: present but not overwhelming)**
- Frequency is **proportional to your behavior**: a clean ruler is rarely targeted; a notorious schemer attracts schemes. Naturally treacherous neighbors scheme more.
- **Golden rule: you always get a warning** first ("your spymaster intercepted a suspicious letter"). You never lose a key character to a hidden roll you could not respond to.
- **Counter-intelligence:** spies and wizards assigned to defense, plus buildings, raise detection.

### 6.10 Plots discovered in your court **(Confirmed)**
When you uncover a plotter in your own court:
- **Execute:** certain, no percentage. The plotter's relatives lose loyalty.
- **Imprison:** over time they may **escape**, **die**, or (after long imprisonment) **decide to join you**.
- **Double agent:** shown as a **% chance** to succeed. If it works, they feed their employers false information.
- **No pardon option.**

---

## 7. Reputation, decrees, and suspicion

### 7.1 Two reputations **(Confirmed)**
- **Ruler reputation:** what the world thinks of the current ruler. Moves relatively quickly. **Weighs more overall.**
- **House reputation:** the world's long memory of your dynasty. Grows and fades slowly.

### 7.2 Distance weighting **(Confirmed)**
- **Nearby factions** care more about the **ruler** (they deal with him directly).
- **Distant factions** care more about the **House** (they only know the stories).

### 7.3 Reputation traits **(Proposed list)**
Trustworthy / Treacherous, Merciful / Cruel, Generous / Greedy, Peaceful / Expansionist, Pious / Impious, Liberator / Conqueror, Honorable / Dishonorable. Shown as clear labels with tooltips listing the deeds behind them.

### 7.4 The new ruler's first impressions window **(Confirmed)**
- For about **10 turns** after a new ruler takes power, the world is watching: the ruler's actions move **both** reputations much faster than normal, including the slow House reputation.
- Owner example: a House known as expansionist and treacherous gets a new ruler (the son) who immediately issues peaceful, economic decrees. The world sees the son of a tyrant righting his father's wrongs, and both reputations shift quickly.
- **It cuts both ways:** a son who continues his father's cruelty cements the House's bad name faster.

### 7.5 Retiring a ruler to reset reputation **(Confirmed, with safeguard Proposed)**
- Retiring a disgraced ruler and choosing a new one with a better reputation changes how factions see you.
- **Safeguard:** frequent ruler changes mark the House as **unstable**; each swap within a short span shortens the next first-impressions window and costs legitimacy or court loyalty.

### 7.6 Decrees **(Confirmed concept: the owner's "verdicts")**
The ruler issues decrees, limited in number by Realm Standing. Examples:
- Peaceful/economic: lower taxes, amnesty for rebels, open trade, honor old treaties, grain doles, temple endowments.
- Harsh: purge the court, mobilize the realm, seize merchant gold, punish a rebellious region, forced conversion.
Decrees have mechanical effects and shift reputation; during the first-impressions window, their reputation effect is amplified.

### 7.7 Detection: suspected vs. proven **(Proposed, owner open to it)**
- **Suspected:** minor attitude penalty with the victim; they watch you more closely (harder future schemes against them).
- **Proven:** full reputation damage with the victim **and** with others depending on context (scheming against an ally and getting caught hurts you with all your allies; can shift you from Trustworthy to Treacherous). May start a war. Proof usually comes from a captured low-level agent who confesses, or an intercepted letter.

### 7.8 Suspicion **(Proposed, owner agreed)**
- Each neighbor tracks **suspicion** of you. Every suspicious war, death, coup, or rebellion near you nudges it up, even without proof. It decays over time.
- High suspicion makes your schemes against them harder and their counter-intel stronger.
- Rewards pacing your plots.

### 7.9 Racial politics **(Confirmed)**
- A human who schemes heavily against other humans earns quiet respect from orcs, ratmen, and other Destruction peoples (and vice versa).
- Order/Destruction bloc membership shapes baseline willingness to deal (Section 10.2).

---

## 8. Diplomacy, allies, vassals, and puppets

### 8.1 Confirmed rules carried from the constitution and earlier decisions
- **Relationship web:** attacking a faction strongly harms relations with the victim and, less strongly, with its allies.
- **Faction tendencies** shape perception (cruel/treacherous neighbors worry others more than kind/generous ones).
- **Bundled offers:** land, gold, resource tribute, troop transfers (actual troops), marriage, alliances, ceasefires, peace, trade, embassies, captives, secrets (Proposed addition).
- **Allies choose** whether to join a war or only support it (gold, resources, troops) without becoming belligerents.
- **Treaty protection: 20 turns** after peace or ceasefire.
- **Betrayal rule:** attacking during a ceasefire/peace or its 20-turn protection causes irreversible war with every faction and permanent loss of allies and trade partners. *(Still the V1 rule; flagged as the future Chaos trigger: betraying an ally during an invasion turns you to Chaos post-V1, §0.)* Cancelling trade is allowed anytime. **AI never triggers it** (hardcoded); treacherous AI shows treachery in other ways (breaking trade, abandoning allies, refusing calls).
- **Military access (Confirmed 2026-10-02):** movement is drastically reduced in foreign territory (§12.1); a military access agreement (or an alliance) restores home-territory movement in the partner's land, and entering foreign land without one at peace is trespass (attitude penalty, no automatic war). See docs/diplomacy-design.md §11.

### 8.2 Embassies **(Confirmed)**
- **Envoys can reach anyone** on the map, travelling automatically; contact happens on arrival (confirmed 2026-10-05, §0). *Superseded: embassies requiring prior contact.*
- Sending an **embassy** is a diplomatic action. Any faction with no reason to refuse will accept.
- An embassy reveals that faction's **full court** (members, blurbs, who hates whom and why).
- Factions **at war with you** require **spies** to see their court.
- Deeper information (true loyalties, secrets, hidden traits) always requires a spy embedded in that court.

### 8.3 Faction dossiers **(Confirmed)**
- Open any faction you have visibility into: their court, each member's blurb, relationships ("who hates whom and why"), reputation, tendencies.
- Blurbs are written dynamically in the **Grey Scribes'** voice from what has actually happened, so each faction reads like a chronicle.

### 8.4 Commandable allies and vassals **(Confirmed)**
TW's "request help attacking" done right:
- The player can give allies and vassals **specific orders**: attack this settlement, attack this army, defend this region, join this siege.
- The AI must **make a genuine attempt** with a real force, not a token army.
- **Willingness** depends on: your economic and military dominance (the strongest economy in the region gets the most help), their dependence on you, rewards offered, their personality, and your reputation.
- Weaker factions competing for your favor will do your dirty work.

### 8.5 Vassals **(Confirmed: all routes)**
Ways to make a vassal: war and surrender, diplomacy, debt, marriage, protection from a bigger threat.
Vassals owe (Proposed): tribute, troops on request, obeying war calls, following your diplomatic lead. Loyalty and dependence decide how reliably.

### 8.6 Minor factions **(Confirmed 2026-10-02)**
The constitution wants targets attackable without wider diplomatic repercussions. Minor factions have **no allies at start**, and attacking an unprotected minor carries **no relationship penalty beyond the minor itself** (no web penalty with anyone else, no war justification needed). The exception is a minor under a major faction's explicit **protection pact**: attacking it then counts against the protector and the full web applies. Whether a Throne City edict can protect a minor is decided with the religion design. See docs/diplomacy-design.md §13.

### 8.7 Order and Destruction in diplomacy **(Confirmed)**
- Same-bloc deals are easier; cross-bloc deals cost more and carry reputation consequences with your own bloc.
- Neutral peoples (desert humans, lizardmen leaning Order) can be courted by both.

### 8.8 War declarations **(Proposed)**
Retire the temporary "attacking declares war" rule. War requires a declaration (Diplomacy screen or attack confirmation). Declaring war without a **justification** (a grudge, a claim, a provocation, a Holy War, defending an ally) costs reputation. Schemes can manufacture justifications.

### 8.9 Threats and demands **(Confirmed 2026-10-02; build with diplomacy)**
- The player can demand things under threat: gold, a region, vassalage, breaking an alliance, a marriage.
- **Refusal** gives a justified war: no unjustified-war penalty.
- **Acceptance** depends on relative power. Small, weak factions mostly accept, or face annihilation.
- **Overuse** feeds a Bully or Tyrant reputation.

---

## 9. Religion and the Throne City

### 9.1 Research summary: Medieval II's model **(reference)**
- The Pope led the Papal States, issued missions, called Crusades, and excommunicated factions.
- The Pope appointed priests from various factions as Cardinals; when he died, Cardinals elected a new Pope from the three most pious. More Cardinals meant more influence; factions with few could bribe votes.
- Excommunication gave other Catholic factions an excuse to attack.
- Favor came from churches, Crusades, conversion, missions, and having your Cardinal elected.
- The Papal States could never truly be destroyed.
- Crusades had a joining window, paid joiners per unit when finished, and high favor let a faction suggest the target.

### 9.2 Caeloth, the Throne City **(Confirmed)**
- A **huge, very rich, neutral metropolis** at the heart of Aldryn. Every human culture cares about it.
- Ruled by the **Throne Church** as an **untouchable** religious faction (Papal States-like). No human faction's goal is to take it.
- **Shared:** the Throne Church is the God-Emperor's church; Romans and Greeks revere the city as the root of their faith even though they worship the Seven.
- **No scheming against the Throne City itself in V1** (Confirmed). Scheming within its politics (elections) is allowed.

### 9.3 Influence **(Confirmed sources and uses)**
**Gain influence by:** completing Throne Church missions, building religious buildings, sending tribute, marriage into Church-aligned families, (Proposed) answering the Wardens' plea, joining Holy Wars.
**Influence buys (Confirmed: all):** trade privileges in Caeloth, a voice in calling and targeting Holy Wars, legitimacy for your ruler, the right to host or sway elections.

### 9.4 The Throne Church hierarchy **(Proposed names)**
- **The Voice of the Throne:** the elected high priest who speaks for the silent God-Emperor.
- **Exarchs:** senior prelates who elect the Voice. Pious priests from faithful (Medieval) realms can be raised to Exarch; Roman and Greek realms get a smaller number of honorary seats (reflecting shared origin), so they matter but cannot dominate.
- **Priests:** a career path (Section 4.3).

### 9.5 Elections **(Proposed, inspired by MTW2)**
- When the Voice dies (assassination is possible but heavily punished), an election is called.
- Candidates are the three most pious Exarchs.
- Factions vote with their Exarchs; votes can be bought (politicians, merchants).
- Getting **your own family member** elected is a huge prize: strong Church favor, Holy War targeting, legitimacy.

### 9.6 Holy Wars **(Proposed, inspired by MTW2 Crusades)**
- Called by the Voice against: heretics, Destruction peoples, or an anathematized faction.
- High-influence factions can **request** a Holy War and **choose the target**.
- Joining window; joining armies gain movement and morale bonuses; joiners are rewarded when the target falls.
- Mastermind use: turn half the human world against a rival without lifting a sword.

### 9.7 Anathema (excommunication) **(Proposed)**
- Falls on Throne Church factions that attack Church-protected targets, defy missions repeatedly, or are proven guilty of heinous schemes.
- Effects: public order penalty, every faithful faction gains a justification to attack you, Holy Wars can target you.
- Lifted by: a new Voice, a new ruler (first-impressions window), penance (gold, tribute, missions).

### 9.8 The Inquisition **(Proposed)**
Sent into realms that fall out of Church favor or harbor heresy and other faiths; targets characters and lowers public order.

### 9.9 The Radiant Seven in play **(Proposed)**
- **Temples** to specific gods give targeted bonuses (Kael = military, Merovan = trade, Ilith = oracles).
- **Roman state cult:** omens read before war (morale), triumphs dedicated to the Seven (reputation), priestly colleges as Senate offices.
- **Greek oracles:** prophecies that can be consulted (paid), bought (bribed), or ignored (Section 10.4).
- **Relationship with the Throne Church:** honored root faith. Schism events possible (theological disputes, Exarchs declaring Seven-worship heresy), which can trigger Holy Wars between human cultures.

### 9.10 Other faiths **(Proposed; AI flavor in V1)**
| Faith | Signature |
|---|---|
| Forge Fathers (dwarves) | **Book of Grudges**: wrongs must be avenged or the king loses legitimacy |
| Starweave (elves) | **Prophecies**: acting on them grants favor, ignoring them costs it |
| Blood and Iron (orcs) | **Challenges and great hordes** |
| Eternal Sun (desert) | **Mortuary cult**: raise the honored dead |
| Severed Star (dark elves) | **Blood rites and slave tribute** |
| Horned Dark (beastmen) | **Herdstones and razing** |
| Great Gnawing (ratmen) | **Clan treachery** |
| Old Plan (lizardmen) | **The Plan's long goals** |

### 9.11 Conversion and religious mix **(Proposed)**
Regions have a faith mix that shifts over time (priests, temples, rulers, decrees). Faith mismatch with the ruler lowers public order. Forced conversion is possible and harsh.

### 9.12 Foreign cults **(Confirmed 2026-10-02; build with religion)**
- Faiths can establish cults in other factions' settlements, TW-style.
- V1 cults: the Throne Church, ratmen clans, dark elves, Tomb-King mortuary cults, and others.
- Chaos cults come post-V1.
- Effects are proposed later (for example influence, unrest, intelligence, conversion).

---

## 10. Races, cultures, and the three playable human cultures

### 10.1 The three-layer model **(Confirmed, adapted from TW:WH3)**
TW:WH3 layers race mechanics (shared by every faction of a race), legendary lord/faction effects, and starting position. Ours:
1. **Race/culture mechanics:** dramatic, never change. How you rule, scheme, and worship.
2. **House tradition:** fixed per faction (e.g. the Aurekids' trade and sea focus). Does not change from ruler to ruler.
3. **Current ruler's traits:** change as rulers change (or never, for immortal founders).

### 10.2 Order, Destruction, neutral **(Confirmed)**
See world bible Section 3. Baseline diplomatic ease within blocs; costs across them.

### 10.3 Roman culture: the Senate **(Confirmed core; details Proposed)**
**Goal:** start as one great family; **unite all the families under your rule.**
- **The Senate:** a body of family-held seats in Crownhaven. Offices (Consul, Censor, Praetor, Tribune, Pontifex) grant powers and prestige.
- **Influence over families:** each rival family has an attitude toward you; marriages, patronage, bribes, schemes, and offices shift it.
- **Absorption routes:** a family can be **married in**, **made clients** (vassal-like), **outvoted and broken**, or **conquered**.
- **Triumphs:** after major victories, hold a triumph in Crownhaven (gold cost, big reputation and loyalty gain).
- **Client states:** foreign factions bound by patronage (vassal variant).
- **Distinct from Greek:** Rome is **politics inside one realm**.

### 10.4 Greek culture: the free cities **(Confirmed core; details Proposed)**
**Goal:** start as one city among independent city-states; **unite the coast** (like TW's Empire uniting the Elector Counts, and both founding and leading a league).
- **Leagues:** found or join a league of cities; lead it, dominate it, or betray it. League members contribute ships, gold, troops.
- **Oracles:** temples of Ilith deliver prophecies; consult (gold), bribe (influence what others are told), or ignore.
- **Tyranny vs. democracy:** each city has a government type; you can support popular factions or tyrants inside other cities (a natural fit for the weak-ruler scheme).
- **Colonies:** found colonies on distant coasts (outposts that grow into cities).
- **Sea power:** trade and naval bonuses.
- **Distinct from Roman:** the Greeks practice **diplomacy between many small realms**.

### 10.5 Medieval culture: feudalism and the Throne Church **(Confirmed core; details Proposed)**
- **Feudal vassals:** lords hold land from you and owe service. Their loyalty and obligations are central.
- **Knightly orders:** militant orders (some Church-sponsored) providing elite troops and their own politics.
- **The Throne Church:** strongest connection to Caeloth (most Exarch seats, Holy War leadership).
- **The Greywall:** the North's burden and opportunity (Section 12.9).

### 10.6 Unique buildings **(Confirmed)**
Each culture has its own buildings (examples: Roman forum, Senate house, aqueduct; Greek oracle, theater, agora, shipyard; Medieval cathedral, knightly chapterhouse, motte castle). Shared function categories keep the economy consistent; unique buildings carry culture mechanics.

### 10.7 Rosters and mythic monsters **(Confirmed)**
- Each culture/faction has a **distinct roster**.
- **Mythic monsters** per faction: some have a handful, some many (examples in world bible Section 5).
- Ordinary monsters require special buildings; unique legendary monsters can be recruited only by heroes of extraordinary stature (constitution).

### 10.8 Non-playable races in V1 **(Confirmed approach)**
- They run on **shared systems** (economy, armies, diplomacy, intrigue, AI) with their own rosters, faiths, tendencies, and naming.
- Their **dramatic race mechanics are built when each becomes playable**. Elves first.

### 10.9 Climate **(Confirmed)**
Each race has preferred terrains/climates. Settlements in unsuitable climates **produce fewer resources** (a dwarf mountain hold vastly outproduces a dwarf jungle hold). Not a hard ban.

### 10.10 Underground travel **(Confirmed, simple)**
Dwarves and ratmen can move underground between their own cities. Details deferred.

### 10.11 Cross-race integration **(Confirmed from constitution)**
Courts can contain multiple races. Welcoming outsiders requires sustained commitment; exclusion breeds distrust and rebellion. Integration can harm relations with prejudiced same-race friends while opening cross-race alliances.

---

## 11. Economy, realm, and order

### 11.1 Already built (prototype)
Gold income per turn, population taxes, resource endowments, settlement types and levels, construction with main-chain caps, building effects, upkeep, debt rules, recruitment from population.

### 11.2 Governors **(Confirmed)**
- **Governors never skim from you.** Your treasury is your faction.
- Governors affect their region through traits and skills (public order, growth, income bonuses, defense) and handle occasional regional events.
- **Puppets you install in other factions skim that faction's gold to you** (Section 6.6).

### 11.3 Public order **(Confirmed: TW-style)**
One bar per region. Drivers: taxes, faith mix, culture mix, the governor's popularity, recent wars and raids, decrees, garrison, buildings, and the ruler's reputation.

### 11.4 Culture and race mix **(Confirmed)**
Each region has a culture/race mix that shifts over decades. Mismatch with the ruler lowers public order and affects recruitment and loyalty.

### 11.5 Conquered peoples **(Confirmed)**
- **Expel:** the easy choice. Population drops, refugees flee (constitution: toward nearby fortresses; others can admit them at a cost), reputation suffers.
- **Integrate:** harder, slower, but rewarding (full recruitment, growth, loyalty over time).

### 11.6 Realm Standing **(Confirmed concept, adapted from Rome II's Imperium)**
Rome II reference: Imperium level rose with conquest and wealth and raised caps on armies, fleets, agents, and edicts.
- Realm Standing rises with territory, population, and wealth.
- Each level raises caps on: **lord armies**, **agents per career**, **active decrees**.
- **No growth penalties** (Confirmed): no corruption, no administrative strain.
- **Softened ambition** (Confirmed, Section 4.7): bigger realms make courtiers want more, shown as requests.

### 11.7 Capture and post-battle options **(Confirmed: all exist)**
- **After capturing a settlement:** occupy, sack, raze, expel population.
- **After a battle:** release, enslave, or execute captives.
- All shape reputation and epithets ("the Butcher," "the Merciful").

### 11.8 Small rebellions **(Confirmed)**
- A low-loyalty governor or vassal can declare independence with their region.
- **Rules:** several turns of visible warning; one region at most (no chain reactions); only happens if the player neglected them.
- **The people decide:** if they dislike the rebel, they send an envoy asking for your help (Liberator's Call); if they love him, the rebellion has real support and you must fight, negotiate, or let him go and make him an ally.

### 11.9 Mercenaries **(Confirmed)**
- Hireable sellsword companies with **no loyalty system**: pure contracts, they serve whoever pays.
- Useful for funding wars secretly (Section 6.4).

### 11.10 Debt and loss condition **(Confirmed earlier)**
- Debt allowed to a limit; while in debt, no construction or recruitment, and desertion.
- Losing the last settlement starts a grace period; failing to retake one destroys the faction.

---

## 12. The campaign map: movement, captains, outposts, trade, navies, magic

### 12.1 Movement **(Confirmed)**
- TW-style controls (TW parity block): select, hold right-click to preview a colored path with no numbers, range boundary, Q/E rotation.
- **Full movement in your own and allied territory; drastically reduced in foreign territory.** (Note: TW:WH3 mostly grants own-territory bonuses through skills, technologies, and roads; we make it a baseline rule.)
- **Large armies block passage** (confirmed 2026-10-05, §0): enemy forces cannot slip past a large army in a pass, valley or open ground near it; the blocking radius scales with army size. Rivers are crossable only at fords and bridges.
- Roads speed movement (built).

### 12.2 Lord armies **(Confirmed)**
- A lord (General) is required to **attack**.
- Full stack = **20 units** (TW term "20-stack").
- Max lord armies capped by Realm Standing.

### 12.3 Captain-led detachments **(Confirmed)**
- Armies **without a lord** can move, led by a **captain**.
- **Small unit cap** (placeholder 6) so they can never be full stacks.
- Normal movement in own/allied territory, **drastically reduced elsewhere**.
- Purpose: ferry fresh recruits to lords, reinforce garrisons, consolidate.
- Merge into a lord's army on contact.
- Proposed: captains cannot initiate attacks (defend only) and fight without a general's morale aura.

### 12.4 Raise banners **(Constitution; reconciled Proposed)**
The "raise banners" action gathers population from your territories at the capital. With army caps, raised banners form **captain-led detachments** that must be merged into lords' armies.

### 12.5 Outposts **(Confirmed: all functions)**
- Secure a pass, claim a resource, forward supply base, trading post, watchtower (reveals the shroud).
- **Extend home-territory movement** into regions you do not own.
- Can be **attacked by armies** or **burned by assassins**.

### 12.6 Shroud **(Confirmed)**
TW-style: unseen areas are **darkened**, no literal fog. Vision from armies, agents, settlements, outposts, allies, and embassies (court info).

### 12.7 Trade routes **(Confirmed)**
- When you trade with a faction, **lines are drawn on the map** (sea and land) with **little ships and caravans** moving along them. Visual only; not individually simulated.
- Each route has an **abstract income**.
- **Raiding** (TW reference): a raiding army or fleet draws income from nearby trade routes and settlements, deducted from the route's income; raiding harms relations but is not an act of war; raiding a province also lowers its public order.
- Dark elves are natural raiders.

### 12.8 Navies **(Confirmed)**
- Naval **transport** only (armies embark and sail).
- Naval battles are **auto-resolved**, nothing fancy.
- Naval research gates high-seas crossings (constitution).

### 12.9 The Greywall **(Confirmed)**
- The Wall must be **manned** (men, prisoners, exiles, gold sent to the Wardens).
- If neglected, it **falls**, and orcs pour through faster than usual.
- Supporting it earns Throne Church influence and northern reputation.

### 12.10 Legendary monsters **(Confirmed)**
Wild legendary monsters roam certain regions (dragons, giants, frost-beasts). Map dangers, hunting targets for warlords, and recruitable by heroes of extraordinary stature.

### 12.11 Magic **(Confirmed direction)**
- Mainly a **battle power**: in our simulation, wizards and spells act as battle modifiers (area damage, morale, protection).
- **Campaign spells** (a few): seal a mountain pass, plague a region's income, scry a court, protect against assassins.
- **Counter:** assassinate the wizard, counter-magic from your own wizards.

### 12.12 Battles **(Confirmed: complete for V1)**
- **Stance only** (confirmed 2026-10-05, §0; `docs/war-and-realm.md` §1): the pre-battle panel shows both forces, terrain, the balance-of-power bar, the stance choice (Aggressive / Balanced / Defensive), Withdraw (defender) and Besiege (settlements). The battle report keeps the "why you won or lost" summary and casualties. *Superseded below: Quick Resolve as the default and the optional deployment screen.*
No further battle work in V1 except bugs. Magic and new unit types feed the existing simulation as data.
- **Quick Resolve is the default** (confirmed 2026-10-04, owner): a battle resolves at once with the default deployment; the deployment screen is an optional button for players who want to place units and give orders.
- **Removed from the roadmap** (2026-10-04): TW-style free deployment and the true spatial battle simulation.
- **Post-V1 idea, recorded only** (2026-10-04): typed battle orders. The player types orders in plain words ("hold the ford with the spears, cavalry round the left"); a local model (for example Ollama, free and offline) translates them into a deployment and orders, which the player confirms before the battle. Not designed, not scheduled.

### 12.13 Living settlements and changing land **(Confirmed 2026-10-04, owner)**
**A. Big cities feel big.**
- Major settlements are procedural sprawl, not single models:
  - walls, districts, and suburbs spilling past the gates;
  - converging roads, and surrounding villages and farmland.
- Each settlement level visibly grows the footprint, not just the center.
- Landmarks keep their unique models but gain the same surrounding sprawl.
- Built from the low-poly kits through the asset manifest (a building kit per culture), so the art pass upgrades them automatically.
- Scale target: our major cities and fortresses are bigger than TW:WH3's equivalents, relative to the map and to lord figures.
  - A level-3 city dominates its region visually: walls, districts, suburbs, outlying villages.
  - A great fortress reads as a massive defensive work, not a single keep.
- Regions are large enough to hold a sprawling city plus its countryside and industry without crowding neighbors.

**B. The countryside shows what's built.** Each building chain adds visible features around its settlement, growing with level:

| Chain | Visible features |
|---|---|
| Farms | Field patchwork spreading outward |
| Mines | Pits, spoil heaps, carts in nearby hills |
| Port | Docks, ships, warehouses |
| Barracks, stables, range | Training yards, tents, paddocks |
| Temples | Spires and shrines |
| Markets | Stalls and caravans |
| Walls and towers | Visible fortifications |

The features are placed procedurally in the region around the settlement, respecting terrain (mines on hills, fields on flat ground, docks on the coast). They update when buildings complete or are demolished.

**C. Land transforms to match its owner.**
- Every culture has a biome profile: terrain colors and textures, ground cover, tree types, weather and snow, building kit, and props.

| Culture | Biome |
|---|---|
| Medieval | Mostly green north: meadows, pine and oak, grey stone |
| Roman | Warm, vineyards, cypress |
| Greek | Dry hills, olives, white stone |
| Orcs | Lively northern wilderness: dark pines, mossy tundra, rivers, old snow in hollows, crude timber and bone camps |
| Dwarves | Bare rock, stone works |
| Elves | Lush, magical: emerald meadows, white stone, slender spires |
| Dark elves | Black rock, purple heather, witchlight, spiked towers, grim coasts |
| Beastmen | Wild overgrowth, bones, herdstones |
| Ratmen | Drowned swamp forest, mildly polluted, crooked scrap towers |
| Lizardmen | Jungle |
| Tomb-King desert | Sand, red stone, a green river ribbon, benevolent visible magic |

  Chaos and Hollow Dynasty profiles (twisted, corrupted land) come after V1, but the system supports them.
- When any faction takes a region from another culture, the region transforms toward the new owner's profile (data values):
  - noticeable after 3 turns;
  - very noticeable after 6;
  - fully converted after 9.

  Owning that culture's buildings there speeds it up (data). It works in every direction, for every culture.
- The old owner's buildings become ruins that linger and decay over the conversion period. This is flavor; the focus is the new owner's look growing in.
- Gameplay follows the visuals:
  - the climate yield penalty for the new owner (§10.9) fades over the same period;
  - once converted, the region is foreign climate for the original culture if they retake it, which starts converting it back.
- This is the land, not the people: a region's culture and faith mix (§11.4) still shifts on its own over decades.

**D. Specialization paths** **(Confirmed 2026-10-04, owner; notes in `docs/reference/specializations/specialization-prompts.md`)**
- **The commitment:**
  - A town commits to exactly one path: **military, farming, mining, lumber or market**.
  - Paths exist for all 11 cultures.
  - Any town can take any path. Missing resources are added; for example, a mine pit opens beside a mining town with no hills.
- **The look:**
  - The town's look follows its path, in its countryside and its city.
  - Each path has a **fixed, designed appearance per culture**, never generated on the fly.
  - Every culture has one signature building per path.
- **Buildings and changes:**
  - All buildings stay available whatever the path.
  - Changing path means demolishing and rebuilding from scratch.
- **Path characters:**
  - Mining looks gritty.
  - Lumber towns keep their forests.
  - Markets are rich and crowded when populous.
- **Big cities have no path,** only growth.
- **Gameplay effects:** proposed later (not designed).

**E. Settlement levels 3 → 5** **(Proposed, likely post-V1)**: five settlement levels as in TW:WH3, instead of three. Needs approval before any work.

**F. Alive at scale** **(Confirmed 2026-10-04, owner)**: the map feels alive through tiny details: specks of people on the roads, chimney smoke, carts, and birds as a couple of brush strokes.

**G. Overall visual style** **(Confirmed 2026-10-04, owner)**
- Vivid and colourful, TW style, even for grim races: menace through shapes and details, not murk.
- Architecture is grimdark gothic, colossal, almost unrealistically epic.

**H. Faction identity within races** **(Confirmed 2026-10-04, owner)**
- Every faction has its own crest, colours and feel.
- Every faction sits somewhere on a good-to-evil spectrum: some Roman houses are noble, others cruel. The same holds for every race.

**I. Land conversion extremes and mixed populations** **(Confirmed 2026-10-04, owner)**
- Extreme conversions are allowed: orcs can turn desert to snow, and lizardmen can turn tundra to jungle.
- A region with a mixed population shows a blend of both cultures' land and architecture.

**J. Biome specifics** **(Confirmed 2026-10-04, owner; targets `docs/reference/biomes/`, palette and style only)**
- Desert magic is benevolent and visible (enchanted crops, glowing springs).
- Elves and dark elves are fully high-fantasy and magical.
- Beastmen architecture grows from the wild.
- Ratmen pollution is mild.
- Orc lands are lively, not barren.
- The Medieval north is mostly green.

**K. Settlement layouts** **(Confirmed 2026-10-04, owner)**
- **Never default to circular walled forts.** Layouts follow terrain and culture:

| Culture | Layout |
|---|---|
| Roman | A grid with straight roads and a forum |
| Greek | Terraced hillside down to a harbour |
| Medieval | Organic streets around a castle and church |
| Dwarves | Vertical, carved into cliffs and mountains |
| Orcs | Sprawling camps around a stronghold |
| Elves | Vertical spires and bridges |
| Dark elves | Jagged towers on rock and sea |
| Beastmen | Woven into wild growth |
| Ratmen | Crooked stacks over ruins |
| Lizardmen | Monumental plazas and pyramids |
| Desert | Along the river, with processional roads |

- **Use the terrain:** settlements built into mountainsides, on hilltops with districts sloping down to lower towns, along rivers and coasts, across valleys, against cliffs. A citadel on high ground with the city spilling downhill should be common.
- **Walls** follow the terrain and the city's shape (irregular outlines, ridgelines, riverbanks), with proper curtain walls, towers and gatehouses.
- Every settlement is **dense and asymmetric**, with no empty ground inside the walls and suburbs spilling outside.
- The Gemini reference images are references for palette, materials and architectural style, **not layout**; never copy their composition.

**L. Seasons** **(Confirmed in concept 2026-10-04; mechanics to be designed; NOT implemented)**
- Long, irregular Game of Thrones seasons: a summer can last about 7 years, a winter 1–2 years.
- Seasons are visible on the map.
- Gameplay effects are to be designed; nothing is built until then.

**M. Goldspire Rock redesign** **(Confirmed 2026-10-04, owner; reference `docs/reference/landmarks/goldspire rock.jpg`)**: the castle is carved INTO the rock:
- halls, colonnades and towers emerge from the cliff;
- mines glow inside it;
- the Greek city lies at its foot and the harbour below.

---

## 13. Research **(Confirmed)**
- **Each race has its own tech tree.**
- Research **takes turns**; something should **always** be researching (TW-style).
- Research unlocks buildings, units, naval progression, decree slots, agent skills, and culture mechanics.
- This **moves research into V1** (previously deferred).

---

## 14. Events, quests, items, and the chronicle

### 14.1 Events **(Confirmed)**
- **Pop-ups with art.** Maximum satisfaction: every major event (plot discovered, assassination, election, marriage, triumph, uprising, liberation) gets a painted illustration.
- **Art pipeline:** generate an illustration library in Gemini (same approach as unit cards), with a consistent style guide.
- **Cadence:** front-loaded in the opening, tapering to a steady, prominent rhythm.
- Event choices show consequences in tooltips (TW-clear, not CK-dense).

### 14.2 Quests **(Confirmed)**
No battle attached (for now): take this city, secure this alliance, marry into this house, win this election, man the Wall. Rewards: items, influence, reputation, traits.

### 14.3 Personal ambitions **(Proposed)**
Optional long-term goals per ruler or house ("Unite the free cities," "Seat a Varn as Voice of the Throne") that give direction in a no-victory sandbox.

### 14.4 Items and legendary items **(Confirmed)**
Characters can carry items (weapons, armor, talismans, banners). Legendary items come from quests, landmarks, and monsters.

### 14.5 The chronicle **(Confirmed: light)**
The Grey Scribes record key events only (wars, coronations, elections, great battles, falls of houses). May be phased out later. Dossier blurbs (Section 8.3) also use the Scribes' voice.

---

## 15. The freshness engine (1,000-turn campaigns) **(Proposed; owner requirement)**
The owner plays very long campaigns, so the game must stay fresh. Sources of novelty:
1. **Elections and schisms:** Voice elections, theological disputes, Holy Wars between cultures.
2. **AI civil wars and successions:** rival realms fracture (never the player's).
3. **Rising powers:** minor factions or rebels occasionally grow into new majors.
4. **Monster awakenings:** legendary monsters emerge in new regions.
5. **The Greywall:** orc pressure rising and falling; breakthroughs.
6. **Desert temptation:** desert realms flirting with Destruction; post-V1, a desert realm could fall into becoming a second Hollow Dynasty.
7. **Plagues, famines, golden ages:** regional events with real decisions.
8. **Migrations:** refugees and peoples on the move after wars.
9. **New generations:** children with surprising traits, epithets earned, legendary characters reaching level 20.
10. **Crises (post-V1):** the Hollow Dynasty waking, the Unbound invasion.
11. **Personal ambitions:** new goals unlocked as old ones complete.

---

## 16. Difficulty and campaign settings

### 16.1 Difficulty **(Confirmed: both)**
- Lower and middle levels: AI becomes **smarter and more aggressive** (coordination, scheming, army use) under the same rules as the player.
- Top levels add a **visible economic bonus** to the AI (TW-style pressure: multiple full stacks).
- Shown openly in settings.

### 16.2 Campaign settings **(Proposed, kept slim)**
- Difficulty.
- Women's roles (equal / culture-specific).
- Scheming frequency against the player (low / normal / high).
- Greywall strength.
- Guidance on/off.

---

## 17. AI requirements **(Proposed)**
- AI factions use **the same systems**: court, careers, agents, schemes, reputation, diplomacy, religion.
- AI rulers **scheme** (against each other and the player, proportional to their tendencies).
- AI **allies and vassals execute player orders** with real forces (Section 8.4).
- AI factions can suffer **civil wars and succession crises**; the player cannot.
- AI never triggers the betrayal rule.
- **Performance:** huge map with many factions requires a strict AI time budget per turn, shared odds caching, and staggered decisions (not every faction re-plans everything every turn).

---

## 18. UI screens (TW:WH3 parity)
All screens follow TW:WH3 layout conventions.
| Screen | Purpose |
|---|---|
| **Court / Family** | Family tree, every character's portrait, epithet, traits, loyalty, career, role; assign roles; marriages; heir selection |
| **Character details** | Skill tree, traits, items, history (TW character panel) |
| **Spymaster** | Agents, missions in progress, intel reports, secrets, counter-intel, suspicion levels |
| **Diplomacy** | Faction list with attitude, proposal builder, acceptance indicator, reasoning; embassies |
| **Faction dossier** | Court and relationships of a visible faction, Scribes' blurbs |
| **Throne City / Religion** | Influence, missions, Exarchs, elections, Holy Wars, Anathema |
| **Research** | Tech tree per race |
| **Decrees** | Active decrees and slots |
| **Realm Standing** | Level, caps, progress |
| **Events** | Illustrated pop-ups with choices and consequence tooltips |
| **Senate (Roman) / League (Greek) / Vassals (Medieval)** | Culture mechanic screens |

---

## 19. V1 scope (revised) **(Confirmed direction; details Proposed)**

### 19.1 Map
- Design for the **full huge world**. Build in **stages**:
  1. **Stage A:** a medium slice containing all three playable cultures, Caeloth, and nearby non-human neighbors, to prove the map pipeline and AI performance.
  2. **Stage B onward:** expand region by region until Aldryn, Ossara, and Sothmire are complete.
- **Excluded from V1:** the Ashlands (Hollow Dynasty, Unbound Hosts), endgame crises.
- As many factions as possible: crowded start, quick consolidation.

### 19.2 Races and factions
- **Playable:** House Varn (Medieval), House Varrenus (Roman), the Aurekids (Greek).
- **AI:** all other V1 races and factions on shared systems with their own rosters, faiths, and tendencies.

### 19.3 Systems in V1
Everything already built, plus: TW parity pass; court, dynasty, careers; agents and spymaster; the three priority schemes plus core intrigue; reputation, decrees, suspicion; diplomacy (embassies, dossiers, commandable allies, vassals, puppets, treaties, betrayal); religion and the Throne City (influence, missions, elections, Holy Wars, Anathema); three human culture mechanics; research; public order, culture/faith mix, capture options; outposts, captains, trade routes and raiding, naval transport, shroud, the Greywall, legendary monsters (basic), campaign magic (basic); events with art, quests, items, chronicle; Realm Standing; difficulty and settings; illustrated intro and guidance.

### 19.4 Deferred past V1
Playable non-human races (elves first), Ashlands content and crises, typed battle orders through a local model (idea only; free deployment and the spatial battle sim were dropped 2026-10-04), deep underground travel, ascension details, schemes against the Throne City itself, Hollow Dynasty transformation event.

### 19.5 Changes vs. the approved `docs/v1-scope.md`
- Map: southern Aldryn only → full world (staged), minus Ashlands.
- Playable: House Aurek only → three human cultures.
- Races: humans, dwarves, ratmen → all V1 races present as AI.
- Research: deferred → in V1.
- Characters: minimal family tree → full court, careers, agents.

---

## 20. Constitution changes required (on approval)
1. Vision: "Crusader Kings depth, Total War look and feel"; depth through events, not management screens.
2. TW:WH3 parity principle for everything the player touches.
3. Battles complete for V1; no further battle work except bugs.
4. **Reproduction:** cross-race marriage allowed; children take the father's race (supersedes same-race-only).
5. **Human cultures:** Medieval (Throne Church), Roman and Greek (Radiant Seven); Tomb-King desert humans neutral. Isles = dark elves.
6. **Religion:** Throne City as an untouchable Papal-States-like faction; elections, Holy Wars, Anathema.
7. **Playable V1:** one faction per human culture.
8. **Research moves into V1**, per-race tech trees.
9. **Agents are court members**; careers list; level gates; capture outcomes by level.
10. **Reputation:** ruler + House, distance-weighted, first-impressions window, decrees, instability safeguard.
11. **No player civil wars or succession wars**; small rebellions with warning and the people's choice.
12. **Governors never skim**; puppets skim from host factions.
13. **Realm Standing** caps (armies, agents per career, decrees); no growth penalties; softened ambition.
14. **Captain-led detachments**; raise banners form detachments.
15. **Movement:** full at home/allied, reduced abroad; outposts extend home movement.
16. **Trade routes** visual with abstract raidable income.
17. **Difficulty:** smarter AI first, visible economic bonus at top levels.
18. **No victory conditions**; freshness engine requirement.
19. **Recruitment** rule change from the TW parity block (province-wide recruitment).
20. **Legendary founders immortal from start**; level 20 a rare feat; no level cap.
21. Throne City scheming deferred.
22. Updated V1 scope (Section 19).

---

## 21. Implementation roadmap **(Proposed order)**
Each item is one or more CC blocks; design-heavy items start with a design note and a stop for approval.

1. **TW parity pass** (written; pending).
2. **Debt and loss condition** (written; pending; diplomacy design part replaced by item 8 below).
3. **Constitution and docs update** from this document and world bible v2.
4. **Map-authoring pipeline:** generate terrain, provinces, regions, roads, coasts, settlements, resources, climate from data files, so the world is designed in data rather than by hand. Includes performance budget checks for large maps.
5. **Map Stage A:** the medium slice (three playable cultures, Caeloth, neighbors), with placeholder art.
6. **Characters core:** court, family tree, ages and maturity, careers, skill trees, traits/epithets, loyalty, marriage, heirs, renaming. Court screen.
7. **Agents and spymaster:** agents on the map, direct control, automated travel, level gates, basic missions, capture outcomes.
8. **Reputation, suspicion, decrees** and **diplomacy** (design note first): embassies, dossiers, war justifications, commandable allies, vassals, treaties, betrayal.
9. **Intrigue schemes:** the top three plus forged letters, secrets, misinformation, plots in your court, being schemed against with warnings.
10. **Religion and the Throne City** (design note first): influence, missions, Exarchs, elections, Holy Wars, Anathema, Radiant Seven temples and oracles.
11. **Realm mechanics:** public order, culture/faith mix, capture and post-battle options, small rebellions and the Liberator's Call, governors, puppets, mercenaries.
12. **Map mechanics:** home/foreign movement, captains, raise banners, outposts, trade routes and raiding, naval transport, shroud, Greywall, legendary monsters, campaign magic.
13. **Research** per race.
14. **Culture mechanics:** Roman Senate, Greek leagues and oracles, Medieval feudalism and orders. Unique buildings and rosters.
15. **Events, quests, items, chronicle**, illustrated pop-ups, the intro and guidance.
16. **AI upgrade:** AI uses courts, agents, schemes, diplomacy, religion; obeys player commands; performance budget.
17. **Map Stages B+:** expand to the full world.
18. **Playtest and balance passes** between stages.

---

## 22. Open questions
1. Exact numbers: maturity speeds, level gates, Realm Standing thresholds and caps, captain unit cap, first-impressions window length, suspicion decay, influence values.
2. How many Exarch seats Roman and Greek realms get (Section 9.4).
3. Ascension mechanics for immortal warlords.
4. Whether Greek colonies are a type of outpost or a separate system.
5. Hero cap per career at each Realm Standing level.
6. How legendary items and monsters are distributed on the map.
7. Map Stage A boundaries.
8. Event art style guide (for Gemini).
9. Whether minor factions are playable later.
10. How the Wardens of the Greywall behave as an AI faction (independent order, or a Medieval vassal by default).

---

## 23. Glossary
| Term | Meaning |
|---|---|
| **20-stack / full stack** | A Total War army at maximum size (20 units) |
| **Lord** | A General leading an army |
| **Hero / agent** | A court member on a non-General career acting on the map |
| **Captain** | Leader of a small lordless detachment |
| **Realm Standing** | Our version of Rome II's Imperium: caps on armies, agents, decrees |
| **Liberator's Call** | A region's people asking you to remove their hated ruler |
| **Puppet** | A ruler you installed in another faction; obedience scales with investment |
| **Exarch** | Senior Throne Church prelate who votes in elections |
| **Voice of the Throne** | Elected high priest of the Throne Church |
| **Anathema** | Excommunication |
| **Holy War** | Crusade equivalent |
| **Decree** | A ruler's policy with mechanical and reputation effects |
| **Suspicion** | Unproven distrust from neighbors after suspicious events |
| **First-impressions window** | ~10 turns after a new ruler when reputations shift fast |
| **Grey Scribes** | Neutral chroniclers whose voice writes the chronicle and dossiers |
| **Shroud** | Darkened unexplored or unseen areas of the map |
