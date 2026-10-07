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
# Far terrain (high zoom): TILE-metre tiles of TILE_SUBDIV quads replace their 64 chunks once the
# camera is more than TILE_FROM metres from the tile (Godot visibility parents, a hierarchical LOD),
# so the whole world at the highest zoom costs a few dozen draw calls.
const TILE = 2048.0
const TILE_SUBDIV = 63
const TILE_FROM = 2600.0
const TREE_RANGE = 320.0 # 3D trees near the camera; farther forests are the terrain's canopy carpet
const TREE_DENSITY = 0.12 # trees per forest cell (2 m) at density 1; the terrain's canopy carpet fills between them
const ROCK_DENSITY = 0.0015 # boulders per hill or mountain cell
const OPEN_TREE_DENSITY = 0.009 # countryside trees per open cell (clumped), A8
const OPEN_TREE_CLEAR = 0.7 # open-land trees keep out of this share of a settlement's footprint radius
const TREE_LOD_BIAS = 0.25 # a chunk's trees share one LOD, picked from the chunk's nearest point: bias it coarser
var tree_shadows := true
const BUILD_RADIUS = 700.0
const DROP_RADIUS = 950.0
const CLIMATE_STEP = 8 # cells per climate texel (map/pipeline.gd)
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
var far_tiles := 0 # far terrain tiles (0 on maps of one tile)
var climate_img: Image # the render cache's climate looks (RGBA: snow, frost, dry, wet), or null
var zoom_amount := 0.0 # 0 close .. 1 at the farthest 3D zoom (core/camera_rig.gd high_zoom)
var highlight_faction := "" # the faction whose land is highlighted (hovering its settlement or army)
var player_faction := ""
var _last_focus := Vector3(INF,0,INF)

func setup(campaign_state):
 state = campaign_state
 player_faction = str(state.player_faction)
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
 climate_img = rc.get("climate")
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
 # Climate looks (the north snowy and frosted, the south dry), blurred so they blend without seams.
 if climate_img != null:
  material.set_shader_parameter("climate",ImageTexture.create_from_image(climate_img))
  material.set_shader_parameter("has_climate",true)
  material.set_shader_parameter("climate_scale",Vector2(cols,rows)/(Vector2(climate_img.get_width(),climate_img.get_height())*float(CLIMATE_STEP)))
 material.set_shader_parameter("roads",ImageTexture.create_from_image(Image.create_from_data(cols,rows,false,Image.FORMAT_R8,grid.road))) # 0 or 1 per cell (the shader scales it)
 material.set_shader_parameter("sea_level",sea_level)
 material.set_shader_parameter("canopy_fade_end",TREE_RANGE)
 material.set_shader_parameter("canopy_fade_begin",TREE_RANGE*0.72)
 material.set_shader_parameter("culture_colors",ImageTexture.create_from_image(cc))
 palette_img = Image.create(maxi(1,region_names.size()+1),1,false,Image.FORMAT_RGBA8)
 palette_tex = ImageTexture.create_from_image(palette_img)
 material.set_shader_parameter("palette",palette_tex)
 owners_img = Image.create(maxi(1,region_names.size()+1),2,false,Image.FORMAT_RGBA8)
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
# Row 0: the owner's colour (alpha 1 = owned). Row 1: the owner's faction index (R + 256 G, 0 = none)
# and flags in B (1 = the player's, 2 = the highlighted faction's), so borders compare owners, not
# colours.
func refresh_owners():
 if owners_img == null: return
 owners_img.fill(Color(0,0,0,0))
 var index = {}
 for i in region_names.size():
  var sid = region_names[i]
  if not state.settlements.has(sid): continue
  var o = str(state.settlements[sid].get("owner",""))
  if o == "": continue
  if not index.has(o): index[o] = index.size()+1
  var flags = (1 if o == player_faction else 0)+(2 if o == highlight_faction else 0)
  owners_img.set_pixel(i+1,0,Color(Color(WorldMap.faction(o).get("primary","#ffffff")),1.0))
  owners_img.set_pixel(i+1,1,Color8(index[o]%256,index[o]/256,flags,255))
 owners_tex.update(owners_img)
 if player_faction != "": material.set_shader_parameter("player_color",Color(WorldMap.faction(player_faction).get("primary","#ffffff")))

