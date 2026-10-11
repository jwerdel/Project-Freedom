extends Node3D
# The god-game look test (docs/pivot/god-game.md, slice 1): Frosthold and its countryside at
# character scale, Edric Varn with Where Winds Meet traversal and flight, one-punch destruction,
# living townsfolk, and the seamless rise to the campaign map and the strategic map.
# Entry: the main menu's "God Test", or  runtime\Godot.exe --path . god/god_test.tscn -- [options]
#  --shot=<name> [--view=x,y,z,yaw,pitch]   a screenshot from a fixed camera, then quit
#  --flat                                   the culture kits' flat colours (the material pass's "before")
#  --showcase                               the scripted 60-90 s showcase (god/showcase.gd); with
#                                           Godot's --write-movie it records the video
#  --perf=<file>                            run the showcase in real time and log frame timings
#  --no-villagers --no-foliage              leave parts out (measurements)
# data/god_test.json holds the tuning; nothing here touches the strategy game's state.

const MapRegistry = preload("res://core/map_registry.gd")
const GameState = preload("res://core/game_state.gd")
const WorldMap = preload("res://core/world_map.gd")
const Movement = preload("res://core/movement.gd")
const Terrain = preload("res://god/terrain.gd")
const Town = preload("res://god/town.gd")
const Debris = preload("res://god/debris.gd")
const Materials = preload("res://god/materials.gd")
const GodModel = preload("res://god/god_model.gd")
const GodPlayer = preload("res://god/god_player.gd")
const Vfx = preload("res://god/vfx.gd")
const Foliage = preload("res://god/foliage.gd")
const Villagers = preload("res://god/villagers.gd")
const Empire = preload("res://god/empire.gd")
const Hud = preload("res://god/hud.gd")
const MeshKit = preload("res://god/mesh_kit.gd")

var cfg: Dictionary
var args: Array
var terrain
var town
var debris
var map_view
var campaign_root: Node3D
var state
var site := Vector2.ZERO # the settlement's campaign position
var cscale := 2.0
var sun: DirectionalLight3D
var env: Environment
var cam_attr: CameraAttributesPractical
var camera: Camera3D
var player
var model
var vfx
var foliage
var villagers
var empire
var hud
var showcase
var ready_done := false
var real_clock := 0.0
var slow_until := 0.0
var stop_until := 0.0
var meteor_t := 0.0
var smoke_nodes: Array = []
var detail_on := true
var big_punch_frame := -10 # the frame of the last serious punch (perf runs report it apart)

func _ready():
 args = Array(OS.get_cmdline_user_args())
 cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/god_test.json"))
 cscale = float(cfg.scale.campaign_scale)
 var t0 = Time.get_ticks_msec()
 if args.has("--flat"):
  Materials.flat = true
  MeshKit.set_flat(true)
 _viewport()
 _environment()
 _campaign()
 print("GODTEST stage _campaign %d ms" % (Time.get_ticks_msec()-t0))
 _terrain()
 print("GODTEST stage _terrain %d ms" % (Time.get_ticks_msec()-t0))
 _god()
 print("GODTEST stage _god %d ms" % (Time.get_ticks_msec()-t0))
 vfx = Vfx.new()
 vfx.name = "Vfx"
 add_child(vfx)
 vfx.setup_collider()

 _ambient_effects()
 if not args.has("--no-foliage"):
  foliage = Foliage.new()
  foliage.name = "Foliage"
  add_child(foliage)
  await foliage.setup(cfg.render,terrain,town,Callable(self,"is_forest"))
  print("GODTEST stage foliage %d ms" % (Time.get_ticks_msec()-t0))
 if not args.has("--no-villagers"):
  villagers = Villagers.new()
  villagers.name = "Villagers"
  add_child(villagers)
  villagers.setup(cfg.town,terrain,town,player,int(cfg.town.villagers))
 print("GODTEST stage villagers %d ms" % (Time.get_ticks_msec()-t0))
 empire = Empire.new()
 empire.name = "Empire"
 add_child(empire)
 empire.setup(self,player,cfg.rise)
 empire.message.connect(func(t): if t != "": hud.say(t))
 hud = Hud.new()
 add_child(hud)
 hud.setup(self)
 vfx.prewarm()
 town.approval = float(cfg.town.approval_start)
 await _warm_up()
 print("GODTEST built in %d ms (trees %d, villagers %d)" % [Time.get_ticks_msec()-t0,foliage.tree_count if foliage else 0,villagers.people.size() if villagers else 0])
 ready_done = true
 if _arg("--perf=","") != "": add_child(load("res://god/frame_probe.gd").new())
 if args.has("--showcase") or _arg("--perf=","") != "":
  showcase = load("res://god/showcase.gd").new()
  add_child(showcase)
  showcase.start(self,_arg("--perf=",""))
 elif _arg("--shot=","") != "": _shot.call_deferred(_arg("--shot=",""))
 elif _arg("--bench=","") != "": _bench.call_deferred(_arg("--bench=",""))

