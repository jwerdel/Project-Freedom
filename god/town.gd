extends Node3D
# Frosthold at character scale for the god-game look test (docs/pivot/god-game.md): the landmark's
# castle (visuals/landmarks/frosthold_visual.gd) and a town of medieval culture-kit houses on
# burgage-style plots along the roads (Manor Lords), a market square with a well, a church, farmsteads
# and strip fields, all built at kit_scale from god/mesh_kit.gd chunks so every wall, roof and tower
# can break apart at its seams.
#  - blocks: one per building (the castle split on a grid); each has a StaticBody3D with one convex
#    shape per chunk, removed as chunks break; a block that loses too much collapses into rubble.
#  - render cells: chunks are drawn merged per CELL metres and per material, rebuilt (a few per
#    frame) when chunks break, so the town costs a few hundred draw calls.
# Gameplay values: none (presentation only); approval here is the look test's stand-in for the
# Where Winds Meet suspicion / Manor Lords approval that a later slice would build for real.

signal block_collapsed(block: int)

const MeshKit = preload("res://god/mesh_kit.gd")
const Materials = preload("res://god/materials.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const K = preload("res://visuals/landmarks/landmark_kit.gd")
const S = preload("res://visuals/kits/cultures/kit_shapes.gd")
const CELL = 32.0
const HASH = 6.0
const COLLAPSE_AT = 0.62 # a block collapses once less than this share of its chunks stands
const REBUILDS_PER_FRAME = 4

var terrain
var kit_scale := 2.0
var castle := Vector2(0,-40)
var chunks: Array = []
var blocks: Array = []
var cells = {}
var grid = {}
var dirty_cells = {}
var roads: Array = [] # PackedVector2Array polylines
var road_graph = {"points":PackedVector2Array(),"links":[]} # villager paths: points and neighbour lists
var homes: Array = [] # block ids
var well := Vector3.ZERO
var market := Vector3.ZERO
var church := Vector3.ZERO
var field_spots: Array = [] # Vector3 work spots in the fields
var springs: Array = [] # Vector3 hot springs (steam)
var plots: Array = [] # {pos: Vector2, yaw, kind}
var approval := 72.0
var approval_cap := 100.0
var debris # god/debris.gd
var rng := RandomNumberGenerator.new()
var rubble_root: Node3D
var chimneys: Array = [] # Vector3 chimney tops (smoke)

# --- Layout (before the terrain meshes: plots flatten the ground) ---------------------------------

func layout(t,seed: int):
 terrain = t
 rng.seed = seed
 castle = terrain.castle
 var ch = terrain.height_at(castle.x,castle.y)
 terrain.flatten(castle,40.0,ch,25.0)
 # Roads leave the castle gates (south +z, north -z) and branch east and west below the market.
 var south = _road(castle+Vector2(0,60),PI*0.5,1180.0,0.0025,11)
 var north = _road(castle+Vector2(0,-60),-PI*0.5,1180.0,0.003,23)
 var market2 = south[int(70.0/8.0)]
 var east = _road(south[int(95.0/8.0)],0.15,1250.0,0.004,37)
 var west = _road(south[int(150.0/8.0)],PI-0.25,1250.0,0.0035,41)
 var lane_ne = _road(north[int(70.0/8.0)],-0.35,420.0,0.006,53)
 var lane_nw = _road(north[int(90.0/8.0)],PI+0.45,380.0,0.006,59)
 var lane_s = _road(east[int(120.0/8.0)],PI*0.5+0.2,360.0,0.006,61)
 roads = [south,north,east,west,lane_ne,lane_nw,lane_s]
 for r in roads:
  terrain.paint_line(r,5.5,0,1.0)
  terrain.paint_line(r,9.0,1,0.55)
 # The market square on the south road, the well at its centre, the church beside it.
 var mh = terrain.height_at(market2.x,market2.y)
 terrain.flatten(market2,22.0,mh,10.0)
 terrain.paint_disc(market2,19.0,3,1.0,4.0)
 market = Vector3(market2.x,mh,market2.y)
 well = market+Vector3(4.0,0,-2.0)
 var cp = market2+Vector2(42.0,8.0)
 church = Vector3(cp.x,0,cp.y)
 terrain.flatten_rect(cp,Vector2(6.0,13.0),0.0,terrain.height_at(cp.x,cp.y),5.0)
 terrain.paint_disc(market2.lerp(cp,0.5),6.0,1,0.8)
 # The castle court is paved.
 terrain.paint_disc(castle,30.0,3,0.9,6.0)
 # Plots along the roads.
 _plots_along(south,6.0,1.0)
 _plots_along(east,6.0,1.0)
 _plots_along(west,6.0,1.0)
 _plots_along(north,6.0,0.8)
 _plots_along(lane_ne,5.5,0.8)
 _plots_along(lane_nw,5.5,0.8)
 _plots_along(lane_s,5.5,0.8)
 # Farmsteads and strip fields beyond the town.
 for r in [south,east,west,north]: _farms_along(r)
 for p in plots:
  var h = _plot_height(p)
  p.h = h
  terrain.flatten_rect(p.pos,p.half+Vector2(1.0,1.0),p.yaw,h,4.0)
  terrain.paint_rect(p.pos,p.half+Vector2(1.5,1.5),p.yaw,1,0.45)
  if p.kind == "house": _backyard_paint(p)
 _build_road_graph()

func _plot_height(p: Dictionary) -> float:
 var s = 0.0
 var cs = cos(p.yaw)
 var sn = sin(p.yaw)
 for o in [Vector2.ZERO,Vector2(p.half.x,p.half.y),Vector2(-p.half.x,p.half.y),Vector2(p.half.x,-p.half.y),Vector2(-p.half.x,-p.half.y)]:
  var w = Vector2(o.x*cs+o.y*sn,-o.x*sn+o.y*cs)+p.pos
  s += terrain.height_at(w.x,w.y)
 return s/5.0

# A road from p heading `angle` (x = cos, z = sin) for `length` metres, wandering with noise and
# leaning away from the castle; 8 m steps.
func _road(p: Vector2,angle: float,length: float,wander: float,seed: int) -> PackedVector2Array:
 var nz = FastNoiseLite.new()
 nz.seed = seed
 nz.frequency = wander
 var pts = PackedVector2Array([p])
 var a = angle
 var d = 0.0
 while d<length:
  a = angle+nz.get_noise_1d(d)*0.9
  var np = pts[pts.size()-1]+Vector2(cos(a),sin(a))*8.0
  if not terrain.inside(np.x,np.y,4.0): break
  pts.append(np)
  d += 8.0
 return pts

func _near_road(p: Vector2,clear: float,skip = null) -> bool:
 for r in roads:
  if r == skip: continue
  for k in r.size()-1:
   if Geometry2D.get_closest_point_to_segment(p,r[k],r[k+1]).distance_to(p)<clear: return true
 return false

func _free_spot(p: Vector2,r: float) -> bool:
 if p.distance_to(castle)<70.0+r: return false
 if p.distance_to(Vector2(market.x,market.z))<24.0+r: return false
 if p.distance_to(Vector2(church.x,church.z))<16.0+r: return false
 for q in plots:
  if q.pos.distance_to(p)<q.radius+r: return false
 return true

func _plots_along(road: PackedVector2Array,setback: float,density: float):
 var d = 0.0
 var k = 0
 while k<road.size()-2:
  var a = road[k]
  var b = road[k+1]
  var dir = (b-a).normalized()
  var normal = Vector2(-dir.y,dir.x)
  for side in [-1.0,1.0]:
   var dist_c = a.distance_to(castle)
   if dist_c>430.0 or rng.randf()>density*(1.0-smoothstep(220.0,430.0,dist_c)*0.7): continue
   var kind_roll = rng.randf()
   var piece = "house_1"
   if dist_c<180.0 and kind_roll<0.3: piece = "tall"
   elif kind_roll<0.6: piece = "house_2"
   elif kind_roll<0.8: piece = "house_3"
   var half = Vector2(3.6,3.0) if piece != "tall" else Vector2(3.2,3.2)
   var sb = setback+half.y+rng.randf_range(0.0,1.5)
   var pos = a+dir*rng.randf_range(0.0,3.0)+normal*side*sb
   if not terrain.inside(pos.x,pos.y,30.0) or not _free_spot(pos,6.5) or _near_road(pos,sb-0.8,road): continue
   if terrain.normal_at(pos.x,pos.y).y<0.94: continue
   # The door (kit +z) faces the road.
   var face = -normal*side
   var yaw = atan2(face.x,face.y)+rng.randf_range(-0.06,0.06)
   plots.append({"pos":pos,"yaw":yaw,"kind":"house","piece":piece,"half":half,"radius":6.5,"face":face})
  k += maxi(1,int(rng.randf_range(10.0,14.0)/8.0+0.5))

func _farms_along(road: PackedVector2Array):
 var k = int(440.0/8.0)
 while k<road.size()-4:
  var a = road[k]
  var b = road[k+1]
  var dir = (b-a).normalized()
  var normal = Vector2(-dir.y,dir.x)
  var side = -1.0 if rng.randf()<0.5 else 1.0
  if a.distance_to(castle)<1000.0 and rng.randf()<0.55:
   var pos = a+normal*side*16.0
   if terrain.inside(pos.x,pos.y,60.0) and _free_spot(pos,14.0) and not _near_road(pos,12.0,road) and not _forest(pos):
    var face = -normal*side
    plots.append({"pos":pos,"yaw":atan2(face.x,face.y),"kind":"farm","piece":"path_farming","half":Vector2(6.0,5.0),"radius":14.0,"face":face})
    # Strip fields behind the farm (long strips at right angles to the road).
    for s in 4:
     var fc = pos+normal*side*(70.0)+dir*(s-1.5)*24.0
     if not terrain.inside(fc.x,fc.y,40.0) or _forest(fc) or _near_road(fc,40.0,null): continue
     terrain.paint_rect(fc,Vector2(10.5,46.0),atan2(dir.x,dir.y),2,1.0)
     field_spots.append(Vector3(fc.x,terrain.height_at(fc.x,fc.y),fc.y))
  k += rng.randi_range(5,9)

var forest_fn: Callable
func _forest(p: Vector2) -> bool:
 return forest_fn.is_valid() and forest_fn.call(p.x,p.y)

func _backyard_paint(p: Dictionary):
 # Behind the house: a garden patch (bare soil) inside a fenced yard.
 var back = -p.face
 var yc = p.pos+back*(p.half.y+7.0)
 terrain.paint_rect(yc,Vector2(4.5,6.0),p.yaw,1,0.8)
 p.yard = yc

func _build_road_graph():
 var pts = PackedVector2Array()
 var links = []
 var index = {}
 for r in roads:
  var prev = -1
  for q in r:
   var key = Vector2i(roundi(q.x/4.0),roundi(q.y/4.0))
   var id = index.get(key,-1)
   if id<0:
    # Join junctions: snap to an existing point within 6 m.
    for j in pts.size():
     if pts[j].distance_to(q)<6.0:
      id = j
      break
   if id<0:
    id = pts.size()
    pts.append(q)
    links.append([])
   index[key] = id
   if prev>=0 and prev != id:
    if not links[prev].has(id): links[prev].append(id)
    if not links[id].has(prev): links[id].append(prev)
   prev = id
 road_graph = {"points":pts,"links":links}

# --- Building (after the terrain is final) --------------------------------------------------------

func build():
 rubble_root = Node3D.new()
 rubble_root.name = "Rubble"
 add_child(rubble_root)
 var t0 = Time.get_ticks_msec()
 _build_castle()
 for p in plots:
  var id = _piece_block("kit.medieval."+p.piece,p.pos,p.yaw,p.h-0.12,p.kind)
  blocks[id].door = Vector3(p.pos.x,p.h,p.pos.y)+Vector3(p.face.x,0,p.face.y)*(p.half.y+1.2)
  if p.kind == "house":
   homes.append(id)
   if p.has("yard"): _yard(id,p)
 _church()
 _market_stalls()
 _well()
 for c in cells: _rebuild_cell(c)
 dirty_cells.clear()
 print("GODTEST town: %d blocks, %d chunks, %d homes, %d cells in %d ms" % [blocks.size(),chunks.size(),homes.size(),cells.size(),Time.get_ticks_msec()-t0])

# Height lookup for the landmark at campaign scale, in its own space (origin under the castle).
func _h_campaign(x: float,z: float) -> float:
 return terrain.height_at(castle.x+x*kit_scale,castle.y+z*kit_scale)/kit_scale

func _build_castle():
 var lm = load("res://visuals/landmarks/frosthold_visual.gd").new()
 lm.stage = 2
 lm.h = Callable(self,"_h_campaign")
 lm.make()
 # Stage 3's spires and greenhouse (its scattered houses are replaced by the town above).
 var c = lm.at(0,0)
 for s in [-1.0,1.0]: K.spire(lm,c+Vector3(-3.0+s*3.0,14.0,-6.0),1.0,10.0,lm.STONE,lm.SLATE)
 S.box(lm,Vector3(6.0,2.8,3.2),lm.at(-9.0,6.0),Color("9ec8b8"))
 for p in [Vector3(4.0,0,-8.0),Vector3(-10.0,0,8.0),Vector3(2.0,0,10.0)]:
  var w = Vector2(castle.x+p.x*kit_scale,castle.y+p.z*kit_scale)
  springs.append(Vector3(w.x,terrain.height_at(w.x,w.y)+0.6,w.y))
 var xf = Transform3D(Basis().scaled(Vector3.ONE*kit_scale),Vector3(castle.x,0,castle.y))
 var list = MeshKit.collect(lm,xf,terrain.height_at(castle.x,castle.y)-2.0,"stone")
 lm.free()
 # Split the castle into blocks on a 12 m grid (each falls on its own).
 var groups = {}
 for ch in list:
  var k = Vector2i(floori(ch.center.x/12.0),floori(ch.center.z/12.0))
  if not groups.has(k): groups[k] = []
  groups[k].append(ch)
 for k in groups: _add_block(groups[k],"castle")

func _piece_block(id: String,pos: Vector2,yaw: float,y: float,kind: String) -> int:
 var node = AssetManifest.instantiate(id)
 var xf = Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*kit_scale),Vector3(pos.x,y,pos.y))
 var list = MeshKit.collect(node,xf,y)
 # Chimney tops smoke (the kit's chimneys are the small stone boxes on the roof).
 for mi in node.find_children("*","MeshInstance3D",true,false):
  if mi.mesh is BoxMesh and absf((mi.mesh as BoxMesh).size.x-0.52)<0.01: chimneys.append(xf*(mi.position+Vector3(0,0.12,0)))
 node.free()
 if kind in ["house","farm"] and not MeshKit.Builder.flat_mode: _vary(list)
 return _add_block(list,kind,yaw)