# The faction whose whole territory is highlighted ("" = none): hovering its settlement or army.
func set_highlight(faction: String):
 if faction == highlight_faction: return
 highlight_faction = faction
 refresh_owners()

# The zoom-dependent territory look (main.gd every frame): border widths grow with the camera
# distance so they stay a few pixels wide, and the faction wash rises with high_zoom (0-1).
func set_zoom_look(camera_distance: float,high_zoom: float):
 if material == null: return
 zoom_amount = high_zoom
 material.set_shader_parameter("border_scale",maxf(1.0,camera_distance/90.0))
 material.set_shader_parameter("wash",high_zoom)

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
 # Far tiles: only on maps larger than one tile (the test map stays all chunks).
 var tiles = {}
 var per = int(TILE/CHUNK)
 if cols*cell>TILE or rows*cell>TILE:
  var tm = PlaneMesh.new()
  tm.size = Vector2(TILE,TILE)
  tm.subdivide_width = TILE_SUBDIV
  tm.subdivide_depth = TILE_SUBDIV
  for tz in int(ceil(float(nz)/per)):
   for tx in int(ceil(float(nx)/per)):
    var t = MeshInstance3D.new()
    t.name = "FarTile_%d_%d" % [tx,tz]
    t.mesh = tm
    t.material_override = material
    t.position = Vector3(origin.x+(tx+0.5)*TILE,0,origin.y+(tz+0.5)*TILE)
    t.custom_aabb = AABB(Vector3(-TILE*0.5,-20,-TILE*0.5),Vector3(TILE,120,TILE))
    t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    t.visibility_range_begin = TILE_FROM
    t.visibility_range_begin_margin = 150.0
    add_child(t)
    tiles[Vector2i(tx,tz)] = t
 far_tiles = tiles.size()
 for cz in nz:
  for cx in nx:
   var node = Node3D.new()
   node.position = Vector3(origin.x+(cx+0.5)*CHUNK,0,origin.y+(cz+0.5)*CHUNK)
   add_child(node)
   var tile = tiles.get(Vector2i(cx/per,cz/per))
   for i in LODS.size():
    var mi = MeshInstance3D.new()
    mi.mesh = meshes[i]
    mi.material_override = material
    mi.custom_aabb = AABB(Vector3(-CHUNK*0.5,-20,-CHUNK*0.5),Vector3(CHUNK,120,CHUNK))
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    mi.visibility_range_begin = LODS[i][1]
    mi.visibility_range_end = LODS[i][2]
    node.add_child(mi)
    if tile != null: mi.visibility_parent = NodePath("../../"+str(tile.name)) # chunk -> map view -> tile
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
 if AssetManifest.is_landmark(sid):
  spec.landmark_radius = float(AssetManifest.landmarks()[sid].get("radius",LANDMARK_RADIUS))
  spec.landmark_walls = AssetManifest.landmark_has_walls(sid,clampi(int(st.level),1,3))
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
 var open = grid.names.find("open")
 var rocky = [grid.names.find("hills"),grid.names.find("mountain")]
 var terrain: PackedByteArray = grid.terrain
 var road: PackedByteArray = grid.road
 # Open-land trees keep clear of towns: the settlements near this chunk and their clear radii.
 var clear = []
 var cc = origin+Vector2((k.x+0.5)*CHUNK,(k.y+0.5)*CHUNK)
 for sid in WorldMap.settlements_near(cc,CHUNK+120.0):
  var t0 = str(state.settlements[sid].type) if state.settlements.has(sid) else "city"
  clear.append([WorldMap.settlement_position(sid),float(Sprawl.sprawl_data().footprint.radius.get(t0,60))*OPEN_TREE_CLEAR])
 for z in range(z0,mini(z0+n,rows)):
  for x in range(x0,mini(x0+n,cols)):
   var i = z*cols+x
   var t = terrain[i]
   var h = _hash(x,z)
   if t != forest:
    # Boulders on the hills and below the cliffs.
    if t in rocky and h<ROCK_DENSITY: _plant(groups,"nature.rock_%d" % (1+int(h*977.0)%3),x,z,h,Color("ffffff"),[1.0,1.0],2.2)
    # Countryside trees (owner 2026-10-06, A8): lone trees and small groves on open land in the
    # land's own biome, clumped by a coarse hash, never on roads, rivers or inside a town.
    if t == open and road[i] == 0 and h<OPEN_TREE_DENSITY*(0.25+1.75*_hash(x/14,z/14)):
     var po = origin+Vector2(x,z)*cell
     if rivers.get_pixel(x,z).r>0.12 or clear.any(func(cl): return po.distance_to(cl[0])<cl[1]): continue
     _plant_biome_tree(groups,po,x,z,h)
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
   # Snowy climates frost the trees (the terrain shader snows on the canopy carpet the same way).
   var tint = Color(fo.tint)
   if climate_img != null:
    var cs = climate_img.get_pixel(clampi(x/CLIMATE_STEP,0,climate_img.get_width()-1),clampi(z/CLIMATE_STEP,0,climate_img.get_height()-1))
    tint = tint.lerp(Color(0.86,0.9,0.95),cs.r*0.5)
   _plant(groups,_pick_tree(fo.trees,fmod(h*4111.0,1.0)),x,z,h,tint,fo.scale,7.0)
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

