extends Node3D
# Goldspire Rock (docs/world.md landmark #2, House Aurek): a colossal sea cliff with a fortress
# carved into and on top of it, glowing mine entrances, gold-roofed towers, harbor at its foot.
# Stage 1: mine tunnels and a tower on the summit. Stage 2: carved halls, harbor, walls.
# Stage 3: the whole sea face terraced with halls and towers.
# Local space: origin at sea level under the rock's center, +z faces the sea. The owner positions
# the node on the coast, adds it to the tree, then calls build().

const ProtoKit = preload("res://visuals/common/proto_kit.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")
const PIECES = {
 "tower": preload("res://assets/quaternius/ultimate-fantasy-rts/WatchTower_SecondAge_Level1.gltf"),
 "battle_tower": preload("res://assets/quaternius/ultimate-fantasy-rts/WatchTower_SecondAge_Level2.gltf"),
 "keep": preload("res://assets/quaternius/ultimate-fantasy-rts/TowerHouse_SecondAge.gltf"),
 "spire": preload("res://assets/quaternius/ultimate-fantasy-rts/Temple_SecondAge_Level1.gltf"),
 "wall_towers": preload("res://assets/quaternius/ultimate-fantasy-rts/WallTowers_SecondAge.gltf"),
 "wall_gate": preload("res://assets/quaternius/ultimate-fantasy-rts/WallTowers_Door_SecondAge.gltf"),
 "wall": preload("res://assets/quaternius/ultimate-fantasy-rts/Wall_SecondAge.gltf"),
 "house": preload("res://assets/quaternius/ultimate-fantasy-rts/Houses_SecondAge_1_Level1.gltf"),
 "house_small": preload("res://assets/quaternius/ultimate-fantasy-rts/Houses_SecondAge_3_Level1.gltf"),
 "hall": preload("res://assets/quaternius/ultimate-fantasy-rts/Storage_SecondAge_Level1.gltf"),
 "port": preload("res://assets/quaternius/ultimate-fantasy-rts/Port_SecondAge_Level1.gltf"),
 "port_large": preload("res://assets/quaternius/ultimate-fantasy-rts/Port_SecondAge_Level2.gltf"),
 "dock": preload("res://assets/quaternius/ultimate-fantasy-rts/Dock_FirstAge.gltf"),
}
const A = 14.0 # half length along the coast
const B = 10.5 # half depth, land to sea
const H = 21.0 # summit plateau height
const BASE = -4.0
const SEGMENTS = 40
const LEDGES = [5.5,10.5,15.5]
const TERRACE = 2.6 # stage 3 terrace depth; lower terraces step out toward the sea
const SCALE = 2.4 # pack pieces -> campaign scale (houses ~1.85 m)
const TOWER_SCALE = 4.2 # summit tower ~5 m, the top of the campaign tower range
const HALL_ANGLES = [1.3,1.85]
const MINES = [
 [1.15,1.3,1],[2.05,1.3,1],[0.35,7.0,1],[2.75,9.0,1],
 [1.6,13.0,2],[0.8,17.0,2],
 [2.35,13.0,3],[0.55,12.5,3],
]
# The main rock carries the fortress; two landward shoulders break the silhouette.
const MAIN = {"c":Vector3.ZERO,"a":A,"b":B,"h":H,"phase":0.0,"plateau":true}
const MASSES = [
 {"c":Vector3(12.0,0,-4.0),"a":7.5,"b":6.5,"h":16.0,"phase":1.7,"plateau":false,"peak":0.35},
 {"c":Vector3(-11.5,0,-5.0),"a":6.0,"b":5.0,"h":11.0,"phase":4.2,"plateau":false,"peak":0.4},
]
const STRATA = [Color("9a7547"),Color("8e6b43"),Color("a47d4c"),Color("93704a"),Color("9e7849")]
const TOP = Color("958a64")
const WET = Color("54452f")

@export_range(1,3) var stage := 1

var kit
var noise = FastNoiseLite.new()
var gold: StandardMaterial3D
var glow: StandardMaterial3D
var pale: StandardMaterial3D
var quay_stone: StandardMaterial3D
var dark: StandardMaterial3D
var timber: StandardMaterial3D
var features: Array = []
var _height: Callable

