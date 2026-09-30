extends Node3D
# Prototype visual for one road surface stage. The stage's look is set in its .tscn;
# the route curves come from the owner, so swapping art never changes where roads go.
# The owner adds this node to the tree, then calls build().

const ProtoKit = preload("res://visuals/common/proto_kit.gd")

@export var surface_texture := "coast_sand_01"
@export var surface_color := Color("75664b")
@export var width := 1.0
@export var edge_markers := false

var surface_material: StandardMaterial3D

# ctx.curves: Array[Curve3D] route centerlines; ctx.height: Callable(x, z) -> terrain height.
func build(ctx: Dictionary):
 var kit = ProtoKit.shared()
 var height: Callable = ctx.height
 surface_material = kit.textured(surface_texture,surface_color,1.5)
 surface_material.cull_mode = BaseMaterial3D.CULL_DISABLED
 for c in ctx.curves:
  kit.ribbon(c,width,surface_material,self,height)
  if edge_markers:
   for i in range(2,int(c.get_baked_length()),3):
    var p = c.sample_baked(i)
    var d = (c.sample_baked(i+0.2)-p).normalized()
    var side = Vector3(-d.z,0,d.x)*0.93
    for s in [-1,1]:
     var v = p+side*s
     kit.box(self,Vector3(v.x,height.call(v.x,v.z)+0.13,v.z),Vector3(0.23,0.22,0.48),kit.stone)
 kit.batch(self)
