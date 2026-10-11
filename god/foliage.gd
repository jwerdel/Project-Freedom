extends Node3D
# Trees, grass, rocks and props of the god-game look test.
#  - Trees: the CC0 Poly Haven fir (assets/fir_optimized.glb, three variants) stretched into tall
#    firs, planted on the campaign map's forest cells and in clumps on open ground, kept off roads,
#    plots and fields. Per 150 m chunk one MultiMesh per variant near the camera (snow on the
#    branches, wind) and crossed-quad impostors (rendered from the model at start) beyond.
#    Punches flatten them (knock_down).
#  - Grass: procedural dry tufts poking out of the snow, in 32 m tiles built around the camera.
#  - Rocks (CC0 Poly Haven moss rock sets) on slopes and in the forest; props (barrels, crates,
#    buckets, stumps) by the houses and the market.

const SAPLING = "res://assets/fir_optimized.glb"
const FirBuilder = preload("res://god/fir_builder.gd")
const TREE_CHUNK = 150.0
const GRASS_TILE = 32.0

var terrain
var town
var cfg: Dictionary
var forest_fn: Callable
var rng := RandomNumberGenerator.new()
var fir_meshes: Array = []
var saplings: Array = []
var impostor_mats: Array = []
var impostor_mesh: ArrayMesh
var tree_chunks = {} # Vector2i -> {"full": [MultiMeshInstance3D], "imp": [MultiMeshInstance3D], "items": [[variant, idx, pos, yaw, sx, sy, alive]]}
var grass_tiles = {}
var grass_mesh: ArrayMesh
var grass_mat: ShaderMaterial
var tree_count := 0
var near_range := 220.0
var grass_radius := 70.0
var grass_density := 0.9

func setup(c: Dictionary,t,tw,forest: Callable):
 cfg = c
 terrain = t
 town = tw
 forest_fn = forest
 near_range = float(cfg.tree_near)
 grass_radius = float(cfg.grass_radius)
 grass_density = float(cfg.grass_density)/10.0
 rng.seed = 404
 _occupy()
 _load_firs()
 await _make_impostors()
 _plant_trees()
 _grass_setup()
 _rocks()
 _props()

func _load_firs():
 var mats = FirBuilder.materials(0.38)
 for i in 4:
  var h = [12.0,15.0,18.0,22.0][i]
  var mesh = FirBuilder.build(h,100+i*17)
  mesh.surface_set_material(0,mats[0])
  mesh.surface_set_material(1,mats[1])
  fir_meshes.append({"mesh":mesh,"h":h,"w":h*0.46})
 # The Poly Haven fir sapling at its own size: young firs at the forest edge and along the roads.
 var scene = load(SAPLING).instantiate()
 for mi in scene.find_children("*","MeshInstance3D",true,false):
  var mesh: Mesh = mi.mesh.duplicate()
  for s in mesh.get_surface_count():
   var src = mesh.surface_get_material(s)
   var m = ShaderMaterial.new()
   m.shader = load("res://god/tree.gdshader")
   if src is BaseMaterial3D:
    m.set_shader_parameter("albedo_tex",src.albedo_texture)
    m.set_shader_parameter("normal_tex",src.normal_texture)
    m.set_shader_parameter("tint",src.albedo_color)
   m.set_shader_parameter("tex_size",Vector2(1.0,1.0))
   m.set_shader_parameter("sway",3.0)
   mesh.surface_set_material(s,m)
  saplings.append(mesh)
 scene.free()