# A tree of the land's biome at a cell (its culture's forest profile, frosted in snowy climates).
func _plant_biome_tree(groups: Dictionary,p: Vector2,x: int,z: int,h: float):
 var sid = WorldMap.region_at(p)
 var cul = "medieval"
 if state.land.has(sid):
  var e = state.land[sid]
  cul = e.to if fmod(h*7919.0,1.0)<float(e.value) else e.from
 var fo = Sprawl.culture(cul).forest
 if fmod(h*31.0,1.0)>float(fo.density): return
 var tint = Color(fo.tint)
 if climate_img != null:
  var cs = climate_img.get_pixel(clampi(x/CLIMATE_STEP,0,climate_img.get_width()-1),clampi(z/CLIMATE_STEP,0,climate_img.get_height()-1))
  tint = tint.lerp(Color(0.86,0.9,0.95),cs.r*0.5)
 _plant(groups,_pick_tree(fo.trees,fmod(h*4111.0,1.0)),x,z,h,tint,fo.scale,7.0)

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
# drawn as a colossal stone wall following the ground (owner 2026-10-06: not a flat slab): a battered
# plinth, a curtain with buttresses on both faces and crenellations on both parapets every WALL_STEP
# metres, a tower with a crenellated top and a roofed turret every WALL_TOWER metres, and at every
# pass a fortified gatehouse: two great flanking towers and an arched gate block spanning the road
# (high above it, so the pass stays open; movement reads only the baked grid). MultiMeshes with vertex
# colours, so the whole wall costs a handful of draw calls.
const WALL_STEP = 10.0
const WALL_TOWER = 120.0
const WALL_HEIGHT = 24.0
const WALL_DEPTH = 9.0
const WALL_STONE = Color("7a7771")
const WALL_DARK = Color("5a5752")
const WALL_ROOF = Color("4b5262")
const GATE_GAP = 1.6 # pass half-width in wall steps (as the gap is cut)
var wall_stats := {}