func _arg(prefix: String,default: String) -> String:
 for a in args:
  if a.begins_with(prefix): return a.get_slice("=",1)
 return default

func _viewport():
 var vp = get_viewport()
 vp.msaa_3d = Viewport.MSAA_DISABLED
 vp.use_taa = bool(cfg.render.taa)
 vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
 var fsr = float(cfg.render.fsr_scale)
 if fsr<0.999:
  vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
  vp.scaling_3d_scale = fsr
 vp.anisotropic_filtering_level = Viewport.ANISOTROPY_8X
 vp.mesh_lod_threshold = 1.5
 RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
 RenderingServer.directional_shadow_atlas_set_size(4096,true)

func _environment():
 sun = DirectionalLight3D.new()
 sun.name = "Sun"
 # A low winter sun from the south-west.
 sun.rotation = Vector3(deg_to_rad(-24.0),deg_to_rad(-38.0),0)
 sun.light_color = Color(1.0,0.88,0.74)
 sun.light_energy = 2.8
 sun.light_angular_distance = 0.8
 sun.shadow_enabled = true
 sun.shadow_bias = 0.03
 sun.shadow_normal_bias = 1.0
 sun.shadow_blur = 1.0
 sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
 sun.directional_shadow_max_distance = float(cfg.render.shadow_distance)
 sun.directional_shadow_split_1 = 0.035
 sun.directional_shadow_split_2 = 0.11
 sun.directional_shadow_split_3 = 0.33
 sun.directional_shadow_blend_splits = true
 sun.directional_shadow_fade_start = 0.85
 add_child(sun)
 env = Environment.new()
 env.background_mode = Environment.BG_SKY
 var sky = Sky.new()
 var sm = ShaderMaterial.new()
 sm.shader = load("res://god/sky.gdshader")
 sm.set_shader_parameter("noise_tex",Materials.cloud_noise())
 sky.sky_material = sm
 sky.process_mode = Sky.PROCESS_MODE_REALTIME
 sky.radiance_size = Sky.RADIANCE_SIZE_256
 env.sky = sky
 env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
 env.ambient_light_energy = 0.55
 env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
 env.tonemap_mode = Environment.TONE_MAPPER_AGX
 env.tonemap_exposure = 1.05
 env.ssao_enabled = bool(cfg.render.ssao)
 env.ssao_radius = 1.4
 env.ssao_intensity = 2.4
 env.ssao_power = 1.7
 env.ssao_detail = 0.7
 env.ssao_horizon = 0.06
 env.ssil_enabled = bool(cfg.render.ssil)
 env.sdfgi_enabled = bool(cfg.render.sdfgi)
 env.glow_enabled = true
 env.glow_intensity = 0.45
 env.glow_bloom = 0.03
 env.glow_hdr_threshold = 1.4
 env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
 env.fog_enabled = true
 env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
 env.fog_light_color = Color(0.68,0.74,0.83)
 env.fog_light_energy = 1.0
 env.fog_sun_scatter = 0.2
 env.fog_density = 0.00032
 env.fog_aerial_perspective = 0.6
 env.fog_sky_affect = 0.12
 env.fog_height = 40.0
 env.fog_height_density = 0.002
 env.volumetric_fog_enabled = bool(cfg.render.volumetric_fog)
 env.volumetric_fog_density = 0.0028
 env.volumetric_fog_albedo = Color(0.9,0.92,0.96)
 env.volumetric_fog_length = 160.0
 env.volumetric_fog_detail_spread = 2.0
 env.volumetric_fog_gi_inject = 0.5
 env.volumetric_fog_anisotropy = 0.55
 env.volumetric_fog_sky_affect = 0.0
 env.adjustment_enabled = true
 env.adjustment_brightness = 1.0
 env.adjustment_contrast = 1.12
 env.adjustment_saturation = 0.9
 var we = WorldEnvironment.new()
 we.environment = env
 cam_attr = CameraAttributesPractical.new()
 cam_attr.dof_blur_far_enabled = true
 cam_attr.dof_blur_far_distance = 700.0
 cam_attr.dof_blur_far_transition = 600.0
 cam_attr.dof_blur_amount = 0.03
 we.camera_attributes = cam_attr
 add_child(we)

