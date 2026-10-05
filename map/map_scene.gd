extends Node3D
# A pipeline map in 3D (map/map_view.gd) with an orbit camera, for viewing, showcase captures and the
# GPU budget measurements (docs/map-pipeline-design.md §6.2, Addendum A.6). The campaign game still
# runs on Main.tscn (the test map) until the map-agnostic map scene replaces it.
#   runtime\Godot.exe --path . map/map_scene.tscn -- [--map=synthetic600] [--sprawl-max] [--land-demo]
#     [--focus=<settlement>|dense] [--view=x,z,distance,yaw,pitch] [--showcase=city1|city3|farm|mine|convert:N]
#     [--strategic [--layer=culture]] [--gpu=<label> --out=<file>] [--capture --name=<file>] [--instanced]

const MapRegistry = preload("res://core/map_registry.gd")
const GameState = preload("res://core/game_state.gd")
const WorldMap = preload("res://core/world_map.gd")
const Movement = preload("res://core/movement.gd")
const MapView = preload("res://map/map_view.gd")
const SprawlNode = preload("res://map/sprawl_node.gd")
const Land = preload("res://core/land.gd")
const UiData = preload("res://core/ui_data.gd")
const StrategicMap = preload("res://ui/strategic_map.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const CULTURES = ["medieval","roman","greek","orc","dwarf","elf","dark_elf","beastmen","ratmen","lizardmen","desert"]

var view: MapView
var state
var camera: Camera3D
var target := Vector3.ZERO
var distance := 120.0
var yaw := 0.5
var pitch := 0.75
var args := []
var strategic: Control
var lord: Node3D

func _ready():
 args = Array(OS.get_cmdline_user_args())
 var map_id = _arg("--map=","synthetic600")
 MapRegistry.set_active(map_id)
 state = GameState.from_data()
 SprawlNode.merge = not args.has("--instanced") # the old one-MultiMesh-per-kit-mesh drawing, for comparisons
 if args.has("--sprawl-max"): _sprawl_max()
 if args.has("--land-demo"): _land_demo()
 var sc = _arg("--showcase=","")
 _environment()
 view = MapView.new()
 view.tree_shadows = not args.has("--no-tree-shadows")
 add_child(view)
 var focus_id = ""
 if sc != "": focus_id = _showcase(sc)
 view.setup(state)
 camera = Camera3D.new()
 camera.far = 4000.0
 add_child(camera)
 var f = _arg("--focus=","")
 if f == "dense": target = _densest()
 elif f != "": focus_id = f
 if focus_id != "":
  var p = WorldMap.settlement_position(focus_id)
  target = Vector3(p.x,view.height_at(p.x,p.y),p.y)
 elif target == Vector3.ZERO:
  var p = WorldMap.settlement_position(WorldMap.settlement_ids()[0])
  target = Vector3(p.x,0,p.y)
 if _arg("--distance=","") != "": distance = float(_arg("--distance=",""))
 if _arg("--pitch=","") != "": pitch = float(_arg("--pitch=",""))
 if _arg("--yaw=","") != "": yaw = float(_arg("--yaw=",""))
 var v = _arg("--view=","")
 if v != "":
  var q = v.split(",")
  target = Vector3(float(q[0]),view.height_at(float(q[0]),float(q[1])),float(q[1]))
  distance = float(q[2])
  yaw = float(q[3])
  pitch = float(q[4])
 if args.has("--strategic"): _open_strategic()
 _place_camera()
 view.update(target)
 if _arg("--gpu=","") != "": _measure.call_deferred()
 elif args.has("--capture"): _capture.call_deferred()

func _arg(prefix: String,default: String) -> String:
 for a in args:
  if a.begins_with(prefix): return a.get_slice("=",1)
 return default

func _environment():
 var sun = DirectionalLight3D.new()
 sun.rotation = Vector3(-0.95,0.6,0)
 sun.light_energy = 1.15
 sun.shadow_enabled = true
 sun.directional_shadow_max_distance = 220.0
 sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS # two cascades suffice at campaign distances (half the shadow passes)
 add_child(sun)
 var env = Environment.new()
 env.background_mode = Environment.BG_SKY
 var sky = Sky.new()
 sky.sky_material = ProceduralSkyMaterial.new()
 env.sky = sky
 env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
 env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 # Atmosphere (TW:WH3): far land fades into a pale blue haze that sells the scale, and a mild grade
 # keeps the colours rich (data/campaign_view.json "atmosphere").
 var at = _atmosphere()
 env.fog_enabled = true
 env.fog_mode = Environment.FOG_MODE_DEPTH
 env.fog_light_color = Color(at.haze)
 env.fog_depth_begin = float(at.haze_begin)
 env.fog_depth_end = float(at.haze_end)
 env.fog_depth_curve = float(at.haze_curve)
 env.fog_density = float(at.haze_max)
 env.fog_aerial_perspective = float(at.aerial_perspective)
 env.fog_sky_affect = 0.4
 env.adjustment_enabled = true
 env.adjustment_saturation = float(at.saturation)
 env.adjustment_contrast = float(at.contrast)
 env.adjustment_brightness = float(at.brightness)
 var we = WorldEnvironment.new()
 we.environment = env
 add_child(we)

func _place_camera():
 var dir = Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))
 camera.position = target+dir*distance
 camera.look_at(target,Vector3.UP)

