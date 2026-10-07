extends RefCounted
# The map pipeline's build for authored maps (map.json "kind": "pipeline"; design
# docs/map-pipeline-design.md §4.1): sketch.svg (map/sketch.gd) + world.json -> the committed bakes
# (provinces.json, movement.json overlay, baked/ movement grid, region raster, components, parts,
# graph, hierarchy) and the render cache (heights, colours, rivers). Deterministic: randomness only
# from map.json detail_seed. Then the validator (map/validator.gd) runs and its report is returned.
#
# Sketch layers used (world coordinates = map origin + SVG units, 1 unit = 1 m):
#  land (closed shapes), lakes (closed), hills (closed), forests (closed, data-density 0-1),
#  ranges (open paths, data-height, data-width), passes (open paths or circles, data-width),
#  rivers (open paths, source to mouth, data-width), sites (circles, id = region id), roads (open
#  paths, pinned; they bridge rivers), fords (circles: river crossings), borders (optional), climates
#  (closed, data-climate: ground colours only). River cores are water: crossed only at bridges and fords.
#  Other layers (e.g. "stages") are kept in the sketch for tools and ignored here.
# world.json: {"provinces": [...], "regions": {id: {name, province, owner, major: {name, type,
# level, port, landmark, path}, resources, polygon (optional: pinned region outline)}},
# "factions_file", "start_file", "armies_dir", "allow_legacy_majors"}.

const Sketch = preload("res://map/sketch.gd")
const MapBake = preload("res://map/map_bake.gd")
const MapRegistry = preload("res://core/map_registry.gd")
const PathHierarchy = preload("res://core/path_hierarchy.gd")
const Synthetic = preload("res://map/synthetic.gd")
const OPEN = 0
const FOREST = 1
const HILLS = 2
const PASS = 3
const SETTLEMENT = 4
const MOUNTAIN = 5
const WATER = 6
const MOUNTAIN_ABOVE = 22.0
const HILLS_ABOVE = 8.0
# Ground tints of the sketch's "climates" layer (render colours only).
const CLIMATE_TINTS = {"snow":Color("e8ecef"),"tundra":Color("a3ab92"),"taiga":Color("5f7a52"),"mediterranean":Color("b3aa66"),"desert":Color("dcbb7c"),"redrock":Color("a4523a"),"swamp":Color("56653f"),"steppe":Color("c8b26a"),"ash":Color("5f5b58"),"jungle":Color("2f6a32"),"white":Color("e4e4dc"),"marsh":Color("6d7a4c")}
# What each climate does to the 3D ground (map/terrain_view.gdshader; owner 2026-10-06: the north reads
# as snow and frost): [snow cover, frost, dryness, wetness], 0-1. Baked per CLIMATE_STEP cells and
# blurred over CLIMATE_BLUR metres into the render cache, so climates blend without seams.
const CLIMATE_LOOK = {"snow":[0.8,1.0,0.0,0.0],"white":[0.7,0.9,0.0,0.0],"tundra":[0.45,0.85,0.0,0.0],"taiga":[0.18,0.6,0.0,0.0],"mediterranean":[0.0,0.0,0.2,0.0],"desert":[0.0,0.0,1.0,0.0],"steppe":[0.0,0.1,0.55,0.0],"redrock":[0.0,0.0,0.7,0.0],"ash":[0.0,0.2,0.4,0.0],"swamp":[0.0,0.0,0.0,1.0],"marsh":[0.0,0.0,0.0,0.7],"jungle":[0.0,0.0,0.0,0.6]}
const CLIMATE_STEP = 8
const CLIMATE_BLUR = 220.0

static func sources_hash(map_id: String) -> String:
 var parts = []
 for f in ["map.json","sketch.svg","world.json"]:
  parts.append(FileAccess.get_file_as_string(MapRegistry.path(f,map_id)) if MapRegistry.has_file(f,map_id) else "")
 return str(hash("\n".join(parts)))

