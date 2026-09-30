extends Node3D
# Prototype harbor: twin piers, quay with cargo, harbor house and lighthouse.
# Legacy prototype layout: the node stays at the origin and builds in world space.

const ProtoKit = preload("res://visuals/common/proto_kit.gd")

# ctx.coast: Callable(x) -> shoreline z; ctx.ground: Callable(Vector2) -> Vector3 on terrain;
# ctx.rng: the world RandomNumberGenerator (shared so generation order stays stable).
func build(ctx: Dictionary):
 var kit = ProtoKit.shared()
 var coast: Callable = ctx.coast
 var ground: Callable = ctx.ground
 var rng: RandomNumberGenerator = ctx.rng
 var z = coast.call(-18)
 for x in [-21.0,-16.0]:
  kit.box(self,Vector3(x,0.85,z+2),Vector3(1.4,0.35,9.0),kit.wood)
  for j in range(5):
   for side in [-0.55,0.55]:
    kit.cylinder(self,Vector3(x+side,0.15,z-1+j*1.6),0.12,0.12,2.1,kit.wood,8)
 kit.box(self,Vector3(-18.5,0.9,z-1.8),Vector3(8,0.4,2),kit.wood)
 for i in range(5):
  kit.box(self,Vector3(-21+rng.randf()*6,1.35,z-2+rng.randf()),Vector3(0.5,0.6,0.5),kit.wood)
 kit.house(self,ground.call(Vector2(-24,z-4)),2,3,1.6,0,rng)
 var lighthouse_pos = Vector2(-5,coast.call(-5)-3)
 kit.tower(self,ground.call(lighthouse_pos),0.7,3.7,true)
