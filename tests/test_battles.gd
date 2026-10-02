extends GutTest
# Battles in the campaign (core/battles.gd): the temporary war rule, building a battle from the map
# (garrisons, reinforcements, walls), quick resolve, every aftermath rule, sieges and endurance,
# generals and captains, withdrawal, the report summary, and determinism.

const GameState = preload("res://core/game_state.gd")
const Battles = preload("res://core/battles.gd")
const BattleSim = preload("res://core/battle_sim.gd")
const BattleReport = preload("res://core/battle_report.gd")
const Movement = preload("res://core/movement.gd")
const Armies = preload("res://core/armies.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const WorldMap = preload("res://core/world_map.gd")
const UiData = preload("res://core/ui_data.gd")
const HOST = "aurek_host"

func after_each():
 BattleSim.reset()
 Movement.reset()
 Armies.reset()

func place(s,army: String,p: Vector2):
 s.army_state[army].position = [p.x,p.y]
 s.army_state[army].garrison = ""

func near(sid: String) -> Vector2:
 return WorldMap.settlement_position(sid)+Vector2(8,4)

# A settlement battle against Willowmere (Verrin), the host standing next to it.
func willowmere_battle(s) -> Dictionary:
 place(s,HOST,near("willowmere"))
 var t = Battles.target_at(s,HOST,WorldMap.settlement_position("willowmere"))
 Battles.declare_war(s,"house_aurek",t.faction)
 return Battles.prebattle(s,HOST,t)

# A field battle: the Silverfall Guard stands in the open and the host attacks it.
func field_battle(s) -> Dictionary:
 place(s,"silverfall_guard",Vector2(2,-12))
 place(s,HOST,Vector2(2,-2))
 var t = Battles.target_at(s,HOST,Vector2(2,-12))
 Battles.declare_war(s,"house_aurek","house_lannet")
 return Battles.prebattle(s,HOST,t)

func test_attacking_declares_war_once_and_logs_it():
 var data = UiData.new()
 var t = data.battle_target(HOST,WorldMap.settlement_position("greyhaven"))
 assert_eq(t.kind,"settlement")
 assert_eq(t.faction,"house_lannet")
 assert_true(t.needs_war,"not at war yet: confirmation first")
 var before = data.events("war").size()
 data.declare_war("house_lannet")
 assert_true(data.at_war("house_lannet"))
 assert_true(Battles.at_war(data.state,"house_lannet","house_aurek"),"war is mutual")
 assert_eq(data.events("war").size(),before+1)
 assert_true(data.state.chronicle[-1].title.contains("War"))
 data.declare_war("house_lannet")
 assert_eq(data.events("war").size(),before+1,"declared once")
 assert_false(data.battle_target(HOST,WorldMap.settlement_position("greyhaven")).needs_war)
 assert_false(data.at_war("house_verrin"),"only the attacked faction")

func test_garrisons_scale_with_main_level_and_walls():
 var s = GameState.from_data()
 var g1 = Battles.garrison_units(s,"willowmere")   # village level 1, no walls
 var g2 = Battles.garrison_units(s,"greyhaven")    # city level 2 with walls
 assert_gt(g1.size(),0)
 assert_gt(g2.size(),g1.size())
 var archers = 0
 for u in g2: if u.unit == "archers": archers += 1
 assert_gt(archers,0,"walls add archers")
 Movement.reset()
 var pb = willowmere_battle(s)
 var setup = Battles.setup(s,pb,1)
 var garrison = 0
 for u in setup.sides[1].units: if u.get("garrison","") == "willowmere": garrison += 1
 assert_eq(garrison,g1.size(),"the garrison fights alongside the defenders")

func test_reinforcements_join_in_reserve_or_late():
 var s = GameState.from_data()
 Armies.raise_army(s,"house_aurek","crownwatch")
 var second = Armies.armies_of(s,"house_aurek").filter(func(a): return a != HOST)[0]
 Armies.recruit(s,second,"peasant_levy")
 TurnLoop.end_turn(s)
 var pb = field_battle(s)
 assert_true(pb.attacker.reinforcements.is_empty(),"far away: no reinforcements")
 place(s,second,Vector2(2,3))
 pb = Battles.prebattle(s,HOST,Battles.target_at(s,HOST,Vector2(2,-12)))
 assert_eq(pb.attacker.reinforcements.size(),1)
 var r = pb.attacker.reinforcements[0]
 assert_eq(r.army,second)
 var setup = Battles.setup(s,pb,1)
 var joined = setup.sides[0].units.filter(func(u): return u.get("army","") == second)
 assert_eq(joined.size(),s.army_state[second].units.size())
 for u in joined:
  assert_eq(u.line,"reserve")
  assert_eq(u.arrive_tick,int(r.arrive_tick))
 # Within the reserve radius they are there from the start; further out, they arrive late.
 place(s,second,Vector2(2,-6)) # 6 m from the battle: inside the reserve radius
 pb = Battles.prebattle(s,HOST,Battles.target_at(s,HOST,Vector2(2,-12)))
 assert_eq(int(pb.attacker.reinforcements[0].arrive_tick),0)

func test_walls_from_stored_defense_and_siege_turns():
 var s = GameState.from_data()
 place(s,HOST,near("greyhaven"))
 var t = Battles.target_at(s,HOST,WorldMap.settlement_position("greyhaven"))
 var pb = Battles.prebattle(s,HOST,t)
 assert_not_null(pb.field.walls,"Greyhaven's defense is above the wall threshold")
 assert_eq(int(pb.field.walls.defense),int(s.settlements.greyhaven.defense))
 assert_null(willowmere_battle(GameState.from_data()).field.get("walls"),"a village without walls: field battle")

func test_quick_resolve_applies_casualties_experience_and_movement_cost():
 var s = GameState.from_data()
 var pb = field_battle(s)
 var max_points = float(s.army_state[HOST].max_points)
 var out = Battles.quick_resolve(s,pb)
 var res = out.result
 assert_eq(s.battles,1)
 # Every surviving unit carries the battle's casualties and its experience.
 var host_units = res.sides[0].units
 var gone = out.aftermath.destroyed_units.filter(func(d): return d.army == HOST).size()
 if s.army_state.has(HOST):
  assert_eq(s.army_state[HOST].units.size(),host_units.size()-gone)
  var lost_total = 0
  for u in s.army_state[HOST].units: lost_total += int(u.max_men)-int(u.men)
  assert_gt(lost_total,0,"casualties applied")
  for u in s.army_state[HOST].units: assert_true(u.has("xp") and u.has("rank"))
  # Attacking costs a share of the movement allowance; the army may fight again if points remain.
  if out.aftermath.attacker_won:
   assert_almost_eq(float(s.army_state[HOST].points),max_points*(1.0-float(Battles.cfg().attack_movement_share)),0.01)

func test_destroyed_units_and_armies_are_removed():
 var s = GameState.from_data()
 # A hopeless defender: the Highbloom Levy alone in the open against the host.
 place(s,"highbloom_levy",Vector2(-40,-10))
 place(s,HOST,Vector2(-30,-10))
 Battles.declare_war(s,"house_aurek","house_verrin")
 var pb = Battles.prebattle(s,HOST,Battles.target_at(s,HOST,Vector2(-40,-10)))
 var out = Battles.quick_resolve(s,pb)
 assert_true(out.aftermath.attacker_won)
 for d in out.aftermath.destroyed_armies: assert_false(s.army_state.has(d.army))
 for d in out.aftermath.destroyed_armies: assert_does_not_have(s.armies,d.army)
 if s.army_state.has("highbloom_levy"):
  for u in s.army_state.highbloom_levy.units: assert_gt(int(u.men),0)

func test_capture_occupies_and_beaten_defenders_must_retreat_elsewhere():
 var s = GameState.from_data()
 var pb = willowmere_battle(s)
 var buildings = s.settlements.willowmere.buildings.duplicate(true)
 var pop = s.settlements.willowmere.population
 var out = Battles.quick_resolve(s,pb)
 assert_true(out.aftermath.attacker_won)
 assert_eq(out.aftermath.captured,"willowmere")
 assert_eq(s.settlements.willowmere.owner,"house_aurek")
 assert_eq(s.settlements.willowmere.buildings,buildings,"occupation keeps the buildings")
 assert_almost_eq(s.settlements.willowmere.population,pop,0.001,"and the population")
 assert_eq(s.army_state[HOST].garrison,"willowmere")
 # Verrin has nowhere left to retreat to: its army is destroyed (decision 5).
 assert_false(s.army_state.has("highbloom_levy"))
 var titles = []
 for e in out.aftermath.entries: titles.append(e.title)
 assert_true(titles.any(func(t): return t.contains("Willowmere")),"capture logged")

func test_loser_retreats_toward_its_nearest_own_settlement():
 var s = GameState.from_data()
 var pb = field_battle(s)
 var out = Battles.quick_resolve(s,pb)
 for r in out.aftermath.retreated:
  if r.destroyed: continue
  assert_ne(r.to,"","retreats toward an own settlement")
  assert_eq(s.settlements[r.to].owner,s.army_state[r.army].faction)
  assert_eq(s.army_state[r.army].points,0.0,"its allowance is spent")

func test_generals_wounded_or_killed_and_captains():
 var s = GameState.from_data()
 BattleSim.data().campaign.general_death = {"won":1.0,"lost":1.0,"routed":1.0,"destroyed":1.0}
 var pb = field_battle(s)
 var out = Battles.quick_resolve(s,pb)
 var killed = out.aftermath.generals.filter(func(g): return g.fate == "killed")
 assert_gt(killed.size(),0)
 for g in killed:
  if not s.army_state.has(g.army): continue
  var c = Battles.commander(s,g.army)
  assert_eq(c.status,"captain")
  # A captain cannot move the army...
  var plan = Movement.plan(s,g.army,Movement.position(s,g.army)+Vector2(4,0))
  assert_false(plan.ok)
  assert_eq(plan.reason,Movement.NO_GENERAL)
  # ...until a general is appointed (the general fee).
  s.treasury[s.army_state[g.army].faction] = 100000
  assert_true(Battles.appoint_general(s,g.army).ok)
  assert_true(Battles.can_move(s,g.army))
 # Death is more likely when routed or destroyed than in victory (data).
 BattleSim.reset()
 var gd = BattleSim.data().campaign.general_death
 assert_lt(float(gd.won),float(gd.lost))
 assert_lt(float(gd.lost),float(gd.routed))
 assert_lt(float(gd.routed),float(gd.destroyed))

func test_wounded_generals_return_and_captains_can_be_promoted():
 var s = GameState.from_data()
 var c = s.army_state[HOST].commander
 s.army_state[HOST].commander = {"name":"Captain","rank":1,"xp":0.0,"status":"wounded","wounded_turns":2,"general":c.duplicate()}
 assert_false(Battles.can_move(s,HOST))
 TurnLoop.end_turn(s)
 assert_false(Battles.can_move(s,HOST))
 TurnLoop.end_turn(s)
 assert_true(Battles.can_move(s,HOST))
 assert_eq(s.army_state[HOST].commander.name,c.name,"the wounded general returns")
 # A captain who wins a settlement battle (important) is promoted.
 var s2 = GameState.from_data()
 BattleSim.data().campaign.general_death = {"won":0.0,"lost":0.0,"routed":0.0,"destroyed":0.0}
 BattleSim.data().campaign.general_wound = {"won":0.0,"lost":0.0,"routed":0.0,"destroyed":0.0}
 var pb = willowmere_battle(s2)
 s2.army_state[HOST].commander = {"name":"Captain of Goldspire","rank":1,"xp":0.0,"status":"captain"}
 var out = Battles.quick_resolve(s2,pb)
 assert_true(out.aftermath.attacker_won)
 assert_eq(out.aftermath.promoted.size(),1)
 assert_eq(Battles.commander(s2,HOST).status,"ok")

func test_siege_endurance_starvation_and_surrender():
 var s = GameState.from_data()
 place(s,HOST,near("greyhaven"))
 Battles.declare_war(s,"house_aurek","house_lannet")
 var e = Battles.endurance(s,"greyhaven")
 assert_between(e,1,int(BattleSim.data().sieges.max_endurance),"endurance is capped (about 8 turns)")
 var r = Battles.besiege(s,HOST,"greyhaven")
 assert_true(r.ok)
 assert_eq(r.endurance,e)
 assert_false(Battles.besiege(s,HOST,"willowmere").ok,"no walls: assault instead")
 var guard_men = 0
 for u in s.army_state.silverfall_guard.units: guard_men += int(u.men)
 var turns = 0
 while s.settlements.greyhaven.owner == "house_lannet" and turns<30:
  s.army_state[HOST].points = 0.0
  TurnLoop.end_turn(s)
  turns += 1
  if turns<=e: assert_eq(s.settlements.greyhaven.siege.turns,turns)
 assert_eq(s.settlements.greyhaven.owner,"house_aurek","the starving garrison surrenders")
 assert_gt(turns,e,"not before its supplies run out")
 assert_false(s.settlements.greyhaven.has("siege"))
 # Siege turns weaken the walls in an assault.
 var s2 = GameState.from_data()
 place(s2,HOST,near("greyhaven"))
 Battles.besiege(s2,HOST,"greyhaven")
 s2.army_state[HOST].points = 0.0
 TurnLoop.end_turn(s2)
 var pb = Battles.prebattle(s2,HOST,Battles.target_at(s2,HOST,WorldMap.settlement_position("greyhaven")))
 assert_eq(int(pb.field.walls.siege_turns),1)

func test_siege_lifts_when_the_besieger_leaves():
 var s = GameState.from_data()
 place(s,HOST,near("greyhaven"))
 Battles.besiege(s,HOST,"greyhaven")
 place(s,HOST,Vector2(60,-20))
 var events = Battles.end_turn(s)
 assert_true(events.any(func(e): return e.kind == "siege_lifted"))
 assert_false(s.settlements.greyhaven.has("siege"))

func test_withdraw_costs_men_and_retreats():
 var s = GameState.from_data()
 var pb = field_battle(s)
 var before = 0
 for u in s.army_state.silverfall_guard.units: before += int(u.men)
 var r = Battles.withdraw(s,pb)
 assert_true(r.ok)
 var after = 0
 for u in s.army_state.silverfall_guard.units: after += int(u.men)
 assert_almost_eq(float(after),before*(1.0-float(Battles.cfg().withdraw_casualty_share)),float(s.army_state.silverfall_guard.units.size()))
 assert_false(Battles.withdraw(s,willowmere_battle(GameState.from_data())).ok,"a besieged garrison cannot withdraw")

func test_same_seed_gives_identical_result_and_report():
 var a = GameState.from_data()
 var b = GameState.from_data()
 var pa = field_battle(a)
 var pbb = field_battle(b)
 assert_eq(pa.seed,pbb.seed)
 assert_eq(pa.odds,pbb.odds)
 var oa = Battles.quick_resolve(a,pa)
 var ob = Battles.quick_resolve(b,pbb)
 assert_eq(JSON.stringify(oa.result),JSON.stringify(ob.result))
 assert_eq(JSON.stringify(BattleReport.build(pa,oa.result,oa.aftermath,"house_aurek")),JSON.stringify(BattleReport.build(pbb,ob.result,ob.aftermath,"house_aurek")))
 assert_eq(JSON.stringify(a.to_dict()),JSON.stringify(b.to_dict()))

func test_report_is_short_and_explains():
 var s = GameState.from_data()
 var pb = field_battle(s)
 var out = Battles.quick_resolve(s,pb)
 var rep = BattleReport.build(pb,out.result,out.aftermath,"house_aurek")
 assert_true(rep.headline.begins_with("Victory") or rep.headline.begins_with("Defeat"))
 assert_between(rep.why.size(),1,5,"a 3-5 line summary at most")
 if not rep.won: assert_true(rep.why[-1].begins_with("Lesson"),"defeats end with a lesson")
 assert_eq(rep.units.size(),out.result.sides[0].units.size())
 assert_true(rep.numbers.has("your_losses") and rep.numbers.has("their_losses"))

func test_balance_of_power_reflects_the_odds():
 var s = GameState.from_data()
 var strong = willowmere_battle(s)      # the host against two levies and a small garrison
 assert_gt(strong.odds,0.8)
 var s2 = GameState.from_data()
 place(s2,HOST,near("greyhaven"))
 var weak = Battles.prebattle(s2,HOST,Battles.target_at(s2,HOST,WorldMap.settlement_position("greyhaven")))
 assert_lt(weak.odds,strong.odds,"walls and a larger garrison lower the odds")
