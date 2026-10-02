extends RefCounted
# Army movement over the campaign map (constitution: a per-turn movement allowance, Total War
# style; an army may move several times while its allowance permits). Pure functions over GameState.
#  - Each army has movement points per turn (data/movement.json), refilled on End Turn.
#  - Walking into a grid cell costs the distance in meters times that cell's terrain cost; road
#    cells cost the road multiplier of the current road level instead (PLACEHOLDER rule).
#  - Pathfinding: A* on the baked terrain cost grid (the map's movement grid, 2 m cells).
#  - An order beyond this turn's range moves as far as the points allow; the rest of the path is
#    kept on the army and continues automatically on End Turn. Orders can be cancelled.
#  - Ending a move in one's own settlement garrisons the army there. Moving onto a foreign
#    settlement or another faction's army is not a move: the map opens the battle flow (core/battles.gd).
# OPEN (not designed, so not implemented): zone of control, attrition,
# trespass penalties and military access (free until diplomacy, decision 2026-10-01), naval movement.

const WorldMap = preload("res://core/world_map.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const MapRegistry = preload("res://core/map_registry.gd")
const DATA = "res://data/movement.json" # global rules; the active map's movement.json overlays it
const BLOCKED_BATTLE = "Enemy here: attacking means battle"
const IMPASSABLE = "Impassable terrain"
const NO_ROUTE = "No route"
const NO_GENERAL = "No general: a captain cannot move the army"

static var _data = null
static var _grid = null
static var _map := "" # the map the caches belong to
static var _astar = {} # road level -> AStarGrid2D
static var _costs = {} # road level -> PackedFloat64Array of cell_cost per cell index

static func _check_map():
 if _map != MapRegistry.active:
  reset()
  _map = MapRegistry.active

# The global rules (data/movement.json) with the active map's overlay merged in (its road network,
# passes and bake rectangle).
static func data() -> Dictionary:
 _check_map()
 if _data == null:
  _data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
  assert(_data is Dictionary and _data.has("terrain") and _data.has("roads"),"Invalid "+DATA)
  if MapRegistry.has_file("movement.json"):
   var over = JSON.parse_string(FileAccess.get_file_as_string(MapRegistry.path("movement.json")))
   for k in over:
    if over[k] is Dictionary and _data.get(k) is Dictionary: _data[k].merge(over[k],true)
    else: _data[k] = over[k]
 return _data

static func reset():
 _data = null
 _grid = null
 _map = ""
 _astar = {}
 _costs = {}
 _applied = {}

# The baked grid: {cell, origin, cols, rows, terrain (PackedByteArray of terrain indices), names,
# road (PackedByteArray, 1 where a road crosses the cell)}. A pipeline map stores it in
# baked/movement.bin (below); the test map in movement_grid.json (one symbol per cell, baked by
# main.gd --bake-movement-grid).
static func grid() -> Dictionary:
 _check_map()
 if _grid == null and MapRegistry.has_file("baked/movement.json"): _grid = _load_baked()
 if _grid == null:
  var GRID = MapRegistry.path("movement_grid.json")
  var g = JSON.parse_string(FileAccess.get_file_as_string(GRID))
  assert(g is Dictionary and g.has("rows_data"),"Invalid "+GRID+" (rebuild: main.gd --bake-movement-grid)")
  var names = []
  var by_symbol = {}
  for t in data().terrain:
   if t.begins_with("_"): continue
   by_symbol[data().terrain[t].symbol] = names.size()
   names.append(t)
  var cols = int(g.cols)
  var rows = int(g.rows)
  var terrain = PackedByteArray()
  terrain.resize(cols*rows)
  for z in rows:
   var row: String = g.rows_data[z]
   assert(row.length() == cols,"%s: row %d has %d cells, expected %d" % [GRID,z,row.length(),cols])
   for x in cols:
    assert(by_symbol.has(row[x]),"%s: unknown terrain symbol '%s'" % [GRID,row[x]])
    terrain[z*cols+x] = by_symbol[row[x]]
  _grid = {"cell":float(g.cell),"origin":Vector2(g.origin[0],g.origin[1]),"cols":cols,"rows":rows,"terrain":terrain,"names":names}
  _grid.road = _road_mask()
 return _grid

# Pipeline grid: baked/movement.json {cell, origin, cols, rows, names} and baked/movement.bin,
# zstd-compressed: cols x rows terrain bytes (indices into names, which must equal data/movement.json
# terrain in order), then cols x rows road bytes (1 = road). Sliced natively, no per-cell loop.
static func _load_baked() -> Dictionary:
 var meta = JSON.parse_string(FileAccess.get_file_as_string(MapRegistry.path("baked/movement.json")))
 var names = []
 for t in data().terrain:
  if not t.begins_with("_"): names.append(t)
 assert(meta.names == names,"baked/movement.json terrain names differ from data/movement.json: rebuild the map")
 var n = int(meta.cols)*int(meta.rows)
 var f = FileAccess.open_compressed(MapRegistry.path("baked/movement.bin"),FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
 var raw = f.get_buffer(2*n)
 assert(raw.size() == 2*n,"baked/movement.bin is truncated: rebuild the map")
 var cols = int(meta.cols)
 var rows = int(meta.rows)
 var terrain = raw.slice(0,n)
 var road = raw.slice(n)
 return {"cell":float(meta.cell),"origin":Vector2(meta.origin[0],meta.origin[1]),"cols":cols,"rows":rows,"terrain":terrain,"names":names,"road":road}

static func _road_mask() -> PackedByteArray:
 var g = _grid
 var mask = PackedByteArray()
 mask.resize(g.cols*g.rows)
 var half = float(data().roads.width)*0.5
 for road in data().roads.network:
  for i in road.points.size()-1:
   var a = Vector2(road.points[i][0],road.points[i][1])
   var b = Vector2(road.points[i+1][0],road.points[i+1][1])
   var lo = cell_of(Vector2(minf(a.x,b.x),minf(a.y,b.y))-Vector2.ONE*(half+g.cell))
   var hi = cell_of(Vector2(maxf(a.x,b.x),maxf(a.y,b.y))+Vector2.ONE*(half+g.cell))
   for z in range(maxi(lo.y,0),mini(hi.y,g.rows-1)+1):
    for x in range(maxi(lo.x,0),mini(hi.x,g.cols-1)+1):
     var c = center_of(Vector2i(x,z))
     if c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b))<=half: mask[z*g.cols+x] = 1
 return mask

