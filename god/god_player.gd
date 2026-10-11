extends CharacterBody3D
# Edric Varn's body and camera in the god-game look test, copying Where Winds Meet traversal
# (docs/pivot/god-game.md, borrowed mechanics): walk (hold Alt), run (default), sprint (Shift);
# jump and Threefold Skywalk (three jumps in the air, then a Skywalk Dash); wall-running when
# sprinting into a wall; gliding while jump is held in a fall; flight (double-tap jump in the air or
# F: Space climbs, Ctrl descends, Shift is flight sprint with a sonic boom at top speed); superhero
# landings that crack the ground; the dive (Meteor Flight) that ends in a ground slam; a light punch
# (left click) and the charged "serious" punch (hold left click). Third-person camera on a spring
# arm behind the shoulder; FOV widens with speed. The showcase drives the same controls through `ctl`.

signal landed(hard: bool,speed: float)
signal punched(serious: bool,origin: Vector3,dir: Vector3,charge: float)
signal boom(pos: Vector3,dir: Vector3)
signal slammed(pos: Vector3)
signal crashed(pos: Vector3,speed: float)

enum {GROUND,AIR,WALL,GLIDE,FLY,DIVE,LAND}
const STATE_NAMES = ["ground","air","wall","glide","fly","dive","land"]

var cfg: Dictionary
var cam_cfg: Dictionary
var state := GROUND
var model # god/god_model.gd
var town
var terrain
var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var yaw := 0.0
var pitch := -0.18
var cam_extra := 0.0 # added spring length (flight, the rise)
var cam_pitch_bias := 0.0
var shake := 0.0
var _shake_t := 0.0
var sky_left := 0
var dashed := false
var wall_t := 0.0
var wall_n := Vector3.ZERO
var wall_up := true
var land_t := 0.0
var last_jump_t := -10.0
var boomed := false
var charge := 0.0
var charging := false
var punch_t := -1.0
var punch_serious := false
var punch_charge := 0.0
var punch_pending := false
var air_peak := 0.0
var fly_speed := 0.0
var facing := 0.0
var external_camera := false # god/empire.gd takes the camera during the rise
var dive_target = null
var scripted := false
var mouse_captured := false
# Controls this frame (keyboard and mouse, or the showcase script when scripted).
var ctl = {"move":Vector2.ZERO,"jump":false,"jump_pressed":false,"sprint":false,"walk":false,"up":false,"down":false,
 "fly_pressed":false,"punch":false,"look":Vector2.ZERO}
var _prev_jump := false
var _prev_punch := false
var _prev_fly := false
var hit_stop := 0.0
var fly_since := -10.0
var clock := 0.0 # game time (Movie Maker runs slower than real time)

func setup(c: Dictionary,camc: Dictionary,mdl,t,tw):
 cfg = c
 cam_cfg = camc
 model = mdl
 terrain = t
 town = tw
 collision_layer = 8
 collision_mask = 1|2
 floor_snap_length = 0.6
 floor_max_angle = deg_to_rad(50.0)
 var shape = CapsuleShape3D.new()
 shape.radius = 0.55
 shape.height = 2.7
 var cs = CollisionShape3D.new()
 cs.shape = shape
 cs.position.y = 1.35
 add_child(cs)
 add_child(model)
 pivot = Node3D.new()
 pivot.top_level = true
 add_child(pivot)
 arm = SpringArm3D.new()
 arm.collision_mask = 1|2
 arm.margin = 0.3
 arm.spring_length = float(cam_cfg.distance)
 var probe = SphereShape3D.new()
 probe.radius = 0.35
 arm.shape = probe
 arm.add_excluded_object(get_rid())
 pivot.add_child(arm)
 camera = Camera3D.new()
 camera.fov = float(cam_cfg.fov)
 camera.near = 0.08
 camera.far = 60000.0
 arm.add_child(camera)
 camera.make_current()
 pivot.global_position = global_position+Vector3(0,float(cam_cfg.height),0)

func speed_now() -> float:
 return velocity.length()

func _unhandled_input(e):
 if scripted: return
 if e is InputEventMouseMotion and mouse_captured:
  ctl.look += e.relative
 if e is InputEventMouseButton and e.pressed and not mouse_captured and not external_camera:
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
  mouse_captured = true
 if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE and mouse_captured:
  Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
  mouse_captured = false

