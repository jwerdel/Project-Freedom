# Project Freedom: V1 Content

**Status:** Approved direction (owner, 2026-10-05). Content written by the designer from the world bible, owner decisions, and Total War / Warhammer conventions. All names, stats, and numbers are placeholders; items marked Proposed still need the owner's approval before implementation.
**Companions:** `docs/game-design.md`, `docs/world-bible-v2.md`, `docs/war-and-realm.md`.

## Contents
1. Unit rosters
2. Characters: traits, epithets, skill trees
3. Titles and lore friendships
4. Events
5. Research
6. Religion details
7. Art style guides (portraits, events, cards)

---

## 1. Unit rosters

### 1.1 Structure (Total War pattern)
Total War: Warhammer rosters group units by **category** (melee infantry, missile infantry, cavalry, war machines, monsters) and **tier**, with **weapon variants** of the same soldiers (e.g. Spearmen and Spearmen with Shields; Halberdiers; Swordsmen; Greatswords). We follow the same pattern:

- **Tiers 1-5**: tier 1 is levy-grade, tier 5 is elite or legendary.
- **Shared base soldiers per culture**, varied by weapons and armor.
- **Unit roles**: Line (hold), Anti-large (spears, halberds vs. cavalry and monsters), Shock (charge), Missile, Skirmish (light and fast), Siege (war machines), Monster.
- **Levy vs. professional**: levy units come from calling banners (cheap, weaker); professional units come from buildings and cost upkeep.
- **Buildings unlock tiers**: barracks (infantry), ranges (missile), stables (cavalry), workshops (siege), special buildings (monsters).
- Each unit has: category, tier, role, men, cost, upkeep, turns, stats (melee attack, defense, armor, missile, charge, morale, speed), and tags (shielded, anti-large, armor-piercing, fear, flying, large).

### 1.2 Medieval humans (House Varn and the North)
Heavy cavalry and steadfast infantry, holy warriors, few but mighty monsters.

| Tier | Unit | Category | Role | Notes |
|---|---|---|---|---|
| 1 | Peasant Levy | Melee infantry | Line | Pitchforks and spears; levy |
| 1 | Levy Bowmen | Missile | Missile | Short bows; levy |
| 1 | Spearmen | Melee infantry | Anti-large | Mail and spear |
| 1 | Spearmen (Shields) | Melee infantry | Anti-large | Sturdier variant |
| 2 | Men-at-Arms | Melee infantry | Line | Sword and shield, mail |
| 2 | Crossbowmen | Missile | Missile | Armor-piercing |
| 2 | Mounted Sergeants | Cavalry | Shock | Light lance cavalry |
| 2 | Longbowmen | Missile | Missile | Long range |
| 3 | Halberdiers | Melee infantry | Anti-large | Armor-piercing |
| 3 | Greatswords of the Throne | Melee infantry | Shock | Two-handed swords, oath-sworn |
| 3 | Knights of the Realm | Cavalry | Shock | Heavy lance cavalry |
| 3 | Trebuchet | War machine | Siege | Wall breaker |
| 4 | Templars of the Undying Throne | Cavalry | Shock | Holy knights; fear-resistant; Throne Church building required |
| 4 | Penitent Host | Melee infantry | Shock | Frenzied zealots; never rout |
| 4 | Winter Bears | Monster | Shock | Trained war bears; North only |
| 5 | Griffon Knights | Monster cavalry | Shock | Flying; North high-tier |
| 5 | Throne Colossus | Monster | Siege/Shock | Armored holy war-beast of the Throne Church; legendary |

### 1.3 Roman humans (House Varrenus and the south)
Disciplined legions, engineering, heavy infantry; monsters from the arena and the south.

