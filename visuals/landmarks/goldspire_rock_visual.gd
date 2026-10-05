extends Node3D
# Goldspire Rock (docs/world-bible-v2.md landmark, House Aurek), redesigned to the owner's brief
# (2026-10-04) and docs/reference/landmarks/goldspire rock.jpg (palette and style; never its
# layout): a towering golden rock whose castle is carved INTO it, with colonnaded halls and gold-roofed
# towers emerging from the cliff on its ledges, mines glowing inside it, and a colossal statue cut into
# its face; the white Greek city with red roofs at its foot, a theatre, and the harbour below, with a
# breakwater and lighthouses.
# Stage 1: mine mouths, a summit tower, a few houses at the foot.
# Stage 2: carved halls on the lower ledges, a harbour and the city walls; more of the city.
# Stage 3: halls and towers on every ledge, the statue, the theatre, the whole city.
# Local space: origin at sea level under the rock's centre, +z faces the sea. The owner positions
# the node on the coast, adds it to the tree, then calls build().

const ProtoKit = preload("res://visuals/common/proto_kit.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const S = preload("res://visuals/kits/cultures/kit_shapes.gd")
const A = 13.0 # half length of the rock along the coast
const B = 10.0 # half depth, land to sea
const H = 30.0 # summit height
const BASE = -4.0
const SEGMENTS = 48
const RINGS = 22
const LEDGES = [6.0,12.5,19.0,24.5]
const ROCK = Color("c99a4a")
const ROCK_DARK = Color("8a6232")
const MARBLE = Color("f4f0e4")
const ROOF = Color("b8573a")
const GOLD = Color("e0b040")
const GLOW = Color("ffa030")

@export_range(1,3) var stage := 1
var features: Array = []
var _height: Callable
var noise = FastNoiseLite.new()

func build(ctx: Dictionary):
 _height = ctx.get("height",func(_x,_z): return 0.0)
 noise.seed = 2002
 noise.frequency = 1.0
 _build_rock()
 _build_mines()
 _build_summit()
 _build_city()
 if stage>=2:
  _build_halls(2 if stage == 2 else LEDGES.size())
  _build_harbor()
  _build_walls()
 if stage>=3:
  _build_terraces()
  _build_statue()
  _build_theatre()
 set_meta("stage",stage)
 set_meta("features",features)
 ProtoKit.shared().batch(self)

# --- The rock: a spire of vertical golden folds -----------------------------------------------------

# Radius of the rock at angle t (0 = +x, PI/2 = +z, the sea) and height y.
func _radius(t: float,y: float) -> float:
 var u = clampf(y/H,0.0,1.0)
 var base = Vector2(cos(t)*A,sin(t)*B).length()
 # Taper toward a narrow summit; the sea face is steeper (less taper at mid heights).
 var taper = 1.0-0.62*pow(u,1.25)-0.08*smoothstep(0.6,1.0,u)
 # Vertical folds: noise that varies around the rock and slowly up it.
 var folds = 1.0+0.2*noise.get_noise_2d(cos(t)*3.2+sin(t)*1.7,y*0.06)+0.09*noise.get_noise_2d(t*7.0,y*0.22)+0.05*noise.get_noise_2d(t*15.0,y*0.6)
 return base*taper*folds

func _point(t: float,y: float,out := 0.0) -> Vector3:
 var r = _radius(t,y)+out
 return Vector3(cos(t)*r,y,sin(t)*r)

func _normal_at(t: float) -> Vector3:
 return Vector3(cos(t)*B,0,sin(t)*A).normalized()

func _build_rock():
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rings = []
 for k in RINGS+1:
  var y = lerpf(BASE,H,float(k)/RINGS)
  var ring = []
  for i in SEGMENTS: ring.append(_point(i*TAU/SEGMENTS,y))
  rings.append(ring)
 for k in RINGS:
  for i in SEGMENTS:
   var a = rings[k][i]
   var b = rings[k][(i+1)%SEGMENTS]
   var c = rings[k+1][(i+1)%SEGMENTS]
   var d = rings[k+1][i]
   var shade = 0.82+0.3*noise.get_noise_2d(i*0.9,k*0.35)
   var col = ROCK.lerp(ROCK_DARK,clampf(0.55-shade*0.5+0.25*sin(i*1.7),0.0,0.8))
   for tri in [[a,b,c],[a,c,d]]:
    var n = (tri[1]-tri[0]).cross(tri[2]-tri[0]).normalized()
    for v in tri:
     st.set_color(col)
     st.set_normal(-n)
     st.add_vertex(v)
 # The summit cap.
 var top = Vector3(0,H+0.6,0)
 for i in SEGMENTS:
  var a = rings[RINGS][i]
  var b = rings[RINGS][(i+1)%SEGMENTS]
  for v in [a,top,b]:
   st.set_color(ROCK)
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
 features.append("rock")

# A spot on the rock face at angle t and height y, a little proud of the surface, facing out.
func _on_face(t: float,y: float,out := 0.4) -> Transform3D:
 var p = _point(t,y,out)
 var n = _normal_at(t)
 return Transform3D(Basis.looking_at(-n,Vector3.UP),p)

func _piece(id: String,xf: Transform3D,sc := 1.0) -> Node3D:
 var n = AssetManifest.instantiate(id)
 add_child(n)
 n.transform = xf.scaled_local(Vector3.ONE*sc)
 return n

# --- Mines glowing inside the rock ---------------------------------------------------------------

const MINES = [[1.2,1.2,1],[2.0,1.4,1],[0.4,6.4,1],[2.7,8.0,1],[1.55,13.0,2],[0.8,16.5,2],[2.3,14.0,3],[0.55,21.0,3],[1.9,22.5,3]]

func _build_mines():
 var count = 0
 for m in MINES:
  if m[2]>stage: continue
  var xf = _on_face(m[0],m[1],-0.2)
  var root = Node3D.new()
  add_child(root)
  root.transform = xf
  S.box(root,Vector3(1.6,2.2,0.6),Vector3(0,0,0),Color("1c140c"))
  S.box(root,Vector3(1.2,1.7,0.2),Vector3(0,0,0.25),GLOW,Vector3.ZERO,2.2)
  S.box(root,Vector3(2.2,0.35,0.7),Vector3(0,2.2,0),ROCK_DARK)
  count += 1
 features.append("mines:%d" % count)

# --- Summit ---------------------------------------------------------------------------------------

func _gold_tower(root_xf: Transform3D,h: float,r: float):
 var root = Node3D.new()
 add_child(root)
 root.transform = root_xf
 S.cylinder(root,r,r*1.08,h,Vector3.ZERO,MARBLE,10)
 S.box(root,Vector3(r*2.3,0.3,r*2.3),Vector3(0,h,0),MARBLE.darkened(0.08))
 S.cylinder(root,0.0,r*1.15,h*0.6,Vector3(0,h+0.3,0),GOLD,10)

func _build_summit():
 _gold_tower(Transform3D(Basis(),Vector3(0,H+0.4,0)),5.0 if stage == 1 else 6.5,1.0)
 features.append("summit_tower")
 if stage>=2:
  for i in 3:
   var t = PI*0.5+(i-1)*0.9
   _gold_tower(Transform3D(Basis(),_point(t,H-1.5,-0.6)),4.0,0.75)
 if stage>=3: features.append("goldspire")

# --- Carved halls ----------------------------------------------------------------------------------

# A colonnaded hall emerging from the cliff: a marble front with columns and a red pediment,
# its back sunk into the rock.
func _hall(t: float,y: float,w: float):
 var root = Node3D.new()
 add_child(root)
 root.transform = _on_face(t,y,0.6)
 S.box(root,Vector3(w,3.6,3.0),Vector3(0,0,-1.0),MARBLE)
 S.colonnade(root,-w*0.42,w*0.42,0.75,maxi(3,int(w/1.1)),3.0,0.2,MARBLE.lightened(0.3),0.4)
 S.box(root,Vector3(w+0.3,0.4,1.0),Vector3(0,0,0.5),MARBLE.darkened(0.05))
 S.gable(root,w+0.4,2.2,1.0,Vector3(0,3.6,0.1),ROOF)
 S.box(root,Vector3(w*0.25,1.8,0.1),Vector3(0,0.4,-0.2),Color("2a1e14"))

func _build_halls(ledges: int):
 for k in ledges:
  var y = LEDGES[k]
  # Halls at uneven spacing and sizes, so the cliff shows between them.
  var n = 2+(k+1)%2
  for i in n:
   var t = PI*0.5+(i-(n-1)*0.5)*(0.62-k*0.06)+sin(k*2.3+i*1.7)*0.14
   _hall(t,y+sin(i*3.1+k)*0.8,3.4+fmod(k*1.3+i*0.7,1.0)*1.4)
 # The great gate hall at the foot, with a stair up to the first ledge.
 var root = Node3D.new()
 add_child(root)
 root.transform = _on_face(PI*0.5,0.8,0.8)
 S.box(root,Vector3(6.0,5.0,2.0),Vector3(0,0,-0.6),MARBLE)
 S.box(root,Vector3(2.4,3.6,0.2),Vector3(0,0,0.45),Color("2a1e14"))
 S.box(root,Vector3(1.4,1.0,0.1),Vector3(0,1.2,0.5),GLOW,Vector3.ZERO,1.6)
 S.gable(root,6.4,2.4,1.4,Vector3(0,5.0,-0.6),ROOF)
 for i in 8: S.box(root,Vector3(1.6,0.5,1.0),Vector3(4.0+i*0.35,i*0.6,0.4-i*0.25),MARBLE.darkened(0.1),Vector3(0,0.3,0))
 features.append("halls")

func _build_terraces():
 # Gold-roofed towers rising out of the cliff between the halls, and balustrades along the ledges.
 for k in LEDGES.size():
  for s in [-1.0,1.0]:
   var t = PI*0.5+s*(0.75-k*0.08)
   _gold_tower(_on_face(t,LEDGES[k]-0.5,0.2),5.5-k*0.6,0.9-k*0.08)
  for i in 9:
   var t = PI*0.5+(i-4)*0.12
   var root = Node3D.new()
   add_child(root)
   root.transform = _on_face(t,LEDGES[k]-0.2,1.6)
   S.box(root,Vector3(1.6,0.6,0.3),Vector3.ZERO,MARBLE)
 features.append("terraces")

# --- The colossus cut into the face -----------------------------------------------------------------

func _build_statue():
 var root = Node3D.new()
 add_child(root)
 root.transform = _on_face(PI*0.5+0.62,0.5,0.9)
 var stone = ROCK.lightened(0.08)
 S.box(root,Vector3(3.0,1.2,2.0),Vector3.ZERO,stone.darkened(0.15)) # plinth
 S.cylinder(root,1.1,1.6,7.0,Vector3(0,1.2,0),stone,8) # robe
 S.cylinder(root,0.9,1.0,3.0,Vector3(0,8.2,0),stone,8) # chest
 S.dome(root,0.85,Vector3(0,11.2,0),stone,1.3) # head
 S.box(root,Vector3(0.35,7.5,0.35),Vector3(1.6,2.2,0.4),stone.darkened(0.1)) # staff
 S.cone(root,0.6,1.2,Vector3(1.6,9.7,0.4),GLOW) # the torch
 S.box(root,Vector3(0.4,0.4,0.4),Vector3(1.6,10.0,0.4),GLOW,Vector3.ZERO,3.0)
 features.append("statue")

# --- The city at the foot ---------------------------------------------------------------------------

# Dry ground near the rock's foot (local), or null.
func _land(p: Vector2) -> bool:
 return float(_height.call(p.x,p.y))>0.35

func _ground(p: Vector2) -> float:
 return float(_height.call(p.x,p.y))

func _build_city():
 var rng = RandomNumberGenerator.new()
 rng.seed = 2002
 var want = [12,34,64][stage-1]
 var placed = []
 var tries = 0
 while placed.size()<want and tries<want*30:
  tries += 1
  # Around the foot, mostly on the sea side, spreading wider with each stage.
  var t = PI*0.5+rng.randf_range(-1.0,1.0)*(1.1+stage*0.35)
  var d = rng.randf_range(1.5,4.0+stage*3.5)
  var c = _point(t,1.0,d)
  var p = Vector2(c.x,c.z)
  if not _land(p): continue
  var ok = true
  for q in placed:
   if q.distance_to(p)<2.9:
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
  var temple_at = _point(PI*0.5-1.1,1.0,6.0)
  if _land(Vector2(temple_at.x,temple_at.z)): _piece("kit.greek.temple",Transform3D(Basis(Vector3.UP,0.4),Vector3(temple_at.x,_ground(Vector2(temple_at.x,temple_at.z)),temple_at.z)),0.8)
 features.append("greek_city")

func _build_theatre():
 # A semicircle of stepped seats cut into the slope on the land side of the city.
 var c3 = _point(PI*0.5+1.35,0.5,7.0)
 var c = Vector2(c3.x,c3.z)
 var root = Node3D.new()
 add_child(root)
 root.position = Vector3(c.x,_ground(c),c.y)
 root.rotation.y = -(PI*0.5+1.35)
 for row in 5:
  var r = 3.0+row*1.1
  for i in 11:
   var a = PI*(0.1+0.8*i/10.0)
   S.box(root,Vector3(1.2,0.5+row*0.45,0.9),Vector3(cos(a)*r,0,-sin(a)*r),MARBLE.darkened(0.05*row),Vector3(0,a,0))
 features.append("theatre")

# --- Harbour and walls --------------------------------------------------------------------------------

func _build_harbor():
 # A curved breakwater out to sea with a lighthouse at each head, and quays along the shore.
 var root = Node3D.new()
 add_child(root)
 var front = B+9.0
 for i in 15:
  var a = lerpf(-1.0,1.0,i/14.0)
  var p = Vector3(a*13.0,-0.6,front+4.0*(1.0-a*a))
  S.box(root,Vector3(2.2,1.6,1.8),p,Color("a89a80"),Vector3(0,-a*0.6,0))
 for s in [-1.0,1.0]:
  var p = Vector3(s*13.2,0.9,front)
  S.cylinder(root,0.6,0.8,4.5,p,MARBLE,8)
  S.box(root,Vector3(0.9,0.8,0.9),p+Vector3(0,4.5,0),GLOW,Vector3.ZERO,2.5)
 for i in 4:
  var p = Vector3(-6.0+i*4.0,-0.4,B+3.0)
  S.box(root,Vector3(3.0,0.6,4.0),p,Color("8a6e48"))
 # Ships in the harbour: hulls with a mast and a sail.
 for i in 5:
  var p = Vector3(-8.0+i*4.0,0.0,front-2.5+(i%2)*1.5)
  S.box(root,Vector3(0.9,0.6,3.2),p,Color("6a4a2a"))
  S.box(root,Vector3(0.12,3.0,0.12),p+Vector3(0,0.6,0),Color("5a4028"))
  S.box(root,Vector3(1.6,1.4,0.05),p+Vector3(0,1.6,0.1),Color("f0e6d0"))
 features.append("harbor")

func _build_walls():
 # City walls from the cliff down to the sea on both sides, with square towers.
 for s in [-1.0,1.0]:
  var from = _point(PI*0.5+s*1.35,1.0,0.0)
  var to = from+Vector3(s*4.0,0,9.0+stage*2.0)
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
    S.box(root,Vector3(2.4,4.6,2.4),Vector3.ZERO,MARBLE.darkened(0.06))
    S.box(root,Vector3(2.7,0.4,2.7),Vector3(0,4.6,0),ROOF)
   else:
    S.box(root,Vector3(3.1,3.0,1.0),Vector3.ZERO,MARBLE.darkened(0.1))
 features.append("walls")