# The campaign map (Varos) drawn at campaign_scale around the character-scale area, so its terrain
# continues past the area's edge and the rise to the empire view is one motion (god/empire.gd).
func _campaign():
 MapRegistry.set_active(MapRegistry.CAMPAIGN)
 state = GameState.from_data()
 site = WorldMap.settlement_position(str(cfg.area.settlement))
 campaign_root = Node3D.new()
 campaign_root.name = "Campaign"
 campaign_root.scale = Vector3.ONE*cscale
 campaign_root.position = Vector3(-site.x*cscale,0,-site.y*cscale)
 add_child(campaign_root)
 map_view = load("res://map/map_view.gd").new()
 campaign_root.add_child(map_view)
 map_view.setup(state)
 map_view.set_winter(1.0) # the north under snow, as the character-scale area
 var inv = campaign_root.transform.affine_inverse()
 map_view.material.set_shader_parameter("map_from_world",Projection(inv))
 _hole(true)
 map_view.update(Vector3(site.x,0,site.y))
 hide_campaign_site()
 _great_wall_look()

func _hole(on: bool):
 var h = float(cfg.area.half_size)/cscale
 map_view.material.set_shader_parameter("hole",Vector4(site.x-h+4.0,site.y-h+4.0,site.x+h-4.0,site.y+h-4.0) if on else Vector4.ZERO)

# The campaign's own Frosthold (sprawl and landmark) and its trees inside the area give way to the
# character-scale ones while those are shown.
func hide_campaign_site():
 var sid = str(cfg.area.settlement)
 if map_view.settlements.has(sid): map_view.settlements[sid].visible = not detail_on
 if map_view.landmarks.has(sid): map_view.landmarks[sid].visible = not detail_on
 var h = float(cfg.area.half_size)/cscale
 for k in map_view.chunks:
  var c = map_view.chunks[k]
  if c.trees == null or c.trees.has_meta("god_culled"): continue
  var p = Vector2(c.node.position.x,c.node.position.z)
  if absf(p.x-site.x)<h+192.0 and absf(p.y-site.y)<h+192.0:
   c.trees.set_meta("god_culled",true)
   for t in c.trees.get_children():
    if t is MultiMeshInstance3D: _cull_multimesh(t,h)

func _cull_multimesh(mmi: MultiMeshInstance3D,h: float):
 var mm = mmi.multimesh
 var keep = []
 var cols = []
 for i in mm.instance_count:
  var xf = mmi.transform*mm.get_instance_transform(i)
  var p = Vector2(xf.origin.x,xf.origin.z)
  if absf(p.x-site.x)<h and absf(p.y-site.y)<h: continue
  keep.append(mm.get_instance_transform(i))
  if mm.use_colors: cols.append(mm.get_instance_color(i))
 if keep.size() == mm.instance_count: return
 var nm = MultiMesh.new()
 nm.transform_format = MultiMesh.TRANSFORM_3D
 nm.use_colors = mm.use_colors
 nm.mesh = mm.mesh
 nm.instance_count = keep.size()
 for i in keep.size():
  nm.set_instance_transform(i,keep[i])
  if mm.use_colors: nm.set_instance_color(i,cols[i])
 mmi.multimesh = nm

# Campaign height at a local character-scale point (metres, character scale).
func campaign_height(x: float,z: float) -> float:
 return map_view.height_at(site.x+x/cscale,site.y+z/cscale)*cscale

func is_forest(x: float,z: float) -> bool:
 return Movement.terrain_at(Vector2(site.x+x/cscale,site.y+z/cscale)) == "forest"

func _terrain():
 terrain = Terrain.new()
 terrain.name = "Terrain"
 add_child(terrain)
 terrain.build(cfg.area,Callable(self,"campaign_height"))
 town = Town.new()
 town.name = "Town"
 town.kit_scale = float(cfg.scale.kit_scale)
 town.forest_fn = Callable(self,"is_forest")
 town.layout(terrain,int(cfg.area.seed))
 terrain.finish(Materials.terrain())
 add_child(town)
 debris = Debris.new()
 debris.name = "Debris"
 add_child(debris)
 debris.setup(cfg.punch,terrain)
 town.debris = debris
 town.build()

