extends RefCounted
# End of turn: one turn is one year (constitution). Runs a fixed, deterministic sequence:
#   1. income   2. expenses   3. construction (completions)   4. population growth
#   5. placeholder AI construction   6. armies: movement points refill, standing orders continue
#   7. recruitment queues complete   8. replenishment
#   9. calendar + event log (chronicle)
# Randomness is only drawn from a generator seeded by (campaign seed, year), and is used
# only to vary the chronicle's wording.

const Economy = preload("res://core/economy.gd")
const Chronicle = preload("res://core/chronicle.gd")
const Construction = preload("res://core/construction.gd")
const Movement = preload("res://core/movement.gd")
const Armies = preload("res://core/armies.gd")

# Returns a report: {year (the year that ended), ledgers, growth, completed, ai_started, moves (army id -> points walked), recruited, replenished, entries}.
static func end_turn(state) -> Dictionary:
 var ended = state.year
 var ledgers = {}
 # 1-2. Income then expenses, for every faction alike.
 for f in state.factions(): ledgers[f] = Economy.faction_ledger(state,f)
 for f in ledgers: state.treasury[f] += ledgers[f].income_total
 for f in ledgers: state.treasury[f] -= ledgers[f].expense_total
 # 3. Construction advances one year; finished buildings take effect from here on.
 var completed = Construction.advance(state)
 # 4. Growth (computed from the post-construction state, then applied together).
 var growth = {}
 var ids = state.settlements.keys()
 ids.sort()
 for id in ids: growth[id] = Economy.growth(state,id)
 for id in ids: state.settlements[id].population = maxf(0.0,state.settlements[id].population+growth[id].delta)
 # 5. PLACEHOLDER AI: non-player factions spend surplus gold on construction.
 var ai_started = []
 for f in state.factions():
  if f != state.player_faction: ai_started.append_array(Construction.ai_turn(state,f))
 # 6. Armies: a new year's movement allowance; multi-turn orders keep walking.
 var moves = Movement.end_turn(state)
 # 7-8. Recruits join their armies; armies regain men (free at home, paid in foreign lands).
 var recruited = Armies.advance_queues(state)
 var replenished = Armies.replenish(state)
 # 9. Calendar and event log.
 state.year += 1
 state.turn += 1
 state.last_ledgers = ledgers
 var rng = RandomNumberGenerator.new()
 rng.seed = hash([state.seed,ended])
 var entries = Chronicle.building_entries(ended,completed,rng)
 entries.append_array(Chronicle.year_entries(state,ended,ledgers,growth,rng))
 state.chronicle.append_array(entries)
 return {"year":ended,"ledgers":ledgers,"growth":growth,"completed":completed,"ai_started":ai_started,"moves":moves,"recruited":recruited,"replenished":replenished,"entries":entries}