# bakes = false: only the local render cache (heights, colours, rivers) is written; the game does this
# on first run or when the cache is stale (the committed bakes ship with the map).
# progress (optional): called with (fraction 0-1, step name) as the build moves on; it may run on a
# worker thread (the first-run screen), so it must only store the values.
static func build(map_id: String,bakes := true,progress := Callable()) -> Dictionary:
 var step = func(f: float,name: String): if progress.is_valid(): progress.call(f,name)
 var t_all = Time.get_ticks_msec()
 var meta = MapRegistry.meta(map_id)
 var dir = MapRegistry.dir(map_id)
 var report = {"map":map_id,"errors":[],"warnings":[],"times":{}}
 var sketch = Sketch.parse_file(dir+"sketch.svg")
 report.errors.append_array(sketch.errors)
 var world = JSON.parse_string(FileAccess.get_file_as_string(dir+"world.json")) if FileAccess.file_exists(dir+"world.json") else null
 if world == null: report.errors.append("world.json missing or invalid")
 if not report.errors.is_empty(): return report
 var cell = float(meta.cell)
 var origin = Vector2(meta.origin[0],meta.origin[1])
 var cols = int(float(meta.size[0])/cell)
 var rows = int(float(meta.size[1])/cell)
 var n = cols*rows
 var L = sketch.layers
 var to_w = func(p: Vector2) -> Vector2: return origin+p
 var cell_of = func(w: Vector2) -> Vector2i: return Vector2i(((w-origin)/cell).floor())
 var center_of = func(i: int) -> Vector2: return origin+(Vector2(i%cols,i/cols)+Vector2(0.5,0.5))*cell
 var seed = int(meta.get("detail_seed",1))
 step.call(0.02,"Coasts and lakes")
 # --- 1. Land and lakes -------------------------------------------------------------------------
 var t = Time.get_ticks_msec()
 var land = _fill(L.get("land",[]),origin,cell,cols,rows)
 var lakes = _fill(L.get("lakes",[]),origin,cell,cols,rows)
 for i in n: if lakes[i] == 1: land[i] = 0
 var hills = _fill(L.get("hills",[]),origin,cell,cols,rows)
 var forest_mask = _fill(L.get("forests",[]),origin,cell,cols,rows)
 report.times.land = Time.get_ticks_msec()-t
 step.call(0.1,"Mountains, hills and rivers")
 # --- 2. Heights -----------------------------------------------------------------------------------
 t = Time.get_ticks_msec()
 var fn = Synthetic._fnl(seed,0.02*cell,FastNoiseLite.FRACTAL_FBM,4)
 var ridged = Synthetic._fnl(seed+1,0.035*cell,FastNoiseLite.FRACTAL_RIDGED,4)
 var h = PackedFloat32Array()
 h.resize(n)
 var hill_soft = _blur(hills,cols,rows,int(8.0/cell))
 var land_soft = _blur(land,cols,rows,int(6.0/cell))
 for i in n:
  var x = i%cols
  var z = i/cols
  var b = fn.get_noise_2d(x,z)*0.5+0.5
  h[i] = lerpf(-3.0,2.0+b*4.0,land_soft[i])+hill_soft[i]*(4.0+b*7.0)
 # Ranges: ridges along their lines, lumpy, falling off over their width.
 var range_mask = PackedFloat32Array()
 range_mask.resize(n)
 for e in L.get("ranges",[]):
  var height = float(e.data.get("height",40))
  var width = float(e.data.get("width",30))
  var near = _near(e.points,cell,cols,rows,width)
  for i in near:
   var k = exp(-pow(near[i]/(width*0.45),2.0))
   var r = ridged.get_noise_2d(i%cols,i/cols)*0.5+0.5
   h[i] += height*k*(0.55+0.7*r)
   range_mask[i] = maxf(range_mask[i],k)
 # Passes: a valley floor through the range.
 var pass_mask = PackedByteArray()
 pass_mask.resize(n)
 for e in L.get("passes",[]):
  var width = float(e.data.get("width",8))
  var pts = e.points if e.kind == "path" else PackedVector2Array([e.center,e.center+Vector2(0.01,0)])
  var near = _near(pts,cell,cols,rows,width*1.6)
  for i in near:
   var d = near[i]
   var k = 1.0-smoothstep(width*0.5,width*1.6,d)
   h[i] = lerpf(h[i],minf(h[i],12.0+fn.get_noise_2d(i%cols,i/cols)*2.0),k)
   if d<width*0.5: pass_mask[i] = 1
 # Rivers: valleys whose bed only descends from source to mouth.
 var rivers = PackedByteArray()
 rivers.resize(n)
 for e in L.get("rivers",[]):
  var width = float(e.data.get("width",6))
  var near = _near(e.points,cell,cols,rows,width*2.5)
  for i in near:
   var d = near[i]
   var k = 1.0-smoothstep(width*0.5,width*2.5,d)
   h[i] = lerpf(h[i],minf(h[i],0.3+d*0.15),k)
   if d<maxf(width*0.5,cell*0.75): rivers[i] = 255 # the core: water, crossed only at bridges and fords
   elif d<width*0.8: rivers[i] = maxi(rivers[i],140)
 # Settlements: flattened plateaus.
 var sites = {}
 for e in L.get("sites",[]):
  sites[e.id] = to_w.call(e.center)
  var flat = float(e.data.get("flat",9))
  var c = cell_of.call(sites[e.id])
  var ci = clampi(c.y,0,rows-1)*cols+clampi(c.x,0,cols-1)
  var level = maxf(1.2,h[ci])
  var near = _near(PackedVector2Array([e.center,e.center+Vector2(0.01,0)]),cell,cols,rows,flat*1.8)
  for i in near: h[i] = lerpf(h[i],level,1.0-smoothstep(flat,flat*1.8,near[i]))
 report.times.heights = Time.get_ticks_msec()-t
 step.call(0.3,"Regions")
 # --- 3. Regions ------------------------------------------------------------------------------------
 t = Time.get_ticks_msec()
 var region_ids = world.regions.keys()
 region_ids.sort()
 var rid = PackedInt32Array()
 rid.resize(n)
 var pinned = region_ids.filter(func(r): return world.regions[r].has("polygon"))
 for k in region_ids.size():
  var r = world.regions[region_ids[k]]
  if not r.has("polygon"): continue
  var poly = PackedVector2Array()
  for v in r.polygon: poly.append(Vector2(v[0],v[1])-origin)
  var m = _fill([{"points":poly,"closed":true}],origin,cell,cols,rows)
  for i in n: if m[i] == 1 and land[i] == 1: rid[i] = k+1
 if pinned.size()<region_ids.size():
  # Flood fill from the sites of the regions without a pinned outline; ranges slow it, so borders
  # follow the ridges.
  var queue = []
  for k in region_ids.size():
   if pinned.has(region_ids[k]) or not sites.has(region_ids[k]): continue
   var c = cell_of.call(sites[region_ids[k]])
   queue.append(c.y*cols+c.x)
   rid[c.y*cols+c.x] = k+1
  var head = 0
  while head<queue.size():
   var i = queue[head]
   head += 1
   for j in [i-1,i+1,i-cols,i+cols]:
    if j<0 or j>=n or rid[j] != 0 or land[j] == 0: continue
    if absi(j%cols-i%cols)>1: continue
    if range_mask[j]>0.6 and pass_mask[j] == 0 and range_mask[i]<0.6: continue # ridges stop the fill
    rid[j] = rid[i]
    queue.append(j)
  # Ridge cores the fill never entered (mountains and walls between two regions) join the nearest
  # region on either side, so every land cell has a region.
  var front = []
  for i in n:
   if rid[i] == 0: continue
   for j in [i-1,i+1,i-cols,i+cols]:
    if j>=0 and j<n and rid[j] == 0 and land[j] == 1 and absi(j%cols-i%cols)<=1:
     front.append(i)
     break
  head = 0
  while head<front.size():
   var i = front[head]
   head += 1
   for j in [i-1,i+1,i-cols,i+cols]:
    if j<0 or j>=n or rid[j] != 0 or land[j] == 0: continue
    if absi(j%cols-i%cols)>1: continue
    rid[j] = rid[i]
    front.append(j)
 report.times.regions = Time.get_ticks_msec()-t
 step.call(0.45,"Ground, forests and climates")
 # --- 4. Classes ------------------------------------------------------------------------------------
 t = Time.get_ticks_msec()
 var cls = PackedByteArray()
 cls.resize(n)
 var colors = PackedByteArray()
 colors.resize(n*3)
 var pal = [Color("8fae5a"),Color("4f7a38"),Color("a69a5e"),Color("b59a6c"),Color("8a8466"),Color("8a7f72"),Color("3f6f8e")]
 var forest_n = Synthetic._fnl(seed+2,0.05*cell,FastNoiseLite.FRACTAL_FBM,3)
 for i in n:
  var x = i%cols
  var z = i/cols
  var c = OPEN
  if land[i] == 0 or rivers[i] == 255: c = WATER
  else:
   var dx = h[mini(i+1,n-1)]-h[maxi(i-1,0)]
   var dz = h[mini(i+cols,n-1)]-h[maxi(i-cols,0)]
   var slope = sqrt(dx*dx+dz*dz)/(2.0*cell)
   if pass_mask[i] == 1: c = PASS
   elif h[i]>MOUNTAIN_ABOVE or (range_mask[i]>0.5 and slope>0.9): c = MOUNTAIN
   elif h[i]>HILLS_ABOVE or slope>0.5 or hills[i] == 1: c = HILLS
   if c in [OPEN,HILLS] and rivers[i]<128:
    var fd = forest_n.get_noise_2d(x,z)*0.5+0.5
    if forest_mask[i] == 1 and fd>0.35: c = FOREST
  cls[i] = c
 for id in sites:
  var cc = cell_of.call(sites[id])
  if cc.x>=0 and cc.y>=0 and cc.x<cols and cc.y<rows: cls[cc.y*cols+cc.x] = SETTLEMENT
 for i in n:
  var col: Color = pal[cls[i]]
  colors[i*3] = col.r8
  colors[i*3+1] = col.g8
  colors[i*3+2] = col.b8
 report.times.classes = Time.get_ticks_msec()-t
 # Climates (sketch layer "climates", closed shapes with data-climate): ground colours only, in the
 # render cache; the gameplay climate of each region comes with the map's content. Later shapes win.
 var ccols = int(ceil(float(cols)/CLIMATE_STEP))
 var crows = int(ceil(float(rows)/CLIMATE_STEP))
 var clim = PackedFloat32Array()
 clim.resize(ccols*crows*4)
 for e in L.get("climates",[]):
  var cname = str(e.data.get("climate",""))
  if not CLIMATE_TINTS.has(cname):
   report.warnings.append("climate '%s' on '%s' is unknown (known: %s)" % [cname,e.id,", ".join(CLIMATE_TINTS.keys())])
   continue
  var tint: Color = CLIMATE_TINTS[cname]
  var m = _fill([e],origin,cell,cols,rows)
  # The climate's look on the coarse grid (later shapes win).
  var look = CLIMATE_LOOK.get(cname,[0.0,0.0,0.0,0.0])
  for cz in crows:
   for cx in ccols:
    var i0 = mini(rows-1,cz*CLIMATE_STEP+CLIMATE_STEP/2)*cols+mini(cols-1,cx*CLIMATE_STEP+CLIMATE_STEP/2)
    if m[i0] == 0: continue
    for k in 4: clim[(cz*ccols+cx)*4+k] = float(look[k])
  for i in n:
   if m[i] == 0 or cls[i] == WATER: continue
   var base = Color8(colors[i*3],colors[i*3+1],colors[i*3+2])
   var col = base.lerp(tint,0.95 if cls[i] == MOUNTAIN and cname in ["snow","redrock","ash","white"] else 0.72)
   colors[i*3] = col.r8
   colors[i*3+1] = col.g8
   colors[i*3+2] = col.b8
 var climate = _blur_climate(clim,ccols,crows,maxi(1,int(round(CLIMATE_BLUR/(cell*CLIMATE_STEP)))))
 step.call(0.7,"Roads")
 # --- 5. Roads (pinned lines) -------------------------------------------------------------------------
 var road = PackedByteArray()
 road.resize(n)
 var network = []
 var bridges = 0
 for e in L.get("roads",[]):
  var pts = []
  for p in e.points:
   var w = to_w.call(p)
   pts.append([snappedf(w.x,0.1),snappedf(w.y,0.1)])
  network.append({"id":e.id,"points":pts})
  # Roads cross rivers on bridges (the river core under a road becomes open ground); they never
  # run into lakes or the sea. On coarse cells the road keeps at least one cell's width.
  for i in _near(e.points,cell,cols,rows,maxf(1.0,cell*0.75)):
   if cls[i] == WATER and rivers[i] == 255 and land[i] == 1:
    cls[i] = OPEN
    bridges += 1
   if cls[i] != WATER: road[i] = 1
 # Fords (sketch layer "fords", circles): shallow crossings of a river, slow going (pass terrain).
 var fords = 0
 for e in L.get("fords",[]):
  var r = maxf(float(e.get("r",6.0)),cell*1.5)
  for i in _near(PackedVector2Array([e.center,e.center+Vector2(0.01,0)]),cell,cols,rows,r):
   if rivers[i] == 255 and land[i] == 1:
    cls[i] = PASS
    fords += 1
 report.crossings = {"bridge_cells":bridges,"ford_cells":fords}
 var passes = []
 for e in L.get("passes",[]):
  if e.kind != "path": continue
  var pts = []
  for p in e.points:
   var w = to_w.call(p)
   pts.append([snappedf(w.x,0.1),snappedf(w.y,0.1)])
  passes.append({"name":str(e.data.get("name",e.id)),"points":pts,"width":float(e.data.get("width",8))})
 step.call(0.8,"Saving the map")
 # --- 6. Outputs -----------------------------------------------------------------------------------
 t = Time.get_ticks_msec()
 var regions = {}
 var pts_of = {}
 for i in n:
  if rid[i]>0 and (i%cols)%3 == 0 and (i/cols)%3 == 0: pts_of.get_or_add(rid[i],PackedVector2Array()).append(center_of.call(i))
 for k in region_ids.size():
  var id = region_ids[k]
  var r = world.regions[id].duplicate(true)
  var poly = r.get("polygon",[])
  if poly.is_empty() and pts_of.has(k+1):
   var hull = Geometry2D.convex_hull(pts_of[k+1])
   for v in hull.slice(0,hull.size()-1): poly.append([snappedf(v.x,0.1),snappedf(v.y,0.1)])
  var out = {"name":r.get("name",id),"owner":r.get("owner",""),"resources":r.get("resources",{"wood":0,"stone":0,"food":0,"minerals":0}),"polygon":poly}
  if r.has("major") and sites.has(id):
   var m = r.major
   var p = sites[id]
   out.settlement = {"name":m.get("name",out.name),"type":m.get("type","city"),"level":int(m.get("level",1)),"coastal":bool(m.get("port",false)),"position":[snappedf(p.x,0.1),snappedf(p.y,0.1)]}
   for k2 in ["landmark","path"]: if m.has(k2): out.settlement[k2] = m[k2]
  else: out.settlement = null
  regions[id] = out
 if not bakes:
  MapBake.write_render_cache(map_id,cell,origin,cols,rows,h,colors,rivers,climate,ccols,crows)
  report.times.total = Time.get_ticks_msec()-t_all
  return report
 MapBake.write_json(dir+"provinces.json",{"_note":"GENERATED by the map pipeline (map/pipeline.gd) from sketch.svg and world.json; do not edit.","provinces":world.provinces,"regions":regions})
 MapBake.write_json(dir+"movement.json",{"_note":"GENERATED by the map pipeline: pinned roads and passes from sketch.svg.","roads":{"network":network},"passes":{"list":passes}})
 DirAccess.make_dir_recursive_absolute(dir+"baked")
 MapBake.write_regions(dir,cell,origin,cols,rows,rid,region_ids)
 MapBake.write_movement(dir,cell,origin,cols,rows,cls,road)
 MapBake.write_components(dir,MapBake.components_of(cls,cols,rows))
 MapBake.write_parts(dir,MapBake.parts_of(cls,rid,cols,rows))
 var adj = {}
 var site_cells = []
 for k in region_ids.size():
  var p = sites.get(region_ids[k],origin)
  site_cells.append(cell_of.call(p))
 for z in rows:
  for x in cols:
   var i = z*cols+x
   var a = rid[i]
   if a == 0: continue
   if x<cols-1 and rid[i+1] != 0 and rid[i+1] != a: Synthetic._border(adj,a,rid[i+1],i,i+1,cls,site_cells,cols)
   if z<rows-1 and rid[i+cols] != 0 and rid[i+cols] != a: Synthetic._border(adj,a,rid[i+cols],i,i+cols,cls,site_cells,cols)
 var edges = []
 for key in adj:
  if adj[key][1]>=0: edges.append([key/65536-1,key%65536-1,adj[key][1],adj[key][2]])
 MapBake.write_graph(dir,edges)
 MapBake.write_json(dir+"baked/sources.json",{"_note":"Hash of map.json, sketch.svg and world.json when the bakes were built (the validator checks it).","hash":sources_hash(map_id)})
 MapBake.write_render_cache(map_id,cell,origin,cols,rows,h,colors,rivers,climate,ccols,crows)
 report.times.write = Time.get_ticks_msec()-t
 PathHierarchy.build(map_id)
 report.regions = region_ids.size()
 report.cols = cols
 report.rows = rows
 report.times.total = Time.get_ticks_msec()-t_all
 return report

