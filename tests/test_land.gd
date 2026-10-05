extends GutTest
# Land conversion and climate (core/land.gd; owner decision 2026-10-04, game-design §12.13 C) and
# settlement sprawl (map/sprawl.gd; §12.13 A and B).

const GameState = preload("res://core/game_state.gd")
const Land = preload("res://core/land.gd")
const Economy = preload("res://core/economy.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const Sprawl = preload("res://map/sprawl.gd")
const SaveSystem = preload("res://core/save_system.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")

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
# --- Sprawl ------------------------------------------------------------------------------------

func flat(_p): return "open"

func city(level: int,extra := {}) -> Dictionary:
 var s = {"id":"test_city","type":"city","level":level,"position":Vector2.ZERO,"from":"medieval","to":"medieval","value":1.0,"buildings":[]}
 s.merge(extra,true)
 return s

func count(layout: Array,piece_part := "") -> int:
 return layout.filter(func(p): return piece_part == "" or str(p.piece).contains(piece_part)).size()

func houses(layout: Array) -> Array:
 return layout.filter(func(p): return str(p.piece).ends_with("house_1") or str(p.piece).ends_with("house_2") or str(p.piece).ends_with("house_3") or str(p.piece).ends_with(".tall"))

func extent(layout: Array) -> float:
 var r = 0.0
 for p in houses(layout): r = maxf(r,p.pos.length())
 return r

func test_each_level_grows_the_footprint_and_the_houses():
 var sizes = []
 var n = []
 for l in [1,2,3]:
  var lay = Sprawl.layout(city(l),flat)
  sizes.append(extent(lay))
  n.append(houses(lay).size())
 assert_lt(sizes[0],sizes[2])
 assert_lt(n[0],n[1])
 assert_lt(n[1],n[2])
 assert_gt(sizes[2],40.0,"a level-3 city is about 100 m across")

func test_layout_is_deterministic():
 assert_eq(Sprawl.layout(city(3),flat),Sprawl.layout(city(3),flat))

func test_every_culture_builds_its_own_pieces_in_its_own_layout():
 # Owner decisions 2026-10-04: every culture has its own buildings, and layouts follow culture.
 var seen = {}
 for cu in Sprawl.culture_data().cultures:
  var lay = Sprawl.layout(city(3,{"id":"c_"+cu,"from":cu,"to":cu}),flat)
  var own = lay.filter(func(p): return str(p.piece).begins_with("kit.%s." % cu))
  assert_gt(own.size(),30,cu+" builds with its own kit")
  for p in own: assert_true(AssetManifest.has(p.piece),p.piece+" goes through the asset manifest")
  # A fingerprint of the layout: no two cultures may share it.
  var fp = []
  for p in houses(lay).slice(0,12): fp.append(Vector2i(p.pos.round()))
  assert_false(seen.has(fp),cu+" has its own layout")
  seen[fp] = true

func test_walls_are_not_a_circle_and_the_inside_is_built_up():
 var lay = Sprawl.layout(city(3,{"id":"walled"}),flat)
 var walls = lay.filter(func(p): return str(p.piece).ends_with(".wall") or str(p.piece).ends_with(".tower") or str(p.piece).ends_with(".gate"))
 assert_gt(walls.size(),20)
 var d = walls.map(func(p): return p.pos.length())
 var mean = 0.0
 for x in d: mean += x
 mean /= d.size()
 var v = 0.0
 for x in d: v += (x-mean)*(x-mean)
 assert_gt(sqrt(v/d.size())/mean,0.06,"an irregular outline, not a ring")
 # No empty ground inside: most points well inside the walls are near a building.
 var near = 0
 var total = 0
 for i in 200:
  var a = i*2.399
  var q = Vector2.from_angle(a)*sqrt(float(i)/200.0)*mean*0.75
  total += 1
  for p in lay:
   if not str(p.piece).begins_with("kit.road") and p.pos.distance_to(q)<4.5:
    near += 1
    break
 assert_gt(float(near)/total,0.8,"dense inside the walls")

func test_roman_grid_has_straight_streets_and_a_square_wall():
 var lay = Sprawl.layout(city(3,{"id":"rome","from":"roman","to":"roman"}),flat)
 assert_eq(count(lay,"kit.roman.temple"),1,"the forum temple")
 var walls = lay.filter(func(p): return str(p.piece).begins_with("kit.roman.wall"))
 # Square walls: wall pieces face only two directions (and their opposites).
 var dirs = {}
 for p in walls: dirs[int(round(fposmod(p.rot,PI)/(PI/8.0)))%8] = true
 assert_lte(dirs.size(),2)

func test_mining_town_opens_a_pit_on_flat_land_and_mines_the_hills():
 # Any town can take any path: without hills a mine pit opens beside the town.
 var town = city(2,{"type":"town","buildings":[{"chain":"mine","level":2}]})
 var lay = Sprawl.layout(town,flat)
 assert_gt(count(lay,"kit.pit"),0,"a pit opens")
 assert_eq(count(lay,"path_mining"),1,"the culture's mine")
 var hilly = func(p: Vector2): return "hills" if p.x>30.0 else "open"
 lay = Sprawl.layout(town,hilly)
 for p in lay.filter(func(q): return str(q.piece).ends_with("path_mining")): assert_gt(p.pos.x,25.0,"the mine sits in the hills")
 assert_eq(Sprawl.path_of(city(3,{"buildings":[{"chain":"mine","level":2}]})),"","big cities have no path")

func test_docks_only_on_a_coast():
 var port = city(2,{"buildings":[{"chain":"port","level":1}]})
 assert_eq(count(Sprawl.layout(port,flat),"kit.dock"),0)
 var coast = func(p: Vector2): return "water" if p.y>40.0 else "open"
 assert_gt(count(Sprawl.layout(port,coast),"kit.dock"),0)

func test_farming_towns_have_more_fields_and_lumber_towns_keep_their_forest():
 var plain = Sprawl.layout(city(2,{"type":"town"}),flat)
 var farmed = Sprawl.layout(city(2,{"type":"town","buildings":[{"chain":"farm","level":2}]}),flat)
 assert_gt(count(farmed,"kit.field"),count(plain,"kit.field"))
 assert_gt(count(farmed,"path_farming"),0)
 var wooded = func(p: Vector2): return "forest" if p.length()>25.0 else "open"
 for p in Sprawl.layout(city(2,{"type":"town","path":"lumber"}),wooded):
  if p.piece == "kit.field": assert_lte(p.pos.length(),25.5,"no fields cut into the forest")

func test_conversion_mixes_cultures_and_leaves_ruins():
 var s = city(3,{"from":"greek","to":"orc","value":0.0})
 var at0 = Sprawl.layout(s,flat)
 s.value = 0.5
 var mid = Sprawl.layout(s,flat)
 s.value = 1.0
 var done = Sprawl.layout(s,flat)
 assert_eq(at0.filter(func(p): return str(p.piece).begins_with("kit.orc.")).size(),0,"nothing new yet")
 assert_gt(at0.filter(func(p): return p.ruin).size(),0,"war damage: ruins from the start")
 assert_gt(mid.filter(func(p): return str(p.piece).begins_with("kit.orc.")).size(),0)
 assert_gt(mid.filter(func(p): return str(p.piece).begins_with("kit.greek.")).size(),0)
 assert_eq(done.filter(func(p): return p.ruin or str(p.piece).begins_with("kit.greek.")).size(),0,"fully converted")
 assert_gt(done.filter(func(p): return str(p.piece).begins_with("kit.orc.")).size(),0,"orc camps")
