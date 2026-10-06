extends RefCounted
# Procedural building kits, one per culture (owner decision 2026-10-04: every culture has its own
# buildings), built from simple shapes (kit_shapes.gd). Style targets: docs/reference/biomes/ and
# docs/reference/specializations/ (palette, materials, architectural style; never their layouts)
# and docs/world-bible-v2.md:
#  medieval  grey stone, timber frames, steep slate roofs, round towers, church spires
#  roman     cream stone, red terracotta, columns, square towers, podium temples
#  greek     white marble cubes, blue accents, columns, flat roofs
#  desert    sandstone, flat roofs, lapis and gold, obelisks, gold-capped pyramids
#  dwarf     heavy red and grey carved stone, squat and massive, bronze, forge glow
#  orc       crude timber, hide, bone and skulls, spiked palisades, war totems
#  elf       clean white stone, gold, slender spires with leaf-curved teal roofs, bridges
#  dark_elf  black stone and iron, jagged spiked towers, violet witchlight
#  beastmen  woven living domes, standing stones, bone arches, horned totems
#  ratmen    crooked leaning stacks of old timber and scrap, bell towers, green glow
#  lizardmen golden stone stepped pyramids, jade, monumental plazas
# Pieces (asset manifest ids "kit.<culture>.<piece>", data/asset_manifest.json "procedural"):
# house_1-3, tall, hut, wall, tower, gate, keep, temple, and one signature building per
# specialization path: path_military, path_farming, path_mining, path_lumber, path_market.
# Sizes in metres at campaign kit scale (a house about 3 m, a lord about 8.8 m tall). Presentation
# only: no gameplay value comes from here.

const S = preload("res://visuals/kits/cultures/kit_shapes.gd")

const PIECES = ["house_1","house_2","house_3","tall","hut","wall","tower","gate","keep","temple",
 "path_military","path_farming","path_mining","path_lumber","path_market","bridge","plinth","people"]

# wall, accent, roof, roof2, trim, glow (none = no glow), roof style.
const STYLE = {
 "medieval": {"wall":"#ddd2bc","stone":"#a9a49a","timber":"#5e432c","roof":"#4e5868","roof2":"#a88a4c","trim":"#3e4450","glow":"","roofs":"steep"},
 "roman": {"wall":"#efe2c8","stone":"#e2d4b6","timber":"#7a5232","roof":"#b5533a","roof2":"#9c4632","trim":"#f6f0e2","glow":"","roofs":"low"},
 "greek": {"wall":"#f7f4ec","stone":"#ece6d8","timber":"#8a6a4a","roof":"#e8e0d0","roof2":"#3b6db0","trim":"#3b6db0","glow":"","roofs":"flat"},
 "desert": {"wall":"#dcb27a","stone":"#e6c28a","timber":"#7a5a3a","roof":"#d4a46a","roof2":"#2c4c94","trim":"#d8b040","glow":"#5ad8e0","roofs":"flat"},
 "dwarf": {"wall":"#8e6656","stone":"#7c7672","timber":"#5a4030","roof":"#5c5a58","roof2":"#b0803a","trim":"#c08a3a","glow":"#ff8a2a","roofs":"slab"},
 "orc": {"wall":"#6e5034","stone":"#6a6660","timber":"#5a3e26","roof":"#9c7a54","roof2":"#7a5a3c","trim":"#ece2c8","glow":"#ff6a2a","roofs":"hide"},
 "elf": {"wall":"#f6f6f0","stone":"#e8e8de","timber":"#c8b088","roof":"#2a8c9c","roof2":"#2a5aa8","trim":"#e2c262","glow":"#9ae8ff","roofs":"spire"},
 "dark_elf": {"wall":"#34303a","stone":"#46444e","timber":"#2a2630","roof":"#22202a","roof2":"#5a3a72","trim":"#8a8a96","glow":"#b05aff","roofs":"jagged"},
 "beastmen": {"wall":"#6a5434","stone":"#7a7a68","timber":"#4e3a26","roof":"#5a6e32","roof2":"#7a6a3a","trim":"#e6dcc4","glow":"#ff9a3a","roofs":"woven"},
 "ratmen": {"wall":"#6a5a44","stone":"#5e5a50","timber":"#4e3e2c","roof":"#5a5248","roof2":"#7a4a2a","trim":"#6a6a5e","glow":"#7aff5a","roofs":"crooked"},
 "lizardmen": {"wall":"#c9ae6c","stone":"#d4bc7c","timber":"#6a5a34","roof":"#7a8a3a","roof2":"#2f9a6c","trim":"#e0c050","glow":"#ffd25a","roofs":"thatch"},
}

static func style(culture: String) -> Dictionary:
 var st = STYLE.get(culture,STYLE.medieval)
 var out = {}
 for k in st: out[k] = Color(st[k]) if str(st[k]).begins_with("#") else st[k]
 out.has_glow = str(st.glow) != ""
 return out

static func build(culture: String,piece: String) -> Node3D:
 var root = Node3D.new()
 root.name = "%s_%s" % [culture,piece]
 var st = style(culture)
 match piece:
  "house_1": _house(root,st,culture,Vector3(2.6,2.0,2.2),0)
  "house_2": _house(root,st,culture,Vector3(3.2,2.3,2.4),1)
  "house_3": _house(root,st,culture,Vector3(2.4,2.6,2.0),2)
  "tall": _tall(root,st,culture)
  "hut": _hut(root,st,culture)
  "wall": _wall(root,st,culture)
  "tower": _tower(root,st,culture)
  "gate": _gate(root,st,culture)
  "keep": _keep(root,st,culture)
  "temple": _temple(root,st,culture)
  "path_military": _military(root,st,culture)
  "path_farming": _farming(root,st,culture)
  "path_mining": _mining(root,st,culture)
  "path_lumber": _lumber(root,st,culture)
  "path_market": _market(root,st,culture)
  "people": # specks of townsfolk (alive at scale, game-design §12.13 F): a small group in the culture's colours
   var cols = [st.timber.lightened(0.2),st.roof,st.trim,st.wall.darkened(0.3),st.roof2]
   for i in 5:
    var p = Vector3(cos(i*2.4)*0.7,0,sin(i*2.4)*0.7)
    S.cylinder(root,0.14,0.18,0.62,p,cols[i%cols.size()],5)
    S.cylinder(root,0.12,0.12,0.2,p+Vector3(0,0.62,0),Color("e0b898"),5)
  "plinth": # a 1 m block of terrace stone, scaled under a building (Greek acropolis terraces): warm
   # limestone retaining walls with coursed bands, not white blocks
   var lime = Color("c4b28c")
   S.box(root,Vector3(1.0,1.0,1.0),Vector3.ZERO,lime)
   for y in [0.3,0.62]: S.box(root,Vector3(1.012,0.025,1.012),Vector3(0,y,0),lime.darkened(0.22))
   S.box(root,Vector3(1.04,0.08,1.04),Vector3(0,0.96,0),st.wall)
  "bridge": # a 1 m beam along x, scaled to span two towers (elf bridges, ratmen walkways)
   S.box(root,Vector3(1.0,0.35,1.0),Vector3(0,-0.17,0),st.trim if culture == "elf" else st.timber)
  _: push_error("Unknown kit piece "+piece)
 return root

