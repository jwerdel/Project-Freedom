extends Node3D
# Prototype farming village (Willowmere): a ring of houses and a windmill.
# Legacy prototype layout: the node stays at the origin and builds in world space.

const ProtoKit = preload("res://visuals/common/proto_kit.gd")

var rotors: Array = []

# ctx.center: Vector2 village center; ctx.ground: Callable(Vector2) -> Vector3 on terrain;
# ctx.rng: the world RandomNumberGenerator (shared so generation order stays stable).
func build(ctx: Dictionary):
 var kit = ProtoKit.shared()
 var ground: Callable = ctx.ground
 var rng: RandomNumberGenerator = ctx.rng
 for i in range(12):
  var a = i*2.399
  var p = ctx.center+Vector2(cos(a),sin(a))*(2.2+sqrt(i)*0.7)
  kit.house(self,ground.call(p),rng.randf_range(0.9,1.3),1.7,1.05,-a,rng)
 var windmill = Node3D.new()
 add_child(windmill)
 windmill.position = ground.call(ctx.center+Vector2(-7,2))
 kit.cylinder(windmill,Vector3(0,1.7,0),0.8,0.5,3.4,kit.plaster)
 kit.cylinder(windmill,Vector3(0,3.8,0),0.8,0,1.1,kit.slate)
 var rotor = Node3D.new()
 windmill.add_child(rotor)
 rotor.position = Vector3(0,2.9,0.65)
 for i in range(4):
  var arm = Node3D.new()
  rotor.add_child(arm)
  arm.rotation.z = i*PI/2
  kit.box(arm,Vector3(0,1.1,0),Vector3(0.12,2.2,0.1),kit.wood)
  kit.box(arm,Vector3(0.25,1.35,0.02),Vector3(0.45,1.4,0.06),kit.sail)
 rotors.append(rotor)