func _read_input():
 if scripted: return
 var m = Vector2.ZERO
 if Input.is_physical_key_pressed(KEY_W): m.y -= 1
 if Input.is_physical_key_pressed(KEY_S): m.y += 1
 if Input.is_physical_key_pressed(KEY_A): m.x -= 1
 if Input.is_physical_key_pressed(KEY_D): m.x += 1
 ctl.move = m.limit_length(1.0)
 ctl.jump = Input.is_physical_key_pressed(KEY_SPACE)
 ctl.sprint = Input.is_physical_key_pressed(KEY_SHIFT)
 ctl.walk = Input.is_physical_key_pressed(KEY_ALT)
 ctl.up = ctl.jump
 ctl.down = Input.is_physical_key_pressed(KEY_CTRL)
 var f = Input.is_physical_key_pressed(KEY_F)
 ctl.fly_pressed = f and not _prev_fly
 _prev_fly = f
 ctl.punch = mouse_captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _physics_process(delta):
 clock += delta
 _read_input()
 var jp = ctl.jump and not _prev_jump
 _prev_jump = ctl.jump
 if not external_camera:
  yaw -= ctl.look.x*float(cam_cfg.mouse)
  pitch = clampf(pitch-ctl.look.y*float(cam_cfg.mouse),-1.45,1.1)
 ctl.look = Vector2.ZERO
 var now = clock
 match state:
  GROUND: _ground(delta,jp,now)
  AIR, GLIDE: _air(delta,jp,now)
  WALL: _wall(delta,jp)
  FLY: _fly(delta,jp,now)
  DIVE: _dive(delta)
  LAND: _land(delta)
 _punch(delta)
 var was_floor = is_on_floor()
 var vy_before = velocity.y
 var pre_speed = velocity.length()
 move_and_slide()
 _after_move(vy_before,pre_speed,was_floor)
 _animate(delta)

func _cam_basis_flat() -> Basis:
 return Basis(Vector3.UP,yaw)

func _wish(local: Vector2) -> Vector3:
 var d = _cam_basis_flat()*Vector3(local.x,0,local.y)
 return d.normalized()*local.length() if d.length()>0.001 else Vector3.ZERO

func _accel_to(target: Vector3,a: float,delta: float):
 var h = Vector3(velocity.x,0,velocity.z)
 h = h.move_toward(target,a*delta)
 velocity.x = h.x
 velocity.z = h.z

func _ground(delta,jp,now):
 var sp = float(cfg.run)
 if ctl.walk: sp = float(cfg.walk)
 elif ctl.sprint: sp = float(cfg.sprint)
 var wish = _wish(ctl.move)
 _accel_to(wish*sp,float(cfg.accel)*(1.6 if ctl.sprint else 1.0),delta)
 velocity.y = -2.0
 if not is_on_floor():
  state = AIR
  sky_left = int(cfg.sky_jumps)
  dashed = false
  air_peak = global_position.y
 if jp:
  velocity.y = float(cfg.jump)
  model.play_once("jump",0.05,1.4)
  model.player.seek(0.45,true)
  state = AIR
  sky_left = int(cfg.sky_jumps)
  dashed = false
  last_jump_t = now
  air_peak = global_position.y
 if ctl.fly_pressed: _start_fly()
 # Sprinting into a wall runs up it (or along it at a glancing angle).
 if ctl.sprint and is_on_wall() and wish.length()>0.3:
  var n = get_wall_normal()
  var into = -wish.normalized().dot(n)
  if into>0.25: _start_wall(n,into>0.7)

func _air(delta,jp,now):
 var wish = _wish(ctl.move)
 var g = float(cfg.gravity)
 air_peak = maxf(air_peak,global_position.y)
 if state == GLIDE:
  # Fan Glider: a slow fall carried forward.
  var fwd = wish
  if fwd.length()<0.1: fwd = Vector3(velocity.x,0,velocity.z)
  if fwd.length()<0.1: fwd = Basis(Vector3.UP,facing)*Vector3(0,0,-1)
  _accel_to(fwd.normalized()*float(cfg.glide_speed),8.0,delta)
  velocity.y = maxf(velocity.y-g*0.4*delta,-float(cfg.glide_fall))
  if not ctl.jump: state = AIR
  air_peak = global_position.y
 else:
  var hs = Vector3(velocity.x,0,velocity.z).length()
  _accel_to(wish*maxf(hs,float(cfg.run)),float(cfg.accel)*float(cfg.air_control),delta)
  velocity.y -= g*delta
  if ctl.jump and velocity.y<-2.0 and now-last_jump_t>0.35: state = GLIDE
 if jp:
  if now-last_jump_t<float(cfg.double_tap):
   _start_fly() # double tap in the air: take flight
  elif sky_left>0:
   # Threefold Skywalk.
   velocity.y = float(cfg.sky_jump)
   sky_left -= 1
   state = AIR
   model.play_once("fall",0.05,1.6)
   air_peak = global_position.y
  elif not dashed:
   # Skywalk Dash: a burst forward after the third air jump.
   var d = wish if wish.length()>0.1 else -_cam_basis_flat().z
   velocity = d.normalized()*float(cfg.dash)+Vector3(0,3.0,0)
   dashed = true
   shake = maxf(shake,0.2)
  last_jump_t = now
 if ctl.fly_pressed: _start_fly()
 if ctl.sprint and is_on_wall() and wish.length()>0.3:
  var n = get_wall_normal()
  if -wish.normalized().dot(n)>0.25: _start_wall(n,-wish.normalized().dot(n)>0.7)