# ctx.height: optional Callable(local_x, local_z) -> terrain height in this node's space.
func build(ctx: Dictionary):
 kit = ProtoKit.shared()
 _height = ctx.get("height",func(_x,_z): return 0.0)
 noise.seed = 2002
 noise.frequency = 1.0
 gold = kit.mat(Color("d6a93c"),0.32,0.85)
 glow = kit.mat(Color("ff8f2a"))
 glow.emission_enabled = true
 glow.emission = Color("ff7a18")
 glow.emission_energy_multiplier = 1.8
 pale = kit.mat(Color("cdbd96"))
 quay_stone = kit.mat(Color("9c8866"))
 dark = kit.mat(Color("17110d"))
 timber = kit.mat(Color("6e5538"))
 _build_rock()
 _build_mines()
 _build_summit()
 if stage>=2:
  _build_halls()
  _build_harbor()
  _build_walls()
 if stage>=3: _build_terraces()
 set_meta("stage",stage)
 set_meta("features",features)
 # Collapse static pieces by material; the mine lights stay as they are.
 kit.batch(self)

# --- Rock -------------------------------------------------------------------

func _sea_weight(t: float) -> float:
 return smoothstep(0.2,0.65,sin(t))

func _ledges_above(y: float,inclusive: bool) -> int:
 var n = 0
 for l in LEDGES:
  if l>y or (inclusive and is_equal_approx(l,y)): n += 1
 return n

# Horizontal outset of the sea face at height y (stage 3 terraces step outward going down).
func _outset(t: float,ledges: int) -> float:
 return TERRACE*_sea_weight(t)*ledges if stage>=3 else 0.0

func _normal_at(t: float) -> Vector3:
 return Vector3(B*cos(t),0,A*sin(t)).normalized()

# Surface point of a rock mass: sheer fluted cliffs, an irregular footprint, and either a rim and
# flat summit plateau (the main rock) or a crag that narrows to a peak.
func _mass_point(m: Dictionary,t: float,y: float,ledges: int) -> Vector3:
 var h = clampf(y/m.h,0,1)
 var f = 1.0-0.05*h
 f -= 0.08*h*maxf(0,-sin(t)) # the land side leans back
 if m.plateau:
  # Tiered mesa: sheer cliff, a sharp shoulder, a second cliff, then the crown rim.
  f *= lerpf(1.0,0.84,smoothstep(0.55,0.62,h))
  f *= lerpf(1.0,0.82,smoothstep(0.86,0.93,h))
 else: f *= lerpf(1.0,m.peak,smoothstep(0.45,1.0,h))
 var shape = 1.0+0.10*sin(2*t+0.7+m.phase)+0.06*sin(3*t+2.1+m.phase)
 # Vertical buttresses (noise constant up the face), broad bulges, and small chips.
 var ribs = noise.get_noise_3d(cos(t)*3.5+m.phase*7,0.0,sin(t)*3.5)*0.10+noise.get_noise_3d(cos(t)*2.0+m.phase,y*0.03,sin(t)*2.0)*0.07+noise.get_noise_3d(cos(t)*9,y*0.15,sin(t)*9)*0.02
 var p = Vector3(m.a*cos(t),0,m.b*sin(t))*f*shape*(1+ribs)+m.c
 if m.plateau: p += _normal_at(t)*_outset(t,ledges)
 p.y = y
 return p

func _point(t: float,y: float,ledges: int) -> Vector3:
 return _mass_point(MAIN,t,y,ledges)

# Point on the cliff face between ledges, nudged outward so attached pieces never sink in.
func _face(t: float,y: float,out = 0.3) -> Vector3:
 return _point(t,y,_ledges_above(y,false))+_normal_at(t)*out

func _build_rock():
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rings = []
 for y in [BASE,0.0,1.4,3.2,5.5,8.0,10.5,11.6,13.0,15.5,17.0,18.1,19.5,20.4,H]:
  if stage>=3 and y in LEDGES:
   rings.append([y,_ledges_above(y,true)])
  rings.append([y,_ledges_above(y,false)])
 _build_mass(st,MAIN,rings,Vector3(0,H,0))
 for m in MASSES:
  var mass_rings = []
  for k in [-0.3,0.0,0.2,0.4,0.55,0.7,0.82,0.92,1.0]: mass_rings.append([maxf(BASE,k*m.h),0])
  _build_mass(st,m,mass_rings,m.c+Vector3(0,m.h+(1.2 if m.peak<0.5 else 0.2),0))
 var mat = kit.mat(Color.WHITE,1.0)
 mat.vertex_color_use_as_albedo = true
 mat.vertex_color_is_srgb = true
 kit.add_mesh(self,st.commit(),mat)
 features.append("rock")

