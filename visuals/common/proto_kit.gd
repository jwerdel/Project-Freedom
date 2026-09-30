extends RefCounted
# Shared palette and primitive builders for the procedural prototype visuals.
# Placeholder-only: the real art pass replaces the scenes that use this, not gameplay.

static var _shared

var stone: StandardMaterial3D
var wood: StandardMaterial3D
var slate: StandardMaterial3D
var plaster: StandardMaterial3D
var brass: StandardMaterial3D
var iron: StandardMaterial3D
var dark: StandardMaterial3D
var sail: StandardMaterial3D
var city_materials: Array = []

# One palette instance for the whole map, so static batching groups by the same materials.
static func shared():
 if _shared == null:
  _shared = new()
 return _shared

func _init():
 stone = textured("medieval_blocks_03",Color(0.80,0.79,0.72),1.0)
 wood = textured("weathered_brown_planks",Color(0.49,0.39,0.29),1.0)
 slate = textured("roof_slates_02",Color("9099a2"),1.0)
 slate.cull_mode = BaseMaterial3D.CULL_DISABLED
 plaster = mat(Color("b0aa8c"))
 brass = mat(Color("b99a53"),0.4,0.7)
 iron = mat(Color("828e94"),0.35,0.78)
 dark = mat(Color("202b2c"))
 sail = mat(Color("cbc5a7"))
 for c in ["a79b7b","bbb397","969884","b2a084"]:
  city_materials.append(textured("plastered_stone_wall",Color(c),1.0))

func mat(color: Color, rough = 0.85, metallic = 0.0) -> StandardMaterial3D:
 var m = StandardMaterial3D.new()
 m.albedo_color = color
 m.roughness = rough
 m.metallic = metallic
 return m

func textured(id: String, color: Color, scale_uv: float) -> StandardMaterial3D:
 var m = mat(color)
 m.albedo_texture = load("res://assets/"+id+"_Diffuse.jpg")
 m.normal_enabled = true
 m.normal_texture = load("res://assets/"+id+"_nor_gl.jpg")
 m.normal_scale = 0.55
 m.uv1_scale = Vector3.ONE*scale_uv
 m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
 return m

func add_mesh(parent: Node3D, mesh: Mesh, material: Material, pos = Vector3.ZERO, scale_v = Vector3.ONE) -> MeshInstance3D:
 var n = MeshInstance3D.new()
 n.mesh = mesh
 n.material_override = material
 n.position = pos
 n.scale = scale_v
 parent.add_child(n)
 return n