# One orthographic side view per fir variant, rendered once into a texture with alpha.
func _make_impostors():
 var headless = DisplayServer.get_name() == "headless" # no frames are drawn: impostors stay blank
 var mesh = ArrayMesh.new()
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for k in 2:
  var a = k*PI*0.5
  var d = Vector3(cos(a),0,sin(a))*0.5
  var n = Vector3(-sin(a),0.35,cos(a)).normalized()
  var q = [-d,d,d+Vector3(0,1,0),-d+Vector3(0,1,0)]
  var uv = [Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]
  for i in [0,1,2,0,2,3]:
   st.set_normal(n)
   st.set_uv(uv[i])
   st.add_vertex(q[i])
 impostor_mesh = st.commit()
 for f in fir_meshes:
  var vp = SubViewport.new()
  vp.size = Vector2i(256,384)
  vp.transparent_bg = true
  vp.render_target_update_mode = SubViewport.UPDATE_ONCE
  vp.own_world_3d = true
  add_child(vp)
  var mi = MeshInstance3D.new()
  mi.mesh = f.mesh
  vp.add_child(mi)
  var cam = Camera3D.new()
  cam.projection = Camera3D.PROJECTION_ORTHOGONAL
  cam.size = f.h*1.02
  cam.keep_aspect = Camera3D.KEEP_HEIGHT
  cam.position = Vector3(0,f.h*0.5,4.0)
  vp.add_child(cam)
  var l = DirectionalLight3D.new()
  l.rotation = Vector3(-0.6,0.5,0)
  l.light_energy = 1.4
  vp.add_child(l)
  var we = WorldEnvironment.new()
  var e = Environment.new()
  e.background_mode = Environment.BG_CLEAR_COLOR
  e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
  e.ambient_light_color = Color(0.55,0.6,0.68)
  e.ambient_light_energy = 0.9
  we.environment = e
  vp.add_child(we)
  if not headless:
   await RenderingServer.frame_post_draw
   await RenderingServer.frame_post_draw
  var img = null if headless else vp.get_texture().get_image()
  var tex = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
  var m = StandardMaterial3D.new()
  m.albedo_texture = tex
  m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
  m.alpha_scissor_threshold = 0.45
  m.cull_mode = BaseMaterial3D.CULL_DISABLED
  m.roughness = 1.0
  m.albedo_color = Color(0.92,0.95,1.0)
  impostor_mats.append(m)
  vp.queue_free()

var _occupied = {}
func _occupy():
 for p in town.plots:
  for dx in range(-2,3):
   for dz in range(-2,3):
    var q = p.pos+Vector2(dx,dz)*6.0
    _occupied[Vector2i(floori(q.x/6.0),floori(q.y/6.0))] = true

func _blocked(x: float,z: float) -> bool:
 if _occupied.has(Vector2i(floori(x/6.0),floori(z/6.0))): return true
 var s = terrain.splat_at(x,z)
 if s.r>0.05 or s.b>0.05 or s.a>0.05 or s.g>0.12: return true
 if Vector2(x,z).distance_to(town.castle)<75.0: return true
 return false

func _plant_trees():
 var half = terrain.half-20.0
 var nz = FastNoiseLite.new()
 nz.seed = 77
 nz.frequency = 0.004
 var per = {}
 var step = 7.0
 var x = -half
 while x<half:
  var z = -half
  while z<half:
   var px = x+rng.randf_range(-3.0,3.0)
   var pz = z+rng.randf_range(-3.0,3.0)
   var forest = forest_fn.call(px,pz)
   var clump = nz.get_noise_2d(px,pz)
   var chance = 0.62 if forest else (0.16 if clump>0.35 else 0.0)
   # The town keeps its fields of view: few trees within 230 m of the castle.
   var dc = Vector2(px,pz).distance_to(town.castle)
   if dc<230.0: chance *= 0.12
   elif dc<330.0: chance *= 0.45
   # Thin the forest edge toward the open land.
   if forest and clump<-0.3: chance *= 0.6
   if rng.randf()<chance and not _blocked(px,pz) and terrain.normal_at(px,pz).y>0.82:
    var k = Vector2i(floori(px/TREE_CHUNK),floori(pz/TREE_CHUNK))
    if not per.has(k): per[k] = []
    var hgt = rng.randf_range(10.0,23.0)*(1.0 if forest else 0.8)
    var v = clampi(int((hgt-10.0)/13.0*fir_meshes.size()),0,fir_meshes.size()-1)
    var s = hgt/fir_meshes[v].h

    per[k].append([v,0,Vector3(px,terrain.height_at(px,pz)-0.2,pz),rng.randf()*TAU,s*rng.randf_range(0.9,1.1),s,true])
   z += step
  x += step
 for k in per: _tree_chunk(k,per[k])
 _plant_saplings()

