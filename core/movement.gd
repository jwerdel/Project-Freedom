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
const MapBake = preload("res://map/map_bake.gd")
const PathHierarchy = preload("res://core/path_hierarchy.gd")
const DATA = "res://data/movement.json" # global rules; the active map's movement.json overlays it
const BLOCKED_BATTLE = "Enemy here: attacking means battle"
const IMPASSABLE = "Impassable terrain"
const NO_ROUTE = "No route"
const NO_GENERAL = "No general: a captain cannot move the army"

static var _data = null
static var _grid = null
static var _map := "" # the map the caches belong to
static var _astar = {} # road level -> AStarGrid2D
static var _costs = {} # road level -> cost per cell code (_code_costs)
static var _runs = null # row runs of the grid (map/map_bake.gd runs_of)

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
 _runs = null
 _blk = {}
 _blk_applied = {}
 _blk_dirty = {}
 _blk_key = []
 _graph = null
 _hpa = null
 _comp = null

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
 return {"cell":float(meta.cell),"origin":Vector2(meta.origin[0],meta.origin[1]),"cols":cols,"rows":rows,"terrain":terrain,"names":names,"road":road,"runs":int(meta.get("runs",0))}

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

# Cost per meter for every cell code (terrain index + 16 * road), or -1 if impassable.
static func _code_costs(road_level: int) -> PackedFloat64Array:
 if _costs.has(road_level): return _costs[road_level]
 var g = grid()
 var t = PackedFloat64Array()
 t.resize(32)
 t.fill(-1.0)
 for i in g.names.size():
  var c = data().terrain[g.names[i]].cost
  if c == null: continue
  t[i] = float(c)
  t[i+16] = road_multiplier(road_level)
 _costs[road_level] = t
 return t

# Row runs of identical cells (map/map_bake.gd runs_of): baked with a pipeline map, computed here
# for the test map.
static func _grid_runs() -> PackedInt32Array:
 if _runs == null:
  var g = grid()
  var n = int(g.get("runs",0))
  if n>0: _runs = MapBake.read_runs(MapRegistry.dir(),n)
  if _runs == null or _runs.size() != n*4: _runs = MapBake.runs_of(g.terrain,g.road,g.cols,g.rows)
 return _runs

# A* grid per road level, built in bulk from the row runs (one native fill per run, not one call per
# cell). Weights are normalized so the cheapest cell weighs 1, which keeps the Euclidean heuristic
# admissible (paths are least-cost).
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
 var costs = _code_costs(road_level)
 var runs = _grid_runs()
 for k in range(0,runs.size(),4):
  var cost = costs[runs[k+3]]
  var r = Rect2i(runs[k],runs[k+1],runs[k+2],1)
  if cost<0: a.fill_solid_region(r,true)
  elif not is_equal_approx(cost,lo): a.fill_weight_scale_region(r,cost/lo)
 _astar[road_level] = a
 _blk_applied[road_level] = null # no faction's blocking applied yet
 return a

# --- Blocking: enemy armies and foreign settlements ------------------------------------------------
# A move may not path through another faction's army or settlement (moving onto one is the battle
# flow instead). The blocked cells are kept as an index updated incrementally (only armies that
# moved and settlements that changed hands are recomputed), with per-cell counts for every area and
# for each faction's own areas: a cell blocks faction F when it lies in an area F does not own.
# Switching the A* grid from one faction to another only touches those two factions' own cells.
static var _blk = {}            # {"total": {cell: n}, "own": {faction: {cell: n}}, "areas": {key: [faction, at, cells]}}
static var _blk_applied = {}    # road level -> faction whose blocking is applied to that grid (null: none)
static var _blk_dirty = {}      # cells whose count changed since the grids were last synced
static var _blk_faction := "" # the faction the next sync is for (set by its callers)

static func _area_cells(at: Vector2,radius: float) -> PackedInt32Array:
 var g = grid()
 var out = PackedInt32Array()
 var lo = cell_of(at-Vector2.ONE*radius)
 var hi = cell_of(at+Vector2.ONE*radius)
 for z in range(maxi(lo.y,0),mini(hi.y,g.rows-1)+1):
  for x in range(maxi(lo.x,0),mini(hi.x,g.cols-1)+1):
   if center_of(Vector2i(x,z)).distance_to(at)<=radius: out.append(z*g.cols+x)
 return out

static func _blk_add(key: String,faction: String,at: Vector2,radius: float,sign: int):
 var total = _blk.total
 var own = _blk.own.get_or_add(faction,{})
 var cells = _area_cells(at,radius) if sign>0 else _blk.areas[key][2]
 for c in cells:
  total[c] = total.get(c,0)+sign
  own[c] = own.get(c,0)+sign
  if total[c] == 0: total.erase(c)
  if own[c] == 0: own.erase(c)
  _blk_dirty[c] = true
 if sign>0: _blk.areas[key] = [faction,at,cells]
 else: _blk.areas.erase(key)

