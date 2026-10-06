extends "res://visuals/landmarks/landmark_base.gd"
# Frosthold (world bible landmark 4, House Varn; docs/reference/landmarks/frosthold.jpg for style):
# grey double walls with round towers, a gothic keep, hot springs steaming inside, and the pale-barked
# Hearthtree in the godswood with its red crown.
# Stage 1: the keep, the Hearthtree, the inner wall. Stage 2: the hot springs, the outer wall.
# Stage 3: the keep's spires and greenhouses, the town outside.

const STONE = Color("7d8088")
const SLATE = Color("4b5262")
const BARK = Color("eae6dc")
const LEAVES = Color("a8262a")

func make():
 var c = at(0,0)
 # The keep: a tall gothic block with a steep roof and corner turrets.
 S.box(self,Vector3(11.0,14.0,9.0),c+Vector3(-3.0,0,-2.0),STONE)
 S.gable(self,11.4,9.4,6.0,c+Vector3(-3.0,14.0,-2.0),SLATE)
 for sx in [-1.0,1.0]:
  for sz in [-1.0,1.0]: K.round_tower(self,c+Vector3(-3.0+sx*5.4,0,-2.0+sz*4.4),1.4,16.0,STONE,SLATE,4.0)
 for i in 3: S.box(self,Vector3(0.9,3.2,0.1),c+Vector3(-6.0+i*3.0,6.0,2.55),Color("e8c060"),Vector3.ZERO,1.2)
 features.append("keep")
 # The Hearthtree.
 var t = at(8.0,6.0)
 S.cylinder(self,0.9,1.4,7.0,t,BARK,8)
 for i in 5: S.dome(self,3.2-i*0.3,t+Vector3(cos(i*1.3)*1.8,6.0+i*0.7,sin(i*1.3)*1.8),LEAVES.lightened(i*0.04),0.8)
 features.append("hearthtree")
 K.wall_ring(self,h,c,17.0,7.0,2.4,STONE,13.0,[PI*0.5],SLATE)
 features.append("inner_wall")
 if stage>=2:
  for p in [Vector3(4.0,0,-8.0),Vector3(-10.0,0,8.0),Vector3(2.0,0,10.0)]:
   K.water(self,at(p.x,p.z,0.05),2.4,Color("8fd0d8"))
   S.box(self,Vector3(0.6,1.2,0.6),at(p.x,p.z),Color(1,1,1,1).darkened(0.05)) # a steam marker
  features.append("hot_springs")
  K.wall_ring(self,h,c,24.0,8.5,2.8,STONE,14.0,[PI*0.5,-PI*0.5],SLATE)
  features.append("double_walls")
 if stage>=3:
  for s in [-1.0,1.0]: K.spire(self,c+Vector3(-3.0+s*3.0,14.0,-6.0),1.0,10.0,STONE,SLATE)
  S.box(self,Vector3(6.0,2.8,3.2),at(-9.0,6.0),Color("9ec8b8")) # greenhouse
  K.houses(self,h,"medieval",c,27.0,36.0,22,421)
  features.append("town")
