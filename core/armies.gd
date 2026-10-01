extends RefCounted
# Armies as campaign state (state.army_state[id], shared with core/movement.gd): composition,
# recruitment queue, disbanding, replenishment, raising new armies, and a placeholder AI.
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
# OPEN (not implemented): recruitment slots per settlement, global recruitment, raise banners,
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

# Starting composition from data/armies/<id>.json ("strength" is the fraction of full size).
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

# The own settlement this army can recruit at: where it is garrisoned, else the nearest own
# settlement within the adjacent radius; "" if none.
static func recruit_settlement(state,army_id: String) -> String:
 var a = army(state,army_id)
 if a.garrison != "" and state.settlements[a.garrison].owner == a.faction: return a.garrison
 var at = Movement.position(state,army_id)
 var best = ""
 var best_d = float(data().recruitment.adjacent_radius)
 for id in WorldMap.settlement_ids():
  if state.settlements[id].owner != a.faction: continue
  var d = WorldMap.settlement_position(id).distance_to(at)
  if d<=best_d:
   best = id
   best_d = d
 return best

static func recruitable_types() -> Array:
 var out = []
 for id in UnitTypes.ids():
  if UnitTypes.get_type(id).recruitment != null: out.append(id)
 return out

# The building level that unlocks a unit, for locked reasons ("Requires Barracks: Garrison").
static func unlocked_by(unit_id: String) -> String:
 for c in Buildings.chain_ids():
  var ch = Buildings.chain(c)
  for i in ch.levels.size():
   if unit_id in ch.levels[i].effects.get("unlocks",[]): return "%s: %s" % [ch.name,ch.levels[i].name]
 return "a building"

static func can_recruit(state,army_id: String,unit_id: String) -> Dictionary:
 var a = army(state,army_id)
 var sid = recruit_settlement(state,army_id)
 if sid == "": return {"ok":false,"reasons":["Must be in or next to one of your settlements"],"settlement":""}
 var u = UnitTypes.get_type(unit_id)
 if u.recruitment == null: return {"ok":false,"reasons":["Cannot be recruited"],"settlement":sid}
 var s = state.settlements[sid]
 var reasons = []
 if not unit_id in s.get("unlocks",[]): reasons.append("Requires %s" % unlocked_by(unit_id))
 if card_count(a)+1>max_units(): reasons.append("Army is full (%d units)" % max_units())
 if int(state.treasury.get(a.faction,0))<int(u.recruitment.cost): reasons.append("Not enough gold (%d needed)" % int(u.recruitment.cost))
 if float(s.population)-int(u.size)<float(data().recruitment.min_population):
  reasons.append("Too few people in %s (keeps at least %d)" % [WorldMap.region(sid).settlement.name,int(data().recruitment.min_population)])
 return {"ok":reasons.is_empty(),"reasons":reasons,"settlement":sid}

# Recruitment panel entries: every recruitable unit type with cost, turns, upkeep, men and reasons.
static func options(state,army_id: String) -> Array:
 var out = []
 for id in recruitable_types():
  var u = UnitTypes.get_type(id)
  var check = can_recruit(state,army_id,id)
  out.append({"unit":id,"name":u.display_name,"cost":int(u.recruitment.cost),"turns":int(u.recruitment.turns),
   "upkeep":int(round(float(u.placeholder_stats.upkeep)*float(Economy.data().upkeep.army_upkeep_multiplier))),"men":int(u.size),
   "available":check.ok,"reasons":check.reasons,"settlement":check.settlement})
 return out

# Queue a unit: gold and men are taken now. Returns {ok, reasons}.
static func recruit(state,army_id: String,unit_id: String) -> Dictionary:
 var check = can_recruit(state,army_id,unit_id)
 if not check.ok: return check
 var a = army(state,army_id)
 var u = UnitTypes.get_type(unit_id)
 state.treasury[a.faction] -= int(u.recruitment.cost)
 state.settlements[check.settlement].population = float(state.settlements[check.settlement].population)-int(u.size)
 a.queue.append({"unit":unit_id,"settlement":check.settlement,"turns_left":int(u.recruitment.turns),"turns_total":int(u.recruitment.turns),"cost":int(u.recruitment.cost),"men":int(u.size)})
 return check

# Cancel a queued unit: full refund of gold and men. Returns {gold, men}.
static func cancel_recruit(state,army_id: String,index: int) -> Dictionary:
 var a = army(state,army_id)
 if index<0 or index>=a.queue.size(): return {"gold":0,"men":0}
 var q = a.queue[index]
 a.queue.remove_at(index)
 state.treasury[a.faction] += int(q.cost)
 state.settlements[q.settlement].population = float(state.settlements[q.settlement].population)+int(q.men)
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
 if armies_of(state,faction).size()>=int(r.max_per_faction): reasons.append("Army limit reached (%d, placeholder)" % int(r.max_per_faction))
 if not Movement.garrison_of(state,settlement_id).is_empty(): reasons.append("An army is already garrisoned here")
 if int(state.treasury.get(faction,0))<int(r.general_cost): reasons.append("Not enough gold (%d needed)" % int(r.general_cost))
 return {"ok":reasons.is_empty(),"reasons":reasons}

# Hire a general at a settlement: a new army, garrisoned there with no units yet.
static func raise_army(state,faction: String,settlement_id: String) -> Dictionary:
 var check = can_raise(state,faction,settlement_id)
 if not check.ok: return check
 var n = 1
 while state.army_state.has("%s_army_%d" % [faction,n]): n += 1
 var id = "%s_army_%d" % [faction,n]
 var name = general_name(state,faction)
 var a = Movement.new_army_state(faction,WorldMap.settlement_position(settlement_id))
 a.merge({"display_name":"Army of %s" % name,"commander":{"name":name,"rank":1},"units":[],"queue":[]})
 a.garrison = settlement_id
 state.treasury[faction] -= int(data().armies.general_cost)
 state.army_state[id] = a
 state.armies.append(id)
 return {"ok":true,"reasons":[],"army":id,"name":name}

# --- PLACEHOLDER AI --------------------------------------------------------------------

static func capital(state,faction: String) -> String:
 var best = ""
 for id in state.settlements_of(faction):
  if best == "" or float(state.settlements[id].population)>float(state.settlements[best].population): best = id
 return best

# Keep one defensive garrison army at the capital (see data/recruitment.json ai). Returns actions.
static func ai_turn(state,faction: String) -> Array:
 var ai = data().ai
 var actions = []
 var home = capital(state,faction)
 if home == "": return actions
 var garrison = ""
 for id in Movement.garrison_of(state,home):
  if state.army_state[id].faction == faction: garrison = id
 var reserve = int(ai.reserve_gold)
 if garrison == "":
  if int(state.treasury[faction])-int(data().armies.general_cost)<reserve or not can_raise(state,faction,home).ok: return actions
  var r = raise_army(state,faction,home)
  actions.append({"action":"raise","army":r.army,"faction":faction})
  garrison = r.army
 var a = state.army_state[garrison]
 for n in int(ai.max_recruits_per_turn):
  if a.units.size()+a.queue.size()>=int(ai.garrison_units): break
  var net = Economy.faction_ledger(state,faction).net
  var best = {}
  for o in options(state,garrison):
   if not o.available or int(state.treasury[faction])-o.cost<reserve or net-o.upkeep<0: continue
   if best.is_empty() or o.cost<best.cost or (o.cost == best.cost and o.unit<best.unit): best = o
  if best.is_empty(): break
  recruit(state,garrison,best.unit)
  actions.append({"action":"recruit","army":garrison,"unit":best.unit,"faction":faction})
 return actions
