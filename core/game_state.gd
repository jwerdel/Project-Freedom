extends RefCounted
# Mutable campaign state: calendar, faction treasuries, settlements (owner, type, level,
# population, buildings), armies, and the chronicle log. Built from data/campaign_start.json
# plus the world data in data/provinces.json. Systems change it; the UI reads it via UiData.

const WorldMap = preload("res://core/world_map.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const START = "res://data/campaign_start.json"

var seed := 0
var year := 1
var turn := 1
var player_faction := ""
var treasury = {}     # faction id -> int gold
var settlements = {}  # settlement id -> {owner, type, level, population (float), buildings, resources}
var armies = []       # army ids (data/armies/)
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
   "population":float(start.get("population",0)),"buildings":start.get("buildings",[]).duplicate(true),
   "resources":r.get("resources",{}).duplicate()}
 s.armies = data.get("armies",[]).duplicate()
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
  if UnitTypes.army(id).faction == faction: out.append(id)
 return out

# Everything that defines the state, for determinism checks and later save/load.
func to_dict() -> Dictionary:
 return {"seed":seed,"year":year,"turn":turn,"player_faction":player_faction,"treasury":treasury.duplicate(true),"settlements":settlements.duplicate(true),"armies":armies.duplicate(),"chronicle":chronicle.duplicate(true)}
