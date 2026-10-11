extends Node3D
# Effects of the god-game look test: dust clouds, stone chips and wood splinters, embers and fire,
# expanding shockwave rings (a screen-distorting band), the sonic boom's vapour ring, craters and
# landing cracks (decals that stay until reset), the charge-up swirl, impact flashes, and the town's
# steady smoke and steam. One-shot GPU particle systems free themselves after their lifetime (game
# time, so Movie Maker captures match play). Textures are generated at start (no files).

var smoke_tex: Texture2D
var spark_tex: Texture2D
var crater_tex: Texture2D
var crater_n: Texture2D
var crack_tex: Texture2D
var ring_mat: ShaderMaterial
var dust_mat: StandardMaterial3D
var fire_mat: StandardMaterial3D
var ember_mat: StandardMaterial3D
var chip_mesh: Mesh
var splinter_mesh: BoxMesh
var clock := 0.0
var timed: Array = [] # [node, free_at]
var rings: Array = [] # {node, t, dur, r0, r1}
var decals: Array = []
var swirl: GPUParticles3D
var collider: GPUParticlesCollisionHeightField3D
var rng := RandomNumberGenerator.new()
const MAX_DECALS = 60

func _ready():
 rng.seed = 5
 smoke_tex = _soft_tex(128,0.55,true)
 spark_tex = _soft_tex(32,0.2,false)
 _crater_textures()
 dust_mat = StandardMaterial3D.new()
 dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
 dust_mat.albedo_texture = smoke_tex
 dust_mat.vertex_color_use_as_albedo = true
 dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
 dust_mat.proximity_fade_enabled = true
 dust_mat.proximity_fade_distance = 2.0
 dust_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
 dust_mat.distance_fade_min_distance = 0.5
 dust_mat.distance_fade_max_distance = 3.0
 fire_mat = StandardMaterial3D.new()
 fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
 fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
 fire_mat.albedo_texture = smoke_tex
 fire_mat.vertex_color_use_as_albedo = true
 fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 fire_mat.albedo_color = Color(1.0,0.55,0.2)
 fire_mat.emission_enabled = true
 fire_mat.emission = Color(1.0,0.45,0.12)
 fire_mat.emission_energy_multiplier = 3.0
 ember_mat = fire_mat.duplicate()
 ember_mat.albedo_texture = spark_tex
 ember_mat.emission_energy_multiplier = 6.0
 # Stone chips: small faceted lumps; wood: thin splinters.
 var sm = SphereMesh.new()
 sm.radius = 0.07
 sm.height = 0.1
 sm.radial_segments = 5
 sm.rings = 3
 chip_mesh = sm
 splinter_mesh = BoxMesh.new()
 splinter_mesh.size = Vector3(0.035,0.035,0.32)
 ring_mat = ShaderMaterial.new()
 ring_mat.shader = load("res://god/shockwave.gdshader")

func _soft_tex(size: int,edge: float,noisy: bool) -> ImageTexture:
 var img = Image.create(size,size,false,Image.FORMAT_RGBA8)
 var nz = FastNoiseLite.new()
 nz.frequency = 0.06*128.0/size
 nz.fractal_octaves = 4
 for y in size:
  for x in size:
   var d = Vector2(x+0.5,y+0.5).distance_to(Vector2(size,size)*0.5)/(size*0.5)
   var a = clampf(1.0-smoothstep(1.0-edge-0.3,1.0,d),0.0,1.0)
   if noisy: a *= clampf(0.55+nz.get_noise_2d(x,y)*0.9,0.0,1.0)
   img.set_pixel(x,y,Color(1,1,1,a))
 img.generate_mipmaps()
 return ImageTexture.create_from_image(img)

