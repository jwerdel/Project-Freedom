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
  "plinth": # a 1 m block of terrace stone, scaled under a building (Greek acropolis terraces)
   S.box(root,Vector3(1.0,1.0,1.0),Vector3.ZERO,st.stone.darkened(0.06))
   S.box(root,Vector3(1.04,0.08,1.04),Vector3(0,0.96,0),st.wall)
  "bridge": # a 1 m beam along x, scaled to span two towers (elf bridges, ratmen walkways)
   S.box(root,Vector3(1.0,0.35,1.0),Vector3(0,-0.17,0),st.trim if culture == "elf" else st.timber)
  _: push_error("Unknown kit piece "+piece)
 return root

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
   return
  "elf":
   S.cylinder(root,size.x*0.38,size.x*0.45,size.y*1.4,Vector3.ZERO,st.wall,8)
   S.cylinder(root,0.0,size.x*0.5,size.y*1.3,Vector3(0,size.y*1.4,0),st.roof if v != 1 else st.roof2,8)
   S.box(root,Vector3(size.x*0.6,0.12,0.12),Vector3(0,size.y*1.35,0),st.trim)
   return
  "dark_elf":
   S.box(root,Vector3(size.x*0.85,size.y*1.4,size.z*0.85),Vector3.ZERO,st.wall)
   _roof(root,st,size.x*0.85,size.z*0.85,size.y*1.4,v)
   return
  "lizardmen":
   if v == 2:
    S.steps(root,size.x*1.1,3,size.y*0.45,Vector3.ZERO,st.stone)
    S.box(root,Vector3(size.x*0.4,0.6,size.z*0.4),Vector3(0,size.y*1.35,0),st.roof2)
    return
   S.box(root,Vector3(size.x*0.9,size.y*0.8,size.z*0.9),Vector3.ZERO,st.wall)
   _roof(root,st,size.x*0.9,size.z*0.9,size.y*0.8,v)
   return
  "dwarf":
   S.box(root,Vector3(size.x*1.1,size.y*0.9,size.z*1.1),Vector3.ZERO,st.wall if v != 1 else st.stone)
   _roof(root,st,size.x*1.1,size.z*1.1,size.y*0.9,v)
   return
 # Medieval, Roman, Greek, desert: walls and a roof (timber frame for the north).
 S.box(root,size,Vector3.ZERO,st.wall)
 if cu == "medieval":
  S.box(root,Vector3(size.x+0.04,0.14,size.z+0.04),Vector3(0,size.y*0.5,0),st.timber)
  if v == 2: S.box(root,Vector3(size.x+0.25,size.y*0.5,size.z+0.25),Vector3(0,size.y*0.55,0),st.wall.darkened(0.05)) # jettied upper floor
 if cu == "greek" and v == 1: S.box(root,Vector3(size.x*0.55,size.y*0.6,size.z*0.55),Vector3(-size.x*0.2,size.y,0),st.wall)
 if cu == "desert" and v == 2: S.box(root,Vector3(size.x*0.5,size.y*0.7,size.z*0.5),Vector3(size.x*0.2,size.y,0),st.wall.darkened(0.04))
 _roof(root,st,size.x,size.z,size.y+(size.y*0.5 if cu == "medieval" and v == 2 else 0.0),v)

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
  "desert":
   S.box(root,Vector3(2.6,4.2,2.6),Vector3.ZERO,st.wall)
   S.box(root,Vector3(2.8,0.3,2.8),Vector3(0,4.2,0),st.roof2)
  "greek":
   S.box(root,Vector3(2.6,3.6,2.6),Vector3.ZERO,st.wall)
   S.box(root,Vector3(1.6,1.6,1.6),Vector3(0.3,3.6,0.3),st.wall)
   S.box(root,Vector3(1.7,0.15,1.7),Vector3(0.3,5.2,0.3),st.roof2)
  "roman":
   S.box(root,Vector3(3.2,5.0,2.6),Vector3.ZERO,st.wall)
   _roof(root,st,3.2,2.6,5.0,0)
   S.box(root,Vector3(3.3,0.15,2.7),Vector3(0,2.5,0),st.stone.darkened(0.08))
  _:
   S.box(root,Vector3(2.4,4.6,2.4),Vector3.ZERO,st.wall)
   S.box(root,Vector3(2.5,0.15,2.5),Vector3(0,2.3,0),st.timber)
   _roof(root,st,2.4,2.4,4.6,0)

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
   for i in 8:
    var h = 2.6+0.5*sin(i*2.3)
    S.cylinder(root,0.22,0.22,h,Vector3(-1.4+i*0.4,0,0),st.timber,5,Vector3(0,0,0.05*sin(i*1.7)))
    S.spike(root,0.22,0.6,Vector3(-1.4+i*0.4,h,0),st.timber.darkened(0.2))
   if cu == "orc": S.box(root,Vector3(0.5,0.4,0.4),Vector3(0,2.0,0.25),st.trim) # skull
  "dark_elf":
   S.box(root,Vector3(3.3,3.4,1.2),Vector3.ZERO,st.wall)
   for i in 4: S.spike(root,0.18,1.2,Vector3(-1.2+i*0.8,3.4,0),st.trim)
  "elf":
   S.box(root,Vector3(3.3,2.8,0.7),Vector3.ZERO,st.wall)
   S.box(root,Vector3(3.3,0.18,0.9),Vector3(0,2.8,0),st.trim)
  "dwarf":
   S.box(root,Vector3(3.3,3.6,1.8),Vector3.ZERO,st.stone)
   for i in 3: S.box(root,Vector3(0.7,0.6,1.8),Vector3(-1.1+i*1.1,3.6,0),st.stone.darkened(0.1))
  "lizardmen":
   S.box(root,Vector3(3.3,2.6,1.4),Vector3.ZERO,st.stone)
   S.box(root,Vector3(3.3,0.3,1.6),Vector3(0,2.6,0),st.roof2)
  _:
   S.box(root,Vector3(3.3,3.0,1.1),Vector3.ZERO,st.stone)
   for i in 3: S.box(root,Vector3(0.6,0.5,1.1),Vector3(-1.1+i*1.1,3.0,0),st.stone.darkened(0.08))

