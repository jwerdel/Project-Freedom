extends Node3D
# Townsfolk of the god-game look test (a small taste of Manor Lords' living villagers): peasants
# (the shared CC0 Quaternius soldier model in peasant clothes, visuals/units/soldier_visual.gd) who
# walk the roads between their homes, the well, the market and the fields, idle there, and carry
# buckets and crates home. They react to the god: they stop and stare when he lands nearby, flee
# from destruction, get knocked down when he crashes through them, and fill a Where Winds Meet-style
# suspicion bar (drawn by god/hud.gd) at reckless behaviour, which pulls the town's approval down.
# Walking uses the Mixamo walk from the god's clips, retargeted onto the Quaternius rig at start
# (swing retarget per limb: bone directions, no twist); idling uses Quaternius' Idle_Loop.

const AssetManifest = preload("res://core/asset_manifest.gd")
const IDLE = preload("res://assets/quaternius/animations/Idle_Loop.res")
const WALK_SRC = "res://assets/characters/edric_varn/walking.fbx"
const MAP = {"Hips":"pelvis","Spine":"spine_01","Spine1":"spine_02","Spine2":"spine_03","Neck":"neck_01","Head":"Head",
 "LeftShoulder":"clavicle_l","LeftArm":"upperarm_l","LeftForeArm":"lowerarm_l","LeftHand":"hand_l",
 "RightShoulder":"clavicle_r","RightArm":"upperarm_r","RightForeArm":"lowerarm_r","RightHand":"hand_r",
 "LeftUpLeg":"thigh_l","LeftLeg":"calf_l","LeftFoot":"foot_l","LeftToeBase":"ball_l",
 "RightUpLeg":"thigh_r","RightLeg":"calf_r","RightFoot":"foot_r","RightToeBase":"ball_r"}
# Limb bones and the child whose joint gives their direction (swing retarget).
const LIMBS = {"LeftArm":"LeftForeArm","LeftForeArm":"LeftHand","RightArm":"RightForeArm","RightForeArm":"RightHand",
 "LeftUpLeg":"LeftLeg","LeftLeg":"LeftFoot","LeftFoot":"LeftToeBase","RightUpLeg":"RightLeg","RightLeg":"RightFoot","RightFoot":"RightToeBase",
 "LeftShoulder":"LeftArm","RightShoulder":"RightArm"}
const LOOKS = [
 {"outfit":"outfit.peasant","tint":"#a08a6a","hair":["hair.buzzed"],"hair_color":"#4a3424"},
 {"outfit":"outfit.peasant","tint":"#7d8a92","hair":["hair.beard"],"hair_color":"#6b4a30"},
 {"outfit":"outfit.peasant","tint":"#8a6a5a","hair":["hair.parted"],"hair_color":"#2e241c"},
 {"outfit":"outfit.ranger_hoodless","tint":"#8c8070","hair":["hair.parted"],"hair_color":"#8a6a40"},
 {"outfit":"outfit.peasant","tint":"#6a7058","hair":["hair.beard","hair.buzzed"],"hair_color":"#5a3c26"},
 {"outfit":"outfit.ranger","tint":"#706a62","hair":[],"hair_color":"#3a2a1e"}]

enum {WALK,IDLE_AT,LOOK,FLEE,DOWN}

var town
var terrain
var cfg: Dictionary
var people: Array = []
var walk_anim: Animation
var rng := RandomNumberGenerator.new()
var god: Node3D
var clock := 0.0
var lod_range := 90.0
var bucket_mesh: Array = []
var hurt := 0

func setup(c: Dictionary,t,tw,g: Node3D,count: int):
 cfg = c
 terrain = t
 town = tw
 god = g
 lod_range = float(c.get("villager_lod",90.0))
 rng.seed = 2024
 walk_anim = _retarget_walk()
 _build_astar()
 var scene = load("res://assets/god/models/wooden_bucket_01/wooden_bucket_01.gltf").instantiate()
 for mi in scene.find_children("*","MeshInstance3D",true,false): bucket_mesh.append([mi.mesh,mi.transform])
 scene.free()
 var homes = town.homes.duplicate()
 for i in count:
  var home = homes[rng.randi_range(0,homes.size()-1)]
  _spawn(i,home)

