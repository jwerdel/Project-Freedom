# Project Freedom — Design Constitution

Status: living design draft. Confirmed decisions below record the user's intent; open questions are not approved mechanics. Reference names describe inspiration and are not final world or faction names. A first local visual prototype has been implemented in ProjectFreedom; campaign mechanics remain unimplemented.

## Vision

A fantasy strategy game combining Total War's accessible campaign interface, armies, and territorial play with deeper dynasties, relationships, politics, and economic connections inspired by Crusader Kings. Prioritize macro decisions, personal stories, and a changing political map over repetitive micromanagement. The player should know their faction's people and see their decisions change the world.

## Project constraints

- Use free development tools and run the game locally, without required servers or paid runtime services.
- Version control: private GitHub repository https://github.com/jwerdel/Project-Freedom . The project lives outside OneDrive (C:\Users\Owner\dev\project-freedom).
- Engine pinned to Godot 4.7.2 (standard build, not .NET). scripts/get_godot.ps1 downloads and checksum-verifies it into runtime/; the engine binary is not committed. Blender remains an optional art tool and has not been installed.
- No audio in V1.
- Final art target: detailed, realistically proportioned fantasy figures with minimal animation; avoid a blocky Roblox-like appearance. Development reaches this through a later art pass (see Art direction and development order).
- Decision (2026-10-01): no walk cycle for the prototype commander; the campaign figure slides with a subtle bob until it is replaced by a rigged Blender model.
- Campaign army movement matters. No watchable battles or live tactical control in V1.
- Do not impose the previously proposed arbitrary cap of 6–10 units per army. Actual performance budgets and representation remain to be established; the early performance test below is the first measurement.
- Development PC (detected on this machine): AMD Ryzen 7 5700X3D (8 cores / 16 threads), NVIDIA GeForce RTX 4060 8 GB, 32 GB DDR4 (2 × 16 GB Corsair CMK32GX4M2E3200C16, dual channel, 3200 MT/s detected, so XMP is active), 256 GB NVMe SSD. The memory sits in slots the BIOS reports as non-optimal (channel A DIMM 1 + channel B DIMM 0); the boot warning is expected and accepted. A 1 TB NVMe SSD is arriving but not yet installed.

## Art direction and development order

Confirmed:

- Gameplay first on low-poly placeholder art; a realistic, Total War-style art pass comes later. Visual quality is no longer the gate for gameplay work.
- A small early performance test will validate that large armies are feasible: one soldier model duplicated into a large army, measured on the development PC.
- All soldiers may share one placeholder model for now. Unit cards must still visually resemble their unit.
- Art and gameplay data are separate: gameplay values live in data files, each visual is its own scene, and one asset manifest maps IDs to visual scenes, so the art pass swaps visuals without touching gameplay. CLAUDE.md holds the working rules.
- Campaign UI direction: the campaign UI should heavily resemble Total War: Warhammer III's campaign UI: round menu buttons top-left, a resource bar top-center, minimap top-right, event messages on the right, province stats on the left, a bottom-center province panel with settlement tabs and building-slot cards (or the army panel with unit cards when an army is selected), and a large round End Turn button bottom-right. Dark panels with ornate gold-trimmed frames, tinted per faction. Placeholder UI art comes from Kenney's CC0 UI packs.
- Placeholder packs: the Quaternius and Kenney packs listed in ASSETS.md are approved (2026-09-30).
- Two scales:
  - Campaign map scale: stylized miniature scale. Generals and heroes are deliberately oversized relative to settlements for readability. The current prototype's proportions are the reference: the commander figure stands about 4.4 m to the helmet top (banner pole about 5.1 m) on a 1.1 m radius base; houses are about 1.3–2.5 m to the roof ridge; Greyhaven's wall ring has a radius of about 8.7 m with 1.6 m walls; towers are 2.35–5.2 m; roads are 1.0 / 1.3 / 1.6 m wide (dirt / gravel / stone); wagons are about 3.3 m long including the draft animal; ships are about 4 m long with a 3.4 m mast; fir trees are 3.5–6.8 m.
  - World/battle scale: 1 Godot unit = 1 meter, humans about 1.8 m. Applies to deployment and battle scenes and to the source proportions of all character models; campaign-map figures are scaled up from these sources.

Open:

- Target army size and frame-rate threshold for the performance test.

