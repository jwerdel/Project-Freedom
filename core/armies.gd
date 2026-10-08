extends RefCounted
# Armies as campaign state (state.army_state[id], shared with core/movement.gd): composition,
# recruitment queue, disbanding, replenishment, raising new armies.
# Constitution rules applied: recruitment draws directly from the settlement's population;
# disbanded survivors return to population; replenishment is automatic in friendly regions with no
# population cost and faster in populous regions, and costs gold in enemy territory.
# Choices (placeholders in data/recruitment.json):
#  - Recruitment is per settlement, not per province: the men come from that settlement's population
#    (constitution: "the region's population pool", one settlement per region) and the units from that
#    settlement's own buildings. Provinces on this map can be split between owners, so a province
#    pool would let one faction recruit from another's buildings.
#  - Army cap: max_units cards per army (general included, queued units counted). PLACEHOLDER.
#  - Max armies per faction is OPEN; general cost and generated names are STUBS until the character
#    and family system exists.
# Global recruitment and recruitment capacity: see "Recruitment modes and capacity" below.
# OPEN (not implemented): recruitment slots per settlement, raise banners,
# disbanding a whole army or its general, how a negative treasury is handled, who counts as an enemy
# for replenishment once diplomacy exists (now: any region the army's faction does not own).

const UnitTypes = preload("res://core/unit_types.gd")
const WorldMap = preload("res://core/world_map.gd")
const Buildings = preload("res://core/buildings.gd")
const Movement = preload("res://core/movement.gd")
const Economy = preload("res://core/economy.gd")
const DATA = "res://data/recruitment.json"
const NAMES = "res://data/names.json"

static var _data = null
static var _names = null

static func data() -> Dictionary:
 if _data == null:
  _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
  assert(_data is Dictionary and _data.has("recruitment") and _data.has("army_cap"),"Invalid "+DATA)
 return _data

static func names() -> Dictionary:
 if _names == null:
  _names = JSON.parse_string(FileAccess.get_file_as_string(NAMES))
  assert(_names is Dictionary and _names.has("cultures"),"Invalid "+NAMES)
 return _names

static func reset():
 _data = null
 _names = null

static func max_units() -> int:
 return int(data().army_cap.max_units)

# --- Composition -------------------------------------------------------------------

# Starting composition from data/maps/<map>/armies/<id>.json ("strength" is the fraction of full size).
static func from_data(army_id: String) -> Dictionary:
 var a = UnitTypes.army(army_id)
 var units = []
 for u in a.units:
  var size = int(UnitTypes.get_type(u.unit).size)
  units.append({"unit":u.unit,"men":int(round(size*float(u.get("strength",1.0)))),"max_men":size})
 return {"faction":a.faction,"display_name":a.display_name,"commander":{"name":a.commander.name,"rank":int(a.commander.get("rank",1))},"units":units,"queue":[]}

static func army(state,army_id: String) -> Dictionary:
 assert(state.army_state.has(army_id),"Unknown army '%s'" % army_id)
 return state.army_state[army_id]

# Cards in the army: the general, its units and the units queued for it.
static func card_count(a: Dictionary) -> int:
 return 1+a.units.size()+a.queue.size()

static func men(a: Dictionary) -> int:
 var total = 0
 for u in a.units: total += int(u.men)
 return total

# --- Recruitment --------------------------------------------------------------------

# Province-wide recruitment (constitution, confirmed 2026-10-02; TW:WH3 local recruitment): an army
# standing anywhere in a region its faction owns can recruit. The units on offer come from the
# faction's buildings in that region's province (every settlement it owns there); each recruit's men
# are drawn from one of those settlements (the one that unlocks it with the most people).
# Returns {ok, reason, region, province, settlements: [own settlements in the province]}.
static func recruit_context(state,army_id: String) -> Dictionary:
 var a = army(state,army_id)
 var region = WorldMap.region_at(Movement.position(state,army_id))
 if region == "" or not state.settlements.has(region) or state.settlements[region].owner != a.faction:
  return {"ok":false,"reason":"Must be in your own territory","region":region,"province":"","settlements":[]}
 var province = WorldMap.province_of(region)
 var own = []
 for sid in WorldMap.province(province).regions:
  if state.settlements.has(sid) and state.settlements[sid].owner == a.faction: own.append(sid)
 return {"ok":true,"reason":"","region":region,"province":province,"settlements":own}

