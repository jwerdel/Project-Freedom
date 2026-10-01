extends GutTest
# Economy and turn loop: income math follows data/economy.json for every settlement type, Goldspire
# out-earns a generic city, resources raise income but are never consumed, economic settlements
# grow faster than defensive ones, and End Turn is deterministic for a given seed.

const GameState = preload("res://core/game_state.gd")
const Economy = preload("res://core/economy.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const Buildings = preload("res://core/buildings.gd")
const Construction = preload("res://core/construction.gd")
const NO_RESOURCES = {"wood":0,"stone":0,"food":0,"minerals":0}

func after_each():
 Economy.reset()

# A fresh state with one settlement rewritten to the given type, level, resources and population,
# holding only its main building (so only those inputs and the listed buildings count).
func state_with(type: String,level: int,resources: Dictionary,population := 5000.0,id := "greyhaven",buildings := []):
 var s = GameState.from_data()
 s.settlements[id].type = type
 s.settlements[id].level = level
 s.settlements[id].resources = resources.duplicate()
 s.settlements[id].population = population
 s.settlements[id].buildings = GameState.starting_slots(id,type,level,buildings)
 Buildings.refresh(s,id)
 return s

# Independent restatement of the income formula (data/economy.json _income), without buildings.
func expected_income(type: String,level: int,resources: Dictionary,population := 5000.0) -> int:
 var t = Economy.data().settlement_types[type]
 var bonus = 0.0
 for r in resources: bonus += resources[r]*Economy.data().resources[r].income_bonus
 var tax = population*Economy.data().taxes.tax_per_capita
 return int(round(minf((t.base_income[level-1]+tax)*t.economic_factor*(1.0+bonus),t.income_ceiling[level-1])))

func test_income_matches_data_for_every_settlement_type_and_level():
 var res = {"wood":1,"stone":2,"food":3,"minerals":1}
 for type in ["city","town","village","castle","fortress"]:
  for level in [1,2,3]:
   var s = state_with(type,level,res)
   assert_eq(Economy.settlement_income(s,"greyhaven").total,expected_income(type,level,res),"%s level %d" % [type,level])

func test_cities_out_earn_fortresses_and_fortresses_hit_a_lower_ceiling():
 for level in [1,2,3]:
  var city = Economy.settlement_income(state_with("city",level,NO_RESOURCES),"greyhaven").total
  var fort = Economy.settlement_income(state_with("fortress",level,NO_RESOURCES),"greyhaven").total
  assert_gt(city,fort,"level %d" % level)
 # Even a lavishly endowed, fully developed fortress stops at its ceiling.
 var rich = {"wood":5,"stone":5,"food":5,"minerals":5}
 var capped = Economy.settlement_income(state_with("fortress",3,rich),"greyhaven")
 assert_true(capped.capped)
 assert_eq(capped.total,int(Economy.data().settlement_types.fortress.income_ceiling[2]))
 assert_lt(capped.total,Economy.data().settlement_types.city.income_ceiling[2])

func test_goldspire_out_earns_a_generic_city_of_the_same_level():
 for level in [1,2,3]:
  var s = GameState.from_data()
  s.settlements.goldspire_rock.level = level
  s.settlements.greyhaven.level = level
  var goldspire = Economy.settlement_income(s,"goldspire_rock").total
  var generic = Economy.settlement_income(state_with("city",level,NO_RESOURCES),"greyhaven").total
  assert_eq(s.settlements.goldspire_rock.type,"city")
  assert_gt(goldspire,generic*1.5,"level %d: Goldspire %d vs generic city %d" % [level,goldspire,generic])
  assert_gt(goldspire,Economy.settlement_income(s,"greyhaven").total,"level %d: Goldspire vs Greyhaven" % level)

func test_resources_raise_income_but_are_never_consumed():
 var with_res = {"wood":2,"stone":2,"food":2,"minerals":2}
 assert_gt(Economy.settlement_income(state_with("city",2,with_res),"greyhaven").total,Economy.settlement_income(state_with("city",2,NO_RESOURCES),"greyhaven").total)
 var s = GameState.from_data()
 var before = {}
 for id in s.settlements: before[id] = s.settlements[id].resources.duplicate()
 for i in 10: TurnLoop.end_turn(s)
 for id in s.settlements: assert_eq(s.settlements[id].resources,before[id],id+" resources must not change")

func test_economic_settlements_grow_faster_than_defensive_ones():
 for pair in [["city","fortress"],["village","castle"],["town","castle"]]:
  for level in [1,2,3]:
   # Same resources and the same fraction of capacity, so only the settlement type differs.
   var cap_a = Economy.data().settlement_types[pair[0]].capacity[level-1]
   var cap_b = Economy.data().settlement_types[pair[1]].capacity[level-1]
   var a = Economy.growth(state_with(pair[0],level,NO_RESOURCES,cap_a*0.4),"greyhaven")
   var b = Economy.growth(state_with(pair[1],level,NO_RESOURCES,cap_b*0.4),"greyhaven")
   assert_gt(a.delta/(cap_a*0.4),b.delta/(cap_b*0.4),"%s vs %s level %d" % [pair[0],pair[1],level])

func test_food_and_wealth_raise_growth_and_popularity_is_a_neutral_stub():
 var poor = Economy.growth(state_with("city",2,NO_RESOURCES),"greyhaven")
 var fed = Economy.growth(state_with("city",2,{"wood":0,"stone":0,"food":4,"minerals":0}),"greyhaven")
 assert_gt(fed.rate,poor.rate)
 assert_eq(poor.popularity_part,0.0)

func test_population_approaches_but_does_not_pass_capacity():
 var s = state_with("village",1,{"wood":0,"stone":0,"food":5,"minerals":0},2000.0)
 # Keep the placeholder AI from upgrading the settlement (which would raise the cap).
 for i in 200:
  s.treasury.house_lannet = 0
  TurnLoop.end_turn(s)
 var cap = Economy.data().settlement_types.village.capacity[0]
 assert_lt(s.settlements.greyhaven.population,cap+0.5)
 assert_gt(s.settlements.greyhaven.population,cap*0.95)

func test_turn_applies_income_then_expenses_for_every_faction():
 var s = GameState.from_data()
 var before = s.treasury.duplicate()
 var ledgers = {}
 for f in s.factions(): ledgers[f] = Economy.faction_ledger(s,f)
 var report = TurnLoop.end_turn(s)
 for f in s.factions():
  # The placeholder AI may also start construction after income and expenses.
  var spent = 0
  for a in report.ai_started:
   if a.faction == f: spent += int(Construction.in_progress(s,a.settlement).cost)
  # Replenishing in foreign land also costs gold.
  for id in report.replenished:
   if s.army_state[id].faction == f: spent += int(report.replenished[id].gold)
  assert_eq(s.treasury[f],before[f]+ledgers[f].income_total-ledgers[f].expense_total-spent,f)
 assert_eq(report.year,1)
 assert_eq(s.year,2)
 var aurek = ledgers.house_aurek
 var army = 0
 for e in aurek.expenses: if e.kind == "army": army += e.amount
 assert_eq(army,Economy.army_upkeep(s,"aurek_host"))
 assert_gt(army,0)

func test_end_turn_is_deterministic_with_the_same_seed():
 var a = GameState.from_data()
 var b = GameState.from_data()
 for i in 10:
  TurnLoop.end_turn(a)
  TurnLoop.end_turn(b)
 assert_eq(JSON.stringify(a.to_dict(),"",true),JSON.stringify(b.to_dict(),"",true))

func test_chronicle_records_each_year_in_the_grey_scribes_voice():
 var s = GameState.from_data()
 var start = s.chronicle.size()
 TurnLoop.end_turn(s)
 assert_eq(s.chronicle.size(),start+2)
 var summary = s.chronicle[start]
 assert_eq(summary.year,1)
 assert_string_contains(summary.text,"House Aurek")
 assert_eq(s.chronicle[start+1].year,2)
