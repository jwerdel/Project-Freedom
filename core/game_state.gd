extends RefCounted
# Mutable campaign state: calendar, faction treasuries, settlements (owner, type, level,
# population, buildings), armies, and the chronicle log. Built from the active map's
# campaign_start.json plus its world data (data/maps/<id>/, core/map_registry.gd). Systems change it; the UI reads it via UiData.

const WorldMap = preload("res://core/world_map.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const Buildings = preload("res://core/buildings.gd")
const Movement = preload("res://core/movement.gd")
const Armies = preload("res://core/armies.gd")
const MapRegistry = preload("res://core/map_registry.gd")
const START = "" # "" = the active map's campaign_start.json (see start_path)

var map_id := ""      # the map this campaign plays on (data/maps/<id>)
var map_version := 0 # its map.json version (saves from another version are refused)
var seed := 0
var year := 1
var turn := 1
var player_faction := ""
var treasury = {}     # faction id -> int gold
var settlements = {}  # settlement id -> {owner, type, level, population (float), buildings (slots), construction, resources, defense, unlocks}
var armies = []       # army ids (data/maps/<map>/armies/)
var army_state = {}   # army id -> army: composition and queue (core/armies.gd) plus movement (core/movement.gd)
var wars = []        # faction pairs at war, "a|b" sorted (core/battles.gd; temporary rule until diplomacy)
var battles := 0     # battles fought so far (part of each battle's seed)
var road_level := 0   # road network level: 0 dirt, 1 gravel, 2 stone
var chronicle = []    # {year, category, title, text}
var last_ledgers = {} # faction id -> ledger of the last processed turn
var pending_battles = [] # AI attacks on the human player awaiting the player's answer (pre-battle data)
var grace = {}      # faction -> End Turns left to retake a settlement (core/realm.gd)
var destroyed = []  # factions destroyed (loss condition)
var land = {}       # region -> {from, to, value, built}: its land's culture and conversion (core/land.gd)

# A new campaign with a random campaign seed (stored in the state; every later random draw is
# seeded from it, so a campaign replays exactly from its seed).
static func new_campaign(path := START) -> RefCounted:
 var rng = RandomNumberGenerator.new()
 rng.randomize()
 return from_data(path,rng.randi_range(1,2147483646))

# The starting state. campaign_seed 0 uses the start file's fixed seed (tests, self-test, captures).
static func start_path(path := START) -> String:
 return path if path != "" else MapRegistry.path("campaign_start.json")

static func from_data(path := START,campaign_seed := 0) -> RefCounted:
 path = start_path(path)
 var data = JSON.parse_string(FileAccess.get_file_as_string(path))
 assert(data is Dictionary and data.has("settlements"),"Invalid campaign start: "+path)
 var s = load("res://core/game_state.gd").new()
 s.map_id = MapRegistry.active
 s.map_version = MapRegistry.version()
 s.seed = campaign_seed if campaign_seed != 0 else int(data.seed)
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
 load("res://core/land.gd").init(s)
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

# Everything that defines the state: determinism checks and save files (core/save_system.gd).
# Nothing the campaign needs may live outside these fields.
func to_dict() -> Dictionary:
 return {"map_id":map_id,"map_version":map_version,"seed":seed,"year":year,"turn":turn,"player_faction":player_faction,"treasury":treasury.duplicate(true),"settlements":settlements.duplicate(true),"armies":armies.duplicate(),"army_state":army_state.duplicate(true),"road_level":road_level,"wars":wars.duplicate(),"battles":battles,"chronicle":chronicle.duplicate(true),"last_ledgers":last_ledgers.duplicate(true),"pending_battles":pending_battles.duplicate(true),"grace":grace.duplicate(),"destroyed":destroyed.duplicate(),"land":land.duplicate(true)}

# The inverse of to_dict (a loaded save).
static func from_dict(d: Dictionary) -> RefCounted:
 var s = load("res://core/game_state.gd").new()
 s.map_id = str(d.get("map_id",MapRegistry.DEFAULT))
 s.map_version = int(d.get("map_version",1))
 s.seed = int(d.seed)
 s.year = int(d.year)
 s.turn = int(d.turn)
 s.player_faction = str(d.player_faction)
 s.treasury = d.treasury.duplicate(true)
 s.settlements = d.settlements.duplicate(true)
 s.armies = d.armies.duplicate()
 s.army_state = d.army_state.duplicate(true)
 s.road_level = int(d.road_level)
 s.wars = d.wars.duplicate()
 s.battles = int(d.battles)
 s.chronicle = d.chronicle.duplicate(true)
 s.last_ledgers = d.get("last_ledgers",{}).duplicate(true)
 s.pending_battles = d.get("pending_battles",[]).duplicate(true)
 s.grace = d.get("grace",{}).duplicate()
 s.destroyed = d.get("destroyed",[]).duplicate()
 s.land = d.get("land",{}).duplicate(true)
 if s.land.is_empty(): load("res://core/land.gd").init(s) # saves from before land conversion
 return s

# A hash of the full state in its saved form: values, int/float types and dictionary order.
func state_hash() -> int:
 return load("res://core/save_codec.gd").to_json(to_dict()).hash()

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
