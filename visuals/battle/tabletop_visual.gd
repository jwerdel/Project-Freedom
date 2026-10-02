extends Node3D
# Tabletop battlefield for the deployment screen (docs/battle-design.md section 2): tiles per lane
# and band built from the sampled terrain, trees, hills, rock for impassable lanes, walls for
# sieges, and small blocks of the real unit figures standing in their slots. Visual only: the
# deployment rules live in core/deployment.gd. Attacker side at +z (near the default camera).

const ProtoKit = preload("res://visuals/common/proto_kit.gd")
const UnitTypes = preload("res://core/unit_types.gd")
const UiKit = preload("res://ui/ui_kit.gd")
const LANE_W = 6.0
const BAND_D = 4.0
const TERRAIN_COLORS = {"open":Color("7f9a55"),"road":Color("9a8564"),"forest":Color("4f7340"),"hills":Color("8d8a5a"),"pass":Color("8b8270"),"closed":Color("5b5550")}
const ORDER_LETTERS = {"hold":"H","aggressive":"A","flank":"F","protect":"P","reserve":"R"}
const ORDER_COLORS = {"hold":Color("e9e2c8"),"aggressive":Color("ef8a6a"),"flank":Color("e9cf5a"),"protect":Color("7fc8ef"),"reserve":Color("b7a8e0")}

var kit
var lanes := 5
var terrain: Array = []
var blocks = {}      # key -> {node, figures, label, ring, banner}
var arrows: Node3D
var time := 0.0

func _ready():
 kit = ProtoKit.shared()

func lane_x(lane: int) -> float:
 return (lane-(lanes-1)/2.0)*LANE_W

func band_z(b: int) -> float:
 return (2.5-b)*BAND_D

# Line rows of each side (z), including the general's row and the reserve behind it.
func row_z(role: int,line: String) -> float:
 var s = 1.0 if role == 0 else -1.0
 match line:
  "front": return band_z(1 if role == 0 else 4)
  "back": return band_z(0 if role == 0 else 5)
  "general": return s*(2.5*BAND_D+BAND_D*0.9)
  _: return s*(2.5*BAND_D+BAND_D*1.9)

# spec: {terrain, walls (bool), colors: [attacker, defender]}
func build(spec: Dictionary):
 if kit == null: kit = ProtoKit.shared()
 terrain = spec.terrain
 lanes = terrain.size()
 var w = lanes*LANE_W
 # Table and the deployment strips behind each side (general's row and reserve).
 kit.box(self,Vector3(0,-0.35,0),Vector3(w+3,0.5,6*BAND_D+2*BAND_D*2.6),kit.mat(Color("4a3a2a")))
 for role in 2:
  var c = Color(spec.colors[role]).darkened(0.35)
  kit.box(self,Vector3(0,-0.05,row_z(role,"general")),Vector3(w,0.12,BAND_D*0.8),kit.mat(c.lerp(Color("6d6450"),0.6)))
  kit.box(self,Vector3(0,-0.05,row_z(role,"reserve")),Vector3(w,0.12,BAND_D*0.9),kit.mat(c.lerp(Color("5a5246"),0.5)))
 var rng = RandomNumberGenerator.new()
 rng.seed = 7
 for l in lanes:
  for b in terrain[l].size():
   var t = terrain[l][b]
   var p = Vector3(lane_x(l),0,band_z(b))
   var h = 0.1 if t != "hills" else 0.7
   var tile = kit.box(self,p+Vector3(0,h/2-0.05,0),Vector3(LANE_W-0.12,h,BAND_D-0.12),kit.mat(TERRAIN_COLORS.get(t,TERRAIN_COLORS.open)))
   tile.name = "Tile_%d_%d" % [l,b]
   match t:
    "forest":
     for k in 4: _tree(p+Vector3(rng.randf_range(-2.2,2.2),0.05,rng.randf_range(-1.4,1.4)),rng.randf_range(1.3,2.0))
    "road":
     kit.box(self,p+Vector3(0,0.08,0),Vector3(1.4,0.04,BAND_D),kit.mat(Color("b39e78")))
    "closed":
     for k in 3: kit.box(self,p+Vector3(rng.randf_range(-2,2),0.9,rng.randf_range(-1.2,1.2)),Vector3(rng.randf_range(1.2,2.4),rng.randf_range(1.2,2.4),rng.randf_range(1.0,1.8)),kit.mat(Color("6e6862")))
    "pass":
     for sx in [-1,1]: kit.box(self,p+Vector3(sx*(LANE_W*0.38),0.9,0),Vector3(LANE_W*0.22,1.8,BAND_D-0.2),kit.mat(Color("6e6862")))
 if spec.get("walls",false):
  # Wall between no man's land and the defender's front line, with a gate in the center lane.
  var z = (band_z(3)+band_z(4))*0.5
  for l in lanes:
   if l == lanes/2:
    kit.box(self,Vector3(lane_x(l)-LANE_W*0.4,0.8,z),Vector3(LANE_W*0.2,1.6,0.7),kit.stone)
    kit.box(self,Vector3(lane_x(l)+LANE_W*0.4,0.8,z),Vector3(LANE_W*0.2,1.6,0.7),kit.stone)
    continue
   kit.wall(self,Vector3(lane_x(l)-LANE_W/2,0,z),Vector3(lane_x(l)+LANE_W/2,0,z),1.4)
  for l in [0,lanes-1]: kit.tower(self,Vector3(lane_x(l)+(-LANE_W/2 if l == 0 else LANE_W/2),0,z),0.9,2.6)
 arrows = Node3D.new()
 arrows.name = "Arrows"
 add_child(arrows)

