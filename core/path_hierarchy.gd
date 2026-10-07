extends RefCounted
# Hierarchical pathfinding (HPA*, docs/map-pipeline-design.md §6.3) for pipeline maps.
#
# Build time (scripts/build_map.gd, after the movement grid and region graph are baked): every pair
# of border crossings of a region (baked/graph.json: one passable crossing cell per pair of
# neighbouring regions) is joined by its least-cost cell path on the terrain grid; the paths are
# stored with sample points every SAMPLE cells and the terrain cost of each sampled segment
# (baked/hpa.json + baked/hpa.bin).
#
# Runtime (core/movement.gd plan): the stored paths become chains of nodes in a native AStar2D graph
# whose node weights carry the terrain cost. A long move adds its start and goal to that graph,
# finds its route over the crossings, searches cell by cell only from the start to its first
# crossing and from its last crossing to the goal, and splices in the stored paths between. A
# stored segment that a foreign army or settlement now blocks is searched again live. Routes are
# chosen at road level 1 (the bake's level); the walked path is costed at the current level.

const MapRegistry = preload("res://core/map_registry.gd")
const MapBake = preload("res://map/map_bake.gd")
const SAMPLE = 16        # cells between chain nodes
const BAKE_ROAD_LEVEL = 1

# --- Build ---------------------------------------------------------------------------------------

