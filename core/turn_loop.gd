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
 var ctx = _begin(state,null)
 var ai = {"actions":[],"pending":[],"entries":[],"moves":{},"ms":0.0,"ran":false}
 if opts.get("ai",true): ai = Ai.take_turns(state,opts)
 return _finish(state,ctx,ai)

# The same End Turn spread over frames (the game, so the map never freezes): the yearly steps and
# the AI phase hand control back to the engine whenever budget_ms of work has been done in a frame.
# Identical results to end_turn (same steps, same order; tests/test_turn_slicing.gd). progress is
# called with (factions done, factions in all) during the AI phase.
static func end_turn_sliced(state,tree: SceneTree,budget_ms := 12.0,progress := Callable(),opts := {}) -> Dictionary:
 var slicer = Slicer.new(tree,budget_ms)
 var ctx = await _begin_sliced(state,slicer)
 var ai = {"actions":[],"pending":[],"entries":[],"moves":{},"ms":0.0,"ran":false}
 if opts.get("ai",true): ai = await Ai.take_turns_sliced(state,opts,slicer,progress)
 var report = _finish(state,ctx,ai)
 slicer.max_chunk_us = maxi(slicer.max_chunk_us,Time.get_ticks_usec()-slicer.start_us)
 report.frames = slicer.frames
 report.max_chunk_ms = slicer.max_chunk_us/1000.0
 return report

# Hands control back to the engine once a frame's work budget is spent.
class Slicer extends RefCounted:
 var tree: SceneTree
 var budget_us := 12000
 var start_us := 0
 var frames := 0
 var max_chunk_us := 0 # the longest stretch of work between two frames
 func _init(t: SceneTree,ms: float):
  tree = t
  budget_us = int(ms*1000.0)
  start_us = Time.get_ticks_usec()
 func over() -> bool:
  return Time.get_ticks_usec()-start_us>=budget_us
 func next_frame():
  max_chunk_us = maxi(max_chunk_us,Time.get_ticks_usec()-start_us)
  await tree.process_frame
  frames += 1
  start_us = Time.get_ticks_usec()

# Steps 1-9 (everything before the AI phase).
static func _begin(state,_unused) -> Dictionary:
 var ended = state.year
 var ledgers = {}
 # 1-2. Income then expenses, for every faction alike.
 for f in state.factions(): ledgers[f] = Economy.faction_ledger(state,f)
 return _begin_rest(state,ended,ledgers)

static func _begin_sliced(state,slicer) -> Dictionary:
 var ended = state.year
 var ledgers = {}
 for f in state.factions():
  ledgers[f] = Economy.faction_ledger(state,f)
  if slicer.over(): await slicer.next_frame()
 return await _begin_rest_sliced(state,ended,ledgers,slicer)

static func _begin_rest(state,ended: int,ledgers: Dictionary) -> Dictionary:
 var ctx = {"ended":ended,"ledgers":ledgers,"growth":{}}
 for k in BEGIN_STAGES: _begin_stage(k,state,ctx)
 return ctx

static func _begin_rest_sliced(state,ended: int,ledgers: Dictionary,slicer) -> Dictionary:
 var ctx = {"ended":ended,"ledgers":ledgers,"growth":{}}
 for k in BEGIN_STAGES:
  if k == 3:
   # Growth is computed settlement by settlement (the largest step on a big map), then applied.
   var ids = state.settlements.keys()
   ids.sort()
   for id in ids:
    ctx.growth[id] = Economy.growth(state,id)
    if slicer.over(): await slicer.next_frame()
  else: _begin_stage(k,state,ctx)
  if slicer.over(): await slicer.next_frame()
 return ctx

# Steps 1-9 as stages (end_turn runs them in a row; end_turn_sliced may give a frame back between).
const BEGIN_STAGES = 9
static func _begin_stage(k: int,state,ctx: Dictionary):
 match k:
  0:
   for f in ctx.ledgers: state.treasury[f] += ctx.ledgers[f].income_total
   for f in ctx.ledgers: state.treasury[f] -= ctx.ledgers[f].expense_total
  1: ctx.debt = Realm.apply_debt(state) # 2b. Debt: desertion in debt, disbanding below the limit (core/realm.gd).
  2: ctx.completed = Construction.advance(state) # 3. Construction advances one year; finished buildings take effect from here on.
  3:
   # 4. Growth (computed from the post-construction state, then applied together).
   var ids = state.settlements.keys()
   ids.sort()
   for id in ids: ctx.growth[id] = Economy.growth(state,id)
  4:
   var ids = state.settlements.keys()
   ids.sort()
   for id in ids: state.settlements[id].population = maxf(0.0,state.settlements[id].population+ctx.growth[id].delta)
  5: ctx.moves = Movement.end_turn(state) # 5. Armies: a new year's movement allowance; multi-turn orders keep walking.
  6:
   # 6-7. Recruits join their armies; armies regain men (free at home, paid in foreign lands).
   ctx.recruited = Armies.advance_queues(state)
   ctx.replenished = Armies.replenish(state)
  7: ctx.sieges = Battles.end_turn(state) # 8. Sieges advance (starvation, surrender); wounded generals heal.
  8:
   # 9. Calendar and event log.
   state.year += 1
   state.turn += 1
   state.last_ledgers = ctx.ledgers
   var rng = RandomNumberGenerator.new()
   rng.seed = hash([state.seed,ctx.ended])
   var entries = Chronicle.building_entries(ctx.ended,ctx.completed,rng)
   entries.append_array(Chronicle.year_entries(state,ctx.ended,ctx.ledgers,ctx.growth,rng))
   state.chronicle.append_array(entries)
   ctx.entries = entries

# Steps 10 (the AI phase's results) and 11 (the loss condition).
static func _finish(state,ctx: Dictionary,ai: Dictionary) -> Dictionary:
 var entries = ctx.entries
 if ai.get("ran",true):
  state.pending_battles = []
  for pb in ai.pending:
   var p = pb.duplicate(true)
   p.erase("approach") # the attacker has already marched; nothing left to plan
   state.pending_battles.append(p)
  entries.append_array(ai.entries)
 # 11. The loss condition: grace periods start, count down, end (survived or destroyed).
 var realm = Realm.check_survival(state)
 var realm_entries = Realm.entries(state,state.year,ctx.debt+realm)
 state.chronicle.append_array(realm_entries)
 entries.append_array(realm_entries)
 return {"year":ctx.ended,"ledgers":ctx.ledgers,"growth":ctx.growth,"completed":ctx.completed,"moves":ctx.moves,"recruited":ctx.recruited,"replenished":ctx.replenished,"sieges":ctx.sieges,"entries":entries,"ai":ai,"debt":ctx.debt,"realm":realm}