# A scorched crater with radial cracks (albedo with alpha, and a normal map for the dished rim).
func _crater_textures():
 var s = 256
 var img = Image.create(s,s,false,Image.FORMAT_RGBA8)
 var nimg = Image.create(s,s,false,Image.FORMAT_RGBA8)
 var crk = Image.create(s,s,false,Image.FORMAT_RGBA8)
 var nz = FastNoiseLite.new()
 nz.frequency = 0.03
 nz.fractal_octaves = 5
 var cr = FastNoiseLite.new()
 cr.noise_type = FastNoiseLite.TYPE_CELLULAR
 cr.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
 cr.frequency = 0.035
 for y in s:
  for x in s:
   var p = Vector2(x,y)-Vector2(s,s)*0.5
   var d = p.length()/(s*0.5)
   var a = atan2(p.y,p.x)
   var n = nz.get_noise_2d(x,y)
   var dd = d+n*0.08
   var crack = 1.0-smoothstep(0.0,0.06,absf(sin(a*7.0+n*3.0))*d)
   crack *= smoothstep(1.0,0.2,dd)
   var cell = cr.get_noise_2d(x,y)
   var web = smoothstep(0.85,0.98,cell)*smoothstep(1.0,0.3,dd)
   var scorch = smoothstep(1.0,0.35,dd)
   var col = Color(0.12,0.1,0.09).lerp(Color(0.32,0.28,0.24),clampf(dd+n*0.3,0.0,1.0))
   col = col.darkened(clampf(crack+web,0.0,1.0)*0.6)
   img.set_pixel(x,y,Color(col.r,col.g,col.b,clampf(scorch*1.1+crack*0.5,0.0,1.0)))
   # Dish: the rim slopes outward around d = 0.75.
   var slope = sin(clampf(dd/0.95,0.0,1.0)*PI)*0.7
   var nd = p.normalized()*slope*(1.0 if dd<0.75 else -1.0)
   nimg.set_pixel(x,y,Color(0.5-nd.x*0.5,0.5-nd.y*0.5,1.0,1.0))
   var cl = clampf(crack*1.4+web,0.0,1.0)*smoothstep(1.0,0.5,dd)
   crk.set_pixel(x,y,Color(0.08,0.07,0.06,cl))
 img.generate_mipmaps()
 nimg.generate_mipmaps()
 crk.generate_mipmaps()
 crater_tex = ImageTexture.create_from_image(img)
 crater_n = ImageTexture.create_from_image(nimg)
 crack_tex = ImageTexture.create_from_image(crk)

func _process(delta):
 clock += delta
 var i = 0
 while i<timed.size():
  if clock>=timed[i][1]:
   if is_instance_valid(timed[i][0]): timed[i][0].queue_free()
   timed.remove_at(i)
  else: i += 1
 i = 0
 while i<rings.size():
  var r = rings[i]
  r.t += delta
  var f = clampf(r.t/r.dur,0.0,1.0)
  var e = 1.0-pow(1.0-f,2.4)
  var rad = lerpf(r.r0,r.r1,e)
  r.node.scale = Vector3(rad,r.get("hs",1.0)*lerpf(1.0,0.3,f),rad)
  r.node.set_instance_shader_parameter("fade",1.0-f)
  if f>=1.0:
   r.node.queue_free()
   rings.remove_at(i)
  else: i += 1
 if collider != null and get_viewport().get_camera_3d() != null:
  var c = get_viewport().get_camera_3d().global_position
  collider.global_position = Vector3(snappedf(c.x,4.0),0,snappedf(c.z,4.0))

func _later(n: Node,secs: float):
 timed.append([n,clock+secs])

func setup_collider():
 collider = GPUParticlesCollisionHeightField3D.new()
 collider.size = Vector3(240,400,240)
 collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
 collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
 collider.follow_camera_enabled = true
 add_child(collider)

func _particles(pos: Vector3,amount: int,life: float,mat: Material,mesh: Mesh,pm: ParticleProcessMaterial,one_shot := true) -> GPUParticles3D:
 var p = GPUParticles3D.new()
 p.amount = amount
 p.lifetime = life
 p.one_shot = one_shot
 p.explosiveness = 0.9 if one_shot else 0.0
 p.process_material = pm
 p.draw_pass_1 = mesh
 p.material_override = mat
 p.visibility_aabb = AABB(Vector3(-120,-20,-120),Vector3(240,140,240))
 p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 p.local_coords = false
 p.fixed_fps = 0
 add_child(p)
 p.global_position = pos
 p.emitting = true
 if one_shot: _later(p,life+0.5)
 return p

