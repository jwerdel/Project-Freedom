extends Node3D
# Prototype covered wagon with a harnessed pack animal, at campaign-map scale.

const ProtoKit = preload("res://visuals/common/proto_kit.gd")

func _ready():
 var kit = ProtoKit.shared()
 var n = self
 kit.box(n,Vector3(0,0.5,0),Vector3(0.75,0.18,1.25),kit.wood)
 kit.sphere(n,Vector3(0,0.87,0),Vector3(0.42,0.46,0.69),kit.sail)
 for x in [-0.46,0.46]:
  for z in [-0.43,0.43]:
   var wheel = kit.cylinder(n,Vector3(x,0.34,z),0.28,0.28,0.1,kit.dark,12)
   wheel.rotation.z = PI/2
 # Small harnessed pack animal at map scale.
 kit.sphere(n,Vector3(0,0.68,-1.65),Vector3(0.24,0.29,0.5),kit.wood)
 kit.sphere(n,Vector3(0,0.97,-2.04),Vector3(0.15,0.23,0.21),kit.wood)
 for x in [-0.16,0.16]:
  for z in [-1.92,-1.35]: kit.cylinder(n,Vector3(x,0.30,z),0.045,0.04,0.6,kit.wood,6)