func _start_wall(n: Vector3,up: bool):
 state = WALL
 wall_n = n
 wall_up = up
 wall_t = 0.0

func _wall(delta,jp):
 wall_t += delta
 var sp = float(cfg.wall_run)
 if wall_up:
  velocity = -wall_n*2.0+Vector3(0,sp,0)
 else:
  var along = wall_n.cross(Vector3.UP)
  var wish = _wish(ctl.move)
  if along.dot(wish)<0.0: along = -along
  velocity = along*sp*1.15-wall_n*2.0+Vector3(0,2.0-wall_t*3.0,0)
 if jp:
  velocity = wall_n*9.0+Vector3(0,float(cfg.jump),0)+(-_cam_basis_flat().z)*4.0
  state = AIR
  sky_left = int(cfg.sky_jumps)
  last_jump_t = clock
  return
 if wall_t>float(cfg.wall_run_time) or not ctl.sprint:
  state = AIR
  velocity += wall_n*3.0
  return
 if not is_on_wall() and wall_t>0.1:
  # Over the top: vault up and onto it.
  state = AIR
  velocity = Vector3(0,7.5,0)-wall_n*5.0
  sky_left = int(cfg.sky_jumps)

func _start_fly():
 fly_since = clock
 state = FLY
 velocity.y = maxf(velocity.y,4.0)
 boomed = false
 model.play("fly",0.25)

func _fly(delta,jp,now):
 var cb = Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,pitch)
 var fwd = -cb.z
 var right = cb.x
 var target = Vector3.ZERO
 var sp = float(cfg.fly)
 if ctl.sprint and ctl.up:
  # Rapid climb: straight up at most of flight-sprint speed (the rise to the empire view).
  sp = float(cfg.fly_sprint)
  target = Vector3(fwd.x,0,fwd.z).normalized()*12.0+Vector3(0,sp*0.8,0)
 elif ctl.sprint:
  sp = float(cfg.fly_sprint)
  target = fwd*sp
 else:
  target = (fwd*-ctl.move.y+right*ctl.move.x)*sp
 if ctl.up and not ctl.sprint: target.y += float(cfg.fly_vertical)
 if ctl.down: target.y -= float(cfg.fly_vertical)
 var a = sp*float(cfg.fly_accel) if ctl.sprint else 40.0
 velocity = velocity.move_toward(target,a*delta)
 fly_speed = velocity.length()
 if fly_speed>float(cfg.boom_speed) and not boomed:
  boomed = true
  boom.emit(global_position+Vector3(0,1.4,0),velocity.normalized())
  shake = maxf(shake,0.6)
 if fly_speed<float(cfg.boom_speed)*0.7: boomed = false
 if ctl.fly_pressed:
  state = AIR
  last_jump_t = now
  air_peak = global_position.y
 # Smash through buildings at speed.
 if fly_speed>28.0 and town != null:
  var ahead = global_position+Vector3(0,1.4,0)+velocity*delta*1.5
  var hit = town.chunks_in_sphere(ahead,2.2)
  if not hit.is_empty():
   town.break_chunks(hit,global_position,fly_speed*0.5,0.1)
   crashed.emit(ahead,fly_speed)
   velocity *= 0.9
   shake = maxf(shake,0.35)

# Meteor Flight: straight down onto the target at dive speed, then the slam.
func start_dive(target: Vector3,speed: float):
 dive_target = target
 state = DIVE
 velocity = (target-global_position).normalized()*speed

func _dive(delta):
 var to = dive_target-global_position
 velocity = to.normalized()*maxf(velocity.length(),60.0)
 if to.length()<velocity.length()*delta*1.5: velocity = to/maxf(delta,0.001)

func _land(delta):
 land_t -= delta
 velocity.x = move_toward(velocity.x,0.0,40.0*delta)
 velocity.z = move_toward(velocity.z,0.0,40.0*delta)
 velocity.y = -2.0
 if land_t<=0.0: state = GROUND

