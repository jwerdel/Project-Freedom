extends GutTest
# The scale fixes (VALIDATION.md, map pipeline): the incremental blocking index, the pathfinding
# grid built from row runs, hierarchical paths (HPA*), instant "no route" across components, the
# per-turn odds budget, End Turn spread over frames with identical results, and background saves.

const MapRegistry = preload("res://core/map_registry.gd")
const Synthetic = preload("res://map/synthetic.gd")
const GameState = preload("res://core/game_state.gd")
const WorldMap = preload("res://core/world_map.gd")
const Movement = preload("res://core/movement.gd")
const PathHierarchy = preload("res://core/path_hierarchy.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const Ai = preload("res://core/ai.gd")
const SaveSystem = preload("res://core/save_system.gd")
const MAP = "synthetic_tiny"
const TEST_DIR = "user://test_saves_scale"

func before_all():
 Synthetic.build(MAP)

func after_each():
 MapRegistry.set_active(MapRegistry.DEFAULT)
 SaveSystem.dir = SaveSystem.DIR

# Brute force, as the old code did: cells within radius of every foreign settlement and army.
func reference_blocked(s,faction: String) -> Dictionary:
 var out = {}
 var g = Movement.grid()
 var areas = []
 for sid in WorldMap.settlement_ids():
  if s.settlements[sid].owner != faction: areas.append([WorldMap.settlement_position(sid),float(Movement.data().settlements.radius)])
 for id in s.army_state:
  if s.army_state[id].faction != faction: areas.append([Movement.position(s,id),float(Movement.data().armies.block_radius)])
 for a in areas:
  for c in Movement._area_cells(a[0],a[1]): out[c] = true
 return out

func blocked_now(s,faction: String) -> Dictionary:
 Movement._blk_faction = faction
 Movement._blk_key = []
 Movement._sync_blocks(s)
 var out = {}
 for c in Movement._blk.total:
  if Movement.blocked_for(c,faction): out[c] = true
 return out

func test_blocking_index_matches_brute_force_after_moves_and_captures():
 for map_id in [MapRegistry.DEFAULT,MAP]:
  MapRegistry.set_active(map_id)
  var s = GameState.from_data()
  var factions = s.factions()
  for f in factions: assert_eq(blocked_now(s,f),reference_blocked(s,f),"%s %s at start" % [map_id,f])
  # Move armies, change a settlement's owner: the index follows incrementally.
  var rng = RandomNumberGenerator.new()
  rng.seed = 5
  for id in s.army_state:
   var p = Movement.position(s,id)+Vector2(rng.randf_range(-20,20),rng.randf_range(-20,20))
   s.army_state[id].position = [p.x,p.y]
  var sid = WorldMap.settlement_ids()[0]
  s.settlements[sid].owner = factions[-1]
  for f in factions: assert_eq(blocked_now(s,f),reference_blocked(s,f),"%s %s after changes" % [map_id,f])

func test_grid_from_runs_matches_per_cell_costs():
 MapRegistry.set_active(MAP)
 var a = Movement._astar_for(1)
 var g = Movement.grid()
 var lo = Movement._min_cost()
 for i in range(0,g.cols*g.rows,97):
  var c = Vector2i(i%g.cols,i/g.cols)
  var cost = Movement.cell_cost(c,1)
  if cost<0: assert_true(a.is_point_solid(c),"impassable %s" % c)
  else: assert_almost_eq(a.get_point_weight_scale(c),cost/lo,0.0001)

func path_cost(cells: Array) -> float:
 var t = 0.0
 for k in range(1,cells.size()):
  t += Movement.center_of(cells[k-1]).distance_to(Movement.center_of(cells[k]))*Movement.cell_cost(cells[k],1)
 return t

func test_hierarchical_paths_are_valid_and_close_to_optimal():
 MapRegistry.set_active(MAP)
 var s = GameState.from_data()
 s.road_level = 1
 var a = Movement._astar_for(1)
 var h = PathHierarchy.load_for(Movement)
 assert_false(h.is_empty(),"the tiny map has a hierarchy")
 var ids = WorldMap.settlement_ids()
 var tested = 0
 for i in ids.size():
  for j in range(i+1,ids.size(),5):
   var from = Movement.cell_of(WorldMap.settlement_position(ids[i])+Vector2(6,0))
   var to = Movement.cell_of(WorldMap.settlement_position(ids[j])+Vector2(6,0))
   if a.is_point_solid(from) or a.is_point_solid(to): continue
   var cells = PathHierarchy.route(Movement,h,a,from,to,"")
   if cells.is_empty(): continue
   tested += 1
   assert_eq(cells[0],from)
   assert_eq(cells[-1],to)
   for k in range(1,cells.size()):
    assert_lte(maxi(absi(cells[k].x-cells[k-1].x),absi(cells[k].y-cells[k-1].y)),1,"contiguous")
    assert_false(a.is_point_solid(cells[k]),"walkable")
   var direct = Array(a.get_id_path(from,to))
   assert_lte(path_cost(cells),path_cost(direct)*1.6+20.0,"near the optimal cost")
 assert_gt(tested,5)

func test_no_route_across_components_is_instant():
 MapRegistry.set_active(MAP)
 var s = GameState.from_data()
 var id = s.army_state.keys()[0]
 # A point on another continent (or the sea): no land route.
 var p = Movement.position(s,id)
 var g = Movement.grid()
 var far = Vector2.ZERO
 Movement._same_component(Vector2i.ZERO,Vector2i.ZERO)
 var mine = Movement._comp[Movement.cell_of(p).y*g.cols+Movement.cell_of(p).x]
 for i in range(0,g.cols*g.rows,13):
  var c = Movement._comp[i]
  if c != 0 and c != mine and Movement.cell_cost(Vector2i(i%g.cols,i/g.cols),s.road_level)>=0:
   far = Movement.center_of(Vector2i(i%g.cols,i/g.cols))
   break
 if far == Vector2.ZERO:
  pass_test("one land mass on this seed")
  return
 var t = Time.get_ticks_usec()
 var r = Movement.plan(s,id,far)
 assert_false(r.ok)
 assert_lt((Time.get_ticks_usec()-t)/1000.0,20.0)

func test_odds_budget_caps_simulations_per_turn():
 MapRegistry.set_active(MAP)
 var s = GameState.from_data()
 Ai._begin_phase(s)
 assert_eq(Ai._odds_turn_spent,0)
 assert_eq(Ai._odds_groups,1,"few factions: every faction may simulate")

func test_sliced_end_turn_gives_identical_results():
 for map_id in [MapRegistry.DEFAULT,MAP]:
  MapRegistry.set_active(map_id)
  var a = GameState.from_data()
  var b = GameState.from_data()
  a.player_faction = ""
  b.player_faction = ""
  for k in 2:
   TurnLoop.end_turn(a)
   var r = await TurnLoop.end_turn_sliced(b,get_tree(),0.001) # a tiny budget: a new frame at every chance
   assert_true(r.has("ai"))
  assert_eq(b.state_hash(),a.state_hash(),"%s: same state either way" % map_id)

func test_sliced_end_turn_hands_frames_back():
 MapRegistry.set_active(MAP)
 var s = GameState.from_data()
 s.player_faction = ""
 var frames = [Engine.get_process_frames()]
 await TurnLoop.end_turn_sliced(s,get_tree(),0.001)
 assert_gt(Engine.get_process_frames()-frames[0],1,"the turn spanned several frames")

func test_background_save_returns_at_once_and_lands_intact():
 SaveSystem.dir = TEST_DIR
 var s = GameState.from_data()
 var r = SaveSystem.save(s,"bg","Background","manual",null,false,{},true)
 assert_true(r.ok)
 assert_true(r.background)
 var w = SaveSystem.wait_for_saves()
 assert_true(w.ok)
 assert_gt(int(w.bytes),0)
 var meta = SaveSystem.read_meta("bg")
 assert_eq(meta.name,"Background","the meta sidecar is read")
 var ld = SaveSystem.load_save("bg")
 assert_true(ld.ok)
 assert_eq(ld.state.state_hash(),s.state_hash())
 assert_true(SaveSystem.delete("bg"))
 assert_false(FileAccess.file_exists(SaveSystem.meta_of("bg")),"the sidecar goes with the save")

func test_ai_window_search_matches_the_full_search_and_fails_cheaply():
 # The AI's direct searches (Movement.ai_cap) run on a window around start and goal: a nearby
 # path costs what the full search finds, foreign armies still block, and an unreachable goal
 # fails fast instead of exploring the whole map.
 MapRegistry.set_active(MAP)
 var s = GameState.from_data()
 s.road_level = 1
 var f = s.army_state[s.army_state.keys()[0]].faction
 Movement._blk_faction = f
 Movement._blk_key = []
 Movement._sync_blocks(s)
 var a = Movement._astar_for(1)
 Movement._apply_blocks(s,a,f)
 var rng = RandomNumberGenerator.new()
 rng.seed = 11
 var g = Movement.grid()
 var tested = 0
 for i in 60:
  var from = Vector2i(rng.randi_range(10,g.cols-11),rng.randi_range(10,g.rows-11))
  var to = from+Vector2i(rng.randi_range(-15,15),rng.randi_range(-15,15))
  if to.x<0 or to.y<0 or to.x>=g.cols or to.y>=g.rows or a.is_point_solid(from) or a.is_point_solid(to): continue
  var full = Array(a.get_id_path(from,to))
  var win = Movement._window_path(s,f,from,to)
  if full.is_empty(): continue
  tested += 1
  assert_false(win.is_empty(),"a short route is found in the window")
  for c in win: assert_false(a.is_point_solid(c),"walkable and not blocked")
  assert_almost_eq(path_cost(win),path_cost(full),0.01,"same cost as the full search")
 assert_gt(tested,10)
 # A goal ringed by a foreign army's blocking: no route, and quickly.
 var goal = Vector2i(g.cols/2,g.rows/2)
 while a.is_point_solid(goal) or a.is_point_solid(goal+Vector2i(40,0)): goal.x = (goal.x+7)%(g.cols-50)
 var ring = {}
 for c in Movement._area_cells(Movement.center_of(goal),12.0): ring[c] = true
 for c in Movement._area_cells(Movement.center_of(goal),6.0): ring.erase(c)
 var foe = "ringer"
 for c in ring:
  var key = "a:ring%d" % c
  Movement._blk_add(key,foe,Movement.center_of(Vector2i(c%g.cols,c/g.cols)),0.1,1)
 var t0 = Time.get_ticks_usec()
 assert_eq(Movement._window_path(s,f,goal+Vector2i(40,0),goal),[],"ringed goal unreachable")
 assert_lt((Time.get_ticks_usec()-t0)/1000.0,50.0)
 Movement.reset()