func _quad(size: float) -> QuadMesh:
 var q = QuadMesh.new()
 q.size = Vector2(size,size)
 return q

# A billowing dust cloud: radius r, `amount` puffs, rising and spreading, lasting `life` seconds.
func dust(pos: Vector3,r: float,amount: int,life := 6.0,col := Color(0.62,0.58,0.53,0.75),speed := 6.0,up := 0.6):
 var pm = ParticleProcessMaterial.new()
 pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
 pm.emission_sphere_radius = r*0.5
 pm.direction = Vector3(0,up,0)
 pm.spread = 80.0
 pm.initial_velocity_min = speed*0.4
 pm.initial_velocity_max = speed
 pm.gravity = Vector3(0,0.35,0)
 pm.damping_min = 1.2
 pm.damping_max = 2.4
 pm.scale_min = 0.8
 pm.scale_max = 1.6
 var sc = Curve.new()
 sc.add_point(Vector2(0,0.35))
 sc.add_point(Vector2(0.3,0.9))
 sc.add_point(Vector2(1,1.6))
 var st = CurveTexture.new()
 st.curve = sc
 pm.scale_curve = st
 pm.angle_min = -180.0
 pm.angle_max = 180.0
 pm.angular_velocity_min = -12.0
 pm.angular_velocity_max = 12.0
 var g = Gradient.new()
 g.set_color(0,Color(col.r,col.g,col.b,0.0))
 g.add_point(0.08,col)
 g.add_point(0.6,Color(col.r,col.g,col.b,col.a*0.6))
 g.set_color(g.get_point_count()-1,Color(col.r*1.05,col.g*1.05,col.b*1.05,0.0))
 var gt = GradientTexture1D.new()
 gt.gradient = g
 pm.color_ramp = gt
 _particles(pos,amount,life,dust_mat,_quad(clampf(r*0.5,2.0,10.0)),pm)

# Stone chips or wood splinters thrown out from an impact (they bounce on the ground).
func chips(pos: Vector3,dir: Vector3,amount: int,col: Color,speed := 14.0,spread := 60.0,wood := false):
 amount = mini(amount,48)
 var pm = ParticleProcessMaterial.new()
 pm.direction = (dir+Vector3(0,0.5,0)).normalized()
 pm.spread = spread
 pm.initial_velocity_min = speed*0.4
 pm.initial_velocity_max = speed
 pm.gravity = Vector3(0,-22,0)
 pm.angular_velocity_min = -600.0
 pm.angular_velocity_max = 600.0
 pm.scale_min = 0.6
 pm.scale_max = 2.4
 pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
 pm.collision_bounce = 0.25
 pm.collision_friction = 0.6
 pm.color = col
 var m = StandardMaterial3D.new()
 m.albedo_color = col
 m.roughness = 0.9
 var p = _particles(pos,amount,3.5,m,splinter_mesh if wood else chip_mesh,pm)
 p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func embers(pos: Vector3,r: float,amount: int,life := 4.0):
 var pm = ParticleProcessMaterial.new()
 pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
 pm.emission_sphere_radius = r
 pm.direction = Vector3(0,1,0)
 pm.spread = 50.0
 pm.initial_velocity_min = 2.0
 pm.initial_velocity_max = 9.0
 pm.gravity = Vector3(0,1.5,0)
 pm.turbulence_enabled = true
 pm.turbulence_noise_strength = 2.0
 pm.scale_min = 0.6
 pm.scale_max = 1.4
 var g = Gradient.new()
 g.set_color(0,Color(1.0,0.8,0.4,1.0))
 g.set_color(1,Color(1.0,0.3,0.05,0.0))
 var gt = GradientTexture1D.new()
 gt.gradient = g
 pm.color_ramp = gt
 _particles(pos,amount,life,ember_mat,_quad(0.18),pm).explosiveness = 0.5

