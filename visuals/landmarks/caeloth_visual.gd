extends "res://visuals/landmarks/landmark_base.gd"
# Caeloth, the Throne City (world bible landmark 1; docs/reference/landmarks/caeloth.jpg for palette
# and style): a vast walled metropolis ringed by marsh-moats, the cathedral of the Undying Throne
# with its golden dome visible from leagues away, spires, bridges and market islands.
# Stage 1: the cathedral and the inner wall. Stage 2: the moat, the outer wall, bridges, the city.
# Stage 3: the full dome lantern and spires, more of the city, the gate towers.

const STONE = Color("d9cfb6")
const GOLD = Color("e2b640")
const SLATE = Color("6a7286")

func make():
 # The Undying Throne: a cross-shaped nave, the great golden dome on a drum, flanking spires.
 var c = at(0,0)
 S.box(self,Vector3(10.0,9.0,24.0),c,STONE)
 S.box(self,Vector3(24.0,8.0,9.0),c,STONE)
 S.gable(self,10.4,24.4,4.0,c+Vector3(0,9.0,0),SLATE,Vector3(0,PI*0.5,0))
 K.dome(self,c+Vector3(0,9.0,0),7.5,6.0,STONE,GOLD,14.0 if stage>=3 else 6.0)
 for s in [-1.0,1.0]: K.spire(self,c+Vector3(s*5.0,0,-11.0),1.5,22.0 if stage>=2 else 14.0,STONE,GOLD)
 features.append("cathedral")
 K.wall_ring(self,h,c,22.0,6.0,2.2,STONE,16.0,[PI*0.5,-PI*0.5],SLATE)
 features.append("inner_wall")
 if stage>=2:
  K.water(self,c+Vector3(0,0.15,0),31.0,Color("4a86a6"),25.0)
  features.append("moat")
  K.wall_ring(self,h,c,34.0,7.0,2.6,STONE,18.0,[PI*0.5,0.0,PI,-PI*0.5],SLATE)
  features.append("outer_wall")
  for a in [PI*0.5,0.0,PI,-PI*0.5]:
   var p0 = c+Vector3(cos(a)*23.5,0,sin(a)*23.5)
   var p1 = c+Vector3(cos(a)*33.0,0,sin(a)*33.0)
   K.arch_bridge(self,at(p0.x,p0.z),at(p1.x,p1.z),3.6,2.2,3,STONE.darkened(0.05))
  features.append("bridges")
  K.houses(self,h,"medieval",c,13.0,20.5,18 if stage == 2 else 26,401)
 if stage>=3:
  K.houses(self,h,"medieval",c,36.5,42.0,14,402,0.2)
  for i in 6:
   var a = i*TAU/6+0.3
   K.spire(self,c+Vector3(cos(a)*15.0,y(cos(a)*15.0,sin(a)*15.0),sin(a)*15.0),1.0,13.0,STONE,SLATE)
  features.append("spires")