# --- Grid queries ----------------------------------------------------------------

static func cell_of(p: Vector2) -> Vector2i:
 var g = _grid if _grid != null else grid()
 return Vector2i(floori((p.x-g.origin.x)/g.cell),floori((p.y-g.origin.y)/g.cell))

static func center_of(c: Vector2i) -> Vector2:
 var g = _grid if _grid != null else grid()
 return g.origin+(Vector2(c)+Vector2(0.5,0.5))*g.cell

static func in_grid(c: Vector2i) -> bool:
 var g = grid()
 return c.x>=0 and c.y>=0 and c.x<g.cols and c.y<g.rows

static func terrain_of(c: Vector2i) -> String:
 if not in_grid(c): return "water"
 return grid().names[grid().terrain[c.y*grid().cols+c.x]]

static func terrain_at(p: Vector2) -> String:
 return terrain_of(cell_of(p))

static func is_road(c: Vector2i) -> bool:
 return in_grid(c) and grid().road[c.y*grid().cols+c.x] == 1

static func road_multiplier(road_level: int) -> float:
 var m = data().roads.multiplier_by_level
 return float(m[clampi(road_level,0,m.size()-1)])

# Cost per meter of walking into a cell, or -1 if impassable.
static func cell_cost(c: Vector2i,road_level: int) -> float:
 var t = data().terrain[terrain_of(c)]
 if t.cost == null: return -1.0
 if is_road(c): return road_multiplier(road_level)
 return float(t.cost)

# Points spent walking from a to b (b inside the cell being entered).
static func segment_cost(a: Vector2,b: Vector2,road_level: int) -> float:
 return a.distance_to(b)*cell_cost(cell_of(b),road_level)

static func _min_cost() -> float:
 var m = 1.0e9
 for t in data().terrain:
  if not t.begins_with("_") and data().terrain[t].cost != null: m = minf(m,float(data().terrain[t].cost))
 for r in data().roads.multiplier_by_level: m = minf(m,float(r))
 return m

