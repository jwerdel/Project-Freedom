extends Node3D

const ProtoKit = preload("res://visuals/common/proto_kit.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const COMMANDER_ARMY = "aurek_host"
const WorldMap = preload("res://core/world_map.gd")
const UiData = preload("res://core/ui_data.gd")
const Movement = preload("res://core/movement.gd")
const PortraitStudio = preload("res://core/portrait_studio.gd")
const CampaignUI = preload("res://ui/campaign_ui.gd")
const UiKit = preload("res://ui/ui_kit.gd")
const SettlementBanner = preload("res://ui/settlement_banner.gd")
const TerritoryOverlay = preload("res://visuals/terrain/territory_overlay.gd")
const MovementOverlay = preload("res://ui/movement_overlay.gd")
const WALK_SPEED = 12.0 # map meters per second while the figure walks (presentation only)
# Overview camera (Home). Framed so the coast and Goldspire's sea face sit above the bottom panel.
const OVERVIEW_TARGET = Vector3(10,3,21)
const OVERVIEW_YAW = 0.08
const OVERVIEW_PITCH = 0.85
const OVERVIEW_DISTANCE = 155.0
const ROAD_VISUALS = ["road.dirt","road.gravel","road.stone"]

const CITY_ID = "greyhaven"
const CITY = Vector2(-12, 6)
const KEEP = Vector2(48, -35)
const VILLAGE = Vector2(-56, -24)
# Goldspire Rock stands in the sea at the coast; its sheer sea face looks toward the overview camera.
const GOLDSPIRE_ID = "goldspire_rock"
const GOLDSPIRE = Vector2(44, 36.5)
const GOLDSPIRE_CLEAR = 20.0
var rng = RandomNumberGenerator.new()
var noise = FastNoiseLite.new()
var detail = FastNoiseLite.new()
var camera: Camera3D
var target = OVERVIEW_TARGET
var yaw = OVERVIEW_YAW
var pitch = OVERVIEW_PITCH
var distance = OVERVIEW_DISTANCE
var desired_distance = OVERVIEW_DISTANCE
var time = 0.0
var paused = false
var city_level = 2
var road_level = 1
var city_root: Node3D
var roads_root: Node3D
var goldspire_level = 2
var goldspire_root: Node3D
var traffic: Array = []
var road_curves: Array = []
var forest_points: Array = [] # tree positions (x/z), used only by the movement-grid bake
var flags: Array = []
var sun: DirectionalLight3D
var environment: Environment
var dusk = false
var screenshot_requested = false
var capture_frames = 0
var capture_mode = false
var kit
var road_material: StandardMaterial3D


var commander: Node3D
var pins: Array = []
var ui
var ui_data
var studio
var pins_root: Control
var settlement_anchors = {}
var overlays = {"borders":true,"settlements":true,"armies":true}
var press_pos = Vector2.ZERO
var terrain_material: ShaderMaterial
var minimap
var movement_overlay
var walks = {}           # army id -> figure walking a path: {points, dist, total}
var army_figures = {}    # army id -> map figure (the commander visual, banner in faction colors)
var follow_army = false   # camera follows the selected army
var right_press_pos = Vector2.ZERO
var preview_key = Vector2i(1<<20,0)
var preview_text = ""
var forced_preview = null # capture flag --preview=x,z: preview this point instead of the mouse

func _ready():
 rng.seed = 87231
 noise.seed = 441
 noise.frequency = 0.023
 noise.fractal_octaves = 5
 detail.seed = 272
 detail.frequency = 0.12
 detail.fractal_octaves = 3
 capture_mode = "--capture" in OS.get_cmdline_user_args()
 kit = ProtoKit.shared()
 make_environment()
 make_terrain()
 make_sea()
 make_roads()
 make_city()
 make_fortress(KEEP)
 make_village()
 make_farms()
 make_forest()
 make_coastal_rocks()
 make_harbor()
 kit.batch(self,[city_root,roads_root])
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--goldspire-stage="): goldspire_level = clampi(int(arg.get_slice("=",1)),1,3)
 make_goldspire()
 make_traffic()
 if "--bake-movement-grid" in OS.get_cmdline_user_args():
  bake_movement_grid()
  set_process(false)
  get_tree().quit()
  return
 make_commander()
 make_ui()
 camera_update(1.0)
 if "--developed" in OS.get_cmdline_user_args():
  city_level = 3
  road_level = 2
  make_city()
  make_roads()
  ui_data.set_settlement_level(CITY_ID,city_level)
 if "--closeup" in OS.get_cmdline_user_args():
  target = Vector3(CITY.x, height_at(CITY.x,CITY.y), CITY.y)
  distance = 42
  desired_distance = 42
  yaw = -0.5
 if "--hero" in OS.get_cmdline_user_args():
  target = commander.position + Vector3(0,2.8,0)
  distance = 15
  desired_distance = 15
  yaw = 0.35
  pitch = 0.23
 if "--goldspire" in OS.get_cmdline_user_args():
  focus_goldspire()
  distance = desired_distance
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--select="): select_settlement(arg.get_slice("=",1))
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--build=") and ui.selected_settlement != "":
   var b = arg.get_slice("=",1)
   ui_data.start_construction(ui.selected_settlement,int(b.get_slice(":",0)),b.get_slice(":",1))
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--browser=") and ui.selected_settlement != "": ui.open_building_browser(ui.selected_settlement,int(arg.get_slice("=",1)))
 if "--army" in OS.get_cmdline_user_args(): select_army()
 for arg in OS.get_cmdline_user_args():
  var xz = arg.get_slice("=",1).split(",")
  if arg.begins_with("--order="):
   select_army()
   order_army(Vector2(float(xz[0]),float(xz[1])))
   update_walk(1000.0)
  if arg.begins_with("--preview="):
   select_army()
   forced_preview = Vector2(float(xz[0]),float(xz[1]))
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--recruit-queue="):
   for u in arg.get_slice("=",1).split(","): ui_data.recruit(COMMANDER_ARMY,u)
   select_army()
  if arg.begins_with("--select-army="): select_army(arg.get_slice("=",1))
  if arg == "--recruit-panel":
   select_army()
   ui.open_recruitment(COMMANDER_ARMY)
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--view="):
   var v = arg.get_slice("=",1).split(",")
   target = ground(Vector2(float(v[0]),float(v[1])))
   distance = float(v[2])
   desired_distance = distance
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--end-turns="):
   for i in int(arg.get_slice("=",1)):
    ui_data.end_turn()
    update_walk(1000.0)
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--select-after="): select_settlement(arg.get_slice("=",1))
 if "--chronicle" in OS.get_cmdline_user_args(): ui.toggle_chronicle()
 if "--self-test" in OS.get_cmdline_user_args():
  run_checks()
 print("FREEDOM_READY | city=%s road=%s traffic=%s" % [city_level,road_level,traffic.size()])

func make_environment():
 environment = Environment.new()
 environment.background_mode = Environment.BG_SKY
 var sky = Sky.new()
 var skymat = ProceduralSkyMaterial.new()
 skymat.sky_top_color = Color("536f7e")
 skymat.sky_horizon_color = Color("bdc7bd")
 skymat.ground_horizon_color = Color("aabbb4")
 skymat.ground_bottom_color = Color("4e6066")
 sky.sky_material = skymat
 environment.sky = sky
 environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.ambient_light_color = Color("9bb4bd")
 environment.ambient_light_energy = 0.60
 environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 environment.fog_enabled = true
 environment.fog_light_color = Color("98afb0")
 environment.fog_density = 0.00035
 environment.ssao_enabled = true
 environment.ssao_radius = 1.5
 environment.ssao_intensity = 1.3
 var world = WorldEnvironment.new()
 world.environment = environment
 add_child(world)
 sun = DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-43,-34,0)
 sun.light_color = Color("fff0d6")
 sun.light_energy = 1.3
 sun.shadow_enabled = true
 sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
 sun.directional_shadow_max_distance = 250
 sun.shadow_bias = 0.035
 add_child(sun)
 camera = Camera3D.new()
 camera.fov = 43
 camera.near = 0.25
 camera.far = 700
 add_child(camera)
 camera.current = true

