extends RefCounted
# End of turn: one turn is one year (constitution). Runs a fixed, deterministic sequence:
#   1. income   2. expenses   3. population growth   4. calendar + event log (chronicle)
# Randomness is only drawn from a generator seeded by (campaign seed, year), and is used
# only to vary the chronicle's wording.

const Economy = preload("res://core/economy.gd")
const Chronicle = preload("res://core/chronicle.gd")

# Returns a report: {year (the year that ended), ledgers, growth, entries (new chronicle entries)}.
static func end_turn(state) -> Dictionary:
 var ended = state.year
 var ledgers = {}
 # 1-2. Income then expenses, for every faction alike (AI factions only accumulate for now).
 for f in state.factions(): ledgers[f] = Economy.faction_ledger(state,f)
 for f in ledgers: state.treasury[f] += ledgers[f].income_total
 for f in ledgers: state.treasury[f] -= ledgers[f].expense_total
 # 3. Growth (computed from the start-of-year state, then applied together).
 var growth = {}
 var ids = state.settlements.keys()
 ids.sort()
 for id in ids: growth[id] = Economy.growth(state,id)
 for id in ids: state.settlements[id].population = maxf(0.0,state.settlements[id].population+growth[id].delta)
 # 4. Calendar and event log.
 state.year += 1
 state.turn += 1
 state.last_ledgers = ledgers
 var rng = RandomNumberGenerator.new()
 rng.seed = hash([state.seed,ended])
 var entries = Chronicle.year_entries(state,ended,ledgers,growth,rng)
 state.chronicle.append_array(entries)
 return {"year":ended,"ledgers":ledgers,"growth":growth,"entries":entries}