func _tree(p: Vector3,h: float):
 kit.cylinder(self,p+Vector3(0,h*0.25,0),0.12,0.1,h*0.5,kit.mat(Color("5a4330")),6)
 kit.cylinder(self,p+Vector3(0,h*0.75,0),0.75,0.05,h*0.9,kit.mat(Color("3f6a36")),8)

# Positions of the units sharing one slot, spread across the lane.
func slot_point(role: int,lane: int,line: String,k: int,n: int) -> Vector3:
 var x = lane_x(lane) if line in ["front","back","general"] else 0.0
 var spread = (LANE_W*0.8)/maxi(1,n) if line != "reserve" else minf(3.2,lanes*LANE_W*0.9/maxi(1,n))
 var y = 0.05+(0.6 if line in ["front","back"] and terrain[lane][(1 if line == "front" else 0) if role == 0 else (4 if line == "front" else 5)] == "hills" else 0.0)
 return Vector3(x+(k-(n-1)/2.0)*spread,y,row_z(role,line))

# units: [{key, unit, lane, line, order, hidden, role, color}] for both sides. Blocks persist and move.
func set_units(units: Array):
 var keep = {}
 var groups = {}
 for u in units:
  var gk = "%d:%s:%d" % [u.role,u.line,int(u.lane) if u.line != "reserve" else 0]
  if not groups.has(gk): groups[gk] = []
  groups[gk].append(u)
 for gk in groups:
  var list = groups[gk]
  for k in list.size():
   var u = list[k]
   keep[u.key] = true
   var blk = blocks.get(u.key)
   if blk == null:
    blk = _make_block(u)
    blocks[u.key] = blk
   var target = slot_point(u.role,int(u.lane),u.line,k,list.size())
   blk.node.position = target
   blk.node.rotation.y = 0.0 if u.role == 1 else PI
   blk.label.text = "?" if u.get("hidden",false) else ORDER_LETTERS.get(u.order,"")
   blk.label.modulate = Color("d0d0d0") if u.get("hidden",false) else ORDER_COLORS.get(u.order,Color.WHITE)
   blk.data = u
 for key in blocks.keys():
  if not keep.has(key):
   blocks[key].node.queue_free()
   blocks.erase(key)

