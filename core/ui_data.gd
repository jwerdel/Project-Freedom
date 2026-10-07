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
# Event Messages groups (owner spec 2026-10-07): the turn summary (grouped, only what matters to you),
# your wars and battles, your court and realm, and the world this turn (expires after one turn).
const CATEGORIES = [{"id":"turn","name":"Turn Summary"},{"id":"war","name":"Your Wars and Battles"},{"id":"court","name":"Court and Realm"},{"id":"world","name":"World (this turn)"}]

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
 for e in ledger.income:
  match str(e.get("kind","settlement")):
   "trade": out.income.append({"label":"Trade with %s" % WorldMap.faction(e.label).name,"amount":e.amount})
   "title": out.income.append({"label":"Title tolls","amount":e.amount})
   _: out.income.append({"label":"%s (%s)" % [WorldMap.region(e.label).settlement.name,state.settlements[e.label].type],"amount":e.amount})
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
 # Proposals waiting in Diplomacy show in the turn summary and on the End Turn button (no longer a
 # chronicle line repeated every turn, 2026-10-07). The summary is built before the feed is told of
 # the new entries, so the Event Messages show it at once.
 report.alerts = alerts_since(before)
 state.last_summary = _build_summary(report)
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
 # Answers to your envoys this turn: one reply pop-up each (owner spec 2026-10-07).
 for rep in unseen_replies(): report.alerts.append(_reply_alert(rep))
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
 var last = int(state.year)-1 # the year the last End Turn closed
 for e in state.chronicle:
  var cat = str(e.category)
  match category:
   "war": if cat == "war" and _involves_me(e): out.append(e)
   # The world: others' wars, captures, titles and marriages, from the last turn only.
   "world": if cat in ["war","world"] and int(e.year)>=last and not _involves_me(e): out.append(e)
   "turn": pass # the grouped turn summary (turn_summary)
   _: if cat == category and e.get("faction",state.player_faction) == state.player_faction: out.append(e)
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
 # A muster point of a faction calling its banners (seen by everyone: war-and-realm §2.2).
 s.muster = ""
 for f in state.musters:
  if str(state.musters[f].get("point","")) == id: s.muster = str(f)
 return s

# Something can be built or upgraded in this settlement now (TW:WH3 green hammer on the map banner
# and in lists; the building cards show which).
func upgrade_available(id: String) -> bool:
 for i in state.settlements[id].buildings.size():
  if not Construction.in_slot(state,id,i).is_empty(): continue
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
 var out = []
 for i in s.buildings.size():
  var b = s.buildings[i]
  var pending = construction(settlement_id,i)
  var view = {"slot":i,"empty":true}
  if b.has("chain"):
   var c = Buildings.chain(b.chain)
   view = {"slot":i,"chain":b.chain,"name":b.get("name",Buildings.building_name(settlement_id,b.chain,int(b.level))),"visual":c.visual,
    "level":int(b.level),"max_level":Buildings.max_level(b.chain),"main":c.get("main",false),"effects":Buildings.effect_lines(b.chain,int(b.level))}
   # Upgradeable now (TW:WH3 green arrow on the card).
   view.upgrade = pending.is_empty() and s.owner == state.player_faction and Construction.can_build(state,settlement_id,i,b.chain).ok
  if not pending.is_empty():
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

# A construction in progress (in this slot, or the first one with slot -1), or {}: {settlement, slot,
# chain, name, level, turns_left, turns_total, cost, progress (0..1), refund (gold if cancelled now)}.
func construction(settlement_id: String,slot := -1) -> Dictionary:
 var c = Construction.in_progress(state,settlement_id) if slot<0 else Construction.in_slot(state,settlement_id,slot)
 if c.is_empty(): return {}
 return {"settlement":settlement_id,"slot":int(c.slot),"chain":c.chain,"name":Buildings.building_name(settlement_id,c.chain,int(c.level)),"level":int(c.level),
  "turns_left":int(c.turns_left),"turns_total":int(c.turns_total),"cost":int(c.cost),
  "progress":1.0-float(c.turns_left)/maxf(1.0,float(c.turns_total)),"refund":Construction.refund_amount(state,settlement_id,int(c.slot))}

# The realm construction queue (owner spec 2026-10-07): everything building in your settlements,
# soonest first: [construction views as above, plus settlement_name].
func realm_constructions() -> Array:
 var out = []
 for e in Construction.realm_jobs(state,state.player_faction):
  var v = construction(e.settlement,int(e.job.slot))
  v.settlement_name = settlement(e.settlement).name
  out.append(v)
 out.sort_custom(func(a,b): return [a.turns_left,a.settlement_name,a.slot]<[b.turns_left,b.settlement_name,b.slot])
 return out

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