func _process(delta):
 if camera == null: return
 var move = Vector3.ZERO
 if Input.is_physical_key_pressed(KEY_W): move.z -= 1
 if Input.is_physical_key_pressed(KEY_S): move.z += 1
 if Input.is_physical_key_pressed(KEY_A): move.x -= 1
 if Input.is_physical_key_pressed(KEY_D): move.x += 1
 if Input.is_physical_key_pressed(KEY_Q): yaw += delta*1.4
 if Input.is_physical_key_pressed(KEY_E): yaw -= delta*1.4
 target += move.rotated(Vector3.UP,yaw)*delta*distance*0.6
 _place_camera()
 view.update(target)

func _unhandled_input(e):
 if e is InputEventMouseButton and e.pressed:
  if e.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(15.0,distance*0.88)
  if e.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(260.0,distance*1.13)

# --- Worst cases and showcases ------------------------------------------------------------------

# Every settlement a level-3 city or fortress with every industry: the heaviest sprawl.
func _sprawl_max():
 for sid in state.settlements:
  var s = state.settlements[sid]
  s.level = 3
  s.buildings = [{"chain":"main_"+s.type,"level":3},{"chain":"farm","level":3},{"chain":"mine","level":3},{"chain":"port","level":3},
   {"chain":"market","level":3},{"chain":"temple","level":3},{"chain":"barracks","level":3},{"chain":"walls","level":3}]

# Mixed conversion states: every region's land from another culture, 0 to 1 of the way.
func _land_demo():
 var rng = RandomNumberGenerator.new()
 rng.seed = 9
 for sid in state.land:
  var e = state.land[sid]
  var other = CULTURES[rng.randi_range(0,CULTURES.size()-1)]
  if other == e.to: continue
  state.land[sid] = {"from":other,"to":e.to,"value":[0.0,0.34,0.67,1.0][rng.randi_range(0,3)],"built":0}

# A settlement set up for a showcase shot (with a lord beside it for scale); returns its id.
func _showcase(kind: String) -> String:
 var sid = _pick(kind)
 var s = state.settlements[sid]
 s.type = "city"
 s.buildings = []
 match kind:
  "city1":
   s.level = 1
  "city3":
   s.level = 3
   s.buildings = [{"chain":"market","level":3},{"chain":"temple","level":2},{"chain":"walls","level":3},{"chain":"barracks","level":2},{"chain":"farm","level":2}]
  "farm":
   s.type = "town"
   s.level = 2
   s.buildings = [{"chain":"farm","level":3}]
  "mine":
   s.type = "town"
   s.level = 2
   s.buildings = [{"chain":"mine","level":3}]
  _:
   if kind.begins_with("convert:"):
    s.level = 3
    s.buildings = [{"chain":"market","level":2},{"chain":"temple","level":2},{"chain":"farm","level":2}]
    var turns = float(kind.get_slice(":",1))
    state.land[sid] = {"from":"greek","to":"orc","value":clampf(turns/9.0,0.0,1.0),"built":0}
 if kind in ["city1","city3"] or kind.begins_with("convert:"): state.land[sid] = state.land.get(sid,{}) if kind.begins_with("convert:") else {"from":"greek","to":"greek","value":1.0,"built":0}
 _place_lord.call_deferred(sid)
 distance = 95.0 if kind != "city1" else 70.0
 pitch = 0.62
 yaw = 0.7
 return sid

func _place_lord(sid: String):
 var p = WorldMap.settlement_position(sid)+Vector2(-30,26)
 lord = AssetManifest.instantiate("unit.commander")
 add_child(lord)
 lord.scale = Vector3.ONE*2.0 # data/campaign_view.json lord_scale
 lord.position = Vector3(p.x,view.height_at(p.x,p.y),p.y)
 lord.rotation.y = yaw

# A settlement with open land around it (and hills near it for the mining town).
func _pick(kind: String) -> String:
 var best = ""
 var best_score = -1.0
 for sid in WorldMap.settlement_ids():
  var c = WorldMap.settlement_position(sid)
  var open = 0
  var hills = 0
  var water = 0
  for i in 48:
   var p = c+Vector2.from_angle(i*TAU/48.0)*(18.0+(i%4)*10.0)
   var t = Movement.terrain_at(p)
   if t == "open": open += 1
   elif t in ["hills","pass"]: hills += 1
   elif t == "water": water += 1
  var score = float(open)-water*3.0
  if kind == "mine": score = float(mini(hills,10))*3.0+open*0.5-water*3.0
  if score>best_score:
   best_score = score
   best = sid
 return best