func _god():
 model = GodModel.new()
 model.setup(float(cfg.scale.god_height))
 player = GodPlayer.new()
 player.name = "Edric"
 add_child(player)
 player.setup(cfg.move,cfg.camera,model,terrain,town)
 player.set_meta("charge_time",float(cfg.punch.charge_time))
 player.set_meta("pull_from",float(cfg.rise.pull_from))
 # Start on the south road below the market, facing the castle.
 var road = town.roads[0]
 var p = road[mini(28,road.size()-1)]
 player.global_position = Vector3(p.x,terrain.height_at(p.x,p.y)+0.5,p.y)
 player.yaw = atan2(-(town.castle.x-p.x),-(town.castle.y-p.y))
 player.landed.connect(_on_landed)
 player.punched.connect(_on_punch)
 player.boom.connect(_on_boom)
 player.slammed.connect(_on_slam)
 player.crashed.connect(_on_crash)
 camera = player.camera

# Chimney smoke and hot-spring steam (a sample, to keep the particle count low).
func _ambient_effects():
 var n = 0
 for c in town.chimneys:
  n += 1
  if n%3 != 0: continue
  smoke_nodes.append(vfx.smoke(c,0.8,-1.0,Color(0.5,0.5,0.52,0.28),6))
 for s in town.springs: smoke_nodes.append(vfx.smoke(s,2.4,-1.0,Color(0.9,0.92,0.95,0.3),14))

# --- Events --------------------------------------------------------------------------------------------

func _on_landed(hard: bool,strength: float):
 var t0 = Time.get_ticks_usec()
 var p = player.global_position
 if villagers: villagers.on_landing(p,45.0,hard)
 if hard:
  vfx.dust(p,6.0+strength*8.0,int(18+strength*30),5.0,Color(0.78,0.78,0.8,0.7),10.0+strength*10.0,0.15)
  vfx.crater(p+Vector3(0,1,0),4.0+strength*6.0,true)
  vfx.ring(p+Vector3(0,0.4,0),2.0,10.0+strength*14.0,0.55,Vector3.UP,1.2,0.7)
  vfx.chips(p,Vector3.UP,int(20+strength*30),Color(0.5,0.48,0.46),10.0+strength*8.0,80.0)
  _hit_stop(0.04+strength*0.04)
  # A hard enough landing in town breaks what is right under the god.
  if strength>0.5:
   var hit = town.chunks_in_sphere(p,3.0+strength*3.0)
   if not hit.is_empty(): town.break_chunks(hit,p-Vector3(0,2,0),18.0,0.8)
  print("GODTEST hard landing %.1f ms" % ((Time.get_ticks_usec()-t0)/1000.0))