func cancel_construction(settlement_id: String,slot := -1) -> int:
 if state.settlements[settlement_id].owner != state.player_faction: return 0
 var refund = Construction.cancel(state,settlement_id,slot)
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
 # A court character without an army (the court screen's Details): its own career tree and no army.
 if not state.army_state.has(army_id) and state.characters.has(army_id): return _court_character(army_id)
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
 var view = {"army_id":army_id,"name":c.name,"epithet":str(c.get("epithet","")),"level":Characters.level(c),"xp":Characters.xp_progress(c),
  "status":str(c.get("status","ok")),"faction":a.faction,"faction_data":faction(a.faction),"player_owned":a.faction == state.player_faction,
  "stats":Characters.stats(c),"traits":Characters.traits(state,army_id),"rows":rows,"points":Characters.skill_points(c),
  "auto":Characters.auto_on(state,army_id),"army":army(army_id),"men":Armies.men(a),"location":m.garrison_name if m.garrison != "" else WorldMap.region(WorldMap.region_at(m.position)).get("name","the wilds") if WorldMap.region_at(m.position) != "" else "the wilds"}
 # The general as a court member: epithet, life traits, loyalty and history (core/court.gd).
 var cid = str(c.get("character",""))
 if cid != "" and state.characters.has(cid):
  var cv = character_view(cid)
  view.court = cv
  view.epithet = cv.epithet
  for t in cv.traits: view.traits.append({"id":t.id,"name":t.name,"text":"A %s trait, earned from deeds." % t.kind})
 return view

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
  "settlements":towns,"min_population":int(Armies.data().recruitment.min_population),"options":_recruit_options(army_id,mode),"mode":mode,
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
  _host_follow(army_id)
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
 return {"points":pts,"turns":Movement.simulate(pts,m.points,m.max_points,state.road_level).turns,"settlement":str(state.army_state[army_id].get("order_settlement",""))}

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
  # Re-planned toward a moving target; under the hold rule it only redraws the path (no walking).
  if ap.get("plan",{}).get("ok",false): Movement.order(state,id,ap.point,not Movement.holds_orders(state,a.faction))

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
# Declare war (diplomacy-design §7; the dialog shows declaration_preview first). Breaking a treaty is
# betrayal (the V1 rule): only with betray = true, after the dialog spelled out the consequences.
# Returns the chronicle entry ({} if nothing happened).
func declare_war(target_faction: String,betray := false) -> Dictionary:
 var D = load("res://core/diplomacy.gd")
 var pv = D.declaration_preview(state,state.player_faction,target_faction)
 if pv.betrayal != "" and not betray: return {}
 var r = D.declare_war(state,state.player_faction,target_faction)
 var e = r.get("entry",{})
 if r.get("betrayal",false): e = Chronicle.entry(state.year,"war","Betrayal","You broke your word to %s. Every hand is now raised against you." % faction(target_faction).name)
 if not e.is_empty(): event_added.emit(e)
 changed.emit()
 return e

func declaration_preview(target_faction: String) -> Dictionary:
 var pv = load("res://core/diplomacy.gd").declaration_preview(state,state.player_faction,target_faction)
 pv.ally_names = pv.allies.map(func(f): return faction(f).name)
 pv.angered_names = pv.angered.map(func(f): return faction(f).name)
 return pv

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

func _diplomacy():
 return load("res://core/diplomacy.gd")

# --- Diplomacy screen (docs/tw-ui-parity.md §15; docs/diplomacy-design.md) ---------------------
# Real: war and peace status, holdings and strength, faction tendencies, who is at war with whom.
# PLACEHOLDERS until the diplomacy system: attitude (neutral start, diplomacy-design §3.3),
# reliability, deal chances and every treaty but war.
const ATTITUDE_STEPS = ["Hostile","Unfriendly","Indifferent","Friendly","Very friendly"]

func diplomacy_faction(id: String) -> Dictionary:
 var D = load("res://core/diplomacy.gd")
 var Rep = load("res://core/reputation.gd")
 var V = load("res://core/vassals.gd")
 var f = faction(id)
 var me = state.player_faction
 var men = 0
 for a in Armies.armies_of(state,id): men += Armies.men(state.army_state[a])
 var wars = state.factions().filter(func(o): return o != id and Battles.at_war(state,id,o)).map(func(o): return faction(o).name)
 var att = D.attitude(state,id,me) if id != me else 0.0
 var treaties = []
 var t = D.treaty(state,id,me)
 if not t.is_empty() and id != me: treaties.append({"name":str(t.kind).capitalize(),"left":D.protected_turns_left(state,id,me)})
 for n in D.d(state).agreements.get(D.key(id,me),{}):
  var label = {"trade":"Trade","defensive":"Defensive pact","nap":"Non-aggression"}.get(n,"")
  if n.begins_with("access:"): label = "Military access (%s)" % ("theirs" if n == "access:"+me else "yours")
  if n.begins_with("embassy:"): label = "Embassy (%s)" % ("yours" if n == "embassy:"+me else "theirs")
  if label != "": treaties.append({"name":label,"left":0})
 if V.liege_of(state,id) == me: treaties.append({"name":"Your vassal","left":0})
 if V.liege_of(state,me) == id: treaties.append({"name":"Your liege","left":0})
 var st = Rep.standing(state,id)
 return {"id":id,"name":f.name,"faction_data":f,"realm":f.get("realm",""),"seat":f.get("seat",""),"culture":str(f.get("culture","")).capitalize(),
  "settlements":state.settlements_of(id).size(),"armies":Armies.armies_of(state,id).size(),"men":men,
  "traits":f.get("traits",[]).map(func(x): return str(x).capitalize()),"wars":wars,"at_war":id != me and at_war(id),
  "attitude":att,"face":D.face(att),"attitude_label":ATTITUDE_STEPS[D.face(att)],"attitude_reasons":D.attitude_reasons(state,id,me),
  "relation":D.relation(state,me,id),"contact":id == me or D.has_contact(state,me,id),"treaties":treaties,
  "reputation":Rep.labels(state,me if id != me else "",id),"standing":st,
  "reliability":"Treacherous" if id in D.d(state).betrayers else ("Reliable" if float(Rep.perceived(state,"",id).trust)>-30.0 else "Untrustworthy"),
  "court":D.court_visibility(state,me,id),"envoy":D.envoys_from(state,me).filter(func(e): return e.to == id).map(func(e): return {"kind":e.kind,"arrive":int(e.arrive)-int(state.turn)}),
  "minor":D.is_minor(id),"untouchable":D.untouchable(id),"liege":V.liege_of(state,id)}

# The player's faction and every other faction: those met first (contact), then the rest (envoys can
# reach anyone, war-and-realm §0.2), the player first.
func diplomacy() -> Dictionary:
 var D = load("res://core/diplomacy.gd")
 var met = []
 var unmet = []
 for f in state.factions():
  if f == player_faction_id() or f in state.destroyed or state.settlements_of(f).is_empty(): continue
  var v = diplomacy_faction(f)
  if v.contact: met.append(v)
  else: unmet.append(v)
 var envoys = D.envoys_from(state,player_faction_id()).map(func(e): return {"to":e.to,"name":faction(e.to).name,"kind":e.kind,"turns":int(e.arrive)-int(state.turn)})
 return {"me":diplomacy_faction(player_faction_id()),"factions":met+unmet,"envoys":envoys,"proposals":proposals()}

