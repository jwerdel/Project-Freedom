extends GutTest
# Recruitment and army upkeep (data/recruitment.json, data/units/*.json): recruiting draws men from
# the settlement's population and stops at the minimum; only units a settlement building unlocked
# can be recruited; queues complete on time and cancel refunds in full; disbanding returns men to
# the region's population; replenishment is free in friendly regions (faster where populous) and
# paid in enemy ones; the army cap holds; upkeep follows the real army.

const GameState = preload("res://core/game_state.gd")
const Armies = preload("res://core/armies.gd")
const Movement = preload("res://core/movement.gd")
const Economy = preload("res://core/economy.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const WorldMap = preload("res://core/world_map.gd")
const Buildings = preload("res://core/buildings.gd")
const ARMY = "aurek_host"
const GS = "goldspire_rock"

func after_each():
 Armies.reset()
 Movement.reset()
 Economy.reset()

# A state with the host garrisoned at Goldspire and plenty of gold.
func home_state():
 var s = GameState.from_data()
 var p = WorldMap.settlement_position(GS)
 s.army_state[ARMY].position = [p.x,p.y]
 s.army_state[ARMY].garrison = GS
 s.treasury.house_aurek = 1000000
 return s

func place(s,p: Vector2):
 s.army_state[ARMY].position = [p.x,p.y]
 s.army_state[ARMY].garrison = ""

func test_recruiting_takes_gold_and_population_and_queues_the_unit():
 var s = home_state()
 var u = UnitTypes.get_type("spearmen")
 var pop = s.settlements[GS].population
 var gold = s.treasury.house_aurek
 var r = Armies.recruit(s,ARMY,"spearmen")
 assert_true(r.ok,", ".join(r.reasons))
 assert_eq(r.settlement,GS)
 assert_almost_eq(s.settlements[GS].population,pop-u.size,0.001)
 assert_eq(s.treasury.house_aurek,gold-int(u.recruitment.cost))
 assert_eq(s.army_state[ARMY].queue.size(),1)
 assert_eq(s.army_state[ARMY].queue[0].turns_left,int(u.recruitment.turns))

func test_cannot_recruit_below_the_minimum_population():
 var s = home_state()
 var size = int(UnitTypes.get_type("spearmen").size)
 var minimum = float(Armies.data().recruitment.min_population)
 s.settlements[GS].population = minimum+size-1
 var r = Armies.recruit(s,ARMY,"spearmen")
 assert_false(r.ok)
 assert_string_contains(", ".join(r.reasons),"Too few people")
 s.settlements[GS].population = minimum+size
 assert_true(Armies.recruit(s,ARMY,"spearmen").ok,"exactly at the minimum is allowed")
 assert_almost_eq(s.settlements[GS].population,minimum,0.001)

func test_only_units_unlocked_by_a_settlement_building_can_be_recruited():
 var s = home_state()
 # Goldspire: main building (levy) and Garrison barracks level 1 (levy, spearmen).
 assert_true(Armies.can_recruit(s,ARMY,"peasant_levy").ok)
 assert_true(Armies.can_recruit(s,ARMY,"spearmen").ok)
 for locked in ["swordsmen","heavy_infantry","archers","cavalry"]:
  var r = Armies.can_recruit(s,ARMY,locked)
  assert_false(r.ok,locked)
  assert_string_contains(", ".join(r.reasons),"Requires",locked)
 assert_false(Armies.can_recruit(s,ARMY,"commander").ok,"generals are hired, not recruited")
 # Crownwatch has no barracks: levies only.
 var p = WorldMap.settlement_position("crownwatch")
 s.army_state[ARMY].position = [p.x,p.y]
 s.army_state[ARMY].garrison = "crownwatch"
 assert_true(Armies.can_recruit(s,ARMY,"peasant_levy").ok)
 assert_false(Armies.can_recruit(s,ARMY,"spearmen").ok)

func test_recruiting_needs_own_territory_not_a_settlement():
 var s = home_state()
 place(s,Vector2(-25,15)) # open country in Lannet's land (Greyhaven's region)
 var r = Armies.can_recruit(s,ARMY,"peasant_levy")
 assert_false(r.ok)
 assert_eq(r.reasons,["Must be in your own territory"])
 assert_false(Armies.recruit_context(s,ARMY).ok)
 # Anywhere in an own region counts, far from the settlement itself.
 var c = WorldMap.settlement_position("crownwatch")
 place(s,c+Vector2(0,40))
 assert_eq(WorldMap.region_at(c+Vector2(0,40)),"crownwatch","precondition: still Crownwatch's region")
 assert_true(Armies.recruit_context(s,ARMY).ok)
 assert_eq(Armies.can_recruit(s,ARMY,"peasant_levy").settlement,"crownwatch")
 # A foreign region never recruits for this army.
 place(s,WorldMap.settlement_position("greyhaven")+Vector2(5,0))
 assert_false(Armies.recruit_context(s,ARMY).ok)

func test_queue_completes_on_time_and_cancel_refunds_fully():
 var s = home_state()
 s.settlements[GS].unlocks.append("cavalry")
 var units = s.army_state[ARMY].units.size()
 Armies.recruit(s,ARMY,"spearmen")
 Armies.recruit(s,ARMY,"cavalry")
 var report = TurnLoop.end_turn(s)
 assert_eq(s.army_state[ARMY].units.size(),units+1,"one-turn unit arrives after one End Turn")
 assert_eq(report.recruited[0].unit,"spearmen")
 var arrived = s.army_state[ARMY].units[-1]
 assert_eq(arrived.men,arrived.max_men,"recruits arrive at full strength")
 assert_eq(s.army_state[ARMY].queue.size(),1)
 TurnLoop.end_turn(s)
 assert_eq(s.army_state[ARMY].units.size(),units+2,"two-turn unit arrives after two")
 assert_true(s.army_state[ARMY].queue.is_empty())
 # Cancel: full refund of gold and men, even after a turn has passed.
 var pop = s.settlements[GS].population
 var gold = s.treasury.house_aurek
 Armies.recruit(s,ARMY,"cavalry")
 TurnLoop.end_turn(s)
 var pop2 = s.settlements[GS].population
 var gold2 = s.treasury.house_aurek
 var r = Armies.cancel_recruit(s,ARMY,0)
 assert_eq(r.gold,int(UnitTypes.get_type("cavalry").recruitment.cost))
 assert_eq(s.treasury.house_aurek,gold2+r.gold)
 assert_almost_eq(s.settlements[GS].population,pop2+int(UnitTypes.get_type("cavalry").size),0.001)
 assert_true(s.army_state[ARMY].queue.is_empty())

func test_disband_returns_men_to_the_region_population():
 var s = home_state()
 var u = s.army_state[ARMY].units[0]
 var men = int(u.men)
 var pop = s.settlements[GS].population
 var count = s.army_state[ARMY].units.size()
 var r = Armies.disband(s,ARMY,0)
 assert_eq(r.men,men)
 assert_eq(r.settlement,GS)
 assert_almost_eq(s.settlements[GS].population,pop+men,0.001)
 assert_eq(s.army_state[ARMY].units.size(),count-1)
 # In Lannet's land the men join Greyhaven's population (the region they stand in).
 place(s,Vector2(-25,15))
 var gpop = s.settlements.greyhaven.population
 r = Armies.disband(s,ARMY,0)
 assert_eq(r.settlement,"greyhaven")
 assert_almost_eq(s.settlements.greyhaven.population,gpop+r.men,0.001)
 # In the unsettled Greyspine there is no population to return to.
 place(s,Vector2(-250,-332))
 assert_eq(Armies.disband(s,ARMY,0).settlement,"")

func test_replenishment_is_free_at_home_and_faster_where_populous():
 var s = home_state()
 for u in s.army_state[ARMY].units: u.men = int(u.max_men/2)
 var pops = {}
 for id in s.settlements: pops[id] = s.settlements[id].population
 var gold = s.treasury.house_aurek
 var before = Armies.men(s.army_state[ARMY])
 var r = Armies.replenish(s)
 assert_gt(Armies.men(s.army_state[ARMY]),before)
 assert_eq(r[ARMY].gold,0)
 assert_eq(s.treasury.house_aurek,gold,"free in friendly regions")
 for id in s.settlements: assert_eq(s.settlements[id].population,pops[id],"no population cost")
 # More populous home region, faster replenishment.
 var rich = Armies.replenish_rate(s,ARMY).rate
 s.settlements[GS].population = 1000.0
 assert_lt(Armies.replenish_rate(s,ARMY).rate,rich)
 # Never above full strength.
 for i in 30: Armies.replenish(s)
 for u in s.army_state[ARMY].units: assert_eq(u.men,u.max_men)

func test_replenishment_costs_gold_in_enemy_territory():
 var s = home_state()
 place(s,Vector2(-25,15))
 assert_ne(Armies.region_owner(s,ARMY),"house_aurek")
 for u in s.army_state[ARMY].units: u.men = int(u.max_men/2)
 var gold = s.treasury.house_aurek
 var r = Armies.replenish(s)
 assert_false(r[ARMY].friendly)
 assert_gt(r[ARMY].gold,0)
 assert_eq(s.treasury.house_aurek,gold-r[ARMY].gold)
 # With an empty treasury nothing is replenished abroad.
 s.treasury.house_aurek = 0
 for u in s.army_state[ARMY].units: u.men = int(u.max_men/2)
 assert_false(Armies.replenish(s).has(ARMY))

func test_army_cap_is_enforced():
 var s = home_state()
 var cap = Armies.max_units()
 assert_eq(cap,20)
 while Armies.card_count(s.army_state[ARMY])<cap:
  s.settlements[GS].population = 100000.0
  assert_true(Armies.recruit(s,ARMY,"peasant_levy").ok)
 var r = Armies.recruit(s,ARMY,"peasant_levy")
 assert_false(r.ok)
 assert_string_contains(", ".join(r.reasons),"Army is full")

func test_upkeep_follows_the_real_army():
 var s = home_state()
 var before = Economy.army_upkeep(s,ARMY)
 Armies.recruit(s,ARMY,"spearmen")
 assert_eq(Economy.army_upkeep(s,ARMY),before,"queued units cost nothing yet")
 TurnLoop.end_turn(s)
 var per_unit = int(round(UnitTypes.get_type("spearmen").placeholder_stats.upkeep*Economy.data().upkeep.army_upkeep_multiplier))
 assert_almost_eq(Economy.army_upkeep(s,ARMY),before+per_unit,1)
 Armies.disband(s,ARMY,s.army_state[ARMY].units.size()-1)
 assert_almost_eq(Economy.army_upkeep(s,ARMY),before,1)

func test_rival_factions_start_with_garrisoned_armies():
 var s = GameState.from_data()
 assert_eq(s.armies_of("house_lannet"),["silverfall_guard"])
 assert_eq(s.armies_of("house_verrin"),["highbloom_levy"])
 assert_eq(s.army_state.silverfall_guard.garrison,"greyhaven")
 assert_eq(s.army_state.highbloom_levy.garrison,"willowmere")
 for id in s.army_state:
  for u in s.army_state[id].units: assert_between(int(u.men),1,int(u.max_men),id)

func test_hiring_a_general_raises_a_new_garrisoned_army():
 var s = home_state()
 # Goldspire already holds the host: hire at Crownwatch.
 assert_false(Armies.can_raise(s,"house_aurek",GS).ok,"one army per garrison")
 var gold = s.treasury.house_aurek
 var r = Armies.raise_army(s,"house_aurek","crownwatch")
 assert_true(r.ok,", ".join(r.reasons))
 var a = s.army_state[r.army]
 assert_eq(s.treasury.house_aurek,gold-int(Armies.data().armies.general_cost))
 assert_eq(a.faction,"house_aurek")
 assert_eq(a.garrison,"crownwatch")
 assert_true(a.units.is_empty())
 assert_string_contains(a.commander.name,"Aurek")
 assert_ne(a.commander.name,s.army_state[ARMY].commander.name)
 assert_has(s.armies,r.army)
 assert_has(s.armies_of("house_aurek"),r.army)
 assert_eq(Movement.position(s,r.army),WorldMap.settlement_position("crownwatch"))
 assert_true(Armies.can_recruit(s,r.army,"peasant_levy").ok,"the new army recruits where it was raised")
 assert_gt(Economy.army_upkeep(s,r.army),0,"a general costs upkeep")
 # Foreign settlements, the army limit and an empty treasury are refused.
 assert_false(Armies.can_raise(s,"house_aurek","greyhaven").ok)
 s.army_state[r.army].garrison = ""
 s.army_state[r.army].position = [150.0,-25.0]
 while Armies.armies_of(s,"house_aurek").size()<int(Armies.data().armies.max_per_faction):
  var n = Armies.raise_army(s,"house_aurek","crownwatch")
  assert_true(n.ok)
  s.army_state[n.army].garrison = ""
  s.army_state[n.army].position = [150.0,-30.0]
 var over = Armies.can_raise(s,"house_aurek","crownwatch")
 assert_false(over.ok)
 assert_string_contains(", ".join(over.reasons),"Army limit")