# A fire burning in a ruin for `secs` seconds (flames, smoke above).
func fire(pos: Vector3,size: float,secs: float):
 var pm = ParticleProcessMaterial.new()
 pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
 pm.emission_sphere_radius = size*0.6
 pm.direction = Vector3(0,1,0)
 pm.spread = 15.0
 pm.initial_velocity_min = 1.5
 pm.initial_velocity_max = 3.5
 pm.gravity = Vector3(0,2.0,0)
 pm.scale_min = 0.7
 pm.scale_max = 1.3
 var sc = Curve.new()
 sc.add_point(Vector2(0,0.6))
 sc.add_point(Vector2(0.4,1.0))
 sc.add_point(Vector2(1,0.1))
 var st = CurveTexture.new()
 st.curve = sc
 pm.scale_curve = st
 var g = Gradient.new()
 g.set_color(0,Color(1.0,0.75,0.35,0.0))
 g.add_point(0.15,Color(1.0,0.6,0.2,0.9))
 g.set_color(g.get_point_count()-1,Color(0.6,0.15,0.05,0.0))
 var gt = GradientTexture1D.new()
 gt.gradient = g
 pm.color_ramp = gt
 var f = _particles(pos,int(28*size),1.2,fire_mat,_quad(size*1.4),pm,false)
 _later(f,secs)
 var light = OmniLight3D.new()
 light.light_color = Color(1.0,0.55,0.25)
 light.light_energy = 2.5*size
 light.omni_range = 9.0*size
 light.shadow_enabled = false
 add_child(light)
 light.global_position = pos+Vector3(0,size,0)
 _later(light,secs)
 smoke(pos+Vector3(0,size*1.5,0),size,secs,Color(0.2,0.19,0.18,0.55))

# A steady column of smoke or steam.
func smoke(pos: Vector3,size: float,secs: float,col := Color(0.55,0.55,0.56,0.35),rate := 10) -> GPUParticles3D:
 var pm = ParticleProcessMaterial.new()
 pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
 pm.emission_sphere_radius = size*0.3
 pm.direction = Vector3(0.25,1,0.1)
 pm.spread = 12.0
 pm.initial_velocity_min = 1.2
 pm.initial_velocity_max = 2.4
 pm.gravity = Vector3(0.6,0.5,0.2)
 pm.damping_min = 0.2
 pm.damping_max = 0.5
 var sc = Curve.new()
 sc.add_point(Vector2(0,0.4))
 sc.add_point(Vector2(1,2.2))
 var st = CurveTexture.new()
 st.curve = sc
 pm.scale_curve = st
 pm.angle_min = -180.0
 pm.angle_max = 180.0
 var g = Gradient.new()
 g.set_color(0,Color(col.r,col.g,col.b,0.0))
 g.add_point(0.15,col)
 g.set_color(g.get_point_count()-1,Color(col.r,col.g,col.b,0.0))
 var gt = GradientTexture1D.new()
 gt.gradient = g
 pm.color_ramp = gt
 var p = _particles(pos,rate,7.0,dust_mat,_quad(size*1.6),pm,false)
 if secs>0.0: _later(p,secs)
 return p

# An expanding ring on the ground (shockwave) or across the flight path (sonic boom).
func ring(pos: Vector3,r0: float,r1: float,dur: float,normal := Vector3.UP,thickness := 1.0,strength := 1.0):
 var mi = MeshInstance3D.new()
 var tm = TorusMesh.new()
 tm.inner_radius = 0.82
 tm.outer_radius = 1.0
 tm.rings = 48
 tm.ring_segments = 8
 mi.mesh = tm
 mi.material_override = ring_mat
 mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(mi)
 mi.global_position = pos
 if normal.normalized().abs() != Vector3.UP:
  mi.global_basis = Basis(Quaternion(Vector3.UP,normal.normalized()))
 mi.set_instance_shader_parameter("strength",strength)
 mi.set_instance_shader_parameter("fade",1.0)
 rings.append({"node":mi,"t":0.0,"dur":dur,"r0":r0,"r1":r1,"hs":thickness,"vertical":normal.normalized().abs() != Vector3.UP})

