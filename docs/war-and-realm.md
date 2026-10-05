# Project Freedom: War and Realm Design

**Status:** Approved direction (owner, 2026-10-05). Items marked **Proposed** still need the owner's approval before implementation. The §0.2 rule changes are applied to `constitution.md` and `docs/game-design.md` §0.
**Markers:** **Confirmed** = owner decision from the brainstorm. **Proposed** = design proposal needing approval. All numbers are placeholders for tuning.
**Companions:** `docs/game-design.md`, `docs/world-bible-v2.md`, `docs/v1-content.md`.

---

## 0. Summary and rule changes

### 0.1 The core idea
War has weight. Armies take time to raise, can't be hidden, and are only as strong as the loyalty behind them. The most powerful rulers don't just own land: they command houses that would kill and die for them. The campaign moves through escalating **Ages** that pull rivals into wars, races into alliances, and eventually the whole world into a fight for survival.

### 0.2 Earlier rules this document changes
| Earlier rule | New rule |
|---|---|
| Deployment screen with lanes and orders; Quick Resolve default | **Battles are stance only** (Aggressive / Balanced / Defensive), then auto-resolve. Deployment screen removed from V1. |
| Gold is the only spendable currency; resources only raise income | **Gold, food, wood, stone** are real stockpiles. Gold rules and can buy the others. |
| Confederation absorbs a faction | **Confederation = fealty.** The house swears to you and remains its own faction as a loyal vassal. |
| Embassies require prior contact | **Envoys can reach anyone**, traveling automatically; contact happens on arrival. |
| War ends trade | **Trade continues during war** with tariffs and disruption, unless raided, blockaded, or cancelled. |
| Betrayal: permanent war with every faction | **Betraying an ally during an invasion turns you to Chaos** (post-V1 playstyle). In V1, betrayal keeps the current rule and is flagged as the future Chaos trigger. |
| Free movement through foreign land until diplomacy | Fast in friendly land, slow in enemy land (already recorded), and **large armies block passage**. |
| Campaign arc as fixed turn numbers (owner placeholder) | **Condition-driven Ages** that repeat and escalate. |

---

## 1. Battles: stances **(Confirmed)**

1. Before a battle, the player picks one **stance** for the whole force:
   - **Aggressive:** attack hard. Higher casualties on both sides, better chance of a decisive win, worse if outmatched.
   - **Balanced:** default.
   - **Defensive:** hold ground. Fewer casualties, better on strong terrain and walls, less likely to destroy the enemy.
2. The existing battle simulation stays underneath and weighs terrain, unit types, generals, walls, weather, and stance. It must scale to **multi-army hosts** (many stacks per side) by treating each army as a block within the battle.
3. The pre-battle panel shows both forces, terrain, the balance-of-power bar, the stance choice, Withdraw (defender), and Besiege (settlements).
4. The battle report keeps the 3-5 line "why you won or lost" summary and casualty table. The 2D replay and deployment screen are removed from V1 (deployment code can stay dormant).
5. **Proposed:** generals' traits interact with stances (a Reckless general fights better Aggressive; a Cautious one better Defensive).

---

## 2. Armies and the cost of war

### 2.1 Three kinds of force **(Confirmed)**
| Force | Source | Character |
|---|---|---|
| **Standing army** | Professional troops paid from the treasury | Always ready, expensive upkeep, best quality. A strong economy can field one. |
| **Levies** | Fighting-age men from your regions | Cheap, slower to gather, weaker. Drawn from young men only, so production drops while they serve but total population is mostly preserved. |
| **Vassal armies** | Your sworn houses answer the call | Their own lords and troops, under your orders. Your path to truly huge wars. |

### 2.2 Calling the banners **(Confirmed)**
- Calling the banners gathers levies and vassal armies into a **Host**.
- Contingents march to a **muster point** you choose. Mustering is **visible to the world**: neighbors, spies, and merchants learn a war is coming.
- Speed and size of the call depend on **reputation and loyalty only** (no extra resource):