# A fenced backyard behind a house: posts and two rails on three sides, a woodpile.
func _yard(block: int,p: Dictionary):
 var root = Node3D.new()
 var w = 4.5
 var d = 6.0
 var timber = Color("5e432c")
 for side in [[Vector2(-w,-d),Vector2(-w,d)],[Vector2(w,-d),Vector2(w,d)],[Vector2(-w,d),Vector2(w,d)]]:
  var a = side[0]
  var b = side[1]
  var len = a.distance_to(b)
  var n = int(len/2.5)
  for i in n+1:
   var q = a.lerp(b,float(i)/n)
   S.box(root,Vector3(0.12,1.15,0.12),Vector3(q.x,0,q.y),timber.darkened(0.1))
  for y in [0.45,0.95]:
   var m = (a+b)*0.5
   var rail = S.box(root,Vector3(0.07,0.07,len) if a.x == b.x else Vector3(len,0.07,0.07),Vector3(m.x,y,m.y),timber)
 for j in 3: S.cylinder(root,0.16,0.16,1.6,Vector3(-w+0.8,0.16+j*0.3,-d+1.2+j*0.05),Color("7a5636"),6,Vector3(0,0,PI*0.5))
 var back = -p.face
 var yc = p.yard
 var yaw = p.yaw
 var y = terrain.height_at(yc.x,yc.y)
 var xf = Transform3D(Basis(Vector3.UP,yaw),Vector3(yc.x,y,yc.y))
 var list = MeshKit.collect(root,xf,y)
 root.free()
 _merge_into(block,list)

