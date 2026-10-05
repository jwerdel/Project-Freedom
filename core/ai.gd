extends RefCounted
# Campaign AI (docs/ai-design.md). Each AI faction, once per turn, after the yearly processing:
# assess threats and opportunities, maybe declare war, build, raise and recruit, then give each
# army one job (defend, attack or besiege, flee, stage, rest). It acts only through the player's
# functions (Construction.start, Armies.raise_army/recruit, Movement.order, Battles.*), so it
# pays the same gold, upkeep and movement. Weights: data/ai.json. Randomness: a generator seeded by
# (campaign seed, year, faction); fixed iteration orders, so campaigns replay exactly.

const Battles = preload("res://core/battles.gd")
const BattleSim = preload("res://core/battle_sim.gd")
const Battlefield = preload("res://core/battlefield.gd")
const Movement = preload("res://core/movement.gd")
const Armies = preload("res://core/armies.gd")
const Construction = preload("res://core/construction.gd")
const Buildings = preload("res://core/buildings.gd")
const Economy = preload("res://core/economy.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const WorldMap = preload("res://core/world_map.gd")
const Chronicle = preload("res://core/chronicle.gd")
const Realm = preload("res://core/realm.gd")
const DATA = "res://data/ai.json"

static var _data = null

static func data() -> Dictionary:
 if _data == null:
  _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
  assert(_data is Dictionary,"Invalid AI data: "+DATA)
 return _data

static func reset():
 _data = null

# --- Personality --------------------------------------------------------------------------------

# The product of the faction's trait multipliers (data/maps/<map>/factions.json traits; data/ai.json).
static func personality(faction: String) -> Dictionary:
 var p = {"aggression":1.0,"boldness":1.0,"reserve":1.0,"armies":1.0,"economy":1.0,"defense":1.0,"wariness":0.0,
  "assault":0,"vengeful":0,"opportunist":0,"landless":-1,"composition":data().recruitment.composition}
 var table = data().personalities
 for t in WorldMap.faction(faction).get("traits",[]):
  if not table.has(t): continue
  for k in table[t]:
   if k == "composition": p.composition = table[t][k]
   elif k in ["assault","vengeful","opportunist"]: p[k] = maxi(int(p[k]),int(table[t][k]))
   elif k == "wariness": p.wariness = float(p.wariness)+float(table[t][k])
   else: p[k] = float(p[k])*float(table[t][k])
 return p

# --- Strength estimates ---------------------------------------------------------------------

static func unit_power(u: Dictionary) -> float:
 var c = data().power
 var b = UnitTypes.get_type(u.unit).battle
 var s = float(b.melee_attack)+float(b.melee_defence)+float(b.armour)*float(c.armour_weight)+float(b.get("charge",0))*float(c.charge_weight)
 var m = b.get("missile")
 if m != null: s += float(m.damage)*float(m.volleys)*float(c.missile_weight)
 return float(u.men)*s/float(c.divisor)*(1.0+int(u.get("rank",0))*float(c.rank_bonus))

# Cached within an AI phase: units change only through battles (the counter) or disbanding.
static var _power_cache = {}

static func army_power(state,army_id: String) -> float:
 var a = state.army_state[army_id]
 var key = "%s:%d:%d" % [army_id,state.battles,a.units.size()]
 if _power_cache.has(key): return _power_cache[key]
 var p = 0.0
 for u in a.units: p += unit_power(u)
 _power_cache[key] = p
 return p

static func walled(state,sid: String) -> bool:
 return Battlefield.walls(int(state.settlements[sid].get("defense",0)),0,5) != null

# What an attacker would face at a settlement: its garrison, armies inside, and friendly armies
# close enough to reinforce, all stronger behind walls.
static func settlement_defense(state,sid: String) -> float:
 var c = data().power
 var owner = state.settlements[sid].owner
 var p = 0.0
 for u in Battles.garrison_units(state,sid): p += unit_power(u)
 var at = WorldMap.settlement_position(sid)
 var rr = float(Battles.cfg().reinforcement_radius)
 for e in _armies_near(state,at,rr):
  if e.faction != owner: continue
  if e.garrison == sid: p += army_power(state,e.id)
  else: p += army_power(state,e.id)*float(c.reinforce_share)
 if walled(state,sid): p *= 1.0+float(c.wall_bonus)
 return p

# Every army as {id, faction, pos, garrison}, sorted by id. During an AI phase the list is kept and
# rebuilt only after something moves, fights or is raised (_invalidate); outside a phase (direct
# calls, tests) it is built fresh each time.
static var _snap = null
static var _in_phase := false

static func _armies(state) -> Array:
 if _in_phase and _snap != null: return _snap
 var out = []
 for id in _sorted(state.army_state.keys()):
  var a = state.army_state[id]
  out.append({"id":id,"faction":a.faction,"pos":Vector2(a.position[0],a.position[1]),"garrison":a.garrison})
 _snap_buckets = null
 if _in_phase: _snap = out
 return out

# The snapshot's armies within `radius` of a point, in the snapshot's order (by id), found through
# 64 m buckets instead of a scan of every army (scales to hundreds of armies).
const ARMY_BUCKET = 64.0
static var _snap_buckets = null
static func _armies_near(state,at: Vector2,radius: float) -> Array:
 var all = _armies(state)
 if _snap_buckets == null or not _in_phase:
  _snap_buckets = {}
  for i in all.size(): _snap_buckets.get_or_add(Vector2i((all[i].pos/ARMY_BUCKET).floor()),[]).append(i)
 var idx = []
 var lo = Vector2i(((at-Vector2.ONE*radius)/ARMY_BUCKET).floor())
 var hi = Vector2i(((at+Vector2.ONE*radius)/ARMY_BUCKET).floor())
 for bz in range(lo.y,hi.y+1):
  for bx in range(lo.x,hi.x+1):
   for i in _snap_buckets.get(Vector2i(bx,bz),[]):
    if all[i].pos.distance_to(at)<=radius: idx.append(i)
 idx.sort()
 return idx.map(func(i): return all[i])

static func _invalidate():
 _snap = null
 _snap_buckets = null

static func _sorted(a: Array) -> Array:
 var out = a.duplicate()
 out.sort()
 return out

# Factions this faction treats as hostile: at war with it, or (for threat purposes only) wary of.
static func at_war_with(state,f: String) -> Array:
 var out = []
 for o in state.factions():
  if o != f and Battles.at_war(state,f,o) and alive(state,o): out.append(o)
 return out

static func alive(state,f: String) -> bool:
 return not state.settlements_of(f).is_empty() or not Armies.armies_of(state,f).is_empty()

# --- The AI phase -----------------------------------------------------------------------------

# Run every AI faction's turn. opts: factions (which factions the AI controls; default all but
# the player), resolve_player (true: battles the AI starts against a human player are resolved at
# once with the default defender choice instead of being returned as pending).
# Returns {actions, pending: [battle], entries, moves (army id -> points walked, for the map), ms}.
# Fresh caches and the odds budget for an AI phase.
static func _begin_phase(state):
 _odds_cache = {}
 _power_cache = {}
 _in_phase = true
 _snap = null
 _odds_turn_spent = 0
 # With more factions than the per-turn budget, only every k-th faction (rotating by year) may run
 # simulated odds this turn; the others use the curve. Few factions: everyone may.
 _odds_groups = maxi(1,ceili(float(state.factions().size())/maxf(1.0,float(data().odds.turn_budget))))
 _odds_year = int(state.year)
 # The AI's direct searches stay in a window (Movement.ai_cap), and the blocking index catches up
 # with the yearly moves here, once, rather than inside some army's turn.
 Movement.ai_cap = true
 Movement._blk_key = []
 Movement._sync_blocks(state)

static func _end_phase():
 _in_phase = false
 _snap = null
 Movement.ai_cap = false

static func take_turns(state,opts := {}) -> Dictionary:
 var t0 = Time.get_ticks_usec()
 var report = {"actions":[],"pending":[],"entries":[],"moves":{},"ms":0.0,"faction_ms":{}}
 var controlled = opts.get("factions",state.factions().filter(func(f): return f != state.player_faction))
 _begin_phase(state)
 for f in _sorted(controlled):
  if not alive(state,f): continue
  var tf = Time.get_ticks_usec()
  faction_turn(state,f,report,opts,controlled)
  report.faction_ms[f] = (Time.get_ticks_usec()-tf)/1000.0
 _end_phase()
 report.ms = (Time.get_ticks_usec()-t0)/1000.0
 return report

# The AI phase spread over frames (TurnLoop.end_turn_sliced): the same factions in the same order
# as take_turns, handing control back to the engine between factions once the frame budget is spent.
static func take_turns_sliced(state,opts: Dictionary,slicer,progress := Callable()) -> Dictionary:
 var t0 = Time.get_ticks_usec()
 var report = {"actions":[],"pending":[],"entries":[],"moves":{},"ms":0.0,"faction_ms":{}}
 var controlled = opts.get("factions",state.factions().filter(func(f): return f != state.player_faction))
 slicer.at = "ai: phase start"
 _begin_phase(state)
 if slicer.over(): await slicer.next_frame()
 var order = _sorted(controlled)
 for k in order.size():
  var f = order[k]
  if alive(state,f):
   slicer.at = "ai: %s start" % f
   var tf = Time.get_ticks_usec()
   var c = _faction_begin(state,f)
   for step in FACTION_STEPS:
    slicer.at = "ai: %s step %d" % [f,step]
    if step == 6:
     # Army orders one army at a time (a big faction's orders can take a while).
     var busy = _command_prelude(state,f,c.look,report)
     for id in field_armies(state,f):
      slicer.at = "ai: %s army %s" % [f,id]
      _army_order(state,id,f,c.p,c.look,report,opts,controlled,busy)
      if slicer.over():
       _in_phase = false
       await slicer.next_frame()
       _in_phase = true
       _invalidate()
     continue
    _faction_step(step,state,f,c,report,opts,controlled)
    if slicer.over() and step<FACTION_STEPS-1:
     _in_phase = false
     await slicer.next_frame()
     _in_phase = true
     _invalidate()
   report.faction_ms[f] = (Time.get_ticks_usec()-tf)/1000.0
  if progress.is_valid(): progress.call(k+1,order.size(),f) # (done, total, the faction that just moved)
  if slicer.over():
   # Another frame: the snapshot of army positions is rebuilt after it (the map may have
   # changed nothing, but the cached lookups must not outlive the frame for safety).
   _in_phase = false
   await slicer.next_frame()
   _in_phase = true
   _invalidate()
 _end_phase()
 report.ms = (Time.get_ticks_usec()-t0)/1000.0
 return report

static func faction_turn(state,f: String,report: Dictionary,opts := {},controlled := []):
 var c = _faction_begin(state,f)
 for k in FACTION_STEPS: _faction_step(k,state,f,c,report,opts,controlled)

# A faction's turn in steps (take_turns_sliced may hand a frame back between them).
const FACTION_STEPS = 7
static func _faction_begin(state,f: String) -> Dictionary:
 _odds_spent = 0
 _odds_faction = f
 _invalidate()
 var rng = RandomNumberGenerator.new()
 rng.seed = hash([state.seed,state.year,f,"ai"])
 var p = personality(f)
 # Landless (grace period, core/realm.gd): everything turns to retaking a settlement in time.
 var left = Realm.grace_left(state,f)
 if left>=0:
  p = p.duplicate()
  p.landless = left
  p.boldness = float(p.boldness)*float(data().grace.boldness)
  p.aggression = maxf(float(p.aggression),1.0)
 return {"rng":rng,"p":p,"look":{}}

static func _faction_step(k: int,state,f: String,c: Dictionary,report: Dictionary,opts: Dictionary,controlled: Array):
 match k:
  0: c.look = assess(state,f,c.p)
  1: _consider_war(state,f,c.p,c.look,c.rng,report)
  2: _balance_books(state,f,report)
  3: _build(state,f,c.p,c.look,report)
  4: _raise(state,f,c.p,report)
  5: _recruit(state,f,c.p,report)
  6: _command(state,f,c.p,c.look,report,opts,controlled)

# Threats to own settlements and the posture they set.
static func assess(state,f: String,p: Dictionary) -> Dictionary:
 var d = data()
 var enemies = at_war_with(state,f)
 var threats = {}
 var threatened = []
 for sid in state.settlements_of(f):
  var at = WorldMap.settlement_position(sid)
  var t = 0.0
  for e in _armies(state):
   if e.faction == f: continue
   if e.pos.distance_to(at)>float(d.reach.threat_meters): continue
   var w = 1.0 if e.faction in enemies else float(personality(e.faction).wariness)
   if w>0.0: t += army_power(state,e.id)*w
  var def = settlement_defense(state,sid)
  threats[sid] = {"threat":t,"defense":def}
  if t>def*float(d.defend.threatened_ratio): threatened.append(sid)
 return {"enemies":enemies,"threats":threats,"threatened":threatened}

# Targets an army could strike this turn (reach default) or march on (war_meters): foreign
# settlements and field armies, strongest odds first.
static func targets_for(state,army_id: String,reach := -1.0) -> Array:
 var me = state.army_state[army_id]
 var from = Movement.position(state,army_id)
 if reach<0.0: reach = float(data().reach.reach_meters)
 var out = []
 for sid in _sorted(WorldMap.settlements_near(from,reach)):
  var s = state.settlements[sid]
  if s.owner == me.faction: continue
  var pos = WorldMap.settlement_position(sid)
  out.append({"kind":"settlement","id":sid,"faction":s.owner,"position":pos,"defense":settlement_defense(state,sid)})
 var rr = float(Battles.cfg().reinforcement_radius)
 var share = float(data().power.reinforce_share)
 for e in _armies_near(state,from,reach):
  if e.faction == me.faction or e.garrison != "": continue
  # A field army is joined by its friends nearby.
  var def = army_power(state,e.id)
  for o in _armies_near(state,e.pos,rr):
   if o.id != e.id and o.faction == e.faction: def += army_power(state,o.id)*share
  out.append({"kind":"army","id":e.id,"faction":e.faction,"position":e.pos,"defense":def})
 # Own armies close enough to the target join the battle as reinforcements (Battles), so they count.
 var mine = army_power(state,army_id)
 for t in out:
  var help = 0.0
  for o in _armies_near(state,t.position,rr):
   if o.id != army_id and o.faction == me.faction: help += army_power(state,o.id)*share
  t.ratio = (mine+help)/maxf(1.0,float(t.defense))
 out.sort_custom(func(a,b): return a.ratio>b.ratio or (a.ratio == b.ratio and a.id<b.id))
 return out

# What the faction could bring against a target over a few turns: its field armies within
# war_meters of it, times gather_share (not all of them will arrive or be spared).
static func strategic_power(state,f: String,at: Vector2) -> float:
 var p = 0.0
 for id in field_armies(state,f):
  if state.army_state[id].units.size()>=int(data().recruitment.garrison_units) and Movement.position(state,id).distance_to(at)<=float(data().reach.war_meters): p += army_power(state,id)
 return p*float(data().war.gather_share)

static func field_armies(state,f: String) -> Array:
 return Armies.armies_of(state,f).filter(func(id):
  var a = state.army_state[id]
  return not a.units.is_empty() and Battles.can_move(state,id))

# --- War ----------------------------------------------------------------------------------------

static func _consider_war(state,f: String,p: Dictionary,look: Dictionary,rng: RandomNumberGenerator,report: Dictionary):
 var w = data().war
 var landless = int(p.landless)>=0
 if look.enemies.size()>=int(w.max_wars) and not landless: return
 # The best target among factions at peace, from any army with enough units.
 var best = {}
 for id in field_armies(state,f):
  if state.army_state[id].units.size()<int(data().recruitment.garrison_units) and not landless: continue
  for t in targets_for(state,id,float(data().reach.war_meters)):
   if t.faction in look.enemies or t.faction == "": continue
   if landless and t.kind != "settlement": continue
   # The whole field force that could gather against it, not one army.
   var ratio = maxf(float(t.ratio),strategic_power(state,f,t.position)/maxf(1.0,float(t.defense)))
   var score = ratio
   # A walled target the force could besiege (a match for it without the walls) counts as weak
   # enough to start a war over, at siege_weight.
   if t.kind == "settlement" and walled(state,t.id): score = maxf(score,ratio*(1.0+float(data().power.wall_bonus))*float(w.siege_weight))
   if int(p.opportunist) == 1 and not at_war_with(state,t.faction).is_empty(): score *= 1.5
   if best.is_empty() or score>best.score: best = {"score":score,"target":t,"army":id}
 if best.is_empty(): return
 var weakness = clampf(minf(2.0,best.score)-1.0,0.0,1.0)
 var chance = 1.0 if landless else float(w.base_chance)*float(p.aggression)*weakness
 var roll = rng.randf()
 if roll>=chance: return # (a landless faction does not roll: it must take a settlement)
 # Only for a fight it expects to win (the curve estimate; the attack itself is re-checked by
 # simulation before it is made).
 if curve_odds(float(best.score))<float(data().attack.min_odds)/float(p.boldness): return
 var e = Battles.declare_war(state,f,best.target.faction)
 if not e.is_empty():
  report.entries.append(e)
  report.actions.append({"action":"war","faction":f,"against":best.target.faction,"chance":chance})
  look.enemies.append(best.target.faction)

# --- Economy ----------------------------------------------------------------------------------

static func reserve(f: String,p: Dictionary) -> int:
 return int(float(data().economy.reserve_gold)*float(p.reserve))

static func _build(state,f: String,p: Dictionary,look: Dictionary,report: Dictionary):
 var e = data().economy
 for n in int(e.max_builds_per_turn):
  var surplus = int(state.treasury.get(f,0))-reserve(f,p)
  var net = int(Economy.faction_ledger(state,f).net)
  var best = {}
  for sid in state.settlements_of(f):
   if not Construction.in_progress(state,sid).is_empty(): continue
   var weights = e.threatened_weights if sid in look.threatened else e.economy_weights
   var s = state.settlements[sid]
   var first_empty = -1
   for i in s.buildings.size():
    if s.buildings[i].is_empty():
     first_empty = i
     break
   for i in s.buildings.size():
    if s.buildings[i].is_empty() and i != first_empty: continue
    for o in Construction.options(state,sid,i):
     if not o.available or o.cost>surplus or net-int(o.upkeep)<int(e.min_net_income): continue
     var wgt = float(weights.get(o.category,0.0))
     if o.category in ["main","economic"]: wgt *= float(p.economy)
     if o.category in ["defense","military"]: wgt *= float(p.defense)
     if wgt<=0.0: continue
     var key = [-wgt,o.cost,sid,o.chain]
     if best.is_empty() or key<best.key: best = {"key":key,"id":sid,"slot":i,"chain":o.chain}
  if best.is_empty(): return
  if Construction.start(state,best.id,best.slot,best.chain).ok:
   report.actions.append({"action":"build","faction":f,"settlement":best.id,"chain":best.chain})

# Upkeep the faction cannot carry: when next year would end in debt (treasury + net income < 0),
# disband units, least power per upkeep first, until income covers upkeep, when disbanding can do
# that at all (the player can do the same;
# what a negative treasury does is OPEN in the constitution, so the AI avoids it).
static func _balance_books(state,f: String,report: Dictionary):
 # Pointless if even an army-less faction would be in deficit (buildings, generals): keep the troops.
 var unit_upkeep = 0.0
 for id in Armies.armies_of(state,f):
  for u in state.army_state[id].units: unit_upkeep += float(UnitTypes.get_type(u.unit).placeholder_stats.upkeep)*float(Economy.data().upkeep.army_upkeep_multiplier)
 if float(Economy.faction_ledger(state,f).net)+unit_upkeep<0.0: return
 var guard = 0
 while guard<40:
  var net = int(Economy.faction_ledger(state,f).net)
  # Stop once income covers upkeep, or the treasury can carry the shortfall another year.
  if net>=0 or int(state.treasury[f])+net>=0: return
  guard += 1
  var worst = {}
  for id in Armies.armies_of(state,f):
   var a = state.army_state[id]
   for i in a.units.size():
    var u = a.units[i]
    var t = UnitTypes.get_type(u.unit)
    var upkeep = float(t.placeholder_stats.upkeep)
    var key = [unit_power(u)/maxf(1.0,upkeep),id,i]
    if worst.is_empty() or key<worst.key: worst = {"key":key,"army":id,"index":i,"unit":u.unit}
  if worst.is_empty(): return
  Armies.disband(state,worst.army,worst.index)
  report.actions.append({"action":"disband","faction":f,"army":worst.army,"unit":worst.unit})
  _power_cache.clear()

# Raise a new army when under the faction's army target and it can pay a general plus a margin.
static func _raise(state,f: String,p: Dictionary,report: Dictionary):
 var r = data().recruitment
 var cap = int(Armies.data().armies.max_per_faction)
 var want = clampi(int(round(float(r.base_armies)*float(p.armies))),1,cap)
 var have = Armies.armies_of(state,f).size()
 if have>=want: return
 # With no army at all, a faction digs into its reserve (keeps emergency_reserve_share of it).
 var floor = reserve(f,p)+int(r.raise_margin) if have>0 else int(reserve(f,p)*float(r.emergency_reserve_share))
 if int(state.treasury.get(f,0))-int(Armies.data().armies.general_cost)<floor: return
 var best = ""
 for sid in state.settlements_of(f):
  if not Armies.can_raise(state,f,sid).ok: continue
  if best == "" or float(state.settlements[sid].population)>float(state.settlements[best].population): best = sid
 if best == "": return
 var res = Armies.raise_army(state,f,best)
 _invalidate()
 if res.ok: report.actions.append({"action":"raise","faction":f,"army":res.army,"settlement":best})

static func role_of(unit_id: String) -> String:
 var t = UnitTypes.get_type(unit_id)
 if unit_id == "peasant_levy": return "levy"
 if t.category == "infantry" and t.battle.get("brace",false): return "spear"
 return t.category

# Recruit toward the faction's target composition: the available unit with the largest shortfall.
static func _recruit(state,f: String,p: Dictionary,report: Dictionary):
 var r = data().recruitment
 var comp = p.composition
 var net = int(Economy.faction_ledger(state,f).net)
 # With hardly any troops left, recruiting digs into the reserve like an emergency raise.
 var total = 0
 for id in Armies.armies_of(state,f): total += state.army_state[id].units.size()+state.army_state[id].queue.size()
 var floor = reserve(f,p) if total>=int(r.garrison_units) else int(reserve(f,p)*float(r.emergency_reserve_share))
 for id in Armies.armies_of(state,f):
  var a = state.army_state[id]
  if not Armies.recruit_context(state,id).ok: continue
  for n in int(r.max_recruits_per_turn):
   var size = a.units.size()+a.queue.size()
   # A rich faction fills its armies past the field size, up to the army cap.
   var target = int(r.field_units) if int(state.treasury[f])<reserve(f,p)*float(r.rich_factor) else Armies.max_units()-1
   if size>=target: break
   var counts = {}
   for u in a.units: counts[role_of(u.unit)] = counts.get(role_of(u.unit),0)+1
   for q in a.queue: counts[role_of(q.unit)] = counts.get(role_of(q.unit),0)+1
   var best = {}
   for o in Armies.options(state,id):
    if not o.available or int(state.treasury[f])-o.cost<floor or net-o.upkeep<int(data().economy.min_net_income): continue
    var role = role_of(o.unit)
    var shortfall = float(comp.get(role,0.0))*(size+1)-float(counts.get(role,0))
    var key = [-shortfall,-unit_power({"unit":o.unit,"men":o.men})/maxf(1.0,o.cost),o.unit]
    if best.is_empty() or key<best.key: best = {"key":key,"unit":o.unit,"upkeep":o.upkeep}
   if best.is_empty(): break
   if not Armies.recruit(state,id,best.unit).ok: break
   net -= int(best.upkeep)
   report.actions.append({"action":"recruit","faction":f,"army":id,"unit":best.unit})

# --- Armies -------------------------------------------------------------------------------------

# Win chance for an attack: decided by the power ratio when clear, else by seeded quick simulations.
static var _odds_cache = {} # odds by (year, battle counter, army, target, position, both strengths), reset each AI phase
static var _odds_spent := 0 # simulated odds estimates this faction has used this turn
static var _odds_turn_spent := 0 # ... and all factions together this AI phase (odds.turn_budget)
static var _odds_groups := 1
static var _odds_year := 0
static var _odds_faction := ""

static func attack_odds(state,army_id: String,target: Dictionary) -> float:
 var o = data().odds
 var ratio = army_power(state,army_id)/maxf(1.0,float(target.defense))
 if ratio>=float(o.sure_ratio): return 0.95
 if ratio<=float(o.hopeless_ratio): return 0.05
 var key = "%d:%d:%s:%s:%s:%.3f:%.3f" % [state.year,state.battles,army_id,target.id,str(state.army_state[army_id].position),army_power(state,army_id),float(target.defense)]
 if _odds_cache.has(key): return _odds_cache[key]
 # Over this faction's or this turn's simulation budget, or not this faction's turn to simulate: a
 # logistic curve of the power ratio stands in.
 if _odds_spent>=int(o.odds_budget) or _odds_turn_spent>=int(o.turn_budget): return curve_odds(ratio)
 if _odds_groups>1 and (absi(hash(_odds_faction))+_odds_year)%_odds_groups != 0: return curve_odds(ratio)
 _odds_spent += 1
 _odds_turn_spent += 1
 var pb = Battles.prebattle(state,army_id,target,false)
 var v = Battles.odds(state,pb,int(o.odds_runs))
 _odds_cache[key] = v
 return v

# Win chance from the power ratio alone (no simulation).
static func curve_odds(ratio: float) -> float:
 return 1.0/(1.0+exp(-float(data().odds.curve_k)*(ratio-1.0)))

static func _command(state,f: String,p: Dictionary,look: Dictionary,report: Dictionary,opts: Dictionary,controlled: Array,prelude_only = null):
 var d = data()
 var busy = {}
 # 0. Armies besieging hold while the siege can still win.
 for sid in _sorted(state.settlements.keys()):
  var sg = state.settlements[sid].get("siege",{})
  var id = sg.get("army","")
  if id == "" or not state.army_state.has(id) or state.army_state[id].faction != f: continue
  busy[id] = true
  report.actions.append({"action":"hold_siege","faction":f,"army":id,"settlement":sid})
 # 1. Defend threatened settlements: armies in reach move in if they can make the difference.
 var tl = look.threatened.duplicate()
 tl.sort_custom(func(a,b): return look.threats[a].threat>look.threats[b].threat or (look.threats[a].threat == look.threats[b].threat and a<b))
 for sid in tl:
  var need = float(look.threats[sid].threat)*float(d.defend.save_ratio)
  var have = float(look.threats[sid].defense)
  var helpers = []
  for id in field_armies(state,f):
   if busy.has(id): continue
   if state.army_state[id].garrison == sid:
    busy[id] = true
    continue
   if Movement.position(state,id).distance_to(WorldMap.settlement_position(sid))<=float(d.reach.reach_meters): helpers.append(id)
  for id in helpers:
   if have>=need: break
   have += army_power(state,id)
  if have<need: continue # cannot be saved: do not throw armies away
  for id in helpers:
   if busy.has(id): continue
   var r = _move(state,report,id,WorldMap.settlement_position(sid))
   if r.ok:
    busy[id] = true
    report.actions.append({"action":"defend","faction":f,"army":id,"settlement":sid})
 if prelude_only != null:
  prelude_only.busy = busy
  return
 # 2.-5. Every other army: attack or besiege, flee, stage, rest.
 for id in field_armies(state,f): _army_order(state,id,f,p,look,report,opts,controlled,busy)

# Steps 0-1 of _command; returns the armies they took (the sliced turn then orders the rest one by one).
static func _command_prelude(state,f: String,look: Dictionary,report: Dictionary) -> Dictionary:
 var c = {"busy":{}}
 _command(state,f,{},look,report,{},[],c)
 return c.busy

static func _army_order(state,id: String,f: String,p: Dictionary,look: Dictionary,report: Dictionary,opts: Dictionary,controlled: Array,busy: Dictionary):
 if busy.has(id) or not state.army_state.has(id): return
 if _try_attack(state,id,f,p,look,report,opts,controlled): return
 if _flee(state,id,f,report): return
 if _stage(state,id,f,p,look,report): return
 _rest(state,id,f,report)

static func _try_attack(state,id: String,f: String,p: Dictionary,look: Dictionary,report: Dictionary,opts: Dictionary,controlled: Array) -> bool:
 var d = data()
 var a = state.army_state[id]
 # A home army keeps building up before it marches out.
 if a.units.size()<int(d.recruitment.garrison_units) and look.enemies.is_empty(): return false
 var tries = 0
 var landless = int(p.landless)
 for t in targets_for(state,id):
  if not t.faction in look.enemies: continue
  if landless>=0 and t.kind != "settlement": continue # only a settlement saves it
  if tries>=int(d.reach.plan_candidates): break
  tries += 1
  var appr = Battles.approach(state,id,t)
  if not appr.ok: continue
  var odds = attack_odds(state,id,t)
  var min_odds = float(d.attack.min_odds)/float(p.boldness)
  if int(p.vengeful) == 1: min_odds /= 1.1
  if t.kind == "settlement" and walled(state,t.id):
   var assault = int(p.assault) == 1 and odds>=min_odds
   if odds<float(d.attack.assault_min_odds) and not assault:
    # Starve it out: besiege when the army is a match for the defenders without their walls
    # (it can hold the siege lines), though not for an assault.
    var open_ratio = float(t.ratio)*(1.0+float(d.power.wall_bonus))
    if open_ratio<float(d.attack.siege_ratio)/float(p.boldness) or state.settlements[t.id].has("siege"): continue
    # A landless faction cannot wait out a siege longer than its grace period.
    if landless>=0 and Battles.endurance(state,t.id)>=landless: continue
    _record(report,id,Battles.move_to_attack(state,id,appr))
    var r = Battles.besiege(state,id,t.id)
    if r.ok:
     var e = Chronicle.siege_entry(state.year,t.id,f)
     state.chronicle.append(e)
     report.entries.append(e)
     report.actions.append({"action":"besiege","faction":f,"army":id,"settlement":t.id})
     return true
    continue
  if odds<min_odds: continue
  _attack(state,id,t,appr,report,opts,controlled)
  return true
 return false

# Fight now (AI against AI), or leave the battle pending for a human defender.
static func _attack(state,id: String,t: Dictionary,appr: Dictionary,report: Dictionary,opts: Dictionary,controlled: Array):
 var pb = Battles.prebattle(state,id,t,false)
 pb.approach = appr
 _record(report,id,Battles.move_to_attack(state,id,appr))
 var human = t.faction == state.player_faction and not state.player_faction in controlled
 report.actions.append({"action":"attack","faction":state.army_state[id].faction,"army":id,"target":t.id,"kind":t.kind,"against":t.faction})
 if human and not opts.get("resolve_player",false):
  pb.odds = -1.0
  report.pending.append(pb)
  return
 resolve_as_defender(state,pb,report,controlled)

# Would this defender withdraw? Field battles only, when its odds are below withdraw_below.
static func defender_withdraws(state,pb: Dictionary) -> bool:
 if pb.kind != "army": return false
 var odds = float(pb.odds) if float(pb.get("odds",-1.0))>=0.0 else Battles.odds(state,pb,int(data().odds.odds_runs))
 return 1.0-odds<float(data().defend.withdraw_below)

# The defender's choice (AI or a headless player): withdraw from a hopeless field battle, else fight.
static func resolve_as_defender(state,pb: Dictionary,report: Dictionary,controlled := []) -> Dictionary:
 if pb.kind == "army":
  if defender_withdraws(state,pb):
   var w = Battles.withdraw(state,pb)
   _power_cache.clear() # the withdrawal cost men
   _invalidate()
   if w.ok:
    var e = Chronicle.withdraw_entry(state.year,pb)
    state.chronicle.append(e)
    report.entries.append(e)
    report.actions.append({"action":"withdraw","faction":pb.defender.faction,"armies":pb.defender.armies})
    return {"withdrew":true}
 # Nobody reads a report of an AI-only battle: fast mode (same outcome, no replay). A battle the
 # human player is in keeps its full record for the report window.
 var human = state.player_faction != "" and not state.player_faction in controlled
 var fast = not human or (pb.attacker.faction != state.player_faction and pb.defender.faction != state.player_faction)
 var out = Battles.quick_resolve(state,pb,fast)
 _invalidate()
 report.entries.append_array(out.aftermath.entries)
 report.actions.append({"action":"battle","attacker":pb.attacker.faction,"defender":pb.defender.faction,"winner":out.result.winner,"captured":out.aftermath.captured})
 return out

# Fall back to the nearest own settlement from an enemy force it cannot face.
static func _flee(state,id: String,f: String,report: Dictionary) -> bool:
 var a = state.army_state[id]
 if a.garrison != "": return false
 var at = Movement.position(state,id)
 var enemies = at_war_with(state,f)
 var t = 0.0
 for e in _armies(state):
  if e.faction in enemies and e.pos.distance_to(at)<=float(data().reach.threat_meters): t += army_power(state,e.id)
 if t<=army_power(state,id)*float(data().defend.flee_ratio): return false
 var home = _nearest_own(state,f,at)
 if home == "": return false
 var r = _move(state,report,id,WorldMap.settlement_position(home))
 if r.ok: report.actions.append({"action":"flee","faction":f,"army":id,"to":home})
 return r.ok

# At war with nothing in reach: march on the most promising enemy target within war_meters (its
# approach point, a multi-turn order), or else to the own settlement closest to the enemy.
static func _stage(state,id: String,f: String,p: Dictionary,look: Dictionary,report: Dictionary) -> bool:
 if look.enemies.is_empty() or float(p.aggression)<0.3: return false
 var a = state.army_state[id]
 if a.units.size()<int(data().recruitment.garrison_units) and int(p.landless)<0: return false
 var cap = Armies.capital(state,f)
 var last_home = a.garrison == cap and Movement.garrison_of(state,cap).size()<=1 and Armies.armies_of(state,f).size()<=1
 if not last_home:
  var tries = 0
  for t in targets_for(state,id,float(data().reach.war_meters)):
   if not t.faction in look.enemies: continue
   if tries>=int(data().reach.plan_candidates): break
   tries += 1
   var force = maxf(float(t.ratio),strategic_power(state,f,t.position)/maxf(1.0,float(t.defense)))
   if t.kind == "settlement" and walled(state,t.id): force *= (1.0+float(data().power.wall_bonus))*float(data().war.siege_weight)
   if force<float(data().attack.march_ratio)/float(p.boldness): continue
   var appr = Battles.approach(state,id,t)
   if appr.ok or not appr.has("point"): continue # in reach (attack declined) or unreachable
   var m = _move(state,report,id,appr.point)
   if m.ok:
    report.actions.append({"action":"march","faction":f,"army":id,"target":t.id})
    return true
 var best = ""
 var best_d = INF
 for sid in _sorted(state.settlements.keys()):
  if not state.settlements[sid].owner in look.enemies: continue
  var p_enemy = WorldMap.settlement_position(sid)
  for own in state.settlements_of(f):
   var dd = WorldMap.settlement_position(own).distance_to(p_enemy)
   if dd<best_d:
    best_d = dd
    best = own
 if best == "" or a.garrison == best: return false
 # Keep the capital defended: the last army at the capital stays.
 if a.garrison == cap and Movement.garrison_of(state,cap).size()<=1 and not cap in look.threatened and best != cap:
  if Armies.armies_of(state,f).size()<=1: return false
 var r = _move(state,report,id,WorldMap.settlement_position(best))
 if r.ok: report.actions.append({"action":"stage","faction":f,"army":id,"to":best})
 return r.ok

# Nothing to do: go home (garrisoned armies replenish and recruit).
static func _rest(state,id: String,f: String,report: Dictionary):
 var a = state.army_state[id]
 if a.garrison != "" or not a.order.is_empty(): return
 var home = _nearest_own(state,f,Movement.position(state,id))
 if home == "": return
 if _move(state,report,id,WorldMap.settlement_position(home)).ok: report.actions.append({"action":"rest","faction":f,"army":id,"to":home})

static func _nearest_own(state,f: String,at: Vector2) -> String:
 var best = ""
 var best_d = INF
 for sid in state.settlements_of(f):
  var dd = WorldMap.settlement_position(sid).distance_to(at)
  if dd<best_d:
   best_d = dd
   best = sid
 return best

# Every AI move goes through here so the map can replay it (report.moves: army -> points walked).
static func _move(state,report: Dictionary,id: String,point: Vector2) -> Dictionary:
 var r = Movement.order(state,id,point)
 _invalidate()
 if r.ok: _record(report,id,r.get("moved",[]))
 return r

static func _record(report: Dictionary,id: String,walked: Array):
 _invalidate()
 if walked.size()<2: return
 if not report.moves.has(id): report.moves[id] = walked.duplicate()
 else: report.moves[id].append_array(walked.slice(1))