func _tree_chunk(k: Vector2i,items: Array):
 var c = {"full":[],"imp":[],"items":items}
 tree_count += items.size()
 var by = []
 for v in fir_meshes.size(): by.append([])
 for it in items:
  it[1] = by[it[0]].size()
  by[it[0]].append(it)
 var center = Vector3((k.x+0.5)*TREE_CHUNK,0,(k.y+0.5)*TREE_CHUNK)
 for v in fir_meshes.size():
  if by[v].is_empty():
   c.full.append(null)
   c.imp.append(null)
   continue
  for pass_i in 2:
   var mm = MultiMesh.new()
   mm.transform_format = MultiMesh.TRANSFORM_3D
   mm.use_colors = true
   mm.mesh = fir_meshes[v].mesh if pass_i == 0 else impostor_mesh
   mm.instance_count = by[v].size()
   for i in by[v].size(): mm.set_instance_transform(i,_tree_xf(by[v][i],pass_i == 1,v))
   for i in by[v].size(): mm.set_instance_color(i,Color(1,1,1).darkened(rng.randf()*0.25))
   var mmi = MultiMeshInstance3D.new()
   mmi.multimesh = mm
   add_child(mmi)
   if pass_i == 0:
    mmi.visibility_range_end = near_range
    mmi.visibility_range_end_margin = 30.0
    mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
    c.full.append(mmi)
   else:
    mmi.material_override = impostor_mats[v]
    mmi.visibility_range_begin = near_range-20.0
    mmi.visibility_range_begin_margin = 30.0
    mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    c.imp.append(mmi)
   # Visibility ranges measure from each instance's AABB centre: keep the chunk's at its middle.
   mmi.custom_aabb = AABB(center-Vector3(TREE_CHUNK*0.5,0,TREE_CHUNK*0.5)+Vector3(0,-50,0),Vector3(TREE_CHUNK,140,TREE_CHUNK))
 tree_chunks[k] = c

func _tree_xf(it: Array,impostor: bool,v: int) -> Transform3D:
 var sx = it[4]
 var sy = it[5]
 if impostor:
  var w = fir_meshes[v].w*sx
  var h = fir_meshes[v].h*sy
  return Transform3D(Basis(Vector3.UP,it[3]).scaled(Vector3(w,h,w)),it[2])
 var b = Basis(Vector3.UP,it[3]).scaled(Vector3(sx,sy,sx))
 if not it[6]:
  # Knocked flat, away from the blow (stored in it[7]).
  b = Basis(it[7],PI*0.47)*b
 return Transform3D(b,it[2])

# Flatten the trees within `range` of origin inside the cone (cos_half; -1 = all around).
func knock_down(origin: Vector3,dir: Vector3,range: float,cos_half: float) -> int:
 var n = 0
 for k in tree_chunks:
  var cc = Vector3((k.x+0.5)*TREE_CHUNK,origin.y,(k.y+0.5)*TREE_CHUNK)
  if Vector2(cc.x,cc.z).distance_to(Vector2(origin.x,origin.z))>range+TREE_CHUNK: continue
  var c = tree_chunks[k]
  for it in c.items:
   if not it[6]: continue
   var d = it[2]-origin
   d.y = 0.0
   var l = d.length()
   if l>range: continue
   if cos_half>-1.0 and l>2.0 and d.normalized().dot(Vector3(dir.x,0,dir.z).normalized())<cos_half: continue
   it[6] = false
   var away = d.normalized() if l>0.1 else Vector3.FORWARD
   it.append(Vector3.UP.cross(away).normalized()*-1.0)
   for pass_i in 2:
    var mmi = c.full[it[0]] if pass_i == 0 else c.imp[it[0]]
    if mmi != null: mmi.multimesh.set_instance_transform(it[1],_tree_xf(it,false,it[0]) if pass_i == 0 else Transform3D(Basis().scaled(Vector3.ONE*0.001),it[2]))
   n += 1
 return n

