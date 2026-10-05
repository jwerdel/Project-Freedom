extends Node3D
# The 3D campaign map of a pipeline map (docs/map-pipeline-design.md §4.3, Addendum A):
#  - terrain: 256 m chunks, each with four LOD grids (2 / 4 / 8 / 16 m spacing) on Godot's
#    visibility ranges, all sharing one material that displaces them from the heightfield texture
#    and colours them by terrain class and land culture (map/terrain_view.gdshader);
#  - a sea plane;
#  - trees scattered per chunk from the forest cells, built only near the camera (per chunk one
#    MultiMesh per tree mesh), their species following the region's land conversion;
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
const TREE_RANGE = 520.0
const BUILD_RADIUS = 700.0
const DROP_RADIUS = 950.0
const TREE_DENSITY = 0.16 # trees per forest cell

var state
var grid: Dictionary
var heights: Image
var cell := 2.0
var origin := Vector2.ZERO
var cols := 0
var rows := 0
var material: ShaderMaterial
var palette_img: Image
var palette_tex: ImageTexture
var region_names: Array = []
var culture_ids: Array = []
var chunks = {}       # Vector2i -> {"node": Node3D, "trees": Node3D or null, "key": land key}
var settlements = {}  # id -> SprawlNode
var sea_level := 0.0
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
 assert(not rc.is_empty(),"No render cache for %s: run scripts/build_map.gd -- --map=%s" % [MapRegistry.active,MapRegistry.active])
 heights = rc.heights
 _make_material()
 _make_terrain()
 _make_sea()

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
 var classes = grid.names
 var cc = Image.create(8,culture_ids.size(),false,Image.FORMAT_RGBA8)
 for y in culture_ids.size():
  var terr = Sprawl.culture(culture_ids[y]).terrain
  for x in classes.size(): cc.set_pixel(x,y,Color(terr.get(classes[x],"#ff00ff")))
 material.set_shader_parameter("culture_colors",ImageTexture.create_from_image(cc))
 palette_img = Image.create(maxi(1,region_names.size()+1),1,false,Image.FORMAT_RGBA8)
 palette_tex = ImageTexture.create_from_image(palette_img)
 material.set_shader_parameter("palette",palette_tex)
 material.set_shader_parameter("origin",origin)
 material.set_shader_parameter("world_size",Vector2(cols,rows)*cell)
 material.set_shader_parameter("grid_size",Vector2(cols,rows))
 material.set_shader_parameter("region_count",float(region_names.size()))
 material.set_shader_parameter("culture_count",float(culture_ids.size()))
 refresh_land()

# The land of every region into the palette texture (after End Turn or a change of hands).
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

func terrain_at(p: Vector2) -> String:
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
  elif d>DROP_RADIUS and settlements.has(sid):
   settlements[sid].queue_free()
   settlements.erase(sid)

# What map/sprawl.gd needs to lay a settlement out, from the campaign state.
func settlement_spec(sid: String) -> Dictionary:
 var st = state.settlements[sid]
 var e = Land.entry(state,sid)
 return {"id":sid,"type":st.type,"level":int(st.level),"position":WorldMap.settlement_position(sid),"from":e.from,"to":e.to,
  "value":snappedf(float(e.value),0.05),"buildings":st.buildings.filter(func(b): return b.has("chain")),"landmark_radius":0.0}

func _make_trees(k: Vector2i) -> Node3D:
 var root = Node3D.new()
 add_child(root)
 var tree_meshes = KitCache.meshes("nature.tree")
 if tree_meshes.is_empty(): return root
 var groups = {}
 var x0 = int((k.x*CHUNK)/cell)
 var z0 = int((k.y*CHUNK)/cell)
 var n = int(CHUNK/cell)
 var forest = grid.names.find("forest")
 var terrain: PackedByteArray = grid.terrain
 for z in range(z0,mini(z0+n,rows)):
  for x in range(x0,mini(x0+n,cols)):
   var i = z*cols+x
   if terrain[i] != forest: continue
   var h = _hash(x,z)
   if h>TREE_DENSITY: continue
   var p = origin+Vector2(x+fmod(h*97.0,1.0),z+fmod(h*61.0,1.0))*cell
   var sid = WorldMap.region_at(p)
   var cul = "medieval"
   if state.land.has(sid):
    var e = state.land[sid]
    cul = e.to if fmod(h*7919.0,1.0)<float(e.value) else e.from
   var tr = Sprawl.culture(cul).tree
   var mi = clampi(int(tr.variant),0,tree_meshes.size()-1)
   var base_h = maxf(0.1,tree_meshes[mi].mesh.get_aabb().size.y)
   var sz = (4.2+fmod(h*331.0,1.0)*2.6)/base_h
   var basis = Basis(Vector3.UP,fmod(h*1000.0,TAU)).scaled(Vector3(sz*float(tr.scale[0]),sz*float(tr.scale[1]),sz*float(tr.scale[0])))
   var xf = Transform3D(basis,Vector3(p.x,height_at(p.x,p.y),p.y))*tree_meshes[mi].xform
   if not groups.has(mi): groups[mi] = {"xf":[],"col":[]}
   groups[mi].xf.append(xf)
   groups[mi].col.append(Color(tr.tint))
 for mi in groups:
  var mm = MultiMesh.new()
  mm.transform_format = MultiMesh.TRANSFORM_3D
  mm.use_colors = true
  mm.mesh = tree_meshes[mi].mesh
  mm.instance_count = groups[mi].xf.size()
  for j in groups[mi].xf.size():
   mm.set_instance_transform(j,groups[mi].xf[j])
   mm.set_instance_color(j,groups[mi].col[j])
  var mmi = MultiMeshInstance3D.new()
  mmi.multimesh = mm
  mmi.visibility_range_end = TREE_RANGE
  root.add_child(mmi)
 return root

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
