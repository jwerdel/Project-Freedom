extends Node3D
# Prototype single-masted trading ship, at campaign-map scale.

const ProtoKit = preload("res://visuals/common/proto_kit.gd")

func _ready():
 var kit = ProtoKit.shared()
 var n = self
 var hull = kit.sphere(n,Vector3(0,0.35,0),Vector3(0.73,0.48,2.05),kit.wood)
 hull.rotation.z = 0.02
 kit.box(n,Vector3(0,0.58,0),Vector3(1.0,0.12,2.8),kit.wood)
 kit.cylinder(n,Vector3(0,2.1,0),0.065,0.045,3.4,kit.wood,10)
 for y in [2.2,3.4]:
  var spar = kit.cylinder(n,Vector3(0,y,0),0.04,0.04,2.5,kit.wood,8)
  spar.rotation.z = PI/2
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for y in range(8):
  for x in range(10):
   for off in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
    var u = (x+off.x)/10
    var v = (y+off.y)/8
    st.add_vertex(Vector3((u-0.5)*2.35,2.0+v*1.42,sin(u*PI)*sin(v*PI)*0.48))
 st.generate_normals()
 var sm = kit.sail.duplicate()
 sm.cull_mode = BaseMaterial3D.CULL_DISABLED
 kit.add_mesh(n,st.commit(),sm)
 kit.banner(n,Vector3(0,3.6,0),0.65)