# The point with the most settlements within 300 m (the heaviest view).
func _densest() -> Vector3:
 var ids = WorldMap.settlement_ids()
 var best = Vector2.ZERO
 var best_n = -1
 for a in ids:
  var pa = WorldMap.settlement_position(a)
  var n = 0
  for b in ids: if WorldMap.settlement_position(b).distance_to(pa)<300.0: n += 1
  if n>best_n:
   best_n = n
   best = pa
 return Vector3(best.x,0,best.y)

func _open_strategic():
 var layer = CanvasLayer.new()
 add_child(layer)
 strategic = StrategicMap.new()
 layer.add_child(strategic)
 var size = Vector2(MapRegistry.meta().size[0],MapRegistry.meta().size[1])
 strategic.setup(UiData.new(state),Rect2(Vector2(MapRegistry.meta().origin[0],MapRegistry.meta().origin[1]),size))
 strategic.set_layer(_arg("--layer=","affiliation"))
 strategic.open_map(true)
 if args.has("--strategic-hidden"): strategic.visible = false # baseline: the empty 2D frame, for the strategic map's own GPU cost
 # Stress: N copies of the territory pass (the GPU clocks down on a light 2D frame, which inflates its
 # measured time; per-copy cost under load = (time with N - time with 1) / (N - 1)).
 var stress = int(_arg("--strategic-stress=","1"))
 if stress>1:
  strategic._layout()
  for i in stress-1:
   var c = strategic._surface.duplicate()
   strategic.add_child(c)
   strategic.move_child(c,strategic._surface.get_index())
   c.position = strategic._surface.position
   c.size = strategic._surface.size
 # As in the game (main.gd): nothing 3D renders behind the opaque strategic map.
 get_viewport().disable_3d = true

# --- Measurement and capture -----------------------------------------------------------------------

func _measure():
 var rid = get_viewport().get_viewport_rid()
 RenderingServer.viewport_set_measure_render_time(rid,true)
 # Warm up: streaming builds and shaders compile.
 for i in 120: await get_tree().process_frame
 _debug_hide(_arg("--hide=","").split(",",false))
 var gpu = 0.0
 var cpu = 0.0
 var frames = 0
 var dc = 0
 var prims = 0
 var t0 = Time.get_ticks_msec()
 while Time.get_ticks_msec()-t0<3000:
  await get_tree().process_frame
  gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
  cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
  dc = maxi(dc,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
  prims = maxi(prims,int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
  frames += 1
 var vram = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0
 var st = view.stats()
 var label = _arg("--gpu=","view")
 var line = "GPU %s gpu_ms=%.2f render_cpu_ms=%.2f fps=%.1f draw_calls=%d primitives=%d vram_mb=%.0f settlements_built=%d settlement_pieces=%d trees=%d window=%s" % [label,gpu/frames,cpu/frames,Engine.get_frames_per_second(),dc,prims,vram,st.settlements_built,st.settlement_pieces,st.trees,str(DisplayServer.window_get_size())]
 print(line)
 var out = _arg("--out=","")
 if out != "":
  var f = FileAccess.open(out,FileAccess.READ_WRITE) if FileAccess.file_exists(out) else FileAccess.open(out,FileAccess.WRITE)
  f.seek_end()
  f.store_line(line)
  f.close()
 if args.has("--capture"): await _capture()
 get_tree().quit(0)

func _capture():
 for i in 90: await get_tree().process_frame
 await RenderingServer.frame_post_draw
 var folder = ProjectSettings.globalize_path("res://captures")
 DirAccess.make_dir_recursive_absolute(folder)
 var path = folder+"/"+_arg("--name=","map_view")+".png"
 var err = get_viewport().get_texture().get_image().save_png(path)
 print("CAPTURE ",path," result=",err)
 get_tree().quit(0)

func _atmosphere() -> Dictionary:
 return JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_view.json")).atmosphere

# Cost attribution for the GPU report: --hide=trees,cities,terrain,shadows.
func _debug_hide(what: Array):
 for k in view.chunks:
  var c = view.chunks[k]
  if "trees" in what and c.trees != null: c.trees.visible = false
  if "terrain" in what:
   for mi in c.node.get_children(): mi.visible = false
 if "cities" in what:
  for sid in view.settlements: view.settlements[sid].visible = false
 if "shadows" in what:
  for n in find_children("*","DirectionalLight3D",true,false): n.shadow_enabled = false
