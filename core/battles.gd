extends RefCounted
# Battles in the campaign (docs/battle-design.md sections 9-11 and the owner's decisions): war
# status, building a battle from the map, quick resolve, and the aftermath. The fight itself is
# core/battle_sim.gd; deployments come from core/battle_deploy.gd templates (quick resolve).
#  - TEMPORARY war rule: attacking another faction's army or settlement declares war after a
#    confirmation; no peace until diplomacy exists.
#  - Reinforcements: friendly armies within a radius join, in reserve or a few ticks late.
#  - Settlements get an automatic garrison from their main building level and walls.
#  - Aftermath: casualties, destroyed units and armies, experience and ranks, generals wounded or
#    killed (a captain takes over and cannot move the army until a new general is appointed, the
#    wounded general returns, or the captain wins an important battle and is promoted), retreat
#    toward the nearest own settlement (destroyed if no path), occupation of captured settlements
#    (sack, raze and expel are open), movement cost for the attacker, sieges with endurance.
# All numbers: data/battle.json "campaign" and "sieges" (placeholders).

const BattleSim = preload("res://core/battle_sim.gd")
const BattleDeploy = preload("res://core/battle_deploy.gd")
const Battlefield = preload("res://core/battlefield.gd")
const Movement = preload("res://core/movement.gd")
const Armies = preload("res://core/armies.gd")
const Buildings = preload("res://core/buildings.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const WorldMap = preload("res://core/world_map.gd")
const Chronicle = preload("res://core/chronicle.gd")
const Deployment = preload("res://core/deployment.gd")

static func cfg() -> Dictionary:
 return BattleSim.data().campaign

# --- War status (temporary rule) --------------------------------------------------------

static func war_key(a: String,b: String) -> String:
 return "%s|%s" % [a,b] if a<b else "%s|%s" % [b,a]

static func at_war(state,a: String,b: String) -> bool:
 return war_key(a,b) in state.wars

static func declare_war(state,attacker: String,defender: String) -> Dictionary:
 if at_war(state,attacker,defender): return {}
 state.wars.append(war_key(attacker,defender))
 var e = Chronicle.war_entry(state.year,attacker,defender)
 state.chronicle.append(e)
 return e

# --- Generals -----------------------------------------------------------------------------

# A general's state: status ok, wounded (with turns left) or captain (a stand-in who cannot move the army).
static func commander(state,army_id: String) -> Dictionary:
 var c = state.army_state[army_id].commander
 if not c.has("status"): c.status = "ok"
 if not c.has("xp"): c.xp = 0.0
 return c

static func can_move(state,army_id: String) -> bool:
 return commander(state,army_id).status == "ok"

# Hire a new general for a leaderless army (the general fee from data/recruitment.json).
static func appoint_general(state,army_id: String) -> Dictionary:
 var a = state.army_state[army_id]
 var c = commander(state,army_id)
 if c.status == "ok": return {"ok":false,"reasons":["The army already has a general"]}
 var cost = int(Armies.data().armies.general_cost)
 if int(state.treasury.get(a.faction,0))<cost: return {"ok":false,"reasons":["Not enough gold (%d needed)" % cost]}
 state.treasury[a.faction] -= cost
 var name = Armies.general_name(state,a.faction)
 a.commander = {"name":name,"rank":1,"xp":0.0,"status":"ok"}
 if state.get("courts") != null and not state.courts.is_empty():
  load("res://core/court.gd").promote_captain(state,army_id)
  name = a.commander.name
 return {"ok":true,"name":name}

# --- Building a battle --------------------------------------------------------------------

# What an order onto `point` would attack: {kind: army|settlement|"", id, faction, position}.
static func target_at(state,army_id: String,point: Vector2) -> Dictionary:
 var me = state.army_state[army_id]
 var sid = Movement.settlement_at(point)
 if sid != "" and state.settlements[sid].owner != me.faction:
  return {"kind":"settlement","id":sid,"faction":state.settlements[sid].owner,"position":WorldMap.settlement_position(sid)}
 for other in state.army_state:
  var o = state.army_state[other]
  if other == army_id or o.faction == me.faction: continue
  var p = Movement.position(state,other)
  if p.distance_to(point)<=float(Movement.data().armies.block_radius):
   if o.garrison != "": return {"kind":"settlement","id":o.garrison,"faction":state.settlements[o.garrison].owner,"position":WorldMap.settlement_position(o.garrison)}
   return {"kind":"army","id":other,"faction":o.faction,"position":p}
 return {"kind":""}

# Where the attacker stands to fight: next to the target on the way in. Returns {ok, reason, point, plan}.
static func approach(state,army_id: String,target: Dictionary) -> Dictionary:
 if not can_move(state,army_id): return {"ok":false,"reason":"No general: a captain cannot lead an attack"}
 if bool(state.army_state[army_id].get("captain",false)): return {"ok":false,"reason":"Levies under a captain defend only: merge them into a lord's army"}
 var from = Movement.position(state,army_id)
 var reach = maxf(float(Movement.data().armies.block_radius),float(Movement.data().settlements.radius))+1.0
 # A large army's zone of control is fought at its edge (core/hosts.gd zoc_radius).
 if str(target.get("kind","")) == "army" and state.army_state.has(str(target.get("id",""))) and state.get("courts") != null and not state.courts.is_empty():
  reach = maxf(reach,load("res://core/hosts.gd").zoc_radius(state,target.id,float(Movement.data().armies.block_radius))+1.0)
 if from.distance_to(target.position)<=reach+0.5: return {"ok":true,"point":from,"plan":{}}
 var dir = (from-target.position).normalized()
 for k in [0,1,-1,2,-2,3,-3]:
  var p = target.position+dir.rotated(k*0.5)*reach
  var plan = Movement.plan(state,army_id,p)
  if plan.ok:
   if plan.total_turns>1: return {"ok":false,"reason":"Too far to attack this turn (%d turns away)" % plan.total_turns,"point":p,"plan":plan}
   return {"ok":true,"point":p,"plan":plan}
 return {"ok":false,"reason":"No way to reach the enemy"}

static func _units_of(state,army_id: String) -> Array:
 var out = []
 var a = state.army_state[army_id]
 for i in a.units.size():
  var u = a.units[i]
  out.append({"unit":u.unit,"men":float(u.men),"max_men":float(u.max_men),"rank":int(u.get("rank",0)),"index":i,"army":army_id})
 return out

# Automatic garrison of a settlement (decision 3): units by main building level, more with walls.
static func garrison_units(state,sid: String) -> Array:
 var g = cfg().garrison
 var s = state.settlements[sid]
 var list = []
 for i in int(s.level): list.append_array(g.per_level)
 if int(s.level)>=2: list.append_array(g.level_2)
 if int(s.level)>=3: list.append_array(g.level_3)
 if int(s.get("defense",0))>=int(BattleSim.data().sieges.wall_threshold): list.append_array(g.walls)
 var out = []
 for pair in list:
  for n in int(pair[1]):
   var size = int(UnitTypes.get_type(pair[0]).size)
   out.append({"unit":pair[0],"men":float(size),"max_men":float(size),"index":-1,"army":"","garrison":sid})
 return out

static func _reinforcements(state,faction: String,at: Vector2,exclude: Array) -> Array:
 var out = []
 for id in state.army_state:
  var a = state.army_state[id]
  if a.faction != faction or id in exclude or a.units.is_empty(): continue # an army with no units brings nothing
  var d = Movement.position(state,id).distance_to(at)
  if d>float(cfg().reinforcement_radius): continue
  var tick = 0 if d<=float(cfg().reinforcement_reserve_radius) else int(ceil(d*float(cfg().reinforcement_ticks_per_meter)))
  out.append({"army":id,"distance":d,"arrive_tick":tick})
 out.sort_custom(func(a,b): return a.army<b.army)
 return out

static func _men(units: Array) -> int:
 var n = 0
 for u in units: n += int(u.men)
 return n

# Everything the pre-battle panel shows: {attacker {faction, army, reinforcements}, defender {...},
# kind, settlement, field {terrain, summary, walls}, weather, seed, odds (attacker wins 0..1)}.
static func prebattle(state,army_id: String,target: Dictionary,with_odds := true) -> Dictionary:
 var me = state.army_state[army_id]
 var at = target.position
 var att_pos = Movement.position(state,army_id)
 var field = Battlefield.sample(at,att_pos)
 var defenders = []
 var sid = ""
 var siege_turns = 0
 if target.kind == "settlement":
  sid = target.id
  defenders = Movement.garrison_of(state,sid).filter(func(x): return state.army_state[x].faction == target.faction)
  var siege = state.settlements[sid].get("siege",{})
  if siege.get("army","") == army_id: siege_turns = int(siege.turns)
  field.walls = Battlefield.walls(int(state.settlements[sid].get("defense",0)),siege_turns,field.lanes)
 else:
  defenders = [target.id]
 var pb = {"kind":target.kind,"settlement":sid,"siege_turns":siege_turns,"position":[at.x,at.y],
  "attacker":{"faction":me.faction,"army":army_id,"reinforcements":_reinforcements(state,me.faction,at,[army_id])},
  "defender":{"faction":target.faction,"armies":defenders,"reinforcements":_reinforcements(state,target.faction,at,defenders)},
  "field":field,"seed":battle_seed(state,army_id,defenders,sid),"lanes":field.lanes}
 pb.weather = BattleSim.roll_weather(pb.seed)
 pb.stances = {"0":"balanced","1":"balanced"}
 pb.odds = odds(state,pb) if with_odds else -1.0
 if with_odds:
  # Each side's AI stance from the balance of power (the player's panel sets its own side).
  pb.stances = {"0":ai_stance(pb.odds),"1":ai_stance(1.0-pb.odds)}
  pb.odds = odds(state,pb)
 return pb

# Stances (docs/war-and-realm.md §1): the AI fights Aggressive when likely to win, Defensive when not.
static func ai_stance(win_share: float) -> String:
 var a = BattleSim.data().get("stances",{}).get("ai",{"aggressive_above":0.65,"defensive_below":0.4})
 if win_share>=float(a.aggressive_above): return "aggressive"
 if win_share<float(a.defensive_below): return "defensive"
 return "balanced"

# The player picks a side's stance (role 0 attacker, 1 defender); the balance of power follows.
static func set_stance(state,pb: Dictionary,role: int,stance: String):
 pb.stances[str(role)] = stance
 pb.odds = odds(state,pb)

# Seed of a battle: the campaign seed, the year, the campaign's battle counter and both sides'
# army IDs, so two battles in the same year differ while every battle stays reproducible.
static func battle_seed(state,attacker: String,defenders: Array,settlement := "") -> int:
 var d = defenders.duplicate()
 d.sort()
 return hash([state.seed,state.year,state.battles,attacker,d,settlement])

# The units a side brings (its main armies, plus the garrison when defending a settlement).
static func side_units(state,pb: Dictionary,role: int) -> Array:
 var spec = pb.attacker if role == 0 else pb.defender
 var main_armies = [spec.army] if role == 0 else spec.armies
 var units = []
 for a in main_armies: units.append_array(_units_of(state,a))
 if role == 1 and pb.kind == "settlement": units.append_array(garrison_units(state,pb.settlement))
 return units

# The faction's default template for this battle (data/maps/<map>/factions.json battle_style).
static func default_template(state,pb: Dictionary,role: int) -> String:
 var spec = pb.attacker if role == 0 else pb.defender
 var style = WorldMap.faction(spec.faction).get("battle_style",{"default":"line"})
 return BattleDeploy.choose_template(style,side_units(state,pb,role),role == 1 and pb.field.get("walls") != null)

# A side's default deployment (AI sides always; quick resolve for the player).
static func default_placement(state,pb: Dictionary,role: int) -> Array:
 return BattleDeploy.deploy(side_units(state,pb,role),default_template(state,pb,role),pb.field.terrain,role)

# Battle setup for the simulation. A side uses pb.deployment (core/deployment.gd) when it is that
# side's, otherwise its default template.
static func setup(state,pb: Dictionary,seed: int,fast := false) -> Dictionary:
 var terrain = pb.field.terrain
 var sides = []
 for role in 2:
  var spec = pb.attacker if role == 0 else pb.defender
  var faction = spec.faction
  var main_armies = [spec.army] if role == 0 else spec.armies
  var placed = default_placement(state,pb,role)
  var general_lane = terrain.size()/2
  if pb.has("deployment") and int(pb.deployment.role) == role:
   placed = Deployment.setup_units(pb.deployment)
   general_lane = int(pb.deployment.general_lane)
  for r in spec.reinforcements:
   for u in _units_of(state,r.army):
    u.line = "reserve"
    u.order = "reserve"
    u.lane = terrain.size()/2
    u.arrive_tick = int(r.arrive_tick)
    placed.append(u)
  var g = {"name":"","rank":1,"traits":[]}
  if not main_armies.is_empty():
   var c = commander(state,main_armies[0])
   g = {"name":c.name,"rank":int(c.rank) if c.status == "ok" else 1,"traits":WorldMap.faction(faction).get("general_traits",[])}
  elif pb.kind == "settlement":
   g = {"name":"the garrison commander","rank":1,"traits":WorldMap.faction(faction).get("general_traits",[])}
  sides.append({"faction":faction,"general":g,"general_lane":general_lane,"units":placed,"stance":str(pb.get("stances",{}).get(str(role),"balanced"))})
 var f = {"terrain":terrain,"weather":pb.weather}
 if pb.field.get("walls") != null: f.walls = pb.field.walls
 return {"seed":seed,"lanes":pb.lanes,"field":f,"sides":sides,"fast":fast}

# Balance of power: share of seeded quick runs the attacker wins (decision 13).
# runs 0: the configured count (the player's balance bar); the AI asks for fewer.
static func odds(state,pb: Dictionary,runs := 0) -> float:
 var n = runs if runs>0 else int(cfg().odds_runs)
 var wins = 0
 for i in n:
  if BattleSim.simulate(setup(state,pb,hash([pb.seed,"odds",i]),true)).winner == 0: wins += 1
 return float(wins)/n

# --- Resolution and aftermath ------------------------------------------------------------------

# fast: skip the replay and event log (same outcome; for battles nobody will read a report of).
static func quick_resolve(state,pb: Dictionary,fast := false) -> Dictionary:
 state.battles += 1
 var result = BattleSim.simulate(setup(state,pb,int(pb.seed),fast))
 var after = aftermath(state,pb,result)
 return {"result":result,"aftermath":after}

static func _rank_for(xp: float,thresholds: Array) -> int:
 var r = 0
 for i in thresholds.size():
  if xp>=float(thresholds[i]): r = i
 return r

static func aftermath(state,pb: Dictionary,result: Dictionary) -> Dictionary:
 var xp = BattleSim.data().experience
 var rng = RandomNumberGenerator.new()
 rng.seed = hash([pb.seed,"aftermath"])
 var att_f = pb.attacker.faction
 var def_f = pb.defender.faction
 var winner_f = att_f if result.winner == 0 else def_f
 var loser_f = def_f if result.winner == 0 else att_f
 var out = {"winner":winner_f,"loser":loser_f,"attacker_won":result.winner == 0,"destroyed_units":[],"destroyed_armies":[],
  "generals":[],"captured":"","retreated":[],"promoted":[],"entries":[],"deeds":[]}
 # 1. Casualties and experience, unit by unit; destroyed units leave their army.
 var removals = {}
 for side in 2:
  for u in result.sides[side].units:
   if u.army == "" or not state.army_state.has(u.army): continue
   var a = state.army_state[u.army]
   var unit = a.units[int(u.index)]
   unit.men = maxi(0,int(u.men_end))
   unit.xp = float(unit.get("xp",0.0))+float(u.xp)
   unit.rank = _rank_for(unit.xp,xp.rank_thresholds)
   if u.outcome == "destroyed" or unit.men<=0:
    if not removals.has(u.army): removals[u.army] = []
    removals[u.army].append(int(u.index))
    out.destroyed_units.append({"army":u.army,"unit":u.unit})
 for army in removals:
  var idx = removals[army]
  idx.sort()
  idx.reverse()
  for i in idx: state.army_state[army].units.remove_at(i)
 # 2. Generals: experience, wounds and deaths (placeholder chances, worse when routed or destroyed).
 var involved = [[pb.attacker.army,0]]
 for a in pb.defender.armies: involved.append([a,1])
 for spec in [pb.attacker,pb.defender]:
  for r in spec.reinforcements: involved.append([r.army,0 if spec == pb.attacker else 1])
 var enemy_men = [0,0]
 for side in 2:
  for u in result.sides[side].units: enemy_men[1-side] += int(u.men_start)
 for pair in involved:
  var id = pair[0]
  var side = pair[1]
  if not state.army_state.has(id): continue
  var a = state.army_state[id]
  var c = commander(state,id)
  var won = result.winner == side
  var g = result.sides[side].general
  var fate = "won" if won else ("routed" if g.get("fled",false) or g.get("killed",false) else "lost")
  if a.units.is_empty(): fate = "destroyed"
  var cid = str(c.get("character",""))
  if cid != "" and c.status == "ok": out.deeds.append({"character":cid,"won":won,"stronger":enemy_men[side]>_men_of(result,side)*1.2,"desperate":won and side == 1 and enemy_men[side]>_men_of(result,side)*1.5,"faction":a.faction})
  if c.status == "ok":
   c.xp = float(c.xp)+float(xp.general_per_battle)+(float(xp.general_per_victory) if won else 0.0)
   c.rank = maxi(int(c.rank),_rank_for(c.xp,xp.general_rank_thresholds))
   var roll = rng.randf()
   var die = float(cfg().general_death[fate])
   var wound = float(cfg().general_wound[fate])
   if roll<die:
    out.generals.append({"army":id,"name":c.name,"fate":"killed","faction":a.faction,"character":cid})
    a.commander = {"name":"Captain of %s" % a.display_name.trim_prefix("The "),"rank":1,"xp":0.0,"status":"captain","fallen":c.name}
   elif roll<die+wound:
    out.generals.append({"army":id,"name":c.name,"fate":"wounded","faction":a.faction})
    a.commander = {"name":"Captain of %s" % a.display_name.trim_prefix("The "),"rank":1,"xp":0.0,"status":"wounded",
     "wounded_turns":int(cfg().wound_turns),"general":c.duplicate()}
  elif won and (enemy_men[side]>=int(cfg().captain_promotion_enemy_men) or pb.kind == "settlement"):
   # A captain who wins an important or big battle is promoted to general.
   var name = Armies.general_name(state,a.faction)
   a.commander = {"name":name,"rank":1,"xp":float(xp.general_per_victory),"status":"ok"}
   load("res://core/court.gd").promote_captain(state,id)
   name = a.commander.name
   out.promoted.append({"army":id,"name":name,"faction":a.faction})
 # 3. Armies with no units left are destroyed.
 for pair in involved:
  var id = pair[0]
  if state.army_state.has(id) and state.army_state[id].units.is_empty():
   out.destroyed_armies.append({"army":id,"name":state.army_state[id].display_name,"faction":state.army_state[id].faction})
   state.army_state.erase(id)
   state.armies.erase(id)
 # 4. Movement cost for the attacker (it may fight again while points remain).
 if state.army_state.has(pb.attacker.army):
  var m = state.army_state[pb.attacker.army]
  m.points = maxf(0.0,float(m.points)-float(cfg().attack_movement_share)*float(m.max_points))
  m.order = []
 # 5. A won settlement battle captures (occupies) the settlement first, so its beaten defenders
 #    must retreat elsewhere.
 if pb.kind == "settlement" and result.winner == 0:
  occupy(state,pb.settlement,att_f,pb.attacker.army)
  out.captured = pb.settlement
 elif pb.kind == "settlement" and state.settlements[pb.settlement].get("siege",{}).get("army","") == pb.attacker.army:
  state.settlements[pb.settlement].erase("siege")
 # 6. The loser's surviving armies retreat toward their nearest own settlement.
 for pair in involved:
  var id = pair[0]
  if not state.army_state.has(id) or state.army_state[id].faction != loser_f: continue
  var r = retreat(state,id,float(cfg().retreat_movement_share))
  out.retreated.append(r)
  if r.destroyed: out.destroyed_armies.append({"army":id,"name":r.name,"faction":loser_f})
 out.entries = Chronicle.battle_entries(state.year,pb,result,out)
 state.chronicle.append_array(out.entries)
 # Characters, reputation and fallen houses (core/court.gd; game-design §4.4, §4.10).
 if state.get("courts") != null and not state.courts.is_empty(): load("res://core/court.gd").on_battle(state,pb,out)
 return out

static func _men_of(result: Dictionary,side: int) -> int:
 var n = 0
 for u in result.sides[side].units: n += int(u.men_start)
 return maxi(1,n)

# Move a beaten army toward its nearest own settlement on a reduced allowance; destroyed if no path.
static func retreat(state,army_id: String,share: float) -> Dictionary:
 var a = state.army_state[army_id]
 var name = a.display_name
 a.garrison = ""
 a.order = []
 var best = ""
 var best_plan = {}
 for sid in state.settlements_of(a.faction):
  var plan = Movement.plan(state,army_id,WorldMap.settlement_position(sid),true)
  if plan.ok and (best == "" or plan.cost<best_plan.cost):
   best = sid
   best_plan = plan
 if best == "":
  # No path to any own settlement (decision 5): the army is destroyed.
  state.army_state.erase(army_id)
  state.armies.erase(army_id)
  return {"army":army_id,"name":name,"destroyed":true,"to":""}
 a.points = float(a.max_points)*share
 a.order = []
 for q in best_plan.points.slice(1): a.order.append([q.x,q.y])
 a.order_settlement = best
 var walked = Movement.advance(state,army_id)
 a.order = []
 a.order_settlement = ""
 a.points = 0.0
 return {"army":army_id,"name":name,"destroyed":false,"to":best,"walked":walked}

# Occupy a captured settlement: new owner, buildings and population kept, construction cancelled.
static func occupy(state,sid: String,faction: String,army_id: String):
 var s = state.settlements[sid]
 s.owner = faction
 s.constructions = []
 s.erase("siege")
 Buildings.refresh(state,sid)
 if state.army_state.has(army_id):
  var p = WorldMap.settlement_position(sid)
  state.army_state[army_id].position = [p.x,p.y]
  state.army_state[army_id].garrison = sid

# Defender's withdrawal before battle: a casualty share, then a retreat (field battles only).
static func withdraw(state,pb: Dictionary) -> Dictionary:
 if pb.kind == "settlement": return {"ok":false,"reasons":["A besieged garrison cannot withdraw"]}
 var share = float(cfg().withdraw_casualty_share)
 var out = []
 for id in pb.defender.armies:
  if not state.army_state.has(id): continue
  for u in state.army_state[id].units: u.men = maxi(1,int(round(int(u.men)*(1.0-share))))
  out.append(retreat(state,id,float(cfg().retreat_movement_share)))
 return {"ok":true,"retreated":out}

# --- Sieges ------------------------------------------------------------------------------------

# Turns a settlement can hold out (decision: about 8 at most): base + food endowment + farm level
# + 1 above a population, capped.
static func endurance(state,sid: String) -> int:
 var s = BattleSim.data().sieges
 var st = state.settlements[sid]
 var farm = 0
 for b in st.buildings:
  if b.get("chain","") == "farm": farm = int(b.level)
 var e = int(s.endurance_base)+int(st.resources.get("food",0))+farm+(1 if float(st.population)>float(s.population_bonus_over) else 0)
 return mini(e,int(s.max_endurance))

static func besiege(state,army_id: String,sid: String) -> Dictionary:
 var a = state.army_state[army_id]
 if state.settlements[sid].owner == a.faction: return {"ok":false,"reasons":["Your own settlement"]}
 if Battlefield.walls(int(state.settlements[sid].get("defense",0)),0,5) == null: return {"ok":false,"reasons":["No walls: assault it instead"]}
 state.settlements[sid].siege = {"army":army_id,"turns":0,"endurance":endurance(state,sid),"starving":0}
 a.order = []
 a.points = 0.0
 return {"ok":true,"endurance":state.settlements[sid].siege.endurance}

# End Turn: sieges advance (starvation after endurance, surrender), wounded generals heal.
static func end_turn(state) -> Array:
 var events = []
 var s = BattleSim.data().sieges
 for sid in state.settlements:
  var st = state.settlements[sid]
  if not st.has("siege"): continue
  var sg = st.siege
  var besieger = sg.army
  var radius = float(Movement.data().settlements.radius)+float(Movement.data().armies.block_radius)+2.0
  if not state.army_state.has(besieger) or Movement.position(state,besieger).distance_to(WorldMap.settlement_position(sid))>radius:
   st.erase("siege")
   events.append({"kind":"siege_lifted","settlement":sid})
   continue
  sg.turns = int(sg.turns)+1
  if sg.turns>int(sg.endurance):
   sg.starving = int(sg.starving)+1
   for id in Movement.garrison_of(state,sid):
    for u in state.army_state[id].units: u.men = maxi(1,int(round(int(u.men)*(1.0-float(s.starvation_loss)))))
   # After as many starving turns as it lasted, the garrison surrenders.
   if sg.starving>=maxi(1,int(sg.endurance)/2):
    var att_f = state.army_state[besieger].faction
    var was = str(state.settlements[sid].owner)
    for id in Movement.garrison_of(state,sid):
     if state.army_state[id].faction != att_f: retreat(state,id,float(cfg().retreat_movement_share))
    occupy(state,sid,att_f,besieger)
    var e = Chronicle.capture_entry(state.year,sid,att_f,true,was)
    state.chronicle.append(e)
    events.append({"kind":"surrendered","settlement":sid,"faction":att_f})
 for id in state.army_state:
  var c = state.army_state[id].commander
  if c.get("status","ok") == "wounded":
   c.wounded_turns = int(c.wounded_turns)-1
   if c.wounded_turns<=0:
    state.army_state[id].commander = c.general
    state.army_state[id].commander.status = "ok"
    events.append({"kind":"general_returns","army":id,"name":c.general.name})
 return events

# Move the attacker to its approach point next to the target (pb.approach from approach()), as
# Quick Resolve, Fight and Besiege all do before acting. Returns the points walked.
static func move_to_attack(state,army_id: String,appr: Dictionary) -> Array:
 if not appr.get("plan",{}).has("points"): return []
 return Movement.order(state,army_id,appr.point).get("moved",[])
