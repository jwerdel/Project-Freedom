# Battle system design

**STATUS: APPROVED (2026-10-01), decisions in section 13. Being implemented; section 13 overrides earlier sections where they differ.** `constitution.md` governs; every number below is a placeholder that will live in data files (`data/battle.json`, `data/units/*.json`).

Constitution rules this design satisfies: the player inspects the battlefield, deploys and gives standing orders before resolution; resolution is a simulation with no animated 3D combat in V1; deployment and orders have visible, explainable consequences; a battle report teaches; troops, casualties and generals flow back into the campaign; an army may fight several battles while its movement allowance lasts; settlement walls and towers count in settlement battles; siege endurance is about 8 turns at most, supply model open.

## 1. Battlefield generation

A battle happens where the defender stands. The field faces the attacker's approach direction (the last segment of its path).

The field is **lanes x 6 bands deep** (3 or 5 lanes, section 2; shown with 3 below), sampled from the baked movement grid (`data/movement_grid.json`) in a window around the battle point: the window is 9-10 grid cells wide (3 cells per lane with 3 lanes, 2 with 5), each band 2 cells deep (about 18 x 12 map meters, scaled up to a notional 300 x 240 m battlefield). Each lane-band takes the majority terrain of its cells:

| Terrain | Effect |
|---|---|
| Open | none |
| Forest | units inside take half missile damage, move at 0.6x, cannot be charged at full charge; hidden from the enemy until they fight |
| Hills | the side holding them gets +10 melee attack and +1 band missile range against units below |
| Road | 1.2x movement along the lane |
| Pass | lane frontage halved (a chokepoint) |
| Mountain / water | lane closed: no units, no flanking past it |
| River (not on the map yet) | fords: crossing units fight at -20 defence for 2 ticks |
| Settlement walls (sieges) | a wall band in front of the defender, gates in lanes with a road; see section 11 |

Bands 1-2 are the attacker's deployment zone, 3-4 no man's land, 5-6 the defender's zone.

```
            Left        Center       Right
 band 6  [ forest ]  [  open  ]  [  open  ]   defender back line
 band 5  [ forest ]  [  road  ]  [  hills ]   defender front line
 band 4  [  open  ]  [  road  ]  [  hills ]   no man's land
 band 3  [  open  ]  [  road  ]  [  open  ]   no man's land
 band 2  [  open  ]  [  road  ]  [  open  ]   attacker front line
 band 1  [  open  ]  [  open  ]  [ water  ]   attacker back line (Right lane closed: water)
```

**Weather** is rolled from the battle seed, light effects only: clear (70%), rain (20%: missiles -30%), fog (10%: missile range -1 band, enemy back line hidden).

**What you see of the enemy:** its units on open ground and hills, with type and strength. Units in forest, in reserve, or in the back line during fog show as an "unknown unit" card. The defender always knows the attacker's composition; the attacker sees the defender's army list but not hidden placements.

## 2. Deployment model

Each side arranges its units on a small grid, not free placement, so choices stay readable and the simulation stays tractable.

```
                 LEFT            CENTER           RIGHT
 FRONT LINE   [ slot ][ slot ] [ slot ][ slot ] [ slot ][ slot ]
 BACK LINE    [ slot ][ slot ] [ slot ][ slot ] [ slot ][ slot ]
 GENERAL                        [  general  ]
 RESERVE      [ any number of units, held behind the center ]
```

- Lane capacity per line (3 lanes): 3 units on open ground, 2 in forest or hills, 1 in a pass, 0 in a closed lane; with 5 lanes, 2, 1, 1 and 0. Up to 20 units per army (the army cap) fit in the slots plus reserve.
- The general sits behind the center by default; it can be placed in any lane's back line.
- Each unit has one order (section 3). Units without one get the default for their type.

**3 lanes or 5?** The lane count is a data value (`lanes` in `data/battle.json`), so both can be tested by the harness (section 12). With 5 lanes (Far left, Left, Center, Right, Far right; each lane 2 grid cells wide, lane capacity 2 per line):