func _after_move(vy_before: float,pre_speed: float,was_floor: bool):
 # Walking through fences and small things; sprinting smashes doors and stalls.
 for i in get_slide_collision_count():
  var col = get_slide_collision(i)
  var c = col.get_collider()
  if c is StaticBody3D and c.has_meta("block") and town != null and state != WALL:
   var small = town.chunks_in_sphere(col.get_position(),1.0 if pre_speed<12.0 else 1.8)
   var keep = []
   # On foot only small things give way (fences, stalls, barrels); walls stay for wall-running.
   # In flight at speed everything does (god/god_player.gd _fly smashes ahead too).
   for ci in small:
    var s = town.chunks[ci].size
    if s.x*s.y*s.z<1.2 or (state == FLY and pre_speed>20.0): keep.append(ci)
   if not keep.is_empty(): town.break_chunks(keep,global_position,maxf(6.0,pre_speed*0.6),0.2)
 var on = is_on_floor()
 if on and state in [AIR,GLIDE,FLY,DIVE] and not (state == FLY and clock-fly_since<0.5):
  var impact = -vy_before
  var fall = air_peak-global_position.y
  if state == DIVE:
   slammed.emit(global_position)
   _hard_land(1.0)
  elif state == FLY:
   if impact>float(cfg.hard_landing) or pre_speed>60.0: _hard_land(clampf(pre_speed/120.0,0.4,1.0))
   else:
    state = GROUND
    landed.emit(false,impact)
  elif impact>float(cfg.hard_landing) or fall>18.0:
   _hard_land(clampf(impact/50.0,0.35,1.0))
  else:
   state = GROUND
   landed.emit(false,impact)
 if state == GROUND and not on and vy_before<-1.0:
  pass

func _hard_land(strength: float):
 state = LAND
 land_t = 0.55+0.3*strength
 shake = maxf(shake,0.5+strength*0.8)
 velocity = Vector3.ZERO
 model.play_once("land",0.05,1.5)
 landed.emit(true,strength)

# --- Punches ------------------------------------------------------------------------------------------

func _punch(delta):
 var p = ctl.punch
 var pressed = p and not _prev_punch
 var released = not p and _prev_punch
 _prev_punch = p
 if state in [WALL,DIVE]: return
 if pressed:
  charging = true
  charge = 0.0
 if charging and p:
  charge += delta
  if charge>0.22:
   model.pose.twist = -clampf(charge/float(get_meta("charge_time",1.4)),0.0,1.0)*1.2
   if model.current != "punch" or model.player.current_animation_position>0.28:
    model.play_once("punch",0.12,1.0)
    model.player.seek(0.12,true)
   model.player.speed_scale = 0.0
 if charging and released:
  charging = false
  var ct = float(get_meta("charge_time",1.4))
  punch_serious = charge>0.35
  punch_charge = clampf(charge/ct,0.0,1.0)
  model.play_once("punch",0.04,1.6 if not punch_serious else 2.2)
  model.player.seek(0.12 if punch_serious else 0.0,true)
  model.pose.twist = 0.0
  punch_t = 0.0
  punch_pending = true
  charge = 0.0
 if punch_pending:
  punch_t += delta
  if punch_t>=(0.08 if punch_serious else 0.16):
   punch_pending = false
   var dir = -camera.global_transform.basis.z
   if not punch_serious:
    # A light punch goes where the god faces, at chest height.
    dir = Vector3(sin(facing+PI),0,cos(facing+PI))
    var aim = -camera.global_transform.basis.z
    dir = (dir+Vector3(0,clampf(aim.y,-0.6,0.6),0)).normalized()
   else:
    facing = atan2(-dir.x,-dir.z)
   punched.emit(punch_serious,global_position+Vector3(0,1.7,0),dir,punch_charge)

func charge_amount() -> float:
 return clampf(charge/float(get_meta("charge_time",1.4)),0.0,1.0) if charging and charge>0.22 else 0.0

# --- Animation and camera -----------------------------------------------------------------------------