| Your ruler is | Effect on calling banners |
|---|---|
| **Loved** (any power level) | Fast muster, large turnout, high loyalty in the field |
| **Feared and powerful** | Same as loved |
| **Feared but weak** | Large turnout, but low loyalty (desertion risk, contingents refuse dangerous orders) |
| **Neutral** | Slow muster and small turnout. No reward for avoiding diplomacy. |

- Each vassal's turnout also scales with **its own loyalty** to you.

### 2.3 Time to raise **(Confirmed starting value)**
- A full 20-unit army takes about **5 turns** to build from nothing (standing army recruitment), as a starting point to tune.
- Hosts are faster to gather than to recruit from scratch, but take turns to march to the muster point.

### 2.4 No cohesion decay **(Confirmed)**
War is part of life. Hosts stay together as long as the ruler wants, with no unhappiness or weakening over time. The only practical limits are **supply** and **terrain**.

### 2.5 Army caps **(Confirmed)**
- **Realm Standing** caps the number of **lords** (and therefore standing armies) you field.
- **Host size is not hard-capped.** Huge hosts are possible, limited softly by supply, chokepoints, and how many vassals answer.

### 2.6 Movement **(Confirmed)**
- **Fast in friendly and allied territory**, slow in enemy territory. Outposts extend friendly movement.
- **Large armies block passage.** Enemy forces cannot slip past a large army in a pass, valley, or open ground near it. The blocking radius (zone of control) **scales with army size**.
- **Chokepoints are real:** bridges, fords, mountain passes, and the Greywall can be held. Rivers are crossable only at fords and bridges.

### 2.7 Supply **(Confirmed concept; details Proposed)**
- Each army has **one supply bar**.
- **Full** in friendly and allied land. **Drains** in enemy land.
- **Refilled** by capturing settlements, foraging (raiding stance), supply trains from friendly outposts, allied territory, or buying food (gold).
- **Empty supply** means attrition each turn.
- **Winter** drains supply faster (Section 9).
- Supply draws on the faction's **food stockpile** (Section 7).

### 2.8 Sieges **(Confirmed)**
Sieges matter but aren't too long. Existing siege endurance stays (up to ~8 turns, based on settlement food and buildings). Food stockpiles in the settlement extend endurance.

### 2.9 Professional troops for hire **(Confirmed)**
- Factions with a military economy can **loan or sell** professional troops to others.
- **Default: per-turn rental** like a mercenary contract, ended anytime by either side. **Option:** a lump-sum contract for a whole war.
- Loaned troops follow the renter's orders; casualties are compensated per the contract.

---

## 3. Intelligence and secrecy

### 3.1 Big armies can't hide **(Confirmed)**
- Large armies and musters are **visible from afar** by default.
- Information spreads through many channels: **merchants on trade routes, sailors along coasts, food sellers** noticing a faction buying grain for a host, **spies, allies, outposts, watchtowers, priests, envoys**.
- **Small detachments** can move quietly.

### 3.2 Layers of intel **(Confirmed)**
| Source | What you learn |
|---|---|
| Rumor (default) | Vague: "a large host gathers in the east," rough size and direction |
| Allied and vassal networks (shared vision) | Positions of armies near allies |
| Watchtowers and outposts | Exact positions in range |
| Embedded spies | Exact composition, commander, intentions, and planned targets |

### 3.3 Deception and hiding **(Confirmed)**
- **False reports:** spies can feed the enemy fake troop movements, hiding an army for a turn or two.
- **Hiding an army:** possible in forests, with spymaster skills, or by **screening** (the army stays put, spends a few men and most of its movement to clear spies around it). Costly by design.

### 3.4 Shared vision **(Confirmed)**
Alliance and vassal agreements include shared vision.

---

## 4. Vassals and confederation

### 4.1 Fealty, not absorption **(Confirmed)**
- "Confederation" in the UI means a house **swears fealty**. It stays its own faction with its own family, lands, armies, and banners, loyal to you.
- When you conquer a house, you can **leave its family in power as a vassal** instead of absorbing it.
- Your realm can be **mostly direct lands, mostly vassals, or a blend**, depending on how you play.

