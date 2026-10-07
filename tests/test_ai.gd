extends GutTest
# Campaign AI (core/ai.gd, docs/ai-design.md): it keeps the player's rules (gold, movement, upkeep,
# recruitment and army limits), defends, refuses bad odds, besieges walls, answers with the right
# defender choice, leaves attacks on a human player for the player, is deterministic, and its
# personality changes how often it goes to war.

const GameState = preload("res://core/game_state.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const Ai = preload("res://core/ai.gd")
const Battles = preload("res://core/battles.gd")
const BattleSim = preload("res://core/battle_sim.gd")
const Armies = preload("res://core/armies.gd")
const Movement = preload("res://core/movement.gd")
const Economy = preload("res://core/economy.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const WorldMap = preload("res://core/world_map.gd")
const SaveCodec = preload("res://core/save_codec.gd")
const UiData = preload("res://core/ui_data.gd")
const HOST = "aurek_host"
const GUARD = "silverfall_guard"
const KINDS = ["spearmen","swordsmen","archers","heavy_infantry","spearmen","archers","cavalry"]

func after_each():
 WorldMap.reset()
 Ai.reset()
 BattleSim.reset()

func all_ai(s) -> Dictionary:
 return {"factions":s.factions(),"resolve_player":true}

func reinforce(s,id: String,n: int):
 for i in n: s.army_state[id].units.append({"unit":KINDS[i%KINDS.size()],"men":100,"max_men":100})

func place(s,id: String,p: Vector2,garrison := ""):
 s.army_state[id].position = [p.x,p.y]
 s.army_state[id].garrison = garrison

func near(sid: String,dx := -35.0,dz := 15.0) -> Vector2:
 var p = WorldMap.settlement_position(sid)
 return Vector2(p.x+dx,p.y+dz)

func actions_of(rep: Dictionary,kind: String,f := "") -> Array:
 return rep.actions.filter(func(a): return a.action == kind and (f == "" or a.get("faction","") == f))

# --- Same rules as the player -------------------------------------------------------------------

func test_ai_spends_only_what_it_pays_for_and_keeps_every_limit():
 var s = GameState.from_data(GameState.START,77)
 var cap_units = Armies.max_units()
 var cap_armies = int(Armies.data().armies.max_per_faction)
 var min_net = 0 # each faction's own minimum (Ai.min_net), never below zero
 for turn in 25:
  # The yearly processing alone, then the AI phase, so its spending can be checked exactly.
  TurnLoop.end_turn(s,{"ai":false})
  var before = s.treasury.duplicate()
  var pos = {}
  for id in s.army_state: pos[id] = Movement.position(s,id)
  var points = {}
  for id in s.army_state: points[id] = float(s.army_state[id].points)
  var rep = Ai.take_turns(s,all_ai(s))
  var spent = {}
  for f in s.factions(): spent[f] = 0
  for a in rep.actions:
   match a.action:
    "build": spent[a.faction] += int(s.settlements[a.settlement].construction.get("cost",0)) if s.settlements[a.settlement].owner == a.faction else 0
    "raise": spent[a.faction] += int(Armies.data().armies.general_cost)
    "recruit": spent[a.faction] += int(UnitTypes.get_type(a.unit).recruitment.cost)
  for f in s.factions():
   assert_gte(int(s.treasury[f]),0,"%s never goes into debt" % f)
   # Battles, captures and retreats cost no gold; a building lost with its settlement in the
   # same phase cannot be counted, so only factions that kept their builds are checked exactly.
   var lost_build = rep.actions.any(func(a): return a.action == "build" and a.faction == f and s.settlements[a.settlement].owner != f)
   if not lost_build: assert_eq(int(s.treasury[f]),int(before[f])-spent[f],"%s pays exactly for what it does (turn %d)" % [f,turn])
   assert_lte(Armies.armies_of(s,f).size(),cap_armies,"army cap")
   if not actions_of(rep,"recruit",f).is_empty() or not actions_of(rep,"build",f).is_empty():
    assert_gte(int(Economy.faction_ledger(s,f).net),mini(min_net,Ai.min_net(s,f)),"%s never builds or recruits into negative income" % f)
  for id in s.army_state:
   var a = s.army_state[id]
   assert_lte(Armies.card_count(a),cap_units,"units per army")
   assert_gte(float(a.points),-0.0001,"movement points never negative")
   # Straight-line distance can never exceed what the points buy on the cheapest terrain.
   if pos.has(id) and not rep.actions.any(func(x): return x.action in ["battle","withdraw"]):
    var cheapest = float(Movement.data().roads.multiplier_by_level[s.road_level])
    assert_lte(pos[id].distance_to(Movement.position(s,id)),points[id]/cheapest+0.01,"%s moved within its allowance" % id)

func test_ai_never_moves_a_captain_led_army():
 var s = GameState.from_data()
 Battles.declare_war(s,"house_lannet","house_aurek")
 reinforce(s,GUARD,9)
 place(s,GUARD,near("crownwatch"))
 var c = Battles.commander(s,GUARD)
 s.army_state[GUARD].commander = {"name":"Captain","rank":1,"status":"captain","general":c.duplicate()}
 var at = Movement.position(s,GUARD)
 var rep = Ai.take_turns(s,all_ai(s))
 assert_eq(Movement.position(s,GUARD),at)
 assert_true(actions_of(rep,"attack","house_lannet").is_empty())

# --- Decisions ------------------------------------------------------------------------------------

func test_ai_defends_a_threatened_settlement():
 var s = GameState.from_data()
 Battles.declare_war(s,"house_aurek","house_lannet")
 # The Aurek host stands near Greyhaven; Lannet's guard is out in the field nearby, reinforced
 # enough to make the difference.
 place(s,HOST,near("greyhaven",25.0,-35.0))
 reinforce(s,GUARD,4)
 place(s,GUARD,near("greyhaven",-50.0,-25.0))
 var look = Ai.assess(s,"house_lannet",Ai.personality("house_lannet"))
 assert_true("greyhaven" in look.threatened,"precondition: Greyhaven is threatened")
 var rep = Ai.take_turns(s,{"factions":["house_lannet","house_verrin"]})
 assert_false(actions_of(rep,"defend","house_lannet").is_empty(),"the guard moves to defend")
 assert_eq(s.army_state[GUARD].garrison,"greyhaven","and garrisons Greyhaven")

func test_ai_does_not_attack_at_bad_odds():
 var s = GameState.from_data()
 Battles.declare_war(s,"house_lannet","house_aurek")
 # The guard (4 units) faces the much stronger Aurek host in the open.
 place(s,GUARD,near("crownwatch"))
 place(s,HOST,near("crownwatch",-75.0,25.0))
 var rep = Ai.take_turns(s,{"factions":["house_lannet","house_verrin"]})
 assert_true(actions_of(rep,"attack","house_lannet").is_empty(),"no attack")
 assert_true(rep.pending.is_empty())
 assert_false(actions_of(rep,"flee","house_lannet").is_empty(),"it falls back instead")

func test_ai_besieges_walls_it_cannot_storm_and_storms_when_it_can():
 for extra in [2,9]:
  var s = GameState.from_data()
  Battles.declare_war(s,"house_lannet","house_aurek")
  reinforce(s,GUARD,extra)
  place(s,GUARD,near("crownwatch"))
  var gp = WorldMap.settlement_position("goldspire_rock")
  place(s,HOST,gp,"goldspire_rock")
  assert_true(Ai.walled(s,"crownwatch"),"precondition: Crownwatch has walls")
  var rep = Ai.take_turns(s,{"factions":["house_lannet","house_verrin"]})
  if extra == 2:
   assert_false(actions_of(rep,"besiege","house_lannet").is_empty(),"a weaker army besieges")
   assert_eq(s.settlements.crownwatch.get("siege",{}).get("army",""),GUARD)
   assert_true(rep.pending.is_empty(),"no suicidal assault")
   # It holds the siege on the next turn.
   var rep2 = Ai.take_turns(s,{"factions":["house_lannet","house_verrin"]})
   assert_false(actions_of(rep2,"hold_siege","house_lannet").is_empty())
  else:
   assert_eq(actions_of(rep,"attack","house_lannet").size(),1,"a strong army assaults")
   assert_false(s.settlements.crownwatch.has("siege"))

func test_attacks_on_a_human_player_wait_for_the_player():
 var s = GameState.from_data()
 Battles.declare_war(s,"house_lannet","house_aurek")
 reinforce(s,GUARD,9)
 place(s,GUARD,near("crownwatch"))
 var gp = WorldMap.settlement_position("goldspire_rock")
 place(s,HOST,gp,"goldspire_rock")
 var owner_before = s.settlements.crownwatch.owner
 var battles_before = s.battles
 TurnLoop.end_turn(s)
 assert_eq(s.pending_battles.size(),1,"the attack waits for the player")
 assert_eq(s.battles,battles_before,"no battle fought yet")
 assert_eq(s.settlements.crownwatch.owner,owner_before)
 # The UI side: the pre-battle panel with the player defending, no Close, then Quick Resolve.
 var ui = UiData.new(s)
 var pb = ui.pending_battle()
 assert_false(pb.is_empty())
 assert_true(pb.player_is_defender and pb.forced)
 assert_eq(pb.attacker.army,GUARD)
 assert_eq(pb.settlement,"crownwatch")
 ui.quick_resolve(pb)
 assert_true(s.pending_battles.is_empty(),"answered")
 assert_eq(s.battles,battles_before+1)
 # The pending attack is part of a save.
 var s2 = GameState.from_data()
 Battles.declare_war(s2,"house_lannet","house_aurek")
 reinforce(s2,GUARD,9)
 place(s2,GUARD,near("crownwatch"))
 place(s2,HOST,gp,"goldspire_rock")
 TurnLoop.end_turn(s2)
 var back = GameState.from_dict(SaveCodec.from_json(SaveCodec.to_json(s2.to_dict())))
 assert_eq(back.pending_battles.size(),1)

func test_a_stale_pending_attack_is_dropped():
 var s = GameState.from_data()
 Battles.declare_war(s,"house_lannet","house_aurek")
 reinforce(s,GUARD,9)
 place(s,GUARD,near("crownwatch"))
 place(s,HOST,WorldMap.settlement_position("goldspire_rock"),"goldspire_rock")
 TurnLoop.end_turn(s)
 assert_eq(s.pending_battles.size(),1)
 # The attacker has gone (destroyed elsewhere): nothing to answer.
 s.army_state.erase(GUARD)
 s.armies.erase(GUARD)
 assert_true(UiData.new(s).pending_battle().is_empty())
 assert_true(s.pending_battles.is_empty())

func test_a_hopeless_ai_army_withdraws_when_the_player_attacks():
 var s = GameState.from_data()
 var ui = UiData.new(s)
 # The Verrin levy (weak) in the open, the Aurek host reinforced next to it.
 place(s,"highbloom_levy",Vector2(5,-35))
 reinforce(s,HOST,10)
 place(s,HOST,Vector2(5,-5))
 Battles.declare_war(s,"house_aurek","house_verrin")
 var pb = ui.prebattle(HOST,Vector2(5,-35))
 assert_eq(pb.kind,"army")
 assert_lt(1.0-float(pb.odds),float(Ai.data().defend.withdraw_below),"precondition: hopeless for the defender")
 var out = ui.quick_resolve(pb)
 assert_true(out.get("withdrew",false),"it withdraws instead of fighting")
 assert_true(s.chronicle.any(func(e): return e.category == "war" and e.get("faction","") == "house_verrin"),"recorded in the chronicle")

func test_raised_armies_recruit_toward_a_composition_not_just_the_cheapest():
 var s = GameState.from_data()
 # Lannet rich, Greyhaven able to train spears and archers.
 s.treasury.house_lannet = 60000
 var g = s.settlements.greyhaven
 for i in g.buildings.size():
  if g.buildings[i].is_empty():
   g.buildings[i] = {"chain":"barracks","level":1}
   break
 for i in g.buildings.size():
  if g.buildings[i].is_empty():
   g.buildings[i] = {"chain":"archery_range","level":1}
   break
 load("res://core/buildings.gd").refresh(s,"greyhaven")
 var rep = {"actions":[],"pending":[],"entries":[],"moves":{}}
 for t in 4:
  Ai._recruit(s,"house_lannet",Ai.personality("house_lannet"),rep)
 var units = {}
 for a in actions_of(rep,"recruit","house_lannet"): units[a.unit] = true
 assert_gt(units.size(),1,"a mix of units, not only the cheapest: %s" % str(units.keys()))

# --- Personality and determinism ----------------------------------------------------------------

func wars_started_by(traits: Array,seeds: Array,turns: int) -> int:
 var n = 0
 for sd in seeds:
  WorldMap.reset()
  WorldMap.faction("house_lannet").traits = traits
  WorldMap.faction("house_verrin").traits = traits
  var s = GameState.from_data(GameState.START,sd)
  for t in turns:
   var rep = TurnLoop.end_turn(s,all_ai(s))
   n += actions_of(rep.ai,"war").filter(func(a): return a.faction in ["house_lannet","house_verrin"]).size()
 WorldMap.reset()
 return n

func test_an_expansionist_faction_goes_to_war_more_than_a_passive_one():
 var seeds = [1,2,3,4,5,6]
 var exp = wars_started_by(["expansionist"],seeds,25)
 var pas = wars_started_by(["passive","kind"],seeds,25)
 gut.p("wars started over %d seeded 25-turn campaigns: expansionist %d, passive+kind %d" % [seeds.size(),exp,pas])
 assert_gt(exp,pas)
 assert_gt(exp,seeds.size()/2,"expansionists usually find a war")

func test_personality_multiplies_trait_weights():
 WorldMap.faction("house_lannet").traits = ["expansionist","income_focused"]
 var p = Ai.personality("house_lannet")
 var d = Ai.data().personalities
 assert_almost_eq(float(p.aggression),float(d.expansionist.aggression)*float(d.income_focused.aggression),0.0001)
 assert_almost_eq(float(p.reserve),float(d.income_focused.reserve),0.0001)
 WorldMap.faction("house_verrin").traits = ["levy_heavy"]
 assert_eq(Ai.personality("house_verrin").composition,d.levy_heavy.composition)

func test_ai_campaigns_are_deterministic_per_seed():
 var a = GameState.from_data(GameState.START,4)
 var b = GameState.from_data(GameState.START,4)
 for t in 20:
  TurnLoop.end_turn(a,all_ai(a))
  TurnLoop.end_turn(b,all_ai(b))
 assert_eq(SaveCodec.to_json(a.to_dict()),SaveCodec.to_json(b.to_dict()))
 assert_gt(a.chronicle.size(),20)

func test_ai_war_news_reaches_the_player():
 var s = GameState.from_data()
 Battles.declare_war(s,"house_lannet","house_verrin")
 var ui = UiData.new(s)
 assert_true(ui.events("war").any(func(e): return e.get("faction","") == "house_lannet"),"an AI war shows in Event Messages")