func _build_mass(st: SurfaceTool,m: Dictionary,rings: Array,cap: Vector3):
 var grid = []
 for r in rings:
  var ring = []
  for j in SEGMENTS:
   ring.append(_mass_point(m,j*TAU/SEGMENTS,r[0],r[1]))
  grid.append(ring)
 var strata = []
 for k in grid.size():
  strata.append(STRATA[posmod(int(rings[k][0]*0.37+m.phase*3)+k*3,STRATA.size())])
 for k in grid.size()-1:
  for j in SEGMENTS:
   var a = grid[k][j]
   var b = grid[k][(j+1)%SEGMENTS]
   var c = grid[k+1][j]
   var d = grid[k+1][(j+1)%SEGMENTS]
   # Horizontal strata per ring, darker and lighter vertical streaks per column.
   var color = WET if a.y<0.5 else strata[k]*(0.82+0.3*(0.5+0.5*noise.get_noise_2d(j*1.7+m.phase*11,k*0.15)))
   _tri(st,m.c,a,b,c,color)
   _tri(st,m.c,b,d,c,color)
 for j in SEGMENTS:
  _tri(st,m.c,cap,grid[-1][j],grid[-1][(j+1)%SEGMENTS],TOP)

# One flat-shaded triangle facing away from its mass's axis; upward faces get the summit color.
func _tri(st: SurfaceTool,center: Vector3,a: Vector3,b: Vector3,c: Vector3,color: Color):
 var mid = (a+b+c)/3.0
 var outward = Vector3(mid.x-center.x,0,mid.z-center.z).normalized()+Vector3(0,0.3,0)
 var n = (c-a).cross(b-a)
 if n.length_squared()<0.000001: return
 if n.dot(outward)<0:
  var swap = b
  b = c
  c = swap
  n = -n
 n = n.normalized()
 st.set_color(TOP if n.y>0.8 else color)
 st.set_normal(n)
 for v in [a,b,c]: st.add_vertex(v)

# --- Features ---------------------------------------------------------------

func _place(key: String,pos: Vector3,facing: Vector3,s: float) -> Node3D:
 var n = PIECES[key].instantiate()
 add_child(n)
 n.position = pos
 n.rotation.y = atan2(facing.x,facing.z)
 n.scale = Vector3.ONE*s
 # The pack's "Main" team color (red roofs, banners) becomes House Aurek's gold.
 for m in n.find_children("*","MeshInstance3D",true,false):
  for i in m.mesh.get_surface_count():
   var mat = m.mesh.surface_get_material(i)
   if mat and mat.resource_name == "Main": m.set_surface_override_material(i,gold)
 return n

# A child frame at pos whose local +z faces the given direction.
func _frame(pos: Vector3,facing: Vector3) -> Node3D:
 var n = Node3D.new()
 add_child(n)
 n.position = pos
 n.rotation.y = atan2(facing.x,facing.z)
 return n

func _build_mines():
 var count = 0
 for m in MINES:
  if m[2]>stage: continue
  var t = m[0]
  var f = _frame(_face(t,m[1],0.0),_normal_at(t))
  # Dark tunnel mouth with the lamp-lit gallery deep inside, timber portal, spoil ramp.
  kit.box(f,Vector3(0,0,-0.1),Vector3(2.1,2.6,1.4),dark)
  kit.box(f,Vector3(0,-0.45,0.62),Vector3(1.2,1.5,0.2),glow)
  for x in [-1.05,1.05]: kit.box(f,Vector3(x,-0.05,0.85),Vector3(0.26,2.7,0.3),timber)
  kit.box(f,Vector3(0,1.32,0.85),Vector3(2.5,0.3,0.34),timber)
  kit.box(f,Vector3(0,-1.35,1.35),Vector3(1.9,0.22,1.3),timber)
  var spoil = kit.cylinder(f,Vector3(0,-1.6,2.2),1.5,0.4,0.7,dark,7)
  spoil.scale = Vector3(1.0,1.0,0.7)
  if count<5:
   var light = OmniLight3D.new()
   light.light_color = Color("ffa94d")
   light.light_energy = 1.4
   light.omni_range = 5.5
   f.add_child(light)
   light.position = Vector3(0,-0.2,1.8)
  count += 1
 features.append("mines:%d" % count)