# The settlement in the army's province that would supply this unit: one that unlocks it, the
# most populous first (ties: the army's own region, then id). "" if none unlocks it.
static func recruit_source(state,ctx: Dictionary,unit_id: String) -> String:
 var best = ""
 for sid in ctx.settlements:
  if not unit_id in state.settlements[sid].get("unlocks",[]): continue
  if best == "": best = sid
  else:
   var p = float(state.settlements[sid].population)
   var q = float(state.settlements[best].population)
   if p>q or (p == q and (sid == ctx.region or (best != ctx.region and sid<best))): best = sid
 return best

# The unit types a faction can ever recruit: its culture's roster (levies come only from the banners),
# or the generic units when it has no roster (the test map). Without a faction: every generic type.
static func recruitable_types(faction := "") -> Array:
 var out = []
 var R = load("res://core/rosters.gd")
 var cul = str(WorldMap.faction(faction).get("culture","")) if faction != "" else ""
 if faction != "" and R.has_roster(cul):
  for id in R.units_of(cul):
   if not bool(UnitTypes.get_type(id).get("levy",false)): out.append(id)
  return out
 for id in UnitTypes.ids():
  var u = UnitTypes.get_type(id)
  if u.recruitment != null and str(u.get("culture","")) == "": out.append(id)
 return out

# The building level that unlocks a unit, for locked reasons ("Requires Barracks: Garrison").
static func unlocked_by(unit_id: String) -> String:
 for c in Buildings.chain_ids():
  var ch = Buildings.chain(c)
  for i in ch.levels.size():
   if unit_id in ch.levels[i].effects.get("unlocks",[]): return "%s: %s" % [ch.name,ch.levels[i].name]
 return "a building"

# --- Recruitment modes and capacity (TW:WH3; constitution, confirmed 2026-10-02) ---------------
# Local: units from the faction's buildings in the army's province, in its own territory (above).
# Global: anywhere (also abroad), every unit the faction's buildings unlock anywhere, at
# global.cost_multiplier x the gold and global.turns_multiplier x the turns.
# Capacity: capacity() units recruit at their normal time; further units are overflow and take
# extra turns (data/recruitment.json capacity). Queue entries carry their kind for the TW banner
# (local green, global blue, overflow orange). Recruiting never locks movement (owner decision).

const MODES = ["local","global"]

# Units this army's lord recruits at normal speed. Hooks: buildings in the army's province with the
# effect recruit_capacity, and the general's own recruit_capacity (traits and skills, from the
# character system; none exist yet).
static func capacity(state,army_id: String) -> int:
 var a = army(state,army_id)
 var n = int(data().recruitment.capacity.per_turn)
 var ctx = recruit_context(state,army_id)
 for sid in ctx.settlements:
  for b in Buildings.built(state,sid): n += int(Buildings.level_data(b.chain,b.level).effects.get("recruit_capacity",0))
 n += int(a.get("commander",{}).get("recruit_capacity",0))
 return maxi(1,n)

# Extra turns for a unit queued at position `pos` (0-based) in a queue with capacity `cap`.
static func overflow_turns(pos: int,cap: int) -> int:
 if pos<cap: return 0
 return (1+(pos-cap)/cap)*int(data().recruitment.capacity.overflow_extra_turns)

# Global recruitment: every settlement of the faction counts as a source.
static func global_context(state,army_id: String) -> Dictionary:
 var a = army(state,army_id)
 var region = WorldMap.region_at(Movement.position(state,army_id))
 var own = state.settlements_of(a.faction)
 own.sort()
 if own.is_empty(): return {"ok":false,"reason":"Your house holds no settlement","region":region,"province":"","settlements":[]}
 return {"ok":true,"reason":"","region":region,"province":"","settlements":own}

