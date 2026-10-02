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
const StrategicMap = preload("res://ui/strategic_map.gd")
const UiKit = preload("res://ui/ui_kit.gd")
const SettlementBanner = preload("res://ui/settlement_banner.gd")
const TerritoryOverlay = preload("res://visuals/terrain/territory_overlay.gd")
const MovementOverlay = preload("res://ui/movement_overlay.gd")
const Battles = preload("res://core/battles.gd")
const Deployment = preload("res://core/deployment.gd")
const SaveSystem = preload("res://core/save_system.gd")
const Session = preload("res://core/session.gd")
const Settings = preload("res://core/settings.gd")
const MapRegistry = preload("res://core/map_registry.gd")
const PauseMenu = preload("res://ui/pause_menu.gd")
const GameOver = preload("res://ui/game_over.gd")
const Realm = preload("res://core/realm.gd")
const Ai = preload("res://core/ai.gd")
const TurnLoop = preload("res://core/turn_loop.gd")
const BattleSim = preload("res://core/battle_sim.gd")
const WALK_SPEED = 12.0 # map meters per second while the figure walks (presentation only)
const STRATEGIC_RETURN_DISTANCE = 150.0 # zoom after returning from the strategic map to a place
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
var map_press := false # the left press landed on the map (not on the interface); only then is the release a map click
var terrain_material: ShaderMaterial
var minimap
var movement_overlay
var walks = {}           # army id -> figure walking a path: {points, dist, total}
var army_figures = {}    # army id -> map figure (the commander visual, banner in faction colors)
var follow_army = false   # camera follows the selected army
var collecting_moves = false # End Turn: moves are gathered, then replayed (AI armies near you followed)
var collected_moves = {}
var spectate_queue: Array = [] # [[army id, path]] still to show, camera following
var ai_paused := false # the AI turn bar's Pause (presentation only)
var strategic: Control # the strategic map (Tab or zooming out)
var spectating := {}           # {id, hold}: the AI army the camera follows now
var rmb_held := false       # right mouse held with an army selected: path preview (TW:WH3)
var pitch_offset := 0.0     # middle-drag tilt on top of the zoom-dependent tilt
var preview_key = Vector2i(1<<20,0)
var preview_text = ""
var forced_preview = null # capture flag --preview=x,z: preview this point instead of the mouse
var loaded_from := ""    # "" prototype start, "new" campaign from the menu, or the save file loaded
var unsaved := false     # campaign changed since the last save or load
var pause_menu: Control
var game_over: Control

func _ready():
 rng.seed = 87231
 noise.seed = 441
 noise.frequency = 0.023
 noise.fractal_octaves = 5
 detail.seed = 272
 detail.frequency = 0.12
 detail.fractal_octaves = 3
 capture_mode = "--capture" in OS.get_cmdline_user_args()
 # Captures and the self-test never touch the player's saves.
 if capture_mode or "--self-test" in OS.get_cmdline_user_args(): SaveSystem.dir = "user://capture_saves"
 kit = ProtoKit.shared()
 set_pitch(OVERVIEW_PITCH) # the overview's tilt at its zoom
 Settings.apply(get_tree())
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
  set_pitch(OVERVIEW_PITCH)
 if "--hero" in OS.get_cmdline_user_args():
  target = commander.position + Vector3(0,2.8,0)
  distance = 15
  desired_distance = 15
  yaw = 0.35
  set_pitch(0.23)
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
 # --recruit-demo (captures): the host at Goldspire with a mixed queue (local green, global blue,
 # overflow orange) and the recruitment panel open.
 if "--recruit-demo" in OS.get_cmdline_user_args():
  var gp = WorldMap.settlement_position(GOLDSPIRE_ID)
  ui_data.state.army_state[COMMANDER_ARMY].position = [gp.x,gp.y]
  ui_data.state.army_state[COMMANDER_ARMY].garrison = GOLDSPIRE_ID
  ui_data.state.treasury[ui_data.player_faction_id()] += 20000
  place_commander()
  for m in ["local","local","global","local","local"]: ui_data.recruit(COMMANDER_ARMY,"peasant_levy",m)
  select_army()
  ui.open_recruitment(COMMANDER_ARMY)
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
  if arg.begins_with("--attack="):
   # Captures: stand the host next to a settlement, declare war, open the pre-battle panel.
   var sid = arg.get_slice("=",1)
   var sp = WorldMap.settlement_position(sid)
   ui_data.state.army_state[COMMANDER_ARMY].position = [sp.x+8.0,sp.y+4.0]
   ui_data.state.army_state[COMMANDER_ARMY].garrison = ""
   place_commander()
   select_army()
   var t = ui_data.battle_target(COMMANDER_ARMY,sp)
   ui_data.declare_war(t.faction)
   t.needs_war = false
   ui.open_battle_flow(COMMANDER_ARMY,sp,t)
   if "--attack-resolve" in OS.get_cmdline_user_args():
    ui.battle_box.find_child("QuickResolve",true,false).pressed.emit()
    update_walk(1000.0)
 # Debt and loss captures: --set-treasury=N; --lose-lands gives the player's settlements to House
 # Lannet (armies kept) and ends the turn, so the grace period starts; --game-over destroys the
 # player's house.
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--set-treasury="):
   ui_data.state.treasury[ui_data.player_faction_id()] = int(arg.get_slice("=",1))
   ui_data.changed.emit()
  if arg == "--lose-lands":
   for sid in ui_data.state.settlements_of(ui_data.player_faction_id()):
    Battles.occupy(ui_data.state,sid,"house_lannet","")
   for id in ui_data.state.army_state:
    if ui_data.state.army_state[id].faction == ui_data.player_faction_id(): ui_data.state.army_state[id].garrison = ""
   end_turn()
   update_walk(1000.0)
  if arg == "--game-over":
   Realm.destroy(ui_data.state,ui_data.player_faction_id())
   ui_data.changed.emit()
   refresh_army_overlays()
   show_game_over()
 # AI captures: --scenario=siege|attacked puts House Lannet at war with the player and its army
 # (reinforced for the setup) near Crownwatch, then runs a real End Turn: a weaker army besieges,
 # a stronger one attacks and the player must answer (--defense opens the panel).
 # --ai-turns=N plays N turns with every faction AI-controlled (chronicle captures).
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--scenario="):
   var kind = arg.get_slice("=",1)
   var st = ui_data.state
   var g = st.army_state.silverfall_guard
   var kinds = ["spearmen","swordsmen","archers","heavy_infantry","spearmen","archers","cavalry"]
   for i in (2 if kind == "siege" else 9): g.units.append({"unit":kinds[i%kinds.size()],"men":100,"max_men":100})
   var cw = WorldMap.settlement_position("crownwatch")
   g.position = [cw.x-14.0,cw.y+6.0]
   g.garrison = ""
   var gp = WorldMap.settlement_position(GOLDSPIRE_ID)
   if kind == "siege":
    st.army_state[COMMANDER_ARMY].position = [gp.x,gp.y]
    st.army_state[COMMANDER_ARMY].garrison = GOLDSPIRE_ID
   Battles.declare_war(st,"house_lannet",st.player_faction)
   place_commander()
   end_turn()
   update_walk(1000.0)
   focus_at(ground(cw,4.0),70.0)
  if arg.begins_with("--ai-turns="):
   var opts = {"factions":ui_data.state.factions(),"resolve_player":true}
   for i in int(arg.get_slice("=",1)): TurnLoop.end_turn(ui_data.state,opts)
   ui_data.changed.emit()
   ui._rebuild_events()
   refresh_army_overlays()
 # Deployment captures: --deploy opens the screen, --deploy-2d shows the board, --deploy-template=
 # applies a template, --deploy-orders=i:order[:arg],... gives orders (arg: left/right or a unit)
 # and --deploy-fight fights with that deployment.
 for arg in OS.get_cmdline_user_args():
  if arg == "--deploy" and ui.battle_visible():
   ui.open_deployment()
   var ds = ui.deployment_screen
   for a2 in OS.get_cmdline_user_args():
    if a2.begins_with("--deploy-template="): ds.apply_template(a2.get_slice("=",1))
   for a2 in OS.get_cmdline_user_args():
    if a2.begins_with("--deploy-orders="):
     for o in a2.get_slice("=",1).split(","):
      var p = o.split(":")
      ds.select(int(p[0]))
      if p[1] == "protect":
       ds._order("protect")
       ds.select(int(p[2]))
      else: ds._order(p[1]+(":"+p[2] if p.size()>2 else ""))
   if "--deploy-2d" in OS.get_cmdline_user_args(): ds._set_view(false)
   ds.update_odds()
   if "--deploy-fight" in OS.get_cmdline_user_args():
    ds._fight()
    update_walk(1000.0)
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
  if arg.begins_with("--select-after="):
   ui.close_report()
   select_settlement(arg.get_slice("=",1))
 # Report captures: --report-event=k jumps the replay to timeline event k; --report-timeline expands it.
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--report-event=") and ui.report_visible():
   var ev = ui.report_timeline.get_child(int(arg.get_slice("=",1)))
   if ev: ev.pressed.emit()
  if arg == "--report-timeline" and ui.report_visible(): ui.report_box.find_child("TimelineToggle",true,false).pressed.emit()
 if "--chronicle" in OS.get_cmdline_user_args(): ui.toggle_chronicle()
 # --strategic opens the strategic map at once; --layer=ID picks its layer (captures).
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--layer="): strategic.set_layer(arg.get_slice("=",1))
 if "--strategic" in OS.get_cmdline_user_args(): open_strategic_map(true)
 if "--pause-menu" in OS.get_cmdline_user_args(): open_pause_menu()
 if "--self-test" in OS.get_cmdline_user_args():
  run_checks()
 print("FREEDOM_READY | city=%s road=%s traffic=%s seed=%d" % [city_level,road_level,traffic.size(),ui_data.state.seed])

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
 # Faction tint and glowing territory borders, rasterized from data/maps/<map>/provinces.json.
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
 set_pitch(0.36)

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
 # The army this commander leads (data/maps/<map>/armies/); shown in the army panel.
 commander.set_meta("army_id",COMMANDER_ARMY)