# The coarse climate grid (4 floats per texel) blurred by two box passes of radius r texels along
# each axis (running sums, so the cost does not grow with r), as RGBA8 bytes for the render cache.
static func _blur_climate(src: PackedFloat32Array,w: int,h: int,r: int) -> PackedByteArray:
 var a = src
 for pass_i in 2:
  a = _box(a,w,h,r,true)
  a = _box(a,w,h,r,false)
 var out = PackedByteArray()
 out.resize(a.size())
 for i in a.size(): out[i] = int(round(clampf(a[i],0.0,1.0)*255.0))
 return out

# One box blur along x (rows) or z (columns), edges clamped.
static func _box(a: PackedFloat32Array,w: int,h: int,r: int,along_x: bool) -> PackedFloat32Array:
 var b = PackedFloat32Array()
 b.resize(a.size())
 var lines = h if along_x else w
 var length = w if along_x else h
 var norm = 1.0/(2*r+1)
 var stride = 4 if along_x else w*4
 var last = length-1
 for l in lines:
  for k in 4:
   var base = (l*w*4 if along_x else l*4)+k
   var s = 0.0
   for t in range(-r,r+1): s += a[base+clampi(t,0,last)*stride]
   for t in length:
    b[base+t*stride] = s*norm
    s += a[base+mini(t+r+1,last)*stride]-a[base+maxi(t-r,0)*stride]
 return b