static func mode_context(state,army_id: String,mode: String) -> Dictionary:
 return global_context(state,army_id) if mode == "global" else recruit_context(state,army_id)

# Gold and turns of a unit in a mode (before overflow).
static func mode_cost(unit_id: String,mode: String) -> int:
 var c = int(UnitTypes.get_type(unit_id).recruitment.cost)
 return int(ceil(c*float(data().recruitment.global.cost_multiplier))) if mode == "global" else c

static func mode_turns(unit_id: String,mode: String) -> int:
 var t = int(UnitTypes.get_type(unit_id).recruitment.turns)
 return t*int(data().recruitment.global.turns_multiplier) if mode == "global" else t

static func can_recruit(state,army_id: String,unit_id: String,mode := "local") -> Dictionary:
 var a = army(state,army_id)
 var ctx = mode_context(state,army_id,mode)
 if not ctx.ok: return {"ok":false,"reasons":[ctx.reason],"settlement":""}
 var u = UnitTypes.get_type(unit_id)
 if u.recruitment == null: return {"ok":false,"reasons":["Cannot be recruited"],"settlement":""}
 var sid = recruit_source(state,ctx,unit_id)
 var reasons = []
 if sid == "": reasons.append(("Requires %s in your realm" if mode == "global" else "Requires %s in this province") % unlocked_by(unit_id))
 var s = state.settlements[sid] if sid != "" else {"population":0.0}
 var cost = mode_cost(unit_id,mode)
 if card_count(a)+1>max_units(): reasons.append("Army is full (%d units)" % max_units())
 if int(state.treasury.get(a.faction,0))<0: reasons.append("In debt: no recruitment until the treasury is out of debt")
 elif int(state.treasury.get(a.faction,0))<cost: reasons.append("Not enough gold (%d needed)" % cost)
 if sid != "" and float(s.population)-int(u.size)<float(data().recruitment.min_population):
  reasons.append("Too few people in %s (keeps at least %d)" % [WorldMap.region(sid).settlement.name,int(data().recruitment.min_population)])
 # Food or wood for some units (Part B, data/resources.json unit_costs).
 var Res = load("res://core/resources.gd")
 reasons.append_array(Res.shortfall(state,a.faction,Res.unit_cost(unit_id)))
 return {"ok":reasons.is_empty(),"reasons":reasons,"settlement":sid}

# Recruitment panel entries for a mode: every recruitable unit type with cost, turns (including the
# overflow the next recruit would get), upkeep, men and reasons.
static func options(state,army_id: String,mode := "local") -> Array:
 var out = []
 var a = army(state,army_id)
 var extra = overflow_turns(a.queue.size(),capacity(state,army_id))
 for id in recruitable_types(a.faction):
  var u = UnitTypes.get_type(id)
  var check = can_recruit(state,army_id,id,mode)
  out.append({"unit":id,"name":u.display_name,"cost":mode_cost(id,mode),"turns":mode_turns(id,mode)+extra,"overflow":extra>0,"mode":mode,
   "upkeep":int(round(float(u.placeholder_stats.upkeep)*float(Economy.data().upkeep.army_upkeep_multiplier))),"men":int(u.size),
   "available":check.ok,"reasons":check.reasons,"settlement":check.settlement,"materials":load("res://core/resources.gd").unit_cost(id)})
 return out

# One card per unit (owner spec 2026-10-07: no duplicate cards): the best source for each, local when
# it can be recruited here (cheaper and faster), else global, else the local entry with its reasons.
static func best_options(state,army_id: String) -> Array:
 var local = options(state,army_id,"local")
 var global = options(state,army_id,"global")
 var by_unit = {}
 for o in global: by_unit[o.unit] = o
 var out = []
 var seen = {}
 for o in local:
  if seen.has(o.unit): continue
  seen[o.unit] = true
  var g = by_unit.get(o.unit,{})
  out.append(o if o.available or g.is_empty() or not g.available else g)
 return out

