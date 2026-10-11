extends Node
# The seamless rise from Edric Varn's shoulder to the empire view, and the dive back
# (docs/pivot/god-game.md, slice 1): flying upward pulls the camera back and up (god/god_player.gd);
# past empire_at metres above the ground the camera hands over to the campaign zoom
# (core/camera_rig.gd's tilt curve, at campaign_scale), climbing on through a cloud deck where the
# character-scale world gives way to the campaign map's own (the seam hides in the cloud), up to the
# campaign's highest zoom, and on into the strategic map (ui/strategic_map.gd). Picking a place on
# the strategic map, or clicking the 3D map, dives the god there: Meteor Flight down through the
# clouds onto a ground slam. Only Frosthold's area is built at character scale; anywhere else the dive
# is refused ("not built yet").

signal message(text: String)
signal mode_changed(mode: String)

const CameraRig = preload("res://core/camera_rig.gd")
const UiData = preload("res://core/ui_data.gd")
const StrategicMap = preload("res://ui/strategic_map.gd")
const MapRegistry = preload("res://core/map_registry.gd")

var host # god/god_test.gd
var player
var camera: Camera3D
var cfg: Dictionary
var mode := "ground" # ground, empire, strategic, dive
var d := 0.0 # campaign zoom distance (campaign metres)
var target := Vector2.ZERO # campaign position the camera looks at
var yaw := 0.0
var pitch_from := 0.0
var blend := 1.0
var maxd := 7000.0
var hold_out := 0.0
var strategic: Control
var layer: CanvasLayer
var clouds: MeshInstance3D
var clouds2: MeshInstance3D
var world_on := true
var dive_from := Vector3.ZERO
var dive_to := Vector3.ZERO
var dive_t := 0.0
var dive_alt := 0.0
var trail: Array = []
var climb_wheel := 0.0
var scripted := false
var script_climb := false
var script_descend := false
var climb_scale := 1.0 # the showcase climbs slower, so the campaign zoom is seen

func setup(h,p,c: Dictionary):
 host = h
 player = p
 camera = p.camera
 cfg = c
 var size = Vector2(MapRegistry.meta().size[0],MapRegistry.meta().size[1])
 maxd = CameraRig.max_distance(size)
 _cloud_deck()
 layer = CanvasLayer.new()
 layer.layer = 5
 add_child(layer)
 strategic = StrategicMap.new()
 strategic.name = "StrategicMap"
 layer.add_child(strategic)
 strategic.setup(UiData.new(host.state),Rect2(Vector2(MapRegistry.meta().origin[0],MapRegistry.meta().origin[1]),size))
 strategic.location_chosen.connect(_on_chosen)
 strategic.closed.connect(func(): _close_strategic(null))

# A thick, patchy cloud deck at cloud_height: the band where the two worlds swap.
func _cloud_deck():
 clouds = MeshInstance3D.new()
 var pm = PlaneMesh.new()
 pm.size = Vector2(16000,16000)
 clouds.mesh = pm
 var m = ShaderMaterial.new()
 m.shader = load("res://god/clouds.gdshader")
 m.set_shader_parameter("noise_tex",load("res://god/materials.gd").cloud_noise())
 clouds.material_override = m
 clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 host.add_child(clouds)
 clouds.position = Vector3(0,float(cfg.cloud_height),0)
 # A second, thinner layer above gives the deck depth as the camera passes through.
 var c2 = clouds.duplicate()
 c2.position.y = float(cfg.cloud_height)+90.0
 c2.material_override = m.duplicate()
 c2.material_override.set_shader_parameter("density",0.7)
 c2.material_override.set_shader_parameter("offset",Vector2(37.0,11.0))
 host.add_child(c2)
 clouds2 = c2

func world_to_campaign(p: Vector3) -> Vector2:
 return Vector2(host.site.x+p.x/host.cscale,host.site.y+p.z/host.cscale)

func campaign_to_world(c: Vector2) -> Vector3:
 var x = (c.x-host.site.x)*host.cscale
 var z = (c.y-host.site.y)*host.cscale
 var y = host.terrain.height_at(x,z) if host.terrain.inside(x,z) else host.campaign_height(x,z)
 return Vector3(x,y,z)

func in_area(c: Vector2) -> bool:
 var w = campaign_to_world(c)
 return host.terrain.inside(w.x,w.z,120.0)