# --- Campaign UI ---------------------------------------------------------------
# The TW:WH3-style shell lives in ui/campaign_ui.gd and reads only from UiData (core/ui_data.gd).

# A new campaign gets a random seed; captures and the self-test use the start file's fixed seed,
# and --seed=N replays a given campaign.
func _campaign():
 var GameState = load("res://core/game_state.gd")
 if Session.pending_state != null:
  loaded_from = Session.pending_name if Session.pending_name != "" else "new"
  var s = Session.pending_state
  Session.pending_state = null
  Session.pending_name = ""
  return s
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--seed="): return GameState.from_data(GameState.START,int(arg.get_slice("=",1)))
 if capture_mode or "--self-test" in OS.get_cmdline_user_args(): return GameState.from_data()
 return GameState.new_campaign()

func make_ui():
 var layer = CanvasLayer.new()
 add_child(layer)
 studio = PortraitStudio.new()
 add_child(studio)
 ui_data = UiData.new(_campaign())
 # The prototype start state takes its two showcase settlements' levels from the scene; a loaded or
 # menu-started campaign keeps its own and the scene follows it (sync_settlement_visuals).
 if loaded_from == "":
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
 strategic = StrategicMap.new()
 strategic.name = "StrategicMap"
 layer.add_child(strategic)
 layer.move_child(strategic,ui.get_index()) # under the interface, over the 3D map
 strategic.setup(ui_data,TerritoryOverlay.RECT)
 strategic.location_chosen.connect(close_strategic_map)
 strategic.closed.connect(func(): close_strategic_map())
 ui.end_turn_requested.connect(end_turn_pressed)
 ui.warning_step.connect(step_warning)
 ui.warning_skip.connect(skip_warning)
 ui.ai_skip.connect(skip_spectating)
 ui.ai_pause_toggled.connect(func(on): ai_paused = on)
 ui_data.changed.connect(refresh_warnings)
 ui.settlement_selected.connect(focus_settlement)
 ui.overlay_toggled.connect(set_overlay)
 ui.menu_requested.connect(open_pause_menu)
 ui.army_chosen.connect(func(id):
  select_army(id)
  if army_figures.has(id): pan_to(army_figures[id].position+Vector3(0,2.2,0)))
 ui.settlement_chosen.connect(func(id): if settlement_anchors.has(id): select_settlement(id,true))
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
 ui_data.changed.connect(sync_territory)
 ui.battle_resolved.connect(func(_out): refresh_army_overlays())
 ui.army_raised.connect(func(id):
  refresh_army_overlays()
  select_army(id))
 refresh_army_overlays()
 refresh_warnings()
 ui_data.changed.connect(func(): unsaved = true)
 if loaded_from != "":
  sync_settlement_visuals()
  sync_territory()
  apply_camera_view(Session.take_view())
  if ui_data.resources().destroyed: show_game_over.call_deferred()
  if loaded_from != "new": ui.toast("Loaded: %s" % loaded_from)
  if capture_mode: print("LOAD_TO_CAMPAIGN_MS %d (scene rebuilt from the save)" % (Time.get_ticks_msec()-Session.started_at))