| Tier | Unit | Category | Role | Notes |
|---|---|---|---|---|
| 1 | Rural Levy | Melee infantry | Line | Levy |
| 1 | Slingers | Missile | Skirmish | Cheap, fast |
| 1 | Hastati | Melee infantry | Line | Sword and scutum |
| 1 | Hastati (Pila) | Melee infantry | Line | Throws javelins before charging |
| 2 | Principes | Melee infantry | Line | Mail, heavier |
| 2 | Auxiliary Archers | Missile | Missile | Composite bows |
| 2 | Equites | Cavalry | Shock | Medium cavalry |
| 2 | Triarii | Melee infantry | Anti-large | Veteran spearmen |
| 3 | Legionaries | Melee infantry | Line | Lorica segmentata; testudo-like defense |
| 3 | Scorpion | War machine | Missile | Bolt thrower |
| 3 | Onager | War machine | Siege | Wall breaker |
| 4 | Praetorian Guard | Melee infantry | Line | Elite; ruler's guard |
| 4 | Cataphracts | Cavalry | Shock | Armored cavalry |
| 4 | War Elephants | Monster | Shock | From southern trade; fear |
| 5 | Arena Beasts | Monster | Shock | Chained monsters unleashed in battle; chaotic |
| 5 | Bronze Siege-Titan | Monster | Siege | Legendary engine-construct |

### 1.4 Greek humans (the Aurekids and the coast)
Phalanxes, skirmishers, sea power; mythic monsters.

| Tier | Unit | Category | Role | Notes |
|---|---|---|---|---|
| 1 | Citizen Levy | Melee infantry | Line | Levy |
| 1 | Peltasts | Missile | Skirmish | Javelins, fast |
| 1 | Hoplites | Melee infantry | Anti-large | Spear and aspis; phalanx |
| 2 | Toxotai | Missile | Missile | Archers |
| 2 | Hippeis | Cavalry | Skirmish | Light cavalry |
| 2 | Marines | Melee infantry | Line | Ship-borne; bonus on coasts |
| 3 | Elite Hoplites | Melee infantry | Anti-large | Bronze-armored phalanx |
| 3 | Thureophoroi | Melee infantry | Line | Oval shield, versatile |
| 3 | Lithobolos | War machine | Siege | Stone thrower |
| 4 | Sacred Band | Melee infantry | Shock | Oath-bound elite pairs; never rout while paired |
| 4 | Companion Cavalry | Cavalry | Shock | Elite |
| 4 | Centaurs | Monster cavalry | Skirmish | Archers; fast |
| 5 | Bronze Automatons | Monster | Line | Unbreakable constructs |
| 5 | Griffons | Monster | Shock | Flying |
| 5 | Cyclops | Monster | Siege | Legendary; hurls boulders |

### 1.5 AI races: base rosters (V1)
Compact rosters until each race becomes playable. Each needs at least: levy, line, anti-large, missile, cavalry or fast unit, elite, and 1-3 monsters.

| Race | Levy / line | Anti-large | Missile | Fast / cavalry | Elite | Monsters |
|---|---|---|---|---|---|---|
| **Tomb-King desert** | Sand Levy, Spearmen | Temple Guard | Archers, Slingers | Chariots | Ushabti-like guardians | Bone Giant, Walking Sphinx, Scorpion Construct |
| **Dwarves** | Clan Warriors | Longbeard Halberds | Crossbowmen, Thunderers | (none; Mountain Rangers) | Ironbreakers, Hammerers | Gyro-flyer, Organ engine |
| **Orcs** | Goblin Mob, Orc Boyz | Big Spears | Goblin Archers | Wolf Riders, Boar Boyz | Black Iron Orcs | Trolls, War-Mammoth, Giant |
| **Elves** | Spearguard | Silverspears | Archers, Sea Guard | Silver Riders | Swordmasters, Phoenix Guard | Great Eagles, Dragon (legendary) |
| **Dark elves** | Dreadspears, Bleakswords | Black Guard | Crossbowmen | Dark Riders | Executioners, Witch-sisters | Sea Serpent, War Hydra, Harpies |
| **Beastmen** | Ungor Herd | Ungor Spears | Ungor Raiders | Centigors, Razorgors | Bestigor | Minotaurs, Cygor, Jabberslythe-like horror |
| **Ratmen** | Clanrats, Slaves | Clanrat Spears | Globadiers, Jezzail-like rifles | Gutter Runners | Stormvermin | Rat Ogres, Doom-bell engine, Abomination |
| **Lizardmen** | Skink Cohort, Saurus Warriors | Saurus Spears | Skink Skirmishers | Cold One Riders | Temple Guard | Stegadon, Carnosaur, Bastiladon |