func _spawn(i: int,home: int):
 var look = LOOKS[i%LOOKS.size()]
 var v = AssetManifest.instantiate("unit.soldier")
 add_child(v)
 v.configure({"outfit":look.outfit,"loadout":[],"visual_config":{"pose":"idle","tint":look.tint,"hair":look.hair,"hair_color":look.hair_color,"scale":rng.randf_range(0.94,1.04)}})
 var body = v.skeleton.get_parent()
 while body.get_parent() != v: body = body.get_parent()
 var ap = AnimationPlayer.new()
 body.add_child(ap)
 var lib = AnimationLibrary.new()
 var idle = IDLE.duplicate()
 idle.loop_mode = Animation.LOOP_LINEAR
 lib.add_animation("idle",idle)
 lib.add_animation("walk",walk_anim)
 ap.add_animation_library("",lib)
 ap.play("idle")
 ap.seek(rng.randf()*2.0,true)
 for mi in v.find_children("*","MeshInstance3D",true,false):
  mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
  mi.visibility_range_end = lod_range
  mi.visibility_range_end_margin = 10.0
 var door: Vector3 = town.blocks[home].door
 var p = {"node":v,"ap":ap,"skel":v.skeleton,"home":home,"pos":door+Vector3(rng.randf_range(-2,2),0,rng.randf_range(-2,2)),"yaw":rng.randf()*TAU,
  "state":IDLE_AT,"t":rng.randf_range(0.0,6.0),"path":[],"speed":rng.randf_range(1.25,1.6),"sus":0.0,"alarm":false,"goal":"home",
  "carry":null,"look_t":0.0,"lean":0.0,"down_axis":Vector3.RIGHT,"down_t":0.0}
 people.append(p)
 _place(p)

# --- Walk retarget (Mixamo -> Quaternius) ------------------------------------------------------------