func _church():
 var id = _piece_block("kit.medieval.temple",Vector2(church.x,church.z),0.0,terrain.height_at(church.x,church.z)-0.15,"church")
 blocks[id].door = Vector3(church.x,terrain.height_at(church.x,church.z+20.0),church.z+20.0)

func _market_stalls():
 var m2 = Vector2(market.x,market.z)
 var id = _piece_block("kit.medieval.path_market",m2+Vector2(-6.0,-6.0),0.3,market.y-0.1,"market")
 blocks[id].door = market
 for i in 6:
  var a = i*TAU/6.0+0.4
  var p = m2+Vector2(cos(a),sin(a))*13.0
  var root = Node3D.new()
  for x in [-1.1,1.1]:
   for z in [-0.7,0.7]: S.box(root,Vector3(0.1,1.3,0.1),Vector3(x,0,z),Color("5e432c"))
  S.box(root,Vector3(2.3,0.5,1.2),Vector3(0,0,0.2),Color("6b4c30"))
  S.box(root,Vector3(2.6,0.06,1.7),Vector3(0,1.3,0),[Color("8a3a2c"),Color("3c5a7a"),Color("a8883c"),Color("4c6a3c")][i%4],Vector3(0.25,0,0))
  var y = terrain.height_at(p.x,p.y)
  var list = MeshKit.collect(root,Transform3D(Basis(Vector3.UP,-a+PI*0.5).scaled(Vector3.ONE*kit_scale),Vector3(p.x,y-0.05,p.y)),y)
  root.free()
  _add_block(list,"stall")

