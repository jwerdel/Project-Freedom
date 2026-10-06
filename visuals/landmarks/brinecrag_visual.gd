extends "res://visuals/landmarks/landmark_base.gd"
# Brinecrag (world bible landmark 15, the Reavers of Brinecrag; was Saltborn): towers on grey sea
# stacks linked by rope bridges, slave pens, and ships with black sails. The reference image in
# docs/reference/landmarks/brinecrag.jpg shows a dwarf hold instead (used for Emberdeep), so this
# follows the world bible's description.
# Stage 1: the main stack and its spiked tower. Stage 2: more stacks, towers and rope bridges.
# Stage 3: the pens, the docks and the black-sailed fleet.

const ROCK = Color("5a5e62")
const BLACK = Color("26222c")
const VIOLET = Color("b05aff")
const IRON = Color("6a6a76")

func _stack(x: float,z: float,height: float,r: float) -> Vector3:
 var base = Vector3(x,-3.0,z)
 S.cylinder(self,r*0.8,r,height+3.0,base,ROCK,7)
 S.cylinder(self,r*0.9,r*0.8,1.0,base+Vector3(0,height+3.0,0),ROCK.darkened(0.1),7)
 return Vector3(x,height+1.0,z)

func _spike_tower(top: Vector3,height: float,r: float):
 S.cylinder(self,r*0.7,r,height,top,BLACK,5)
 S.spike(self,r*0.9,height*0.5,top+Vector3(0,height,0),BLACK.lightened(0.1))
 for i in 3: S.spike(self,0.2,2.0,top+Vector3(cos(i*2.1)*r,height*0.7,sin(i*2.1)*r),IRON,Vector3(cos(i*2.1)*0.6,0,sin(i*2.1)*0.6))
 K.glow(self,top+Vector3(0,height*0.6,r*0.75),Vector3(0.5,1.0,0.1),VIOLET,2.6)

func make():
 var main = _stack(0.0,6.0,16.0,6.0)
 _spike_tower(main,14.0,2.6)
 features.append("main_stack")
 if stage>=2:
  var tops = [main]
  for p in [Vector3(-12.0,0,10.0),Vector3(11.0,0,13.0),Vector3(-4.0,0,20.0)]:
   var t = _stack(p.x,p.z,11.0+absf(p.x)*0.2,3.5)
   _spike_tower(t,8.0,1.6)
   tops.append(t)
  for i in range(1,tops.size()): K.arch_bridge(self,tops[0]+Vector3(0,2.0,0),tops[i]+Vector3(0,2.0,0),1.0,0.0,1,Color("4a3a2a"),false)
  features.append("rope_bridges")
 if stage>=3:
  for i in 3:
   var p = at(-14.0+i*6.0,-6.0)
   for k in 4: S.box(self,Vector3(0.15,2.4,0.15),p+Vector3(-1.5+k,0,1.5),IRON) # pens
   S.box(self,Vector3(3.6,0.2,3.6),p+Vector3(0,2.4,0),IRON)
  for i in 4:
   var p = Vector3(-14.0+i*9.0,0.0,30.0)
   S.box(self,Vector3(1.4,0.9,5.5),p,Color("2a2420"))
   S.box(self,Vector3(0.15,5.0,0.15),p+Vector3(0,0.9,0),Color("2a2420"))
   S.box(self,Vector3(2.8,2.4,0.06),p+Vector3(0,2.6,0.2),Color("141214"))
  features.append("black_fleet")