# --- Architectural details (owner, 2026-10-06: real architecture, not cubes) --------------------

const WINDOW = Color("2a2420")

# Rows of windows on the long faces (both, or the front only), and on the short sides when asked.
static func _windows(root: Node3D,w: float,d: float,y0: float,floors: int,fh: float,c: Color,sides := false,both := true):
 for f in floors:
  var y = y0+f*fh+fh*0.38
  var n = maxi(1,int(w/1.05))
  for i in n:
   var x = -w*0.5+(i+0.5)*w/n
   S.box(root,Vector3(0.34,0.46,0.08),Vector3(x,y,d*0.5+0.01),c)
   if both: S.box(root,Vector3(0.34,0.46,0.08),Vector3(x,y,-d*0.5-0.01),c)
  if sides:
   var m = maxi(1,int(d/1.2))
   for i in m:
    var z = -d*0.5+(i+0.5)*d/m
    for sx in [-1.0,1.0]: S.box(root,Vector3(0.08,0.46,0.34),Vector3(sx*(w*0.5+0.01),y,z),c)

static func _door(root: Node3D,x: float,d: float,c: Color,h := 1.1):
 S.box(root,Vector3(0.62,h,0.08),Vector3(x,0,d*0.5+0.02),c)

static func _chimney(root: Node3D,p: Vector3,h: float,c: Color):
 S.box(root,Vector3(0.42,h,0.42),p,c)
 S.box(root,Vector3(0.52,0.12,0.52),p+Vector3(0,h,0),c.darkened(0.2))

# Half-timbering on the long faces: corner and middle posts, a floor beam and diagonal braces.
static func _timber_frame(root: Node3D,w: float,d: float,y0: float,h: float,c: Color):
 for zs in [-1.0,1.0]:
  var z = zs*(d*0.5+0.03)
  var n = maxi(2,int(w/1.0))
  for i in n+1: S.box(root,Vector3(0.11,h,0.05),Vector3(-w*0.5+i*w/n,y0,z),c)
  S.box(root,Vector3(w+0.06,0.11,0.05),Vector3(0,y0,z),c)
  S.box(root,Vector3(w+0.06,0.11,0.05),Vector3(0,y0+h-0.11,z),c)
  for i in n:
   var x = -w*0.5+(i+0.5)*w/n
   S.box(root,Vector3(0.09,h*0.95,0.04),Vector3(x,y0+0.02,z),c,Vector3(0,0,0.55 if i%2 == 0 else -0.55))

# A roof border: a low parapet around a flat roof.
static func _parapet(root: Node3D,w: float,d: float,y: float,c: Color):
 for zs in [-1.0,1.0]: S.box(root,Vector3(w,0.32,0.14),Vector3(0,y,zs*(d*0.5-0.07)),c)
 for xs in [-1.0,1.0]: S.box(root,Vector3(0.14,0.32,d),Vector3(xs*(w*0.5-0.07),y,0),c)

# Houses of the human cultures: walls with windows and a door, the culture's roof and details.
static func _human_house(root: Node3D,st: Dictionary,cu: String,size: Vector3,v: int):
 var w = size.x
 var d = size.z
 var floors = 2 if v == 2 or (v == 1 and cu in ["medieval","roman"]) else 1
 var fh = 1.25
 var h = maxf(size.y,floors*fh+0.25)
 match cu:
  "medieval":
   # Stone ground floor, a jettied half-timbered upper floor, a steep slate roof and a chimney.
   S.box(root,Vector3(w,fh,d),Vector3.ZERO,st.stone)
   var up = h-fh
   var ww = w+(0.22 if floors>1 else 0.0)
   var dd = d+(0.22 if floors>1 else 0.0)
   S.box(root,Vector3(ww,up,dd),Vector3(0,fh,0),st.wall)
   _timber_frame(root,ww,dd,fh,up,st.timber)
   _windows(root,w,d,0.0,1,fh,WINDOW)
   _windows(root,ww,dd,fh,1,up,WINDOW,true)
   _door(root,-w*0.25,d,st.timber.darkened(0.3))
   S.gable(root,ww+0.35,dd+0.35,dd*0.95,Vector3(0,h,0),st.roof if v != 1 else st.roof.darkened(0.12))
   _chimney(root,Vector3(w*0.3,h,-d*0.15),dd*0.85,st.stone.darkened(0.1))
  "roman":
   # Cream walls, small windows, a low hipped terracotta roof with wide eaves.
   S.box(root,Vector3(w,h,d),Vector3.ZERO,st.wall)
   S.box(root,Vector3(w+0.04,0.18,d+0.04),Vector3(0,0,0),st.stone.darkened(0.1)) # plinth course
   if floors>1: S.box(root,Vector3(w+0.04,0.12,d+0.04),Vector3(0,fh,0),st.stone)
   _windows(root,w,d,0.0,floors,fh,WINDOW)
   _door(root,0.0,d,st.timber.darkened(0.2),1.2)
   S.hip(root,w+0.5,d+0.5,d*0.38,Vector3(0,h,0),st.roof if v != 1 else st.roof2)
   if v == 0: _chimney(root,Vector3(-w*0.25,h,0.0),d*0.4,st.stone)
  "greek":
   # Whitewashed walls with blue doors and shutters; flat roofs with parapets or low red tiles.
   S.box(root,Vector3(w,h,d),Vector3.ZERO,st.wall)
   _windows(root,w,d,0.0,floors,fh,st.roof2)
   _door(root,w*0.2,d,st.roof2,1.15)
   if v == 1:
    S.hip(root,w+0.35,d+0.35,d*0.32,Vector3(0,h,0),Color("b8573a"))
   else:
    _parapet(root,w,d,h,st.wall.darkened(0.04))
    if v == 2:
     S.box(root,Vector3(w*0.5,1.1,d*0.5),Vector3(-w*0.2,h,-d*0.15),st.wall) # a room on the roof
     _windows(root,w*0.5,d*0.5,h,1,1.1,st.roof2,false,false)
    S.box(root,Vector3(w+0.05,0.1,d+0.05),Vector3(0,h-0.1,0),st.roof2) # blue cornice
  "desert":
   # Sandstone, deep small windows, flat roof with parapet; a dome on the larger houses.
   S.box(root,Vector3(w,h,d),Vector3.ZERO,st.wall)
   _windows(root,w,d,0.0,floors,fh,WINDOW)
   _door(root,0.0,d,st.roof2,1.2)
   _parapet(root,w,d,h,st.wall.darkened(0.06))
   if v == 1: S.dome(root,minf(w,d)*0.32,Vector3(w*0.15,h,0),st.trim,0.9)
   if v == 2: S.box(root,Vector3(w*0.45,1.1,d*0.45),Vector3(w*0.2,h,0),st.wall.darkened(0.04))

