extends GutTest
# Land conversion and climate (core/land.gd; owner decision 2026-10-04, game-design §12.13 C) and
# settlement sprawl (map/sprawl.gd; §12.13 A and B).

const GameState = preload("res://core/game_state.gd")
const Land = preload("res://core/land.gd")
const Economy = preload("res://core/economy.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const Sprawl = preload("res://map/sprawl.gd")
const SaveSystem = preload("res://core/save_system.gd")

func roman_takes_goldspire():
 var s = GameState.from_data()
 s.settlements.goldspire_rock.owner = "house_verrin" # Roman takes a Greek city
 return s

func turns(s,n: int):
 for i in n: TurnLoop.end_turn(s,{"ai":false})

func test_land_starts_as_each_owners_culture():
 var s = GameState.from_data()
 for sid in s.settlements:
  assert_eq(Land.entry(s,sid).to,Land.faction_culture(s.settlements[sid].owner))
  assert_eq(Land.stage(s,sid),3)
  assert_eq(Land.climate_factor(s,sid),1.0)

func test_conversion_stages_after_3_6_and_9_turns():
 var s = roman_takes_goldspire()
 var stages = []
 for t in 10:
  stages.append(Land.stage(s,"goldspire_rock"))
  turns(s,1)
 # Turn counts start at the first End Turn after the capture.
 assert_eq(stages.slice(1,10),[0,0,1,1,1,2,2,2,3])
 assert_eq(Land.entry(s,"goldspire_rock").to,"roman")
 assert_eq(Land.entry(s,"goldspire_rock").from,"roman","converted")

func test_climate_penalty_fades_with_the_conversion():
 var s = roman_takes_goldspire()
 turns(s,1)
 var f1 = Land.climate_factor(s,"goldspire_rock")
 assert_almost_eq(f1,lerpf(float(Land.data().climate.foreign_yield),1.0,1.0/9.0),0.001)
 turns(s,8)
 assert_eq(Land.climate_factor(s,"goldspire_rock"),1.0)
 var inc = Economy.settlement_income(s,"goldspire_rock")
 assert_eq(inc.climate,1.0)

func test_retaking_converts_it_back_and_is_foreign_for_the_original_owner():
 var s = roman_takes_goldspire()
 turns(s,9) # fully Roman now
 s.settlements.goldspire_rock.owner = "house_aurek" # the Greeks retake it
 turns(s,1)
 var e = Land.entry(s,"goldspire_rock")
 assert_eq([e.from,e.to],["roman","greek"])
 assert_lt(Land.climate_factor(s,"goldspire_rock"),1.0,"foreign climate for the original culture")

func test_retaking_half_way_resumes_from_there():
 var s = roman_takes_goldspire()
 turns(s,3)
 var v = float(Land.entry(s,"goldspire_rock").value)
 s.settlements.goldspire_rock.owner = "house_aurek"
 Land.retarget(s,"goldspire_rock")
 assert_almost_eq(float(Land.entry(s,"goldspire_rock").value),1.0-v,0.0001)

func test_same_culture_capture_does_not_convert():
 var s = GameState.from_data()
 s.settlements.greyhaven.owner = "house_aurek" # Greek takes Greek
 turns(s,1)
 assert_eq(Land.stage(s,"greyhaven"),3)
 assert_eq(Land.climate_factor(s,"greyhaven"),1.0)

func test_owner_buildings_speed_it_up():
 var a = roman_takes_goldspire()
 var b = roman_takes_goldspire()
 turns(a,1)
 Land.end_turn(b,[{"settlement":"goldspire_rock","faction":"house_verrin"},{"settlement":"goldspire_rock","faction":"house_verrin"}])
 assert_gt(float(b.land.goldspire_rock.value),float(a.land.goldspire_rock.value))

func test_land_is_saved():
 SaveSystem.dir = "user://test_saves_land"
 var s = roman_takes_goldspire()
 turns(s,2)
 assert_true(SaveSystem.save(s,"land","Land").ok)
 var ld = SaveSystem.load_save("land")
 assert_true(ld.ok)
 assert_eq(ld.state.land,s.land)
 SaveSystem.delete("land")
 SaveSystem.dir = SaveSystem.DIR

# --- Sprawl ------------------------------------------------------------------------------------

func flat(_p): return "open"

func city(level: int,extra := {}) -> Dictionary:
 var s = {"id":"test_city","type":"city","level":level,"position":Vector2.ZERO,"from":"medieval","to":"medieval","value":1.0,"buildings":[]}
 s.merge(extra,true)
 return s

func count(layout: Array,piece_prefix := "") -> int:
 return layout.filter(func(p): return piece_prefix == "" or str(p.piece).begins_with(piece_prefix)).size()

func extent(layout: Array) -> float:
 var r = 0.0
 for p in layout: r = maxf(r,p.pos.length())
 return r

func test_each_level_grows_the_footprint_and_the_houses():
 var sizes = []
 var houses = []
 for l in [1,2,3]:
  var lay = Sprawl.layout(city(l),flat)
  sizes.append(extent(lay))
  houses.append(lay.filter(func(p): return p.piece in ["kit.house_a","kit.house_b","kit.house_tall"]).size())
 assert_lt(sizes[0],sizes[1])
 assert_lt(sizes[1],sizes[2])
 assert_lt(houses[0],houses[1])
 assert_lt(houses[1],houses[2])
 assert_gt(sizes[2],45.0,"a level-3 city reaches about 50 m: about 100 m across")

func test_layout_is_deterministic():
 assert_eq(Sprawl.layout(city(3),flat),Sprawl.layout(city(3),flat))

func test_mines_only_in_hills_and_docks_only_on_a_coast():
 var mine_town = city(2,{"buildings":[{"chain":"mine","level":2}]})
 assert_eq(count(Sprawl.layout(mine_town,flat),"kit.mine"),0,"no hills: no mine")
 var hilly = func(p: Vector2): return "hills" if p.x>30.0 else "open"
 var lay = Sprawl.layout(mine_town,hilly)
 assert_gt(count(lay,"kit.mine"),0)
 for p in lay.filter(func(q): return q.piece == "kit.mine"): assert_gt(p.pos.x,25.0,"the mine sits in the hills")
 var port = city(2,{"buildings":[{"chain":"port","level":1}]})
 assert_eq(count(Sprawl.layout(port,flat),"kit.dock"),0)
 var coast = func(p: Vector2): return "water" if p.y>40.0 else "open"
 assert_gt(count(Sprawl.layout(port,coast),"kit.dock"),0)

func test_farms_add_fields_on_open_ground_only():
 var plain = Sprawl.layout(city(2),flat)
 var farmed = Sprawl.layout(city(2,{"buildings":[{"chain":"farm","level":2}]}),flat)
 assert_gt(count(farmed,"kit.field"),count(plain,"kit.field"))
 var wooded = func(p: Vector2): return "forest" if p.length()>25.0 else "open"
 for p in Sprawl.layout(city(2,{"buildings":[{"chain":"farm","level":2}]}),wooded):
  if p.piece == "kit.field": assert_lte(p.pos.length(),25.5)

func test_conversion_mixes_cultures_and_leaves_ruins():
 var s = city(3,{"from":"greek","to":"orc","value":0.0})
 var at0 = Sprawl.layout(s,flat)
 s.value = 0.5
 var mid = Sprawl.layout(s,flat)
 s.value = 1.0
 var done = Sprawl.layout(s,flat)
 assert_eq(at0.filter(func(p): return p.culture == "orc" and not p.piece in ["kit.road","kit.field"]).size(),0,"nothing new yet")
 assert_gt(at0.filter(func(p): return p.ruin).size(),0,"war damage: ruins from the start")
 assert_gt(mid.filter(func(p): return p.culture == "orc").size(),0)
 assert_gt(mid.filter(func(p): return p.culture == "greek").size(),0)
 assert_eq(done.filter(func(p): return p.ruin or p.culture == "greek").size(),0,"fully converted")
 assert_gt(done.filter(func(p): return p.piece == "kit.hut").size(),0,"orc huts")