# Closed shapes (sketch elements, SVG coordinates) scanned into a 0/1 mask.
static func _fill(elements: Array,origin: Vector2,cell: float,cols: int,rows: int) -> PackedByteArray:
 var m = PackedByteArray()
 m.resize(cols*rows)
 for e in elements:
  var pts: PackedVector2Array = e.points
  if pts.size()<3: continue
  var lo = INF
  var hi = -INF
  for p in pts:
   lo = minf(lo,p.y)
   hi = maxf(hi,p.y)
  for z in range(maxi(0,int(lo/cell)),mini(rows,int(hi/cell)+1)):
   var y = (z+0.5)*cell
   var xs = []
   for k in pts.size():
    var a = pts[k]
    var b = pts[(k+1)%pts.size()]
    if (a.y<=y and b.y>y) or (b.y<=y and a.y>y): xs.append(a.x+(y-a.y)/(b.y-a.y)*(b.x-a.x))
   xs.sort()
   for k in range(0,xs.size()-1,2):
    for x in range(maxi(0,int(ceil(xs[k]/cell-0.5))),mini(cols-1,int(floor(xs[k+1]/cell-0.5)))+1): m[z*cols+x] = 1
 return m

# {cell index: distance in metres} for every cell within `reach` of a polyline (SVG coordinates).
static func _near(pts: PackedVector2Array,cell: float,cols: int,rows: int,reach: float) -> Dictionary:
 var best = {}
 for k in pts.size()-1:
  var a = pts[k]
  var b = pts[k+1]
  var lo = Vector2i(((a.min(b)-Vector2.ONE*reach)/cell).floor())
  var hi = Vector2i(((a.max(b)+Vector2.ONE*reach)/cell).ceil())
  for z in range(maxi(lo.y,0),mini(hi.y,rows-1)+1):
   for x in range(maxi(lo.x,0),mini(hi.x,cols-1)+1):
    var p = (Vector2(x,z)+Vector2(0.5,0.5))*cell
    var d = p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b))
    if d<=reach:
     var i = z*cols+x
     if d<best.get(i,INF): best[i] = d
 return best

# A 0/1 mask softened to 0-1 over r cells (box blur, separable).
static func _blur(m: PackedByteArray,cols: int,rows: int,r: int) -> PackedFloat32Array:
 var a = PackedFloat32Array()
 a.resize(cols*rows)
 for i in m.size(): a[i] = float(m[i])
 if r<1: return a
 var img = Image.create_from_data(cols,rows,false,Image.FORMAT_RF,a.to_byte_array())
 img.resize(maxi(1,cols/r),maxi(1,rows/r),Image.INTERPOLATE_BILINEAR)
 img.resize(cols,rows,Image.INTERPOLATE_BILINEAR)
 return img.get_data().to_float32_array()
