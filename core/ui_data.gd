extends RefCounted
# The one data interface the campaign UI reads. Everything the panels show comes from here.
# Real systems: the campaign state (core/game_state.gd), economy (core/economy.gd), turn loop
# (core/turn_loop.gd) and chronicle, plus world data (factions, provinces, unit types, armies).
# Values with no system yet (public order) come from the clearly marked data/mock_ui.json.

signal changed
signal event_added(event: Dictionary)

const WorldMap = preload("res://core/world_map.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const GameState = preload("res://core/game_state.gd")
const Economy = preload("res://core/economy.gd")
const Buildings = preload("res://core/buildings.gd")
const Construction = preload("res://core/construction.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const Chronicle = preload("res://core/chronicle.gd")
const MOCK = "res://data/mock_ui.json"
const CATEGORIES = [{"id":"turn","name":"Turn Summary"},{"id":"buildings","name":"Buildings Constructed"},{"id":"war","name":"War Declared"},{"id":"world","name":"World Events"}]

var state
var mock: Dictionary
var last_turn_ms := 0.0

func _init(campaign_state = null,mock_path := MOCK):
 state = campaign_state if campaign_state != null else GameState.from_data()
 var data = JSON.parse_string(FileAccess.get_file_as_string(mock_path))
 assert(data is Dictionary and data.has("_MOCK"),"UI mock data must be marked with _MOCK: "+mock_path)
 mock = data

func is_mock() -> bool:
 return mock.has("_MOCK")

# --- Faction and resources ---------------------------------------------------

func player_faction_id() -> String:
 return state.player_faction

func faction(id: String) -> Dictionary:
 return WorldMap.faction(id)

func player_faction() -> Dictionary:
 return faction(player_faction_id())

# Treasury now, projected net income for the coming turn, population, calendar.
func resources() -> Dictionary:
 var f = player_faction_id()
 return {"treasury":int(state.treasury[f]),"income":int(Economy.faction_ledger(state,f).net),"population":state.population_of(f),"year":state.year,"turn":state.turn}

# Per-turn income sources and expenses of the player faction, with readable labels.
func income_breakdown(faction_id := "") -> Dictionary:
 var f = faction_id if faction_id != "" else player_faction_id()
 var ledger = Economy.faction_ledger(state,f)
 var out = {"income":[],"expenses":[],"income_total":ledger.income_total,"expense_total":ledger.expense_total,"net":ledger.net,"treasury":int(state.treasury[f])}
 for e in ledger.income: out.income.append({"label":"%s (%s)" % [WorldMap.region(e.label).settlement.name,state.settlements[e.label].type],"amount":e.amount})
 for e in ledger.expenses:
  var label = "Building upkeep: %s" % WorldMap.region(e.label).settlement.name if e.kind == "buildings" else "Army upkeep: %s" % UnitTypes.army(e.label).display_name
  out.expenses.append({"label":label,"amount":e.amount})
 return out

# Advance one year through the turn loop; new chronicle entries go to Event Messages.
func end_turn():
 var t0 = Time.get_ticks_usec()
 var report = TurnLoop.end_turn(state)
 last_turn_ms = (Time.get_ticks_usec()-t0)/1000.0
 for e in report.entries: event_added.emit(e)
 changed.emit()
 return report

# --- Event messages and chronicle ------------------------------------------------

func event_categories() -> Array:
 return CATEGORIES

# Event Messages: building completions only for the player's own settlements (the chronicle keeps all).
func events(category: String) -> Array:
 var out = []
 for e in state.chronicle:
  if e.category == category and e.get("faction",state.player_faction) == state.player_faction: out.append(e)
 out.reverse() # newest first
 return out

func chronicle() -> Array:
 var out = state.chronicle.duplicate()
 out.reverse()
 return out

func add_event(category: String,title: String,text := ""):
 var e = Chronicle.entry(state.year,category,title,text)
 state.chronicle.append(e)
 event_added.emit(e)

# --- Provinces and settlements -----------------------------------------------

func settlement_ids() -> Array:
 return WorldMap.settlement_ids()

func settlement(id: String) -> Dictionary:
 var r = WorldMap.region(id)
 if r.is_empty() or r.settlement == null: return {}
 var s = r.settlement.duplicate(true)
 var live = state.settlements[id]
 s.id = id
 s.level = int(live.level)
 s.type = live.type
 s.owner = live.owner
 s.population = int(round(live.population))
 s.faction = faction(live.owner)
 s.province = WorldMap.province_of(id)
 s.province_name = WorldMap.province(s.province).name
 s.defense = int(live.defense)
 s.player_owned = live.owner == state.player_faction
 return s

# Developer override (prototype keys, capture flags): sets the main building level directly.
func set_settlement_level(id: String,level: int):
 Construction.set_level(state,id,level)
 changed.emit()

# Growth-stage visual of a settlement: {stage, generic}; see AssetManifest.settlement_stage_path.
func settlement_visual_stage(id: String) -> Dictionary:
 return Construction.visual_stage(state,id)

func province(id: String) -> Dictionary:
 return WorldMap.province(id)

func settlements_in_province(province_id: String) -> Array:
 return WorldMap.settlements_in(province_id)

# Real income, growth and population summed over the province; public order is still mock.
func province_stats(province_id: String) -> Dictionary:
 var out = {"growth":0,"income":0,"public_order":0,"population":0,"public_order_is_mock":true}
 var ids = settlements_in_province(province_id)
 var growth = 0.0
 for id in ids:
  out.income += Economy.settlement_income(state,id).total
  growth += Economy.growth(state,id).delta
  out.population += int(round(state.settlements[id].population))
  out.public_order += int(mock.public_order.get(id,0))
 out.growth = int(round(growth))
 if ids.size()>0: out.public_order = int(out.public_order/ids.size())
 return out

# Building slots of a settlement as card views: {slot, chain, name, visual, level, max_level, main,
# effects}, {slot, empty}, or {locked, requires} for slots a higher settlement level would open.
# A slot under construction also carries "construction" (see construction()).
func building_slots(settlement_id: String) -> Array:
 var s = state.settlements[settlement_id]
 var pending = construction(settlement_id)
 var out = []
 for i in s.buildings.size():
  var b = s.buildings[i]
  var view = {"slot":i,"empty":true}
  if b.has("chain"):
   var c = Buildings.chain(b.chain)
   view = {"slot":i,"chain":b.chain,"name":b.get("name",Buildings.building_name(settlement_id,b.chain,int(b.level))),"visual":c.visual,
    "level":int(b.level),"max_level":Buildings.max_level(b.chain),"main":c.get("main",false),"effects":Buildings.effect_lines(b.chain,int(b.level))}
  if not pending.is_empty() and pending.slot == i:
   view.construction = pending
   if view.has("empty"):
    view.erase("empty")
    view.merge({"chain":pending.chain,"name":pending.name,"visual":Buildings.chain(pending.chain).visual,"level":0,"max_level":Buildings.max_level(pending.chain),"main":false,"effects":[]})
  out.append(view)
 var main = Buildings.main_chain_id(s.type)
 for level in range(int(s.level)+1,Buildings.max_level(main)+1):
  for i in Buildings.slot_count(s.type,level)-Buildings.slot_count(s.type,level-1):
   out.append({"locked":true,"requires":"%s (settlement level %d)" % [Buildings.building_name(settlement_id,main,level),level]})
 return out

func settlement_defense(settlement_id: String) -> int:
 return int(state.settlements[settlement_id].defense)

# --- Construction --------------------------------------------------------------

# The settlement's construction in progress, or {}: {slot, chain, name, level, turns_left,
# turns_total, cost, progress (0..1), refund (gold if cancelled now)}.
func construction(settlement_id: String) -> Dictionary:
 var c = Construction.in_progress(state,settlement_id)
 if c.is_empty(): return {}
 return {"slot":int(c.slot),"chain":c.chain,"name":Buildings.building_name(settlement_id,c.chain,int(c.level)),"level":int(c.level),
  "turns_left":int(c.turns_left),"turns_total":int(c.turns_total),"cost":int(c.cost),
  "progress":1.0-float(c.turns_left)/maxf(1.0,float(c.turns_total)),"refund":Construction.refund_amount(state,settlement_id)}

# Building browser entries for a slot (see Construction.options); only the owner may build.
func building_options(settlement_id: String,slot: int) -> Array:
 var out = Construction.options(state,settlement_id,slot)
 if state.settlements[settlement_id].owner != state.player_faction:
  for o in out:
   o.available = false
   o.reasons = ["Not your settlement"]+o.reasons
 return out

func start_construction(settlement_id: String,slot: int,chain_id: String) -> Dictionary:
 if state.settlements[settlement_id].owner != state.player_faction: return {"ok":false,"reasons":["Not your settlement"]}
 var r = Construction.start(state,settlement_id,slot,chain_id)
 if r.ok: changed.emit()
 return r

func cancel_construction(settlement_id: String) -> int:
 if state.settlements[settlement_id].owner != state.player_faction: return 0
 var refund = Construction.cancel(state,settlement_id)
 changed.emit()
 return refund

# --- Armies and units --------------------------------------------------------

func army(id: String) -> Dictionary:
 var a = UnitTypes.army(id)
 a.faction_data = faction(a.faction)
 a.upkeep = Economy.army_upkeep(id)
 return a

func unit_type(id: String) -> Dictionary:
 return UnitTypes.get_type(id)