func _make_walls():
 var path = MapRegistry.path("sketch.svg")
 if not FileAccess.file_exists(path): return
 var sk = load("res://map/sketch.gd").parse_file(path)
 var origin = Vector2(MapRegistry.meta().origin[0],MapRegistry.meta().origin[1])
 var blocks = []
 var towers = []
 var gate_towers = []
 var gates = []
 var gaps = []
 for e in sk.layers.get("passes",[]): gaps.append_array(Array(e.points).map(func(p): return origin+p))
 for e in sk.layers.get("ranges",[]):
  if str(e.data.get("kind","")) != "wall": continue
  var since_tower = WALL_TOWER*0.5
  var was_gap = false
  var last_xf = null
  for i in range(1,e.points.size()):
   var a: Vector2 = origin+e.points[i-1]
   var b: Vector2 = origin+e.points[i]
   var n = maxi(1,int(a.distance_to(b)/WALL_STEP))
   for k in n:
    var p = a.lerp(b,(k+0.5)/n)
    var yaw = atan2(b.x-a.x,b.y-a.y)
    var ground = minf(minf(height_at(p.x,p.y),height_at(p.x+cos(yaw)*4.0,p.y-sin(yaw)*4.0)),height_at(p.x-cos(yaw)*4.0,p.y+sin(yaw)*4.0))
    var xf = Transform3D(Basis(Vector3.UP,yaw),Vector3(p.x,ground-6.0,p.y))
    var gap = gaps.any(func(q): return q.distance_to(p)<WALL_STEP*GATE_GAP)
    if gap and not was_gap:
     if last_xf != null: gate_towers.append(last_xf) # the gate's near tower
     # The gate block across the pass, at the pass point nearest the wall.
     var q = gaps[0]
     for g in gaps:
      if g.distance_to(p)<q.distance_to(p): q = g
     gates.append(Transform3D(Basis(Vector3.UP,yaw),Vector3(q.x,height_at(q.x,q.y),q.y)))
    if not gap and was_gap: gate_towers.append(xf) # ... and its far tower
    was_gap = gap
    if gap: continue
    last_xf = xf
    since_tower += a.distance_to(b)/n
    if since_tower>=WALL_TOWER:
     towers.append(xf)
     since_tower = 0.0
    else: blocks.append(xf)
 if blocks.is_empty() and towers.is_empty(): return
 var root = Node3D.new()
 root.name = "GreatWalls"
 add_child(root)
 for set in [[blocks,_wall_block_mesh()],[towers,_wall_tower_mesh(false)],[gate_towers,_wall_tower_mesh(true)],[gates,_wall_gate_mesh()]]:
  if set[0].is_empty(): continue
  var mm = MultiMesh.new()
  mm.transform_format = MultiMesh.TRANSFORM_3D
  mm.mesh = set[1]
  mm.instance_count = set[0].size()
  for i in set[0].size(): mm.set_instance_transform(i,set[0][i])
  var mi = MultiMeshInstance3D.new()
  mi.multimesh = mm
  root.add_child(mi)
 wall_stats = {"blocks":blocks.size(),"towers":towers.size(),"gate_towers":gate_towers.size(),"gates":gates.size()}

func _wall_mat() -> StandardMaterial3D:
 var m = StandardMaterial3D.new()
 m.vertex_color_use_as_albedo = true
 m.roughness = 0.95
 return m

# A box into the surface tool, in one vertex colour.
func _box_into(st: SurfaceTool,size: Vector3,center: Vector3,col := WALL_STONE):
 var bm = BoxMesh.new()
 bm.size = size
 var arr = bm.get_mesh_arrays()
 var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
 var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
 var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
 for i in idx:
  st.set_color(col)
  st.set_normal(norms[i])
  st.add_vertex(verts[i]+center)

# A pyramid roof (four faces) of half-width w and height hgt with its base centre at c.
func _pyramid_into(st: SurfaceTool,w: float,hgt: float,c: Vector3,col: Color):
 var top = c+Vector3(0,hgt,0)
 var corners = [c+Vector3(-w,0,-w),c+Vector3(-w,0,w),c+Vector3(w,0,w),c+Vector3(w,0,-w)]
 for i in 4:
  var p0: Vector3 = corners[i]
  var p1: Vector3 = corners[(i+1)%4]
  var nrm = ((p0+p1)*0.5-c).normalized()*0.7+Vector3(0,0.7,0)
  for v in [p0,p1,top]:
   st.set_color(col)
   st.set_normal(nrm.normalized())
   st.add_vertex(v)

func _commit(st: SurfaceTool) -> ArrayMesh:
 var m = st.commit()
 m.surface_set_material(0,_wall_mat())
 return m