static func _human_tall(root: Node3D,st: Dictionary,cu: String):
 match cu:
  "medieval":
   # A tower house: stone base, two timbered floors, a steep roof and chimney.
   S.box(root,Vector3(2.6,1.6,2.6),Vector3.ZERO,st.stone)
   S.box(root,Vector3(2.9,3.2,2.9),Vector3(0,1.6,0),st.wall)
   _timber_frame(root,2.9,2.9,1.6,3.2,st.timber)
   _windows(root,2.6,2.6,0.0,1,1.6,WINDOW)
   _windows(root,2.9,2.9,1.6,2,1.6,WINDOW,true)
   _door(root,0.0,2.6,st.timber.darkened(0.3))
   S.gable(root,3.3,3.3,3.0,Vector3(0,4.8,0),st.roof)
   _chimney(root,Vector3(0.9,4.8,0.5),2.4,st.stone.darkened(0.1))
  "roman":
   # An insula: three floors of windows over shop arches, a hipped tile roof.
   S.box(root,Vector3(3.4,5.4,2.8),Vector3.ZERO,st.wall)
   for i in 3: S.box(root,Vector3(0.7,1.0,0.08),Vector3(-1.1+i*1.1,0,1.42),WINDOW) # shop openings
   _windows(root,3.4,2.8,1.4,3,1.3,WINDOW,true)
   for y in [1.35,2.65,3.95]: S.box(root,Vector3(3.45,0.1,2.85),Vector3(0,y,0),st.stone)
   S.hip(root,3.9,3.3,1.1,Vector3(0,5.4,0),st.roof)
  "greek":
   S.box(root,Vector3(2.8,3.0,2.6),Vector3.ZERO,st.wall)
   S.box(root,Vector3(1.8,1.6,1.8),Vector3(0.4,3.0,0.3),st.wall)
   _windows(root,2.8,2.6,0.0,2,1.4,st.roof2,true)
   _door(root,-0.6,2.6,st.roof2,1.15)
   _parapet(root,2.8,2.6,3.0,st.wall.darkened(0.04))
   S.hip(root,2.1,2.1,0.6,Vector3(0.4,4.6,0.3),Color("b8573a"))
  "desert":
   S.box(root,Vector3(2.8,5.0,2.8),Vector3.ZERO,st.wall)
   _windows(root,2.8,2.8,0.4,3,1.4,WINDOW,true)
   for i in 4: S.box(root,Vector3(0.6,0.5,0.6),Vector3(cos(i*PI*0.5+0.785)*1.05,5.0,sin(i*PI*0.5+0.785)*1.05),st.wall.darkened(0.08))
   S.dome(root,0.9,Vector3(0,5.0,0),st.trim,0.9)

# --- Walls, towers and gatehouses (owner, 2026-10-06: real height and thickness, crenellations,
# towers at intervals, proper gatehouses). Each wall piece reaches 2 m below its foot so it follows
# sloping ground without gaps.

static func _merlons(root: Node3D,len: float,y: float,depth: float,c: Color,both := true):
 var n = maxi(2,int(len/0.9))
 for i in n:
  var x = -len*0.5+(i+0.5)*len/n
  S.box(root,Vector3(len/n*0.55,0.6,0.35),Vector3(x,y,depth*0.5-0.18),c)
  if both: S.box(root,Vector3(len/n*0.55,0.6,0.35),Vector3(x,y,-depth*0.5+0.18),c)
const VOID_DARK = Color("1e1a16")

# --- Roofs ---------------------------------------------------------------------------------------

static func _roof(root: Node3D,st: Dictionary,w: float,d: float,y: float,variant := 0):
 var c: Color = st.roof if variant != 1 else st.roof2
 match st.roofs:
  "steep": S.gable(root,w+0.3,d+0.3,d*0.9,Vector3(0,y,0),c)
  "low": S.gable(root,w+0.3,d+0.3,d*0.35,Vector3(0,y,0),c)
  "flat":
   S.box(root,Vector3(w+0.15,0.18,d+0.15),Vector3(0,y,0),st.trim if variant == 1 else st.wall.darkened(0.06))
  "slab":
   S.box(root,Vector3(w+0.5,0.45,d+0.5),Vector3(0,y,0),st.stone.darkened(0.1))
   S.box(root,Vector3(w*0.6,0.3,d*0.6),Vector3(0,y+0.45,0),st.trim)
  "hide": S.cone(root,maxf(w,d)*0.75,d*0.95,Vector3(0,y,0),c,6)
  "spire":
   S.cylinder(root,0.0,maxf(w,d)*0.62,d*1.6,Vector3(0,y,0),c,8)
  "jagged":
   S.hip(root,w+0.2,d+0.2,d*1.1,Vector3(0,y,0),c)
   S.spike(root,0.15,1.2,Vector3(w*0.45,y,d*0.45),st.trim)
   S.spike(root,0.15,1.0,Vector3(-w*0.45,y,-d*0.45),st.trim)
  "woven": S.dome(root,maxf(w,d)*0.62,Vector3(0,y-0.3,0),c,0.8)
  "crooked": S.gable(root,w+0.4,d+0.4,d*0.8,Vector3(0.15,y,0),c,Vector3(0,0,0.12))
  "thatch": S.hip(root,w+0.5,d+0.5,d*0.85,Vector3(0,y,0),c)

# --- Houses --------------------------------------------------------------------------------------

