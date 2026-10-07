extends RefCounted
# The one data interface the campaign UI reads. Everything the panels show comes from here.
# Real systems: the campaign state (core/game_state.gd), economy (core/economy.gd), turn loop
# (core/turn_loop.gd) and chronicle, plus world data (factions, provinces, unit types, armies).
# Values with no system yet (public order) come from the clearly marked data/mock_ui.json.

signal changed
signal event_added(event: Dictionary)
signal army_moved(army_id: String,walked: Array) # points walked (world x/z), for the map figure
signal alert(alert: Dictionary) # an important event for a pop-up (TW:WH3 notifications)

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
const Realm = preload("res://core/realm.gd")
const Land = preload("res://core/land.gd")
const Characters = preload("res://core/characters.gd")
const MOCK = "res://data/mock_ui.json"
const CATEGORIES = [{"id":"turn","name":"Turn Summary"},{"id":"buildings","name":"Buildings Constructed"},{"id":"war","name":"Wars and Battles"},{"id":"world","name":"World Events"}]

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
 # Debt (core/realm.gd): in_debt below 0, below_limit under the debt limit; grace: End Turns left to
 # retake a settlement (-1 when not landless).
 return {"treasury":int(state.treasury[f]),"income":int(Economy.faction_ledger(state,f).net),"population":state.population_of(f),"year":state.year,"turn":state.turn,
  "in_debt":Realm.in_debt(state,f),"below_limit":Realm.below_limit(state,f),"debt_limit":int(Realm.debt().limit),"desertion_pct":int(round(float(Realm.debt().desertion_share)*100)),
  "grace":Realm.grace_left(state,f),"destroyed":Realm.destroyed(state,f)}

# A faction's grace period (-1 when it is not landless), for map banners.
func grace_left(faction_id: String) -> int:
 return Realm.grace_left(state,faction_id)

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
 var before = _alert_snapshot()
 _refresh_attack_orders()
 var report = TurnLoop.end_turn(state)
 last_turn_ms = (Time.get_ticks_usec()-t0)/1000.0
 return _after_turn(report,before)

# End Turn spread over frames (the game): the map keeps rendering and the AI turn bar shows
# turn_progress(factions done, factions in all). Same result as end_turn.
signal turn_progress(done: int,total: int,faction: String)
func end_turn_async(tree: SceneTree,budget_ms := 12.0):
 var t0 = Time.get_ticks_usec()
 var before = _alert_snapshot()
 _refresh_attack_orders()
 var report = await TurnLoop.end_turn_sliced(state,tree,budget_ms,func(d,n,f := ""): turn_progress.emit(d,n,f))
 last_turn_ms = (Time.get_ticks_usec()-t0)/1000.0
 return _after_turn(report,before)

func _after_turn(report: Dictionary,before: Dictionary) -> Dictionary:
 for e in report.entries: event_added.emit(e)
 # Standing orders walked first, then the AI phase: one path per army for the map to replay.
 var moves = {}
 for src in [report.moves,report.ai.moves]:
  for id in src:
   if not moves.has(id): moves[id] = src[id].duplicate()
   else: moves[id].append_array(src[id].slice(1))
 report.all_moves = moves
 for id in moves: army_moved.emit(id,moves[id])
 changed.emit()
 report.alerts = alerts_since(before)
 for a in report.alerts: alert.emit(a)
 return report

# --- AI attacks on the player (state.pending_battles) ------------------------------------------

