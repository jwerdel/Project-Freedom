extends RefCounted
# End of turn: one turn is one year (constitution). Runs a fixed, deterministic sequence:
#   1. income   2. expenses   3. construction (completions)   4. population growth
#   5. armies: movement points refill, standing orders continue   6. recruitment queues complete
#   7. replenishment   8. sieges and wounded generals   8b. land conversion (core/land.gd)
#   9. calendar + event log (chronicle)
#   2b. debt (desertion, disbanding below the limit)
#   10. the AI phase (core/ai.gd): every AI faction acts in the new year with full movement. Its
#       attacks on a human player wait in state.pending_battles for the player's answer.
#   11. the loss condition (grace periods, destruction; core/realm.gd).
#   12. generals with auto-allocation on (all AI generals) spend their skill points (core/characters.gd).
#   9b. the realm (Part 4): courts age and grow (core/court.gd), envoys arrive and treaties expire
#       (core/diplomacy.gd), vassals pay tribute and their loyalty moves (core/vassals.gd), levies set
#       out and Hosts follow their leaders (core/hosts.gd), titles change hands (core/titles.gd).
#   10b. the AI's court, diplomacy, vassal and banner layer (core/ai_realm.gd).
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
const Land = preload("res://core/land.gd")
const Characters = preload("res://core/characters.gd")
const Court = preload("res://core/court.gd")
const Diplomacy = preload("res://core/diplomacy.gd")
const Vassals = preload("res://core/vassals.gd")
const Hosts = preload("res://core/hosts.gd")
const Titles = preload("res://core/titles.gd")
const AiRealm = preload("res://core/ai_realm.gd")
const Resources = preload("res://core/resources.gd")
const Supply = preload("res://core/supply.gd")
const Seasons = preload("res://core/seasons.gd")
const Markets = preload("res://core/markets.gd")

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
 slicer.at = "finish"
 slicer.note_chunk()
 report.frames = slicer.frames
 report.max_chunk_ms = slicer.max_chunk_us/1000.0
 report.max_chunk_at = slicer.max_chunk_at
 return report

# Hands control back to the engine once a frame's work budget is spent.
class Slicer extends RefCounted:
 var tree: SceneTree
 var budget_us := 12000
 var start_us := 0
 var frames := 0
 var max_chunk_us := 0 # the longest stretch of work between two frames
 var at := "" # what is running (set by the steps; names the longest chunk in reports)
 var max_chunk_at := ""
 var _chunk_from := ""
 func _init(t: SceneTree,ms: float):
  tree = t
  budget_us = int(ms*1000.0)
  start_us = Time.get_ticks_usec()
 func over() -> bool:
  return Time.get_ticks_usec()-start_us>=budget_us
 func next_frame():
  note_chunk()
  await tree.process_frame
  frames += 1
  start_us = Time.get_ticks_usec()
  _chunk_from = at
 func note_chunk():
  var us = Time.get_ticks_usec()-start_us
  if us>max_chunk_us:
   max_chunk_us = us
   max_chunk_at = at if _chunk_from == at else "%s .. %s" % [_chunk_from,at]

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
 slicer.at = "ledgers"
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
  slicer.at = "stage %d" % k
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
const BEGIN_STAGES = 11
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
   for id in ids:
    # A starving realm does not grow (core/resources.gd; it shrinks from the second hungry turn).
    var delta = float(ctx.growth[id].delta)
    if Resources.starving(state,str(state.settlements[id].owner)): delta = minf(delta,0.0)
    state.settlements[id].population = maxf(0.0,state.settlements[id].population+delta)
   # 4b. Food, wood and stone: production in, consumption out; famine (Part B).
   ctx.resources = Resources.end_turn(state)
  5: ctx.moves = Movement.end_turn(state) # 5. Armies: a new year's movement allowance; multi-turn orders keep walking.
  6:
   # 6-7. Recruits join their armies; armies regain men (free at home, paid in foreign lands).
   ctx.recruited = Armies.advance_queues(state)
   ctx.replenished = Armies.replenish(state)
  7:
   ctx.sieges = Battles.end_turn(state) # 8. Sieges advance (starvation, surrender); wounded generals heal.
   ctx.supply = Supply.end_turn(state) # 8b. Army supply drains and refills; raiders plunder (Part B).
  8: ctx.land = Land.end_turn(state,ctx.completed) # 8b. The land turns toward its owners' cultures (core/land.gd).
  9:
   # 9. Calendar and event log.
   state.year += 1
   state.turn += 1
   ctx.seasons = Seasons.end_turn(state) # 9a. Forecasts and the change of seasons (Part B).
   state.last_ledgers = ctx.ledgers
   var rng = RandomNumberGenerator.new()
   rng.seed = hash([state.seed,ctx.ended])
   var entries = Chronicle.building_entries(ctx.ended,ctx.completed,rng)
   entries.append_array(Chronicle.year_entries(state,ctx.ended,ctx.ledgers,ctx.growth,rng))
   state.chronicle.append_array(entries)
   ctx.entries = entries
  10: ctx.realm = realm_year(state,ctx)

