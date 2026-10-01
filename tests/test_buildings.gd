extends GutTest
# Population taxes and building effects (data/economy.json, data/buildings.json): income scales with
# population, economic buildings add income or growth, military buildings record unit unlocks,
# walls and towers add a defense value stored on the settlement, upkeep comes from the chain data.

const GameState = preload("res://core/game_state.gd")
const Economy = preload("res://core/economy.gd")
const Buildings = preload("res://core/buildings.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const NO_RESOURCES = {"wood":0,"stone":0,"food":0,"minerals":0}

func after_each():
 Economy.reset()

func state_with(type: String,level: int,buildings := [],population := 5000.0,resources := NO_RESOURCES):
 var s = GameState.from_data()
 var st = s.settlements.greyhaven
 st.type = type
 st.level = level
 st.population = population
 st.resources = resources.duplicate()
 st.buildings = GameState.starting_slots("greyhaven",type,level,buildings)
 Buildings.refresh(s,"greyhaven")
 return s

func income(s) -> Dictionary:
 return Economy.settlement_income(s,"greyhaven")

func test_taxes_scale_with_population():
 var rate = float(Economy.data().taxes.tax_per_capita)
 assert_gt(rate,0.0)
 var small = income(state_with("city",2,[],4000.0))
 var big = income(state_with("city",2,[],12000.0))
 assert_almost_eq(small.tax,4000.0*rate,0.001)
 assert_almost_eq(big.tax,12000.0*rate,0.001)
 # With no endowments or buildings, the difference is exactly the extra tax.
 assert_eq(big.total-small.total,int(round(8000.0*rate)))
 assert_gt(big.total,small.total)

func test_taxes_respect_the_type_factor_and_ceiling():
 var city = income(state_with("city",1,[],10000.0))
 var fort = income(state_with("fortress",1,[],10000.0))
 assert_lt(fort.tax*fort.economic_factor,city.tax*city.economic_factor+0.001)
 var huge = income(state_with("fortress",1,[],1000000.0))
 assert_true(huge.capped)
 assert_eq(huge.total,int(Economy.data().settlement_types.fortress.income_ceiling[0]))

func test_market_adds_income_and_raises_tax_take():
 var plain = income(state_with("city",2,[],8000.0))
 var market = income(state_with("city",2,[{"chain":"market","level":2}],8000.0))
 var e = Buildings.level_data("market",2).effects
 assert_almost_eq(market.tax,plain.tax*(1.0+e.tax_pct),0.001)
 assert_eq(market.buildings,float(e.income))
 assert_gt(market.total,plain.total)

func test_mine_income_scales_with_mineral_endowment():
 var poor = income(state_with("city",2,[{"chain":"mine","level":2}],5000.0,NO_RESOURCES))
 var rich = income(state_with("city",2,[{"chain":"mine","level":2}],5000.0,{"wood":0,"stone":0,"food":0,"minerals":5}))
 var e = Buildings.level_data("mine",2).effects
 assert_eq(poor.buildings,float(e.income))
 assert_eq(rich.buildings,float(e.income)+5.0*e.income_per_endowment.minerals)

func test_farms_and_housing_raise_growth_and_capacity():
 var plain = Economy.growth(state_with("village",2,[],1500.0),"greyhaven")
 var farmed = Economy.growth(state_with("village",2,[{"chain":"farm","level":2}],1500.0),"greyhaven")
 assert_almost_eq(farmed.building_part,float(Buildings.level_data("farm",2).effects.growth),0.0001)
 assert_gt(farmed.delta,plain.delta)
 var housed = state_with("city",2,[{"chain":"houses","level":2}])
 assert_eq(Economy.capacity(housed,"greyhaven"),float(Economy.data().settlement_types.city.capacity[1])+Buildings.level_data("houses",2).effects.capacity)

func test_military_buildings_record_unit_unlocks():
 var s = state_with("city",3,[{"chain":"barracks","level":2},{"chain":"archery_range","level":1},{"chain":"stables","level":1}])
 var unlocks = s.settlements.greyhaven.unlocks
 # Unlocks accumulate over a chain's levels: barracks 2 keeps level 1's units.
 for u in ["peasant_levy","spearmen","swordsmen","archers","cavalry"]: assert_has(unlocks,u)
 assert_does_not_have(unlocks,"heavy_infantry")
 for u in unlocks: assert_true(UnitTypes.ids().has(u),"unlock %s must be a unit type" % u)

func test_walls_and_towers_add_a_stored_defense_value():
 var bare = state_with("fortress",2)
 var walled = state_with("fortress",2,[{"chain":"walls","level":2},{"chain":"watchtower","level":1}])
 var expected = int(Buildings.level_data("main_fortress",2).effects.defense)+int(Buildings.level_data("walls",2).effects.defense)+int(Buildings.level_data("watchtower",1).effects.defense)
 assert_eq(walled.settlements.greyhaven.defense,expected)
 assert_gt(walled.settlements.greyhaven.defense,bare.settlements.greyhaven.defense)

func test_building_upkeep_comes_from_each_built_level():
 var s = state_with("city",2,[{"chain":"market","level":1},{"chain":"port","level":2}])
 var expected = int(Buildings.level_data("main_city",2).upkeep)+int(Buildings.level_data("market",1).upkeep)+int(Buildings.level_data("port",2).upkeep)
 assert_eq(Economy.building_upkeep(s,"greyhaven"),expected)

func test_every_chain_is_valid_data():
 for id in Buildings.chain_ids():
  var c = Buildings.chain(id)
  assert_between(c.levels.size(),1,3,id)
  assert_true(c.has("visual") and c.has("category"),id)
  for l in c.levels:
   for k in ["name","cost","turns","upkeep","effects"]: assert_true(l.has(k),"%s: level missing %s" % [id,k])
   if not c.get("main",false): assert_between(int(l.turns),1,2,"%s %s: construction takes 1-2 turns" % [id,l.name])
   for u in l.effects.get("unlocks",[]): assert_true(UnitTypes.ids().has(u),"%s unlocks unknown unit %s" % [id,u])
 for type in Economy.data().settlement_types:
  if type.begins_with("_"): continue
  assert_true(Buildings.is_main(Buildings.main_chain_id(type)),type)

func test_slot_counts_rank_cities_over_fortresses_over_villages():
 for level in [1,2,3]:
  assert_gt(Buildings.slot_count("city",level),Buildings.slot_count("fortress",level))
  assert_gt(Buildings.slot_count("fortress",level),Buildings.slot_count("village",level))
  if level>1: assert_gt(Buildings.slot_count("city",level),Buildings.slot_count("city",level-1))

func test_starting_settlements_respect_level_caps_and_slot_counts():
 var s = GameState.from_data()
 for id in s.settlements:
  var st = s.settlements[id]
  assert_eq(st.buildings.size(),Buildings.slot_count(st.type,int(st.level)),id)
  assert_eq(st.buildings[0].chain,Buildings.main_chain_id(st.type),id)
  assert_eq(int(st.buildings[0].level),int(st.level),id)
  for b in Buildings.built(s,id): assert_lte(b.level,int(st.level),"%s %s" % [id,b.chain])
