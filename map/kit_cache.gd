extends RefCounted
# Meshes of kit pieces (asset manifest kit.* and other visual ids), extracted once from their
# visual scenes for MultiMesh batching: [{mesh, xform}] per id. Materials are duplicated with
# vertex colour as albedo, so each instance can be tinted (culture tint, ruins, field colours).

const AssetManifest = preload("res://core/asset_manifest.gd")

static var _cache = {}
# Packs whose vertex colours hold other data (Quaternius Stylized Nature: wind masks), which Godot's
# glTF import would otherwise show as colour.
const NO_VERTEX_COLOUR = "nature."

static func meshes(id: String) -> Array:
 if _cache.has(id): return _cache[id]
 var out = []
 var root = AssetManifest.instantiate(id)
 for m in root.find_children("*","MeshInstance3D",true,false):
  if m.mesh == null: continue
  var t = Transform3D.IDENTITY
  var p = m
  while p != null and p != root:
   t = p.transform*t
   p = p.get_parent()
  # Which surfaces really colour with their vertex colours (some packs store wind masks there).
  var vc = []
  for s in m.mesh.get_surface_count():
   var mat = m.get_surface_override_material(s) if m.get_surface_override_material(s) != null else m.mesh.surface_get_material(s)
   vc.append(mat is BaseMaterial3D and mat.vertex_color_use_as_albedo and not id.begins_with(NO_VERTEX_COLOUR))
  out.append({"mesh":_tintable(m.mesh,m),"xform":t,"vc":vc})
 root.free()
 _cache[id] = out
 return out

# A copy of the mesh whose surface materials take the instance colour as an albedo multiplier.
static func _tintable(mesh: Mesh,mi: MeshInstance3D) -> Mesh:
 var copy = mesh.duplicate()
 for s in copy.get_surface_count():
  var mat = mi.get_surface_override_material(s) if mi.get_surface_override_material(s) != null else copy.surface_get_material(s)
  if mat is StandardMaterial3D:
   var m2: StandardMaterial3D = mat.duplicate()
   m2.vertex_color_use_as_albedo = true
   copy.surface_set_material(s,m2)
 return copy

static func reset():
 _cache = {}
 _baked = {}
 _looks = {}
 _tris = {}

# --- One mesh per piece (map/sprawl_node.gd) ----------------------------------------------------
# A kit piece's parts and surfaces baked into one mesh with one surface per look (its material
# without the colour): the material colours go into the vertex colours (linear, as the shader
# multiplies them with the instance colour), the parts' transforms into the vertices, and the
# distance LODs are generated again for the combined surface. A city then draws one MultiMesh per
# piece with one or two surfaces, instead of one per model part with a surface per material.
static var _baked = {}
static var _looks = {} # look key -> shared material