static func build(map_id: String) -> Dictionary:
 var prev = MapRegistry.active
 MapRegistry.set_active(map_id)
 var Movement = load("res://core/movement.gd")
 var g = Movement.grid()
 var cols: int = g.cols
 var a = Movement._astar_for(BAKE_ROAD_LEVEL)
 # Stored paths go around every settlement (each blocks every faction but its owner, and settlements
 # never move), so they stay valid for almost every army; an owner still passes through on a live leg.
 var WorldMap = load("res://core/world_map.gd")
 var sr = float(Movement.data().settlements.radius)
 var walled = []
 for sid in WorldMap.settlement_ids():
  for c in Movement._area_cells(WorldMap.settlement_position(sid),sr):
   var v = Vector2i(c%cols,c/cols)
   if not a.is_point_solid(v):
    a.set_point_solid(v,true)
    walled.append(v)
 var edges = JSON.parse_string(FileAccess.get_file_as_string(MapRegistry.path("baked/graph.json"))).edges
 var by_region = {}
 for i in edges.size():
  by_region.get_or_add(int(edges[i][0]),[]).append(i)
  by_region.get_or_add(int(edges[i][1]),[]).append(i)
 var flat = PackedInt32Array()
 var weights = PackedFloat32Array()
 var paths = 0
 var cells_total = 0
 var regions = by_region.keys()
 regions.sort()
 for r in regions:
  var list = by_region[r]
  for i in list.size():
   for j in range(i+1,list.size()):
    var cu = int(edges[list[i]][2])
    var cv = int(edges[list[j]][2])
    var path = a.get_id_path(Vector2i(cu%cols,cu/cols),Vector2i(cv%cols,cv/cols))
    if path.is_empty(): continue
    # Sample indices along the path (first and last always) and each sampled segment's cost.
    var samples = [0]
    var k = SAMPLE
    while k<path.size()-1:
     samples.append(k)
     k += SAMPLE
    if path.size()>1: samples.append(path.size()-1)
    flat.append_array([list[i],list[j],r,path.size(),samples.size()])
    for c in path: flat.append(c.y*cols+c.x)
    for s in samples: flat.append(s)
    for s in range(1,samples.size()):
     var cost = 0.0
     for q in range(samples[s-1]+1,samples[s]+1):
      cost += Movement.center_of(path[q-1]).distance_to(Movement.center_of(path[q]))*maxf(0.0,Movement.cell_cost(path[q],BAKE_ROAD_LEVEL))
     var d = Movement.center_of(path[samples[s-1]]).distance_to(Movement.center_of(path[samples[s]]))
     weights.append(cost/maxf(d,0.001))
    paths += 1
    cells_total += path.size()
 for v in walled: a.set_point_solid(v,false)
 MapBake.write_json(MapRegistry.path("baked/hpa.json"),{"_note":"GENERATED (core/path_hierarchy.gd): stored cell paths between the border crossings of each region, for hierarchical pathfinding.","paths":paths,"ints":flat.size(),"weights":weights.size(),"sample":SAMPLE,"road_level":BAKE_ROAD_LEVEL})
 var f = FileAccess.open_compressed(MapRegistry.path("baked/hpa.bin"),FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
 f.store_buffer(flat.to_byte_array())
 f.store_buffer(weights.to_byte_array())
 f = null
 MapRegistry.set_active(prev)
 return {"paths":paths,"cells":cells_total}

# --- Runtime -------------------------------------------------------------------------------------

# {astar: AStar2D, crossings: PackedInt32Array (cell per crossing), region_crossings: {region: [ids]},
#  chain: {node id: path index}, paths: [{u, v, cells: PackedInt32Array}], s, g: temp node ids}
static func load_for(Movement) -> Dictionary:
 if not MapRegistry.has_file("baked/hpa.json") or not MapRegistry.has_file("baked/graph.json"): return {}
 var meta = JSON.parse_string(FileAccess.get_file_as_string(MapRegistry.path("baked/hpa.json")))
 var edges = JSON.parse_string(FileAccess.get_file_as_string(MapRegistry.path("baked/graph.json"))).edges
 var f = FileAccess.open_compressed(MapRegistry.path("baked/hpa.bin"),FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
 var flat = f.get_buffer(int(meta.ints)*4).to_int32_array()
 var weights = f.get_buffer(int(meta.weights)*4).to_float32_array()
 var g = Movement.grid()
 var cols: int = g.cols
 var astar = AStar2D.new()
 var crossings = PackedInt32Array() # the crossing cell (stored paths start and end here)
 var across = PackedInt32Array()    # the neighbouring cell on the other side of the border
 var parts = MapBake.read_parts(MapRegistry.dir(),cols*int(g.rows)) if MapRegistry.has_file("baked/parts.bin") else PackedInt32Array()
 if parts.size() != cols*int(g.rows): return {}
 var part_crossings = {} # region part -> crossings touching it (on either side)
 for i in edges.size():
  var c = int(edges[i][2])
  var o = int(edges[i][3]) if edges[i].size()>3 else c
  crossings.append(c)
  across.append(o)
  astar.add_point(i,Movement.center_of(Vector2i(c%cols,c/cols)))
  part_crossings.get_or_add(parts[c],[]).append(i)
  if parts[o] != parts[c]: part_crossings.get_or_add(parts[o],[]).append(i)
 var next = edges.size()
 var chain = {}
 var paths = []
 var p = 0
 var w = 0
 while p<flat.size():
  var u = flat[p]
  var v = flat[p+1]
  var n = flat[p+3]
  var ns = flat[p+4]
  var cells = flat.slice(p+5,p+5+n)
  var samples = flat.slice(p+5+n,p+5+n+ns)
  p += 5+n+ns
  var pi = paths.size()
  paths.append({"u":u,"v":v,"cells":cells})
  var prev_id = u
  for s in range(1,ns-1):
   var c = cells[samples[s]]
   astar.add_point(next,Movement.center_of(Vector2i(c%cols,c/cols)),maxf(weights[w+s-1],0.01))
   astar.connect_points(prev_id,next)
   chain[next] = pi
   prev_id = next
   next += 1
  # The last segment enters the crossing v, whose weight is 1: a zero-length node at v carries
  # that segment's cost instead.
  if ns>=2:
   var c_last = cells[samples[ns-1]]
   astar.add_point(next,Movement.center_of(Vector2i(c_last%cols,c_last/cols)),maxf(weights[w+ns-2],0.01))
   astar.connect_points(prev_id,next)
   astar.connect_points(next,v)
   chain[next] = pi
   next += 1
  w += maxi(ns-1,0)
 return {"astar":astar,"crossings":crossings,"across":across,"parts":parts,"part_crossings":part_crossings,"chain":chain,"paths":paths,"s":next,"g":next+1}

# Cells from `from` to `to` through the hierarchy, or [] (no hierarchy, both ends in the same region
# part, or a live leg failed: the caller searches directly). The start and goal connect only to the
# crossings of their own region part (the area of their region they reach without crossing a
# ridge), so their live legs stay short.
static func route(Movement,h: Dictionary,a: AStarGrid2D,from: Vector2i,to: Vector2i,faction: String) -> Array:
 if h.is_empty(): return []
 var cols0: int = Movement.grid().cols
 var ps = h.parts[from.y*cols0+from.x]
 var pg = h.parts[to.y*cols0+to.x]
 if ps == 0 or pg == 0 or ps == pg: return []
 var astar: AStar2D = h.astar
 var cols: int = Movement.grid().cols
 var sp = Movement.center_of(from)
 var gp = Movement.center_of(to)
 astar.add_point(h.s,sp)
 astar.add_point(h.g,gp)
 for c in h.part_crossings.get(ps,[]): astar.connect_points(h.s,c)
 for c in h.part_crossings.get(pg,[]): astar.connect_points(h.g,c)
 var ids = astar.get_id_path(h.s,h.g)
 astar.remove_point(h.s)
 astar.remove_point(h.g)
 if ids.size()<3: return []
 # The crossings visited, and the stored path taken between each consecutive pair.
 var marks = []   # crossing ids in order
 var via = []     # path index between marks[k] and marks[k+1]
 for k in range(1,ids.size()-1):
  var id = ids[k]
  if id<h.crossings.size():
   marks.append(id)
  elif h.chain.has(id) and (via.size()<marks.size()):
   via.append(h.chain[id])
 if marks.is_empty(): return []
 # First leg: to the crossing's cell on the start's side, then onto the crossing cell itself.
 var first = h.crossings[marks[0]]
 var near0 = first if h.parts[first] == ps else h.across[marks[0]]
 var out = _leg(Movement,a,from,Vector2i(near0%cols,near0/cols),faction)
 if out.is_empty(): return []
 if near0 != first: out.append(Vector2i(first%cols,first/cols))
 for k in range(marks.size()-1):
  var cu = h.crossings[marks[k]]
  var cv = h.crossings[marks[k+1]]
  var seg = []
  if k<via.size():
   var pth = h.paths[via[k]]
   var cells: PackedInt32Array = pth.cells
   var ok = true
   for c in cells:
    if Movement.blocked_for(c,faction):
     ok = false
     break
   if ok:
    var forward = pth.u == marks[k]
    for q in cells.size():
     var c = cells[q] if forward else cells[cells.size()-1-q]
     seg.append(Vector2i(c%cols,c/cols))
  if seg.is_empty(): seg = _leg(Movement,a,Vector2i(cu%cols,cu/cols),Vector2i(cv%cols,cv/cols),faction)
  if seg.is_empty(): return []
  out.append_array(seg.slice(1) if not out.is_empty() else seg)
 # Last leg: from the crossing cell (stepping across first when the goal is on the other side).
 var last = h.crossings[marks[-1]]
 var near1 = last if h.parts[last] == pg else h.across[marks[-1]]
 if near1 != last: out.append(Vector2i(near1%cols,near1/cols))
 var tail = _leg(Movement,a,Vector2i(near1%cols,near1/cols),to,faction)
 if tail.is_empty(): return []
 out.append_array(tail.slice(1))
 return out

# A leg inside one region part: a small local search around its ends first (a whole-grid search
# with the road-normalised weights explores far too wide on a big map; 2026-10-06: 1 km previews
# went from about 8.5 to the budget), the whole grid only when the leg detours outside the box.
const LEG_PAD = 8
static func _leg(Movement,a: AStarGrid2D,p: Vector2i,q: Vector2i,faction: String) -> Array:
 if p == q: return [p]
 if a.is_point_solid(q): return []
 var w = Movement.window_cells(Movement.route_road_level,faction,p,q,LEG_PAD)
 if not w.is_empty(): return w
 # The AI's searches stay in windows (Movement.ai_cap): an army sealed in by zones of control would
 # otherwise search the whole map for every failed leg (half a second each in the debug build).
 if Movement.ai_cap: return []
 return Array(a.get_id_path(p,q))

# The coarse route for a preview (no leg searches): from, the crossings the region graph visits,
# to. [] when the hierarchy has nothing to add (same part, no route).
static func coarse(Movement,h: Dictionary,from: Vector2i,to: Vector2i) -> Array:
 if h.is_empty(): return []
 var cols: int = Movement.grid().cols
 var ps = h.parts[from.y*cols+from.x]
 var pg = h.parts[to.y*cols+to.x]
 if ps == 0 or pg == 0 or ps == pg: return []
 var astar: AStar2D = h.astar
 astar.add_point(h.s,Movement.center_of(from))
 astar.add_point(h.g,Movement.center_of(to))
 for c in h.part_crossings.get(ps,[]): astar.connect_points(h.s,c)
 for c in h.part_crossings.get(pg,[]): astar.connect_points(h.g,c)
 var ids = astar.get_id_path(h.s,h.g)
 astar.remove_point(h.s)
 astar.remove_point(h.g)
 if ids.size()<3: return []
 var out = [from]
 for k in range(1,ids.size()-1):
  if ids[k]<h.crossings.size():
   var c = h.crossings[ids[k]]
   out.append(Vector2i(c%cols,c/cols))
 out.append(to)
 return out