func _process(delta):
 var real = delta/maxf(Engine.time_scale,0.05)
 match mode:
  "ground": _ground_mode()
  "empire": _empire_mode(real)
  "dive": _dive_mode(delta)
 _world_visibility()

func _alt_above_ground(p: Vector3) -> float:
 return p.y-(host.terrain.height_at(p.x,p.z) if host.terrain.inside(p.x,p.z) else host.campaign_height(p.x,p.z))

# Flying high hands the camera over to the campaign zoom.
func _ground_mode():
 if player.state != player.FLY: return
 var alt = _alt_above_ground(player.global_position)
 var climbing = player.ctl.up or player.velocity.y>10.0 or script_climb
 if alt>float(cfg.empire_at) and climbing:
  mode = "empire"
  player.external_camera = true
  var cp = camera.global_position
  target = world_to_campaign(player.global_position)
  d = maxf(CameraRig.min_distance(),(cp.distance_to(player.global_position)+alt)/host.cscale)
  yaw = player.yaw
  pitch_from = -camera.global_rotation.x
  blend = 0.0
  player.velocity = Vector3.ZERO
  mode_changed.emit(mode)

func _empire_mode(real: float):
 var climb = float(cfg.climb)*climb_scale
 var up = (player.ctl.up and not scripted) or script_climb or climb_wheel>0.0
 var down = (player.ctl.down and not scripted) or script_descend or climb_wheel<0.0
 if up: d = minf(maxd,d*exp(climb*real*(1.0+absf(climb_wheel))))
 if down: d = maxf(CameraRig.min_distance()*4.0,d*exp(-climb*real*(1.0+absf(climb_wheel))))
 climb_wheel = move_toward(climb_wheel,0.0,real*6.0)
 # Pan with WASD across the campaign map.
 var m = player.ctl.move
 if m.length()>0.0:
  target += Vector2(m.x,m.y).rotated(-yaw)*d*0.45*real
 blend = minf(1.0,blend+real*0.6)
 if up and d>=maxd*0.995:
  hold_out += real
  if hold_out>0.35: _open_strategic()
 else: hold_out = 0.0
 # Back down below the hand-over height: the god takes the camera again.
 if down and d<float(cfg.empire_at)/host.cscale*0.9:
  _return_to_god()
  return
 _place_camera()

func _place_camera():
 var p = lerpf(pitch_from,CameraRig.pitch_at(d,maxd),smoothstep(0.0,1.0,blend))
 var focus = campaign_to_world(target)
 var dist = d*host.cscale
 var dir = Vector3(sin(yaw)*cos(p),sin(p),cos(yaw)*cos(p))
 camera.global_position = focus+dir*dist
 camera.look_at(focus,Vector3.UP)
 camera.near = clampf(dist*0.002,0.08,8.0)
 camera.fov = lerpf(camera.fov,55.0,0.05)
 _stream()
 var hz = CameraRig.high_zoom(d,maxd)
 host.map_view.set_zoom_look(d,hz)
 host.hide_campaign_site()


func _return_to_god():
 mode = "ground"
 player.external_camera = false

 var w = campaign_to_world(target)
 player.global_position = Vector3(w.x,maxf(player.global_position.y,w.y+float(cfg.empire_at)*0.8),w.z)
 player.pivot.global_position = player.global_position
 camera.transform = Transform3D.IDENTITY
 camera.near = 0.08
 mode_changed.emit(mode)

func wheel(step: float):
 if mode == "empire": climb_wheel = clampf(climb_wheel+step,-3.0,3.0)

# --- Strategic map -------------------------------------------------------------------------------------

func _open_strategic():
 if strategic.is_open(): return
 mode = "strategic"
 hold_out = 0.0
 strategic.open_map()
 # The 3D view keeps rendering behind the opaque map (about 3 ms from this high up), so the dive starts
 # straight from it.
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
 player.mouse_captured = false
 mode_changed.emit(mode)

func _close_strategic(world):
 strategic.close_map()
 mode = "empire"
 if world != null: target = world
 d = maxd*0.95
 blend = 1.0
 mode_changed.emit(mode)

func _on_chosen(world: Vector2,from_scroll: bool):
 if from_scroll:
  _close_strategic(world)
  return
 if not in_area(world):
  message.emit("Not built yet: only Frosthold can be entered at character scale in this test.")
  return
 _close_strategic(world)
 start_dive(world)