func flash(pos: Vector3,energy: float,range: float,secs := 0.18):
 var l = OmniLight3D.new()
 l.light_color = Color(1.0,0.86,0.66)
 l.light_energy = energy
 l.omni_range = range
 add_child(l)
 l.global_position = pos
 var tw = create_tween()
 tw.tween_property(l,"light_energy",0.0,secs)
 _later(l,secs+0.1)

# A crater (scorched dish with radial cracks) or a landing crack, projected onto ground and ruins.
func crater(pos: Vector3,r: float,cracks_only := false):
 var d = Decal.new()
 d.size = Vector3(r*2.0,maxf(6.0,r*0.8),r*2.0)
 d.texture_albedo = crack_tex if cracks_only else crater_tex
 if not cracks_only: d.texture_normal = crater_n
 d.albedo_mix = 1.0
 d.normal_fade = 0.3
 d.cull_mask = 1
 add_child(d)
 d.global_position = pos
 d.rotation.y = rng.randf()*TAU
 decals.append(d)
 if decals.size()>MAX_DECALS:
  decals[0].queue_free()
  decals.remove_at(0)

# Dust swirling in toward the god while a punch charges (on while `on`).
func charge_swirl(pos: Vector3,on: bool,amount: float):
 if swirl == null:
  var pm = ParticleProcessMaterial.new()
  pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
  pm.emission_ring_axis = Vector3.UP
  pm.emission_ring_radius = 7.0
  pm.emission_ring_inner_radius = 3.0
  pm.emission_ring_height = 0.5
  pm.orbit_velocity_min = 0.35
  pm.orbit_velocity_max = 0.6
  pm.radial_velocity_min = -5.0
  pm.radial_velocity_max = -2.5
  pm.direction = Vector3(0,1,0)
  pm.spread = 20.0
  pm.initial_velocity_min = 0.5
  pm.initial_velocity_max = 2.5
  pm.gravity = Vector3(0,1.2,0)
  pm.scale_min = 0.6
  pm.scale_max = 1.2
  var g = Gradient.new()
  g.set_color(0,Color(0.7,0.66,0.6,0.0))
  g.add_point(0.3,Color(0.7,0.66,0.6,0.5))
  g.set_color(g.get_point_count()-1,Color(0.7,0.66,0.6,0.0))
  var gt = GradientTexture1D.new()
  gt.gradient = g
  pm.color_ramp = gt
  swirl = _particles(pos,90,1.6,dust_mat,_quad(2.4),pm,false)
 swirl.global_position = pos
 swirl.emitting = on
 swirl.amount_ratio = clampf(amount,0.1,1.0)

func clear():
 for d in decals: d.queue_free()
 decals.clear()
 for t in timed: if is_instance_valid(t[0]): t[0].queue_free()
 timed.clear()
 for r in rings: r.node.queue_free()
 rings.clear()

# Each kind of effect once, out of sight, at start: their particle shaders compile now rather than on
# the frame of the first punch.
func prewarm():
 var p = Vector3(0,-3000,0)
 dust(p,2.0,4,0.5)
 chips(p,Vector3.UP,4,Color.GRAY)
 chips(p,Vector3.UP,4,Color.BROWN,10.0,60.0,true)
 embers(p,1.0,4,0.5)
 fire(p,1.0,0.5)
 smoke(p,1.0,0.5)
 # The rings read the screen texture: draw one where the camera sees it, so that pass starts now.
 var cam = get_viewport().get_camera_3d()
 if cam != null:
  var front = cam.global_position-cam.global_transform.basis.z*6.0
  ring(front,0.1,0.2,0.2,Vector3.UP,0.01,0.0)
  # Decals (their textures go into the decal atlas on first use) and a light, in view, invisible.
  for cracks in [false,true]:
   crater(front,0.5,cracks)
   decals[-1].albedo_mix = 0.0
   decals[-1].modulate = Color(1,1,1,0)
  flash(front,0.001,0.5,0.05)
 flash(p,1.0,1.0,0.1)
 charge_swirl(p,false,0.0)