# --- Diplomacy: offers, envoys, proposals, dossiers (core/diplomacy.gd) -------------------------------

# The item palette for a deal with faction f, grouped as in TW:WH3, each with its eligibility both ways.
func offer_palette(f: String) -> Array:
 var D = load("res://core/diplomacy.gd")
 var me = player_faction_id()
 var out = []
 var treaty_items = [["alliance","Military alliance"],["defensive","Defensive pact"],["nap","Non-aggression pact"],["ceasefire","Ceasefire"],["peace","Peace"],["trade","Trade agreement"],["embassy","Embassy"]]
 for t in treaty_items:
  var e = D.eligible(state,me,f,{"kind":t[0]})
  out.append({"group":"Treaties","item":{"kind":t[0]},"name":t[1],"give":e,"take":e})
 out.append({"group":"Treaties","item":{"kind":"access"},"name":"Military access","give":D.eligible(state,me,f,{"kind":"access"}),"take":D.eligible(state,f,me,{"kind":"access"})})
 out.append({"group":"Treaties","item":{"kind":"vassalage"},"name":"Vassalage","give":D.eligible(state,me,f,{"kind":"vassalage"}),"take":D.eligible(state,f,me,{"kind":"vassalage"})})
 for g in [500,1000,2500]:
  out.append({"group":"Payments","item":{"kind":"gold","amount":g},"name":"%d gold" % g,"give":D.eligible(state,me,f,{"kind":"gold","amount":g}),"take":D.eligible(state,f,me,{"kind":"gold","amount":g})})
 for g in [50,150]:
  out.append({"group":"Payments","item":{"kind":"tribute","amount":g,"turns":10},"name":"Tribute %d a turn (10 turns)" % g,"give":D.eligible(state,me,f,{"kind":"tribute","amount":g}),"take":D.eligible(state,f,me,{"kind":"tribute","amount":g})})
 for sid in state.settlements_of(me)+state.settlements_of(f):
  var mine = state.settlements[sid].owner == me
  var it = {"kind":"region","settlement":sid}
  out.append({"group":"Land","item":it,"name":WorldMap.region(sid).settlement.name,"give":D.eligible(state,me,f,it) if mine else {"ok":false,"reason":"Not yours"},"take":D.eligible(state,f,me,it) if not mine else {"ok":false,"reason":"Already yours"}})
 # Marriages: your unmarried adults with theirs (when you can see their court).
 var C = load("res://core/court.gd")
 if D.court_visibility(state,me,f) != "unknown":
  for a in C.members(state,me):
   var ca = state.characters[a]
   if str(ca.spouse) != "" or not C.is_adult(ca) or ca.legendary: continue
   for b in C.members(state,f):
    var cb = state.characters[b]
    if cb.gender == ca.gender or str(cb.spouse) != "" or not C.is_adult(cb) or cb.legendary: continue
    var it = {"kind":"marriage","a":a,"b":b}
    var e = C.can_marry(state,a,b)
    out.append({"group":"Characters","item":it,"name":"Marriage: %s and %s" % [C.full_name(ca),C.full_name(cb)],"give":e,"take":e})
 for id in C.members(state,f)+C.members(state,me):
  var c = state.characters[id]
  if str(c.role) == "prisoner:"+me: out.append({"group":"Characters","item":{"kind":"captive","character":id},"name":"Release %s" % C.full_name(c),"give":{"ok":true,"reason":""},"take":{"ok":false,"reason":"Not their captive"}})
 return out

# The receiver's view of an offer (score, chance label, reasons with numbers).
func evaluate_offer(f: String,offer: Dictionary) -> Dictionary:
 return load("res://core/diplomacy.gd").evaluate(state,player_faction_id(),f,offer)

func propose_offer(f: String,offer: Dictionary) -> Dictionary:
 var r = load("res://core/diplomacy.gd").propose(state,player_faction_id(),f,offer)
 if r.get("accept",false): add_event("court","Agreement with %s" % faction(f).name,"They accept your proposal.")
 # An answer at once (you have met): the reply pop-up now. A sent envoy answers when it arrives.
 if not r.get("reply",{}).is_empty(): alert.emit(_reply_alert(r.reply))
 changed.emit()
 return r

func send_envoy(f: String,kind := "embassy") -> Dictionary:
 var r = load("res://core/diplomacy.gd").send_envoy(state,player_faction_id(),f,kind)
 changed.emit()
 return r

func cancel_agreement(f: String,name: String) -> Dictionary:
 var r = load("res://core/diplomacy.gd").cancel(state,player_faction_id(),f,name)
 changed.emit()
 return r

# AI proposals and calls to arms waiting for the player's answer (diplomacy-design §15).
func proposals() -> Array:
 var out = []
 var D = load("res://core/diplomacy.gd")
 var i = 0
 for p in D.d(state).proposals:
  if p.to == player_faction_id():
   var v = {"index":i,"from":p.from,"name":faction(p.from).name,"offer":p.offer,"call":str(p.offer.get("call",""))}
   v.text = "%s calls you to war against %s" % [faction(p.from).name,faction(v.call).name] if v.call != "" else _offer_text(p.from,p.offer)
   out.append(v)
  i += 1
 return out

func _offer_text(f: String,offer: Dictionary) -> String:
 var parts = []
 for it in offer.get("give",[]): parts.append("they offer "+_item_name(it))
 for it in offer.get("take",[]): parts.append("they ask for "+_item_name(it))
 return "%s: %s" % [faction(f).name,", ".join(parts)]

func _item_name(it: Dictionary) -> String:
 var C = load("res://core/court.gd")
 match str(it.kind):
  "gold": return "%d gold" % int(it.amount)
  "tribute": return "tribute of %d a turn" % int(it.amount)
  "region": return WorldMap.region(it.settlement).settlement.name
  "marriage": return "a marriage (%s and %s)" % [C.full_name(C.get_char(state,it.a)),C.full_name(C.get_char(state,it.b))]
  "vassalage": return "vassalage"
  "access": return "military access"
  "nap": return "a non-aggression pact"
  "defensive": return "a defensive pact"
 return str(it.kind)

