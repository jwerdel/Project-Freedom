extends GutTest
# Part B (owner spec 2026-10-07; war-and-realm §2.7, §2.8, §7): food, wood and stone stockpiles,
# production and upkeep, deficits, material costs, markets, army supply and siege endurance.

const GameState = preload("res://core/game_state.gd")
const Resources = preload("res://core/resources.gd")
const Markets = preload("res://core/markets.gd")
const Supply = preload("res://core/supply.gd")
const Seasons = preload("res://core/seasons.gd")
const Buildings = preload("res://core/buildings.gd")
const Construction = preload("res://core/construction.gd")
const Battles = preload("res://core/battles.gd")
const BattleSim = preload("res://core/battle_sim.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const WorldMap = preload("res://core/world_map.gd")
const MapRegistry = preload("res://core/map_registry.gd")
const Land = preload("res://core/land.gd")
const SaveCodec = preload("res://core/save_codec.gd")
const GS = "goldspire_rock"
const ARMY = "aurek_host"
const ME = "house_aurek"

func _summer(s):
 s.seasons = {"schedule":[{"kind":"summer","start":0,"length":1000}],"announced":[]}

func _winter(s):
 s.seasons = {"schedule":[{"kind":"summer","start":0,"length":int(s.turn)},{"kind":"winter","start":int(s.turn),"length":3,"forecast":2}],"announced":[]}

func _empty_slot(s,id) -> int:
 for i in s.settlements[id].buildings.size():
  if s.settlements[id].buildings[i].is_empty(): return i
 return -1

# --- Starting state ----------------------------------------------------------------------------------

func _check_start(map_id: String):
 MapRegistry.set_active(map_id)
 var s = GameState.from_data()
 var st = Resources.data().start
 for f in s.factions():
  if s.settlements_of(f).is_empty(): continue
  var food = Resources.amount(s,f,"food")
  assert_gte(food,int(ceil(Resources.consumption(s,f)*float(st.start_food_turns))),"%s %s: food for its first turns" % [map_id,f])
  assert_gte(int(Resources.ledger(s,f).food.net),0,"%s %s: no faction starts short of food" % [map_id,f])
  assert_gt(Resources.amount(s,f,"wood"),0)
  assert_gt(Resources.amount(s,f,"stone"),0)
  assert_false(Resources.starving(s,f))

func test_no_faction_starts_short():
 _check_start(MapRegistry.DEFAULT)
 _check_start(MapRegistry.CAMPAIGN)
 MapRegistry.set_active(MapRegistry.DEFAULT)

# --- Production and upkeep ------------------------------------------------------------------------------

func test_production_is_land_people_and_buildings_times_season_and_climate():
 var s = GameState.from_data()
 _summer(s)
 var land = Resources.data().land
 var st = s.settlements[GS]
 var e = st.resources
 var food = float(e.get("food",0))*float(land.food)+float(st.population)/1000.0*float(land.subsistence)
 var stone = float(e.get("stone",0))*float(land.stone)+float(e.get("minerals",0))*float(land.minerals_stone)
 var wood = float(e.get("wood",0))*float(land.wood)
 for b in st.buildings:
  if not b.has("chain"): continue
  var p = Buildings.produces(b.chain,int(b.level))
  food += float(p.get("food",0)); wood += float(p.get("wood",0)); stone += float(p.get("stone",0))
 food *= Seasons.food_factor(s,GS)*Land.climate_factor(s,GS)
 var got = Resources.production(s,GS)
 assert_eq(got.food,int(round(food)))
 assert_eq(got.wood,int(round(wood)))
 assert_eq(got.stone,int(round(stone)))
 assert_gt(Seasons.food_factor(s,GS),1.0,"summer bonus")

func test_buildings_produce_what_their_data_says():
 assert_gt(int(Buildings.produces("farm",1).get("food",0)),0)
 assert_gt(int(Buildings.produces("farm",2).food),int(Buildings.produces("farm",1).food))
 assert_gt(int(Buildings.produces("lumber",1).get("wood",0)),0)
 assert_gt(int(Buildings.produces("quarry",1).get("stone",0)),0)
 assert_gt(int(Buildings.produces("mine",1).get("stone",0)),0)
 assert_gt(int(Buildings.produces("pasture",1).get("food",0)),0)

func test_consumption_counts_people_and_every_unit():
 var s = GameState.from_data()
 var c = Resources.data().consumption
 var pop = 0.0
 for sid in s.settlements_of(ME): pop += float(s.settlements[sid].population)
 var units = 0
 for id in s.armies_of(ME): units += s.army_state[id].units.size()
 assert_almost_eq(Resources.consumption(s,ME),pop/1000.0*float(c.per_1000)+units*float(c.per_unit),0.001)
 var l = Resources.ledger(s,ME)
 assert_eq(l.food.net,l.food.income-l.food.expense)
 assert_almost_eq(float(l.food.expense),Resources.consumption(s,ME),1.0)

func test_end_turn_adds_the_net_to_the_stockpile():
 var s = GameState.from_data()
 _summer(s)
 var before = Resources.stock(s,ME).duplicate()
 var l = Resources.ledger(s,ME)
 Resources.end_turn(s)
 for k in Resources.KINDS: assert_eq(Resources.amount(s,ME,k),int(before[k])+int(l[k].net),k)

# --- Deficits ---------------------------------------------------------------------------------------------

func test_a_food_deficit_stops_growth_then_shrinks_people_and_bleeds_field_armies():
 var s = GameState.from_data()
 _summer(s)
 # Far more mouths than food: a huge army.
 var a = s.army_state[ARMY]
 for i in 400: a.units.append(a.units[0].duplicate())
 Resources.stock(s,ME).food = 0
 assert_lt(int(Resources.ledger(s,ME).food.net),0)
 assert_gte(Resources.food_turns_left(s,ME),0,"the End Turn warning knows when food runs out")
 var ev = Resources.end_turn(s)
 assert_true(Resources.starving(s,ME))
 assert_eq(Resources.amount(s,ME,"food"),0,"never below zero")
 assert_true(ev.any(func(e): return e.faction == ME and e.kind == "famine"))
 # Next turn: growth stops (the turn loop), people do not yet shrink.
 var pop = float(s.settlements[GS].population)
 var men = int(s.army_state[ARMY].units[0].men)
 Resources.end_turn(s)
 assert_eq(float(s.settlements[GS].population),pop,"the first hungry turn only stops growth")
 # Then they shrink and field armies lose men.
 Resources.end_turn(s)
 assert_lt(float(s.settlements[GS].population),pop)
 if str(s.army_state[ARMY].get("garrison","")) == "": assert_lt(int(s.army_state[ARMY].units[0].men),men)
 # Food again: the famine ends.
 Resources.stock(s,ME).food = 100000
 for sid in s.settlements_of(ME): s.settlements[sid].population = 100.0
 ev = Resources.end_turn(s)
 assert_false(Resources.starving(s,ME))
 assert_true(ev.any(func(e): return e.faction == ME and e.kind == "famine_ends"))

func test_a_starving_realm_does_not_grow_in_the_turn_loop():
 var s = GameState.from_data()
 _summer(s)
 Resources.stock(s,ME).starving = 1
 Resources.stock(s,ME).food = 0
 var pop = float(s.settlements[GS].population)
 TurnLoop.end_turn(s)
 assert_lte(float(s.settlements[GS].population),pop)

# --- Material costs ---------------------------------------------------------------------------------------

func test_buildings_cost_wood_and_stone_and_refund_them():
 var s = GameState.from_data()
 s.treasury[ME] = 1000000
 var mats = Resources.building_cost("market",1)
 assert_gt(int(mats.get("wood",0))+int(mats.get("stone",0)),0)
 var walls = Resources.building_cost("walls",1)
 assert_gt(int(walls.get("stone",0)),int(walls.get("wood",0)),"walls are mostly stone")
 var slot = _empty_slot(s,GS)
 Resources.stock(s,ME).wood = 0
 var check = Construction.can_build(s,GS,slot,"market")
 assert_false(check.ok)
 assert_string_contains(", ".join(check.reasons),"Not enough wood")
 Resources.stock(s,ME).wood = 1000
 Resources.stock(s,ME).stone = 1000
 assert_true(Construction.start(s,GS,slot,"market").ok)
 assert_eq(Resources.amount(s,ME,"wood"),1000-int(mats.wood))
 assert_eq(Resources.amount(s,ME,"stone"),1000-int(mats.stone))
 Construction.cancel(s,GS,slot)
 assert_eq(Resources.amount(s,ME,"wood"),1000,"cancelled the same turn: full refund")
 # The construction options show the materials.
 var opts = Construction.options(s,GS,slot)
 assert_true(opts.any(func(o): return o.has("materials")))

func test_some_units_cost_food_or_wood():
 var costs = Resources.data().unit_costs
 assert_true(costs.siege.has("wood"))
 assert_true(costs.cav_shock.has("food"))
 var s = GameState.from_data()
 Resources.stock(s,ME).wood = 10
 assert_eq(Resources.shortfall(s,ME,{"wood":90}),["Not enough wood (90 needed)"])
 assert_eq(Resources.shortfall(s,ME,{"wood":5}),[])

# --- Markets ----------------------------------------------------------------------------------------------

func test_market_prices_follow_scarcity_biome_and_season():
 var s = GameState.from_data()
 _summer(s)
 Resources.stock(s,ME).food = 10000
 var plenty = float(Markets.price(s,ME,"food").price)
 Resources.stock(s,ME).food = 0
 var scarce = float(Markets.price(s,ME,"food").price)
 assert_gt(scarce,plenty,"scarce food is dear")
 var summer = Markets.price(s,ME,"food")
 _winter(s)
 var winter = Markets.price(s,ME,"food")
 if Seasons.dry_land(load("res://core/armies.gd").capital(s,ME)):
  assert_almost_eq(float(winter.season),float(Resources.data().markets.season.dry.food),0.001)
 else:
  assert_almost_eq(float(winter.price),float(summer.price)*float(Resources.data().markets.season.winter.food),0.001,"food dearer in winter")
 assert_almost_eq(float(winter.price),float(winter.base)*float(winter.scarcity)*float(winter.biome)*float(winter.season),0.001)
 # Wood is dear in the desert.
 assert_gt(float(Resources.data().markets.biome.desert.wood),1.0)

func test_buying_and_selling_move_gold_and_stock():
 var s = GameState.from_data()
 s.treasury[ME] = 5000
 var cost = Markets.buy_cost(s,ME,"stone",100)
 var stone = Resources.amount(s,ME,"stone")
 assert_true(Markets.buy(s,ME,"stone",100).ok)
 assert_eq(int(s.treasury[ME]),5000-cost)
 assert_eq(Resources.amount(s,ME,"stone"),stone+100)
 var value = Markets.sell_value(s,ME,"stone",100)
 assert_lt(value,Markets.buy_cost(s,ME,"stone",100),"selling pays less than buying")
 var gold = int(s.treasury[ME])
 assert_true(Markets.sell(s,ME,"stone",100).ok)
 assert_eq(int(s.treasury[ME]),gold+value)
 s.treasury[ME] = 0
 assert_false(Markets.buy(s,ME,"food",100).ok)
 Resources.stock(s,ME).wood = 5
 assert_false(Markets.sell(s,ME,"wood",100).ok)

func test_the_ai_stockpiles_food_before_winter_and_covers_shortages():
 var s = GameState.from_data()
 s.turn = 10
 s.seasons = {"schedule":[{"kind":"summer","start":0,"length":12},{"kind":"winter","start":12,"length":2,"forecast":3}],"announced":[]}
 s.treasury[ME] = 100000
 Resources.stock(s,ME).food = 0
 var trades = Markets.ai_turn(s,ME)
 assert_true(trades.any(func(t): return t.kind == "food"),"buys food before the winter")
 assert_gt(Resources.amount(s,ME,"food"),0)
 assert_lt(int(s.treasury[ME]),100000)
 # A poor faction spends nothing.
 var p = GameState.from_data()
 p.treasury[ME] = 0
 assert_eq(Markets.ai_turn(p,ME),[])

# --- Supply -----------------------------------------------------------------------------------------------

func _enemy_setup() -> Dictionary:
 var s = GameState.from_data()
 _summer(s)
 var enemy = ""
 for f in s.factions():
  if f != ME and not s.settlements_of(f).is_empty():
   enemy = f
   break
 Battles.declare_war(s,ME,enemy)
 var sid = s.settlements_of(enemy)[0]
 var p = WorldMap.settlement_position(sid)+Vector2(30,30)
 if WorldMap.region_at(p) != sid: p = WorldMap.settlement_position(sid)
 s.army_state[ARMY].position = [p.x,p.y]
 s.army_state[ARMY].erase("garrison")
 return {"s":s,"enemy":enemy,"sid":sid}

func test_supply_drains_in_enemy_land_faster_in_winter_and_empties_into_attrition():
 var d = _enemy_setup()
 var s = d.s
 var c = Resources.data().supply
 assert_eq(Supply.land_of(s,ARMY).kind,"enemy")
 assert_eq(Supply.supply(s,ARMY),float(c.max),"armies start full")
 Supply.end_turn(s)
 assert_almost_eq(Supply.supply(s,ARMY),float(c.max)-float(c.enemy),0.01)
 _winter(s)
 var before = Supply.supply(s,ARMY)
 Supply.end_turn(s)
 assert_almost_eq(Supply.supply(s,ARMY),before-float(c.enemy)*float(Seasons.data().effects.winter_supply),0.01,"faster in winter")
 Supply.set_supply(s,ARMY,0.0)
 var men = 0
 for u in s.army_state[ARMY].units: men += int(u.men)
 var ev = Supply.end_turn(s)
 var after = 0
 for u in s.army_state[ARMY].units: after += int(u.men)
 assert_lt(after,men,"empty supply: attrition")
 assert_true(ev.any(func(e): return e.kind == "starving" and e.army == ARMY))

func test_raiding_forages_and_plunders_the_owner():
 var d = _enemy_setup()
 var s = d.s
 var c = Resources.data().supply
 Supply.set_supply(s,ARMY,50.0)
 Supply.set_raid(s,ARMY,true)
 s.treasury[d.enemy] = 10000
 var gold = int(s.treasury[ME])
 var ev = Supply.end_turn(s)
 assert_almost_eq(Supply.supply(s,ARMY),50.0+float(c.forage),0.01)
 var g = int(c.raid_gold)*s.army_state[ARMY].units.size()
 assert_eq(int(s.treasury[ME]),gold+g)
 assert_eq(int(s.treasury[d.enemy]),10000-g)
 assert_true(ev.any(func(e): return e.kind == "plunder"))
 assert_almost_eq(Supply.move_factor(s,ARMY),float(c.raid_move),0.001,"raiders crawl")

func test_friendly_land_refills_from_the_food_stockpile_and_captures_fill():
 var s = GameState.from_data()
 _summer(s)
 var p = WorldMap.settlement_position(GS)
 s.army_state[ARMY].position = [p.x,p.y]
 assert_eq(Supply.land_of(s,ARMY).kind,"friendly")
 Supply.set_supply(s,ARMY,20.0)
 var o = Supply.outlook(s,ARMY)
 assert_gt(int(o.food),0)
 Resources.stock(s,ME).food = 1000
 Supply.end_turn(s)
 assert_almost_eq(Supply.supply(s,ARMY),20.0+float(Resources.data().supply.refill),0.01)
 assert_eq(Resources.amount(s,ME,"food"),1000-int(o.food))
 # No food: no refill.
 Supply.set_supply(s,ARMY,20.0)
 Resources.stock(s,ME).food = 0
 Supply.end_turn(s)
 assert_almost_eq(Supply.supply(s,ARMY),20.0,0.01)
 Supply.on_capture(s,ARMY)
 assert_eq(Supply.supply(s,ARMY),float(Resources.data().supply.max))

# --- Sieges -----------------------------------------------------------------------------------------------

func test_a_food_stockpile_extends_siege_endurance_up_to_the_cap():
 var s = GameState.from_data()
 Resources.stock(s,ME).food = 0
 var base = Battles.endurance(s,GS)
 var sc = Resources.data().siege
 Resources.stock(s,ME).food = int(sc.per_turn)
 assert_eq(Battles.endurance(s,GS),mini(base+1,int(BattleSim.data().sieges.max_endurance)))
 Resources.stock(s,ME).food = 1000000
 var full = Battles.endurance(s,GS)
 assert_lte(full,int(BattleSim.data().sieges.max_endurance),"capped at about 8")
 assert_lte(full,base+int(sc.extra))

# --- Saves ------------------------------------------------------------------------------------------------

func test_stockpiles_supply_and_seasons_survive_a_save():
 var s = GameState.from_data()
 Resources.stock(s,ME).wood = 1234
 Supply.set_supply(s,ARMY,42.0)
 Supply.set_raid(s,ARMY,true)
 var back = GameState.from_dict(SaveCodec.from_json(SaveCodec.to_json(s.to_dict())))
 assert_eq(Resources.amount(back,ME,"wood"),1234)
 assert_almost_eq(Supply.supply(back,ARMY),42.0,0.001)
 assert_true(Supply.raiding(back,ARMY))
 assert_eq(back.seasons.schedule,s.seasons.schedule)