func _make_block(u: Dictionary) -> Dictionary:
 var n = Node3D.new()
 n.name = "Unit_%s" % u.key.replace(":","_")
 add_child(n)
 var figures = []
 var col = Color(u.color)
 kit.box(n,Vector3(0,0.03,0),Vector3(2.0 if u.unit != "commander" else 1.2,0.06,1.2),kit.mat(col.darkened(0.2)))
 if u.get("hidden",false):
  kit.box(n,Vector3(0,0.6,0),Vector3(1.4,1.1,0.8),kit.mat(Color("5d5d5d")))
 else:
  var count = 1 if u.unit == "commander" else 2
  for i in count:
   var holder = Node3D.new()
   holder.position = Vector3((i-(count-1)/2.0)*0.85,0.06,0)
   holder.scale = Vector3.ONE*(0.62 if u.unit != "commander" else 0.4)
   n.add_child(holder)
   UnitTypes.build_visual(UnitTypes.get_type(u.unit),holder)
   if holder.get_child_count()>0 and holder.get_child(0).has_method("set_banner_color"): holder.get_child(0).set_banner_color(col)
   figures.append(holder)
 var banner = null
 if u.unit == "commander" and not u.get("hidden",false):
  banner = Node3D.new()
  n.add_child(banner)
  kit.banner(banner,Vector3(0.7,0,0),1.2)
  for m in banner.find_children("*","MeshInstance3D",true,false):
   if m.material_override is ShaderMaterial: m.material_override.set_shader_parameter("tint",col)
 var label = Label3D.new()
 label.font = UiKit.FONT_BOLD
 label.font_size = 64
 label.outline_size = 16
 label.pixel_size = 0.012
 label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 label.no_depth_test = true
 label.position = Vector3(0,2.0,0)
 n.add_child(label)
 var ring = MeshInstance3D.new()
 var torus = TorusMesh.new()
 torus.inner_radius = 1.1
 torus.outer_radius = 1.3
 ring.mesh = torus
 ring.material_override = kit.mat(Color("ffe08a"))
 ring.position = Vector3(0,0.08,0)
 ring.visible = false
 n.add_child(ring)
 return {"node":n,"figures":figures,"label":label,"ring":ring,"banner":banner,"data":u}

func select(key: String):
 for k in blocks: blocks[k].ring.visible = k == key

func block_position(key: String) -> Vector3:
 return blocks[key].node.position if blocks.has(key) else Vector3.ZERO

# Arrows for Protect (protector -> protected) and Flank (around the outer edge to the enemy rear).
func set_arrows(list: Array):
 for c in arrows.get_children(): c.queue_free()
 for a in list:
  var pts: Array = a.points
  var st = SurfaceTool.new()
  st.begin(Mesh.PRIMITIVE_TRIANGLES)
  var w = 0.28
  for i in range(1,pts.size()):
   var p0: Vector3 = pts[i-1]+Vector3(0,0.35,0)
   var p1: Vector3 = pts[i]+Vector3(0,0.35,0)
   var side = Vector3(p1.z-p0.z,0,p0.x-p1.x).normalized()*w
   for v in [p0+side,p0-side,p1+side,p1+side,p0-side,p1-side]: st.add_vertex(v)
  # Arrow head.
  var tip: Vector3 = pts[-1]+Vector3(0,0.35,0)
  var back: Vector3 = (pts[-2]+Vector3(0,0.35,0)-tip).normalized()
  var perp = Vector3(back.z,0,-back.x)*0.8
  for v in [tip,tip+back*1.2+perp,tip+back*1.2-perp]: st.add_vertex(v)
  var m = StandardMaterial3D.new()
  m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  m.albedo_color = a.color
  m.cull_mode = BaseMaterial3D.CULL_DISABLED
  m.no_depth_test = true
  var mi = MeshInstance3D.new()
  mi.mesh = st.commit()
  mi.material_override = m
  arrows.add_child(mi)

# Which slot a point on the table falls in: {role, lane, line} or {} (no man's land / off the table).
func slot_at(p: Vector3) -> Dictionary:
 var lane = int(floor(p.x/LANE_W+lanes/2.0))
 var inside = lane>=0 and lane<lanes
 for role in 2:
  for line in ["front","back","general","reserve"]:
   var z = row_z(role,line)
   var half = BAND_D*0.5 if line in ["front","back"] else BAND_D*0.45
   if absf(p.z-z)<=half:
    if line == "reserve" and absf(p.x)<=lanes*LANE_W/2.0: return {"role":role,"lane":clampi(lane,0,lanes-1),"line":"reserve"}
    if inside: return {"role":role,"lane":lane,"line":line}
 return {}

func _process(delta):
 time += delta
 # Minimal idle life: the figures shift their weight now and then.
 var i = 0
 for k in blocks:
  for f in blocks[k].figures:
   f.rotation.y = sin(time*0.7+i*1.7)*0.06
   i += 1