# Territory colors follow settlement ownership (captures change them).
var territory_owners := {}
func sync_territory():
 var owners = {}
 for id in ui_data.settlement_ids(): owners[id] = ui_data.settlement(id).owner
 if owners == territory_owners: return
 var first = territory_owners.is_empty()
 territory_owners = owners
 TerritoryOverlay.live_owners = owners
 if first and owners.keys().all(func(k): return owners[k] == WorldMap.owner_of(k)): return
 terrain_material.set_shader_parameter("territory_tint",TerritoryOverlay.tint_texture())
 terrain_material.set_shader_parameter("territory_border",TerritoryOverlay.border_texture())
 if minimap: minimap.refresh()

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

# Selecting on the map never moves the camera (TW:WH3, owner). focus: jumps from lists, cycling
# and bookmarks pan there at the current zoom (G keeps its Goldspire view).
func select_settlement(id: String,focus := false):
 ui.show_settlement(id)
 if focus: focus_settlement(id)

func focus_settlement(id: String):
 var a = settlement_anchors[id]
 pan_to(ground(Vector2(a.x,a.z)))

# Move the camera's target at the current zoom (no zoom change).
func pan_to(p: Vector3):
 target = p

func pan_to_capital():
 var cap = load("res://core/armies.gd").capital(ui_data.state,ui_data.player_faction_id())
 if cap != "" and settlement_anchors.has(cap): pan_to(ground(Vector2(settlement_anchors[cap].x,settlement_anchors[cap].z)))

# Left click on empty ground: cancel the selection (TW:WH3).
func deselect():
 if ui.selected_settlement == "" and ui.selected_army == "": return
 ui.clear_selection()
 refresh_army_overlays()

# K hides or shows the interface (TW:WH3); Alt+K also adds cinematic letterbox bars. Esc brings
# the interface back.
var letterbox: CanvasLayer
func toggle_interface(cinematic := false):
 var show = not ui.visible
 ui.visible = show
 pins_root.visible = show and overlays.get("settlements",true)
 if letterbox == null:
  letterbox = CanvasLayer.new()
  letterbox.layer = 5
  for top in [true,false]:
   var bar = ColorRect.new()
   bar.color = Color.BLACK
   bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
   bar.anchor_right = 1.0
   bar.anchor_top = 0.0 if top else 1.0
   bar.anchor_bottom = 0.0 if top else 1.0
   bar.offset_top = 0.0 if top else -90.0
   bar.offset_bottom = 90.0 if top else 0.0
   letterbox.add_child(bar)
  add_child(letterbox)
 letterbox.visible = cinematic and not show

# Ctrl+T (TW:WH3): settlement labels (the banners) on or off.
func toggle_labels():
 var on = not overlays.get("settlements",true)
 set_overlay("settlements",on)
 ui.set_overlay_state("settlements",on)

# Keys 1 and 2 (TW:WH3 overview and garrison): the selected settlement's building slots or its
# garrison; with an army selected that stands in a settlement, that settlement.
func panel_tab(tab: String):
 if ui.selected_settlement == "" and army_selected():
  var g = ui_data.army_movement(selected_army_id()).garrison
  if g != "" and settlement_anchors.has(g): ui.show_settlement(g)
 if ui.selected_settlement != "": ui.set_settlement_tab(tab)

# R (TW:WH3 character move speed): your armies' map animation at 1x or 2x (saved in Settings).
func toggle_army_speed():
 Settings.set_value("army_speed",2 if Settings.army_speed() == 1 else 1)
 ui.toast("Your armies move at %dx speed." % Settings.army_speed())
 ui.camera_settings_changed()

# Tab, or zooming out past the farthest zoom (TW:WH3): the flat strategic map. Clicking a place or
# scrolling in there returns to the 3D map at that place; Tab or Esc returns where the camera was.
func toggle_strategic_map():
 if map_open(): close_strategic_map()
 else: open_strategic_map()

func map_open() -> bool:
 return strategic != null and strategic.is_open()

func open_strategic_map(instant := false):
 if map_open(): return
 cancel_move_preview()
 ui.hide_hover()
 strategic.set_selected_army(selected_army_id())
 strategic.open_map(instant)
 pins_root.visible = false

# world: where to return (null: where the camera was).
func close_strategic_map(world = null):
 if not map_open(): return
 strategic.close_map()
 get_viewport().disable_3d = false
 pins_root.visible = ui.visible and overlays.get("settlements",true)
 if world != null:
  pan_to(ground(world))
  desired_distance = minf(desired_distance,STRATEGIC_RETURN_DISTANCE)

func cancel_move_preview():
 rmb_held = false
 ui.preview_movement(0.0,false)
 ui.hide_hover()
 if movement_overlay: movement_overlay.clear("preview")
 preview_key = Vector2i(1<<20,0)

# , and . : previous / next own army, or own settlement when a settlement is selected; the camera
# pans there at the current zoom.
func cycle_selection(step: int):
 if ui.selected_settlement != "":
  var own = ui_data.state.settlements_of(ui_data.player_faction_id()).filter(func(s): return settlement_anchors.has(s))
  if own.is_empty(): return
  var i = own.find(ui.selected_settlement)
  select_settlement(own[posmod(i+step,own.size())],true)
  return
 var armies = []
 for id in ui_data.army_ids():
  if ui_data.army(id).player_owned: armies.append(id)
 if armies.is_empty(): return
 var j = armies.find(selected_army_id())
 var next = armies[posmod(j+step,armies.size()) if j>=0 else 0]
 select_army(next)
 if army_figures.has(next): pan_to(army_figures[next].position+Vector3(0,2.2,0))

