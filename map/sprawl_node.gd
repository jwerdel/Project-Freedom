extends Node3D
# One settlement's sprawl on the map: the placement list from map/sprawl.gd drawn as one MultiMesh
# per kit piece, each piece baked into one surface per look (map/kit_cache.gd baked(): its parts and
# material colours combined, distance LODs kept), so a whole city is a dozen or so draw calls.
# Fields, roads and small props cast no shadow (data/settlement_sprawl.json no_shadow). Ruins are
# sunk, tilted and darkened. height_at(x, z) gives the ground height; water pieces (ships) sit at
# sea level. merge = false draws one MultiMesh per model part instead (the old way, for comparisons).

const Sprawl = preload("res://map/sprawl.gd")
const KitCache = preload("res://map/kit_cache.gd")
const AssetManifest = preload("res://core/asset_manifest.gd")

static var merge := true
static var _decal: ShaderMaterial = null
const DRAPED = ["kit.field","kit.road"]

var key := "" # what the sprawl was built from (rebuilt when it changes)
var pieces := 0

func build(s: Dictionary,terrain_at: Callable,height_at: Callable,sea_level := 0.0,visibility_end := 0.0):
 for c in get_children():
  remove_child(c)
  c.queue_free()
 var placed = Sprawl.layout(s,terrain_at,height_at)
 pieces = placed.size()
 var rng = RandomNumberGenerator.new()
 rng.seed = hash(["ruins",s.id])
 var quiet = Sprawl.sprawl_data().get("no_shadow",[])
 var draped = [] # fields and roads: one mesh over the ground
 var merged = {} # culture kit pieces: one mesh per look for the whole settlement
 var groups = {} # merge: piece -> {mesh, xforms, colors}; else "piece|part" -> the same
 for p in placed:
  # Seated on the low side of its footprint (a slope shows the foundation instead of a floating edge).
  var y = sea_level
  if not p.get("water",false):
   y = INF
   for o in [Vector2.ZERO,Vector2(1.2,0),Vector2(-1.2,0),Vector2(0,1.2),Vector2(0,-1.2)]: y = minf(y,float(height_at.call(p.pos.x+o.x,p.pos.y+o.y)))
  # The piece's local +z faces rot (a direction in the map plane).
  var basis = Basis(Vector3.UP,PI*0.5-float(p.rot))*Basis.from_scale(p.scale)
  if p.ruin:
   basis = Basis(Vector3(rng.randf_range(-1,1),0,rng.randf_range(-1,1)).normalized(),rng.randf_range(0.12,0.3))*basis.scaled(Vector3(1,rng.randf_range(0.45,0.7),1))
   y -= 0.4
  if merge and DRAPED.has(p.piece):
   draped.append(p)
   continue
  var xf = Transform3D(basis,Vector3(p.pos.x,y,p.pos.y))
  if merge and AssetManifest.procedural_builder(p.piece) != "":
   _merge_piece(merged,p.piece,xf,p.color)
   continue
  if merge:
   if KitCache.baked(p.piece) == null: continue
   if not groups.has(p.piece): groups[p.piece] = {"mesh":KitCache.baked(p.piece),"xforms":[],"colors":[],"shadow":not quiet.has(p.piece)}
   groups[p.piece].xforms.append(xf)
   groups[p.piece].colors.append(p.color)
  else:
   var parts = KitCache.meshes(p.piece)
   for i in parts.size():
    var k = "%s|%d" % [p.piece,i]
    if not groups.has(k): groups[k] = {"mesh":parts[i].mesh,"xforms":[],"colors":[],"shadow":true}
    groups[k].xforms.append(xf*parts[i].xform)
    groups[k].colors.append(p.color)
 for k in groups:
  var g = groups[k]
  var mm = MultiMesh.new()
  mm.transform_format = MultiMesh.TRANSFORM_3D
  mm.use_colors = true
  mm.mesh = g.mesh
  mm.instance_count = g.xforms.size()
  for i in g.xforms.size():
   mm.set_instance_transform(i,g.xforms[i])
   mm.set_instance_color(i,g.colors[i])
  var mi = MultiMeshInstance3D.new()
  mi.multimesh = mm
  mi.name = str(k).validate_node_name()
  if not g.shadow: mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  if visibility_end>0.0: mi.visibility_range_end = visibility_end
  mi.lod_bias = float(Sprawl.sprawl_data().get("lod_bias",1.0))
  # Far cities keep only their big pieces (data/settlement_sprawl.json detail_ranges).
  var piece = str(k).get_slice("|",0)
  var dr = Sprawl.sprawl_data().get("detail_ranges",{})
  if visibility_end>0.0 and not dr.is_empty():
   if quiet.has(piece): mi.visibility_range_end = float(dr.small)
   elif dr.houses.has(piece) or dr.houses.has(piece.get_slice(".",2)): mi.visibility_range_end = float(dr.house)
  add_child(mi)
 if not draped.is_empty(): _drape(draped,height_at,visibility_end)
 _merged_meshes(merged,visibility_end)

