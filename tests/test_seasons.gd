extends GutTest
# Seasons (owner spec 2026-10-07, Part B; war-and-realm §9; data/seasons.json): generation per seed,
# forecasts, food by latitude and the dry season, winter movement and the map's snow.

const GameState = preload("res://core/game_state.gd")
const Seasons = preload("res://core/seasons.gd")
const Movement = preload("res://core/movement.gd")
const MapRegistry = preload("res://core/map_registry.gd")
const WorldMap = preload("res://core/world_map.gd")
const ARMY = "aurek_host"

func test_generation_alternates_within_the_ranges_and_follows_the_seed():
 var d = Seasons.data()
 var a = Seasons.generate(7)
 assert_eq(a,Seasons.generate(7),"same seed, same seasons")
 assert_ne(a.schedule,Seasons.generate(8).schedule,"another seed, other seasons")
 var t = 0
 for i in a.schedule.size():
  var e = a.schedule[i]
  assert_eq(e.kind,"summer" if i%2 == 0 else "winter","summer first, then alternating")
  assert_eq(int(e.start),t,"no gaps")
  t += int(e.length)
  if e.kind == "summer": assert_between(int(e.length),int(d.summer[0]),int(d.summer[1]))
  else:
   assert_true(int(e.length) == int(d.long_winter) or (int(e.length)>=int(d.winter[0]) and int(e.length)<=int(d.winter[1])))
   assert_between(int(e.forecast),int(d.forecast[0]),int(d.forecast[1]))
 assert_gte(t,int(d.schedule_turns))

func test_long_winters_are_rare():
 var long = 0
 var all = 0
 for seed in 40:
  for e in Seasons.generate(seed).schedule:
   if e.kind != "winter": continue
   all += 1
   if int(e.length)>=int(Seasons.data().long_winter): long += 1
 assert_gt(long,0,"they happen")
 assert_lt(float(long)/float(all),0.3,"but rarely")

func test_the_forecast_comes_before_the_winter_once_and_the_seasons_announce_themselves():
 var s = GameState.from_data()
 s.seasons = {"schedule":[{"kind":"summer","start":0,"length":6},{"kind":"winter","start":6,"length":3,"forecast":3},{"kind":"summer","start":9,"length":5}],"announced":[]}
 s.turn = 2
 assert_eq(Seasons.end_turn(s),[])
 s.turn = 3
 var ev = Seasons.end_turn(s)
 assert_eq(ev.size(),1)
 assert_eq(ev[0].kind,"forecast")
 assert_eq(int(ev[0].turns),3)
 assert_true(ev[0].long,"three turns of snow: a long winter")
 assert_eq(Seasons.end_turn(s),[],"announced once")
 s.turn = 6
 ev = Seasons.end_turn(s)
 assert_true(ev.any(func(e): return e.kind == "winter"))
 assert_true(Seasons.is_winter(s))
 assert_eq(int(Seasons.at(s).turns_left),2)
 s.turn = 9
 assert_true(Seasons.end_turn(s).any(func(e): return e.kind == "summer"))
 assert_false(Seasons.is_winter(s))

func test_winter_food_falls_more_in_the_north_and_summer_has_a_bonus():
 var s = GameState.from_data()
 var e = Seasons.data().effects
 var north = ""
 var south = ""
 var ny = INF
 var sy = -INF
 for sid in s.settlements:
  if Seasons.dry_land(sid): continue
  var y = WorldMap.settlement_position(sid).y
  if y<ny: ny = y; north = sid
  if y>sy: sy = y; south = sid
 s.seasons = {"schedule":[{"kind":"summer","start":0,"length":1000}],"announced":[]}
 assert_almost_eq(Seasons.food_factor(s,north),float(e.summer_food),0.001)
 s.seasons = {"schedule":[{"kind":"winter","start":0,"length":1000,"forecast":2}],"announced":[]}
 assert_lt(Seasons.food_factor(s,north),Seasons.food_factor(s,south),"the north loses more")
 assert_lt(Seasons.food_factor(s,south),1.0)
 assert_gte(Seasons.food_factor(s,north),float(e.north_food))

func test_desert_and_jungle_get_a_dry_season_instead_of_snow():
 MapRegistry.set_active(MapRegistry.CAMPAIGN)
 var s = GameState.from_data()
 s.seasons = {"schedule":[{"kind":"winter","start":0,"length":1000,"forecast":2}],"announced":[]}
 var dry = ""
 for sid in s.settlements:
  if Seasons.dry_land(sid): dry = sid; break
 assert_ne(dry,"","Varos has desert or jungle regions")
 if dry != "": assert_almost_eq(Seasons.food_factor(s,dry),float(Seasons.data().effects.dry_food),0.001)
 MapRegistry.set_active(MapRegistry.DEFAULT)

func test_winter_slows_movement_in_the_north_only():
 var s = GameState.from_data()
 var e = Seasons.data().effects
 var size = MapRegistry.meta().get("size",[1000,1000])
 var origin = MapRegistry.meta().get("origin",[0,0])
 var far_north = Vector2(float(origin[0])+float(size[0])*0.5,float(origin[1])+10.0)
 s.seasons = {"schedule":[{"kind":"summer","start":0,"length":1000}],"announced":[]}
 assert_eq(Seasons.move_factor(s,far_north),1.0)
 s.seasons = {"schedule":[{"kind":"winter","start":0,"length":1000,"forecast":2}],"announced":[]}
 assert_almost_eq(Seasons.move_factor(s,far_north),float(e.winter_move),0.001)
 # Somewhere in the south on low ground stays open.
 var open = false
 for sid in s.settlements:
  if Seasons.move_factor(s,WorldMap.settlement_position(sid)) == 1.0: open = true
 assert_true(open,"southern lowlands are not snowed in")
 # The army's allowance refills smaller at End Turn.
 var p = far_north
 s.army_state[ARMY].position = [p.x,p.y]
 Movement.end_turn(s)
 assert_lt(float(s.army_state[ARMY].points),float(s.army_state[ARMY].max_points))

func test_the_map_whitens_over_the_winter():
 var s = GameState.from_data()
 s.seasons = {"schedule":[{"kind":"summer","start":0,"length":4},{"kind":"winter","start":4,"length":3,"forecast":2}],"announced":[]}
 s.turn = 2
 assert_eq(Seasons.snow_amount(s),0.0)
 s.turn = 4
 var first = Seasons.snow_amount(s)
 assert_gt(first,0.0)
 s.turn = 5
 assert_gt(Seasons.snow_amount(s),first,"deeper each winter turn")
 assert_lte(Seasons.snow_amount(s),1.0)

func test_a_new_campaign_starts_in_summer_with_a_winter_ahead():
 var s = GameState.from_data()
 assert_false(Seasons.is_winter(s))
 assert_false(Seasons.next_winter(s).is_empty())