func select_army(id := COMMANDER_ARMY):
 if not army_figures.has(id): return
 ui.show_army(id,army_location(id))
 refresh_army_overlays()


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
 update_grace_labels()
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
# The held-right-click preview (TW:WH3): the coloured path (green this turn) and, on the movement
# bar, what it would spend. No numbers: the returned tooltip text is only for an impossible move
# ("" when the move is fine) or an attack ("Attack Greyhaven").
func preview_move(p: Vector2) -> String:
 var key = Vector2i(floori(p.x),floori(p.y))
 if key == preview_key: return preview_text
 preview_key = key
 var id = selected_army_id()
 var plan = ui_data.plan_move(id,p)
 preview_text = ""
 if not plan.ok and plan.reason == Movement.BLOCKED_BATTLE:
  var atk = ui_data.attack_preview(id,p)
  if atk.plan.get("ok",false):
   plan = atk.plan
   preview_text = "Attack %s" % atk.name if atk.ok else "%s: %s" % [atk.name,atk.reason]
  else:
   movement_overlay.show_blocked(p,atk.reason)
   ui.preview_movement(0.0,false)
   preview_text = atk.reason if atk.reason != "" else plan.reason
   return preview_text
 elif not plan.ok:
  movement_overlay.show_blocked(p,plan.reason)
  ui.preview_movement(0.0,false)
  preview_text = plan.reason
  return preview_text
 movement_overlay.show_path("preview",plan.points,plan.turns)
 var m = ui_data.army_movement(id)
 ui.preview_movement(minf(float(plan.cost),m.points)/maxf(1.0,m.max_points),int(plan.total_turns)>1)
 return preview_text

func order_army(p: Vector2):
 var r = ui_data.order_move(selected_army_id(),p)
 movement_overlay.clear("preview")
 if not r.ok:
  # An enemy army or settlement: the war / pre-battle flow (core/battles.gd).
  if r.reason == Movement.BLOCKED_BATTLE:
   var t = ui_data.battle_target(selected_army_id(),p)
   if t.kind != "":
    ui.open_battle_flow(selected_army_id(),p,t)
    return
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
 if collecting_moves:
  collected_moves[id] = walked
  return
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
  var own = ui_data.state.army_state.has(id) and ui_data.state.army_state[id].faction == ui_data.player_faction_id()
  if ai_paused and not own: continue # the AI turn is paused (its bar's Pause)
  w.dist = minf(w.total,w.dist+delta*Settings.walk_speed(WALK_SPEED,own))
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

func end_turn(_skip_warnings := false):
 if spectating_now():
  return
 warn_skipped.clear()
 warn_index.clear()
 if ui_data.has_pending_battle():
  ui.toast("An enemy army is attacking: answer it first.")
  open_pending_battle()
  return
 # Autosave at the start of End Turn (3 rotating slots), before anything changes.
 var t0 = Time.get_ticks_usec()
 var a = SaveSystem.autosave(ui_data.state,thumbnail(),camera_view())
 if capture_mode: print("AUTOSAVE_MS %.2f (with thumbnail) BYTES %d" % [(Time.get_ticks_usec()-t0)/1000.0,a.get("bytes",0)])
 if not a.ok: ui.toast("Autosave failed: %s" % a.error)
 collecting_moves = true
 collected_moves = {}
 ui_data.end_turn()
 collecting_moves = false
 var r = ui_data.resources()
 ui.toast("Year %d begins. Treasury %s gold." % [r.year,UiKit.format_int(r.treasury)])
 if r.destroyed:
  show_game_over()
  return
 play_moves(collected_moves)

func set_overlay(overlay: String,on: bool):
 overlays[overlay] = on
 if overlay == "armies":
  for id in army_figures: army_figures[id].visible = on
 if overlay == "borders": terrain_material.set_shader_parameter("territory_on",1.0 if on else 0.0)
 if overlay == "settlements":
  minimap.show_settlements = on
  pins_root.visible = on and ui.visible
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
 desired_distance = OVERVIEW_DISTANCE
 set_pitch(OVERVIEW_PITCH)

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
 if pause_menu != null or game_over != null: return
 if map_open():
  # The strategic map takes the mouse itself; here only Tab and Esc (back to the 3D map).
  if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_TAB,KEY_ESCAPE]:
   close_strategic_map()
   get_viewport().set_input_as_handled()
  return
 if spectating_now() and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE,KEY_ESCAPE]:
  skip_spectating()
  get_viewport().set_input_as_handled()
  return
 # Mouse (TW:WH3, docs/tw-ui-parity.md): left click selects (empty ground deselects); hold right
 # click previews a move and releasing gives the order (left click or Esc during the hold cancels
 # it); middle drag orbits; the wheel zooms. Selecting never moves the camera.
 if event is InputEventMouseButton:
  if event.pressed:
   if event.button_index == MOUSE_BUTTON_WHEEL_UP: desired_distance = clampf(desired_distance*0.88,10,210)
   if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
    if desired_distance>=209.9: open_strategic_map() # past the farthest zoom (TW:WH3)
    desired_distance = clampf(desired_distance*1.13,10,210)
   if event.button_index == MOUSE_BUTTON_LEFT:
    press_pos = event.position
    map_press = true
    if rmb_held: cancel_move_preview()
   if event.button_index == MOUSE_BUTTON_RIGHT and army_selected():
    rmb_held = true
    preview_key = Vector2i(1<<20,0)
  elif event.button_index == MOUSE_BUTTON_LEFT and map_press and event.position.distance_to(press_pos)<6:
   map_press = false
   var hit = pick(event.position)
   if hit.begins_with("army:"): select_army(hit.get_slice(":",1))
   elif hit != "": select_settlement(hit)
   else: deselect()
  elif event.button_index == MOUSE_BUTTON_LEFT: map_press = false
  elif event.button_index == MOUSE_BUTTON_RIGHT:
   var held = rmb_held
   rmb_held = false
   ui.preview_movement(0.0,false)
   if movement_overlay: movement_overlay.clear("preview")
   if held and army_selected(): order_army(move_target(event.position))
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
  yaw -= event.relative.x*0.005
  pitch_offset = clampf(pitch_offset+event.relative.y*0.004,-0.6,0.6)
 if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed:
  if event.keycode == KEY_S: quicksave()
  if event.keycode == KEY_L: quickload()
  if event.keycode == KEY_P: ui.disband_selected()
  if event.keycode == KEY_T: toggle_labels()
  return
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode == KEY_HOME: pan_to_capital()
  if event.keycode == KEY_END:
   yaw = OVERVIEW_YAW
   pitch_offset = 0.0
  if event.keycode == KEY_F12: request_capture()
  if event.keycode == KEY_TAB: toggle_strategic_map()
  if event.keycode == KEY_K: toggle_interface(event.alt_pressed)
  if event.keycode == KEY_ESCAPE:
   # Esc cancels a held move preview, then closes panels (and shows a hidden interface); with
   # nothing open it pauses.
   if rmb_held: cancel_move_preview()
   elif not ui.visible: toggle_interface(false)
   elif ui.close_top_panel(): refresh_army_overlays()
   else: open_pause_menu()
  if event.keycode == KEY_COMMA: cycle_selection(-1)
  if event.keycode == KEY_PERIOD: cycle_selection(1)
  if event.keycode == KEY_G:
   ui.show_settlement(GOLDSPIRE_ID)
   focus_goldspire()
  if event.keycode == KEY_F: toggle_follow()
  if event.keycode == KEY_R: toggle_army_speed()
  if event.keycode == KEY_BACKSPACE and army_selected(): ui_data.cancel_army_order(selected_army_id())
  if event.keycode == KEY_3 and ui.selected_settlement != "": ui.open_first_empty_slot(ui.selected_settlement)
  if event.keycode == KEY_1: panel_tab("buildings")
  if event.keycode == KEY_2: panel_tab("garrison")
  if event.keycode == KEY_4 and army_selected(): ui.open_recruitment(selected_army_id())
  if event.keycode == KEY_5: ui.toast("Recruit heroes: coming later.")
  if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
   if event.shift_pressed: end_turn(true)
   else: end_turn_pressed()
  if event.keycode == KEY_H: jump_to_notification()
  # Debug keys (Settings: on by default for now; listed in README).
  if Settings.debug_keys():
   if event.keycode == KEY_F8: toggle_pause()
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
 if Input.is_key_pressed(KEY_CTRL) or pause_menu != null or map_open(): dir = Vector3.ZERO # Ctrl+S is quicksave; paused means paused
 target += dir.rotated(Vector3.UP,yaw)*delta*distance*(0.75 if Input.is_key_pressed(KEY_SHIFT) else 0.30)
 target.x = clampf(target.x,-105,105)
 target.z = clampf(target.z,-90,65)
 # Q / E rotate (TW:WH3); Shift pans faster.
 if pause_menu == null and not Input.is_key_pressed(KEY_CTRL) and not map_open():
  if Input.is_physical_key_pressed(KEY_Q): yaw += delta*1.6
  if Input.is_physical_key_pressed(KEY_E): yaw -= delta*1.6
 distance = lerpf(distance,desired_distance,minf(1,delta*9))
 # The tilt follows the zoom (steeper high up, flatter close in, as in TW:WH3); middle drag adds an
 # offset.
 pitch = clampf(tilt_for(distance)+pitch_offset,0.15,1.25)
 var offset = Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
 camera.position = target+offset
 camera.position.y = maxf(camera.position.y,height_at(camera.position.x,camera.position.z)+2.0)
 camera.look_at(target)