func click_dive(screen: Vector2):
 if mode != "empire": return
 var from = camera.project_ray_origin(screen)
 var dir = camera.project_ray_normal(screen)
 # March the ray down to the ground.
 var t = 0.0
 var p = from
 for i in 400:
  t += maxf(2.0,_alt_above_ground(p)*0.5)
  p = from+dir*t
  if _alt_above_ground(p)<1.0: break
 var c = world_to_campaign(p)
 if not in_area(c):
  message.emit("Not built yet: only Frosthold can be entered at character scale in this test.")
  return
 start_dive(c)

# Meteor Flight: the god drops from the camera's height onto the target, the camera chasing him.
func start_dive(c: Vector2):
 target = c
 dive_to = campaign_to_world(c)
 var cp = camera.global_position
 dive_from = Vector3(dive_to.x,maxf(cp.y,dive_to.y+1500.0),dive_to.z)+Vector3(cp.x-dive_to.x,0,cp.z-dive_to.z).normalized()*minf(1200.0,Vector2(cp.x-dive_to.x,cp.z-dive_to.z).length()*0.3)
 dive_alt = dive_from.y-dive_to.y
 dive_t = 0.0
 mode = "dive"

 player.external_camera = true
 player.global_position = dive_from
 player.velocity = Vector3.ZERO
 player.state = player.DIVE
 player.dive_target = dive_to
 player.set_physics_process(false)
 mode_changed.emit(mode)
 message.emit("")

func _dive_mode(delta):
 # Exponential fall: fast from high up, still a meteor at the end.
 dive_t += delta
 var p = player.global_position
 var to = dive_to-p
 var alt = to.length()
 var speed = maxf(140.0,alt*2.2)
 var step = minf(alt,speed*delta)
 var dir = to.normalized()
 player.global_position = p+dir*step
 player.velocity = dir*speed
 player._animate(delta)
 host.vfx_meteor(player.global_position,dir,speed)
 # The camera chases from behind and above, locked to the god (no lag at meteor speed).
 var back = -Vector3(dir.x,0,dir.z).normalized()
 if back.length()<0.1: back = Vector3(sin(player.yaw),0,cos(player.yaw))
 var gp = player.global_position
 camera.global_position = gp+back*clampf(alt*0.06,14.0,90.0)+Vector3(0,clampf(alt*0.1,7.0,160.0),0)
 camera.look_at(gp+dir*clampf(alt*0.1,6.0,60.0),Vector3.UP)
 camera.near = clampf(alt*0.0015,0.08,4.0)
 camera.fov = lerpf(camera.fov,88.0,0.04)
 _stream()
 if alt<3.0:
  # Impact: hand the body back to physics; it lands this frame and slams.
  player.global_position = dive_to+Vector3(0,0.3,0)
  player.set_physics_process(true)
  player.state = player.DIVE
  player.velocity = Vector3(0,-80,0)
  player.external_camera = false
  player.pivot.global_position = player.global_position+Vector3(0,2.5,0)
  player.yaw = atan2(-back.x,-back.z)+PI
  player.pitch = -0.32
  player.pivot.rotation = Vector3(player.pitch,player.yaw,0)
  player.arm.spring_length = 9.0
  camera.transform = Transform3D.IDENTITY # back on the spring arm, facing along it
  camera.near = 0.08
  mode = "ground"
  mode_changed.emit(mode)

# --- The swap between the two worlds -------------------------------------------------------------------

func _world_visibility():
 var cp = camera.global_position
 var alt = _alt_above_ground(cp)
 var on = alt<float(cfg.cloud_height)+600.0 or (mode == "ground")
 if on != world_on:
  world_on = on
  host.set_detail_world(on)
 # The cloud deck shows only around its band: absent from the ground, thinning once the camera is well
 # above it (the campaign zoom wants a clear view). It fades rather than hiding.
 var ch = float(cfg.cloud_height)
 var fade = smoothstep(ch*0.3,ch*0.75,alt)*(1.0-smoothstep(ch+400.0,ch+2600.0,alt))
 clouds.material_override.set_shader_parameter("fade",fade)
 clouds2.material_override.set_shader_parameter("fade",fade)

# The campaign map streams its settlements and near trees around a focus (map/map_view.gd); here only
# when the view has panned far from where it last streamed (the land around Frosthold is built at
# start), so the rise and the dive do not stall on a rebuild.
var _streamed := Vector2(INF,INF)
func _stream():
 if _streamed.x == INF: _streamed = host.site
 if target.distance_to(_streamed)<1500.0: return
 _streamed = target
 host.map_view.update(Vector3(target.x,0,target.y))
 host.hide_campaign_site()