# Bring the index up to date with the state: armies that moved, appeared or vanished, settlements
# that changed hands. Cheap when nothing changed (one pass over armies and settlements).
static var _blk_key = []
static func _sync_blocks(state):
 # Within one frame, for the same faction and with no battle or army change since, nothing that
 # blocks this faction has moved (only its own armies did), so the last sync still holds.
 var sync_key = [state.get_instance_id(),Engine.get_process_frames(),state.battles,state.army_state.size(),_blk_faction]
 if sync_key == _blk_key and not _blk.is_empty(): return
 _blk_key = sync_key
 if _blk.is_empty(): _blk = {"total":{},"own":{},"areas":{}}
 var areas = _blk.areas
 var seen = {}
 var sr = float(data().settlements.radius)
 for sid in WorldMap.settlement_ids():
  var key = "s:"+sid
  seen[key] = true
  var owner = state.settlements[sid].owner
  var old = areas.get(key)
  if old != null and old[0] == owner: continue
  if old != null: _blk_add(key,old[0],old[1],sr,-1)
  _blk_add(key,owner,WorldMap.settlement_position(sid),sr,1)
 var ar = float(data().armies.block_radius)
 for id in state.army_state:
  var key = "a:"+id
  seen[key] = true
  var o = state.army_state[id]
  var at = Vector2(o.position[0],o.position[1])
  var old = areas.get(key)
  if old != null and old[0] == o.faction and old[1] == at: continue
  if old != null: _blk_add(key,old[0],old[1],ar,-1)
  _blk_add(key,o.faction,at,ar,1)
 for key in areas.keys():
  if not seen.has(key): _blk_add(key,areas[key][0],areas[key][1],0.0,-1)

static func blocked_for(cell: int,faction: String) -> bool:
 return _blk.total.get(cell,0)-_blk.own.get(faction,{}).get(cell,0)>0

static func _apply_blocks(state,a: AStarGrid2D,faction: String):
 _blk_faction = faction
 _sync_blocks(state)
 var cols = grid().cols
 var costs = _code_costs(state.road_level)
 var g = grid()
 var prev = _blk_applied.get(state.road_level)
 var touch = {}
 if prev == null: touch = _blk.total.duplicate()
 elif prev != faction:
  touch.merge(_blk.own.get(prev,{}))
  touch.merge(_blk.own.get(faction,{}))
 touch.merge(_blk_dirty)
 for c in touch:
  var terrain_solid = costs[g.terrain[c]+16*g.road[c]]<0
  a.set_point_solid(Vector2i(c%cols,c/cols),terrain_solid or blocked_for(c,faction))
 _blk_applied[state.road_level] = faction
 # Dirty cells are now synced for this grid; other road levels resync them in full on their next use.
 if not _blk_dirty.is_empty():
  for lvl in _blk_applied:
   if lvl != state.road_level: _blk_applied[lvl] = null
  _blk_dirty = {}

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
 var near = WorldMap.settlements_near(p,float(data().settlements.radius))
 if near.is_empty(): return ""
 # The first in file order, as before.
 var best = near[0]
 for id in near:
  if WorldMap.settlement_ids().find(id)<WorldMap.settlement_ids().find(best): best = id
 return best

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
# Where an order to `target` would end, or why it cannot be given.
static func destination(state,army_id: String,target: Vector2) -> Dictionary:
 var me = army(state,army_id)
 var sid = settlement_at(target)
 if sid != "":
  if state.settlements[sid].owner != me.faction: return {"ok":false,"reason":BLOCKED_BATTLE,"settlement":sid}
  return {"ok":true,"point":WorldMap.settlement_position(sid),"settlement":sid}
 # Another faction's army near the target: only searched when the blocking index shows a foreign
 # area within reach of the target cell (any army within block_radius blocks a cell that close).
 if _foreign_area_near(state,target,me.faction):
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
 var cells = []
 if not a.is_point_solid(to) and _same_component(from,to):
  cells = _hierarchical_path(a,start,dest.point,from,to)
  if cells.is_empty(): cells = a.get_id_path(from,to)
 a.set_point_solid(from,was_solid)
 if cells.is_empty(): return {"ok":false,"reason":NO_ROUTE}
 var points = [start]
 var go: Vector2 = grid().origin+Vector2(0.5,0.5)*grid().cell
 var gc: float = grid().cell
 for i in range(1,cells.size()-1): points.append(go+Vector2(cells[i])*gc)
 if dest.point.distance_to(start)>0.001: points.append(dest.point)
 var sim = simulate(points,float(me.points),float(me.max_points),state.road_level)
 return {"ok":true,"points":points,"turns":sim.turns,"reach":sim.reach,"total_turns":sim.turns[-1]+1,"cost":sim.cost,"settlement":dest.settlement}

# --- Hierarchical paths (docs/map-pipeline-design.md §6.3) ---------------------------------------
# Long moves on a pipeline map go through core/path_hierarchy.gd (HPA*: region crossings joined by
# stored paths); short moves, the test map and failed hierarchy queries search the grid directly.
const HIER_MIN_DISTANCE = 100.0 # metres; shorter moves are searched directly
static var _graph = null      # {index: {region id: graph index}} or {}
static var _hpa = null        # core/path_hierarchy.gd data, or {}