func answer_proposal(index: int,accept: bool,answer := "") -> Dictionary:
 var D = load("res://core/diplomacy.gd")
 var list = D.d(state).proposals
 if index<0 or index>=list.size(): return {"ok":false}
 var p = list[index]
 if p.offer.has("call"):
  D.answer_call(state,p.from,str(p.offer.call),answer if answer != "" else ("join" if accept else "refuse"))
 else:
  list.remove_at(index)
  if accept:
   # The AI's offer, checked again from the player's side only for eligibility.
   var ok = true
   for it in p.offer.get("give",[]): ok = ok and D.eligible(state,p.from,player_faction_id(),it).ok
   for it in p.offer.get("take",[]): ok = ok and D.eligible(state,player_faction_id(),p.from,it).ok
   if ok: D.apply_offer(state,p.from,player_faction_id(),p.offer)
 changed.emit()
 return {"ok":true}

# A faction's dossier (diplomacy-design §4): court (when visible), blurbs in the Grey Scribes' voice
# from real history, who hates whom, reputation, tendencies, treaties and wars.
func dossier(f: String) -> Dictionary:
 var D = load("res://core/diplomacy.gd")
 var C = load("res://core/court.gd")
 var vis = D.court_visibility(state,player_faction_id(),f)
 var court = []
 if vis != "unknown":
  for id in C.members(state,f):
   if vis == "basic" and id != C.ruler(state,f): continue
   court.append(character_view(id))
 var hates = []
 for g in state.factions():
  if g == f or state.settlements_of(g).is_empty(): continue
  var a = D.attitude(state,f,g)
  if a<=-25.0:
   var why = D.attitude_reasons(state,f,g)
   hates.append({"faction":faction(g).name,"value":a,"why":why[0].text if not why.is_empty() else ""})
 hates.sort_custom(func(x,y): return x.value<y.value)
 var v = diplomacy_faction(f)
 v.visibility = vis
 v.court_members = court
 v.hates = hates.slice(0,5)
 v.blurbs = court.map(func(c): return {"name":c.full_name,"text":c.blurb})
 v.history = D.d(state).log.filter(func(l): return faction(f).name in l.text).map(func(l): return "Year %d. %s" % [l.year,l.text]).slice(-6)
 return v

# --- Court and characters (core/court.gd; game-design §4) ---------------------------------------------

func character_view(id: String) -> Dictionary:
 var C = load("res://core/court.gd")
 var c = C.get_char(state,id)
 if c.is_empty(): return {}
 var role = str(c.role)
 var role_text = {"ruler":"Ruler","courtier":"Courtier","child":"Child","exile":"In exile"}.get(role,role.capitalize())
 if role.begins_with("governor:"): role_text = "Governor of %s" % WorldMap.region(role.get_slice(":",1)).settlement.name
 if role.begins_with("general:") or str(c.army) != "": role_text = ("Ruler, leads " if C.ruler(state,c.faction) == id else "Leads ")+(state.army_state[c.army].display_name if state.army_state.has(c.army) else "an army")
 if role.begins_with("prisoner:"): role_text = "Prisoner of %s" % faction(role.get_slice(":",1)).name
 if C.heir(state,c.faction) == id: role_text = "Heir · "+role_text
 var titles = []
 for t in state.titles:
  if str(state.titles[t].get("character","")) == id: titles.append(load("res://core/titles.gd").data().titles[t].name)
 var blurb = "%s, %s%s." % [C.full_name(c),role_text.to_lower(),(", "+str(int(c.age))+" years old")]
 if not c.history.is_empty(): blurb = "The Scribes record of %s: %s" % [c.name,str(c.history[-1].text).to_lower()]
 return {"id":id,"name":str(c.name),"house":str(c.house),"full_name":C.full_name(c),"epithet":str(c.epithet),"age":int(c.age),"gender":str(c.gender),
  "race":str(c.race),"culture":str(c.culture),"career":str(c.career),"career_name":str(C.data().careers.get(str(c.career),{}).get("name","")),"career_pending":bool(c.career_pending),
  "level":int(c.level),"xp":float(c.xp),"next_xp":C.xp_for_level(int(c.level)+1),"points":C.skill_points(c),"traits":C.visible_traits(c),"loyalty":int(c.loyalty),
  "loyalty_reasons":C.loyalty_reasons(c),"role":role,"role_text":role_text,"spouse":str(c.spouse),"father":str(c.father),"mother":str(c.mother),"children":c.children.duplicate(),
  "immortal":bool(c.immortal),"legendary":bool(c.legendary),"dead":bool(c.dead),"faction":str(c.faction),"army":str(c.army),"history":c.history.duplicate(),
  "titles":titles,"ruler":C.ruler(state,c.faction) == id,"heir":C.heir(state,c.faction) == id,"blurb":blurb,"defeated":int(c.defeated_until)>=0,"skills":c.skills.duplicate()}

# The player's court (or another faction's when visible): ruler, heir, members by family branch.
func court_view(f := "") -> Dictionary:
 var C = load("res://core/court.gd")
 f = f if f != "" else player_faction_id()
 var members = C.members(state,f).map(func(id): return character_view(id))
 return {"faction":f,"faction_data":faction(f),"ruler":C.ruler(state,f),"heir":C.heir(state,f),"members":members,"pending_careers":C.careers_pending(state,f),
  "careers":C.data().careers.keys().map(func(k): return {"id":k,"name":C.data().careers[k].name,"text":C.data().careers[k].text}),
  "size":members.size(),"cap":C.court_cap(state,f),"birth_factor":C.birth_factor(state,f)}

func _court_call(r: Dictionary) -> Dictionary:
 changed.emit()
 return r

