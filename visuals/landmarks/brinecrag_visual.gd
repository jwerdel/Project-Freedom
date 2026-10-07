extends "res://visuals/landmarks/landmark_base.gd"
# Brinecrag (world bible landmark 15, the Reavers of Brinecrag; docs/reference/landmarks/brinecrag.jpg
# for style, not layout): black gothic towers bristling with spikes and needle spires, standing on
# grey sea stacks, linked by sagging chain bridges hung with lantern cages; violet and sickly green
# light in the slit windows; sea gates (spiked arches with portcullises) between the stacks; quays
# and the black-hulled fleet with purple sails below.
# Stage 1: the great stack with its spired citadel, a second stack and their chain bridge.
# Stage 2: more stacks and towers, more chain bridges, the sea gates (its walls).
# Stage 3: the quays, the fleet and the outer stacks.

const ROCK = Color("4a4b52")
const ROCK_DARK = Color("33343a")
const BLACK = Color("1f1c24")
const DARK = Color("2d2933")
const IRON = Color("58566a")
const VIOLET = Color("b05aff")
const GREEN = Color("6aff8e")
const SAIL = Color("4b2a5e")
const HULL = Color("221c20")

# A sea stack: a rough rock column from below the waves to `height`, its top at the returned point.
func _stack(x: float,z: float,height: float,r: float) -> Vector3:
 var base = Vector3(x,-4.0,z)
 S.cylinder(self,r*0.82,r,height*0.55+4.0,base,ROCK,7)
 S.cylinder(self,r*0.7,r*0.84,height*0.45,base+Vector3(0.4,height*0.55+4.0,-0.3),ROCK.lightened(0.04),7,Vector3(0,0.4,0))
 S.cylinder(self,r*0.78,r*0.72,1.0,Vector3(x,height,z),ROCK_DARK,7) # the cap the tower stands on
 for i in 4:
  var a = i*1.7+x*0.13
  S.dome(self,r*0.38,Vector3(x+cos(a)*r*0.95,-0.6,z+sin(a)*r*0.95),ROCK_DARK,0.8) # boulders at the foot
 return Vector3(x,height+1.0,z)

# A black gothic tower: tiers narrowing upward, spikes at every tier's corners, slit windows glowing
# violet (a few green), a needle spire and pinnacles on top. Returns the top of the shaft.
func _spiked_tower(base: Vector3,height: float,r: float,tiers: int) -> Vector3:
 var y0 = 0.0
 var th = height/tiers
 for t in tiers:
  var rr = r*(1.0-0.16*t)
  S.cylinder(self,rr*0.92,rr,th,base+Vector3(0,y0,0),BLACK if t%2 == 0 else DARK,8)
  # Corner spikes, leaning out, and a ring of small ones.
  for k in 4:
   var a = k*PI*0.5+0.4+t*0.3
   S.spike(self,rr*0.18,th*0.55,base+Vector3(cos(a)*rr*0.95,y0+th*0.85,sin(a)*rr*0.95),DARK.lightened(0.1),Vector3(sin(a)*0.45,0,-cos(a)*0.45))
  # Slit windows.
  for k in 3:
   var a = k*2.1+t*0.9
   K.glow(self,base+Vector3(cos(a)*rr*0.97,y0+th*0.45,sin(a)*rr*0.97),Vector3(0.35,th*0.4,0.35),GREEN if (k+t)%4 == 3 else VIOLET,2.6)
  y0 += th
 var top = base+Vector3(0,y0,0)
 var rt = r*(1.0-0.16*(tiers-1))
 S.cone(self,rt*0.85,height*0.55,top,BLACK,8) # the needle spire
 for k in 3:
  var a = k*TAU/3+0.5
  S.cone(self,rt*0.22,height*0.22,top+Vector3(cos(a)*rt*0.75,0,sin(a)*rt*0.75),DARK,6) # pinnacles
 return top

# A chain bridge sagging from a to b (two chains and planks) with lantern cages hanging from it.
func _chain_bridge(a: Vector3,b: Vector3,lanterns := 2):
 var n = maxi(6,int(a.distance_to(b)/1.6))
 var sag = a.distance_to(b)*0.12
 for i in n:
  var t = (i+0.5)/n
  var p = a.lerp(b,t)-Vector3(0,sin(t*PI)*sag,0)
  var d = b-a
  var yaw = atan2(d.x,d.z)
  S.box(self,Vector3(1.4,0.18,a.distance_to(b)/n*1.05),p,Color("3b2f28"),Vector3(0,yaw,0)) # plank
  for s in [-1.0,1.0]: S.box(self,Vector3(0.12,0.12,a.distance_to(b)/n*1.05),p+Vector3(cos(yaw)*s*0.75,0.9,-sin(yaw)*s*0.75),IRON,Vector3(0,yaw,0)) # chain rail
 for k in lanterns:
  var t = (k+1.0)/(lanterns+1.0)
  var p = a.lerp(b,t)-Vector3(0,sin(t*PI)*sag+2.2,0)
  S.box(self,Vector3(0.08,2.0,0.08),p+Vector3(0,1.1,0),IRON)
  S.box(self,Vector3(0.7,0.9,0.7),p,IRON.darkened(0.3))
  K.glow(self,p,Vector3(0.45,0.6,0.45),VIOLET,3.0)

