extends SceneTree
# Road planner for authored maps (Stage A content, 2026-10-06):
#   runtime\Godot.exe --headless --path . -s scripts/plan_roads.gd -- --map=<map_id> [--keep=<id>,...]
# Run after a build (it reads the map's baked movement grid and its rivers), then build again.
# Every major settlement is joined to its nearest neighbours (up to NEIGHBOURS within MAX_LINK
# metres) and by a spanning tree, so the network is connected wherever land allows. Each road is
# routed with A* on the movement grid: mountains, lakes and the sea block it (passes are the way
# through ranges and the Greywall); crossing a river costs extra (a bridge), so roads keep few
# crossings. Routes are thinned without cutting corners into blocked cells and written into
# sketch.svg's "roads" layer (replacing it); river stretches far from any bridge get a ford in the
# "fords" layer. The sketch stays the source: edit roads in Inkscape afterwards if wanted.

const MapRegistry = preload("res://core/map_registry.gd")
const WorldMap = preload("res://core/world_map.gd")
const Movement = preload("res://core/movement.gd")
const MapBake = preload("res://map/map_bake.gd")
const Sketch = preload("res://map/sketch.gd")

const NEIGHBOURS = 3
const MAX_LINK = 1400.0
const RIVER_COST = 25.0
const FORD_SPACING = 700.0

var g: Dictionary
var river: PackedByteArray

func _initialize():
 var map_id = "varos"
 for a in OS.get_cmdline_user_args():
  if a.begins_with("--map="): map_id = a.get_slice("=",1)
 MapRegistry.set_active(map_id)
 g = Movement.grid()
 var rc = MapBake.load_render_cache(map_id)
 if rc.is_empty():
  load("res://map/pipeline.gd").build(map_id,false)
  rc = MapBake.load_render_cache(map_id)
 river = rc.rivers.get_data() if not rc.is_empty() else PackedByteArray()
 var t0 = Time.get_ticks_msec()
 var a = _astar()
 var ids = WorldMap.settlement_ids()
 ids.sort()
 var pos = {}
 for id in ids: pos[id] = WorldMap.settlement_position(id)
 # Candidate links: nearest neighbours, then a spanning tree (Prim) so nothing is left out.
 var links = {}
 for id in ids:
  var near = ids.filter(func(o): return o != id and pos[o].distance_to(pos[id])<MAX_LINK)
  near.sort_custom(func(x,y): return pos[x].distance_to(pos[id])<pos[y].distance_to(pos[id]))
  for o in near.slice(0,NEIGHBOURS): links[_key(id,o)] = [id,o]
 var inside = {ids[0]:true}
 while inside.size()<ids.size():
  var best = []
  var bd = INF
  for i in inside:
   for o in ids:
    if inside.has(o): continue
    var d = pos[i].distance_to(pos[o])
    if d<bd:
     bd = d
     best = [i,o]
  if best.is_empty(): break
  inside[best[1]] = true
  if bd<MAX_LINK*2.0: links[_key(best[0],best[1])] = best
 # Route every link.
 var roads = []
 var crossings = []
 var failed = 0
 for k in links:
  var l = links[k]
  var from = Movement.cell_of(pos[l[0]])
  var to = Movement.cell_of(pos[l[1]])
  a.set_point_solid(from,false)
  a.set_point_solid(to,false)
  var cells = a.get_id_path(from,to)
  if cells.size()<2:
   failed += 1
   continue
  for c in cells:
   if _is_river(c): crossings.append(Movement.center_of(c))
  roads.append({"id":"road_%s" % k,"points":_thin(cells,pos[l[0]],pos[l[1]])})
 # Fords: along each river, every FORD_SPACING metres without a bridge nearby.
 var sk = Sketch.parse_file(MapRegistry.path("sketch.svg"))
 var origin = Vector2(MapRegistry.meta().origin[0],MapRegistry.meta().origin[1])
 var fords = []
 for e in sk.layers.get("rivers",[]):
  var since = FORD_SPACING*0.5
  for i in range(1,e.points.size()):
   var p = origin+e.points[i]
   since += (e.points[i]-e.points[i-1]).length()
   if since<FORD_SPACING: continue
   if crossings.any(func(q): return q.distance_to(p)<FORD_SPACING*0.5): continue
   var c = Movement.cell_of(p)
   if not Movement.in_grid(c): continue
   fords.append(p)
   since = 0.0
 _write_sketch(map_id,roads,fords,origin)
 print("ROADS map=%s links=%d roads=%d failed=%d bridges=%d fords=%d ms=%d" % [map_id,links.size(),roads.size(),failed,crossings.size(),fords.size(),Time.get_ticks_msec()-t0])
 quit()