```
              FAR LEFT    LEFT      CENTER     RIGHT    FAR RIGHT
 FRONT LINE   [  ][  ]   [  ][  ]   [  ][  ]   [  ][  ]   [  ][  ]
 BACK LINE    [  ][  ]   [  ][  ]   [  ][  ]   [  ][  ]   [  ][  ]
 GENERAL                           [ general ]
 RESERVE      [ any number of units, held behind the center ]
```

| | 3 lanes | 5 lanes |
|---|---|---|
| Flanking | Flankers leave from a whole wing; "the flank" is a third of the army | Flankers leave from the far lanes; the line (Left, Center, Right) and the flanks are separate decisions |
| Screening a flank | All or nothing per wing | A single unit in a far lane can screen or bait a flank |
| Terrain | Coarse: one forest can fill a whole wing | A forest or hill can cover one far lane, which reads like a real battlefield edge |
| Small armies (3-5 units) | Fill the field naturally | Leave the far lanes empty, so they are easy to outflank: a meaningful weakness of small armies |
| Deployment effort | 18 slots, fast | 20 slots, a little more to arrange; templates and Auto-deploy do it in one click |
| Simulation cost | Lower | Still small (under 2 ms target) |

Recommendation: **5 lanes** (open question 1). With armies of up to 20 units, 3 lanes make flanking and screening too coarse to teach anything: whether a flank attack works should depend on which far lane it comes from and what screens it, not on a whole wing. The rest of this document is written for either count; "the outer lanes" means Left/Right with 3 lanes and Far left/Far right with 5.

**Deployment screen:** a tabletop diorama built from the sampled terrain: flat tiles for open ground, raised tiles for hills, tree props from the manifest (`nature.tree`), wall pieces for sieges, a darker strip for no man's land. Units appear as small blocks of their existing figures (`UnitTypes.build_visual`, a few figures per block) on the slots. Unit cards along the bottom (the existing cards) are dragged onto slots; each placed card shows an order icon. A 2D top-down toggle shows the same grid as colored blocks. The enemy's visible units stand in their zone. Buttons: Auto-deploy, Quick resolve, Fight.

## 3. Orders

| Order | Behavior |
|---|---|
| **Hold** | Stays in its slot and fights what reaches it. Braced: +15 defence against charges; spears holding negate the charge bonus entirely. Never advances, even when winning. |
| **Aggressive** | Advances down its lane at its speed toward the nearest visible enemy in the lane, charging on contact. If its lane is empty it turns on the nearest enemy in an adjacent lane after 2 ticks. Leaves its slot open. |
| **Flank** | Only from the outer lanes. Leaves the field edge and arrives at the enemy's flank after a delay (lane length / speed, x1.5 through forest, impossible past a closed lane). On arrival it attacks the enemy back line in that lane, from behind. |
| **Protect (unit X)** | Stays next to X. Any enemy that engages X, or arrives to flank X, fights the protector first. A protector in front of archers lets them keep shooting. |
| **Reserve** | Off the grid, behind the center. Commits automatically: (a) to intercept an arriving flanker, (b) to fill a lane whose front unit routs, (c) cavalry reserves pursue routing enemies. One commitment per reserve unit. |

**Interactions**

- Flank vs reserves: each enemy reserve unit intercepts one flanker, turning it into a normal frontal fight (no rear bonus, no morale shock). With no reserve left, the flanker hits from behind: +30% attack, the target's defence halved, -20 morale to the target and -10 to its lane neighbours.
- Hold vs aggressive: the aggressive unit charges a braced unit; the bracing usually wins the first clash, then numbers and stats decide.
- Protect vs cavalry: a spear unit protecting archers meets the charge braced; the archers keep firing.
- Aggressive vs aggressive: both charge, both get the charge bonus, the meeting point is where their movement crosses.

**Speed, terrain and the general:** movement is in bands per tick (infantry 0.5, cavalry 1.5), times terrain. The general's rank (1-10) shortens order delays (flankers arrive 1 tick earlier per 3 ranks; reserves commit 1 tick sooner at rank 5+) and gives a morale aura of +2 per rank to units in its lane and the center. Mediocre generals (personality, section 8) add 1 tick to every delay.

