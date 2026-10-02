extends GutTest
# Battle simulation (docs/battle-design.md): the Monte Carlo scenarios at a smaller sample (the full
# report is scripts/battle_harness.gd, same seeds), determinism, fast mode, AI templates, and the approved rules.

const BattleSim = preload("res://core/battle_sim.gd")
const BattleDeploy = preload("res://core/battle_deploy.gd")
const Harness = preload("res://tests/battle_harness.gd")
const UnitTypes = preload("res://core/unit_types.gd")
# Same battle count and seeds as the authoritative report (scripts/battle_harness.gd), so the tests
# reproduce its table exactly; narrow bands like 45-55% need this sample size.
const N = 500

func after_each():
 BattleSim.reset()
 UnitTypes.reset()

func _check(id: String):
 for row in Harness.evaluate(Harness.scenario(id),N):
  assert_true(row.pass,"scenario %s, %s: target %s, actual %s" % [row.scenario,row.label,row.target,row.actual])

func test_scenario_1_mirror(): _check("1")
func test_scenario_2_good_vs_bad_deployment(): _check("2")
func test_scenario_3_braced_spears_vs_charge(): _check("3")
func test_scenario_4_cavalry_vs_unprotected_archers(): _check("4")
func test_scenario_5_flanks_and_reserves(): _check("5")
func test_scenario_6_holding_a_pass(): _check("6")
func test_scenario_7_archers_vs_armour(): _check("7")
func test_scenario_8_walls(): _check("8")
func test_scenario_9_general_rank(): _check("9")
func test_scenario_10_more_men_wins_more(): _check("10")
func test_scenario_11_determinism(): _check("11")
func test_scenario_12_speed(): _check("12")

func standard_setup(seed: int) -> Dictionary:
 return Harness.build(Harness.resolve(Harness.scenario("1"),0),seed,true,5)

func test_same_seed_gives_identical_result_report_and_replay():
 var a = BattleSim.simulate(standard_setup(99))
 var b = BattleSim.simulate(standard_setup(99))
 assert_eq(JSON.stringify(a),JSON.stringify(b))
 assert_gt(a.events.size(),0)
 assert_eq(a.replay.size(),a.ticks)
 var c = BattleSim.simulate(standard_setup(100))
 assert_ne(JSON.stringify(a),JSON.stringify(c),"a different seed gives a different battle")

func test_fast_mode_gives_the_same_outcome_without_replay_or_events():
 for seed in 20:
  var full = BattleSim.simulate(standard_setup(seed))
  var setup = standard_setup(seed)
  setup.fast = true
  var fast = BattleSim.simulate(setup)
  assert_eq(fast.winner,full.winner)
  assert_eq(BattleSim.losses(fast,0),BattleSim.losses(full,0))
  assert_eq(fast.replay.size(),0)
  assert_eq(fast.events.size(),0)

func test_templates_respect_lane_capacity_and_give_valid_orders():
 var army = []
 for id in Harness.data().armies.standard: army.append({"unit":id,"men":UnitTypes.get_type(id).size})
 for field in ["open","pass"]:
  var ter = Harness.terrain(field,5)
  for t in BattleDeploy.TEMPLATES:
   for role in 2:
    var placed = BattleDeploy.deploy(army,t,ter,role)
    assert_eq(placed.size(),army.size(),"%s %s: every unit placed" % [t,field])
    var used = {}
    for u in placed:
     assert_true(u.order in ["hold","aggressive","flank","protect","reserve"],u.order)
     if u.line == "reserve": continue
     var band = (1 if u.line == "front" else 0) if role == 0 else (4 if u.line == "front" else 5)
     var key = "%s:%d" % [u.line,u.lane]
     used[key] = used.get(key,0)+1
     assert_lte(used[key],BattleDeploy.capacity(ter,5,u.lane,band),"%s %s: lane %d %s over capacity" % [t,field,u.lane,u.line])
     if u.order == "flank": assert_true(u.lane == 0 or u.lane == 4,"flankers start in an outer lane")

func test_the_ai_picks_templates_from_faction_style():
 var levies = []
 for i in 5: levies.append({"unit":"peasant_levy","men":160})
 levies.append({"unit":"spearmen","men":120})
 var style = {"default":"line","if_levy_majority":"levy_swarm"}
 assert_eq(BattleDeploy.choose_template(style,levies,false),"levy_swarm")
 assert_eq(BattleDeploy.choose_template({"default":"shield_wall"},levies,false),"shield_wall")
 assert_eq(BattleDeploy.choose_template(style,levies,true),"hold_walls")

func duel(cav_charge_share: float) -> Dictionary:
 BattleSim.data().combat.brace_charge_reduction = cav_charge_share
 var c = Harness.resolve(Harness.scenario("3"),0)
 return BattleSim.simulate(Harness.build(c,5,false,5))

func test_braced_spears_blunt_but_do_not_cancel_the_charge():
 var share = float(BattleSim.data().combat.brace_charge_reduction)
 assert_between(share,0.0,0.99,"a share, not a full cancel")
 var r = duel(share)
 var braced = false
 for e in r.events: braced = braced or e.tag == "charge_braced"
 assert_true(braced)
 assert_true(r.causes.has("brace:1"))

func test_turning_to_face_removes_the_rear_attack():
 var c = Harness.resolve(Harness.scenario("5"),0)
 BattleSim.data().orders.turn_face.base = 1.0
 BattleSim.data().orders.turn_face.max = 1.0
 var faced = 0
 var rear = 0
 for seed in 20:
  var r = BattleSim.simulate(Harness.build(c,seed,true,5))
  for e in r.events:
   if e.tag == "turned_to_face": faced += 1
   if e.tag == "flank_hit_rear": rear += 1
 assert_gt(faced,0)
 assert_eq(rear,0,"with a certain turn, no flanker ever hits from behind")

func test_waiting_units_support_the_fight_in_a_pass():
 var c = Harness.resolve(Harness.scenario("6"),0)
 var changed = 0
 for seed in 20:
  var setup = Harness.build(c,seed,false,5)
  BattleSim.data().combat.pass_support_fraction = 0.0
  var without = BattleSim.simulate(setup.duplicate(true))
  BattleSim.data().combat.pass_support_fraction = 1.0
  var with_support = BattleSim.simulate(setup.duplicate(true))
  if JSON.stringify(without.sides) != JSON.stringify(with_support.sides): changed += 1
 assert_gt(changed,0,"support changes at least some pass fights")