static func _tower(root: Node3D,st: Dictionary,cu: String):
 match cu:
  "medieval":
   S.cylinder(root,1.4,1.55,5.6,Vector3.ZERO,st.stone,10)
   S.cone(root,1.75,2.6,Vector3(0,5.6,0),st.roof,10)
  "roman", "greek":
   S.box(root,Vector3(2.6,5.0,2.6),Vector3.ZERO,st.stone)
   for i in 4: S.box(root,Vector3(0.6,0.5,0.6),Vector3(cos(i*PI*0.5+0.785)*1.0,5.0,sin(i*PI*0.5+0.785)*1.0),st.stone.darkened(0.08))
   if cu == "roman": _roof(root,st,2.6,2.6,5.0,0)
  "desert":
   S.cylinder(root,1.0,1.6,5.2,Vector3.ZERO,st.wall,4,Vector3(0,PI*0.25,0))
   S.box(root,Vector3(1.6,0.4,1.6),Vector3(0,5.2,0),st.trim)
  "dwarf":
   S.box(root,Vector3(3.4,5.0,3.4),Vector3.ZERO,st.stone)
   S.box(root,Vector3(3.9,0.8,3.9),Vector3(0,5.0,0),st.wall)
   S.box(root,Vector3(0.6,0.6,0.1),Vector3(0,3.4,1.72),st.glow,Vector3.ZERO,2.5)
  "orc", "ratmen", "beastmen":
   _tall(root,st,cu)
  "elf":
   S.cylinder(root,0.8,1.0,7.0,Vector3.ZERO,st.wall,10)
   S.cylinder(root,0.0,1.1,3.4,Vector3(0,7.0,0),st.roof2,10)
  "dark_elf":
   S.cylinder(root,0.8,1.5,7.5,Vector3.ZERO,st.wall,5)
   S.spike(root,1.0,3.5,Vector3(0,7.5,0),st.roof)
   for i in 3: S.spike(root,0.18,1.6,Vector3(cos(i*2.1)*1.0,5.5,sin(i*2.1)*1.0),st.trim,Vector3(cos(i*2.1)*0.6,0,sin(i*2.1)*0.6))
  "lizardmen":
   var top = S.steps(root,3.2,3,1.2,Vector3.ZERO,st.stone)
   S.box(root,Vector3(1.0,1.2,1.0),Vector3(0,top,0),st.roof2)

static func _gate(root: Node3D,st: Dictionary,cu: String):
 # Two flanking towers and a lintel over a dark opening.
 var c = st.stone
 if cu in ["orc","ratmen","beastmen"]: c = st.timber
 for sx in [-1.0,1.0]:
  S.box(root,Vector3(1.3,4.6,1.6),Vector3(sx*1.35,0,0),c)
 S.box(root,Vector3(4.0,1.0,1.6),Vector3(0,3.6,0),c.darkened(0.05))
 S.box(root,Vector3(1.3,2.6,0.2),Vector3(0,0,0.75),Color("1e1a16"))
 S.box(root,Vector3(1.3,2.6,0.2),Vector3(0,0,-0.75),Color("1e1a16"))
 match cu:
  "medieval":
   for sx in [-1.0,1.0]: S.cone(root,0.95,1.6,Vector3(sx*1.35,4.6,0),st.roof,8)
  "roman":
   S.gable(root,4.2,1.8,0.7,Vector3(0,4.6,0),st.roof)
  "orc":
   S.box(root,Vector3(0.9,0.8,0.6),Vector3(0,4.6,0.4),st.trim) # beast skull
   for sx in [-1.0,1.0]: S.spike(root,0.16,1.3,Vector3(sx*1.35,4.6,0),st.trim)
  "dark_elf":
   for sx in [-1.0,1.0]: S.spike(root,0.5,2.6,Vector3(sx*1.35,4.6,0),st.roof)
  "elf":
   for sx in [-1.0,1.0]: S.cylinder(root,0.0,0.75,2.4,Vector3(sx*1.35,4.6,0),st.roof,8)
  "desert":
   for sx in [-1.0,1.0]: S.box(root,Vector3(0.7,2.2,0.7),Vector3(sx*2.4,0,0.6),st.trim) # guardian statues
  "dwarf":
   S.box(root,Vector3(1.4,1.0,0.2),Vector3(0,4.6,0.7),st.trim) # carved face
  "lizardmen":
   S.box(root,Vector3(4.2,0.4,1.8),Vector3(0,4.6,0),st.roof2)

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