func _on_punch(serious: bool,origin: Vector3,dir: Vector3,charge: float):
 var pc = cfg.punch
 if not serious:
  var hit_p = origin+dir*2.4
  var ids = town.chunks_in_sphere(hit_p,float(pc.light_radius))
  vfx.ring(hit_p,0.5,4.0,0.25,dir,0.6,0.6)
  if ids.is_empty():
   vfx.dust(hit_p,1.0,6,1.5,Color(0.8,0.8,0.82,0.35),4.0,0.0)
   return
  var r = town.break_chunks(ids,origin-dir*1.0,float(pc.light_impulse),0.25)
  _impact_effects(hit_p,dir,r,1.0)
  vfx.flash(hit_p,6.0,10.0)
  _hit_stop(float(pc.hit_stop))
  player.shake = maxf(player.shake,0.35)
  if villagers: villagers.on_destruction(hit_p,30.0,0.6,2.0)
  return
 # The serious punch: a cone that levels everything ahead.
 var range = lerpf(38.0,float(pc.serious_range),charge)
 var flat = Vector3(dir.x,dir.y*0.35,dir.z).normalized()
 var cos_half = cos(float(pc.serious_cone))
 big_punch_frame = Engine.get_process_frames()
 var t0 = Time.get_ticks_usec()
 var ids = town.chunks_in_cone(origin,flat,range,cos_half)
 var r = town.break_chunks(ids,origin-flat*2.0,float(pc.serious_impulse)*(0.6+0.6*charge),0.3,0.0)
 # Every building whose centre lies in the cone comes down, the far ones straight into rubble.
 var extra = 0
 for b in town.blocks.size():
  var blk = town.blocks[b]
  if blk.ruined: continue
  var d = blk.center-origin
  d.y *= 0.35
  if d.length()<range and d.normalized().dot(flat)>cos_half-0.05:
   town.collapse(b,origin,float(pc.serious_impulse)*0.4)
   r.ruins.append(blk.center)
   extra += 1
 var trees = foliage.knock_down(origin,flat,range*1.15,cos_half-0.1) if foliage else 0
 print("GODTEST serious punch: range %.0f m, %d chunks broken, %d buildings down, %d trees, %.1f ms" % [range,r.broken,r.collapsed+extra,trees,(Time.get_ticks_usec()-t0)/1000.0])
 # Effects: the blast ring, a long dust front down the cone, fires in the ruins.
 vfx.ring(origin-Vector3(0,1.2,0),2.0,range,0.9,Vector3.UP,2.5,1.4)
 vfx.ring(origin+flat*3.0,1.0,12.0,0.35,flat,1.5,1.2)
 for k in 9:
  var p = origin+flat*range*(0.12+0.1*k)
  p.y = terrain.height_at(p.x,p.z)+2.0
  vfx.dust(p,8.0+k*1.6,14,10.0+k*0.6,Color(0.66,0.62,0.56,0.8),14.0,0.35)
 vfx.dust(origin+flat*6.0,5.0,24,4.0,Color(0.85,0.85,0.88,0.6),20.0,0.1)
 var fires = 0
 for c in r.ruins:
  if fires<6 and randf()<0.35:
   vfx.fire(Vector3(c.x,terrain.height_at(c.x,c.z)+0.8,c.z),1.4,40.0)
   fires += 1
  vfx.embers(Vector3(c.x,terrain.height_at(c.x,c.z)+2.0,c.z),4.0,30,5.0)
 _impact_effects(origin+flat*8.0,flat,r,3.0)
 vfx.crater(origin-Vector3(0,1.0,0)+flat*6.0,10.0,true)
 vfx.flash(origin+flat*4.0,40.0,60.0,0.35)
 hud.flash = 0.55
 player.shake = maxf(player.shake,1.3)
 _time_slow(float(pc.time_slow),float(pc.time_slow_for))
 if villagers: villagers.on_destruction(origin+flat*range*0.5,range*1.4,1.0,range*0.8)

func _impact_effects(p: Vector3,dir: Vector3,r: Dictionary,scale: float):
 for m in r.mats:
  var cls = MeshKit.MAT_IDS[m]
  var col = Color(0.5,0.48,0.45)
  match cls:
   "timber","planks","door","window": col = Color(0.36,0.26,0.17)
   "plaster": col = Color(0.78,0.75,0.68)
   "slate": col = Color(0.27,0.3,0.34)
   "thatch": col = Color(0.62,0.52,0.3)
  vfx.chips(p,dir,int(minf(40.0,r.mats[m]*2.0*scale)),col,12.0*scale,70.0,cls in ["timber","planks","door","window"])
 var n = 0
 for c in r.centers:
  n += 1
  if n%4 != 0: continue
  vfx.dust(c,3.0*scale,10,4.0+scale,Color(0.7,0.66,0.6,0.7),5.0,0.3)

func _on_boom(pos: Vector3,dir: Vector3):
 vfx.ring(pos,2.0,26.0,0.6,dir,2.0,1.5)
 vfx.ring(pos-dir*6.0,1.0,16.0,0.45,dir,1.2,1.0)
 vfx.dust(pos,3.0,16,1.6,Color(0.92,0.94,0.98,0.5),18.0,0.0)
 hud.flash = maxf(hud.flash,0.2)
 # The boom flattens what stands right below a low pass.
 var alt = pos.y-terrain.height_at(pos.x,pos.z)
 if alt<25.0 and foliage: foliage.knock_down(Vector3(pos.x,terrain.height_at(pos.x,pos.z),pos.z),dir,18.0,-1.0)