# A sea gate between two stacks: a spiked arch over the water with a portcullis.
func _sea_gate(a: Vector3,b: Vector3,height: float):
 var d = b-a
 var yaw = atan2(d.x,d.z)
 var mid = (a+b)*0.5
 var len = Vector2(d.x,d.z).length()
 var root = K.node(self,Vector3(mid.x,0,mid.z),yaw)
 S.box(root,Vector3(3.2,3.0,len),Vector3(0,height,0),BLACK)
 S.box(root,Vector3(3.4,0.8,len*0.9),Vector3(0,height-0.6,0),DARK)
 for k in int(len/1.4): S.box(root,Vector3(0.18,height-0.5,0.18),Vector3(0,0.0,-len*0.45+k*1.4),IRON) # portcullis bars
 for k in int(len/2.2): S.spike(root,0.3,1.8,Vector3(0,height+3.0,-len*0.42+k*2.2),DARK.lightened(0.1))
 K.glow(root,Vector3(1.75,height+1.4,0),Vector3(0.1,0.8,1.6),VIOLET,2.4)

# A black ship with purple sails (bow toward local -z).
func _ship(x: float,z: float,yaw: float,size := 1.0):
 var n = K.node(self,Vector3(x,0.0,z),yaw)
 S.box(n,Vector3(1.6,1.0,6.0)*size,Vector3(0,0.0,0),HULL)
 S.box(n,Vector3(1.0,0.8,1.6)*size,Vector3(0,0.2,-3.4*size),HULL,Vector3(0.3,0,0))
 S.box(n,Vector3(0.14,5.6,0.14)*size,Vector3(0,0.5,0),Color("2a2420"))
 S.box(n,Vector3(3.2,2.6,0.08)*size,Vector3(0,2.9*size,0.2),SAIL)
 S.box(n,Vector3(2.0,1.4,0.08)*size,Vector3(0,1.6*size,-2.0*size),SAIL.darkened(0.2))

func make():
 # The sea the stacks stand in (an inlet of dark water when the site lies inland).
 K.water(self,at(0,16.0,0.05),34.0,Color("2a3f4e"))
 # Stage 1: the great stack and its citadel, a second stack, the first chain bridge.
 var main = _stack(0.0,8.0,15.0,6.5)
 var crown = _spiked_tower(main,20.0,3.4,4)
 for k in 4:
  var a = k*PI*0.5+0.78
  _spiked_tower(main+Vector3(cos(a)*4.4,0,sin(a)*4.4),9.0,1.0,2) # the citadel's corner turrets
 var west = _stack(-11.0,15.0,11.0,4.0)
 var west_top = _spiked_tower(west,13.0,2.0,3)
 _chain_bridge(main+Vector3(0,7.0,0),west+Vector3(0,5.0,0),2)
 features.append("main_stack")
 features.append("spiked_towers")
 features.append("chain_bridges")
 var tops = [main,west]
 if stage>=2:
  for p in [Vector3(12.0,0,16.0),Vector3(-4.0,0,25.0),Vector3(16.0,0,29.0)]:
   var s = _stack(p.x,p.z,9.0+absf(p.x)*0.15,3.6)
   _spiked_tower(s,11.0,1.8,3)
   tops.append(s)
  for pair in [[0,2],[1,3],[2,4],[3,4]]: _chain_bridge(tops[pair[0]]+Vector3(0,4.0,0),tops[pair[1]]+Vector3(0,4.0,0),2)
  _sea_gate(tops[1]-Vector3(0,tops[1].y,0),tops[3]-Vector3(0,tops[3].y,0),7.0)
  _sea_gate(tops[2]-Vector3(0,tops[2].y,0),tops[4]-Vector3(0,tops[4].y,0),7.5)
  features.append("sea_gates")
 if stage>=3:
  # Quays at the stacks' feet and the fleet in the lee of the sea gates.
  for q in [[Vector3(-2.0,0.3,17.0),0.3],[Vector3(8.0,0.3,22.0),-0.4]]:
   S.box(self,Vector3(3.0,0.6,12.0),q[0],Color("2e2620"),Vector3(0,q[1],0))
   for k in 4: S.box(self,Vector3(0.4,2.0,0.4),q[0]+Vector3(0,-0.6,-4.5+k*3.0),Color("2e2620"))
  for sh in [[-6.0,20.0,0.4],[4.0,19.0,-0.3],[10.0,24.0,0.6],[-12.0,27.0,-0.2],[22.0,22.0,1.2]]: _ship(sh[0],sh[1],sh[2])
  for p in [Vector3(-22.0,0,10.0),Vector3(26.0,0,14.0)]:
   var s = _stack(p.x,p.z,7.0,2.8)
   _spiked_tower(s,7.0,1.3,2)
  K.glow(self,crown+Vector3(0,2.0,0),Vector3(0.8,0.8,0.8),GREEN,3.4) # the witch-light atop the citadel
  features.append("docks")
  features.append("black_fleet")