func _process(delta):
 _update_spectate(delta)
 # Nothing 3D shows behind the opaque strategic map: skip rendering it once the fade is done.
 if map_open() and strategic.fade>=1.0 and not get_viewport().disable_3d: get_viewport().disable_3d = true
 # Answer AI attacks once nothing else is on screen (captures only with --defense).
 if not spectating_now() and (not capture_mode or "--defense" in OS.get_cmdline_user_args()) and ui_data.has_pending_battle(): open_pending_battle()
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
  # Hold Space (TW:WH3 overlays): settlement banners at any zoom.
  b.visible = overlays.settlements and not camera.is_position_behind(p.world) and (distance>18 or (Input.is_physical_key_pressed(KEY_SPACE) and not spectating_now()))
  if b.visible: b.position = camera.unproject_position(p.world)-b.anchor_offset()
  b.set_selected(ui.selected_settlement == p.id)
 var mouse = get_viewport().get_mouse_position()
 var hit = "" if get_viewport().gui_get_hovered_control() != null else pick(mouse)
 # Path preview only while right click is held (TW:WH3); --preview captures force it.
 var previewing = army_selected() and not walks.has(selected_army_id()) and (forced_preview != null or (rmb_held and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)))
 if rmb_held and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT): rmb_held = false
 if "--ledger" in OS.get_cmdline_user_args(): ui.show_hover(ui._ledger_text(),Vector2(560,70))
 elif "--treasury-tip" in OS.get_cmdline_user_args(): ui.show_hover(ui.resource_groups.treasury.tooltip_text,Vector2(560,70))
 elif previewing:
  var at = forced_preview if forced_preview != null else move_target(mouse)
  var text = preview_move(at)
  # No numbers: a tooltip only says why a move is impossible, or what it attacks.
  if text != "": ui.show_hover(text,camera.unproject_position(army_ground(at,1.0)) if forced_preview != null else mouse)
  else: ui.hide_hover()
 elif hit != "" and ui.visible: ui.show_hover(hover_text(hit),mouse)
 else: ui.hide_hover()
 if movement_overlay and not previewing and movement_overlay.has_content("preview"):
  movement_overlay.clear("preview")
  ui.preview_movement(0.0,false)
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
 # --save-as=Name (captures): save the campaign with this frame as its thumbnail.
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--save-as="): save_named(arg.get_slice("=",1))
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
 if "--army" in args and not Array(args).any(func(x): return x.begins_with("--name=")): name_v = "army"
 if not capture_mode: name_v="view_"+Time.get_datetime_string_from_system().replace(":","-")
 var path = folder+"/"+name_v+".png"
 var result = get_viewport().get_texture().get_image().save_png(path)
 print("CAPTURE ",path," result=",result," window=",DisplayServer.window_get_size()," ui=",get_viewport().get_visible_rect().size)
 if ui: ui.toast("Saved view to ProjectFreedom / captures.")
 if capture_mode:
  SaveSystem.wait_for_images()
  get_tree().quit(0 if result==OK else 1)

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
 # Saves: End Turn autosaved; a manual save loads back to the identical state.
 assert(FileAccess.file_exists(SaveSystem.path_of("autosave_1")))
 var sv = SaveSystem.save(ui_data.state,"self_test","Self-test","manual",thumbnail(),false,camera_view())
 var ld = SaveSystem.load_save("self_test")
 assert(sv.ok and ld.ok and ld.state.state_hash() == ui_data.state.state_hash())
 assert(ld.view == camera_view()) # the camera comes back with the save
 print("SAVE_MS %.2f LOAD_MS %.2f SAVE_BYTES %d" % [sv.ms,ld.ms,sv.bytes])
 # Esc order: panels close first; with nothing open the pause menu opens. Exiting with unsaved
 # progress asks first.
 ui.show_settlement(CITY_ID)
 assert(ui.close_top_panel() and not ui.close_top_panel())
 open_pause_menu()
 assert(pause_menu != null and pause_menu.buttons.visible)
 pause_menu._show_save()
 assert(pause_menu.save_box.visible and pause_menu.save_name.text.contains("year"))
 pause_menu._show_buttons()
 unsaved = true
 var exited = [false]
 pause_menu._guard("Exit?",func(): exited[0] = true)
 assert(pause_menu.confirm_box.visible and not exited[0])
 pause_menu._show_buttons()
 unsaved = false
 pause_menu._guard("Exit?",func(): exited[0] = true)
 assert(exited[0])
 close_pause_menu()
 # Army movement: preview, blocked order, multi-turn order continuing on End Turn, garrison, cancel.
 # The army's state is restored afterwards so the capture is unchanged.
 var saved_army = ui_data.state.army_state[COMMANDER_ARMY].duplicate(true)
 # TW parity: selecting never moves or zooms the camera.
 var cam_before = [target,desired_distance,yaw]
 select_army()
 assert([target,desired_distance,yaw] == cam_before)
 assert(movement_overlay.has_content("reach"))
 # The preview: a coloured path, no numbers or text on the map, the spend on the movement bar.
 preview_move(Vector2(-118,-30))
 assert(movement_overlay.has_content("preview") and preview_text == "")
 for n in movement_overlay.get_node("preview").get_children(): assert(not n is Label3D)
 assert(ui.movement_bar.spend>0.0 and ui.movement_bar.overflow)
 cancel_move_preview()
 assert(not movement_overlay.has_content("preview") and ui.movement_bar.spend == 0.0)
 # A held right click previews; releasing it gives the order (simulated input).
 var mid_screen = camera.unproject_position(ground(Vector2(-20,-10)))
 var press = InputEventMouseButton.new()
 press.button_index = MOUSE_BUTTON_RIGHT
 press.pressed = true
 press.position = mid_screen
 _unhandled_input(press)
 assert(rmb_held)
 var esc = InputEventKey.new()
 esc.keycode = KEY_ESCAPE
 esc.pressed = true
 _unhandled_input(esc)
 assert(not rmb_held and selected_army_id() == COMMANDER_ARMY) # Esc cancels the hold only
 # Cycling armies pans at the current zoom.
 desired_distance = 90.0
 cycle_selection(1)
 assert(desired_distance == 90.0 and selected_army_id() != "")
 # End Turn warnings: the button jumps to the first warning before it ends the turn.
 refresh_warnings()
 var warns = current_warnings()
 if not warns.is_empty():
  var year_before = ui_data.state.year
  end_turn_pressed()
  assert(ui_data.state.year == year_before)
 warn_skipped.clear()
 warn_index.clear()
 select_army()
 var points_before = ui_data.army_movement(COMMANDER_ARMY).points
 order_army(WorldMap.settlement_position(CITY_ID))
 assert(ui.battle_visible() and ui.battle_box.find_child("DeclareWar",true,false) != null) # not at war yet: confirmation first
 ui.close_battle()
 assert(ui_data.army_movement(COMMANDER_ARMY).points == points_before)
 # Deployment screen: open it (war set temporarily), place, order, fail a capacity rule, toggle
 # the view, then Back: nothing spent, the pre-battle panel returns.
 var city_t = ui_data.battle_target(COMMANDER_ARMY,WorldMap.settlement_position(CITY_ID))
 var war_key = Battles.war_key(ui_data.player_faction_id(),city_t.faction)
 ui_data.state.wars.append(war_key)
 city_t.needs_war = false
 ui.open_battle_flow(COMMANDER_ARMY,WorldMap.settlement_position(CITY_ID),city_t)
 ui.open_deployment()
 assert(ui.deployment_visible() and not ui.battle_visible())
 var ds = ui.deployment_screen
 ds.apply_template("line")
 assert(ds.dep.units.size()>0 and Deployment.validate(ds.dep).is_empty())
 ds.select(0)
 ds._order("reserve")
 assert(ds.dep.units[0].line == "reserve" and ds.dep.units[0].order == "reserve")
 ds._order("flank:left")
 assert(ds.dep.units[0].order == "flank" and int(ds.dep.units[0].lane) == 0)
 ds._set_view(false)
 assert(ds.board.visible and not ds.viewport_box.visible)
 ds.update_odds()
 assert(ds.odds>=0.0 and ds.odds<=1.0)
 # Full report from a pure simulation of this deployment (no campaign change): replay, scrubber
 # markers, tables, collapsed timeline; clicking an event jumps the replay and highlights.
 var rpb = ds.pb.duplicate()
 rpb.deployment = ds.dep
 var sim = BattleSim.simulate(Battles.setup(ui_data.state,rpb,rpb.seed))
 ui.open_battle_report(rpb,{"result":sim,"aftermath":{"captured":"","generals":[],"promoted":[]}})
 assert(ui.report_visible() and ui.report_replay.frames.size() == int(sim.ticks)+1)
 assert(not ui.report_timeline.visible and ui.report_box.find_child("EnemyUnits",true,false) != null)
 if ui.report_timeline.get_child_count()>0:
  ui.report_timeline.get_child(0).pressed.emit()
  assert(ui.report_replay.tick == int(sim.events[0].tick) and not ui.report_replay.highlight.is_empty())
 ui.close_report()
 ds.closed.emit()
 assert(not ui.deployment_visible() and ui.battle_visible())
 assert(ui_data.army_movement(COMMANDER_ARMY).points == points_before)
 ui.close_battle()
 ui_data.state.wars.erase(war_key)
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
 # Recruitment at Crownwatch: open the panel, queue a levy, cancel it with a full refund.
 select_army()
 ui.open_recruitment(COMMANDER_ARMY)
 assert(ui.recruitment_visible())
 var gold0 = ui_data.resources().treasury
 var pop0 = ui_data.settlement("crownwatch").population
 ui.recruit_box.find_child("Recruit_peasant_levy",true,false).pressed.emit()
 assert(ui_data.army(COMMANDER_ARMY).queue.size()==1 and ui_data.settlement("crownwatch").population<pop0)
 # TW:WH3 recruitment: the panel stays open across clicks; past the capacity (3) units overflow
 # (orange); global recruitment (blue) costs more; every cancel refunds in full.
 ui_data.state.treasury[ui_data.player_faction_id()] += 5000
 for i in 3:
  ui.recruit_box.find_child("Recruit_peasant_levy",true,false).pressed.emit()
  assert(ui.recruitment_visible())
 ui.toggle_recruitment(COMMANDER_ARMY,"global")
 assert(ui.recruitment_visible() and ui.recruit_mode == "global")
 ui.recruit_box.find_child("Recruit_peasant_levy",true,false).pressed.emit()
 var kinds = ui_data.army(COMMANDER_ARMY).queue.map(func(q): return q.kind)
 assert(kinds == ["local","local","local","overflow","overflow"],str(kinds))
 assert(ui.recruitment_visible())
 while not ui_data.army(COMMANDER_ARMY).queue.is_empty(): ui_data.cancel_recruit(COMMANDER_ARMY,0)
 ui_data.state.treasury[ui_data.player_faction_id()] -= 5000
 assert(ui_data.resources().treasury==gold0 and ui_data.settlement("crownwatch").population==pop0)
 ui.close_recruitment()
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
 print("SELF_TEST_PASS | upgrades cycle; traffic routes valid; manifest visuals present; city dry; sea submerged; goldspire stages cycle; ui selection, army panel and end turn; construction upgrades goldspire's stage; army movement preview (hold right click, no numbers), selection without camera moves, cycling at the current zoom, End Turn warnings, orders, blocking and garrison; deployment screen place, orders, view and back; battle report replay, timeline and jump; autosave and save/load round trip; esc order and pause menu; recruitment queue and refund, panel open across clicks, capacity overflow, global recruitment")