# The next attack the player must answer, rebuilt from the current state as a pre-battle panel
# with the player defending ({} if none). Attacks that no longer make sense are dropped.
func pending_battle() -> Dictionary:
 while not state.pending_battles.is_empty():
  var p = state.pending_battles[0]
  var army = p.attacker.army
  var target = {}
  if state.army_state.has(army) and Battles.can_move(state,army):
   if p.kind == "settlement" and state.settlements[p.settlement].owner == state.player_faction:
    target = {"kind":"settlement","id":p.settlement,"faction":state.player_faction,"position":WorldMap.settlement_position(p.settlement)}
   elif p.kind == "army" and not p.defender.armies.is_empty() and state.army_state.has(p.defender.armies[0]):
    var d = p.defender.armies[0]
    target = {"kind":"army","id":d,"faction":state.army_state[d].faction,"position":Movement.position(state,d)}
  if not target.is_empty() and Movement.position(state,army).distance_to(target.position)<=float(Ai.data().reach.reach_meters):
   var pb = Battles.prebattle(state,army,target)
   pb.approach = {"ok":true,"point":Movement.position(state,army),"plan":{}}
   pb.view = {"attacker":_side_view(pb,0),"defender":_side_view(pb,1)}
   pb.player_is_defender = true
   pb.forced = true # the player must answer: no Close button
   Battles.set_stance(state,pb,1,"balanced") # the player's stance starts Balanced
   return pb
  state.pending_battles.pop_front()
 return {}

func has_pending_battle() -> bool:
 return not state.pending_battles.is_empty()

# The front attack has been answered (fought, withdrawn from).
func _answered(pb: Dictionary):
 if pb.get("forced",false) and not state.pending_battles.is_empty(): state.pending_battles.pop_front()

# --- Event messages and chronicle ------------------------------------------------

func event_categories() -> Array:
 return CATEGORIES

# Event Messages: building completions only for the player's own settlements (the chronicle keeps all).
func events(category: String) -> Array:
 var out = []
 for e in state.chronicle:
  # Wars, battles and captures are news from the whole map (AI wars included); other categories
  # are the player's own.
  if e.category == category and (category == "war" or e.get("faction",state.player_faction) == state.player_faction): out.append(e)
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
 # Under siege: who besieges it and how long it has held ({} if not).
 var sg = live.get("siege",{})
 s.siege = {} if sg.is_empty() or not state.army_state.has(sg.army) else {"faction":faction(state.army_state[sg.army].faction),"turns":int(sg.turns),"endurance":int(sg.endurance)}
 s.upgrade_available = s.player_owned and upgrade_available(id)
 return s

# Something can be built or upgraded in this settlement now (TW:WH3 green hammer on the map banner
# and in lists; the building cards show which).
func upgrade_available(id: String) -> bool:
 if not Construction.in_progress(state,id).is_empty(): return false
 for i in state.settlements[id].buildings.size():
  for o in Construction.options(state,id,i):
   if o.available: return true
 return false

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
   # Upgradeable now (TW:WH3 green arrow on the card).
   view.upgrade = pending.is_empty() and s.owner == state.player_faction and Construction.can_build(state,settlement_id,i,b.chain).ok
   # Upgradeable now (TW:WH3 green arrow on the card).
   view.upgrade = pending.is_empty() and s.owner == state.player_faction and Construction.can_build(state,settlement_id,i,b.chain).ok
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
 for q in a.queue:
  var e = q.duplicate()
  e.kind = Armies.queue_kind(q) # TW banner: local green, global blue, overflow orange
  queue.append(e)
 return {"id":id,"display_name":a.display_name,"faction":a.faction,"faction_data":faction(a.faction),
  "commander":{"unit":"commander","name":a.commander.name,"rank":int(a.commander.rank),"men":1,"max_men":1},
  "units":a.units.duplicate(true),"queue":queue,"upkeep":Economy.army_upkeep(state,id),"max_units":Armies.max_units(),
  "player_owned":a.faction == state.player_faction}

func army_ids() -> Array:
 var out = state.army_state.keys()
 out.sort()
 return out

# --- Lords & Heroes character window (docs/tw-ui-parity.md §15; core/characters.gd) ------------

