extends Node3D

const ProtoKit = preload("res://visuals/common/proto_kit.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const COMMANDER_ARMY = "aurek_host"
const WorldMap = preload("res://core/world_map.gd")
const UiData = preload("res://core/ui_data.gd")
const PortraitStudio = preload("res://core/portrait_studio.gd")
const CampaignUI = preload("res://ui/campaign_ui.gd")
const UiKit = preload("res://ui/ui_kit.gd")
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
var army: Dictionary
var pins: Array = []
var ui
var ui_data
var studio
var pins_root: Control
var settlement_anchors = {}
var overlays = {"borders":true,"settlements":true,"armies":true}
var press_pos = Vector2.ZERO

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
 if "--army" in OS.get_cmdline_user_args(): select_army()
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
 road_curves.append(curve_from([CITY,Vector2(0,-5),Vector2(15,-14),Vector2(30,-22),KEEP]))
 road_curves.append(curve_from([CITY,Vector2(-24,-8),Vector2(-41,-13),VILLAGE]))
 road_curves.append(curve_from([CITY,Vector2(-17,17),Vector2(-18,27)]))
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
 army = UnitTypes.army(COMMANDER_ARMY)
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
  var b = Button.new()
  b.text = ui_data.settlement(id).name.to_upper()
  b.add_theme_font_override("font",UiKit.head_font())
  b.add_theme_font_size_override("font_size",15)
  b.focus_mode = Control.FOCUS_NONE
  b.pressed.connect(select_settlement.bind(id))
  pins_root.add_child(b)
  pins.append({"button":b,"world":settlement_anchors[id],"id":id})

func select_settlement(id: String):
 ui.show_settlement(id)
 focus_settlement(id)

func focus_settlement(id: String):
 if id == GOLDSPIRE_ID:
  focus_goldspire()
  return
 var a = settlement_anchors[id]
 focus_at(ground(Vector2(a.x,a.z)),48)

func select_army():
 ui.show_army(COMMANDER_ARMY,army_location())
 focus_at(commander.position+Vector3(0,2.2,0),26.0)

func army_location() -> String:
 var region = WorldMap.region_at(Vector2(commander.position.x,commander.position.z))
 return WorldMap.province(WorldMap.province_of(region)).get("name","")

func end_turn():
 ui_data.end_turn()
 ui.toast("Year %d begins." % ui_data.resources().year)

func set_overlay(overlay: String,on: bool):
 overlays[overlay] = on
 if overlay == "armies": commander.visible = on

func upgrade_city():
 city_level = city_level%3+1
 make_city()
 if ui_data: ui_data.set_settlement_level(CITY_ID,city_level)
 if ui: ui.toast(["Greyhaven returns to its original fishing town.","Greyhaven's ramparts rise around its growing streets.","New wards and a high tower transform Greyhaven's skyline."][city_level-1])

func upgrade_roads():
 road_level = (road_level+1)%3
 make_roads()
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

# What is under the mouse on the map: "army", a settlement ID, or "".
func pick(screen: Vector2) -> String:
 if commander.visible and not camera.is_position_behind(commander.position):
  var c = camera.unproject_position(commander.position+Vector3(0,2.2,0))
  if c.distance_to(screen)<_screen_radius(commander.position,2.6,26): return "army"
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
 if hit == "army":
  var f = WorldMap.faction(army.faction)
  return "%s\n%s · %s\n%s" % [army.commander.name,f.name,army.display_name,army_location()]
 var s = ui_data.settlement(hit)
 return "%s\n%s\n%s" % [s.name,s.faction.name,s.province_name]

func _unhandled_input(event):
 if event is InputEventMouseButton:
  if event.pressed:
   if event.button_index == MOUSE_BUTTON_WHEEL_UP: desired_distance = clampf(desired_distance*0.88,10,210)
   if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: desired_distance = clampf(desired_distance*1.13,10,210)
   if event.button_index == MOUSE_BUTTON_LEFT: press_pos = event.position
  elif event.button_index == MOUSE_BUTTON_LEFT and event.position.distance_to(press_pos)<6:
   var hit = pick(event.position)
   if hit == "army": select_army()
   elif hit != "": select_settlement(hit)
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
   ui.visible = true
   pins_root.visible = true
  if event.keycode == KEY_G: select_settlement(GOLDSPIRE_ID)
  if event.keycode == KEY_C: select_army()
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
 camera_update(delta)
 for p in pins:
  var b = p.button
  b.visible = overlays.settlements and not camera.is_position_behind(p.world) and distance>25
  if b.visible: b.position = camera.unproject_position(p.world)-b.size*Vector2(0.5,1.0)
 var mouse = get_viewport().get_mouse_position()
 var hit = "" if get_viewport().gui_get_hovered_control() != null else pick(mouse)
 if hit != "" and ui.visible: ui.show_hover(hover_text(hit),mouse)
 else: ui.hide_hover()
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
 assert(army.units.size()>=7 and army.commander.unit=="commander")
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
 assert(ui_data.events("turn")[0].title=="Year %d begins" % (year+1))
 ui.clear_selection()
 reset_camera()
 print("SELF_TEST_PASS | upgrades cycle; traffic routes valid; manifest visuals present; city dry; sea submerged; goldspire stages cycle; ui selection, army panel and end turn")
