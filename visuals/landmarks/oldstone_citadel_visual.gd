extends "res://visuals/landmarks/landmark_base.gd"
# Oldstone Citadel (world bible landmark 10, Port Dallow; docs/reference/landmarks/oldstone
# citadel.jpg for style): the scholars' tower-lighthouse with its fire at the top, library domes
# around it, star-shaped bastion walls and a harbour closed by a chain.
# Stage 1: the tower and its fire. Stage 2: the library domes, the bastions.
# Stage 3: the harbour, the chain, the city inside the walls.

const STONE = Color("a8916c")
const DOME = Color("5c78a8")
const BRONZE = Color("8a6a3a")
const FIRE = Color("ff8a2a")

func make():
 var c = at(0,0)
 # The tower: square, stepped, with a lantern and a fire.
 S.box(self,Vector3(7.0,18.0,7.0),c,STONE)
 S.box(self,Vector3(5.6,10.0,5.6),c+Vector3(0,18.0,0),STONE.lightened(0.05))
 S.cylinder(self,2.2,2.6,6.0,c+Vector3(0,28.0,0),STONE.darkened(0.06),10)
 K.glow(self,c+Vector3(0,34.0,0),Vector3(2.6,2.4,2.6),FIRE,3.0)
 for k in 4: S.box(self,Vector3(0.6,1.4,0.1),c+Vector3(-1.5+k,6.0+k*3.0,3.55),Color("2a2018"))
 features.append("lighthouse_tower")
 if stage>=2:
  for i in 5:
   var a = i*TAU/5+0.4
   K.dome(self,at(cos(a)*10.0,sin(a)*10.0),3.0-0.3*(i%2),3.0,STONE.lightened(0.1),DOME if i%2 == 0 else BRONZE)
  features.append("library_domes")
  # Star-shaped bastions: wall points out and in.
  for i in 10:
   var a = i*TAU/10
   var r0 = 22.0 if i%2 == 0 else 17.0
   var r1 = 17.0 if i%2 == 0 else 22.0
   var a1 = (i+1)*TAU/10
   var p0 = at(cos(a)*r0,sin(a)*r0)
   var p1 = at(cos(a1)*r1,sin(a1)*r1)
   var d = p1-p0
   var n = K.node(self,(p0+p1)*0.5,atan2(d.x,d.z))
   S.box(n,Vector3(3.0,8.0,Vector2(d.x,d.z).length()+1.0),Vector3(0,-2.0,0),STONE.darkened(0.05))
  features.append("bastions")
 if stage>=3:
  var front = 26.0
  for s in [-1.0,1.0]: K.round_tower(self,at(s*7.0,front),1.8,7.0,STONE,null)
  S.box(self,Vector3(14.0,0.3,0.3),at(0,front)+Vector3(0,1.4,0),Color("3a3a3a")) # the chain
  K.houses(self,h,"roman",c,11.0,16.0,16,471)
  features.append("harbour_chain")