# --- Movement grid bake ------------------------------------------------------------
# Writes the test map's movement_grid.json (data/maps/testmap/), the terrain grid army movement reads (core/movement.gd), by
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
 var f = FileAccess.open(MapRegistry.path("movement_grid.json"),FileAccess.WRITE)
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

# --- Saves ---------------------------------------------------------------------------------
# A picture of the map for the load screen and menu backdrop: one extra frame drawn with the
# interface hidden (none when headless or before the first frames).
func thumbnail() -> Image:
 if DisplayServer.get_name() == "headless" or Engine.get_frames_drawn()<3: return null
 var shown = [ui.visible,pins_root.visible]
 ui.visible = false
 pins_root.visible = false
 RenderingServer.force_draw(false)
 var img = get_viewport().get_texture().get_image()
 ui.visible = shown[0]
 pins_root.visible = shown[1]
 return img if img != null and not img.is_empty() else null

func quicksave():
 var r = SaveSystem.quicksave(ui_data.state,thumbnail(),camera_view())
 if r.ok: unsaved = false
 ui.toast("Quicksaved (year %d)." % ui_data.state.year if r.ok else "Quicksave failed: %s" % r.error)
 return r

func save_named(name: String) -> Dictionary:
 var t0 = Time.get_ticks_usec()
 var r = SaveSystem.save(ui_data.state,SaveSystem.file_for(name),name,"manual",thumbnail(),false,camera_view())
 if capture_mode: print("SAVE_NAMED_MS %.2f (with thumbnail) BYTES %d" % [(Time.get_ticks_usec()-t0)/1000.0,r.get("bytes",0)])
 if r.ok: unsaved = false
 ui.toast("Saved \"%s\"." % name if r.ok else "Save failed: %s" % r.error)
 return r