func box(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
 var m = BoxMesh.new()
 m.size = size
 return add_mesh(parent,m,material,pos)

func cylinder(parent: Node3D, pos: Vector3, bottom: float, top: float, h: float, material: Material, segments = 16) -> MeshInstance3D:
 var m = CylinderMesh.new()
 m.bottom_radius = bottom
 m.top_radius = top
 m.height = h
 m.radial_segments = segments
 return add_mesh(parent,m,material,pos)

func sphere(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
 var m = SphereMesh.new()
 m.radius = 1.0
 m.height = 2.0
 m.radial_segments = 16
 m.rings = 8
 return add_mesh(parent,m,material,pos,size)

func ribbon(curve: Curve3D, width: float, material: Material, parent: Node3D, height: Callable):
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var count = int(curve.get_baked_length()/0.65)
 for i in range(count+1):
  var t = float(i)/count*curve.get_baked_length()
  var p = curve.sample_baked(t)
  var ahead = curve.sample_baked(minf(t+0.2,curve.get_baked_length()))
  if i == count: ahead = p+(p-curve.sample_baked(t-0.2))
  var side = Vector3(-(ahead-p).z,0,(ahead-p).x).normalized()*width*0.5
  for sign_v in [-1,1]:
   var v = p+side*sign_v
   v.y = height.call(v.x,v.z)+0.09
   st.set_uv(Vector2((sign_v+1)*0.5,t/width))
   st.add_vertex(v)
 for i in range(count):
  var a = i*2
  for idx in [a,a+1,a+2,a+1,a+3,a+2]: st.add_index(idx)
 st.generate_normals()
 add_mesh(parent,st.commit(),material)

func roof(parent: Node3D, pos: Vector3, w: float,d: float,h: float, material: Material):
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var v = [Vector3(-w/2,0,-d/2),Vector3(w/2,0,-d/2),Vector3(0,h,-d/2),Vector3(-w/2,0,d/2),Vector3(w/2,0,d/2),Vector3(0,h,d/2)]
 for i in [0,1,2,3,5,4,0,5,3,0,2,5,1,5,2,1,4,5]:
  st.set_uv(Vector2(v[i].x,v[i].z))
  st.add_vertex(v[i])
 st.generate_normals()
 st.index()
 var m = add_mesh(parent,st.commit(),material,pos)
 return m

func house(parent: Node3D, pos: Vector3, w: float,d: float,h: float, angle: float, rng: RandomNumberGenerator, rich = false):
 var n = Node3D.new()
 parent.add_child(n)
 n.position = pos
 n.rotation.y = angle
 box(n,Vector3(0,h/2,0),Vector3(w,h,d),city_materials[rng.randi_range(0,3)])
 box(n,Vector3(0,0.18,0),Vector3(w+0.15,0.36,d+0.15),stone)
 roof(n,Vector3(0,h,0),w+0.34,d+0.32,w*0.60,slate)
 # Timber frame, roof ridge, chimney, recessed doors and windows.
 for x in [-w/2+0.06,w/2-0.06]:
  box(n,Vector3(x,h/2,d/2+0.015),Vector3(0.08,h,0.08),wood)
 box(n,Vector3(0,h*0.54,d/2+0.03),Vector3(w,0.09,0.08),wood)
 box(n,Vector3(0,h+w*0.60,0),Vector3(0.13,0.13,d+0.42),slate)
 box(n,Vector3(w*0.27,h+w*0.35,-d*0.26),Vector3(0.28,0.8,0.28),stone)
 box(n,Vector3(0,0.30,d/2+0.045),Vector3(0.28,0.60,0.05),wood)
 for x in [-w*0.28,w*0.28]:
  box(n,Vector3(x,h*0.73,d/2+0.05),Vector3(0.19,0.28,0.05),dark)
  if rich: box(n,Vector3(x,h*0.73,d/2+0.085),Vector3(0.025,0.29,0.025),brass)
 return n

func tower(parent: Node3D, pos: Vector3, radius: float, h: float, pointed = false):
 cylinder(parent,pos+Vector3(0,h/2,0),radius*1.13,radius,h,stone,20)
 cylinder(parent,pos+Vector3(0,h-0.12,0),radius*1.19,radius*1.19,0.4,stone,20)
 if pointed:
  cylinder(parent,pos+Vector3(0,h+radius*0.9,0),radius*1.35,0,radius*1.9,slate,20)
 else:
  for i in range(10):
   var a = i*TAU/10
   var b = box(parent,pos+Vector3(cos(a)*radius*1.04,h+0.25,sin(a)*radius*1.04),Vector3(0.37,0.60,0.38),stone)
   b.rotation.y = -a
 for a in [0.0,PI/2,PI,PI*1.5]:
  var b = box(parent,pos+Vector3(sin(a)*radius,h*0.68,cos(a)*radius),Vector3(0.13,0.45,0.05),dark)
  b.rotation.y = a

func wall(parent: Node3D,a: Vector3,b: Vector3,h: float):
 var d = b-a
 var center = (a+b)*0.5+Vector3(0,h/2,0)
 var mesh = box(parent,center,Vector3(d.length(),h,0.6),stone)
 mesh.rotation.y = -atan2(d.z,d.x)
 for i in range(int(d.length()/0.75)+1):
  var p = a.lerp(b,float(i)/maxi(1,int(d.length()/0.75)))+Vector3(0,h+0.16,0)
  var merlon = box(parent,p,Vector3(0.39,0.38,0.70),stone)
  merlon.rotation.y = mesh.rotation.y

func banner(parent: Node3D,pos: Vector3,size_v: float):
 cylinder(parent,pos+Vector3(0,size_v*0.7,0),0.035,0.025,size_v*1.6,wood,8)
 var mesh = PlaneMesh.new()
 mesh.orientation = PlaneMesh.FACE_Z
 mesh.size = Vector2(size_v*0.65,size_v*0.40)
 mesh.subdivide_width = 10
 mesh.subdivide_depth = 5
 var m = ShaderMaterial.new()
 m.shader = load("res://banner.gdshader")
 add_mesh(parent,mesh,m,pos+Vector3(size_v*0.32,size_v*1.30,0))
 # Brass diamond heraldry, deliberately legible at campaign scale.
 var crest = box(parent,pos+Vector3(size_v*0.29,size_v*1.30,0.025),Vector3(size_v*0.1,size_v*0.1,0.015),brass)
 crest.rotation.z = PI/4

func batch(root: Node3D, exclude: Array = []):
 # Collapse static architecture by material to avoid thousands of draw calls.
 var groups = {}
 var nodes = root.find_children("*","MeshInstance3D",true,false)
 for node in nodes:
  var skip = false
  for other in exclude:
   if other and other.is_ancestor_of(node): skip = true
  if skip: continue
  if node.mesh == null: continue
  if node.material_override is ShaderMaterial: continue
  var relative = root.global_transform.affine_inverse()*node.global_transform
  for s in range(node.mesh.get_surface_count()):
   var material = node.material_override if node.material_override else node.mesh.surface_get_material(s)
   if material == null: continue
   var key = material.get_instance_id()
   if not groups.has(key):
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    groups[key] = {"st":st,"material":material}
   groups[key].st.append_from(node.mesh,s,relative)
  node.free()
 for group in groups.values():
  add_mesh(root,group.st.commit(),group.material)