# The window's view of an army's general: name, epithet, level and experience, stats, traits,
# the skill rows with each skill's state (taken, available, locked + reason), points and the
# auto-allocate switch, plus the army he leads.
func character(army_id: String) -> Dictionary:
 var a = state.army_state[army_id]
 var c = a.commander
 var rows = []
 for r in Characters.rows():
  var skills = []
  for s in r.skills:
   var can = Characters.can_take(c,s.id)
   skills.append({"id":s.id,"name":s.name,"level":int(s.level),"text":s.text,"taken":s.id in c.get("skills",[]),"available":can.ok,"reason":can.reason})
  rows.append({"id":r.id,"name":r.name,"function":r.function,"skills":skills})
 var m = army_movement(army_id)
 return {"army_id":army_id,"name":c.name,"epithet":str(c.get("epithet","")),"level":Characters.level(c),"xp":Characters.xp_progress(c),
  "status":str(c.get("status","ok")),"faction":a.faction,"faction_data":faction(a.faction),"player_owned":a.faction == state.player_faction,
  "stats":Characters.stats(c),"traits":Characters.traits(state,army_id),"rows":rows,"points":Characters.skill_points(c),
  "auto":Characters.auto_on(state,army_id),"army":army(army_id),"men":Armies.men(a),"location":m.garrison_name if m.garrison != "" else WorldMap.region(WorldMap.region_at(m.position)).get("name","the wilds") if WorldMap.region_at(m.position) != "" else "the wilds"}

func take_skill(army_id: String,skill_id: String) -> bool:
 var ok = Characters.take(state,army_id,skill_id)
 if ok: changed.emit()
 return ok

func set_auto_skills(army_id: String,on: bool):
 Characters.set_auto(state,army_id,on)
 changed.emit()

# --- Recruitment ---------------------------------------------------------------------

# Recruitment panel data: {settlement ("" if the army is not in or next to its own settlement),
# settlement_name, population, min_population, options (see Armies.options)}.
# Recruitment for an army (province-wide, core/armies.gd): {ok, reason, province, province_name,
# settlements [{id, name, population}], min_population, options}.
# The recruitment panel for a mode (local or global, TW:WH3): where, the sources' population,
# capacity slots (units queued vs the lord's capacity) and the recruitable units.
func recruitment(army_id: String,mode := "local") -> Dictionary:
 var ctx = Armies.mode_context(state,army_id,mode)
 var towns = []
 for sid in ctx.settlements: towns.append({"id":sid,"name":WorldMap.region(sid).settlement.name,"population":int(state.settlements[sid].population)})
 return {"ok":ctx.ok,"reason":ctx.reason,"province":ctx.province,"province_name":WorldMap.province(ctx.province).name if ctx.province != "" else "",
  "settlements":towns,"min_population":int(Armies.data().recruitment.min_population),"options":Armies.options(state,army_id,mode),"mode":mode,
  "capacity":Armies.capacity(state,army_id),"queued":state.army_state[army_id].queue.size(),
  "global_cost":float(Armies.data().recruitment.global.cost_multiplier),"global_turns":int(Armies.data().recruitment.global.turns_multiplier)}

func recruit(army_id: String,unit_id: String,mode := "local") -> Dictionary:
 if state.army_state[army_id].faction != state.player_faction: return {"ok":false,"reasons":["Not your army"]}
 var r = Armies.recruit(state,army_id,unit_id,mode)
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
func coarse_plan(army_id: String,target: Vector2) -> Dictionary:
 return Movement.coarse_plan(state,army_id,target)

func plan_move(army_id: String,target: Vector2) -> Dictionary:
 return Movement.plan(state,army_id,target)

# Commit a move: walks as far as this turn allows, keeps the rest as a standing order.
func order_move(army_id: String,target: Vector2) -> Dictionary:
 if Movement.army(state,army_id).faction != state.player_faction: return {"ok":false,"reason":"Not your army"}
 var r = Movement.order(state,army_id,target)
 if r.ok:
  state.army_state[army_id].erase("attack") # a new order replaces an attack order
  army_moved.emit(army_id,r.moved)
  changed.emit()
 return r

func cancel_army_order(army_id: String):
 if state.army_state.has(army_id): state.army_state[army_id].erase("attack")
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

