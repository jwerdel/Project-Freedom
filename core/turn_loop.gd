extends RefCounted
# End of turn: one turn is one year (constitution). Runs a fixed, deterministic sequence:
#   1. income   2. expenses   3. construction (completions)   4. population growth
#   5. armies: movement points refill, standing orders continue   6. recruitment queues complete
#   7. replenishment   8. sieges and wounded generals   9. calendar + event log (chronicle)
#   2b. debt (desertion, disbanding below the limit)
#   10. the AI phase (core/ai.gd): every AI faction acts in the new year with full movement. Its
#       attacks on a human player wait in state.pending_battles for the player's answer.
#   11. the loss condition (grace periods, destruction; core/realm.gd).
# Randomness is only drawn from generators seeded by the campaign seed and year (chronicle
# wording, AI choices).

const Economy = preload("res://core/economy.gd")
const Chronicle = preload("res://core/chronicle.gd")
const Construction = preload("res://core/construction.gd")
const Movement = preload("res://core/movement.gd")
const Armies = preload("res://core/armies.gd")
const Battles = preload("res://core/battles.gd")
const Ai = preload("res://core/ai.gd")
const Realm = preload("res://core/realm.gd")

# Returns a report: {year (the year that ended), ledgers, growth, completed, moves (army id ->
# points walked), recruited, replenished, sieges, entries, ai (Ai.take_turns report)}.
# opts: ai (false skips the AI phase, for tests of other systems), plus Ai.take_turns options.
static func end_turn(state,opts := {}) -> Dictionary:
 var ended = state.year
 var ledgers = {}
 # 1-2. Income then expenses, for every faction alike.
 for f in state.factions(): ledgers[f] = Economy.faction_ledger(state,f)
 for f in ledgers: state.treasury[f] += ledgers[f].income_total
 for f in ledgers: state.treasury[f] -= ledgers[f].expense_total
 # 2b. Debt: desertion in debt, disbanding below the limit (core/realm.gd).
 var debt = Realm.apply_debt(state)
 # 3. Construction advances one year; finished buildings take effect from here on.
 var completed = Construction.advance(state)
 # 4. Growth (computed from the post-construction state, then applied together).
 var growth = {}
 var ids = state.settlements.keys()
 ids.sort()
 for id in ids: growth[id] = Economy.growth(state,id)
 for id in ids: state.settlements[id].population = maxf(0.0,state.settlements[id].population+growth[id].delta)
 # 5. Armies: a new year's movement allowance; multi-turn orders keep walking.
 var moves = Movement.end_turn(state)
 # 6-7. Recruits join their armies; armies regain men (free at home, paid in foreign lands).
 var recruited = Armies.advance_queues(state)
 var replenished = Armies.replenish(state)
 # 8. Sieges advance (starvation, surrender); wounded generals heal.
 var sieges = Battles.end_turn(state)
 # 9. Calendar and event log.
 state.year += 1
 state.turn += 1
 state.last_ledgers = ledgers
 var rng = RandomNumberGenerator.new()
 rng.seed = hash([state.seed,ended])
 var entries = Chronicle.building_entries(ended,completed,rng)
 entries.append_array(Chronicle.year_entries(state,ended,ledgers,growth,rng))
 state.chronicle.append_array(entries)
 # 10. The AI phase.
 var ai = {"actions":[],"pending":[],"entries":[],"moves":{},"ms":0.0}
 if opts.get("ai",true):
  ai = Ai.take_turns(state,opts)
  state.pending_battles = []
  for pb in ai.pending:
   var p = pb.duplicate(true)
   p.erase("approach") # the attacker has already marched; nothing left to plan
   state.pending_battles.append(p)
  entries.append_array(ai.entries)
 # 11. The loss condition: grace periods start, count down, end (survived or destroyed).
 var realm = Realm.check_survival(state)
 var realm_entries = Realm.entries(state,state.year,debt+realm)
 state.chronicle.append_array(realm_entries)
 entries.append_array(realm_entries)
 return {"year":ended,"ledgers":ledgers,"growth":growth,"completed":completed,"moves":moves,"recruited":recruited,"replenished":replenished,"sieges":sieges,"entries":entries,"ai":ai,"debt":debt,"realm":realm}