## Campaign and world

- Confirmed (2026-10-01), loss condition: a faction that loses its last settlement enters a grace period of N turns (data). If its armies retake a settlement in time it survives; otherwise it is destroyed and its armies disband. For the player, destruction is game over.
- One campaign turn represents one year.
- Three major landmasses: two relatively close and a third far away. Game of Thrones is a geographic reference, not the desired limit on fantasy.
- Existing cultures, religions, and internal histories at campaign start, but no starting wars, alliances, or diplomatic relationship bonuses.
- Campaign play creates international history. Important events should be recorded in a readable chronicler's log, resembling a maester's account.
- Factions merge, territories and cities change hands, and races can be destroyed; the exact meaning of destruction remains open.

## Peoples and factions

Every race has multiple factions, with all intended factions available for player selection, including potential crisis factions. Consolidating the other factions of the player's race is an early objective; whether optional or mandatory remains open. Routes include conquest, peaceful confederation, dynastic inheritance/marriage, subordination, and removing hostile rulers to install friendly ones. The player decides whether absorbed ruling families enter court, retain lands, or are removed; retained families may seek independence.

Geographic references:

- Western continent: multiple human realms inspired geographically by the Reach, Stormlands, and Westerlands; northern orcs; dwarves in southern mountains in the broadly Dorne-like region; Easterling-inspired people in desert areas.
- Nearby eastern continent: principally elves and beastmen.
- Far eastern portion of that continent: Necron-like and Chaos-like peoples, the intended origin of world-ending threats. How threats coexist with neutrality and playable factions remains open.
- Remote southern continent: ratmen along the coast and lizardmen deep in the jungle.

Lean strongly into fantasy. Each race/faction has massed troops and distinctive monsters, with different access to monsters: beastmen have many, humans relatively few. Environment should influence faction design. Specific cultures, religions, species names, rosters, and maps remain to be developed.

## Faction behavior and diplomacy

- Factions have recognizable tendencies such as passive, income-focused, generous, kind, expansionist, cruel, or treacherous.
- Other factions should account for those tendencies: cruel or treacherous neighbors cause more concern than kind or generous ones, despite neutral starting relationships. How this differs from numerical relationship bonuses must be defined.
- Relationships form a web: an attack harms the victim's relationship strongly and can also harm relations with its allies to a lesser degree.
- Alliances and dynastic marriages can improve relations.
- Negotiations should support bundled offers using a faction's available means, including land, gold, resource tribute, troop transfers, marriage, alliances, and ceasefires. Eligibility and valuation remain open.
- Army tribute means sending actual troops.
- Attacking during a ceasefire/peace treaty or within its protected post-treaty period causes irreversible war with every faction and permanent loss of allies and trade partners; only loading an earlier save reverses it. Cancelling trade is permitted at any time and does not trigger this punishment.
- Confirmed (2026-10-01): after peace or a ceasefire the treaty is protected for 20 turns; attacking during the treaty or that protection triggers the betrayal rule above.
- AI suffers the same betrayal penalty. Confirmed (2026-10-01): the AI never triggers the betrayal rule (hardcoded). Treacherous AI factions show treachery in other ways: breaking trade agreements, abandoning allies, refusing alliance calls.
- Courts may contain multiple races, independently of reproduction. An orc faction rejected by other orcs can join a welcoming human faction. Latest clarification: reproduction is within the same race only; this supersedes the earlier crossbreeding-alliance idea.
- Welcoming an outsider requires sustained commitment to earn trust; exclusion can produce distrust and rebellion. Integration may damage relations with prejudiced same-race friends while creating opportunities for cross-race alliances.
- Some human/orc factions should always hate the other race; a small minority may pursue friendship. This qualifies or conflicts with the earlier universally neutral start: distinguish starting relations, permanent prejudice, and willingness to negotiate before implementation.
- Expelling conquered peoples is an intended player option, described by the user as the easy choice; retaining/integrating them is harder but potentially rewarding. Mechanical consequences, migration destinations, and the meaning of race destruction remain open.

## Economy and settlements