# Attack orders (TW:WH3 flow, owner 2026-10-05): after any war declaration, the lord marches on the
# target over as many turns as needed; the pre-battle panel opens only when the lord stands in attack
# range (ready_attack). The order lives in the army's state ("attack": {kind, id}), so saves keep it.
# Returns {ok, now (in range this turn: the army moved next to it), turns, reason}.
func attack_order(army_id: String,point: Vector2) -> Dictionary:
 var t = Battles.target_at(state,army_id,point)
 if t.kind == "": return {"ok":false,"reason":"Nothing to attack there"}
 var a = Battles.approach(state,army_id,t)
 if a.ok:
  if a.get("plan",{}).has("points"):
   var r = Movement.order(state,army_id,a.point)
   if r.get("moved",[]).size()>1: army_moved.emit(army_id,r.moved)
  state.army_state[army_id].erase("attack")
  changed.emit()
  return {"ok":true,"now":true,"turns":0}
 if not a.get("plan",{}).get("ok",false): return {"ok":false,"reason":a.get("reason","No way to reach the enemy")}
 var r2 = Movement.order(state,army_id,a.point)
 if not r2.ok: return {"ok":false,"reason":r2.get("reason","No way to reach the enemy")}
 state.army_state[army_id].attack = {"kind":t.kind,"id":t.id}
 if r2.get("moved",[]).size()>1: army_moved.emit(army_id,r2.moved)
 changed.emit()
 return {"ok":true,"now":false,"turns":int(a.plan.total_turns)}

# Where an attack-ordered target is now: {kind, id, faction, position}, or {} when it is gone or no
# longer an enemy.
func _attack_target(army_id: String) -> Dictionary:
 var at = state.army_state[army_id].get("attack",{})
 if at.is_empty(): return {}
 var me = state.army_state[army_id].faction
 if at.kind == "settlement":
  if not state.settlements.has(at.id) or state.settlements[at.id].owner == me: return {}
  return {"kind":"settlement","id":at.id,"faction":state.settlements[at.id].owner,"position":WorldMap.settlement_position(at.id)}
 if not state.army_state.has(at.id) or state.army_state[at.id].faction == me: return {}
 var o = state.army_state[at.id]
 if o.garrison != "": return {"kind":"settlement","id":o.garrison,"faction":state.settlements[o.garrison].owner,"position":WorldMap.settlement_position(o.garrison)}
 return {"kind":"army","id":at.id,"faction":o.faction,"position":Movement.position(state,at.id)}

# Before End Turn's marching: an attack order follows a target that moved.
func _refresh_attack_orders():
 for id in state.army_state:
  var a = state.army_state[id]
  if a.faction != state.player_faction or not a.has("attack"): continue
  var t = _attack_target(id)
  if t.is_empty():
   a.erase("attack")
   continue
  var ap = Battles.approach(state,id,t)
  if ap.ok and not ap.get("plan",{}).has("points"): continue # already there
  if ap.get("plan",{}).get("ok",false): Movement.order(state,id,ap.point)

# The first of the player's attack orders whose army now stands within attack range of its target:
# {army, point, target} for the pre-battle panel (opened at the start of the turn), or {}.
func ready_attack() -> Dictionary:
 for id in state.army_state:
  var a = state.army_state[id]
  if a.faction != state.player_faction or not a.has("attack"): continue
  var t = _attack_target(id)
  if t.is_empty():
   a.erase("attack")
   continue
  if not Battles.at_war(state,a.faction,t.faction): continue
  var ap = Battles.approach(state,id,t)
  if ap.ok and not ap.get("plan",{}).has("points"):
   return {"army":id,"point":t.position,"target":t}
 return {}

# The pre-battle panel opened for an attack order: the order is done (the player fights or not).
func clear_attack(army_id: String):
 if state.army_state.has(army_id): state.army_state[army_id].erase("attack")

# TEMPORARY war rule: the player's confirmation declares war (no peace until diplomacy).
func declare_war(target_faction: String) -> Dictionary:
 var e = Battles.declare_war(state,state.player_faction,target_faction)
 if not e.is_empty(): event_added.emit(e)
 changed.emit()
 return e