# A* grid per road level. Weights are normalized so the cheapest cell weighs 1, which keeps the
# Euclidean heuristic admissible (paths are least-cost).
static func _astar_for(road_level: int) -> AStarGrid2D:
 if _astar.has(road_level): return _astar[road_level]
 var g = grid()
 var a = AStarGrid2D.new()
 a.region = Rect2i(0,0,g.cols,g.rows)
 a.cell_size = Vector2.ONE
 a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
 a.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
 a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
 a.update()
 var lo = _min_cost()
 for z in g.rows:
  for x in g.cols:
   var c = Vector2i(x,z)
   var cost = cell_cost(c,road_level)
   if cost<0: a.set_point_solid(c,true)
   else: a.set_point_weight_scale(c,cost/lo)
 _astar[road_level] = a
 return a

# --- Army state --------------------------------------------------------------------

static func max_points() -> float:
 return float(data().army.movement_points)

# Initial movement state of an army (composition is added by core/armies.gd).
static func new_army_state(faction: String,position: Vector2) -> Dictionary:
 return {"faction":faction,"position":[position.x,position.y],"points":max_points(),"max_points":max_points(),
  "order":[],"order_settlement":"","garrison":""}

static func army(state,army_id: String) -> Dictionary:
 assert(state.army_state.has(army_id),"No movement state for army '%s'" % army_id)
 return state.army_state[army_id]

static func position(state,army_id: String) -> Vector2:
 var p = army(state,army_id).position
 return Vector2(p[0],p[1])

static func settlement_at(p: Vector2) -> String:
 var r = float(data().settlements.radius)
 for id in WorldMap.settlement_ids():
  if WorldMap.settlement_position(id).distance_to(p)<=r: return id
 return ""

# Armies garrisoned in a settlement.
static func garrison_of(state,settlement_id: String) -> Array:
 var out = []
 for id in state.army_state:
  if state.army_state[id].garrison == settlement_id: out.append(id)
 out.sort()
 return out

# Cells the army may not enter: foreign settlements and other factions' armies (battle).
# Foreign armies and settlements are solid for a faction's paths. They stay applied on the shared
# A* grid between plans and are re-applied only when the faction, road level, foreign armies'
# positions or settlement owners change (each application costs O(armies x cells), and the AI
# plans many paths in a row).
static var _applied = {} # road level -> {key, cells}

static func _apply_blocks(state,a: AStarGrid2D,faction: String):
 var parts = [faction,str(state.road_level)]
 var ids = state.army_state.keys()
 ids.sort()
 for id in ids:
  var o = state.army_state[id]
  if o.faction != faction: parts.append("%s@%s" % [id,str(o.position)])
 for sid in WorldMap.settlement_ids(): parts.append(state.settlements[sid].owner)
 var key = "|".join(parts)
 var ap = _applied.get(state.road_level,{})
 if ap.get("key","") == key: return
 for c in ap.get("cells",[]): a.set_point_solid(c,cell_cost(c,state.road_level)<0)
 var cells = _faction_blocked_cells(state,faction)
 for c in cells: a.set_point_solid(c,true)
 _applied[state.road_level] = {"key":key,"cells":cells}

static func _faction_blocked_cells(state,faction: String) -> Array:
 var out = []
 var areas = []
 for id in WorldMap.settlement_ids():
  if state.settlements[id].owner != faction: areas.append([WorldMap.settlement_position(id),float(data().settlements.radius)])
 for other in state.army_state:
  if state.army_state[other].faction != faction: areas.append([position(state,other),float(data().armies.block_radius)])
 for a in areas:
  var lo = cell_of(a[0]-Vector2.ONE*a[1])
  var hi = cell_of(a[0]+Vector2.ONE*a[1])
  for z in range(lo.y,hi.y+1):
   for x in range(lo.x,hi.x+1):
    var c = Vector2i(x,z)
    if in_grid(c) and center_of(c).distance_to(a[0])<=a[1]: out.append(c)
 return out