func _retarget_walk() -> Animation:
 var src_scene = load(WALK_SRC).instantiate()
 var sk: Skeleton3D = src_scene.find_children("*","Skeleton3D",true,false)[0]
 var sp: AnimationPlayer = src_scene.find_children("*","AnimationPlayer",true,false)[0]
 var anim: Animation = sp.get_animation(sp.get_animation_list()[0])
 var tgt_root = load("res://assets/quaternius/characters/Superhero_Male_FullBody.gltf").instantiate()
 var tk: Skeleton3D = tgt_root.find_children("*","Skeleton3D",true,false)[0]
 var skel_path = str(tgt_root.get_path_to(tk))
 # Source rest (locals) and track lookup.
 var tracks = {}
 for t in anim.get_track_count():
  var bn = anim.track_get_path(t).get_concatenated_subnames()
  if not tracks.has(bn): tracks[bn] = {}
  tracks[bn][anim.track_get_type(t)] = t
 var out = Animation.new()
 out.length = anim.length
 out.loop_mode = Animation.LOOP_LINEAR
 var tgt_tracks = {}
 for m in MAP:
  var tb = tk.find_bone(MAP[m])
  if tb<0: continue
  var tr = out.add_track(Animation.TYPE_ROTATION_3D)
  out.track_set_path(tr,NodePath(skel_path+":"+MAP[m]))
  tgt_tracks[m] = tr
 var pelvis_tr = out.add_track(Animation.TYPE_POSITION_3D)
 out.track_set_path(pelvis_tr,NodePath(skel_path+":pelvis"))
 var src_hip_h = sk.get_bone_global_rest(sk.find_bone("mixamorig_Hips")).origin.y-sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftToe_End")).origin.y
 var tgt_hip = tk.get_bone_rest(tk.find_bone("pelvis")).origin
 var tgt_hip_h = tk.get_bone_global_rest(tk.find_bone("pelvis")).origin.y
 var hip_scale = tgt_hip_h/maxf(src_hip_h,0.0001)
 var first_hip = Vector3.ZERO
 var steps = int(anim.length*30.0)
 for s in steps+1:
  var time = anim.length*s/steps
  # Source FK at this time.
  var g = {}
  for i in sk.get_bone_count():
   var bn = sk.get_bone_name(i)
   var rest = sk.get_bone_rest(i)
   var rot = rest.basis.get_rotation_quaternion()
   var pos = rest.origin
   if tracks.has(bn):
    if tracks[bn].has(Animation.TYPE_ROTATION_3D): rot = anim.rotation_track_interpolate(tracks[bn][Animation.TYPE_ROTATION_3D],time)
    if tracks[bn].has(Animation.TYPE_POSITION_3D): pos = anim.position_track_interpolate(tracks[bn][Animation.TYPE_POSITION_3D],time)
   var local = Transform3D(Basis(rot),pos)
   var par = sk.get_bone_parent(i)
   g[i] = (g[par]*local) if par>=0 else local
  var tg = {} # target global transforms (rotation part used), by Mixamo name
  # Walk the target hierarchy in index order so parents come first.
  var tglob = {}
  for ti in tk.get_bone_count():
   var tname = tk.get_bone_name(ti)
   var mname = ""
   for m in MAP: if MAP[m] == tname: mname = m
   var trest_g = tk.get_bone_global_rest(ti)
   var tpar = tk.get_bone_parent(ti)
   var parent_g = tglob[tpar] if tpar>=0 else Transform3D.IDENTITY
   var gb: Basis
   if mname == "":
    gb = parent_g.basis*tk.get_bone_rest(ti).basis
   else:
    var si = sk.find_bone("mixamorig_"+mname)
    if LIMBS.has(mname):
     var ci = sk.find_bone("mixamorig_"+LIMBS[mname])
     var d_src = (g[ci].origin-g[si].origin).normalized()
     var tci = tk.find_bone(MAP[LIMBS[mname]])
     var d_rest = (tk.get_bone_global_rest(tci).origin-trest_g.origin).normalized()
     gb = Basis(_swing(d_rest,d_src))*trest_g.basis.orthonormalized()
    else:
     var src_rest_g = sk.get_bone_global_rest(si).basis.orthonormalized()
     var delta = g[si].basis.orthonormalized()*src_rest_g.inverse()
     gb = delta*trest_g.basis.orthonormalized()
   var local_b = parent_g.basis.orthonormalized().inverse()*gb.orthonormalized()
   tglob[ti] = Transform3D(parent_g.basis.orthonormalized()*local_b,Vector3.ZERO)
   if mname != "" and tgt_tracks.has(mname):
    out.rotation_track_insert_key(tgt_tracks[mname],time,local_b.get_rotation_quaternion())
  var hip = g[sk.find_bone("mixamorig_Hips")].origin
  if s == 0: first_hip = hip
  out.position_track_insert_key(pelvis_tr,time,tgt_hip+Vector3(0,(hip.y-first_hip.y)*hip_scale,0))
 src_scene.free()
 tgt_root.free()
 return out

static func _swing(a: Vector3,b: Vector3) -> Quaternion:
 var c = a.cross(b)
 var d = a.dot(b)
 if c.length()<1e-6: return Quaternion() if d>0.0 else Quaternion(Vector3.UP,PI)
 return Quaternion(c.normalized(),acos(clampf(d,-1.0,1.0)))

# --- Behaviour ----------------------------------------------------------------------------------------

func _place(p: Dictionary):
 p.pos.y = terrain.height_at(p.pos.x,p.pos.z)
 p.node.position = p.pos
 var r = Basis(Vector3.UP,p.yaw)
 if p.state == DOWN:
  r = Basis(p.down_axis,PI*0.5*clampf(p.down_t*3.0,0.0,1.0))*r
 elif p.lean != 0.0:
  r = Basis(r.x,p.lean)*r
 p.node.basis = r

var astar: AStar2D