func at_war(other_faction: String) -> bool:
 return Battles.at_war(state,state.player_faction,other_faction)

# A faction's relation to the player for the diplomacy map mode: "self", "vassal", "ally", "trade",
# "neutral", "hostile" or "war" (core/diplomacy.gd when it exists; lore rivals count as hostile).
func relation_to_player(f: String) -> String:
 var me = state.player_faction
 if f == me: return "self"
 if at_war(f): return "war"
 var D = _diplomacy()
 if D != null: return D.relation(state,me,f)
 if str(WorldMap.faction(me).get("relations",{}).get(f,"")) == "rival": return "hostile"
 return "neutral"

# The faction this one is a vassal of ("" = independent).
func liege_of(f: String) -> String:
 var D = _diplomacy()
 return D.liege_of(state,f) if D != null else ""

static var _dip_script = null
func _diplomacy():
 if _dip_script == null and ResourceLoader.exists("res://core/diplomacy.gd"): _dip_script = load("res://core/diplomacy.gd")
 return _dip_script

# --- Diplomacy screen (docs/tw-ui-parity.md §15; docs/diplomacy-design.md) ---------------------
# Real: war and peace status, holdings and strength, faction tendencies, who is at war with whom.
# PLACEHOLDERS until the diplomacy system: attitude (neutral start, diplomacy-design §3.3),
# reliability, deal chances and every treaty but war.
const ATTITUDE_STEPS = ["Hostile","Unfriendly","Indifferent","Friendly","Very friendly"]

func diplomacy_faction(id: String) -> Dictionary:
 var f = faction(id)
 var men = 0
 for a in Armies.armies_of(state,id): men += Armies.men(state.army_state[a])
 var wars = state.factions().filter(func(o): return o != id and Battles.at_war(state,id,o)).map(func(o): return faction(o).name)
 return {"id":id,"name":f.name,"faction_data":f,"realm":f.get("realm",""),"seat":f.get("seat",""),"culture":str(f.get("culture","")).capitalize(),
  "settlements":state.settlements_of(id).size(),"armies":Armies.armies_of(state,id).size(),"men":men,
  "traits":f.get("traits",[]).map(func(t): return str(t).capitalize()),"wars":wars,"at_war":id != player_faction_id() and at_war(id),
  "attitude":0,"attitude_label":ATTITUDE_STEPS[2],"reliability":"Reliable"}

# The player's faction and the known factions (met or at war), the player first.
func diplomacy() -> Dictionary:
 var others = []
 for f in known_factions():
  if f != player_faction_id() and not f in state.destroyed: others.append(diplomacy_faction(f))
 return {"me":diplomacy_faction(player_faction_id()),"factions":others}

# Pre-battle panel data (see Battles.prebattle) with readable army lists added.
func prebattle(army_id: String,point: Vector2) -> Dictionary:
 var t = Battles.target_at(state,army_id,point)
 var a = Battles.approach(state,army_id,t)
 var pb = Battles.prebattle(state,army_id,t)
 pb.approach = a
 pb.view = {"attacker":_side_view(pb,0),"defender":_side_view(pb,1)}
 pb.player_is_defender = pb.defender.faction == state.player_faction
 Battles.set_stance(state,pb,1 if pb.player_is_defender else 0,"balanced") # the player's stance starts Balanced
 return pb

# The player's stance for a battle (Aggressive, Balanced, Defensive); the balance of power follows.
func set_battle_stance(pb: Dictionary,stance: String):
 Battles.set_stance(state,pb,1 if pb.get("player_is_defender",false) else 0,stance)

func battle_stance(pb: Dictionary) -> String:
 return str(pb.get("stances",{}).get("1" if pb.get("player_is_defender",false) else "0","balanced"))

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
 _answered(pb)
 for e in out.aftermath.entries: event_added.emit(e)
 changed.emit()
 return out