func set_heir(id: String) -> Dictionary: return _court_call(load("res://core/court.gd").set_heir(state,player_faction_id(),id))
func make_ruler(id: String) -> Dictionary: return _court_call(load("res://core/court.gd").make_ruler(state,player_faction_id(),id,"chosen"))
func choose_career(id: String,career: String) -> Dictionary: return _court_call(load("res://core/court.gd").choose_career(state,id,career))
func appoint_governor(id: String,sid: String) -> Dictionary: return _court_call(load("res://core/court.gd").appoint_governor(state,player_faction_id(),id,sid))
func gift_character(id: String,gold: int) -> Dictionary: return _court_call(load("res://core/court.gd").gift(state,player_faction_id(),id,gold))
func rename_character(id: String,new_name: String) -> bool:
 var ok = load("res://core/court.gd").rename(state,id,new_name)
 if ok: changed.emit()
 return ok
func take_character_skill(id: String,skill: String) -> bool:
 var ok = load("res://core/court.gd").take_skill(state,id,skill)
 if ok: changed.emit()
 return ok

# Marry two characters: within your court at once; across courts as an offer to the other faction.
func arrange_marriage(a: String,b: String) -> Dictionary:
 var C = load("res://core/court.gd")
 var cb = C.get_char(state,b)
 if cb.is_empty(): return {"ok":false,"reason":"Unknown character"}
 if str(cb.faction) == player_faction_id(): return _court_call(C.marry(state,a,b))
 return propose_offer(str(cb.faction),{"give":[{"kind":"marriage","a":a,"b":b}],"take":[]})

# Characters the player could marry `id` to: own court and courts in contact (whose court is visible).
func marriage_candidates(id: String) -> Array:
 var C = load("res://core/court.gd")
 var D = load("res://core/diplomacy.gd")
 var out = []
 for f in state.courts:
  if f != player_faction_id() and (not D.has_contact(state,player_faction_id(),f) or D.court_visibility(state,player_faction_id(),f) == "unknown" or Battles.at_war(state,player_faction_id(),f)): continue
  for o in C.members(state,f):
   if C.can_marry(state,id,o).ok and not state.characters[o].legendary:
    var v = character_view(o)
    v.faction_name = faction(f).name
    out.append(v)
 return out

# --- Realm: standing, reputation, titles, vassals, banners, hosts -------------------------------------

func realm_standing(f := "") -> Dictionary:
 return load("res://core/realm_standing.gd").summary(state,f if f != "" else player_faction_id())

func reputation_view(f := "") -> Dictionary:
 var Rep = load("res://core/reputation.gd")
 f = f if f != "" else player_faction_id()
 var e = Rep.entry(state,f)
 return {"standing":Rep.standing(state,f),"labels":Rep.labels(state,"",f),"ruler":e.ruler,"house":e.house,"first_impressions":Rep.in_first_impressions(state,f),"deeds":e.deeds.slice(-8)}

func titles_panel() -> Array:
 var T = load("res://core/titles.gd")
 var out = T.panel(state,player_faction_id())
 for t in out: t.holder_name = faction(t.holder).name if t.holder != "" else ""
 return out

func grant_title(title: String,to_faction := "",character := "") -> Dictionary:
 var r = load("res://core/titles.gd").grant(state,title,player_faction_id(),to_faction,character)
 changed.emit()
 return r

func vassals_view() -> Array:
 var V = load("res://core/vassals.gd")
 var out = []
 for f in V.vassals_of(state,player_faction_id()):
  var s = V.summary(state,f)
  s.name = faction(f).name
  s.faction_data = faction(f)
  s.settlements = state.settlements_of(f).size()
  s.armies = Armies.armies_of(state,f).size()
  out.append(s)
 return out

func set_vassal_goal(f: String,goal: String) -> bool:
 var ok = load("res://core/vassals.gd").set_econ_goal(state,f,goal)
 changed.emit()
 return ok

func gift_vassal(f: String,gold: int) -> Dictionary:
 var r = load("res://core/vassals.gd").gift(state,player_faction_id(),f,gold)
 changed.emit()
 return r

# Order an ally or vassal: kind attack / besiege / defend, target a settlement or army id.
func order_ally(f: String,kind: String,target: String,gold := 0) -> Dictionary:
 var r = load("res://core/diplomacy.gd").give_order(state,player_faction_id(),f,kind,target,gold)
 changed.emit()
 return r

func banner_terms() -> Dictionary:
 var H = load("res://core/hosts.gd")
 var t = H.terms(state,player_faction_id())
 var plan = H.levy_plan(state,player_faction_id(),float(t.turnout))
 var n = 0
 for k in plan: n += int(plan[k])
 t.levies = n
 t.vassals = load("res://core/vassals.gd").vassals_of(state,player_faction_id()).size()
 t.mustering = H.mustering(state,player_faction_id())
 t.muster = state.musters.get(player_faction_id(),{})
 return t

func call_banners(sid: String) -> Dictionary:
 var r = load("res://core/hosts.gd").call_banners(state,player_faction_id(),sid)
 if r.ok: add_event("court","The banners are called","Your banners gather at %s: %d levy units%s, %s." % [WorldMap.region(sid).settlement.name,int(r.levies),(" and %d vassal hosts" % int(r.contingents)) if int(r.contingents)>0 else "","setting out at once" if int(r.turns)<=0 else "setting out in %d turns" % int(r.turns)])
 changed.emit()
 return r

func dismiss_levies() -> int:
 var n = load("res://core/hosts.gd").dismiss_levies(state,player_faction_id())
 changed.emit()
 return n

func form_host(leader: String,members: Array) -> Dictionary:
 var r = load("res://core/hosts.gd").form_host(state,leader,members)
 changed.emit()
 return r

func leave_host(army_id: String):
 load("res://core/hosts.gd").leave_host(state,army_id)
 changed.emit()

func host_of(army_id: String) -> String:
 return load("res://core/hosts.gd").host_of(state,army_id)

