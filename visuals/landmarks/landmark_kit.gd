extends RefCounted
# Shared building blocks for the Stage A landmarks (visuals/landmarks/*_visual.gd, 2026-10-06):
# curtain walls with towers, round and square towers, domes and spires, arched bridges, statues,
# scattered culture houses and glows. Shapes come from the culture kits' simple shapes
# (visuals/kits/cultures/kit_shapes.gd), so a landmark merges into a few surfaces (ProtoKit.batch).
# Campaign scale: a house about 3 m, a lord about 4.5 m, landmarks up to about 45 m tall.
# `h` is the landmark's local height lookup (map/map_view.gd passes it to build()).

const S = preload("res://visuals/kits/cultures/kit_shapes.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")

static func ground(h: Callable,x: float,z: float) -> float:
 return float(h.call(x,z)) if h.is_valid() else 0.0

static func node(parent: Node3D,pos := Vector3.ZERO,yaw := 0.0) -> Node3D:
 var n = Node3D.new()
 parent.add_child(n)
 n.position = pos
 n.rotation.y = yaw
 return n

# A round tower: a drum, a crenellated top and an optional conical roof.
static func round_tower(parent: Node3D,pos: Vector3,r: float,height: float,stone: Color,roof = null,roof_h := 0.0):
 S.cylinder(parent,r,r*1.08,height+2.0,pos-Vector3(0,2.0,0),stone,12)
 S.cylinder(parent,r*1.12,r*1.12,0.6,pos+Vector3(0,height-0.6,0),stone.darkened(0.1),12)
 for i in 8: S.box(parent,Vector3(r*0.38,0.6,r*0.38),pos+Vector3(cos(i*0.785)*r*1.02,height,sin(i*0.785)*r*1.02),stone.darkened(0.06))
 if roof != null: S.cone(parent,r*1.25,roof_h if roof_h>0.0 else r*1.8,pos+Vector3(0,height,0),roof,12)

static func square_tower(parent: Node3D,pos: Vector3,w: float,height: float,stone: Color,roof = null,yaw := 0.0):
 var n = node(parent,pos,yaw)
 S.box(n,Vector3(w,height+2.0,w),Vector3(0,-2.0,0),stone)
 for sx in [-1.0,1.0]:
  for sz in [-1.0,1.0]: S.box(n,Vector3(w*0.24,0.6,w*0.24),Vector3(sx*w*0.38,height,sz*w*0.38),stone.darkened(0.06))
 if roof != null: S.hip(n,w*1.1,w*1.1,w*0.7,Vector3(0,height,0),roof)

# A curtain wall along a closed ring (a circle of `radius`, or a polygon), on the ground, with towers
# every `every` metres and gatehouses at the given angles. Returns the number of towers.
# A landmark's wall: since 2026-10-07 a terrain-following trace (wall_trace; owner: walls never read as
# circles). `every` is kept for the callers and no longer used. Returns the towers built.
static func wall_ring(parent: Node3D,h: Callable,center: Vector3,radius: float,height: float,thick: float,stone: Color,every := 14.0,gates := [],tower_roof = null) -> int:
 return wall_trace(parent,h,center,radius,height,thick,stone,gates,tower_roof,int(radius*97.0+center.x*13.0+center.z*7.0),0.14).size()

# The old circular ring (kept for reference; no landmark uses it).
static func _wall_circle(parent: Node3D,h: Callable,center: Vector3,radius: float,height: float,thick: float,stone: Color,every := 14.0,gates := [],tower_roof = null) -> int:
 var segs = maxi(12,int(TAU*radius/3.2))
 var towers = 0
 var since = 0.0
 for i in segs:
  var a = (i+0.5)*TAU/segs
  var p = center+Vector3(cos(a)*radius,0,sin(a)*radius)
  p.y = ground(h,p.x,p.z)
  var gate = gates.any(func(g): return absf(angle_difference(a,g))<0.12)
  since += TAU*radius/segs
  var n = node(parent,p,-a+PI*0.5)
  if gate:
   for sx in [-1.0,1.0]: S.box(n,Vector3(2.4,height+4.0,thick+1.4),Vector3(sx*2.2,-2.0,0),stone.darkened(0.04))
   S.box(n,Vector3(2.0,height-3.4,thick+1.0),Vector3(0,3.4,0),stone.darkened(0.04))
   S.box(n,Vector3(1.8,3.4,thick+1.1),Vector3(0,-0.1,0),Color("1e1a16"))
   continue
  S.box(n,Vector3(TAU*radius/segs+0.15,height+2.0,thick),Vector3(0,-2.0,0),stone)
  for k in 2: S.box(n,Vector3(0.6,0.6,0.4),Vector3(-0.8+k*1.6,height,thick*0.5-0.2),stone.darkened(0.08))
  if since>=every:
   round_tower(parent,p,thick*1.3,height+3.0,stone,tower_roof,thick*2.0)
   towers += 1
   since = 0.0
 return towers