# Load a save into a freshly built campaign scene; a failed load leaves this campaign untouched.
func load_file(file: String) -> Dictionary:
 var r = SaveSystem.load_save(file)
 if not r.ok:
  ui.toast(r.error)
  return r
 Session.start(get_tree(),r.state,r.meta.get("name",file),r.get("view",{}))
 return r

func quickload():
 if not FileAccess.file_exists(SaveSystem.path_of(SaveSystem.QUICKSAVE)):
  ui.toast("No quicksave yet (Ctrl+S makes one).")
  return
 load_file(SaveSystem.QUICKSAVE)

func open_pause_menu():
 if pause_menu != null: return
 ui.hide_hover()
 pause_menu = PauseMenu.new()
 pause_menu.name = "PauseMenu"
 ui.add_child(pause_menu)
 pause_menu.setup(self)
 pause_menu.closed.connect(close_pause_menu)

func close_pause_menu():
 if pause_menu: pause_menu.queue_free()
 pause_menu = null

func _notification(what):
 # Let thumbnails still being written finish before the window closes.
 if what == NOTIFICATION_WM_CLOSE_REQUEST: SaveSystem.wait_for_images()

# --- AI turn presentation -------------------------------------------------------------------
# After End Turn every army walks its path. AI armies whose path comes near the player's
# settlements or armies (data/ai.json presentation.watch_meters) are shown one at a time with the
# camera following (Settings: follow AI moves); Space or Esc skips. Then any AI attack on the
# player opens the pre-battle panel with the player defending.

func play_moves(moves: Dictionary):
 var ids = moves.keys()
 ids.sort()
 var watch = float(Ai.data().presentation.watch_meters)
 var mine = []
 for sid in ui_data.state.settlements_of(ui_data.player_faction_id()): mine.append(WorldMap.settlement_position(sid))
 for id in ui_data.army_ids():
  if ui_data.army(id).player_owned: mine.append(ui_data.army_movement(id).position)
 for id in ids:
  var follow = (not capture_mode or "--follow-ai" in OS.get_cmdline_user_args()) and ui_data.state.army_state.has(id) and not ui_data.army(id).player_owned and Settings.should_follow(Settings.follow_ai_mode(),_near(moves[id],mine,watch))
  if follow: spectate_queue.append([id,moves[id]])
  else: _on_army_moved(id,moves[id])
 _next_spectate()

func _near(path: Array,points: Array,radius: float) -> bool:
 for p in path:
  for q in points:
   if p.distance_to(q)<=radius: return true
 return false

func spectating_now() -> bool:
 return not spectating.is_empty() or not spectate_queue.is_empty()

func _next_spectate():
 ui.show_ai_turn_bar(not spectate_queue.is_empty())
 if spectate_queue.is_empty():
  spectating = {}
  ai_paused = false
  open_pending_battle()
  return
 var next = spectate_queue.pop_front()
 _on_army_moved(next[0],next[1])
 spectating = {"id":next[0],"hold":float(Ai.data().presentation.hold_seconds)/Settings.ai_speed()}
 ui.toast("%s marches." % ui_data.army(next[0]).display_name if ui_data.state.army_state.has(next[0]) else "An army marches.")

