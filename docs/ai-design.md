# Campaign AI design

Status: design note for the campaign AI block (2026-10-01). Every number is a placeholder in `data/ai.json`. Mechanics the constitution leaves open stay open: diplomacy, peace, relationships, and the betrayal rules.

## 1. Rules the AI follows

- **Same rules as the player.** The AI acts only through the functions the player's UI uses:
  - `Construction.start`
  - `Armies.raise_army` and `Armies.recruit`
  - `Movement.order`
  - `Battles.approach`, `prebattle`, `quick_resolve`, `besiege` and `withdraw`

  So no bonus gold, no free units, no skipping movement costs, upkeep, recruitment limits or the army cap. Battles use the same simulation, seeds and aftermath.
- **War** uses the temporary rule: attacking another faction's army or settlement declares war on it. Wars never end, because peace does not exist yet (section 7).
- **Information:** the AI sees what the player sees. The campaign map has no fog of war: every army and settlement is visible. Pre-battle hidden units (forest, reserve) affect only deployment, and the AI uses the default templates.
- **AI factions fight each other** under the same rules as the player.

## 2. Turn structure

End Turn runs in this order:
1. The yearly processing: income, upkeep, construction, growth, movement refill, standing orders, recruits arriving, replenishment and sieges.
2. The **AI phase**. Each AI faction, in a fixed order (sorted ids), acts with the new year's full movement allowance, just as the player will.
3. The player's turn.

An AI attack on the player becomes a **pending battle**. When the player's turn starts, the pre-battle panel opens with the player as defender (Deploy, Quick Resolve, Withdraw). In headless runs (tests, soak) the player's side answers with the default defender choice (section 5).

Randomness in AI choices (war rolls, tie-breaks) comes only from a generator seeded by (campaign seed, year, faction). Iteration orders are fixed, so a campaign replays exactly from its seed, through saves too.

## 3. How a faction decides each turn

