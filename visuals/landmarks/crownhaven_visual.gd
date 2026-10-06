extends "res://visuals/landmarks/landmark_base.gd"
# Crownhaven (world bible landmark 2, Roman; docs/reference/landmarks/crowhevan.jpg for style): the
# old imperial capital on three hills: the Senate House (a domed temple front) on the forum, the
# triumphal Road of the Seven lined with the gods' statues, the ruined arena (the Wyrm Pit), walls
# and an aqueduct.
# Stage 1: the Senate House on its hill. Stage 2: the forum, the Road of the Seven, the walls.
# Stage 3: the Wyrm Pit, the aqueduct, the third hill's fortress and the whole city.

const STONE = Color("e6d8b8")
const MARBLE = Color("f2ece0")
const TILE = Color("b5533a")
const BRONZE = Color("6f8a7a")

func _hill(cx: float,cz: float,r: float,height: float) -> Vector3:
 var g = at(cx,cz)
 S.cylinder(self,r*0.82,r,height,g,STONE.darkened(0.12),16)
 return g+Vector3(0,height,0)

func make():
 # The Senate hill.
 var top = _hill(-8.0,-6.0,11.0,5.0)
 S.box(self,Vector3(12.0,1.2,9.0),top,MARBLE)
 S.box(self,Vector3(9.0,6.0,7.0),top+Vector3(0,1.2,-0.6),MARBLE)
 S.colonnade(self,-4.2,4.2,3.6,7,5.4,0.3,MARBLE.lightened(0.2),1.2)
 S.gable(self,9.6,2.2,1.6,top+Vector3(0,7.2,3.4),TILE)
 K.dome(self,top+Vector3(0,7.2,-1.5),3.6,2.0,MARBLE,BRONZE,2.0)
 features.append("senate_house")
 if stage>=2:
  # The forum and the Road of the Seven: seven statues in two rows to the gate.
  var f0 = at(0,4)
  S.box(self,Vector3(10.0,0.3,22.0),f0,MARBLE.darkened(0.06))
  for i in 7:
   var s = -1.0 if i%2 == 0 else 1.0
   K.statue(self,at(s*4.2,-4.0+i*2.6),5.5,Color("9aa09a"),PI)
  features.append("road_of_the_seven")
  K.wall_ring(self,h,Vector3(0,0,0),30.0,6.0,2.2,STONE,16.0,[PI*0.5,0.0],TILE)
  features.append("walls")
  K.houses(self,h,"roman",Vector3.ZERO,12.0,28.0,22 if stage == 2 else 34,411,0.2,func(p): return p.distance_to(Vector2(-8,-6))<12.0 or absf(p.x)<5.5 and p.y>-6.0)
 if stage>=3:
  # The Wyrm Pit: an oval arena with a broken rim.
  var ac = at(12.0,-10.0)
  for i in 28:
   var a = i*TAU/28
   if i in [3,4,5]: continue # the ruined side
   var hh = 6.0 if i%5 != 0 else 4.0
   var n = K.node(self,ac+Vector3(cos(a)*8.0,0,sin(a)*5.6),-a+PI*0.5)
   S.box(n,Vector3(1.9,hh,1.6),Vector3.ZERO,STONE)
   S.box(n,Vector3(1.0,1.6,1.62),Vector3(0,1.0,0),Color("2a2018"))
  features.append("wyrm_pit")
  # The aqueduct striding in from the hills.
  K.arch_bridge(self,at(-30.0,18.0),at(-6.0,18.0),2.0,7.0,7,STONE,false)
  features.append("aqueduct")
  var t3 = _hill(10.0,14.0,7.0,4.0)
  K.square_tower(self,t3,4.0,8.0,STONE,TILE)
  features.append("three_hills")