func _well():
 var root = Node3D.new()
 var stone = Color("8a8680")
 S.cylinder(root,0.75,0.8,0.55,Vector3.ZERO,stone,10)
 S.cylinder(root,0.55,0.55,0.56,Vector3(0,0.02,0),Color("1e1a16"),10)
 for x in [-0.7,0.7]: S.box(root,Vector3(0.12,1.5,0.12),Vector3(x,0.5,0),Color("5e432c"))
 S.box(root,Vector3(1.6,0.1,0.1),Vector3(0,1.9,0),Color("5e432c"))
 S.gable(root,1.9,1.3,0.55,Vector3(0,2.0,0),Color("4e5868"))
 var list = MeshKit.collect(root,Transform3D(Basis().scaled(Vector3.ONE*kit_scale),well),well.y)
 root.free()
 _add_block(list,"well")

func _add_block(list: Array,kind: String,yaw := 0.0) -> int:
 var id = blocks.size()
 var body = StaticBody3D.new()
 body.collision_layer = 2
 body.collision_mask = 0
 body.set_meta("block",id)
 add_child(body)
 var b = {"kind":kind,"chunks":PackedInt32Array(),"alive":0,"total":0,"body":body,"ruined":false,"center":Vector3.ZERO,"radius":0.0,"door":Vector3.ZERO,"yaw":yaw}
 blocks.append(b)
 _merge_into(id,list)
 return id

