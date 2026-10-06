extends "res://visuals/landmarks/landmark_base.gd"
# Skyreach (world bible landmark 7, House Aldane; docs/reference/landmarks/skyreach.jpg for style):
# white towers on a peak, one stair road winding up, a basket lift, waterfalls down the rock.
# Stage 1: the peak and its summit castle. Stage 2: the road's walls and gate towers, waterfalls.
# Stage 3: the basket lift, more towers, the walled town at the foot.

const ROCK = Color("8a8780")
const WHITE = Color("eef0f2")
const BLUE = Color("4a6f9a")
const TIMBER = Color("5a432c")
const PEAK = 26.0

func make():
 var c = at(0,0)
 # The peak: a craggy cone.
 for i in 7:
  var a = i*TAU/7
  S.cone(self,9.0-i%3,PEAK*(0.55+0.1*(i%3)),c+Vector3(cos(a)*5.0,0,sin(a)*5.0),ROCK.darkened(0.05*(i%3)),7)
 S.cone(self,12.0,PEAK,c,ROCK,9)
 var top = c+Vector3(0,PEAK-3.0,0)
 # The summit castle.
 S.box(self,Vector3(9.0,5.0,9.0),top,WHITE)
 K.round_tower(self,top,2.0,14.0,WHITE,BLUE,4.0)
 for i in 4:
  var a = i*PI*0.5+0.6
  K.round_tower(self,top+Vector3(cos(a)*5.0,0,sin(a)*5.0),1.1,8.0,WHITE,BLUE,3.0)
 features.append("summit_castle")
 if stage>=2:
  # The one road: a spiral of wall segments around the peak with towers.
  for i in 22:
   var u = float(i)/22.0
   var a = u*TAU*1.6
   var r = 11.5-u*6.0
   var n = K.node(self,c+Vector3(cos(a)*r,u*(PEAK-6.0),sin(a)*r),-a)
   S.box(n,Vector3(2.6,1.6,3.0),Vector3.ZERO,WHITE.darkened(0.08))
   if i%6 == 0: K.round_tower(self,n.position,1.0,5.0,WHITE,BLUE,2.5)
  for a in [0.8,2.6]: S.box(self,Vector3(0.6,PEAK*0.7,0.3),c+Vector3(cos(a)*11.0,1.0,sin(a)*11.0),Color("d8eef4"),Vector3(0,-a,0),0.6) # waterfalls
  features.append("stair_road")
 if stage>=3:
  S.box(self,Vector3(0.2,PEAK,0.2),c+Vector3(-9.0,0,6.0),TIMBER)
  S.box(self,Vector3(1.6,1.2,1.6),c+Vector3(-9.0,PEAK*0.45,6.0),TIMBER)
  features.append("basket_lift")
  K.wall_ring(self,h,Vector3(0,0,14.0),10.0,5.0,1.8,WHITE.darkened(0.06),9.0,[PI*0.5],BLUE)
  K.houses(self,h,"medieval",Vector3(0,0,14.0),0.0,8.5,10,441)