static func _blocked_cells(state,army_id: String) -> Array:
 var me = army(state,army_id)
 var out = []
 var areas = []
 for id in WorldMap.settlement_ids():
  if state.settlements[id].owner != me.faction: areas.append([WorldMap.settlement_position(id),float(data().settlements.radius)])
 for other in state.army_state:
  if other != army_id and state.army_state[other].faction != me.faction: areas.append([position(state,other),float(data().armies.block_radius)])
 for a in areas:
  var lo = cell_of(a[0]-Vector2.ONE*a[1])
  var hi = cell_of(a[0]+Vector2.ONE*a[1])
  for z in range(lo.y,hi.y+1):
   for x in range(lo.x,hi.x+1):
    var c = Vector2i(x,z)
    if in_grid(c) and center_of(c).distance_to(a[0])<=a[1]: out.append(c)
 return out

# Where an order to `target` would end, or why it cannot be given.
static func destination(state,army_id: String,target: Vector2) -> Dictionary:
 var me = army(state,army_id)
 var sid = settlement_at(target)
 if sid != "":
  if state.settlements[sid].owner != me.faction: return {"ok":false,"reason":BLOCKED_BATTLE,"settlement":sid}
  return {"ok":true,"point":WorldMap.settlement_position(sid),"settlement":sid}
 for other in state.army_state:
  if other != army_id and state.army_state[other].faction != me.faction and position(state,other).distance_to(target)<=float(data().armies.block_radius):
   return {"ok":false,"reason":BLOCKED_BATTLE,"army":other}
 if not in_grid(cell_of(target)) or cell_cost(cell_of(target),state.road_level)<0: return {"ok":false,"reason":IMPASSABLE}
 return {"ok":true,"point":target,"settlement":""}

# Plan a move: {ok, reason, points (world x/z from the army to the destination), turns (turn index
# of each point: 0 = this turn), reach (last point reachable this turn), total_turns, cost, settlement}.
static func plan(state,army_id: String,target: Vector2,retreating := false) -> Dictionary:
 # A captain (dead or wounded general) cannot order a move (core/battles.gd); a beaten army's
 # retreat is not an order and needs no general.
 if not retreating and army(state,army_id).get("commander",{}).get("status","ok") != "ok": return {"ok":false,"reason":NO_GENERAL}
 var dest = destination(state,army_id,target)
 if not dest.ok: return dest
 var me = army(state,army_id)
 var start = position(state,army_id)
 var a = _astar_for(state.road_level)
 _apply_blocks(state,a,me.faction)
 var from = cell_of(start)
 var to = cell_of(dest.point)
 var was_solid = a.is_point_solid(from)
 a.set_point_solid(from,false)
 var cells = a.get_id_path(from,to) if not a.is_point_solid(to) else []
 a.set_point_solid(from,was_solid)
 if cells.is_empty(): return {"ok":false,"reason":NO_ROUTE}
 var points = [start]
 for i in range(1,cells.size()-1): points.append(center_of(cells[i]))
 if dest.point.distance_to(start)>0.001: points.append(dest.point)
 var sim = simulate(points,float(me.points),float(me.max_points),state.road_level)
 return {"ok":true,"points":points,"turns":sim.turns,"reach":sim.reach,"total_turns":sim.turns[-1]+1,"cost":sim.cost,"settlement":dest.settlement}

# Turn index of every path point, starting with `points_left` this turn and a full allowance on
# each later turn. An army stops before a step it cannot afford (Total War style).
static func simulate(points: Array,points_left: float,full: float,road_level: int) -> Dictionary:
 var turns = [0]
 var turn = 0
 var budget = points_left
 var total = 0.0
 var reach = 0
 for i in range(1,points.size()):
  var c = segment_cost(points[i-1],points[i],road_level)
  total += c
  if c>budget+0.0001:
   turn += 1
   budget = full
  budget -= c
  turns.append(turn)
  if turn == 0: reach = i
 return {"turns":turns,"reach":reach,"cost":total}

# Give an order and move as far as this turn allows. Returns the plan plus "moved" (the points
# walked now, starting at the old position).
static func order(state,army_id: String,target: Vector2) -> Dictionary:
 var p = plan(state,army_id,target)
 if not p.ok: return p
 var me = army(state,army_id)
 me.order = []
 for q in p.points.slice(1): me.order.append([q.x,q.y])
 me.order_settlement = p.settlement
 p.moved = advance(state,army_id)
 return p

