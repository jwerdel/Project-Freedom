extends RefCounted
# The one data interface the campaign UI reads. Everything the panels show comes from here.
# World data (factions, provinces, unit types, armies) is real data; economy, events, province
# stats and building slots come from the clearly marked mock file data/mock_ui.json until real
# systems exist. Swapping in a system means changing this class, not the UI.

signal changed
signal event_added(event: Dictionary)

const WorldMap = preload("res://core/world_map.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const MOCK = "res://data/mock_ui.json"

var mock: Dictionary
var settlement_levels = {} # live overrides, e.g. Greyhaven's stage from the map

func _init(path := MOCK):
 var data = JSON.parse_string(FileAccess.get_file_as_string(path))
 assert(data is Dictionary and data.has("_MOCK"),"UI mock data must be marked with _MOCK: "+path)
 mock = data.duplicate(true)

func is_mock() -> bool:
 return mock.has("_MOCK")

# --- Faction and resources ---------------------------------------------------

func player_faction_id() -> String:
 return mock.player_faction

func faction(id: String) -> Dictionary:
 return WorldMap.faction(id)

func player_faction() -> Dictionary:
 return faction(player_faction_id())

func resources() -> Dictionary:
 return {"treasury":int(mock.treasury),"income":int(mock.income_per_turn),"population":int(mock.population),"year":int(mock.year),"turn":int(mock.turn)}

# Advance the calendar by one year (one turn = one year). No other mechanics run.
func end_turn():
 mock.year = int(mock.year)+1
 mock.turn = int(mock.turn)+1
 add_event("turn","Year %d begins" % mock.year,"The %s turn has begun." % _ordinal(int(mock.turn)))
 changed.emit()

# --- Event messages ----------------------------------------------------------

func event_categories() -> Array:
 return mock.event_categories

func events(category: String) -> Array:
 var out = []
 for e in mock.events:
  if e.category == category: out.append(e)
 out.reverse() # newest first
 return out

func add_event(category: String,title: String,text := ""):
 var e = {"category":category,"title":title,"text":text,"year":int(mock.year)}
 mock.events.append(e)
 event_added.emit(e)

# --- Provinces and settlements -----------------------------------------------

func settlement_ids() -> Array:
 return WorldMap.settlement_ids()

func settlement(id: String) -> Dictionary:
 var r = WorldMap.region(id)
 if r.is_empty() or r.settlement == null: return {}
 var s = r.settlement.duplicate(true)
 s.id = id
 s.level = int(settlement_levels.get(id,s.level))
 s.owner = r.owner
 s.faction = faction(r.owner)
 s.province = WorldMap.province_of(id)
 s.province_name = WorldMap.province(s.province).name
 return s

func set_settlement_level(id: String,level: int):
 settlement_levels[id] = level
 changed.emit()

func province(id: String) -> Dictionary:
 return WorldMap.province(id)

func settlements_in_province(province_id: String) -> Array:
 return WorldMap.settlements_in(province_id)

# Mock growth / income / public order, summed over the province's settlements.
func province_stats(province_id: String) -> Dictionary:
 var out = {"growth":0,"income":0,"public_order":0,"population":0}
 var ids = settlements_in_province(province_id)
 for id in ids:
  var r = mock.regions.get(id,{})
  for k in out: out[k] += int(r.get(k,0))
 if ids.size()>0: out.public_order = int(out.public_order/ids.size())
 return out

# Building slots of a settlement: {name, visual, level} cards, {empty}, or {locked, requires}.
func building_slots(settlement_id: String) -> Array:
 return mock.regions.get(settlement_id,{}).get("buildings",[])

# --- Armies and units --------------------------------------------------------

func army(id: String) -> Dictionary:
 var a = UnitTypes.army(id)
 a.faction_data = faction(a.faction)
 return a

func unit_type(id: String) -> Dictionary:
 return UnitTypes.get_type(id)

func _ordinal(n: int) -> String:
 var suffix = "th"
 if n%100<11 or n%100>13: suffix = {1:"st",2:"nd",3:"rd"}.get(n%10,"th")
 return "%d%s" % [n,suffix]