func coast(x: float) -> float:
 return 31.0 + sin(x*0.032)*8.0 + sin(x*0.095)*2.2

func height_at(x: float,z: float) -> float:
 var n = noise.get_noise_2d(x,z)
 var h = 3.7 + n*4.0 + detail.get_noise_2d(x,z)*0.65
 var mountain = exp(-pow((z+88.0)/26.0,2.0))
 h += mountain*(13.0+abs(noise.get_noise_2d(x*1.7,z*1.5))*43.0)
 h += exp(-((x-52)*(x-52)+(z+35)*(z+35))/350.0)*6.2
 for p in [CITY,VILLAGE,KEEP]:
  var d = Vector2(x,z).distance_to(p)
  var flat = 4.4 if p != KEEP else 9.4
  h = lerpf(flat,h,smoothstep(8.0 if p==CITY else 4.0,15.0 if p==CITY else 8.0,d))
 var shore = coast(x)-z
 h = lerpf(-3.0,h,smoothstep(-6.0,7.0,shore))
 return h

func ground(p: Vector2, offset = 0.0) -> Vector3:
 return Vector3(p.x,height_at(p.x,p.y)+offset,p.y)

func make_terrain():
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var size_x = 280.0
 var size_z = 270.0
 var nx = 280
 var nz = 270
 for z in range(nz+1):
  for x in range(nx+1):
   var px = x*size_x/nx-size_x/2
   var pz = z*size_z/nz-size_z/2
   st.set_uv(Vector2(px,pz)*0.1)
   var normal = Vector3(height_at(px-0.3,pz)-height_at(px+0.3,pz),0.6,height_at(px,pz-0.3)-height_at(px,pz+0.3)).normalized()
   st.set_normal(normal)
   st.set_tangent(Plane(Vector3.RIGHT,1))
   st.add_vertex(Vector3(px,height_at(px,pz),pz))
 for z in range(nz):
  for x in range(nx):
   var a = z*(nx+1)+x
   for i in [a,a+1,a+nx+1,a+1,a+nx+2,a+nx+1]:
    st.add_index(i)
 var material = ShaderMaterial.new()
 material.shader = load("res://terrain.gdshader")
 material.set_shader_parameter("grass",load("res://assets/aerial_grass_rock_Diffuse.jpg"))
 material.set_shader_parameter("rock",load("res://assets/rocky_terrain_Diffuse.jpg"))
 material.set_shader_parameter("sand",load("res://assets/coast_sand_01_Diffuse.jpg"))
 material.set_shader_parameter("grass_normal",load("res://assets/aerial_grass_rock_nor_gl.jpg"))
 # Faction tint and glowing territory borders, rasterized from data/provinces.json.
 material.set_shader_parameter("territory_tint",TerritoryOverlay.tint_texture())
 material.set_shader_parameter("territory_border",TerritoryOverlay.border_texture())
 material.set_shader_parameter("territory_rect",TerritoryOverlay.rect_uniform())
 material.set_shader_parameter("territory_on",1.0)
 terrain_material = material
 kit.add_mesh(self,st.commit(),material)

func make_sea():
 var plane = PlaneMesh.new()
 plane.size = Vector2(750,750)
 plane.subdivide_width = 100
 plane.subdivide_depth = 100
 var m = ShaderMaterial.new()
 m.shader = load("res://water.gdshader")
 kit.add_mesh(self,plane,m,Vector3(0,0,120))
 # Thin broken ribbons of foam delineate the irregular shore.
 var foam = kit.mat(Color("a7c3b6"))
 for j in range(2):
  var st = SurfaceTool.new()
  st.begin(Mesh.PRIMITIVE_TRIANGLES)
  for x in range(-130,130):
   var z = coast(x)+0.2+j*1.3
   var z1 = coast(x+1)+0.2+j*1.3
   var w = 0.13+0.09*sin(x*1.7)
   for v in [Vector3(x,0.09,z),Vector3(x+1,0.09,z1),Vector3(x,0.09,z+w),Vector3(x+1,0.09,z1),Vector3(x+1,0.09,z1+w),Vector3(x,0.09,z+w)]:
    st.add_vertex(v)
  st.generate_normals()
  kit.add_mesh(self,st.commit(),foam)

func curve_from(points: Array) -> Curve3D:
 var curve = Curve3D.new()
 curve.bake_interval = 0.65
 for i in range(points.size()):
  var p = ground(points[i],0.12)
  var tangent = Vector3.ZERO
  if i>0 and i<points.size()-1:
   tangent = (ground(points[i+1])-ground(points[i-1]))*0.16
  curve.add_point(p,-tangent,tangent)
 return curve

func make_roads():
 if roads_root:
  remove_child(roads_root)
  roads_root.queue_free()
 roads_root = AssetManifest.instantiate(ROAD_VISUALS[road_level])
 add_child(roads_root)
 road_curves.clear()
 # The road network is gameplay data (movement costs); the map draws the same polylines.
 for road in Movement.data().roads.network:
  var pts = []
  for p in road.points: pts.append(Vector2(p[0],p[1]))
  road_curves.append(curve_from(pts))
 roads_root.build({"curves":road_curves,"height":height_at})
 road_material = roads_root.surface_material