# --- Grass ---------------------------------------------------------------------------------------------

func _grass_setup():
 # A tuft: eight bent blades of three segments each.
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var r = RandomNumberGenerator.new()
 r.seed = 3
 for b in 14:
  var a = r.randf()*TAU
  var lean = Vector3(cos(a),0,sin(a))*r.randf_range(0.08,0.3)
  var h = r.randf_range(0.3,0.7)
  var w = 0.022
  var side = Vector3(-sin(a),0,cos(a))*w
  var base = Vector3(cos(a*3.0),0,sin(a*3.0))*r.randf_range(0.0,0.12)
  var prev_l = base-side
  var prev_r = base+side
  for s in 3:
   var t = float(s+1)/3.0
   var c = base+lean*t*t+Vector3(0,h*t,0)
   var ww = 1.0-t*0.85
   var l = c-side*ww
   var rr = c+side*ww
   for v in [[prev_l,t-1.0/3.0],[prev_r,t-1.0/3.0],[rr,t],[prev_l,t-1.0/3.0],[rr,t],[l,t]]:
    st.set_uv(Vector2(0,1.0-v[1]))
    st.set_color(Color(1,1,1,v[1]))
    st.set_normal(Vector3(0,1,0))
    st.add_vertex(v[0])
   prev_l = l
   prev_r = rr
 grass_mesh = st.commit()
 grass_mat = ShaderMaterial.new()
 grass_mat.shader = load("res://god/grass.gdshader")

func update_grass(focus: Vector3):
 var built = 0
 var cx = floori(focus.x/GRASS_TILE)
 var cz = floori(focus.z/GRASS_TILE)
 var reach = int(ceil(grass_radius/GRASS_TILE))+1
 for dz in range(-reach,reach+1):
  for dx in range(-reach,reach+1):
   var k = Vector2i(cx+dx,cz+dz)
   if grass_tiles.has(k): continue
   var center = Vector2((k.x+0.5)*GRASS_TILE,(k.y+0.5)*GRASS_TILE)
   if center.distance_to(Vector2(focus.x,focus.z))>grass_radius+GRASS_TILE: continue
   if not terrain.inside(center.x,center.y,GRASS_TILE): continue
   grass_tiles[k] = _grass_tile(k)
   built += 1
   if built>=2: return

func _grass_tile(k: Vector2i) -> MultiMeshInstance3D:
 var r = RandomNumberGenerator.new()
 r.seed = hash(k)
 var xs = []
 var n = int(GRASS_TILE*GRASS_TILE*grass_density)
 var nz = FastNoiseLite.new()
 nz.seed = 11
 nz.frequency = 0.05
 for i in n:
  var x = (k.x+r.randf())*GRASS_TILE
  var z = (k.y+r.randf())*GRASS_TILE
  var s = terrain.splat_at(x,z)
  if s.a>0.3 or s.r>0.45: continue
  # Tufts where the snow is thin: bare ground, road verges, field edges, and patches in the open.
  var w = maxf(s.g*1.2,s.b*0.5)+maxf(0.0,nz.get_noise_2d(x,z))*0.9
  if r.randf()>w: continue
  var y = terrain.height_at(x,z)
  var sc = r.randf_range(0.45,0.95)
  xs.append(Transform3D(Basis(Vector3.UP,r.randf()*TAU).scaled(Vector3(sc,sc*r.randf_range(0.8,1.3),sc)),Vector3(x,y-0.03,z)))
 var mm = MultiMesh.new()
 mm.transform_format = MultiMesh.TRANSFORM_3D
 mm.mesh = grass_mesh
 mm.instance_count = xs.size()
 for i in xs.size(): mm.set_instance_transform(i,xs[i])
 var mmi = MultiMeshInstance3D.new()
 mmi.multimesh = mm
 mmi.material_override = grass_mat
 mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 mmi.visibility_range_end = grass_radius
 mmi.visibility_range_end_margin = 10.0
 mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
 add_child(mmi)
 return mmi