func _merge_into(id: int,list: Array):
 var b = blocks[id]
 var center = b.center*b.total
 for ch in list:
  var ci = chunks.size()
  ch.block = id
  ch.owner = -1
  var sz: Vector3 = ch.size
  if not ch.has("trim") and (minf(sz.x,minf(sz.y,sz.z))>0.2 or sz.length()>2.5):
   var shape = ConvexPolygonShape3D.new()
   var pts = PackedVector3Array()
   for q in ch.hull: pts.append(q+ch.center)
   shape.points = pts
   ch.shape = shape
   var owner = b.body.create_shape_owner(b.body)
   b.body.shape_owner_add_shape(owner,shape)
   ch.owner = owner
  chunks.append(ch)
  b.chunks.append(ci)
  center += ch.center
  b.total += 1
  b.alive += 1
  var cell = Vector2i(floori(ch.center.x/CELL),floori(ch.center.z/CELL))
  ch.cell = cell
  if not cells.has(cell): cells[cell] = {"mi":null,"chunks":PackedInt32Array()}
  cells[cell].chunks.append(ci)
  dirty_cells[cell] = true
  var hk = Vector2i(floori(ch.center.x/HASH),floori(ch.center.z/HASH))
  if not grid.has(hk): grid[hk] = PackedInt32Array()
  grid[hk].append(ci)
 b.center = center/maxf(1.0,b.total)
 var r = 0.0
 for ci in b.chunks: r = maxf(r,Vector2(chunks[ci].center.x,chunks[ci].center.z).distance_to(Vector2(b.center.x,b.center.z)))
 b.radius = r+2.0

# --- Drawing ----------------------------------------------------------------------------------------

func _rebuild_cell(key: Vector2i):
 var cell = cells[key]
 var per = {}
 for ci in cell.chunks:
  var ch = chunks[ci]
  if not ch.alive: continue
  if not per.has(ch.m): per[ch.m] = [PackedVector3Array(),PackedVector3Array(),PackedVector2Array(),PackedFloat32Array(),PackedColorArray()]
  var a = per[ch.m]
  a[0].append_array(ch.v)
  a[1].append_array(ch.n)
  a[2].append_array(ch.uv)
  a[3].append_array(ch.t)
  a[4].append_array(ch.c)
 if cell.mi == null:
  cell.mi = MeshInstance3D.new()
  add_child(cell.mi)
 if per.is_empty():
  cell.mi.mesh = null
  return
 var mesh = ArrayMesh.new()
 for m in per:
  var arr = []
  arr.resize(Mesh.ARRAY_MAX)
  arr[Mesh.ARRAY_VERTEX] = per[m][0]
  arr[Mesh.ARRAY_NORMAL] = per[m][1]
  arr[Mesh.ARRAY_TEX_UV] = per[m][2]
  arr[Mesh.ARRAY_TANGENT] = per[m][3]
  arr[Mesh.ARRAY_COLOR] = per[m][4]
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
  mesh.surface_set_material(mesh.get_surface_count()-1,Materials.surface(m))
 cell.mi.mesh = mesh

# Debris and rubble are spawned from a queue within a per-frame budget, so a blast that breaks
# hundreds of chunks spreads its cost over a few frames (behind the dust) instead of one long frame.
var work: Array = []
const WORK_BUDGET_USEC = 4000

func _fly(ci: int,v: Vector3,dist: float,origin: Vector3,drop: bool):
 if debris == null: return
 if not debris.spawn(self,ci,v,dist) and drop: debris.drop_rubble(self,ci,origin)

func _process(_delta):
 var t0 = Time.get_ticks_usec()
 while not work.is_empty() and Time.get_ticks_usec()-t0<WORK_BUDGET_USEC: work.pop_front().call()
 var n = 0
 for k in dirty_cells.keys():
  _rebuild_cell(k)
  dirty_cells.erase(k)
  n += 1
  if n>=REBUILDS_PER_FRAME: break
 approval = minf(approval_cap,approval+_delta*0.15)