(Names are placeholders inspired by archetypes; final names must be original before any public use.)

> **Rename before any public release.** These unit names echo Warhammer and are placeholders only: Temple Guard, Ushabti-like guardians, Bone Giant, Walking Sphinx, Ironbreakers, Hammerers, Thunderers, Longbeard Halberds, Gyro-flyer, Organ engine, Orc Boyz, Boar Boyz, Black Iron Orcs, Wolf Riders, Goblin Mob, Silverspears, Swordmasters, Phoenix Guard, Sea Guard, Silver Riders, Great Eagles, Dreadspears, Bleakswords, Black Guard, Dark Riders, Executioners, Witch-sisters, War Hydra, Harpies, Ungor Herd, Ungor Spears, Ungor Raiders, Centigors, Razorgors, Bestigor, Minotaurs, Cygor, Jabberslythe-like horror, Clanrats, Globadiers, Jezzail-like rifles, Gutter Runners, Stormvermin, Rat Ogres, Doom-bell engine, Abomination, Skink Cohort, Saurus Warriors, Saurus Spears, Skink Skirmishers, Cold One Riders, Stegadon, Carnosaur, Bastiladon. Also check §1.2-1.4 (for example Knights of the Realm, Greatswords) before release.

---

## 2. Characters

### 2.1 Trait system
- Traits come from **birth, upbringing, life events, and deeds**. They are earned, not chosen.
- Each character has up to **6 visible traits**; some are hidden until a spy reveals them (Secrets).
- Traits affect stats, loyalty, opinions, event outcomes, and AI behavior.
- Many traits have **levels** (e.g. Brave I-III) that grow with repeated deeds.

### 2.2 Trait list (V1)
**Personality (from upbringing and events)**
| Trait | Effect (direction) |
|---|---|
| Brave / Craven | Battle morale; Craven generals withdraw early |
| Cruel / Merciful | Fear vs. love; post-battle and capture choices |
| Honorable / Deceitful | Oath reliability; scheme success |
| Ambitious / Content | Requests for titles and land; loyalty drift |
| Pious / Cynical | Church influence; priest effectiveness |
| Generous / Greedy | Loyalty from gifts; governor income |
| Wrathful / Calm | Stance preference; diplomacy |
| Cautious / Reckless | Defensive vs. Aggressive stance bonus |
| Just / Arbitrary | Public order as governor |
| Charismatic / Awkward | Envoy and marriage success; banner turnout |
| Paranoid / Trusting | Counter-intel vs. vulnerability to schemes |

**Competence (from career and deeds)**
| Trait | Earned by |
|---|---|
| Strategist | Winning battles against stronger foes |
| Siege Master | Taking walled settlements |
| Logistician | Long campaigns without attrition |
| Administrator | Governing a region well for years |
| Spymaster | Successful agent missions |
| Silver Tongue | Successful negotiations |
| Merchant Prince | Profitable trade deals |
| Scholar | Research focus, education events |
| Duelist | Winning duels (warlords) |

**Life and body**
| Trait | Notes |
|---|---|
| Scarred | Survived a near-death battle; respect |
| Maimed | Lost a limb; weaker in combat, respected |
| Kinslayer | Killed family; massive loyalty and reputation penalty |
| Bastard / Legitimized | Birth status; politics |
| Prodigy / Broken | Early-lord gamble outcomes |
| Ward of [House] | Raised by another house; loyalty link |
| Immortal | Level 20 or legendary founder |