func _animate(delta):
 var hv = Vector3(velocity.x,0,velocity.z)
 var hs = hv.length()
 if state in [GROUND,AIR,GLIDE,WALL] and hs>0.5:
  var target = atan2(hv.x,hv.z)+PI
  if state == WALL and wall_up: target = atan2(-wall_n.x,-wall_n.z)+PI
  facing = lerp_angle(facing,target,1.0-exp(-delta*12.0))
 elif state == FLY:
  var cb = -camera.global_transform.basis.z
  facing = lerp_angle(facing,atan2(cb.x,cb.z)+PI,1.0-exp(-delta*6.0))
 model.rotation = Vector3(0,facing,0)
 var p = model.pose
 p.lean = 0.0
 p.glide = 0.0
 p.reach = 0.0
 p.sweep = 0.0
 p.crouch = 0.0
 p.breath = 0.0
 var busy = model.current in ["punch","land"] and model.player.is_playing() and model.player.speed_scale>0.0 and model.player.current_animation_position<model.player.current_animation_length*0.92
 if charging and charge>0.22:
  busy = true
  p.crouch = 0.25
 match state:
  GROUND:
   if not busy:
    if hs<0.4:
     # No idle clip: the landing clip held on its last (standing) frame, breathing.
     model.play("idle",0.3,1.0)
     p.breath = 1.0
    else:
     var stride = 1.0 if ctl.walk else (1.9 if hs<float(cfg.run)+1.0 else 2.6)
     model.play("walk",0.2,hs/float(cfg.walk)*0.62/maxf(1.0,stride*0.7))
     p.lean = clampf((hs-float(cfg.walk))/float(cfg.sprint),0.0,1.0)*0.9
     p.sweep = clampf((hs-float(cfg.run))/(float(cfg.sprint)-float(cfg.run)),0.0,1.0)*0.5
  AIR:
   var jumping = model.current == "jump" and model.player.is_playing() and model.player.current_animation_position<1.2
   if not busy and not jumping: model.play("fall",0.25,1.0)
   p.lean = 0.2 if dashed else 0.0
   p.sweep = 0.8 if dashed else 0.0
  GLIDE:
   model.play("fall",0.3,0.6)
   p.glide = 0.9
   p.lean = 0.5
  WALL:
   model.play("walk",0.15,3.4)
   p.lean = -0.25 if wall_up else 0.3
  FLY:
   if not busy: model.play("fly",0.3,1.0)
   var f = clampf(fly_speed/float(cfg.fly_sprint),0.0,1.0)
   p.reach = smoothstep(0.25,0.6,f)
   p.lean = f*0.5
   # Superman pose at speed: pitch the body along the flight path.
   var vdir = velocity.normalized() if fly_speed>1.0 else Vector3.ZERO
   var tilt = -acos(clampf(vdir.dot(Vector3.UP),-1.0,1.0))*smoothstep(8.0,40.0,fly_speed)
   model.rotation.x = tilt*0.92
  DIVE:
   model.play("fly",0.2,1.4)
   p.reach = 1.0
   model.rotation.x = -PI*0.92
  LAND:
   p.crouch = clampf(land_t*1.5,0.0,0.9)

func _process(delta):
 if external_camera: return
 var real = delta/maxf(Engine.time_scale,0.05)
 var hs = velocity.length()
 var target = global_position+Vector3(0,float(cam_cfg.height),0)
 var follow = 1.0-exp(-real*(18.0 if state != FLY else 30.0))
 pivot.global_position = pivot.global_position.lerp(target,follow)
 var alt = global_position.y-terrain.height_at(global_position.x,global_position.z)
 var pull = maxf(0.0,alt-float(get_meta("pull_from",60.0)))
 var speed_back = clampf(hs/60.0,0.0,1.0)*4.0
 var want = float(cam_cfg.distance)+speed_back+cam_extra+pull*0.18
 arm.spring_length = lerpf(arm.spring_length,want,1.0-exp(-real*4.0))
 # High up the camera tips over to look down on the god and the land below (the rise).
 var k = smoothstep(0.0,350.0,pull)
 pivot.rotation = Vector3(clampf(lerpf(pitch+cam_pitch_bias,-0.95,k),-1.5,1.1),yaw,0)
 var shoulder = float(cam_cfg.shoulder)*(1.0-clampf(pull/80.0,0.0,1.0))
 # Shake (decays) and the FOV that widens with speed.
 _shake_t += real
 shake = maxf(0.0,shake-real*1.4)
 var s = shake*shake
 camera.h_offset = shoulder+(sin(_shake_t*47.0)+sin(_shake_t*31.0))*0.12*s
 camera.v_offset = (sin(_shake_t*53.0)+cos(_shake_t*37.0))*0.12*s
 var fov_t = clampf(hs/float(cam_cfg.fov_speed),0.0,1.0)
 camera.fov = lerpf(camera.fov,lerpf(float(cam_cfg.fov),float(cam_cfg.fov_max),fov_t*fov_t*(3.0-2.0*fov_t))-charge_amount()*8.0,1.0-exp(-real*3.0))

func state_name() -> String:
 return STATE_NAMES[state]