# A single chunk as its own mesh, centred on the chunk (debris).
func chunk_mesh(ci: int) -> ArrayMesh:
 var ch = chunks[ci]
 var v = PackedVector3Array()
 v.resize(ch.v.size())
 for i in ch.v.size(): v[i] = ch.v[i]-ch.center
 var arr = []
 arr.resize(Mesh.ARRAY_MAX)
 arr[Mesh.ARRAY_VERTEX] = v
 arr[Mesh.ARRAY_NORMAL] = ch.n
 arr[Mesh.ARRAY_TEX_UV] = ch.uv
 arr[Mesh.ARRAY_TANGENT] = ch.t
 arr[Mesh.ARRAY_COLOR] = ch.c
 var mesh = ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
 mesh.surface_set_material(0,Materials.surface(ch.m))
 return mesh

# --- Destruction --------------------------------------------------------------------------------------

func chunks_in_sphere(c: Vector3,r: float) -> Array:
 var out = []
 var r2 = r*r
 for gx in range(floori((c.x-r)/HASH),floori((c.x+r)/HASH)+1):
  for gz in range(floori((c.z-r)/HASH),floori((c.z+r)/HASH)+1):
   var g = grid.get(Vector2i(gx,gz))
   if g == null: continue
   for ci in g:
    var ch = chunks[ci]
    if ch.alive and ch.center.distance_squared_to(c)<=r2+ch.size.length_squared()*0.25: out.append(ci)
 return out

# The chunks in a cone from `origin` along `dir` (unit) out to `range`, cos_half the half-angle cosine.
func chunks_in_cone(origin: Vector3,dir: Vector3,range: float,cos_half: float) -> Array:
 var out = []
 for ci in chunks_in_sphere(origin+dir*range*0.5,range*0.5+2.0)+chunks_in_sphere(origin,range*0.5):
  var d = chunks[ci].center-origin
  var l = d.length()
  if l>range or l<0.01: continue
  if d.normalized().dot(dir)>=cos_half-clampf(4.0/l,0.0,0.6): out.append(ci)
 var seen = {}
 var uniq = []
 for ci in out:
  if not seen.has(ci):
   seen[ci] = true
   uniq.append(ci)
 return uniq

# Break chunks: each loses its collision and leaves the drawn cell; the nearest become physics
# debris (debris.gd caps them), the rest fall as rubble or vanish in the dust. A block that would drop
# below COLLAPSE_AT collapses whole (its collision body goes at once, cheaper than shape by shape).
# force_collapse: blocks whose centre lies within that radius of origin collapse regardless.
# Returns {broken, collapsed, centers (a sample for effects), mats, ruins (collapsed block centres)}.
func break_chunks(ids: Array,origin: Vector3,impulse: float,up := 0.35,force_collapse := 0.0) -> Dictionary:
 ids.sort_custom(func(a,b): return chunks[a].center.distance_squared_to(origin)<chunks[b].center.distance_squared_to(origin))
 var hits = {}
 for ci in ids:
  if chunks[ci].alive: hits[chunks[ci].block] = hits.get(chunks[ci].block,0)+1
 var falling = {}
 for b in hits:
  var blk = blocks[b]
  if blk.ruined: continue
  var near = force_collapse>0.0 and Vector2(blk.center.x-origin.x,blk.center.z-origin.z).length()<force_collapse
  if near or float(blk.alive-hits[b])/maxf(1.0,blk.total)<COLLAPSE_AT: falling[b] = true
 var centers = []
 var mats = {}
 var broken = 0
 var reshaped = {}
 for b in falling:
  blocks[b].body.queue_free()
  blocks[b].body = null
 for ci in ids:
  var ch = chunks[ci]
  if not ch.alive: continue
  _kill(ci,false)
  if not falling.has(ch.block): reshaped[ch.block] = true
  broken += 1
  if centers.size()<48: centers.append(ch.center)
  mats[ch.m] = mats.get(ch.m,0)+1
  var d = ch.center-origin
  var dist = maxf(1.0,d.length())
  var v = (d.normalized()+Vector3(0,up,0)).normalized()*impulse*clampf(14.0/dist,0.25,1.6)*rng.randf_range(0.6,1.2)
  work.append(_fly.bind(ci,v,dist,origin,true))
 # Standing blocks that lost chunks: rebuild their collision once (one compound build, rather than
 # one per removed shape).
 for b in reshaped: _rebody(b)
 var ruins = []
 for b in falling:
  collapse(b,origin,impulse*0.35)
  ruins.append(blocks[b].center)
 approval = maxf(0.0,approval-broken*0.004-falling.size()*0.9)
 return {"broken":broken,"collapsed":falling.size(),"centers":centers,"mats":mats,"ruins":ruins}

func _kill(ci: int,remove_shape := true):
 var ch = chunks[ci]
 ch.alive = false
 var b = blocks[ch.block]
 b.alive -= 1
 if ch.owner>=0 and b.body != null and remove_shape:
  b.body.remove_shape_owner(ch.owner)
  ch.owner = -1
 dirty_cells[ch.cell] = true