func withdraw(pb: Dictionary) -> Dictionary:
 var r = Battles.withdraw(state,pb)
 if r.ok:
  _answered(pb)
  var e = Chronicle.withdraw_entry(state.year,pb)
  state.chronicle.append(e)
  event_added.emit(e)
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

# What a held right click on an enemy army or settlement would do: {ok, reason, name, plan (the
# march to the attack position, as Movement.plan returns it)}. No odds (that is the pre-battle panel).
func attack_preview(army_id: String,point: Vector2) -> Dictionary:
 var t = Battles.target_at(state,army_id,point)
 if t.kind == "": return {"ok":false,"reason":"Blocked","name":"","plan":{}}
 var name = settlement(t.id).name if t.kind == "settlement" else state.army_state[t.id].display_name
 var a = Battles.approach(state,army_id,t)
 var plan = a.get("plan",{})
 if plan.is_empty() and a.ok:
  var here = Movement.position(state,army_id)
  plan = {"ok":true,"points":[here,here],"turns":[0,0],"total_turns":1,"cost":0.0}
 return {"ok":a.ok,"reason":a.get("reason",""),"name":name,"plan":plan}

# --- End Turn warnings (TW:WH3 end-turn notifications, docs/tw-ui-parity.md E2-E4) ------------
# The kinds that apply to systems we have; each can be switched off in Settings:
#   construction: an own settlement with nothing being built and something it can build now
#   army_moves:   an own army (led by a general, with units) that can still move and has no order
#   funds:        the treasury is in debt or will be after this turn's income and upkeep
# Returns [{kind, label, items: [{type: settlement|army, id, name}]}], in this order.
# End Turn warnings (TW:WH3, docs/tw-ui-parity.md §15): each skippable, each item jumps to its subject.
const WARNINGS = [["funds","Low funds"],["settlement_upgrade","Settlement can be upgraded"],["construction","Idle construction slots"],
 ["army_moves","Lords with movement left"],["skill_points","Unspent skill points"],["recruit","Army can recruit"]]

func end_turn_warnings(enabled := {}) -> Array:
 var out = []
 var f = player_faction_id()
 for w in WARNINGS:
  if not enabled.get(w[0],true): continue
  var items = []
  match w[0]:
   "funds":
    if Realm.in_debt(state,f) or int(state.treasury[f])+int(Economy.faction_ledger(state,f).net)<0:
     items.append({"type":"faction","id":f,"name":"Treasury"})
   "construction":
    for sid in state.settlements_of(f):
     if not Construction.in_progress(state,sid).is_empty(): continue
     var can = false
     for i in state.settlements[sid].buildings.size():
      for o in Construction.options(state,sid,i):
       if o.available: can = true
     if can: items.append({"type":"settlement","id":sid,"name":settlement(sid).name})
   "army_moves":
    for id in Armies.armies_of(state,f):
     var a = state.army_state[id]
     if a.units.is_empty() or not a.order.is_empty() or not Battles.can_move(state,id): continue
     if float(a.points)>=float(a.max_points)*0.25: items.append({"type":"army","id":id,"name":a.display_name})
   "settlement_upgrade":
    # The main building (the settlement level) can go up now.
    for sid in state.settlements_of(f):
     if not Construction.in_progress(state,sid).is_empty(): continue
     var s = state.settlements[sid]
     var main = Buildings.main_chain_id(s.type)
     for i in s.buildings.size():
      if s.buildings[i].get("chain","") == main and Construction.can_build(state,sid,i,main).ok:
       items.append({"type":"settlement","id":sid,"name":settlement(sid).name})
   "skill_points":
    # Generals with free points and auto-allocate off (placeholder skills: data/skills.json).
    for id in Armies.armies_of(state,f):
     if not Characters.auto_on(state,id) and Characters.skill_points(state.army_state[id].commander)>0: items.append({"type":"character","id":id,"name":state.army_state[id].commander.name})
   "recruit":
    # Armies in recruiting range with room and gold for at least one unit.
    for id in Armies.armies_of(state,f):
     var a = state.army_state[id]
     if Armies.card_count(a)>=Armies.max_units() or not a.queue.is_empty(): continue
     if Armies.options(state,id,"local").any(func(o): return o.available): items.append({"type":"army","id":id,"name":a.display_name})
  if not items.is_empty(): out.append({"kind":w[0],"label":w[1],"items":items})
 return out

