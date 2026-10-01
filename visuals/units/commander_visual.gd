extends Node3D
# Prototype armored commander at campaign-map scale (deliberately oversized; see constitution.md).

const ProtoKit = preload("res://visuals/common/proto_kit.gd")

func _ready():
 var kit = ProtoKit.shared()
 # Sculpted plate-armour silhouette with articulated limbs and cloth, not a block figure.
 var n = self
 kit.cylinder(n,Vector3(0,0.08,0),1.1,1.1,0.16,kit.stone,48)
 for x in [-0.30,0.30]:
  kit.sphere(n,Vector3(x,0.36,0.12),Vector3(0.22,0.20,0.40),kit.iron)
  kit.sphere(n,Vector3(x,0.92,0),Vector3(0.18,0.56,0.22),kit.iron)
  kit.sphere(n,Vector3(x,1.46,-0.02),Vector3(0.24,0.23,0.26),kit.brass)
  kit.sphere(n,Vector3(x,1.92,0),Vector3(0.26,0.50,0.28),kit.iron)
 kit.sphere(n,Vector3(0,2.45,0),Vector3(0.55,0.42,0.33),kit.dark)
 kit.sphere(n,Vector3(0,2.99,0),Vector3(0.61,0.70,0.35),kit.iron)
 for y in [2.45,2.62,2.79]:
  kit.sphere(n,Vector3(0,y,0.04),Vector3(0.57,0.15,0.36),kit.iron)
 for x in [-0.76,0.76]:
  kit.sphere(n,Vector3(x,3.37,0),Vector3(0.39,0.28,0.42),kit.iron)
  kit.sphere(n,Vector3(x*1.13,2.92,0),Vector3(0.21,0.40,0.23),kit.iron)
  kit.sphere(n,Vector3(x*1.22,2.45,0.12),Vector3(0.19,0.37,0.21),kit.iron)
  kit.sphere(n,Vector3(x*1.24,2.08,0.16),Vector3(0.16,0.20,0.18),kit.dark)
 kit.cylinder(n,Vector3(0,3.70,0),0.25,0.24,0.32,kit.brass)
 kit.sphere(n,Vector3(0,4.02,0),Vector3(0.34,0.43,0.33),kit.iron)
 kit.box(n,Vector3(0,4.08,0.321),Vector3(0.50,0.058,0.07),kit.dark)
 kit.box(n,Vector3(0,3.95,0.345),Vector3(0.055,0.31,0.07),kit.brass)
 for x in [-0.15,-0.075,0.075,0.15]:
  kit.box(n,Vector3(x,3.88,0.317),Vector3(0.028,0.11,0.055),kit.dark)
 # Raised central breastplate crest.
 var crest = kit.box(n,Vector3(0,3.15,0.35),Vector3(0.20,0.27,0.035),kit.brass)
 crest.rotation.z = PI/4
 # Shield, blade and scabbard.
 kit.sphere(n,Vector3(-1.04,2.47,0.42),Vector3(0.47,0.68,0.12),kit.brass)
 kit.sphere(n,Vector3(-1.04,2.47,0.52),Vector3(0.40,0.60,0.05),kit.mat(Color("204b4a")))
 kit.box(n,Vector3(-1.04,2.47,0.58),Vector3(0.09,0.9,0.025),kit.brass)
 kit.box(n,Vector3(-1.04,2.47,0.58),Vector3(0.55,0.09,0.025),kit.brass)
 kit.box(n,Vector3(0.94,1.24,0.16),Vector3(0.11,1.70,0.07),kit.iron)
 kit.box(n,Vector3(0.94,2.02,0.16),Vector3(0.49,0.10,0.11),kit.brass)
 # Curved shoulder cape.
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for y in range(12):
  for x in range(12):
   for off in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
    var u = (x+off.x)/12
    var v = (y+off.y)/12
    st.set_uv(Vector2(u,v))
    st.add_vertex(Vector3((u-0.5)*(1.25+v*0.4),3.5-v*2.7,-0.3-v*0.5-sin(u*PI*6)*0.09))
 st.generate_normals()
 var cloth = ShaderMaterial.new()
 cloth.shader = load("res://banner.gdshader")
 kit.add_mesh(n,st.commit(),cloth)
 kit.banner(n,Vector3(1.3,0,-0.4),3.4)

# Faction colors on the cape and banner (banner.gdshader tint). Called after _ready by the map.
func set_banner_color(c: Color):
 for m in find_children("*","MeshInstance3D",true,false):
  var mat = m.material_override
  if mat is ShaderMaterial and mat.shader != null and mat.shader.resource_path == "res://banner.gdshader": mat.set_shader_parameter("tint",c)