func make_city():
 if city_root:
  remove_child(city_root)
  city_root.queue_free()
 city_root = AssetManifest.instantiate_settlement(CITY_ID,city_level)
 add_child(city_root)
 city_root.position = ground(CITY)
 city_root.build({"height":height_at,"plaza_material":road_material})

func make_fortress(p: Vector2):
 var n = AssetManifest.instantiate("settlement.fortress")
 add_child(n)
 n.position = ground(p)

func make_village():
 var village = AssetManifest.instantiate("settlement.village")
 add_child(village)
 village.build({"center":VILLAGE,"ground":ground,"rng":rng})
 flags.append_array(village.rotors)

func make_farms():
 var farms = AssetManifest.instantiate("terrain.farmland")
 add_child(farms)
 farms.build({"center":Vector2(-37.5,-9),"half_size":Vector2(16,14.5),"angle":0.21,"seed":5113,"height":height_at,"ground":ground,"open":farmland_open})

# 1 where fields may grow, fading to 0 on roads and around the village and city.
func farmland_open(p: Vector2) -> float:
 var open = smoothstep(7.5,10.5,p.distance_to(VILLAGE))*smoothstep(15.5,18.0,p.distance_to(CITY))
 var g = ground(p)
 for c in road_curves:
  var q = c.get_closest_point(g)
  open *= smoothstep(1.15,2.0,Vector2(q.x,q.z).distance_to(p))
 return open

func make_forest():
 var source = AssetManifest.instantiate("nature.tree")
 var meshes: Array = []
 for child in source.find_children("*", "MeshInstance3D", true, false):
  meshes.append(child.mesh)
 var groups: Array = [[],[],[]]
 for i in range(2200):
  var p = Vector2(rng.randf_range(-118,118),rng.randf_range(-100,25))
  var h = height_at(p.x,p.y)
  if h<2.5 or h>25: continue
  if noise.get_noise_2d(p.x*2+900,p.y*2)<-0.02: continue
  if p.distance_to(CITY)<17 or p.distance_to(VILLAGE)<10 or p.distance_to(KEEP)<10: continue
  if p.x>-53 and p.x<-24 and p.y>-23 and p.y<7: continue
  var near_road = false
  for c in road_curves:
   if c.get_closest_point(ground(p)).distance_to(ground(p))<2.6: near_road=true
  if near_road: continue
  var idx = i%meshes.size()
  var base_height = meshes[idx].get_aabb().size.y
  var scale_v = rng.randf_range(3.5,6.8)/base_height
  var basis = Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_v)
  # Checked after the rng draws so the rest of the layout is unchanged.
  if p.distance_to(GOLDSPIRE)<GOLDSPIRE_CLEAR: continue
  groups[idx].append(Transform3D(basis,Vector3(p.x,h,p.y)))
  forest_points.append(p)
 for i in range(meshes.size()):
  make_multimesh(meshes[i],null,groups[i],false)
 source.free()

func make_multimesh(mesh: Mesh, material: Material, transforms: Array, colors: bool):
 var mm = MultiMesh.new()
 mm.transform_format = MultiMesh.TRANSFORM_3D
 mm.use_colors = colors
 mm.mesh = mesh
 mm.instance_count = transforms.size()
 for i in range(transforms.size()):
  mm.set_instance_transform(i,transforms[i])
  if colors: mm.set_instance_color(i,Color(rng.randf_range(0.8,1.25),rng.randf_range(0.9,1.18),rng.randf_range(0.70,1.0)))
 var n = MultiMeshInstance3D.new()
 n.multimesh = mm
 n.material_override = material
 add_child(n)

func make_coastal_rocks():
 var source = AssetManifest.instantiate("nature.rock")
 var meshes: Array = []
 for child in source.find_children("*", "MeshInstance3D", true, false):
  meshes.append(child.mesh)
 var groups: Array = []
 for m in meshes: groups.append([])
 for i in range(100):
  var x = rng.randf_range(-120,120)
  var p = Vector2(x,coast(x)+rng.randf_range(-3,4))
  if abs(x+18)<7: continue
  var s = rng.randf_range(0.3,1.4)
  # Same three rng draws as the old sphere rocks' rotation, so later layout (harbor, traffic) is unchanged.
  var yaw = rng.randf()*TAU
  var tilt = Vector3(rng.randf()-0.5,0,rng.randf()-0.5)*0.3
  var idx = i%meshes.size()
  var size = meshes[idx].get_aabb().size
  var scale_v = 2.0*s/max(size.x,size.z)
  var basis = Basis.from_euler(tilt)*Basis(Vector3.UP,yaw).scaled(Vector3(1,0.8,1)*scale_v)
  if p.distance_to(GOLDSPIRE)<GOLDSPIRE_CLEAR: continue
  groups[idx].append(Transform3D(basis,ground(p,-0.1*s)))
 for i in range(meshes.size()):
  make_multimesh(meshes[i],null,groups[i],false)
 source.free()

func make_goldspire():
 if goldspire_root:
  remove_child(goldspire_root)
  goldspire_root.queue_free()
 goldspire_root = AssetManifest.instantiate_settlement(GOLDSPIRE_ID,goldspire_level)
 add_child(goldspire_root)
 goldspire_root.position = Vector3(GOLDSPIRE.x,0,GOLDSPIRE.y)
 goldspire_root.build({"height":func(x,z): return height_at(GOLDSPIRE.x+x,GOLDSPIRE.y+z)})

func cycle_goldspire():
 goldspire_level = goldspire_level%3+1
 make_goldspire()
 if ui_data: ui_data.set_settlement_level(GOLDSPIRE_ID,goldspire_level)
 if minimap: minimap.refresh()
 if ui: ui.toast(["Goldspire Rock: mine tunnels glow beneath a lone summit tower.","Goldspire Rock: carved halls, a walled summit and a harbor at its foot.","Goldspire Rock: the whole sea face is terraced with halls and gold-roofed towers."][goldspire_level-1])

# Camera bookmark (G): Goldspire's sea face from the southwest.
func focus_goldspire():
 target = Vector3(GOLDSPIRE.x,9,GOLDSPIRE.y)
 desired_distance = 64
 yaw = 0.42
 pitch = 0.36

func make_harbor():
 var harbor = AssetManifest.instantiate("settlement.harbor")
 add_child(harbor)
 harbor.build({"coast":coast,"ground":ground,"rng":rng})