- Confirmed (2026-10-01), debt: a faction may go into debt down to a limit (data). While in debt it cannot start construction or recruit, and its units lose a share of their men to desertion each turn (data). Below the limit, its worst-upkeep units disband.
- Gold is the currency. Income and expenses are calculated per turn; buildings, units, and upgrades cost gold.
- Construction should not require manually managing material inventories. Resources such as stone increase economic potential rather than serving as direct construction requirements.
- Candidate resources: wood, stone, food, and minerals; final categories and any exceptional uses remain open.
- Regional resource endowments differ and should make some places intrinsically richer. A Casterly Rock-like resource center should have unusually high earning potential.
- Cities prioritize economic potential; fortresses prioritize defensibility and have a lower economic ceiling even when developed economically. The user's 50K city / 20K fortress example illustrates the intended tradeoff, not approved balance numbers.
- Markets are dynamic: goods are more valuable where scarce. Selling wood to a desert region should be more lucrative than selling it to an abundant woodland region, all else equal.
- Trade agreements, partners, roads, ships, caravans, buildings, and routes affect how effectively resources generate gold. Equal production need not yield equal income.
- Player decisions concern agreements and infrastructure; detailed trade pricing, transport, and automation rules remain open.
- Establishing outposts and moving armies through the world are core interests. Exact outpost functions remain to be designed.
- Recruitment draws directly from the region's population pool. Disbanded survivors return to population. Military mobilization should have demographic consequences without routinely trapping the player in hopeless situations.
- A populous territory should be capable of raising multiple armies in one turn. A 'raise banners' action gathers population from the player's territories at the capital to form armies; timing, travel, and costs remain open.
- Population and growth respond to resource abundance, developed wealth, and the popularity of the ruler. People can migrate toward regions where a popular ruler is appointed or moves to govern.
- Economic settlement development supports greater population and growth than defensive development. Latest geographic clarification supersedes the earlier four-cities-per-territory example: countries contain territories; each territory can have only one major city or fortress. Other settlements are villages (economic), castles (defensive), or towns (mixed). Governor jurisdiction and outposts remain open.
- Cities and fortresses can be converted into each other. Cities have more building slots, so converting to a fortress requires destroying buildings that will no longer fit. Open (2026-10-01): conversion is confirmed but deferred; it is not part of the first construction system, and its cost, time and rules remain to be designed.
- Confirmed (2026-10-01), construction in the Total War: Warhammer III style: each settlement has a main building whose level is the settlement level and caps every other building's level; upgrading it raises the population cap, opens building slots and moves the settlement to its next visual growth stage. Slot counts depend on settlement type and level (cities most, fortresses fewer, villages fewest). Buildings form chains of 1-3 levels with a gold cost, a construction time in turns (mostly 1-2 years), upkeep and effects. Numbers, the cancel refund rule and the AI construction behavior are placeholders in data/buildings.json.
- Refugees default toward nearby fortresses. Players can admit refugees, gaining population at the cost of public order and income needed to feed them. Precise destination and capacity rules remain open.
- During invasions, displaced people prefer the safety of fortresses over cities. How settlement populations aggregate into the regional recruiting pool remains open.
- Materials affect income and should not directly block buildings or recruitment. Research unlocks buildings, including naval progression. Siege endurance is also intended to depend on settlement resources; how this works without manual inventories remains open.
- Confirmed (2026-10-01): income scales with population through taxes. A settlement's income is a base amount by settlement type and level plus a per-capita tax on its population, both modified by resource endowments, buildings, and the settlement type's income factor and ceiling.
- Confirmed (2026-10-01): buildings have real effects: income, growth, recruitment unlocks, and defense.
- Confirmed (2026-10-01): the research tree is deferred past V1 (see docs/v1-scope.md). In V1, building availability is gated by settlement level, plus geography where a building needs it: confirmed 2026-10-01, ports require a coastal settlement.

## Characters, dynasties, and governing