# Steps 10 (the AI phase's results) and 11 (the loss condition).
static func _finish(state,ctx: Dictionary,ai: Dictionary) -> Dictionary:
 var entries = ctx.entries
 # 10b. The AI's court, diplomacy, vassals and banners.
 if ai.get("ran",true): ai.realm = AiRealm.take_turns(state,state.factions())
 if ai.get("ran",true):
  state.pending_battles = []
  for pb in ai.pending:
   var p = pb.duplicate(true)
   p.erase("approach") # the attacker has already marched; nothing left to plan
   state.pending_battles.append(p)
  entries.append_array(ai.entries)
  # Marriages between other houses: world news for this turn (owner spec 2026-10-07).
  var WorldMap = load("res://core/world_map.gd")
  for a in ai.realm.get("actions",[]):
   if str(a.action) != "marriage" or str(a.get("with","")) == "" or state.player_faction in [str(a.faction),str(a.with)]: continue
   var e = Chronicle.entry(ctx.ended,"world","A marriage of houses","%s and %s are joined by marriage." % [WorldMap.faction(a.faction).name,WorldMap.faction(a.with).name],str(a.faction))
   e.with = str(a.with)
   state.chronicle.append(e)
   entries.append(e)
 # 10c. Markets (Part B): AI factions cover shortages and stockpile food before winter.
 ai.market = []
 if ai.get("ran",true):
  for f in state.factions():
   if f == state.player_faction or state.settlements_of(f).is_empty(): continue
   ai.market.append_array(Markets.ai_turn(state,f))
 # Part B news for the player: famine, the seasons, supply and plunder.
 entries.append_array(_economy_news(state,ctx))
 # 11. The loss condition: grace periods start, count down, end (survived or destroyed).
 var realm = Realm.check_survival(state)
 # 12. Skill points (placeholder skills, no effects yet).
 Characters.auto_allocate_all(state)
 var realm_entries = Realm.entries(state,state.year,ctx.debt+realm)
 state.chronicle.append_array(realm_entries)
 entries.append_array(realm_entries)
 return {"year":ctx.ended,"ledgers":ctx.ledgers,"growth":ctx.growth,"completed":ctx.completed,"moves":ctx.moves,"recruited":ctx.recruited,"replenished":ctx.replenished,"sieges":ctx.sieges,"land":ctx.land,"entries":entries,"ai":ai,"debt":ctx.debt,"realm":realm,"court":ctx.realm,"resources":ctx.get("resources",[]),"supply":ctx.get("supply",[]),"seasons":ctx.get("seasons",[])}

# 9b. The realm's yearly processing; notable events for the player go to the chronicle ("court").
static func realm_year(state,ctx: Dictionary) -> Dictionary:
 var out = {"court":Court.end_turn(state),"diplomacy":Diplomacy.end_turn(state),"vassals":Vassals.end_turn(state),"hosts":Hosts.end_turn(state),"titles":Titles.end_turn(state)}
 var me = state.player_faction
 var year = ctx.ended
 var WorldMap = load("res://core/world_map.gd")
 var news = []
 for e in out.court:
  if e.faction == me and e.kind in ["birth","courtier","career","returned"]: news.append(Chronicle.entry(year,"court",{"birth":"A child is born","courtier":"A courtier asks to join","career":"A path to choose","returned":"Returned"}[e.kind],e.text,me))
 for e in out.vassals:
  if e.liege == me: news.append(Chronicle.entry(year,"court","Your vassal" if e.kind != "warning" else "A vassal wavers",e.text,me))
 for e in out.titles:
  var t = Titles.data().titles[e.title].name
  news.append(Chronicle.entry(year,"world","%s %s" % [t,"claimed" if e.kind == "earned" else "lost"],"%s %s the title %s." % [WorldMap.faction(e.faction).name,"claims" if e.kind == "earned" else "loses",t]))
 for r in out.diplomacy.envoys:
  if r.from == me: news.append(Chronicle.entry(year,"court","Your envoy arrives","Your envoy reached %s: %s." % [WorldMap.faction(r.to).name,"they accept" if r.ok else ("they refuse (%s)" % r.reason if r.reason != "" else "they refuse")],me))
 state.chronicle.append_array(news)
 ctx.entries.append_array(news)
 return out

# Part B events for the player's chronicle and Event Messages: famine, forecasts and the change of
# seasons (everyone's news), supply running out and plunder (the player's armies or land).
static func _economy_news(state,ctx: Dictionary) -> Array:
 var me = state.player_faction
 var year = int(ctx.ended)
 var WorldMap = load("res://core/world_map.gd")
 var out = []
 for e in ctx.get("resources",[]):
  if e.faction == me: out.append(Chronicle.entry(year,"court","Famine" if e.kind == "famine" else "The famine ends",e.text,me))
 var culture = str(WorldMap.faction(me).get("culture","")) if me != "" else ""
 for e in ctx.get("seasons",[]):
  var title = {"forecast":"Winter is coming","winter":"Winter","summer":"Summer"}.get(e.kind,"")
  var text = str(e.text)
  if e.kind == "forecast": text = "%s warn: %s" % [Seasons.seers(culture).capitalize(),text]
  var c = Chronicle.entry(year,"court",title+(": a long winter" if e.long and e.kind != "summer" else ""),text,me)
  c.season = e.kind
  out.append(c)
 for e in ctx.get("supply",[]):
  if e.kind == "starving" and e.faction == me and state.army_state.has(e.army): out.append(Chronicle.entry(year,"war","No supply","%s lost %d men: its supply is gone." % [state.army_state[e.army].display_name,int(e.men)],me))
  if e.kind == "plunder" and (e.faction == me or e.victim == me):
   var p = Chronicle.entry(year,"war","Plunder" if e.faction == me else "Raiders in your land","%s took %d gold from %s." % [WorldMap.faction(e.faction).name,int(e.gold),WorldMap.region(e.region).get("name",e.region)],e.faction)
   p.with = e.victim
   out.append(p)
 state.chronicle.append_array(out)
 return out
