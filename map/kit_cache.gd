extends RefCounted
# Meshes of kit pieces (asset manifest kit.* and other visual ids), extracted once from their
# visual scenes for MultiMesh batching: [{mesh, xform}] per id. Materials are duplicated with
# vertex colour as albedo, so each instance can be tinted (culture tint, ruins, field colours).

const AssetManifest = preload("res://core/asset_manifest.gd")

static var _cache = {}

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
  out.append({"mesh":_tintable(m.mesh,m),"xform":t})
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