# A dome on a drum, with an optional lantern spire.
static func dome(parent: Node3D,pos: Vector3,r: float,drum_h: float,wall: Color,cap: Color,spire := 0.0):
 S.cylinder(parent,r*1.02,r*1.02,drum_h,pos,wall,16)
 S.dome(parent,r,pos+Vector3(0,drum_h,0),cap,1.15)
 if spire>0.0:
  S.cylinder(parent,r*0.12,r*0.16,r*0.5,pos+Vector3(0,drum_h+r*1.1,0),cap,8)
  S.cone(parent,r*0.12,spire,pos+Vector3(0,drum_h+r*1.6,0),cap,8)

static func spire(parent: Node3D,pos: Vector3,r: float,height: float,stone: Color,cap: Color):
 S.cylinder(parent,r,r*1.1,height*0.6,pos,stone,8)
 S.cone(parent,r*1.05,height*0.4,pos+Vector3(0,height*0.6,0),cap,8)

# An arched bridge from a to b (local, ground heights at both ends), `n` arches.
static func arch_bridge(parent: Node3D,a: Vector3,b: Vector3,width: float,height: float,n: int,stone: Color,battlements := true):
 var d = b-a
 var yaw = atan2(d.x,d.z)
 var len = Vector2(d.x,d.z).length()
 var root = node(parent,a,yaw)
 S.box(root,Vector3(width,1.0,len),Vector3(0,height,len*0.5),stone)
 for i in n+1:
  var z = len*i/n
  S.box(root,Vector3(width*0.8,height+2.0,1.4),Vector3(0,-2.0,z),stone.darkened(0.06))
 if battlements:
  for s in [-1.0,1.0]:
   for k in int(len/1.6): S.box(root,Vector3(0.35,0.6,0.7),Vector3(s*(width*0.5-0.18),height+1.0,0.8+k*1.6),stone.darkened(0.1))

# A robed statue on a plinth (`height` metres tall).
static func statue(parent: Node3D,pos: Vector3,height: float,stone: Color,yaw := 0.0):
 var n = node(parent,pos,yaw)
 var u = height/10.0
 S.box(n,Vector3(3.0*u,1.2*u,3.0*u),Vector3.ZERO,stone.darkened(0.15))
 S.cylinder(n,0.9*u,1.4*u,6.0*u,Vector3(0,1.2*u,0),stone,8)
 S.cylinder(n,0.75*u,0.85*u,2.0*u,Vector3(0,7.2*u,0),stone,8)
 S.dome(n,0.7*u,Vector3(0,9.2*u,0),stone,1.3)

# Culture houses scattered on dry ground between radii r0 and r1 around `center` (kit pieces).
static func houses(parent: Node3D,h: Callable,culture: String,center: Vector3,r0: float,r1: float,count: int,seed: int,tall_share := 0.12,avoid := Callable()) -> int:
 var rng = RandomNumberGenerator.new()
 rng.seed = seed
 var placed = []
 var tries = 0
 while placed.size()<count and tries<count*25:
  tries += 1
  var a = rng.randf()*TAU
  var r = sqrt(rng.randf_range(r0*r0,r1*r1))
  var p = Vector2(center.x+cos(a)*r,center.z+sin(a)*r)
  var y = ground(h,p.x,p.y)
  if y<0.3: continue
  if avoid.is_valid() and avoid.call(p): continue
  if placed.any(func(q): return q.distance_to(p)<3.2): continue
  placed.append(p)
  var id = "kit.%s.%s" % [culture,"tall" if rng.randf()<tall_share else ["house_1","house_2","house_3"][rng.randi_range(0,2)]]
  var n = AssetManifest.instantiate(id)
  parent.add_child(n)
  n.position = Vector3(p.x,y-0.1,p.y)
  n.rotation.y = rng.randf()*TAU
 return placed.size()

