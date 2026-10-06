extends Node3D
# The 3D campaign map of a pipeline map (docs/map-pipeline-design.md §4.3, Addendum A):
#  - terrain: 256 m chunks, each with four LOD grids (2 / 4 / 8 / 16 m spacing) on Godot's
#    visibility ranges, all sharing one material that displaces them from the heightfield texture
#    and colours them by terrain class and land culture (map/terrain_view.gdshader);
#  - a sea plane;
#  - trees planted per chunk on the forest cells near the camera (per chunk one MultiMesh per tree
#    model, from the culture's forest profile and the region's land conversion), boulders on the
#    hills; beyond TREE_RANGE forests are the terrain shader's canopy carpet;
#  - settlements: procedural sprawl (map/sprawl.gd) built only within build_radius of the camera.
# Reads the active map's bakes (render cache, movement grid, region raster) and the campaign state
# (owners, levels, buildings, land). update(focus) streams; refresh_land() after End Turn.

const MapRegistry = preload("res://core/map_registry.gd")
const MapBake = preload("res://map/map_bake.gd")
const Movement = preload("res://core/movement.gd")
const WorldMap = preload("res://core/world_map.gd")
const Land = preload("res://core/land.gd")
const Sprawl = preload("res://map/sprawl.gd")
const SprawlNode = preload("res://map/sprawl_node.gd")
const KitCache = preload("res://map/kit_cache.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const CHUNK = 256.0
const LODS = [[127,0.0,420.0],[63,420.0,950.0],[31,950.0,2200.0],[15,2200.0,0.0]] # subdivisions, range begin, end
const TREE_RANGE = 320.0 # 3D trees near the camera; farther forests are the terrain's canopy carpet
const TREE_DENSITY = 0.12 # trees per forest cell (2 m) at density 1; the terrain's canopy carpet fills between them
const ROCK_DENSITY = 0.0015 # boulders per hill or mountain cell
const TREE_LOD_BIAS = 0.25 # a chunk's trees share one LOD, picked from the chunk's nearest point: bias it coarser
var tree_shadows := true
const BUILD_RADIUS = 700.0
const DROP_RADIUS = 950.0
const GROUND_LAYERS = ["grass","dry","forest_floor","canopy","rock","scree","snow","dirt","sand","water"] # map/terrain_view.gdshader columns

var state
var grid: Dictionary
var heights: Image
var rivers: Image
var cell := 2.0
var origin := Vector2.ZERO
var cols := 0
var rows := 0
var material: ShaderMaterial
var palette_img: Image
var palette_tex: ImageTexture
var owners_img: Image
var owners_tex: ImageTexture
var region_names: Array = []
var culture_ids: Array = []
var chunks = {}       # Vector2i -> {"node": Node3D, "trees": Node3D or null, "key": land key}
var settlements = {}  # id -> SprawlNode
var sea_level := 0.0
var spec_overrides = {} # settlement id -> spec fields to override (showcases: a town's path)
var landmarks = {} # settlement id -> its landmark model (asset manifest landmarks)
const LANDMARK_RADIUS = 20.0
var only := "" # build only this settlement (showcases)
var _last_focus := Vector3(INF,0,INF)

func setup(campaign_state):
 state = campaign_state
 grid = Movement.grid()
 cell = float(grid.cell)
 origin = grid.origin
 cols = int(grid.cols)
 rows = int(grid.rows)
 sea_level = float(MapRegistry.meta().get("sea_level",0.0))
 var rc = MapBake.load_render_cache(MapRegistry.active)
 if rc.is_empty() and str(MapRegistry.meta().get("kind","")) == "pipeline":
  # First run (or a rebuilt map): the render cache is local, so build it from the map's sources.
  load("res://map/pipeline.gd").build(MapRegistry.active,false)
  rc = MapBake.load_render_cache(MapRegistry.active)
 assert(not rc.is_empty(),"No render cache for %s: run scripts/build_map.gd -- --map=%s" % [MapRegistry.active,MapRegistry.active])
 heights = rc.heights
 rivers = rc.rivers
 _make_material()
 _make_terrain()
 _make_sea()
 _make_walls()

func _make_material():
 material = ShaderMaterial.new()
 material.shader = load("res://map/terrain_view.gdshader")
 material.set_shader_parameter("heights",ImageTexture.create_from_image(heights))
 material.set_shader_parameter("classes",ImageTexture.create_from_image(Image.create_from_data(cols,rows,false,Image.FORMAT_R8,grid.terrain)))
 WorldMap.region_at(Vector2.ZERO)
 var ras = WorldMap._raster
 region_names = ras.names
 # The int32 region ids are already RGBA8 texels: id = R + 256 G (no per-pixel loop).
 material.set_shader_parameter("regions",ImageTexture.create_from_image(Image.create_from_data(cols,rows,false,Image.FORMAT_RGBA8,ras.ids.to_byte_array())))
 culture_ids = Sprawl.culture_data().cultures.keys()
 # Biome layers per culture (data/cultures.json "ground"), in the shader's column order (sRGB), and
 # each culture's parameters (snow line / 100 m) in a float texture.
 var cc = Image.create(GROUND_LAYERS.size(),culture_ids.size(),false,Image.FORMAT_RGBA8)
 var cp = Image.create(culture_ids.size(),1,false,Image.FORMAT_RF)
 for y in culture_ids.size():
  var gr = Sprawl.culture(culture_ids[y]).ground
  for x in GROUND_LAYERS.size(): cc.set_pixel(x,y,Color(gr.get(GROUND_LAYERS[x],"#ff00ff")))
  cp.set_pixel(y,0,Color(float(gr.get("snow_line",999))/100.0,0,0))
 material.set_shader_parameter("culture_params",ImageTexture.create_from_image(cp))
 var classes = grid.names
 for k in ["forest","hills","pass","settlement","mountain","water"]: material.set_shader_parameter("class_"+k,classes.find(k))
 material.set_shader_parameter("rivers",ImageTexture.create_from_image(rivers))
 material.set_shader_parameter("roads",ImageTexture.create_from_image(Image.create_from_data(cols,rows,false,Image.FORMAT_R8,grid.road))) # 0 or 1 per cell (the shader scales it)
 material.set_shader_parameter("sea_level",sea_level)
 material.set_shader_parameter("canopy_fade_end",TREE_RANGE)
 material.set_shader_parameter("canopy_fade_begin",TREE_RANGE*0.72)
 material.set_shader_parameter("culture_colors",ImageTexture.create_from_image(cc))
 palette_img = Image.create(maxi(1,region_names.size()+1),1,false,Image.FORMAT_RGBA8)
 palette_tex = ImageTexture.create_from_image(palette_img)
 material.set_shader_parameter("palette",palette_tex)
 owners_img = Image.create(maxi(1,region_names.size()+1),1,false,Image.FORMAT_RGBA8)
 owners_tex = ImageTexture.create_from_image(owners_img)
 material.set_shader_parameter("owners",owners_tex)
 refresh_owners()
 material.set_shader_parameter("origin",origin)
 material.set_shader_parameter("world_size",Vector2(cols,rows)*cell)
 material.set_shader_parameter("grid_size",Vector2(cols,rows))
 material.set_shader_parameter("region_count",float(region_names.size()))
 material.set_shader_parameter("culture_count",float(culture_ids.size()))
 refresh_land()

# The land of every region into the palette texture (after End Turn or a change of hands).
# Faction borders on the terrain (TW:WH3): each region's owner colour, drawn by the shader where
# neighbouring regions have different owners. Call after captures.
func refresh_owners():
 if owners_img == null: return
 owners_img.fill(Color(0,0,0,0))
 for i in region_names.size():
  var sid = region_names[i]
  if not state.settlements.has(sid): continue
  var o = str(state.settlements[sid].get("owner",""))
  if o == "": continue
  owners_img.set_pixel(i+1,0,Color(Color(WorldMap.faction(o).get("primary","#ffffff")),1.0))
 owners_tex.update(owners_img)

# Settlements rebuild on the next update when their spec changed (levels, buildings, owners).
func refresh_settlements():
 _last_focus = Vector3(INF,0,INF)

func refresh_land():
 for i in region_names.size():
  var sid = region_names[i]
  var from_i = 0
  var to_i = 0
  var v = 1.0
  if state.land.has(sid):
   var e = state.land[sid]
   from_i = maxi(0,culture_ids.find(e.from))
   to_i = maxi(0,culture_ids.find(e.to))
   v = float(e.value)
  palette_img.set_pixel(i+1,0,Color8(from_i,to_i,int(round(v*255.0)),255))
 palette_tex.update(palette_img)
 # Trees and settlements whose land changed rebuild on the next update.
 for k in chunks: chunks[k].key = ""
 _last_focus = Vector3(INF,0,INF)

func _make_terrain():
 var meshes = []
 for l in LODS:
  var pm = PlaneMesh.new()
  pm.size = Vector2(CHUNK,CHUNK)
  pm.subdivide_width = l[0]
  pm.subdivide_depth = l[0]
  meshes.append(pm)
 var nx = int(ceil(cols*cell/CHUNK))
 var nz = int(ceil(rows*cell/CHUNK))
 for cz in nz:
  for cx in nx:
   var node = Node3D.new()
   node.position = Vector3(origin.x+(cx+0.5)*CHUNK,0,origin.y+(cz+0.5)*CHUNK)
   add_child(node)
   for i in LODS.size():
    var mi = MeshInstance3D.new()
    mi.mesh = meshes[i]
    mi.material_override = material
    mi.custom_aabb = AABB(Vector3(-CHUNK*0.5,-20,-CHUNK*0.5),Vector3(CHUNK,120,CHUNK))
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    mi.visibility_range_begin = LODS[i][1]
    mi.visibility_range_end = LODS[i][2]
    node.add_child(mi)
   chunks[Vector2i(cx,cz)] = {"node":node,"trees":null,"key":""}

func _make_sea():
 var pm = PlaneMesh.new()
 pm.size = Vector2(cols,rows)*cell*1.6
 var sea = MeshInstance3D.new()
 sea.mesh = pm
 var m = StandardMaterial3D.new()
 m.albedo_color = Color("2f5f80")
 m.roughness = 0.25
 m.metallic_specular = 0.6
 sea.material_override = m
 sea.position = Vector3(origin.x+cols*cell*0.5,sea_level-0.05,origin.y+rows*cell*0.5)
 sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(sea)

# --- Queries ------------------------------------------------------------------------------------

func height_at(x: float,z: float) -> float:
 var gx = clampf((x-origin.x)/cell-0.5,0.0,cols-1.001)
 var gz = clampf((z-origin.y)/cell-0.5,0.0,rows-1.001)
 var x0 = int(gx)
 var z0 = int(gz)
 var fx = gx-x0
 var fz = gz-z0
 var a = lerpf(heights.get_pixel(x0,z0).r,heights.get_pixel(x0+1,z0).r,fx)
 var b = lerpf(heights.get_pixel(x0,z0+1).r,heights.get_pixel(x0+1,z0+1).r,fx)
 return maxf(lerpf(a,b,fz),sea_level)

# The terrain class for settlement layouts: the movement class, except that rivers (drawn, not yet
# in the movement rules) count as water, so towns grow along their banks instead of across them.
func terrain_at(p: Vector2) -> String:
 var x = int((p.x-origin.x)/cell)
 var z = int((p.y-origin.y)/cell)
 if rivers != null and x>=0 and z>=0 and x<cols and z<rows and rivers.get_pixel(x,z).r>0.42: return "water"
 return Movement.terrain_at(p)

# --- Streaming ----------------------------------------------------------------------------------

func update(focus: Vector3):
 if Vector2(focus.x,focus.z).distance_to(Vector2(_last_focus.x,_last_focus.z))<24.0: return
 _last_focus = focus
 var f2 = Vector2(focus.x,focus.z)
 for k in chunks:
  var c = chunks[k]
  var center = Vector2(c.node.position.x,c.node.position.z)
  var near = center.distance_to(f2)<TREE_RANGE+CHUNK*0.75
  if near and (c.trees == null or c.key != "built"):
   if c.trees != null: c.trees.queue_free()
   c.trees = _make_trees(k)
   c.key = "built"
  elif not near and c.trees != null:
   c.trees.queue_free()
   c.trees = null
   c.key = ""
 for sid in WorldMap.settlement_ids():
  var p = WorldMap.settlement_position(sid)
  var d = p.distance_to(f2)
  if only != "" and sid != only: continue
  if d<BUILD_RADIUS:
   var s = settlement_spec(sid)
   var key = str(s.hash())
   if not settlements.has(sid):
    var n = SprawlNode.new()
    add_child(n)
    settlements[sid] = n
   if settlements[sid].key != key:
    settlements[sid].build(s,terrain_at,height_at,sea_level,BUILD_RADIUS)
    settlements[sid].key = key
    if AssetManifest.is_landmark(sid): _landmark(sid,int(s.level))
  elif d>DROP_RADIUS and settlements.has(sid):
   settlements[sid].queue_free()
   settlements.erase(sid)
   if landmarks.has(sid):
    landmarks[sid].queue_free()
    landmarks.erase(sid)

# A landmark settlement's own model at its growth stage (AssetManifest.instantiate_settlement), built
# on the terrain. Local space: origin at sea level under the site, local +z toward the nearest water
# (coastal landmarks such as Goldspire's sea cliff face the sea); build() gets heights in that space.
func _landmark(sid: String,level: int):
 if landmarks.has(sid): landmarks[sid].queue_free()
 var p = WorldMap.settlement_position(sid)
 var n = AssetManifest.instantiate_settlement(sid,clampi(level,1,3))
 add_child(n)
 n.position = Vector3(p.x,sea_level,p.y)
 var th = _toward_water(p)
 n.rotation.y = th
 var c = cos(th)
 var s = sin(th)
 if n.has_method("build"): n.build({"height":func(x,z): return height_at(p.x+x*c+z*s,p.y-x*s+z*c)-sea_level})
 landmarks[sid] = n

# The heading (rotation about y) that turns local +z toward the water around p; 0 when inland.
func _toward_water(p: Vector2) -> float:
 var d = Vector2.ZERO
 for r in [25.0,45.0,70.0]:
  for i in 32:
   var v = Vector2.from_angle(i*TAU/32.0)
   if height_at(p.x+v.x*r,p.y+v.y*r)<sea_level: d += v/r
 return 0.0 if d.length()<0.0001 else atan2(d.x,d.y)

# What map/sprawl.gd needs to lay a settlement out, from the campaign state.
func settlement_spec(sid: String) -> Dictionary:
 var st = state.settlements[sid]
 var e = Land.entry(state,sid)
 var spec = {"id":sid,"type":st.type,"level":int(st.level),"position":WorldMap.settlement_position(sid),"from":e.from,"to":e.to,
  "value":snappedf(float(e.value),0.05),"buildings":st.buildings.filter(func(b): return b.has("chain")),"landmark_radius":0.0}
 # A landmark keeps its own model at the centre; the town grows around it.
 if AssetManifest.is_landmark(sid): spec.landmark_radius = LANDMARK_RADIUS
 # The specialization path, from the map data until the path system exists (game-design §12.13 D).
 var rs = WorldMap.region(sid).get("settlement")
 if rs is Dictionary and str(rs.get("path","")) != "": spec.path = str(rs.path)
 spec.merge(spec_overrides.get(sid,{}),true)
 return spec

func _make_trees(k: Vector2i) -> Node3D:
 var root = Node3D.new()
 add_child(root)
 var groups = {} # model id -> {xf, col}
 var x0 = int((k.x*CHUNK)/cell)
 var z0 = int((k.y*CHUNK)/cell)
 var n = int(CHUNK/cell)
 var forest = grid.names.find("forest")
 var rocky = [grid.names.find("hills"),grid.names.find("mountain")]
 var terrain: PackedByteArray = grid.terrain
 for z in range(z0,mini(z0+n,rows)):
  for x in range(x0,mini(x0+n,cols)):
   var i = z*cols+x
   var t = terrain[i]
   var h = _hash(x,z)
   if t != forest:
    # Boulders on the hills and below the cliffs.
    if t in rocky and h<ROCK_DENSITY: _plant(groups,"nature.rock_%d" % (1+int(h*977.0)%3),x,z,h,Color("ffffff"),[1.0,1.0],2.2)
    continue
   if h>TREE_DENSITY*1.6: continue
   var p = origin+Vector2(x,z)*cell
   var sid = WorldMap.region_at(p)
   var cul = "medieval"
   if state.land.has(sid):
    var e = state.land[sid]
    cul = e.to if fmod(h*7919.0,1.0)<float(e.value) else e.from
   var fo = Sprawl.culture(cul).forest
   if h>TREE_DENSITY*float(fo.density): continue
   _plant(groups,_pick_tree(fo.trees,fmod(h*4111.0,1.0)),x,z,h,Color(fo.tint),fo.scale,7.0)
 for id in groups:
  var mesh = KitCache.baked(id)
  if mesh == null: continue
  var mm = MultiMesh.new()
  mm.transform_format = MultiMesh.TRANSFORM_3D
  mm.use_colors = true
  mm.mesh = mesh
  mm.instance_count = groups[id].xf.size()
  for j in groups[id].xf.size():
   mm.set_instance_transform(j,groups[id].xf[j])
   mm.set_instance_color(j,groups[id].col[j])
  var mmi = MultiMeshInstance3D.new()
  mmi.multimesh = mm
  mmi.visibility_range_end = TREE_RANGE
  mmi.lod_bias = TREE_LOD_BIAS
  if not tree_shadows: mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  root.add_child(mmi)
 return root

# One tree (or rock) at a cell, jittered, sized to about `size` metres tall, turned and tinted.
func _plant(groups: Dictionary,id: String,x: int,z: int,h: float,tint: Color,scale: Array,size: float):
 var mesh = KitCache.baked(id)
 if mesh == null: return
 var p = origin+Vector2(x+fmod(h*97.0,1.0),z+fmod(h*61.0,1.0))*cell
 var sz = size*(0.75+fmod(h*331.0,1.0)*0.5)/maxf(0.1,mesh.get_aabb().size.y)
 var basis = Basis(Vector3.UP,fmod(h*1000.0,TAU)).scaled(Vector3(sz*float(scale[0]),sz*float(scale[1]),sz*float(scale[0])))
 if not groups.has(id): groups[id] = {"xf":[],"col":[]}
 groups[id].xf.append(Transform3D(basis,Vector3(p.x,height_at(p.x,p.y)-0.2,p.y)))
 groups[id].col.append(tint)

# A weighted choice from [[model id, weight], ...] by u in 0-1.
static func _pick_tree(trees: Array,u: float) -> String:
 var total = 0.0
 for t in trees: total += float(t[1])
 var a = u*total
 for t in trees:
  a -= float(t[1])
  if a<0.0: return t[0]
 return trees[-1][0]

func _hash(x: int,z: int) -> float:
 var h = (x*73856093) ^ (z*19349663)
 h = (h ^ (h >> 13))*1274126177
 return float(h & 0xffffff)/16777216.0

# Counts for the budget report.
func stats() -> Dictionary:
 var trees = 0
 for k in chunks:
  if chunks[k].trees != null:
   for c in chunks[k].trees.get_children(): trees += c.multimesh.instance_count
 var pieces = 0
 for sid in settlements: pieces += settlements[sid].pieces
 return {"chunks":chunks.size(),"settlements_built":settlements.size(),"settlement_pieces":pieces,"trees":trees}

# --- Great walls (the Greywall): sketch ranges with data-kind="wall" ------------------------------
# The pipeline makes the wall's line impassable (a range) and leaves a pass at its gate; here it is
# drawn as a colossal stone wall following the ground: battlemented blocks every WALL_STEP metres and
# a tower every WALL_TOWER metres (MultiMeshes, so the whole wall costs a few draw calls).
const WALL_STEP = 10.0
const WALL_TOWER = 160.0
const WALL_HEIGHT = 24.0
const WALL_DEPTH = 9.0
const WALL_STONE = Color("8d8a84")

func _make_walls():
 var path = MapRegistry.path("sketch.svg")
 if not FileAccess.file_exists(path): return
 var sk = load("res://map/sketch.gd").parse_file(path)
 var origin = Vector2(MapRegistry.meta().origin[0],MapRegistry.meta().origin[1])
 var blocks = []
 var towers = []
 var gaps = []
 for e in sk.layers.get("passes",[]): gaps.append_array(Array(e.points).map(func(p): return origin+p))
 for e in sk.layers.get("ranges",[]):
  if str(e.data.get("kind","")) != "wall": continue
  var since_tower = WALL_TOWER*0.5
  for i in range(1,e.points.size()):
   var a: Vector2 = origin+e.points[i-1]
   var b: Vector2 = origin+e.points[i]
   var n = maxi(1,int(a.distance_to(b)/WALL_STEP))
   for k in n:
    var p = a.lerp(b,(k+0.5)/n)
    if gaps.any(func(q): return q.distance_to(p)<WALL_STEP*1.6): continue # the gate's pass stays open
    var yaw = atan2(b.x-a.x,b.y-a.y)
    var ground = minf(minf(height_at(p.x,p.y),height_at(p.x+cos(yaw)*4.0,p.y-sin(yaw)*4.0)),height_at(p.x-cos(yaw)*4.0,p.y+sin(yaw)*4.0))
    var xf = Transform3D(Basis(Vector3.UP,yaw),Vector3(p.x,ground-6.0,p.y))
    since_tower += a.distance_to(b)/n
    if since_tower>=WALL_TOWER:
     towers.append(xf)
     since_tower = 0.0
    else: blocks.append(xf)
 if blocks.is_empty() and towers.is_empty(): return
 var root = Node3D.new()
 root.name = "GreatWalls"
 add_child(root)
 for set in [[blocks,_wall_block_mesh()],[towers,_wall_tower_mesh()]]:
  if set[0].is_empty(): continue
  var mm = MultiMesh.new()
  mm.transform_format = MultiMesh.TRANSFORM_3D
  mm.mesh = set[1]
  mm.instance_count = set[0].size()
  for i in set[0].size(): mm.set_instance_transform(i,set[0][i])
  var mi = MultiMeshInstance3D.new()
  mi.multimesh = mm
  root.add_child(mi)

func _wall_mat() -> StandardMaterial3D:
 var m = StandardMaterial3D.new()
 m.albedo_color = WALL_STONE
 m.roughness = 0.95
 return m

func _box_into(st: SurfaceTool,size: Vector3,center: Vector3):
 var bm = BoxMesh.new()
 bm.size = size
 st.append_from(bm,0,Transform3D(Basis(),center))

# One wall block: WALL_STEP long along its local z, a battered body and merlons on both faces.
func _wall_block_mesh() -> ArrayMesh:
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 _box_into(st,Vector3(WALL_DEPTH+3.0,8.0,WALL_STEP+0.2),Vector3(0,4.0,0))
 _box_into(st,Vector3(WALL_DEPTH,WALL_HEIGHT+6.0,WALL_STEP+0.2),Vector3(0,(WALL_HEIGHT+6.0)*0.5,0))
 for s in [-1.0,1.0]:
  for k in 3: _box_into(st,Vector3(1.2,2.2,1.8),Vector3(s*(WALL_DEPTH*0.5-0.6),WALL_HEIGHT+7.1,-WALL_STEP*0.33+k*WALL_STEP*0.33))
 st.generate_normals()
 var m = st.commit()
 m.surface_set_material(0,_wall_mat())
 return m

func _wall_tower_mesh() -> ArrayMesh:
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 _box_into(st,Vector3(WALL_DEPTH+8.0,WALL_HEIGHT+16.0,WALL_DEPTH+8.0),Vector3(0,(WALL_HEIGHT+16.0)*0.5,0))
 for sx in [-1.0,1.0]:
  for sz in [-1.0,1.0]: _box_into(st,Vector3(2.4,2.6,2.4),Vector3(sx*(WALL_DEPTH*0.5+2.8),WALL_HEIGHT+17.3,sz*(WALL_DEPTH*0.5+2.8)))
 st.generate_normals()
 var m = st.commit()
 m.surface_set_material(0,_wall_mat())
 return m