- Factions have family trees. Family members are heroes with skills, traits, and personalities that evolve through assignments and life events.
- Players choose children's paths; military and political/economic careers should produce different capabilities.
- Events should create intimate knowledge of the family and consequential choices, not merely cosmetic biographies.
- Character behavior responds to experience and personality. Repeated losses can create desperation or jealousy of successful peers and increase willingness to rebel or defect. These are intended possibilities, not mandatory responses to every defeat.
- The court must be managed through appointments and consequential decisions.
- Conquest raises questions about the previous ruler: killed in battle, removed, retained, or integrated through marriage and grants of land.
- People mature and stop aging in their prime. No sickness or old-age deaths; non-immortal characters die only in battle or through assassination.
- The player may replace the faction ruler at any time. A ruler could serve one turn or more than 1,000 turns. Replaced rulers become heroes. This role change is distinct from the still-unresolved level-20 monster ascension mechanics.
- Generals are drawn from the court. Court members can also serve hero roles such as hunters and wizards. Recruited specialists such as wizards may be single-entity units represented by one unit card; they need not literally be monsters.
- The player controls when new children are added to the main family tree. Rules for other families remain open.
- At level 20 a character can become immortal and then ascend into a monster-like unit. An immortal defeated in battle returns after X turns; an assassinated immortal returns after Y turns, with Y substantially longer. Values, recovery location, and ascension details remain open.
- The player controls the faction regardless of its current ruler; faction destruction is the loss condition. The exact test for destruction (last settlement versus remaining armies, for example) remains open.
- A wartime upbringing and battle-hardened childhood are valid player-directed story paths. Exact ages for training, command, and other roles remain open.

## Battles and armies

