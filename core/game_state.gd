extends RefCounted
# Mutable campaign state: calendar, faction treasuries, settlements (owner, type, level,
# population, buildings), armies, and the chronicle log. Built from data/campaign_start.json
# plus the world data in data/provinces.json. Systems change it; the UI reads it via UiData.

const WorldMap = preload("res://core/world_map.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const Buildings = preload("res://core/buildings.gd")
const Movement = preload("res://core/movement.gd")
const Armies = preload("res://core/armies.gd")
const START = "res://data/campaign_start.json"

var seed := 0
var year := 1
var turn := 1
var player_faction := ""
var treasury = {}     # faction id -> int gold
var settlements = {}  # settlement id -> {owner, type, level, population (float), buildings (slots), construction, resources, defense, unlocks}
var armies = []       # army ids (data/armies/)
var army_state = {}   # army id -> army: composition and queue (core/armies.gd) plus movement (core/movement.gd)
var wars = []        # faction pairs at war, "a|b" sorted (core/battles.gd; temporary rule until diplomacy)
var battles := 0     # battles fought so far (part of each battle's seed)
var road_level := 0   # road network level: 0 dirt, 1 gravel, 2 stone
var chronicle = []    # {year, category, title, text}
var last_ledgers = {} # faction id -> ledger of the last processed turn

static func from_data(path := START) -> RefCounted:
 var data = JSON.parse_string(FileAccess.get_file_as_string(path))
 assert(data is Dictionary and data.has("settlements"),"Invalid campaign start: "+path)
 var s = load("res://core/game_state.gd").new()
 s.seed = int(data.seed)
 s.year = int(data.year)
 s.turn = 1
 s.player_faction = data.player_faction
 for f in WorldMap.factions(): s.treasury[f] = int(data.treasury.get(f,0))
 for id in WorldMap.settlement_ids():
  var r = WorldMap.region(id)
  var start = data.settlements.get(id,{})
  s.settlements[id] = {
   "owner":r.owner,"type":r.settlement.type,"level":int(r.settlement.level),
   "population":float(start.get("population",0)),"buildings":starting_slots(id,r.settlement.type,int(r.settlement.level),start.get("buildings",[])),
   "construction":{},"coastal":bool(r.settlement.get("coastal",false)),"resources":r.get("resources",{}).duplicate()}
  Buildings.refresh(s,id)
 s.armies = data.get("armies",[]).duplicate()
 s.road_level = int(data.get("road_level",0))
 for id in s.armies:
  var p = data.get("army_positions",{}).get(id,[0,0])
  var a = Armies.from_data(id)
  var pos = Vector2(p[0],p[1])
  a.merge(Movement.new_army_state(a.faction,pos))
  # An army starting on its own settlement starts garrisoned there.
  var at = Movement.settlement_at(pos)
  if at != "" and s.settlements[at].owner == a.faction: a.garrison = at
  s.army_state[id] = a
 s.chronicle = load("res://core/chronicle.gd").opening_entries()
 return s

func factions() -> Array:
 var out = treasury.keys()
 out.sort()
 return out

func settlements_of(faction: String) -> Array:
 var out = []
 for id in settlements:
  if settlements[id].owner == faction: out.append(id)
 out.sort()
 return out

func population_of(faction: String) -> int:
 var total = 0.0
 for id in settlements_of(faction): total += settlements[id].population
 return int(round(total))

func armies_of(faction: String) -> Array:
 var out = []
 for id in armies:
  if army_state[id].faction == faction: out.append(id)
 return out

# Everything that defines the state, for determinism checks and later save/load.
func to_dict() -> Dictionary:
 return {"seed":seed,"year":year,"turn":turn,"player_faction":player_faction,"treasury":treasury.duplicate(true),"settlements":settlements.duplicate(true),"armies":armies.duplicate(),"army_state":army_state.duplicate(true),"road_level":road_level,"wars":wars.duplicate(),"battles":battles,"chronicle":chronicle.duplicate(true)}

# Slot list of a starting settlement: the main building (at the settlement's level) in slot 0, the
# start file's other buildings ({chain, level[, name]}), then empty slots up to the slot count.
static func starting_slots(id: String,type: String,level: int,listed: Array) -> Array:
 var slots = [{"chain":Buildings.main_chain_id(type),"level":level}]
 for b in listed:
  assert(not Buildings.is_main(b.chain),"%s: the main building is implied, do not list %s" % [id,b.chain])
  assert(int(b.level)>=1 and int(b.level)<=mini(level,Buildings.max_level(b.chain)),"%s: %s level %d exceeds settlement level %d" % [id,b.chain,int(b.level),level])
  slots.append(b.duplicate())
 var count = Buildings.slot_count(type,level)
 assert(slots.size()<=count,"%s: %d buildings but only %d slots" % [id,slots.size(),count])
 while slots.size()<count: slots.append({})
 return slots