# The whole block comes down: its standing chunks fall where they stand (a few as debris pushed by
# the blast), the rest heap into a rubble pile.
func collapse(b: int,origin: Vector3,impulse: float):
 var blk = blocks[b]
 if blk.ruined: return
 blk.ruined = true
 if blk.body != null:
  blk.body.queue_free()
  blk.body = null
 var rest = []
 for ci in blk.chunks: if chunks[ci].alive: rest.append(ci)
 rest.sort_custom(func(x,y): return chunks[x].center.y<chunks[y].center.y)
 var spawned = 0
 for ci in rest:
  _kill(ci)
  var ch = chunks[ci]
  var d = ch.center-origin
  var v = d.normalized()*impulse*rng.randf_range(0.1,0.5)+Vector3(rng.randf_range(-2,2),rng.randf_range(-1,2),rng.randf_range(-2,2))
  if spawned<26 and rng.randf()<0.35:
   work.append(_fly.bind(ci,v,d.length(),origin,false))
   spawned += 1
 work.append(_rubble_pile.bind(b,rest))
 approval_cap = maxf(35.0,approval_cap-0.8)
 block_collapsed.emit(b)

func _rubble_pile(b: int,ids: Array):
 var blk = blocks[b]
 var per = {}
 var c = blk.center
 var gy = terrain.height_at(c.x,c.z)
 var r = clampf(blk.radius*0.6,2.0,7.0)
 var mh = clampf(0.4+r*0.1,0.5,1.2)
 var count = 0
 for ci in ids:
  if rng.randf()>0.55 or count>70: continue
  count += 1
  var ch = chunks[ci]
  var a = rng.randf()*TAU
  var rr = sqrt(rng.randf())*r
  var p = Vector3(c.x+cos(a)*rr,0,c.z+sin(a)*rr)
  p.y = terrain.height_at(p.x,p.z)+_mound_h(rr/r,mh)+rng.randf_range(-0.1,0.3)
  var basis = Basis.from_euler(Vector3(rng.randf_range(-1.2,1.2),rng.randf()*TAU,rng.randf_range(-1.2,1.2))).scaled(Vector3.ONE*rng.randf_range(0.35,0.65))
  if not per.has(ch.m): per[ch.m] = [PackedVector3Array(),PackedVector3Array(),PackedVector2Array(),PackedFloat32Array(),PackedColorArray()]
  var arr = per[ch.m]
  for i in ch.v.size():
   arr[0].append(basis*(ch.v[i]-ch.center)+p)
   arr[1].append((basis*ch.n[i]).normalized())
   arr[2].append(ch.uv[i])
   var t = basis*Vector3(ch.t[i*4],ch.t[i*4+1],ch.t[i*4+2])
   arr[3].append_array([t.x,t.y,t.z,ch.t[i*4+3]])
   arr[4].append(Color(ch.c[i].r*0.8,ch.c[i].g*0.78,ch.c[i].b*0.75,0.0))
 # A low, uneven mound of broken stone and earth under the heap.
 rubble_root.add_child(_mound(c,r,mh))
 if per.is_empty(): return
 var mesh = ArrayMesh.new()
 for m in per:
  var a2 = []
  a2.resize(Mesh.ARRAY_MAX)
  a2[Mesh.ARRAY_VERTEX] = per[m][0]
  a2[Mesh.ARRAY_NORMAL] = per[m][1]
  a2[Mesh.ARRAY_TEX_UV] = per[m][2]
  a2[Mesh.ARRAY_TANGENT] = per[m][3]
  a2[Mesh.ARRAY_COLOR] = per[m][4]
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a2)
  mesh.surface_set_material(mesh.get_surface_count()-1,Materials.surface(m))
 var mi = MeshInstance3D.new()
 mi.mesh = mesh
 rubble_root.add_child(mi)

static var _mound_m: ShaderMaterial
func _mound_mat() -> ShaderMaterial:
 if _mound_m == null:
  _mound_m = ShaderMaterial.new()
  _mound_m.shader = load("res://god/surface.gdshader")
  _mound_m.set_shader_parameter("albedo_tex",Materials.tex("rustic_stone_wall","diff"))
  _mound_m.set_shader_parameter("normal_tex",Materials.tex("rustic_stone_wall","nor_gl"))
  _mound_m.set_shader_parameter("arm_tex",Materials.tex("rustic_stone_wall","arm"))
  _mound_m.set_shader_parameter("tint",Vector3(0.55,0.53,0.5))
  _mound_m.set_shader_parameter("saturation",0.5)
  _mound_m.set_shader_parameter("snow_tex",Materials.tex("snow_02","diff"))
  _mound_m.set_shader_parameter("snow_n",Materials.tex("snow_02","nor_gl"))
  _mound_m.set_shader_parameter("snow",0.12)
  _mound_m.set_shader_parameter("grime",0.0)
 return _mound_m