**Racial and cultural (examples)**
| Trait | Culture |
|---|---|
| Wall-Sworn | Medieval (served at the Greywall) |
| Senator | Roman (holds a Senate seat) |
| Oracle-Touched | Greek |
| Grudge-Bearer | Dwarves |
| Starborn | Elves |

### 2.3 Epithets
- A character earns **one epithet** when a defining pattern of deeds crosses a threshold. It can change once later if their legacy shifts.
- Epithets show in their name ("Edric the Wise") and color reputation.

| Epithet | Earned by |
|---|---|
| the Great | Conquering many regions and winning many battles |
| the Conqueror | Taking many settlements |
| the Wise | Just rule, high public order, good counsel |
| the Just | Fair judgments in events |
| the Builder | Many buildings and landmark upgrades |
| the Pious | Church devotion, Holy Wars |
| the Merciful | Sparing captives and cities |
| the Cruel | Executions, razing |
| the Butcher | Razing cities, massacres |
| the Kinslayer | Killing family |
| the Liberator | Answering Liberator's Calls |
| the Wallwarden | Defending the Greywall |
| the Silver-Tongued | Many diplomatic successes |
| the Shadow | Many successful schemes (if exposed) |
| the Unbroken | Surviving desperate defenses |
| the Golden | Great wealth |
| the Young | Ruling as a teen (early-lord gamble) |
| the Undying | Becoming immortal |
| the Oathbreaker | Betraying allies |

### 2.4 Skill trees (one per career)
Each career has **3 branches** of about **6-8 skills**; one point per level; level 20 is rare. Key skills shown.

**General** (leads armies)
| Branch | Key skills |
|---|---|
| Command | Inspiring Presence (morale), Iron Discipline (Defensive bonus), Fury of Battle (Aggressive bonus), Veteran Officers (unit experience), Rally Point |
| Logistics | Forced March (movement), Foragers (supply in enemy land), Winter Campaigner, Siege Engineers, Recruitment Capacity +1/+2 |
| Conquest | Terror (enemy morale), Plunder (loot), Pacifier (public order in conquered land), Raider, Holds the Line (zone of control radius) |

**Warlord** (single-entity champion)
| Branch | Key skills |
|---|---|
| Duelist | Challenge (duel enemy lords), Killing Blow, Unstoppable |
| Monster | Monstrous Strength, Terrifying Presence; level 20 path toward Ascension (post-V1 details) |
| Hunter | Beast Slayer (legendary monsters), Tracker, Trophies (morale) |

**Assassin**
| Branch | Key skills |
|---|---|
| Blade | Wound, Assassinate, Poisoner, Clean Kill (no trace) |
| Sabotage | Burn Outposts, Sabotage Buildings, Spoil Supplies |
| Ghost | Evasion, Disguise, Unbreakable (never confesses, early) |

**Spy**
| Branch | Key skills |
|---|---|
| Whispers | Rumors, Forge Letters, Sow Distrust, False Reports (hide armies) |
| Networks | Embed in Court, Steal Secrets, Informant Web (intel range), Shared Eyes |
| Counter | Catch Spies, Turn Agents (double agents), Secure Court |

**Politician**
| Branch | Key skills |
|---|---|
| Diplomacy | Envoy, Treaty Maker, Marriage Broker, Silver Tongue |
| Governance | Administrator, Tax Collector, Peacekeeper, Builder |
| Intrigue | Bribery, Coup Funding, Kingmaker (support claimants), Senate Influence (Roman) |

**Merchant**
| Branch | Key skills |
|---|---|
| Trade | Trade Routes, Tariff Master, Market Insight (better prices) |
| Wealth | Investor (gold over time), Moneylender (loans to factions), Moonvault Contacts |
| Shadow Trade | Smuggling, Secret Funding, Arms Dealer (fund both sides) |

**Wizard**
| Branch | Key skills |
|---|---|
| Battle Magic | Fireball-type damage, Shielding Wards, Curse of Weakness |
| Earth and Sky | Seal Pass, Bless Harvest, Call Storm (sea), Plague Region |
| Sight | Scry Court, Detect Spies, Protect Ruler |