func make_traffic():
 for i in range(6):
  var n = AssetManifest.instantiate("commerce.wagon")
  add_child(n)
  traffic.append({"node":n,"curve":i%2,"offset":i*0.163,"sea":false})
 for i in range(4):
  var n = AssetManifest.instantiate("commerce.ship")
  add_child(n)
  traffic.append({"node":n,"offset":i*0.25,"sea":true})

func make_commander():
 commander = AssetManifest.instantiate("unit.commander")
 add_child(commander)
 commander.position = ground(Vector2(2,0),0.18)
 commander.rotation.y = 0.5
 # The army this commander leads (data/armies/); shown in the army panel.
 commander.set_meta("army_id",COMMANDER_ARMY)

# --- Campaign UI ---------------------------------------------------------------
# The TW:WH3-style shell lives in ui/campaign_ui.gd and reads only from UiData (core/ui_data.gd).

func make_ui():
 var layer = CanvasLayer.new()
 add_child(layer)
 studio = PortraitStudio.new()
 add_child(studio)
 ui_data = UiData.new()
 ui_data.set_settlement_level(CITY_ID,city_level)
 ui_data.set_settlement_level(GOLDSPIRE_ID,goldspire_level)
 pins_root = Control.new()
 pins_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 pins_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
 layer.add_child(pins_root)
 ui = CampaignUI.new()
 layer.add_child(ui)
 ui.setup(ui_data,studio)
 pins_root.theme = ui.theme
 ui.end_turn_requested.connect(end_turn)
 ui.settlement_selected.connect(focus_settlement)
 ui.overlay_toggled.connect(set_overlay)
 settlement_anchors = {CITY_ID:ground(CITY,6),"crownwatch":ground(KEEP,6),"willowmere":ground(VILLAGE,5),GOLDSPIRE_ID:Vector3(GOLDSPIRE.x,27,GOLDSPIRE.y)}
 for id in settlement_anchors:
  var b = SettlementBanner.new(ui_data.settlement(id))
  b.pressed.connect(select_settlement.bind(id))
  pins_root.add_child(b)
  pins.append({"button":b,"world":settlement_anchors[id],"id":id})
 ui_data.changed.connect(func():
  for p in pins: p.button.update_settlement(ui_data.settlement(p.id)))
 ui_data.changed.connect(sync_settlement_visuals)
 minimap = ui.setup_minimap(get_viewport().world_3d,TerritoryOverlay.RECT,camera_footprint)
 minimap.minimap_clicked.connect(func(p: Vector2): target = Vector3(clampf(p.x,-105,105),height_at(p.x,p.y),clampf(p.y,-90,65)))
 movement_overlay = MovementOverlay.new()
 add_child(movement_overlay)
 movement_overlay.setup(height_at)
 ui_data.army_moved.connect(_on_army_moved)
 ui_data.changed.connect(refresh_army_overlays)
 ui.follow_toggled.connect(func(on): follow_army = on)
 ui.cancel_order_requested.connect(func(id): ui_data.cancel_army_order(id))
 ui.army_raised.connect(func(id):
  refresh_army_overlays()
  select_army(id))
 refresh_army_overlays()

# Settlement visuals follow the campaign data: a finished main-building upgrade raises the level,
# and the settlement switches to that growth stage (generic stages or its landmark's own).
func sync_settlement_visuals():
 var city_stage = ui_data.settlement_visual_stage(CITY_ID).stage
 if city_stage != city_level:
  city_level = city_stage
  make_city()
 var goldspire_stage = ui_data.settlement_visual_stage(GOLDSPIRE_ID).stage
 if goldspire_stage != goldspire_level:
  goldspire_level = goldspire_stage
  make_goldspire()
 if minimap: minimap.refresh()

func select_settlement(id: String):
 ui.show_settlement(id)
 focus_settlement(id)

func focus_settlement(id: String):
 if id == GOLDSPIRE_ID:
  focus_goldspire()
  return
 var a = settlement_anchors[id]
 focus_at(ground(Vector2(a.x,a.z)),48)

func select_army(id := COMMANDER_ARMY):
 if not army_figures.has(id): return
 ui.show_army(id,army_location(id))
 focus_at(army_figures[id].position+Vector3(0,2.2,0),26.0)
 refresh_army_overlays()

# C: select the next of the player's armies.
func cycle_player_army():
 var own = []
 for id in ui_data.army_ids():
  if ui_data.army(id).player_owned: own.append(id)
 if own.is_empty(): return
 var i = own.find(selected_army_id())
 select_army(own[(i+1)%own.size()])

func army_location(id := "") -> String:
 if id == "": id = selected_army_id() if selected_army_id() != "" else COMMANDER_ARMY
 var p = army_figures[id].position if army_figures.has(id) else Vector3.ZERO
 var region = WorldMap.region_at(Vector2(p.x,p.z))
 return WorldMap.province(WorldMap.province_of(region)).get("name","")

# --- Army movement (rules: core/movement.gd via UiData; drawing: ui/movement_overlay.gd) ------
# Every army has a map figure (faction-colored banner). Select with left click or C (cycles your
# armies); hovering the map previews the selected army's path; right click (without dragging)
# gives the order; Backspace or the army panel cancels a standing order; F toggles camera follow.
# Other factions' armies can be selected to inspect, not ordered.

func selected_army_id() -> String:
 return ui.selected_army if ui != null and army_figures.has(ui.selected_army) else ""

# True when the selected army is the player's (it can be previewed and ordered).
func army_selected() -> bool:
 var id = selected_army_id()
 return id != "" and ui_data.army(id).player_owned

func army_ground(p: Vector2,lift := 0.18) -> Vector3:
 return Vector3(p.x,maxf(height_at(p.x,p.y),0.0)+lift,p.y)

# One figure per army in the campaign state; new armies get one, disbanded ones lose theirs.
func sync_army_figures():
 for id in ui_data.army_ids():
  if army_figures.has(id): continue
  var f = commander if id == COMMANDER_ARMY and commander != null else AssetManifest.instantiate("unit.commander")
  if f.get_parent() == null: add_child(f)
  f.set_meta("army_id",id)
  f.set_banner_color(Color(ui_data.army(id).faction_data.primary))
  f.visible = overlays.armies
  army_figures[id] = f
 for id in army_figures.keys():
  if not id in ui_data.army_ids():
   army_figures[id].queue_free()
   army_figures.erase(id)
 place_commander()

# Put each figure where the campaign state says its army is (garrisoned armies stand in the town).
func place_commander():
 for id in army_figures:
  if walks.has(id): continue
  army_figures[id].position = army_ground(ui_data.army_movement(id).position)