# --- Rocks and props -------------------------------------------------------------------------------------

func _gltf_meshes(path: String) -> Array:
 var out = []
 var scene = load(path).instantiate()
 for mi in scene.find_children("*","MeshInstance3D",true,false): out.append({"mesh":mi.mesh,"aabb":mi.get_aabb(),"xf":mi.transform})
 scene.free()
 return out

func _scatter(meshes: Array,points: Array,shadows := true,range := 300.0):
 # Chunked (so each chunk culls, picks its mesh LOD and drops out past `range` on its own; one
 # MultiMesh over the whole area drew every rock at full detail).
 var by = {}
 for p in points:
  var k = [p[0],floori(p[1].origin.x/TREE_CHUNK),floori(p[1].origin.z/TREE_CHUNK)]
  if not by.has(k): by[k] = []
  by[k].append(p[1])
 for k in by:
  var mm = MultiMesh.new()
  mm.transform_format = MultiMesh.TRANSFORM_3D
  mm.mesh = meshes[k[0]].mesh
  mm.instance_count = by[k].size()
  for j in by[k].size(): mm.set_instance_transform(j,by[k][j])
  var mmi = MultiMeshInstance3D.new()
  mmi.multimesh = mm
  mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  mmi.visibility_range_end = range
  mmi.visibility_range_end_margin = range*0.1
  add_child(mmi)

func _rocks():
 var meshes = _gltf_meshes("res://assets/god/models/rock_moss_set_01/rock_moss_set_01.gltf")+_gltf_meshes("res://assets/god/models/rock_moss_set_02/rock_moss_set_02.gltf")
 var pts = []
 var half = terrain.half-30.0
 for i in 1400:
  var x = rng.randf_range(-half,half)
  var z = rng.randf_range(-half,half)
  var nrm = terrain.normal_at(x,z)
  var forest = forest_fn.call(x,z)
  if not (nrm.y<0.93 or forest or rng.randf()<0.15): continue
  if _blocked(x,z): continue
  var mi = rng.randi_range(0,meshes.size()-1)
  var sc = rng.randf_range(0.5,2.4)*(1.6 if nrm.y<0.9 else 1.0)
  var b = Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*sc)
  var y = terrain.height_at(x,z)-meshes[mi].aabb.size.y*sc*0.25-meshes[mi].aabb.position.y*sc
  pts.append([mi,Transform3D(b,Vector3(x,y,z))])
 _scatter(meshes,pts,true,320.0)