### 4.2 Commanding vassals **(Confirmed)**
- **Armies:** you give orders (attack this, defend that, join my host, besiege here). Vassals carry them out **promptly and with real force**.
- **Economy:** you set **broad goals** per vassal; the AI manages the rest.
  - Goals: **Fortify** (walls, garrisons, military buildings), **Military** (armies, barracks), **Economy** (markets, farms, mines), **Balanced**.
  - Example: border vassals fortify and arm; heartland vassals grow the economy.
- Vassals **never become stronger than you**. (Proposed: hard cap on any single vassal's size relative to the overlord, enforced by AI behavior and title rules.)

### 4.3 Vassal goals **(Confirmed)**
Each vassal has personal goals (a neighbor's land, a marriage, a title, revenge on a rival). They **tell you** what they want. Helping them earns loyalty and **gives you a cut** (gold, a share of conquered land, troops).

### 4.4 Loyalty **(Confirmed: well-treated vassals never rebel)**
Loyalty rises with: marriages, protection, shared enemies, gifts, honoring oaths, winning wars together, helping their goals, time, titles granted.

**Wavering (Proposed):** loyalty only falls through:
- **Neglect:** ignoring their goals and calls for help.
- **Dishonor:** you betray allies, break oaths, or attack fellow vassals.
- **Humiliation:** repeatedly calling their banners for wars with no plunder or glory, or sacrificing their troops.
- **Enemy intrigue:** rival spies working on them (counterable).
- Every drop is visible with a reason, and fixable before anything happens. Low-loyalty vassals turn out fewer troops and slower; only a neglected vassal at rock bottom can break away (one region at most, with the Liberator's Call rules from game-design.md).

### 4.5 Lore friendships **(Confirmed)**
Starting lore pre-defines natural allies and old rivalries (like Gelt and the Emperor in Total War: Warhammer), so the player knows which houses to court early. Written per playable start in `v1-content.md`.

---

## 5. Titles **(Confirmed)**

- Titles exist **per race and per region** (examples: **High King of Aldryn**, **Warden of the North**, **Archon of the Coast**, **First Senator of the Republic**, **Lord of the Marches**).
- Titles are **collectible** (hold several) and **dynamic** (they change hands through conquest, election, inheritance, or grant).
- **Earned** by being a powerful faction that is loved or feared, plus title-specific conditions (control of key regions, number of vassals, a Senate vote, a Throne Church blessing).
- **Powers:** easier to win vassals in that area, decrees over vassals in the title's region, larger banner turnout, diplomatic weight. Each title has 2-3 unique powers.
- **Proposed:** you can **grant** lesser titles to vassals or family as a loyalty reward.

---

## 6. Alliances and joint war

### 6.1 Fighting together **(Confirmed)**
- **Plan campaigns with allies:** assign targets, fronts, and timing; see allied armies' orders.
- **Borrow allied armies:** control an ally's army for a campaign.
- **Combine in battle:** allied armies nearby join automatically.

### 6.2 Good and evil in every race **(Confirmed)**
- Every race has factions across a **good-to-evil spectrum**. Evil human factions can ally with Destruction races; good orc factions can side with Order.
- **Event (example):** a good orc faction is driven from its lands, warns you of a coming invasion, and asks for land. Accept (a fierce ally, scorn from prejudiced humans) or refuse.
- Factions can **fall to Chaos** or side with evil factions as the Ages progress.

### 6.3 Betrayal **(Confirmed direction)**
Betraying an ally during an invasion carries massive consequences: you **turn to Chaos** and can never align with any non-Chaos faction. Chaos as a playstyle is post-V1; in V1 this triggers the existing betrayal rule and is flagged for the Chaos expansion.

---

## 7. Economy: resources, markets, trade

### 7.1 Resources **(Confirmed)**
| Resource | Produced by | Used for |
|---|---|---|
| **Gold** | Taxes, trade, mines, markets | Everything; buys other resources |
| **Food** | Farms, fishing, pastures | Population, armies' supply, sieges, winter |
| **Wood** | Lumber towns, forests | Buildings, ships, siege works |
| **Stone** | Quarries, mountain regions | Buildings, walls, fortifications |

- Specialization paths map to production (farming = food, mining = gold and stone, lumber = wood, market = gold and trade, military = troops).
- **Minerals** from the old list fold into gold (mines) and stone (quarries).

### 7.2 Markets **(Confirmed: gold buys the rest)**
- Buy or sell food, wood, and stone for gold at a **regional market**.
- **Prices vary** by scarcity (wood sells high in the desert, food high in winter). Simple and readable, not a full dynamic economy.
- A very rich faction can buy whatever it lacks.

### 7.3 Trade **(Confirmed)**
- Trade agreements draw routes on the map (visual) with abstract income.
- **Trade continues during war** with tariffs and disruption; raids skim it, blockades cut it, either side can cancel.
- **Envoys can reach anyone** on the map, traveling automatically in the background. Distant factions can trade and talk without ever meeting in battle.

---

## 8. The Ages (campaign arc) **(Confirmed concept; triggers Proposed)**

### 8.1 Principles
- The campaign moves through **Ages**: named eras that each bring a defining threat. Triggered by **world conditions**, not fixed turns, with a latest-turn backstop.
- **Each playable culture gets its own version** of each Age.
- Ages **repeat and escalate** (they can come twice or three times), so the game never runs out of drama.
- Each Age has **goals with rewards** (titles, relics, mechanics), but the game never ends.
- When an Age begins: a **named banner** ("The Age of Iron Oaths"), an illustrated **event**, and a Grey Scribes entry.
- By about **turn 100**, each race should have **2-3 superpowers**.

### 8.2 The sequence (placeholder ordering)
| Age | What happens | Proposed trigger |
|---|---|---|
| **1. The Scramble** | Start: neighbors of your race and one hostile race nearby; quick early expansion (Liberator's Call, marriages, minor wars) | Campaign start |
| **2. The Rivalry** | A real war with a rival power of your own race doing the same thing as you (Britain vs. France) | You or your rival controls a set number of regions, or turn ~30 |
| **3. The Breather** | Consolidation, intrigue, building, vassal politics (can be skipped by events) | Rivalry ends or stalls |
| **4. The Invasion** | A full invasion from one hostile race; your race must unite or fall | Your race has 2-3 strong powers, or turn ~60 |
| **5. The Great Coalition** | Invasion by a coalition of Destruction races (evil vs. good); cross-race alliances become essential | The world's Order powers are strong enough, or turn ~100 |
| **6. Chaos** | World-ending threat from the far east (post-V1) | Post-V1 |

### 8.3 Per-culture invasions (Proposed)
| Culture | First invasion (Age 4) | Coalition (Age 5) |
|---|---|---|
| **Medieval (North)** | Orcs break the Greywall | Orcs, beastmen, dark elves |
| **Roman (South)** | Ratmen rise from the Skulkmire and Sothmire | Ratmen, dark elves, evil desert dominions |
| **Greek (West coast)** | Dark elf reaver fleets and the Black Ark | Dark elves, ratmen, beastmen from overseas |

### 8.4 Invasion rules **(Confirmed)**
- Invasions **always happen** and are **dangerous**, scaled to the world's strength.
- The player **prepares** by fortifying and militarizing border regions, keeping the heartland economic, building alliances, and holding chokepoints (the Wall).
- Factions that face an invasion alone usually **fall**; survival needs a superpower or a coalition.
- During invasions, AI factions can **backstab** each other or **defect** to the invaders.

### 8.5 The rhythm of war **(Confirmed)**
War is constant but varied: raids, border skirmishes, minor lords feuding, helping allies, meddling in AI wars, with **big wars arriving in waves** tied to the Ages. War length follows scale, not a turn limit.

---

## 9. Seasons **(Confirmed concept; details Proposed)**

Goal: Game of Thrones seasons that create anticipation, not chores.

1. **Long, irregular seasons:** summers last 3-9 years (turns), winters 1-3, randomized per campaign.
2. **Forecasts:** your scholars (or priests, oracles, seers by culture) predict winter **2-4 turns ahead**, with confidence that improves with research. "Winter is coming" is an event.
3. **Summer:** food bonus, normal campaigning.
4. **Winter:**
   - Food production drops, **more the further north**; the south barely changes.
   - Armies in enemy land drain supply faster; friendly land stays painless.
   - Snow slows movement in the north and in mountains.
   - The map turns progressively white (desert and jungle cultures get a dry season instead of snow).
   - Winter favors intrigue, building, marriages, and feasts over war.
5. **Food stockpiles** let prepared rulers ride out winter; markets let rich ones buy food.
6. **Long winters** (2-3 years) are rare, dramatic events.

---

## 10. Navies **(Proposed, owner left to designer)**

1. **Fleets:** built at ports (wood cost), led by admirals (a General career variant).
2. **Transport:** armies embark at a port (or on any coast at a movement penalty) and sail as part of a fleet.
3. **Blockades:** a fleet next to an enemy port cuts that port's sea trade and supply.
4. **Raiding:** fleets in raiding stance skim sea trade routes.
5. **Naval battles:** auto-resolved with stances, like land battles.
6. **High seas:** early ships hug coasts; research unlocks ocean-going ships (reaching Sothmire and crossing quickly).
7. **Culture strengths:** Greeks and dark elves strongest at sea; elves strong; dwarves and orcs weak.
8. **The Black Ark** is a moving dark elf fortress-fleet.

---

## 11. The AI **(Proposed, owner left to designer)**

Built in layers, each tested with AI-only soak runs before the next.

| Layer | Responsibility |
|---|---|
| **Strategic** | Faction goals (expand, survive, ally, scheme) by tendency and position; responding to the Ages; choosing allies and enemies; deciding to defect to invaders |
| **Campaign** | Forming hosts, calling banners, choosing targets, coordinating with allies, holding chokepoints, sieges |
| **Vassal** | Obeying the overlord's orders promptly with real force; running the economy toward the assigned goal; pursuing personal goals and asking the overlord for help |
| **Court and intrigue** | Using their own agents and schemes (with the warning guarantee toward the player) |
| **Economy** | Building by specialization path, managing food, wood, stone, gold; trading at markets |

**Targets:** superpowers emerge naturally by ~turn 100; invasions are genuinely dangerous; vassals feel loyal and competent; AI turn time stays within budget on the full map.

---

## 12. First playable milestone **(Proposed)**

Before building everything everywhere, reach one complete, fun slice:

1. **Map:** Stage A slice (North to Red Peaks).
2. **Playable:** **House Varn (Medieval North)** first; it exercises the most systems (the Wall, the Throne Church, feudal vassals, an orc invasion). Roman and Greek follow.
3. **Systems:** stance battles; resources and markets; hosts, banners, vassals, titles; court and characters (careers, traits, loyalty, marriage); agents with core missions; diplomacy; seasons; Ages 1-4 for the North; events with art; research for Medieval.
4. **AI:** strategic, campaign, and vassal layers.
5. **Goal:** play turns 1-80 as House Varn and feel the arc: early scramble, rivalry with a southern house, the Wall breaking, uniting the North.

Then: add Roman and Greek starts, the rest of Stage A content, Age 5, and later map stages.

---

## 13. Open questions
1. Exact numbers: army build time, banner turnout by reputation, zone-of-control radius by army size, supply drain, season lengths, market prices.
2. Vassal size cap relative to the overlord.
3. Title list and each title's powers (draft in `v1-content.md`).
4. Age triggers and backstop turns.
5. Whether winter forecasts can be wrong.
6. Which second playable culture follows the North.