func _on_slam(pos: Vector3):
 var pc = cfg.punch
 var rad = float(pc.slam_radius)
 var t0 = Time.get_ticks_usec()
 var ids = town.chunks_in_sphere(pos,rad)
 var r = town.break_chunks(ids,pos-Vector3(0,4,0),float(pc.slam_impulse),0.9,rad*0.55)
 var t1 = Time.get_ticks_usec()
 var trees = foliage.knock_down(pos,Vector3.FORWARD,rad*1.6,-1.0) if foliage else 0
 var t2 = Time.get_ticks_usec()
 vfx.crater(pos+Vector3(0,2,0),16.0)
 vfx.ring(pos+Vector3(0,0.6,0),3.0,rad*1.8,1.0,Vector3.UP,3.0,1.6)
 vfx.ring(pos+Vector3(0,3.0,0),2.0,rad*1.2,0.7,Vector3.UP,1.5,1.0)
 # The dust ring, chips, embers and fires start a frame later (the slam's own frame is busy enough).
 get_tree().process_frame.connect(func():
  for k in 10:
   var a = k*TAU/10.0
   var p = pos+Vector3(cos(a),0,sin(a))*rad*0.7
   p.y = terrain.height_at(p.x,p.z)+1.5
   vfx.dust(p,9.0,12,9.0,Color(0.7,0.68,0.64,0.8),16.0,0.2)
  vfx.dust(pos,6.0,16,6.0,Color(0.86,0.86,0.9,0.7),24.0,0.05)
  vfx.chips(pos,Vector3.UP,80,Color(0.45,0.42,0.4),26.0,85.0)
  vfx.embers(pos,6.0,60,5.0)
  for c in r.ruins.slice(0,4): vfx.fire(Vector3(c.x,terrain.height_at(c.x,c.z)+0.8,c.z),1.2,35.0),CONNECT_ONE_SHOT)
 vfx.flash(pos+Vector3(0,3,0),60.0,80.0,0.4)
 hud.flash = 0.7
 player.shake = 1.6
 _hit_stop(0.12)
 var t3 = Time.get_ticks_usec()
 if villagers: villagers.on_destruction(pos,rad*2.2,1.0,rad)
 print("GODTEST slam: %d chunks, %d buildings, %d trees; break %.1f ms, trees %.1f ms, effects %.1f ms, villagers %.1f ms" % [r.broken,r.collapsed,trees,(t1-t0)/1000.0,(t2-t1)/1000.0,(t3-t2)/1000.0,(Time.get_ticks_usec()-t3)/1000.0])

func _on_crash(pos: Vector3,speed: float):
 vfx.dust(pos,3.0,10,3.0,Color(0.7,0.66,0.6,0.7),8.0,0.2)
 vfx.chips(pos,player.velocity.normalized(),24,Color(0.5,0.45,0.4),speed*0.4,50.0)
 if villagers: villagers.on_destruction(pos,30.0,0.5,3.0)

# Meteor Flight's trail while diving (called by god/empire.gd).
func vfx_meteor(pos: Vector3,dir: Vector3,speed: float):
 meteor_t += get_process_delta_time()
 if meteor_t<0.05: return
 meteor_t = 0.0
 vfx.embers(pos,1.5,6,1.2)
 if speed<900.0: vfx.dust(pos,2.0,3,1.5,Color(0.95,0.7,0.45,0.5),2.0,0.0)

# --- Time effects (in real time, so they hold under Engine.time_scale) -----------------------------------

func _hit_stop(secs: float):
 stop_until = maxf(stop_until,real_clock+secs)

func _time_slow(scale: float,secs: float):
 slow_until = real_clock+secs
 Engine.time_scale = scale

func _process(delta):
 var real = delta/maxf(Engine.time_scale,0.01)
 real_clock += real
 var ts = 1.0
 if real_clock<slow_until: ts = minf(ts,float(cfg.punch.time_slow))
 if real_clock<stop_until: ts = 0.03
 Engine.time_scale = ts
 if not ready_done: return
 if foliage and detail_on: foliage.update_grass(camera.global_position if camera != player.camera else player.global_position)
 vfx.charge_swirl(player.global_position+Vector3(0,0.3,0),player.charge_amount()>0.0,player.charge_amount())
 model.model.find_children("*","MeshInstance3D",true,false)[0].material_override.set_shader_parameter("power",player.charge_amount())
 if player.charge_amount()>0.5: player.shake = maxf(player.shake,(player.charge_amount()-0.5)*0.9)
 # Atmosphere with altitude: the haze thins and the depth of field goes as the camera climbs.
 var cp = camera.global_position
 var alt = cp.y-(terrain.height_at(cp.x,cp.z) if terrain.inside(cp.x,cp.z) else campaign_height(cp.x,cp.z))
 var high = smoothstep(150.0,1600.0,alt)
 # Strengths fade (kept just above zero) rather than the features switching on and off mid-flight.
 env.fog_density = lerpf(0.00032,0.000002,high)
 env.fog_height_density = lerpf(0.002,0.00001,high)
 env.volumetric_fog_density = lerpf(0.0028,0.00002,smoothstep(200.0,600.0,alt))
 cam_attr.dof_blur_amount = lerpf(0.03,0.002,smoothstep(150.0,300.0,alt))
 terrain.material.set_shader_parameter("far_blend",smoothstep(300.0,2500.0,alt))
 sun.directional_shadow_max_distance = lerpf(float(cfg.render.shadow_distance),1600.0,smoothstep(100.0,900.0,alt))
 # On the ground the campaign map stays as built around the site (only its far land shows past the
 # area's edge); streaming it as the god walks cost 100+ ms hitches for nothing visible.