# Queue a unit: gold and men are taken now. Its kind is the mode, or "overflow" past the capacity.
# Returns {ok, reasons, settlement, kind, turns}.
static func recruit(state,army_id: String,unit_id: String,mode := "local") -> Dictionary:
 var check = can_recruit(state,army_id,unit_id,mode)
 if not check.ok: return check
 var a = army(state,army_id)
 var u = UnitTypes.get_type(unit_id)
 var cost = mode_cost(unit_id,mode)
 var extra = overflow_turns(a.queue.size(),capacity(state,army_id))
 var turns = mode_turns(unit_id,mode)+extra
 state.treasury[a.faction] -= cost
 var Res = load("res://core/resources.gd")
 var mats = Res.unit_cost(unit_id)
 Res.pay(state,a.faction,mats)
 state.settlements[check.settlement].population = float(state.settlements[check.settlement].population)-int(u.size)
 a.queue.append({"unit":unit_id,"settlement":check.settlement,"turns_left":turns,"turns_total":turns,"cost":cost,"materials":mats,"men":int(u.size),"mode":mode,"extra":extra})
 check.kind = queue_kind(a.queue[-1])
 check.turns = turns
 return check

# Banner kind of a queue entry: overflow (orange) beats global (blue) beats local (green).
static func queue_kind(q: Dictionary) -> String:
 if int(q.get("extra",0))>0: return "overflow"
 return "global" if q.get("mode","local") == "global" else "local"

# Cancel a queued unit: full refund of gold and men. Later overflow units move up into the freed
# slot and lose the extra turns they no longer need. Returns {gold, men}.
static func cancel_recruit(state,army_id: String,index: int) -> Dictionary:
 var a = army(state,army_id)
 if index<0 or index>=a.queue.size(): return {"gold":0,"men":0}
 var q = a.queue[index]
 a.queue.remove_at(index)
 state.treasury[a.faction] += int(q.cost)
 load("res://core/resources.gd").refund(state,a.faction,q.get("materials",{}))
 state.settlements[q.settlement].population = float(state.settlements[q.settlement].population)+int(q.men)
 var cap = capacity(state,army_id)
 for i in a.queue.size():
  var e = a.queue[i]
  var now = overflow_turns(i,cap)
  if now<int(e.get("extra",0)):
   e.turns_left = maxi(1,int(e.turns_left)-(int(e.extra)-now))
   e.extra = now
 return {"gold":int(q.cost),"men":int(q.men)}

# End Turn: queued units count down; finished ones join their army at full strength.
static func advance_queues(state) -> Array:
 var done = []
 var ids = state.army_state.keys()
 ids.sort()
 for id in ids:
  var a = state.army_state[id]
  var keep = []
  for q in a.queue:
   q.turns_left = int(q.turns_left)-1
   if q.turns_left>0:
    keep.append(q)
    continue
   a.units.append({"unit":q.unit,"men":int(q.men),"max_men":int(UnitTypes.get_type(q.unit).size)})
   done.append({"army":id,"unit":q.unit,"faction":a.faction})
  a.queue = keep
 return done

# Disband a unit: its surviving men return to the population of the region the army stands in
# (lost if that region has no settlement). Returns {men, settlement}.
static func disband(state,army_id: String,index: int) -> Dictionary:
 var a = army(state,army_id)
 if index<0 or index>=a.units.size(): return {"men":0,"settlement":""}
 var u = a.units[index]
 a.units.remove_at(index)
 var region = WorldMap.region_at(Movement.position(state,army_id))
 var sid = region if state.settlements.has(region) else ""
 if sid != "": state.settlements[sid].population = float(state.settlements[sid].population)+int(u.men)
 return {"men":int(u.men),"settlement":sid}

# --- Replenishment --------------------------------------------------------------------

# Owner of the region an army stands in ("" for unclaimed land such as the Greyspine).
static func region_owner(state,army_id: String) -> String:
 var region = WorldMap.region_at(Movement.position(state,army_id))
 if state.settlements.has(region): return state.settlements[region].owner
 return WorldMap.owner_of(region)