# One wall block: WALL_STEP long along its local z; a darker battered plinth, the curtain, a
# buttress on each face, a parapet with four merlons on each side and the wall walk.
func _wall_block_mesh() -> ArrayMesh:
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 _box_into(st,Vector3(WALL_DEPTH+4.0,8.0,WALL_STEP+0.2),Vector3(0,4.0,0),WALL_DARK)
 _box_into(st,Vector3(WALL_DEPTH,WALL_HEIGHT+6.0,WALL_STEP+0.2),Vector3(0,(WALL_HEIGHT+6.0)*0.5,0))
 for s in [-1.0,1.0]:
  _box_into(st,Vector3(2.0,WALL_HEIGHT*0.7,2.6),Vector3(s*(WALL_DEPTH*0.5+1.0),WALL_HEIGHT*0.35+4.0,0),WALL_DARK.lightened(0.08)) # buttress
  _box_into(st,Vector3(1.2,1.0,WALL_STEP+0.2),Vector3(s*(WALL_DEPTH*0.5-0.6),WALL_HEIGHT+6.5,0),WALL_STONE.lightened(0.06)) # parapet
  for k in 4: _box_into(st,Vector3(1.3,2.0,1.4),Vector3(s*(WALL_DEPTH*0.5-0.6),WALL_HEIGHT+8.0,-WALL_STEP*0.375+k*WALL_STEP*0.25),WALL_STONE.lightened(0.06))
 _box_into(st,Vector3(WALL_DEPTH-2.4,0.3,WALL_STEP+0.2),Vector3(0,WALL_HEIGHT+6.1,0),WALL_DARK) # the wall walk
 return _commit(st)

# A tower: a square shaft on a plinth, a crenellated top and a roofed turret; gate towers are larger.
func _wall_tower_mesh(gate: bool) -> ArrayMesh:
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var w = WALL_DEPTH+(12.0 if gate else 8.0)
 var hh = WALL_HEIGHT+(24.0 if gate else 16.0)
 _box_into(st,Vector3(w+3.0,10.0,w+3.0),Vector3(0,5.0,0),WALL_DARK)
 _box_into(st,Vector3(w,hh,w),Vector3(0,hh*0.5,0))
 _box_into(st,Vector3(w+1.4,1.2,w+1.4),Vector3(0,hh+0.6,0),WALL_STONE.lightened(0.05))
 var per = 5 if gate else 4
 for side in 4:
  for k in per:
   var t = -w*0.5+0.9+k*(w-1.8)/(per-1)
   var off = [Vector3(t,0,-w*0.5),Vector3(w*0.5,0,t),Vector3(-t,0,w*0.5),Vector3(-w*0.5,0,-t)][side]
   _box_into(st,Vector3(1.6,2.2,1.6),off+Vector3(0,hh+2.3,0),WALL_STONE.lightened(0.06))
 var tw = w*0.36
 _box_into(st,Vector3(tw*2.0,6.0,tw*2.0),Vector3(0,hh+4.2,0))
 _pyramid_into(st,tw*1.25,tw*2.2,Vector3(0,hh+7.2,0),WALL_ROOF)
 if gate:
  for s in [-1.0,1.0]: _box_into(st,Vector3(1.0,5.0,0.4),Vector3(s*w*0.25,hh*0.6,-w*0.5-0.1),Color("231f1a")) # arrow slits
 return _commit(st)

# The gate block across a pass: a high span (its underside well above the road), battlements on top
# and a dark portcullis band, about the pass's width.
func _wall_gate_mesh() -> ArrayMesh:
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var span = WALL_STEP*GATE_GAP*2.0
 var under = WALL_HEIGHT*0.55
 _box_into(st,Vector3(WALL_DEPTH+2.0,WALL_HEIGHT+8.0-under,span),Vector3(0,under+(WALL_HEIGHT+8.0-under)*0.5,0))
 _box_into(st,Vector3(WALL_DEPTH+2.2,3.0,span*0.8),Vector3(0,under+1.0,0),Color("231f1a")) # the portcullis
 for s in [-1.0,1.0]:
  for k in 6: _box_into(st,Vector3(1.4,2.2,1.6),Vector3(s*(WALL_DEPTH*0.5+0.4),WALL_HEIGHT+9.1,-span*0.42+k*span*0.168),WALL_STONE.lightened(0.06))
 return _commit(st)
