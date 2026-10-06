extends "res://visuals/landmarks/landmark_base.gd"
# Tempest Keep (world bible landmark 11, House Durran; docs/reference/landmarks/tempest keep.jpg
# for style): one enormous drum tower on a storm cliff, buttressed and battlemented, a ring of
# curtain wall and a harbour under the cliff.
# Stage 1: the great drum. Stage 2: the curtain ring and its towers. Stage 3: the harbour town.

const STONE = Color("5e5a56")
const DARK = Color("3a3734")

func make():
 var c = at(0,0)
 # The drum: wider at the base, buttresses all round, a battlemented crown.
 S.cylinder(self,10.0,12.0,26.0,c-Vector3(0,2.0,0),STONE,24)
 for i in 12:
  var a = i*TAU/12
  var n = K.node(self,c+Vector3(cos(a)*11.6,0,sin(a)*11.6),-a+PI*0.5)
  S.box(n,Vector3(1.4,14.0,2.2),Vector3(0,-2.0,0),DARK)
 S.cylinder(self,10.6,10.6,1.2,c+Vector3(0,23.0,0),DARK,24)
 for i in 20: S.box(self,Vector3(1.4,1.2,1.0),c+Vector3(cos(i*0.314)*10.2,24.2,sin(i*0.314)*10.2),STONE)
 for k in 3:
  for i in 8: S.box(self,Vector3(0.6,1.4,0.1),c+Vector3(cos(i*0.785)*11.3,6.0+k*6.0,sin(i*0.785)*11.3),Color("1e1a16"),Vector3(0,-i*0.785+PI*0.5,0))
 features.append("great_drum")
 if stage>=2:
  K.wall_ring(self,h,c,18.0,6.5,2.4,STONE,12.0,[-PI*0.5],DARK)
  features.append("curtain")
 if stage>=3:
  K.houses(self,h,"roman",c,20.0,30.0,16,481)
  for i in 4: S.box(self,Vector3(3.0,0.6,5.0),at(-6.0+i*4.0,26.0),Color("6a5038"))
  features.append("harbour_town")