# Own armies near an army (that could join its Host).
func armies_near(army_id: String,radius := 120.0) -> Array:
 var at = Movement.position(state,army_id)
 var f = state.army_state[army_id].faction
 return Armies.armies_of(state,f).filter(func(id): return id != army_id and Movement.position(state,id).distance_to(at)<=radius)

# Fallen houses awaiting the player's choice (game-design §4.10).
func absorptions() -> Array:
 return state.absorptions.map(func(a): return {"fallen":a.fallen,"name":faction(a.fallen).name,"settlement":a.settlement,"settlement_name":WorldMap.region(a.settlement).settlement.name})

func resolve_absorption(fallen: String,choice: String) -> Dictionary:
 var a = state.absorptions.filter(func(x): return x.fallen == fallen)
 if a.is_empty(): return {"ok":false}
 var r = load("res://core/court.gd").resolve_absorption(state,player_faction_id(),fallen,a[0].settlement,choice)
 changed.emit()
 return r

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
# [kind, label, short text on the End Turn button, icon] in priority order (owner spec 2026-10-07: the
# button itself shows the top item).
const WARNINGS = [["choices","A choice awaits","A choice awaits you","chronicle"],["diplomacy","Diplomatic replies","Envoys await your answer","diplomacy"],
 ["funds","Low funds","Treasury will run dry","coin"],["skill_points","Unspent skill points","Lord has skill points","star"],
 ["settlement_upgrade","Settlement can be upgraded","Settlement can be upgraded","spire"],["construction","Idle construction slots","Idle building slot","hammer"],
 ["orders","Orders waiting","Army order waiting","horn"],["army_moves","Lords with movement left","Lord has not moved","armies"],["recruit","Army can recruit","Army can recruit","sword"]]

func end_turn_warnings(enabled := {}) -> Array:
 var out = []
 var f = player_faction_id()
 for w in WARNINGS:
  if not enabled.get(w[0],true): continue
  var items = []
  match w[0]:
   "choices":
    # Absorbed families to decide (core/court.gd) and children whose career is due.
    for a in absorptions(): items.append({"type":"absorption","id":str(a.get("fallen","")),"name":"The fate of %s" % str(a.get("name",a.get("fallen","")))})
    if state.get("courts") != null and not state.courts.is_empty():
     for cid in load("res://core/court.gd").careers_pending(state,f): items.append({"type":"career","id":cid,"name":"%s chooses a path" % state.characters[cid].name})
   "diplomacy":
    for rep in unseen_replies(): items.append({"type":"reply","id":str(rep.id),"name":"%s answers your envoy" % faction(rep.from).name})
    for p in proposals(): items.append({"type":"diplomacy","id":str(p.get("from","")),"name":str(p.get("text","An offer"))})
   "orders":
    for id in waiting_orders(): items.append({"type":"army","id":id,"name":state.army_state[id].display_name})
   "funds":
    if Realm.in_debt(state,f) or int(state.treasury[f])+int(Economy.faction_ledger(state,f).net)<0:
     items.append({"type":"faction","id":f,"name":"Treasury"})
   "construction":
    # An empty slot, not building, with something it could build now (every slot builds at once).
    for sid in state.settlements_of(f):
     var can = false
     for i in state.settlements[sid].buildings.size():
      if state.settlements[sid].buildings[i].has("chain") or not Construction.in_slot(state,sid,i).is_empty(): continue
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
  if not items.is_empty(): out.append({"kind":w[0],"label":w[1],"short":w[2],"icon":w[3],"items":items})
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

# A court character's details (no army): stats at its level, its career's skill tree, traits.
func _court_character(id: String) -> Dictionary:
 var C = load("res://core/court.gd")
 var c = C.get_char(state,id)
 var cv = character_view(id)
 var rows = []
 for r in C.career_rows(c):
  var skills = []
  for s in r.skills:
   var can = C.can_take_skill(c,s.id)
   skills.append({"id":s.id,"name":s.name,"level":int(s.level),"text":s.text,"taken":s.id in c.skills,"available":can.ok,"reason":can.reason})
  rows.append({"id":r.id,"name":r.name,"function":r.function,"skills":skills})
 var traits = cv.traits.map(func(t): return {"id":t.id,"name":t.name,"text":"A %s trait, earned from deeds." % t.kind})
 return {"army_id":id,"character_id":id,"name":cv.full_name,"epithet":cv.epithet,"level":cv.level,"xp":{"xp":cv.xp,"from":C.xp_for_level(cv.level),"to":cv.next_xp},
  "status":"ok","faction":cv.faction,"faction_data":faction(cv.faction),"player_owned":cv.faction == state.player_faction,
  "stats":Characters.stats({"rank":cv.level}),"traits":traits,"rows":rows,"points":cv.points,"auto":false,"army":{},"men":0,"location":cv.role_text,"court":cv}

# A Host's members march with their leader when the player orders it (core/hosts.gd follow).
func _host_follow(army_id: String):
 if state.get("hosts") == null or not state.hosts.has(army_id): return
 var Hosts = load("res://core/hosts.gd")
 var before = {}
 for m in state.hosts[army_id].members: before[m] = Movement.position(state,m)
 Hosts.follow(state)
 for m in before:
  if state.army_state.has(m) and Movement.position(state,m) != before[m]: army_moved.emit(m,[before[m],Movement.position(state,m)])

# Waiting multi-turn orders (Movement.holds_orders): the player's armies whose order still has a
# path and who have points to walk it. continue_orders walks them (one army or all).
func waiting_orders() -> Array:
 var out = []
 for id in state.armies_of(state.player_faction):
  var a = state.army_state[id]
  if not a.get("order",[]).is_empty() and float(a.points)>0.5: out.append(id)
 return out

func continue_orders(ids := []) -> int:
 var n = 0
 for id in (ids if not ids.is_empty() else waiting_orders()):
  if not state.army_state.has(id) or state.army_state[id].faction != state.player_faction: continue
  var walked = Movement.continue_order(state,id)
  if walked.size()>1:
   n += 1
   army_moved.emit(id,walked)
   _host_follow(id)
 if n>0: changed.emit()
 return n