func _mound_h(t: float,mh: float) -> float:
 return mh*pow(maxf(0.0,1.0-t*t),1.3)

# The mound: a disc of rings, heights falling off to the edge with noise, UVs in world metres.
func _mound(c: Vector3,r: float,mh: float) -> MeshInstance3D:
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rings = 6
 var segs = 18
 var pts = []
 for j in rings+1:
  var row = []
  for i in segs:
   var t = float(j)/rings
   var a = TAU*i/segs
   var wob = 1.0+rng.randf_range(-0.18,0.18)*t
   var x = c.x+cos(a)*r*t*wob
   var z = c.z+sin(a)*r*t*wob
   var y = terrain.height_at(x,z)+_mound_h(t,mh)*rng.randf_range(0.75,1.25)-0.15*t
   row.append(Vector3(x,y,z))
  pts.append(row)
 for j in rings:
  for i in segs:
   var a = pts[j][i]
   var b = pts[j][(i+1)%segs]
   var d = pts[j+1][(i+1)%segs]
   var e = pts[j+1][i]
   for q in [a,e,d,a,d,b]:
    st.set_uv(Vector2(q.x,q.z)*0.7)
    st.set_color(Color(0.8,0.76,0.72,1.0))
    st.add_vertex(q)
 st.generate_normals()
 st.generate_tangents()
 var mi = MeshInstance3D.new()
 mi.mesh = st.commit()
 mi.material_override = _mound_mat()
 return mi

func stats() -> Dictionary:
 var alive = 0
 for ch in chunks: if ch.alive: alive += 1
 var ruined = 0
 for b in blocks: if b.ruined: ruined += 1
 return {"chunks":chunks.size(),"alive":alive,"blocks":blocks.size(),"ruined":ruined}

# R: everything stands again (chunks, collision, cells), rubble and approval reset.
func reset():
 work.clear()
 for c in rubble_root.get_children(): c.queue_free()
 for b in blocks.size():
  var blk = blocks[b]
  if blk.body != null: blk.body.queue_free()
  var body = StaticBody3D.new()
  body.collision_layer = 2
  body.collision_mask = 0
  body.set_meta("block",b)
  add_child(body)
  blk.body = body
  blk.ruined = false
  blk.alive = blk.total
  for ci in blk.chunks:
   var ch = chunks[ci]
   ch.alive = true
   ch.owner = -1
   if ch.has("shape"):
    var owner = body.create_shape_owner(body)
    body.shape_owner_add_shape(owner,ch.shape)
    ch.owner = owner
 for k in cells: _rebuild_cell(k)
 dirty_cells.clear()
 approval = 72.0
 approval_cap = 100.0

# A fresh collision body for a block from its standing chunks.
func _rebody(b: int):
 var blk = blocks[b]
 if blk.body != null: blk.body.queue_free()
 var body = StaticBody3D.new()
 body.collision_layer = 2
 body.collision_mask = 0
 body.set_meta("block",b)
 add_child(body)
 blk.body = body
 for ci in blk.chunks:
  var ch = chunks[ci]
  ch.owner = -1
  if ch.alive and ch.has("shape"):
   var owner = body.create_shape_owner(body)
   body.shape_owner_add_shape(owner,ch.shape)
   ch.owner = owner

# Each house its own: some roofs thatched instead of slate, the plaster limewashed in a different
# shade, the timbers older or newer (Manor Lords villages never repeat a house exactly).
const PLASTERS = [Color(1.0,0.99,0.97),Color(0.92,0.9,0.86),Color(0.84,0.83,0.81),Color(0.95,0.92,0.87),Color(0.88,0.85,0.8)]
func _vary(list: Array):
 var thatch = rng.randf()<0.38
 var plaster = PLASTERS[rng.randi_range(0,PLASTERS.size()-1)]
 var timber = rng.randf_range(0.7,1.1)
 var slate = MeshKit.mat_id("slate")
 var th = MeshKit.mat_id("thatch")
 var pl = MeshKit.mat_id("plaster")
 var tm = MeshKit.mat_id("timber")
 for ch in list:
  if thatch and ch.m == slate: ch.m = th
  var mul = Color(1,1,1)
  if ch.m == pl: mul = plaster
  elif ch.m == tm: mul = Color(timber,timber*0.97,timber*0.94)
  if mul == Color(1,1,1): continue
  for i in ch.c.size(): ch.c[i] = Color(ch.c[i].r*mul.r,ch.c[i].g*mul.g,ch.c[i].b*mul.b,ch.c[i].a)