static func _house(root: Node3D,st: Dictionary,cu: String,size: Vector3,v: int):
 match cu:
  "orc":
   S.cylinder(root,size.x*0.5,size.x*0.55,size.y*0.7,Vector3.ZERO,st.wall,7)
   S.cone(root,size.x*0.68,size.y*0.9,Vector3(0,size.y*0.7,0),st.roof,7)
   S.spike(root,0.1,1.0,Vector3(0,size.y*1.5,0),st.trim)
   S.box(root,Vector3(0.6,1.0,0.1),Vector3(0,0,size.x*0.52),st.timber.darkened(0.3)) # door flap
   S.box(root,Vector3(0.5,0.4,0.4),Vector3(0,size.y*0.75,size.x*0.45),st.trim) # skull over the door
   return
  "beastmen":
   S.dome(root,size.x*0.62,Vector3.ZERO,st.roof if v != 1 else st.roof2,0.9)
   S.box(root,Vector3(0.18,size.y*1.2,0.18),Vector3(size.x*0.5,0,0),st.timber,Vector3(0,0,-0.3))
   return
  "ratmen":
   var lean = Vector3(0,0,0.08*(v-1))
   var b = S.box(root,Vector3(size.x,size.y*1.3,size.z),Vector3.ZERO,st.wall if v != 1 else st.timber,lean)
   S.box(root,Vector3(size.x*0.8,size.y*0.9,size.z*0.8),Vector3(0.2,size.y*1.3,0),st.timber,lean*2.0)
   _roof(root,st,size.x*0.8,size.z*0.8,size.y*2.2,v)
   S.box(root,Vector3(0.12,size.y*2.4,0.12),Vector3(size.x*0.55,0,size.z*0.55),st.stone) # stilt
   _windows(root,size.x*0.8,size.z,size.y*0.3,1,size.y,st.glow.darkened(0.2),false,false)
   _door(root,-size.x*0.2,size.z,WINDOW)
   return
  "elf":
   S.cylinder(root,size.x*0.38,size.x*0.45,size.y*1.4,Vector3.ZERO,st.wall,8)
   S.cylinder(root,0.0,size.x*0.5,size.y*1.3,Vector3(0,size.y*1.4,0),st.roof if v != 1 else st.roof2,8)
   S.box(root,Vector3(size.x*0.6,0.12,0.12),Vector3(0,size.y*1.35,0),st.trim)
   S.box(root,Vector3(0.36,0.9,0.08),Vector3(0,0,size.x*0.43),st.trim.darkened(0.2)) # door
   S.box(root,Vector3(0.24,0.4,0.06),Vector3(0,size.y*0.8,size.x*0.42),st.glow,Vector3.ZERO,1.2) # lit window
   return
  "dark_elf":
   S.box(root,Vector3(size.x*0.85,size.y*1.4,size.z*0.85),Vector3.ZERO,st.wall)
   _roof(root,st,size.x*0.85,size.z*0.85,size.y*1.4,v)
   _windows(root,size.x*0.85,size.z*0.85,0.2,2,size.y*0.6,st.glow.darkened(0.3),false,false)
   _door(root,0.0,size.z*0.85,WINDOW)
   return
  "lizardmen":
   if v == 2:
    S.steps(root,size.x*1.1,3,size.y*0.45,Vector3.ZERO,st.stone)
    S.box(root,Vector3(size.x*0.4,0.6,size.z*0.4),Vector3(0,size.y*1.35,0),st.roof2)
    return
   S.box(root,Vector3(size.x*0.9,size.y*0.8,size.z*0.9),Vector3.ZERO,st.wall)
   _roof(root,st,size.x*0.9,size.z*0.9,size.y*0.8,v)
   _door(root,0.0,size.z*0.9,WINDOW)
   return
  "dwarf":
   S.box(root,Vector3(size.x*1.1,size.y*0.9,size.z*1.1),Vector3.ZERO,st.wall if v != 1 else st.stone)
   _roof(root,st,size.x*1.1,size.z*1.1,size.y*0.9,v)
   S.box(root,Vector3(0.8,1.2,0.1),Vector3(0,0,size.z*0.56),Color("2a2018")) # heavy door
   S.box(root,Vector3(1.0,0.2,0.12),Vector3(0,1.2,size.z*0.56),st.trim) # bronze lintel
   S.box(root,Vector3(0.4,0.35,0.06),Vector3(size.x*0.3,0.8,size.z*0.56),st.glow,Vector3.ZERO,2.0) # forge-lit window
   return
 _human_house(root,st,cu,size,v)

static func _tall(root: Node3D,st: Dictionary,cu: String):
 match cu:
  "elf":
   S.cylinder(root,0.75,0.95,7.5,Vector3.ZERO,st.wall,10)
   S.cylinder(root,0.0,1.05,3.6,Vector3(0,7.5,0),st.roof,10)
   S.box(root,Vector3(2.4,0.14,0.14),Vector3(0,6.2,0),st.trim)
  "dark_elf":
   S.box(root,Vector3(1.8,6.0,1.8),Vector3.ZERO,st.wall)
   S.box(root,Vector3(1.3,3.0,1.3),Vector3(0,6.0,0),st.stone,Vector3(0,0.4,0))
   S.spike(root,0.6,3.4,Vector3(0,9.0,0),st.roof)
   S.box(root,Vector3(0.4,0.6,0.1),Vector3(0,7.0,0.68),st.glow,Vector3.ZERO,2.0)
  "ratmen":
   var lean = 0.0
   var y = 0.0
   for i in 4:
    lean += 0.05
    S.box(root,Vector3(2.0-i*0.25,2.0,2.0-i*0.25),Vector3(i*0.18,y,0),st.timber if i%2 == 0 else st.wall,Vector3(0,0,-lean))
    y += 2.0
   _roof(root,st,1.4,1.4,y,0)
  "orc":
   S.cylinder(root,0.9,1.1,5.0,Vector3.ZERO,st.timber,6)
   S.box(root,Vector3(2.6,0.4,2.6),Vector3(0,5.0,0),st.wall)
   for i in 4: S.spike(root,0.12,1.2,Vector3(cos(i*PI*0.5)*1.1,5.4,sin(i*PI*0.5)*1.1),st.trim)
  "dwarf":
   S.box(root,Vector3(3.0,4.2,3.0),Vector3.ZERO,st.stone)
   S.box(root,Vector3(3.4,0.6,3.4),Vector3(0,4.2,0),st.wall)
   S.box(root,Vector3(0.5,0.5,0.1),Vector3(0,2.0,1.52),st.glow,Vector3.ZERO,2.5)
  "beastmen":
   S.box(root,Vector3(0.9,5.5,0.7),Vector3.ZERO,st.stone,Vector3(0.06,0,0.05))
   S.box(root,Vector3(0.9,4.8,0.7),Vector3(1.6,0,0),st.stone,Vector3(-0.05,0,0.08))
   S.box(root,Vector3(2.8,0.6,0.8),Vector3(0.8,5.0,0),st.stone)
  "lizardmen":
   var top = S.steps(root,4.2,4,1.1,Vector3.ZERO,st.stone)
   S.box(root,Vector3(1.0,1.0,1.0),Vector3(0,top,0),st.trim)
  "desert", "greek", "roman", "medieval": _human_tall(root,st,cu)
  _:
   _human_tall(root,st,"medieval")

