extends Node3D
# Prototype visual for one Greyhaven development stage (1 town, 2 walled city, 3 expanded city).
# The owner positions this node on the terrain, adds it to the tree, then calls build().

const ProtoKit = preload("res://visuals/common/proto_kit.gd")

@export_range(1,3) var stage := 1

# ctx.height: Callable(x, z) -> terrain height; ctx.plaza_material: the current road surface.
func build(ctx: Dictionary):
 var kit = ProtoKit.shared()
 var height: Callable = ctx.height
 var rng = RandomNumberGenerator.new()
 rng.seed = 934
 kit.cylinder(self,Vector3(0,0.04,0),8.1,8.1,0.10,ctx.plaza_material,64)
 var count = 20+stage*15
 for i in range(count):
  var a = i*2.39996
  var r = 2.7+sqrt(float(i)/count)*(4.0+stage*0.65)
  var p = Vector3(cos(a)*r,0,sin(a)*r)
  if abs(p.x)<0.75 or (abs(p.z)<0.8): continue
  var w = rng.randf_range(0.65,1.12)
  kit.house(self,p,w,rng.randf_range(0.9,1.65),rng.randf_range(0.8,1.45)+stage*0.12,-a,rng,stage>1)
 # Keep, great hall, chapel, market square.
 kit.box(self,Vector3(0,1.25,-1.8),Vector3(2.6,2.5,2.3),kit.stone)
 kit.roof(self,Vector3(0,2.5,-1.8),2.9,2.7,1.6,kit.slate)
 kit.tower(self,Vector3(-1.6,0,-2.8),0.65,4.1,true)
 kit.tower(self,Vector3(1.6,0,-2.8),0.65,4.1,true)
 kit.banner(self,Vector3(0,4.1,-1.8),1.6)
 kit.cylinder(self,Vector3(0,0.22,1.5),0.85,0.85,0.3,kit.stone,24)
 kit.cylinder(self,Vector3(0,0.55,1.5),0.18,0.28,0.65,kit.stone)
 for i in range(4):
  var p = Vector3(-2.8+i*1.8,0,3.4)
  kit.box(self,p+Vector3(0,0.8,0),Vector3(1.0,0.1,0.7),kit.sail)
  kit.box(self,p+Vector3(0,0.3,0),Vector3(0.85,0.55,0.55),kit.wood)
  for dx in [-0.43,0.43]: kit.cylinder(self,p+Vector3(dx,0.45,0),0.035,0.035,0.9,kit.wood,6)
 if stage>=2:
  for i in range(12):
   var a = i*TAU/12
   var b = (i+1)*TAU/12
   var p = Vector3(cos(a)*8.7,0,sin(a)*8.7)
   var q = Vector3(cos(b)*8.7,0,sin(b)*8.7)
   if i!=2 and i!=8: kit.wall(self,p,q,1.6)
   kit.tower(self,p,0.47,2.35)
 if stage>=3:
  for i in range(14):
   var a = i*2.399
   var p = Vector3(cos(a)*11.0,0,sin(a)*10.0)
   p.y = height.call(position.x+p.x,position.z+p.z)-position.y
   kit.house(self,p,0.95,1.6,1.8,-a,rng,true)
  kit.tower(self,Vector3(3.3,0,-3.9),0.85,5.2,true)
 kit.batch(self)
