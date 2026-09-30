extends Node3D
# Prototype hill fortress (Crownwatch): hexagonal curtain wall, six towers, central keep.

const ProtoKit = preload("res://visuals/common/proto_kit.gd")

func _ready():
 var kit = ProtoKit.shared()
 var n = self
 kit.cylinder(n,Vector3(0,0.15,0),4.8,4.3,0.5,kit.stone,32)
 for i in range(6):
  var a = i*TAU/6
  var b = (i+1)*TAU/6
  var from = Vector3(cos(a)*3.6,0.2,sin(a)*3.6)
  var to = Vector3(cos(b)*3.6,0.2,sin(b)*3.6)
  if i!=1: kit.wall(n,from,to,2.0)
  kit.tower(n,from,0.72,3.7)
 kit.box(n,Vector3(0,2.0,-0.5),Vector3(2.6,3.8,2.6),kit.stone)
 kit.roof(n,Vector3(0,3.9,-0.5),2.9,2.9,1.6,kit.slate)
 kit.banner(n,Vector3(0,5.6,-0.5),2.0)