# --- Panels and lists of the TW:WH3 layout (docs/tw-ui-parity.md L2-L7) -------------------------

# Right column of the army panel: {upkeep, replenish_pct, territory (own / foreign), paid_gold}.
func army_info(army_id: String) -> Dictionary:
 var r = Armies.replenish_rate(state,army_id)
 var a = state.army_state[army_id]
 var owner = Armies.region_owner(state,army_id)
 return {"upkeep":Economy.army_upkeep(state,army_id),"replenish_pct":int(round(float(r.get("rate",0.0))*100)),
  "territory":"own" if owner == a.faction else ("unclaimed" if owner == "" else "foreign"),"region_owner":faction(owner).get("name","") if owner != "" else ""}

# The garrison a settlement would fight with: its automatic garrison units plus armies inside.
func garrison(settlement_id: String) -> Dictionary:
 var units = []
 for u in Battles.garrison_units(state,settlement_id): units.append({"unit":u.unit,"men":int(u.men),"max_men":int(u.max_men)})
 return {"units":units,"armies":Movement.garrison_of(state,settlement_id).map(func(id): return state.army_state[id].display_name)}

# Right column of the province panel: resource endowments, the terrain of the region (as its
# climate until climates exist) and the effects of its buildings.
func region_details(settlement_id: String) -> Dictionary:
 var effects = []
 for slot in building_slots(settlement_id):
  for line in slot.get("effects",[]): if not line in effects: effects.append(line)
 return {"resources":state.settlements[settlement_id].get("resources",{}),"terrain":region_terrain(settlement_id),"effects":effects}

var _terrain_cache := {}
# Share of each terrain in a region (from the movement grid, cached): [[name, share], ...] largest first.
func region_terrain(region_id: String) -> Array:
 if _terrain_cache.has(region_id): return _terrain_cache[region_id]
 var g = Movement.grid()
 var counts = {}
 var total = 0
 var poly = WorldMap.region(region_id).points
 for z in range(0,g.rows,2):
  for x in range(0,g.cols,2):
   var p = g.origin+Vector2(x+0.5,z+0.5)*g.cell
   if not Geometry2D.is_point_in_polygon(p,poly): continue
   var n = g.names[g.terrain[z*g.cols+x]]
   counts[n] = counts.get(n,0)+1
   total += 1
 var out = []
 for n in counts: out.append([n,float(counts[n])/maxi(1,total)])
 out.sort_custom(func(a,b): return a[1]>b[1])
 _terrain_cache[region_id] = out
 return out

# Lords and heroes list: the player's armies.
func lords_list() -> Array:
 var out = []
 for id in Armies.armies_of(state,player_faction_id()):
  var a = army(id)
  var m = army_movement(id)
  out.append({"id":id,"general":a.commander.name,"army":a.display_name,"units":a.units.size(),"men":Armies.men(state.army_state[id]),
   "where":m.garrison_name if m.garrison != "" else WorldMap.region(WorldMap.region_at(m.position)).get("name","the wilds") if WorldMap.region_at(m.position) != "" else "the wilds",
   "movement":m.points/maxf(1.0,m.max_points),"level":Characters.level(state.army_state[id].commander),"points":Characters.skill_points(state.army_state[id].commander)})
 return out

# Provinces list: the player's provinces with income, growth and public order.
func provinces_list() -> Array:
 var out = []
 var seen = {}
 for sid in state.settlements_of(player_faction_id()):
  var p = WorldMap.province_of(sid)
  if seen.has(p): continue
  seen[p] = true
  var st = province_stats(p)
  out.append({"id":p,"name":province(p).name,"settlement":sid,"income":int(st.income),"growth":int(st.growth),"public_order":int(st.public_order)})
 return out