func _build_astar():
 astar = AStar2D.new()
 var pts: PackedVector2Array = town.road_graph.points
 var links: Array = town.road_graph.links
 for i in pts.size(): astar.add_point(i,pts[i])
 for i in pts.size():
  for j in links[i]:
   if j>i: astar.connect_points(i,j)

func _nearest_node(pos: Vector3) -> int:
 return astar.get_closest_point(Vector2(pos.x,pos.z))

# A walk along the roads (AStar2D over the town's road graph), ending at `to`.
func _path(from: Vector3,to: Vector3) -> Array:
 var a = _nearest_node(from)
 var b = _nearest_node(to)
 var route = []
 for q in astar.get_point_path(a,b): route.append(Vector3(q.x,0,q.y))
 route.append(to)
 return route

func _choose_goal(p: Dictionary) -> Vector3:
 var roll = rng.randf()
 var target: Vector3
 if p.goal != "home" and roll<0.45:
  p.goal = "home"
  target = town.blocks[p.home].door
 elif roll<0.65:
  p.goal = "well"
  target = town.well+Vector3(rng.randf_range(-3,3),0,rng.randf_range(-3,3))
 elif roll<0.85 or town.field_spots.is_empty():
  p.goal = "market"
  target = town.market+Vector3(rng.randf_range(-9,9),0,rng.randf_range(-9,9))
 else:
  p.goal = "field"
  target = town.field_spots[rng.randi_range(0,town.field_spots.size()-1)]+Vector3(rng.randf_range(-8,8),0,rng.randf_range(-30,30))
 return target

func _set_carry(p: Dictionary,on: bool):
 if on and p.carry == null:
  var att = BoneAttachment3D.new()
  att.bone_name = "hand_r"
  p.skel.add_child(att)
  for bm in bucket_mesh:
   var mi = MeshInstance3D.new()
   mi.mesh = bm[0]
   mi.transform = Transform3D(Basis(Vector3.RIGHT,PI),Vector3(0,-0.05,0.05))*bm[1]
   att.add_child(mi)
  p.carry = att
 elif not on and p.carry != null:
  p.carry.queue_free()
  p.carry = null

func _process(delta):
 clock += delta
 var gp = god.global_position if god != null else Vector3(INF,0,INF)
 var cam = get_viewport().get_camera_3d()
 var cp = cam.global_position if cam != null else gp
 var god_speed = god.velocity.length() if god != null and "velocity" in god else 0.0
 for p in people:
  var near = p.pos.distance_to(cp)<lod_range+10.0
  p.ap.active = near
  if near: p.ap.speed_scale = 1.0
  # Crashing through people.
  if god_speed>8.0 and p.state != DOWN and p.pos.distance_to(gp)<2.6:
   _knock(p,gp)
   _suspect(p,float(cfg.suspicion_crash))
  match p.state:
   WALK, FLEE:
    if p.path.is_empty():
     if p.state == FLEE:
      p.state = IDLE_AT
      p.t = rng.randf_range(3.0,6.0)
     else:
      p.state = IDLE_AT
      p.t = rng.randf_range(4.0,12.0)
      _set_carry(p,p.goal == "well" or (p.goal == "market" and rng.randf()<0.4))
     if near: p.ap.play("idle",0.3)
     continue
    var tgt: Vector3 = p.path[0]
    var d = Vector3(tgt.x-p.pos.x,0,tgt.z-p.pos.z)
    var sp = p.speed*(2.9 if p.state == FLEE else 1.0)
    if d.length()<0.6:
     p.path.pop_front()
     continue
    var step = d.normalized()*minf(sp*delta,d.length())
    p.pos += step
    p.yaw = lerp_angle(p.yaw,atan2(d.x,d.z),1.0-exp(-delta*8.0))
    p.lean = 0.12 if p.state == FLEE else 0.0
    if near:
     if p.ap.current_animation != "walk": p.ap.play("walk",0.25)
     p.ap.speed_scale = sp/1.35
   IDLE_AT:
    p.t -= delta
    if p.t<=0.0:
     p.path = _path(p.pos,_choose_goal(p))
     p.state = WALK
     if p.goal != "home" and p.carry != null and rng.randf()<0.6: _set_carry(p,false)
   LOOK:
    p.t -= delta
    p.yaw = lerp_angle(p.yaw,atan2(gp.x-p.pos.x,gp.z-p.pos.z),1.0-exp(-delta*5.0))
    if near and p.ap.current_animation != "idle": p.ap.play("idle",0.3)
    if p.t<=0.0:
     p.state = IDLE_AT
     p.t = rng.randf_range(0.5,2.0)
   DOWN:
    p.down_t += delta
    if near and p.ap.current_animation != "idle": p.ap.play("idle",0.2)
    if p.down_t>3.5:
     p.state = FLEE
     p.down_t = 0.0
     p.path = _flee_path(p,gp)
  p.sus = maxf(0.0,p.sus-delta*float(cfg.suspicion_decay))
  _place(p)