func _build_summit():
 var sea = Vector3(0,0,1)
 _place("tower",Vector3(1.8,H,-1.2),sea,TOWER_SCALE)
 features.append("summit_tower")
 if stage>=2:
  _place("keep",Vector3(-3.2,H,-0.5),sea,SCALE)
  for x in [-6.2,6.2]: _place("battle_tower",Vector3(x,H,0.0),Vector3(signf(x),0,0),3.0)
 if stage>=3:
  _place("spire",Vector3(-0.2,H,2.0),sea,1.6)
  _place("house_small",Vector3(4.5,H,1.6),sea,SCALE)
  _place("house_small",Vector3(-4.5,H,1.8),sea,SCALE)
  features.append("goldspire")

func _build_halls():
 for t in HALL_ANGLES:
  var f = _frame(_face(t,LEDGES[0],0.0)+Vector3(0,2.3,0),_normal_at(t))
  kit.box(f,Vector3(0,0,0.1),Vector3(5.0,4.6,1.6),dark)
  for x in [-1.9,-0.65,0.65,1.9]: kit.cylinder(f,Vector3(x,-0.1,1.1),0.3,0.3,4.2,pale,10)
  kit.box(f,Vector3(0,2.25,1.05),Vector3(5.6,0.6,0.85),pale)
  kit.box(f,Vector3(0,2.62,1.05),Vector3(5.7,0.16,0.9),gold)
  kit.roof(f,Vector3(0,2.7,1.05),5.6,0.8,1.15,gold)
  kit.box(f,Vector3(0,-2.3,1.3),Vector3(5.8,0.3,1.4),pale)
 features.append("halls")

func _build_harbor():
 var t = 2.25
 var n = _normal_at(t)
 var side = Vector3(n.z,0,-n.x)
 var quay = _face(t,0.0,0.0)+n*2.2
 var f = _frame(quay,n)
 kit.box(f,Vector3(0,0.1,0),Vector3(13.0,1.2,4.6),quay_stone)
 _place("port_large" if stage>=3 else "port",quay+n*5.4+Vector3(0,0.45,0),n,SCALE)
 for s in [-4.6,4.6]: _place("dock",quay+side*s+n*4.4+Vector3(0,0.6,0),n,SCALE)
 var ships = 2 if stage>=3 else 1
 for i in ships:
  var ship = AssetManifest.instantiate("commerce.ship")
  add_child(ship)
  ship.position = quay+side*(-7.4 if i==0 else 7.4)+n*6.5
  ship.rotation.y = atan2(n.x,n.z)
 features.append("harbor")

func _build_walls():
 # Curtain wall with towers around the summit plateau, gate toward the land.
 var points = []
 var count = 8
 for i in count:
  var t = -PI/2+i*TAU/count
  points.append(Vector3(cos(t)*6.6,H,sin(t)*4.1))
 for i in count:
  var a = points[i]
  var b = points[(i+1)%count]
  var mid = (a+b)*0.5
  var key = "wall_gate" if i==0 else "wall_towers"
  var w = _place(key,mid,Vector3(mid.x,0,mid.z),SCALE)
  w.scale.x = a.distance_to(b)/1.98
 # Land gate at the foot of the rock.
 var gate = Vector3(0,0,-B-3.0)
 gate.y = _height.call(gate.x,gate.z)
 _place("wall_gate",gate,Vector3(0,0,-1),SCALE)
 for x in [-6.3,6.3]:
  var p = Vector3(x,0,-B-2.4)
  p.y = _height.call(p.x,p.z)
  var w = _place("wall",p,Vector3(0,0,-1),SCALE)
  w.rotation.y += -0.18*signf(x)
 features.append("walls")

func _build_terraces():
 var keys = ["house","hall","house_small","house","house_small","hall","house"]
 for li in LEDGES.size():
  var y = LEDGES[li]
  var steps = 9
  for i in steps:
   var t = lerpf(0.72,2.42,float(i)/(steps-1))
   if li==0:
    var near_hall = false
    for h in HALL_ANGLES:
     if absf(t-h)<0.24: near_hall = true
    if near_hall: continue
   var outer = _point(t,y,_ledges_above(y,true))
   var inner = _point(t,y,_ledges_above(y,false))
   var pos = (outer+inner)*0.5
   var n = _normal_at(t)
   if i==0 or i==steps-1: _place("tower",pos,n,3.0)
   else:
    var key = keys[(i+li*2)%keys.size()]
    _place(key,pos,n,1.8 if key=="hall" else SCALE)
 features.append("terraces")
