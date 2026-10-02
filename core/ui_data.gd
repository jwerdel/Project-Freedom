extends RefCounted
# The one data interface the campaign UI reads. Everything the panels show comes from here.
# Real systems: the campaign state (core/game_state.gd), economy (core/economy.gd), turn loop
# (core/turn_loop.gd) and chronicle, plus world data (factions, provinces, unit types, armies).
# Values with no system yet (public order) come from the clearly marked data/mock_ui.json.

signal changed
signal event_added(event: Dictionary)
signal army_moved(army_id: String,walked: Array) # points walked (world x/z), for the map figure

const WorldMap = preload("res://core/world_map.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const GameState = preload("res://core/game_state.gd")
const Economy = preload("res://core/economy.gd")
const Buildings = preload("res://core/buildings.gd")
const Construction = preload("res://core/construction.gd")
const Movement = preload("res://core/movement.gd")
const Armies = preload("res://core/armies.gd")
const Battles = preload("res://core/battles.gd")
const BattleReport = preload("res://core/battle_report.gd")
const Deployment = preload("res://core/deployment.gd")
const BattleDeploy = preload("res://core/battle_deploy.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const Chronicle = preload("res://core/chronicle.gd")
const Ai = preload("res://core/ai.gd")
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
  var label = "Building upkeep: %s" % WorldMap.region(e.label).settlement.name if e.kind == "buildings" else "Army upkeep: %s" % state.army_state[e.label].display_name
  out.expenses.append({"label":label,"amount":e.amount})
 return out

# Advance one year through the turn loop; new chronicle entries go to Event Messages.
func end_turn():
 var t0 = Time.get_ticks_usec()
 var report = TurnLoop.end_turn(state)
 last_turn_ms = (Time.get_ticks_usec()-t0)/1000.0
 for e in report.entries: event_added.emit(e)
 for id in report.moves: army_moved.emit(id,report.moves[id])
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
 s.garrison = []
 for a in Movement.garrison_of(state,id): s.garrison.append(state.army_state[a].display_name)
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

# An army as the panel shows it: {id, display_name, faction, faction_data, commander (a card entry
# for the general), units ({unit, men, max_men} card entries), queue, upkeep, max_units}.
func army(id: String) -> Dictionary:
 var a = state.army_state[id]
 var queue = []
 for q in a.queue: queue.append(q.duplicate())
 return {"id":id,"display_name":a.display_name,"faction":a.faction,"faction_data":faction(a.faction),
  "commander":{"unit":"commander","name":a.commander.name,"rank":int(a.commander.rank),"men":1,"max_men":1},
  "units":a.units.duplicate(true),"queue":queue,"upkeep":Economy.army_upkeep(state,id),"max_units":Armies.max_units(),
  "player_owned":a.faction == state.player_faction}

func army_ids() -> Array:
 var out = state.army_state.keys()
 out.sort()
 return out

# --- Recruitment ---------------------------------------------------------------------

# Recruitment panel data: {settlement ("" if the army is not in or next to its own settlement),
# settlement_name, population, min_population, options (see Armies.options)}.
func recruitment(army_id: String) -> Dictionary:
 var sid = Armies.recruit_settlement(state,army_id)
 return {"settlement":sid,"settlement_name":WorldMap.region(sid).settlement.name if sid != "" else "",
  "population":int(state.settlements[sid].population) if sid != "" else 0,"min_population":int(Armies.data().recruitment.min_population),
  "options":Armies.options(state,army_id)}

func recruit(army_id: String,unit_id: String) -> Dictionary:
 if state.army_state[army_id].faction != state.player_faction: return {"ok":false,"reasons":["Not your army"]}
 var r = Armies.recruit(state,army_id,unit_id)
 if r.ok: changed.emit()
 return r

func cancel_recruit(army_id: String,index: int) -> Dictionary:
 if state.army_state[army_id].faction != state.player_faction: return {"gold":0,"men":0}
 var r = Armies.cancel_recruit(state,army_id,index)
 changed.emit()
 return r

func disband_unit(army_id: String,index: int) -> Dictionary:
 if state.army_state[army_id].faction != state.player_faction: return {"men":0,"settlement":""}
 var r = Armies.disband(state,army_id,index)
 changed.emit()
 return r

func unit_type(id: String) -> Dictionary:
 return UnitTypes.get_type(id)

# --- Army movement ---------------------------------------------------------------

func army_movement(army_id: String) -> Dictionary:
 var m = Movement.army(state,army_id)
 var order = []
 for p in m.order: order.append(Vector2(p[0],p[1]))
 return {"position":Movement.position(state,army_id),"points":float(m.points),"max_points":float(m.max_points),"order":order,
  "garrison":m.garrison,"garrison_name":WorldMap.region(m.garrison).settlement.name if m.garrison != "" else "","player_owned":m.faction == state.player_faction}

# Preview a move without committing it (see Movement.plan).
func plan_move(army_id: String,target: Vector2) -> Dictionary:
 return Movement.plan(state,army_id,target)

# Commit a move: walks as far as this turn allows, keeps the rest as a standing order.
func order_move(army_id: String,target: Vector2) -> Dictionary:
 if Movement.army(state,army_id).faction != state.player_faction: return {"ok":false,"reason":"Not your army"}
 var r = Movement.order(state,army_id,target)
 if r.ok:
  army_moved.emit(army_id,r.moved)
  changed.emit()
 return r

func cancel_army_order(army_id: String):
 Movement.cancel_order(state,army_id)
 changed.emit()

# World x/z centers of the cells the army can still reach this turn, and the cell size.
func reachable_area(army_id: String) -> Dictionary:
 var out = []
 for c in Movement.reachable(state,army_id): out.append(Movement.center_of(c))
 return {"centers":out,"cell":Movement.grid().cell}

func road_level() -> int:
 return state.road_level

func set_road_level(level: int):
 state.road_level = level
 changed.emit()

# The army's standing order as a drawable path: {points (from the army), turns (0 = this turn)}.
func order_path(army_id: String) -> Dictionary:
 var m = army_movement(army_id)
 if m.order.is_empty(): return {"points":[],"turns":[]}
 var pts = [m.position]+m.order
 return {"points":pts,"turns":Movement.simulate(pts,m.points,m.max_points,state.road_level).turns}

# Upkeep per turn of one unit of this type.
func unit_upkeep(unit_id: String) -> int:
 return int(round(float(UnitTypes.get_type(unit_id).placeholder_stats.upkeep)*float(Economy.data().upkeep.army_upkeep_multiplier)))

# --- New armies ----------------------------------------------------------------------

# Whether the player can hire a general (a new army) at this settlement, and the cost.
func raise_army_check(settlement_id: String) -> Dictionary:
 var r = Armies.can_raise(state,state.player_faction,settlement_id)
 r.cost = int(Armies.data().armies.general_cost)
 r.max_armies = int(Armies.data().armies.max_per_faction)
 return r

# Hire a general at one of the player's settlements: a new army garrisoned there.
func raise_army(settlement_id: String) -> Dictionary:
 var r = Armies.raise_army(state,state.player_faction,settlement_id)
 if r.ok: changed.emit()
 return r

# --- Battles (core/battles.gd) ---------------------------------------------------------------

# What an order onto `point` would attack, and whether war must be declared first.
# {kind: army|settlement|"", id, faction, faction_name, needs_war, can_attack, reason}
func battle_target(army_id: String,point: Vector2) -> Dictionary:
 var t = Battles.target_at(state,army_id,point)
 if t.kind == "": return t
 var me = state.army_state[army_id].faction
 t.faction_name = faction(t.faction).name
 t.needs_war = not Battles.at_war(state,me,t.faction)
 var a = Battles.approach(state,army_id,t)
 t.can_attack = a.ok
 t.reason = a.get("reason","")
 return t

# TEMPORARY war rule: the player's confirmation declares war (no peace until diplomacy).
func declare_war(target_faction: String) -> Dictionary:
 var e = Battles.declare_war(state,state.player_faction,target_faction)
 if not e.is_empty(): event_added.emit(e)
 changed.emit()
 return e

func at_war(other_faction: String) -> bool:
 return Battles.at_war(state,state.player_faction,other_faction)

# Pre-battle panel data (see Battles.prebattle) with readable army lists added.
func prebattle(army_id: String,point: Vector2) -> Dictionary:
 var t = Battles.target_at(state,army_id,point)
 var a = Battles.approach(state,army_id,t)
 var pb = Battles.prebattle(state,army_id,t)
 pb.approach = a
 pb.view = {"attacker":_side_view(pb,0),"defender":_side_view(pb,1)}
 pb.player_is_defender = pb.defender.faction == state.player_faction
 return pb

func _side_view(pb: Dictionary,role: int) -> Dictionary:
 var spec = pb.attacker if role == 0 else pb.defender
 var armies = [spec.army] if role == 0 else spec.armies
 var lines = []
 var men = 0
 for id in armies:
  var a = army(id)
  lines.append({"army":a.display_name,"general":a.commander.name,"units":a.units,"arrives":"in the battle"})
  for u in a.units: men += int(u.men)
 for r in spec.reinforcements:
  var a = army(r.army)
  lines.append({"army":a.display_name,"general":a.commander.name,"units":a.units,"arrives":"in reserve" if int(r.arrive_tick) == 0 else "after %d ticks" % int(r.arrive_tick)})
  for u in a.units: men += int(u.men)
 if role == 1 and pb.kind == "settlement":
  var g = Battles.garrison_units(state,pb.settlement)
  lines.append({"army":"Garrison of %s" % WorldMap.region(pb.settlement).settlement.name,"general":"","units":g,"arrives":"in the battle"})
  for u in g: men += int(u.men)
 return {"faction":faction(spec.faction),"lines":lines,"men":men}

# Fight now with both sides' default deployments. Moves the attacker next to the target first.
# Returns {result, aftermath} (see Battles.quick_resolve).
func quick_resolve(pb: Dictionary) -> Dictionary:
 if pb.approach.get("plan",{}).has("points"):
  var r = Movement.order(state,pb.attacker.army,pb.approach.point)
  if r.get("moved",[]).size()>1: army_moved.emit(pb.attacker.army,r.moved)
 # An AI army caught in the field may withdraw instead of fighting (core/ai.gd, its own odds).
 if pb.defender.faction != state.player_faction and Ai.defender_withdraws(state,pb):
  var w = Battles.withdraw(state,pb)
  if w.ok:
   var e = Chronicle.withdraw_entry(state.year,pb)
   state.chronicle.append(e)
   event_added.emit(e)
   changed.emit()
   return {"withdrew":true,"entry":e}
 var out = Battles.quick_resolve(state,pb)
 for e in out.aftermath.entries: event_added.emit(e)
 changed.emit()
 return out

func withdraw(pb: Dictionary) -> Dictionary:
 var r = Battles.withdraw(state,pb)
 changed.emit()
 return r

# Besiege: march next to the settlement first (as Quick Resolve does), so the siege holds at End
# Turn. pb: the pre-battle data with its approach; without one the army besieges from where it is.
func besiege(army_id: String,settlement_id: String,pb := {}) -> Dictionary:
 var walked = Battles.move_to_attack(state,army_id,pb.get("approach",{}))
 if walked.size()>1: army_moved.emit(army_id,walked)
 var r = Battles.besiege(state,army_id,settlement_id)
 changed.emit()
 return r

func siege_of(settlement_id: String) -> Dictionary:
 return state.settlements[settlement_id].get("siege",{})

func appoint_general(army_id: String) -> Dictionary:
 var r = Battles.appoint_general(state,army_id)
 changed.emit()
 return r

func general_status(army_id: String) -> Dictionary:
 return Battles.commander(state,army_id)

func battle_report(pb: Dictionary,out: Dictionary) -> Dictionary:
 return BattleReport.build(pb,out.result,out.aftermath,state.player_faction)

func battle_odds_runs() -> int:
 return int(Battles.cfg().odds_runs)

func battle_withdraw_share() -> float:
 return float(Battles.cfg().withdraw_casualty_share)

# --- Deployment screen (core/deployment.gd) ----------------------------------------------------

func player_role(pb: Dictionary) -> int:
 return 1 if pb.player_is_defender else 0

func deployment_templates() -> Array:
 return BattleDeploy.TEMPLATES

# A fresh deployment of the player's side from a template (default: the faction's own).
func deployment_create(pb: Dictionary,template := "") -> Dictionary:
 var role = player_role(pb)
 if template == "": template = Battles.default_template(state,pb,role)
 return Deployment.create(Battles.side_units(state,pb,role),pb.field.terrain,role,template)

func deployment_apply_template(pb: Dictionary,dep: Dictionary,template: String):
 Deployment.apply_template(dep,Battles.side_units(state,pb,player_role(pb)),template)

func deployment_can_place(dep: Dictionary,i: int,lane: int,line: String) -> Dictionary:
 return Deployment.can_place(dep,i,lane,line)

func deployment_place(dep: Dictionary,i: int,lane: int,line: String) -> Dictionary:
 return Deployment.place(dep,i,lane,line)

func deployment_order(dep: Dictionary,i: int,order: String,arg = null) -> Dictionary:
 return Deployment.set_order(dep,i,order,arg)

func deployment_general(dep: Dictionary,lane: int) -> Dictionary:
 return Deployment.set_general_lane(dep,lane)

func deployment_lane_name(lanes: int,lane: int) -> String:
 return Deployment.lane_name(lanes,lane)

# The enemy as the player sees it before battle: its default deployment, with units hidden by
# forest, reserve or fog marked unknown (decision 12).
func deployment_enemy(pb: Dictionary) -> Array:
 var role = 1-player_role(pb)
 var out = []
 for u in Battles.default_placement(state,pb,role):
  var v = u.duplicate()
  v.hidden = Deployment.hidden(u,pb.field.terrain,role,pb.weather)
  out.append(v)
 return out

# Balance of power for this deployment (seeded quick runs).
func deployment_odds(pb: Dictionary,dep: Dictionary) -> float:
 var p = pb.duplicate()
 p.deployment = dep
 return Battles.odds(state,p)

# Fight with the player's deployment (the enemy uses its default). Same flow as Quick Resolve.
func fight(pb: Dictionary,dep: Dictionary) -> Dictionary:
 var p = pb.duplicate()
 p.deployment = dep
 return quick_resolve(p)
