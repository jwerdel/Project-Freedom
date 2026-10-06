extends "res://visuals/landmarks/landmark_base.gd"
# Wardens' Gate (world bible landmark 5, the Greywall; docs/reference/landmarks/greywall.jpg for
# style): the Wardens' fortress where the road meets the Wall, with its own stretch of colossal
# wall, the gate through it, a switchback stair and a lift cage up the face. The rest of the
# Greywall is drawn along the map's wall line by map/map_view.gd.
# Stage 1: the keep and the gate in the wall. Stage 2: the courtyard walls, the stair.
# Stage 3: the lift cage, more towers, the sheds and smithies outside.

const STONE = Color("8a8d92")
const DARK = Color("4e5258")
const ICE = Color("dfeef4")
const TIMBER = Color("5a432c")

func make():
 # A stretch of the Wall behind the fortress (local -z, away from the road), with the gate.
 for i in 9:
  var x = -24.0+i*6.0
  if absf(x)<3.5: continue
  S.box(self,Vector3(6.2,26.0,8.0),at(x,-16.0)-Vector3(0,4.0,0),STONE)
  S.box(self,Vector3(6.2,2.0,8.2),at(x,-16.0)+Vector3(0,20.0,0),ICE)
 S.box(self,Vector3(7.0,10.0,8.4),at(0,-16.0)+Vector3(0,12.0,0),STONE.darkened(0.05)) # over the gate
 S.box(self,Vector3(5.0,9.0,8.6),at(0,-16.0),Color("1c1a18"))
 # The keep.
 K.square_tower(self,at(-6.0,-4.0),8.0,16.0,STONE,DARK)
 features.append("wall_gate")
 features.append("keep")
 if stage>=2:
  K.wall_ring(self,h,Vector3(0,0,-2.0),13.0,6.0,2.2,STONE,10.0,[PI*0.5],DARK)
  features.append("courtyard")
  # The switchback stair up the Wall's face.
  for k in 4:
   for i in 6:
    var s = 1.0 if k%2 == 0 else -1.0
    S.box(self,Vector3(2.0,0.6,1.4),at(8.0+s*(-3.0+i*1.2),-11.8)+Vector3(0,2.0+k*4.6+i*0.75,0),DARK)
  features.append("stair")
 if stage>=3:
  S.box(self,Vector3(0.25,24.0,0.25),at(-14.0,-11.6),TIMBER) # the lift's rope
  S.box(self,Vector3(2.0,1.8,2.0),at(-14.0,-10.8)+Vector3(0,9.0,0),TIMBER) # the cage
  for x in [-12.0,12.0]: K.square_tower(self,at(x,4.0),4.0,9.0,STONE,DARK)
  K.houses(self,h,"medieval",Vector3(0,0,10.0),10.0,22.0,14,431)
  features.append("lift")
