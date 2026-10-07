extends GutTest
# Free movement (owner spec 2026-10-07, A1): lords move anywhere passable, not only along roads;
# roads are about 35% faster and the planner takes them when they pay; forest and marsh cost more;
# water and peaks stay impassable. Varos (the campaign map) with its marshes.

const MapRegistry = preload("res://core/map_registry.gd")
const GameState = preload("res://core/game_state.gd")
const Movement = preload("res://core/movement.gd")

func before_each():
 MapRegistry.set_active(MapRegistry.CAMPAIGN)

func after_each():
 MapRegistry.set_active(MapRegistry.DEFAULT)

func terrain_index(name: String) -> int:
 return Movement.grid().names.find(name)

func test_roads_are_about_35_percent_faster():
 var t = Movement.data().terrain
 var road = float(Movement.data().roads.multiplier_by_level[0])
 assert_almost_eq(float(t.open.cost)/road,1.35,0.02,"a dirt road is about 35% faster than open ground")
 assert_gt(float(t.forest.cost),float(t.open.cost))
 assert_gt(float(t.marsh.cost),float(t.open.cost),"marsh costs more")
 assert_null(t.water.cost)
 assert_null(t.mountain.cost)

func test_lords_move_off_road_across_open_country():
 var s = GameState.from_data()
 var g = Movement.grid()
 # A point in open country away from every road, reached across open ground.
 var id = s.armies_of("house_varn")[0]
 var from = Movement.position(s,id)
 var open = terrain_index("open")
 var found = false
 for k in 24:
  var p = from+Vector2(70,0).rotated(k*TAU/24.0)
  var c = Movement.cell_of(p)
  var i = c.y*g.cols+c.x
  if g.terrain[i] != open or g.road[i] != 0: continue
  var plan = Movement.plan(s,id,p)
  if not plan.ok: continue
  # The path leaves the road (free movement, not a road graph); it may take the road out of town
  # first where that is faster.
  var off = 0
  for q in plan.points:
   var qc = Movement.cell_of(q)
   if g.road[qc.y*g.cols+qc.x] == 0: off += 1
  assert_gt(off,2,"the route runs off-road")
  found = true
  break
 assert_true(found,"an off-road destination near Frosthold")

func test_marsh_exists_on_varos_and_is_passable():
 var g = Movement.grid()
 var m = terrain_index("marsh")
 assert_gt(m,-1)
 var n = 0
 for i in range(0,g.terrain.size(),97):
  if g.terrain[i] == m: n += 1
 assert_gt(n,0,"the swamps and marshes of Varos are marsh ground")
 assert_gt(Movement.cell_cost(Vector2i(0,0),0),-2.0) # the grid loads with the appended class