# The low-poly culture kit pieces of the whole settlement merged into one mesh per look (two or three
# draw calls for a city of hundreds of buildings); ruins keep their darkened tint.
func _merge_piece(merged: Dictionary,id: String,xf: Transform3D,tint: Color):
 var nb = Transform3D(xf.basis.inverse().transposed(),Vector3.ZERO)
 var tr = KitCache.tris(id)
 for k in tr:
  var t = tr[k]
  if not merged.has(k): merged[k] = {"v":PackedVector3Array(),"n":PackedVector3Array(),"c":PackedColorArray(),"material":t.material}
  var m = merged[k]
  m.v.append_array(xf*t.v)
  m.n.append_array(nb*t.n)
  if tint == Color.WHITE: m.c.append_array(t.c)
  else:
   for c in t.c: m.c.append(c*tint)

func _merged_meshes(merged: Dictionary,visibility_end: float):
 for k in merged:
  var m = merged[k]
  if m.v.is_empty(): continue
  var arr = []
  arr.resize(Mesh.ARRAY_MAX)
  arr[Mesh.ARRAY_VERTEX] = m.v
  arr[Mesh.ARRAY_NORMAL] = m.n
  arr[Mesh.ARRAY_COLOR] = m.c
  var mesh = ArrayMesh.new()
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
  mesh.surface_set_material(0,m.material)
  var mi = MeshInstance3D.new()
  mi.name = "Buildings"
  mi.mesh = mesh
  if visibility_end>0.0: mi.visibility_range_end = visibility_end
  add_child(mi)

# Fields and roads as one mesh draped over the ground: each a grid of quads whose corners sit on the
# terrain (height_at), so they follow slopes instead of floating as flat squares; fields turn to run
# along the contour, as terraces and strips do on a hillside.
func _drape(placed: Array,height_at: Callable,visibility_end: float):
 var v = PackedVector3Array()
 var col = PackedColorArray()
 var uv2 = PackedVector2Array()
 var road_base = Color(0.48,0.40,0.30).srgb_to_linear()
 for p in placed:
  var road = p.piece == "kit.road"
  var sx = float(p.scale.x)
  var sz = float(p.scale.z)
  # Sprawl angles are directions in the map plane (x, z); a Y rotation of PI - rot turns a piece's
  # local z (its length) along them.
  var rot = PI*0.5-float(p.rot)
  if not road:
   var c = p.pos
   var gx = float(height_at.call(c.x+2.0,c.y))-float(height_at.call(c.x-2.0,c.y))
   var gz = float(height_at.call(c.x,c.y+2.0))-float(height_at.call(c.x,c.y-2.0))
   if absf(gx)+absf(gz)>0.15: rot = atan2(-gx,-gz) # local x along the contour: furrows follow it
  var nx = 2 if road else maxi(2,int(sx/1.5))
  var nz = maxi(2,int(sz/1.5))
  var b = Basis(Vector3.UP,rot)
  var tint: Color = p.color
  var cc = (road_base*tint) if road else tint.srgb_to_linear()
  cc.a = 1.0
  var lift = 0.14 if road else 0.1
  var pts = []
  for j in nz+1:
   for i in nx+1:
    var lp = b*Vector3((float(i)/nx-0.5)*sx,0,(float(j)/nz-0.5)*sz)
    var wx = p.pos.x+lp.x
    var wz = p.pos.y+lp.z
    pts.append(Vector3(wx,float(height_at.call(wx,wz))+lift,wz))
  for j in nz:
   for i in nx:
    var a = pts[j*(nx+1)+i]
    var bb = pts[j*(nx+1)+i+1]
    var c2 = pts[(j+1)*(nx+1)+i]
    var d = pts[(j+1)*(nx+1)+i+1]
    for q in [a,bb,d,a,d,c2]:
     v.append(q)
     col.append(cc)
    var u0 = float(j)/nz*sz # metres across the furrows (they run along local x)
    var u1 = float(j+1)/nz*sz
    var rv = 1.0 if road else 0.0
    for u in [u0,u0,u1,u0,u1,u1]: uv2.append(Vector2(u,rv))
 if v.is_empty(): return
 var arr = []
 arr.resize(Mesh.ARRAY_MAX)
 arr[Mesh.ARRAY_VERTEX] = v
 arr[Mesh.ARRAY_COLOR] = col
 arr[Mesh.ARRAY_TEX_UV2] = uv2
 var st = SurfaceTool.new()
 st.create_from_arrays(arr)
 st.generate_normals()
 var mesh = st.commit()
 if _decal == null:
  _decal = ShaderMaterial.new()
  _decal.shader = load("res://map/ground_decal.gdshader")
 mesh.surface_set_material(0,_decal)
 var mi = MeshInstance3D.new()
 mi.name = "Ground"
 mi.mesh = mesh
 mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 if visibility_end>0.0: mi.visibility_range_end = visibility_end
 add_child(mi)

# Surfaces drawn (each is a draw call per pass).
func draw_calls() -> int:
 var n = 0
 for c in get_children():
  n += c.multimesh.mesh.get_surface_count() if c is MultiMeshInstance3D else c.mesh.get_surface_count()
 return n