static func _hut(root: Node3D,st: Dictionary,cu: String):
 match cu:
  "orc", "beastmen":
   S.cone(root,1.4,2.2,Vector3.ZERO,st.roof,6)
  "lizardmen":
   S.cylinder(root,1.0,1.1,1.2,Vector3.ZERO,st.timber,6)
   S.cone(root,1.5,1.4,Vector3(0,1.2,0),st.roof,6)
  "elf":
   S.dome(root,1.3,Vector3.ZERO,st.wall,0.9)
   S.spike(root,0.2,1.2,Vector3(0,1.1,0),st.roof)
  _:
   S.box(root,Vector3(2.0,1.4,1.7),Vector3.ZERO,st.wall.darkened(0.12))
   S.gable(root,2.3,2.0,1.1,Vector3(0,1.4,0),st.roof2 if st.roofs != "flat" else st.wall.darkened(0.2))

# --- Walls, towers, gates (length along local x: 3.2 m) --------------------------------------

static func _wall(root: Node3D,st: Dictionary,cu: String):
 match cu:
  "orc", "ratmen", "beastmen":
   # A palisade of sharpened logs on an earth bank, with a fighting step behind.
   S.box(root,Vector3(3.4,1.2,2.4),Vector3(0,-2.0,0),st.stone.darkened(0.25)) # bank
   S.box(root,Vector3(3.4,2.0,2.4),Vector3(0,-0.8,0),st.wall.darkened(0.3))
   for i in 9:
    var h = 4.0+0.6*sin(i*2.3)
    S.cylinder(root,0.2,0.24,h+2.0,Vector3(-1.6+i*0.4,-2.0,0.5),st.timber,5,Vector3(0,0,0.05*sin(i*1.7)))
    S.spike(root,0.24,0.8,Vector3(-1.6+i*0.4,h,0.5),st.timber.darkened(0.2))
   S.box(root,Vector3(3.4,0.25,1.0),Vector3(0,2.4,-0.5),st.timber.darkened(0.1)) # fighting step
   if cu == "orc": S.box(root,Vector3(0.6,0.5,0.5),Vector3(0,3.0,0.8),st.trim) # skull
  "dark_elf":
   S.box(root,Vector3(3.3,8.0,2.2),Vector3(0,-2.0,0),st.wall)
   for i in 4: S.spike(root,0.2,1.6,Vector3(-1.2+i*0.8,6.0,0.9),st.trim)
   _merlons(root,3.3,6.0,2.2,st.wall.darkened(0.1),false)
  "elf":
   S.box(root,Vector3(3.3,7.2,1.4),Vector3(0,-2.0,0),st.wall)
   S.box(root,Vector3(3.3,0.25,1.7),Vector3(0,5.2,0),st.trim)
   _merlons(root,3.3,5.45,1.7,st.wall)
  "dwarf":
   S.box(root,Vector3(3.3,8.4,3.0),Vector3(0,-2.0,0),st.stone)
   S.box(root,Vector3(3.4,0.5,3.2),Vector3(0,1.8,0),st.stone.darkened(0.12)) # carved course
   _merlons(root,3.3,6.4,3.0,st.stone.darkened(0.1))
  "lizardmen":
   S.box(root,Vector3(3.3,6.8,2.2),Vector3(0,-2.0,0),st.stone)
   S.box(root,Vector3(3.3,0.4,2.5),Vector3(0,4.8,0),st.roof2)
  _:
   # Stone curtain wall: battered base, wall-walk and crenellations on both faces.
   S.box(root,Vector3(3.3,2.6,2.6),Vector3(0,-2.0,0),st.stone.darkened(0.08))
   S.box(root,Vector3(3.3,7.2,1.9),Vector3(0,-2.0,0),st.stone)
   S.box(root,Vector3(3.35,0.12,1.95),Vector3(0,2.6,0),st.stone.darkened(0.12)) # string course
   _merlons(root,3.3,5.2,1.9,st.stone.darkened(0.06))

static func _tower(root: Node3D,st: Dictionary,cu: String):
 match cu:
  "medieval":
   S.cylinder(root,2.0,2.2,11.0,Vector3(0,-2.0,0),st.stone,12)
   S.cylinder(root,2.3,2.3,0.6,Vector3(0,8.4,0),st.stone.darkened(0.1),12) # machicolation ring
   for i in 10: S.box(root,Vector3(0.5,0.6,0.5),Vector3(cos(i*0.628)*2.05,9.0,sin(i*0.628)*2.05),st.stone.darkened(0.06))
   S.cone(root,2.4,3.6,Vector3(0,9.0,0),st.roof,12)
   for i in 3: S.box(root,Vector3(0.25,0.7,0.1),Vector3(0,2.0+i*2.0,2.1),WINDOW)
  "roman", "greek":
   S.box(root,Vector3(3.6,10.6,3.6),Vector3(0,-2.0,0),st.stone)
   S.box(root,Vector3(3.8,0.15,3.8),Vector3(0,4.0,0),st.stone.darkened(0.1))
   for i in 2: S.box(root,Vector3(0.35,0.7,0.1),Vector3(0,3.0+i*2.5,1.82),WINDOW)
   for sx in [-1.0,1.0]:
    for sz in [-1.0,1.0]: S.box(root,Vector3(0.7,0.6,0.7),Vector3(sx*1.45,8.6,sz*1.45),st.stone.darkened(0.08))
   if cu == "roman": S.hip(root,3.9,3.9,1.4,Vector3(0,8.6,0),st.roof)
   else: _merlons(root,3.6,8.6,3.6,st.stone.darkened(0.08))
  "desert":
   S.cylinder(root,1.4,2.2,10.0,Vector3(0,-2.0,0),st.wall,4,Vector3(0,PI*0.25,0))
   S.box(root,Vector3(2.4,0.5,2.4),Vector3(0,8.0,0),st.trim)
   for i in 4: S.box(root,Vector3(0.6,0.6,0.6),Vector3(cos(i*PI*0.5+0.785)*0.95,8.5,sin(i*PI*0.5+0.785)*0.95),st.wall.darkened(0.08))
  "dwarf":
   S.box(root,Vector3(4.2,10.0,4.2),Vector3(0,-2.0,0),st.stone)
   S.box(root,Vector3(4.8,1.0,4.8),Vector3(0,8.0,0),st.wall)
   _merlons(root,4.8,9.0,4.8,st.stone.darkened(0.1))
   S.box(root,Vector3(0.7,0.7,0.1),Vector3(0,5.0,2.12),st.glow,Vector3.ZERO,2.5)
  "orc", "ratmen", "beastmen":
   S.box(root,Vector3(2.8,1.0,2.8),Vector3(0,-1.0,0),st.timber.darkened(0.2))
   _tall(root,st,cu)
  "elf":
   S.cylinder(root,1.0,1.3,11.0,Vector3(0,-2.0,0),st.wall,12)
   S.cylinder(root,0.0,1.4,4.2,Vector3(0,9.0,0),st.roof2,12)
  "dark_elf":
   S.cylinder(root,1.0,2.0,12.0,Vector3(0,-2.0,0),st.wall,5)
   S.spike(root,1.3,4.5,Vector3(0,10.0,0),st.roof)
   for i in 3: S.spike(root,0.22,2.0,Vector3(cos(i*2.1)*1.3,7.5,sin(i*2.1)*1.3),st.trim,Vector3(cos(i*2.1)*0.6,0,sin(i*2.1)*0.6))
  "lizardmen":
   var top = S.steps(root,4.2,4,1.8,Vector3(0,-2.0,0),st.stone)
   S.box(root,Vector3(1.4,1.4,1.4),Vector3(0,top-2.0,0),st.roof2)

