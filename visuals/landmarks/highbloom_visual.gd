extends "res://visuals/landmarks/landmark_base.gd"
# Highbloom (world bible landmark 9, House Verrin; docs/reference/landmarks/highbloom.jpg for style):
# concentric rings of white walls with gardens and orchards between them, a palace at the heart,
# fountains, and an aqueduct.
# Stage 1: the palace and the inner ring. Stage 2: the middle ring, gardens and fountains.
# Stage 3: the outer ring, the aqueduct, orchards and houses.

const WHITE = Color("f0ebe0")
const TILE = Color("b5533a")
const HEDGE = Color("3f7a3a")
const WATER = Color("5aa6c8")

func _gardens(r0: float,r1: float,n: int,seed: int):
 var rng = RandomNumberGenerator.new()
 rng.seed = seed
 for i in n:
  var a = rng.randf()*TAU
  var r = rng.randf_range(r0,r1)
  var p = at(cos(a)*r,sin(a)*r)
  S.box(self,Vector3(rng.randf_range(2.0,3.4),0.8,rng.randf_range(1.2,2.2)),p,HEDGE,Vector3(0,a,0))
  if i%5 == 0: S.dome(self,0.9,p+Vector3(1.6,0,0),HEDGE.lightened(0.1),1.3) # a tree

func make():
 var c = at(0,0)
 S.box(self,Vector3(12.0,5.0,8.0),c,WHITE)
 S.colonnade(self,-5.4,5.4,4.3,8,5.0,0.28,WHITE.lightened(0.3))
 S.hip(self,12.6,8.6,2.2,c+Vector3(0,5.0,0),TILE)
 features.append("palace")
 K.wall_ring(self,h,c,11.0,4.5,1.6,WHITE,10.0,[PI*0.5],TILE)
 features.append("ring_1")
 if stage>=2:
  K.wall_ring(self,h,c,20.0,5.0,1.8,WHITE,12.0,[PI*0.5,-PI*0.5],TILE)
  _gardens(12.5,18.5,22,461)
  for a in [0.4,2.2,4.0]: K.water(self,at(cos(a)*15.0,sin(a)*15.0,0.1),1.2,WATER)
  features.append("ring_2")
 if stage>=3:
  K.wall_ring(self,h,c,30.0,5.5,2.0,WHITE,14.0,[PI*0.5,0.0,PI],TILE)
  _gardens(21.5,28.5,30,462)
  K.houses(self,h,"roman",c,21.5,28.5,14,463)
  K.arch_bridge(self,at(26.0,-8.0),at(46.0,-20.0),1.8,6.0,6,WHITE.darkened(0.05),false)
  features.append("ring_3")
  features.append("aqueduct")