# Well above the cloud deck the character-scale area hides, the hole in the campaign terrain closes and
# the campaign's own Frosthold shows (from there the area would read as a square patch of different
# ground); the swap happens with the deck between the camera and the land.
func set_detail_world(on: bool):
 detail_on = on
 for n in [terrain,town,debris,foliage,villagers]:
  if n != null: n.visible = on
 _hole(on)
 var sid = str(cfg.area.settlement)
 if map_view.settlements.has(sid): map_view.settlements[sid].visible = not on
 if map_view.landmarks.has(sid): map_view.landmarks[sid].visible = not on

func reset_town():
 town.reset()
 debris.clear()
 vfx.clear()
 if foliage: foliage.reset()
 if villagers: villagers.reset_all()
 _ambient_effects()
 hud.say("Frosthold restored.",2.0)

func _unhandled_input(e):
 if showcase != null: return
 if e is InputEventKey and e.pressed and not e.echo:
  match e.physical_keycode:
   KEY_R: reset_town()
   KEY_H: hud.show_help = not hud.show_help
   KEY_F3: hud.show_perf = not hud.show_perf
   KEY_TAB:
    if empire.mode == "strategic": empire._close_strategic(null)
    elif empire.mode == "empire": empire._open_strategic()
 if e is InputEventMouseButton and e.pressed:
  if e.button_index == MOUSE_BUTTON_WHEEL_UP: empire.wheel(-1.0)
  if e.button_index == MOUSE_BUTTON_WHEEL_DOWN: empire.wheel(1.0)
  if e.button_index == MOUSE_BUTTON_LEFT and empire.mode == "empire": empire.click_dive(e.position)

func _physics_process(_delta):
 if hud != null and hud.show_perf:
  hud.perf_text = "%d fps  %.1f ms  draws %d  tris %dk  debris %d  VRAM %d MB" % [Engine.get_frames_per_second(),1000.0/maxf(1.0,Engine.get_frames_per_second()),
   Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)/1000,debris.live_count(),
   Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576]

# --- Captures ---------------------------------------------------------------------------------------

func _shot(name: String):
 var v = _arg("--view=","")
 if v != "":
  # A fixed camera of its own (the player's sits on a spring arm); no HUD, for comparisons.
  var q = v.split(",")
  var cam = Camera3D.new()
  cam.fov = float(cfg.camera.fov)
  cam.far = 60000.0
  cam.near = 0.1
  add_child(cam)
  cam.global_position = Vector3(float(q[0]),float(q[1]),float(q[2]))
  cam.global_rotation = Vector3(deg_to_rad(float(q[4])),deg_to_rad(float(q[3])),0)
  cam.make_current()
  camera = cam
  hud.visible = false
  if foliage: for i in 40: foliage.update_grass(cam.global_position)
 elif args.has("--face"):
  # Edric seen from the front (model checks).
  var pz = _arg("--pose=","")
  if pz != "":
   player.set_physics_process(false)
   model.play(pz.get_slice(":",0),0.0,0.0)
   model.player.seek(float(pz.get_slice(":",1)),true)
  var cam = Camera3D.new()
  cam.fov = 40.0
  add_child(cam)
  var fwd = Basis(Vector3.UP,player.yaw+deg_to_rad(float(_arg("--face-angle=","0"))))*Vector3(0,0,-1)
  cam.global_position = player.global_position+fwd*6.5+Vector3(0,2.0,0)
  cam.look_at(player.global_position+Vector3(0,1.4,0),Vector3.UP)
  cam.make_current()
  camera = cam
  hud.visible = false
 hud.show_help = false
 for i in 60: await get_tree().process_frame
 if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
 print("GODTEST player %s at %s, ground %.2f, floor %s, anim %s" % [player.state_name(),player.global_position,terrain.height_at(player.global_position.x,player.global_position.z),player.is_on_floor(),model.current])
 save_frame(name)
 get_tree().quit(0)

