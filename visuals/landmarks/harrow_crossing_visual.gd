extends "res://visuals/landmarks/landmark_base.gd"
# Harrow Crossing (world bible landmark 8, House Tollan; docs/reference/landmarks/harrow
# crossing.jpg for style): two identical castles joined by a long fortified bridge with a tower at
# its middle.
# Stage 1: the two keeps and the bridge. Stage 2: the castles' curtain walls and the bridge tower.
# Stage 3: the market towns at both ends.

const STONE = Color("cfc8b8")
const ROOF = Color("4a5a78")

func _castle(cx: float):
 var c = at(cx,0)
 K.square_tower(self,c,6.0,13.0,STONE,ROOF)
 for k in 2: K.round_tower(self,c+Vector3(-2.5+k*5.0,0,-3.5),1.3,15.0,STONE,ROOF,3.5)
 if stage>=2: K.wall_ring(self,h,c,9.0,6.0,2.0,STONE,9.0,[PI*0.5 if cx<0 else -PI*0.5],ROOF)

func make():
 _castle(-20.0)
 _castle(20.0)
 features.append("twin_castles")
 K.arch_bridge(self,at(-11.0,0),at(11.0,0),5.0,4.5,6,STONE)
 features.append("fortified_bridge")
 if stage>=2:
  K.round_tower(self,at(0,0)+Vector3(0,4.5,0),2.0,9.0,STONE,ROOF,4.0)
  features.append("bridge_tower")
 if stage>=3:
  K.houses(self,h,"medieval",Vector3(-20.0,0,0),11.0,20.0,14,451)
  K.houses(self,h,"medieval",Vector3(20.0,0,0),11.0,20.0,14,452)
  features.append("towns")