static func _gate(root: Node3D,st: Dictionary,cu: String):
 # A gatehouse: twin towers flanking a dark arched passage, a crenellated top and the culture's
 # roofs or ornaments.
 var c = st.stone
 if cu in ["orc","ratmen","beastmen"]: c = st.timber
 if cu in ["dark_elf","elf","desert"]: c = st.wall
 for sx in [-1.0,1.0]:
  S.box(root,Vector3(2.2,11.5,3.0),Vector3(sx*2.3,-2.0,0),c)
 S.box(root,Vector3(2.6,9.0,2.6),Vector3(0,-2.0,0),c.darkened(0.04)) # the passage block
 for zs in [-1.0,1.0]:
  S.box(root,Vector3(1.8,3.6,0.12),Vector3(0,0,zs*1.33),VOID_DARK)
  S.cylinder(root,0.9,0.9,0.12,Vector3(0,3.6,zs*1.33),VOID_DARK,10,Vector3(PI*0.5,0,0))
 if not cu in ["orc","ratmen","beastmen","elf"]:
  for sx in [-1.0,1.0]:
   for i in 3: S.box(root,Vector3(0.5,0.6,0.5),Vector3(sx*2.3-0.75+i*0.75,9.5,1.25),c.darkened(0.06))
   for i in 3: S.box(root,Vector3(0.5,0.6,0.5),Vector3(sx*2.3-0.75+i*0.75,9.5,-1.25),c.darkened(0.06))
 match cu:
  "medieval":
   for sx in [-1.0,1.0]: S.cone(root,1.7,3.0,Vector3(sx*2.3,10.1,0),st.roof,8)
  "roman":
   S.gable(root,7.0,3.2,1.0,Vector3(0,7.0,0),st.roof)
   for sx in [-1.0,1.0]: S.hip(root,2.5,3.3,1.0,Vector3(sx*2.3,9.5,0),st.roof)
  "greek":
   S.box(root,Vector3(2.6,0.2,2.8),Vector3(0,7.0,0),st.roof2)
  "orc":
   S.box(root,Vector3(1.2,1.0,0.8),Vector3(0,7.2,1.4),st.trim) # beast skull
   for sx in [-1.0,1.0]: S.spike(root,0.2,1.8,Vector3(sx*2.3,9.5,0),st.trim)
  "dark_elf":
   for sx in [-1.0,1.0]: S.spike(root,0.7,3.4,Vector3(sx*2.3,9.5,0),st.roof)
  "elf":
   for sx in [-1.0,1.0]: S.cylinder(root,0.0,1.3,3.2,Vector3(sx*2.3,9.5,0),st.roof,8)
  "desert":
   for sx in [-1.0,1.0]: S.box(root,Vector3(0.9,3.0,0.9),Vector3(sx*4.2,0,1.6),st.trim) # guardian statues
  "dwarf":
   S.box(root,Vector3(2.0,1.4,0.2),Vector3(0,6.0,1.42),st.trim) # carved face
  "lizardmen":
   S.box(root,Vector3(7.2,0.6,3.2),Vector3(0,9.5,0),st.roof2)

# --- Keep, temple ----------------------------------------------------------------------------------