**Priest**
| Branch | Key skills |
|---|---|
| Faith | Sermon (public order), Conversion, Miracles (events) |
| Church | Church Influence, Exarch Candidacy, Holy War Preacher |
| Zeal | Inquisitor, Denounce (Anathema pressure), Martyr's Courage (morale) |

---

## 3. Titles and lore friendships

### 3.1 Starting titles (V1, Stage A)
| Title | Region | Powers (2-3) | How to earn |
|---|---|---|---|
| **High King of Aldryn** | All Aldryn humans | Summon all vassals' banners at once; vassal loyalty floor; decrees over vassals | Most powerful human faction, loved or feared, controlling Caeloth's favor or 3 human cultural capitals |
| **Warden of the North** | The North | Bonus to Wall garrisons; northern vassals easier; winter immunity for armies | Control Frosthold and 6 northern regions, or defend the Wall in the orc invasion |
| **Warden of the Wall** | The Greywall | Command the Wardens; orc intel | Granted by Wardens or High King |
| **First Senator** | Roman lands | Extra Senate votes; Roman families easier to absorb | Senate vote |
| **Consul of the Republic** | Roman lands | Command of combined legions; decrees | Unite most Roman families |
| **Archon of the Coast** | Greek coast | League leadership; naval bonuses | Lead a league of 4+ cities |
| **Lord of the Marches** | Middle Marches | Toll income at Harrow Crossing; river trade | Control Harrow Crossing and the river regions |
| **Defender of the Faith** | Throne Church lands | Holy War command; Church influence | Lead a successful Holy War |