# Fraction of max strength regained this turn, and the gold per man (0 in friendly regions).
static func replenish_rate(state,army_id: String) -> Dictionary:
 var r = data().replenishment
 var a = army(state,army_id)
 var region = WorldMap.region_at(Movement.position(state,army_id))
 if region_owner(state,army_id) == a.faction:
  var pop = float(state.settlements[region].population) if state.settlements.has(region) else 0.0
  return {"rate":float(r.friendly_rate)+float(r.populous_bonus)*clampf(pop/float(r.populous_reference),0,1),"gold_per_man":0.0,"friendly":true}
 return {"rate":float(r.enemy_rate),"gold_per_man":float(r.enemy_gold_per_man),"friendly":false}

# End Turn: every unit below max strength regains men; never draws population (constitution).
static func replenish(state) -> Dictionary:
 var out = {}
 var ids = state.army_state.keys()
 ids.sort()
 for id in ids:
  var a = state.army_state[id]
  var r = replenish_rate(state,id)
  var gained = 0
  var spent = 0
  for u in a.units:
   var missing = int(u.max_men)-int(u.men)
   if missing<=0: continue
   var gain = mini(missing,int(ceil(float(u.max_men)*r.rate)))
   if r.gold_per_man>0:
    gain = mini(gain,int(floor(float(state.treasury.get(a.faction,0))/r.gold_per_man)))
    if gain<=0: continue
    var cost = int(ceil(gain*r.gold_per_man))
    state.treasury[a.faction] -= cost
    spent += cost
   u.men = int(u.men)+gain
   gained += gain
  if gained>0: out[id] = {"men":gained,"gold":spent,"friendly":r.friendly}
 return out

# --- New armies ------------------------------------------------------------------------

static func armies_of(state,faction: String) -> Array:
 var out = []
 for id in state.army_state:
  if state.army_state[id].faction == faction: out.append(id)
 out.sort()
 return out

# STUB name: a culture given name plus the faction's house (data/names.json), unique among
# living generals, drawn from a generator seeded by the campaign seed, year and faction.
static func general_name(state,faction: String) -> String:
 # Maps whose factions carry their culture and house (Varos) name generals from the culture's pool.
 var wf = WorldMap.faction(faction)
 if not names().factions.has(faction) and names().cultures.has(str(wf.get("culture",""))):
  return _named(state,faction,names().cultures[wf.culture],str(wf.get("house",wf.get("name",faction))))
 var f = names().factions.get(faction,{"culture":names().cultures.keys()[0],"house":WorldMap.faction(faction).get("name",faction)})
 var c = names().cultures[f.culture]
 var used = {}
 for id in state.army_state: used[state.army_state[id].commander.name] = true
 var rng = RandomNumberGenerator.new()
 rng.seed = hash([state.seed,state.year,faction,state.army_state.size()])
 var name = ""
 for i in 50:
  name = c.pattern.replace("{given}",c.given[rng.randi_range(0,c.given.size()-1)]).replace("{house}",f.house)
  if not used.has(name): return name
 return name+" the Younger"

static func can_raise(state,faction: String,settlement_id: String) -> Dictionary:
 var reasons = []
 var r = data().armies
 if not state.settlements.has(settlement_id) or state.settlements[settlement_id].owner != faction: return {"ok":false,"reasons":["Not your settlement"]}
 var cap = lord_army_cap(state,faction)
 if lord_armies(state,faction).size()>=cap: reasons.append("Army limit reached (%d lord armies at your Realm Standing)" % cap)
 if not Movement.garrison_of(state,settlement_id).is_empty(): reasons.append("An army is already garrisoned here")
 if int(state.treasury.get(faction,0))<0: reasons.append("In debt: no new armies until the treasury is out of debt")
 elif int(state.treasury.get(faction,0))<int(r.general_cost): reasons.append("Not enough gold (%d needed)" % int(r.general_cost))
 return {"ok":reasons.is_empty(),"reasons":reasons}

# Lord-led armies (detachments under captains do not count; game-design §12.3).
static func lord_armies(state,faction: String) -> Array:
 return armies_of(state,faction).filter(func(id): return not bool(state.army_state[id].get("captain",false)))