func _props():
 var barrel = _gltf_meshes("res://assets/god/models/wine_barrel_01/wine_barrel_01.gltf")
 var crate = _gltf_meshes("res://assets/god/models/wooden_crate_02/wooden_crate_02.gltf")
 var bucket = _gltf_meshes("res://assets/god/models/wooden_bucket_01/wooden_bucket_01.gltf")
 var stump = _gltf_meshes("res://assets/god/models/tree_stump_01/tree_stump_01.gltf")
 var meshes = barrel+crate+bucket+stump
 var pts = []
 var ib = 0
 var ic = barrel.size()
 var iu = ic+crate.size()
 var istump = iu+bucket.size()
 # Beside the houses: a barrel or two, a crate, a bucket by the door.
 for b in town.homes:
  var blk = town.blocks[b]
  var door: Vector3 = blk.door
  var c: Vector3 = blk.center
  var side = Vector3(door.x-c.x,0,door.z-c.z).normalized().cross(Vector3.UP)
  for k in rng.randi_range(1,3):
   var p = door+side*rng.randf_range(2.2,4.0)*(1.0 if rng.randf()<0.5 else -1.0)+Vector3(rng.randf_range(-0.6,0.6),0,rng.randf_range(-0.6,0.6))
   p.y = terrain.height_at(p.x,p.z)
   var roll = rng.randf()
   if roll<0.5:
    var bx = Transform3D(Basis(Vector3.UP,rng.randf()*TAU),p)
    for part in barrel.size(): pts.append([ib+part,bx*barrel[part].xf])
   elif roll<0.8:
    for part in crate.size(): pts.append([ic+part,Transform3D(Basis(Vector3.UP,rng.randf()*TAU),p)*crate[part].xf])
   else:
    for part in bucket.size(): pts.append([iu+part,Transform3D(Basis(Vector3.UP,rng.randf()*TAU),p)*bucket[part].xf])
 # Market: crates and barrels among the stalls.
 for i in 22:
  var a = rng.randf()*TAU
  var p = town.market+Vector3(cos(a),0,sin(a))*rng.randf_range(5.0,16.0)
  p.y = terrain.height_at(p.x,p.z)
  if rng.randf()<0.5:
   var bx = Transform3D(Basis(Vector3.UP,rng.randf()*TAU),p)
   for part in barrel.size(): pts.append([ib+part,bx*barrel[part].xf])
  else:
   for part in crate.size(): pts.append([ic+part,Transform3D(Basis(Vector3.UP,rng.randf()*TAU),p)*crate[part].xf])
 # Stumps at the forest edge (the town's woodcutters).
 for i in 200:
  var x = rng.randf_range(-600,600)
  var z = rng.randf_range(-600,600)
  if not forest_fn.call(x,z) or _blocked(x,z): continue
  pts.append([istump,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(0.8,1.4)),Vector3(x,terrain.height_at(x,z)-0.1,z))])
 _scatter(meshes,pts,false,110.0)

func reset():
 for k in tree_chunks:
  var c = tree_chunks[k]
  for it in c.items:
   if it[6]: continue
   it[6] = true
   it.resize(7)
   for pass_i in 2:
    var mmi = c.full[it[0]] if pass_i == 0 else c.imp[it[0]]
    if mmi != null: mmi.multimesh.set_instance_transform(it[1],_tree_xf(it,pass_i == 1,it[0]))

# Young firs (the Poly Haven sapling at its own size, scaled 1.2-3 m) at the forest edges and
# scattered along the verges.
func _plant_saplings():
 var xs = []
 var half = terrain.half-30.0
 for i in 4000:
  var x = rng.randf_range(-half,half)
  var z = rng.randf_range(-half,half)
  var edge = forest_fn.call(x,z) != forest_fn.call(x+14.0,z) or forest_fn.call(x,z) != forest_fn.call(x,z+14.0)
  var verge = terrain.splat_at(x,z).g>0.2 and terrain.splat_at(x,z).r<0.1
  if not (edge or (verge and rng.randf()<0.25) or (forest_fn.call(x,z) and rng.randf()<0.08)): continue
  if _blocked(x,z) and not verge: continue
  if terrain.splat_at(x,z).r>0.1 or Vector2(x,z).distance_to(town.castle)<75.0: continue
  var s = rng.randf_range(1.2,3.0)
  xs.append([rng.randi_range(0,saplings.size()-1),Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*s),Vector3(x,terrain.height_at(x,z)-0.05,z))])
 var by = {}
 for e in xs:
  if not by.has(e[0]): by[e[0]] = []
  by[e[0]].append(e[1])
 for i in by:
  # Chunked so visibility ranges can drop the far ones.
  var chunks = {}
  for xf in by[i]:
   var k = Vector2i(floori(xf.origin.x/TREE_CHUNK),floori(xf.origin.z/TREE_CHUNK))
   if not chunks.has(k): chunks[k] = []
   chunks[k].append(xf)
  for k in chunks:
   var mm = MultiMesh.new()
   mm.transform_format = MultiMesh.TRANSFORM_3D
   mm.mesh = saplings[i]
   mm.instance_count = chunks[k].size()
   for j in chunks[k].size(): mm.set_instance_transform(j,chunks[k][j])
   var mmi = MultiMeshInstance3D.new()
   mmi.multimesh = mm
   mmi.visibility_range_end = 75.0
   mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   mmi.visibility_range_end_margin = 10.0
   add_child(mmi)
