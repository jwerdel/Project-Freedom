extends RefCounted
# Simple shapes for the procedural culture kits (visuals/kits/cultures/culture_kit.gd): boxes,
# gabled and hipped roofs, cylinders, cones, spikes, domes and stepped pyramids, each a
# MeshInstance3D with a flat colour (one shared material per colour, so the kit cache merges a whole
# piece into one surface). Metres at world scale; the sprawl places pieces at campaign scale.

static var _mats = {}
static var _meshes = {}

static func mat(c: Color,glow := 0.0) -> StandardMaterial3D:
 var k = "%s|%.2f" % [c.to_html(),glow]
 if not _mats.has(k):
  var m = StandardMaterial3D.new()
  m.albedo_color = c
  m.roughness = 0.9
  if glow>0.0:
   m.emission_enabled = true
   m.emission = c
   m.emission_energy_multiplier = glow
  _mats[k] = m
 return _mats[k]

static func _add(root: Node3D,mesh: Mesh,c: Color,pos: Vector3,rot := Vector3.ZERO,glow := 0.0) -> MeshInstance3D:
 var mi = MeshInstance3D.new()
 mi.mesh = mesh
 mi.material_override = null
 mi.set_surface_override_material(0,mat(c,glow))
 mi.position = pos
 mi.rotation = rot
 root.add_child(mi)
 return mi

static func box(root: Node3D,size: Vector3,pos: Vector3,c: Color,rot := Vector3.ZERO,glow := 0.0) -> MeshInstance3D:
 var m = BoxMesh.new()
 m.size = size
 return _add(root,m,c,pos+Vector3(0,size.y*0.5,0),rot,glow)

# Gabled roof: ridge along x, sitting on top at height y.
static func gable(root: Node3D,w: float,d: float,h: float,pos: Vector3,c: Color,rot := Vector3.ZERO) -> MeshInstance3D:
 var m = PrismMesh.new()
 m.size = Vector3(d,h,w)
 return _add(root,m,c,pos+Vector3(0,h*0.5,0),rot+Vector3(0,PI*0.5,0))

static func cylinder(root: Node3D,r_top: float,r_bottom: float,h: float,pos: Vector3,c: Color,sides := 8,rot := Vector3.ZERO,glow := 0.0) -> MeshInstance3D:
 var m = CylinderMesh.new()
 m.top_radius = r_top
 m.bottom_radius = r_bottom
 m.height = h
 m.radial_segments = sides
 m.rings = 1
 return _add(root,m,c,pos+Vector3(0,h*0.5,0),rot,glow)

static func cone(root: Node3D,r: float,h: float,pos: Vector3,c: Color,sides := 8,rot := Vector3.ZERO) -> MeshInstance3D:
 return cylinder(root,0.0,r,h,pos,c,sides,rot)

# A four-sided pyramid roof (hipped).
static func hip(root: Node3D,w: float,d: float,h: float,pos: Vector3,c: Color) -> MeshInstance3D:
 var mi = cylinder(root,0.0,0.5,h,pos,c,4,Vector3(0,PI*0.25,0))
 mi.scale = Vector3(w*1.414,1,d*1.414)
 return mi

static func dome(root: Node3D,r: float,pos: Vector3,c: Color,squash := 1.0) -> MeshInstance3D:
 var m = SphereMesh.new()
 m.radius = r
 m.height = r*2.0
 m.radial_segments = 10
 m.rings = 5
 m.is_hemisphere = true
 var mi = _add(root,m,c,pos)
 mi.scale = Vector3(1,squash,1)
 return mi

static func spike(root: Node3D,r: float,h: float,pos: Vector3,c: Color,tilt := Vector3.ZERO) -> MeshInstance3D:
 return cylinder(root,0.0,r,h,pos,c,4,tilt)

# Stepped pyramid: `levels` boxes shrinking toward the top; returns the top height.
static func steps(root: Node3D,base: float,levels: int,step_h: float,pos: Vector3,c: Color,shrink := 0.78) -> float:
 var w = base
 var y = 0.0
 for i in levels:
  box(root,Vector3(w,step_h,w),pos+Vector3(0,y,0),c.darkened(0.04*(i%2)))
  y += step_h
  w *= shrink
 return y

# Columns in a row along x from x0 to x1.
static func colonnade(root: Node3D,x0: float,x1: float,z: float,n: int,h: float,r: float,c: Color,y := 0.0):
 for i in n:
  var x = lerpf(x0,x1,float(i)/maxf(1.0,n-1.0))
  cylinder(root,r,r,h,Vector3(x,y,z),c,6)

static func reset():
 _mats = {}
 _meshes = {}