# True when a settlement has walls (besiege rather than storm; core/ai.gd walled).
func settlement_walled(sid: String) -> bool:
 return state.settlements.has(sid) and load("res://core/ai.gd").walled(state,sid)

# The recruitment drawer's cards, one per unit (owner spec 2026-10-07): the local drawer shows each
# unit once from its best source (local, else global); the global drawer only the units that cannot
# be recruited locally.
func _recruit_options(army_id: String,mode: String) -> Array:
 if mode == "global":
  var here = {}
  for o in Armies.options(state,army_id,"local"):
   if o.available: here[o.unit] = true
  return Armies.options(state,army_id,"global").filter(func(o): return not here.has(o.unit))
 return Armies.best_options(state,army_id)

# --- Replies to your envoys and proposals (owner spec 2026-10-07) -------------------------------------

# Replies not yet shown: [reply records, see Diplomacy.add_reply].
func unseen_replies() -> Array:
 return load("res://core/diplomacy.gd").d(state).replies.filter(func(r): return not bool(r.seen))

func mark_reply_seen(id: int):
 for r in load("res://core/diplomacy.gd").d(state).replies:
  if int(r.id) == id: r.seen = true
 changed.emit()

# A reply as the pop-up shows it: {kind "reply", id, faction, faction_data, ruler (character view for
# the portrait), ruler_name, title, blurb (their words), outcome, ok}.
func reply_view(r: Dictionary) -> Dictionary:
 var D = load("res://core/diplomacy.gd")
 var C = load("res://core/court.gd")
 var f = str(r.from)
 var cfg = D.data().replies
 var att = D.attitude(state,f,player_faction_id())
 var tone = "warm" if att>=float(cfg.warm_at) else ("cordial" if att>=float(cfg.cordial_at) else ("hostile" if att<=float(cfg.hostile_at) else "cool"))
 var ok = bool(r.ok)
 var line = ""
 match str(r.kind):
  "embassy": line = str(cfg.embassy.accept if ok else cfg.embassy.decline)
  "contact": line = str(cfg.contact.accept)
  _:
   var lines = cfg.accept[tone] if ok else cfg.decline[tone]
   line = str(lines[int(r.id)%lines.size()])
 var reason = str(r.reason).trim_suffix(".")
 line = line.replace("{us}",faction(f).name).replace("{you}",faction(player_faction_id()).name).replace("{reason}",reason.to_lower() if reason != "" else "it is not in our interest")
 var rid = C.ruler(state,f) if state.get("courts") != null else ""
 var ruler = character_view(rid) if rid != "" and state.characters.has(rid) else {}
 var what = {"embassy":"your embassy","contact":"your envoy"}.get(str(r.kind),"")
 if what == "":
  var parts = []
  for it in r.get("offer",{}).get("give",[]): parts.append(_item_name(it))
  for it in r.get("offer",{}).get("take",[]): parts.append("you ask for "+_item_name(it))
  what = ", ".join(parts) if not parts.is_empty() else "your proposal"
 var outcome = ("Accepted: %s." % what) if ok else ("Declined: %s." % what)
 return {"kind":"reply","id":int(r.id),"faction":f,"faction_data":faction(f),"ruler":ruler,"ruler_name":str(ruler.get("full_name",ruler.get("name",faction(f).name))),
  "title":"%s answers" % faction(f).name,"blurb":line,"outcome":outcome,"ok":ok,"text":"%s\n%s" % [line,outcome]}

func _reply_alert(r: Dictionary) -> Dictionary:
 return reply_view(r)

# Envoys of yours on the road: [{to, name, kind, turns}] (the diplomacy screen lists them).
func envoys_on_the_road() -> Array:
 var D = load("res://core/diplomacy.gd")
 return D.envoys_from(state,player_faction_id()).map(func(e): return {"to":e.to,"name":faction(e.to).name,"kind":str(e.kind),"turns":maxi(0,int(e.arrive)-int(state.turn))})

func reply_by_id(id: int) -> Dictionary:
 for r in load("res://core/diplomacy.gd").d(state).replies:
  if int(r.id) == id: return r
 return {}

# Agreements already active between you and f (owner spec 2026-10-07): they leave the Add Item lists
# and show as "Active" with Cancel instead. [{kind, side (give/take/both), name, cancel (the name for
# cancel_agreement), protected (turns before it may be cancelled)}].
func active_items(f: String) -> Array:
 var D = load("res://core/diplomacy.gd")
 var me = player_faction_id()
 var out = []
 var t = D.treaty(state,me,f)
 if not t.is_empty():
  var k = str(t.kind)
  out.append({"kind":k,"side":"both","name":{"alliance":"Military alliance","peace":"Peace","ceasefire":"Ceasefire","defensive":"Defensive pact","nap":"Non-aggression pact"}.get(k,k.capitalize()),"cancel":k,"protected":D.protected_turns_left(state,me,f)})
 var ag = D.d(state).agreements.get(D.key(me,f),{})
 for k in ["trade","defensive","nap"]:
  if ag.has(k): out.append({"kind":k,"side":"both","name":{"trade":"Trade agreement","defensive":"Defensive pact","nap":"Non-aggression pact"}[k],"cancel":k,"protected":0})
 if ag.has("embassy:"+me): out.append({"kind":"embassy","side":"both","name":"Embassy (yours)","cancel":"embassy:"+me,"protected":0})
 if ag.has("access:"+f): out.append({"kind":"access","side":"give","name":"Military access (theirs, in your land)","cancel":"access:"+f,"protected":0})
 if ag.has("access:"+me): out.append({"kind":"access","side":"take","name":"Military access (yours, in their land)","cancel":"access:"+me,"protected":0})
 return out

# True when an item is already active on this side of a deal with f.
func item_active(f: String,item: Dictionary,side: String) -> bool:
 for a in active_items(f):
  if a.kind == str(item.get("kind","")) and (a.side == "both" or a.side == side): return true
 return false