**General personality hook** (constitution: character behavior responds to experience and personality). The character system does not exist yet, so no general has traits today, but the simulation reads an optional `traits` list on the general and applies modifiers from a table in `data/battle.json`. Placeholder traits:

| Trait | Effect on order execution |
|---|---|
| Cautious | Aggressive orders start 1 tick late; flankers wait until the enemy reserve has committed; +5 morale to units holding |
| Reckless | +10 charge on the first clash; cavalry pursue routing enemies off the field and stay out for 3 ticks (exposed to counter-charges, unavailable as reserve) |
| Steady | Reserves commit 1 tick sooner; lane neighbours lose 5 less morale when a unit routs |
| Impetuous | Holding units with a winning neighbour may advance without orders (25% per tick) |
| Mediocre | +1 tick to every delay (House Verrin's generals by faction default) |

The report names the trait when it mattered ("Ser Bramwell's caution held his levies back until your cavalry had already turned the flank"). Once the character system exists, traits come from the general's personality and experience instead of faction defaults.

## 4. Unit stats and matchups

New battle stats go into `data/units/*.json` next to the existing placeholder stats:

| Unit | Men | Speed | Melee atk / def | Charge | Armour | AP | Missile (dmg / range / volleys) | Shield | Morale | Bonus |
|---|---|---|---|---|---|---|---|---|---|---|
| Peasant Levy | 160 | 0.5 | 18 / 14 | 6 | 10 | 0.1 | none | 0 | 30 | none |
| Spearmen | 120 | 0.5 | 26 / 34 | 8 | 35 | 0.1 | none | 0.3 | 50 | +20 vs cavalry, brace |
| Swordsmen | 120 | 0.5 | 34 / 28 | 10 | 40 | 0.3 | none | 0.3 | 55 | none |
| Heavy Infantry | 90 | 0.4 | 40 / 36 | 12 | 75 | 0.4 | none | 0.2 | 70 | none |
| Archers | 100 | 0.5 | 16 / 12 | 4 | 15 | 0.1 | 10 / 2 bands / 8 | 0 | 40 | none |
| Cavalry | 60 | 1.5 | 36 / 22 | 40 | 40 | 0.2 | none | 0.2 | 55 | mass: heavy |
| General | 1 (20 hp) | 1.5 | 50 / 45 | 30 | 80 | 0.5 | none | 0.3 | 90 | morale aura |

- **Spears vs cavalry:** braced spears cancel the charge and add +20 attack against cavalry.
- **Cavalry vs archers:** archers have little defence and morale; an unprotected archer unit reached by cavalry usually routs within 2-3 ticks.
- **Archers vs armour:** missile kills are multiplied by (1 - armour x (1 - AP) / 100) and by (1 - shield) from the front; heavy infantry takes about a quarter of what levies take.
- **Levies:** cheap mass that holds a line briefly but routs early.

## 5. Simulation

A deterministic, seeded, tick-based model. The seed is hash(campaign seed, year, battle index); the same inputs always give the same battle and the same report. At most 30 ticks. Each tick runs these phases in a fixed order (side, lane, line, slot):

1. **Missiles:** units with ammunition fire at the nearest visible enemy in range (own lane first, then adjacent). Kills = men x 0.04 x missile damage x accuracy (0.6, x weather) x armour factor x (1 - shield if frontal) x forest cover.
2. **Movement:** aggressive units advance; flankers count down their delay; reserves commit if triggered.
3. **Flank arrival:** arriving flankers are intercepted by a reserve or hit their target from behind.
4. **Melee:** each engaged pair exchanges blows. Fighting men = min(men, frontage), frontage 60 per lane slot (30 in a pass). Hit chance = clamp(0.35 + (attack - defence) / 100, 0.08, 0.9). Kills = fighting men x hit chance x 0.08 x armour factor. On the first tick of contact the charger adds its charge to attack (cancelled by braced spears, -50% in forest). Rear and flank modifiers from section 3.
5. **Morale:** each unit starts at its morale plus the general's aura. Per tick: -1.5 per 1% of men lost this tick, -20 when hit from behind, -10 when a lane neighbour routs, -15 if the general dies, +5 when its opponent is losing more men. Below 25 a unit wavers (-20% attack); at 0 it routs.
6. **Rout and pursuit:** routed units leave the fight and are pursued by the nearest unengaged enemy: infantry kill 3% of the router's men per tick, cavalry 8%. A unit that loses 90% of its men is destroyed.

Every exchange gets seeded noise of +/-15%, so equal fights vary but deployment, not luck, decides lopsided ones. The battle ends when one side has no unrouted units (that side loses), or at tick 30 (the defender holds, a draw for campaign purposes).

**Why deployment decisions change the result**

| Decision | Mechanism |
|---|---|
| Archers behind infantry | The front unit absorbs melee; the archers keep firing every tick; left in front, they get caught and rout early. |
| Holding a chokepoint | A pass halves frontage, so a larger army cannot bring its numbers to bear; closed lanes remove flanking routes. |
| Cavalry in reserve | It intercepts enemy flankers, plugs a broken lane, and runs down routing enemies (pursuit casualties). |
| Flanking an enemy with no reserve | The flanker arrives unopposed and hits from behind: halved defence plus morale shock to the target and its neighbours, often a chain rout. |
| Spears holding in front of cavalry | Braced spears negate the charge, so the cavalry's main strength is wasted. |
| Aggressive levies | They reach the enemy first and are the first to break; that rout costs their neighbours morale. |

## 6. Battle report

The simulation writes an event log with cause tags. The report must be scannable in under a minute, so it reads top to bottom from short to detailed:

1. **Headline:** outcome and cost in one line ("Victory at Greyhaven: 214 of your men lost, 610 enemy").
2. **Why you won / why you lost:** 3 to 5 lines, each a cause and its effect, ranked by how many casualties or morale points the cause decided. Built from the same cause tags as the timeline. Example of a defeat:
   - Your archers stood in the front line; enemy cavalry reached them on tick 4 and they broke.
   - You had no reserve, so nothing stopped their flank attack on your right.
   - Your spearmen held the center well (lost 18%), but were cut off once the right collapsed.
   - Lesson: put missile troops behind infantry and keep one unit in reserve.
3. **Key numbers:** men lost and killed per side, units destroyed, battle length.
4. **Full timeline** (collapsed by default, for players who want detail):

- **Decisive moments**, 3 to 8 plain sentences in time order, built from the tags, for example:
  - "Tick 6: Your left flank cavalry hit the enemy archers from behind because they had no reserve."
  - "Tick 9: The Highbloom Levy broke in the center after losing 40% of its men to your archers; its neighbours wavered."
  - "Your spearmen held the pass: the enemy could fight with only half its men at a time."
  - Defeats name the cause: "Your archers were in the front line and were caught by cavalry in the second minute."
- **Per-unit table:** unit, men at start, losses, kills, outcome (held, won, routed, destroyed), experience gained.
- **Replay:** a top-down 2D view of the lane grid with colored unit blocks (faction colors, size by men) at each tick, arrows for charges and flank routes, a scrubber and play button, phase labels, and markers on decisive ticks. It is drawn in the UI from the recorded tick positions; no 3D combat.
- **Chronicle:** one Grey Scribes entry per battle ("In the year 3 the Host of Goldspire met the Silverfall Guard at Greyhaven...").

## 7. Quick resolve

"Quick resolve" skips deployment: your army uses your faction's default template and per-type default orders (section 8), the same simulation runs, and the report appears. Before choosing, both buttons show an estimated outcome from 50 seeded runs of the default deployment ("Likely victory, about 70%"), which costs under 0.1 s.

## 8. AI deployment and orders

The AI picks a template, fills slots by unit type, and assigns orders:

| Template | Layout |
|---|---|
| Line | Infantry front in all open lanes (hold), archers behind (protected), cavalry on one flank (flank), one unit in reserve |
| Shield wall | Spears hold the front, everything else behind; cavalry in reserve; no flanking |
| Hammer and anvil | Center holds; cavalry from both edges flank; archers in the center back line |
| Levy swarm | Levies aggressive in every lane; better units behind and in reserve |
| Hold the walls | Settlement defense: missile units on the wall, infantry at the gates, cavalry in reserve |

Choice comes from faction personality (a `battle_style` field in `data/factions.json`, from `docs/world.md`) and army makeup:

- House Aurek (income-focused, cruel when crossed): Line; Hammer and anvil when it has more cavalry.
- House Verrin (huge levies, mediocre generals): Levy swarm when levies outnumber everything else, otherwise Line; mediocre generals add 1 tick to every delay.
- House Lannet (minor house, no traits recorded): Shield wall.
- Expansionist factions (e.g. House Durran): Hammer and anvil. Treacherous factions: more flanking.
- Defenders in a settlement always use Hold the walls.

## 9. Aftermath

- **Casualties:** each unit's `men` drops by its losses. Destroyed units (90% lost) are removed. An army with no units left is removed; its general's fate is rolled (below).
- **Retreat:** the loser, if it still has units, retreats up to 15 map meters away from the winner toward its nearest own settlement, spending no points. If no path exists (cornered, coast, foreign walls), its routed units are destroyed and the rest take 20% extra losses.
- **Winner:** stays on the field. If it attacked a settlement and won, it **occupies** it: ownership changes, buildings and population stay, construction in progress is cancelled. Sack, raze and expel are open.
- **Experience and ranks:** units gain XP from kills and from surviving; ranks 0-9 (the chevrons already drawn on cards), each rank +2 melee attack, +2 defence, +3 morale. Generals gain XP per battle fought and won.
- **General wounded or killed (placeholder, flagged):** if the general's unit fights and the army loses, 10% killed, 20% wounded (fights at half strength for 3 turns). A killed general is replaced by an unnamed captain (rank 1) until the character and family system exists.
- **Movement cost:** attacking costs 25% of the attacker's maximum movement points. The constitution allows several battles per turn while points remain; the defender pays nothing. Replenishment then works as today.

## 10. War status (temporary rule)

Diplomacy does not exist yet. Proposed temporary rule, clearly flagged: **ordering an attack on another faction's army or settlement asks for confirmation ("This means war with House Lannet") and then puts the two factions at war.** War is stored in the campaign state, posted to Event Messages ("War Declared", the category already exists) and to the chronicle. While at war, moving onto the enemy's army or settlement starts a battle instead of the current "Battles not implemented yet" block. Peace is not possible until diplomacy exists. AI armies still do not move, so the AI only defends. No treaty betrayal penalties apply, since no treaties exist.

## 11. Sieges

Moving onto an enemy settlement whose stored `defense` is 10 or more offers **Assault** or **Besiege**:

- **Assault:** a battle with a wall band between bands 4 and 5. Attackers lose 2 ticks crossing it and fight at -20 attack while on it; defenders on the wall get +20 defence. Gates are in road lanes: attackers there need 3 ticks to break through, then fight normally. Towers fire every tick: damage = settlement defense x 0.5, split over attackers in range. Without walls (defense under 10), it is a field battle at the settlement edge.
- **Garrison:** settlements get automatic garrison units by main building level and walls (placeholder, e.g. 2 levies + 1 spearmen per level), fighting alongside any garrisoned army. Open question below.
- **Besiege:** the army stays adjacent and spends its turn. The settlement gets an endurance in turns = 2 + food endowment + granary or farm level + 1 if population is over 5,000, capped at 8 (constitution). Each turn of siege lowers the wall bonus by 15%. When endurance runs out, the garrison loses 10% of its men per turn until it surrenders (the attacker occupies it) or sallies (a normal battle). Lifting the siege resets endurance.
- **Open:** the real supply model, relief armies, sallies by choice, siege engines, naval blockades, and the post-capture options.

## 12. Validation plan

A Monte Carlo harness (a headless script plus a smaller GUT test subset) runs N seeded battles per scenario (500 for the report, 100 in GUT) and prints win rates, average casualties and average battle length. Both sides use equal-cost armies unless stated.

| # | Scenario | Target |
|---|---|---|
| 1 | Mirror: same army, same deployment | each side 45-55% |
| 2 | Good deployment (archers protected, cavalry in reserve, spears hold) vs bad (archers in front, cavalry aggressive into spears) | good side 75-92% |
| 3 | Braced spears vs a frontal cavalry charge | spears 80-95% |
| 4 | Cavalry vs unprotected archers | cavalry 85-97% |
| 5 | Flanking an enemy with no reserve (meeting engagement: both lines advance) | flanker 70-90%; with a reserve, 40-60% |
| 6 | 1:2 outnumbered, holding a pass vs open ground | holding the pass 50-95%; in the open 15% or less |
| 7 | Archers against heavy infantry vs against levies | at most half the kill rate |
| 8 | Wall assault, equal armies | defender 75-92%; after 4 siege turns, 60% or less |
| 9 | General rank 5 vs rank 1 | rank 5 wins 55-65% (matters but does not decide) |
| 10 | More men, same everything else | win rate rises monotonically |
| 11 | Same seed twice | identical result, report text and replay |
| 12 | Speed | under 10 ms per battle in the debug editor build; re-measure against under 2 ms once a release build exists |
| 13 | Scenarios 2-6 with 3 lanes and with 5 lanes | targets apply to 5 lanes (the configured count); the 3-lane row is informational; 5 lanes shows a larger gap between a screened and an unscreened flank |

Upper bounds (owner, 2026-10-01): no tactical choice is a guaranteed win; good decisions are rewarded clearly but some risk always remains. The pass bound is 50-95% (owner, 2026-10-01): chokepoint defense is intentionally strong; attackers counter it by flanking routes, besieging, or overwhelming numbers. (The archer strength that good-vs-bad deployment and cavalry-vs-archers need also makes the archer behind a braced spear in a pass decisive.)

If a target fails, the fix goes into the numbers in data, not into special cases in code.

## 13. Decisions (owner, 2026-10-01)

These answers are confirmed and override earlier sections where they differ. Every number stays a placeholder in data.

1. **Lanes: 5** (far left, left, center, right, far right). The lane count stays a data value for the harness.
2. **War rule:** attacking another faction's army or settlement declares war after a confirmation; no peace until diplomacy exists. Flagged temporary.
3. **Automatic settlement garrisons:** yes, scaled by main building level and walls (placeholder data).
4. **Generals:** a general can be wounded (out for N turns) or killed. Death is unlikely normally and likelier when the army is routed or destroyed. When the general is dead or wounded, a **captain** takes command: the captain fights but **cannot move the army**. The army moves again when a new general is appointed (general fee), when the wounded general returns, or when the captain **wins an important or big battle and is promoted to general**. Flagged placeholder until the character and family system exists.
5. **Retreat:** the loser retreats toward its nearest own settlement with a reduced movement allowance; it is destroyed if no path exists. Defenders may also **withdraw before battle** at a casualty cost (Total War style, placeholder).
6. **Weather:** seeded, light effects only: rain weakens missiles, fog limits visibility (missile range and hidden back lines). Wind is dropped.
7. **Capture:** occupy only; sack, raze and expel stay open.
8. **Experience:** units gain experience from kills and survival; ranks give small stat bonuses; generals gain ranks too.
9. **Movement cost:** attacking costs a fixed share of the attacker's movement points; the army may fight again if points remain.
10. **AI armies stay static** until the AI block (the AI only defends).
11. **Reinforcements, basic:** friendly armies within a radius join the battle, arriving in reserve or a few ticks late depending on distance.
12. **Hidden units:** forest, reserve and fog, as designed.
13. **Win odds:** shown as a Total War-style balance-of-power bar before battle (from seeded simulation runs).
14. **The general** is a single elite fighter with a morale aura; its death or flight shocks its army's morale.

## 14. Rules added while implementing (approved by the owner, 2026-10-01)

Tuning against the harness showed gaps that numbers alone could not close. These general rules (no scenario-specific code) are now part of the design and override earlier sections where they differ:

1. **Army break:** a side breaks (everyone left routs, reserves and flankers leave) when it has lost `army_break_fraction` of its starting men to death or rout, or when no melee unit is left (missile troops alone cannot hold the field).
2. **Shared frontage:** attackers on one target share that target's frontage (front and rear counted separately), so piling units onto one enemy has diminishing returns.
3. **Line depth:** an idle holding melee unit joins a fight against an enemy already in contact in its lane. Missile troops keep shooting instead.
4. **Archers:** missile units with an advance order move only until an enemy is in range, then stand and shoot; they never charge. They never shoot into a melee they are part of, and shoot into other melees at `engaged_target_factor` of normal effect.
5. **Flank resolution order:** an uncommitted reserve rides out and meets an arriving flanker in its outer lane (cavalry meeting cavalry: both charge). Otherwise an idle unit in that outer lane, in its own half of the field, screens it (units already in melee cannot screen). Otherwise the flanker hits the nearest enemy lane from the outside in, back line first. A flanker that has arrived, and a reserve that has intercepted, keep attacking.
6. **Turning to face:** before a rear hit lands, the target turns to face with chance `turn_face.base + morale x per_morale + general rank x per_general_rank` (capped at `max`). Then it is a frontal fight with no rear bonus and no morale shock. Morale and the general's rank raise the chance.
7. **Braced spears** cut `brace_charge_reduction` of an incoming charge instead of cancelling it.
8. **Passes:** units waiting behind a unit fighting in a pass (idle melee units of its side in that lane, plus the reserve when the pass is the only open lane) add `pass_support_fraction` of their fighting men to that fight.
9. **Reserves and pursuit:** cavalry reserves ride down routing enemies, but not while enemy flankers are still on their way.
10. **Fortunes of the day:** each unit's starting morale varies by up to `start_morale_noise` (seeded), so small edges do not become certainties.
11. **Weather** (decision 6): clear, rain (missiles weaker), fog (missile range and hidden back lines); wind removed.

## 15. Tuned numbers (Phase A, 2026-10-01)

Tuned against the harness with 500 seeded battles per case; further balance comes from playtesting, not the harness (owner, 2026-10-01). Changes from the numbers in sections 4-5 and 11 (all in `data/battle.json` and `data/units/*.json`):

| Value | Design | Tuned |
|---|---|---|
| Melee kill rate | 0.08 | 0.4 |
| Missile rate | 0.04 | 0.03 |
| Archer range | 2 bands | 4 bands |
| Shooting into others' melee (new) | - | 10% of normal |
| General aura per rank / lanes reached | 2 / 1 | 0.4 / 2 |
| Starting morale variation (new) | - | ±37% |
| Army break share (new) | - | 46% of men |
| Braced spears' charge cut (was: cancel) | 100% | 57% |
| Turn to face a flanker (new) | - | 0.48 + 0.002 x morale + 0.02 x general rank, max 0.6 |
| Pass support (new) | - | 56% of waiting men |
| Flank route length | 5 bands | 8.5 bands |
| Wall defence bonus / attack penalty | 20 / 20 | 14 / 14 |
| Tower damage per defense point | 0.5 | 0.38 |
| Wall bonus lost per siege turn | 15% | 23% |
| Cavalry melee attack / defence / charge / armour | 36 / 22 / 40 / 40 | 48 / 28 / 50 / 52 |
| Weather | clear 60, rain 20, fog 10, wind 10 | clear 70, rain 20, fog 10 (decision 6) |

Final harness (5 lanes, 500 battles per case): see VALIDATION.md. The mirror can read up to about 55.5% at this sample size; that is noise (owner, 2026-10-01).

## Implementation phases after approval

1. Battle data (`data/battle.json`, new unit stats), the simulation as pure functions, and the Monte Carlo harness; tune numbers until section 12 passes.
2. Campaign hookups: war status, triggering battles from movement, aftermath, sieges and garrisons, AI deployment.
3. UI: deployment diorama, orders, quick resolve with odds, battle report and 2D replay.