# The lord-army cap: Realm Standing (game-design §11.6, war-and-realm §2.5), never above the
# max_per_faction override (soak scaling) when that is set higher than the default.
static func lord_army_cap(state,faction: String) -> int:
 if state.get("courts") == null or state.courts.is_empty(): return int(data().armies.max_per_faction)
 var c = load("res://core/realm_standing.gd").cap(state,faction,"lord_armies")
 return maxi(c,int(data().armies.max_per_faction)) if int(data().armies.max_per_faction)>3 else c

# Court members who could lead a new army: idle adults, generals first.
static func general_candidates(state,faction: String) -> Array:
 if state.get("courts") == null or state.courts.is_empty(): return []
 var C = load("res://core/court.gd")
 var out = C.members(state,faction).filter(func(id):
  var c = state.characters[id]
  return C.is_adult(c) and str(c.army) == "" and not str(c.role).begins_with("prisoner") and str(c.role) != "exile" and int(c.defeated_until)<0)
 out.sort_custom(func(a,b):
  var ca = state.characters[a]
  var cb = state.characters[b]
  if (ca.career == "general") != (cb.career == "general"): return ca.career == "general"
  if (C.ruler(state,faction) == a) != (C.ruler(state,faction) == b): return C.ruler(state,faction) != a
  return int(ca.level)>int(cb.level) or (int(ca.level) == int(cb.level) and a<b))
 return out

# Hire a general at a settlement: a new army, garrisoned there with no units yet. The general comes from
# the court (character, or the best idle adult); with nobody free a lesser noble joins to lead it.
static func raise_army(state,faction: String,settlement_id: String,character := "") -> Dictionary:
 var check = can_raise(state,faction,settlement_id)
 if not check.ok: return check
 var n = 1
 while state.army_state.has("%s_army_%d" % [faction,n]): n += 1
 var id = "%s_army_%d" % [faction,n]
 var name = general_name(state,faction)
 var cid = ""
 if state.get("courts") != null and not state.courts.is_empty():
  var C = load("res://core/court.gd")
  var cands = general_candidates(state,faction)
  cid = character if character in cands else (cands[0] if not cands.is_empty() else "")
  if cid == "": cid = C.new_character(state,faction,{"name":name.split(" ")[maxi(0,name.split(" ").size()-2)] if name.split(" ").size()>1 else name,"gender":"m","age":26.0,"career":"general","loyalty":int(C.data().loyalty.courtier_start)})
  name = C.full_name(state.characters[cid])
 var a = Movement.new_army_state(faction,WorldMap.settlement_position(settlement_id))
 a.merge({"display_name":"Army of %s" % name,"commander":{"name":name,"rank":maxi(1,int(state.characters[cid].level) if cid != "" else 1),"character":cid},"units":[],"queue":[]})
 a.garrison = settlement_id
 state.treasury[faction] -= int(data().armies.general_cost)
 state.army_state[id] = a
 state.armies.append(id)
 if cid != "":
  state.characters[cid].army = id
  load("res://core/court.gd").set_role(state,cid,"general:"+id)
 return {"ok":true,"reasons":[],"army":id,"name":name,"character":cid}

# --- Helpers for the campaign AI (core/ai.gd) -----------------------------------------------

static func capital(state,faction: String) -> String:
 var best = ""
 for id in state.settlements_of(faction):
  if best == "" or float(state.settlements[id].population)>float(state.settlements[best].population): best = id
 return best


static func _named(state,faction: String,c: Dictionary,house: String) -> String:
 var used = {}
 for id in state.army_state: used[state.army_state[id].commander.name] = true
 var rng = RandomNumberGenerator.new()
 rng.seed = hash([state.seed,state.year,faction,state.army_state.size()])
 var name = ""
 for i in 50:
  name = str(c.pattern).replace("{given}",c.given[rng.randi_range(0,c.given.size()-1)]).replace("{house}",house)
  if not used.has(name): return name
 return name+" the Younger"