static func _region_graph() -> Dictionary:
 _check_map()
 if _graph == null:
  _graph = {}
  if MapRegistry.has_file("baked/graph.json") and MapRegistry.has_file("baked/regions.json"):
   var names = JSON.parse_string(FileAccess.get_file_as_string(MapRegistry.path("baked/regions.json"))).names
   var index = {}
   for i in names.size(): index[names[i]] = i
   _graph = {"index":index}
 return _graph

static func _hierarchical_path(a: AStarGrid2D,start: Vector2,goal: Vector2,from: Vector2i,to: Vector2i) -> Array:
 if start.distance_to(goal)<HIER_MIN_DISTANCE: return []
 var hg = _region_graph()
 if hg.is_empty(): return []
 if _hpa == null: _hpa = PathHierarchy.load_for(load("res://core/movement.gd"))
 return PathHierarchy.route(load("res://core/movement.gd"),_hpa,a,from,to,_blk_faction)

# False when the baked components show no passable land route between the cells (pipeline maps).
static var _comp = null
static func _same_component(a: Vector2i,b: Vector2i) -> bool:
 if _comp == null:
  var g = grid()
  _comp = MapBake.read_components(MapRegistry.dir(),g.cols*g.rows) if MapRegistry.has_file("baked/components.bin") else PackedInt32Array()
  if _comp.size() != g.cols*g.rows: _comp = PackedInt32Array()
 if _comp.is_empty(): return true
 var cols = grid().cols
 var ca = _comp[a.y*cols+a.x]
 var cb = _comp[b.y*cols+b.x]
 # A blocked start (the army stands in a settlement cell) has no component: let the search decide.
 return ca == 0 or cb == 0 or ca == cb


# Turn index of every path point, starting with `points_left` this turn and a full allowance on
# each later turn. An army stops before a step it cannot afford (Total War style).
static func simulate(points: Array,points_left: float,full: float,road_level: int) -> Dictionary:
 var turns = [0]
 var turn = 0
 var budget = points_left
 var total = 0.0
 var reach = 0
 # Inlined segment_cost (one lookup per point in the per-code cost table): long paths have hundreds
 # of points and this runs for every preview update.
 var g = grid()
 var codes = _code_costs(road_level)
 var terrain: PackedByteArray = g.terrain
 var road: PackedByteArray = g.road
 var cols: int = g.cols
 var rows: int = g.rows
 var o: Vector2 = g.origin
 var cs: float = g.cell
 for i in range(1,points.size()):
  var b: Vector2 = points[i]
  var cx = floori((b.x-o.x)/cs)
  var cz = floori((b.y-o.y)/cs)
  var unit = -1.0
  if cx>=0 and cz>=0 and cx<cols and cz<rows:
   var k = cz*cols+cx
   unit = codes[terrain[k]+16*road[k]]
  var c = points[i-1].distance_to(b)*unit
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

# Cells the army can still reach this turn (Dijkstra limited by its remaining points), with the
# same step costs and diagonal rule as the path search.
static func reachable(state,army_id: String) -> Array:
 var g = grid()
 var cols: int = g.cols
 var rows: int = g.rows
 var codes = _code_costs(state.road_level)
 var terrain: PackedByteArray = g.terrain
 var road: PackedByteArray = g.road
 var faction = army(state,army_id).faction
 _blk_faction = faction
 _sync_blocks(state)
 var total: Dictionary = _blk.total
 var own: Dictionary = _blk.own.get(faction,{})
 # Step cost of a cell (-1 impassable or blocked), looked up only for cells the search reaches.
 var cost_of = func(i: int) -> float:
  if total.has(i) and total[i]-own.get(i,0)>0: return -1.0
  return codes[terrain[i]+16*road[i]]
 var budget = float(army(state,army_id).points)
 var start_cell = cell_of(position(state,army_id))
 var start = start_cell.y*cols+start_cell.x
 var start_cost = maxf(cost_of.call(start),0.0)
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
    var c = start_cost if n == start else cost_of.call(n)
    if c<0: continue
    if dx != 0 and dz != 0 and (cost_of.call(z*cols+nx)<0 or cost_of.call(nz*cols+x)<0): continue
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

# True if a cell within block_radius plus a cell of the target is blocked for `faction` (a foreign
# army or settlement is that close).
static func _foreign_area_near(state,target: Vector2,faction: String) -> bool:
 _blk_faction = faction
 _sync_blocks(state)
 var g = grid()
 var c = cell_of(target)
 var r = int(ceil(float(data().armies.block_radius)/g.cell))+1
 for z in range(maxi(c.y-r,0),mini(c.y+r,g.rows-1)+1):
  for x in range(maxi(c.x-r,0),mini(c.x+r,g.cols-1)+1):
   if blocked_for(z*g.cols+x,faction): return true
 return false
