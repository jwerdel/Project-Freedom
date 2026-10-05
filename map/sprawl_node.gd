extends Node3D
# One settlement's sprawl on the map: the placement list from map/sprawl.gd drawn as one MultiMesh
# per kit mesh (a whole city is a few dozen draw calls). Ruins are sunk, tilted and darkened.
# height_at(x, z) gives the ground height; water pieces (ships) sit at sea level.

const Sprawl = preload("res://map/sprawl.gd")
const KitCache = preload("res://map/kit_cache.gd")

var key := "" # what the sprawl was built from (rebuilt when it changes)
var pieces := 0

func build(s: Dictionary,terrain_at: Callable,height_at: Callable,sea_level := 0.0,visibility_end := 0.0):
 for c in get_children():
  remove_child(c)
  c.queue_free()
 var placed = Sprawl.layout(s,terrain_at)
 pieces = placed.size()
 var groups = {} # "piece|mesh index" -> {mesh, xforms, colors}
 var rng = RandomNumberGenerator.new()
 rng.seed = hash(["ruins",s.id])
 for p in placed:
  var parts = KitCache.meshes(p.piece)
  var y = sea_level if p.get("water",false) else float(height_at.call(p.pos.x,p.pos.y))
  var basis = Basis(Vector3.UP,p.rot).scaled(p.scale)
  var col: Color = p.color
  if p.ruin:
   basis = Basis(Vector3(rng.randf_range(-1,1),0,rng.randf_range(-1,1)).normalized(),rng.randf_range(0.12,0.3))*basis.scaled(Vector3(1,rng.randf_range(0.45,0.7),1))
   y -= 0.4
  var xf = Transform3D(basis,Vector3(p.pos.x,y,p.pos.y))
  for i in parts.size():
   var k = "%s|%d" % [p.piece,i]
   if not groups.has(k): groups[k] = {"mesh":parts[i].mesh,"local":parts[i].xform,"xforms":[],"colors":[]}
   groups[k].xforms.append(xf*parts[i].xform)
   groups[k].colors.append(col)
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
  if visibility_end>0.0: mi.visibility_range_end = visibility_end
  add_child(mi)

func draw_calls() -> int:
 return get_child_count()