func _key(x: String,y: String) -> String:
 return x+"__"+y if x<y else y+"__"+x

func _is_river(c: Vector2i) -> bool:
 return _river_at(c)

# The render cache and the movement grid share cells on pipeline maps.
func _river_at(c: Vector2i) -> bool:
 var i = c.y*int(g.cols)+c.x
 return i>=0 and i<river.size() and river[i] == 255

func _astar() -> AStarGrid2D:
 var a = AStarGrid2D.new()
 a.region = Rect2i(0,0,g.cols,g.rows)
 a.cell_size = Vector2.ONE
 a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
 a.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
 a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
 a.update()
 var cost = {"open":1.0,"settlement":1.0,"forest":1.6,"hills":2.2,"pass":2.6,"mountain":-1.0,"water":-1.0}
 for z in g.rows:
  for x in g.cols:
   var i = z*g.cols+x
   var t = g.names[g.terrain[i]]
   var w = float(cost.get(t,1.0))
   if t == "water" and _river_at(Vector2i(x,z)): w = RIVER_COST
   if w<0.0: a.set_point_solid(Vector2i(x,z),true)
   elif w != 1.0: a.set_point_weight_scale(Vector2i(x,z),w)
 return a

# A route's cells thinned to a polyline: a point is dropped while the straight line from the last
# kept point stays on passable, non-river ground (so roads bend around mountains and cross rivers
# only where the route did).
func _thin(cells: Array,start: Vector2,goal: Vector2) -> Array:
 var pts = [start]
 var last = 0
 for i in range(2,cells.size()):
  if not _clear(cells[last],cells[i]) or (i-last)>25:
   pts.append(Movement.center_of(cells[i-1]))
   last = i-1
 pts.append(goal)
 return pts

func _clear(p: Vector2i,q: Vector2i) -> bool:
 var n = maxi(absi(q.x-p.x),absi(q.y-p.y))
 for k in n+1:
  var c = Vector2i(Vector2(p).lerp(Vector2(q),float(k)/maxf(1.0,n)).round())
  var t = g.names[g.terrain[c.y*g.cols+c.x]]
  if t in ["mountain","water"]: return false
 return true

func _write_sketch(map_id: String,roads: Array,fords: Array,origin: Vector2):
 var path = MapRegistry.path("sketch.svg",map_id)
 var text = FileAccess.get_file_as_string(path)
 var lines = []
 for r in roads:
  var d = "M %.1f,%.1f" % [r.points[0].x-origin.x,r.points[0].y-origin.y]
  for i in range(1,r.points.size()): d += " L %.1f,%.1f" % [r.points[i].x-origin.x,r.points[i].y-origin.y]
  lines.append('  <path id="%s" d="%s"/>' % [r.id,d])
 var flines = []
 for i in fords.size(): flines.append('  <circle id="ford_%d" cx="%.1f" cy="%.1f" r="10"/>' % [i,fords[i].x-origin.x,fords[i].y-origin.y])
 text = _replace_layer(text,"roads","\n".join(lines))
 text = _replace_layer(text,"fords","\n".join(flines))
 var f = FileAccess.open(path,FileAccess.WRITE)
 f.store_string(text)
 f.close()

func _replace_layer(text: String,layer: String,body: String) -> String:
 var head = ' <g inkscape:groupmode="layer" id="%s">' % layer
 var start = text.find(head)
 if start<0:
  var end_svg = text.rfind("</svg>")
  return text.substr(0,end_svg)+head+"\n"+body+"\n </g>\n"+text.substr(end_svg)
 var stop = text.find(" </g>",start)
 return text.substr(0,start)+head+"\n"+body+"\n"+text.substr(stop)