# --- The turn summary (owner spec 2026-10-07) ----------------------------------------------------------
# Only what matters to you, short and grouped: your settlements, your armies and battles, diplomacy,
# your court, threats near your borders. Every row jumps to its subject: {text, target {type, id}}.
# Built once after End Turn into state.last_summary (saved); threats are read live.
const SUMMARY_GROUPS = [["settlements","Your settlements"],["armies","Your armies and battles"],["diplomacy","Diplomacy"],["court","Your court"],["threats","Threats near your borders"]]
const THREAT_METRES = 450.0

func _build_summary(report: Dictionary) -> Dictionary:
 var me = player_faction_id()
 var g = {"settlements":[],"armies":[],"diplomacy":[],"court":[]}
 for c in report.get("completed",[]):
  if c.faction == me: g.settlements.append({"text":"%s completed in %s" % [c.name,settlement(c.settlement).name],"target":{"type":"settlement","id":c.settlement}})
 for ev in report.get("sieges",[]):
  var sid = str(ev.get("settlement",""))
  if sid == "" or not state.settlements.has(sid): continue
  if state.settlements[sid].owner == me or str(ev.get("faction","")) == me:
   var what = {"siege_lifted":"The siege of %s is lifted","surrendered":"%s surrendered"}.get(str(ev.kind),"")
   if what != "": g.settlements.append({"text":what % settlement(sid).name,"target":{"type":"settlement","id":sid}})
 var recruits = {}
 for r in report.get("recruited",[]):
  if r.faction == me: recruits[r.army] = int(recruits.get(r.army,0))+1
 for id in recruits:
  if state.army_state.has(id): g.armies.append({"text":"%d unit%s joined %s" % [recruits[id],"" if recruits[id] == 1 else "s",state.army_state[id].display_name],"target":{"type":"army","id":id}})
 for e in report.get("entries",[]):
  var cat = str(e.get("category",""))
  if cat == "war" and _involves_me(e):
   var t = {"type":"settlement","id":str(e.settlement)} if e.has("settlement") else {"type":"faction","id":str(e.get("with",e.get("faction","")))}
   g.armies.append({"text":str(e.title)+(": "+str(e.text) if str(e.text).length()<90 else ""),"target":t})
  elif cat == "court" and str(e.get("faction","")) == me and str(e.title) != "Envoys await you":
   g.court.append({"text":str(e.text) if str(e.text) != "" else str(e.title),"target":{"type":"court","id":""}})
 for a in report.get("alerts",[]):
  if a.kind == "war": g.diplomacy.append({"text":a.text,"target":{"type":"diplomacy","id":str(a.faction)}})
  if a.kind == "settlement_lost": g.settlements.append({"text":a.text,"target":{"type":"settlement","id":str(a.settlement)}})
 for rep in unseen_replies(): g.diplomacy.append({"text":"%s answers: %s" % [faction(rep.from).name,"accepted" if rep.ok else "declined"],"target":{"type":"reply","id":str(rep.id)}})
 var props = proposals()
 if not props.is_empty(): g.diplomacy.append({"text":"%d proposal%s your answer" % [props.size()," awaits" if props.size() == 1 else "s await"],"target":{"type":"diplomacy","id":str(props[0].from)}})
 for a in report.get("ai",{}).get("realm",{}).get("actions",[]):
  if str(a.get("with","")) == me and str(a.action) in ["alliance","peace","trade","vassalize","seek_protection"]:
   g.diplomacy.append({"text":"%s: %s with you" % [faction(a.faction).name,{"alliance":"an alliance","peace":"peace","trade":"trade","vassalize":"fealty","seek_protection":"fealty"}[str(a.action)]],"target":{"type":"diplomacy","id":str(a.faction)}})
 return {"year":int(report.get("year",state.year-1)),"groups":g}

# Did a chronicle entry concern the player (a side of it, or a settlement of theirs)?
func _involves_me(e: Dictionary) -> bool:
 var me = player_faction_id()
 if str(e.get("faction","")) == me or str(e.get("with","")) == me: return true
 var sid = str(e.get("settlement",""))
 return sid != "" and state.settlements.has(sid) and state.settlements[sid].owner == me

# The Event Messages' summary: [{id, name, rows: [{text, target}]}], empty groups left out.
func turn_summary() -> Array:
 var stored = state.get("last_summary") if state.get("last_summary") != null else {}
 var g = stored.get("groups",{})
 var out = []
 for grp in SUMMARY_GROUPS:
  var rows = threats() if grp[0] == "threats" else g.get(grp[0],[])
  if not rows.is_empty(): out.append({"id":grp[0],"name":grp[1],"rows":rows})
 return out

# Armies of factions at war with you (or hostile to you) near your settlements, strongest first.
func threats() -> Array:
 var me = player_faction_id()
 var D = load("res://core/diplomacy.gd")
 var out = []
 for id in state.army_state:
  var a = state.army_state[id]
  if a.faction == me or a.units.is_empty(): continue
  var hostile = Battles.at_war(state,me,a.faction) or D.relation(state,me,a.faction) == "hostile"
  if not hostile: continue
  var p = Movement.position(state,id)
  var near = ""
  var best = THREAT_METRES
  for sid in state.settlements_of(me):
   var d = p.distance_to(WorldMap.settlement_position(sid))
   if d<best:
    best = d
    near = sid
  if near == "": continue
  out.append({"text":"%s near %s (%s men, %s)" % [a.display_name,settlement(near).name,UiKit_format(Armies.men(a)),"at war" if Battles.at_war(state,me,a.faction) else "hostile"],"target":{"type":"army","id":id},"men":Armies.men(a)})
 out.sort_custom(func(x,y): return int(x.men)>int(y.men))
 return out.slice(0,6)

func UiKit_format(n: int) -> String:
 var s = str(n)
 var out = ""
 while s.length()>3:
  out = ","+s.substr(s.length()-3)+out
  s = s.substr(0,s.length()-3)
 return s+out
