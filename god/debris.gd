extends Node3D
# Flying debris for the god-game look test: broken town chunks (god/town.gd) as Jolt rigid bodies
# with a hard cap on live bodies. A body that sleeps, or outlives sleep_after seconds, freezes into
# static rubble (its mesh stays, the body goes); past the rubble cap the oldest rubble sinks away.
# When the live cap is full, new chunks fall straight to the ground as rubble instead.

var live_cap := 320
var rubble_cap := 2600
var sleep_after := 6.0
var live: Array = [] # [body, born]
var rubble: Array = [] # MeshInstance3D
var fading: Array = [] # [node, t]
var terrain
var rng := RandomNumberGenerator.new()
var spawned_total := 0
var _shape_cache = {}
var clock := 0.0

func setup(cfg: Dictionary,t):
 live_cap = int(cfg.debris_live_cap)
 rubble_cap = int(cfg.debris_rubble_cap)
 sleep_after = float(cfg.debris_sleep_after)
 terrain = t
 rng.seed = 99

func live_count() -> int:
 return live.size()

# A chunk of `town` flies off with velocity v. False when the live cap is full (the caller drops it
# as rubble or lets it vanish in the dust).
func spawn(town,ci: int,v: Vector3,dist: float) -> bool:
 if live.size()>=live_cap: return false
 var ch = town.chunks[ci]
 var body = RigidBody3D.new()
 body.collision_layer = 4
 body.collision_mask = 1|2|4
 var vol = maxf(0.05,ch.size.x*ch.size.y*ch.size.z)
 body.mass = clampf(vol*600.0,20.0,6000.0)
 body.continuous_cd = false
 body.can_sleep = true
 body.linear_damp = 0.05
 body.angular_damp = 0.4
 var pm = PhysicsMaterial.new()
 pm.friction = 0.9
 pm.bounce = 0.05
 body.physics_material_override = pm
 var cs = CollisionShape3D.new()
 # A box a little smaller than the piece (cheaper contacts than its convex hull when a blast's worth
 # of debris lands at once; neighbours do not start out overlapping).
 var shape = BoxShape3D.new()
 shape.size = (ch.size*0.8).max(Vector3.ONE*0.15)
 cs.shape = shape
 body.add_child(cs)
 var mi = MeshInstance3D.new()
 mi.mesh = town.chunk_mesh(ci)
 mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if ch.size.length()>1.2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 body.add_child(mi)
 add_child(body)
 body.global_position = ch.center
 body.linear_velocity = v
 body.angular_velocity = Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))*clampf(v.length()*0.12,0.5,6.0)
 live.append([body,clock])
 spawned_total += 1
 return true

# A chunk that does not get a body tumbles straight down onto the ground as static rubble.
func drop_rubble(town,ci: int,origin: Vector3):
 var ch = town.chunks[ci]
 if rubble.size()>=rubble_cap: _fade_oldest(64)
 if ch.size.length()<0.6 or rng.randf()<0.45: return # small bits vanish in the dust
 var mi = MeshInstance3D.new()
 mi.mesh = town.chunk_mesh(ci)
 mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(mi)
 var away = Vector3(ch.center.x-origin.x,0,ch.center.z-origin.z).normalized()
 var p = ch.center+away*rng.randf_range(0.5,4.0)
 p.y = terrain.height_at(p.x,p.z)+ch.size.y*0.2
 mi.global_position = p
 mi.rotation = Vector3(rng.randf_range(-1.4,1.4),rng.randf()*TAU,rng.randf_range(-1.4,1.4))
 rubble.append(mi)

func _physics_process(_delta):
 clock += _delta
 var now = clock
 var i = 0
 var frozen = 0
 while i<live.size():
  var body: RigidBody3D = live[i][0]
  var age = now-live[i][1]
  var low = body.global_position.y<terrain.height_at(body.global_position.x,body.global_position.z)-20.0
  if low:
   body.queue_free()
   live.remove_at(i)
   continue
  # At most a dozen a frame (a blast's debris settles together).
  if frozen<12 and ((body.sleeping and age>0.6) or age>sleep_after):
   _freeze(body)
   live.remove_at(i)
   frozen += 1
   continue
  i += 1

func _freeze(body: RigidBody3D):
 var mi: MeshInstance3D = null
 for c in body.get_children():
  if c is MeshInstance3D: mi = c
 if mi != null:
  var xf = mi.global_transform
  body.remove_child(mi)
  add_child(mi)
  mi.global_transform = xf
  mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  rubble.append(mi)
 body.queue_free()
 if rubble.size()>rubble_cap: _fade_oldest(rubble.size()-rubble_cap)

func _fade_oldest(n: int):
 for k in mini(n,rubble.size()):
  fading.append([rubble[0],0.0])
  rubble.remove_at(0)

func _process(delta):
 var i = 0
 while i<fading.size():
  var f = fading[i]
  f[1] += delta
  var node: Node3D = f[0]
  if not is_instance_valid(node):
   fading.remove_at(i)
   continue
  node.position.y -= delta*0.6
  node.scale = Vector3.ONE*maxf(0.01,1.0-f[1])
  if f[1]>=1.0:
   node.queue_free()
   fading.remove_at(i)
   continue
  i += 1

func clear():
 for l in live: l[0].queue_free()
 live.clear()
 for r in rubble: r.queue_free()
 rubble.clear()
 for f in fading: if is_instance_valid(f[0]): f[0].queue_free()
 fading.clear()