### 3.2 Lore friendships and rivalries (starting relations)
**House Varn (North)**
- Friends: **House Kells** (old blood-oath), **the Wardens of the Greywall** (Varn sons serve there), **House Aldane of Skyreach** (cautious respect).
- Rivals: **House Dunmoor** (Liberator's Call target), the **Ironjaw Horde** (ancient enemy), southern Roman houses (cultural distrust).
- Potential surprise ally: the **Redhand Warband** (good orcs seeking a human friend).

**House Varrenus (Roman)**
- Friends: **House Aemerius** (marriage ties), **Port Dallow** (trade).
- Rivals: **House Corvinus** (rival for the Senate, holds Crownhaven), **the Tullan estates** (Liberator's Call target), **House Durran** (martial rivals in the Stormlands).
- Threat: the Skulkmire Brood.

**The Aurekids (Greek)**
- Friends: **Theros** (old league partner), **Delos Minor** (island colony).
- Rivals: **the Lannetids of Silverfall** (Liberator's Call target), **the Philandrid tyranny of Kyme** (coastal rival), **the Reavers of Brinecrag** (raiders).
- Potential ally: **Aelthas** (elven bankers across the sea).

---

## 4. Events

### 4.1 Writing guide
- **Length:** 2-4 sentences of setup, 2-3 choices. Readable in 15 seconds.
- **Choices** show clear consequences in tooltips (TW-clear, not CK-dense). No "right answer"; each choice trades something.
- **Voice:** grounded, dark, a little literary. Grey Scribes style for chronicle entries; characters speak in their own voice.
- **Art:** every major event has a painted illustration (Section 7). Minor events reuse a pool of generic illustrations.
- **Triggers:** each event lists conditions (culture, season, Age, traits, situation) and a cooldown.
- **Chains:** important events chain over several turns (setup, escalation, resolution).
- **Frequency:** front-loaded early, tapering to a steady rhythm.
- **Data:** events are data files (id, title, text, conditions, choices, effects, art id), so CC can generate many from this guide.

### 4.2 Starter event list (V1, ~70)
**Court and family**
1. A Child's Calling (choose a career path)
2. The Early Gamble (make a child a lord early)
3. A Marriage Proposal Arrives
4. Rival Siblings
5. The Neglected Branch (favoritism resentment)
6. A Courtier's Request (title, region, command)
7. The Ward's Loyalty
8. A Bastard Claims Kinship
9. Feast of the Houses (loyalty and gossip)
10. The Heir's First Battle
11. A Courtier Ascends (level 20, immortality)
12. Captive Kin (ransom, rescue, abandon)

**Intrigue**
13. Intercepted Letter (warning of a plot)
14. A Plot Uncovered (execute, imprison, double agent)
15. The Assassin Arrives (target absent)
16. A Spy Is Caught
17. Whispers of Treachery (suspicion builds)
18. The Forged Insult (your scheme bears fruit)
19. Secrets for Sale
20. A Rival's Spymaster Defects

**Rule and realm**
21. Petition of the Commons
22. The Liberator's Call
23. A Governor's Corruption
24. A Hated Governor (people seek a replacement)
25. The Merchant Guild's Demand
26. Plague in the Lowlands
27. Bountiful Harvest
28. Famine Looms
29. A Town Chooses Its Path (specialization prompt)
30. The Great Fire
31. Refugees at the Gates
32. A Monument Proposed

**War and hosts**
33. The Banners Gather (muster)
34. Word from the Merchants (enemy host spotted)
35. A Vassal Asks for Aid
36. A Vassal's Ambition (goal request)
37. Victory Spoils (divide plunder)
38. The Siege Drags On
39. Hold the Bridge
40. Captured Lord (ransom, execute, recruit)
41. Mutiny of the Levies (feared-but-weak rulers only)
42. Hero of the Battle (promotion)

**Diplomacy**
43. An Envoy from Afar
44. The Threat (demand under threat)
45. Alliance Offer
46. A House Seeks Fealty
47. Tariff Dispute
48. Ally Betrayed (another faction's betrayal)

**Religion**
49. The Voice Is Dead (election)
50. Buying Votes
51. A Holy War Is Called
52. Anathema Threatened
53. The Inquisition Arrives
54. An Oracle Speaks (Greek)
55. Omens Before Battle (Roman)
56. A Cult in the City

**Seasons**
57. Winter Is Coming (forecast)
58. The Long Winter
59. Spring Thaw
60. The Wall Freezes Over

**The Ages**
61. Age Begins: The Scramble
62. Age Begins: The Rivalry
63. Age Begins: The Invasion
64. Age Begins: The Great Coalition
65. The Exiled Orcs (good orcs seek land)
66. The Wall Is Breached
67. The Black Ark Sighted
68. Ratmen Beneath the City
69. A Faction Turns to Darkness
70. The Coalition Forms

---

## 5. Research

### 5.1 Structure
- Each culture has its own tree with **4 branches**: **Economy**, **Military**, **Statecraft**, **Faith and Lore**.
- Each branch has **4-5 tiers** of 2-3 techs; later tiers require earlier ones and a settlement level or building.
- Research takes turns; something is **always** researching (TW-style).
- Research unlocks: buildings, unit tiers, ship types, decree slots, agent skills, season forecasting, culture mechanics.

### 5.2 Medieval tree (example)
| Branch | Tier 1 | Tier 2 | Tier 3 | Tier 4 | Tier 5 |
|---|---|---|---|---|---|
| Economy | Three-Field Rotation | Watermills | Guild Charters | Great Fairs | Royal Mint |
| Military | Levy Musters | Crossbow Guilds | Plate Armor | Knightly Orders | Griffon Eyries |
| Statecraft | Feudal Oaths | Royal Courts | Spymaster's Office | Chancery | High Kingship |
| Faith and Lore | Parish Churches | Throne Pilgrimage | Templar Orders | Inquisition | Cathedral of the North |

Roman (Senate, Legions, Engineering, State Cult) and Greek (Leagues, Phalanx, Navies, Oracles) trees follow the same structure. AI races get simplified trees.

---

## 6. Religion details

### 6.1 Throne Church influence
- Influence is a **value per faction** with the Throne Church (0-100).
- **Gain:** missions completed, religious buildings, tribute, marriages into Church-aligned families, manning the Wall, joining Holy Wars, priests in your court.
- **Loss:** attacking Church-protected targets, ignoring missions, proven heinous schemes, harboring heresy.
- **Uses:** trade privileges in Caeloth, ruler legitimacy, requesting Holy Wars and choosing targets, election weight.

### 6.2 Exarchs and seats
- **15 Exarch seats** (placeholder).
- Medieval (Throne Church) realms fill most seats; Roman and Greek realms hold **3 honorary seats** total.
- A pious priest at level 10+ with high influence can be **raised to Exarch** when a seat opens.

### 6.3 Elections
1. The Voice dies (age, event, or assassination; assassination is massively punished if proven).
2. The three most pious Exarchs become candidates.
3. Over **2 turns**, factions campaign: buy votes (gold), promise support, scheme against candidates.
4. Exarchs vote; each Exarch's vote follows their own faction's preference, modified by bribes and loyalty.
5. The new Voice favors the factions that backed them (influence boosts) and resents those that opposed.

### 6.4 Holy Wars
1. **Called** by the Voice (or requested by a faction with high influence, who may choose the target).
2. Targets: heretics, Destruction factions, anathematized factions.
3. **Joining window:** 5 turns.
4. Joining armies get movement and morale bonuses; joiners share rewards when the target falls (gold, influence, titles).
5. Factions that refuse lose influence; enemies of the target gain a justification.

### 6.5 Anathema
- Imposed on proven heinous acts, attacking Church-protected targets, or repeated defiance.
- Effects: public order penalty, every faithful faction gains a war justification, Holy Wars can target you.
- Lifted by: a new Voice, a new ruler, or penance (gold, tribute, missions).

### 6.6 The Radiant Seven
- **Temples** to each god give targeted bonuses: Aurel (order, legitimacy), Vessa (growth, food), Kael (military morale), Merovan (trade), Ilith (research, oracles), Thalor (navies), Morra (honor of the dead, loyalty).
- **Roman state cult:** omens before war (morale), triumphs dedicated to the Seven (reputation), priestly offices as Senate seats.
- **Greek oracles:** consult (gold) for a prophecy event; bribe to influence what others hear; ignore at a small risk.
- **Schism events** with the Throne Church can trigger Holy Wars between human cultures.

### 6.7 Other faiths (AI flavor in V1)
Book of Grudges (dwarves), Prophecies (elves), Great Hordes (orcs), Mortuary Cult (desert), Blood Rites (dark elves), Herdstones (beastmen), Clan Treachery (ratmen), the Old Plan (lizardmen). Each gives its AI one behavior driver (e.g. dwarves pursue recorded grudges; orcs launch hordes when strong).

### 6.8 Foreign cults
Faiths plant cults in other factions' settlements (TW-style): Throne Church missions, ratmen clans, dark elf slaver dens, desert mortuary cults. Effects: influence, unrest, intel, conversion. Chaos cults post-V1.

---

## 7. Art style guides

### 7.1 Character portraits (Gemini)
- **Format:** head and shoulders, square 1:1, painterly, same style as the landmark and biome art (vivid, grimdark, epic).
- **Consistent framing:** three-quarter view, dark atmospheric background tinted by faction color, no text.
- **Per culture:** clothing, armor, and features match the culture (Medieval mail and furs; Roman togas, laurels, bronze; Greek white linen, bronze helms; etc.).
- **Age stages:** child, youth (12-16), adult, so portraits can show growing up.
- **Plan:** a pool of ~20 portraits per culture and gender as a start; legendary founders get unique portraits.

### 7.2 Event illustrations
- **Format:** landscape 16:9, painterly scene, same style.
- **Plan:** unique art for major events (Ages, elections, Liberator's Call, Wall breach); a shared pool of ~30 generic scenes (court, battlefield, feast, plague, harvest, letters, executions) reused across minor events.

### 7.3 Unit cards
- Tall portrait cards, consistent framing, original heraldry, per the existing card art rule. Generate when rosters are approved.