1. **Assess.**
   - Each army has a *power* estimate: the sum over its units of men × unit strength (melee + defence + armour/2 + missile, × rank), times the general's rank factor.
   - A settlement's defence is its automatic garrison, plus garrisoned armies, plus friendly armies within reinforcement range, × a wall factor.
   - *Reach* is straight-line distance up to `reach_meters` (one turn's allowance at average terrain cost). Movement.plan confirms it only for the actions finally chosen.
   - **Threats** are enemy armies within reach of an own settlement, plus wary neighbours' armies (cruel or treacherous factions not yet at war).
   - **Opportunities** are enemy settlements and armies within reach whose defence is low compared with an own army's power.
   - An attacking army counts its own armies within reinforcement range of the target, as the battle will. War and march decisions count the whole field force within `war_meters` × `gather_share`, so separate armies converge on one target.
   - The power ratio screens everything cheaply. The simulation-based odds estimate (`Battles.odds`, with `odds_runs` seeded runs) is used only for an actual attack decision whose ratio sits in the uncertain band, at most `odds_budget` times per faction per turn. Otherwise a logistic curve of the ratio stands in, and war declarations always use the curve.
2. **War.**
   - At war already: opportunities against those enemies are taken on merit.
   - Not at war: the faction may declare war on a weak target. Chance = `war.base_chance` × personality aggression × how weak the target is.
   - "Cruel when crossed" factions declare (or keep) war on anyone who attacked them.
   - Treacherous factions prefer targets already at war with someone else.
   - Kind, generous and passive factions rarely start wars.
3. **Economy.**
   - Posture is *safe* or *threatened* (any settlement where threat power exceeds defence × `threatened_ratio`).
   - Safe: economic buildings and main-building upgrades, weighted by personality (income-focused builds economy more).
   - Threatened: walls and military buildings first.
   - A gold reserve is always kept (personality-scaled), and net income after upkeep must stay at or above `min_net_income`.
4. **Recruitment.**
   - Each faction has a target composition in data: shares of spear, infantry, archers, cavalry and levies. Verrin, "huge levies", is levy-heavy.
   - Each recruit is the available, affordable unit with the largest shortfall against that target, not simply the cheapest.
   - A new army is raised when the faction can afford its general and some units, is under its personality's army target, and stays under the faction cap.
   - A faction with no army, or with hardly any units, digs into its reserve, keeping only `emergency_reserve_share` of it.
   - A rich faction (more than `rich_factor` × its reserve) fills its armies past `field_units`, up to the army cap.
   - **Books:** when next year would end in debt, it disbands its least efficient units, least power per upkeep first. It does this only if disbanding can balance the books; what a negative treasury does is open in the constitution.
   - **Debt and survival** (constitution, confirmed 2026-10-01): in debt the faction cannot build or recruit (the same rule as the player). Landless in its grace period, it puts everything into retaking a settlement: it declares war on the owner of the best reachable settlement without a roll, attacks at worse odds (`grace.boldness`), targets only settlements, and besieges only when the siege would end inside its grace.
5. **Armies** take one job each turn, in priority order:
   1. **Defend:** move into or next to a threatened settlement that can still be saved.
   2. **Attack:** an opportunity with odds ≥ `attack.min_odds` (personality-adjusted). A walled target is **besieged** instead, unless its assault odds reach `attack.assault_min_odds`. It is besieged only when the army could beat the defenders in the open (power ratio without walls at least `siege_ratio`).
   3. **Retreat/garrison:** an army facing a stronger threat it cannot beat moves into its nearest own settlement.
   4. **Stage:** at war with nothing in reach, march on the best enemy target within `war_meters` (power ratio at least `march_ratio`), with a multi-turn order to its approach point. Otherwise move to the own settlement nearest the enemy. The last army at the capital stays.
   5. **Rest:** stay garrisoned to replenish.

   A captain-led army cannot move (same rule as the player) and stays put. A besieging army holds its siege while the siege can still win.
6. **Battles.** Attackers and defenders use their faction's template (existing). When an AI army is attacked in the field, it **withdraws** if its odds are below `defend.withdraw_below` and withdrawal is possible; otherwise it fights. A garrison cannot withdraw. The same choice is the headless default for the player.

## 4. Personality

Faction traits are listed in `data/factions.json` (`traits`, from docs/world.md). Each trait multiplies the base weights in `data/ai.json`:

| Trait | Effect |
|---|---|
| expansionist | aggression ×2, more armies, lower attack threshold |
| cruel | aggression ×1.5, assaults rather than starving, vengeful |
| treacherous | opportunist (targets already at war), wariness of others ×1 |
| cruel_when_crossed | normal aggression, but always answers an attack with war |
| income_focused | bigger gold reserve, economy-first building, fewer armies |
| generous / kind | aggression ×0.3 |
| passive | aggression ×0.2, defensive building, never stages forward |
| defensive | walls early, armies stay home |

Prototype map:
- **House Aurek** (player in normal play): income-focused, cruel when crossed.
- **House Verrin:** generous, income-focused, plus a levy-heavy composition and mediocre generals (existing trait).
- **House Lannet** has no traits in world.md, so it uses neutral defaults.

No faction on this map is expansionist, so AI-started wars will be rare here. Tests set traits to compare personalities.

Wariness of cruel or treacherous neighbours is AI-internal: their armies count as threats even before war. It is *not* a relationship value. How tendencies differ from relationship bonuses stays open in the constitution.

## 5. Player-side defaults (headless)

When the player's faction is AI-controlled (soak test), it uses the same AI. When the player is human but a run is headless, pending battles are answered by the defender choice in section 3.6.

## 6. Performance budget

Target: **under 50 ms for all AI factions per turn** on this map (4 settlements, 3 factions), in the debug build. Costs:
- power estimates are O(armies × settlements)
- Movement.plan (A*) runs only for each army's chosen job (at most `plan_candidates` tries)
- battle odds run only for attack decisions in the uncertain band (`odds_runs` fast simulations, about 3 ms each)
- the battles themselves cost about 5 ms each

The V1 map has about 30 settlements and about 15 factions. Assessment scales with armies × settlements, roughly 40 × 30 = 1,200 cheap checks; plans and odds scale with the number of armies acting. Measured: the per-phase army snapshot and keeping A* blocked cells applied between plans made the cost about linear in armies (VALIDATION.md, "Campaign AI").

## 7. Gaps and open questions

- **No peace.** Wars, once started, last forever. AI wars accumulate until diplomacy exists (V1 basic diplomacy).
- **No relationship web, alliances or treaties**, so the betrayal penalty and "AI never betrays" are moot for now.
- AI armies do not merge or swap units (no merge mechanic exists).
- No naval movement; AI targets only reachable land.
- Sack, raze and expel stay open: captures occupy only, the same as for the player.
