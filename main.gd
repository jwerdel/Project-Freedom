extends Node3D

const ProtoKit = preload("res://visuals/common/proto_kit.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const ROAD_VISUALS = ["road.dirt","road.gravel","road.stone"]

const CITY = Vector2(-12, 6)
const KEEP = Vector2(48, -35)
const VILLAGE = Vector2(-56, -24)
var rng = RandomNumberGenerator.new()
var noise = FastNoiseLite.new()
var detail = FastNoiseLite.new()
var camera: Camera3D
var target = Vector3(-3, 3, -9)
var yaw = 0.24
var pitch = 0.56
var distance = 151.0
var desired_distance = 151.0
var time = 0.0
var paused = false
var city_level = 2
var road_level = 1
var city_root: Node3D
var roads_root: Node3D
var traffic: Array = []
var road_curves: Array = []
var flags: Array = []
var pins: Array = []
var ui: Control
var title_label: Label
var info_label: Label
var toast_label: Label
var status_label: Label
var city_button: Button
var road_button: Button
var pause_button: Button
var detail_panel: PanelContainer
var selected = "city"
var sun: DirectionalLight3D
var environment: Environment
var dusk = false
var screenshot_requested = false
var capture_frames = 0
var capture_mode = false
var kit
var road_material: StandardMaterial3D
var serif: SystemFont
var sans: SystemFont
var commander: Node3D

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
 make_traffic()
 make_commander()
 make_ui()
 camera_update(1.0)
 if "--developed" in OS.get_cmdline_user_args():
  city_level = 3
  road_level = 2
  make_city()
  make_roads()
  refresh_ui()
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
 city_root = AssetManifest.instantiate("settlement.city.stage_%d" % city_level)
 add_child(city_root)
 city_root.position = ground(CITY)
 city_root.build({"height":height_at,"plaza_material":road_material})

func make_fortress(p: Vector2):
 var n = Node3D.new()
 add_child(n)
 n.position = ground(p)
 kit.cylinder(n,Vector3(0,0.15,0),4.8,4.3,0.5,kit.stone,32)
 for i in range(6):
  var a = i*TAU/6
  var b = (i+1)*TAU/6
  var from = Vector3(cos(a)*3.6,0.2,sin(a)*3.6)
  var to = Vector3(cos(b)*3.6,0.2,sin(b)*3.6)
  if i!=1: kit.wall(n,from,to,2.0)
  kit.tower(n,from,0.72,3.7)
 kit.box(n,Vector3(0,2.0,-0.5),Vector3(2.6,3.8,2.6),kit.stone)
 kit.roof(n,Vector3(0,3.9,-0.5),2.9,2.9,1.6,kit.slate)
 kit.banner(n,Vector3(0,5.6,-0.5),2.0)

func make_village():
 for i in range(12):
  var a = i*2.399
  var p = VILLAGE+Vector2(cos(a),sin(a))*(2.2+sqrt(i)*0.7)
  kit.house(self,ground(p),rng.randf_range(0.9,1.3),1.7,1.05,-a,rng)
 var windmill = Node3D.new()
 add_child(windmill)
 windmill.position = ground(VILLAGE+Vector2(-7,2))
 kit.cylinder(windmill,Vector3(0,1.7,0),0.8,0.5,3.4,kit.plaster)
 kit.cylinder(windmill,Vector3(0,3.8,0),0.8,0,1.1,kit.slate)
 var rotor = Node3D.new()
 windmill.add_child(rotor)
 rotor.position = Vector3(0,2.9,0.65)
 for i in range(4):
  var arm = Node3D.new()
  rotor.add_child(arm)
  arm.rotation.z = i*PI/2
  kit.box(arm,Vector3(0,1.1,0),Vector3(0.12,2.2,0.1),kit.wood)
  kit.box(arm,Vector3(0.25,1.35,0.02),Vector3(0.45,1.4,0.06),kit.sail)
 flags.append(rotor)

func make_farms():
 for i in range(12):
  var p = Vector2(-49+(i%4)*6,-2-floori(i/4.0)*6)
  var material = kit.mat(Color("837b44") if i%3==0 else Color("666b37"))
  var st = SurfaceTool.new()
  st.begin(Mesh.PRIMITIVE_TRIANGLES)
  for z in range(6):
   for x in range(6):
    for off in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
     st.add_vertex(ground(p+Vector2(x,z)*0.8+off*0.8,0.055))
  st.generate_normals()
  kit.add_mesh(self,st.commit(),material)
  for row in range(9):
   var curve = curve_from([p+Vector2(0,row*0.54),p+Vector2(4.8,row*0.54)])
   kit.ribbon(curve,0.085,kit.mat(Color("9a8a53")),self,height_at)

func make_forest():
 var source = load("res://assets/fir_optimized.glb").instantiate()
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
 var material = kit.textured("rocky_terrain",Color("8b938a"),1.2)
 for i in range(100):
  var x = rng.randf_range(-120,120)
  var p = Vector2(x,coast(x)+rng.randf_range(-3,4))
  if abs(x+18)<7: continue
  var s = rng.randf_range(0.3,1.4)
  var rock = kit.sphere(self,ground(p,0.05),Vector3(s,s*0.7,s*0.85),material)
  rock.rotation = Vector3(rng.randf(),rng.randf(),rng.randf())

func make_harbor():
 var z = coast(-18)
 for x in [-21.0,-16.0]:
  kit.box(self,Vector3(x,0.85,z+2),Vector3(1.4,0.35,9.0),kit.wood)
  for j in range(5):
   for side in [-0.55,0.55]:
    kit.cylinder(self,Vector3(x+side,0.15,z-1+j*1.6),0.12,0.12,2.1,kit.wood,8)
 kit.box(self,Vector3(-18.5,0.9,z-1.8),Vector3(8,0.4,2),kit.wood)
 for i in range(5):
  kit.box(self,Vector3(-21+rng.randf()*6,1.35,z-2+rng.randf()),Vector3(0.5,0.6,0.5),kit.wood)
 kit.house(self,ground(Vector2(-24,z-4)),2,3,1.6,0,rng)
 var lighthouse_pos = Vector2(-5,coast(-5)-3)
 kit.tower(self,ground(lighthouse_pos),0.7,3.7,true)

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

func style(bg: Color, border: Color, width = 1) -> StyleBoxFlat:
 var s = StyleBoxFlat.new()
 s.bg_color = bg
 s.border_color = border
 s.set_border_width_all(width)
 s.content_margin_left = 20
 s.content_margin_right = 20
 s.content_margin_top = 14
 s.content_margin_bottom = 14
 return s

func label(text_v: String,size_v: int,color = Color("e4ddc9"),font: Font = null) -> Label:
 var l = Label.new()
 l.text = text_v
 l.add_theme_font_size_override("font_size",size_v)
 l.add_theme_color_override("font_color",color)
 l.add_theme_font_override("font",font if font else sans)
 return l

func button(text_v: String,callback: Callable) -> Button:
 var b = Button.new()
 b.text = text_v
 b.custom_minimum_size.y = 40
 b.add_theme_font_override("font",sans)
 b.add_theme_font_size_override("font_size",14)
 b.add_theme_color_override("font_color",Color("e1d8bd"))
 b.add_theme_stylebox_override("normal",style(Color("233538"),Color("64716a")))
 b.add_theme_stylebox_override("hover",style(Color("354b4b"),Color("c6ab70")))
 b.add_theme_stylebox_override("pressed",style(Color("182a2c"),Color("d0b477")))
 b.pressed.connect(callback)
 b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
 return b

func make_ui():
 serif = SystemFont.new()
 serif.font_names = PackedStringArray(["Georgia"])
 sans = SystemFont.new()
 sans.font_names = PackedStringArray(["Segoe UI"])
 var layer = CanvasLayer.new()
 add_child(layer)
 ui = Control.new()
 ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
 layer.add_child(ui)
 var top = PanelContainer.new()
 ui.add_child(top)
 top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
 top.offset_bottom = 88
 top.add_theme_stylebox_override("panel",style(Color(0.055,0.095,0.105,0.96),Color("7d816e")))
 var h = HBoxContainer.new()
 h.add_theme_constant_override("separation",25)
 top.add_child(h)
 var names = VBoxContainer.new()
 h.add_child(names)
 names.add_child(label("PROJECT  FREEDOM",12,Color("b7aa83")))
 names.add_child(label("The Greywater March",29,Color("eee4c9"),serif))
 var space = Control.new()
 space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 h.add_child(space)
 var build = VBoxContainer.new()
 h.add_child(build)
 build.add_child(label("A LIVING WORLD  /  VISUAL PROTOTYPE",12,Color("b8c6bd")))
 build.add_child(label("Coast of the western kingdoms",15,Color("e6deca"),serif))
 detail_panel = PanelContainer.new()
 ui.add_child(detail_panel)
 detail_panel.position = Vector2(25,115)
 detail_panel.custom_minimum_size = Vector2(285,0)
 detail_panel.add_theme_stylebox_override("panel",style(Color(0.055,0.10,0.11,0.93),Color("677568")))
 var v = VBoxContainer.new()
 v.add_theme_constant_override("separation",12)
 detail_panel.add_child(v)
 v.add_child(label("THE GREYWATER COAST",11,Color("bca978")))
 title_label = label("Greyhaven",29,Color("efe4c9"),serif)
 v.add_child(title_label)
 info_label = label("",14,Color("c2cbc1"))
 v.add_child(info_label)
 v.add_child(HSeparator.new())
 city_button = button("Develop settlement  ·  1 / 3",upgrade_city)
 v.add_child(city_button)
 road_button = button("Improve roads  ·  dirt",upgrade_roads)
 v.add_child(road_button)
 v.add_child(button("Inspect Greyhaven",func(): focus_at(ground(CITY),39.0)))
 v.add_child(button("Inspect the commander",func():
  focus_at(commander.position+Vector3(0,2.2,0),15.0)
  pitch=0.30))
 v.add_child(button("Return to the coast  ·  Home",reset_camera))
 var bottom = PanelContainer.new()
 ui.add_child(bottom)
 bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
 bottom.offset_top = -77
 bottom.add_theme_stylebox_override("panel",style(Color(0.055,0.095,0.105,0.95),Color("677568")))
 var bar = HBoxContainer.new()
 bar.add_theme_constant_override("separation",12)
 bottom.add_child(bar)
 pause_button = button("Pause activity",toggle_pause)
 bar.add_child(pause_button)
 bar.add_child(button("Change light",toggle_light))
 bar.add_child(button("Save view  ·  F12",request_capture))
 var spacer = Control.new()
 spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 bar.add_child(spacer)
 var tips = VBoxContainer.new()
 bar.add_child(tips)
 tips.add_child(label("WASD  pan     •     Drag right mouse  orbit     •     Wheel  zoom",13))
 status_label = label("",12,Color("9eafa6"))
 tips.add_child(status_label)
 toast_label = label("Choose a settlement, or explore the coast.",14)
 ui.add_child(toast_label)
 toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
 toast_label.offset_top = -117
 toast_label.offset_bottom = -88
 toast_label.offset_left = -330
 toast_label.offset_right = 440
 toast_label.add_theme_color_override("font_shadow_color",Color.BLACK)
 toast_label.add_theme_constant_override("shadow_offset_x",1)
 toast_label.add_theme_constant_override("shadow_offset_y",2)
 for data in [["GREYHAVEN",ground(CITY,6),"city"],["CROWNWATCH",ground(KEEP,6),"fortress"],["WILLOWMERE",ground(VILLAGE,5),"village"]]:
  var b = Button.new()
  b.text = data[0]
  b.add_theme_font_override("font",serif)
  b.add_theme_font_size_override("font_size",16)
  b.add_theme_color_override("font_color",Color("f0e3bf"))
  b.add_theme_stylebox_override("normal",style(Color(0.06,0.12,0.13,0.84),Color("7d8971")))
  b.add_theme_stylebox_override("hover",style(Color("334541"),Color("d7b97d")))
  b.pressed.connect(select_place.bind(data[2]))
  ui.add_child(b)
  pins.append({"button":b,"world":data[1]})
 refresh_ui()

func refresh_ui():
 if not info_label: return
 if selected=="city":
  title_label.text = "Greyhaven"
  info_label.text = ["Fishing town · sheltered harbor\nTimber-framed streets and open markets.","Walled city · coastal stronghold\nStone ramparts shelter a growing town.","Chartered city · thriving port\nNew wards spread beyond the old walls."][city_level-1]
 elif selected=="fortress":
  title_label.text = "Crownwatch"
  info_label.text = "Hill fortress · the eastern pass\nSix towers guard the road inland."
 else:
  title_label.text = "Willowmere"
  info_label.text = "Farming village · fertile lowlands\nFields and a mill supply the coast."
 city_button.text = "Develop Greyhaven  ·  %s / 3" % city_level if city_level<3 else "Reset Greyhaven to a town"
 road_button.text = "Improve roads  ·  "+["dirt","gravel","stone → reset"][road_level]

func select_place(id: String):
 selected = id
 refresh_ui()
 var p = CITY if id=="city" else KEEP if id=="fortress" else VILLAGE
 focus_at(ground(p),48)

func upgrade_city():
 city_level = city_level%3+1
 make_city()
 refresh_ui()
 if toast_label: toast_label.text = ["Greyhaven returns to its original fishing town.","Greyhaven's ramparts rise around its growing streets.","New wards and a high tower transform Greyhaven's skyline."][city_level-1]

func upgrade_roads():
 road_level = (road_level+1)%3
 make_roads()
 refresh_ui()
 if toast_label: toast_label.text = ["The coast is linked by dirt tracks.","Gravel roads now connect the coast's settlements.","Stone paving and roadside markers trace the trade network."][road_level]

func toggle_pause():
 paused = not paused
 pause_button.text = "Resume activity" if paused else "Pause activity"

func toggle_light():
 dusk = not dusk
 sun.light_color = Color("ffbe86") if dusk else Color("fff0d6")
 sun.light_energy = 0.95 if dusk else 1.3
 sun.rotation_degrees.x = -19 if dusk else -43
 environment.ambient_light_energy = 0.42 if dusk else 0.60

func reset_camera():
 target = Vector3(-3,3,-9)
 yaw = 0.24
 pitch = 0.56
 desired_distance = 151

func focus_at(p: Vector3,d: float):
 target = p
 desired_distance = d

func request_capture():
 screenshot_requested = true

func _unhandled_input(event):
 if event is InputEventMouseButton and event.pressed:
  if event.button_index == MOUSE_BUTTON_WHEEL_UP: desired_distance = clampf(desired_distance*0.88,10,210)
  if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: desired_distance = clampf(desired_distance*1.13,10,210)
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
  if event.keycode == KEY_TAB: ui.visible = not ui.visible
  if event.keycode == KEY_ESCAPE: ui.visible = true

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
    n.position = Vector3(-10+sin(a)*62,0.08+sin(time*1.4+t.offset)*0.035,48+cos(a)*8)
    n.rotation.y = atan2(-cos(a)*62,sin(a)*8)
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
  b.visible = not camera.is_position_behind(p.world) and distance>25
  if b.visible:
   b.position = camera.unproject_position(p.world)-b.size*Vector2(0.5,1.0)
   b.visible = b.position.x>320 and b.position.y>100 and b.position.y<get_viewport().get_visible_rect().size.y-135
 status_label.text = "%s FPS  ·  Local 3D scene  ·  No campaign simulation yet  ·  Tab hides interface" % Engine.get_frames_per_second()
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
 var name_v = "overview"
 if "--closeup" in OS.get_cmdline_user_args(): name_v="city"
 if "--hero" in OS.get_cmdline_user_args(): name_v="commander"
 if "--developed" in OS.get_cmdline_user_args(): name_v+="_developed"
 if not capture_mode: name_v="view_"+Time.get_datetime_string_from_system().replace(":","-")
 var path = folder+"/"+name_v+".png"
 var result = get_viewport().get_texture().get_image().save_png(path)
 print("CAPTURE ",path," result=",result)
 toast_label.text = "Saved view to ProjectFreedom / captures."
 if capture_mode: get_tree().quit(0 if result==OK else 1)

func run_checks():
 assert(city_level>=1 and city_level<=3)
 assert(road_curves.size()==3)
 assert(traffic.size()==10)
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
 pause_button.pressed.emit()
 assert(paused!=paused_before)
 pause_button.pressed.emit()
 assert(paused==paused_before)
 select_place("fortress")
 assert(title_label.text=="Crownwatch")
 selected="city"
 refresh_ui()
 reset_camera()
 print("SELF_TEST_PASS | upgrades cycle; traffic routes valid; manifest visuals present; city dry; sea submerged")