func refresh_army_overlays():
 if movement_overlay == null: return
 sync_army_figures()
 # Standing orders of the player's armies stay visible on the map.
 for id in army_figures:
  var path = ui_data.order_path(id)
  if not walks.has(id) and path.points.size()>1 and ui_data.army(id).player_owned: movement_overlay.show_path("order:"+id,path.points,path.turns,true)
  else: movement_overlay.clear("order:"+id)
 if army_selected() and not walks.has(selected_army_id()):
  var area = ui_data.reachable_area(selected_army_id())
  movement_overlay.show_reachable(area.centers,area.cell)
 else:
  movement_overlay.clear("reach")
  movement_overlay.clear("preview")
 preview_key = Vector2i(1<<20,0)

# Ground point under the mouse (x/z), marching the camera ray over the heightfield; the sea
# surface counts as ground so orders onto water report "impassable".
func ground_point(screen: Vector2) -> Vector2:
 var origin = camera.project_ray_origin(screen)
 var dir = camera.project_ray_normal(screen)
 var t = 0.0
 var prev = 0.0
 while t<700.0:
  var p = origin+dir*t
  if p.y<=maxf(height_at(p.x,p.z),0.0):
   var lo = prev
   var hi = t
   for i in 12:
    var mid = (lo+hi)*0.5
    var q = origin+dir*mid
    if q.y<=maxf(height_at(q.x,q.z),0.0): hi = mid
    else: lo = mid
   var hit = origin+dir*hi
   return Vector2(hit.x,hit.z)
  prev = t
  t += 1.0
 var far = origin+dir*700.0
 return Vector2(far.x,far.z)

# Move target under the mouse: a settlement's or army's position if one is hovered, else the ground.
func move_target(screen: Vector2) -> Vector2:
 var hit = pick(screen)
 if hit.begins_with("army:"):
  var p = army_figures[hit.get_slice(":",1)].position
  return Vector2(p.x,p.z)
 if hit != "": return WorldMap.settlement_position(hit)
 return ground_point(screen)

# Preview the path to `p` (Total War style: this turn green, later turns in warmer colors, turn
# numbers where each turn's walk ends). Returns the hover text.
func preview_move(p: Vector2) -> String:
 var key = Vector2i(floori(p.x),floori(p.y))
 if key == preview_key: return preview_text
 preview_key = key
 var plan = ui_data.plan_move(selected_army_id(),p)
 if not plan.ok:
  movement_overlay.show_blocked(p,plan.reason)
  preview_text = plan.reason
 else:
  movement_overlay.show_path("preview",plan.points,plan.turns)
  var where = " to "+ui_data.settlement(plan.settlement).name if plan.settlement != "" else ""
  preview_text = "Move%s: %s\nRight click to order" % [where,"this turn" if plan.total_turns == 1 else "%d turns" % plan.total_turns]
 return preview_text

func order_army(p: Vector2):
 var r = ui_data.order_move(selected_army_id(),p)
 movement_overlay.clear("preview")
 if not r.ok:
  ui.toast(r.reason)
  return
 if r.total_turns>1: ui.toast("Marching: %d turns to the destination. The order continues each End Turn." % r.total_turns)
 elif r.settlement != "": ui.toast("Marching into %s." % ui_data.settlement(r.settlement).name)

func toggle_follow():
 follow_army = not follow_army
 ui.set_follow(follow_army)
 ui.toast("Camera follow %s." % ("on" if follow_army else "off"))

func _on_army_moved(id: String,walked: Array):
 if walked.size()<2: return
 sync_army_figures()
 if not army_figures.has(id): return
 var total = 0.0
 for i in range(1,walked.size()): total += walked[i-1].distance_to(walked[i])
 walks[id] = {"points":walked,"dist":0.0,"total":total}
 movement_overlay.clear("order:"+id)
 if id == selected_army_id():
  movement_overlay.clear("reach")
  movement_overlay.clear("preview")

# Figures slide along their walked paths with a subtle step bob (the commander is a procedural
# figure without a skeleton; it will be replaced by a rigged model).
func update_walk(delta: float):
 for id in walks.keys():
  var w = walks[id]
  var fig = army_figures[id]
  w.dist = minf(w.total,w.dist+delta*WALK_SPEED)
  var left = w.dist
  var pts = w.points
  var at = pts[-1]
  var dir = Vector2.ZERO
  for i in range(1,pts.size()):
   var seg = pts[i-1].distance_to(pts[i])
   if left<=seg or i == pts.size()-1:
    at = pts[i-1].lerp(pts[i],clampf(left/maxf(seg,0.0001),0,1))
    dir = pts[i]-pts[i-1]
    break
   left -= seg
  fig.position = army_ground(at,0.18+absf(sin(w.dist*1.9))*0.14)
  if dir.length()>0.001: fig.rotation.y = lerp_angle(fig.rotation.y,atan2(dir.x,dir.y),minf(1,delta*10))
  if w.dist>=w.total:
   walks.erase(id)
   place_commander()
   refresh_army_overlays()
   if id == selected_army_id(): ui.show_army(id,army_location(id))

func end_turn():
 ui_data.end_turn()
 var r = ui_data.resources()
 ui.toast("Year %d begins. Treasury %s gold." % [r.year,UiKit.format_int(r.treasury)])

func set_overlay(overlay: String,on: bool):
 overlays[overlay] = on
 if overlay == "armies":
  for id in army_figures: army_figures[id].visible = on
 if overlay == "borders": terrain_material.set_shader_parameter("territory_on",1.0 if on else 0.0)
 if overlay == "settlements": minimap.show_settlements = on
 minimap.refresh()

# Where the camera's view meets the ground (world x/z), for the minimap's view outline.
func camera_footprint() -> PackedVector2Array:
 var out = PackedVector2Array()
 var vp = get_viewport().get_visible_rect().size
 for corner in [Vector2(0,0),Vector2(vp.x,0),vp,Vector2(0,vp.y)]:
  var origin = camera.project_ray_origin(corner)
  var dir = camera.project_ray_normal(corner)
  var t = (3.0-origin.y)/dir.y if dir.y<-0.02 else 600.0
  var p = origin+dir*minf(t,600.0)
  out.append(Vector2(p.x,p.z))
 return out

func upgrade_city():
 city_level = city_level%3+1
 make_city()
 if ui_data: ui_data.set_settlement_level(CITY_ID,city_level)
 if minimap: minimap.refresh()
 if ui: ui.toast(["Greyhaven returns to its original fishing town.","Greyhaven's ramparts rise around its growing streets.","New wards and a high tower transform Greyhaven's skyline."][city_level-1])