- Before resolution, players deploy units and assign standing orders such as hold ground, act aggressively, or attempt to flank.
- Battle design (approved direction, 2026-10-01): docs/battle-design.md. Its numbers are placeholders and its open questions (section 13) are not decided until the owner answers them.
- Implementation note (2026-10-01): battles are fought from the campaign with the slot-based deployment screen or quick resolve. TEMPORARY war rule until diplomacy: attacking another faction's army or settlement declares war after a confirmation, and there is no peace yet. Captured settlements are occupied only; sack, raze and expel stay open. A dead or wounded general is replaced by a captain who cannot move the army (placeholder until the character system).
- Resolve the battle through simulation without displaying animated combat in V1.
- Detailed figures with minimal animation can be used in deployment; presentation specifics remain open.
- Deployment and orders must have meaningful consequences. A useful explanation of results has been proposed; report format and simulation mechanics are not yet decided.
- Troops, commanders, and casualties must relate back to the campaign; detailed persistence and replenishment rules remain open.
- Replenishment is automatic in friendly regions and costs payment in enemy territory. It does not deduct regional population, but populous regions replenish faster. This is an explicit accessibility exception to the recruitment population model; replacement costs and disbanding must later be balanced to avoid unlimited population creation.
- Implementation note (2026-10-01), placeholders in data/recruitment.json: recruitment is per settlement (men from that settlement's population, units unlocked by its buildings; every main building unlocks peasant levies), with a minimum population; gold and men are taken when a unit is queued and cancelling refunds both; disbanded men return to the population of the region the army stands in. Replenishment regains a share of each unit's max strength per turn, more in populous friendly regions, and costs gold per man anywhere the faction does not own. Army cap: 20 cards per army including the general, a Total War-style placeholder pending the army performance test (the earlier 6-10 cap stays rejected).
- Open (raised by recruitment): recruitment slots per settlement; global recruitment; disbanding a whole army or its general; who counts as an enemy for replenishment once diplomacy exists (now every region the faction does not own); the maximum number of armies per faction (placeholder 3).
- Ordinary monsters require special buildings. Unique legendary monsters exist in the world and can be recruited only by heroes of extraordinary stature; qualification and recruitment mechanics remain open.
- Wars are centered on the opposing factions. Allies choose whether to join the war or support it through gold, resources, or troop tribute without themselves becoming belligerents. Supporting an ally does not automatically mean joining its war.
- Campaign movement uses a per-turn movement allowance in the Total War style. An army may fight multiple battles while its allowance permits; no separate fixed battle count is intended.
- Implementation note (2026-10-01): the allowance is implemented with placeholder numbers (data/movement.json): points refill each End Turn, terrain changes the cost (forest, hills and passes slower; water and mountains impassable except at passes), multi-turn orders continue automatically, and ending a move in one's own settlement garrisons the army. That roads speed movement, scaling with road level, is a placeholder rule, not a confirmed mechanic.
- Confirmed (2026-10-01): until diplomacy exists, armies may move freely through other factions' territory. Diplomacy will later add trespass penalties and military access agreements.
- Open (raised by army movement, not implemented): zone of control; attrition; movement after battle; naval movement; what happens when an army moves onto a foreign settlement or army (battle is not implemented, so it is blocked).
- Siege endurance depends on the settlement's resources, with an approximate maximum of eight turns proposed by the user. Exact supply model and limit remain to be set.

## Endgame crises

- Use the requested Warhammer III-style overwhelming army invasion as the reference: large hostile forces arrive and must be repelled.
- Crisis-associated factions remain playable. Trigger timing, army origins, player participation, diplomacy overrides, and compatibility with treaty penalties remain open.
- An invasion-focused Chaos-like faction starts far away, defeats minor factions to build strength, and is geared toward invading rather than building a conventional empire. Allies can assist factions facing invasion. Treatment of an alliance with the invading faction remains unanswered.

## Minor factions

- Include weaker minor factions that provide early expansion and consolidation opportunities. The user's intended model is a crowded starting map that consolidates quickly; their example counts are illustrative, not an agreed roster or historical claim about Total War.
- The user wants targets that can be attacked without wider diplomatic repercussions. Exact exceptions to relationship webs, starting neutrality, and protected treaties remain unresolved. Do not assume every minor faction in Total War hates everyone or is consequence-free to attack.
- Whether these minor factions are playable exceptions to the earlier 'all factions playable' requirement remains open.

## Required visual experience and validation

- The 2016 Total War: Warhammer campaign map remains the long-term visual benchmark for the later realistic art pass. It is not a gate for gameplay work, which proceeds on low-poly placeholders. Do not promise equivalence without an actual running demonstration.
- A fully 3D campaign map with visible terrain, growing cities, trade routes, ships, and caravans is required; a text adventure, pixel-art map, or blocky Minecraft/Roblox-like treatment would not satisfy the request.
- Generals and heroes appear as oversized map figures. Zooming in reveals smaller environmental details and moving commerce.
- Road upgrades must change visible road surfaces (user examples: dirt, gravel, cement); settlement upgrades visibly enlarge or change settlements.
- The user authorized building the visual milestone. A small native Godot region now demonstrates terrain, three city stages, three road stages, moving commerce, a prototype armored commander, camera controls, and screenshots. It is an initial visual checkpoint, not evidence that the Total War quality benchmark has been met. Its visuals now sit behind the asset manifest and serve as the campaign-map scale reference.
- Research reference checked: https://totalwarwarhammer.fandom.com/wiki/Endgame_scenario . The user's intended invasion model is the design requirement; do not silently import all current or future Warhammer mechanics.

## Naval access

- The remote southern continent is already inhabited but should not be reachable immediately from the other continents.
- Develop naval capability before crossing the high seas. Only appropriate ship classes can make those crossings; early fishing boats cannot.
- Research unlocks the necessary buildings; appropriate ships follow that development. Materials affect income, not access requirements. Specific research, shipyards, ship classes, and gold costs remain open.
- Starting as a southern faction and its initial access to other continents remain open.

## Post-V1 roadmap

Not V1 scope. Recorded 2026-10-01 so the direction is known; nothing here is built for V1. V1 keeps the current slot-based deployment (lanes × front/back, reserve, general's slot).

1. **Total War-style free deployment** (the first post-V1 item). Units are placed freely on a real 3D battlefield inside the deployment zone.
   - Right-click-drag sets a unit's position, frontage width and facing, with a preview.
   - Whole formations can be grouped and locked, moved with Alt-drag and rotated with Ctrl.
   - Each army's last deployment is remembered.
   - Positions snap to the existing lane model behind the scenes, so the battle simulation and its tuned win rates stay unchanged.
2. **True spatial battle simulation** (a V2 decision). Units get real 2D positions, distances and facing, with geometric flanking, replacing the lane model.
   - All win-rate targets must be re-tuned.
   - It is the natural step toward watchable battles.

## Priority questions for the next discussion

The visual feasibility gate is replaced by the gameplay-first direction above. Next: agree placeholder packs and the army performance test. Later topics: visual prototype scope; minor-faction diplomacy/playability; governor jurisdiction and outposts; recruitment and replenishment balance; raise-banners travel; crisis triggers and treaties; siege resources; research choices; hero roles and ascension.

## Scope discipline

The world vision above is not yet a promise that every race and system ships in V1. The V1 content scope is approved and recorded in docs/v1-scope.md (map, races, factions, settlements, systems, and what is deferred past V1). Development milestones and acceptance criteria remain to be agreed. Keep confirmed requirements separate from suggestions and unresolved mechanics as the constitution evolves.