static func baked(id: String):
 if _baked.has(id): return _baked[id]
 var groups = {} # look key -> {v, n, uv, c, i}
 var order = []
 for part in meshes(id):
  var mesh: Mesh = part.mesh
  var t: Transform3D = part.xform
  var nt = Transform3D(t.basis.inverse().transposed(),Vector3.ZERO)
  for s in mesh.get_surface_count():
   if mesh is ArrayMesh and mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES: continue
   var arr = mesh.surface_get_arrays(s)
   var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
   if v.is_empty(): continue
   var n = arr[Mesh.ARRAY_NORMAL]
   var uv = arr[Mesh.ARRAY_TEX_UV]
   var vc = arr[Mesh.ARRAY_COLOR]
   var idx = arr[Mesh.ARRAY_INDEX]
   if n == null or n.size() != v.size():
    n = PackedVector3Array()
    n.resize(v.size())
    n.fill(Vector3.UP)
   if uv == null or uv.size() != v.size():
    uv = PackedVector2Array()
    uv.resize(v.size())
   if idx == null or idx.is_empty():
    idx = PackedInt32Array()
    for i in v.size(): idx.append(i)
   var mat = mesh.surface_get_material(s)
   var base = Color.WHITE
   var key = ""
   if mat is BaseMaterial3D:
    base = mat.albedo_color.srgb_to_linear()
    base.a = mat.albedo_color.a
    key = _look(mat)
   else: key = "own:%d" % (mat.get_instance_id() if mat != null else 0)
   if not _looks.has(key): _looks[key] = _shared(mat)
   if not groups.has(key):
    groups[key] = {"v":PackedVector3Array(),"n":PackedVector3Array(),"uv":PackedVector2Array(),"c":PackedColorArray(),"i":PackedInt32Array()}
    order.append(key)
   var g = groups[key]
   var off = g.v.size()
   g.v.append_array(t*v)
   g.n.append_array(nt*n)
   g.uv.append_array(uv)
   if vc != null and vc.size() == v.size() and part.vc[s]:
    for c in vc: g.c.append(base*c)
   else:
    var cs = PackedColorArray()
    cs.resize(v.size())
    cs.fill(base)
    g.c.append_array(cs)
   for i in idx: g.i.append(i+off)
 var im = ImporterMesh.new()
 for key in order:
  var g = groups[key]
  var arr = []
  arr.resize(Mesh.ARRAY_MAX)
  arr[Mesh.ARRAY_VERTEX] = g.v
  arr[Mesh.ARRAY_NORMAL] = g.n
  arr[Mesh.ARRAY_TEX_UV] = g.uv
  arr[Mesh.ARRAY_COLOR] = g.c
  arr[Mesh.ARRAY_INDEX] = g.i
  im.add_surface(Mesh.PRIMITIVE_TRIANGLES,arr,[],{},_looks[key])
 var out = null # no static meshes (e.g. a visual built by script): nothing to draw, as before
 if im.get_surface_count()>0:
  if g_lods(im): im.generate_lods(60.0,25.0,[]) # the importer's defaults (normal merge 60°, split 25°)
  out = im.get_mesh()
 _baked[id] = out
 return out

# LODs only pay off for detailed models (the imported ones); simple shapes keep their one level.
static func g_lods(im: ImporterMesh) -> bool:
 var tris = 0
 for s in im.get_surface_count(): tris += im.get_surface_arrays(s)[Mesh.ARRAY_INDEX].size()/3
 return tris>200

# Everything about a material except its colour (textures by their pixels: each Kenney model embeds
# its own copy of the same colour map).
static func _look(mat: BaseMaterial3D) -> String:
 var parts = []
 for p in mat.get_property_list():
  if p.usage & PROPERTY_USAGE_STORAGE == 0 or p.name.begins_with("resource_") or p.name == "albedo_color": continue
  var v = mat.get(p.name)
  if v is Texture2D:
   var img = v.get_image()
   parts.append("tex:%d" % (hash(img.get_data()) if img != null else v.get_instance_id()))
  elif v is Resource: parts.append("res:%d" % v.get_instance_id())
  else: parts.append(str(v))
 return str(hash(",".join(parts)))

static func _shared(mat: Material) -> Material:
 if not (mat is BaseMaterial3D): return mat
 var m: BaseMaterial3D = mat.duplicate()
 m.albedo_color = Color.WHITE
 m.vertex_color_use_as_albedo = true
 return m

# --- Merging small pieces (map/sprawl_node.gd) --------------------------------------------------------
# A low-poly piece (the procedural culture kits: tens to hundreds of triangles, no LODs to lose) as
# plain triangle arrays per look, so a whole city's pieces merge into one mesh per look with native
# array appends: {look key: {"v", "n", "c", "material"}}.
static var _tris = {}

static func tris(id: String) -> Dictionary:
 if _tris.has(id): return _tris[id]
 var out = {}
 var mesh = baked(id)
 if mesh != null:
  for s in mesh.get_surface_count():
   var arr = mesh.surface_get_arrays(s)
   var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
   var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
   var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
   var cc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
   var v = PackedVector3Array()
   var n = PackedVector3Array()
   var c = PackedColorArray()
   for i in idx:
    v.append(vv[i])
    n.append(nn[i])
    c.append(cc[i])
   var mat = mesh.surface_get_material(s)
   out[str(mat.get_instance_id())] = {"v":v,"n":n,"c":c,"material":mat}
 _tris[id] = out
 return out