func upgrade_roads():
 road_level = (road_level+1)%3
 make_roads()
 if minimap: minimap.refresh()
 if ui: ui.toast(["The coast is linked by dirt tracks.","Gravel roads now connect the coast's settlements.","Stone paving and roadside markers trace the trade network."][road_level])

func toggle_pause():
 paused = not paused
 if ui: ui.toast("Trade traffic paused." if paused else "Trade traffic resumed.")

func toggle_light():
 dusk = not dusk
 sun.light_color = Color("ffbe86") if dusk else Color("fff0d6")
 sun.light_energy = 0.95 if dusk else 1.3
 sun.rotation_degrees.x = -19 if dusk else -43
 environment.ambient_light_energy = 0.42 if dusk else 0.60

func reset_camera():
 target = OVERVIEW_TARGET
 yaw = OVERVIEW_YAW
 pitch = OVERVIEW_PITCH
 desired_distance = OVERVIEW_DISTANCE

func focus_at(p: Vector3,d: float):
 target = p
 desired_distance = d

func request_capture():
 screenshot_requested = true

# What is under the mouse on the map: "army:<id>", a settlement ID, or "".
func pick(screen: Vector2) -> String:
 for id in army_figures:
  var f = army_figures[id]
  if not f.visible or camera.is_position_behind(f.position): continue
  var c = camera.unproject_position(f.position+Vector3(0,2.2,0))
  if c.distance_to(screen)<_screen_radius(f.position,2.6,26): return "army:"+id
 for id in settlement_anchors:
  var a = settlement_anchors[id]
  var center = ground(Vector2(a.x,a.z),2.0) if id != GOLDSPIRE_ID else Vector3(a.x,12,a.z)
  if camera.is_position_behind(center): continue
  if camera.unproject_position(center).distance_to(screen)<_screen_radius(center,13.0 if id==GOLDSPIRE_ID else 9.0,30): return id
 return ""

func _screen_radius(world: Vector3,meters: float,minimum: float) -> float:
 var a = camera.unproject_position(world)
 var b = camera.unproject_position(world+camera.global_basis.x*meters)
 return maxf(a.distance_to(b),minimum)

func hover_text(hit: String) -> String:
 if hit.begins_with("army:"):
  var id = hit.get_slice(":",1)
  var a = ui_data.army(id)
  var m = ui_data.army_movement(id)
  return "%s\n%s · %s\n%d units%s · %s" % [a.commander.name,a.faction_data.name,a.display_name,a.units.size(),(" · garrison of "+m.garrison_name) if m.garrison != "" else "",army_location(id)]
 var s = ui_data.settlement(hit)
 return "%s\n%s\n%s" % [s.name,s.faction.name,s.province_name]

func _unhandled_input(event):
 if event is InputEventMouseButton:
  if event.pressed:
   if event.button_index == MOUSE_BUTTON_WHEEL_UP: desired_distance = clampf(desired_distance*0.88,10,210)
   if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: desired_distance = clampf(desired_distance*1.13,10,210)
   if event.button_index == MOUSE_BUTTON_LEFT: press_pos = event.position
   if event.button_index == MOUSE_BUTTON_RIGHT: right_press_pos = event.position
  elif event.button_index == MOUSE_BUTTON_LEFT and event.position.distance_to(press_pos)<6:
   var hit = pick(event.position)
   if hit.begins_with("army:"): select_army(hit.get_slice(":",1))
   elif hit != "": select_settlement(hit)
  elif event.button_index == MOUSE_BUTTON_RIGHT and event.position.distance_to(right_press_pos)<6 and army_selected():
   order_army(move_target(event.position))
 if event is InputEventMouseMotion:
  if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
   yaw -= event.relative.x*0.005
   pitch = clampf(pitch+event.relative.y*0.004,0.15,1.25)
  if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
   target += (-camera.global_basis.x*event.relative.x+Vector3(camera.global_basis.z.x,0,camera.global_basis.z.z).normalized()*-event.relative.y)*distance*0.0015
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode == KEY_HOME: reset_camera()
  if event.keycode == KEY_SPACE: toggle_pause()
  if event.keycode == KEY_F12: request_capture()
  if event.keycode == KEY_TAB:
   ui.visible = not ui.visible
   pins_root.visible = ui.visible
  if event.keycode == KEY_ESCAPE:
   ui.clear_selection()
   refresh_army_overlays()
   ui.visible = true
   pins_root.visible = true
  if event.keycode == KEY_G: select_settlement(GOLDSPIRE_ID)
  if event.keycode == KEY_C: cycle_player_army()
  if event.keycode == KEY_F: toggle_follow()
  if event.keycode == KEY_BACKSPACE and army_selected(): ui_data.cancel_army_order(COMMANDER_ARMY)
  if event.keycode == KEY_F5: upgrade_city()
  if event.keycode == KEY_F6: cycle_goldspire()
  if event.keycode == KEY_F7: upgrade_roads()
  if event.keycode == KEY_L: toggle_light()

func camera_update(delta: float):
 var dir = Vector3.ZERO
 if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): dir.z-=1
 if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): dir.z+=1
 if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): dir.x-=1
 if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): dir.x+=1
 target += dir.rotated(Vector3.UP,yaw)*delta*distance*0.30
 target.x = clampf(target.x,-105,105)
 target.z = clampf(target.z,-90,65)
 distance = lerpf(distance,desired_distance,minf(1,delta*9))
 var offset = Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
 camera.position = target+offset
 camera.position.y = maxf(camera.position.y,height_at(camera.position.x,camera.position.z)+2.0)
 camera.look_at(target)

