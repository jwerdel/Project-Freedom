extends Node3D
# Prototype farm field: a terrain-hugging 4.8 m plot with nine furrows.
# Legacy prototype layout: the node stays at the origin and builds in world space.

const ProtoKit = preload("res://visuals/common/proto_kit.gd")

# ctx.origin: Vector2 field corner; ctx.ripe: bool (golden vs green crop);
# ctx.ground: Callable(Vector2, offset) -> Vector3; ctx.height: Callable(x, z) -> float;
# ctx.curve_from: Callable(Array[Vector2]) -> Curve3D following the terrain.
func build(ctx: Dictionary):
 var kit = ProtoKit.shared()
 var ground: Callable = ctx.ground
 var p: Vector2 = ctx.origin
 var material = kit.mat(Color("837b44") if ctx.ripe else Color("666b37"))
 var st = SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for z in range(6):
  for x in range(6):
   for off in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
    st.add_vertex(ground.call(p+Vector2(x,z)*0.8+off*0.8,0.055))
 st.generate_normals()
 kit.add_mesh(self,st.commit(),material)
 for row in range(9):
  var curve = ctx.curve_from.call([p+Vector2(0,row*0.54),p+Vector2(4.8,row*0.54)])
  kit.ribbon(curve,0.085,kit.mat(Color("9a8a53")),self,ctx.height)
