extends Node3D
# Goldspire Rock (docs/world-bible-v2.md landmark, the Aurekids), rebuilt to the owner's playtest
# notes (2026-10-06) after docs/reference/landmarks/goldspire rock.jpg (palette and style; never its
# layout): a sheer golden sea-cliff, not a cone. Its sea face drops vertically to the water; the
# castle is carved INTO that face: tiered colonnaded halls with balconies, carved gateways,
# stairways climbing the cliff, towers emerging from the stone, glowing mine mouths and a giant
# statue cut beside the great gate. Gold-roofed spires crown the summit; the white Greek city with
# red roofs lies at its foot, with a theatre, the harbour, a breakwater and lighthouses below.
# Stage 1: the cliff, the great gate, mine mouths, one summit spire, a few houses at the foot.
# Stage 2: the lower tiers of halls and balconies, a stairway, the harbour and walls, more city.
# Stage 3: every tier, the towers, the statue, the summit spires, the theatre, the whole city.
# Local space: origin at sea level under the cliff's centre, +z faces the sea (map/map_view.gd turns
# the node toward the nearest water and passes a height lookup in this local space to build()).

const ProtoKit = preload("res://visuals/common/proto_kit.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const S = preload("res://visuals/kits/cultures/kit_shapes.gd")
const A = 22.0 # half length of the cliff along the coast
const B = 13.0 # half depth, land to sea
const H = 38.0 # summit height
const BASE = -4.0
const SEGMENTS = 64
const RINGS = 26
const TIERS = [4.5,9.5,14.5,19.5,24.5,29.5] # heights of the carved tiers on the sea face
const ROCK = Color("cf9e48")
const ROCK_DARK = Color("8c6230")
const MARBLE = Color("f4f0e4")
const ROOF = Color("b8573a")
const GOLD = Color("e6b440")
const GLOW = Color("ffa030")
const VOID = Color("231912")

@export_range(1,3) var stage := 1
var features: Array = []
var _height: Callable
var noise = FastNoiseLite.new()

func build(ctx: Dictionary):
 _height = ctx.get("height",func(_x,_z): return 0.0)
 noise.seed = 2002
 noise.frequency = 1.0
 _build_rock()
 _build_gate()
 _build_mines()
 _build_summit()
 _build_city()
 if stage>=2:
  _build_tiers(2 if stage == 2 else TIERS.size())
  _build_stairs(1 if stage == 2 else 3)
  _build_harbor()
  _build_walls()
 if stage>=3:
  _build_towers()
  _build_statue()
  _build_theatre()
 set_meta("stage",stage)
 set_meta("features",features)
 ProtoKit.shared().batch(self)

# --- The cliff: a broad golden massif, vertical toward the sea, sloping back toward the land -----

# How much of angle t faces the sea (1 at the sea face, 0 on the land side).
func _seaward(t: float) -> float:
 return smoothstep(-0.25,0.55,sin(t))

# The cliff's top height at angle t: a craggy skyline, highest behind the sea face.
func _top(t: float) -> float:
 return H*(0.84+0.1*sin(t))+6.0*noise.get_noise_2d(t*4.0,7.0)+2.5*noise.get_noise_2d(t*11.0,3.0)

# Buttresses and ravines around the cliff (1 on a buttress, 0 deep in a ravine).
func _buttress(t: float,y: float) -> float:
 var r = 1.0-absf(0.7*noise.get_noise_2d(t*2.4,y*0.01)+0.3*noise.get_noise_2d(t*7.5,y*0.03))
 return clampf(pow(r,2.2),0.0,1.0)

# Radius of the massif at angle t (0 = +x, PI/2 = +z, the sea) and height y.
func _radius(t: float,y: float) -> float:
 var u = clampf(y/maxf(1.0,_top(t)),0.0,1.0)
 # A blocky plan (superellipse), long along the coast.
 var c = absf(cos(t))
 var s = absf(sin(t))
 var base = 1.0/pow(pow(c/A,3.0)+pow(s/B,3.0),1.0/3.0)
 # The sea face is sheer (barely leaning back); the land side slopes down to the hills.
 var land = 1.0-0.5*pow(u,1.15)
 var sea = 1.0-0.06*u
 var taper = lerpf(land,sea,_seaward(t))-0.06*smoothstep(0.88,1.0,u)
 # Buttresses standing out and ravines cut back, strata ledges, fine vertical flutes.
 var rib = 0.76+0.32*_buttress(t,y)
 # Scree flaring out at the foot of the cliff.
 var scree = 1.0+0.14*(1.0-smoothstep(0.0,0.14,u))
 var strata = 1.0+0.018*smoothstep(0.7,1.0,sin(y*0.55))
 var flutes = 1.0+0.03*noise.get_noise_2d(t*26.0,y*0.05)
 return base*taper*rib*strata*flutes*scree

func _point(t: float,y: float,out := 0.0) -> Vector3:
 var r = _radius(t,y)+out
 return Vector3(cos(t)*r,y,sin(t)*r)

func _normal_at(t: float) -> Vector3:
 return Vector3(cos(t)*B,0,sin(t)*A).normalized()

func _build_rock():
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rings = []
 var shades = []
 for k in RINGS+1:
  var ring = []
  var sh = []
  for i in SEGMENTS:
   var t = i*TAU/SEGMENTS
   var y = lerpf(BASE,_top(t),float(k)/RINGS)
   ring.append(_point(t,y))
   sh.append(_buttress(t,y))
  rings.append(ring)
  shades.append(sh)
 for k in RINGS:
  for i in SEGMENTS:
   var j = (i+1)%SEGMENTS
   var a = rings[k][i]
   var b = rings[k][j]
   var c = rings[k+1][j]
   var d = rings[k+1][i]
   # Golden stone: shadowed ravines, lit buttresses, pale strata bands.
   var lit = (shades[k][i]+shades[k+1][j])*0.5
   var band = 0.12*smoothstep(0.75,1.0,sin(a.y*0.55))
   var sun = clampf(a.y/H,0.0,1.0)*0.25
   var col = ROCK_DARK.lerp(ROCK,clampf(0.15+lit*0.85+band+sun,0.0,1.0)).lerp(ROCK.lightened(0.15),band)
   for tri in [[a,b,c],[a,c,d]]:
    var n = (tri[1]-tri[0]).cross(tri[2]-tri[0]).normalized()
    for v in tri:
     st.set_color(col)
     st.set_normal(-n)
     st.add_vertex(v)
 # The summit: a rough plateau.
 var top = Vector3(0,H+1.0,0)
 for i in SEGMENTS:
  var a = rings[RINGS][i]
  var b = rings[RINGS][(i+1)%SEGMENTS]
  for v in [a,top,b]:
   st.set_color(ROCK.lightened(0.05))
   st.set_normal(Vector3.UP)
   st.add_vertex(v)
 var m = StandardMaterial3D.new()
 m.vertex_color_use_as_albedo = true
 m.vertex_color_is_srgb = true # the rock colours are sRGB
 m.roughness = 0.95
 var mi = MeshInstance3D.new()
 mi.name = "Rock"
 mi.mesh = st.commit()
 mi.material_override = m
 add_child(mi)
 features.append("cliff")

# A frame on the cliff face at angle t and height y, `out` metres proud of the surface, facing out.
func _on_face(t: float,y: float,out := 0.0) -> Transform3D:
 var p = _point(t,y,out)
 var n = _normal_at(t)
 return Transform3D(Basis.looking_at(-n,Vector3.UP),p)

func _node(xf: Transform3D) -> Node3D:
 var root = Node3D.new()
 add_child(root)
 root.transform = xf
 return root

func _piece(id: String,xf: Transform3D,sc := 1.0) -> Node3D:
 var n = AssetManifest.instantiate(id)
 add_child(n)
 n.transform = xf.scaled_local(Vector3.ONE*sc)
 return n

# --- The great gate at the foot of the sea face ----------------------------------------------------

func _build_gate():
 # A tall carved gateway: a dark arch sunk into the rock, framed by columns and a pediment.
 var root = _node(_on_face(PI*0.5,0.6,-0.4))
 S.box(root,Vector3(9.0,9.5,1.2),Vector3(0,0,0.2),MARBLE.darkened(0.04))
 S.box(root,Vector3(4.2,6.8,0.4),Vector3(0,0,0.85),VOID)
 S.cylinder(root,2.1,2.1,0.4,Vector3(0,6.8,0.85),VOID,12,Vector3(PI*0.5,0,0))
 S.colonnade(root,-4.0,4.0,1.0,6,8.2,0.32,MARBLE.lightened(0.3),0.0)
 S.gable(root,9.6,2.0,2.2,Vector3(0,9.5,0.4),MARBLE)
 S.box(root,Vector3(2.0,1.4,0.1),Vector3(0,2.0,1.06),GLOW,Vector3.ZERO,1.8)
 # Broad steps from the quay up to the gate.
 for i in 5: S.box(root,Vector3(10.0-i*0.8,0.5,1.6),Vector3(0,-0.5+i*0.0,1.6+i*-0.0+(4-i)*1.1),MARBLE.darkened(0.1))
 features.append("gate")

# --- Mines glowing inside the rock ---------------------------------------------------------------

const MINES = [[0.35,2.0,1],[2.75,2.4,1],[0.15,9.0,1],[2.95,12.0,2],[1.05,15.0,2],[2.15,21.0,3],[0.75,27.0,3],[2.45,28.0,3]]

func _build_mines():
 var count = 0
 for m in MINES:
  if m[2]>stage: continue
  var root = _node(_on_face(m[0],m[1],-0.3))
  S.box(root,Vector3(2.4,3.0,0.8),Vector3.ZERO,VOID)
  S.box(root,Vector3(1.8,2.3,0.2),Vector3(0,0,0.32),GLOW,Vector3.ZERO,2.4)
  S.box(root,Vector3(3.0,0.5,0.9),Vector3(0,3.0,0),ROCK_DARK)
  count += 1
 features.append("mines:%d" % count)

# --- Carved tiers: halls sunk into the face, balconies in front ---------------------------------

# A hall carved into the cliff: dark interior sunk into the rock, a marble colonnade flush with the
# face, a red pediment above and a balcony slab with a balustrade in front.
func _hall(t: float,y: float,w: float,tall: float):
 var root = _node(_on_face(t,y,0.0))
 S.box(root,Vector3(w,tall,1.6),Vector3(0,0,-0.9),VOID)
 S.colonnade(root,-w*0.44,w*0.44,0.1,maxi(3,int(w/1.3)),tall*0.92,0.24,MARBLE.lightened(0.3),0.0)
 S.box(root,Vector3(w+0.6,0.55,0.9),Vector3(0,tall*0.92,0.05),MARBLE)
 S.gable(root,w+0.4,1.4,1.1,Vector3(0,tall*0.92+0.55,-0.1),ROOF)
 # Balcony: a slab out from the face with a low balustrade.
 S.box(root,Vector3(w+1.2,0.5,2.6),Vector3(0,-0.5,1.2),MARBLE.darkened(0.06))
 S.box(root,Vector3(w+1.2,0.7,0.25),Vector3(0,0.0,2.4),MARBLE)

func _build_tiers(count: int):
 for k in count:
  var y = TIERS[k]
  # Many smaller halls along each tier, uneven, with bare cliff between them (the reference's dense
  # carved front), narrowing toward the top.
  var n = 7-k/2
  var spread = 1.05-k*0.07
  for i in n:
   var u = (i-(n-1)*0.5)/maxf(1.0,(n-1)*0.5)
   var t = PI*0.5+u*spread+sin(k*2.3+i*1.7)*0.04
   if absf(u)<0.12 and k<1: continue # the great gate stands here
   _hall(t,y+sin(i*3.1+k)*0.4,2.6+fmod(k*1.3+i*0.7,1.0)*1.6,3.4-k*0.15)
 features.append("tiers:%d" % count)

# Stairways climbing the face between the tiers: flights of steps hugging the rock.
func _build_stairs(count: int):
 for f in count:
  var y0 = 0.8 if f == 0 else TIERS[f-1]
  var y1 = TIERS[f]
  var t0 = PI*0.5+(0.75 if f%2 == 0 else -0.75)
  var t1 = PI*0.5+(0.35 if f%2 == 0 else -0.35)
  var steps = int((y1-y0)/0.7)
  for i in steps:
   var u = float(i)/steps
   var root = _node(_on_face(lerpf(t0,t1,u),lerpf(y0,y1,u),0.9))
   S.box(root,Vector3(2.2,0.7,1.6),Vector3.ZERO,MARBLE.darkened(0.12))
 features.append("stairs:%d" % count)

# Round towers emerging from the stone between the halls, gold-roofed.
func _build_towers():
 for k in [1,2,3]:
  for s in [-1.0,1.0]:
   var t = PI*0.5+s*(1.05-k*0.12)
   var root = _node(_on_face(t,TIERS[k]-2.0,-0.6))
   S.cylinder(root,1.5,1.7,8.0-k,Vector3.ZERO,MARBLE,12)
   S.box(root,Vector3(3.6,0.4,3.6),Vector3(0,8.0-k,0),MARBLE.darkened(0.08))
   S.cylinder(root,0.0,1.9,4.2,Vector3(0,8.4-k,0),GOLD,12)
 features.append("towers")

# --- Summit spires ---------------------------------------------------------------------------------

func _gold_spire(xf: Transform3D,h: float,r: float):
 var root = _node(xf)
 S.cylinder(root,r,r*1.1,h,Vector3.ZERO,MARBLE,12)
 S.box(root,Vector3(r*2.4,0.4,r*2.4),Vector3(0,h,0),MARBLE.darkened(0.08))
 S.cylinder(root,0.0,r*1.2,h*0.7,Vector3(0,h+0.4,0),GOLD,12)

func _build_summit():
 _gold_spire(Transform3D(Basis(),Vector3(0,H+0.8,0)),7.0 if stage == 1 else 9.0,1.4)
 features.append("summit_spire")
 if stage>=2:
  for i in 4:
   var t = PI*0.5+(i-1.5)*0.7
   _gold_spire(Transform3D(Basis(),_point(t,H-1.0,-2.5)),5.5-absf(i-1.5),1.0)
  # A marble palace on the summit plateau behind the spires.
  var root = _node(Transform3D(Basis(),Vector3(0,H+0.6,-4.0)))
  S.box(root,Vector3(14.0,4.0,7.0),Vector3.ZERO,MARBLE)
  S.colonnade(root,-6.5,6.5,3.6,10,3.6,0.25,MARBLE.lightened(0.3),0.0)
  S.gable(root,14.4,7.4,1.8,Vector3(0,4.0,0),GOLD)
  # A ring of marble halls and towers along the summit's rim, the palace behind the spires.
  for i in 9:
   var t = PI*0.5+(i-4)*0.55
   var p = _point(t,_top(t)-0.5,-3.0)
   var root2 = _node(Transform3D(Basis(Vector3.UP,-t+PI*0.5),p))
   S.box(root2,Vector3(4.5,3.2,3.5),Vector3.ZERO,MARBLE)
   S.hip(root2,4.9,3.9,1.2,Vector3(0,3.2,0),ROOF if i%2 == 0 else GOLD)
 if stage>=3: features.append("goldspire")

# --- The colossus cut beside the gate ---------------------------------------------------------------

func _build_statue():
 # A niche cut into the face and a robed figure with a torch standing in it, about half the cliff.
 var root = _node(_on_face(PI*0.5+0.42,0.4,-0.2))
 var stone = ROCK.lightened(0.1)
 S.box(root,Vector3(7.0,21.0,1.4),Vector3(0,0,-0.4),VOID.lightened(0.05)) # the niche
 S.box(root,Vector3(4.6,1.6,3.0),Vector3(0,0,0.6),stone.darkened(0.15)) # plinth
 S.cylinder(root,1.4,2.2,9.5,Vector3(0,1.6,0.7),stone,10) # robe
 S.cylinder(root,1.2,1.35,4.0,Vector3(0,11.1,0.7),stone,10) # chest
 S.dome(root,1.1,Vector3(0,15.1,0.7),stone,1.3) # head
 S.box(root,Vector3(0.45,13.0,0.45),Vector3(2.2,2.6,1.3),stone.darkened(0.1)) # staff
 S.cone(root,0.8,1.6,Vector3(2.2,15.6,1.3),GLOW) # the torch
 S.box(root,Vector3(0.5,0.5,0.5),Vector3(2.2,16.0,1.3),GLOW,Vector3.ZERO,3.0)
 features.append("statue")

# --- The city at the foot ---------------------------------------------------------------------------

func _land(p: Vector2) -> bool:
 return float(_height.call(p.x,p.y))>0.35

func _ground(p: Vector2) -> float:
 return float(_height.call(p.x,p.y))

func _build_city():
 var rng = RandomNumberGenerator.new()
 rng.seed = 2002
 var want = [14,40,76][stage-1]
 var placed = []
 var tries = 0
 while placed.size()<want and tries<want*30:
  tries += 1
  # Along the foot on both flanks and the shore strip, spreading wider with each stage.
  var t = PI*0.5+rng.randf_range(-1.0,1.0)*(1.2+stage*0.3)
  var d = rng.randf_range(2.0,5.0+stage*4.0)
  var c = _point(t,1.0,d)
  var p = Vector2(c.x,c.z)
  if not _land(p): continue
  var ok = true
  for q in placed:
   if q.distance_to(p)<3.0:
    ok = false
    break
  if not ok: continue
  placed.append(p)
  var id = ["kit.greek.house_1","kit.greek.house_2","kit.greek.house_3"][rng.randi_range(0,2)]
  if rng.randf()<0.12: id = "kit.greek.tall"
  var n = AssetManifest.instantiate(id)
  add_child(n)
  n.position = Vector3(p.x,_ground(p)-0.15,p.y)
  n.rotation.y = rng.randf()*TAU
  # Red roofs, as in the reference: a tile cap on the flat Greek roof.
  S.box(n,Vector3(2.4,0.35,2.0),Vector3(0,2.1 if id != "kit.greek.tall" else 3.7,0),ROOF)
 if stage>=2:
  var temple_at = _point(PI*0.5-1.15,1.0,7.0)
  if _land(Vector2(temple_at.x,temple_at.z)): _piece("kit.greek.temple",Transform3D(Basis(Vector3.UP,0.4),Vector3(temple_at.x,_ground(Vector2(temple_at.x,temple_at.z)),temple_at.z)),0.9)
 features.append("greek_city")

func _build_theatre():
 # A semicircle of stepped seats cut into the slope on the land side of the city.
 var c3 = _point(PI*0.5+1.45,0.5,9.0)
 var c = Vector2(c3.x,c3.z)
 var root = Node3D.new()
 add_child(root)
 root.position = Vector3(c.x,_ground(c),c.y)
 root.rotation.y = -(PI*0.5+1.45)
 for row in 6:
  var r = 3.5+row*1.2
  for i in 13:
   var a = PI*(0.1+0.8*i/12.0)
   S.box(root,Vector3(1.3,0.5+row*0.45,0.9),Vector3(cos(a)*r,0,-sin(a)*r),MARBLE.darkened(0.05*row),Vector3(0,a,0))
 features.append("theatre")

# --- Harbour and walls --------------------------------------------------------------------------------

func _build_harbor():
 # A curved breakwater out to sea with a lighthouse at each head, quays below the cliff and ships.
 var root = Node3D.new()
 add_child(root)
 var front = B+10.0
 for i in 19:
  var a = lerpf(-1.0,1.0,i/18.0)
  var p = Vector3(a*17.0,-0.6,front+5.0*(1.0-a*a))
  S.box(root,Vector3(2.4,1.8,2.0),p,Color("a89a80"),Vector3(0,-a*0.6,0))
 for s in [-1.0,1.0]:
  var p = Vector3(s*17.2,1.1,front)
  S.cylinder(root,0.8,1.0,6.0,p,MARBLE,10)
  S.box(root,Vector3(1.2,1.0,1.2),p+Vector3(0,6.0,0),GLOW,Vector3.ZERO,2.5)
  S.cone(root,0.9,1.2,p+Vector3(0,7.0,0),GOLD,10)
 for i in 6:
  var p = Vector3(-10.0+i*4.0,-0.4,B+3.0)
  S.box(root,Vector3(3.2,0.6,4.0),p,Color("8a6e48"))
 for i in 7:
  var p = Vector3(-12.0+i*4.0,0.0,front-3.0+(i%2)*1.5)
  S.box(root,Vector3(0.9,0.6,3.2),p,Color("6a4a2a"))
  S.box(root,Vector3(0.12,3.0,0.12),p+Vector3(0,0.6,0),Color("5a4028"))
  S.box(root,Vector3(1.6,1.4,0.05),p+Vector3(0,1.6,0.1),Color("f0e6d0"))
 features.append("harbor")

func _build_walls():
 # City walls from the cliff's flanks down to the sea, with square towers and crenellations.
 for s in [-1.0,1.0]:
  var from = _point(PI*0.5+s*1.4,1.0,0.0)
  var to = from+Vector3(s*5.0,0,11.0+stage*2.0)
  var n = int(from.distance_to(to)/3.0)
  for i in n+1:
   var p = from.lerp(to,float(i)/n)
   var pp = Vector2(p.x,p.z)
   if not _land(pp): continue
   var root = Node3D.new()
   add_child(root)
   root.position = Vector3(p.x,_ground(pp)-0.2,p.z)
   root.rotation.y = atan2(to.x-from.x,to.z-from.z)+PI*0.5
   if i%3 == 0:
    S.box(root,Vector3(2.8,6.0,2.8),Vector3.ZERO,MARBLE.darkened(0.06))
    for c in 4: S.box(root,Vector3(0.7,0.6,0.7),Vector3(cos(c*PI*0.5+0.785)*1.1,6.0,sin(c*PI*0.5+0.785)*1.1),MARBLE.darkened(0.1))
   else:
    S.box(root,Vector3(3.1,4.0,1.4),Vector3.ZERO,MARBLE.darkened(0.1))
    for c in 3: S.box(root,Vector3(0.6,0.6,1.4),Vector3(-1.1+c*1.1,4.0,0),MARBLE.darkened(0.12))
 features.append("walls")