func _suspect(p: Dictionary,amount: float):
 var before = p.sus
 p.sus = minf(1.0,p.sus+amount)
 if p.sus>=1.0 and before<1.0:
  p.alarm = true
  town.approval = maxf(0.0,town.approval-1.2)

func _knock(p: Dictionary,from: Vector3):
 p.state = DOWN
 p.down_t = 0.0
 var away = Vector3(p.pos.x-from.x,0,p.pos.z-from.z).normalized()
 if away.length()<0.1: away = Vector3.FORWARD
 p.down_axis = Vector3.UP.cross(away).normalized()
 hurt += 1
 town.approval = maxf(0.0,town.approval-float(cfg.approval_per_villager_hurt))
 _set_carry(p,false)

func _flee_path(p: Dictionary,danger: Vector3) -> Array:
 var away = Vector3(p.pos.x-danger.x,0,p.pos.z-danger.z).normalized()
 if away.length()<0.1: away = Vector3(rng.randf_range(-1,1),0,rng.randf_range(-1,1)).normalized()
 var goal = p.pos+away*rng.randf_range(45.0,80.0)
 goal.x = clampf(goal.x,-terrain.half+50.0,terrain.half-50.0)
 goal.z = clampf(goal.z,-terrain.half+50.0,terrain.half-50.0)
 var path = _path(p.pos,goal)
 # Skip road nodes that lead back toward the danger.
 while path.size()>1 and Vector3(path[0].x-danger.x,0,path[0].z-danger.z).length()<Vector3(p.pos.x-danger.x,0,p.pos.z-danger.z).length()-4.0: path.pop_front()
 return path

# --- Reactions (called by god/god_test.gd) -----------------------------------------------------------------

# The god landed nearby: everyone within `r` stops and stares.
func on_landing(pos: Vector3,r: float,hard: bool):
 for p in people:
  var d = p.pos.distance_to(pos)
  if d>r or p.state in [FLEE,DOWN]: continue
  if hard and d<14.0:
   _suspect(p,float(cfg.suspicion_wreck))
   p.state = FLEE
   p.path = _flee_path(p,pos)
   continue
  p.state = LOOK
  p.t = rng.randf_range(3.0,6.0)

# Destruction at pos (radius r of the blast; people inside `kill_r` are knocked down).
func on_destruction(pos: Vector3,r: float,amount: float,knock_r := 0.0):
 for p in people:
  var d = p.pos.distance_to(pos)
  if d<knock_r and p.state != DOWN:
   _knock(p,pos)
  if d<r:
   _suspect(p,float(cfg.suspicion_wreck)*amount*clampf(1.0-d/r+0.3,0.0,1.0))
   if p.state != DOWN:
    p.state = FLEE
    p.path = _flee_path(p,pos)

func reset_all():
 for p in people:
  p.sus = 0.0
  p.alarm = false
  p.state = IDLE_AT
  p.t = rng.randf_range(0.0,3.0)
  p.path = []
  p.pos = town.blocks[p.home].door
 hurt = 0

func alarmed_count() -> int:
 var n = 0
 for p in people: if p.sus>0.5: n += 1
 return n
