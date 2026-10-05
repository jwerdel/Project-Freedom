extends Node3D
# One settlement's sprawl on the map: the placement list from map/sprawl.gd drawn as one MultiMesh
# per kit piece, each piece baked into one surface per look (map/kit_cache.gd baked(): its parts and
# material colours combined, distance LODs kept), so a whole city is a dozen or so draw calls.
# Fields, roads and small props cast no shadow (data/settlement_sprawl.json no_shadow). Ruins are
# sunk, tilted and darkened. height_at(x, z) gives the ground height; water pieces (ships) sit at
# sea level. merge = false draws one MultiMesh per model part instead (the old way, for comparisons).

const Sprawl = preload("res://map/sprawl.gd")
const KitCache = preload("res://map/kit_cache.gd")

static var merge := true

var key := "" # what the sprawl was built from (rebuilt when it changes)
var pieces := 0

func build(s: Dictionary,terrain_at: Callable,height_at: Callable,sea_level := 0.0,visibility_end := 0.0):
 for c in get_children():
  remove_child(c)
  c.queue_free()
 var placed = Sprawl.layout(s,terrain_at)
 pieces = placed.size()
 var rng = RandomNumberGenerator.new()
 rng.seed = hash(["ruins",s.id])
 var quiet = Sprawl.sprawl_data().get("no_shadow",[])
 var groups = {} # merge: piece -> {mesh, xforms, colors}; else "piece|part" -> the same
 for p in placed:
  var y = sea_level if p.get("water",false) else float(height_at.call(p.pos.x,p.pos.y))
  var basis = Basis(Vector3.UP,p.rot).scaled(p.scale)
  if p.ruin:
   basis = Basis(Vector3(rng.randf_range(-1,1),0,rng.randf_range(-1,1)).normalized(),rng.randf_range(0.12,0.3))*basis.scaled(Vector3(1,rng.randf_range(0.45,0.7),1))
   y -= 0.4
  var xf = Transform3D(basis,Vector3(p.pos.x,y,p.pos.y))
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
  if not g.shadow: mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  if visibility_end>0.0: mi.visibility_range_end = visibility_end
  add_child(mi)

# Surfaces drawn (each is a draw call per pass).
func draw_calls() -> int:
 var n = 0
 for c in get_children(): n += c.multimesh.mesh.get_surface_count()
 return n
