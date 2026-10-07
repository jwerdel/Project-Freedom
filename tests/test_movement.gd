extends GutTest
# Army movement (data/movement.json, the map's movement grid): points are spent by distance and
# terrain, roads are cheaper the higher the road level, water and mountains are impassable except at
# passes, orders beyond this turn continue on End Turn, points refill, armies garrison in their own
# settlements, and foreign settlements or armies are not move targets (they start the battle flow).

const GameState = preload("res://core/game_state.gd")
const Movement = preload("res://core/movement.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const UiData = preload("res://core/ui_data.gd")
const WorldMap = preload("res://core/world_map.gd")
const ARMY = "aurek_host"

func after_each():
 Movement.reset()

# First cell of the given terrain whose four neighbours share it (and are not roads).
func find_cell(terrain: String,road := false) -> Vector2i:
 var g = Movement.grid()
 for z in range(2,g.rows-2):
  for x in range(2,g.cols-2):
   var c = Vector2i(x,z)
   if Movement.terrain_of(c) != terrain or Movement.is_road(c) != road: continue
   var ok = true
   for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
    if Movement.terrain_of(c+d) != terrain or Movement.is_road(c+d) != road: ok = false
   if ok: return c
 return Vector2i(-1,-1)

func place(s,cell: Vector2i,id := ARMY):
 var p = Movement.center_of(cell)
 s.army_state[id].position = [p.x,p.y]
 s.army_state[id].garrison = ""

func test_grid_matches_data_and_map():
 var g = Movement.grid()
 assert_eq(g.cols*g.rows,g.terrain.size())
 for t in ["open","forest","hills","pass","mountain","water","settlement"]: assert_true(find_cell(t).x>=0 or t in ["pass","settlement"],t+" present")
 # Every settlement stands on passable settlement cells; the sea is water.
 for id in WorldMap.settlement_ids(): assert_eq(Movement.terrain_at(WorldMap.settlement_position(id)),"settlement",id)
 assert_eq(Movement.terrain_at(Vector2(0,150)),"water")

func test_points_spent_by_distance_and_terrain():
 var cost = Movement.data().terrain
 for t in ["open","forest","hills"]:
  var c = find_cell(t)
  assert_true(c.x>=0,"found "+t)
  var s = GameState.from_data()
  place(s,c)
  var target = Movement.center_of(c+Vector2i(1,0))
  var r = Movement.order(s,ARMY,target)
  assert_true(r.ok,t)
  var spent = Movement.max_points()-s.army_state[ARMY].points
  assert_almost_eq(spent,Movement.grid().cell*float(cost[t].cost),0.001,t)
  # Diagonal steps cost their real length.
  var s2 = GameState.from_data()
  place(s2,c)
  if Movement.terrain_of(c+Vector2i(1,1)) == t and not Movement.is_road(c+Vector2i(1,1)):
   Movement.order(s2,ARMY,Movement.center_of(c+Vector2i(1,1)))
   assert_almost_eq(Movement.max_points()-s2.army_state[ARMY].points,Movement.grid().cell*sqrt(2.0)*float(cost[t].cost),0.001,t+" diagonal")
 assert_gt(float(cost.forest.cost),float(cost.open.cost))
 assert_gt(float(cost.hills.cost),float(cost.open.cost))

func test_roads_are_faster_and_scale_with_road_level():
 var m = Movement.data().roads.multiplier_by_level
 assert_gt(m[0],m[1])
 assert_gt(m[1],m[2])
 assert_lt(m[0],Movement.data().terrain.open.cost)
 var c = Vector2i(-1,-1)
 var g = Movement.grid()
 for i in g.cols*g.rows:
  var cc = Vector2i(i%g.cols,i/g.cols)
  if Movement.is_road(cc) and Movement.terrain_of(cc) == "open":
   c = cc
   break
 assert_true(c.x>=0,"a road cell over open ground")
 for level in 3: assert_almost_eq(Movement.cell_cost(c,level),float(m[level]),0.0001)
 # Greyhaven gate to Crownwatch along the road: cheaper at every road level.
 var costs = []
 for level in 3:
  var s = GameState.from_data()
  s.road_level = level
  s.settlements.greyhaven.owner = "house_aurek" # so the route may start at its gate
  var start = Vector2(-40,12.5)
  s.army_state[ARMY].position = [start.x,start.y]
  var p = Movement.plan(s,ARMY,WorldMap.settlement_position("crownwatch"))
  assert_true(p.ok)
  costs.append(p.cost)
 assert_gt(costs[0],costs[1])
 assert_gt(costs[1],costs[2])

func test_water_and_mountains_are_impassable_except_at_passes():
 var s = GameState.from_data()
 var water = Movement.plan(s,ARMY,Vector2(0,150))
 assert_false(water.ok)
 assert_eq(water.reason,Movement.IMPASSABLE)
 var peak = Movement.center_of(find_cell("mountain"))
 assert_eq(Movement.plan(s,ARMY,peak).reason,Movement.IMPASSABLE)
 # Crossing the Greyspine to the far side must use the pass.
 var north = Vector2(-250,-332)
 assert_eq(Movement.terrain_at(north),"open")
 var p = Movement.plan(s,ARMY,north)
 assert_true(p.ok,"reachable through the pass")
 var used = false
 for q in p.points:
  var t = Movement.terrain_at(q)
  assert_ne(t,"mountain")
  assert_ne(t,"water")
  used = used or t == "pass"
 assert_true(used,"the route crosses the pass")

func test_long_orders_continue_on_end_turn_and_points_refill():
 # Settings "Continue multi-turn orders automatically" on (off by default: tests/test_order_hold.gd).
 Movement.continue_player_orders = true
 var s = GameState.from_data()
 var target = Vector2(-250,-332)
 var r = Movement.order(s,ARMY,target)
 assert_true(r.ok)
 assert_gt(r.total_turns,1)
 var a = s.army_state[ARMY]
 assert_false(a.order.is_empty(),"remaining path kept as an order")
 assert_lt(a.points,Movement.max_points()-1.0)
 assert_eq(r.moved.size()-1,r.reach,"moved exactly this turn's portion")
 var turns = 0
 while not a.order.is_empty() and turns<20:
  var before = Movement.position(s,ARMY)
  var report = TurnLoop.end_turn(s)
  turns += 1
  assert_true(report.moves.has(ARMY))
  assert_ne(Movement.position(s,ARMY),before,"moved on End Turn")
 assert_true(a.order.is_empty())
 assert_eq(turns,r.total_turns-1,"arrives on the planned turn")
 assert_almost_eq(Movement.position(s,ARMY).distance_to(target),0.0,0.01)
 # Without an order, End Turn just refills the allowance.
 TurnLoop.end_turn(s)
 assert_eq(a.points,Movement.max_points())
 Movement.continue_player_orders = false

func test_cancel_keeps_position_and_drops_the_order():
 var s = GameState.from_data()
 Movement.order(s,ARMY,Vector2(-250,-332))
 var at = Movement.position(s,ARMY)
 Movement.cancel_order(s,ARMY)
 assert_true(s.army_state[ARMY].order.is_empty())
 TurnLoop.end_turn(s)
 assert_eq(Movement.position(s,ARMY),at)

func test_moving_into_an_own_settlement_garrisons_the_army():
 var data = UiData.new()
 var s = data.state
 var r = data.order_move(ARMY,WorldMap.settlement_position("crownwatch")+Vector2(1,1))
 assert_true(r.ok)
 for i in 10:
  if s.army_state[ARMY].order.is_empty(): break
  data.end_turn()
 assert_eq(s.army_state[ARMY].garrison,"crownwatch")
 assert_eq(Movement.garrison_of(s,"crownwatch"),[ARMY])
 assert_has(data.settlement("crownwatch").garrison,"The Host of Goldspire")
 assert_eq(data.army_movement(ARMY).garrison_name,"Crownwatch")
 # Marching out leaves the garrison.
 data.end_turn()
 data.order_move(ARMY,WorldMap.settlement_position("crownwatch")+Vector2(0,30))
 assert_eq(s.army_state[ARMY].garrison,"")
 assert_true(data.settlement("crownwatch").garrison.is_empty())

func test_foreign_settlements_and_armies_are_blocked():
 var data = UiData.new()
 var s = data.state
 assert_ne(s.settlements.greyhaven.owner,"house_aurek")
 var r = data.order_move(ARMY,WorldMap.settlement_position("greyhaven"))
 assert_false(r.ok)
 assert_eq(r.reason,Movement.BLOCKED_BATTLE)
 assert_eq(s.army_state[ARMY].points,Movement.max_points(),"nothing spent")
 # Another faction's army (a stand-in movement entry; there is no second army in the data yet).
 s.army_state["rival"] = {"faction":"house_lannet","position":[20.0,-10.0],"points":60.0,"max_points":60.0,"order":[],"order_settlement":"","garrison":""}
 var b = data.plan_move(ARMY,Vector2(21,-10))
 assert_false(b.ok)
 assert_eq(b.reason,Movement.BLOCKED_BATTLE)
 # Routes go around foreign settlements instead of through them.
 var around = data.plan_move(ARMY,Vector2(-17.5,-60))
 assert_true(around.ok)
 for q in around.points: assert_gt(q.distance_to(WorldMap.settlement_position("greyhaven")),Movement.data().settlements.radius-0.01)
 # Foreign territory itself is not blocked (military access is open in the constitution).
 assert_eq(WorldMap.region_at(Vector2(-17.5,-60)),"greyhaven")
 assert_ne(Movement.terrain_at(Vector2(-17.5,-60)),"mountain")

func test_reachable_area_respects_remaining_points():
 var s = GameState.from_data()
 var full = Movement.reachable(s,ARMY)
 assert_gt(full.size(),50)
 var start = Movement.position(s,ARMY)
 for c in full: assert_lt(Movement.center_of(c).distance_to(start),Movement.max_points()/Movement.data().roads.multiplier_by_level[2]+4.0)
 s.army_state[ARMY].points = 10.0
 assert_lt(Movement.reachable(s,ARMY).size(),full.size())
 # The planned reach point of any destination lies inside the reachable area.
 var p = Movement.plan(s,ARMY,Vector2(-250,-332))
 var cells = {}
 for c in Movement.reachable(s,ARMY): cells[c] = true
 # (or next to it: the planner and the flood fill round the last cell differently at 1 m cells)
 var rc = Movement.cell_of(p.points[p.reach])
 var inside = false
 for dy in range(-1,2):
  for dx in range(-1,2): if cells.has(rc+Vector2i(dx,dy)): inside = true
 assert_true(inside)

func test_movement_state_is_part_of_the_campaign_state():
 var s = GameState.from_data()
 Movement.order(s,ARMY,Vector2(-250,-332))
 var d = s.to_dict()
 assert_true(d.has("army_state") and d.has("road_level"))
 assert_eq(d.army_state[ARMY].order.size(),s.army_state[ARMY].order.size())
 var a = GameState.from_data()
 var b = GameState.from_data()
 for st in [a,b]:
  Movement.order(st,ARMY,Vector2(-250,-332))
  for i in 3: TurnLoop.end_turn(st)
 assert_eq(JSON.stringify(a.to_dict()),JSON.stringify(b.to_dict()))

func test_reachable_area_agrees_with_the_path_planner():
 var s = GameState.from_data()
 var cells = {}
 for c in Movement.reachable(s,ARMY): cells[c] = true
 var start = Movement.cell_of(Movement.position(s,ARMY))
 var budget = Movement.max_points()
 for dz in range(-40,41,4):
  for dx in range(-40,41,4):
   var c = start+Vector2i(dx,dz)
   if not Movement.in_grid(c) or Movement.cell_cost(c,s.road_level)<0: continue
   var p = Movement.plan(s,ARMY,Movement.center_of(c))
   if not p.ok: continue
   # Allow a few points of slack: the planner starts at the exact position, the area at the cell center.
   if p.cost<=budget-5.0: assert_true(cells.has(c),"%s costs %.1f but is outside the area" % [c,p.cost])
   if p.cost>budget+5.0: assert_false(cells.has(c),"%s costs %.1f but is inside the area" % [c,p.cost])

func test_blocked_orders_report_the_message_and_cost_nothing():
 var data = UiData.new()
 var before = data.army_movement(ARMY)
 for target in [WorldMap.settlement_position("greyhaven"),WorldMap.settlement_position("willowmere")+Vector2(1,0)]:
  var r = data.order_move(ARMY,target)
  assert_false(r.ok)
  assert_eq(r.reason,Movement.BLOCKED_BATTLE)
 var after = data.army_movement(ARMY)
 assert_eq(after.position,before.position)
 assert_eq(after.points,before.points)
 assert_true(after.order.is_empty())

func test_coarse_preview_for_long_moves_only():
 # A long move gets a coarse first draft (straight lines between the hierarchy's crossings) that
 # ends where the full plan ends; a short move gets none (the full plan is fast there).
 var s = GameState.from_data()
 var far = Vector2(-250,-332)
 var c = Movement.coarse_plan(s,ARMY,far)
 if not c.is_empty():
  assert_true(c.ok and c.coarse)
  assert_almost_eq(c.points[-1].distance_to(Movement.plan(s,ARMY,far).points[-1]),0.0,0.01)
  assert_gt(c.total_turns,1)
 var near = Movement.position(s,ARMY)+Vector2(20,0)
 assert_eq(Movement.coarse_plan(s,ARMY,near),{},"short moves are planned in full")