static func cancel_order(state,army_id: String):
 var me = army(state,army_id)
 me.order = []
 me.order_settlement = ""

# Walk the army along its order while its points allow. Returns the points walked.
static func advance(state,army_id: String) -> Array:
 var me = army(state,army_id)
 var at = position(state,army_id)
 var walked = [at]
 while not me.order.is_empty():
  var next = Vector2(me.order[0][0],me.order[0][1])
  var c = segment_cost(at,next,state.road_level)
  if c<0 or c>float(me.points)+0.0001: break
  me.points = maxf(0.0,float(me.points)-c)
  me.order.pop_front()
  at = next
  walked.append(at)
 me.position = [at.x,at.y]
 if walked.size()>1: me.garrison = ""
 if me.order.is_empty():
  if me.order_settlement != "" and state.settlements[me.order_settlement].owner == me.faction: me.garrison = me.order_settlement
  me.order_settlement = ""
 return walked

# End Turn: refill every army's allowance, then continue standing orders. Returns {army: walked}.
static func end_turn(state) -> Dictionary:
 var moves = {}
 var ids = state.army_state.keys()
 ids.sort()
 for id in ids:
  var me = state.army_state[id]
  me.points = float(me.max_points)
  if not me.order.is_empty(): moves[id] = advance(state,id)
 return moves

static func _cost_table(road_level: int) -> PackedFloat64Array:
 if _costs.has(road_level): return _costs[road_level]
 var g = grid()
 var t = PackedFloat64Array()
 t.resize(g.cols*g.rows)
 for i in t.size(): t[i] = cell_cost(Vector2i(i%g.cols,i/g.cols),road_level)
 _costs[road_level] = t
 return t

# Cells the army can still reach this turn (Dijkstra limited by its remaining points), with the
# same step costs and diagonal rule as the path search.
static func reachable(state,army_id: String) -> Array:
 var g = grid()
 var cols: int = g.cols
 var rows: int = g.rows
 var cost = _cost_table(state.road_level).duplicate()
 for c in _blocked_cells(state,army_id): cost[c.y*cols+c.x] = -1.0
 var budget = float(army(state,army_id).points)
 var start_cell = cell_of(position(state,army_id))
 var start = start_cell.y*cols+start_cell.x
 cost[start] = maxf(cost[start],0.0)
 var best = PackedFloat64Array()
 best.resize(cols*rows)
 best.fill(INF)
 best[start] = 0.0
 var cell = float(g.cell)
 var diag = cell*sqrt(2.0)
 var heap = [[0.0,start]]
 var out = []
 while not heap.is_empty():
  var top = _heap_pop(heap)
  var d: float = top[0]
  var i: int = top[1]
  if d>best[i]: continue
  out.append(Vector2i(i%cols,i/cols))
  var x = i%cols
  var z = i/cols
  for dz in [-1,0,1]:
   var nz = z+dz
   if nz<0 or nz>=rows: continue
   for dx in [-1,0,1]:
    var nx = x+dx
    if (dx == 0 and dz == 0) or nx<0 or nx>=cols: continue
    var n = nz*cols+nx
    var c = cost[n]
    if c<0: continue
    if dx != 0 and dz != 0 and (cost[z*cols+nx]<0 or cost[nz*cols+x]<0): continue
    var nd = d+(diag if dx != 0 and dz != 0 else cell)*c
    if nd<=budget and nd<best[n]:
     best[n] = nd
     _heap_push(heap,[nd,n])
 return out
static func _heap_push(heap: Array,item: Array):
 heap.append(item)
 var i = heap.size()-1
 while i>0:
  var p = (i-1)/2
  if heap[p][0]<=heap[i][0]: break
  var t = heap[p]
  heap[p] = heap[i]
  heap[i] = t
  i = p

static func _heap_pop(heap: Array) -> Array:
 var top = heap[0]
 var last = heap.pop_back()
 if not heap.is_empty():
  heap[0] = last
  var i = 0
  while true:
   var l = i*2+1
   var r = l+1
   var m = i
   if l<heap.size() and heap[l][0]<heap[m][0]: m = l
   if r<heap.size() and heap[r][0]<heap[m][0]: m = r
   if m == i: break
   var t = heap[m]
   heap[m] = heap[i]
   heap[i] = t
   i = m
 return top