# Known factions list: every other faction still in the game, with war or peace (attitude comes
# with diplomacy).
func factions_list() -> Array:
 var out = []
 for f in state.factions():
  if f == player_faction_id() or f in state.destroyed: continue
  out.append({"id":f,"name":faction(f).name,"at_war":at_war(f),"settlements":state.settlements_of(f).size(),"armies":Armies.armies_of(state,f).size()})
 return out

# --- Important events (pop-ups, docs/tw-ui-parity.md L8) ----------------------------------------
# Found by comparing the state before and after End Turn: a war declared on you, a settlement of
# yours lost, your house landless, your house destroyed. Which events TW pops up is unverified;
# these are ours.

func _alert_snapshot() -> Dictionary:
 var me = player_faction_id()
 return {"settlements":state.settlements_of(me),"wars":state.factions().filter(func(f): return f != me and at_war(f)),
  "grace":int(state.grace.get(me,-1)),"destroyed":me in state.destroyed}

func alerts_since(before: Dictionary) -> Array:
 var now = _alert_snapshot()
 var out = []
 for f in now.wars:
  if not f in before.wars: out.append({"kind":"war","title":"War declared","text":"%s has declared war on your house." % faction(f).name,"faction":f})
 for sid in before.settlements:
  if not sid in now.settlements:
   var owner = state.settlements[sid].owner
   out.append({"kind":"settlement_lost","title":"Settlement lost","text":"%s has fallen to %s." % [WorldMap.region(sid).settlement.name,faction(owner).get("name","the enemy")],"settlement":sid})
 if now.destroyed and not before.destroyed: out.append({"kind":"destroyed","title":"Your house is destroyed","text":"No settlement was retaken in time. The Grey Scribes close your house's chronicle."})
 elif now.grace>=0 and before.grace<0: out.append({"kind":"landless","title":"Your house is landless","text":"Retake a settlement within %d turn%s or your house is destroyed." % [now.grace,"" if now.grace == 1 else "s"]})
 return out

# --- Land and culture (core/land.gd; game-design §12.13 C) ------------------------------------------

# A region's land: {from, to, value (0-1), stage (0 none, 1 noticeable, 2 very, 3 converted),
# from_color, to_color (strategic map), climate (yield factor for its owner)}.
func land(settlement_id: String) -> Dictionary:
 var e = Land.entry(state,settlement_id)
 var cul = Land.data().cultures
 return {"from":e.from,"to":e.to,"value":float(e.value),"stage":Land.stage(state,settlement_id),
  "from_color":cul.get(e.from,{}).get("map_color","#888888"),"to_color":cul.get(e.to,{}).get("map_color","#888888"),
  "climate":Land.climate_factor(state,settlement_id)}

func culture_name(culture: String) -> String:
 return str(Land.data().cultures.get(culture,{}).get("name",culture.capitalize()))

# Factions the player has met (strategic map legend; diplomacy lists): the player, factions at war
# with the player, and factions with a settlement or army near the player's settlements or armies.
# PLACEHOLDER until contact and envoys exist (docs/war-and-realm.md §7.3: envoys can reach anyone).
static func met_radius() -> float:
 return float(JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_rules.json")).contact.met_radius)

func known_factions() -> Array:
 var me = state.player_faction
 var mine = []
 for sid in state.settlements_of(me): mine.append(WorldMap.settlement_position(sid))
 for id in state.army_state:
  if state.army_state[id].faction == me: mine.append(Movement.position(state,id))
 var out = [me]
 var met = met_radius()
 for f in state.factions():
  if f == me: continue
  if Battles.at_war(state,me,f):
   out.append(f)
   continue
  var near = false
  for sid in state.settlements_of(f):
   var p = WorldMap.settlement_position(sid)
   for q in mine:
    if p.distance_to(q)<met:
     near = true
     break
   if near: break
  if near: out.append(f)
 return out