# Skip the rest of the AI moves: everything jumps to where it ended.
func skip_spectating():
 ai_paused = false
 for q in spectate_queue: _on_army_moved(q[0],q[1])
 spectate_queue.clear()
 ui.show_ai_turn_bar(false)
 for id in walks: walks[id].dist = walks[id].total
 update_walk(0.0)
 spectating = {}
 open_pending_battle()

func _update_spectate(delta: float):
 if spectating.is_empty(): return
 if ai_paused: return
 var id = spectating.id
 if army_figures.has(id) and is_instance_valid(army_figures[id]):
  var c = army_figures[id].position
  target = target.lerp(Vector3(c.x,c.y+2.2,c.z),minf(1,delta*3))
  desired_distance = minf(desired_distance,float(Ai.data().presentation.camera_distance))
 if walks.has(id): return
 spectating.hold -= delta
 if spectating.hold<=0.0: _next_spectate()

func open_pending_battle():
 if ui.battle_visible() or ui.report_visible() or ui.deployment_visible(): return
 var pb = ui_data.pending_battle()
 if pb.is_empty(): return
 var p = Vector2(pb.position[0],pb.position[1])
 focus_at(ground(p,2.0),70.0)
 ui.open_defense(pb)

# The camera as saved with a campaign, and restored when it loads.
func camera_view() -> Dictionary:
 return {"target":[target.x,target.y,target.z],"yaw":yaw,"pitch":pitch,"distance":desired_distance}

func apply_camera_view(v: Dictionary):
 if v.is_empty() or not v.has("target"): return
 target = Vector3(float(v.target[0]),float(v.target[1]),float(v.target[2]))
 yaw = float(v.yaw)
 desired_distance = float(v.distance)
 distance = desired_distance
 set_pitch(float(v.pitch))
 camera_update(1.0)

# A landless faction's armies carry its countdown above their banners (turns left to retake a
# settlement, core/realm.gd).
func update_grace_labels():
 for id in army_figures:
  var fig = army_figures[id]
  if not is_instance_valid(fig) or not ui_data.state.army_state.has(id): continue
  var left = ui_data.grace_left(ui_data.state.army_state[id].faction)
  var label: Label3D = fig.get_node_or_null("GraceLabel")
  if left<0:
   if label: label.visible = false
   continue
  if label == null:
   label = Label3D.new()
   label.name = "GraceLabel"
   label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
   label.no_depth_test = true
   label.fixed_size = true
   label.pixel_size = 0.0007
   label.font = UiKit.FONT_BOLD
   label.font_size = 26
   label.outline_size = 10
   label.modulate = Color("ffd2c4")
   label.outline_modulate = Color("5a1010")
   label.position = Vector3(0,4.6,0)
   fig.add_child(label)
  label.visible = true
  label.text = "LANDLESS · %d" % left

# The player's house is destroyed (core/realm.gd): the defeat screen; the map stays behind it.
func show_game_over():
 if game_over != null: return
 ui.hide_hover()
 close_pause_menu()
 game_over = GameOver.new()
 game_over.name = "GameOver"
 ui.add_child(game_over)
 game_over.setup(self,ui_data.player_faction(),ui_data.state.year)

# Camera tilt for a zoom distance: about 35 degrees close in, steeper when high (TW:WH3's
# zoom-linked pitch; docs/tw-ui-parity.md C8).
func tilt_for(d: float) -> float:
 return lerpf(0.61,1.0,clampf((d-10.0)/200.0,0.0,1.0))

# Set the camera tilt for the current zoom target (views, captures, loaded saves).
func set_pitch(p: float):
 pitch_offset = p-tilt_for(desired_distance)
 pitch = p

# --- End Turn warnings (TW:WH3) --------------------------------------------------------------
# While warnings are pending the End Turn button (and Enter) jumps to the current one and moves on
# to the next; once every kind has been visited or skipped, it ends the turn. Shift+Enter ends the
# turn anyway; H jumps without moving on. Kinds and items: UiData.end_turn_warnings.
var warn_skipped: Array = []  # kinds visited or skipped this turn
var warn_index := {}          # kind -> item shown next

func current_warnings() -> Array:
 return ui_data.end_turn_warnings(Settings.end_turn_warnings()).filter(func(w): return not w.kind in warn_skipped)

func refresh_warnings():
 if ui == null: return
 var w = current_warnings()
 if w.is_empty():
  ui.show_end_turn_warning({})
  return
 var c = w[0]
 var i = clampi(int(warn_index.get(c.kind,0)),0,c.items.size()-1)
 ui.show_end_turn_warning({"label":c.label,"name":c.items[i].name,"index":i,"count":c.items.size()})

func end_turn_pressed():
 if spectating_now(): return
 var w = current_warnings()
 if w.is_empty():
  end_turn()
  return
 var c = w[0]
 var i = clampi(int(warn_index.get(c.kind,0)),0,c.items.size()-1)
 _jump_to(c.items[i])
 if i+1>=c.items.size():
  warn_skipped.append(c.kind)
  warn_index.erase(c.kind)
 else: warn_index[c.kind] = i+1
 refresh_warnings()

func jump_to_notification():
 var w = current_warnings()
 if w.is_empty(): return
 var c = w[0]
 _jump_to(c.items[clampi(int(warn_index.get(c.kind,0)),0,c.items.size()-1)])

func step_warning(dir: int):
 var w = current_warnings()
 if w.is_empty(): return
 var c = w[0]
 var i = posmod(int(warn_index.get(c.kind,0))+dir,c.items.size())
 warn_index[c.kind] = i
 _jump_to(c.items[i])
 refresh_warnings()

func skip_warning():
 var w = current_warnings()
 if w.is_empty(): return
 warn_skipped.append(w[0].kind)
 refresh_warnings()

# Go to a warning's subject: select it and pan there at the current zoom.
func _jump_to(item: Dictionary):
 match item.type:
  "settlement": select_settlement(item.id,true)
  "army":
   select_army(item.id)
   if army_figures.has(item.id): pan_to(army_figures[item.id].position+Vector3(0,2.2,0))
  "faction": ui.toast("Low funds: hover the treasury for the ledger.")