func save_frame(name: String):
 if DisplayServer.get_name() == "headless": return
 var dir = "res://captures/god_test/"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
 get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(dir+name+".png"))
 print("GODTEST shot ",name)

# A short camera tour while loading: every kind of thing is drawn once (near and far LODs, impostors,
# the area seen from above, the campaign map high up), so shaders compile now instead of stalling the
# first rise or dive by 100-500 ms.
func _warm_up():
 if DisplayServer.get_name() == "headless": return
 var cam = Camera3D.new()
 cam.far = 60000.0
 add_child(cam)
 cam.make_current()
 var c = Vector3(town.castle.x,0,town.castle.y)
 for v in [[Vector3(0,40,260),Vector3(0,10,0)],[Vector3(300,300,500),c],[Vector3(0,1500,900),c],[Vector3(0,3000,10),c],[Vector3(0,7000,2000),c],[Vector3(-600,60,-300),Vector3(-900,20,-500)],[Vector3(700,80,600),c]]:
  cam.global_position = v[0]
  cam.look_at(v[1],Vector3.UP)
  for i in 4: await get_tree().process_frame
 camera = player.camera
 camera.make_current()
 cam.queue_free()

# --bench=<label>: GPU and CPU frame cost from a fixed ground view in the town (3 s after warm-up),
# appended to --out=<file>; flags --no-ssao, --no-vfog, --ssil, --sdfgi, --fsr=<scale>,
# --no-foliage, --no-villagers, --view=... change what is measured.
func _bench(label: String):
 if args.has("--no-ssao"): env.ssao_enabled = false
 if args.has("--no-vfog"): env.volumetric_fog_enabled = false
 if args.has("--ssil"): env.ssil_enabled = true
 if args.has("--sdfgi"):
  env.sdfgi_enabled = true
  env.sdfgi_use_occlusion = true
 if _arg("--fsr=","") != "":
  get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
  get_viewport().scaling_3d_scale = float(_arg("--fsr=","1.0"))
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 var v = _arg("--view=","")
 if v != "":
  var q = v.split(",")
  var cam = Camera3D.new()
  cam.fov = float(cfg.camera.fov)
  cam.far = 60000.0
  add_child(cam)
  cam.global_position = Vector3(float(q[0]),float(q[1]),float(q[2]))
  cam.global_rotation = Vector3(deg_to_rad(float(q[4])),deg_to_rad(float(q[3])),0)
  cam.make_current()
  camera = cam
 hud.show_help = false
 var rid = get_viewport().get_viewport_rid()
 RenderingServer.viewport_set_measure_render_time(rid,true)
 for i in 90: await get_tree().process_frame
 var gpu = 0.0
 var cpu = 0.0
 var n = 0
 var worst = 0.0
 var last = Time.get_ticks_usec()
 var t0 = last
 while Time.get_ticks_usec()-t0<3000000:
  await get_tree().process_frame
  var now = Time.get_ticks_usec()
  worst = maxf(worst,(now-last)/1000.0)
  last = now
  gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
  cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
  n += 1
 var line = "GODTEST bench %s window=%s fps=%.1f frame_ms=%.2f worst_ms=%.1f gpu_ms=%.2f render_cpu_ms=%.2f draw_calls=%d primitives=%d vram_mb=%.0f" % [label,str(DisplayServer.window_get_size()),n/3.0,3000.0/n,worst,gpu/n,cpu/n,
  Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0]
 print(line)
 var out = _arg("--out=","")
 if out != "":
  var f = FileAccess.open(out,FileAccess.READ_WRITE) if FileAccess.file_exists(out) else FileAccess.open(out,FileAccess.WRITE)
  f.seek_end()
  f.store_line(line)
  f.close()
 get_tree().quit(0)

# The campaign map's Greywall stands on the horizon from Frosthold; at this scale its flat campaign
# colour reads as cardboard, so here it gets the castle stone (world triplanar, cool grey).
func _great_wall_look():
 var walls = map_view.get_node_or_null("GreatWalls")
 if walls == null: return
 var m = StandardMaterial3D.new()
 m.albedo_texture = Materials.tex("castle_wall_slates","diff")
 m.normal_enabled = true
 m.normal_texture = Materials.tex("castle_wall_slates","nor_gl")
 m.uv1_triplanar = true
 m.uv1_world_triplanar = true
 m.uv1_scale = Vector3.ONE*0.18
 m.albedo_color = Color(0.72,0.75,0.8)
 m.roughness = 0.9
 for mi in walls.get_children(): if mi is GeometryInstance3D: mi.material_override = m
