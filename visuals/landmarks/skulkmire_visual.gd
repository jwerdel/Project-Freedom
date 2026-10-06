extends "res://visuals/landmarks/landmark_base.gd"
# The Skulkmire (world bible landmark 12, the Skulkmire Brood; docs/reference/landmarks/skulkmire.jpg
# for style): drowned ruins in the swamp, a stepped ruin overgrown with moss, crooked timber towers
# with green-glowing windows and chimneys, rope bridges between them and stilt docks.
# Stage 1: the drowned stepped ruin and one crooked tower. Stage 2: more towers, glowing chimneys,
# bridges. Stage 3: the great bell tower and the stilt docks.

const MOSS = Color("4e5a34")
const STONE = Color("5e5e4e")
const TIMBER = Color("4e3e2c")
const GLOW = Color("8aff5a")

func _tower(x: float,z: float,height: float):
 var p = at(x,z)
 var yy = 0.0
 var lean = 0.0
 var i = 0
 while yy<height:
  lean += 0.04
  S.box(self,Vector3(3.6-i*0.3,2.6,3.6-i*0.3),p+Vector3(i*0.2,yy,0),TIMBER if i%2 == 0 else STONE,Vector3(0,i*0.15,-lean))
  K.glow(self,p+Vector3(i*0.2,yy+1.2,1.7-i*0.15),Vector3(0.5,0.6,0.1),GLOW,2.2)
  yy += 2.6
  i += 1
 S.gable(self,3.0,3.0,2.0,p+Vector3(i*0.2,yy,0),Color("6a3a2a"))
 return p+Vector3(i*0.2,yy,0)

func make():
 var c = at(0,0)
 K.water(self,c+Vector3(0,0.1,0),24.0,Color("3a4a38"))
 S.steps(self,16.0,5,2.2,c,MOSS)
 features.append("drowned_ruin")
 _tower(9.0,4.0,12.0)
 features.append("crooked_towers")
 if stage>=2:
  var tops = []
  for p in [Vector2(-10.0,2.0),Vector2(4.0,-10.0),Vector2(-4.0,11.0)]: tops.append(_tower(p.x,p.y,10.0+absf(p.x)*0.4))
  for t in tops:
   S.cylinder(self,0.4,0.5,5.0,t,STONE,6)
   K.glow(self,t+Vector3(0,5.0,0),Vector3(0.8,0.8,0.8),GLOW,3.0)
  for i in tops.size(): K.arch_bridge(self,tops[i]-Vector3(0,3.0,0),tops[(i+1)%tops.size()]-Vector3(0,3.0,0),1.0,0.0,1,TIMBER,false)
  features.append("green_chimneys")
 if stage>=3:
  var bell = _tower(0.0,0.0,20.0)
  S.dome(self,1.6,bell,Color("6a6a3a"),1.2)
  for i in 8:
   var a = i*TAU/8
   S.box(self,Vector3(1.2,0.3,6.0),at(cos(a)*20.0,sin(a)*20.0,0.6),TIMBER,Vector3(0,-a,0))
  features.append("bell_tower")