static func _keep(root: Node3D,st: Dictionary,cu: String):
 match cu:
  "medieval":
   S.box(root,Vector3(6.0,7.5,6.0),Vector3.ZERO,st.stone)
   for i in 4:
    var p = Vector3(cos(i*PI*0.5+0.785),0,sin(i*PI*0.5+0.785))*4.0
    S.cylinder(root,1.3,1.4,9.0,p,st.stone,10)
    S.cone(root,1.6,3.0,p+Vector3(0,9.0,0),st.roof,10)
   S.hip(root,6.0,6.0,3.4,Vector3(0,7.5,0),st.roof)
  "roman":
   # Praetorium: a courtyard block with corner towers.
   S.box(root,Vector3(8.0,4.0,8.0),Vector3.ZERO,st.wall)
   _roof(root,st,8.0,8.0,4.0,0)
   S.colonnade(root,-3.6,3.6,4.2,6,3.6,0.28,st.trim)
  "greek":
   S.box(root,Vector3(7.0,4.2,5.0),Vector3.ZERO,st.wall)
   S.box(root,Vector3(4.0,2.4,3.0),Vector3(1.0,4.2,0),st.wall)
   S.colonnade(root,-3.2,3.2,2.7,6,4.0,0.25,st.trim.lightened(0.6))
  "desert":
   var top = S.steps(root,10.0,1,6.0,Vector3.ZERO,st.stone)
   S.cylinder(root,0.0,5.2,6.0,Vector3(0,top,0),st.stone,4,Vector3(0,PI*0.25,0))
   S.cylinder(root,0.0,1.2,1.4,Vector3(0,top+4.6,0),st.trim,4,Vector3(0,PI*0.25,0),1.2) # gold cap
  "dwarf":
   S.box(root,Vector3(9.0,6.0,7.0),Vector3.ZERO,st.stone)
   S.box(root,Vector3(7.0,3.0,5.0),Vector3(0,6.0,-0.5),st.wall)
   S.box(root,Vector3(3.0,4.0,0.3),Vector3(0,0,3.6),Color("2a2018"))
   S.box(root,Vector3(3.6,0.6,0.5),Vector3(0,4.2,3.6),st.trim)
   S.box(root,Vector3(2.4,1.2,0.2),Vector3(0,1.0,3.62),st.glow,Vector3.ZERO,2.0)
  "orc":
   S.cylinder(root,3.2,3.6,6.0,Vector3.ZERO,st.timber,8)
   S.cone(root,4.2,4.0,Vector3(0,6.0,0),st.roof,8)
   for i in 8: S.spike(root,0.2,2.2,Vector3(cos(i*0.785)*3.8,4.0,sin(i*0.785)*3.8),st.trim,Vector3(cos(i*0.785)*0.5,0,sin(i*0.785)*0.5))
   S.box(root,Vector3(1.6,1.2,1.0),Vector3(0,7.0,3.2),st.trim)
  "elf":
   S.cylinder(root,1.4,1.8,14.0,Vector3.ZERO,st.wall,12)
   S.cylinder(root,0.0,1.9,5.0,Vector3(0,14.0,0),st.roof,12)
   for i in 3:
    var p = Vector3(cos(i*2.09),0,sin(i*2.09))*3.6
    S.cylinder(root,0.8,1.0,9.0,p,st.wall,10)
    S.cylinder(root,0.0,1.1,3.4,p+Vector3(0,9.0,0),st.roof2,10)
    S.box(root,Vector3(3.4,0.25,0.5),p*0.5+Vector3(0,7.5,0),st.trim,Vector3(0,-i*2.09,0)) # bridge
   S.dome(root,1.3,Vector3(0,19.0,0),st.glow.lerp(Color.WHITE,0.4))
  "dark_elf":
   S.cylinder(root,1.6,3.2,12.0,Vector3.ZERO,st.wall,5)
   S.spike(root,1.8,6.0,Vector3(0,12.0,0),st.roof)
   for i in 5:
    var p = Vector3(cos(i*1.26),0,sin(i*1.26))*3.4
    S.spike(root,0.9,8.0+i%3*2.0,p,st.stone,Vector3(cos(i*1.26)*0.15,0,sin(i*1.26)*0.15))
   S.box(root,Vector3(0.6,1.2,0.1),Vector3(0,8.0,1.75),st.glow,Vector3.ZERO,3.0)
  "beastmen":
   # Herdstone in a ring of standing stones.
   S.box(root,Vector3(2.4,6.0,1.6),Vector3.ZERO,st.stone,Vector3(0,0.3,0.05))
   S.box(root,Vector3(0.6,0.6,0.1),Vector3(0,3.5,0.82),st.glow,Vector3.ZERO,2.0)
   for i in 7: S.box(root,Vector3(0.8,3.0+i%3,0.6),Vector3(cos(i*0.9)*5.0,0,sin(i*0.9)*5.0),st.stone.darkened(0.1),Vector3(0.05*sin(i),-i*0.9,0.06*cos(i)))
  "ratmen":
   # The great bell tower.
   var y = 0.0
   for i in 6:
    S.box(root,Vector3(4.0-i*0.4,2.6,4.0-i*0.4),Vector3(i*0.15,y,0),st.timber if i%2 == 0 else st.stone,Vector3(0,i*0.1,-0.03*i))
    y += 2.6
   S.box(root,Vector3(1.6,1.4,1.6),Vector3(1.0,y,0),st.roof2)
   S.box(root,Vector3(0.5,0.5,0.1),Vector3(0.8,y-3.0,1.2),st.glow,Vector3.ZERO,2.5)
  "lizardmen":
   var top = S.steps(root,14.0,5,1.6,Vector3.ZERO,st.stone)
   S.box(root,Vector3(1.6,top,3.0),Vector3(0,0,6.0),st.wall,Vector3(-0.55,0,0)) # stairway
   S.box(root,Vector3(2.6,2.0,2.6),Vector3(0,top,0),st.roof2)
   S.box(root,Vector3(1.0,0.4,1.0),Vector3(0,top+2.0,0),st.glow,Vector3.ZERO,2.0)

static func _temple(root: Node3D,st: Dictionary,cu: String):
 match cu:
  "medieval":
   # Gothic church: nave, transept and a tall spire.
   S.box(root,Vector3(4.0,4.4,9.0),Vector3.ZERO,st.stone)
   S.gable(root,4.3,9.2,3.2,Vector3(0,4.4,0),st.roof,Vector3(0,PI*0.5,0))
   S.box(root,Vector3(2.4,7.5,2.4),Vector3(0,0,-4.8),st.stone)
   S.cylinder(root,0.0,1.5,6.0,Vector3(0,7.5,-4.8),st.roof,4,Vector3(0,PI*0.25,0))
  "roman", "greek":
   S.box(root,Vector3(6.4,1.2,9.6),Vector3.ZERO,st.stone) # podium
   S.box(root,Vector3(4.0,3.6,6.0),Vector3(0,1.2,-1.0),st.wall)
   for z in [-4.2,4.2]: S.colonnade(root,-2.8,2.8,z,5,3.6,0.28,st.trim if cu == "roman" else Color("fbfaf6"),1.2)
   S.gable(root,6.2,9.4,1.4,Vector3(0,4.8,0),st.roof if cu == "roman" else st.wall,Vector3(0,PI*0.5,0))
  "desert":
   S.box(root,Vector3(8.0,4.6,6.0),Vector3.ZERO,st.wall)
   S.colonnade(root,-3.4,3.4,3.2,6,4.6,0.4,st.stone)
   S.box(root,Vector3(8.4,0.5,6.4),Vector3(0,4.6,0),st.roof2)
   for sx in [-1.0,1.0]: S.box(root,Vector3(0.6,6.5,0.6),Vector3(sx*5.4,0,3.4),st.trim) # obelisks
  "elf":
   S.cylinder(root,3.0,3.2,4.0,Vector3.ZERO,st.wall,12)
   S.dome(root,3.1,Vector3(0,4.0,0),st.glow.lerp(Color.WHITE,0.3))
  "dwarf":
   S.box(root,Vector3(7.0,5.0,7.0),Vector3.ZERO,st.stone)
   S.box(root,Vector3(5.0,2.0,5.0),Vector3(0,5.0,0),st.trim)
   S.box(root,Vector3(1.6,1.6,0.2),Vector3(0,1.5,3.55),st.glow,Vector3.ZERO,2.0)
  "lizardmen":
   var top = S.steps(root,9.0,4,1.4,Vector3.ZERO,st.stone)
   S.box(root,Vector3(1.4,1.4,1.4),Vector3(0,top,0),st.glow,Vector3.ZERO,1.5)
  "dark_elf":
   S.box(root,Vector3(5.0,6.0,5.0),Vector3.ZERO,st.wall)
   S.spike(root,2.4,7.0,Vector3(0,6.0,0),st.roof)
   S.box(root,Vector3(1.0,2.0,0.1),Vector3(0,2.0,2.55),st.glow,Vector3.ZERO,3.0)
  "orc", "beastmen":
   # War totem: a carved trunk with skulls and horns.
   S.cylinder(root,0.5,0.6,7.0,Vector3.ZERO,st.timber,6)
   S.box(root,Vector3(1.4,1.0,1.0),Vector3(0,6.0,0),st.trim)
   for sx in [-1.0,1.0]: S.spike(root,0.2,1.6,Vector3(sx*0.7,6.8,0),st.trim,Vector3(0,0,-sx*0.9))
   S.cylinder(root,1.6,1.8,0.4,Vector3.ZERO,st.glow if st.has_glow else st.timber,8,Vector3.ZERO,1.5) # fire ring
  "ratmen":
   S.box(root,Vector3(4.0,3.0,4.0),Vector3.ZERO,st.stone)
   S.cylinder(root,0.6,0.8,7.0,Vector3(1.2,3.0,1.2),st.stone,6,Vector3(0,0,0.12)) # pipe chimney
   S.dome(root,1.8,Vector3(-0.6,3.0,-0.6),st.glow,0.6)

