extends RefCounted
# The land of each region and its culture (owner decision 2026-10-04, game-design §12.13 C;
# constitution, Economy and settlements). state.land[region] = {from, to, value, built}: the land
# is `from` turning into `to`, `value` of the way (1 = fully `to`). A region starts as its owner's
# culture. When an owner of another culture holds it, each End Turn moves it toward the owner's
# culture by 1/full_turns, plus per_building for every building the owner completed there since;
# retaking it starts converting it back. The climate yield factor (game-design §10.9) follows the
# same mix: an owner on land of another culture earns foreign_yield, rising to 1 as it converts.
# Numbers in data/cultures.json (placeholders).

const WorldMap = preload("res://core/world_map.gd")
const CULTURES = "res://data/cultures.json"

static var _data = null

static func data() -> Dictionary:
 if _data == null: _data = JSON.parse_string(FileAccess.get_file_as_string(CULTURES))
 return _data

static func faction_culture(faction: String) -> String:
 var c = str(WorldMap.faction(faction).get("culture",""))
 return c if data().cultures.has(c) else str(data().default)

# Every settled region's land starts as its owner's culture.
static func init(state):
 state.land = {}
 for sid in state.settlements:
  var c = faction_culture(state.settlements[sid].owner)
  state.land[sid] = {"from":c,"to":c,"value":1.0,"built":0}

static func entry(state,sid: String) -> Dictionary:
 if not state.land.has(sid):
  var c = faction_culture(state.settlements[sid].owner)
  state.land[sid] = {"from":c,"to":c,"value":1.0,"built":0}
 return state.land[sid]

# The share of a culture in a region's land (0-1).
static func share(state,sid: String,culture: String) -> float:
 var e = entry(state,sid)
 var v = float(e.value)
 var s = 0.0
 if e.to == culture: s += v
 if e.from == culture: s += 1.0-v
 return clampf(s,0.0,1.0)

# Climate yield factor for the settlement's owner (game-design §10.9).
static func climate_factor(state,sid: String) -> float:
 var own = share(state,sid,faction_culture(state.settlements[sid].owner))
 return lerpf(float(data().climate.foreign_yield),1.0,own)

# 0 none, 1 noticeable, 2 very noticeable, 3 converted (the owner's thresholds, in turns).
static func stage(state,sid: String) -> int:
 var e = entry(state,sid)
 if e.from == e.to or float(e.value)>=1.0: return 3
 var c = data().conversion
 var turns = float(e.value)*float(c.full_turns)
 if turns>=float(c.very_turns): return 2
 if turns>=float(c.noticeable_turns): return 1
 return 0

# Point a region's land at its owner's culture after a change of hands: the mix continues from where
# it stands (retaking a half-converted region converts it back from that point).
static func retarget(state,sid: String):
 var e = entry(state,sid)
 var oc = faction_culture(state.settlements[sid].owner)
 if e.to == oc: return
 var v = float(e.value)
 if e.from == oc: state.land[sid] = {"from":e.to,"to":oc,"value":1.0-v,"built":0}
 else: state.land[sid] = {"from":e.to if v>=0.5 else e.from,"to":oc,"value":0.0,"built":0}

# End Turn: every region turns toward its owner's culture. completed: this turn's finished
# buildings (core/construction.gd advance), which speed up conversion where the owner built them.
static func end_turn(state,completed := []) -> Array:
 var c = data().conversion
 var changed = []
 var ids = state.settlements.keys()
 ids.sort()
 # Point every region at its owner first (a change of hands resets the count), then count the
 # owners' new buildings, then advance.
 for sid in ids: retarget(state,sid)
 for d in completed:
  if state.land.has(d.settlement) and state.settlements[d.settlement].owner == d.faction: state.land[d.settlement].built = int(state.land[d.settlement].built)+1
 for sid in ids:
  var e = state.land[sid]
  if e.from == e.to or float(e.value)>=1.0: continue
  var before = stage(state,sid)
  e.value = minf(1.0,float(e.value)+1.0/float(c.full_turns)+float(c.per_building)*int(e.built))
  if float(e.value)>=1.0:
   e.from = e.to
   e.value = 1.0
   e.built = 0
  if stage(state,sid) != before: changed.append({"settlement":sid,"stage":stage(state,sid),"culture":e.to})
 return changed
