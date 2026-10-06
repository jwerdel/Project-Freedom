extends "res://visuals/landmarks/landmark_base.gd"
# Emberdeep (world bible landmark 13, Hold Emberdeep, the dwarves' High King): a gate carved as two
# colossal dwarf kings in a red mountain face, forge vents glowing in the rock, carved halls in tiers
# and the Hall of the Book of Grudges within. Style after the dwarf-hold reference image (the file
# docs/reference/landmarks/brinecrag.jpg, which shows a dwarf hold, not Brinecrag).
# Stage 1: the mountain face, the gate and the two kings. Stage 2: carved tiers and forge vents.
# Stage 3: the curved outer wall, its towers and the foundries outside.

const RED = Color("8e3e2a")
const DARK_RED = Color("5e2618")
const STONE = Color("6e6a66")
const FORGE = Color("ff8a2a")

func make():
 var c = at(0,0)
 # The mountain face: a red massif behind (local -z), steepest toward the gate.
 for i in 9:
  var x = -24.0+i*6.0
  S.cone(self,9.0,30.0+10.0*sin(i*1.3)+(8.0 if i == 4 else 0.0),c+Vector3(x,0,-14.0-absf(x)*0.2),RED.lerp(DARK_RED,float(i%3)/3.0),7)
 # The gate and the two kings.
 S.box(self,Vector3(8.0,12.0,3.0),c+Vector3(0,0,-6.0),STONE)
 S.box(self,Vector3(4.6,8.0,0.4),c+Vector3(0,0,-4.4),Color("2a2018"))
 S.gable(self,8.6,3.4,3.0,c+Vector3(0,12.0,-6.0),STONE)
 for s in [-1.0,1.0]:
  var p = c+Vector3(s*7.5,0,-5.0)
  S.box(self,Vector3(4.0,2.0,4.0),p,STONE.darkened(0.1))
  S.cylinder(self,1.8,2.4,9.0,p+Vector3(0,2.0,0),STONE,8) # body
  S.cone(self,2.0,3.0,p+Vector3(0,7.0,0.8),STONE.lightened(0.1),8) # the beard
  S.dome(self,1.5,p+Vector3(0,11.0,0),STONE,1.2) # head
  S.box(self,Vector3(0.6,11.0,0.6),p+Vector3(s*-1.6,1.0,1.6),STONE.darkened(0.15)) # the axe haft
 features.append("king_gate")
 if stage>=2:
  for k in 3:
   for i in 5:
    var x = -16.0+i*8.0
    if absf(x)<6.0 and k == 0: continue
    var p = c+Vector3(x,5.0+k*7.0,-9.0-k*2.0)
    S.box(self,Vector3(5.0,4.0,2.0),p,STONE)
    K.glow(self,p+Vector3(0,1.0,1.05),Vector3(1.6,1.6,0.1),FORGE,2.4)
  for x in [-12.0,10.0]: K.glow(self,c+Vector3(x,8.0,-12.0),Vector3(0.6,9.0,0.4),FORGE,2.0) # lava channels
  features.append("carved_tiers")
 if stage>=3:
  for i in 9:
   var a = PI*0.1+i*PI*0.8/8.0
   var p = at(cos(a)*16.0,sin(a)*12.0+2.0)
   var n = K.node(self,p,-a+PI*0.5)
   S.box(n,Vector3(6.2,8.0,3.0),Vector3(0,-2.0,0),STONE)
   if i%2 == 0: K.square_tower(self,p,4.0,10.0,STONE,null)
  for x in [-22.0,22.0]:
   S.box(self,Vector3(6.0,4.0,5.0),at(x,6.0),STONE.darkened(0.1))
   S.cylinder(self,0.6,0.8,7.0,at(x,6.0)+Vector3(1.5,4.0,0),STONE,6)
   K.glow(self,at(x,6.0)+Vector3(0,1.0,2.55),Vector3(2.0,1.4,0.1),FORGE,2.4)
  features.append("outer_wall")