static func glow(parent: Node3D,pos: Vector3,size: Vector3,c: Color,energy := 2.0):
 S.box(parent,size,pos,c,Vector3.ZERO,energy)

# A flat disc of water (moats, pools, springs) just above the ground.
static func water(parent: Node3D,pos: Vector3,r: float,c := Color("3f7fa6"),inner := 0.0):
 if inner<=0.0:
  S.cylinder(parent,r,r,0.25,pos,c,24)
  return
 var segs = 36
 for i in segs:
  var a = (i+0.5)*TAU/segs
  var mid = (r+inner)*0.5
  var n = node(parent,pos+Vector3(cos(a)*mid,0,sin(a)*mid),-a+PI*0.5)
  S.box(n,Vector3(TAU*mid/segs+0.1,0.25,r-inner),Vector3.ZERO,c)

# A wall that follows the terrain (owner 2026-10-07: walls must never read as circles): corner points
# around the centre at radius x (1 - spread .. 1 + spread), each pushed to the highest ground in its
# range (walls keep to the crest), joined by straight stretches stepped along the slope, a tower at
# every corner and a gatehouse on the stretch nearest each gate angle. Deterministic per seed.
static func wall_trace(parent: Node3D,h: Callable,center: Vector3,radius: float,height: float,thick: float,stone: Color,gates := [],tower_roof = null,seed := 1,spread := 0.16) -> Array:
 var rng = RandomNumberGenerator.new()
 rng.seed = seed
 var n = clampi(int(TAU*radius/14.0),9,13)
 var corners = []
 for i in n:
  var a = (i+rng.randf_range(-0.28,0.28))*TAU/n
  var best_r = radius
  var best_h = -INF
  for k in 7:
   var r = radius*(1.0-spread+2.0*spread*k/6.0)
   var gh = ground(h,center.x+cos(a)*r,center.z+sin(a)*r)+rng.randf_range(-0.3,0.3)
   if gh>best_h:
    best_h = gh
    best_r = r
  corners.append(center+Vector3(cos(a)*best_r,0,sin(a)*best_r))
 # The gate stretches: the edge whose midpoint lies nearest each gate angle.
 var gate_edges = {}
 for g in gates:
  var bi = 0
  var bd = INF
  for i in n:
   var m = (corners[i]+corners[(i+1)%n])*0.5-center
   var dd = absf(angle_difference(atan2(m.z,m.x),g))
   if dd<bd:
    bd = dd
    bi = i
  gate_edges[bi] = true
 for i in n:
  var a = corners[i]
  var b = corners[(i+1)%n]
  var d = Vector2(b.x-a.x,b.z-a.z)
  var len = d.length()
  var yaw = -atan2(d.y,d.x)
  var steps = maxi(1,int(len/3.2))
  for s in steps:
   var t0 = float(s)/steps
   var t1 = float(s+1)/steps
   var p = a.lerp(b,(t0+t1)*0.5)
   p.y = ground(h,p.x,p.z)
   var nd = node(parent,p,yaw)
   if gate_edges.has(i) and absi(s-steps/2)<=0:
    for sx in [-1.0,1.0]: S.box(nd,Vector3(2.4,height+4.0,thick+1.4),Vector3(sx*2.2,-2.0,0),stone.darkened(0.04))
    S.box(nd,Vector3(2.0,height-3.4,thick+1.0),Vector3(0,3.4,0),stone.darkened(0.04))
    S.box(nd,Vector3(1.8,3.4,thick+1.1),Vector3(0,-0.1,0),Color("1e1a16"))
    continue
   S.box(nd,Vector3(len/steps+0.2,height+2.0,thick),Vector3(0,-2.0,0),stone)
   for k in 2: S.box(nd,Vector3(0.6,0.6,0.4),Vector3(-0.8+k*1.6,height,thick*0.5-0.2),stone.darkened(0.08))
  # A tower at every other corner (towers at every corner read as a heap of towers).
  if i%2 == 0:
   var tp = a
   tp.y = ground(h,tp.x,tp.z)
   round_tower(parent,tp,thick*1.15,height+2.5,stone,tower_roof,thick*1.8)
 return corners