# --- Specialization signature buildings (one per path, per culture) ------------------------------

static func _military(root: Node3D,st: Dictionary,cu: String):
 # Barracks hall with a drill yard fence; the culture's own touches.
 var hall = Vector3(7.0,2.8,3.4)
 if cu in ["orc","beastmen"]:
  S.box(root,Vector3(8.0,2.0,4.0),Vector3.ZERO,st.timber)
  S.gable(root,8.4,4.4,1.8,Vector3(0,2.0,0),st.roof)
  for i in 5: S.spike(root,0.18,1.6,Vector3(-3.6+i*1.8,0,3.0),st.trim)
  return
 S.box(root,hall,Vector3.ZERO,st.wall if cu != "dwarf" else st.stone)
 _roof(root,st,hall.x,hall.z,hall.y,0)
 for i in 6: S.box(root,Vector3(0.12,0.9,0.12),Vector3(-3.5+i*1.4,0,3.4),st.timber)
 S.box(root,Vector3(7.2,0.12,0.12),Vector3(0,0.75,3.4),st.timber)
 S.box(root,Vector3(0.14,4.0,0.14),Vector3(3.8,0,2.2),st.timber) # banner pole
 S.box(root,Vector3(0.9,1.2,0.05),Vector3(4.3,2.6,2.2),st.trim if cu != "greek" else st.roof2)

static func _farming(root: Node3D,st: Dictionary,cu: String):
 # Granary or barn, with haystacks.
 match cu:
  "desert", "lizardmen":
   S.cylinder(root,1.4,1.6,3.0,Vector3.ZERO,st.wall,8)
   S.dome(root,1.5,Vector3(0,3.0,0),st.wall.darkened(0.08))
   S.cylinder(root,1.2,1.4,2.6,Vector3(3.2,0,0),st.wall,8)
   S.dome(root,1.3,Vector3(3.2,2.6,0),st.wall.darkened(0.08))
  "orc", "beastmen":
   S.cone(root,1.6,2.4,Vector3.ZERO,st.roof2,6)
   S.box(root,Vector3(3.0,0.8,2.0),Vector3(3.0,0,0),st.timber)
  _:
   S.box(root,Vector3(5.0,2.8,3.2),Vector3.ZERO,Color("8e4a32") if cu == "medieval" else st.wall)
   S.gable(root,5.3,3.5,1.8,Vector3(0,2.8,0),st.roof2 if st.roofs != "flat" else st.wall.darkened(0.15))
 for i in 3: S.cone(root,0.7,1.2,Vector3(-1.5+i*1.4,0,3.0),Color("d8b85a"),6)

static func _mining(root: Node3D,st: Dictionary,cu: String):
 # Headframe over a shaft, a smelter with a chimney and glow, ore spoil: gritty.
 var dark = Color("3e3a36")
 S.box(root,Vector3(4.0,0.6,4.0),Vector3.ZERO,dark)
 for i in 4: S.box(root,Vector3(0.25,5.0,0.25),Vector3(cos(i*PI*0.5+0.785)*1.3,0.6,sin(i*PI*0.5+0.785)*1.3),st.timber,Vector3(-sin(i*PI*0.5+0.785)*0.08,0,cos(i*PI*0.5+0.785)*0.08))
 S.cylinder(root,0.6,0.6,0.5,Vector3(0,5.4,0),st.timber,8,Vector3(PI*0.5,0,0))
 S.box(root,Vector3(3.2,2.6,2.6),Vector3(4.0,0,0),st.stone if cu != "orc" else st.timber)
 S.cylinder(root,0.45,0.6,5.5,Vector3(5.0,0,0.6),dark,6)
 if st.has_glow: S.box(root,Vector3(1.0,0.8,0.1),Vector3(4.0,0.6,1.32),st.glow,Vector3.ZERO,2.5)
 S.cone(root,1.8,1.4,Vector3(-3.4,0,1.6),Color("5a524a"),7)

static func _lumber(root: Node3D,st: Dictionary,cu: String):
 # Sawmill shed and log piles.
 S.box(root,Vector3(5.0,2.4,3.0),Vector3.ZERO,st.timber)
 S.gable(root,5.3,3.3,1.3,Vector3(0,2.4,0),st.roof if st.roofs in ["steep","low","thatch"] else st.timber.darkened(0.2))
 for j in 3:
  for i in 4-j: S.cylinder(root,0.32,0.32,4.0,Vector3(-1.2+i*0.66+j*0.33,0.32+j*0.56,3.0),Color("8a6040"),6,Vector3(0,0,PI*0.5))
 S.cylinder(root,0.9,0.9,0.25,Vector3(2.9,1.2,-1.0),Color("6a6a6a"),10,Vector3(PI*0.5,0,0)) # saw / wheel

static func _market(root: Node3D,st: Dictionary,cu: String):
 # Market hall (open, on posts) among stalls with bright awnings.
 S.box(root,Vector3(6.0,0.25,4.0),Vector3.ZERO,st.stone)
 for x in [-2.6,0.0,2.6]:
  for z in [-1.6,1.6]: S.box(root,Vector3(0.3,2.6,0.3),Vector3(x,0.25,z),st.timber if cu != "greek" else st.wall)
 _roof(root,st,6.0,4.0,2.85,1)
 var awnings = [Color("c8402c"),Color("2c6ac8"),Color("e0b02c"),Color("3c9a4c")]
 for i in 4:
  var p = Vector3(-3.0+i*2.0,0,3.6)
  S.box(root,Vector3(1.4,1.0,1.0),p,st.timber)
  S.box(root,Vector3(1.6,0.12,1.3),p+Vector3(0,1.6,0),awnings[i],Vector3(0.2,0,0))

# Entry point for the asset manifest ("procedural" section): "kit.<culture>.<piece>".
static func build_id(id: String) -> Node3D:
 var parts = id.split(".")
 return build(parts[1],parts[2])