func _process(delta):
 if not paused:
  time += delta
  for rotor in flags: rotor.rotation.z += delta*0.3
  for t in traffic:
   var n = t.node
   if t.sea:
    var a = time*0.023+t.offset*TAU
    # Loop stays west of Goldspire Rock.
    n.position = Vector3(-18+sin(a)*44,0.08+sin(time*1.4+t.offset)*0.035,48+cos(a)*8)
    n.rotation.y = atan2(-cos(a)*44,sin(a)*8)
    n.rotation.z = sin(time*0.7+t.offset)*0.025
   else:
    var curve = road_curves[t.curve]
    var length = curve.get_baked_length()
    var progress = fposmod(time*0.017+t.offset,2.0)
    var along = progress if progress<1 else 2-progress
    var p = curve.sample_baked(along*length)
    var q = curve.sample_baked(clampf(along*length+(0.25 if progress<1 else -0.25),0,length))
    n.position = Vector3(p.x,height_at(p.x,p.z)+0.14,p.z)
    if p.distance_to(q)>0.01: n.rotation.y = atan2(-(q-p).x,-(q-p).z)
 update_walk(delta)
 var follow_id = selected_army_id()
 if follow_army and follow_id != "":
  var c = army_figures[follow_id].position
  target = target.lerp(Vector3(c.x,c.y+2.2,c.z),minf(1,delta*4))
 camera_update(delta)
 for p in pins:
  var b = p.button
  b.visible = overlays.settlements and not camera.is_position_behind(p.world) and distance>18
  if b.visible: b.position = camera.unproject_position(p.world)-b.anchor_offset()
  b.set_selected(ui.selected_settlement == p.id)
 var mouse = get_viewport().get_mouse_position()
 var hit = "" if get_viewport().gui_get_hovered_control() != null else pick(mouse)
 if "--ledger" in OS.get_cmdline_user_args(): ui.show_hover(ui._ledger_text(),Vector2(560,70))
 elif forced_preview != null and army_selected() and not walks.has(selected_army_id()):
  ui.show_hover(preview_move(forced_preview),camera.unproject_position(army_ground(forced_preview,1.0)))
 elif army_selected() and ui.visible and not walks.has(selected_army_id()) and not capture_mode and get_viewport().gui_get_hovered_control() == null and not hit.begins_with("army:"):
  var text = preview_move(move_target(mouse))
  ui.show_hover(hover_text(hit)+"
"+text if hit != "" else text,mouse)
 elif hit != "" and ui.visible: ui.show_hover(hover_text(hit),mouse)
 else: ui.hide_hover()
 if movement_overlay and forced_preview == null and movement_overlay.has_content("preview") and not (army_selected() and not walks.has(selected_army_id()) and get_viewport().gui_get_hovered_control() == null and not hit.begins_with("army:")):
  movement_overlay.clear("preview")
  preview_key = Vector2i(1<<20,0)
 ui.set_fps("%d FPS" % Engine.get_frames_per_second())
 if capture_mode:
  capture_frames += 1
  if capture_frames==180: screenshot_requested = true
  if capture_frames%60==0: print("FRAME ",capture_frames," FPS ",Engine.get_frames_per_second()," delta ",delta," draws ",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
 if screenshot_requested:
  screenshot_requested = false
  save_capture.call_deferred()

func save_capture():
 await RenderingServer.frame_post_draw
 var folder = ProjectSettings.globalize_path("res://captures")
 DirAccess.make_dir_recursive_absolute(folder)
 var args = OS.get_cmdline_user_args()
 var name_v = "overview"
 if "--closeup" in args: name_v="city"
 if "--hero" in args: name_v="commander"
 if "--goldspire" in args: name_v="goldspire"
 if "--developed" in args: name_v+="_developed"
 for arg in args:
  if arg.begins_with("--goldspire-stage="): name_v+="_goldspire_stage_%d" % goldspire_level if name_v!="goldspire" else "_stage_%d" % goldspire_level
  if arg.begins_with("--select="): name_v = "selected_"+arg.get_slice("=",1)
  if arg.begins_with("--name="): name_v = arg.get_slice("=",1)
 if "--army" in args: name_v = "army"
 if not capture_mode: name_v="view_"+Time.get_datetime_string_from_system().replace(":","-")
 var path = folder+"/"+name_v+".png"
 var result = get_viewport().get_texture().get_image().save_png(path)
 print("CAPTURE ",path," result=",result," window=",DisplayServer.window_get_size()," ui=",get_viewport().get_visible_rect().size)
 if ui: ui.toast("Saved view to ProjectFreedom / captures.")
 if capture_mode: get_tree().quit(0 if result==OK else 1)

func run_checks():
 assert(city_level>=1 and city_level<=3)
 assert(road_curves.size()==3)
 assert(traffic.size()==10)
 assert(ui_data.army(COMMANDER_ARMY).units.size()>=7 and ui_data.army(COMMANDER_ARMY).commander.unit=="commander")
 var level_before = city_level
 for i in range(3): upgrade_city()
 assert(city_level==level_before)
 var road_before = road_level
 for i in range(3): upgrade_roads()
 assert(road_level==road_before)
 for curve in road_curves: assert(curve.get_baked_length()>10)
 assert(height_at(CITY.x,CITY.y)>0)
 assert(height_at(0,70)<0)
 for id in AssetManifest.visuals():
  assert(ResourceLoader.exists(AssetManifest.scene_path(id)),"Missing visual scene for "+id)
 var zoom_before = desired_distance
 var event = InputEventMouseButton.new()
 event.button_index = MOUSE_BUTTON_WHEEL_UP
 event.pressed = true
 _unhandled_input(event)
 assert(desired_distance<zoom_before)
 desired_distance=zoom_before
 var paused_before = paused
 toggle_pause()
 assert(paused!=paused_before)
 toggle_pause()
 assert(paused==paused_before)
 # Map settlements match the province data the UI reads.
 for id in settlement_anchors:
  var a = settlement_anchors[id]
  assert(WorldMap.settlement_position(id).distance_to(Vector2(a.x,a.z))<0.5,"Settlement position mismatch: "+id)
  assert(WorldMap.region_at(Vector2(a.x,a.z))==id,"Settlement outside its region: "+id)
 select_settlement("crownwatch")
 assert(ui.selected_settlement=="crownwatch" and ui.province_title=="Crownwatch Pass")
 # Goldspire Rock: a registered landmark standing in the sea, its stages cycle, G jumps to it.
 assert(AssetManifest.is_landmark(GOLDSPIRE_ID))
 assert(height_at(GOLDSPIRE.x,GOLDSPIRE.y+8)<0)
 var goldspire_before = goldspire_level
 for i in range(3):
  cycle_goldspire()
  assert(goldspire_root.get_meta("stage")==goldspire_level)
 assert(goldspire_level==goldspire_before)
 var key = InputEventKey.new()
 key.keycode = KEY_G
 key.pressed = true
 _unhandled_input(key)
 assert(ui.selected_settlement==GOLDSPIRE_ID)
 assert(Vector2(target.x,target.z).distance_to(GOLDSPIRE)<1)
 select_army()
 assert(ui.selected_army==COMMANDER_ARMY and army_location()=="The Greywater March")
 # End Turn advances the year by one and posts the new year to Event Messages.
 var year = ui_data.resources().year
 end_turn()
 assert(ui_data.resources().year==year+1)
 assert(ui_data.events("turn")[0].year==year+1 and ui_data.events("turn")[1].category=="turn")
 print("END_TURN_MS %.3f" % ui_data.last_turn_ms)
 # Army movement: preview, blocked order, multi-turn order continuing on End Turn, garrison, cancel.
 # The army's state is restored afterwards so the capture is unchanged.
 var saved_army = ui_data.state.army_state[COMMANDER_ARMY].duplicate(true)
 select_army()
 assert(movement_overlay.has_content("reach"))
 preview_move(Vector2(-118,-30))
 assert(movement_overlay.has_content("preview") and preview_text.contains("3 turns"))
 var points_before = ui_data.army_movement(COMMANDER_ARMY).points
 order_army(WorldMap.settlement_position(CITY_ID))
 assert(ui.toast_label.text == "Battles not implemented yet")
 assert(ui_data.army_movement(COMMANDER_ARMY).points == points_before)
 order_army(Vector2(80,-10))
 update_walk(1000.0)
 var m = ui_data.army_movement(COMMANDER_ARMY)
 assert(not m.order.is_empty() and m.points<points_before)
 assert(movement_overlay.has_content("order:"+COMMANDER_ARMY))
 assert(commander.position.distance_to(army_ground(m.position))<0.01)
 var mid = m.position
 end_turn()
 update_walk(1000.0)
 assert(ui_data.army_movement(COMMANDER_ARMY).position != mid)
 ui_data.cancel_army_order(COMMANDER_ARMY)
 assert(ui_data.army_movement(COMMANDER_ARMY).order.is_empty())
 end_turn()
 update_walk(1000.0)
 order_army(WorldMap.settlement_position("crownwatch"))
 update_walk(1000.0)
 for i in 5:
  if ui_data.army_movement(COMMANDER_ARMY).order.is_empty(): break
  end_turn()
  update_walk(1000.0)
 assert(ui_data.army_movement(COMMANDER_ARMY).garrison == "crownwatch")
 assert(not ui_data.settlement("crownwatch").garrison.is_empty())
 ui_data.state.army_state[COMMANDER_ARMY] = saved_army
 place_commander()
 refresh_army_overlays()
 # Construction: a main-building upgrade at Goldspire completes on End Turn and moves the landmark
 # to its next growth stage; the visual is then restored for the capture.
 var level_now = goldspire_level
 if level_now<3:
  ui_data.state.treasury[ui_data.player_faction_id()] += 100000
  assert(ui_data.start_construction(GOLDSPIRE_ID,0,ui_data.state.settlements[GOLDSPIRE_ID].buildings[0].chain).ok)
  ui.show_settlement(GOLDSPIRE_ID)
  ui.open_building_browser(GOLDSPIRE_ID,0)
  assert(ui.browser_visible())
  ui.close_building_browser()
  for i in ui_data.construction(GOLDSPIRE_ID).turns_left: end_turn()
  assert(ui_data.settlement(GOLDSPIRE_ID).level==level_now+1 and goldspire_level==level_now+1)
  assert(goldspire_root.get_meta("stage")==level_now+1)
  assert(ui_data.events("buildings").size()>0)
  ui_data.set_settlement_level(GOLDSPIRE_ID,level_now)
  assert(goldspire_level==level_now)
 ui.clear_selection()
 reset_camera()
 print("SELF_TEST_PASS | upgrades cycle; traffic routes valid; manifest visuals present; city dry; sea submerged; goldspire stages cycle; ui selection, army panel and end turn; construction upgrades goldspire's stage; army movement preview, orders, blocking and garrison")

# --- Movement grid bake ------------------------------------------------------------
# Writes data/movement_grid.json, the terrain grid army movement reads (core/movement.gd), by
# classifying this map's heightfield, forest and coast with the thresholds in data/movement.json
# (grid_bake), then stamping passes and settlements. Gameplay never reads the terrain mesh; rerun
# after changing the map:  runtime\Godot.exe --path . -- --bake-movement-grid
func bake_movement_grid():
 var d = Movement.data()
 var b = d.grid_bake
 var cell = float(b.cell)
 var origin = Vector2(b.rect[0],b.rect[1])
 var cols = int(b.rect[2]/cell)
 var rows = int(b.rect[3]/cell)
 var sym = {}
 for t in d.terrain:
  if not t.begins_with("_"): sym[t] = d.terrain[t].symbol
 var trees = {}
 for p in forest_points:
  var k = Vector2i(floori(p.x/4.0),floori(p.y/4.0))
  if not trees.has(k): trees[k] = []
  trees[k].append(p)
 var out = []
 var counts = {}
 for z in rows:
  var row = ""
  for x in cols:
   var p = origin+(Vector2(x,z)+Vector2(0.5,0.5))*cell
   var h = height_at(p.x,p.y)
   var slope = Vector2(height_at(p.x+1,p.y)-height_at(p.x-1,p.y),height_at(p.x,p.y+1)-height_at(p.x,p.y-1)).length()*0.5
   var t = "open"
   if h<float(b.water_below): t = "water"
   elif h>float(b.mountain_above) or slope>float(b.steep_slope): t = "mountain"
   elif h>float(b.hills_above): t = "hills"
   else:
    var k = Vector2i(floori(p.x/4.0),floori(p.y/4.0))
    for dz in [-1,0,1]:
     for dx in [-1,0,1]:
      for q in trees.get(k+Vector2i(dx,dz),[]):
       if q.distance_to(p)<float(b.forest_tree_radius): t = "forest"
   for corridor in d.passes.list:
    for i in corridor.points.size()-1:
     var a = Vector2(corridor.points[i][0],corridor.points[i][1])
     var e = Vector2(corridor.points[i+1][0],corridor.points[i+1][1])
     if t != "water" and p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,e))<=float(corridor.width)*0.5: t = "pass"
   for id in WorldMap.settlement_ids():
    if WorldMap.settlement_position(id).distance_to(p)<=float(d.settlements.radius): t = "settlement"
   counts[t] = counts.get(t,0)+1
   row += sym[t]
  out.append(row)
 var grid = {"_note":"GENERATED by main.gd --bake-movement-grid from the map and data/movement.json (grid_bake). Do not hand-edit; rerun the bake. One character per %s m cell, rows from z = %s (north) southward, columns from x = %s; symbols are data/movement.json terrain symbols." % [cell,origin.y,origin.x],
  "cell":cell,"origin":[origin.x,origin.y],"cols":cols,"rows":rows,"rows_data":out}
 var f = FileAccess.open("res://data/movement_grid.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(grid,"  ",false)+"\n")
 f.close()
 print("MOVEMENT_GRID %dx%d %s" % [cols,rows,counts])
 # Lowest crossing of the northern mountains (to place passes): highest point per column.
 var best = []
 for x in range(-130,131,4):
  var top = 0.0
  for z in range(-130,-50,2): top = maxf(top,height_at(x,z))
  best.append([top,x])
 best.sort()
 print("MOUNTAIN_CROSSINGS (max height, x): ",best.slice(0,6))
